extends SceneTree
## Compare full predecessor topology, not merely route length, against the
## cf80691 ranked-heap implementation on real access/contested-edge rules.
const Legacy = preload("res://tests/support/legacy_pathfinding.gd")
var failures: Array[String] = []
var checks := 0
var fields := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value and failures.size() < 20: failures.append(message)

func run() -> void:
	for mirror in [false, true]:
		var state := fixture(mirror)
		var rank := EquivariantOrder.city_rank_map(state, 0, 0)
		check(rank[4] == rank[5], "fixture has equal quantized five-part keys")
		for start in [0, 1, 2, 3, 4, 6, 7, 8]:
			for owner in [-1, 0, 1, 2]:
				for goal in [-1, 1, 2]:
					for danger in [false, true]:
						for contested in [false, true]:
							compare(state, start, owner, contested, danger, goal)
		for blocked in [{4: true}, {6: true}, {1: true}, {0: true}]:
			compare(state, 0, 0, false, true, -1, blocked)
			compare(state, 0, 0, false, false, 1, blocked)
		# The initial occupied-city controller may be crossed only when that
		# lost settlement is the explicit exit district, never as general access.
		state.cities[0].owner_nation = 1
		state.ownership_revision += 1
		compare(state, 0, 0, false, true)
		compare(state, 4, 0, false, true, -1, {}, 0)
		compare(state, 4, 0, false, true, -1, {}, -1)
		var exit_allowed := Pathfinding.dijkstra_field(state, 4, 0, false, false, -1, 0, {}, 0)
		var exit_forbidden := Pathfinding.dijkstra_field(state, 4, 0, false, false)
		check(float(exit_allowed.dist[0]) < INF and float(exit_forbidden.dist[0]) == INF,
			"lost-city withdrawal does not grant access to other enemy districts")
	var fixture_state := fixture(false)
	var third := Pathfinding.dijkstra_field(fixture_state, 0, 0)
	check(float(third.dist[2]) == INF, "neutral third country is actually blocked")
	var attack := Pathfinding.dijkstra_field(fixture_state, 0, 0, false, false, 1)
	check(float(attack.dist[1]) < INF, "specified enemy final district is actually accessible")
	var unblocked := Pathfinding.dijkstra_field(fixture_state, 0, 0, false, false)
	var contested := Pathfinding.dijkstra_field(fixture_state, 0, 0, true, false)
	check(unblocked.prev != contested.prev, "enemy road occupation genuinely changes route topology")
	for variant in ["no_capital", "center_axis", "terrain_key"]:
		var varied := fixture(false)
		if variant == "no_capital": varied.nations[0].capital_city_id = -1
		elif variant == "center_axis":
			varied.cities[0].map_position.x = .5
			varied.cities[3].map_position.x = .5
		else:
			varied.cities[5].terrain_height = .01
			varied.cities[4].terrain_relief = .01
		for start in [0,4,6]: compare(varied,start,0,false,false)
	# A cost guard separates this optimization's baseline RED from behavioral
	# comparisons: Atlas must not materialize all worldwide city ranks.
	EquivariantOrder._city_rank_cache.clear()
	if OS.get_cmdline_user_args().has("--baseline-repro"):
		Legacy.dijkstra_field(fixture_state, 0, 0)
	else:
		Pathfinding.dijkstra_field(fixture_state, 0, 0)
	check(EquivariantOrder._city_rank_cache.is_empty(), "Atlas local search avoids worldwide rank materialization")
	_earth_samples()
	for message in failures: printerr("ATLAS_PATH_ORDER_FAIL ", message)
	print("ATLAS_PATH_ORDER_RESULT fields=%d checks=%d failures=%d" % [fields, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fixture(mirror: bool) -> GameState:
	var state := GameState.new(); state._reset_world(77991)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 3, false)
	var positions := [Vector2(.1,.5), Vector2(.9,.5), Vector2(.8,.8), Vector2(.6,.5),
		Vector2(.25,.3), Vector2(.2500001,.3), Vector2(.4,.5), Vector2(.7,.5),
		Vector2(.6,.8), Vector2(.2,.2), Vector2(.3,.7), Vector2(.2,.7)]
	for id in range(positions.size()):
		var city := City.new(); city.id = id
		city.owner_nation = id if id in [1,2] else 0
		city.map_position = positions[id]
		if mirror: city.map_position.x = 1.0 - city.map_position.x
		if id >= 4:
			city.node_kind = City.NodeKind.TRAFFIC
			city.owner_nation = -1; city.politically_active = false
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
		state.administrative_center_by_city.append(id if id < 4 else -1)
	state.administrative_center_city_ids = [0,1,2,3] as Array[int]
	for owner in range(3): state.nations[owner].capital_city_id = owner
	state.atlas_layout = {"model":"atlas-path-order-test", "territorial_pairs": []}
	state._initialize_recognized_city_owners()
	for record in [[0,4,0,1.,.1], [0,5,0,1.,0.], [4,6,0,1.,0.], [5,6,0,1.,.1],
		[6,3,3,1.,0.], [6,7,1,1.,.2], [7,1,1,1.,0.], [6,8,2,1.,0.],
		[8,2,2,1.,0.], [0,9,0,.25,0.], [9,3,3,.25,0.], [6,10,0,1.,0.],
		[10,11,0,1.,0.], [5,11,0,1.,0.]]:
		var edge := Edge.new(); edge.city_a = mini(record[0],record[1]); edge.city_b = maxi(record[0],record[1])
		edge.control_city_id = record[2]; edge.precise_distance = record[3]; edge.danger = record[4]
		if edge.city_a == 0 and edge.city_b == 9: edge.max_manpower = 0
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(edge.city_a,edge.city_b)] = edge
		(state.adjacency[edge.city_a] as Array[int]).append(edge.city_b)
		(state.adjacency[edge.city_b] as Array[int]).append(edge.city_a)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	var enemy := Army.new(); enemy.id = 0; enemy.owner_nation = 1; enemy.size = 15000
	enemy.on_edge = true; enemy.move_from = 0; enemy.move_to = 4; enemy.move_progress = .5
	state.armies.append(enemy)
	return state

func compare(state: GameState, start: int, owner: int, contested: bool, danger: bool,
	goal: int = -1, blocked: Dictionary = {}, exit_city: int = -1) -> void:
	var rng_before := state.rng.state
	var expected := Legacy.dijkstra_field(state,start,owner,contested,danger,goal,15000,blocked,exit_city)
	var actual := Pathfinding.dijkstra_field(state,start,owner,contested,danger,goal,15000,blocked,exit_city)
	fields += 1
	var label := "start=%d nation=%d contested=%s danger=%s goal=%d exit=%d" % [start,owner,contested,danger,goal,exit_city]
	check(expected.dist == actual.dist, label + " every finite/infinite distance is exact")
	check(expected.prev == actual.prev, label + " every predecessor and tie decision is exact")
	check(state.rng.state == rng_before, label + " path queries never consume simulation RNG")

func _earth_samples() -> void:
	var state := GameState.new()
	state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").military())
	for owner in [0, 7, 23]:
		if owner >= state.nations.size(): continue
		var start := state.nations[owner].capital_city_id
		if start < 0: continue
		for danger in [false,true]:
			for contested in [false,true]: compare(state,start,owner,contested,danger)
		var neighbor: int = state.neighbors(start)[0]
		compare(state,neighbor,owner,false,true,-1,{},start)
		compare(state,start,-1,false,true)
