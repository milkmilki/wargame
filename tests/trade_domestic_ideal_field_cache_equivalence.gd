extends SceneTree
## domestic ideal field 跨 build shared cache 等价守卫。
## Godot --headless --path . --script res://tests/trade_domestic_ideal_field_cache_equivalence.gd

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_old_api_compatibility()
	_test_dynamic_only_hit_matches_uncached()
	_test_static_changes_miss()
	_test_direct_mutation_not_shared()
	_test_malformed_snapshot_rebuilds()
	_test_size_mismatch_snapshot_rebuilds()
	_test_shared_cache_size_limit()
	_test_simulation_owned_cache_path()
	print("=== domestic ideal field cache 等价校验 ===")
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TRADE_DOMESTIC_IDEAL_FIELD_CACHE_EQUIVALENT")
		quit(0)
		return
	for failure in _failures:
		push_error("TRADE_DOMESTIC_IDEAL_FIELD_CACHE_FAIL: " + failure)
	print("TRADE_DOMESTIC_IDEAL_FIELD_CACHE_DIVERGED")
	quit(1)


func _test_old_api_compatibility() -> void:
	var state := _make_state()
	var legacy := TradeNetwork.build_structure(state, true)
	var explicit := TradeNetwork.build_structure(state, true, {}, {})
	_check(
		legacy == explicit,
		"api/build_structure_tail_default_compatible"
	)


func _test_dynamic_only_hit_matches_uncached() -> void:
	var cached_state := _make_state()
	var uncached_state := _make_state()
	var shared := _make_shared_cache(cached_state)
	var before := _build_with_shared(cached_state, shared)
	_mutate_dynamic_only(cached_state)
	_mutate_dynamic_only(uncached_state)
	var after_cached := _build_with_shared(cached_state, shared)
	var after_uncached := TradeNetwork.build_structure(uncached_state, true)
	_check(
		after_cached["structure"] == after_uncached,
		"dynamic_only/cached_matches_uncached"
	)
	_check(
		int(before["counters"]["domestic_ideal_shared_cache_misses"]) > 0
			and int(after_cached["counters"]["domestic_ideal_shared_cache_hits"]) > 0,
		"dynamic_only/hits_after_warm",
		"before=%s after=%s" % [
			str(before["counters"]), str(after_cached["counters"]),
		]
	)


func _test_static_changes_miss() -> void:
	_assert_static_miss(
		"ownership",
		func(state: GameState) -> void:
			state.cities[0].owner_nation = 1
			state.cities[2].owner_nation = 0
	)
	_assert_static_miss(
		"capital_source",
		func(state: GameState) -> void:
			state.nations[0].capital_city_id = 1
			state.cities[1].is_dock = false
	)
	_assert_static_miss(
		"edge_distance",
		func(state: GameState) -> void:
			state.edges[0].distance += 1
	)
	_assert_static_miss(
		"edge_kind",
		func(state: GameState) -> void:
			state.edges[0].kind = Edge.Kind.RIVER
	)
	_assert_static_miss(
		"edge_capacity",
		func(state: GameState) -> void:
			state.edges[0].max_manpower = 5000
			state.edges[0].base_max_manpower = 5000
	)
	_assert_static_miss(
		"edge_travel",
		func(state: GameState) -> void:
			state.edges[0].travel_time_multiplier += 0.25
	)
	_assert_static_miss(
		"edge_danger",
		func(state: GameState) -> void:
			state.edges[0].danger += 0.15
	)
	_assert_static_miss(
		"edge_supply_loss",
		func(state: GameState) -> void:
			state.edges[0].supply_loss_multiplier += 0.20
	)
	_assert_static_miss(
		"edge_order",
		func(state: GameState) -> void:
			var edge: Edge = state.edges.pop_at(0) as Edge
			state.edges.append(edge)
	)
	_assert_static_miss(
		"topology",
		func(state: GameState) -> void:
			var edge := Edge.new()
			edge.city_a = 0
			edge.city_b = 4
			edge.kind = Edge.Kind.LAND
			edge.max_manpower = 20000
			edge.base_max_manpower = 20000
			edge.distance = 1
			edge.travel_time_multiplier = 1.0
			edge.danger = 0.0
			edge.supply_loss_multiplier = 0.0
			state.edges.append(edge)
	)


