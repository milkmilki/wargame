extends SceneTree

const Chain = preload("res://tests/succession_chain.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func fixture() -> Dictionary:
	var state: GameState = Chain.fixture()
	var prince := state.nations[0].prince_person_ids[1]
	PrincePolitics.person(state, 0, prince).archetype = RulerProfile.DIPLOMAT
	var army := state.create_army(0, 0, 15000)
	army.political_person_id = prince
	var sim := Simulation.new()
	sim.setup(state)
	return {"state": state, "prince": prince, "army": army, "sim": sim}

func run() -> void:
	var x := fixture()
	var state: GameState = x.state
	var proposal := SuccessionRules.proposal(state, 0, x.prince)
	check(not proposal.is_empty(), "offensive_ban_not_inherited")
	check(int(proposal.R) == 1000, "post_defection_R")
	var remote := state.create_army(0, 2, 15000)
	remote.political_person_id = state.nations[0].crown_prince_person_id
	state.administrative_center_by_city[2] = 2
	state.administrative_center_city_ids.append(2)
	state.administrative_region_revision += 1
	state.refresh_derived()
	proposal = SuccessionRules.proposal(state, 0, x.prince)
	check(int(proposal.V) == 0, "remote_crown_excluded")
	check(int(proposal.R) == 500, "single_fu_bonus")
	state.edge_of(0, 1).max_manpower = 0
	state.road_network_revision += 1
	check(SuccessionRules.proposal(state, 0, x.prince).is_empty(), "broken_route_rejected")
	x.sim.free()
	x = fixture()
	state = x.state
	var blocker := state.create_army(0, 1, 1000)
	blocker.political_person_id = -1
	var other := state.create_army(0, 2, 1000)
	other.political_person_id = -1
	check(SuccessionRules.proposal(state, 0, x.prince).is_empty(), "other_group_camp_rejected")
	state.administrative_center_by_city = PackedInt32Array([0, 1, 2])
	state.administrative_center_city_ids = [0, 1, 2] as Array[int]
	state.administrative_region_revision += 1
	state.refresh_derived()
	check(SuccessionRules.proposal(state, 0, x.prince).is_empty(), "no_fu_no_preparation")
	x.sim.free()
	for reason in ["expired", "capital", "dead", "war"]:
		x = fixture()
		state = x.state
		check(SuccessionRules.begin_preparation(state, 0, x.prince), "begin_" + reason)
		var conflict: SuccessionConflict = state.succession_conflicts[0]
		x.sim._plan_succession_conflicts()
		check(x.army.state == Army.State.MOVING and x.army.ai_target_city == conflict.camp_city_id, "real_order_" + reason)
		x.sim._advance_movement()
		var edge: bool = x.army.on_edge
		var destination: int = x.army.move_to
		match reason:
			"expired":
				state.day = conflict.started_day + 360
				x.army.size = 1
				x.sim._update_succession_conflicts()
			"capital":
				state.nations[0].capital_city_id = 2
				x.sim._update_succession_conflicts()
			"dead":
				PrincePolitics.person(state, 0, x.prince).alive = false
				x.sim._plan_succession_conflicts()
			"war":
				var enemy := Nation.new()
				enemy.id = 1
				state.nations.append(enemy)
				state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
				x.sim._update_succession_conflicts()
		check(state.succession_conflicts.is_empty() and conflict.war_id < 0, "cancel_not_launch_" + reason)
		check(x.army.on_edge == edge and x.army.move_to == destination, "current_leg_preserved_" + reason)
		check(x.army.ai_target_city == -1 and x.army.path.is_empty() and x.army.political_person_id == x.prince, "orders_released_patron_preserved_" + reason)
		x.sim.free()
	x = fixture()
	state = x.state
	check(SuccessionRules.begin_preparation(state, 0, x.prince), "begin_for_accession")
	var crown := state.nations[0].crown_prince_person_id
	state.day = RulerProfile.succession_due_day(state.nations[0], state.world_seed)
	x.sim._resolve_ruler_successions()
	check(state.succession_conflicts.is_empty() and state.nations[0].ruler_person_id == crown, "preparation_does_not_defer_accession")
	x.sim.free()
	for failure in failures:
		push_error("SUCCESSION_PREPARATION_FAIL: " + failure)
	print("SUCCESSION_PREPARATION: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
