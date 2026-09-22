extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94101)
	var valid := true
	var center_id := -1
	for center_value in state.administrative_center_city_ids:
		var candidate := int(center_value)
		if state.administrative_members(candidate).size() > 1:
			center_id = candidate
			break
	valid = valid and center_id >= 0
	for city in state.cities:
		if city.is_dock:
			valid = valid and state.city_garrison_capacity(city.id) == 0
			continue
		if state.is_zhou_city(city.id):
			valid = valid and city.garrison_manpower == 15000
			valid = valid and state.city_garrison_capacity(city.id) == 15000
		else:
			valid = valid and city.garrison_manpower == 0
			valid = valid and state.city_garrison_capacity(city.id) == 0
	if center_id >= 0:
		var center := state.cities[center_id]
		var defender := center.owner_nation
		var attacker := (defender + 1) % state.nations.size()
		state.set_diplomatic_relation(
			attacker, defender, GameState.DiplomaticRelation.WAR
		)
		var members := state.administrative_members(center_id)
		var fu_ids: Array[int] = []
		for member_id in members:
			if member_id != center_id:
				fu_ids.append(member_id)
				state.cities[member_id].owner_nation = defender
		valid = valid and is_equal_approx(
			state.administrative_campaign_control_share(attacker, center_id),
			0.0
		)
		valid = valid and state.campaign_siege_requirement(
			attacker, center_id
		) == 45000
		var captured := ceili(float(fu_ids.size()) * 0.5)
		for index in range(captured):
			state.cities[fu_ids[index]].owner_nation = attacker
		var expected_share := float(captured) / float(fu_ids.size())
		valid = valid and is_equal_approx(
			state.administrative_campaign_control_share(attacker, center_id),
			expected_share
		)
		for fu_id in fu_ids:
			state.cities[fu_id].owner_nation = attacker
		valid = valid and state.campaign_siege_requirement(
			attacker, center_id
		) == 15000
		state.armies.clear()
		var relief := Army.new()
		relief.id = 9901
		relief.owner_nation = defender
		relief.size = 12000
		relief.max_size = 15000
		relief.location_city = center_id
		relief.move_from = center_id
		relief.state = Army.State.IDLE
		state.armies.append(relief)
		valid = valid and state.campaign_reinforcement_threat(
			attacker, center_id
		) == 12000
		relief.state = Army.State.RECOVERING
		valid = valid and state.campaign_reinforcement_threat(
			attacker, center_id
		) == 0
		relief.state = Army.State.IDLE
		var outside_city := -1
		for city in state.cities:
			if (
				not city.is_dock
				and state.administrative_center_of(city.id) != center_id
			):
				outside_city = city.id
				break
		valid = valid and outside_city >= 0
		if outside_city >= 0:
			relief.location_city = outside_city
			relief.move_from = outside_city
			relief.move_to = -1
			relief.on_edge = false
			valid = valid and state.campaign_reinforcement_threat(
				attacker, center_id
			) == 0
			relief.move_to = fu_ids[0]
			relief.move_progress = 0.25
			relief.on_edge = true
			valid = valid and state.campaign_reinforcement_threat(
				attacker, center_id
			) == 12000
			relief.move_from = center_id
			relief.move_to = fu_ids[0]
			valid = valid and state.campaign_reinforcement_threat(
				attacker, center_id
			) == 12000
			relief.state = Army.State.RETREATING
			valid = valid and state.campaign_reinforcement_threat(
				attacker, center_id
			) == 0
			relief.state = Army.State.IDLE
		var neutral_id := (defender + 2) % state.nations.size()
		if neutral_id not in [attacker, defender]:
			state.set_diplomatic_relation(
				attacker, neutral_id, GameState.DiplomaticRelation.NEUTRAL
			)
			var neutral := Army.new()
			neutral.id = 9902
			neutral.owner_nation = neutral_id
			neutral.size = 15000
			neutral.max_size = 15000
			neutral.location_city = center_id
			neutral.move_from = center_id
			neutral.state = Army.State.IDLE
			state.armies.append(neutral)
			valid = valid and state.campaign_reinforcement_threat(
				attacker, center_id
			) == 12000
	if center_id >= 0:
		var monthly_center := state.cities[center_id]
		var monthly_owner := state.nations[monthly_center.owner_nation]
		monthly_center.garrison_manpower = 10000
		monthly_owner.manpower_pool = 1000
		valid = valid and state.reinforce_city_garrisons_monthly() >= 1000
		valid = valid and monthly_center.garrison_manpower == 11000
		valid = valid and monthly_owner.manpower_pool == 0
		monthly_owner.manpower_pool = 5000
		state.reinforce_city_garrisons_monthly()
		valid = valid and monthly_center.garrison_manpower == 12500
		valid = valid and monthly_owner.manpower_pool == 3500
	var template := MapDefinition.from_state(state)
	valid = valid and int(template.get("version", -1)) == 6
	valid = valid and MapDefinition.validate(template).is_empty()
	for record_value in template.get("cities", []):
		var record: Dictionary = record_value
		valid = valid and not record.has("garrison_defense_base")
		valid = valid and not record.has("garrison_manpower")
	var native_snapshot := NativeSnapshotBuilder.build(state)
	valid = valid and int(native_snapshot.get("garrison_revision", -1)) >= 0
	var expected_garrisons := PackedInt32Array()
	for city in state.cities:
		expected_garrisons.append(city.garrison_manpower)
	valid = valid and (
		(native_snapshot["cities"] as Dictionary)["garrison_manpower"]
			== expected_garrisons
	)
	if center_id >= 0:
		var combat_state := GameState.new()
		combat_state.generate_grid_world(94102)
		var combat_center := int(combat_state.administrative_center_city_ids[0])
		var target := combat_state.cities[combat_center]
		var attacker_owner := (target.owner_nation + 1) % combat_state.nations.size()
		var neighbor := int(combat_state.neighbors(combat_center)[0])
		var edge := combat_state.edge_of(neighbor, combat_center)
		combat_state.armies.clear()
		combat_state.battles.clear()
		var attacker := Army.new()
		attacker.id = 9001
		attacker.owner_nation = attacker_owner
		attacker.size = 45000
		attacker.max_size = 45000
		attacker.attack = 10
		attacker.defense = 10
		attacker.morale = 2.0
		attacker.max_morale = 2.0
		attacker.location_city = neighbor
		attacker.move_from = neighbor
		attacker.move_to = combat_center
		attacker.move_progress = 1.0
		combat_state.armies.append(attacker)
		var sim := Simulation.new()
		sim.setup(combat_state)
		var before := target.garrison_manpower
		sim._start_or_join_siege(attacker, target, edge)
		var siege := sim._siege_battle_of(target)
		valid = valid and siege != null
		valid = valid and not siege.side_b_defends_city
		valid = valid and not siege.uses_field_combat_rules()
		if siege != null:
			sim._advance_siege(siege, 9, 123456)
			valid = valid and target.garrison_manpower < before
			for army in combat_state.armies:
				valid = valid and not army.is_city_garrison
			for army in siege.side_b:
				valid = valid and not army.is_city_garrison
		sim.free()
	if center_id >= 0:
		var capture_state := GameState.new()
		capture_state.generate_grid_world(94105)
		var capture_center := int(capture_state.administrative_center_city_ids[0])
		var capture_city := capture_state.cities[capture_center]
		var old_owner := capture_city.owner_nation
		var new_owner := (old_owner + 1) % capture_state.nations.size()
		capture_city.garrison_manpower = 0
		capture_state.nations[new_owner].manpower_pool = 7000
		var capture_battle := Battle.new()
		capture_battle.city = capture_city
		capture_battle.siege_attacker_nation = new_owner
		capture_battle.siege_claimant_nation = new_owner
		var capture_sim := Simulation.new()
		capture_sim.setup(capture_state)
		capture_sim._complete_siege_capture(capture_battle)
		valid = valid and capture_city.owner_nation == new_owner
		valid = valid and capture_city.garrison_manpower == 7000
		valid = valid and capture_state.nations[new_owner].manpower_pool == 0
		capture_sim.free()
	if valid:
		print("GARRISON_SYSTEM_OK center=%d" % center_id)
		quit(0)
		return
	push_error("GARRISON_SYSTEM_FAILED center=%d" % center_id)
	quit(1)
