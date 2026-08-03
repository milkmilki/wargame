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
	var strict_mirror := (
		OS.get_environment("AI_DUEL_STRICT_MIRROR") == "1"
	)
	var trace_combat := (
		OS.get_environment("AI_DUEL_TRACE_COMBAT") == "1"
	)
	if trace_combat:
		Combat.clear_battle_log()
		Combat.battle_log_enabled = true
	var started := Time.get_ticks_msec()
	for _day in range(DUEL_DAYS):
		if state.winner != -1:
			break
		var combat_log_start := Combat.battle_log.size()
		simulation._advance_day()
		if strict_mirror:
			var mismatch := _strict_mirror_mismatch(state)
			if not mismatch.is_empty():
				if trace_combat:
					for log_index in range(
						combat_log_start,
						Combat.battle_log.size()
					):
						print(
							"combat_trace=%s"
							% JSON.stringify(
								Combat.battle_log[log_index]
							)
						)
				print(
					"verdict=STRICT_MIRROR_FAIL day=%d %s"
					% [state.day, mismatch]
				)
				Combat.battle_log_enabled = false
				simulation.free()
				quit(4)
				return
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
	elif duel_mode == "legacy-fairness":
		left_policy = "legacy"
		right_policy = "legacy"
	elif duel_mode == "balanced-fairness":
		left_policy = "balanced"
		right_policy = "balanced"
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
	if strict_mirror:
		print("strict_mirror_days=%d" % state.day)
	Combat.battle_log_enabled = false
	_print_army_diagnostics(state)
	var improved_ai_better := false
	if duel_mode in [
		"current-control",
		"legacy-fairness",
		"balanced-fairness",
	]:
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
		"legacy-fairness":
			simulation.rotate_ai_nation_order = false
			for nation_id in [LEFT_NATION, RIGHT_NATION]:
				simulation.ai_legacy_id_personality_overrides[nation_id] = true
		"balanced-fairness":
			pass
		"current-control":
			for nation_id in [LEFT_NATION, RIGHT_NATION]:
				simulation.ai_executable_attack_paths_overrides[nation_id] = false
		"improved-right":
			simulation.ai_executable_attack_paths_overrides[LEFT_NATION] = false
		"offense-only":
			simulation.ai_adaptive_garrison_overrides[LEFT_NATION] = false
			simulation.ai_strategic_planning_overrides[RIGHT_NATION] = false
			simulation.ai_adaptive_garrison_overrides[RIGHT_NATION] = false
		"garrison-only":
			simulation.ai_strategic_planning_overrides[LEFT_NATION] = false
			simulation.ai_strategic_planning_overrides[RIGHT_NATION] = false
			simulation.ai_adaptive_garrison_overrides[RIGHT_NATION] = false
		_:
			simulation.ai_executable_attack_paths_overrides[RIGHT_NATION] = false


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
		city.fort_strength = 12 + (row * 3 + mirror_col * 5) % 17
		city.fort_strength_max = city.fort_strength
		city.fort_last_capture_day = -1
		city.manpower_per_month = 7 + (row * 7 + mirror_col * 11) % 8
		city.gold_per_month = 6 + (row * 2 + mirror_col * 3) % 10
		city.food_per_half_year = 600 + (row * 17 + mirror_col * 29) % 201
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
	_set_capital(state, LEFT_NATION, left_capital, 16000)
	_set_capital(state, RIGHT_NATION, right_capital, 16000)

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
		edge.max_manpower = 30000
		edge.passing_count = 0
		edge.occupied = false

	state.armies.clear()
	for city_id in range(state.cities.size()):
		var city := state.cities[city_id]
		var row := city.coord.y
		var mirror_col := mini(city.coord.x, GameState.GRID - 1 - city.coord.x)
		var army := state.create_army(
			city.owner_nation,
			city_id,
			GameState.INITIAL_LIGHT_ARMY_SIZE,
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
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
	var left_owned := state.cities_of(LEFT_NATION)
	left_owned.sort_custom(func(a: City, b: City) -> bool:
		return a.id < b.id
	)
	for index in range(left_owned.size() / 2):
		var left_city := left_owned[index * 2]
		var right_city := state.cities[_mirror_city_id(
			state,
			left_city.id
		)]
		var paired_cities: Array[City] = [
			left_city,
			right_city,
		]
		for city in paired_cities:
			var row := city.coord.y
			var mirror_col := mini(
				city.coord.x,
				GameState.GRID - 1 - city.coord.x
			)
			var army := state.create_army(
				city.owner_nation,
				city.id,
				GameState.INITIAL_HEAVY_ARMY_SIZE,
				GameState.INITIAL_HEAVY_ARMY_SIZE
			)
			army.attack = 9 + (row * 5 + mirror_col * 3) % 7
			army.defense = 9 + (row * 3 + mirror_col * 5) % 7
			army.speed_factor = 0.5
	var rng_seed := 991199
	var seed_override := OS.get_environment("AI_DUEL_RNG_SEED")
	if not seed_override.is_empty():
		rng_seed = int(seed_override)
	state.rng.seed = rng_seed
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
				or left.fort_strength != right.fort_strength
				or left.fort_strength_max != right.fort_strength_max
				or left.fort_last_capture_day
					!= right.fort_last_capture_day
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
			or edge.max_manpower != mirror.max_manpower
		):
			return false
	return true


