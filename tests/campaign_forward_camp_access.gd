extends SceneTree
const Direct = preload("res://tests/direct_center_camp.gd")
var checks := 0
var failures: Array[String] = []
var scenario := ""
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(scenario + ": " + label)
func fixture(reverse: bool = false, chain: bool = false, stale_entry: bool = false) -> Dictionary:
	var state := Direct.fixture()
	var actor := 1 if reverse else 0
	var defender := 1 - actor
	var center := 0 if reverse else 3
	var blocker := 1 if reverse else 4
	if reverse:
		state.administrative_center_by_city[6] = 0; state.administrative_center_by_city[7] = 0
		state.administrative_center_city_ids = PackedInt32Array([0, 3, 5])
		if stale_entry:
			# The old front border is closed by a neutral third party; the new
			# entrance below is the only lawful route into the target state.
			state.cities[2].owner_nation = 2; state.recognized_city_owners[2] = 2
	var camp := City.new(); camp.id = state.cities.size(); camp.owner_nation = actor
	camp.occupation_sponsor_nation = actor; camp.map_position = Vector2(.9, .1)
	camp.food_storage = 100000; camp.has_warehouse = true
	state.cities.append(camp); state.adjacency[camp.id] = [] as Array[int]
	state.administrative_center_by_city.append(state.nations[actor].capital_city_id if stale_entry else center)
	state.region_ids.append(0); state.recognized_city_owners.append(defender)
	if not stale_entry:
		state._add_edge(camp.id, blocker); state.edge_of(camp.id, blocker).distance = .1
	else:
		state._add_edge(camp.id, state.nations[actor].capital_city_id)
		state.edge_of(camp.id, state.nations[actor].capital_city_id).distance = .1
	var old_entry := blocker
	var second_blocker := -1
	if chain or stale_entry:
		var next_fu := City.new(); next_fu.id = state.cities.size(); next_fu.owner_nation = defender
		next_fu.map_position = Vector2(.8, .1); next_fu.food_storage = 100000
		state.cities.append(next_fu); state.adjacency[next_fu.id] = [] as Array[int]
		state.administrative_center_by_city.append(center)
		state.region_ids.append(0); state.recognized_city_owners.append(defender)
		if chain: state.edge_of(blocker, center).max_manpower = 0
		var source := camp.id if stale_entry else blocker
		state._add_edge(source, next_fu.id); state.edge_of(source, next_fu.id).distance = .1
		state._add_edge(next_fu.id, center); state.edge_of(next_fu.id, center).distance = .1
		if stale_entry: blocker = next_fu.id
		else: second_blocker = next_fu.id
	state.armies.clear(); state.battles.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED; nation.ruler_traits.clear()
	var troops: Array[Army] = []
	for i in range(3): troops.append(Direct.army(state, actor, camp.id))
	var guard := Direct.army(state, defender, center)
	var front := state.create_campaign_front(state.war_id_between(0, 1), [actor] as Array[int], actor, CoalitionCampaignFront.Mode.OFFENSE, center)
	front.phase = CoalitionCampaignFront.Phase.BREAK_IN if stale_entry else CoalitionCampaignFront.Phase.HOLD_CAMP
	front.camp_city_id = -1 if stale_entry else camp.id; front.staging_city_id = camp.id; front.had_forces = true
	front.entry_city_id = old_entry if stale_entry else -2
	front.tactical_target_city_ids = [old_entry if stale_entry else blocker] as Array[int]
	for army in troops:
		army.campaign_front_id = front.front_id; army.campaign_war_id = front.war_id
		front.army_assignments[army.id] = camp.id
	state.ownership_revision += 1; state.administrative_region_revision += 1; state.refresh_derived()
	var sim := Simulation.new(); root.add_child(sim); sim.setup(state); sim.paused = true
	for army in troops: army.attack = 50.; army.defense = 50.
	return {"state":state,"sim":sim,"front":front,"troops":troops,"guard":guard,"actor":actor,"defender":defender,"camp":camp.id,"blocker":blocker,"old_entry":old_entry,"second_blocker":second_blocker,"center":center}
