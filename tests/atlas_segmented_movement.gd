extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_SEGMENTS_FAIL ",message)
func fixture(split: bool) -> GameState:
	var state := GameState.new(); state._reset_world(1); state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,2,false)
	for id in range(4 if split else 2):
		var city := City.new(); city.id = id; city.map_position = Vector2(id*.1,.5); city.owner_nation = 0
		if id>=2: city.node_kind = City.NodeKind.TRAFFIC; city.owner_nation = -1; city.politically_active = false
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
	var pairs := [Vector2i(0,2),Vector2i(2,3),Vector2i(3,1)] if split else [Vector2i(0,1)]
	for pair in pairs:
		var edge := Edge.new(); edge.city_a = mini(pair.x,pair.y); edge.city_b = maxi(pair.x,pair.y)
		edge.precise_distance = .12/pairs.size(); edge.control_city_id = 0; edge.danger = .2
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(pair.x,pair.y)] = edge
		(state.adjacency[pair.x] as Array[int]).append(pair.y); (state.adjacency[pair.y] as Array[int]).append(pair.x)
	state.atlas_layout = {"model":"fixture","territorial_pairs":[]}
	return state
func _initialize() -> void:
	var plain := fixture(false); var split := fixture(true)
	var plain_cost: float = Pathfinding.dijkstra_field(plain,0,0).dist[1]
	var split_cost: float = Pathfinding.dijkstra_field(split,0,0).dist[1]
	check(is_equal_approx(plain_cost,split_cost),"risk cost additive across splits")
	var plain_loss := Pathfinding._supply_edge_loss(plain.edges[0]); var split_loss := 0.
	var travel := 0.
	for edge in split.edges: split_loss += Pathfinding._supply_edge_loss(edge); travel += Simulation.edge_travel_days(edge)
	check(is_equal_approx(plain_loss,split_loss),"supply loss additive")
	check(is_equal_approx(travel,Simulation.edge_travel_days(plain.edges[0])),"no per-segment travel toll")
	var army := Army.new(); army.id = 0; army.owner_nation = 0; army.size = 15000; army.max_size = 15000; army.location_city = 0; army.move_from = 0
	army.state = Army.State.MOVING; army.path = [2,3,1] as Array[int]; split.armies.append(army)
	var simulation := Simulation.new(); simulation.state = split
	simulation._begin_next_leg(army); simulation._advance_movement()
	check(army.move_from==3 and army.move_to==1 and is_equal_approx(army.move_progress,.5),"one day consumes remaining budget through two traffic nodes")
	simulation.free()
	print("ATLAS_SEGMENTED_MOVEMENT failures=",failures); quit(1 if failures else 0)
