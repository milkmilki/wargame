extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(94001)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var region: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if state.cities[center_id].is_capital:
			continue
		var candidate := state.expand_enfeoff_to_administrative_states(
			0, [center_id] as Array[int]
		)
		if not candidate.is_empty():
			region = candidate
			break
	var subject := state.enfeoff(0, region)
	_check(subject > 0, "完整州藩王测试夹具必须分封成功")
	if subject <= 0:
		_finish()
		return
	var enemy := 1 if subject != 1 else 2
	state.set_diplomatic_relation(0, enemy, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(subject, enemy, GameState.DiplomaticRelation.WAR)
	state.uses_heightmap = true
	state.refresh_derived()
	var main := state.create_army(
		subject,
		state.nations[subject].capital_city_id,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	_check(main != null, "藩王必须能建立单重军 MAIN 战团")
	if main == null:
		_finish()
		return
	var group := state.create_battle_group(subject)
	state.assign_army_to_battle_group(main, group.id)
	var view := AiWorldView.build(state, subject)
	var snapshot := StrategicMapSnapshot.build(view)
	var threat := ThreatField.build(view)
	var defense_plan := CityDefensePlan.build(view, snapshot, threat)
	var simulation := Simulation.new()
	simulation.setup(state)
	var assessment := simulation._build_force_structure_assessment(
		view,
		{},
		{}
	)
	_check(
		not assessment.small_nation_survival,
		"和平宗藩参加共同战争后必须使用普通国家军制"
	)
	var foreign_enemy_city := -1
	for city in state.land_cities_of(enemy):
		if state.recognized_owner_of(city.id) != subject:
			foreign_enemy_city = city.id
			break
	_check(foreign_enemy_city >= 0, "测试夹具必须存在非本藩法理敌城")
	_check(
		foreign_enemy_city >= 0
			and defense_plan.can_join_offensive(main, foreign_enemy_city),
		"藩王 MAIN 必须能够参加针对共同敌人的普通攻势"
	)
	var military_contexts := {
		subject: {
			"view": view,
			"threat": threat,
			"defense_plan": defense_plan,
		},
	}
	var decision_contexts := {
		subject: {"wars": state.wars_of(subject)},
	}
	await simulation._run_ai_campaign_planning_phase(
		[subject] as Array[int],
		military_contexts,
		decision_contexts,
		{},
		false,
		Time.get_ticks_usec()
	)
	var nation := state.nations[subject]
	_check(
		nation.administrative_campaign_plan != null,
		"参战藩王必须进入与普通国家相同的战役规划阶段"
	)
	simulation.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("VASSAL_REGULAR_MILITARY_AI_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("VASSAL_REGULAR_MILITARY_AI_FAIL: " + failure)
	quit(1)
