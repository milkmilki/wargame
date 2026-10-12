class_name NativeCompute
extends RefCounted
## Native runtime graph boundary. Gameplay objects, financial identities and
## side effects stay in GDScript; kernels only read their query inputs.
const API_VERSION := 6
const EXTENSION_PATH := "res://native/runtime_graph/runtime_graph.gdextension"
static var _override := ""
static var _graphs: Dictionary = {}
static var _batches: Dictionary = {}
static var _trade_graphs: Dictionary = {}
static var _trade_batches: Dictionary = {}
static var _profile_enabled := false
static var _profile: Dictionary = {}
static var _mutex := Mutex.new()

static func backend() -> String:
	if not OS.has_feature("debug"):
		return "native"
	if not _override.is_empty():
		return _override
	var requested := OS.get_environment("WARGAME_COMPUTE_BACKEND")
	return requested if requested in ["gdscript", "compare", "native"] else "native"

static func set_backend_for_tests(name: String) -> void:
	assert(OS.has_feature("debug"), "Backend overrides require a debug build")
	assert(name in ["gdscript", "native", "compare"], "Unknown compute backend")
	_override = name
	clear_caches_for_tests()

static func clear_caches_for_tests() -> void:
	_mutex.lock()
	_graphs.clear()
	_batches.clear()
	_trade_graphs.clear()
	_trade_batches.clear()
	_mutex.unlock()

static func invalidate_state(state: GameState) -> void:
	_mutex.lock()
	_graphs.erase(state.get_instance_id())
	_batches.erase(state.get_instance_id())
	_trade_graphs.erase(state.get_instance_id())
	_trade_batches.erase(state.get_instance_id())
	_mutex.unlock()

static func set_profiling_for_tests(enabled: bool) -> void:
	_mutex.lock()
	_profile_enabled = enabled
	_profile.clear()
	_mutex.unlock()

static func profile_snapshot() -> Dictionary:
	_mutex.lock()
	var result := _profile.duplicate()
	_mutex.unlock()
	return result

static func _profile_start() -> int:
	return Time.get_ticks_usec() if _profile_enabled else 0

static func _record_profile(label: String, stage: String, started: int) -> void:
	if started == 0: return
	var elapsed := Time.get_ticks_usec() - started
	var key := label + "_" + stage
	_mutex.lock()
	_profile[key + "_usec"] = int(_profile.get(key + "_usec", 0)) + elapsed
	_profile[key + "_count"] = int(_profile.get(key + "_count", 0)) + 1
	_mutex.unlock()

## Called only before an existing read-only phase dispatches its workers.
## Batches are explicitly retired before gameplay commits; standalone queries
## still read live edge costs and access, including direct fixture edits.
static func begin_frozen_batch(state: GameState, nations: Array[int], travel: bool, supply: bool) -> bool:
	if backend() == "gdscript" or state.atlas_layout.is_empty(): return false
	# A nested caller must leave ownership of the outer scope with its creator.
	if not _batch(state).is_empty(): return false
	var started := _profile_start()
	var data := _state_graph(state)
	if data.is_empty(): return false
	var count: int = data.edges.size()
	var packed := _edge_inputs(data, (11 if travel else 0) | (4 if supply else 0))
	var ownership := _ownership_inputs(state, data)
	var access_profiles := {}
	var all_access := PackedByteArray()
	all_access.resize(count)
	all_access.fill(1)
	access_profiles[Vector2i(-1, 0)] = all_access
	for nation in nations:
		if nation < 0: continue
		for logistics in ([false, true] if supply else [false]):
			var key := Vector2i(nation, int(logistics))
			if not access_profiles.has(key):
				access_profiles[key] = _base_access(state, data, nation, logistics, ownership, packed.controls)
	access_profiles.make_read_only()
	var batch := {"state": weakref(state), "data": data, "enabled": packed.enabled,
		"travel_costs": packed.travel, "path_costs": packed.path, "danger_costs": packed.danger,
		"supply_costs": packed.supply, "access_profiles": access_profiles,
		"controls": packed.controls,
		"owners": ownership.owners, "strategic_enabled": _strategic_enabled(data)}
	batch.make_read_only()
	_mutex.lock()
	if _batches.has(state.get_instance_id()):
		_mutex.unlock()
		return false
	_batches[state.get_instance_id()] = batch
	_mutex.unlock()
	_record_profile("batch", "pack", started)
	return true