func test_access(reverse: bool, chain: bool = false, stale_entry: bool = false):
	scenario = "reverse=%s chain=%s stale_entry=%s" % [reverse, chain, stale_entry]
	var x := fixture(reverse, chain, stale_entry); var state: GameState = x.state; var sim: Simulation = x.sim
	var front: CoalitionCampaignFront = x.front
	var initial_grain := state.nations[x.actor].granary_food
	var center_force := preload("res://scripts/simulation/rules/simple_campaign.gd").ready_force(sim, front, x.center, x.camp, ActionCandidate.Kind.ATTACK)
	if stale_entry:
		check(sim._campaign_staging_cities(x.actor, x.old_entry).is_empty() and not sim._campaign_staging_cities(x.actor, x.blocker).is_empty(), "lost entry has no legal staging route while another fu remains reachable")
	else: check(state.campaign_has_forward_camp(front) and center_force.manpower == 0, "occupied forward camp cannot bypass hostile intervening settlement")
	check(sim._campaign_force_at_city(front, x.camp) == 45000 and state.campaign_minimum_launch_requirement(x.actor, x.center) == 13501, "fixture has sufficient healthy force for current strict field gate")
	var war := front.war_id
	sim._manage_administrative_campaign(front)
	check(front.phase == (CoalitionCampaignFront.Phase.BREAK_IN if stale_entry else CoalitionCampaignFront.Phase.RAID_FU) and x.troops.any(func(a): return a.state == Army.State.MOVING and a.ai_target_city == x.blocker), "blocked center route starts actual attack on reachable enemy fu")
	if stale_entry: check(front.entry_city_id == x.blocker and front.camp_city_id < 0, "invalid entrance is replaced without inventing an occupied forward camp")
	else: check(x.troops.any(func(a): return a.location_city == x.camp and a.state == Army.State.IDLE), "existing fu allocation retains a camp guard")
	var marching: Array = x.troops.filter(func(a): return a.state == Army.State.MOVING)
	sim._ai_planned_armies.clear(); sim._manage_administrative_campaign(front)
	check(not marching.is_empty() and marching.all(func(a): return a.ai_target_city == x.blocker and a.state == Army.State.MOVING), "replanning preserves the issued fu attack instead of recalling it to camp")
	var cleared := false; var assaulted := false; var second_attacked := false
	for tick in range(100):
		state.day += 1; sim._ai_planned_armies.clear()
		if state.campaign_front(front.front_id) != null: sim._manage_administrative_campaign(front)
		sim._advance_movement(); sim._resolve_battles(); sim._resolve_eliminated_nation_capitulations()
		cleared = cleared or state.cities[x.blocker].owner_nation == x.actor
		assaulted = assaulted or x.troops.any(func(a): return a.ai_target_city == x.center)
		second_attacked = second_attacked or (chain and x.troops.any(func(a): return a.ai_target_city == x.second_blocker))
		if not state.nations[x.defender].alive: break
	check(cleared and assaulted, "real fu capture opens onward center assault")
	if chain: check(second_attacked, "multiple hostile fu are attacked in sequence before the center instead of leaving a stale camp wait")
	check(not state.nations[x.defender].alive and state.cities[x.center].owner_nation == x.actor, "real forward/reverse siege captures enemy capital and eliminates actual loser")
	ChronicleRules.finalize_pending(state)
	check(not state.is_enemy(0, 1) and x.troops.all(func(a): return a.campaign_war_id != war), "victory releases war and troop bindings")
	# Ordinary capital capitulation keeps its own fiscal contract; it is not
	# annexation. Check actual warehouse access and ownership of captured stock.
	check(state.nations[x.defender].warehouse_city_ids.is_empty() and state.nations[x.defender].granary_food == 0, "actual losing nation releases warehouse and grain access")
	var warehouses := state.warehouse_cities_of(x.actor)
	var grain := 0
	for city in warehouses: grain += city.food_storage
	check(grain > initial_grain and grain == state.nations[x.actor].granary_food and warehouses.all(func(c): return c.owner_nation == x.actor), "capture spoils reach winner's physical warehouses and grain ledger")
	check(state.nations[2].alive, "neutral third party survives the forward/reverse settlement")
	var events := state.chronicle_events.filter(func(e): return e.get("kind", "") == "external_war" and e.get("war_id", -1) == war)
	check(events.size() == 1, "real capture records one final war event")
	var count := state.chronicle_events.size()
	var resources := [state.nations[x.actor].treasury_gold, state.nations[x.actor].manpower_pool, state.nations[x.actor].granary_food]
	sim._resolve_eliminated_nation_capitulations(); ChronicleRules.finalize_pending(state)
	check(state.chronicle_events.size() == count, "repeated cleanup does not duplicate settlement")
	check([state.nations[x.actor].treasury_gold, state.nations[x.actor].manpower_pool, state.nations[x.actor].granary_food] == resources, "repeated cleanup does not settle resources twice")
	sim.free()
