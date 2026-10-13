extends SceneTree
const Direct = preload("res://tests/direct_center_camp.gd")
const Information = preload("res://scripts/atlas/information_model.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("STATE_CAMPAIGN_FAIL ",label)
func run():
	var state := Direct.fixture()
	check(state.has_method("state_campaigns_for_nation"),"paired state campaign query exists")
	if not state.has_method("state_campaigns_for_nation"):
		finish(); return
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
	state.war_objectives.clear()
	var attacker := Direct.army(state,0,2,45000)
	var defender := Direct.army(state,1,3)
	var sim := Simulation.new(); sim.setup(state)
	for nation in state.nations:
		nation.ruler_archetype=RulerProfile.BALANCED; nation.ruler_traits.clear()
	var rng_before := state.rng.state
	var guard_before := var_to_bytes([defender.campaign_front_id,defender.campaign_war_id,defender.path,defender.ai_target_city,state.nations[1].treasury_gold])
	check(sim._start_war_preparation(0,1,{"objective_city":3,"objective_center_city":3}),"preparation starts through real entry")
	var attack_records: Array=state.call("state_campaigns_for_nation",0)
	var defense_records: Array=state.call("state_campaigns_for_nation",1,-1,true)
	check(attack_records.size()==1 and defense_records.size()==1,"both sides exist in preparation")
	check(state.call("state_campaigns_for_nation",1).is_empty(),"defender preparation is hidden")
	check(Information.campaign_rows(state,0).any(func(item): return item.label=="战役状态" and item.value=="准备"),"initiator view shows preparation status")
	check(Information.campaign_rows(state,1)[0].value=="暂无州战役","defender view hides preparation")
	check(var_to_bytes([defender.campaign_front_id,defender.campaign_war_id,defender.path,defender.ai_target_city,state.nations[1].treasury_gold])==guard_before,"preparation does not command or reserve defending troops")
	check(state.campaign_fronts.is_empty(),"preparation does not create military executors")
	if attack_records.is_empty(): sim.free(); finish(); return
	var campaign_id: int=attack_records[0].campaign_id
	sim._clear_war_preparation(0)
	check(state.call("state_campaigns_for_nation",0).is_empty() and state.call("state_campaigns_for_nation",1,-1,true).is_empty(),"cancellation removes both sides")
	check(sim._start_war_preparation(0,1,{"objective_city":3,"objective_center_city":3}),"second preparation starts")
	campaign_id=state.call("state_campaigns_for_nation",0)[0].campaign_id
	sim._set_coalition_war([0] as Array[int],[1] as Array[int])
	var war := state.war_id_between(0,1)
	attack_records=state.call("state_campaigns_for_nation",0,war)
	defense_records=state.call("state_campaigns_for_nation",1,war)
	check(attack_records.size()==1 and defense_records.size()==1,"declaration publishes both sides")
	if not attack_records.is_empty(): check(attack_records[0].campaign_id==campaign_id,"declaration preserves preparation identity")
	sim._clear_war_preparation(0,false,false)
	check(not state.campaign_defense_context(1,3,war).active,"paired existence does not invent physical enemy activity")
	sim._manage_coalition_campaigns()
	var guard := state.campaign_front_for(1,3,CoalitionCampaignFront.Mode.DEFENSE,war)
	check(guard!=null,"defense exists before physical invasion")
	if guard!=null:
		check(guard.army_assignments.has(defender.id),"published defense can reserve a real army")
	check(not Information.campaign_rows(state,1).is_empty(),"nation view can render the defense")
	check(state.rng.state==rng_before,"pair lifecycle consumes no simulation randomness")
	sim.free()
	test_declaration_wakes_existing_component()
	test_preparation_invalidated_by_annexation()
	test_waiting_target_replacement()
	test_unallocated_records_respect_slots()
	test_shared_defense()
	test_independent_defense_after_ending()
	test_direct_offense()
	test_snapshot_and_visibility()
	test_battle_ending(true)
	test_battle_ending(false)
	test_camp_loss_ends_pair()
	test_withdrawal_delays_collection()
	test_topology_migration()
	test_war_merge_and_third_party()
	for winner in [0,1]:
		for allied in [false,true]: test_actual_annexation(winner,allied)
	finish()
func test_declaration_wakes_existing_component():
	var state := Direct.fixture()
	Direct.army(state,0,2,45000)
	var defender := Direct.army(state,1,3)
	var war := state.war_id_between(0,1)
	var components := state.coalition_campaign_components(); state.sync_campaign_pairs(components)
	var sim := Simulation.new(); sim.setup(state)
	for component in components:
		sim._coalition_campaign_next_due_day[component.key]=state.day+10
	var record := state.activate_state_campaign(0,1,3,war,components)
	check(record!=null,"new target activates inside an existing war")
	sim._manage_coalition_campaigns()
	var guard := state.campaign_front(record.defense_front_id)
	check(guard!=null and guard.army_assignments.has(defender.id),"declaration wakes an existing component before its next planning day")
	check(guard!=null and guard.camp_city_id==-1,"quiet public defense postpones unused retreat path search")
	state.armies[0].location_city=3
	sim._coalition_defense_activity=state.campaign_defense_activity_index()
	sim._execute_coalition_defense(guard)
	check(guard.camp_city_id>=0 and guard.camp_city_id!=guard.center_city_id,"real threat prepares defense retreat with existing path rules")
	sim.free()
func test_shared_defense():
	var state := Direct.fixture()
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.WAR)
	var war := state.war_id_between(0,1)
	state.merge_war_ids(war,state.war_id_between(1,2))
	var components := state.coalition_campaign_components()
	state.sync_campaign_pairs(components)
	var first: StateCampaign=state.activate_state_campaign(0,1,3,war,components)
	var second: StateCampaign=state.activate_state_campaign(2,1,3,war,components)
	check(first!=null and second!=null and first.campaign_id!=second.campaign_id,"disconnected allied attackers have separate paired relations")
	if first==null or second==null: return
	check(first.defense_front_id==second.defense_front_id,"same-state defense executor is shared")
	var guard_id := second.defense_front_id
	state.end_state_campaign(first.campaign_id,"first relation ended")
	state.collect_state_campaigns()
	check(state.campaign_front(guard_id)!=null and state.state_campaigns.has(second.campaign_id),"one relation ending preserves another relation's defense")
	state.end_state_campaign(second.campaign_id,"second relation ended")
	state.collect_state_campaigns()
	check(state.state_campaigns.is_empty() and state.campaign_front(guard_id)==null,"last relation ending removes both records and unused shared defense")
