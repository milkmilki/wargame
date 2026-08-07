class_name StrategicMapSnapshot
extends RefCounted
## 国家级战略地图。所有字段均为派生缓存，不写回 GameState。

var nation_id: int
var ownership_revision: int
var strategic_planning_enabled: bool
var city_value: Dictionary = {}            ## city_id -> float
var edge_value: Dictionary = {}            ## normalized edge key -> float
var bridge_impact: Dictionary = {}         ## edge key -> 被切断友城价值
var articulation_impact: Dictionary = {}   ## city_id -> 被切断友城价值
var corridor_flow: Dictionary = {}         ## edge key -> 粮仓到前线的路径计数
var supply_corridor_importance: Dictionary = {} ## city_id -> 0~1 粮道节点重要度
var critical_supply_cities: Array[int] = []
var frontier_edges: Array[Edge] = []
var frontier_cities: Array[int] = []
var frontier_enemy_cities: Array[int] = []
var potential_frontier_edges: Array[Edge] = []
var potential_frontier_cities: Array[int] = []
var potential_border_threat: Dictionary = {} ## friendly city_id -> float
var potential_edge_threat: Dictionary = {}   ## edge key -> dimensionless threat
var priority_enemy_cities: Array[int] = []
var offensive_value: Dictionary = {}       ## enemy city_id -> 两层占领后战略价值
var campaign_target: int = -1               ## 国家级主战役目标

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
	snapshot.strategic_planning_enabled = view.strategic_planning_enabled
	snapshot._state = view.state
	snapshot._compute_city_values()
	snapshot._find_frontier()
	snapshot._compute_connectivity()
	snapshot._compute_supply_corridors(view)
	snapshot._finalize_edge_values()
	snapshot._compute_offensive_values(view)
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
			+ float(city.fort_strength) / 30.0 * 0.25
		)
		if city.is_capital:
			value += 5.0
		if city.has_warehouse:
			value += 3.0 + minf(float(city.food_storage) / 1000.0, 2.0)
		if city.is_food_hub:
			value += 4.0
		if city.is_manpower_hub:
			value += 4.0
		city_value[city.id] = value
		if city.owner_nation == nation_id:
			_total_friendly_value += value


func _find_frontier() -> void:
	var frontier_seen := {}
	var enemy_seen := {}
	var neutral_cities_by_nation := {}
	var neutral_edges_by_nation := {}
	for edge in _state.edges:
		if edge.max_manpower <= 0:
			continue
		var owner_a := _state.cities[edge.city_a].owner_nation
		var owner_b := _state.cities[edge.city_b].owner_nation
		if owner_a == owner_b:
			continue
		if owner_a != nation_id and owner_b != nation_id:
			continue
		var friendly_id := edge.city_a if owner_a == nation_id else edge.city_b
		var other_id := edge.city_b if owner_a == nation_id else edge.city_a
		var other_nation := _state.cities[other_id].owner_nation
		if _state.is_enemy(nation_id, other_nation):
			frontier_edges.append(edge)
			if not frontier_seen.has(friendly_id):
				frontier_seen[friendly_id] = true
				frontier_cities.append(friendly_id)
			if not enemy_seen.has(other_id):
				enemy_seen[other_id] = true
				frontier_enemy_cities.append(other_id)
		elif (
			_state.relation_between(nation_id, other_nation)
			== GameState.DiplomaticRelation.NEUTRAL
		):
			if not neutral_cities_by_nation.has(other_nation):
				neutral_cities_by_nation[other_nation] = {}
				neutral_edges_by_nation[other_nation] = []
			neutral_cities_by_nation[other_nation][friendly_id] = true
			neutral_edges_by_nation[other_nation].append(edge)
	var neutral_nations := neutral_cities_by_nation.keys()
	neutral_nations.sort_custom(func(a, b) -> bool:
		return EquivariantOrder.nation_less(
			_state,
			nation_id,
			int(a),
			int(b)
		)
	)
	var potential_seen := {}
	var diplomacy_evaluation_cache := {}
	for other_nation_value in neutral_nations:
		var other_nation := int(other_nation_value)
		var threat_score := DiplomacyAI.threat_from_nation(
			_state,
			nation_id,
			other_nation,
			diplomacy_evaluation_cache
		)
		if threat_score < 1.0:
			continue
		var border_city_ids: Array = neutral_cities_by_nation[other_nation].keys()
		EquivariantOrder.sort_city_ids(
			border_city_ids,
			_state,
			nation_id
		)
		var deployable_power := _army_power_of(other_nation)
		var per_city_power := (
			deployable_power
			/ float(maxi(border_city_ids.size(), 1))
			* clampf(threat_score / 2.0, 0.25, 1.0)
		)
		for city_id_value in border_city_ids:
			var city_id := int(city_id_value)
			var local_concentration := _neutral_border_concentration(
				other_nation,
				city_id
			)
			potential_border_threat[city_id] = (
				float(potential_border_threat.get(city_id, 0.0))
				+ maxf(per_city_power, local_concentration)
			)
			if not potential_seen.has(city_id):
				potential_seen[city_id] = true
				potential_frontier_cities.append(city_id)
		for edge in neutral_edges_by_nation[other_nation]:
			if not potential_frontier_edges.has(edge):
				potential_frontier_edges.append(edge)
			potential_edge_threat[_edge_key(edge.city_a, edge.city_b)] = threat_score
	EquivariantOrder.sort_edges(
		frontier_edges,
		_state,
		nation_id
	)
	EquivariantOrder.sort_edges(
		potential_frontier_edges,
		_state,
		nation_id
	)
	EquivariantOrder.sort_city_ids(frontier_cities, _state, nation_id)
	EquivariantOrder.sort_city_ids(
		frontier_enemy_cities,
		_state,
		nation_id
	)
	EquivariantOrder.sort_city_ids(
		potential_frontier_cities,
		_state,
		nation_id
	)