static func end_frozen_batch(state: GameState) -> void:
	_mutex.lock()
	_batches.erase(state.get_instance_id())
	_mutex.unlock()

static func _batch(state: GameState) -> Dictionary:
	_mutex.lock()
	var result: Dictionary = _batches.get(state.get_instance_id(), {})
	_mutex.unlock()
	return result

static func require_native() -> bool:
	var version: Dictionary = Engine.get_version_info()
	if int(version.major) != 4 or int(version.minor) != 7 or int(version.patch) != 1:
		_fatal("Native compute requires Godot 4.7.1; rebuild and validate against the selected engine before changing this contract.")
		return false
	if not ClassDB.class_exists("NativeGraphSnapshot"):
		# Loading the descriptor also supports a fresh checkout before editor import.
		if ResourceLoader.exists(EXTENSION_PATH):
			load(EXTENSION_PATH)
	if not ClassDB.class_exists("NativeGraphSnapshot"):
		_fatal("NativeGraphSnapshot is missing. Build the Godot 4.7.1 extension with scripts/tools/build_native_compute.py.")
		return false
	var probe: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	if int(probe.call("api_version")) != API_VERSION or not probe.has_method("make_access_mask") or not probe.has_method("patch_access_mask") or not probe.has_method("query_connectivity_filtered") or not probe.has_method("pack_edge_inputs") or not probe.has_method("pack_owner_inputs") or not probe.has_method("query_administrative_fields") or not probe.has_method("query_key_order") or not probe.has_method("pack_trade_city_inputs") or not probe.has_method("query_logistics_access"):
		_fatal("NativeGraphSnapshot API version mismatch; rebuild the extension.")
		return false
	return true

static func _fatal(message: String) -> void:
	push_error(message)
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		loop.call_deferred("quit", 1)

static func verify_equal(expected: Variant, actual: Variant, label: String) -> void:
	if var_to_bytes(expected) != var_to_bytes(actual):
		_fatal("Native compute differs from GDScript: " + label)

static func _checked(result: Dictionary, label: String) -> Dictionary:
	if result.has("error"):
		_fatal("Native compute " + label + ": " + str(result.error))
	return result

static func _new_graph(state: GameState, adjacency: Variant, edges: Array, lookup: Dictionary) -> Dictionary:
	if not require_native():
		return {}
	var offsets := PackedInt32Array([0])
	var targets := PackedInt32Array()
	var edge_ids := PackedInt32Array()
	var controls := PackedInt32Array()
	var geometry := PackedFloat64Array()
	var indices := {}
	var control_edges := {}
	var edge_indices := {}
	for index in range(edges.size()):
		var edge: Edge = edges[index]
		indices[edge.get_instance_id()] = index
		controls.append(edge.control_city_id if edge.control_city_id >= 0 and edge.control_city_id < state.cities.size() else -1)
		edge_indices[GameState.edge_key(edge.city_a, edge.city_b)] = index
		if not control_edges.has(edge.control_city_id):
			control_edges[edge.control_city_id] = PackedInt32Array()
		var entries: PackedInt32Array = control_edges[edge.control_city_id]
		entries.append(index)
		control_edges[edge.control_city_id] = entries
	for city in state.cities:
		geometry.append_array(PackedFloat64Array([
			city.map_position.x, city.map_position.y,
			absf(city.map_position.x - 0.5), city.terrain_height, city.terrain_relief,
		]))
		for neighbor in adjacency[city.id]:
			var edge: Edge = lookup.get(GameState.edge_key(city.id, neighbor))
			if edge == null:
				continue
			targets.append(neighbor)
			edge_ids.append(indices[edge.get_instance_id()])
		offsets.append(targets.size())
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	if not bool(graph.call("configure", offsets, targets, edge_ids, controls, geometry)):
		_fatal("Cannot configure native graph snapshot")
		return {}
	return {"graph": graph, "edges": edges, "controls": controls, "control_edges": control_edges, "edge_indices": edge_indices}

