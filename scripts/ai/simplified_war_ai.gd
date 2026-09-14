class_name SimplifiedWarAI
extends RefCounted
## 只处理主战军团的战略层：编组、交战国公共首都走廊与军团行军命令。

const ROUTE_MERGE_HOPS: int = 2
const DEFENSIVE_EDGE_HOLD_BIAS_MIN: float = 1.35

static func group_strength(state: GameState, group: BattleGroup) -> int:
	var result := 0
	for army in state.battle_group_members(group.owner_nation, group.id):
		result += army.size
	return result


static func group_origin(state: GameState, group: BattleGroup) -> int:
	var members := state.battle_group_members(group.owner_nation, group.id)
	members.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	for army in members:
		if army.on_edge and army.move_to >= 0:
			return army.move_to if army.move_progress >= 0.5 else army.move_from
		if army.location_city >= 0:
			return army.location_city
	return -1


static func reconcile_groups(state: GameState, nation_id: int) -> void:
	if nation_id < 0 or nation_id >= state.nations.size():
		return
	var nation := state.nations[nation_id]
	var guard_group_ids := {}
	var field_groups: Array[BattleGroup] = []
	for group in nation.battle_groups:
		if group.role == BattleGroup.Role.CAPITAL_GUARD:
			guard_group_ids[group.id] = true
		else:
			field_groups.append(group)
	var main_armies: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and not guard_group_ids.has(army.battle_group_id)
			and (
				army.strategic_role == Army.StrategicRole.MAIN
				or army.battle_group_id >= 0
			)
		):
			main_armies.append(army)
	main_armies.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	var required := 0
	var planned_fill := 0
	for army in main_armies:
		if (
			required == 0
			or planned_fill + army.size > BattleGroup.MAX_MANPOWER
		):
			required += 1
			planned_fill = 0
		planned_fill += army.size
	nation.battle_groups.sort_custom(
		func(a: BattleGroup, b: BattleGroup) -> bool: return a.id < b.id
	)
	field_groups.sort_custom(
		func(a: BattleGroup, b: BattleGroup) -> bool: return a.id < b.id
	)
	while field_groups.size() < required:
		field_groups.append(state.create_battle_group(nation_id))
	while field_groups.size() > required:
		nation.battle_groups.erase(field_groups.pop_back())
	for army in main_armies:
		army.battle_group_id = -1
		army.strategic_role = Army.StrategicRole.MAIN
	var group_index := 0
	var filled := 0
	for army in main_armies:
		if group_index >= field_groups.size():
			break
		if filled > 0 and filled + army.size > BattleGroup.MAX_MANPOWER:
			group_index += 1
			filled = 0
		if group_index >= field_groups.size():
			break
		army.battle_group_id = field_groups[group_index].id
		army.clear_line_assignment()
		filled += army.size


static func route_to_city(
	state: GameState,
	group: BattleGroup,
	target_city: int
) -> Array[int]:
	var origin := group_origin(state, group)
	if (
		origin < 0
		or target_city < 0
		or target_city >= state.cities.size()
	):
		return [] as Array[int]
	if origin == target_city:
		return [origin] as Array[int]
	var target_nation := state.cities[target_city].owner_nation
	var suffix := Pathfinding.campaign_route(
		state, origin, target_city, group.owner_nation, target_nation
	)
	if suffix.is_empty():
		return [] as Array[int]
	var route: Array[int] = [origin]
	route.append_array(suffix)
	return route


static func shared_capital_route(
	state: GameState,
	nation_a: int,
	nation_b: int,
	edge_penalties: Dictionary = {}
) -> Array[int]:
	if (
		nation_a < 0 or nation_b < 0
		or nation_a >= state.nations.size()
		or nation_b >= state.nations.size()
		or nation_a == nation_b
	):
		return [] as Array[int]
	var canonical_a := mini(nation_a, nation_b)
	var canonical_b := maxi(nation_a, nation_b)
	var capital_a := state.nations[canonical_a].capital_city_id
	var capital_b := state.nations[canonical_b].capital_city_id
	if (
		capital_a < 0 or capital_b < 0
		or capital_a >= state.cities.size()
		or capital_b >= state.cities.size()
	):
		return [] as Array[int]
	var suffix := Pathfinding.campaign_route(
		state, capital_a, capital_b, canonical_a, canonical_b,
		edge_penalties
	)
	var canonical_route: Array[int] = []
	if not suffix.is_empty():
		canonical_route = [capital_a]
		canonical_route.append_array(suffix)
	else:
		suffix = Pathfinding.campaign_route(
			state, capital_b, capital_a, canonical_b, canonical_a,
			edge_penalties
		)
		if suffix.is_empty():
			return [] as Array[int]
		canonical_route = [capital_b]
		canonical_route.append_array(suffix)
		canonical_route.reverse()
	if nation_a == canonical_a:
		return canonical_route
	var reversed: Array[int] = canonical_route.duplicate()
	reversed.reverse()
	return reversed


