extends SceneTree
## 40 国正式地图压力基准。对照默认 4 国，隔离国家数量带来的 AI/外交复杂度。

const STRESS_NATION_COUNT: int = 40
const DEFAULT_DAYS: int = 365
const DEFAULT_SEED: int = 12345
const SuccessionAudit = preload("res://tests/succession_audit.gd")


func _init() -> void:
	if OS.get_cmdline_user_args().has("--test-territory-report"):
		quit(0 if _test_territory_report() else 1)
		return
	var days := _environment_int(
		"AI_STRESS_DAYS",
		DEFAULT_DAYS
	)
	var world_seed := _environment_int(
		"AI_STRESS_SEED",
		DEFAULT_SEED
	)
	var stress := _run_case(
		STRESS_NATION_COUNT,
		days,
		world_seed
	)
	if OS.get_environment("AI_STRESS_SKIP_BASELINE") == "1":
		_print_case(stress)
		print(
			"verdict=%s"
			% (
				"STRESS_PASS"
				if bool(stress["ok"])
				else "STRESS_FAIL"
			)
		)
		quit(0 if bool(stress["ok"]) else 1)
		return
	var baseline := _run_case(
		GameState.NATION_COUNT,
		days,
		world_seed
	)
	_print_case(stress)
	_print_case(baseline)
	_print_scale(stress, baseline)
	var failed := (
		not bool(stress["ok"])
		or not bool(baseline["ok"])
		or not _within_optional_limit(
			stress,
			"ai",
			"AI_STRESS_MAX_AI_MS"
		)
		or not _within_optional_limit(
			stress,
			"monthly",
			"AI_STRESS_MAX_MONTHLY_MS"
		)
	)
	print(
		"verdict=%s"
		% (
			"STRESS_FAIL"
			if failed
			else "STRESS_PASS"
		)
	)
	quit(1 if failed else 0)


func _run_case(
	nation_count: int,
	days: int,
	world_seed: int
) -> Dictionary:
	var generation_started := Time.get_ticks_usec()
	var regional_queries_before := RegionalStrategy.query_count
	var regional_geometry_before := RegionalStrategy.geometry_build_count
	var regional_control_before := RegionalStrategy.control_build_count
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(world_seed, nation_count)
	var generation_usec := (
		Time.get_ticks_usec() - generation_started
	)
	var initial_armies := state.armies.size()
	var initial_land_counts := _land_city_counts(state)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	var all_ticks: Array[int] = []
	var ordinary_ticks: Array[int] = []
	var ai_ticks: Array[int] = []
	var warm_ai_ticks: Array[int] = []
	var monthly_ticks: Array[int] = []
	var cold_ai_usec := 0
	var peak_day := 0
	var peak_usec := 0
	var invariant_error := _invariant_error(
		state,
		simulation
	)
	while (
		state.day < days
		and state.winner == -1
		and invariant_error.is_empty()
	):
		var started := Time.get_ticks_usec()
		simulation._advance_day()
		var elapsed := Time.get_ticks_usec() - started
		all_ticks.append(elapsed)
		if elapsed > peak_usec:
			peak_usec = elapsed
			peak_day = state.day
		var ai_day := (
			state.day == 1
			or state.day
				% Simulation.AI_DECISION_INTERVAL_DAYS
				== 0
		)
		var monthly_day := (
			state.day % Simulation.DAYS_PER_MONTH == 0
		)
		if ai_day:
			ai_ticks.append(elapsed)
			if state.day == 1:
				cold_ai_usec = elapsed
			else:
				warm_ai_ticks.append(elapsed)
		if monthly_day:
			monthly_ticks.append(elapsed)
		if not ai_day and not monthly_day:
			ordinary_ticks.append(elapsed)
		invariant_error = _invariant_error(
			state,
			simulation
		)
	var war_pairs := 0
	var alliance_pairs := 0
	for nation_a in range(state.nations.size()):
		for nation_b in range(
			nation_a + 1,
			state.nations.size()
		):
			if state.is_enemy(nation_a, nation_b):
				war_pairs += 1
			elif state.is_allied(nation_a, nation_b):
				alliance_pairs += 1
	var alive := 0
	for nation in state.nations:
		if nation.alive and not nation.succession_identity:
			alive += 1
	var result := {
		"ok": invariant_error.is_empty(),
		"error": invariant_error,
		"nation_count": nation_count,
		"requested_days": days,
		"completed_days": state.day,
		"seed": world_seed,
		"generation_ms": float(generation_usec) / 1000.0,
		"cities": state.cities.size(),
		"land_cities": state.land_cities().size(),
		"largest_territory": _largest_territory_report(state),
		"succession": SuccessionAudit.inspect(state),
		"initial_land_min": initial_land_counts.min(),
		"initial_land_max": initial_land_counts.max(),
		"initial_armies": initial_armies,
		"final_armies": state.armies.size(),
		"battles": state.battles.size(),
		"alive": alive,
		"winner": state.winner,
		"war_pairs": war_pairs,
		"alliance_pairs": alliance_pairs,
		"diplomatic_events":
			state.diplomatic_history.size(),
		"commit_failures":
			simulation.ai_command_commit_failure_total,
		"peak_day": peak_day,
		"all": _timing_stats(all_ticks),
		"ordinary": _timing_stats(ordinary_ticks),
		"ai": _timing_stats(ai_ticks),
		"warm_ai": _timing_stats(warm_ai_ticks),
		"cold_ai_ms": float(cold_ai_usec) / 1000.0,
		"monthly": _timing_stats(monthly_ticks),
		"regional_queries": RegionalStrategy.query_count - regional_queries_before,
		"regional_geometry_builds": RegionalStrategy.geometry_build_count - regional_geometry_before,
		"regional_control_builds": RegionalStrategy.control_build_count - regional_control_before,
	}
	simulation.free()
	return result


