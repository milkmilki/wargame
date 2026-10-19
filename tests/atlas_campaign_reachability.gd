extends SceneTree
## Public roads ignore jurisdiction labels; actual cities retain access checks.
const Access = preload("res://tests/atlas_access_and_repatriation.gd")
const Faction = preload("res://tests/vassal_faction_conflict.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("ATLAS_CAMPAIGN_FAIL ", message)

func moving_army(state: GameState, goal: int, path: Array[int]) -> Army:
	var army := Army.new()
	army.id = state.armies.size(); army.owner_nation = 0; army.size = 15000
	army.location_city = 0; army.move_from = 0; army.move_to = 5
	army.state = Army.State.MOVING; army.on_edge = true; army.path = path
	army.ai_action = ActionCandidate.Kind.ATTACK; army.ai_target_city = goal
	army.route_origin_city_id = 0; state.armies.append(army)
	return army

func run() -> void:
	for control in [1, 2, 4]:
		var state := Access._fixture([Vector3i(0,5,0), Vector3i(5,6,control), Vector3i(6,1,1)] as Array[Vector3i])
		var army := moving_army(state,1,[6,1] as Array[int])
		var expected := true
		var field := Pathfinding.dijkstra_field(state,0,0,false,false,1)
		check(is_finite(float(field.dist[1])) == expected,"formal route oracle for control %d" % control)
		check(state._campaign_has_live_route(army,1) == expected,"live route ignores rural road control %d" % control)
		check(MilitaryReachability.contact(state,[0],[1],[0,1]) == expected,"projected contact ignores rural road control %d" % control)
		if expected:
			var context := state.campaign_defense_context(1,1,state.war_id_between(0,1))
			check(context.incoming and not context.invaded and context.enemy_manpower==0,"legal attack route creates warning without inventing arrived enemy troops")
			state.cities[5].owner_nation=2; state.cities[6].owner_nation=3
			check(state._campaign_has_live_route(army,1) and MilitaryReachability.contact(state,[0],[1],[0,1]),"foreign traffic display ownership does not block a public road")
			state.edge_of(5,6).max_manpower = 0
			check(not state._campaign_has_live_route(army,1),"closed road invalidates live route")
			check(not MilitaryReachability.contact(state,[0],[1],[0,1]),"closed road cannot create projected contact")
	var allied := Access._fixture([Vector3i(0,5,0),Vector3i(5,2,2),Vector3i(2,6,2),Vector3i(6,1,1)] as Array[Vector3i])
	allied.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
	check(MilitaryReachability.contact(allied,[0],[1],[0,1]),"ordinary ally provides lawful projected transit")
	check(MilitaryReachability.planned_entries(allied, 1, 0, [0], [0,1,2], MilitaryReachability.planned_reachable(allied,0,[0],[0,1,2])).is_empty(),"projected opponent cannot borrow old allied transit")
	var corridor := Access._fixture([Vector3i(0,5,0),Vector3i(5,6,1),Vector3i(6,7,2),Vector3i(7,8,1),Vector3i(8,1,1)] as Array[Vector3i])
	corridor.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
	check(is_finite(float(Pathfinding.dijkstra_field(corridor,0,0,false,false,1).dist[1])),"formal route can cross an allied road between final-goal jurisdiction segments")
	check(MilitaryReachability.contact(corridor,[0],[1],[0,1]),"projected arrival search includes lawful allied road inside the goal corridor")
	var lost := Access._fixture([Vector3i(1,5,1),Vector3i(5,0,0)] as Array[Vector3i])
	var retreat := moving_army(lost,0,[0] as Array[int])
	retreat.location_city=1; retreat.move_from=1; retreat.route_origin_city_id=1; retreat.state=Army.State.RETREATING
	check(lost._campaign_has_live_route(retreat,0),"live retreat honors formal lost-origin evacuation permission")
	var transit := Access._fixture([Vector3i(0,5,0),Vector3i(5,6,3),Vector3i(6,3,3)] as Array[Vector3i])
	transit.cities[3].owner_nation = 0; transit.recognized_city_owners[3] = 0
	var war := transit.war_id_between(0,1)
	var record := transit.activate_state_campaign(1,0,3,war)
	var guard := transit.campaign_front(record.defense_front_id)
	var reinforcement := moving_army(transit,3,[6,3] as Array[int])
	reinforcement.ai_action = ActionCandidate.Kind.REINFORCE
	reinforcement.campaign_front_id = guard.front_id; reinforcement.campaign_war_id = war
	guard.army_assignments[reinforcement.id] = 3
	var reserve := Army.new(); reserve.id = 1; reserve.owner_nation = 0; reserve.size = 15000
	reserve.location_city = 0; reserve.move_from = 0; transit.armies.append(reserve)
	var sim := Simulation.new(); sim.setup(transit)
	sim._allocate_coalition_fronts({"war_id":war,"members":[0] as Array[int],"key":"fixture"})
	check(reserve.campaign_front_id == -1,"valid in-transit guard meets the floor without taking another reserve")
	sim.free()
	test_real_faction_launch()
	print("ATLAS_CAMPAIGN_REACHABILITY checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func test_real_faction_launch() -> void:
	var state := Faction.fixture(true)
	state.edges.clear(); state.edge_lookup.clear()
	for id in state.adjacency: state.adjacency[id].clear()
	for id in [12,13]:
		var city := City.new(); city.id = id; city.node_kind = City.NodeKind.TRAFFIC; city.politically_active = false
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
		state.recognized_city_owners.append(-1); state.administrative_center_by_city.append(-1); state.region_ids.append(-1)
	for road in [Vector3i(0,12,0),Vector3i(12,13,2),Vector3i(13,2,2)]:
		state._add_edge(road.x,road.y); state.edge_of(road.x,road.y).control_city_id = road.z
	state.atlas_layout = {"model":"faction-road-fixture","territorial_pairs":[]}
	var before := var_to_bytes([state.diplomatic_relations,state.rng.state,state.suzerainty])
	check(state.plan_vassal_conflict(1).mode == "war","lawful capital road prevents false isolated independence")
	check(var_to_bytes([state.diplomatic_relations,state.rng.state,state.suzerainty]) == before,"projected access is read-only")
	check(state.start_civil_war(1) and state.is_vassal(1) and state.is_in_civil_war(1),"real launch retains vassal relation and opens civil war")
