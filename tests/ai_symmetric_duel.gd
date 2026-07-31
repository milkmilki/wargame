extends SceneTree
## 左右完全镜像的双国 AI 对战基准。
## A（左侧 nation 0）= 改进 Utility AI；B（右侧 nation 1）= 修改前的当前 Utility AI。

const DUEL_DAYS: int = 3650
const LEFT_NATION: int = 0
const RIGHT_NATION: int = 1


func _init() -> void:
	var state := _build_symmetric_world()
	if not _validate_symmetry(state):
		print("verdict=INVALID_ASYMMETRIC_FIXTURE")
		quit(2)
		return
	if not _validate_annual_food_surplus():
		print("verdict=NEGATIVE_ANNUAL_FOOD_BALANCE")
		quit(3)
		return
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.diplomacy_enabled = false
	var duel_mode := OS.get_environment("AI_DUEL_MODE")
	if duel_mode.is_empty():
		duel_mode = "improved-left"
	_configure_duel_mode(simulation, duel_mode)
	for diagnostic_nation in [LEFT_NATION, RIGHT_NATION]:
		var diagnostic_view := AiWorldView.build(state, diagnostic_nation)
		var diagnostic_snapshot := StrategicMapSnapshot.build(diagnostic_view)
		print(
			"nation=%d critical_supply_cities=%s"
			% [
				diagnostic_nation,
				str(diagnostic_snapshot.critical_supply_cities),
			]
		)

	var initial_owner: Array[int] = []
	for city in state.cities:
		initial_owner.append(city.owner_nation)
	var started := Time.get_ticks_msec()
	for _day in range(DUEL_DAYS):
		if state.winner != -1:
			break
		simulation._advance_day()
		if state.day % 365 == 0:
			_print_snapshot(state)

	var result := _measure(state, initial_owner)
	var elapsed := Time.get_ticks_msec() - started
	print("\n==== A 改进 AI vs B 当前 AI：最终结果 ====")
	print("mode=%s" % duel_mode)
	var left_policy := "improved"
	var right_policy := "current"
	if duel_mode == "current-control":
		left_policy = "current"
	elif duel_mode == "improved-right":
		left_policy = "current"
		right_policy = "improved"
	elif duel_mode == "garrison-only":
		left_policy = "garrison-only"
	elif duel_mode == "offense-only":
		left_policy = "offense-only"
	var summary_template := (
		"day=%d winner=%d elapsed_ms=%d\n"
		+ "left_%s: cities=%d power=%.1f food=%d capital=%s captures=%d\n"
		+ "right_%s: cities=%d power=%.1f food=%d capital=%s captures=%d\n"
		+ "left_advantage_score=%.1f"
	)
	var summary := summary_template % [
		state.day, state.winner, elapsed,
		left_policy,
		result["new_cities"], result["new_power"], result["new_food"],
		str(result["new_capital"]), result["new_captures"],
		right_policy,
		result["old_cities"], result["old_power"], result["old_food"],
		str(result["old_capital"]), result["old_captures"],
		result["score"],
	]
	print(summary)
	_print_army_diagnostics(state)
	var improved_ai_better := false
	if duel_mode == "current-control":
		print("verdict=CONTROL_COMPLETE")
		simulation.free()
		quit(0)
		return
	elif duel_mode == "improved-right":
		improved_ai_better = (
			state.winner == RIGHT_NATION
			or (state.winner == -1 and float(result["score"]) < 0.0)
		)
	else:
		improved_ai_better = (
			state.winner == LEFT_NATION
			or (state.winner == -1 and float(result["score"]) > 0.0)
		)
	print(
		"verdict=%s"
		% ("IMPROVED_AI_BETTER" if improved_ai_better else "IMPROVED_AI_NOT_BETTER")
	)
	simulation.free()
	quit(0 if improved_ai_better else 1)


