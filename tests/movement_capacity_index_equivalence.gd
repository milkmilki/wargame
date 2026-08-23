extends SceneTree
## 行军同向容量局部索引等价守卫。新旧两条路径都调用真实
## _advance_movement()；唯一区别是是否用索引替代逐军全表扫描。
## 定向夹具同时覆盖：既有占边军、同国同向窄路争抢、稳定 state.armies
## 顺序、同国反向独立、不同 owner 独立，以及到达释放后下一 tick 才准入。

const TEST_TICKS: int = 36

var _mismatches: int = 0


func _init() -> void:
	var legacy := _make_contention_case(true)
	var indexed := _make_contention_case(false)
	_compare_states(legacy.state, indexed.state, 0)
	for tick in range(1, TEST_TICKS + 1):
		legacy.simulation._advance_movement()
		indexed.simulation._advance_movement()
		_compare_states(legacy.state, indexed.state, tick)
		_check_index_lifetime(indexed.simulation, tick)
		if tick == 1:
			_check_first_tick(indexed.state)
		elif tick == 2:
			_check_second_tick(indexed.state)

	print(
		"=== 行军容量局部索引等价校验（定向窄路/%d tick）==="
		% TEST_TICKS
	)
	print("不一致=%d" % _mismatches)
	print("verdict=%s" % (
		"MOVEMENT_CAPACITY_INDEX_EQUIVALENT"
		if _mismatches == 0
		else "MOVEMENT_CAPACITY_INDEX_DIVERGED"
	))
	legacy.simulation.free()
	indexed.simulation.free()
	quit(0 if _mismatches == 0 else 1)


func _make_contention_case(disable_index: bool) -> Dictionary:
	var world := GameState.new()
	world.generate_grid_world(20260823)
	world.armies.clear()
	world.battles.clear()
	var from_city := -1
	var to_city := -1
	for candidate in world.edges:
		if (
			world.cities[candidate.city_a].owner_nation
				== world.cities[candidate.city_b].owner_nation
		):
			from_city = candidate.city_a
			to_city = candidate.city_b
			break
	assert(from_city >= 0 and to_city >= 0)
	var edge := world.edge_of(from_city, to_city)
	edge.max_manpower = Edge.TERRAIN_LOW_MANPOWER
	edge.distance = 1
	edge.travel_time_multiplier = 1.0
	edge.danger = 0.0
	edge.passing_count = 0
	edge.occupied = false
	var owner := world.cities[from_city].owner_nation
	var other_owner := (owner + 1) % world.nations.size()
	world.set_diplomatic_relation(
		owner, other_owner, GameState.DiplomaticRelation.ALLIED
	)

	# 既有同向军占半条窄路，并在首 tick 末到达。等待军的准入发生在
	# 到达释放之前，因此首 tick 只能按数组顺序放入第一支。
	var holder := _make_edge_army(9000, owner, from_city, to_city)
	holder.move_progress = 0.99
	world.armies.append(holder)
	edge.passing_count += 1
	edge.occupied = true
	for army_id in range(9001, 9005):
		world.armies.append(
			_make_waiting_army(army_id, owner, from_city, to_city)
		)
	# 反方向与另一 owner 各有独立桶，即使 owner 的正向桶已满仍可入边。
	world.armies.append(
		_make_waiting_army(9010, owner, to_city, from_city)
	)
	world.armies.append(
		_make_waiting_army(9020, other_owner, from_city, to_city)
	)

	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(world)
	simulation.movement_capacity_index_disabled = disable_index
	return {"state": world, "simulation": simulation}


func _make_edge_army(
	army_id: int,
	owner: int,
	from_city: int,
	to_city: int
) -> Army:
	var army := _make_waiting_army(army_id, owner, from_city, to_city)
	army.path.clear()
	army.move_to = to_city
	army.on_edge = true
	return army


func _make_waiting_army(
	army_id: int,
	owner: int,
	from_city: int,
	to_city: int
) -> Army:
	var army := Army.new()
	army.id = army_id
	army.owner_nation = owner
	army.size = Edge.MIN_MANPOWER
	army.max_size = Edge.MIN_MANPOWER
	army.attack = 10
	army.defense = 10
	army.state = Army.State.MOVING
	army.location_city = from_city
	army.move_from = from_city
	army.move_to = -1
	army.move_progress = 0.0
	army.path = [to_city] as Array[int]
	return army