func _validate_annual_food_surplus() -> bool:
	var state := _build_symmetric_world()
	state.armies.clear()
	var left_owned := state.cities_of(LEFT_NATION)
	for i in range(10):
		var left_city := left_owned[(i * 3) % left_owned.size()]
		var right_city_id := _mirror_city_id(state, left_city.id)
		var left_army := state.create_army(
			LEFT_NATION, left_city.id, Army.DEFAULT_MAX_SIZE
		)
		var right_army := state.create_army(
			RIGHT_NATION, right_city_id, Army.DEFAULT_MAX_SIZE
		)
		left_army.max_size = Army.DEFAULT_MAX_SIZE
		right_army.max_size = Army.DEFAULT_MAX_SIZE
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
	return left_surplus > 0 and left_surplus == right_surplus


func _mirror_city_id(state: GameState, city_id: int) -> int:
	var coord := state.cities[city_id].coord
	return coord.y * GameState.GRID + (GameState.GRID - 1 - coord.x)


func _strict_mirror_mismatch(state: GameState) -> String:
	var left_nation := state.nations[LEFT_NATION]
	var right_nation := state.nations[RIGHT_NATION]
	for field in [
		"manpower_pool",
		"treasury_gold",
		"granary_food",
		"last_food_demand",
		"campaign_preparation_started_day",
		"campaign_launched_bonus_days",
	]:
		if left_nation.get(field) != right_nation.get(field):
			return "nation.%s left=%s right=%s" % [
				field,
				str(left_nation.get(field)),
				str(right_nation.get(field)),
			]
	for field in [
		"food_demand_ema",
		"ai_aggression",
		"campaign_preparation_multiplier",
		"campaign_launched_attack_multiplier",
	]:
		if not is_equal_approx(
			float(left_nation.get(field)),
			float(right_nation.get(field))
		):
			return "nation.%s left=%.9f right=%.9f" % [
				field,
				float(left_nation.get(field)),
				float(right_nation.get(field)),
			]
	var right_full_preparation_target := (
		_mirror_city_id(
			state,
			right_nation.campaign_full_preparation_target_city
		)
		if right_nation.campaign_full_preparation_target_city >= 0
		else -1
	)
	if (
		left_nation.campaign_full_preparation_target_city
			!= right_full_preparation_target
	):
		return (
			"nation.campaign_full_preparation_target_city "
			+ "left=%d mirrored_right=%d"
		) % [
			left_nation.campaign_full_preparation_target_city,
			right_full_preparation_target,
		]
	var left_post_capture_plans: Array[String] = []
	for city_id_value in left_nation.campaign_post_capture_plans:
		var city_id := int(city_id_value)
		var plan: Dictionary = (
			left_nation.campaign_post_capture_plans[city_id]
		)
		left_post_capture_plans.append("%d:%d:%d" % [
			city_id,
			int(plan.get("preparation_days", -1)),
			int(plan.get("expires_day", -1)),
		])
	var right_post_capture_plans: Array[String] = []
	for city_id_value in right_nation.campaign_post_capture_plans:
		var city_id := int(city_id_value)
		var plan: Dictionary = (
			right_nation.campaign_post_capture_plans[city_id]
		)
		right_post_capture_plans.append("%d:%d:%d" % [
			_mirror_city_id(state, city_id),
			int(plan.get("preparation_days", -1)),
			int(plan.get("expires_day", -1)),
		])
	left_post_capture_plans.sort()
	right_post_capture_plans.sort()
	if left_post_capture_plans != right_post_capture_plans:
		return "nation.campaign_post_capture_plans left=%s right=%s" % [
			left_post_capture_plans,
			right_post_capture_plans,
		]
	for row in range(GameState.GRID):
		for col in range(GameState.GRID / 2):
			var left_id := row * GameState.GRID + col
			var right_id := _mirror_city_id(state, left_id)
			var left := state.cities[left_id]
			var right := state.cities[right_id]
			var mirrored_owner := _mirror_nation(right.owner_nation)
			if left.owner_nation != mirrored_owner:
				return "city.owner left_city=%d left=%d right_city=%d mirrored_right=%d" % [
					left_id,
					left.owner_nation,
					right_id,
					mirrored_owner,
				]
			for field in [
				"fort_strength",
				"fort_strength_max",
				"fort_last_capture_day",
				"manpower_per_month",
				"gold_per_month",
				"food_per_half_year",
				"food_storage",
				"war_disruption_until_day",
			]:
				if left.get(field) != right.get(field):
					return "city.%s left_city=%d left=%s right_city=%d right=%s" % [
						field,
						left_id,
						str(left.get(field)),
						right_id,
						str(right.get(field)),
					]
	var left_armies := _canonical_army_multiset(
		state,
		LEFT_NATION
	)
	var right_armies := _canonical_army_multiset(
		state,
		RIGHT_NATION
	)
	if left_armies != right_armies:
		var common := mini(left_armies.size(), right_armies.size())
		for index in range(common):
			if left_armies[index] != right_armies[index]:
				return "army[%d] left=%s right=%s" % [
					index,
					left_armies[index],
					right_armies[index],
				]
		return "army_count left=%d right=%d" % [
			left_armies.size(),
			right_armies.size(),
		]
	return ""