static func build_war_corridors(state: GameState) -> Dictionary:
	var result := {}
	for nation_a in range(state.nations.size()):
		if not state.nations[nation_a].alive:
			continue
		for nation_b in range(nation_a + 1, state.nations.size()):
			if (
				not state.nations[nation_b].alive
				or not state.is_enemy(nation_a, nation_b)
			):
				continue
			var route := shared_capital_route(state, nation_a, nation_b)
			if route.is_empty():
				continue
			_set_corridor_pair(result, nation_a, nation_b, route)
	_merge_allied_corridors(state, result)
	return result


static func _corridor_key(from_nation: int, to_nation: int, lane: int) -> Variant:
	return (
		Vector3i(from_nation, to_nation, lane)
		if lane >= 0
		else Vector2i(from_nation, to_nation)
	)


static func _set_corridor_pair(
	corridors: Dictionary,
	from_nation: int,
	to_nation: int,
	forward: Array[int],
	lane: int = -1
) -> void:
	corridors[_corridor_key(from_nation, to_nation, lane)] = forward.duplicate()
	var reverse: Array[int] = forward.duplicate()
	reverse.reverse()
	corridors[_corridor_key(to_nation, from_nation, lane)] = reverse


static func _merge_allied_corridors(
	state: GameState,
	corridors: Dictionary,
	lane: int = -1
) -> void:
	for defender in state.nations:
		if not defender.alive:
			continue
		var attackers := state.wars_of(defender.id)
		attackers.sort_custom(func(a: int, b: int) -> bool:
			return EquivariantOrder.nation_less(
				state, defender.id, a, b
			)
		)
		for leader_index in range(attackers.size()):
			var leader_id := attackers[leader_index]
			var leader_key: Variant = _corridor_key(
				leader_id, defender.id, lane
			)
			if not corridors.has(leader_key):
				continue
			var leader_route: Array[int] = corridors[leader_key]
			var proximity := _route_proximity(
				state, leader_route, ROUTE_MERGE_HOPS
			)
			for follower_index in range(leader_index + 1, attackers.size()):
				var follower_id := attackers[follower_index]
				if not state.is_allied(leader_id, follower_id):
					continue
				var follower_key: Variant = _corridor_key(
					follower_id, defender.id, lane
				)
				if not corridors.has(follower_key):
					continue
				var follower_route: Array[int] = corridors[follower_key]
				var merge := _route_merge_candidate(
					state, leader_route, follower_route, proximity,
					follower_id, defender.id
				)
				if merge.is_empty():
					continue
				var leader_node_index := int(merge["leader_index"])
				var follower_node_index := int(merge["follower_index"])
				var joined: Array[int] = follower_route.slice(
					0, follower_node_index + 1
				)
				joined.append_array(merge["connector"] as Array[int])
				joined.append_array(leader_route.slice(leader_node_index + 1))
				joined = _remove_route_cycles(joined)
				if (
					joined.size() < 2
					or joined[0]
						!= state.nations[follower_id].capital_city_id
					or joined[-1] != defender.capital_city_id
				):
					continue
				_set_corridor_pair(
					corridors, follower_id, defender.id, joined, lane
				)


static func node_threats(state: GameState, defender_id: int) -> Dictionary:
	return all_node_threats(state).get(defender_id, {}) as Dictionary


static func all_node_threats(state: GameState) -> Dictionary:
	var result := {}
	for enemy in state.nations:
		if not enemy.alive:
			continue
		for group in enemy.battle_groups:
			if (
				group.posture != BattleGroup.Posture.ATTACK
				or group.target_nation < 0
				or not state.is_enemy(group.target_nation, enemy.id)
			):
				continue
			var defender_id := group.target_nation
			var border_node := _first_defender_node(
				state, defender_id, group.route
			)
			if border_node < 0:
				continue
			if not result.has(defender_id):
				result[defender_id] = {}
			var defender_threats: Dictionary = result[defender_id]
			defender_threats[border_node] = (
				int(defender_threats.get(border_node, 0))
				+ group_strength(state, group)
			)
	return result


