extends SceneTree
## Two million-manpower states fight for three full years while the test
## independently audits every war-pool and state-front force total each day.

const DAYS := 1095
const ARMY_COUNT_PER_NATION := 67
const ARMY_SIZE := 15000
const NATIONS: Array[int] = [0, 1]


func _init() -> void:
	var state := _build_fixture()
	var target_center := _border_target_center(state, 0, 1)
	if target_center < 0:
		push_error("MILLION_WAR_FIXTURE_NO_BORDER_TARGET")
		quit(1)
		return
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.set_war_objective(
		0, 1, target_center, "双百万军队三年实战门禁"
	)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	# The fixture tests military execution, not AI willingness to negotiate.
	simulation.diplomacy_enabled = false
	var initial_owners: Array[int] = []
	for city in state.cities:
		initial_owners.append(city.owner_nation)
	var observed_battle := false
	var observed_movement := false
	var observed_campaign := false
	var observed_occupation := false
	var positive_pool_days := [0, 0]
	var peak_battles := 0
	var started := Time.get_ticks_msec()
	for _day_index in range(DAYS):
		simulation._advance_day(false)
		if not state.is_enemy(0, 1):
			_fail(simulation, "day=%d war relation ended" % state.day)
			return
		if not state.nations[0].alive or not state.nations[1].alive:
			_fail(simulation, "day=%d one nation was eliminated" % state.day)
			return
		for nation_id in NATIONS:
			var report_error := _war_report_error(
				state, nation_id, war_id
			)
			if not report_error.is_empty():
				_fail(simulation, "day=%d %s" % [state.day, report_error])
				return
			var report := state.campaign_war_force_report(
				nation_id, war_id
			)
			if int(report["war_pool_total"]) > 0:
				positive_pool_days[nation_id] += 1
			observed_campaign = observed_campaign or not (
				state.nations[nation_id].administrative_campaign_plans.is_empty()
			)
		for army in state.armies:
			if army.owner_nation not in NATIONS or army.size <= 0:
				continue
			observed_movement = observed_movement or (
				army.on_edge
				or army.state in [Army.State.MOVING, Army.State.RETREATING]
			)
			observed_battle = observed_battle or army.state == Army.State.FIGHTING
		peak_battles = maxi(peak_battles, _active_battle_count(state))
		for city in state.cities:
			if city.owner_nation != initial_owners[city.id]:
				observed_occupation = true
				break
		if state.day % Simulation.DAYS_PER_YEAR == 0:
			_print_year(state, war_id)
	var valid := (
		observed_battle
		and observed_movement
		and observed_campaign
		and observed_occupation
		and int(positive_pool_days[0]) > 0
		and int(positive_pool_days[1]) > 0
	)
	var elapsed := Time.get_ticks_msec() - started
	if not valid:
		_fail(
			simulation,
			(
				"insufficient execution battle=%s movement=%s campaign=%s "
				+ "occupation=%s pool_days=%s"
			) % [
				observed_battle, observed_movement, observed_campaign,
				observed_occupation, str(positive_pool_days),
			]
		)
		return
	print(
		(
			"MILLION_ARMY_THREE_YEAR_WAR_OK days=%d initial_per_nation=%d "
			+ "peak_battles=%d pool_days=%s elapsed_ms=%d"
		) % [
			state.day, ARMY_COUNT_PER_NATION * ARMY_SIZE,
			peak_battles, str(positive_pool_days), elapsed,
		]
	)
	simulation.free()
	quit(0)