static func _state_graph(state: GameState) -> Dictionary:
	# Only topology is cached. Costs and permissions below are read for each query,
	# so direct capacity/access edits cannot silently reuse stale query inputs.
	_mutex.lock()
	var id := state.get_instance_id()
	var stamp := [state.road_network_revision, state.cities.size(), state.edges.size()]
	if _graphs.has(id) and _graphs[id].stamp == stamp and _graphs[id].state.get_ref() == state:
		var cached: Dictionary = _graphs[id].data
		_mutex.unlock()
		return cached
	for key in _graphs.keys():
		if _graphs[key].state.get_ref() == null:
			_graphs.erase(key)
	var data := _new_graph(state, state.adjacency, state.edges, state.edge_lookup)
	if not data.is_empty():
		var offsets := PackedInt32Array([0])
		var targets := PackedInt32Array()
		var edge_groups: Array = []
		for city in state.cities:
			# Copy raw Atlas topology without invoking its typed convenience accessor.
			# Physical path fixtures may store ordinary arrays in this unrelated graph.
			var neighbors: Array = state.neighbors(city.id) if state.atlas_layout.is_empty() else state.atlas_layout.get("settlement_adjacency", {}).get(city.id, [])
			for neighbor in neighbors:
				var segments: Array[Edge] = []
				var direct := state.edge_of(city.id, neighbor)
				var route_available := direct != null
				if direct != null:
					segments.append(direct)
				else:
					var path: Array = state.atlas_layout.get("strategic_routes", {}).get("%d:%d" % [mini(city.id, neighbor), maxi(city.id, neighbor)], [])
					route_available = not path.is_empty()
					for step in range(1, path.size()):
						var segment := state.edge_of(path[step - 1], path[step])
						if segment == null:
							route_available = false
							segments.clear()
							break
						segments.append(segment)
				if not route_available: continue
				targets.append(neighbor)
				edge_groups.append(segments)
			offsets.append(targets.size())
		data["strategic_offsets"] = offsets
		data["strategic_targets"] = targets
		data["strategic_edge_groups"] = edge_groups
	_graphs[id] = {"stamp": stamp, "state": weakref(state), "data": data}
	_mutex.unlock()
	return data

static func _mask(count: int, keys: Dictionary) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(count)
	for key in keys:
		if int(key) >= 0 and int(key) < count:
			result[int(key)] = 1
	return result

static func travel_field(state: GameState, start: int, required: int, horizon: float) -> Dictionary:
	var started := _profile_start()
	var batch := _batch(state)
	var data: Dictionary = batch.data if not batch.is_empty() else _state_graph(state)
	if data.is_empty(): return {}
	var costs := PackedFloat64Array()
	var enabled := PackedByteArray()
	if not batch.is_empty() and not (batch.travel_costs as PackedFloat64Array).is_empty():
		costs = batch.travel_costs
		enabled = batch.enabled
	else:
		var packed := _edge_inputs(data, 8)
		costs = packed.travel
		enabled = packed.enabled
	_record_profile("travel", "pack", started)
	started = _profile_start()
	var result: Dictionary = data.graph.call("query_travel", start, costs, enabled, horizon)
	return _finish_result(result, "travel", started)

static func _finish_result(result: Dictionary, label: String, started: int) -> Dictionary:
	# Native-call timing includes construction of returned Godot containers.
	_record_profile(label, "native_call", started)
	started = _profile_start()
	var checked := _checked(result, label)
	_record_profile(label, "result_check", started)
	return checked

static func path_field(state: GameState, start: int, nation: int, contested: bool, danger: bool, goal: int, required: int, blocked: Dictionary, explicit_exit: int) -> Dictionary:
	var blocked_edges := Pathfinding._enemy_occupied_edge_keys(state, nation) if contested else {}
	var exit_city := explicit_exit if explicit_exit >= 0 else (start if not state.cities[start].is_traffic else -1)
	return _path_query(state, start, nation, goal, exit_city, required, danger, blocked, blocked_edges, [] as Array[int], false, false)