func test_preparation_invalidated_by_annexation():
	var state := Direct.fixture()
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
	Direct.army(state,0,2,45000)
	var sim := Simulation.new();sim.setup(state)
	check(sim._start_war_preparation(0,1,{"objective_city":3,"objective_center_city":3}),"preparation begins before real third-party annexation")
	check(state.annex_nation(2,1),"third party annexes the preparing defender through normal transaction")
	sim._prepare_coalition_campaign_batch()
	check(state.state_campaigns_for_nation(0).is_empty() and state.state_campaigns_for_nation(1,-1,true).is_empty(),"defender annexation invalidates both preparation records")
	sim.free()
func test_waiting_target_replacement():
	var state := Direct.fixture()
	state.transfer_city_control(6,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"new defending target")
	state.transfer_city_control(7,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"new defending fu")
	var sim := Simulation.new(); sim.setup(state)
	var first := state.activate_state_campaign(0,1,3)
	sim._manage_coalition_campaigns()
	check(first.offense_front_id==-1 and not state.state_campaigns_for_nation(1).is_empty(),"waiting target has no empty offensive executor")
	sim._set_coalition_war_objective([0] as Array[int],[1] as Array[int],0,6,"change waiting objective")
	Direct.army(state,0,1,45000)
	sim._manage_coalition_campaigns(); state.collect_state_campaigns()
	check(not state.state_campaigns.has(first.campaign_id),"changing a waiting battlefield ends its old paired record")
	check(state.state_campaigns_for_nation(0).any(func(record): return record.center_city_id==6),"replacement target has its own paired record")
	sim.free()
