extends SceneTree
## Same-day frontline refresh regression:
## 1) repeated same-day captures dedupe dirty nations into one batch;
## 2) stale old-owner frontier assignments are cleared and new owner gets
##    refreshed LINE deployment in the same flush;
## 3) non-LINE campaign/battle-group metadata remains unchanged;
## 4) dirty set clears while _ai_forced_nations intentionally persists for the
##    next-day full pass; command commit still respects movement capacity.

const LIGHT_SIZE := GameState.INITIAL_LIGHT_ARMY_SIZE
const HEAVY_SIZE := GameState.INITIAL_HEAVY_ARMY_SIZE

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_same_day_frontline_refresh()
	_verify_invalid_or_dead_owners_ignored()
	if _failed:
		quit(1)
	else:
		print("verdict=FRONTLINE_CAPTURE_REFRESH_OK")
		quit()


func _verify_same_day_frontline_refresh() -> void:
	var fixture := _make_refresh_fixture()
	var state: GameState = fixture["state"]
	var sim: Simulation = fixture["simulation"]
	var old_owner: int = fixture["old_owner"]
	var new_owner: int = fixture["new_owner"]
	var first_capture_city: int = fixture["first_capture_city"]
	var second_capture_city: int = fixture["second_capture_city"]
	var old_line: Army = fixture["old_line"]
	var new_line: Army = fixture["new_line"]
	var locked_line: Army = fixture["locked_line"]
	var main_army: Army = fixture["main_army"]
	var target_group: BattleGroup = fixture["main_group"]
	var old_sector_city: int = fixture["old_sector_city"]

	var before_preparation := state.nations[new_owner].campaign_preparation_assignments.duplicate(true)
	var before_attack := state.nations[old_owner].campaign_attack_assignments.duplicate(true)
	var before_group_count := state.nations[new_owner].battle_groups.size()
	var before_group_members := state.battle_group_members(new_owner, target_group.id, false).size()
	var before_main_group_id := main_army.battle_group_id
	var before_main_location := main_army.location_city

	sim._force_ai_replan_for_capture(old_owner, new_owner, first_capture_city)
	sim._force_ai_replan_for_capture(old_owner, new_owner, second_capture_city)
	var dirty_before_flush := sim._frontline_dirty_nations.duplicate(true)
	var forced_before_flush := sim._ai_forced_nations.duplicate(true)

	_assert(
		dirty_before_flush == {
			old_owner: true,
			new_owner: true,
		},
		"same-day capture dirty set must dedupe repeated owners: %s"
		% str(dirty_before_flush)
	)
	_assert(
		forced_before_flush == dirty_before_flush,
		"capture hook must mark both same-day dirty nations and next-day forced replans"
	)

	sim._flush_same_day_frontline_refresh()

	var old_sector: FrontierDefenseSector = state.nations[old_owner].frontier_defense_sectors.get(old_sector_city)
	var old_plan: CityDefensePlan = sim._ai_defense_plan_cache.get(old_owner)
	var new_plan: CityDefensePlan = sim._ai_defense_plan_cache.get(new_owner)
	var old_candidate := old_plan.candidate_for(old_line, ArmyCoordinator.new()) if old_plan != null else null
	var new_candidate := new_plan.candidate_for(new_line, ArmyCoordinator.new()) if new_plan != null else null

	_assert(
		sim.frontline_refresh_batch_total == 1
			and sim.frontline_refresh_nation_total == 2
			and sim.frontline_refresh_build_total == 2,
		"same-day refresh must execute exactly one batch and one build per dirty nation"
	)
	_assert(
		sim._frontline_dirty_nations.is_empty(),
		"dirty set must be cleared after same-day frontline refresh"
	)
	_assert(
		sim._ai_forced_nations == forced_before_flush,
		"same-day flush must intentionally leave _ai_forced_nations for next-day full AI"
	)
	_assert(
		old_plan != null
			and old_line.line_assignment_city != first_capture_city
			and int(old_plan.assigned_city_by_army.get(old_line.id, -1)) != first_capture_city
			and (old_sector == null or old_sector.assigned_army_at(0) != old_line.id)
			and (
				old_candidate == null
				or old_candidate.target_city != first_capture_city
				or old_candidate.kind == ActionCandidate.Kind.RETREAT
			),
		(
			"old owner stale captured-sector assignment must clear after controller loss: "
			+ "line_assignment=%d plan_assignment=%d sector0=%d candidate=%s"
		) % [
			old_line.line_assignment_city,
			int(old_plan.assigned_city_by_army.get(old_line.id, -1))
				if old_plan != null
				else -1,
			old_sector.assigned_army_at(0)
				if old_sector != null
				else -1,
			"null"
				if old_candidate == null
				else "kind=%d target=%d" % [
					old_candidate.kind,
					old_candidate.target_city,
				],
		]
	)
	_assert(
		new_plan != null
			and new_plan.assigned_city_by_army.has(new_line.id)
			and new_line.line_assignment_city == int(new_plan.assigned_city_by_army.get(new_line.id, -1))
			and new_line.ai_action in [
				ActionCandidate.Kind.HOLD,
				ActionCandidate.Kind.REINFORCE,
				ActionCandidate.Kind.RETREAT,
			]
			and new_line.defensive_deployment_until_day > state.day,
		(
			"new owner LINE must get current same-day sector assignment and candidate: "
			+ "assigned=%d line_assignment=%d ai_action=%d deploy_until=%d candidate=%s"
		) % [
			int(new_plan.assigned_city_by_army.get(new_line.id, -1))
				if new_plan != null
				else -1,
			new_line.line_assignment_city,
			new_line.ai_action,
			new_line.defensive_deployment_until_day,
			"null"
				if new_candidate == null
				else "kind=%d target=%d" % [
					new_candidate.kind,
					new_candidate.target_city,
				],
		]
	)
	_assert(
		state.nations[new_owner].campaign_preparation_assignments == before_preparation
			and state.nations[old_owner].campaign_attack_assignments == before_attack
			and main_army.battle_group_id == before_main_group_id
			and main_army.location_city == before_main_location
			and state.nations[new_owner].battle_groups.size() == before_group_count
			and state.battle_group_members(new_owner, target_group.id, false).size() == before_group_members,
		"same-day flush must not alter campaign preparation/attack assignments or battle groups"
	)
	_assert(
		sim.ai_last_command_commit_failures == 0,
		"same-day flush must not violate command capacity"
	)

	sim.free()


