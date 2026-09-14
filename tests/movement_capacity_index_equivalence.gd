extends SceneTree
## 兼容旧测试入口：容量索引已经随军事二值通行规则删除。
## 本守卫验证所有正容量道路并行通行，且每个日阶段不产生等待队列。

const TEST_TICKS: int = 12


func _init() -> void:
	var world := GameState.new()
	world.generate_grid_world(20260823)
	world.armies.clear()
	world.battles.clear()
	var edge: Edge = world.edges[0]
	var owner := world.cities[edge.city_a].owner_nation
	world.cities[edge.city_b].owner_nation = owner
	edge.max_manpower = Edge.MIN_MANPOWER
	edge.distance = 1
	edge.travel_time_multiplier = 1.0
	for army_id in range(9000, 9005):
		var army := Army.new()
		army.id = army_id
		army.owner_nation = owner
		army.size = GameState.INITIAL_HEAVY_ARMY_SIZE
		army.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
		army.state = Army.State.MOVING
		army.location_city = edge.city_a
		army.move_from = edge.city_a
		army.path = [edge.city_b] as Array[int]
		world.armies.append(army)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(world)
	for army in world.armies:
		simulation._begin_next_leg(army)
	var valid := edge.passing_count == world.armies.size()
	for army in world.armies:
		valid = valid and army.on_edge and army.move_to == edge.city_b
	for _tick in range(TEST_TICKS):
		simulation._advance_movement()
	valid = valid and edge.passing_count == 0
	for army in world.armies:
		valid = valid and army.state == Army.State.IDLE
	print("=== 军事二值通行兼容校验 ===")
	print("verdict=%s" % (
		"MILITARY_BINARY_ROAD_EQUIVALENT"
		if valid else "MILITARY_BINARY_ROAD_DIVERGED"
	))
	simulation.free()
	quit(0 if valid else 1)