func test_independent_defense_after_ending():
	var state := Direct.fixture()
	Direct.army(state,0,3)
	var defender := Direct.army(state,1,3)
	var record := state.activate_state_campaign(0,1,3)
	var guard := state.campaign_front(record.defense_front_id)
	defender.campaign_war_id=record.war_id;defender.campaign_front_id=guard.front_id
	guard.army_assignments[defender.id]=3
	state.end_state_campaign(record.campaign_id,"cancel selected target")
	check(not guard.retiring,"independent physical defense is not retired with its old relation")
	state.collect_state_campaigns()
	check(not state.state_campaigns.has(record.campaign_id) and state.campaign_front(guard.front_id)==guard,"ended relation is collected without releasing independently needed defense")
	check(guard.state_campaign_ids.size()==1 and state.state_campaigns[guard.state_campaign_ids[0]].incidental,"preserved independent defense immediately has its own paired relationship")
	check(defender.campaign_front_id==guard.front_id and guard.army_assignments.has(defender.id),"independent defense preserves actual existing army binding")
func test_unallocated_records_respect_slots():
	var state := Direct.fixture()
	for center in [5,6,7]: state.transfer_city_control(center,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"quota fixture")
	var sim := Simulation.new(); sim.setup(state)
	for center in [3,5,6]: state.activate_state_campaign(0,1,center)
	sim._manage_coalition_campaigns(); state.collect_state_campaigns()
	var records := state.state_campaigns_for_nation(0)
	check(records.size()==1 and records[0].center_city_id==3,"zero-force records respect the first waiting slot and do not bypass the second-front gate")
	check(state.campaign_fronts_for_nation(0,-1,CoalitionCampaignFront.Mode.OFFENSE).is_empty(),"unallocated records never create empty offensive executors")
	sim.free()
func test_direct_offense():
	var state := Direct.fixture()
	check(bool(state.transfer_city_control(6,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"second defending state").get("ok",false)),"defender retains another state for completion test")
	check(bool(state.transfer_city_control(7,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"second defending fu").get("ok",false)),"second state has its actual fu")
	var unit := Direct.army(state,0,2,45000)
	var front := Direct.front(state,[unit] as Array[Army])
	var sim := Simulation.new(); sim.setup(state)
	sim._prepare_coalition_campaign_batch()
	check(front.state_campaign_ids.size()==1,"directly created offense acquires paired record")
	check(state.state_campaigns_for_nation(1).size()==1,"direct staging offense is visible to its defender")
	var record: StateCampaign=state.state_campaigns_for_nation(0)[0] if not state.state_campaigns_for_nation(0).is_empty() else null
	if record!=null:
		var old_defenders := record.defender_members.duplicate()
		state.transfer_city_control(3,0,0,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"paired capture")
		sim._prepare_coalition_campaign_batch()
		check(record.defender_members==old_defenders,"zhou capture does not flip the original defending side")
		state.transfer_city_control(4,0,0,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"paired fu capture")
		sim._manage_coalition_campaigns()
		state.collect_state_campaigns()
		check(not state.state_campaigns.has(record.campaign_id),"whole-state completion ends both records")
	sim.free()