func _build_fixture() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(94147)
	state.armies.clear()
	state.battles.clear()
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	for nation in state.nations:
		nation.administrative_campaign_plans.clear()
		nation.battle_groups.clear()
		nation.capital_city_id = -1
		nation.warehouse_city_ids.clear()
		nation.alive = nation.id in NATIONS
		nation.treasury_gold = 100000000 if nation.alive else 0
		nation.manpower_pool = 10000000 if nation.alive else 0
	for city in state.cities:
		var center_id := state.administrative_center_of(city.id)
		var anchor := state.cities[center_id] if center_id >= 0 else city
		var owner_id := 0 if anchor.coord.x < GameState.GRID / 2 else 1
		city.owner_nation = owner_id
		state.recognized_city_owners[city.id] = owner_id
		city.loyalty_target_nation = owner_id
		city.loyalty = 100.0
		city.unrest = 0.0
		city.rebellion_progress = 0
		city.manpower_per_month = 100000
		city.gold_per_month = 100000
		city.food_per_half_year = 1000000
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		if state.administrative_center_city_ids.has(city.id):
			city.garrison_manpower = 15000
	var centers := [
		_extreme_center(state, 0, false),
		_extreme_center(state, 1, true),
	]
	for nation_id in NATIONS:
		var center_id := int(centers[nation_id])
		var nation := state.nations[nation_id]
		nation.capital_city_id = center_id
		nation.warehouse_city_ids = [center_id] as Array[int]
		state.cities[center_id].is_capital = true
		state.cities[center_id].has_warehouse = true
		state.cities[center_id].food_storage = 100000000
		# Keep the regression in active war for all 1095 days. Front-line state
		# capitals retain normal garrisons; only the remote terminal capital gets
		# a deep reserve so capital capture cannot trigger forced peace early.
		state.cities[center_id].garrison_manpower = 1000000
	state.ownership_revision += 1
	state.refresh_derived()
	for nation_id in NATIONS:
		var origins := _owned_centers(state, nation_id)
		for index in range(ARMY_COUNT_PER_NATION):
			var army := state.create_army(
				nation_id,
				origins[index % origins.size()],
				ARMY_SIZE,
				ARMY_SIZE,
			)
			if army == null:
				push_error(
					"MILLION_WAR_ARMY_CREATION_FAILED nation=%d index=%d"
					% [nation_id, index]
				)
				continue
			army.attack = 10
			army.defense = 10
			army.morale = army.max_morale
			army.supply_ratio = 1.0
	state.refresh_derived()
	return state


func _war_report_error(
	state: GameState,
	nation_id: int,
	war_id: int
) -> String:
	var first := state.campaign_war_force_report(nation_id, war_id)
	var second := state.campaign_war_force_report(nation_id, war_id)
	if first != second:
		return "nation=%d same-day report changed" % nation_id
	var assigned_plans := {}
	var expected_fronts := {}
	var duplicate_assignments := 0
	for plan_value in state.nations[
		nation_id
	].administrative_campaign_plans.values():
		var plan := plan_value as AdministrativeCampaignPlan
		if plan == null:
			continue
		if plan.war_id == war_id:
			expected_fronts[plan.center_city_id] = {
				"assigned_total": 0,
				"assigned_effective": 0,
			}
		for army_id_value in plan.army_assignments:
			var army_id := int(army_id_value)
			if assigned_plans.has(army_id):
				duplicate_assignments += 1
				continue
			assigned_plans[army_id] = plan
	var expected_pool_total := 0
	var expected_pool_effective := 0
	var national_total := 0
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		national_total += army.size
		var effective := state.army_effective_for_field_campaign(army)
		if army.campaign_war_id == war_id:
			expected_pool_total += army.size
			if effective:
				expected_pool_effective += army.size
		var assigned_plan := assigned_plans.get(
			army.id
		) as AdministrativeCampaignPlan
		if assigned_plan == null or assigned_plan.war_id != war_id:
			continue
		if army.campaign_war_id != war_id:
			return (
				"nation=%d army=%d front/war binding mismatch"
				% [nation_id, army.id]
			)
		var front: Dictionary = expected_fronts[assigned_plan.center_city_id]
		front["assigned_total"] = int(front["assigned_total"]) + army.size
		if effective:
			front["assigned_effective"] = (
				int(front["assigned_effective"]) + army.size
			)
	if duplicate_assignments != 0:
		return "nation=%d duplicate assignments=%d" % [
			nation_id, duplicate_assignments,
		]
	if (
		int(first["duplicate_assignments"]) != 0
		or int(first["war_pool_total"]) != expected_pool_total
		or int(first["war_pool_effective"]) != expected_pool_effective
		or expected_pool_effective > expected_pool_total
		or expected_pool_total > national_total
	):
		return (
			"nation=%d pool mismatch report=%d/%d expected=%d/%d national=%d"
			% [
				nation_id,
				int(first["war_pool_total"]),
				int(first["war_pool_effective"]),
				expected_pool_total,
				expected_pool_effective,
				national_total,
			]
		)
	var reported_fronts: Dictionary = first["fronts"]
	if reported_fronts.size() != expected_fronts.size():
		return "nation=%d front count changed report=%d expected=%d" % [
			nation_id, reported_fronts.size(), expected_fronts.size(),
		]
	for center_value in expected_fronts:
		var center_id := int(center_value)
		var expected: Dictionary = expected_fronts[center_id]
		var actual: Dictionary = reported_fronts.get(center_id, {})
		if (
			int(actual.get("assigned_total", -1))
				!= int(expected["assigned_total"])
			or int(actual.get("assigned_effective", -1))
				!= int(expected["assigned_effective"])
		):
			return "nation=%d center=%d front mismatch actual=%s expected=%s" % [
				nation_id, center_id, str(actual), str(expected),
			]
	return ""


