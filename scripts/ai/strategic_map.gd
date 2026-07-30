class_name StrategicMapSnapshot
extends RefCounted
## 国家级战略地图。所有字段均为派生缓存，不写回 GameState。

var nation_id: int
var ownership_revision: int
var city_value: Dictionary = {}            ## city_id -> float
var edge_value: Dictionary = {}            ## normalized edge key -> float
var bridge_impact: Dictionary = {}         ## edge key -> 被切断友城价值
var articulation_impact: Dictionary = {}   ## city_id -> 被切断友城价值
var corridor_flow: Dictionary = {}         ## edge key -> 粮仓到前线的路径计数
var frontier_edges: Array[Edge] = []
var frontier_cities: Array[int] = []
var frontier_enemy_cities: Array[int] = []
var priority_enemy_cities: Array[int] = []

var _state: GameState
var _disc: Dictionary = {}
var _low: Dictionary = {}
var _subtree_value: Dictionary = {}
var _time: int = 0
var _total_friendly_value: float = 0.0


static func build(view: AiWorldView) -> StrategicMapSnapshot:
	var snapshot := StrategicMapSnapshot.new()
	snapshot.nation_id = view.nation_id
	snapshot.ownership_revision = view.state.ownership_revision
	snapshot._state = view.state
	snapshot._compute_city_values()
	snapshot._find_frontier()
	snapshot._compute_connectivity()
	snapshot._compute_supply_corridors(view)
	snapshot._finalize_edge_values()
	snapshot._select_priority_targets(view)
	return snapshot


func _compute_city_values() -> void:
	var max_gold := 1
	var max_food := 1
	for city in _state.cities:
		max_gold = maxi(max_gold, city.gold_per_month)
		max_food = maxi(max_food, city.food_per_half_year)
	for city in _state.cities:
		var value := (
			float(city.gold_per_month) / float(max_gold)
			+ float(city.food_per_half_year) / float(max_food)
			+ float(city.defense) / 30.0 * 0.25
		)
		if city.is_capital:
			value += 5.0
		if city.has_warehouse:
			value += 3.0 + minf(float(city.food_storage) / 1000.0, 2.0)
		city_value[city.id] = value
		if city.owner_nation == nation_id:
			_total_friendly_value += value


func _find_frontier() -> void:
	var frontier_seen := {}
	var enemy_seen := {}
	for edge in _state.edges:
		if edge.max_throughput <= 0:
			continue
		var owner_a := _state.cities[edge.city_a].owner_nation
		var owner_b := _state.cities[edge.city_b].owner_nation
		if owner_a == owner_b:
			continue
		if owner_a != nation_id and owner_b != nation_id:
			continue
		frontier_edges.append(edge)
		var friendly_id := edge.city_a if owner_a == nation_id else edge.city_b
		var enemy_id := edge.city_b if owner_a == nation_id else edge.city_a
		if not frontier_seen.has(friendly_id):
			frontier_seen[friendly_id] = true
			frontier_cities.append(friendly_id)
		if not enemy_seen.has(enemy_id):
			enemy_seen[enemy_id] = true
			frontier_enemy_cities.append(enemy_id)
	frontier_edges.sort_custom(func(a: Edge, b: Edge) -> bool:
		return _edge_key(a.city_a, a.city_b) < _edge_key(b.city_a, b.city_b)
	)
	frontier_cities.sort()
	frontier_enemy_cities.sort()


func _compute_connectivity() -> void:
	_disc.clear()
	_low.clear()
	_subtree_value.clear()
	_time = 0
	var roots: Array[int] = []
	var capital := _state.nations[nation_id].capital_city_id
	if capital >= 0 and _state.cities[capital].owner_nation == nation_id:
		roots.append(capital)
	for city in _state.cities:
		if city.owner_nation == nation_id and city.id != capital:
			roots.append(city.id)
	for root in roots:
		if _disc.has(root):
			continue
		_dfs_connectivity_iterative(root)
	for city_id in articulation_impact.keys():
		city_value[city_id] = (
			float(city_value[city_id])
			+ 2.0 * float(articulation_impact[city_id]) / maxf(_total_friendly_value, 0.001)
		)


