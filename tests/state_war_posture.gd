extends SceneTree


func _field_army(owner: int) -> Army:
	var army := Army.new()
	army.owner_nation = owner
	army.size = 15000
	army.max_size = 15000
	army.attack = 10
	army.defense = 10
	army.morale = 1.0
	army.max_morale = 1.0
	return army


func _holding_side_one_sizes() -> Vector2i:
	var holder := _field_army(0)
	var attacker := _field_army(1)
	var battle := Battle.new()
	battle.kind = Battle.Kind.FIELD
	battle.holding_side = 1
	battle.side_a.append(holder)
	battle.side_b.append(attacker)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77102
	Combat.resolve_round(battle, rng, 0, 77102, 0, Vector2.ONE)
	return Vector2i(holder.size, attacker.size)


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(77101)
	var center_id := -1
	for center_value in state.administrative_center_city_ids:
		var candidate := int(center_value)
		var members := state.administrative_members(candidate)
		if members.is_empty():
			continue
		var owner := state.cities[candidate].owner_nation
		var complete := true
		for member_id in members:
			if state.cities[member_id].owner_nation != owner:
				complete = false
				break
		if complete and not state.cities[candidate].is_capital:
			center_id = candidate
			break
	if center_id < 0:
		push_error("STATE_WAR_POSTURE_FAILED no complete non-capital state")
		quit(1)
		return

	var owner := state.cities[center_id].owner_nation
	var fu := -1
	for member_id in state.administrative_members(center_id):
		if member_id != center_id:
			fu = member_id
			break
	if fu < 0:
		push_error("STATE_WAR_POSTURE_FAILED state has no府 fixture")
		quit(1)
		return
	var expanded := state.expand_enfeoff_to_administrative_states(owner, [fu])
	var expected := state.administrative_members(center_id)
	var valid := expanded.size() == expected.size()
	for member_id in expected:
		valid = valid and expanded.has(member_id)

	var army := Army.new()
	army.owner_nation = owner
	army.max_size = 15000
	army.size = 12000
	army.location_city = center_id
	army.state = Army.State.RECOVERING
	var enemy := (owner + 1) % state.nations.size()
	state.nations[owner].manpower_pool = 5000
	valid = valid and ReinforcementRules.REINFORCE_PER_ARMY_PER_MONTH == 1500
	valid = valid and ReinforcementRules.can_reinforce_army(
		state, army, true, {}
	)
	var refill_plan := ReinforcementPhase._build_plans(
		state, owner, [army], true, true, {}
	)
	valid = valid and int(refill_plan["total_deficit"]) == 1500
	valid = valid and Combat.holding_attack_multiplier(true) == 0.5
	valid = valid and Combat.holding_defense_multiplier(true) == 1.5
	var holding_sizes := _holding_side_one_sizes()
	valid = valid and holding_sizes.x < holding_sizes.y
	var invader := Army.new()
	invader.owner_nation = enemy
	invader.size = 10000
	invader.max_size = 15000
	invader.location_city = fu
	invader.ai_target_city = fu
	state.armies.append(invader)
	valid = valid and state.campaign_field_requirement(owner, center_id) == 12500
	var loser := Army.new()
	loser.owner_nation = owner
	loser.size = 10000
	loser.max_size = 15000
	loser.location_city = center_id
	var winner := Army.new()
	winner.owner_nation = enemy
	winner.size = 10000
	winner.max_size = 15000
	var field := Battle.new()
	field.kind = Battle.Kind.FIELD
	field.side_a = [winner]
	field.side_b = [loser]
	field.winner_side = 1
	var sim := Simulation.new()
	sim.setup(state)
	sim._finish_field_battle(field)
	valid = valid and loser.size == 2000
	sim.free()
	if valid:
		print("STATE_WAR_POSTURE_OK center=%d enemy=%d" % [center_id, enemy])
		quit(0)
		return
	push_error("STATE_WAR_POSTURE_FAILED center=%d" % center_id)
	quit(1)
