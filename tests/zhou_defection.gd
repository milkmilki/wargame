extends SceneTree
## 举州易帜门禁：州治陷落 → 全州敌方属府向占领方易主（望风归附）、
## 驻府敌军撤退、战役完成；第三方/盟友属府不动；反向夺回对称易帜。

var _failures: Array[String] = []
var _checks: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_zhou_defection_and_army_retreat()
	_test_third_party_and_ally_fu_untouched()
	_test_reverse_defection()
	_finish()


func _attack_context(state: GameState) -> Dictionary:
	var centers: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		centers.append(int(center_value))
	centers.sort_custom(func(a: int, b: int) -> bool:
		return state.administrative_members(a).size() > state.administrative_members(b).size()
	)
	for center_id in centers:
		if state.administrative_members(center_id).size() < 6:
			continue
		var defender_id := state.cities[center_id].owner_nation
		if state.nations[defender_id].capital_city_id == center_id:
			continue
		for member_id in state.administrative_members(center_id):
			if member_id == center_id:
				continue
			for neighbor_id in state.neighbors(member_id):
				if state.administrative_center_of(neighbor_id) == center_id:
					continue
				var attacker_id := state.cities[neighbor_id].owner_nation
				if attacker_id >= 0 and attacker_id != defender_id:
					return {
						"center": center_id,
						"attacker": attacker_id,
						"defender": defender_id,
					}
	return {}


func _neutralize_diplomacy(state: GameState) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)


func _build_state() -> Dictionary:
	var state := GameState.new()
	state.generate_grid_world(94145)
	var context := _attack_context(state)
	if context.is_empty():
		return {}
	var center_id := int(context["center"])
	var attacker_id := int(context["attacker"])
	var defender_id := int(context["defender"])
	_neutralize_diplomacy(state)
	state.set_diplomatic_relation(
		attacker_id, defender_id, GameState.DiplomaticRelation.WAR
	)
	state.set_war_objective(attacker_id, defender_id, center_id, "易帜门禁")
	for city in state.cities:
		if (
			city.politically_active
			and state.administrative_center_of(city.id) != center_id
		):
			city.owner_nation = attacker_id
	for member_id in state.administrative_members(center_id):
		state.cities[member_id].owner_nation = defender_id
	# 守方保留自己的首都，避免州治转移触发迁都而把首都在夹具里挪进本州。
	var defender_capital := state.nations[defender_id].capital_city_id
	if defender_capital >= 0:
		state.cities[defender_capital].owner_nation = defender_id
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	state.armies.clear()
	state.battles.clear()
	state.ownership_revision += 1
	state.refresh_derived()
	return {
		"state": state,
		"center": center_id,
		"attacker": attacker_id,
		"defender": defender_id,
	}


func _army(id: int, owner_id: int, city_id: int, size: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner_id
	army.size = size
	army.max_size = 15000
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	return army


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		push_error("ZHOU_DEFECTION_FAIL: " + failure)
	print("ZHOU_DEFECTION_%s checks=%d" % [
		"OK" if _failures.is_empty() else "FAILED", _checks,
	])
	quit(0 if _failures.is_empty() else 1)


func _test_zhou_defection_and_army_retreat() -> void:
	var fixture := _build_state()
	_check(not fixture.is_empty(), "易帜夹具必须找到大州")
	if fixture.is_empty():
		return
	var state: GameState = fixture["state"]
	var center_id := int(fixture["center"])
	var attacker_id := int(fixture["attacker"])
	var defender_id := int(fixture["defender"])
	var garrison_fu := -1
	for member_id in state.administrative_members(center_id):
		if member_id != center_id:
			garrison_fu = member_id
			break
	var defender_army := _army(971001, defender_id, garrison_fu, 8000)
	state.armies.append(defender_army)
	var captor := _army(971002, attacker_id, center_id, 15000)
	state.armies.append(captor)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._capture_city(captor, state.cities[center_id], attacker_id)
	for member_id in state.administrative_members(center_id):
		_check(
			state.cities[member_id].owner_nation == attacker_id,
			"易帜后属府/州治必须全部归占领方（城%d 主%d）"
				% [member_id, state.cities[member_id].owner_nation]
		)
	_check(
		defender_army.state != Army.State.IDLE
			or defender_army.diplomatic_repatriation,
		"驻府敌军必须离开易帜属府（状态%d 遣返%s）"
			% [defender_army.state, str(defender_army.diplomatic_repatriation)]
	)
	_check(
		sim._administrative_campaign_complete(
			center_id, [defender_id] as Array[int]
		),
		"易帜后战役必须立即满足完成条件"
	)
	sim.free()


func _test_third_party_and_ally_fu_untouched() -> void:
	var fixture := _build_state()
	_check(not fixture.is_empty(), "第三方易帜夹具必须找到大州")
	if fixture.is_empty():
		return
	var state: GameState = fixture["state"]
	var center_id := int(fixture["center"])
	var attacker_id := int(fixture["attacker"])
	var defender_id := int(fixture["defender"])
	var neutral_id := -1
	var ally_id := -1
	for nation in state.nations:
		if neutral_id < 0 and nation.id not in [attacker_id, defender_id]:
			neutral_id = nation.id
		elif ally_id < 0 and nation.id not in [attacker_id, defender_id, neutral_id]:
			ally_id = nation.id
			break
	state.set_diplomatic_relation(
		attacker_id, ally_id, GameState.DiplomaticRelation.ALLIED
	)
	var members: Array[int] = state.administrative_members(center_id)
	var neutral_fu := int(members[1])
	var ally_fu := int(members[2])
	state.cities[neutral_fu].owner_nation = neutral_id
	state.cities[ally_fu].owner_nation = ally_id
	state.recognized_city_owners[neutral_fu] = neutral_id
	state.recognized_city_owners[ally_fu] = ally_id
	state.ownership_revision += 1
	var captor := _army(971101, attacker_id, center_id, 15000)
	state.armies.append(captor)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._capture_city(captor, state.cities[center_id], attacker_id)
	_check(
		state.cities[neutral_fu].owner_nation == neutral_id,
		"中立第三方持有的属府不得易帜"
	)
	_check(
		state.cities[ally_fu].owner_nation == ally_id,
		"盟友持有的属府不得易帜"
	)
	_check(
		state.cities[center_id].owner_nation == attacker_id,
		"州治本身必须被占领"
	)
	sim.free()


func _test_reverse_defection() -> void:
	var fixture := _build_state()
	_check(not fixture.is_empty(), "反向易帜夹具必须找到大州")
	if fixture.is_empty():
		return
	var state: GameState = fixture["state"]
	var center_id := int(fixture["center"])
	var attacker_id := int(fixture["attacker"])
	var defender_id := int(fixture["defender"])
	var captor := _army(971201, attacker_id, center_id, 15000)
	state.armies.append(captor)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._capture_city(captor, state.cities[center_id], attacker_id)
	for member_id in state.administrative_members(center_id):
		_check(
			state.cities[member_id].owner_nation == attacker_id,
			"正向易帜必须完成（城%d）" % member_id
		)
	var recaptor := _army(971202, defender_id, center_id, 15000)
	state.armies.append(recaptor)
	sim._capture_city(recaptor, state.cities[center_id], defender_id)
	for member_id in state.administrative_members(center_id):
		_check(
			state.cities[member_id].owner_nation == defender_id,
			"州治被夺回后属府必须对称易帜回守方（城%d 主%d）"
				% [member_id, state.cities[member_id].owner_nation]
		)
	sim.free()