static func supply_field(state: GameState, start: int, nation: int, blocked_edges: Dictionary, ready: bool, origins: Array[int], logistics: bool) -> Dictionary:
	if not ready:
		blocked_edges = Pathfinding._enemy_occupied_edge_keys(state, nation)
	return _path_query(state, start, nation, -1, -1, 0, false, {}, blocked_edges, origins, true, logistics)

static func _path_query(state: GameState, start: int, nation: int, goal: int, exit_city: int, required: int, danger: bool, blocked: Dictionary, blocked_edges: Dictionary, origins: Array[int], supply: bool, logistics: bool) -> Dictionary:
	var started := _profile_start()
	var batch := _batch(state)
	var data: Dictionary = batch.data if not batch.is_empty() else _state_graph(state)
	if data.is_empty(): return {}
	var costs := PackedFloat64Array()
	var enabled := PackedByteArray()
	var accessible := PackedByteArray()
	var live_controls := PackedInt32Array()
	var profile_key := Vector2i(nation if nation >= 0 else -1, int(logistics) if nation >= 0 else 0)
	var cost_key := "supply_costs" if supply else ("danger_costs" if danger else "path_costs")
	var cached_inputs: bool = not batch.is_empty() and not (batch[cost_key] as PackedFloat64Array).is_empty() and batch.access_profiles.has(profile_key)
	if cached_inputs:
		costs = batch[cost_key]
		enabled = batch.enabled
		if not blocked_edges.is_empty():
			enabled = enabled.duplicate()
			for key in blocked_edges:
				if data.edge_indices.has(key): enabled[int(data.edge_indices[key])] = 0
		accessible = batch.access_profiles[profile_key]
		live_controls = batch.controls
	else:
		# Standalone searches read live values: direct Edge/owner edits remain
		# observable without relying on the public revision update helpers.
		var packed := _edge_inputs(data, 4 if supply else (2 if danger else 1))
		costs = packed.supply if supply else (packed.danger if danger else packed.path)
		enabled = packed.enabled
		live_controls = packed.controls
		for key in blocked_edges:
			if data.edge_indices.has(key): enabled[int(data.edge_indices[key])] = 0
		if nation < 0:
			accessible.resize(data.edges.size())
			accessible.fill(1)
		else:
			accessible = _base_access(state, data, nation, logistics, _ownership_inputs(state, data), live_controls)
	if nation >= 0:
		var enemy_goal := goal >= 0 and goal < state.cities.size() and state.is_enemy(nation, state.cities[goal].owner_nation)
		if enemy_goal or (not logistics and exit_city >= 0):
			# Use the exact control snapshot that built the base permissions.
			# Native ptrw detaches its packed copy before patching for this worker.
			var patched: Dictionary = _checked(data.graph.call("patch_access_mask", accessible, live_controls,
				goal if enemy_goal else -1, exit_city if not logistics else -1), "access mask patch")
			accessible = patched.mask
	var order_nation := nation if nation >= 0 else state.cities[start].owner_nation
	var sign_value := EquivariantOrder._nation_forward_sign(state, order_nation)
	var blocked_mask := _mask(state.cities.size(), blocked)
	var packed_origins := PackedInt32Array(origins)
	var label := "supply" if supply else "path"
	_record_profile(label, "pack", started)
	started = _profile_start()
	var result: Dictionary = data.graph.call("query_path", start, packed_origins, costs, enabled, accessible, blocked_mask, PackedByteArray(), goal, exit_city, false, sign_value, PackedInt32Array(), supply)
	return _finish_result(result, label, started)

static func _ownership_inputs(state: GameState, data: Dictionary) -> Dictionary:
	var started := _profile_start()
	var result: Dictionary = data.graph.call("pack_owner_inputs", state.cities)
	_record_profile("owner_inputs", "native_pack_call", started)
	return _checked(result, "owner inputs")

static func _edge_inputs(data: Dictionary, modes: int) -> Dictionary:
	var started := _profile_start()
	var result: Dictionary = data.graph.call("pack_edge_inputs", data.edges, modes, PackedFloat64Array([
		Pathfinding.DANGER_WEIGHT, Pathfinding.SUPPLY_DISTANCE_LOSS, Pathfinding.SUPPLY_DANGER_MULT,
		Simulation.MARCH_DAYS_MIN, Simulation.MARCH_DAYS_PER_DISTANCE_STEP,
	]))
	_record_profile("edge_inputs", "native_pack_call", started)
	return _checked(result, "edge inputs")