func _configure_duel_mode(simulation: Simulation, mode: String) -> void:
	match mode:
		"current-control":
			for nation_id in [LEFT_NATION, RIGHT_NATION]:
				simulation.ai_supply_corridor_defense_overrides[nation_id] = false
		"improved-right":
			simulation.ai_supply_corridor_defense_overrides[LEFT_NATION] = false
		"offense-only":
			simulation.ai_adaptive_garrison_overrides[LEFT_NATION] = false
			simulation.ai_strategic_planning_overrides[RIGHT_NATION] = false
			simulation.ai_adaptive_garrison_overrides[RIGHT_NATION] = false
		"garrison-only":
			simulation.ai_strategic_planning_overrides[LEFT_NATION] = false
			simulation.ai_strategic_planning_overrides[RIGHT_NATION] = false
			simulation.ai_adaptive_garrison_overrides[RIGHT_NATION] = false
		_:
			simulation.ai_supply_corridor_defense_overrides[RIGHT_NATION] = false


func _build_symmetric_world() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(880088)
	state.battles.clear()
	state.nations.resize(2)
	state.day = 0
	state.month = 0
	state.winner = -1
	state.ownership_revision = 0
	for nation in state.nations:
		nation.capital_city_id = -1
		nation.warehouse_city_ids.clear()
		nation.granary_food = 0
		nation.alive = true
		nation.treasury_gold = 200

	for city in state.cities:
		var row := city.coord.y
		var col := city.coord.x
		var mirror_col := mini(col, GameState.GRID - 1 - col)
		city.owner_nation = LEFT_NATION if col < GameState.GRID / 2 else RIGHT_NATION
		state.recognized_city_owners[city.id] = city.owner_nation
		city.defense = 12 + (row * 3 + mirror_col * 5) % 17
		city.manpower_per_month = 7 + (row * 7 + mirror_col * 11) % 8
		city.gold_per_month = 6 + (row * 2 + mirror_col * 3) % 10
		city.food_per_half_year = 25 + (row * 7 + mirror_col * 11) % 36
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		city.at_war = true

	for nation in state.nations:
		nation.manpower_pool = 0
	for city in state.cities:
		state.nations[city.owner_nation].manpower_pool += (
			city.manpower_per_month
			* GameState.INITIAL_MANPOWER_RESERVE_MONTHS
		)

	var left_capital := 3 * GameState.GRID + 1
	var right_capital := 3 * GameState.GRID + 6
	_set_capital(state, LEFT_NATION, left_capital, 1500)
	_set_capital(state, RIGHT_NATION, right_capital, 1500)

	for edge in state.edges:
		var a := state.cities[edge.city_a].coord
		var b := state.cities[edge.city_b].coord
		var norm_a := mini(a.x, GameState.GRID - 1 - a.x)
		var norm_b := mini(b.x, GameState.GRID - 1 - b.x)
		var axis := 1 if a.y != b.y else 0
		var signature := mini(a.y, b.y) * 17 + (norm_a + norm_b) * 13 + axis * 7
		edge.distance = 1 + signature % 5
		edge.danger = 0.05 + 0.1 * float(signature % 5)
		if (
			(a.x == 3 and b.x == 4)
			or (a.x == 4 and b.x == 3)
		):
			edge.danger = 0.45
		edge.max_throughput = 2
		edge.passing_count = 0
		edge.occupied = false

	for city_id in range(state.cities.size()):
		var army := state.armies[city_id]
		var city := state.cities[city_id]
		var row := city.coord.y
		var mirror_col := mini(city.coord.x, GameState.GRID - 1 - city.coord.x)
		army.owner_nation = city.owner_nation
		army.size = 700 + (row * 97 + mirror_col * 131) % 700
		army.attack = 9 + (row * 5 + mirror_col * 3) % 7
		army.defense = 9 + (row * 3 + mirror_col * 5) % 7
		army.speed_factor = 0.5
		army.location_city = city_id
		army.move_from = city_id
		army.move_to = -1
		army.move_progress = 0.0
		army.path.clear()
		army.state = Army.State.IDLE
		army.battle_id = -1
		army.on_edge = false
		army.morale = 1.0
		army.supply_ratio = 1.0
		army.starving = false
		army.forced_retreat = false
		army.holding_days = 0
		army.hold_target_progress = -1.0
	state.rng.seed = 991199
	state.refresh_derived()
	return state