func _army_power_of(owner_nation: int) -> float:
	var total := 0.0
	for army in _state.armies:
		if army.owner_nation == owner_nation and army.size > 0:
			total += ArmyPower.effective(army)
	return total


func _neutral_border_concentration(
	other_nation: int,
	friendly_city: int
) -> float:
	var total := 0.0
	for neighbor in _state.neighbors(friendly_city):
		var edge := _state.edge_of(friendly_city, neighbor)
		if (
			edge == null
			or edge.max_manpower <= 0
			or _state.cities[neighbor].owner_nation != other_nation
		):
			continue
		for army in _state.armies:
			if army.owner_nation != other_nation or army.size <= 0:
				continue
			if (
				army.state in [Army.State.IDLE, Army.State.RECOVERING]
				and army.location_city == neighbor
			):
				total += ArmyPower.effective(army)
			elif (
				army.state == Army.State.HOLDING
				and (
					(army.move_from == neighbor and army.move_to == friendly_city)
					or (
						army.move_to == neighbor
						and army.move_from == friendly_city
					)
				)
			):
				total += ArmyPower.effective(army)
	return total


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
	EquivariantOrder.sort_city_ids(roots, _state, nation_id, capital)
	for root in roots:
		if _disc.has(root):
			continue
		_dfs_connectivity_iterative(root)
	var articulation_ids := articulation_impact.keys()
	EquivariantOrder.sort_city_ids(
		articulation_ids,
		_state,
		nation_id,
		capital
	)
	for city_id in articulation_ids:
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
		if edge == null or edge.max_manpower <= 0:
			continue
		result.append(neighbor)
	EquivariantOrder.sort_city_subset(
		result,
		_state,
		nation_id,
		city_id
	)
	return result


func _compute_supply_corridors(view: AiWorldView) -> void:
	var defended_cities: Array[int] = frontier_cities.duplicate()
	for city_id in potential_frontier_cities:
		if not defended_cities.has(city_id):
			defended_cities.append(city_id)
	EquivariantOrder.sort_city_ids(
		defended_cities,
		_state,
		nation_id
	)
	if defended_cities.is_empty():
		return
	for warehouse in view.warehouses:
		var field := Pathfinding.dijkstra_field(_state, warehouse.id, nation_id, false, true)
		var prev: Dictionary = field["prev"]
		for frontier_id in defended_cities:
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
	var max_bridge_impact := 0.001
	for value in bridge_impact.values():
		max_bridge_impact = maxf(max_bridge_impact, float(value))
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
		var capacity_units := (
			float(edge.max_manpower)
				/ float(Edge.STANDARD_MANPOWER)
		)
		value += 0.75 * maxf(capacity_units - 1.0, 0.0)
		if (
			_state.is_enemy(owner_a, owner_b)
			and (owner_a == nation_id or owner_b == nation_id)
		):
			value += 1.0 + edge.danger * 2.0
		if (
			edge.max_manpower > 0
			and edge.danger
				>= Combat.CHOKEPOINT_DANGER_ONSET
		):
			value += 4.0
		value += 2.0 * float(potential_edge_threat.get(key, 0.0))
		edge_value[key] = value
		var normalized_flow := (
			float(corridor_flow.get(key, 0.0)) / max_flow
		)
		if normalized_flow <= 0.0:
			continue
		var bridge_share := clampf(
			float(bridge_impact.get(key, 0.0)) / max_bridge_impact,
			0.0,
			1.0
		)
		# 只有粮流与桥梁属性同时成立才形成硬守备需求。
		# 非桥梁高流量道路仍保留 edge_value 加分，但不钉死常驻军。
		var importance := clampf(
			normalized_flow * bridge_share,
			0.0,
			1.0
		)
		for city_id in [edge.city_a, edge.city_b]:
			if _state.cities[city_id].owner_nation != nation_id:
				continue
			supply_corridor_importance[city_id] = maxf(
				float(supply_corridor_importance.get(city_id, 0.0)),
				importance
			)
	for city_id_value in supply_corridor_importance:
		var city_id := int(city_id_value)
		if float(supply_corridor_importance[city_id]) >= 0.50:
			critical_supply_cities.append(city_id)
	EquivariantOrder.sort_city_ids(
		critical_supply_cities,
		_state,
		nation_id
	)


