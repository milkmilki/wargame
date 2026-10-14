extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func fixture(setup_simulation: bool = true) -> Dictionary:
	var state := GameState.new(); state._reset_world(12684)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 3, false)
	state.day = 100
	for id in range(8):
		var city := City.new(); city.id = id
		city.owner_nation = [0, 0, 1, 1, 2, -1, 1, 0][id]
		city.map_position = Vector2(id * .1, .5)
		city.food_storage = 1000000; city.food_per_half_year = 100000
		city.gold_per_month = 10000; city.garrison_manpower = 1000
		city.has_warehouse = id in [0, 2, 4]
		if id == 5: city.node_kind = City.NodeKind.TRAFFIC; city.politically_active = false
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
		state.recognized_city_owners.append(1 if id == 1 else city.owner_nation)
		if id == 1: city.occupation_sponsor_nation = 0
		state.region_ids.append(0)
		state.administrative_center_by_city.append([0, 2, 2, 2, 4, -1, 6, 0][id])
	state.administrative_center_city_ids = PackedInt32Array([0, 2, 4, 6])
	state.atlas_layout = {"territorial_pairs":[Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(0,7),Vector2i(7,6)] as Array[Vector2i],"settlement_adjacency":{0:[1,7] as Array[int],1:[0,2] as Array[int],2:[1,3] as Array[int],3:[2] as Array[int],6:[7] as Array[int],7:[0,6] as Array[int]}}
	for row in [[0,1,0],[1,5,1],[5,2,4],[2,3,2],[0,7,0],[7,6,6]]:
		var edge := Edge.new(); edge.city_a = row[0]; edge.city_b = row[1]
		edge.control_city_id = row[2]; edge.max_manpower = 15000; edge.distance = .1
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(row[0],row[1])] = edge
		state.adjacency[row[0]].append(row[1]); state.adjacency[row[1]].append(row[0])
	for id in range(3):
		var nation: Nation = state.nations[id]; nation.capital_city_id = [0,2,4][id]
		nation.treasury_gold = 1000000; nation.manpower_pool = 0
		nation.ruler_archetype = RulerProfile.BALANCED; nation.ruler_traits.clear()
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0,1,2,"neutral-route regression")
	var troops: Array[Army] = []
	for id in range(3):
		var army := Army.new(); army.id = id; army.owner_nation = 0
		army.location_city = 1; army.move_from = 1; army.size = 15000
		army.max_size = 15000; army.morale = army.max_morale; army.supply_ratio = 1.
		state.armies.append(army); troops.append(army)
	var front := state.create_campaign_front(state.war_id_between(0,1),[0] as Array[int],0,CoalitionCampaignFront.Mode.OFFENSE,2)
	front.camp_city_id = 1; front.staging_city_id = 1
	front.phase = CoalitionCampaignFront.Phase.HOLD_CAMP; front.had_forces = true
	for army in troops:
		army.campaign_front_id = front.front_id; army.campaign_war_id = front.war_id
		front.army_assignments[army.id] = 1
	state.refresh_derived()
	var sim := Simulation.new(); root.add_child(sim)
	if setup_simulation: sim.setup(state)
	sim.paused = true
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED; nation.ruler_traits.clear()
	return {"state":state,"sim":sim,"front":front,"troops":troops}