func _canonical_army_multiset(
	state: GameState,
	nation_id: int
) -> Array[String]:
	var result: Array[String] = []
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		var location := _canonical_city_for_nation(
			state,
			nation_id,
			army.location_city
		)
		var move_from := _canonical_city_for_nation(
			state,
			nation_id,
			army.move_from
		)
		var move_to := _canonical_city_for_nation(
			state,
			nation_id,
			army.move_to
		)
		var target := _canonical_city_for_nation(
			state,
			nation_id,
			army.ai_target_city
		)
		var path: Array[int] = []
		for city_id in army.path:
			path.append(_canonical_city_for_nation(
				state,
				nation_id,
				city_id
			))
		result.append(
			(
				"s=%d|max=%d|atk=%d|def=%d|state=%d|loc=%d|"
				+ "from=%d|to=%d|prog=%.9f|path=%s|mor=%.9f|"
				+ "sup=%.9f|starve=%s|hold=%d|holdp=%.9f|"
					+ "blocked=%s|forced=%s|action=%d|target=%d|until=%d|"
				+ "off=%.9f|off_until=%d|def_until=%d|reason=%s"
			) % [
				army.size,
				army.max_size,
				army.attack,
				army.defense,
				army.state,
				location,
				move_from,
				move_to,
				army.move_progress,
				str(path),
				army.morale,
				army.supply_ratio,
				str(army.starving),
				army.holding_days,
				army.hold_target_progress,
					str(army.encounter_blocked),
				str(army.forced_retreat),
				army.ai_action,
				target,
				army.ai_order_until_day,
				army.offensive_attack_multiplier,
				army.offensive_bonus_until_day,
				army.defensive_deployment_until_day,
				_reason_shape(army.ai_order_reason),
			]
		)
	result.sort()
	return result


func _reason_shape(reason: String) -> String:
	var result := ""
	for character in reason:
		if character < "0" or character > "9":
			result += character
	return result


func _canonical_city_for_nation(
	state: GameState,
	nation_id: int,
	city_id: int
) -> int:
	if city_id < 0:
		return city_id
	return (
		_mirror_city_id(state, city_id)
		if nation_id == RIGHT_NATION
		else city_id
	)


func _mirror_nation(nation_id: int) -> int:
	if nation_id == LEFT_NATION:
		return RIGHT_NATION
	if nation_id == RIGHT_NATION:
		return LEFT_NATION
	return nation_id


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
