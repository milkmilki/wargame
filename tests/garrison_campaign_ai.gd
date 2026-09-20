extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(94103)
	var attacker_id := -1
	var center_id := -1
	for center_value in state.administrative_center_city_ids:
		var center := int(center_value)
		var defender := state.cities[center].owner_nation
		for member_id in state.administrative_members(center):
			if member_id == center:
				continue
			for neighbor in state.neighbors(member_id):
				var owner := state.cities[neighbor].owner_nation
				if owner != defender and state.is_enemy(owner, defender):
					attacker_id = owner
					center_id = center
					break
			if center_id >= 0:
				break
		if center_id >= 0:
			break
	var valid := attacker_id >= 0 and center_id >= 0
	state.armies.clear()
	state.battles.clear()
	var origin := state.nations[attacker_id].capital_city_id if valid else 0
	var defender_army := Army.new()
	defender_army.id = 9099
	defender_army.owner_nation = state.cities[center_id].owner_nation
	defender_army.size = 12000
	defender_army.max_size = 15000
	defender_army.location_city = center_id
	defender_army.move_from = center_id
	defender_army.state = Army.State.IDLE
	state.armies.append(defender_army)
	for index in range(4):
		var army := Army.new()
		army.id = 9100 + index
		army.owner_nation = attacker_id
		army.size = 15000
		army.max_size = 15000
		army.location_city = origin
		army.move_from = origin
		army.state = Army.State.IDLE
		state.armies.append(army)
	var sim := Simulation.new()
	sim.setup(state)
	if valid:
		# A formation is committed only after a campaign order is accepted.  Busy
		# formations must not create paper strength that blocks later reinforcement.
		for army in state.armies:
			army.state = Army.State.MOVING
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		var busy_plan := state.nations[attacker_id].administrative_campaign_plan
		valid = valid and busy_plan.army_assignments.is_empty()
		valid = valid and state.campaign_committed_manpower(
			attacker_id, center_id
		) == 0
		for army in state.armies:
			army.state = Army.State.IDLE
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		var plan := state.nations[attacker_id].administrative_campaign_plan
		valid = valid and plan != null
		var fixed_threat: int = plan.reinforcement_threat
		valid = valid and fixed_threat > 0
		valid = valid and plan.army_assignments.size() == 3
		defender_army.size = 1000
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		valid = valid and plan.reinforcement_threat == fixed_threat
		valid = valid and state.campaign_reinforcement_budget(
			attacker_id, center_id
		) == fixed_threat
		state.road_network_revision += 1
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		valid = valid and plan.reinforcement_threat == 1250
		defender_army.size = 4000
		state.administrative_region_revision += 1
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		valid = valid and plan.reinforcement_threat == 5000
		state.set_diplomatic_relation(
			attacker_id,
			defender_army.owner_nation,
			GameState.DiplomaticRelation.NEUTRAL
		)
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		valid = valid and plan.reinforcement_threat == 0
		state.set_diplomatic_relation(
			attacker_id,
			defender_army.owner_nation,
			GameState.DiplomaticRelation.WAR
		)
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		valid = valid and plan.reinforcement_threat == 5000
		valid = valid and plan.phase == AdministrativeCampaignPlan.Phase.CAPTURE_FU
		valid = valid and plan.tactical_target_city_ids.size() <= 2
		var failed_army_id := int(plan.army_assignments.keys()[0])
		var failed_army: Army = state.armies.filter(
			func(army: Army) -> bool: return army.id == failed_army_id
		)[0]
		var failed_target := int(plan.army_assignments[failed_army_id])
		var failed_order := ActionCandidate.make(
			ActionCandidate.Kind.ATTACK,
			2000.0,
			"test rejected campaign command",
			failed_target
		)
		failed_army.state = Army.State.MOVING
		sim._commit_ordinary_ai_intent(AiCommandIntent.make(
			failed_army, failed_order, 0, [] as Array[int], false
		))
		valid = valid and not plan.army_assignments.has(failed_army_id)
		failed_army.state = Army.State.IDLE
		var expected_committed := 0
		for army in state.armies:
			if plan.army_assignments.has(army.id):
				expected_committed += army.size
		valid = valid and state.campaign_committed_manpower(
			attacker_id, center_id
		) == expected_committed
		defender_army.size = 0
		state.road_network_revision += 1
		for member_id in state.administrative_members(center_id):
			if member_id != center_id:
				state.cities[member_id].owner_nation = attacker_id
		state.ownership_revision += 1
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		valid = valid and plan.phase == AdministrativeCampaignPlan.Phase.ASSAULT_CENTER
		valid = valid and plan.tactical_target_city_ids == [center_id]
		for army in state.armies:
			if plan.army_assignments.has(army.id):
				army.size = 0
		state.day = 10
		sim._manage_administrative_campaign(attacker_id, center_id, null, null)
		valid = valid and plan.failed_until_day == 70
		var alternate_center := -1
		for center_value in state.administrative_center_city_ids:
			var candidate_center := int(center_value)
			if candidate_center != center_id:
				alternate_center = candidate_center
				break
		valid = valid and alternate_center >= 0
		if alternate_center >= 0:
			sim._manage_administrative_campaign(
				attacker_id, alternate_center, null, null
			)
			var replacement_plan := state.nations[
				attacker_id
			].administrative_campaign_plan
			valid = valid and replacement_plan != plan
			valid = valid and replacement_plan.center_city_id == alternate_center
			valid = valid and replacement_plan.reinforcement_threat >= 0
	sim.free()
	if valid:
		print("GARRISON_CAMPAIGN_AI_OK center=%d attacker=%d" % [
			center_id, attacker_id,
		])
		quit(0)
		return
	push_error("GARRISON_CAMPAIGN_AI_FAILED center=%d attacker=%d" % [
		center_id, attacker_id,
	])
	quit(1)