func test_buffered_access(reverse: bool):
	scenario = "buffered reverse=%s" % reverse
	var x := fixture(reverse); var sim: Simulation = x.sim
	var ids := {}
	for army in x.state.armies: ids[army.id] = true
	sim._begin_ai_command_collection(ids)
	sim._manage_administrative_campaign(x.front)
	check(not x.troops.any(func(a): return a.state == Army.State.MOVING), "buffered planning waits for the normal movement commit")
	sim._commit_ai_command_collection([0, 1, 2] as Array[int])
	check(sim.ai_last_command_commit_failures == 0 and x.troops.any(func(a): return a.state == Army.State.MOVING and a.ai_target_city == x.blocker), "buffered forward/reverse fu plan commits real legal movement")
	check(x.troops.any(func(a): return a.state == Army.State.IDLE and a.location_city == x.camp), "buffered fu attack preserves the existing camp guard")
	sim.free()
func test_no_legal_entry_regroups(reverse: bool):
	scenario = "no entrance reverse=%s" % reverse
	var x := fixture(reverse, false, true); var sim: Simulation = x.sim; var state: GameState = x.state
	state.cities[x.blocker].owner_nation = 2
	state.edge_of(2, 3).max_manpower = 0
	state.ownership_revision += 1; state.road_network_revision += 1; state.refresh_derived()
	sim._manage_administrative_campaign(x.front)
	check(x.front.entry_city_id == -1 and x.front.phase == CoalitionCampaignFront.Phase.ASSEMBLE, "no legal entrance leaves the obsolete break-in phase and rebuilds its rally")
	state.cities[x.blocker].owner_nation = x.defender
	state.ownership_revision += 1; state.refresh_derived()
	var resumed := false
	for tick in range(40):
		state.day += 1; sim._ai_planned_armies.clear(); sim._manage_administrative_campaign(x.front)
		resumed = resumed or x.troops.any(func(a): return a.state == Army.State.MOVING and a.ai_action == ActionCandidate.Kind.ATTACK and a.ai_target_city == x.blocker)
		sim._advance_movement(); sim._resolve_battles()
		if resumed: break
	check(resumed, "a newly legal entrance invalidates the negative cache and resumes physical movement")
	sim.free()
func test_launched_entry_keeps_cohort(reverse: bool):
	scenario = "launched entrance reverse=%s" % reverse
	var x := fixture(reverse, false, true); var sim: Simulation = x.sim; var state: GameState = x.state
	sim._manage_administrative_campaign(x.front)
	var before: Array = x.troops.map(func(a): return [a.state, a.move_from, a.move_to, a.move_progress, a.ai_target_city, a.path.duplicate()])
	x.guard.size = 60000
	state.cities[x.camp].owner_nation = 2
	state.ownership_revision += 1; state.refresh_derived(); sim._ai_planned_armies.clear()
	check(sim._campaign_staging_cities(x.actor, x.blocker).is_empty(), "launched entry loses its friendly staging border")
	sim._manage_administrative_campaign(x.front)
	check(x.front.phase == CoalitionCampaignFront.Phase.BREAK_IN and x.front.tactical_target_city_ids == [x.blocker], "rear-border loss and higher V do not cancel a committed entry cohort")
	check(before == x.troops.map(func(a): return [a.state, a.move_from, a.move_to, a.move_progress, a.ai_target_city, a.path.duplicate()]), "ongoing march keeps its actual path and progress")
	sim.free()
func test_insufficient_or_recovering():
	scenario = "readiness gate"
	for recovering in [false, true]:
		var x := fixture(); var sim: Simulation = x.sim
		if recovering:
			for a in x.troops: a.state = Army.State.RECOVERING
		else: x.guard.size = 60000
		sim._manage_administrative_campaign(x.front)
		check(x.front.phase == CoalitionCampaignFront.Phase.HOLD_CAMP and not x.troops.any(func(a): return a.ai_action == ActionCandidate.Kind.ATTACK and a.state == Army.State.MOVING), "unready armies retain regrouping and field gate")
		sim.free()
func run():
	for reverse in [false, true]:
		test_access(reverse); test_access(reverse, true); test_access(reverse, false, true); test_buffered_access(reverse)
		test_no_legal_entry_regroups(reverse)
		test_launched_entry_keeps_cohort(reverse)
	test_insufficient_or_recovering()
	for failure in failures: push_error("FORWARD_CAMP_ACCESS_FAIL: " + failure)
	print("FORWARD_CAMP_ACCESS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