func _validate_symmetry(state: GameState) -> bool:
	if state.nations.size() != 2:
		return false
	if (
		state.nations[LEFT_NATION].manpower_pool
		!= state.nations[RIGHT_NATION].manpower_pool
	):
		return false
	for row in range(GameState.GRID):
		for col in range(GameState.GRID / 2):
			var left_id := row * GameState.GRID + col
			var right_id := row * GameState.GRID + (GameState.GRID - 1 - col)
			var left := state.cities[left_id]
			var right := state.cities[right_id]
			if (
				left.owner_nation != LEFT_NATION
				or right.owner_nation != RIGHT_NATION
				or left.defense != right.defense
				or left.manpower_per_month != right.manpower_per_month
				or left.gold_per_month != right.gold_per_month
				or left.food_per_half_year != right.food_per_half_year
				or left.is_capital != right.is_capital
				or left.has_warehouse != right.has_warehouse
				or left.food_storage != right.food_storage
			):
				return false
			var left_army := state.armies[left_id]
			var right_army := state.armies[right_id]
			if (
				left_army.size != right_army.size
				or left_army.attack != right_army.attack
				or left_army.defense != right_army.defense
				or not is_equal_approx(left_army.morale, right_army.morale)
			):
				return false
	for edge in state.edges:
		var mirror_a := _mirror_city_id(state, edge.city_a)
		var mirror_b := _mirror_city_id(state, edge.city_b)
		var mirror := state.edge_of(mirror_a, mirror_b)
		if (
			mirror == null
			or edge.distance != mirror.distance
			or not is_equal_approx(edge.danger, mirror.danger)
			or edge.max_throughput != mirror.max_throughput
		):
			return false
	return true


func _validate_annual_food_surplus() -> bool:
	var state := _build_symmetric_world()
	state.armies.clear()
	for nation_id in [LEFT_NATION, RIGHT_NATION]:
		var owned := state.cities_of(nation_id)
		for i in range(10):
			var city := owned[(i * 3) % owned.size()]
			var army := state.create_army(nation_id, city.id, Army.DEFAULT_MAX_SIZE)
			army.max_size = Army.DEFAULT_MAX_SIZE
	var simulation := Simulation.new()
	simulation.setup(state)
	var initial_food := [
		state.nations[LEFT_NATION].granary_food,
		state.nations[RIGHT_NATION].granary_food,
	]
	for month in range(1, 13):
		state.day = month * Simulation.DAYS_PER_MONTH
		simulation._resolve_economy()
		simulation._resolve_supply()
	state.refresh_derived()
	var left_surplus := state.nations[LEFT_NATION].granary_food - int(initial_food[LEFT_NATION])
	var right_surplus := state.nations[RIGHT_NATION].granary_food - int(initial_food[RIGHT_NATION])
	print(
		"annual_food_surplus: left=%d right=%d consumption_rate=%.4f"
		% [left_surplus, right_surplus, Simulation.FOOD_PER_CAPITA]
	)
	simulation.free()
	return left_surplus > 0 and right_surplus > 0


func _mirror_city_id(state: GameState, city_id: int) -> int:
	var coord := state.cities[city_id].coord
	return coord.y * GameState.GRID + (GameState.GRID - 1 - coord.x)