func test_reselection():
	var x := fixture(); var state: GameState = x.state; var sim: Simulation = x.sim
	check(DiplomacyAI.staging_cities_for_objective(state,0,2).has(1),"fixture has a territorial border despite neutral road control")
	check(sim._campaign_staging_cities(0,2).is_empty(),"movement correctly blocks neutral jurisdiction")
	check(not sim._campaign_front_has_entry(x.front),"a forward camp and idle troops in the state are not a usable attack route")
	var objective := DiplomacyAI.select_war_objective(state,0,1,{},-1,false,{},false,DiplomacyAI.ObjectiveContext.CAMPAIGN)
	check(int(objective.get("administrative_center_city_id",-1))==6,"campaign selection skips blocked capital and chooses reachable alternative")
	sim._manage_coalition_campaigns()
	check(state.campaign_front(x.front.front_id)==null,"blocked camp retires through shared campaign lifecycle")
	var fronts := state.campaign_fronts.values().filter(func(f): return f.mode==CoalitionCampaignFront.Mode.OFFENSE and not f.retiring)
	check(fronts.all(func(f): return f.center_city_id!=2),"initial declared objective cannot recreate a blocked executor")
	state.day += 10; sim._prepare_coalition_campaign_batch(); sim._manage_coalition_campaigns()
	fronts = state.campaign_fronts.values().filter(func(f): return f.mode==CoalitionCampaignFront.Mode.OFFENSE and not f.retiring)
	check(fronts.any(func(f): return f.center_city_id==6 and not f.army_assignments.is_empty()),"released forces actually bind a reachable battlefield")
	var bindings := {}
	for front in state.campaign_fronts.values():
		for id in front.army_assignments:
			check(not bindings.has(id),"released troops retain at most one execution task")
			bindings[id] = front.front_id
	check(state.relation_between(0,2)==GameState.DiplomaticRelation.NEUTRAL,"repair preserves neutral diplomacy")
	check(state.campaign_offensive_cooldown_until(x.front.war_id,[0] as Array[int])<state.day,"route invalidation does not invent camp defeat or cooldown")
	sim.free()

func test_route_recovery():
	var x := fixture(); var state: GameState = x.state; var sim: Simulation = x.sim
	var cache := {}; var rng_before := state.rng.state
	check(DiplomacyAI.war_staging_cities_for_objective(state,0,2,cache).is_empty(),"negative route result is cached")
	state.edge_of(5,2).control_city_id = 2; state.road_network_revision += 1
	check(DiplomacyAI.war_staging_cities_for_objective(state,0,2,cache).has(1),"road-control recovery invalidates the negative result")
	check(sim._campaign_front_has_entry(x.front),"a real restored route preserves the forward camp")
	check(state.rng.state==rng_before,"route queries consume no simulation random draws")
	state.edge_of(5,2).max_manpower = 0; state.road_network_revision += 1
	check(DiplomacyAI.war_staging_cities_for_objective(state,0,2,cache).is_empty(),"a zero-capacity road remains impassable")
	check(not sim._campaign_front_has_entry(x.front),"a closed road no longer preserves the forward camp")
	sim.free()

func test_physical_commitment(attack: bool):
	var x := fixture(); var state: GameState = x.state; var sim: Simulation = x.sim
	var army: Army = x.troops[0]
	army.state = Army.State.MOVING; army.on_edge = true
	army.move_from = 5 if attack else 1; army.move_to = 2 if attack else 0
	army.move_progress = .25; army.location_city = -1
	army.ai_action = ActionCandidate.Kind.ATTACK if attack else ActionCandidate.Kind.REINFORCE
	army.ai_target_city = 2 if attack else 0; army.path = [army.move_to] as Array[int]
	check(sim._campaign_front_has_entry(x.front)==attack,"only an actual committed attack preserves an otherwise blocked campaign")
	var physical := [army.on_edge,army.move_from,army.move_to,army.move_progress,army.location_city]
	sim._manage_coalition_campaigns()
	check([army.on_edge,army.move_from,army.move_to,army.move_progress,army.location_city]==physical,"replanning preserves the physical leg and progress")
	check((state.campaign_front(x.front.front_id)!=null)==attack,"in-flight reinforcement cannot indefinitely reserve a blocked offensive slot")
	check(state.relation_between(0,2)==GameState.DiplomaticRelation.NEUTRAL,"physical commitment does not grant neutral transit")
	sim.free()