static func enemy_occupied_edge_keys(state: GameState, nation: int) -> Dictionary:
	var result := {}
	if nation < 0: return result
	var enemy_by_owner := {}
	for army in state.armies:
		# These predicates and the political lookups are pure. Filter inactive
		# armies first, then resolve each owner's private-conflict relation once.
		if army.size <= 0 or not army.on_edge or army.move_to == -1: continue
		var owner := army.owner_nation
		if not enemy_by_owner.has(owner):
			enemy_by_owner[owner] = not state.succession_identity_pair(owner, nation) and state.is_enemy(owner, nation)
		if enemy_by_owner[owner]:
			result[GameState.edge_key(army.move_from, army.move_to)] = true
	return result

static func _base_access(state: GameState, data: Dictionary, nation: int, logistics: bool, ownership: Dictionary, live_controls: PackedInt32Array) -> PackedByteArray:
	var permissions := {}
	for owner in ownership.unique:
		permissions[owner] = state.has_logistics_access(nation, owner) if logistics else state.has_military_access(nation, owner)
	var result: Dictionary = _checked(data.graph.call("make_access_mask", ownership.owners, permissions, live_controls), "access mask")
	return result.get("mask", PackedByteArray())

static func _strategic_enabled(data: Dictionary) -> PackedByteArray:
	var enabled := PackedByteArray()
	for segments: Array in data.strategic_edge_groups:
		var open := 1
		for edge: Edge in segments:
			if edge.max_manpower <= 0:
				open = 0
				break
		enabled.append(open)
	return enabled

static func trade_field(state: GameState, graph: Dictionary, starts: Array[int], allowed: PackedByteArray, operational: bool, besieged: Dictionary, blocked: Dictionary) -> Dictionary:
	# Trade adjacency has its own sorted insertion order; do not substitute the
	# military graph even when it contains the same physical edges.
	var started := _profile_start()
	var data := _trade_graph(state, graph)
	if data.is_empty(): return {}
	_mutex.lock()
	var batch: Dictionary = _trade_batches.get(state.get_instance_id(), {})
	_mutex.unlock()
	var costs := PackedInt64Array()
	var enabled := PackedByteArray()
	if not batch.is_empty() and is_same(batch.source, graph):
		costs = batch.operational if operational else batch.ideal
		enabled = batch.enabled if operational else batch.all_enabled
		if operational and not blocked.is_empty():
			enabled = enabled.duplicate()
			for key in blocked:
				if data.edge_indices.has(key): enabled[int(data.edge_indices[key])] = 0
	else:
		for edge: Edge in data.edges:
			costs.append(TradeNetwork._edge_transport_cost_units(edge, operational))
			enabled.append(1 if not operational or (edge.max_manpower > 0 and not blocked.has(GameState.edge_key(edge.city_a, edge.city_b))) else 0)
	var origins := PackedInt32Array(starts)
	# The legacy API treats missing allowed entries as inaccessible, including
	# an empty mask. Native optional masks mean unrestricted, so pad explicitly.
	if allowed.size() != state.cities.size():
		allowed = allowed.duplicate()
		allowed.resize(state.cities.size())
	var forbidden := _mask(state.cities.size(), besieged) if operational else PackedByteArray()
	_record_profile("trade", "pack", started)
	started = _profile_start()
	var result: Dictionary = data.graph.call("query_trade", origins, costs, enabled, allowed, forbidden, TradeNetwork.INF_COST_UNITS)
	return _finish_result(result, "trade", started)

static func _trade_graph(state: GameState, source: Dictionary) -> Dictionary:
	_mutex.lock()
	var id := state.get_instance_id()
	if _trade_graphs.has(id) and is_same(_trade_graphs[id].source, source) and _trade_graphs[id].state.get_ref() == state:
		var cached: Dictionary = _trade_graphs[id].data
		_mutex.unlock()
		return cached
	for key in _trade_graphs.keys():
		if _trade_graphs[key].state.get_ref() == null: _trade_graphs.erase(key)
	var data := _new_graph(state, source.adjacency, source.edge_lookup.values(), source.edge_lookup)
	_trade_graphs[id] = {"state": weakref(state), "source": source, "data": data}
	_mutex.unlock()
	return data