func _land_city_counts(
	state: GameState
) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(state.nations.size())
	counts.fill(0)
	for city in state.land_cities():
		counts[city.owner_nation] += 1
	return counts


func _largest_territory_report(state: GameState) -> Dictionary:
	var land := state.land_cities()
	var roots := PackedInt32Array()
	roots.resize(state.nations.size())
	for nation in state.nations:
		roots[nation.id] = state.food_pool_holder(nation.id)
	var controlled := {}
	var direct := {}
	for city in land:
		var owner := city.owner_nation
		if owner < 0 or owner >= roots.size():
			continue
		var root_id := roots[owner]
		controlled[root_id] = int(controlled.get(root_id, 0)) + 1
		direct[owner] = int(direct.get(owner, 0)) + 1
	var largest_id := -1
	var largest_count := 0
	for root_value in controlled:
		var root_id := int(root_value)
		var count := int(controlled[root_id])
		if count > largest_count or (count == largest_count and root_id < largest_id):
			largest_id = root_id
			largest_count = count
	return {
		"root_nation_id": largest_id,
		"name": state.nation_display_name(largest_id) if largest_id >= 0 else "none",
		"land_cities": largest_count,
		"direct_land_cities": int(direct.get(largest_id, 0)),
		"total_land_cities": land.size(),
		"share": float(largest_count) / float(land.size()) if not land.is_empty() else 0.0,
	}