func _test_direct_mutation_not_shared() -> void:
	var state := _make_state()
	var shared := _make_shared_cache(state)
	var warmed := _build_with_shared(state, shared)
	var shared_entries: Dictionary = shared["domestic_ideal_fields"]
	var snapshot_before := shared_entries.duplicate(true)
	var domestic_context: Variant = _first_domestic_cached_field(shared_entries)
	_check(
		domestic_context != null,
		"alias/shared_snapshot_created"
	)
	if domestic_context == null:
		return
	var field: Dictionary = warmed["structure"] as Dictionary
	var route: Variant = _first_domestic_route(field)
	_check(route != null, "alias/domestic_route_exists")
	if route == null:
		return
	var rebuilt := _build_with_shared(state, shared)
	_check(
		shared_entries == snapshot_before,
		"alias/shared_snapshot_not_mutated_by_rebuild"
	)
	_check(
		rebuilt["structure"] == warmed["structure"],
		"alias/rebuild_from_shared_matches"
	)


func _test_malformed_snapshot_rebuilds() -> void:
	var state := _make_state()
	var shared := _make_shared_cache(state)
	var warm := _build_with_shared(state, shared)
	var entries: Dictionary = shared["domestic_ideal_fields"]
	var key: Variant = _first_shared_key(entries)
	_check(key != null, "malformed/shared_key_exists")
	if key == null:
		return
	entries[key] = var_to_bytes("bad_payload")
	var rebuilt := _build_with_shared(state, shared)
	_check(
		rebuilt["structure"] == warm["structure"],
		"malformed/rebuild_matches_baseline"
	)
	_check(
		int(rebuilt["counters"]["domestic_ideal_shared_cache_misses"]) > 0
			and int(rebuilt["counters"]["domestic_ideal_shared_cache_builds"]) > 0,
		"malformed/invalid_entry_treated_as_miss",
		str(rebuilt["counters"])
	)
	_check(
		_valid_shared_snapshot(entries[key], state.cities.size()),
		"malformed/entry_replaced_with_valid_snapshot"
	)


func _test_size_mismatch_snapshot_rebuilds() -> void:
	var state := _make_state()
	var shared := _make_shared_cache(state)
	var warm := _build_with_shared(state, shared)
	var entries: Dictionary = shared["domestic_ideal_fields"]
	var key: Variant = _first_shared_key(entries)
	_check(key != null, "size_mismatch/shared_key_exists")
	if key == null:
		return
	entries[key] = var_to_bytes([
		PackedInt64Array([1, 2]),
		PackedInt32Array([0, 1]),
		PackedInt32Array([0, 1]),
	])
	var rebuilt := _build_with_shared(state, shared)
	_check(
		rebuilt["structure"] == warm["structure"],
		"size_mismatch/rebuild_matches_baseline"
	)
	_check(
		int(rebuilt["counters"]["domestic_ideal_shared_cache_misses"]) > 0
			and int(rebuilt["counters"]["domestic_ideal_shared_cache_builds"]) > 0,
		"size_mismatch/invalid_entry_treated_as_miss",
		str(rebuilt["counters"])
	)
	_check(
		_valid_shared_snapshot(entries[key], state.cities.size()),
		"size_mismatch/entry_replaced_with_valid_snapshot"
	)


func _test_shared_cache_size_limit() -> void:
	var shared := _make_shared_cache(_make_state())
	var size_limit := TradeNetwork.DOMESTIC_IDEAL_SHARED_CACHE_MAX_ENTRIES
	var last_state := _make_state()
	var last_structure := {}
	var saw_clear := false
	for index in range(size_limit + 8):
		var state := _make_state()
		state.edges[0].distance += index
		var result := _build_with_shared(state, shared)
		var direct := TradeNetwork.build_structure(state, true)
		_check(
			result["structure"] == direct,
			"size_limit/equivalent_%d" % index
		)
		var entries: Dictionary = shared["domestic_ideal_fields"]
		_check(
			entries.size() <= size_limit,
			"size_limit/entries_bounded_%d" % index,
			"size=%d limit=%d" % [entries.size(), size_limit]
		)
		if int(result["counters"]["domestic_ideal_shared_cache_clears"]) > 0:
			saw_clear = true
		last_state = state
		last_structure = result["structure"]
	_check(saw_clear, "size_limit/clear_recorded")
	_check(
		TradeNetwork.build_structure(last_state, true) == last_structure,
		"size_limit/last_result_still_equivalent"
	)


