extends SceneTree
const Direct = preload("res://tests/direct_center_camp.gd")
const Fixture = preload("res://tests/support/native_runtime_fixture.gd")

var checks := 0
var failures := 0
var frames := 0
var queued_commands := 0

func _initialize() -> void:
	process_frame.connect(func(): frames += 1)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("COALITION_SLICE_FAIL ", label)

func run() -> void:
	var probe := Simulation.new()
	check(probe.has_method("_manage_coalition_campaigns_over_frames"), "planning has a cooperative driver")
	probe.free()
	if failures > 0:
		quit(1)
		return
	for scenario in ["peace", "mobilize", "lost_camp", "reverse", "lost_entry", "reverse_lost_entry"]:
		await compare(scenario)
	check(queued_commands > 0, "equivalence includes executable buffered commands")
	print("COALITION_SLICE_RESULT checks=%d failures=%d queued=%d" % [checks, failures, queued_commands])
	quit(0 if failures == 0 else 1)

func fixture(scenario: String) -> GameState:
	var state := Direct.fixture()
	if scenario == "peace":
		state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
		return state
	if scenario.ends_with("lost_entry"):
		var actor := 1 if scenario.begins_with("reverse") else 0
		var center := 0 if actor == 1 else 3
		if actor == 1:
			state.cities[2].owner_nation = 2
			state.recognized_city_owners[2] = 2
		var entry := City.new(); entry.id = state.cities.size(); entry.owner_nation = 1 - actor
		entry.map_position = Vector2(.7, .1)
		state.cities.append(entry); state.adjacency[entry.id] = [] as Array[int]
		state.administrative_center_by_city.append(center); state.region_ids.append(0)
		state.recognized_city_owners.append(entry.owner_nation)
		var home := state.nations[actor].capital_city_id
		state._add_edge(home, entry.id); state._add_edge(entry.id, center)
		var front := state.create_campaign_front(state.war_id_between(0, 1),
			[actor] as Array[int], actor, CoalitionCampaignFront.Mode.OFFENSE, center)
		front.phase = CoalitionCampaignFront.Phase.BREAK_IN
		front.entry_city_id = 1 if actor == 1 else 4
		front.tactical_target_city_ids = [front.entry_city_id] as Array[int]
		front.staging_city_id = home; front.had_forces = true
		for index in range(3):
			var troop := Direct.army(state, actor, home)
			troop.campaign_front_id = front.front_id; troop.campaign_war_id = front.war_id
			front.army_assignments[troop.id] = home
		Direct.army(state, 1 - actor, center)
		state.ownership_revision += 1; state.administrative_region_revision += 1
		state.refresh_derived()
		return state
	var first := Direct.army(state, 0, 0, 45000)
	Direct.army(state, 0, 1, 45000)
	var defender := Direct.army(state, 1, 3, 45000)
	Direct.army(state, 1, 4, 45000)
	if scenario == "lost_camp":
		var front := Direct.front(state, [first])
		front.camp_city_id = 2
		state.cities[2].owner_nation = 1
		state.ownership_revision += 1
	if scenario == "reverse":
		var front := state.create_campaign_front(state.war_id_between(0, 1),
			[1] as Array[int], 1, CoalitionCampaignFront.Mode.OFFENSE, 0)
		front.staging_city_id = 3
		front.camp_city_id = 3
		defender.campaign_front_id = front.front_id
		defender.campaign_war_id = front.war_id
		front.army_assignments[defender.id] = 3
	return state

func compare(scenario: String) -> void:
	var sims: Array[Simulation] = []
	for index in range(2):
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(fixture(scenario))
		sim.paused = true
		var ids := {}
		for army in sim.state.armies: ids[army.id] = true
		sim._begin_ai_command_collection(ids)
		sims.append(sim)
	var before_frame := frames
	var changed: bool = sims[0]._manage_coalition_campaigns()
	var sliced: Dictionary = await sims[1]._manage_coalition_campaigns_over_frames(null, Time.get_ticks_usec(), 0)
	check(frames > before_frame, scenario + ": zero budget yields to the tree")
	check(changed == bool(sliced.changed), scenario + ": changed result")
	check(int(sliced.slice_started) > 0, scenario + ": carries the remaining slice clock")
	check(sims[0].state.rng.state == sims[1].state.rng.state, scenario + ": RNG")
	check(var_to_bytes(Fixture.snapshot(sims[0].state)) == var_to_bytes(Fixture.snapshot(sims[1].state)),
		scenario + ": state before command commit")
	check(var_to_bytes(command_rows(sims[0])) == var_to_bytes(command_rows(sims[1])), scenario + ": command order and paths")
	check(var_to_bytes(sims[0]._ai_command_sequence) == var_to_bytes(sims[1]._ai_command_sequence),
		scenario + ": per nation command sequence")
	check(var_to_bytes(sims[0]._coalition_campaign_query_cache.mobilization_claims)
		== var_to_bytes(sims[1]._coalition_campaign_query_cache.mobilization_claims), scenario + ": reservations")
	check(var_to_bytes(sims[0]._coalition_campaign_next_due_day) == var_to_bytes(sims[1]._coalition_campaign_next_due_day),
		scenario + ": next due days")
	check(sims[0]._coalition_campaign_wake_day == sims[1]._coalition_campaign_wake_day, scenario + ": wake day")
	queued_commands += sims[1]._ai_command_buffer.size()
	for sim in sims:
		check(sim._collect_ai_commands, scenario + ": collection remains open until commit")
		check(sim._coalition_armies_by_id.is_empty() and sim._coalition_armies_by_nation.is_empty()
			and sim._coalition_defense_activity.is_empty(), scenario + ": temporary planning indexes released")
		sim._commit_ai_command_collection([0, 1, 2] as Array[int])
		check(sim.ai_last_command_commit_failures == 0, scenario + ": real command commit")
	check(var_to_bytes(Fixture.snapshot(sims[0].state)) == var_to_bytes(Fixture.snapshot(sims[1].state)),
		scenario + ": state after command commit")
	if scenario.ends_with("lost_entry"):
		check(sims[0].state.armies.any(func(a): return a.state == Army.State.MOVING and a.ai_action == ActionCandidate.Kind.ATTACK and a.ai_target_city == 8),
			scenario + ": replacement entrance starts actual movement after commit")
	for sim in sims: sim.free()

func command_rows(sim: Simulation) -> Array:
	var rows := []
	for intent in sim._ai_command_buffer:
		var candidate: ActionCandidate = intent.candidate
		rows.append([intent.nation_id, intent.sequence, intent.army.id,
			candidate.kind, candidate.target_city, candidate.target_edge_a, candidate.target_edge_b,
			candidate.score, candidate.minimum_commit_days, candidate.reason, candidate.defensive_deployment,
			candidate.reserve_station_city, intent.prepared_path, intent.path_prevalidated])
	return rows
