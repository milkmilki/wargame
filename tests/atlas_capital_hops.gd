extends SceneTree
## Administrative distance counts settlements, not shared traffic segments.
var checks := 0
var failures: Array[String] = []

func _initialize(): call_deferred("run")

func check(value: bool, label: String):
	checks += 1
	if not value: failures.append(label)

func fixture() -> GameState:
	var state := GameState.new()
	state.atlas_layout = {"model":"admin-hop-test"}
	for id in range(3):
		var nation := Nation.new(); nation.id = id; nation.capital_city_id = id
		state.nations.append(nation)
	for id in range(8):
		var city := City.new(); city.id = id; city.owner_nation = 0 if id < 4 else -1
		if id >= 4: city.node_kind = City.NodeKind.TRAFFIC; city.politically_active = false
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
	for pair in [Vector2i(0,4),Vector2i(4,1),Vector2i(1,5),Vector2i(5,2),Vector2i(0,6),Vector2i(6,7),Vector2i(7,3),Vector2i(3,2)]:
		var edge := Edge.new(); edge.city_a = mini(pair.x,pair.y); edge.city_b = maxi(pair.x,pair.y); edge.control_city_id = 0
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(pair.x,pair.y)] = edge
		(state.adjacency[pair.x] as Array[int]).append(pair.y)
		(state.adjacency[pair.y] as Array[int]).append(pair.x)
	return state

# Independent label relaxation; no strategic-route table, traversal queue or
# implementation helper. Entering a real town costs one, traffic costs zero.
func oracle(state: GameState, nation_id: int) -> Dictionary:
	var distances := {state.nations[nation_id].capital_city_id:0}
	for _pass in range(state.cities.size()):
		var changed := false
		for edge in state.edges:
			if edge.max_manpower <= 0 or edge.control_city_id < 0 or edge.control_city_id >= state.cities.size(): continue
			if state.cities[edge.control_city_id].is_traffic or state.cities[edge.control_city_id].owner_nation != nation_id: continue
			for pair in [Vector2i(edge.city_a,edge.city_b),Vector2i(edge.city_b,edge.city_a)]:
				var target := state.cities[pair.y]
				if not distances.has(pair.x) or (not target.is_traffic and target.owner_nation != nation_id): continue
				var value := int(distances[pair.x]) + (0 if target.is_traffic else 1)
				if value < int(distances.get(pair.y,2147483647)): distances[pair.y] = value; changed = true
		if not changed: break
	var result := {}
	for id in distances:
		if not state.cities[id].is_traffic: result[id] = distances[id]
	return result

func run():
	var state := fixture()
	check(state.capital_hop_distances(0) == {0:0,1:1,2:2,3:1}, "unowned traffic preserves own connection and does not add hops")
	check(state.capital_hop_distances(0) == oracle(state,0), "matches independent relaxation")
	var mutable := state.capital_hop_distances(0); mutable.clear()
	check(state.capital_hop_distances(0).size() == 4, "caller cannot poison later results")
	state.edge_of(4,1).max_manpower = 0
	check(state.capital_hop_distances(0) == {0:0,3:1,2:2,1:3}, "closed shortest route uses longer own alternative")
	state.edge_of(4,1).max_manpower = Edge.STANDARD_MANPOWER
	state.cities[1].owner_nation = 1
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	check(state.capital_hop_distances(0) == {0:0,3:1,2:2}, "allied town is not own administrative transit")
	state.cities[1].owner_nation = 0
	state.edge_of(0,6).control_city_id = 1; state.cities[1].owner_nation = 1
	check(state.capital_hop_distances(0) == {0:0}, "foreign jurisdiction blocks unowned traffic even with alliance")
	state.cities[1].owner_nation = 0
	state.edge_of(0,6).control_city_id = -1
	check(state.capital_hop_distances(0) == {0:0,1:1,2:2,3:3}, "unknown control cannot bypass own administrative gate")
	state.edge_of(0,6).control_city_id = 0
	state.edge_of(0,4).control_city_id = 4
	check(state.capital_hop_distances(0) == {0:0,3:1,2:2,1:3}, "traffic cannot act as controlling jurisdiction")
	state.edge_of(0,4).control_city_id = 0
	state.nations[0].capital_city_id = 2
	check(state.capital_hop_distances(0) == {2:0,1:1,3:1,0:2}, "capital relocation recalculates distances")
	state.nations[0].alive = false
	check(state.capital_hop_distances(0).is_empty(), "dead nation returns no administrative distances")
	state.nations[0].alive = true; state.nations[0].capital_city_id = -1
	check(state.capital_hop_distances(0).is_empty(), "invalid capital returns empty")
	check(RebellionSystem.capital_hops(null,0).is_empty(), "null state returns empty")
	state.nations[0].capital_city_id = 4; state.cities[4].owner_nation = 0
	check(state.capital_hop_distances(0).is_empty(), "traffic cannot be capital")
	state = fixture(); state.atlas_layout.clear()
	for city in state.cities: city.owner_nation = 0
	check(state.capital_hop_distances(0) == {0:0,4:1,6:1,1:2,7:2,5:3,3:3,2:4}, "legacy graph retains physical hop rules")
	fuzz()
	for failure in failures: printerr("ATLAS_CAPITAL_HOPS_FAIL ",failure)
	print("ATLAS_CAPITAL_HOPS_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func fuzz():
	var random := RandomNumberGenerator.new(); random.seed = 15401
	for sample in range(64):
		var state := fixture()
		# Add cycles and shortcuts, including a zero-cost traffic chain that can
		# improve a node after a one-cost discovery in the same BFS frontier.
		for a in range(8):
			for b in range(a+1,8):
				if state.edge_of(a,b) != null or random.randf() > .25: continue
				var edge := Edge.new(); edge.city_a = a; edge.city_b = b; edge.control_city_id = 0
				state.edges.append(edge); state.edge_lookup[GameState.edge_key(a,b)] = edge
				(state.adjacency[a] as Array[int]).append(b); (state.adjacency[b] as Array[int]).append(a)
		for mutation in range(8):
			state.nations[0].capital_city_id = random.randi_range(0,3)
			for id in range(4): state.cities[id].owner_nation = 0 if random.randf() > .2 else 1
			state.cities[state.nations[0].capital_city_id].owner_nation = 0
			for edge in state.edges:
				edge.max_manpower = 0 if random.randf() < .2 else Edge.STANDARD_MANPOWER
				edge.control_city_id = random.randi_range(0,3)
			check(state.capital_hop_distances(0) == oracle(state,0), "random shared graph %d mutation %d" % [sample,mutation])