func _test_territory_report() -> bool:
	var state := preload("res://tests/support/grid_world.gd").new()
	for id in range(4):
		var nation := Nation.new()
		nation.id = id
		nation.alive = true
		state.nations.append(nation)
	for owner in [0, 1, 1, 2, 3, -1]:
		var city := City.new()
		city.id = state.cities.size()
		city.owner_nation = owner
		state.cities.append(city)
	var dock := City.new()
	dock.id = state.cities.size()
	dock.owner_nation = 3
	dock.is_dock = true
	state.cities.append(dock)
	state.suzerainty = {1: {"overlord_id": 0, "civil_war": false}, 2: {"overlord_id": 1, "civil_war": false}}
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.ALLIED)
	var report := _largest_territory_report(state)
	var valid: bool = report.root_nation_id == 0 and report.land_cities == 4 and report.direct_land_cities == 1 and report.total_land_cities == 6 and is_equal_approx(report.share, 4.0 / 6.0)
	state.suzerainty[1].civil_war = true
	report = _largest_territory_report(state)
	valid = valid and report.root_nation_id == 1 and report.land_cities == 3 and report.direct_land_cities == 2
	state.suzerainty.clear()
	state.cities[2].owner_nation = 2
	report = _largest_territory_report(state)
	valid = valid and report.root_nation_id == 2 and report.land_cities == 2
	state.cities[3].owner_nation = 0
	state.cities[5].owner_nation = 2
	report = _largest_territory_report(state)
	valid = valid and report.root_nation_id == 0 and report.land_cities == 2
	report = _largest_territory_report(preload("res://tests/support/grid_world.gd").new())
	valid = valid and report.root_nation_id == -1 and report.total_land_cities == 0 and report.share == 0.0
	if not valid:
		push_error("territory report must count peaceful suzerainty, exclude docks/allies and use stable ties")
	print("STRESS_TERRITORY_REPORT_OK=%s" % valid)
	return valid


func _invariant_error(
	state: GameState,
	simulation: Simulation
) -> String:
	if state.nations.is_empty():
		return "没有生成国家"
	var succession := SuccessionAudit.inspect(state)
	if not succession.errors.is_empty():
		return str(succession.errors[0])
	for pair_value in state.campaign_pairs.values():
		var pair := pair_value as CoalitionCampaignPair
		if pair.battlefields.size() > CoalitionCampaignPair.MAX_BATTLEFIELDS:
			return "集合对%d超过两个州战场" % pair.pair_id
		var centers := {}
		for slot in pair.battlefields:
			if centers.has(slot["center_city_id"]):
				return "集合对%d同州重复占用名额" % pair.pair_id
			centers[slot["center_city_id"]] = true
	var assignments := {}
	var defenses := {}
	for front_value in state.campaign_fronts.values():
		var front := front_value as CoalitionCampaignFront
		for army_id in front.army_assignments:
			if assignments.has(army_id):
				return "军队%d重复绑定任务" % army_id
			assignments[army_id] = front.front_id
		if not front.retiring and front.mode == CoalitionCampaignFront.Mode.DEFENSE:
			var key := "%d:%s:%d" % [front.war_id, str(front.participant_nation_ids), front.center_city_id]
			if defenses.has(key):
				return "防守州%d重复计算需求" % front.center_city_id
			defenses[key] = true
	var owned_counts: Array[int] = []
	owned_counts.resize(state.nations.size())
	owned_counts.fill(0)
	for city in state.cities:
		if (
			city.owner_nation < 0
			or city.owner_nation >= state.nations.size()
		):
			return "城市%d国家索引越界:%d" % [
				city.id,
				city.owner_nation,
			]
		if not city.is_dock:
			owned_counts[city.owner_nation] += 1
	for nation in state.nations:
		if (
			nation.alive
			and owned_counts[nation.id] <= 0
		):
			return "存活国家%d没有城市" % nation.id
		if (
			owned_counts[nation.id] > 0
			and (
				nation.capital_city_id < 0
				or nation.capital_city_id >= state.cities.size()
				or state.cities[
					nation.capital_city_id
				].owner_nation != nation.id
			)
		):
			return "国家%d首都无效:%d" % [
				nation.id,
				nation.capital_city_id,
			]
		if (
			nation.treasury_gold < 0
			or nation.manpower_pool < 0
			or nation.granary_food < 0
			or nation.last_military_upkeep < 0
			or nation.unpaid_military_upkeep < 0
			or nation.unpaid_military_upkeep
				> nation.last_military_upkeep
			or nation.military_payment_ratio < 0.0
			or nation.military_payment_ratio > 1.0
		):
			return "国家%d财政状态无效" % nation.id
	for army in state.armies:
		if (
			army.size <= 0
			or army.owner_nation < 0
			or army.owner_nation >= state.nations.size()
		):
			return "军队%d状态无效" % army.id
		if (
			not army.is_main_battle_role()
			or army.battle_group_id < 0
			or army.max_size != GameState.INITIAL_HEAVY_ARMY_SIZE
			or state.battle_group_members(
				army.owner_nation, army.battle_group_id
			).size() != 1
		):
			return "军队%d不是独立15000人主战指挥单位" % army.id
		var node_city := army.current_city_node()
		if (
			node_city < 0
			or node_city >= state.cities.size()
			or state.has_military_access(
				army.owner_nation,
				state.cities[node_city].owner_nation
			)
		):
			continue
		var battle := state.battle_by_id(army.battle_id)
		var valid_hostile_siege := (
			army.state == Army.State.FIGHTING
			and battle != null
			and not battle.finished
			and battle.kind == Battle.Kind.SIEGE
			and battle.city != null
			and battle.city.id == node_city
			and battle.has_army(army)
		)
		if not valid_hostile_siege:
			var city := state.cities[node_city]
			var relevant_diplomacy: Array[Dictionary] = []
			for event in state.diplomatic_history:
				if (
					int(event.get("day", -1)) == state.day
					and (
						int(event.get("nation_a", -1))
							in [
								army.owner_nation,
								city.owner_nation,
							]
						or int(event.get("nation_b", -1))
							in [
								army.owner_nation,
								city.owner_nation,
							]
					)
				):
					relevant_diplomacy.append(event)
			return (
				"敌军驻留:day=%d army=%d nation=%d state=%d "
				+ "location=%d node=%d edge=%d-%d progress=%.3f "
				+ "forced=%d target=%d battle=%d city_owner=%d "
				+ "recognized=%d sponsor=%d path=%s reason=%s "
					+ "relevant_diplomacy=%s"
			) % [
				state.day,
				army.id,
				army.owner_nation,
				army.state,
				army.location_city,
				node_city,
				army.move_from,
				army.move_to,
				army.move_progress,
				1 if army.forced_retreat else 0,
				army.ai_target_city,
				army.battle_id,
				city.owner_nation,
				state.recognized_owner_of(node_city),
				city.occupation_sponsor_nation,
				str(army.path),
				army.ai_order_reason,
					JSON.stringify(relevant_diplomacy),
			]
	for nation in state.nations:
		if not state.cities_of(nation.id).is_empty():
			continue
		for other in state.nations:
			if (
				other.id != nation.id
				and state.is_enemy(nation.id, other.id)
			):
				return "灭亡国家%d仍与国家%d交战" % [
					nation.id,
					other.id,
				]
	if simulation.ai_command_commit_failure_total > 0:
		return "AI命令提交失败:%d" % (
			simulation.ai_command_commit_failure_total
		)
	return ""