func finish():
	print("STATE_CAMPAIGN_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func settle_ending(state: GameState, sim: Simulation, id: int):
	for step in range(120):
		if not state.state_campaigns.has(id): break
		state.day+=1;sim._advance_movement();state.collect_state_campaigns()
	ChronicleRules.finalize_pending(state)

func test_snapshot_and_visibility():
	var state := Direct.fixture()
	var troop := Direct.army(state,0,2)
	Direct.front(state,[troop] as Array[Army])
	var sim := Simulation.new(); sim.setup(state); sim._prepare_coalition_campaign_batch()
	var snapshot := NativeSnapshotBuilder.build(state)
	check(snapshot.schema_version==29 and NativeSnapshotBuilder.campaign_validation_error(snapshot).is_empty(),"schema29 validates paired records and reverse references")
	var codec := preload("res://tests/support/native_runtime_fixture.gd").new()
	var plain := GameState.new()
	for property in state.get_property_list():
		if property.name!="script" and int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE: plain.set(property.name,state.get(property.name))
	var restored := codec.unpack(codec.pack(plain))
	check(var_to_bytes(NativeSnapshotBuilder.build(restored))==var_to_bytes(snapshot),"typed fixture roundtrip preserves both sides and identity")
	var bad := snapshot.duplicate(true); bad.state_campaigns[0].offense_front_id=99999
	check(not NativeSnapshotBuilder.campaign_validation_error(bad).is_empty(),"dangling execution reference is rejected")
	bad=snapshot.duplicate(true); bad.campaign_fronts.state_campaign_ids[0].append(99999)
	check(not NativeSnapshotBuilder.campaign_validation_error(bad).is_empty(),"dangling reverse reference is rejected")
	bad=snapshot.duplicate(true); bad.state_campaigns[0].pair_id=99999
	check(not NativeSnapshotBuilder.campaign_validation_error(bad).is_empty(),"dangling coalition pair reference is rejected")
	bad=snapshot.duplicate(true); bad.state_campaigns[0].lifecycle=StateCampaign.Lifecycle.ENDING;bad.state_campaigns[0].ending_army_ids=PackedInt32Array([99999])
	check(not NativeSnapshotBuilder.campaign_validation_error(bad).is_empty(),"dangling physical withdrawal reference is rejected")
	bad=snapshot.duplicate(true); bad.schema_version=28
	check(not NativeSnapshotBuilder.succession_validation_error(bad).is_empty(),"old runtime schema is rejected")
	var rows := Information.campaign_rows(state,1)
	check(rows[0].value=="1场 · 进攻0／防守1","nation view reports shared defending record")
	var before := var_to_bytes(NativeSnapshotBuilder.build(state))
	Information.campaign_rows(state,0); Information.campaign_rows(state,1)
	check(before==var_to_bytes(NativeSnapshotBuilder.build(state)),"view queries leave records and simulation unchanged")
	sim.free()

func test_battle_ending(with_regular_guard: bool):
	var state := Direct.fixture()
	var attacker := Direct.army(state,0,3,45000)
	var defender: Army=Direct.army(state,1,3) if with_regular_guard else null
	var front := Direct.front(state,[attacker] as Array[Army])
	var sim := Simulation.new(); sim.setup(state); sim._prepare_coalition_campaign_batch()
	var record: StateCampaign=state.state_campaigns_for_nation(0)[0]
	sim._start_or_join_siege(attacker,state.cities[3],state.edge_of(2,3))
	check(not state.battles.is_empty() and attacker.state==Army.State.FIGHTING,"ending fixture uses real combat startup")
	state.end_state_campaign(record.campaign_id,"撤销目标")
	sim._retire_campaign_front(front)
	state.collect_state_campaigns()
	check(state.state_campaigns.has(record.campaign_id) and state.campaign_front(front.front_id)!=null,"live battle keeps ending record and executor references")
	check(state.state_campaigns_for_nation(0).size()==1 and state.state_campaigns_for_nation(1).size()==1,"both sides remain visible while ending")
	check(Information.campaign_rows(state,1).any(func(item): return item.label=="战役状态" and item.value=="结束处理中"),"defender view shows the shared ending status")
	if not with_regular_guard:
		state.release_campaign_front(front.front_id);state.collect_state_campaigns()
		check(state.state_campaigns.has(record.campaign_id),"actual siege preserves ending pair even after executor releases its binding")
	sim._make_coalition_peace(0,1)
	state.collect_state_campaigns()
	settle_ending(state,sim,record.campaign_id)
	check(not state.state_campaigns.has(record.campaign_id) and attacker.campaign_war_id==-1 and (defender==null or defender.campaign_war_id==-1),"real peace finishes battle and releases the paired state")
	sim.free()

func test_camp_loss_ends_pair():
	var state := Direct.fixture()
	state.transfer_city_control(4,0,0,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"establish attacking camp")
	var attacker := Direct.army(state,0,3,45000)
	var front := Direct.front(state,[attacker] as Array[Army]);front.camp_city_id=4
	var sim := Simulation.new();sim.setup(state);sim._prepare_coalition_campaign_batch()
	var record: StateCampaign=state.state_campaigns_for_nation(0)[0]
	sim._start_or_join_siege(attacker,state.cities[3],state.edge_of(2,3))
	state.transfer_city_control(4,1,1,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"defender retakes actual camp")
	check(sim._fail_lost_campaign_camp(0,front,{}),"real camp loss passes existing battle-report and retreat gate")
	check(record.lifecycle==StateCampaign.Lifecycle.ENDING and record.end_reason=="拔营失败","camp loss ends both sides through the common lifecycle")
	state.collect_state_campaigns()
	check(state.state_campaigns.has(record.campaign_id),"camp loss keeps ending record until its actual siege completes")
	sim._make_coalition_peace(0,1);state.collect_state_campaigns()
	settle_ending(state,sim,record.campaign_id)
	check(not state.state_campaigns.has(record.campaign_id),"camp loss ending is collected through normal peace cleanup")
	sim.free()

func test_actual_annexation(winner: int, allied: bool):
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(13579)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	var war := state.war_id_between(0,1)
	var loser := 1-winner
	if allied:
		state.set_diplomatic_relation(loser,2,GameState.DiplomaticRelation.ALLIED)
		state.set_diplomatic_relation(winner,2,GameState.DiplomaticRelation.WAR)
		state.merge_war_ids(war,state.war_id_between(winner,2))
	var center := -1
	for id in state.administrative_center_city_ids:
		if state.cities[id].owner_nation==1: center=id; break
	check(center>=0,"annexation has real defending state")
	if center<0: return
	var components := state.coalition_campaign_components(); state.sync_campaign_pairs(components)
	var record := state.activate_state_campaign(0,1,center,war,components)
	check(record!=null,"annexation starts with actual paired record")
	if record==null: return
	var front := state.create_campaign_front(war,record.attacker_members,0,CoalitionCampaignFront.Mode.OFFENSE,center)
	state.StateCampaigns.attach(state,record,front)
	for army in state.armies:
		if army.owner_nation==0:
			army.campaign_war_id=war; army.campaign_front_id=front.front_id; front.army_assignments[army.id]=army.location_city; break
	var old_land := state.land_cities_of(loser).duplicate()
	state.nations[loser].manpower_pool=1234
	var manpower_before := state.nations[winner].manpower_pool
	var gold_before := state.nations[winner].treasury_gold+state.nations[loser].treasury_gold
	check(state.annex_nation(winner,loser),"forward/reverse annexation commits real territory and resource transaction")
	check(state.nations[loser].treasury_gold==0 and state.nations[winner].treasury_gold>=gold_before,"annexation transfers treasury and clears losing resource pool")
	check(state.nations[loser].manpower_pool==0 and state.nations[winner].manpower_pool>=manpower_before+1234,"annexation transfers reserve manpower to the actual winner")
	var sim := Simulation.new(); sim.state=state; sim._resolve_eliminated_nation_capitulations()
	ChronicleRules.finalize_pending(state)
	check(not state.nations[loser].alive and not state.is_enemy(0,1),"actual losing nation and war relation are cleaned up")
	for city in old_land: check(city.owner_nation==winner,"annexed territory belongs to actual winner")
	check(not state.state_campaigns.has(record.campaign_id) and state.campaign_front(front.front_id)==null,"annexation removes both state records and old executor")
	for army in state.armies: check(army.campaign_war_id!=war,"annexation releases actual army war bindings")
	if allied: check(state.nations[2].alive and not state.is_enemy(winner,2),"surviving coalition member exits via normal capitulation")
	var events := state.chronicle_events.filter(func(event): return event.get("kind","")=="external_war")
	check(events.size()==1,"real war event is finalized once")
	var gold_after := state.nations[winner].treasury_gold
	var manpower_after := state.nations[winner].manpower_pool
	sim._resolve_eliminated_nation_capitulations()
	ChronicleRules.finalize_pending(state)
	check(state.chronicle_events.filter(func(event): return event.get("kind","")=="external_war").size()==1,"repeated cleanup does not duplicate event")
	check(state.nations[winner].treasury_gold==gold_after and state.nations[winner].manpower_pool==manpower_after,"repeated real cleanup does not settle resources twice")
	sim.free()

func test_withdrawal_delays_collection():
	var state := Direct.fixture()
	var troop := Direct.army(state,0,2,45000)
	var front := Direct.front(state,[troop] as Array[Army])
	var sim := Simulation.new();sim.setup(state);sim._prepare_coalition_campaign_batch()
	var record: StateCampaign=state.state_campaigns_for_nation(0)[0]
	check(sim._order_campaign_army(troop,front,3,ActionCandidate.Kind.ATTACK) and troop.on_edge,"withdrawal fixture starts actual marching on a road")
	state.end_state_campaign(record.campaign_id,"cancel moving task")
	sim._retire_campaign_front(front);state.collect_state_campaigns()
	check(state.state_campaigns.has(record.campaign_id) and troop.on_edge,"released executor keeps both ending records while its cohort withdraws")
	var visited_endpoint := false
	for step in range(40):
		state.day+=1;sim._advance_movement();state.collect_state_campaigns()
		visited_endpoint=visited_endpoint or troop.location_city==3
		if not state.state_campaigns.has(record.campaign_id):break
	check(visited_endpoint and troop.location_city==2 and not troop.on_edge,"withdrawal finishes its current road leg and physically returns to staging")
	check(not state.state_campaigns.has(record.campaign_id),"both records collect only after physical withdrawal finishes")
	sim.free()

func test_war_merge_and_third_party():
	var state := Direct.fixture()
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.WAR)
	var first := state.activate_state_campaign(0,1,3)
	var second := state.activate_state_campaign(2,1,3)
	check(first.war_id!=second.war_id and first.defense_front_id!=second.defense_front_id,"independent wars start with distinct defenses")
	state.merge_war_ids(first.war_id,second.war_id)
	var sim := Simulation.new();sim.setup(state);sim._prepare_coalition_campaign_batch()
	check(first.war_id==second.war_id and first.defense_front_id==second.defense_front_id,"real war merge migrates records and shares the existing defense")
	check(NativeSnapshotBuilder.campaign_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"war merge validates paired and executor references")
	check(bool(state.transfer_city_control(3,2,2,GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL,"third-party capture").ok),"third party captures the actual target through territory transaction")
	sim._prepare_coalition_campaign_batch();state.collect_state_campaigns()
	check(not state.state_campaigns.has(first.campaign_id),"third-party capture ends the original pair")
	check(state.state_campaigns.has(second.campaign_id) and second.defender_members==[1],"third party's independent campaign preserves its original defending side")
	sim.free()