static func plan_nation(
	state: GameState,
	nation_id: int,
	_incoming_threats: Variant = null,
	war_corridors: Dictionary = {}
) -> void:
	reconcile_groups(state, nation_id)
	var nation := state.nations[nation_id]
	var enemies := state.wars_of(nation_id)
	enemies.sort()
	for group in nation.battle_groups:
		if group.role != BattleGroup.Role.CAPITAL_GUARD:
			continue
		_set_group_order(
			state, group, BattleGroup.Posture.PEACE, -1,
			nation.capital_city_id
		)
	var preparation_groups := _plan_war_preparation(state, nation)
	if enemies.is_empty():
		for group in nation.battle_groups:
			if group.role == BattleGroup.Role.CAPITAL_GUARD:
				continue
			if preparation_groups.has(group.id):
				continue
			_set_group_order(
				state, group, BattleGroup.Posture.PEACE, -1,
				nation.capital_city_id
			)
		return
	var corridors := (
		war_corridors
		if not war_corridors.is_empty()
		else build_war_corridors(state)
	)
	var reachable_enemies: Array[int] = []
	for enemy_id in enemies:
		var corridor_key := Vector2i(nation_id, enemy_id)
		if not corridors.has(corridor_key):
			var route := shared_capital_route(state, nation_id, enemy_id)
			if not route.is_empty():
				_set_corridor_pair(
					corridors, nation_id, enemy_id, route
				)
		if (
			corridors.has(corridor_key)
			and not (corridors[corridor_key] as Array).is_empty()
		):
			reachable_enemies.append(enemy_id)
	if reachable_enemies.is_empty():
		for group in nation.battle_groups:
			if (
				group.role == BattleGroup.Role.CAPITAL_GUARD
				or preparation_groups.has(group.id)
			):
				continue
			_set_group_order(
				state, group, BattleGroup.Posture.PEACE, -1,
				nation.capital_city_id
			)
		return
	var field_groups: Array[BattleGroup] = []
	for group in nation.battle_groups:
		if (
			group.role == BattleGroup.Role.CAPITAL_GUARD
			or preparation_groups.has(group.id)
		):
			continue
		field_groups.append(group)
	field_groups.sort_custom(
		func(a: BattleGroup, b: BattleGroup) -> bool: return a.id < b.id
	)
	var targets := _threat_weighted_corridor_targets(
		state, nation_id, reachable_enemies, field_groups.size()
	)
	for group_index in range(field_groups.size()):
		var group := field_groups[group_index]
		var enemy_id := targets[group_index]
		var route: Array[int] = corridors[Vector2i(nation_id, enemy_id)]
		if _is_war_defender(state, nation_id, enemy_id):
			_set_defensive_group_order(state, group, enemy_id, route)
		else:
			_set_group_order(
				state, group, BattleGroup.Posture.ATTACK, enemy_id,
				state.nations[enemy_id].capital_city_id, route
			)


static func _threat_weighted_corridor_targets(
	state: GameState,
	nation_id: int,
	enemies: Array[int],
	group_count: int
) -> Array[int]:
	var result: Array[int] = []
	if enemies.is_empty() or group_count <= 0:
		return result
	var threat := {}
	var assigned := {}
	for enemy_id in enemies:
		threat[enemy_id] = _corridor_threat(state, nation_id, enemy_id)
		assigned[enemy_id] = 0
	while result.size() < group_count:
		var best_enemy := -1
		var best_score := -INF
		for enemy_id in enemies:
			var score := (
				float(threat[enemy_id])
				/ float(int(assigned[enemy_id]) + 1)
			)
			if score > best_score or (
				is_equal_approx(score, best_score)
				and (best_enemy < 0 or enemy_id < best_enemy)
			):
				best_enemy = enemy_id
				best_score = score
		result.append(best_enemy)
		assigned[best_enemy] = int(assigned[best_enemy]) + 1
	return result


static func _corridor_threat(
	state: GameState,
	nation_id: int,
	enemy_id: int
) -> int:
	var committed := 0
	var total_field := 0
	for group in state.nations[enemy_id].battle_groups:
		if group.role != BattleGroup.Role.FIELD:
			continue
		var strength := group_strength(state, group)
		total_field += strength
		if group.target_nation == nation_id:
			committed += strength
	if committed > 0:
		return committed
	return maxi(
		int(ceil(
			float(total_field)
			/ float(maxi(state.wars_of(enemy_id).size(), 1))
		)),
		1
	)