func _timing_stats(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {
			"count": 0,
			"avg_ms": 0.0,
			"p95_ms": 0.0,
			"max_ms": 0.0,
			"total_ms": 0.0,
		}
	var ordered := values.duplicate()
	ordered.sort()
	var total_usec := 0
	for value in values:
		total_usec += value
	var p95_index := clampi(
		int(ceil(float(ordered.size()) * 0.95)) - 1,
		0,
		ordered.size() - 1
	)
	return {
		"count": values.size(),
		"avg_ms": (
			float(total_usec)
				/ float(values.size())
				/ 1000.0
		),
		"p95_ms": float(ordered[p95_index]) / 1000.0,
		"max_ms": float(ordered[-1]) / 1000.0,
		"total_ms": float(total_usec) / 1000.0,
	}


func _print_case(result: Dictionary) -> void:
	print("regional_index queries=%d geometry_builds=%d control_builds=%d" % [
		result["regional_queries"], result["regional_geometry_builds"], result["regional_control_builds"]])
	var all: Dictionary = result["all"]
	var ordinary: Dictionary = result["ordinary"]
	var warm_ai: Dictionary = result["warm_ai"]
	var monthly: Dictionary = result["monthly"]
	print(
		(
			"case nations=%d seed=%d days=%d/%d "
			+ "generation_ms=%.2f cities=%d/%d "
			+ "land_per_nation=%d-%d armies=%d->%d "
			+ "alive=%d winner=%d battles=%d "
			+ "wars=%d alliances=%d diplomacy=%d "
			+ "commit_failures=%d"
		) % [
			result["nation_count"],
			result["seed"],
			result["completed_days"],
			result["requested_days"],
			result["generation_ms"],
			result["land_cities"],
			result["cities"],
			result["initial_land_min"],
			result["initial_land_max"],
			result["initial_armies"],
			result["final_armies"],
			result["alive"],
			result["winner"],
			result["battles"],
			result["war_pairs"],
			result["alliance_pairs"],
			result["diplomatic_events"],
			result["commit_failures"],
		]
	)
	var territory: Dictionary = result["largest_territory"]
	print("  SUCCESSION_AUDIT %s" % str(result.succession))
	print("  largest_power root=%d name=%s land=%d/%d territory_share=%.2f%% direct=%d vassal=%d basis=peaceful_suzerainty_land_cities" % [
		territory.root_nation_id, territory.name, territory.land_cities,
		territory.total_land_cities, float(territory.share) * 100.0,
		territory.direct_land_cities, int(territory.land_cities) - int(territory.direct_land_cities)])
	print(
		(
			"  timing total=%.2fms peak_day=%d "
			+ "all=%d/%.2f/%.2f/%.2fms "
			+ "ordinary=%d/%.2f/%.2f/%.2fms "
			+ "cold_ai=%.2fms "
			+ "warm_ai=%d/%.2f/%.2f/%.2fms "
			+ "monthly=%d/%.2f/%.2f/%.2fms"
		) % [
			all["total_ms"],
			result["peak_day"],
			all["count"],
			all["avg_ms"],
			all["p95_ms"],
			all["max_ms"],
			ordinary["count"],
			ordinary["avg_ms"],
			ordinary["p95_ms"],
			ordinary["max_ms"],
			result["cold_ai_ms"],
			warm_ai["count"],
			warm_ai["avg_ms"],
			warm_ai["p95_ms"],
			warm_ai["max_ms"],
			monthly["count"],
			monthly["avg_ms"],
			monthly["p95_ms"],
			monthly["max_ms"],
		]
	)
	if not bool(result["ok"]):
		print("  invariant_error=%s" % result["error"])


func _print_scale(
	stress: Dictionary,
	baseline: Dictionary
) -> void:
	print(
		(
			"scale 40v4 all_avg=%.2fx warm_ai_avg=%.2fx "
			+ "monthly_avg=%.2fx total=%.2fx"
		) % [
			_ratio(
				stress["all"]["avg_ms"],
				baseline["all"]["avg_ms"]
			),
			_ratio(
				stress["warm_ai"]["avg_ms"],
				baseline["warm_ai"]["avg_ms"]
			),
			_ratio(
				stress["monthly"]["avg_ms"],
				baseline["monthly"]["avg_ms"]
			),
			_ratio(
				stress["all"]["total_ms"],
				baseline["all"]["total_ms"]
			),
		]
	)


func _within_optional_limit(
	result: Dictionary,
	timing_key: String,
	environment_key: String
) -> bool:
	var raw := OS.get_environment(environment_key)
	if raw.is_empty():
		return true
	var limit_ms := float(raw)
	var actual_ms := float(
		result[timing_key]["max_ms"]
	)
	if actual_ms <= limit_ms:
		return true
	print(
		"limit_exceeded %s max=%.2fms limit=%.2fms"
		% [timing_key, actual_ms, limit_ms]
	)
	return false


func _environment_int(
	key: String,
	fallback: int
) -> int:
	var raw := OS.get_environment(key)
	return (
		maxi(int(raw), 1)
		if not raw.is_empty()
		else fallback
	)


func _ratio(value: float, baseline: float) -> float:
	return value / maxf(baseline, 0.0001)
