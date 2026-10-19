extends SceneTree
## Administrative fields preserve real road order, traffic hops and jurisdiction.
var checks := 0
var failures := 0
class CustomState extends GameState:
	var hop_calls := 0
	func capital_hop_distances(owner: int) -> Dictionary:
		hop_calls += 1
		return {nations[owner].capital_city_id:0}
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures += 1; printerr("NATIVE_ADMINISTRATIVE_FAIL ",label)
func fixture(state: GameState = null) -> GameState:
	if state == null: state = GameState.new()
	state.atlas_layout = {"model":"native-administrative-test"}
	for owner in range(3):
		var nation := Nation.new(); nation.id = owner; nation.capital_city_id = owner
		state.nations.append(nation)
	for id in range(8):
		var city := City.new(); city.id = id; city.owner_nation = 0 if id < 4 else -1
		if id >= 4: city.node_kind = City.NodeKind.TRAFFIC
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
	for pair in [Vector2i(0,4),Vector2i(4,1),Vector2i(1,5),Vector2i(5,2),Vector2i(0,6),Vector2i(6,7),Vector2i(7,3),Vector2i(3,2)]:
		add_edge(state,pair.x,pair.y)
	return state
func add_edge(state: GameState,a: int,b: int):
	var edge := Edge.new(); edge.city_a = a; edge.city_b = b; edge.control_city_id = 0
	state.edges.append(edge); state.edge_lookup[GameState.edge_key(a,b)] = edge
	(state.adjacency[a] as Array[int]).append(b); (state.adjacency[b] as Array[int]).append(a)
func oracle(state: GameState,owner: int) -> Dictionary:
	var capital := state.nations[owner].capital_city_id
	if not state.nations[owner].alive or capital < 0 or capital >= state.cities.size() or state.cities[capital].owner_nation != owner or state.cities[capital].is_traffic: return {}
	var distances := {capital:0}
	for iteration in range(state.cities.size()):
		var changed := false
		for from_id in state.adjacency:
			for to_id in state.adjacency[from_id]:
				var edge := state.edge_of(from_id,to_id)
				if edge == null or edge.max_manpower <= 0 or not distances.has(from_id): continue
				var target := state.cities[to_id]
				if not target.is_traffic and target.owner_nation != owner: continue
				var candidate := int(distances[from_id])+(0 if target.is_traffic else 1)
				if candidate < int(distances.get(to_id,2147483647)):
					distances[to_id] = candidate; changed = true
		if not changed: break
	for city in state.cities:
		if city.is_traffic: distances.erase(city.id)
	return distances
func exact(graph: RefCounted,state: GameState,label: String):
	var owners := PackedInt32Array([2,0,1]); var capitals := PackedInt32Array()
	for owner in owners: capitals.append(state.nations[owner].capital_city_id if state.nations[owner].alive else -1)
	var result: Dictionary = graph.call("query_administrative_fields",state.cities,state.adjacency,state.edge_lookup,owners,capitals,City.NodeKind.TRAFFIC)
	check(not result.has("error"),label+": native inputs accepted")
	if result.has("error"): return
	var expected := {}
	for owner in owners:
		check(result.fields[owner] == oracle(state,owner),label+": independent relaxation for owner %d"%owner)
		expected[owner] = RebellionSystem.capital_hops(state,owner)
	check(var_to_bytes(result.fields) == var_to_bytes(expected),label+": exact values and dictionary insertion order")
