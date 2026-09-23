extends SceneTree
## 同一码头两岸属于本地政治接壤。该门禁覆盖正式备战/宣战提交、军队经
## 抢滩码头渡河、州战役推进以及非首都州治实际易手的完整运行链。


func _init() -> void:
	var remote_state := _make_state()
	_add_city(remote_state, 0, true, Vector2(0.50, 0.20))
	_add_edge(remote_state, 6, 2, Edge.Kind.RIVER)
	var remote_field := Pathfinding.dijkstra_field(
		remote_state, 6, 0, false, true, 1
	)
	var remote_path := Pathfinding.reconstruct(
		remote_field["prev"], 6, 1
	)
	var remote_water_route_blocked := remote_path.is_empty()

	var state := _make_state()
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.diplomacy_enabled = false
	state.cities[3].garrison_manpower = 1000

	var objective := DiplomacyAI.select_war_objective(state, 0, 1)
	var tactical_city := int(objective.get("tactical_city_id", -1))
	var objective_center := int(objective.get("city_id", -1))
	var valid := (
		remote_water_route_blocked
		and state.cities_share_territorial_border(0, 1)
		and DiplomacyAI.can_initiate_war_at_range(state, 0, 1)
		and objective_center == 3
		and tactical_city == 1
		and DiplomacyAI.staging_cities_for_objective(
			state, 0, tactical_city
		).has(0)
	)
	var prepare_action := {
		"kind": DiplomacyAI.Action.PREPARE_WAR,
		"a": 0,
		"b": 1,
		"objective_city": tactical_city,
		"objective_center_city": objective_center,
		"objective_reason": "同一码头两岸渡河州战役测试",
		"mobilization_armies": 0,
		"reason": "渡河战争备战测试",
	}
	valid = (
		valid
		and simulation._execute_diplomatic_action(prepare_action)
		and state.nations[0].war_preparation_target_nation == 1
	)
	var declare_action := prepare_action.duplicate(true)
	declare_action["kind"] = DiplomacyAI.Action.DECLARE_WAR
	declare_action["reason"] = "渡河战争宣战测试"
	valid = (
		valid
		and simulation._execute_diplomatic_action(declare_action)
		and state.is_enemy(0, 1)
		and int(state.war_objective(0, 1).get(
			"administrative_center_city_id", -1
		)) == objective_center
	)

	var crossed_dock := false
	var bank_captured := false
	var center_captured := false
	for _day in range(360):
		for army in state.armies:
			if army.owner_nation != 0 or army.size <= 0:
				continue
			crossed_dock = crossed_dock or (
				army.location_city == 2
				or army.move_from == 2
				or army.move_to == 2
				or army.path.has(2)
			)
		simulation._advance_day()
		bank_captured = bank_captured or state.cities[1].owner_nation == 0
		center_captured = state.cities[objective_center].owner_nation == 0
		if center_captured:
			break

	valid = (
		valid
		and crossed_dock
		and state.cities[2].owner_nation == 0
		and bank_captured
		and center_captured
		and state.recognized_owner_of(objective_center) == 1
		and state.territory_structure_valid()
	)
	simulation.free()
	if valid:
		print(
			"RIVER_CROSSING_WAR_E2E_OK day=%d tactical=%d center=%d"
			% [state.day, tactical_city, objective_center]
		)
		quit(0)
		return
	push_error(
		(
			"RIVER_CROSSING_WAR_E2E_FAILED day=%d objective=%s "
			+ "crossed=%s bank_owner=%d center_owner=%d relation=%d"
		) % [
			state.day,
			str(objective),
			str(crossed_dock),
			state.cities[1].owner_nation,
			state.cities[3].owner_nation,
			state.relation_between(0, 1),
		]
	)
	quit(1)


func _make_state() -> GameState:
	var state := GameState.new()
	state.world_seed = 94201
	for nation_id in range(2):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.treasury_gold = 100000
		nation.manpower_pool = 100000
		nation.ruler_archetype = RulerProfile.BALANCED
		state.nations.append(nation)

	_add_city(state, 0, false, Vector2(0.30, 0.50)) # 0 攻方河岸
	_add_city(state, 1, false, Vector2(0.70, 0.50)) # 1 守方河岸府
	_add_city(state, 1, true, Vector2(0.50, 0.50))  # 2 共享码头
	_add_city(state, 1, false, Vector2(0.82, 0.50)) # 3 目标州治
	_add_city(state, 0, false, Vector2(0.12, 0.50)) # 4 攻方首都
	_add_city(state, 1, false, Vector2(0.94, 0.50)) # 5 守方首都
	_add_edge(state, 0, 2, Edge.Kind.LANDING)
	_add_edge(state, 1, 2, Edge.Kind.LANDING)
	_add_edge(state, 0, 4, Edge.Kind.LAND)
	_add_edge(state, 1, 3, Edge.Kind.LAND)
	_add_edge(state, 3, 5, Edge.Kind.LAND)
	state.rebuild_administrative_regions()
	# 三城链的中心稳定为3；攻方两城州的州治无需参与目标断言。
	state.nations[0].capital_city_id = 4
	state.nations[1].capital_city_id = 5
	for capital_id in [4, 5]:
		state.cities[capital_id].is_capital = true
		state.cities[capital_id].has_warehouse = true
		state.cities[capital_id].food_storage = 100000
		state.nations[state.cities[capital_id].owner_nation].warehouse_city_ids = (
			[capital_id] as Array[int]
		)
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
		city.loyalty_target_nation = city.owner_nation
		city.garrison_manpower = 0
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	for army_index in range(4):
		var army := Army.new()
		army.id = 94210 + army_index
		army.owner_nation = 0
		army.size = Army.DEFAULT_MAX_SIZE
		army.max_size = Army.DEFAULT_MAX_SIZE
		army.morale = Army.DEFAULT_MAX_MORALE
		army.location_city = 0
		army.move_from = 0
		army.state = Army.State.IDLE
		state.armies.append(army)
	state.refresh_derived()
	return state


func _add_city(
	state: GameState,
	owner: int,
	is_dock: bool,
	position: Vector2
) -> void:
	var city := City.new()
	city.id = state.cities.size()
	city.owner_nation = owner
	city.is_dock = is_dock
	city.politically_active = true
	city.map_position = position
	city.gold_per_month = 100
	city.food_per_half_year = 30000
	city.manpower_per_month = 1000
	state.cities.append(city)
	state.adjacency[city.id] = [] as Array[int]


func _add_edge(state: GameState, a: int, b: int, kind: int) -> void:
	var edge := Edge.new()
	edge.city_a = mini(a, b)
	edge.city_b = maxi(a, b)
	edge.kind = kind
	edge.distance = 1
	edge.max_manpower = (
		Edge.TERRAIN_LOW_MANPOWER
		if kind == Edge.Kind.LANDING
		else Edge.STANDARD_MANPOWER
	)
	edge.base_max_manpower = edge.max_manpower
	edge.danger = 0.9 if kind == Edge.Kind.LANDING else 0.0
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(a, b)] = edge
	(state.adjacency[a] as Array[int]).append(b)
	(state.adjacency[b] as Array[int]).append(a)