func _compare_states(legacy: GameState, indexed: GameState, tick: int) -> void:
	if legacy.armies.size() != indexed.armies.size():
		_fail(
			"tick=%d army count legacy=%d indexed=%d"
			% [tick, legacy.armies.size(), indexed.armies.size()]
		)
	var indexed_by_id := {}
	for army in indexed.armies:
		indexed_by_id[army.id] = army
	for legacy_army in legacy.armies:
		var indexed_army: Army = indexed_by_id.get(legacy_army.id)
		if indexed_army == null:
			_fail("tick=%d indexed missing army=%d" % [tick, legacy_army.id])
			continue
		var legacy_fp := _army_position_fp(legacy_army)
		var indexed_fp := _army_position_fp(indexed_army)
		if legacy_fp != indexed_fp:
			_fail(
				"tick=%d army=%d\n  legacy=%s\n  indexed=%s"
				% [tick, legacy_army.id, legacy_fp, indexed_fp]
			)
	if legacy.edges.size() != indexed.edges.size():
		_fail(
			"tick=%d edge count legacy=%d indexed=%d"
			% [tick, legacy.edges.size(), indexed.edges.size()]
		)
	var edge_count := mini(legacy.edges.size(), indexed.edges.size())
	for edge_index in range(edge_count):
		var legacy_edge: Edge = legacy.edges[edge_index]
		var indexed_edge: Edge = indexed.edges[edge_index]
		if (
			legacy_edge.city_a != indexed_edge.city_a
			or legacy_edge.city_b != indexed_edge.city_b
			or legacy_edge.passing_count != indexed_edge.passing_count
			or legacy_edge.occupied != indexed_edge.occupied
		):
			_fail(
				"tick=%d edge=%d-%d passing legacy=%d indexed=%d"
				% [
					tick, legacy_edge.city_a, legacy_edge.city_b,
					legacy_edge.passing_count, indexed_edge.passing_count,
				]
			)


func _army_position_fp(army: Army) -> Array:
	return [
		army.owner_nation, army.size, army.state, army.location_city,
		army.move_from, army.move_to, army.move_progress,
		army.path.duplicate(), army.on_edge, army.battle_id,
		army.encounter_blocked,
	]


func _check_index_lifetime(simulation: Simulation, tick: int) -> void:
	if (
		simulation._movement_capacity_index_active
		or not simulation._movement_capacity_load_by_direction.is_empty()
		or not simulation._movement_capacity_entry_by_army.is_empty()
	):
		_fail("tick=%d movement index leaked beyond phase" % tick)


func _check_first_tick(world: GameState) -> void:
	var by_id := _armies_by_id(world)
	var edge := world.edge_of(
		(by_id[9001] as Army).move_from,
		(by_id[9001] as Army).move_to
	)
	if not (
		(by_id[9000] as Army).state == Army.State.IDLE
		and not (by_id[9000] as Army).on_edge
		and (by_id[9001] as Army).on_edge
		and (by_id[9002] as Army).move_to == -1
		and (by_id[9003] as Army).move_to == -1
		and (by_id[9004] as Army).move_to == -1
		and (by_id[9010] as Army).on_edge
		and (by_id[9020] as Army).on_edge
		and edge != null
		and edge.passing_count == 3
	):
		_fail(
			"tick=1 narrow-road arbitration/order/directional buckets incorrect"
		)


func _check_second_tick(world: GameState) -> void:
	var by_id := _armies_by_id(world)
	var edge := world.edge_of(
		(by_id[9001] as Army).move_from,
		(by_id[9001] as Army).move_to
	)
	if not (
		(by_id[9001] as Army).on_edge
		and (by_id[9002] as Army).on_edge
		and (by_id[9003] as Army).move_to == -1
		and (by_id[9004] as Army).move_to == -1
		and edge != null
		and edge.passing_count == 4
	):
		_fail(
			"tick=2 released capacity did not admit exactly the next army"
		)


func _armies_by_id(world: GameState) -> Dictionary:
	var result := {}
	for army in world.armies:
		result[army.id] = army
	return result


func _fail(message: String) -> void:
	_mismatches += 1
	if _mismatches <= 20:
		print("[FAIL] %s" % message)