func _active_battle_count(state: GameState) -> int:
	var count := 0
	for battle in state.battles:
		if not battle.finished:
			count += 1
	return count


func _print_year(state: GameState, war_id: int) -> void:
	var chunks: Array[String] = []
	for nation_id in NATIONS:
		var report := state.campaign_war_force_report(nation_id, war_id)
		chunks.append("N%d total=%d pool=%d effective=%d fronts=%d" % [
			nation_id,
			_nation_manpower(state, nation_id),
			int(report["war_pool_total"]),
			int(report["war_pool_effective"]),
			(report["fronts"] as Dictionary).size(),
		])
	print("MILLION_WAR_YEAR year=%d %s" % [
		state.day / Simulation.DAYS_PER_YEAR,
		" | ".join(chunks),
	])


func _nation_manpower(state: GameState, nation_id: int) -> int:
	var total := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			total += army.size
	return total


func _border_target_center(
	state: GameState,
	attacker_id: int,
	defender_id: int
) -> int:
	for pair in state.territorial_border_pairs():
		var city_a := state.cities[pair.x]
		var city_b := state.cities[pair.y]
		if (
			city_a.owner_nation == attacker_id
			and city_b.owner_nation == defender_id
		):
			return state.administrative_center_of(city_b.id)
		if (
			city_b.owner_nation == attacker_id
			and city_a.owner_nation == defender_id
		):
			return state.administrative_center_of(city_a.id)
	return -1


func _owned_centers(state: GameState, nation_id: int) -> Array[int]:
	var result: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if state.cities[center_id].owner_nation == nation_id:
			result.append(center_id)
	EquivariantOrder.sort_city_ids(result, state, nation_id)
	return result


func _extreme_center(
	state: GameState,
	nation_id: int,
	prefer_larger_x: bool
) -> int:
	var centers := _owned_centers(state, nation_id)
	var best := centers[0]
	for center_id in centers.slice(1):
		var best_x := state.cities[best].coord.x
		var candidate_x := state.cities[center_id].coord.x
		if (
			(prefer_larger_x and candidate_x > best_x)
			or (not prefer_larger_x and candidate_x < best_x)
		):
			best = center_id
	return best


func _fail(simulation: Simulation, message: String) -> void:
	push_error("MILLION_ARMY_THREE_YEAR_WAR_FAILED %s" % message)
	simulation.free()
	quit(1)