func _set_capital(
	state: GameState,
	nation_id: int,
	city_id: int,
	food: int
) -> void:
	var nation := state.nations[nation_id]
	nation.capital_city_id = city_id
	nation.warehouse_city_ids = [city_id] as Array[int]
	var city := state.cities[city_id]
	city.is_capital = true
	city.has_warehouse = true
	city.food_storage = food


func _measure(state: GameState, initial_owner: Array[int]) -> Dictionary:
	var cities := [0, 0]
	var power := [0.0, 0.0]
	var captures := [0, 0]
	for city in state.cities:
		if city.owner_nation in [LEFT_NATION, RIGHT_NATION]:
			cities[city.owner_nation] += 1
			if (
				initial_owner.size() == state.cities.size()
				and city.owner_nation != initial_owner[city.id]
			):
				captures[city.owner_nation] += 1
	for army in state.armies:
		if army.owner_nation in [LEFT_NATION, RIGHT_NATION]:
			power[army.owner_nation] += ArmyPower.effective(army)
	var left_capital_alive := (
		state.nations[LEFT_NATION].capital_city_id >= 0
		and state.cities[state.nations[LEFT_NATION].capital_city_id].owner_nation == LEFT_NATION
	)
	var right_capital_alive := (
		state.nations[RIGHT_NATION].capital_city_id >= 0
		and state.cities[state.nations[RIGHT_NATION].capital_city_id].owner_nation == RIGHT_NATION
	)
	var score: float = (
		float(cities[LEFT_NATION] - cities[RIGHT_NATION]) * 1000.0
		+ power[LEFT_NATION] - power[RIGHT_NATION]
		+ float(
			state.nations[LEFT_NATION].granary_food
			- state.nations[RIGHT_NATION].granary_food
		) * 0.1
		+ (5000.0 if left_capital_alive else 0.0)
		- (5000.0 if right_capital_alive else 0.0)
	)
	return {
		"new_cities": cities[LEFT_NATION],
		"old_cities": cities[RIGHT_NATION],
		"new_power": power[LEFT_NATION],
		"old_power": power[RIGHT_NATION],
		"new_food": state.nations[LEFT_NATION].granary_food,
		"old_food": state.nations[RIGHT_NATION].granary_food,
		"new_capital": left_capital_alive,
		"old_capital": right_capital_alive,
		"new_captures": captures[LEFT_NATION],
		"old_captures": captures[RIGHT_NATION],
		"score": score,
	}


func _print_snapshot(state: GameState) -> void:
	var metrics := _measure(state, [] as Array[int])
	var corridor_counts := [0, 0]
	for nation_id in [LEFT_NATION, RIGHT_NATION]:
		var view := AiWorldView.build(state, nation_id)
		corridor_counts[nation_id] = (
			StrategicMapSnapshot.build(view).critical_supply_cities.size()
		)
	print(
		"year=%d new_cities=%d old_cities=%d new_power=%.0f old_power=%.0f corridors=%s"
		% [
			state.day / 365,
			metrics["new_cities"], metrics["old_cities"],
			metrics["new_power"], metrics["old_power"],
			str(corridor_counts),
		]
	)


func _print_army_diagnostics(state: GameState) -> void:
	for nation_id in [LEFT_NATION, RIGHT_NATION]:
		var states := {}
		var actions := {}
		for army in state.armies:
			if army.owner_nation != nation_id:
				continue
			states[army.state] = int(states.get(army.state, 0)) + 1
			actions[army.ai_action] = int(actions.get(army.ai_action, 0)) + 1
		print("nation=%d states=%s actions=%s" % [nation_id, str(states), str(actions)])
		if nation_id == LEFT_NATION:
			for army in state.armies:
				if army.owner_nation == nation_id:
					print(
						"  army=%d size=%d state=%d city=%d edge=%d-%d action=%d target=%d reason=%s"
						% [
							army.id, army.size, army.state, army.location_city,
							army.move_from, army.move_to, army.ai_action,
							army.ai_target_city, army.ai_order_reason,
						]
					)
