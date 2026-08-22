class_name TradeNetwork
extends RefCounted
## 当前世界状态的纯派生贸易网络。
##
## 本类不持有缓存、不修改 GameState，也不依赖 Simulation。build() 的结果可直接
## 用于月度经济结算、AI 报告或 UI；相同输入始终得到相同路线、分配和 signature。

enum RouteStatus {
	ACTIVE,
	REROUTED,
	BLOCKED,
}

enum Policy {
	BALANCED,
	GOLD,
	FOOD,
	ISOLATION,
}

const STATUS_ACTIVE: int = RouteStatus.ACTIVE
const STATUS_REROUTED: int = RouteStatus.REROUTED
const STATUS_BLOCKED: int = RouteStatus.BLOCKED
const POLICY_BALANCED: int = Policy.BALANCED
const POLICY_GOLD: int = Policy.GOLD
const POLICY_FOOD: int = Policy.FOOD
const POLICY_ISOLATION: int = Policy.ISOLATION
## 简写别名供 UI / 测试直接使用 TradeNetwork.ACTIVE / BALANCED。
const ACTIVE: int = RouteStatus.ACTIVE
const REROUTED: int = RouteStatus.REROUTED
const BLOCKED: int = RouteStatus.BLOCKED
const BALANCED: int = Policy.BALANCED
const GOLD: int = Policy.GOLD
const FOOD: int = Policy.FOOD
const ISOLATION: int = Policy.ISOLATION

## 40 国地图上的硬上限。国际候选按可达性、运输成本和市场价值排序，
## 再以双方都未达到上限为条件贪心选取，因此任何国家都不会超过此值。
const MAX_INTERNATIONAL_ROUTES_PER_NATION: int = 3
const MAX_DOMESTIC_ROUTES_PER_NATION: int = 4
const INTERNATIONAL_HUBS_PER_NATION: int = 3

## 与现有模型匹配的本地常量。刻意不引用 Simulation，避免 core 层循环依赖。
const FOOD_PER_CAPITA_MONTH: float = 0.0025
const BALANCED_FOOD_RESERVE_MONTHS: int = 6
const GOLD_FOOD_RESERVE_MONTHS: int = 3
const FOOD_POLICY_RESERVE_MONTHS: int = 12
const ISOLATION_FOOD_RESERVE_MONTHS: int = 9
const FOOD_UNITS_PER_GOLD: int = 25
const TRADE_CAPACITY_UNIT: int = 10000
const FOOD_CAPACITY_DIVISOR: int = 100
const MAX_ROUTE_GOLD: int = 64

const EDGE_KIND_LAND: int = 0
const EDGE_KIND_LANDING: int = 1
const EDGE_KIND_RIVER: int = 2
const EDGE_KIND_SEA: int = 3
const MATCHED_LOW_CAPACITY: int = 10000
const MATCHED_STANDARD_CAPACITY: int = 20000

const COST_SCALE: int = 1000
const INF_COST_UNITS: int = 0x3fffffffffffffff
const SORT_SCALE: float = 1000000.0
const UNREACHABLE_COST: float = -1.0


## 权威入口。返回的整数数组均以 city_id / nation_id 为下标。
static func build(state: GameState) -> Dictionary:
	if state == null:
		return _empty_result(0, 0)
	var city_count := state.cities.size()
	var nation_count := state.nations.size()
	if not _state_ids_indexable(state):
		return _empty_result(city_count, nation_count)
	var city_gold_bonus := _zero_int_array(city_count)
	var nation_trade_gold := _zero_int_array(nation_count)
	var nation_trade_tax := _zero_int_array(nation_count)
	var nation_food_import := _zero_int_array(nation_count)
	var nation_food_export := _zero_int_array(nation_count)
	var nation_food_cost := _zero_int_array(nation_count)
	var nation_food_sale_income := _zero_int_array(nation_count)
	if city_count <= 0 or nation_count <= 0:
		return _finish_result(
			[] as Array[Dictionary],
			city_gold_bonus, nation_trade_gold, nation_trade_tax,
			nation_food_import, nation_food_export, nation_food_cost,
			nation_food_sale_income,
			[] as Array[int]
		)

	var policies := _collect_policies(state)
	var graph := _build_graph(state)
	var besieged := state.besieged_city_ids()
	var occupied_edges := _enemy_occupancy_records(state)
	var field_cache := {}
	var routes: Array[Dictionary] = []
	routes.append_array(_build_domestic_routes(
		state, graph, policies, besieged, occupied_edges, field_cache
	))
	routes.append_array(_build_international_routes(
		state, graph, policies, besieged, occupied_edges, field_cache
	))

	routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var international_a := bool(a["international"])
		var international_b := bool(b["international"])
		if international_a != international_b:
			return not international_a
		for key in ["nation_a", "nation_b", "source", "destination"]:
			var value_a := int(a[key])
			var value_b := int(b[key])
			if value_a != value_b:
				return value_a < value_b
		return int(a["status"]) < int(b["status"])
	)
	for route_id in range(routes.size()):
		routes[route_id]["id"] = route_id

	_apply_trade_taxes(
		state, routes, policies, city_gold_bonus,
		nation_trade_gold, nation_trade_tax
	)
	_plan_food_transfers(
		state, routes, policies,
		nation_trade_gold, nation_food_import, nation_food_export,
		nation_food_cost, nation_food_sale_income
	)
	return _finish_result(
		routes, city_gold_bonus, nation_trade_gold, nation_trade_tax,
		nation_food_import, nation_food_export, nation_food_cost,
		nation_food_sale_income,
		policies
	)


static func _state_ids_indexable(state: GameState) -> bool:
	for city_index in range(state.cities.size()):
		if state.cities[city_index].id != city_index:
			return false
	for nation_index in range(state.nations.size()):
		if state.nations[nation_index].id != nation_index:
			return false
	return true


## 兼容调用名；所有实现都收敛到 build()。
static func compute(state: GameState) -> Dictionary:
	return build(state)


static func derive(state: GameState) -> Dictionary:
	return build(state)


static func _empty_result(city_count: int, nation_count: int) -> Dictionary:
	return _finish_result(
		[] as Array[Dictionary],
		_zero_int_array(city_count), _zero_int_array(nation_count),
		_zero_int_array(nation_count),
		_zero_int_array(nation_count), _zero_int_array(nation_count),
		_zero_int_array(nation_count), _zero_int_array(nation_count),
		[] as Array[int]
	)


static func _finish_result(
	routes: Array[Dictionary],
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int],
	nation_food_import: Array[int],
	nation_food_export: Array[int],
	nation_food_cost: Array[int],
	nation_food_sale_income: Array[int],
	policies: Array[int]
) -> Dictionary:
	var signature := _result_signature(
		routes, city_gold_bonus, nation_trade_gold, nation_trade_tax,
		nation_food_import, nation_food_export, nation_food_cost,
		nation_food_sale_income,
		policies
	)
	return {
		"routes": routes,
		"city_gold_bonus": city_gold_bonus,
		"nation_trade_gold": nation_trade_gold,
		"nation_trade_tax": nation_trade_tax,
		"nation_food_import": nation_food_import,
		"nation_food_export": nation_food_export,
		"nation_food_cost": nation_food_cost,
		"nation_food_sale_income": nation_food_sale_income,
		"signature": signature,
	}