func test_enemy_fu_entry():
	var x := fixture(); var state: GameState = x.state; var sim: Simulation = x.sim
	var edge := Edge.new(); edge.city_a = 1; edge.city_b = 3
	state.edges.append(edge); state.edge_lookup[GameState.edge_key(1,3)] = edge
	edge.control_city_id = 3; edge.max_manpower = 15000; edge.distance = .1
	state.adjacency[1].append(3); state.adjacency[3].append(1); state.road_network_revision += 1
	state.atlas_layout["territorial_pairs"].append(Vector2i(1,3))
	state.atlas_layout["settlement_adjacency"][1].append(3); state.atlas_layout["settlement_adjacency"][3].append(1)
	check(sim._campaign_staging_cities(0,2).is_empty(),"enemy fu still prevents a direct center assault")
	check(sim._campaign_front_has_entry(x.front),"an enemy fu that can be attacked is a valid route-opening operation")
	sim._manage_administrative_campaign(x.front)
	check(x.troops.any(func(a):return a.state==Army.State.MOVING and a.ai_target_city==3 and a.ai_action==ActionCandidate.Kind.ATTACK),"valid forward camp starts a real attack on the accessible enemy fu")
	sim.free()

func test_buffered_reselection():
	var x := fixture(); var state: GameState = x.state; var sim: Simulation = x.sim
	var ids := {}
	for army in state.armies: ids[army.id] = true
	sim._begin_ai_command_collection(ids); sim._manage_coalition_campaigns()
	check(state.campaign_front(x.front.front_id)==null,"command collection also retires the blocked execution task")
	check(x.troops.all(func(a):return not a.on_edge),"replacement orders wait for the normal command commit")
	sim._commit_ai_command_collection([0,1,2] as Array[int])
	check(sim.ai_last_command_commit_failures==0,"replacement commands pass physical route validation at commit")
	check(x.troops.any(func(a):return a.state==Army.State.MOVING and a.ai_target_city in [6,7]),"the replacement battlefield causes real movement after commit")
	check(state.relation_between(0,2)==GameState.DiplomaticRelation.NEUTRAL,"buffered replanning preserves neutral diplomacy")
	sim.free()