func _test_simulation_owned_cache_path() -> void:
	var world := _make_state()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(world)
	sim.trade_forecast_cache_disabled = false
	sim.trade_domestic_ideal_field_cache_disabled = false
	sim._trade_structure_cache.clear()
	sim._trade_structure_fingerprint = PackedByteArray()
	var first := sim._forecast_trade_and_gold_flows()
	var build_total_before := sim.trade_domestic_ideal_cache_build_total
	var hit_total_before := sim.trade_domestic_ideal_cache_hit_total
	world.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	var second := sim._forecast_trade_and_gold_flows()
	var direct := TradeNetwork.build(world, true)
	_check(
		second["trade"] == direct,
		"simulation_owned/dynamic_change_matches_direct"
	)
	_check(
		sim.trade_domestic_ideal_cache_hit_total > hit_total_before
			or sim.trade_domestic_ideal_cache_build_total >= build_total_before,
		"simulation_owned/diagnostics_recorded",
		"build=%d hit=%d miss=%d clear=%d" % [
			sim.trade_domestic_ideal_cache_build_total,
			sim.trade_domestic_ideal_cache_hit_total,
			sim.trade_domestic_ideal_cache_miss_total,
			sim.trade_domestic_ideal_cache_generation_clear_total,
		]
	)
	_check(
		first["trade"] != {} and second["trade"] != {},
		"simulation_owned/forecast_exercised"
	)
	sim.free()


func _assert_static_miss(
	label: String,
	mutator: Callable
) -> void:
	var cached_state := _make_state()
	var uncached_state := _make_state()
	var shared := _make_shared_cache(cached_state)
	var warm := _build_with_shared(cached_state, shared)
	mutator.call(cached_state)
	mutator.call(uncached_state)
	var after_cached := _build_with_shared(cached_state, shared)
	var after_uncached := TradeNetwork.build_structure(uncached_state, true)
	_check(
		after_cached["structure"] == after_uncached,
		"static_miss/%s_cached_matches_uncached" % label
	)
	_check(
		int(warm["counters"]["domestic_ideal_shared_cache_misses"]) > 0
			and int(after_cached["counters"]["domestic_ideal_shared_cache_misses"]) > 0
			and int(after_cached["counters"]["domestic_ideal_shared_cache_builds"]) > 0,
		"static_miss/%s_forces_miss" % label,
		"warm=%s after=%s" % [
			str(warm["counters"]), str(after_cached["counters"]),
		]
	)


func _build_with_shared(
	state: GameState,
	shared: Dictionary
) -> Dictionary:
	TradeNetwork.reset_connectivity_prefilter_counters()
	var structure := TradeNetwork.build_structure(state, true, {}, shared)
	return {
		"structure": structure,
		"counters": TradeNetwork.connectivity_prefilter_counters(),
	}


func _make_shared_cache(state: GameState) -> Dictionary:
	return {
		"domestic_ideal_fields": {},
	}


func _mutate_dynamic_only(state: GameState) -> void:
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	var army := Army.new()
	army.id = state.armies.size()
	army.owner_nation = 2
	army.size = 4000
	army.on_edge = true
	army.move_from = 1
	army.move_to = 4
	state.armies.append(army)
	var battle := Battle.new()
	battle.id = state.battles.size()
	battle.kind = Battle.Kind.SIEGE
	battle.city = state.cities[1]
	battle.finished = false
	state.battles.append(battle)
	state.refresh_derived()


func _first_domestic_cached_field(shared_entries: Dictionary) -> Variant:
	if shared_entries.is_empty():
		return null
	for _key in shared_entries:
		return shared_entries[_key]
	return null


