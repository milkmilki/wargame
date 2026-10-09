extends SceneTree
## 共享进攻战线门禁：动态 V、集团分兵与命令失败不得破坏战略绑定。


func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(94103)
	# This test starts a new offensive campaign. Remove the generated map's
	# pre-existing occupied Fu, which now correctly require separate defense.
	for city in state.cities:
		var center := state.administrative_center_of(city.id)
		if center >= 0:
			city.owner_nation = state.cities[center].owner_nation
	state.ownership_revision += 1
	var target := _find_border_target(state)
	if target.is_empty():
		_finish(false)
		return
	var attacker_id := int(target["attacker"])
	var defender_id := int(target["defender"])
	var center_id := int(target["center"])
	var war_id := state.set_war_objective(
		attacker_id, defender_id, center_id, "共享州战线门禁"
	)
	state.armies.clear()
	state.battles.clear()
	var defender := _army(9099, defender_id, center_id, 12000)
	state.armies.append(defender)
	for index in range(4):
		state.armies.append(_army(
			9100 + index, attacker_id,
			state.nations[attacker_id].capital_city_id, 15000
		))
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._manage_coalition_campaigns()
	var plan := state.campaign_front_for(
		attacker_id, center_id, CoalitionCampaignFront.Mode.OFFENSE, war_id
	)
	var valid := plan != null
	valid = valid and state.campaign_reinforcement_threat(
		attacker_id, center_id
	) == 12000
	valid = valid and plan.army_assignments.size() <= 4
	valid = valid and plan.army_assignments.size() > 0
	if plan != null:
		valid = valid and state.campaign_committed_manpower(attacker_id, center_id) >= mini(
			sim._front_requirement(plan), 60000
		)
	if valid:
		var army_id := int(plan.army_assignments.keys()[0])
		var army := _army_by_id(state, army_id)
		var target_city := int(plan.army_assignments[army_id])
		var before := state.campaign_committed_manpower(attacker_id, center_id)
		army.state = Army.State.MOVING
		sim._commit_ordinary_ai_intent(AiCommandIntent.make(
			army,
			ActionCandidate.make(
				ActionCandidate.Kind.ATTACK, 2000.0,
				"拒绝命令仍保留集团绑定", target_city
			),
			0, [] as Array[int], false
		))
		valid = valid and army.campaign_front_id == plan.front_id
		valid = valid and plan.army_assignments.has(army.id)
		valid = valid and state.campaign_committed_manpower(
			attacker_id, center_id
		) == before
	defender.size = 4000
	valid = valid and state.campaign_reinforcement_threat(
		attacker_id, center_id
	) == 4000
	sim.free()
	_finish(valid)


func _find_border_target(state: GameState) -> Dictionary:
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		var defender_id := state.cities[center_id].owner_nation
		for member_id in state.administrative_members(center_id):
			for neighbor in state.territorial_border_neighbors(member_id):
				var attacker_id := state.cities[neighbor].owner_nation
				if attacker_id != defender_id and state.is_enemy(attacker_id, defender_id):
					return {
						"attacker": attacker_id,
						"defender": defender_id,
						"center": center_id,
					}
	return {}


func _army(id: int, owner_id: int, city_id: int, size: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner_id
	army.size = size
	army.max_size = 15000
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	army.supply_ratio = 1.0
	army.morale = army.max_morale
	return army


func _army_by_id(state: GameState, army_id: int) -> Army:
	for army in state.armies:
		if army.id == army_id:
			return army
	return null


func _finish(valid: bool) -> void:
	print("GARRISON_CAMPAIGN_AI_%s" % ("OK" if valid else "FAILED"))
	quit(0 if valid else 1)