func test_neutral_center_enemy_fu(reverse: bool = false):
	var x := fixture(false); var state: GameState = x.state; var sim: Simulation = x.sim
	var actor := 1 if reverse else 0; var defender := 1-actor
	if reverse:
		for city in state.cities:
			if city.owner_nation in [0,1]: city.owner_nation = 1-city.owner_nation
			if city.occupation_sponsor_nation in [0,1]: city.occupation_sponsor_nation = 1-city.occupation_sponsor_nation
		for id in range(state.recognized_city_owners.size()):
			if state.recognized_city_owners[id] in [0,1]: state.recognized_city_owners[id] = 1-state.recognized_city_owners[id]
		for army in x.troops: army.owner_nation = actor
		x.front.anchor_nation_id = actor; x.front.participant_nation_ids = [actor] as Array[int]
		state.set_war_objective(0,1,0,"original attacker targets defender's real capital")
	state.cities[2].owner_nation = 2; state.recognized_city_owners[2] = 2
	# As in the real Xing country, the hostile independent capital Fu is the
	# losing country's only territory; the neutral seat is a separate sovereign.
	state.cities[6].owner_nation = actor; state.recognized_city_owners[6] = actor
	state.nations[actor].capital_city_id = 0; state.nations[defender].capital_city_id = 3
	state.cities[3].has_warehouse = true
	for id in [0,3,4]: state.cities[id].is_capital = true
	var edge := Edge.new(); edge.city_a = 1; edge.city_b = 3
	edge.control_city_id = 3; edge.max_manpower = 15000; edge.distance = .1
	state.edges.append(edge); state.edge_lookup[GameState.edge_key(1,3)] = edge
	state.adjacency[1].append(3); state.adjacency[3].append(1)
	state.atlas_layout["territorial_pairs"].append(Vector2i(1,3))
	state.atlas_layout["settlement_adjacency"][1].append(3); state.atlas_layout["settlement_adjacency"][3].append(1)
	state.road_network_revision += 1
	state.ownership_revision += 1; state.refresh_derived()
	sim.setup(state)
	var components := state.coalition_campaign_components()
	var record := state.StateCampaigns.adopt_offense(state,x.front,components)
	check(record!=null and record.defender_members==[defender],"neutral seat's enemy fu determines the actual defending side")
	state.StateCampaigns.reconcile(state,components,state.campaign_defense_activity_index())
	check(record.lifecycle==StateCampaign.Lifecycle.ACTIVE and not x.front.retiring,"preexisting neutral seat does not cancel a legal campaign against its enemy fu")
	check(record.visible_to(actor) and record.visible_to(defender),"both actual hostile sides retain the shared record")
	check(state.cities[2].owner_nation==2 and state.relation_between(actor,2)==GameState.DiplomaticRelation.NEUTRAL,"enemy-fu campaign keeps neutral seat ownership and diplomacy")
	var neutral_stock := state.cities[2].food_storage
	var initial_grain := state.nations[actor].granary_food
	for army in x.troops: army.attack=50.; army.defense=50.
	var attacked := false; var war: int = x.front.war_id
	for tick in range(120):
		state.day += 1; sim._ai_planned_armies.clear()
		if state.campaign_front(x.front.front_id)!=null: sim._manage_administrative_campaign(x.front)
		attacked = attacked or x.troops.any(func(a):return a.ai_action==ActionCandidate.Kind.ATTACK and a.ai_target_city==3 and a.state==Army.State.MOVING)
		sim._advance_movement(); sim._resolve_battles(); sim._resolve_eliminated_nation_capitulations()
		if not state.nations[defender].alive: break
		state.StateCampaigns.reconcile(state,state.coalition_campaign_components(),state.campaign_defense_activity_index())
	check(attacked and state.cities[3].owner_nation==actor and not state.nations[defender].alive,"real forward/reverse attack captures enemy capital fu and eliminates the actual loser")
	check(state.cities[2].owner_nation==2 and state.cities[2].food_storage==neutral_stock and state.nations[2].alive,"neutral state seat and its resources survive the actual victory")
	check(state.nations[defender].warehouse_city_ids.is_empty() and state.nations[defender].granary_food==0,"the actual loser releases its warehouse and grain access")
	var grain := 0
	for city in state.warehouse_cities_of(actor): grain += city.food_storage
	check(grain>initial_grain and grain==state.nations[actor].granary_food,"captured capital grain reaches the winner's physical warehouses and ledger")
	check(not state.is_enemy(0,1) and x.troops.all(func(a):return a.campaign_war_id!=war),"real victory releases war and army bindings")
	ChronicleRules.finalize_pending(state)
	var events := state.chronicle_events.filter(func(e):return e.get("kind","")=="external_war" and e.get("war_id",-1)==war)
	check(events.size()==1,"real forward/reverse capital capture creates one final event")
	var resources := [state.nations[actor].treasury_gold,state.nations[actor].granary_food,state.nations[actor].manpower_pool]
	sim._resolve_eliminated_nation_capitulations(); ChronicleRules.finalize_pending(state)
	check(events.size()==state.chronicle_events.filter(func(e):return e.get("kind","")=="external_war" and e.get("war_id",-1)==war).size(),"repeated settlement does not duplicate the final event")
	check(resources==[state.nations[actor].treasury_gold,state.nations[actor].granary_food,state.nations[actor].manpower_pool],"repeated settlement does not duplicate resource transfer")
	sim.free()

func test_other_hostile_center_is_not_neutral():
	var x := fixture(); var state: GameState = x.state; var sim: Simulation = x.sim
	state.cities[2].owner_nation = 2; state.recognized_city_owners[2] = 2
	state.ownership_revision += 1
	var components := state.coalition_campaign_components()
	var record := state.StateCampaigns.adopt_offense(state,x.front,components)
	check(record!=null,"enemy-fu record exists before the seat's country becomes hostile")
	if record==null:
		sim.free()
		return
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.WAR)
	components = state.coalition_campaign_components()
	state.StateCampaigns.reconcile(state,components,state.campaign_defense_activity_index())
	check(record.lifecycle==StateCampaign.Lifecycle.ENDING,"another enemy component's seat cannot use the neutral-seat exception")
	sim.free()

func run():
	test_reselection(); test_route_recovery(); test_physical_commitment(false); test_physical_commitment(true); test_enemy_fu_entry(); test_buffered_reselection(); test_neutral_center_enemy_fu(); test_neutral_center_enemy_fu(true); test_other_hostile_center_is_not_neutral()
	for label in failures: push_error("NEUTRAL_ROUTE_FAIL: "+label)
	print("NEUTRAL_ROUTE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