func _first_shared_key(shared_entries: Dictionary) -> Variant:
	if shared_entries.is_empty():
		return null
	for key in shared_entries:
		return key
	return null


func _valid_shared_snapshot(
	value: Variant,
	expected_city_count: int
) -> bool:
	if not value is PackedByteArray:
		return false
	var decoded := TradeNetwork._deserialize_preferred_endpoint_field_snapshot(
		value as PackedByteArray,
		expected_city_count
	)
	return not decoded.is_empty()


func _first_domestic_route(structure: Dictionary) -> Variant:
	for route_value in structure.get("routes", []):
		var route: Dictionary = route_value
		if str(route.get("kind", "")) == "domestic":
			return route
	return null


func _make_state() -> GameState:
	var state := GameState.new()
	state.world_seed = 13579
	state.map_aspect_ratio = 1.3
	for nation_id in range(3):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.capital_city_id = nation_id * 2
		nation.warehouse_city_ids = [nation.capital_city_id] as Array[int]
		nation.trade_policy = TradeNetwork.BALANCED
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits = [] as Array[String]
		nation.treasury_gold = 1000
		nation.last_food_demand = 10
		state.nations.append(nation)

	_add_city(state, 0, Vector2(0.10, 0.20), 20, 800, 200)
	_add_city(state, 0, Vector2(0.22, 0.28), 14, 600, 0)
	_add_city(state, 1, Vector2(0.80, 0.25), 18, 700, 0)
	_add_city(state, 1, Vector2(0.68, 0.36), 12, 450, 0)
	_add_city(state, 2, Vector2(0.45, 0.70), 16, 750, 150)
	_add_city(state, 2, Vector2(0.55, 0.62), 11, 420, 0)

	for capital_id in [0, 2, 4]:
		state.cities[capital_id].is_capital = true
		state.cities[capital_id].has_warehouse = true
	state.cities[1].is_crossroads = true
	state.cities[5].is_dock = true

	_add_edge(state, 0, 1, 20000, 2, 1.0, 0.05, 0.05)
	_add_edge(state, 1, 4, 18000, 3, 1.0, 0.10, 0.05)
	_add_edge(state, 4, 5, 50000, 2, 0.72, 0.05, 0.02, Edge.Kind.RIVER)
	_add_edge(state, 5, 3, 50000, 2, 0.62, 0.05, 0.02, Edge.Kind.SEA)
	_add_edge(state, 3, 2, 20000, 2, 1.0, 0.10, 0.05)
	_add_edge(state, 1, 3, 16000, 4, 1.2, 0.20, 0.10)

	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	state.refresh_derived()
	return state


func _add_city(
	state: GameState,
	owner: int,
	position: Vector2,
	gold: int,
	food: int,
	storage: int
) -> void:
	var city := City.new()
	city.id = state.cities.size()
	city.owner_nation = owner
	city.map_position = position
	city.gold_per_month = gold
	city.food_per_half_year = food
	city.food_storage = storage
	state.cities.append(city)
	state.adjacency[city.id] = [] as Array[int]


func _add_edge(
	state: GameState,
	a: int,
	b: int,
	capacity: int,
	distance: int,
	travel: float,
	danger: float,
	supply_loss: float,
	kind: int = Edge.Kind.LAND
) -> void:
	var edge := Edge.new()
	edge.city_a = mini(a, b)
	edge.city_b = maxi(a, b)
	edge.kind = kind
	edge.max_manpower = capacity
	edge.base_max_manpower = capacity
	edge.distance = distance
	edge.travel_time_multiplier = travel
	edge.danger = danger
	edge.supply_loss_multiplier = supply_loss
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(a, b)] = edge
	(state.adjacency[a] as Array[int]).append(b)
	(state.adjacency[b] as Array[int]).append(a)


func _check(
	condition: bool,
	label: String,
	detail: String = ""
) -> void:
	_checks += 1
	if condition:
		return
	var message := label
	if not detail.is_empty():
		message += " :: " + detail
	_failures.append(message)