static func _zero_int_array(size: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(maxi(size, 0))
	result.fill(0)
	return result


static func _collect_policies(state: GameState) -> Array[int]:
	var result: Array[int] = []
	result.resize(state.nations.size())
	result.fill(Policy.BALANCED)
	for nation in state.nations:
		if nation.id < 0 or nation.id >= result.size():
			continue
		result[nation.id] = _policy_of(nation)
	return result


static func _policy_of(nation: Object) -> int:
	var raw: Variant = nation.get(&"trade_policy")
	if raw is String or raw is StringName:
		var normalized := str(raw).strip_edges().to_upper()
		if normalized.begins_with("POLICY_"):
			normalized = normalized.trim_prefix("POLICY_")
		match normalized:
			"GOLD":
				return Policy.GOLD
			"FOOD":
				return Policy.FOOD
			"ISOLATION":
				return Policy.ISOLATION
			_:
				return Policy.BALANCED
	return clampi(int(raw), Policy.BALANCED, Policy.ISOLATION)


## 自建只读邻接快照，避免依赖测试夹具是否手工同步了 GameState.adjacency。
static func _build_graph(state: GameState) -> Dictionary:
	var adjacency: Array = []
	adjacency.resize(state.cities.size())
	for city_id in range(adjacency.size()):
		adjacency[city_id] = [] as Array[int]
	var edge_lookup := {}
	for edge in state.edges:
		var a := int(edge.city_a)
		var b := int(edge.city_b)
		if (
			a < 0 or b < 0 or a >= adjacency.size()
			or b >= adjacency.size() or a == b
		):
			continue
		var key := _edge_key(a, b)
		if edge_lookup.has(key):
			continue
		edge_lookup[key] = edge
		(adjacency[a] as Array[int]).append(b)
		(adjacency[b] as Array[int]).append(a)
	for neighbors_value in adjacency:
		(neighbors_value as Array[int]).sort()
	return {
		"adjacency": adjacency,
		"edge_lookup": edge_lookup,
	}


static func _edge_key(a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return (lo << 32) | hi


## 每条实际占用记录只保留 edge 与 owner。是否为敌军取决于具体贸易双方，
## 因而留到派生单条路线时判断。
static func _enemy_occupancy_records(state: GameState) -> Array[Dictionary]:
	var unique := {}
	for army in state.armies:
		if (
			army.size <= 0 or not army.on_edge
			or army.move_from < 0 or army.move_to < 0
			or army.owner_nation < 0
		):
			continue
		var edge_key := _edge_key(army.move_from, army.move_to)
		var record_key := "%d:%d" % [edge_key, army.owner_nation]
		unique[record_key] = {
			"edge_key": edge_key,
			"owner": army.owner_nation,
		}
	var keys := unique.keys()
	keys.sort()
	var result: Array[Dictionary] = []
	for key in keys:
		result.append(unique[key] as Dictionary)
	return result


static func _blocked_edges_for_parties(
	state: GameState,
	nation_a: int,
	nation_b: int,
	occupied_edges: Array[Dictionary]
) -> Dictionary:
	var result := {}
	for record in occupied_edges:
		var owner := int(record["owner"])
		if (
			state.is_enemy(owner, nation_a)
			or state.is_enemy(owner, nation_b)
		):
			result[int(record["edge_key"])] = true
	return result


static func _allowed_city_mask(
	state: GameState,
	nation_a: int,
	nation_b: int
) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(state.cities.size())
	result.fill(0)
	for city in state.cities:
		if city.id < 0 or city.id >= result.size():
			continue
		var owner := city.owner_nation
		if (
			owner >= 0 and owner < state.nations.size()
			and not state.is_enemy(owner, nation_a)
			and not state.is_enemy(owner, nation_b)
		):
			result[city.id] = 1
	return result


static func _ideal_city_mask(state: GameState) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(state.cities.size())
	result.fill(0)
	for city in state.cities:
		if (
			city.id >= 0 and city.id < result.size()
			and city.owner_nation >= 0
			and city.owner_nation < state.nations.size()
		):
			result[city.id] = 1
	return result


static func _build_domestic_routes(
	state: GameState,
	graph: Dictionary,
	policies: Array[int],
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	field_cache: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for nation in state.nations:
		if not nation.alive:
			continue
		var nation_id := nation.id
		if nation_id < 0 or nation_id >= policies.size():
			continue
		var owned_land := _owned_trade_cities(state, nation_id, false)
		var owned_all := _owned_trade_cities(state, nation_id, true)
		if owned_all.size() < 2:
			continue
		var primary := nation.capital_city_id
		if (
			primary < 0 or primary >= state.cities.size()
			or state.cities[primary].owner_nation != nation_id
			or state.cities[primary].is_dock
		):
			primary = (
				owned_land[0] if not owned_land.is_empty() else owned_all[0]
			)
		var destinations: Array[int] = []
		for city_id in owned_land:
			if city_id != primary:
				destinations.append(city_id)
		_sort_hubs(state, destinations, policies[nation_id])
		# A one-land-city port state still gets a domestic capital-to-dock route.
		if destinations.is_empty():
			for city_id in owned_all:
				if city_id != primary:
					destinations.append(city_id)
			destinations.sort()
		var limit := mini(
			MAX_DOMESTIC_ROUTES_PER_NATION, destinations.size()
		)
		for index in range(limit):
			var route := _derive_route(
				state, graph, [primary] as Array[int],
				[destinations[index]] as Array[int],
				nation_id, nation_id, false, besieged, occupied_edges,
				field_cache
			)
			result.append(route)
	return result


static func _build_international_routes(
	state: GameState,
	graph: Dictionary,
	policies: Array[int],
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	field_cache: Dictionary
) -> Array[Dictionary]:
	var hubs_by_nation: Array = []
	hubs_by_nation.resize(state.nations.size())
	for nation_id in range(state.nations.size()):
		hubs_by_nation[nation_id] = _international_hubs(
			state, nation_id, policies[nation_id]
		)
	var ideal_allowed := _ideal_city_mask(state)

	# At 40 nations this is at most 780 cheap pair evaluations. Dijkstra fields
	# are cached by access mask and source hubs, so neutral worlds need roughly
	# one ideal and one operational field per nation, not one per nation pair.
	var candidates: Array[Dictionary] = []
	for nation_a in range(state.nations.size()):
		if (
			not state.nations[nation_a].alive
			or policies[nation_a] == Policy.ISOLATION
			or (hubs_by_nation[nation_a] as Array[int]).is_empty()
		):
			continue
		for nation_b in range(nation_a + 1, state.nations.size()):
			if (
				not state.nations[nation_b].alive
				or policies[nation_b] == Policy.ISOLATION
				or (hubs_by_nation[nation_b] as Array[int]).is_empty()
			):
				continue
			var source_hubs: Array[int] = hubs_by_nation[nation_a]
			var destination_hubs: Array[int] = hubs_by_nation[nation_b]
			var preferred := _select_preferred_endpoints(
				state, graph, source_hubs, destination_hubs,
				ideal_allowed, false, {}, {}, nation_a, nation_b,
				field_cache, false
			)
			# No ideal path means there is no trade corridor to retain as BLOCKED.
			if float(preferred["cost"]) < 0.0:
				continue
			var allowed := _allowed_city_mask(state, nation_a, nation_b)
			var blocked_edges := _blocked_edges_for_parties(
				state, nation_a, nation_b, occupied_edges
			)
			var operational := _select_preferred_endpoints(
				state, graph, source_hubs, destination_hubs, allowed, true,
				besieged, blocked_edges, nation_a, nation_b,
				field_cache, false
			)
			candidates.append({
				"nation_a": nation_a,
				"nation_b": nation_b,
				"operational": float(operational["cost"]) >= 0.0,
				"preferred_transport_cost": float(preferred["cost"]),
				"candidate_value": _international_candidate_value(
					state, int(preferred["source"]),
					int(preferred["destination"]),
					float(preferred["cost"]),
					policies[nation_a], policies[nation_b]
				),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var operational_a := bool(a["operational"])
		var operational_b := bool(b["operational"])
		if operational_a != operational_b:
			return operational_a
		var value_a := _sort_units(float(a["candidate_value"]))
		var value_b := _sort_units(float(b["candidate_value"]))
		if value_a != value_b:
			return value_a > value_b
		var cost_a := _sort_units(float(a["preferred_transport_cost"]))
		var cost_b := _sort_units(float(b["preferred_transport_cost"]))
		if cost_a != cost_b:
			return cost_a < cost_b
		if int(a["nation_a"]) != int(b["nation_a"]):
			return int(a["nation_a"]) < int(b["nation_a"])
		return int(a["nation_b"]) < int(b["nation_b"])
	)

	var counts := _zero_int_array(state.nations.size())
	var result: Array[Dictionary] = []
	for candidate in candidates:
		var nation_a := int(candidate["nation_a"])
		var nation_b := int(candidate["nation_b"])
		if (
			counts[nation_a] >= MAX_INTERNATIONAL_ROUTES_PER_NATION
			or counts[nation_b] >= MAX_INTERNATIONAL_ROUTES_PER_NATION
		):
			continue
		var route := _derive_route(
			state, graph, hubs_by_nation[nation_a],
			hubs_by_nation[nation_b], nation_a, nation_b, true,
			besieged, occupied_edges, field_cache
		)
		result.append(route)
		counts[nation_a] += 1
		counts[nation_b] += 1
	return result


static func _owned_trade_cities(
	state: GameState, nation_id: int, include_docks: bool
) -> Array[int]:
	var result: Array[int] = []
	for city in state.cities:
		if (
			city.owner_nation == nation_id
			and (include_docks or not city.is_dock)
		):
			result.append(city.id)
	result.sort()
	return result


static func _international_hubs(
	state: GameState, nation_id: int, policy: int
) -> Array[int]:
	if (
		nation_id < 0 or nation_id >= state.nations.size()
		or not state.nations[nation_id].alive
	):
		return [] as Array[int]
	var candidates := _owned_trade_cities(state, nation_id, false)
	_sort_hubs(state, candidates, policy)
	var capital := state.nations[nation_id].capital_city_id
	if capital in candidates:
		candidates.erase(capital)
		candidates.push_front(capital)
	if candidates.size() > INTERNATIONAL_HUBS_PER_NATION:
		candidates.resize(INTERNATIONAL_HUBS_PER_NATION)
	return candidates


static func _sort_hubs(
	state: GameState, city_ids: Array[int], policy: int
) -> void:
	city_ids.sort_custom(func(a: int, b: int) -> bool:
		var score_a := _sort_units(_hub_score(state.cities[a], policy))
		var score_b := _sort_units(_hub_score(state.cities[b], policy))
		if score_a != score_b:
			return score_a > score_b
		return a < b
	)


static func _hub_score(city: City, policy: int) -> float:
	var gold_weight := 3.0 if policy == Policy.GOLD else 1.5
	var food_weight := 0.020 if policy == Policy.FOOD else 0.008
	var score := (
		float(maxi(city.gold_per_month, 0)) * gold_weight
		+ float(maxi(city.food_per_half_year, 0)) * food_weight
	)
	if city.is_capital:
		score += 12.0
	if city.has_warehouse:
		score += 8.0
	if city.is_port_market:
		score += 7.0
	if city.is_crossroads:
		score += 5.0
	if city.is_food_hub:
		score += 8.0 if policy == Policy.FOOD else 3.0
	return score


static func _derive_route(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	destinations: Array[int],
	nation_a: int,
	nation_b: int,
	international: bool,
	besieged: Dictionary,
	occupied_edges: Array[Dictionary],
	field_cache: Dictionary,
	derive_operational: bool = true
) -> Dictionary:
	var allowed := _allowed_city_mask(state, nation_a, nation_b)
	var ideal_allowed := _ideal_city_mask(state)
	var blocked_edges := _blocked_edges_for_parties(
		state, nation_a, nation_b, occupied_edges
	)
	var selection := _select_preferred_endpoints(
		state, graph, sources, destinations, ideal_allowed, false, {}, {},
		nation_a, nation_b, field_cache
	)
	var source := int(selection["source"])
	var destination := int(selection["destination"])
	var preferred_path: Array[int] = selection["path"]
	var preferred_cost := float(selection["cost"])
	var operational := {
		"source": source, "destination": destination,
		"path": [] as Array[int], "cost": UNREACHABLE_COST,
	}
	if derive_operational:
		operational = _select_preferred_endpoints(
			state, graph, sources, destinations, allowed, true,
			besieged, blocked_edges,
			nation_a, nation_b, field_cache
		)
	var operational_source := int(operational["source"])
	var operational_destination := int(operational["destination"])
	var operational_path: Array[int] = operational["path"]
	var operational_cost := float(operational["cost"])

	var status := RouteStatus.BLOCKED
	var city_path: Array[int] = []
	if not operational_path.is_empty():
		source = operational_source
		destination = operational_destination
		city_path = operational_path
		status = (
			RouteStatus.ACTIVE
			if (
				preferred_path.is_empty()
				or (operational_source == int(selection["source"])
				and operational_destination == int(selection["destination"])
				and operational_path == preferred_path)
			)
			else RouteStatus.REROUTED
		)
	elif not preferred_path.is_empty():
		city_path = preferred_path

	var obstruction := _first_obstruction(
		state, graph, preferred_path, allowed, besieged, blocked_edges
	)
	if (
		status == RouteStatus.BLOCKED
		and str(obstruction["reason"]).is_empty()
	):
		obstruction["reason"] = "unreachable"
	var route_cost := (
		operational_cost
		if operational_cost >= 0.0 else preferred_cost
	)
	if route_cost >= 0.0:
		route_cost = _quantize_cost(route_cost)
	var details := _path_details(state, graph, city_path, status)
	var preferred_details := _path_details(
		state, graph, preferred_path
	)
	return {
		"id": -1,
		"international": international,
		"kind": "international" if international else "domestic",
		"nation_a": nation_a,
		"nation_b": nation_b,
		"source": source,
		"destination": destination,
		"source_city": source,
		"destination_city": destination,
		"city_path": city_path,
		"preferred_city_path": preferred_path,
		"preferred_transport_cost": (
			_quantize_cost(preferred_cost)
			if preferred_cost >= 0.0 else UNREACHABLE_COST
		),
		"edge_keys": details["edge_keys"],
		"bottleneck": details["bottleneck"],
		"bottleneck_capacity": details["bottleneck"],
		"transport_cost": route_cost,
		"status": status,
		"blocked_reason": obstruction["reason"],
		"blocked_city": obstruction["city"],
		"blocked_edge_key": obstruction["edge_key"],
		"uses_water": details["uses_water"],
		"preferred_uses_water": preferred_details["uses_water"],
		"dock_count": details["dock_count"],
		"gold": 0,
		"gold_tax": 0,
		"gold_to_a": 0,
		"gold_to_b": 0,
		"gold_a": 0,
		"gold_b": 0,
		"transit_gold": 0,
		"city_gold_bonus": {},
		"food": 0,
		"food_transfer": 0,
		"food_exporter": -1,
		"food_importer": -1,
		"food_source_city": -1,
		"food_destination_city": -1,
		"food_cost": 0,
		"food_cost_gold": 0,
	}


static func _select_preferred_endpoints(
	state: GameState,
	graph: Dictionary,
	sources: Array[int],
	destinations: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary,
	nation_a: int,
	nation_b: int,
	field_cache: Dictionary,
	reconstruct_path: bool = true
) -> Dictionary:
	var best_source := -1
	var best_destination := -1
	var best_cost_units := INF_COST_UNITS
	var best_path: Array[int] = []
	var valid_sources: Array[int] = []
	for source in sources:
		if (
			source >= 0 and source < state.cities.size()
			and not valid_sources.has(source)
		):
			valid_sources.append(source)
	valid_sources.sort()
	var cache_key := "%d:%s:%s:%s" % [
		1 if operational else 0, _int_array_key(valid_sources),
		_byte_mask_key(allowed),
		(
			_operational_block_key(besieged, blocked_edges)
			if operational else ""
		),
	]
	var field: Dictionary
	if field_cache.has(cache_key):
		field = field_cache[cache_key]
	else:
		field = _dijkstra_field(
			state, graph, valid_sources, allowed, operational,
			besieged, blocked_edges
		)
		field_cache[cache_key] = field
	var distances: PackedInt64Array = field["dist"]
	var origins: PackedInt32Array = field["origin"]
	for destination in destinations:
		if (
			destination < 0 or destination >= distances.size()
			or distances[destination] >= INF_COST_UNITS
			or origins[destination] < 0
			or origins[destination] == destination
		):
			continue
		var source := origins[destination]
		var cost_units := distances[destination]
		if (
			cost_units < best_cost_units
			or (cost_units == best_cost_units and (
				best_source < 0 or source < best_source
				or (source == best_source and destination < best_destination)
			))
		):
			best_source = source
			best_destination = destination
			best_cost_units = cost_units
			if reconstruct_path:
				best_path = _reconstruct_path(
					field["prev"], source, destination
				)
	if best_source < 0:
		var fallback := _closest_endpoint_pair(state, sources, destinations)
		best_source = fallback.x
		best_destination = fallback.y
	return {
		"source": best_source,
		"destination": best_destination,
		"path": best_path,
		"cost": (
			float(best_cost_units) / float(COST_SCALE)
			if best_cost_units < INF_COST_UNITS else UNREACHABLE_COST
		),
	}


static func _int_array_key(values: Array[int]) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return ",".join(parts)


static func _byte_mask_key(values: PackedByteArray) -> String:
	var result := ""
	var accumulator := 0
	var bit := 0
	for value in values:
		if value != 0:
			accumulator |= 1 << bit
		bit += 1
		if bit == 30:
			result += "%x," % accumulator
			accumulator = 0
			bit = 0
	return result + "%x" % accumulator


static func _operational_block_key(
	besieged: Dictionary, blocked_edges: Dictionary
) -> String:
	var city_ids := besieged.keys()
	city_ids.sort()
	var edge_ids := blocked_edges.keys()
	edge_ids.sort()
	var result := "c"
	for city_id in city_ids:
		result += "%d," % int(city_id)
	result += "e"
	for edge_key in edge_ids:
		result += "%d," % int(edge_key)
	return result


static func _closest_endpoint_pair(
	state: GameState, sources: Array[int], destinations: Array[int]
) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance_units := INF_COST_UNITS
	for source in sources:
		if source < 0 or source >= state.cities.size():
			continue
		for destination in destinations:
			if (
				destination < 0 or destination >= state.cities.size()
				or source == destination
			):
				continue
			var delta := (
				state.cities[source].map_position
				- state.cities[destination].map_position
			)
			delta.x *= maxf(state.map_aspect_ratio, 0.01)
			var distance_units := _sort_units(delta.length_squared())
			if (
				distance_units < best_distance_units
				or (
					distance_units == best_distance_units
					and (
						best.x < 0 or source < best.x
						or (source == best.x and destination < best.y)
					)
				)
			):
				best = Vector2i(source, destination)
				best_distance_units = distance_units
	return best


## operational=false 是“理想商路”：保留静态边和外交限制，但忽略容量关闭、
## 围城与敌军占边。与 operational=true 比较即可无历史状态地派生 REROUTED。
static func _dijkstra_field(
	state: GameState,
	graph: Dictionary,
	starts: Array[int],
	allowed: PackedByteArray,
	operational: bool,
	besieged: Dictionary,
	blocked_edges: Dictionary
) -> Dictionary:
	var city_count := state.cities.size()
	var dist := PackedInt64Array()
	dist.resize(city_count)
	dist.fill(INF_COST_UNITS)
	var prev := PackedInt32Array()
	prev.resize(city_count)
	prev.fill(-1)
	var origin := PackedInt32Array()
	origin.resize(city_count)
	origin.fill(-1)
	var visited := PackedByteArray()
	visited.resize(city_count)
	visited.fill(0)
	var heap: Array[Dictionary] = []
	for start in starts:
		if (
			start < 0 or start >= city_count
			or start >= allowed.size() or allowed[start] == 0
			or (operational and besieged.has(start))
		):
			continue
		dist[start] = 0
		origin[start] = start
		_heap_push(heap, {"city": start, "cost": 0, "origin": start})
	if heap.is_empty():
		return {"dist": dist, "prev": prev, "origin": origin}
	var adjacency: Array = graph["adjacency"]
	var edge_lookup: Dictionary = graph["edge_lookup"]
	while not heap.is_empty():
		var entry := _heap_pop(heap)
		var city_id := int(entry["city"])
		var known_cost := int(entry["cost"])
		if (
			visited[city_id] != 0
			or known_cost != dist[city_id]
			or int(entry["origin"]) != origin[city_id]
		):
			continue
		visited[city_id] = 1
		var neighbors: Array[int] = adjacency[city_id]
		for neighbor in neighbors:
			if (
				visited[neighbor] != 0
				or neighbor >= allowed.size() or allowed[neighbor] == 0
				or (operational and besieged.has(neighbor))
			):
				continue
			var edge_key := _edge_key(city_id, neighbor)
			var edge: Edge = edge_lookup.get(edge_key, null)
			if edge == null:
				continue
			if operational and (
				edge.max_manpower <= 0 or blocked_edges.has(edge_key)
			):
				continue
			var edge_cost := _edge_transport_cost_units(edge, operational)
			var candidate := known_cost + edge_cost
			var candidate_origin := origin[city_id]
			var improves := candidate < dist[neighbor]
			var tie_improves := (
				candidate == dist[neighbor]
				and (origin[neighbor] < 0 or candidate_origin < origin[neighbor]
				or (candidate_origin == origin[neighbor]
				and (prev[neighbor] < 0 or city_id < prev[neighbor])))
			)
			if improves or tie_improves:
				dist[neighbor] = candidate
				prev[neighbor] = city_id
				origin[neighbor] = candidate_origin
				_heap_push(heap, {
					"city": neighbor,
					"cost": candidate,
					"origin": candidate_origin,
				})
	return {"dist": dist, "prev": prev, "origin": origin}


static func _edge_transport_cost(edge: Edge, operational: bool) -> float:
	var capacity := edge.max_manpower
	if not operational and capacity <= 0:
		capacity = maxi(edge.base_max_manpower, MATCHED_LOW_CAPACITY)
	capacity = maxi(capacity, 1)
	var kind_factor := 1.0
	match edge.kind:
		EDGE_KIND_LANDING:
			kind_factor = 1.10
		EDGE_KIND_RIVER:
			kind_factor = 0.72
		EDGE_KIND_SEA:
			kind_factor = 0.62
		_:
			kind_factor = 1.0
	var capacity_factor := sqrt(
		float(MATCHED_STANDARD_CAPACITY) / float(capacity)
	)
	capacity_factor = clampf(capacity_factor, 0.60, 1.60)
	return (
		float(maxi(edge.distance, 1))
		* maxf(edge.travel_time_multiplier, 0.05)
		* kind_factor
		* capacity_factor
		* (1.0 + clampf(edge.danger, 0.0, 1.0) * 0.50)
		+ maxf(edge.supply_loss_multiplier, 0.0) * 0.10
	)


static func _edge_transport_cost_units(edge: Edge, operational: bool) -> int:
	return maxi(
		int(round(_edge_transport_cost(edge, operational) * float(COST_SCALE))),
		1
	)


static func _heap_entry_less(a: Dictionary, b: Dictionary) -> bool:
	var cost_a := int(a["cost"])
	var cost_b := int(b["cost"])
	if cost_a != cost_b:
		return cost_a < cost_b
	if int(a["origin"]) != int(b["origin"]):
		return int(a["origin"]) < int(b["origin"])
	return int(a["city"]) < int(b["city"])


static func _heap_push(heap: Array[Dictionary], entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := int((index - 1) / 2)
		if not _heap_entry_less(heap[index], heap[parent]):
			break
		var swap: Dictionary = heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = tail
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := left
		if right < heap.size() and _heap_entry_less(heap[right], heap[left]):
			child = right
		if not _heap_entry_less(heap[child], heap[index]):
			break
		var swap: Dictionary = heap[index]
		heap[index] = heap[child]
		heap[child] = swap
		index = child
	return result


static func _reconstruct_path(
	prev: PackedInt32Array, start: int, destination: int
) -> Array[int]:
	var result: Array[int] = []
	if start < 0 or destination < 0 or destination >= prev.size():
		return result
	if start == destination:
		result.append(start)
		return result
	if prev[destination] < 0:
		return result
	var current := destination
	var guard := 0
	while current != start and guard <= prev.size():
		result.push_front(current)
		current = prev[current]
		if current < 0:
			return [] as Array[int]
		guard += 1
	if current != start:
		return [] as Array[int]
	result.push_front(start)
	return result


static func _first_obstruction(
	state: GameState,
	graph: Dictionary,
	preferred_path: Array[int],
	allowed: PackedByteArray,
	besieged: Dictionary,
	blocked_edges: Dictionary
) -> Dictionary:
	for city_id in preferred_path:
		if besieged.has(city_id):
			return {
				"reason": "siege", "city": city_id, "edge_key": -1,
			}
		if city_id >= allowed.size() or allowed[city_id] == 0:
			return {
				"reason": "hostile_territory",
				"city": city_id, "edge_key": -1,
			}
	var edge_lookup: Dictionary = graph["edge_lookup"]
	for index in range(preferred_path.size() - 1):
		var edge_key := _edge_key(
			preferred_path[index], preferred_path[index + 1]
		)
		var edge: Edge = edge_lookup.get(edge_key, null)
		if edge == null or edge.max_manpower <= 0:
			return {
				"reason": "capacity", "city": -1,
				"edge_key": edge_key,
			}
		if blocked_edges.has(edge_key):
			return {
				"reason": "enemy_occupied_edge", "city": -1,
				"edge_key": edge_key,
			}
	return {"reason": "", "city": -1, "edge_key": -1}


static func _path_details(
	state: GameState,
	graph: Dictionary,
	path: Array[int],
	status: int = RouteStatus.ACTIVE
) -> Dictionary:
	var edge_keys: Array[int] = []
	var bottleneck := 0x7fffffff
	var uses_water := false
	var dock_count := 0
	for city_id in path:
		if (
			city_id >= 0 and city_id < state.cities.size()
			and state.cities[city_id].is_dock
		):
			dock_count += 1
	var edge_lookup: Dictionary = graph["edge_lookup"]
	for index in range(path.size() - 1):
		var key := _edge_key(path[index], path[index + 1])
		edge_keys.append(key)
		var edge: Edge = edge_lookup.get(key, null)
		if edge == null:
			bottleneck = 0
			continue
		var capacity := maxi(edge.max_manpower, 0)
		if status == RouteStatus.BLOCKED and capacity <= 0:
			capacity = maxi(edge.base_max_manpower, MATCHED_LOW_CAPACITY)
		bottleneck = mini(bottleneck, capacity)
		uses_water = uses_water or edge.kind in [EDGE_KIND_RIVER, EDGE_KIND_SEA]
	if edge_keys.is_empty():
		bottleneck = 0
	return {
		"edge_keys": edge_keys,
		"bottleneck": bottleneck,
		"uses_water": uses_water,
		"dock_count": dock_count,
	}


static func _quantize_cost(value: float) -> float:
	return float(round(value * 1000.0)) / 1000.0


static func _sortable_cost(value: float) -> float:
	return value if value >= 0.0 else 1000000000.0


static func _sort_units(value: float) -> int:
	if not is_finite(value):
		return INF_COST_UNITS
	return int(round(value * SORT_SCALE))


static func _international_candidate_value(
	state: GameState,
	source: int,
	destination: int,
	transport_cost: float,
	policy_a: int,
	policy_b: int
) -> float:
	if (
		source < 0 or destination < 0
		or source >= state.cities.size() or destination >= state.cities.size()
	):
		return 0.0
	var value := (
		_hub_score(state.cities[source], policy_a)
		+ _hub_score(state.cities[destination], policy_b)
	)
	if transport_cost >= 0.0:
		value /= 1.0 + transport_cost * 0.05
	return value


static func _apply_trade_taxes(
	state: GameState,
	routes: Array[Dictionary],
	policies: Array[int],
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int]
) -> void:
	for route_index in range(routes.size()):
		var route: Dictionary = routes[route_index]
		if int(route["status"]) == RouteStatus.BLOCKED:
			continue
		var eligible: Array[int] = []
		for city_id in route["city_path"] as Array[int]:
			if (
				city_id >= 0 and city_id < state.cities.size()
				and not state.cities[city_id].is_dock
				and not eligible.has(city_id)
			):
				eligible.append(city_id)
		if eligible.is_empty():
			continue
		var tax := _route_tax_gold(state, route, policies, eligible.size())
		var allocation := _allocate_route_tax(state, route, eligible, tax)
		var gold_a := 0
		var gold_b := 0
		var transit_gold := 0
		for city_id in eligible:
			var bonus := int(allocation.get(city_id, 0))
			city_gold_bonus[city_id] += bonus
			var owner := state.cities[city_id].owner_nation
			if owner >= 0 and owner < nation_trade_gold.size():
				nation_trade_gold[owner] += bonus
				nation_trade_tax[owner] += bonus
			if owner == int(route["nation_a"]):
				gold_a += bonus
			elif owner == int(route["nation_b"]):
				gold_b += bonus
			else:
				transit_gold += bonus
		if not bool(route["international"]):
			gold_b = 0
		route["gold"] = tax
		route["gold_tax"] = tax
		route["gold_a"] = gold_a
		route["gold_b"] = gold_b
		route["gold_to_a"] = gold_a
		route["gold_to_b"] = gold_b
		route["transit_gold"] = transit_gold
		route["city_gold_bonus"] = allocation
		routes[route_index] = route


static func _route_tax_gold(
	state: GameState,
	route: Dictionary,
	policies: Array[int],
	eligible_city_count: int
) -> int:
	var source := int(route["source"])
	var destination := int(route["destination"])
	var endpoint_gold := 0
	var endpoint_food := 0
	for city_id in [source, destination]:
		if city_id < 0 or city_id >= state.cities.size():
			continue
		endpoint_gold += maxi(state.cities[city_id].gold_per_month, 0)
		endpoint_food += maxi(state.cities[city_id].food_per_half_year, 0)
	var commerce := (
		2.0 + float(endpoint_gold) * 0.50 + float(endpoint_food) / 600.0
	)
	var bottleneck := maxi(int(route["bottleneck"]), 1)
	var capacity_factor := clampf(
		sqrt(float(bottleneck) / float(TRADE_CAPACITY_UNIT)), 0.65, 2.25
	)
	var cost := maxf(float(route["transport_cost"]), 0.0)
	var distance_factor := 1.0 / (1.0 + cost / 18.0)
	var nation_a := int(route["nation_a"])
	var nation_b := int(route["nation_b"])
	var policy_factor := _gold_policy_factor(policies[nation_a])
	var ruler_factor := _ruler_trade_multiplier(
		state.nations[nation_a]
	)
	if nation_b != nation_a:
		policy_factor = (
			policy_factor + _gold_policy_factor(policies[nation_b])
		) * 0.5
		ruler_factor = (
			ruler_factor + _ruler_trade_multiplier(state.nations[nation_b])
		) * 0.5
	var route_factor := 1.45 if bool(route["international"]) else 1.0
	if bool(route["uses_water"]):
		route_factor *= 1.12
	var raw := int(round(
		commerce * capacity_factor * distance_factor
		* policy_factor * ruler_factor * route_factor
	))
	return maxi(mini(raw, MAX_ROUTE_GOLD), eligible_city_count)


static func _gold_policy_factor(policy: int) -> float:
	match policy:
		Policy.GOLD:
			return 1.35
		Policy.FOOD:
			return 0.85
		Policy.ISOLATION:
			return 0.80
		_:
			return 1.0


static func _ruler_trade_multiplier(nation: Nation) -> float:
	return clampf(RulerProfile.trade_multiplier(nation), 0.25, 4.0)


static func _allocate_route_tax(
	state: GameState,
	route: Dictionary,
	city_ids: Array[int],
	total: int
) -> Dictionary:
	var result := {}
	if city_ids.is_empty() or total <= 0:
		return result
	# 每个沿线非码头城市至少得到 1，余量按枢纽/端点权重最大余数分配。
	for city_id in city_ids:
		result[city_id] = 1
	var remaining := maxi(total - city_ids.size(), 0)
	if remaining <= 0:
		return result
	var weights: Array[int] = []
	var total_weight := 0
	for city_id in city_ids:
		var city := state.cities[city_id]
		var weight := 1
		if city_id in [int(route["source"]), int(route["destination"])]:
			weight += 1
		if city.is_port_market:
			weight += 1
		if city.is_crossroads:
			weight += 1
		weights.append(weight)
		total_weight += weight
	var remainders: Array[Dictionary] = []
	var distributed := 0
	for index in range(city_ids.size()):
		var numerator := remaining * weights[index]
		var share := int(numerator / total_weight)
		result[city_ids[index]] = int(result[city_ids[index]]) + share
		distributed += share
		remainders.append({
			"city": city_ids[index],
			"remainder": numerator % total_weight,
		})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["remainder"]) != int(b["remainder"]):
			return int(a["remainder"]) > int(b["remainder"])
		return int(a["city"]) < int(b["city"])
	)
	for index in range(remaining - distributed):
		var city_id := int(remainders[index]["city"])
		result[city_id] = int(result[city_id]) + 1
	return result


static func _plan_food_transfers(
	state: GameState,
	routes: Array[Dictionary],
	policies: Array[int],
	nation_trade_gold: Array[int],
	nation_food_import: Array[int],
	nation_food_export: Array[int],
	nation_food_cost: Array[int],
	nation_food_sale_income: Array[int]
) -> void:
	var nation_count := state.nations.size()
	var stock := _zero_int_array(nation_count)
	var configured_warehouse_count := _zero_int_array(nation_count)
	var accessible_warehouse_count := _zero_int_array(nation_count)
	var besieged := state.besieged_city_ids()
	for city in state.cities:
		if (
			city.has_warehouse and city.owner_nation >= 0
			and city.owner_nation < nation_count
		):
			configured_warehouse_count[city.owner_nation] += 1
			if besieged.has(city.id):
				continue
			stock[city.owner_nation] += maxi(city.food_storage, 0)
			accessible_warehouse_count[city.owner_nation] += 1
	# 宗藩共享粮仓只在池持有者名下存储。按每个成员的 holder 映射到同一
	# 计划库存，避免藩王被误判为零库存进口国；池内转移不是国际贸易。
	var pool_holder := _zero_int_array(nation_count)
	for nation in state.nations:
		pool_holder[nation.id] = state.food_pool_holder(nation.id)
	var pooled_stock := _zero_int_array(nation_count)
	var pooled_configured := _zero_int_array(nation_count)
	var pooled_accessible := _zero_int_array(nation_count)
	for nation_id in range(nation_count):
		var holder := pool_holder[nation_id]
		if holder < 0 or holder >= nation_count:
			holder = nation_id
		pool_holder[nation_id] = holder
		pooled_stock[holder] += stock[nation_id]
		pooled_configured[holder] += configured_warehouse_count[nation_id]
		pooled_accessible[holder] += accessible_warehouse_count[nation_id]
	stock = pooled_stock
	configured_warehouse_count = pooled_configured
	accessible_warehouse_count = pooled_accessible
	# Old/minimal fixtures sometimes only populate Nation.granary_food. It is a
	# fallback only when no valid warehouse exists, never a second stock source.
	for nation in state.nations:
		if (
			configured_warehouse_count[nation.id] == 0
			and pool_holder[nation.id] == nation.id
		):
			stock[nation.id] = maxi(nation.granary_food, 0)
			# Compatibility for lightweight fixtures without explicit warehouses.
			accessible_warehouse_count[nation.id] = 1

	# last_food_demand / food_demand_ema are produced by Simulation's real
	# supply settlement and already include route loss plus ruler consumption.
	# Before those snapshots exist, use the same per-army base rounding and the
	# exact same ruler multiplier clamp; route loss is conservatively 1.0 here.
	var projected_minimum_demand := _zero_int_array(nation_count)
	for army in state.armies:
		if (
			army.size > 0 and army.owner_nation >= 0
			and army.owner_nation < nation_count
		):
			projected_minimum_demand[army.owner_nation] += (
				_projected_army_monthly_food_demand(
					army, state.nations[army.owner_nation]
				)
			)
	var demand := _zero_int_array(nation_count)
	for nation in state.nations:
		var nation_id := nation.id
		demand[nation_id] = _nation_monthly_food_demand(
			nation, projected_minimum_demand[nation_id]
		)
		if nation.alive and demand[nation_id] <= 0:
			demand[nation_id] = 1
	var pool_reserve := _zero_int_array(nation_count)
	for nation in state.nations:
		var holder := pool_holder[nation.id]
		if holder < 0 or holder >= nation_count:
			holder = nation.id
		pool_reserve[holder] += (
			demand[nation.id]
			* _food_reserve_months(policies[nation.id], nation)
		)
	var pool_export_remaining := _zero_int_array(nation_count)
	var pool_import_remaining := _zero_int_array(nation_count)
	for holder in range(nation_count):
		if accessible_warehouse_count[holder] <= 0:
			continue
		pool_export_remaining[holder] = maxi(
			stock[holder] - pool_reserve[holder], 0
		)
		pool_import_remaining[holder] = maxi(
			pool_reserve[holder] - stock[holder], 0
		)

	var route_order: Array[int] = []
	for index in range(routes.size()):
		if bool(routes[index]["international"]):
			route_order.append(index)
	route_order.sort_custom(func(a: int, b: int) -> bool:
		var route_a: Dictionary = routes[a]
		var route_b: Dictionary = routes[b]
		if int(route_a["status"]) != int(route_b["status"]):
			return int(route_a["status"]) < int(route_b["status"])
		var cost_a := _sort_units(_sortable_cost(
			float(route_a["transport_cost"])
		))
		var cost_b := _sort_units(_sortable_cost(
			float(route_b["transport_cost"])
		))
		if cost_a != cost_b:
			return cost_a < cost_b
		return int(route_a["id"]) < int(route_b["id"])
	)

	for route_index in route_order:
		var route: Dictionary = routes[route_index]
		if int(route["status"]) == RouteStatus.BLOCKED:
			continue
		var nation_a := int(route["nation_a"])
		var nation_b := int(route["nation_b"])
		var holder_a := pool_holder[nation_a]
		var holder_b := pool_holder[nation_b]
		if holder_a == holder_b:
			continue
		var exporter := -1
		var importer := -1
		var exporter_holder := -1
		var importer_holder := -1
		if (
			pool_export_remaining[holder_a] > 0
			and pool_import_remaining[holder_b] > 0
		):
			exporter = nation_a
			importer = nation_b
			exporter_holder = holder_a
			importer_holder = holder_b
		elif (
			pool_export_remaining[holder_b] > 0
			and pool_import_remaining[holder_a] > 0
		):
			exporter = nation_b
			importer = nation_a
			exporter_holder = holder_b
			importer_holder = holder_a
		if exporter < 0:
			continue
		var capacity := _route_food_capacity(route, policies[exporter], policies[importer])
		var price_per_batch := _food_price_per_batch(route)
		var available_gold := maxi(
			state.nations[importer].treasury_gold - nation_food_cost[importer], 0
		)
		var affordable := (
			int(available_gold / price_per_batch) * FOOD_UNITS_PER_GOLD
			if price_per_batch > 0 else 0
		)
		var amount := mini(
			capacity,
			mini(
				pool_export_remaining[exporter_holder],
				pool_import_remaining[importer_holder]
			)
		)
		amount = mini(amount, affordable)
		if amount <= 0:
			continue
		var cost := int(ceil(
			float(amount) / float(FOOD_UNITS_PER_GOLD)
		)) * price_per_batch
		if cost > available_gold:
			continue
		pool_export_remaining[exporter_holder] -= amount
		pool_import_remaining[importer_holder] -= amount
		nation_food_export[exporter] += amount
		nation_food_import[importer] += amount
		nation_food_cost[importer] += cost
		nation_food_sale_income[exporter] += cost
		# nation_trade_gold is the net positive trade receipt exposed to the
		# economy: generated route tax plus conserved food-sale income.
		nation_trade_gold[exporter] += cost
		route["food"] = amount
		route["food_transfer"] = amount
		route["food_exporter"] = exporter
		route["food_importer"] = importer
		route["food_source_city"] = _food_warehouse_city(
			state, exporter_holder, besieged
		)
		route["food_destination_city"] = _food_warehouse_city(
			state, importer_holder, besieged
		)
		route["food_cost"] = cost
		route["food_cost_gold"] = cost
		routes[route_index] = route


static func _food_warehouse_city(
	state: GameState, holder: int, besieged: Dictionary
) -> int:
	var best := -1
	for city in state.cities:
		if (
			city.owner_nation >= 0
			and city.owner_nation < state.nations.size()
			and state.food_pool_holder(city.owner_nation) == holder
			and city.has_warehouse
			and not besieged.has(city.id)
			and (best < 0 or city.id < best)
		):
			best = city.id
	return best


## Matches Simulation's base and ruler rounding:
## ceil(max(ceil(size * FOOD_PER_CAPITA), 1) * route_mult * ruler_mult).
## TradeNetwork has no supply-cache dependency, so its cold-start route_mult is
## exactly 1.0. Once daily settlement exists, last/EMA demand (used above) is
## authoritative and already carries the real route loss.
static func _projected_army_monthly_food_demand(
	army: Army, nation: Nation
) -> int:
	var base := maxi(
		int(ceil(float(army.size) * FOOD_PER_CAPITA_MONTH)),
		1
	)
	return maxi(int(ceil(
		float(base) * _ruler_food_consumption_multiplier(nation)
	)), 1)


static func _nation_monthly_food_demand(
	nation: Nation, projected_demand: int
) -> int:
	var settled_demand := maxi(
		maxi(nation.last_food_demand, 0),
		maxi(int(ceil(nation.food_demand_ema)), 0)
	)
	# Settled values originate in Simulation._finalize_food_demand and already
	# include real route loss plus the ruler multiplier. Never multiply again.
	return settled_demand if settled_demand > 0 else maxi(projected_demand, 0)


static func _ruler_food_consumption_multiplier(nation: Nation) -> float:
	# Keep the clamp identical to Simulation._ruler_food_consumption_multiplier.
	return maxf(RulerProfile.food_consumption_multiplier(nation), 0.1)


static func _food_reserve_months(policy: int, nation: Nation) -> int:
	var base := BALANCED_FOOD_RESERVE_MONTHS
	match policy:
		Policy.GOLD:
			base = GOLD_FOOD_RESERVE_MONTHS
		Policy.FOOD:
			base = FOOD_POLICY_RESERVE_MONTHS
		Policy.ISOLATION:
			base = ISOLATION_FOOD_RESERVE_MONTHS
	return maxi(base + RulerProfile.reserve_months_bonus(nation), 0)


static func _route_food_capacity(
	route: Dictionary, exporter_policy: int, importer_policy: int
) -> int:
	var bottleneck := maxi(int(route["bottleneck"]), 0)
	if bottleneck <= 0:
		return 0
	var capacity := float(bottleneck) / float(FOOD_CAPACITY_DIVISOR)
	var cost := maxf(float(route["transport_cost"]), 0.0)
	capacity /= 1.0 + cost / 24.0
	if bool(route["uses_water"]):
		capacity *= 1.20
	if exporter_policy == Policy.GOLD:
		capacity *= 1.15
	elif exporter_policy == Policy.FOOD:
		capacity *= 0.85
	if importer_policy == Policy.FOOD:
		capacity *= 1.20
	elif importer_policy == Policy.GOLD:
		capacity *= 0.85
	return maxi(int(floor(capacity)), 1)


static func _food_price_per_batch(route: Dictionary) -> int:
	var cost := maxf(float(route["transport_cost"]), 0.0)
	return maxi(1, 1 + int(floor(cost / 20.0)))


static func _result_signature(
	routes: Array[Dictionary],
	city_gold_bonus: Array[int],
	nation_trade_gold: Array[int],
	nation_trade_tax: Array[int],
	nation_food_import: Array[int],
	nation_food_export: Array[int],
	nation_food_cost: Array[int],
	nation_food_sale_income: Array[int],
	policies: Array[int]
) -> int:
	var signature := 17
	for value in policies:
		signature = _signature_step(signature, value)
	for route in routes:
		for key in [
			"id", "nation_a", "nation_b", "source", "destination",
			"status", "bottleneck", "blocked_city",
			"blocked_edge_key", "gold", "food", "food_exporter",
			"food_importer", "food_cost", "dock_count",
			"food_source_city", "food_destination_city",
			"gold_to_a", "gold_to_b",
		]:
			signature = _signature_step(signature, int(route[key]))
		signature = _signature_step(
			signature, int(round(float(route["transport_cost"]) * 1000.0))
		)
		signature = _signature_step(
			signature,
			int(round(float(route["preferred_transport_cost"]) * 1000.0))
		)
		signature = _signature_step(
			signature, 1 if bool(route["international"]) else 0
		)
		signature = _signature_step(
			signature, 1 if bool(route["uses_water"]) else 0
		)
		for city_id in route["city_path"] as Array[int]:
			signature = _signature_step(signature, city_id)
		signature = _signature_step(signature, -7)
		for city_id in route["preferred_city_path"] as Array[int]:
			signature = _signature_step(signature, city_id)
		signature = _signature_step(signature, -13)
		for edge_key in route["edge_keys"] as Array[int]:
			signature = _signature_step(signature, edge_key & 0x7fffffff)
			signature = _signature_step(signature, edge_key >> 32)
		signature = _signature_step(signature, -17)
		for key in ["gold_a", "gold_b", "transit_gold"]:
			signature = _signature_step(signature, int(route[key]))
		signature = _signature_string(
			signature, str(route["blocked_reason"])
		)
		var bonus: Dictionary = route["city_gold_bonus"]
		var bonus_keys := bonus.keys()
		bonus_keys.sort()
		for city_id in bonus_keys:
			signature = _signature_step(signature, int(city_id))
			signature = _signature_step(signature, int(bonus[city_id]))
		signature = _signature_step(signature, -19)
	for values in [
		city_gold_bonus, nation_trade_gold, nation_trade_tax,
		nation_food_import,
		nation_food_export, nation_food_cost, nation_food_sale_income,
	]:
		for value in values:
			signature = _signature_step(signature, int(value))
		signature = _signature_step(signature, -11)
	return signature


static func _signature_step(current: int, value: int) -> int:
	# current 始终限制在 31 位，乘法不会接近 int64 溢出。
	return int((current * 65599 + value + 1013904223) & 0x7fffffff)


static func _signature_string(current: int, value: String) -> int:
	var result := _signature_step(current, value.length())
	for index in range(value.length()):
		result = _signature_step(result, value.unicode_at(index))
	return result