func test_topology_migration():
	var state := Direct.fixture()
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.WAR)
	var war := state.war_id_between(0,1)
	state.merge_war_ids(war,state.war_id_between(1,2))
	var components := state.coalition_campaign_components(); state.sync_campaign_pairs(components)
	state.activate_state_campaign(0,1,3,war,components)
	state.activate_state_campaign(2,1,3,war,components)
	state._add_edge(2,5); state.road_network_revision+=1
	var sim := Simulation.new(); sim.setup(state); sim._prepare_coalition_campaign_batch()
	check(state.state_campaigns_for_nation(0).size()==1 and state.state_campaigns_for_nation(2).size()==1,"merged attacking body shares one state battle")
	var record: StateCampaign=state.state_campaigns_for_nation(0)[0]
	var first := Direct.army(state,0,2)
	var stronger := Direct.army(state,2,2,45000)
	var front := state.create_campaign_front(war,[0,2] as Array[int],0,CoalitionCampaignFront.Mode.OFFENSE,3)
	front.staging_city_id=2
	for army in [first,stronger]:
		army.campaign_front_id=front.front_id; army.campaign_war_id=war; front.army_assignments[army.id]=2
	state.StateCampaigns.attach(state,record,front)
	var edge := state.edge_of(2,5); state.edges.erase(edge)
	state.edge_lookup.erase(GameState.edge_key(2,5)); state.adjacency[2].erase(5); state.adjacency[5].erase(2); state.road_network_revision+=1
	sim._prepare_coalition_campaign_batch()
	check(front.anchor_nation_id==2 and record.attacker_members==[2],"split follows the real executor's strongest surviving component")
	check(state.state_campaigns_for_nation(0).is_empty() and state.state_campaigns_for_nation(2).size()==1,"split does not clone state battle")
	check(NativeSnapshotBuilder.campaign_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"topology migration keeps all references valid")
	sim.free()
