extends "res://tests/atlas_territory_transactions.gd"
## Real segmented movement, capture and peace; geography never assigns a junction an owner.

func _init() -> void:
	call_deferred("run_routes")

func run_routes() -> void:
	_test_origin(3,0,0)
	_test_origin(0,3,3)
	_test_public_road_claim()
	_test_disconnected_claim(Edge.Kind.LAND,0)
	_test_disconnected_claim(Edge.Kind.SEA,3)
	_test_legal_recovery()
	_test_state_unification()
	_test_residual_prefecture()
	_test_siege_connectivity_changes()
	_test_protected_capital_bridge()
	_test_nested_vassal()
	_test_vassal_capital_victory(false)
	_test_vassal_capital_victory(true)
	_test_indirect_allied_siege(0)
	_test_indirect_allied_siege(3)
	for message in _failures: push_error("VASSAL_OCCUPATION_FAIL: "+message)
	print("VASSAL_OCCUPATION checks=%d failures=%d"%[_checks,_failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _political_fixture(root_nation: int = 0) -> GameState:
	var state := _fixture()
	state.suzerainty[3]={"overlord_id":root_nation,"tribute_rate":GameState.DEFAULT_TRIBUTE_RATE,"created_day":0,"last_centralization_day":-1,"civil_war":false}
	state.set_diplomatic_relation(root_nation,3,GameState.DiplomaticRelation.ALLIED)
	for warehouse in state.warehouse_cities_of(3):
		state.deposit_food(root_nation,warehouse.food_storage)
		warehouse.food_storage=0; warehouse.has_warehouse=false
	state.nations[3].warehouse_city_ids.clear()
	for actor in [root_nation,3]: state.set_diplomatic_relation(actor,1-root_nation,GameState.DiplomaticRelation.WAR)
	state.refresh_derived()
	return state

func _add_branch(state: GameState,kind: int,control: int) -> void:
	state._add_edge(3,TRAFFIC_ID)
	var edge := state.edge_of(3,TRAFFIC_ID)
	edge.kind=kind; edge.control_city_id=control
	edge.max_manpower=50000; edge.base_max_manpower=50000
	state.road_network_revision+=1

func _walk_capture(state: GameState,sim: Simulation,owner: int,origin: int) -> Army:
	var army := _army(state,owner,origin)
	army.state=Army.State.MOVING; army.ai_action=ActionCandidate.Kind.ATTACK; army.ai_target_city=4
	army.path=[TRAFFIC_ID,4] as Array[int]
	sim._begin_next_leg(army)
	_check(army.on_edge,"attack starts physical movement")
	for day in range(60):
		state.day+=1; sim._advance_movement()
		if state.cities[4].owner_nation!=1: break
	_check(state.cities[4].owner_nation!=1,"real segmented march reaches and captures the state")
	_check_traffic(state,"occupation route")
	return army

func _test_origin(owner: int,origin: int,expected: int) -> void:
	var state := _political_fixture()
	if origin==3: _add_branch(state,Edge.Kind.LAND,3)
	var sim := Simulation.new(); sim.setup(state)
	var army := _walk_capture(state,sim,owner,origin)
	for city in state.administrative_members(4):
		_check(state.cities[city].owner_nation==expected,"segmented capture follows real departure owner=%d origin=%d city=%d"%[owner,origin,city])
	_check(state.cities[4].occupation_sponsor_nation==owner,"sponsor remains the actual fighting country")
	var peace := sim._make_coalition_peace(0,1)
	_check(bool(peace.get("changed",false)),"real coalition peace commits")
	for city in state.administrative_members(4):
		_check(state.cities[city].owner_nation==expected and state.recognized_owner_of(city)==expected,"peace confirms the same recipient")
	_check(army.battle_id==-1 and state.territory_structure_valid(),"movement and peace preserve bindings and territory")
	sim.free()

func _test_vassal_capital_victory(counterattack: bool) -> void:
	var winner := 1 if counterattack else 0
	var loser := 1-winner
	var state := _political_fixture(winner)
	var war := state.set_war_objective(0,1,4,"vassal conquest regression")
	state.merge_war_ids(war,state.war_id_between(3,loser))
	ChronicleRules.begin_war(state,war,[0] if counterattack else [0,3],[1,3] if counterattack else [1])
	var lost_cities := state.land_cities_of(loser).duplicate()
	var home := state.nations[winner].capital_city_id
	var target := state.nations[loser].capital_city_id
	state.cities[home].food_storage=10000
	state.cities[target].food_storage=20000
	var neutral_resources := [state.nations[2].treasury_gold,state.nations[2].manpower_pool,state.nations[2].granary_food]
	var sim := Simulation.new(); sim.setup(state)
	var captor := _army(state,3,target)
	var defeated := _army(state,loser,target)
	for owner in [3,loser]: sim._reconcile_main_commands(owner)
	for army in [captor,defeated]:
		var front := state.create_campaign_front(war,[army.owner_nation] as Array[int],army.owner_nation,CoalitionCampaignFront.Mode.OFFENSE,target)
		army.campaign_war_id=war; army.campaign_front_id=front.front_id
		front.army_assignments[army.id]=target
	if not counterattack:
		captor.occupation_claimant_nation=3
		_capture(state,sim,captor,4)
		_check(state.cities[4].owner_nation==winner,"ordinary conquest redirects remote prince before capital victory")
	captor.occupation_claimant_nation=3
	var battle := _capture(state,sim,captor,target)
	sim._resolve_eliminated_nation_capitulations(); sim._purge_dead_armies()
	ChronicleRules.finalize_pending(state)
	_check(battle.finished and battle.siege_claimant_nation==winner,"actual capital victory uses the connected root counterattack=%s"%counterattack)
	_check(state.nations[winner].alive and state.nations[3].alive and not state.nations[loser].alive,"only the actual losing country is eliminated")
	for city in lost_cities:
		_check(city.owner_nation==winner and state.recognized_owner_of(city.id)==winner and city.occupation_sponsor_nation==-1,"actual victory permanently settles captured land")
	_check(state.cities[home].food_storage==10000+int(floor(20000.*GameState.TERRITORY_CAPTURE_SPOILS_RATE)) and state.cities[target].food_storage==0,"capital spoils credit the actual shared food pool once")
	_check([state.nations[2].treasury_gold,state.nations[2].manpower_pool,state.nations[2].granary_food]==neutral_resources,"neutral country retains treasury manpower and food")
	_check(not state.is_enemy(0,1) and not state.is_enemy(3,loser) and state.war_relation_ids.is_empty(),"whole defeated war releases both root and vassal relations")
	for army in state.armies:
		_check(army.campaign_war_id!=war and army.campaign_front_id==-1 and army.battle_id==-1,"victory releases actual military bindings")
	_check(state.campaign_fronts.is_empty(),"victory releases execution fronts")
	var events := state.chronicle_events.filter(func(e): return e.get("kind","")=="external_war")
	_check(events.size()==1,"victory records the external war once")
	if events.size()==1:
		_check(str(events[0].views.get(loser,"")).ends_with("国除") and not str(events[0].views.get(winner,"")).contains("国除"),"both historical perspectives follow actual survival")
	var frozen := _resource_fingerprint(state)
	var revision := state.ownership_revision
	var event_count := state.chronicle_events.size()
	sim._resolve_eliminated_nation_capitulations(); ChronicleRules.finalize_pending(state)
	_check(_resource_fingerprint(state)==frozen and state.ownership_revision==revision and state.chronicle_events.size()==event_count,"repeat cleanup cannot settle territory resources or events twice")
	_check(state.territory_structure_valid(),"actual forward or reverse conquest preserves territory invariants")
	_check(state._battle_group_structure_valid(),"actual forward or reverse conquest preserves command invariants")
	sim.free()

func _test_disconnected_claim(kind: int,control: int) -> void:
	var state := _political_fixture()
	if kind == Edge.Kind.LAND:
		# A foreign city, rather than a road's jurisdiction label, separates
		# the prince's capital from this projected conquest.
		state._add_edge(3,2); state._add_edge(2,TRAFFIC_ID)
		for edge in [state.edge_of(3,2),state.edge_of(2,TRAFFIC_ID)]:
			edge.control_city_id = control
		state.road_network_revision += 1
	else:
		_add_branch(state,kind,control)
	var sim := Simulation.new(); sim.setup(state)
	var army := _army(state,3,4)
	army.occupation_claimant_nation=3
	var rng_before := state.rng.state
	var battle := _capture(state,sim,army,4)
	_check(battle.finished and state.cities[4].owner_nation==0,"frozen vassal claim cannot bypass own-land capital connectivity kind=%d"%kind)
	_check(battle.siege_claimant_nation==0,"battle records the actual final recipient")
	_check(state.rng.state==rng_before,"recipient selection consumes no simulation randomness")
	_check(state.cities[4].occupation_sponsor_nation==3,"redirected control preserves combat sponsor")
	_check(state.territory_structure_valid(),"redirected claim preserves territory")
	sim.free()

func _test_public_road_claim() -> void:
	for control in [0,1,2]:
		var state := _political_fixture()
		_add_branch(state,Edge.Kind.LAND,control)
		var sim := Simulation.new(); sim.setup(state)
		var army := _army(state,3,4); army.occupation_claimant_nation=3
		var battle := _capture(state,sim,army,4)
		_check(battle.finished and state.cities[4].owner_nation==3 and battle.siege_claimant_nation==3,
			"public countryside connects the prince's actual capital without creating an enclave")
		_check(state.territory_structure_valid(),"public-road capture preserves territory invariants")
		sim.free()

func _test_state_unification() -> void:
	var state := _political_fixture()
	_check(bool(state.transfer_city_control(11,3,3,GameState.TerritoryStockDisposition.CAPTURE_SPOILS,"occupied_prefecture_fixture").get("ok",false)),"allied occupied prefecture fixture")
	state.transfer_city_sovereignty(12,2,"neutral_prefecture_fixture")
	state.transfer_city_sovereignty(13,3,"legal_vassal_prefecture_fixture")
	var sim := Simulation.new(); sim.setup(state)
	_walk_capture(state,sim,0,0)
	_check(state.cities[4].owner_nation==0 and state.cities[11].owner_nation==0,"captured seat unifies allied temporary occupation immediately")
	_check(state.cities[12].owner_nation==2 and state.recognized_owner_of(12)==2,"neutral legal land is untouched")
	_check(state.cities[13].owner_nation==3 and state.recognized_owner_of(13)==3,"existing legal vassal land is untouched")
	_check(state.territory_structure_valid(),"state unification is a valid territory transaction")
	sim.free()

func _test_residual_prefecture() -> void:
	var state := _political_fixture()
	var sim := Simulation.new(); sim.setup(state)
	_walk_capture(state,sim,0,0)
	state.transfer_city_control(11,1,-1,GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,"residual_prefecture_fixture")
	var army := _army(state,3,11)
	army.occupation_claimant_nation=3
	_capture(state,sim,army,11)
	_check(state.cities[11].owner_nation==0,"residual prefecture follows friendly seat rather than arriving army")
	sim.free()

func _test_siege_connectivity_changes() -> void:
	var state := _political_fixture()
	_add_branch(state,Edge.Kind.LAND,3)
	var sim := Simulation.new(); sim.setup(state)
	var army := _army(state,3,4); army.occupation_claimant_nation=3
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city=state.cities[4]; battle.siege_attacker_nation=3
	battle.siege_claimant_nation=sim._occupation_claimant_for_army(army,battle.city)
	_check(battle.siege_claimant_nation==3,"connected prince can start a siege with its own claim")
	sim._enter_battle(battle,army,1)
	state.edge_of(3,TRAFFIC_ID).max_manpower=0; state.road_network_revision+=1
	sim._complete_siege_capture(battle)
	_check(state.cities[4].owner_nation==0 and battle.siege_claimant_nation==0,"road closure before victory revalidates the frozen claim")
	sim.free()

func _test_legal_recovery() -> void:
	var state := _political_fixture()
	var operations: Array[Dictionary]=[]
	for city in state.administrative_members(4):
		operations.append({"city_id":city,"legal_owner_id":3,"sponsor_id":1,"reason":"recovery_fixture","stock_policy":GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL})
	_check(bool(state.apply_territory_transaction(operations).get("ok",false)),"legal recovery fixture uses a valid enemy occupation transaction")
	var sim := Simulation.new(); sim.setup(state)
	_walk_capture(state,sim,0,0)
	_check(state.cities[4].owner_nation==3 and state.recognized_owner_of(4)==3,"legal recovery returns disconnected old land to its living vassal")
	sim.free()

func _test_protected_capital_bridge() -> void:
	var state := _political_fixture()
	for ally in [0,3]: state.set_diplomatic_relation(2,ally,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(2,1,GameState.DiplomaticRelation.WAR)
	_check(bool(state.transfer_city_control(11,2,2,GameState.TerritoryStockDisposition.CAPTURE_SPOILS,"allied_capital_fixture").get("ok",false)),"ally occupies a prefecture")
	for city in [2,9]:
		_check(bool(state.transfer_city_sovereignty(city,0,"allied_capital_fixture").get("ok",false)),"ally loses old core through a real territory transaction")
	_check(state.nations[2].capital_city_id==11,"surviving ally really relocates its capital to the occupied prefecture")
	state._add_edge(3,11); state.edge_of(3,11).control_city_id=3
	var sim := Simulation.new(); sim.setup(state)
	var army := _army(state,3,4); army.occupation_claimant_nation=3
	_capture(state,sim,army,4)
	_check(state.cities[4].owner_nation==0,"protected ally capital cannot be borrowed as a projected land bridge")
	_check(state.cities[11].owner_nation==2 and state.nations[2].capital_city_id==11,"province capture preserves the protected allied capital")
	_check(state.territory_structure_valid(),"protected capital capture retains actual territory invariants")
	sim.free()

func _test_nested_vassal() -> void:
	var state := _political_fixture()
	state.suzerainty[2]=state.suzerainty[3].duplicate()
	state.suzerainty[3].overlord_id=2
	for ally in [0,3]: state.set_diplomatic_relation(2,ally,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(2,1,GameState.DiplomaticRelation.WAR)
	for warehouse in state.warehouse_cities_of(2):
		state.deposit_food(0,warehouse.food_storage); warehouse.food_storage=0; warehouse.has_warehouse=false
	state.nations[2].warehouse_city_ids.clear(); state.refresh_derived()
	var sim := Simulation.new(); sim.setup(state)
	var army := _army(state,3,4); army.occupation_claimant_nation=3
	_capture(state,sim,army,4)
	_check(state.cities[4].owner_nation==0,"nested disconnected vassal returns new territory to the peaceful sovereign root")
	_check(state.suzerainty_structure_valid() and state.territory_structure_valid(),"nested capture keeps the existing political hierarchy")
	sim.free()

func _test_indirect_allied_siege(first_owner: int) -> void:
	var state := _political_fixture()
	state.set_diplomatic_relation(2,3,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(2,1,GameState.DiplomaticRelation.WAR)
	_check(not state.has_military_access(2,0) and state.alliance_bloc(2).has(0),"indirect ally shares the war component without direct transit rights")
	var war := state.war_id_between(0,1)
	for member in [2,3]: state.merge_war_ids(war,state.war_id_between(member,1))
	_add_branch(state,Edge.Kind.LAND,3)
	state._add_edge(4,2); state.edge_of(4,2).control_city_id=2
	state.cities[4].garrison_manpower=100
	var sim := Simulation.new(); sim.setup(state)
	var first := _army(state,first_owner,4); first.occupation_claimant_nation=first_owner
	sim._start_or_join_siege(first,state.cities[4],state.edge_of(TRAFFIC_ID,4))
	var siege := sim._siege_battle_of(state.cities[4])
	_check(siege!=null and siege.siege_claimant_nation==first_owner,"first siege participant freezes the lawful claim")
	if siege==null: sim.free(); return
	var ally := _army(state,2,4); ally.size=30000; ally.max_size=30000
	sim._start_or_join_siege(ally,state.cities[4],state.edge_of(TRAFFIC_ID,4))
	_check(siege.side_a.has(ally),"stronger indirect ally joins the same actual siege")
	if first_owner==3:
		state.edge_of(3,TRAFFIC_ID).max_manpower=0; state.road_network_revision+=1
	sim._complete_siege_capture(siege)
	_check(state.cities[4].owner_nation==0 and siege.siege_claimant_nation==0,"indirect strongest captor preserves or redirects the claim to the sovereign root")
	_check(state.cities[4].occupation_sponsor_nation==2,"indirect captor remains the actual occupation sponsor")
	_check(not state.has_military_access(2,0),"receiving war spoils does not grant new military transit rights")
	_check(state.territory_structure_valid(),"indirect siege capture preserves political territory invariants")
	sim.free()