static func _is_war_defender(
	state: GameState,
	nation_id: int,
	enemy_id: int
) -> bool:
	var objective := state.war_objective(nation_id, enemy_id)
	return (
		not objective.is_empty()
		and int(objective.get("defender", -1)) == nation_id
	)


static func _set_defensive_group_order(
	state: GameState,
	group: BattleGroup,
	enemy_id: int,
	route: Array[int]
) -> void:
	var objective := _defensive_frontline_objective(
		state, group.owner_nation, route
	)
	var target_city := int(objective.get(
		"city_id", state.nations[group.owner_nation].capital_city_id
	))
	_set_group_order(
		state, group, BattleGroup.Posture.DEFEND, enemy_id,
		target_city, route
	)
	group.defense_edge_to = int(objective.get("edge_to", -1))


## 沿“己都 -> 敌都”走廊维护一个前线指针：优先收复遇到的第一座
## 己方法理失地；没有失地时，在最前沿己控城市或其朝敌道路驻防。
static func _defensive_frontline_objective(
	state: GameState,
	nation_id: int,
	route: Array[int]
) -> Dictionary:
	var forward_city := -1
	var forward_index := -1
	for route_index in range(route.size()):
		var city_id := route[route_index]
		var city := state.cities[city_id]
		if city.owner_nation == nation_id:
			forward_city = city_id
			forward_index = route_index
			continue
		if state.recognized_owner_of(city_id) == nation_id:
			return {"city_id": city_id, "edge_to": -1}
		break
	if forward_city < 0:
		return {}
	var edge_to := -1
	if forward_index + 1 < route.size():
		var next_city := route[forward_index + 1]
		var edge := state.edge_of(forward_city, next_city)
		if (
			edge != null
			and edge.allows_holding
			and Combat.terrain_hold_bias(
				edge.danger, Combat.HOLDING_TAU_DAYS
			) >= DEFENSIVE_EDGE_HOLD_BIAS_MIN
		):
			edge_to = next_city
	return {"city_id": forward_city, "edge_to": edge_to}


static func _plan_war_preparation(
	state: GameState,
	nation: Nation
) -> Dictionary:
	var assigned := {}
	var target_nation := nation.war_preparation_target_nation
	var objective_city := nation.war_preparation_objective_city
	if (
		target_nation < 0
		or target_nation >= state.nations.size()
		or objective_city < 0
		or objective_city >= state.cities.size()
		or state.cities[objective_city].owner_nation != target_nation
	):
		return assigned
	var staging := DiplomacyAI.staging_cities_for_objective(
		state, nation.id, objective_city
	)
	if staging.is_empty():
		return assigned
	var groups: Array[BattleGroup] = []
	for group in nation.battle_groups:
		if (
			group.role == BattleGroup.Role.CAPITAL_GUARD
			or group_strength(state, group) <= 0
		):
			continue
		groups.append(group)
	groups.sort_custom(func(a: BattleGroup, b: BattleGroup) -> bool:
		var strength_a := group_strength(state, a)
		var strength_b := group_strength(state, b)
		return strength_a > strength_b or (
			strength_a == strength_b and a.id < b.id
		)
	)
	var required_troops := maxi(
		DiplomacyAI.required_assault_troops(
			state, nation.id, objective_city
		),
		1
	)
	var assigned_troops := 0
	for group in groups:
		var best_city := -1
		var best_route: Array[int] = []
		for staging_city in staging:
			var candidate := route_to_city(state, group, staging_city)
			if candidate.is_empty():
				continue
			if (
				best_route.is_empty()
				or candidate.size() < best_route.size()
				or (
					candidate.size() == best_route.size()
					and (
						best_city < 0
						or EquivariantOrder.city_id_less(
							state, nation.id, staging_city, best_city
						)
					)
				)
			):
				best_city = staging_city
				best_route = candidate
		if best_city < 0:
			continue
		group.posture = BattleGroup.Posture.RECOVER
		group.target_nation = target_nation
		group.target_city = best_city
		group.corridor_lane = -1
		group.route = best_route
		group.route_revision = state.road_network_revision
		group.merge_group_owner = -1
		group.merge_group_id = -1
		assigned[group.id] = true
		assigned_troops += group_strength(state, group)
		if assigned_troops >= required_troops:
			break
	return assigned