func _dfs_connectivity_iterative(root: int) -> void:
	var parent := {root: -1}
	var child_count := {root: 0}
	_discover_connectivity_node(root)
	var stack: Array[Dictionary] = [{
		"city": root,
		"index": 0,
		"neighbors": _friendly_neighbors(root),
	}]
	while not stack.is_empty():
		var frame: Dictionary = stack[stack.size() - 1]
		var city_id: int = frame["city"]
		var neighbors: Array[int] = frame["neighbors"]
		var index: int = frame["index"]
		if index < neighbors.size():
			var neighbor := neighbors[index]
			frame["index"] = index + 1
			if neighbor == int(parent[city_id]):
				continue
			if not _disc.has(neighbor):
				parent[neighbor] = city_id
				child_count[city_id] = int(child_count.get(city_id, 0)) + 1
				child_count[neighbor] = 0
				_discover_connectivity_node(neighbor)
				stack.append({
					"city": neighbor,
					"index": 0,
					"neighbors": _friendly_neighbors(neighbor),
				})
			else:
				_low[city_id] = mini(int(_low[city_id]), int(_disc[neighbor]))
			continue

		stack.pop_back()
		var parent_id: int = parent[city_id]
		if parent_id == -1:
			if int(child_count[city_id]) > 1:
				articulation_impact[city_id] = (
					float(_subtree_value[city_id])
					- float(city_value.get(city_id, 0.0))
				)
			continue
		_subtree_value[parent_id] = (
			float(_subtree_value[parent_id]) + float(_subtree_value[city_id])
		)
		_low[parent_id] = mini(int(_low[parent_id]), int(_low[city_id]))
		if int(_low[city_id]) > int(_disc[parent_id]):
			bridge_impact[_edge_key(parent_id, city_id)] = float(_subtree_value[city_id])
		if int(parent[parent_id]) != -1 and int(_low[city_id]) >= int(_disc[parent_id]):
			articulation_impact[parent_id] = (
				float(articulation_impact.get(parent_id, 0.0))
				+ float(_subtree_value[city_id])
			)


func _discover_connectivity_node(city_id: int) -> void:
	_time += 1
	_disc[city_id] = _time
	_low[city_id] = _time
	_subtree_value[city_id] = float(city_value.get(city_id, 0.0))


func _friendly_neighbors(city_id: int) -> Array[int]:
	var result: Array[int] = []
	for neighbor in _state.neighbors(city_id):
		if _state.cities[neighbor].owner_nation != nation_id:
			continue
		var edge := _state.edge_of(city_id, neighbor)
		if edge == null or edge.max_throughput <= 0:
			continue
		result.append(neighbor)
	result.sort()
	return result


func _compute_supply_corridors(view: AiWorldView) -> void:
	if frontier_cities.is_empty():
		return
	for warehouse in view.warehouses:
		var field := Pathfinding.dijkstra_field(_state, warehouse.id, nation_id, false, true)
		var prev: Dictionary = field["prev"]
		for frontier_id in frontier_cities:
			var path := Pathfinding.reconstruct(prev, warehouse.id, frontier_id)
			var from_id := warehouse.id
			for to_id in path:
				var key := _edge_key(from_id, to_id)
				corridor_flow[key] = float(corridor_flow.get(key, 0.0)) + 1.0
				from_id = to_id


func _finalize_edge_values() -> void:
	var max_flow := 1.0
	for value in corridor_flow.values():
		max_flow = maxf(max_flow, float(value))
	for edge in _state.edges:
		var key := _edge_key(edge.city_a, edge.city_b)
		var owner_a := _state.cities[edge.city_a].owner_nation
		var owner_b := _state.cities[edge.city_b].owner_nation
		var value := edge.danger
		if owner_a == nation_id:
			value += 0.15 * float(city_value.get(edge.city_a, 0.0))
		if owner_b == nation_id:
			value += 0.15 * float(city_value.get(edge.city_b, 0.0))
		value += 3.0 * float(bridge_impact.get(key, 0.0)) / maxf(_total_friendly_value, 0.001)
		value += 2.0 * float(corridor_flow.get(key, 0.0)) / max_flow
		value += 0.75 * float(maxi(edge.max_throughput - 1, 0))
		if owner_a != owner_b and (owner_a == nation_id or owner_b == nation_id):
			value += 1.0 + edge.danger * 2.0
		edge_value[key] = value


func _select_priority_targets(view: AiWorldView) -> void:
	var scored: Array = []
	for city_id in frontier_enemy_cities:
		scored.append([float(city_value.get(city_id, 0.0)) + 2.0, city_id])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]) or (
			is_equal_approx(float(a[0]), float(b[0])) and int(a[1]) < int(b[1])
		)
	)
	for i in range(mini(scored.size(), 16)):
		priority_enemy_cities.append(int(scored[i][1]))


func value_of_city(city_id: int) -> float:
	return float(city_value.get(city_id, 0.0))


func value_of_edge(a: int, b: int) -> float:
	return float(edge_value.get(_edge_key(a, b), 0.0))


static func _edge_key(a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return lo * GameState.CITY_COUNT + hi
