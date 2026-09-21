extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	_test_two_state_defense_and_sortie()
	_test_national_reserve_distribution()
	for failure in _failures:
		push_error("MULTI_CAMPAIGN_DEFENSE_AI_FAIL: " + failure)
	print("MULTI_CAMPAIGN_DEFENSE_AI_%s checks=9" % [
		"OK" if _failures.is_empty() else "FAILED",
	])
	quit(0 if _failures.is_empty() else 1)


func _test_two_state_defense_and_sortie() -> void:
	var state := GameState.new()
	state.generate_grid_world(94130)
	var defender_id := 0
	var enemy_id := 1
	_configure_single_owner(state, defender_id)
	state.armies.clear()
	state.battles.clear()
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		defender_id, enemy_id, GameState.DiplomaticRelation.WAR
	)
	var centers: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		centers.append(int(center_value))
	EquivariantOrder.sort_city_ids(centers, state, defender_id)
	var reserve_center := state.administrative_center_of(
		state.nations[defender_id].capital_city_id
	)
	var threatened: Array[int] = []
	for center_id in centers:
		if center_id != reserve_center:
			threatened.append(center_id)
		if threatened.size() == 2:
			break
	_check(threatened.size() == 2, "夹具必须至少有两个非首都州")
	if threatened.size() < 2:
		return
	state.set_war_objective(
		enemy_id, defender_id, threatened[0], "多州防守门禁"
	)
	for index in range(2):
		var invader := _army(100 + index, enemy_id, threatened[index])
		state.armies.append(invader)
	for index in range(4):
		state.armies.append(_army(200 + index, defender_id, reserve_center))
	var simulation := Simulation.new()
	simulation.setup(state)
	var view := AiWorldView.build(state, defender_id)
	var snapshot := StrategicMapSnapshot.build(view)
	var threat := ThreatField.build(view)
	var defense_plan := CityDefensePlan.build(view, snapshot, threat)
	var coordinator := ArmyCoordinator.from_view(view)
	simulation._manage_campaign_offensive(
		defender_id,
		defense_plan,
		coordinator,
		{"wars": [enemy_id]},
	)
	var assigned := {}
	for center_id in threatened:
		var plan := state.campaign_plan(defender_id, center_id)
		_check(
			plan != null
			and plan.mode == AdministrativeCampaignPlan.Mode.DEFENSE,
			"每个实际受侵州都必须建立独立防守计划"
		)
		if plan == null:
			continue
		_check(
			plan.phase == AdministrativeCampaignPlan.Phase.HOLD_AND_REINFORCE,
			"增援尚未进入州域时不得提前出城野战"
		)
		_check(
			state.campaign_defensive_committed_manpower(
				defender_id, center_id
			) >= state.campaign_field_requirement(defender_id, center_id),
			"在途增援必须计入该州已承诺C"
		)
		for army_id_value in plan.army_assignments:
			var army_id := int(army_id_value)
			_check(not assigned.has(army_id), "同一支军队不得重复绑定多个州")
			assigned[army_id] = center_id
	_check(assigned.size() == 4, "两个防区应各获得足以填平缺口的两军")
	var native_nations: Dictionary = NativeSnapshotBuilder.build(state)["nations"]
	_check(
		(native_nations["campaign_centers"] as PackedInt32Array).size() >= 2
		and (
			native_nations["campaign_assignment_army_ids"]
			as PackedInt32Array
		).size() == assigned.size(),
		"原生快照必须确定性记录全部州计划及军队绑定"
	)
	for army in state.armies:
		if not assigned.has(army.id):
			continue
		var center_id := int(assigned[army.id])
		army.state = Army.State.IDLE
		army.location_city = center_id
		army.move_from = center_id
		army.move_to = -1
		army.on_edge = false
		army.path.clear()
	view = AiWorldView.build(state, defender_id)
	defense_plan = CityDefensePlan.build(
		view, StrategicMapSnapshot.build(view), ThreatField.build(view)
	)
	simulation._manage_campaign_offensive(
		defender_id,
		defense_plan,
		ArmyCoordinator.from_view(view),
		{"wars": [enemy_id]},
	)
	for center_id in threatened:
		var plan := state.campaign_plan(defender_id, center_id)
		_check(
			plan != null
			and plan.phase == AdministrativeCampaignPlan.Phase.SORTIE,
			"实际到达的防守C满足需求后必须进入SORTIE"
		)
	simulation.free()


func _test_national_reserve_distribution() -> void:
	var state := GameState.new()
	state.generate_grid_world(94131)
	var nation_id := 0
	_configure_single_owner(state, nation_id)
	state.armies.clear()
	state.battles.clear()
	_neutralize_diplomacy(state)
	var centers: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		centers.append(int(center_value))
	EquivariantOrder.sort_city_ids(centers, state, nation_id)
	centers = centers.slice(0, mini(4, centers.size()))
	_check(centers.size() == 4, "预备队夹具必须有四个州治")
	if centers.size() < 4:
		return
	for index in range(12):
		state.armies.append(_army(300 + index, nation_id, centers[0]))
	var simulation := Simulation.new()
	simulation.setup(state)
	var view := AiWorldView.build(state, nation_id)
	var defense_plan := CityDefensePlan.build(
		view, StrategicMapSnapshot.build(view), ThreatField.build(view)
	)
	simulation._balance_national_reserves(nation_id, defense_plan)
	var planned_counts := {}
	for center_id in centers:
		planned_counts[center_id] = 0
	for army in state.armies:
		if army.owner_nation != nation_id:
			continue
		var destination := (
			army.ai_target_city
			if army.ai_target_city >= 0
			else state.administrative_center_of(army.location_city)
		)
		if planned_counts.has(destination):
			planned_counts[destination] = int(planned_counts[destination]) + 1
	var minimum := 999999
	var maximum := -1
	for center_id in centers:
		minimum = mini(minimum, int(planned_counts[center_id]))
		maximum = maxi(maximum, int(planned_counts[center_id]))
	_check(maximum - minimum <= 1, "十二支预备军在四州间应稳定为3/3/3/3")
	for army in state.armies:
		_check(
			army.ai_action != ActionCandidate.Kind.MERGE,
			"独立满编主战军不得收到跨城合并命令"
		)
	simulation.free()


func _configure_single_owner(state: GameState, nation_id: int) -> void:
	for city in state.cities:
		if city.politically_active and not city.is_dock:
			city.owner_nation = nation_id
	state.ownership_revision += 1
	state.nations[nation_id].capital_city_id = int(
		state.administrative_center_city_ids[0]
	)


func _neutralize_diplomacy(state: GameState) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)


func _army(id: int, owner_id: int, city_id: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner_id
	army.size = GameState.INITIAL_HEAVY_ARMY_SIZE
	army.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	return army


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