## TradeNetwork holds its own world lock around route construction. Inputs are
## frozen only for that call; standalone queries always recompute live weights.
static func begin_trade_batch(state: GameState, graph: Dictionary) -> bool:
	if backend() == "gdscript": return false
	_mutex.lock()
	var occupied := _trade_batches.has(state.get_instance_id())
	_mutex.unlock()
	if occupied: return false
	var started := _profile_start()
	var data := _trade_graph(state, graph)
	if data.is_empty(): return false
	var ideal := PackedInt64Array()
	var operational := PackedInt64Array()
	var enabled := PackedByteArray()
	var all_enabled := PackedByteArray()
	for edge: Edge in data.edges:
		ideal.append(TradeNetwork._edge_transport_cost_units(edge, false))
		operational.append(TradeNetwork._edge_transport_cost_units(edge, true))
		enabled.append(1 if edge.max_manpower > 0 else 0)
		all_enabled.append(1)
	var batch := {"source": graph, "ideal": ideal, "operational": operational, "enabled": enabled, "all_enabled": all_enabled}
	batch.make_read_only()
	_mutex.lock()
	_trade_batches[state.get_instance_id()] = batch
	_mutex.unlock()
	_record_profile("trade_batch", "pack", started)
	return true

static func end_trade_batch(state: GameState) -> void:
	_mutex.lock()
	_trade_batches.erase(state.get_instance_id())
	_mutex.unlock()

## Integer key permutation; Godot's equal-key order is part of the contract.
static func key_order(keys: Array) -> PackedInt32Array:
	var reference: Array[int] = []
	if backend() in ["gdscript", "compare"]:
		for index in range(keys.size()): reference.append(index)
		reference.sort_custom(func(a: int, b: int) -> bool:
			return EquivariantOrder._key_less(keys[a], keys[b]))
	if backend() == "gdscript": return PackedInt32Array(reference)
	if not require_native(): return PackedInt32Array()
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	var started := _profile_start()
	var result: Dictionary = graph.call("query_key_order", keys)
	var order: PackedInt32Array = _finish_result(result, "key_order", started).get("order", PackedInt32Array())
	if backend() == "compare": verify_equal(PackedInt32Array(reference), order, "key_order")
	return order


## One frozen fiscal batch. Integer fields retain the reference queue order;
## live adjacency and model properties are packed inside the native call.
static func administrative_fields(state: GameState, nations: Array[int]) -> Dictionary:
	var reference := {}
	if backend() == "gdscript" or state.atlas_layout.is_empty():
		for nation in nations: reference[nation] = RebellionSystem.capital_hops(state,nation)
		return reference
	if not require_native(): return {}
	var started := _profile_start()
	var capitals := PackedInt32Array()
	for nation in nations:
		var capital := (
			state.nations[nation].capital_city_id
			if nation >= 0 and nation < state.nations.size() and state.nations[nation].alive
			else -1
		)
		capitals.append(capital if capital >= 0 and capital < state.cities.size() else -1)
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	_record_profile("administrative_fields", "pack", started)
	started = _profile_start()
	var result: Dictionary = graph.call(
		"query_administrative_fields", state.cities, state.adjacency,
		state.edge_lookup, PackedInt32Array(nations), capitals, City.NodeKind.TRAFFIC
	)
	var fields: Dictionary = _finish_result(result,"administrative_fields",started).get("fields",{})
	if backend() == "compare":
		for nation in nations: reference[nation] = RebellionSystem.capital_hops(state,nation)
		verify_equal(reference,fields,"administrative_fields")
	return fields

