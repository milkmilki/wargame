extends SceneTree
## Existing roads may cross hostile countryside, but no hostile city is transit.
const Access=preload("res://tests/atlas_access_and_repatriation.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("ROAD_CAMPAIGN_FAIL ",label)
func run() -> void:
	for backend in ["gdscript","native"]:
		NativeCompute.set_backend_for_tests(backend)
		var state:=Access._fixture([Vector3i(0,5,0),Vector3i(5,6,4),Vector3i(6,1,1)] as Array[Vector3i])
		state.atlas_layout.settlement_adjacency={0:[1] as Array[int],1:[0] as Array[int]}
		var rng:=state.rng.state
		check(DiplomacyAI._prewar_attack_route_ready(state,0,0,1,{}),backend+": preview uses same opponent's rural road without new construction")
		check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1])),backend+": declared attack follows that same road")
		check(MilitaryReachability.contact(state,[0],[1],[0,1]),backend+": planned contact agrees with actual movement")
		check(Pathfinding._attack_supply_links(state,1,1,0,{}).has(0),backend+": the actual attack corridor can carry rear supply across the same rural road")
		check(not is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,-1).dist[1])),backend+": ordinary movement never borrows attack access")
		check(is_finite(float(Pathfinding.dijkstra_field(state,1,0,false,false,-1).dist[0])),backend+": withdrawal leaves the same opponent's countryside without new roads")
		state.cities[6].owner_nation=1
		check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,6).dist[6])),backend+": a traffic node's display owner never blocks a public road")
		state.cities[6].owner_nation=-1
		check(state.rng.state==rng,backend+": previews and paths consume no random draws")
		state.edge_of(5,6).control_city_id=2;state.road_network_revision+=1
		check(DiplomacyAI._prewar_attack_route_ready(state,0,0,1,{}),backend+": neutral rural road is public during preparation")
		check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1])),backend+": neutral rural road permits actual movement")
		check(MilitaryReachability.contact(state,[0],[1],[0,1]),backend+": neutral rural road permits projected contact")
		check(Pathfinding._attack_supply_links(state,1,1,0,{}).has(0),backend+": neutral rural road also carries supplies")
		state.edge_of(5,6).control_city_id=3;state.road_network_revision+=1
		check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1])),backend+": another enemy countryside remains public transit")
		state=Access._fixture([Vector3i(0,5,0),Vector3i(5,4,4),Vector3i(4,6,4),Vector3i(6,1,1)] as Array[Vector3i])
		state.atlas_layout.settlement_adjacency={0:[4] as Array[int],4:[0,1] as Array[int],1:[4] as Array[int]}
		check(not is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1])),backend+": rear city cannot be attacked through an unconquered enemy city")
		check(not DiplomacyAI._prewar_attack_route_ready(state,0,0,1,{}),backend+": preparation also rejects jumping over a city")
		check(not Pathfinding._attack_supply_links(state,1,1,0,{}).has(0),backend+": supplies cannot bypass an unconquered enemy city either")
		check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,4).dist[4])),backend+": first enemy city remains a legal attack objective")
		# Deliberately stale command: live execution must enforce the city barrier.
		var army:=Army.new();army.id=0;army.owner_nation=0;army.size=15000;army.max_size=15000
		army.location_city=5;army.move_from=5;army.route_origin_city_id=0
		army.state=Army.State.MOVING;army.ai_action=ActionCandidate.Kind.ATTACK;army.ai_target_city=1
		army.path=[4,6,1] as Array[int];state.armies.append(army)
		var sim:=Simulation.new();sim.setup(state)
		sim._begin_next_leg(army)
		check(not army.on_edge or army.move_to!=4,backend+": runtime rejects a stale order to bypass the first enemy city")
		sim.free()
		progression(backend,false)
		progression(backend,true)
		state_target_selection(backend)
	NativeCompute.set_backend_for_tests("native")
	print("ROAD_CAMPAIGN checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func state_target_selection(backend:String) -> void:
	var state:=Access._fixture([Vector3i(0,5,0),Vector3i(5,4,4),Vector3i(4,6,4),Vector3i(6,1,1),Vector3i(0,2,2),Vector3i(2,8,2),Vector3i(8,7,7)] as Array[Vector3i])
	state.cities[7].node_kind=City.NodeKind.SETTLEMENT;state.cities[7].politically_active=true;state.cities[7].owner_nation=1
	state.recognized_city_owners[7]=1
	state.administrative_center_by_city[7]=7
	state.administrative_center_city_ids.append(7)
	state.atlas_layout.settlement_adjacency={0:[4,7] as Array[int],4:[0,1] as Array[int],1:[4] as Array[int],7:[0] as Array[int]}
	state.atlas_layout.territorial_pairs=[Vector2i(0,7),Vector2i(4,1)] as Array[Vector2i]
	for city in state.cities:
		if city.is_settlement():state.region_ids[city.id]=0
	state.nations[0].strategic_region_anchor_city_id=1
	RegionalStrategy.invalidate_geometry(state)
	state.refresh_derived()
	for context in [DiplomacyAI.ObjectiveContext.PREWAR,DiplomacyAI.ObjectiveContext.CAMPAIGN]:
		var selected:=DiplomacyAI.select_war_objective(state,0,1,{},-1,false,{},false,context)
		check(selected.get("city_id",-1)==4,backend+": blocked geographic state border cannot hide a legal road-front state")
	state.transfer_city_control(4,0,0,GameState.TerritoryStockDisposition.CAPTURE_SPOILS,"road_fixture_capture")
	var next:=DiplomacyAI.select_war_objective(state,0,1,{},-1,false,{},false,DiplomacyAI.ObjectiveContext.CAMPAIGN)
	check(next.get("city_id",-1)==1,backend+": after taking the front state, target selection advances to the next state on the same road")

func progression(backend:String,reverse:bool) -> void:
	var actor:=1 if reverse else 0
	var defender:=1-actor
	var state:=Access._fixture([Vector3i(0,5,0),Vector3i(5,4,4),Vector3i(4,6,4),Vector3i(6,1,1),Vector3i(0,2,2),Vector3i(2,8,2),Vector3i(8,7,7)] as Array[Vector3i])
	state.day=100
	state.cities[7].node_kind=City.NodeKind.SETTLEMENT;state.cities[7].politically_active=true;state.cities[7].owner_nation=1
	state.recognized_city_owners[7]=1
	state.atlas_layout.hierarchy.members=[[0],[1,4,7],[2],[3]]
	state.atlas_layout.hierarchy.state_parents=PackedInt32Array([0,1,2,3])
	state.atlas_layout.settlement_adjacency={0:[4,7] as Array[int],4:[0,1] as Array[int],1:[4] as Array[int],7:[0] as Array[int]}
	# The only geometric frontier fu is blocked by a neutral city. The existing
	# road actually enters fu 4, which must be tried before declaring no entry.
	state.atlas_layout.territorial_pairs=[Vector2i(0,7),Vector2i(4,1)] as Array[Vector2i]
	state.rebuild_administrative_regions()
	for city in state.cities:
		if reverse and city.owner_nation in [0,1]:city.owner_nation=1-city.owner_nation;state.recognized_city_owners[city.id]=city.owner_nation
		if city.is_settlement():state.region_ids[city.id]=0
		city.garrison_manpower=100
	state.nations[actor].capital_city_id=0;state.nations[defender].capital_city_id=1
	state.nations[actor].strategic_region_anchor_city_id=1
	RegionalStrategy.invalidate_geometry(state)
	state.set_war_objective(0,1,0 if reverse else 1,"road progression")
	state.refresh_derived()
	var query:=DiplomacyAI.select_war_objective(state,actor,defender,{},-1,false,{},false,DiplomacyAI.ObjectiveContext.CAMPAIGN)
	check(query.get("city_id",-1)==1 and query.get("tactical_city_id",-1)==4,backend+": AI selects the first actual enemy city on the existing road")
	var front:=state.create_campaign_front(state.war_id_between(0,1),[actor] as Array[int],actor,CoalitionCampaignFront.Mode.OFFENSE,1)
	var forces:Array[Army]=[]
	for id in range(3):
		var unit:=Army.new();unit.id=id;unit.owner_nation=actor;unit.size=15000;unit.max_size=15000
		unit.location_city=0;unit.move_from=0;unit.morale=unit.max_morale
		unit.campaign_front_id=front.front_id;unit.campaign_war_id=front.war_id;front.army_assignments[id]=1
		state.armies.append(unit);forces.append(unit)
	var army:=forces[0]
	var sim:=Simulation.new();sim.setup(state)
	check(sim._campaign_entry_fu(actor,1,[actor] as Array[int])==4,backend+": planner tries a road entry after all geometric entries fail")
	sim._manage_administrative_campaign(front)
	check(forces.all(func(a):return a.on_edge and a.ai_target_city==4),backend+": controller dispatches rallied formations to the front city")
	for unit in forces:
		for _leg in range(12):
			if not unit.on_edge:break
			unit.move_progress=1.;sim._arrive_at_node(unit)
	var battle:=state.battle_by_id(army.battle_id)
	check(battle!=null and battle.city.id==4,backend+": real movement first stops for combat at the front enemy city")
	if battle!=null:
		sim._complete_siege_capture(battle)
		check(state.cities[4].owner_nation==actor and state.cities[1].owner_nation==defender,backend+": actual forward/reverse siege captures only the front fu")
		check(sim._campaign_entry_fu(actor,1,[actor] as Array[int])<0,backend+": captured entry no longer repeats while neutral fu remains blocked")
		var next:=Pathfinding.dijkstra_field(state,4,actor,false,false,1)
		check(is_finite(float(next.dist[1])),backend+": center route opens after the real front capture")
		sim._manage_administrative_campaign(front)
		check(forces.all(func(a):return a.on_edge and a.ai_target_city==1),backend+": controller continues to the center without repeating the captured fu")
		for unit in forces:
			for _leg in range(12):
				if not unit.on_edge:break
				unit.move_progress=1.;sim._arrive_at_node(unit)
		battle=state.battle_by_id(army.battle_id)
		check(battle!=null and battle.city.id==1,backend+": real army continues to the rear center after capturing its entry")
		if battle!=null:
			sim._complete_siege_capture(battle);sim._resolve_eliminated_nation_capitulations()
			check(state.cities[1].owner_nation==actor and not state.nations[defender].alive,backend+": actual center victory eliminates the losing country, including defender counterconquest")
			check(not state.is_enemy(0,1) and army.campaign_war_id<0,backend+": final victory releases war and army bindings")
	check(state.cities[2].owner_nation==2 and state.relation_between(actor,2)==GameState.DiplomaticRelation.NEUTRAL,backend+": neutral country is untouched throughout progression")
	sim.free()