func _verify_invalid_or_dead_owners_ignored() -> void:
	var state := _make_base_state()
	for city in state.cities:
		if city.owner_nation == 1:
			city.owner_nation = 0
	state.refresh_derived()
	var sim := Simulation.new()
	sim.setup(state)
	sim._force_ai_replan_for_capture(1, -1, -1)
	_assert(
		sim._frontline_dirty_nations.is_empty()
			and sim._ai_forced_nations.is_empty(),
		(
			"dead or invalid capture owners must not enter same-day dirty/forced sets: "
			+ "dirty=%s forced=%s"
		) % [
			str(sim._frontline_dirty_nations),
			str(sim._ai_forced_nations),
		]
	)
	sim.free()


func _make_refresh_fixture() -> Dictionary:
	var state := _make_base_state()
	var old_owner := 0
	var new_owner := 1
	var first_capture_city := -1
	var second_capture_city := -1
	var old_sector_city := -1

	var old_line := state.create_army(old_owner, 18, LIGHT_SIZE, LIGHT_SIZE)
	var old_locked := state.create_army(old_owner, 18, LIGHT_SIZE, LIGHT_SIZE)
	var new_line := state.create_army(new_owner, 25, LIGHT_SIZE, LIGHT_SIZE)
	var main_army := state.create_army(new_owner, 25, HEAVY_SIZE, HEAVY_SIZE)
	_assert(
		old_line != null and old_locked != null and new_line != null and main_army != null,
		"fixture armies must be created successfully"
	)
	old_line.location_city = 18
	old_line.move_from = 18
	old_locked.location_city = 18
	old_locked.move_from = 18
	new_line.location_city = 25
	new_line.move_from = 25
	main_army.location_city = 25
	main_army.move_from = 25

	var main_group := state.create_battle_group(new_owner)
	_assert(
		main_group != null and state.assign_army_to_battle_group(main_army, main_group.id),
		"fixture main army must enter a battle group"
	)

	var old_view := AiWorldView.build(state, old_owner)
	var old_plan := CityDefensePlan.build(
		old_view,
		StrategicMapSnapshot.build(old_view),
		ThreatField.build(old_view)
	)
	_assert(
		old_plan.assigned_city_by_army.has(old_line.id),
		"fixture old owner must have a seeded frontline assignment"
	)
	old_sector_city = old_line.line_assignment_city
	first_capture_city = old_sector_city
	for candidate_city in [9, 10, 17, 18]:
		if candidate_city != first_capture_city:
			second_capture_city = candidate_city
			break
	state.nations[old_owner].campaign_attack_assignments[
		old_locked.id
	] = second_capture_city
	old_locked.ai_action = ActionCandidate.Kind.HOLD
	old_locked.ai_target_city = second_capture_city
	_assert(
		old_line.line_assignment_city == old_sector_city,
		"fixture old LINE must be assigned to the captured sector"
	)
	_assert(
		state.nations[old_owner].frontier_defense_sectors.has(old_sector_city),
		"fixture old owner must have frontier sector before capture"
	)

	state.cities[first_capture_city].owner_nation = new_owner
	state.cities[second_capture_city].owner_nation = new_owner
	state.ownership_revision += 1

	var sim := Simulation.new()
	sim.setup(state)
	return {
		"state": state,
		"simulation": sim,
		"old_owner": old_owner,
		"new_owner": new_owner,
		"first_capture_city": first_capture_city,
		"second_capture_city": second_capture_city,
		"old_sector_city": old_sector_city,
		"old_line": old_line,
		"locked_line": old_locked,
		"new_line": new_line,
		"main_army": main_army,
		"main_group": main_group,
	}


func _make_base_state() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(7005)
	state.uses_heightmap = true
	state.armies.clear()
	for city in state.cities:
		city.owner_nation = 1
		city.is_capital = false
		city.has_warehouse = false
		city.is_food_hub = false
		city.is_manpower_hub = false
		city.is_dock = false
		city.fort_strength_max = 0
	for city_id in [9, 10, 17, 18, 25]:
		state.cities[city_id].owner_nation = 0
	state.cities[25].owner_nation = 1
	state.cities[25].fort_strength_max = 30
	state.nations[0].capital_city_id = 18
	state.nations[1].capital_city_id = 25
	state.nations[0].battle_groups.clear()
	state.nations[0].next_battle_group_id = 0
	state.nations[1].battle_groups.clear()
	state.nations[1].next_battle_group_id = 0
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	return state


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
