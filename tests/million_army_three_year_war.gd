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
			var report := state.coalition_campaign_allocation(war_id, nation_id)
			if int(report["war_pool_total"]) > 0:
				positive_pool_days[nation_id] += 1
			observed_campaign = observed_campaign or not (
				state.campaign_fronts_for_nation(nation_id).is_empty()
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
	state.clear_campaign_fronts()
	for nation in state.nations:
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
	# 本夹具验证百万级战争池和共享战线，不把普通道路吞吐量当作测试变量。
	# 提高容量后仍保留真实寻路、行军、补给、战斗和占领结算。
	for edge in state.edges:
		edge.max_manpower = 2000000
		edge.base_max_manpower = 2000000
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
	var first := state.coalition_campaign_allocation(war_id, nation_id)
	var second := state.coalition_campaign_allocation(war_id, nation_id)
	if first != second:
		return "nation=%d same-day report changed" % nation_id
	if int(first.get("duplicate_assignments", 0)) != 0:
		return "nation=%d duplicate assignments" % nation_id
	var members: Array[int] = first.get("component_members", [])
	var expected_total := 0
	var expected_effective := 0
	for army in state.armies:
		if army.size <= 0 or not members.has(army.owner_nation):
			continue
		if army.campaign_front_id >= 0:
			var front := state.campaign_front(army.campaign_front_id)
			if front == null or not front.army_assignments.has(army.id):
				return "army=%d stale front binding" % army.id
			if army.campaign_war_id != front.war_id:
				return "army=%d front/war binding mismatch" % army.id
		if army.campaign_war_id == war_id:
			expected_total += army.size
			if state.army_effective_for_field_campaign(army):
				expected_effective += army.size
	if int(first["war_pool_total"]) != expected_total:
		return "nation=%d pool total mismatch" % nation_id
	if int(first["war_pool_effective"]) != expected_effective:
		return "nation=%d effective pool mismatch" % nation_id
	return ""


func _active_battle_count(state: GameState) -> int:
	var result := 0
	for battle in state.battles:
		if not battle.finished:
			result += 1
	return result


func _print_year(state: GameState, war_id: int) -> void:
	var reports: Array[Dictionary] = []
	for nation_id in NATIONS:
		var allocation := state.coalition_campaign_allocation(
			war_id, nation_id
		)
		var front_rows: Array[Dictionary] = []
		for front_id_value in (allocation["fronts"] as Dictionary):
			var front_id := int(front_id_value)
			var front_report: Dictionary = allocation["fronts"][front_id]
			var front := state.campaign_front(front_id)
			var at_target := 0
			if front != null:
				for army in state.armies:
					if (
						army.campaign_front_id == front_id
						and not army.on_edge
						and army.location_city == int(
							front.army_assignments.get(army.id, -1)
						)
					):
						at_target += army.size
			front_rows.append({
				"center": int(front_report["center_id"]),
				"mode": int(front_report["mode"]),
				"phase": front.phase if front != null else -1,
				"staging": front.staging_city_id if front != null else -1,
				"requirement": (
					maxi(
						Simulation.CAMPAIGN_MIN_FRONT_MANPOWER,
						state.campaign_siege_requirement(
							front.anchor_nation_id, front.center_city_id
						) + state.campaign_reinforcement_threat(
							front.anchor_nation_id, front.center_city_id
						)
					)
					if front != null
					and front.mode == CoalitionCampaignFront.Mode.OFFENSE
					else 0
				),
				"assigned": int(front_report["assigned_effective"]),
				"arrived": int(front_report["arrived_effective"]),
				"at_target": at_target,
			})
		reports.append({
			"nation": nation_id,
			"total": int(allocation["war_pool_total"]),
			"effective": int(allocation["war_pool_effective"]),
			"fronts": front_rows,
		})
	print(
		"MILLION_WAR_YEAR day=%d battles=%d reports=%s"
		% [state.day, _active_battle_count(state), str(reports)]
	)

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