## Forecast records use signed int64 and preserve every float64 bit. Models
## remain live and read-only; no revision-based city input cache is introduced.
static func trade_city_inputs(cities: Array, day: int, include_food: bool) -> Dictionary:
	var mode := backend()
	var reference := {}
	if mode in ["gdscript", "compare"]:
		var records := PackedInt64Array()
		var ratios := PackedFloat64Array()
		var width := 4 if include_food else 3
		records.resize(cities.size() * width)
		if include_food: ratios.resize(cities.size())
		for index in range(cities.size()):
			var city = cities[index]
			var offset := index * width
			records[offset] = city.id
			if include_food:
				records[offset + 1] = city.food_storage
				ratios[index] = city.garrison_supply_ratio
			records[offset + width - 2] = city.garrison_manpower
			records[offset + width - 1] = int(day < city.war_disruption_until_day)
		reference = {"records": records, "ratios": ratios}
	if mode == "gdscript": return reference
	if not require_native(): return {}
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	var started := _profile_start()
	var result: Dictionary = _finish_result(graph.call("pack_trade_city_inputs", cities, day, include_food), "trade_city_inputs", started)
	if mode == "compare": verify_equal(reference, result, "trade_city_inputs")
	return result


## A frozen supply preparation pass. Preserve custom callback states and keep
## standalone permission queries live; this table is never revision-cached.
static func logistics_access_rows(state: GameState, travelers: Array[int]) -> Dictionary:
	var mode := backend()
	if mode == "gdscript" or travelers.is_empty() or state.atlas_layout.is_empty() or state.get_script().resource_path != "res://scripts/state/game_state.gd":
		return {}
	if not require_native(): return {}
	var roots := {}
	var owners := PackedInt64Array()
	var identities := PackedByteArray()
	for nation in state.nations:
		var root := state.financial_nation_of(nation.id)
		roots[nation.id] = root
		owners.append(root)
		identities.append(int(nation.succession_identity))
	var queries := PackedInt64Array()
	for traveler in travelers:
		queries.append(int(roots[traveler]) if roots.has(traveler) else state.financial_nation_of(traveler))
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	var started := _profile_start()
	var result := _finish_result(graph.call("query_logistics_access", queries, owners, identities, state.diplomatic_relations, GameState.DiplomaticRelation.ALLIED, GameState.DiplomaticRelation.WAR), "logistics_access", started)
	if not bool(result.get("supported", false)): return {}
	var rows: Dictionary = {}
	for index in range(travelers.size()): rows[travelers[index]] = result["rows"][index]
	if mode == "compare":
		var reference := {}
		for traveler in travelers:
			var row := PackedByteArray()
			for nation in state.nations: row.append(int(state.has_logistics_access(traveler, nation.id)))
			reference[traveler] = row
		verify_equal(reference, rows, "logistics_access")
	return rows


static func connectivity(snapshot: StrategicMapSnapshot, roots: Array[int]) -> Dictionary:
	var started := _profile_start()
	var state := snapshot._state
	var batch := _batch(state)
	var data: Dictionary = batch.data if not batch.is_empty() else _state_graph(state)
	if data.is_empty(): return {}
	if not state.atlas_layout.is_empty():
		var owners: PackedInt32Array = batch.owners if not batch.is_empty() else (_ownership_inputs(state, data).owners as PackedInt32Array)
		var enabled: PackedByteArray = batch.strategic_enabled if not batch.is_empty() else _strategic_enabled(data)
		var sign_value := EquivariantOrder._nation_forward_sign(state, snapshot.nation_id)
		var packed_roots := PackedInt32Array(roots)
		_record_profile("connectivity", "pack", started)
		started = _profile_start()
		var result: Dictionary = data.graph.call("query_connectivity_filtered", packed_roots, data.strategic_offsets, data.strategic_targets, enabled, owners, snapshot.nation_id, snapshot.city_value, sign_value)
		return _finish_result(result, "connectivity", started)
	var offsets := PackedInt32Array([0])
	var targets := PackedInt32Array()
	var values := PackedFloat64Array()
	for city in state.cities:
		values.append(float(snapshot.city_value.get(city.id, 0.0)))
		if city.owner_nation == snapshot.nation_id:
			targets.append_array(PackedInt32Array(snapshot._friendly_neighbors(city.id)))
		offsets.append(targets.size())
	var packed_roots := PackedInt32Array(roots)
	_record_profile("connectivity", "pack", started)
	started = _profile_start()
	var result: Dictionary = data.graph.call("query_connectivity", packed_roots, offsets, targets, values)
	return _finish_result(result, "connectivity", started)