func _compute_offensive_values(view: AiWorldView) -> void:
	for city_id in frontier_enemy_cities:
		var base := value_of_city(city_id)
		if not view.strategic_planning_enabled:
			offensive_value[city_id] = base
			continue
		var target_owner := _state.cities[city_id].owner_nation
		var friendly_links := 0
		var hostile_links := 0
		var gateway_value := 0.0
		for neighbor in _state.neighbors(city_id):
			var edge := _state.edge_of(city_id, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			var neighbor_owner := _state.cities[neighbor].owner_nation
			if neighbor_owner == nation_id:
				friendly_links += 1
			elif neighbor_owner == target_owner:
				hostile_links += 1
				if not frontier_enemy_cities.has(neighbor):
					gateway_value = maxf(gateway_value, value_of_city(neighbor))
		var defensive_gain := float(friendly_links - hostile_links)
		var exposure := maxi(hostile_links - friendly_links, 0)
		var gateway_bonus := 0.0
		if exposure <= 1:
			gateway_bonus = minf(gateway_value * 0.30, 1.5)
		var encirclement_value := DiplomacyAI.encirclement_value(
			_state,
			city_id,
			target_owner
		)
		offensive_value[city_id] = (
			base
			+ maxf(defensive_gain, 0.0) * 1.5
			- float(exposure) * 1.5
			+ gateway_bonus
			+ encirclement_value
		)


func _select_priority_targets(view: AiWorldView) -> void:
	var scored: Array = []
	var diplomatic_targets := {}
	for enemy_id in _state.wars_of(nation_id):
		var objective := _state.war_objective(nation_id, enemy_id)
		if (
			not objective.is_empty()
			and int(objective.get("attacker", -1)) == nation_id
		):
			diplomatic_targets[int(objective["city_id"])] = true
	for city_id in frontier_enemy_cities:
		scored.append([
			value_of_offense(city_id)
				+ 2.0
				+ (4.0 if diplomatic_targets.has(city_id) else 0.0),
			city_id,
		])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		if not is_equal_approx(float(a[0]), float(b[0])):
			return float(a[0]) > float(b[0])
		return EquivariantOrder.city_id_less(
			_state,
			nation_id,
			int(a[1]),
			int(b[1])
		)
	)
	for i in range(scored.size()):
		priority_enemy_cities.append(int(scored[i][1]))
	if view.strategic_planning_enabled and not scored.is_empty():
		campaign_target = int(scored[0][1])


func value_of_city(city_id: int) -> float:
	return float(city_value.get(city_id, 0.0))


func value_of_offense(city_id: int) -> float:
	return float(offensive_value.get(city_id, value_of_city(city_id)))


func value_of_edge(a: int, b: int) -> float:
	return float(edge_value.get(_edge_key(a, b), 0.0))


func potential_threat_at(city_id: int) -> float:
	return float(potential_border_threat.get(city_id, 0.0))


func potential_threat_of_edge(a: int, b: int) -> float:
	return float(potential_edge_threat.get(_edge_key(a, b), 0.0))


func supply_importance_at(city_id: int) -> float:
	return float(supply_corridor_importance.get(city_id, 0.0))


static func _edge_key(a: int, b: int) -> int:
	return GameState.edge_key(a, b)