func run():
	if not NativeCompute.require_native(): return
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	check(graph.has_method("query_administrative_fields"),"native administrative batch method exists")
	if not graph.has_method("query_administrative_fields"): finish(); return
	var state := fixture(); exact(graph,state,"traffic detours")
	for mutation in ["close","foreign_control","invalid_control","traffic_control","move_capital","traffic_capital","dead","adjacency"]:
		state = fixture()
		match mutation:
			"close": state.edges[1].max_manpower = 0
			"foreign_control": state.cities[3].owner_nation = 1; state.edges[0].control_city_id = 3
			"invalid_control": state.edges[0].control_city_id = 1 << 33
			"traffic_control": state.edges[0].control_city_id = 4
			"move_capital": state.nations[0].capital_city_id = 2
			"traffic_capital": state.nations[0].capital_city_id = 4; state.cities[4].owner_nation = 0
			"dead": state.nations[0].alive = false
			"adjacency": state.adjacency[0].clear()
		exact(graph,state,mutation+" without revision")
	var random := RandomNumberGenerator.new(); random.seed = 179412
	for sample in range(32):
		state = fixture()
		for a in range(8):
			for b in range(a+1,8):
				if state.edge_of(a,b) == null and random.randf() < .2: add_edge(state,a,b)
		for iteration in range(6):
			for id in range(4): state.cities[id].owner_nation = random.randi_range(0,2)
			for owner in range(3): state.nations[owner].capital_city_id = random.randi_range(-1,7)
			for edge in state.edges:
				edge.max_manpower = 0 if random.randf() < .2 else Edge.STANDARD_MANPOWER
				edge.control_city_id = random.randi_range(-1,7)
			exact(graph,state,"random %d/%d"%[sample,iteration])
	var error: Dictionary = graph.call("query_administrative_fields",[],{}, {},PackedInt32Array([0]),PackedInt32Array(),City.NodeKind.TRAFFIC)
	check(error.has("error"),"mismatched country and capital arrays are rejected")
	var invalid_state := fixture()
	invalid_state.adjacency[0] = "invalid"
	error = graph.call("query_administrative_fields",invalid_state.cities,invalid_state.adjacency,invalid_state.edge_lookup,PackedInt32Array([0]),PackedInt32Array([0]),City.NodeKind.TRAFFIC)
	check(error.has("error"),"non-array adjacency rows are rejected")
	invalid_state = fixture(); invalid_state.adjacency[0].append(99)
	error = graph.call("query_administrative_fields",invalid_state.cities,invalid_state.adjacency,invalid_state.edge_lookup,PackedInt32Array([0]),PackedInt32Array([0]),City.NodeKind.TRAFFIC)
	check(error.has("error"),"out-of-bounds targets are rejected")
	integration()
	finish()
func integration():
	var state := fixture()
	state.administrative_center_city_ids = PackedInt32Array([0,1,2,3])
	for city in state.cities:
		if not city.is_traffic: city.garrison_manpower = 17000+city.id*1350
	var expected: Array[int] = []
	for owner in range(state.nations.size()): expected.append(Simulation.nation_monthly_garrison_upkeep(state,owner))
	if OS.has_feature("debug"): NativeCompute.set_backend_for_tests("native")
	NativeCompute.set_profiling_for_tests(true)
	var before := var_to_bytes(NativeSnapshotBuilder.build(state)); var rng_state := state.rng.state
	var actual := Simulation.monthly_garrison_upkeep_by_nation(state)
	var profile := NativeCompute.profile_snapshot()
	check(int(profile.get("administrative_fields_native_call_count",0)) == 1,"fiscal batch computes all active countries in one native call")
	check(var_to_bytes(actual) == var_to_bytes(expected),"complete garrison upkeep remains byte-exact")
	check(before == var_to_bytes(NativeSnapshotBuilder.build(state)) and state.rng.state == rng_state,"fiscal batching preserves authoritative state and RNG")
	var custom := fixture(CustomState.new()) as CustomState
	custom.administrative_center_city_ids = state.administrative_center_city_ids.duplicate()
	for city in custom.cities:
		if not city.is_traffic: city.garrison_manpower = 17000+city.id*1350
	var custom_expected := Simulation.nation_monthly_garrison_upkeep(custom,0); custom.hop_calls = 0
	check(Simulation.monthly_garrison_upkeep_by_nation(custom)[0] == custom_expected and custom.hop_calls == 1,"custom capital-hop callbacks retain their fiscal behavior")
	NativeCompute.set_profiling_for_tests(false)
	if OS.has_feature("debug"):
		NativeCompute.set_backend_for_tests("compare")
		check(NativeCompute.administrative_fields(state,[2,0,1] as Array[int]).size() == 3,"development compare mode checks the complete batch")
func finish():
	print("NATIVE_ADMINISTRATIVE_FIELDS checks=",checks," failures=",failures); quit(1 if failures else 0)