static func _set_group_order(
	state: GameState,
	group: BattleGroup,
	posture: int,
	target_nation: int,
	target_city: int,
	route_override: Variant = null,
	corridor_lane: int = -1
) -> void:
	group.posture = posture
	group.target_nation = target_nation
	group.target_city = target_city
	group.defense_edge_to = -1
	group.corridor_lane = (
		corridor_lane if posture == BattleGroup.Posture.ATTACK else -1
	)
	if route_override is Array:
		group.route.assign(route_override)
	else:
		group.route = (
			shared_capital_route(state, group.owner_nation, target_nation)
			if posture == BattleGroup.Posture.ATTACK and target_nation >= 0
			else route_to_city(state, group, target_city)
		)
	group.route_revision = state.road_network_revision
	group.merge_group_owner = -1
	group.merge_group_id = -1


static func _first_defender_node(
	state: GameState,
	defender_id: int,
	route: Array[int]
) -> int:
	for city_id in route:
		if state.cities[city_id].owner_nation == defender_id:
			return city_id
	return -1


static func _route_merge_candidate(
	state: GameState,
	leader_route: Array[int],
	follower_route: Array[int],
	leader_proximity: Dictionary,
	follower_nation: int,
	target_nation: int
) -> Dictionary:
	for follower_index in range(follower_route.size() - 1):
		var follower_node := follower_route[follower_index]
		if not leader_proximity.has(follower_node):
			continue
		var proximity: Dictionary = leader_proximity[follower_node]
		var leader_index := int(proximity["route_index"])
		# 只在敌都之前汇流；两条路线仅共享最终首都不算汇流。
		if leader_index >= leader_route.size() - 1:
			continue
		var leader_node := leader_route[leader_index]
		var connector := _shortest_hop_path(
			state, follower_node, leader_node, ROUTE_MERGE_HOPS,
			follower_nation, target_nation
		)
		if follower_node != leader_node and connector.is_empty():
			continue
		return {
			"leader_index": leader_index,
			"follower_index": follower_index,
			"connector": connector,
		}
	return {}


static func _route_proximity(
	state: GameState,
	route: Array[int],
	max_hops: int
) -> Dictionary:
	var result := {}
	var queue: Array[Vector2i] = []
	for route_index in range(route.size() - 1):
		var node := route[route_index]
		if result.has(node):
			continue
		result[node] = {"distance": 0, "route_index": route_index}
		queue.append(Vector2i(node, route_index))
	while not queue.is_empty():
		var entry: Vector2i = queue.pop_front()
		var node := entry.x
		var source_index := entry.y
		var depth := int((result[node] as Dictionary)["distance"])
		if depth >= max_hops:
			continue
		var neighbors := state.neighbors(node)
		EquivariantOrder.sort_city_subset(
			neighbors,
			state,
			state.cities[route[0]].owner_nation,
			route[0]
		)
		for neighbor in neighbors:
			var edge := state.edge_of(node, neighbor)
			if edge == null or edge.max_manpower <= 0 or result.has(neighbor):
				continue
			result[neighbor] = {
				"distance": depth + 1,
				"route_index": source_index,
			}
			queue.append(Vector2i(neighbor, source_index))
	return result


static func _shortest_hop_path(
	state: GameState,
	start: int,
	goal: int,
	max_hops: int,
	mover_nation: int,
	target_nation: int
) -> Array[int]:
	if start == goal:
		return [] as Array[int]
	var previous := {}
	var depth := {start: 0}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var node: int = queue.pop_front()
		if int(depth[node]) >= max_hops:
			continue
		var neighbors := state.neighbors(node)
		EquivariantOrder.sort_city_subset(
			neighbors, state, mover_nation, start
		)
		for neighbor in neighbors:
			var edge := state.edge_of(node, neighbor)
			if edge == null or edge.max_manpower <= 0 or depth.has(neighbor):
				continue
			var owner := state.cities[neighbor].owner_nation
			if (
				owner != target_nation
				and not state.has_military_access(mover_nation, owner)
			):
				continue
			depth[neighbor] = int(depth[node]) + 1
			previous[neighbor] = node
			if neighbor == goal:
				return Pathfinding.reconstruct(previous, start, goal)
			queue.append(neighbor)
	return [] as Array[int]


static func _remove_route_cycles(route: Array[int]) -> Array[int]:
	var result: Array[int] = []
	var index_by_city := {}
	for city_id in route:
		if index_by_city.has(city_id):
			var keep_index := int(index_by_city[city_id])
			while result.size() > keep_index + 1:
				index_by_city.erase(result.pop_back())
			continue
		index_by_city[city_id] = result.size()
		result.append(city_id)
	return result
