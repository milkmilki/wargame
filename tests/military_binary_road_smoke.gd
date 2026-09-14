extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	print("=== MILITARY_BINARY_ROAD_SMOKE ===")
	_test_positive_capacity_is_binary_for_movement()
	_test_zero_capacity_still_blocks_movement()
	_test_capacity_still_controls_combat_frontage()
	if _failures.is_empty():
		print("MILITARY_BINARY_ROAD_SMOKE_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("MILITARY_BINARY_ROAD_SMOKE_FAIL: " + failure)
	quit(1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _test_positive_capacity_is_binary_for_movement() -> void:
	var state := GameState.new()
	state.generate_grid_world(91001)
	state.armies.clear()
	state.battles.clear()
	var edge: Edge = state.edges[0]
	var from_city := edge.city_a
	var to_city := edge.city_b
	var nation_id := state.cities[from_city].owner_nation
	state.cities[to_city].owner_nation = nation_id
	edge.max_manpower = Edge.MIN_MANPOWER
	edge.distance = 1
	edge.travel_time_multiplier = 1.0
	for army_id in [91010, 91011]:
		var army := Army.new()
		army.id = army_id
		army.owner_nation = nation_id
		army.size = GameState.INITIAL_HEAVY_ARMY_SIZE
		army.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
		army.state = Army.State.MOVING
		army.location_city = from_city
		army.move_from = from_city
		army.path = [to_city] as Array[int]
		state.armies.append(army)
	var simulation := Simulation.new()
	simulation.setup(state)
	for army in state.armies:
		simulation._begin_next_leg(army)
	var all_armies_entered := true
	for army in state.armies:
		all_armies_entered = (
			all_armies_entered
			and army.on_edge
			and army.move_to == to_city
		)
	_check(
		all_armies_entered,
		"正容量道路必须允许多支同向重军同时进入"
	)
	var narrow_days := Simulation.edge_travel_days(
		edge, GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	edge.max_manpower = Edge.TERRAIN_STANDARD_MANPOWER
	var wide_days := Simulation.edge_travel_days(
		edge, GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	_check(
		is_equal_approx(narrow_days, wide_days),
		"正容量大小不得改变军队行军时间：%.1f/%.1f"
			% [narrow_days, wide_days]
	)
	simulation.free()


func _test_zero_capacity_still_blocks_movement() -> void:
	var state := GameState.new()
	state.generate_grid_world(91002)
	var edge: Edge = state.edges[0]
	for candidate in state.edges:
		candidate.max_manpower = 0
	var field := Pathfinding.dijkstra_field(
		state,
		edge.city_a,
		-1,
		false,
		true,
		-1,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	_check(
		float(field["dist"][edge.city_b]) == INF,
		"零容量道路仍必须阻断军事寻路"
	)


func _test_capacity_still_controls_combat_frontage() -> void:
	var battle := Battle.new()
	battle.edge = Edge.new()
	battle.edge.max_manpower = Edge.TERRAIN_LOW_MANPOWER
	_check(
		Combat.combat_frontage(battle) == Edge.TERRAIN_LOW_MANPOWER,
		"取消行军吞吐后，原容量数值仍必须控制战斗正面"
	)
