extends SceneTree
## Explicit read-only batches must preserve query bytes and retire before live edits.
const Factory = preload("res://tests/native_graph_equivalence.gd")
var checks := 0
var failures: Array[String] = []
var parallel_state: GameState
var parallel_expected: Array[PackedByteArray] = []
var parallel_results: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func same(expected: Variant, actual: Variant, label: String) -> void:
	check(var_to_bytes(expected) == var_to_bytes(actual), label)

func fixture(mirror: bool = false) -> GameState:
	var factory := Factory.new()
	var state: GameState = factory.fixture(mirror)
	factory.free()
	return state

func compare_path(state: GameState, start: int, nation: int, contested: bool, goal: int,
		blocked: Dictionary = {}, exit_city: int = -1) -> void:
	var expected := Pathfinding._dijkstra_field_gdscript(state, start, nation, contested, true, goal, 15000, blocked, exit_city)
	var actual := Pathfinding.dijkstra_field(state, start, nation, contested, true, goal, 15000, blocked, exit_city)
	same(expected, actual, "path start=%d nation=%d contested=%s goal=%d exit=%d blocked=%s" % [start, nation, contested, goal, exit_city, blocked])

func compare_supply(state: GameState, logistics: bool) -> void:
	var origins: Array[int] = [3, 4, 3]
	var blocked := Pathfinding._enemy_occupied_edge_keys(state, 0)
	var expected := Pathfinding._supply_loss_field_gdscript(state, 0, 0, blocked, true, origins, logistics)
	var actual := Pathfinding._supply_loss_field(state, 0, 0, blocked, true, origins, logistics)
	same(expected, actual, "supply relays logistics=%s" % logistics)

func compare_travel(state: GameState) -> void:
	for start in [0, 3, 4, 6]:
		var oracle := ThreatField.new()
		var subject := ThreatField.new()
		same(oracle._travel_days_field_gdscript(state, start, 15000), subject._travel_days_field(state, start, 15000), "travel start=%d" % start)

func queries(state: GameState) -> void:
	compare_travel(state)
	compare_supply(state, false)
	compare_supply(state, true)
	# Enemy goal may override its control district; neutral goal cannot.
	for goal in [-1, 1, 2]:
		for contested in [false, true]:
			compare_path(state, 0, 0, contested, goal)
			compare_path(state, 4, 0, contested, goal, {}, 0)
	compare_path(state, 0, 0, false, 1, {1: true, 4: true})
	compare_path(state, 0, 0, false, -1, {0: true, 4: true})
	compare_path(state, 0, -1, false, -1)
	compare_path(state, 0, 2, false, -1)

func frozen_queries(state: GameState) -> void:
	var rng_before := state.rng.state
	NativeCompute.set_profiling_for_tests(true)
	check(NativeCompute.begin_frozen_batch(state, [0, 1, 2] as Array[int], true, true), "explicit batch starts")
	queries(state)
	check(not NativeCompute.begin_frozen_batch(state, [0] as Array[int], true, true), "overlapping batch is rejected without replacing the existing one")
	queries(state)
	var profile := NativeCompute.profile_snapshot()
	check(int(profile.get("batch_pack_count", 0)) == 1, "one prepared input batch serves repeated queries")
	NativeCompute.end_frozen_batch(state)
	NativeCompute.set_profiling_for_tests(false)
	queries(state)
	check(state.rng.state == rng_before, "prepared and standalone queries leave random stream unchanged")

func live_edits(state: GameState) -> void:
	var before: Dictionary = Pathfinding.dijkstra_field(state, 0, -1, false, true)
	state.edges[1].precise_distance = 3.75
	state.edges[1].danger = .65
	state.edges[1].travel_time_multiplier = 2.5
	state.edges[1].supply_loss_multiplier = 2.25
	state.edges[0].max_manpower = 0
	var after: Dictionary = Pathfinding.dijkstra_field(state, 0, -1, false, true)
	check(var_to_bytes(before) != var_to_bytes(after), "direct cost and capacity edits alter the actual result")
	queries(state)
	state.cities[0].owner_nation = 1
	compare_path(state, 4, 0, false, -1, {}, 0)
	compare_path(state, 4, 0, false, -1)
	compare_supply(state, false)
	var neutral: Dictionary = Pathfinding.dijkstra_field(state, 3, 0, false, true)
	state.diplomatic_relations[state._diplomacy_key(0, 2)] = GameState.DiplomaticRelation.ALLIED
	var allied: Dictionary = Pathfinding.dijkstra_field(state, 3, 0, false, true)
	check(float(neutral.dist[2]) == INF and float(allied.dist[2]) < INF, "direct alliance edit opens the formerly neutral district")
	queries(state)
	# A newly prepared batch must capture the same direct edits.
	check(NativeCompute.begin_frozen_batch(state, [0, 1, 2] as Array[int], true, true), "batch rebuilt after direct edits")
	queries(state)
	NativeCompute.end_frozen_batch(state)

func reset_same_instance(state: GameState) -> void:
	var old_count := state.cities.size()
	var old_edge_count := state.edges.size()
	var old_graph: RefCounted = NativeCompute._state_graph(state).graph
	var replacement := fixture(true)
	state._reset_world(replacement.world_seed)
	state.cities = replacement.cities
	state.edges = replacement.edges
	state.nations = replacement.nations
	state.armies = replacement.armies
	state.adjacency = replacement.adjacency
	state.edge_lookup = replacement.edge_lookup
	state.atlas_layout = replacement.atlas_layout
	state.administrative_center_by_city = replacement.administrative_center_by_city
	state.administrative_center_city_ids = replacement.administrative_center_city_ids
	state.diplomatic_relations = replacement.diplomatic_relations
	check(state.cities.size() == old_count and state.edges.size() == old_edge_count and state.road_network_revision == 0, "reset retains counts and revision values which previously collided")
	var new_graph: RefCounted = NativeCompute._state_graph(state).graph
	check(new_graph != old_graph, "same-instance reset retires the previous immutable graph")
	queries(state)

func direct_control_edits(mirror: bool) -> void:
	var state := fixture(mirror)
	state.armies.clear()
	var original_graph: RefCounted = NativeCompute._state_graph(state).graph
	var revision := state.road_network_revision
	var rear_edges: Array[Edge] = []
	for neighbor in state.neighbors(0): rear_edges.append(state.edge_of(0, neighbor))
	for control in [1, 2, -1, state.cities.size() + 10, 0]:
		for edge in rear_edges: edge.control_city_id = control
		var expected := Pathfinding._supply_loss_field_gdscript(state, 0, 0, {}, true, [] as Array[int], true)
		var actual := Pathfinding._supply_loss_field(state, 0, 0, {}, true, [] as Array[int], true)
		same(expected, actual, "standalone supply observes direct rear control=%d mirror=%s" % [control, mirror])
		check(is_finite(actual.dist[3]) == (control == 0), "enemy/neutral/invalid rear jurisdiction cannot feed reachable junctions")
		# Goal and explicit-exit overrides must patch the same live control IDs
		# used by the base access mask, rather than the first CSR's old mapping.
		for goal in [1, 2]: compare_path(state, 0, 0, false, goal)
		compare_path(state, 3, 0, false, -1, {}, 1)
		check(NativeCompute.begin_frozen_batch(state, [0] as Array[int], true, true), "direct-control batch starts")
		same(expected, Pathfinding._supply_loss_field(state, 0, 0, {}, true, [] as Array[int], true), "fresh frozen supply captures direct control edit")
		for goal in [1, 2]: compare_path(state, 0, 0, false, goal)
		compare_path(state, 3, 0, false, -1, {}, 1)
		NativeCompute.end_frozen_batch(state)
	check(state.road_network_revision == revision and NativeCompute._state_graph(state).graph == original_graph, "jurisdiction edits keep the immutable CSR and same public topology revision")
	for edge in rear_edges: edge.control_city_id = 1
	var frozen_supply := Pathfinding._supply_loss_field_gdscript(state, 0, 0, {}, true, [] as Array[int], true)
	var frozen_path := Pathfinding._dijkstra_field_gdscript(state, 0, 0, false, true, 2)
	check(NativeCompute.begin_frozen_batch(state, [0] as Array[int], true, true), "control snapshot publishes before direct mutation")
	for edge in rear_edges: edge.control_city_id = 0
	same(frozen_supply, Pathfinding._supply_loss_field(state, 0, 0, {}, true, [] as Array[int], true), "published control mask is immutable until batch retirement")
	same(frozen_path, Pathfinding.dijkstra_field(state, 0, 0, false, true, 2), "goal patch uses the published control snapshot")
	NativeCompute.end_frozen_batch(state)
	same(Pathfinding._supply_loss_field_gdscript(state, 0, 0, {}, true, [] as Array[int], true), Pathfinding._supply_loss_field(state, 0, 0, {}, true, [] as Array[int], true), "retired supply batch observes the direct control edit")
	compare_path(state, 0, 0, false, 2)
	check(NativeCompute.begin_frozen_batch(state, [0] as Array[int], true, true), "next control batch starts with updated jurisdiction")
	same(Pathfinding._supply_loss_field_gdscript(state, 0, 0, {}, true, [] as Array[int], true), Pathfinding._supply_loss_field(state, 0, 0, {}, true, [] as Array[int], true), "next frozen supply captures the updated jurisdiction")
	NativeCompute.end_frozen_batch(state)

func parallel_query(index: int) -> void:
	var mismatches := 0
	for iteration in range(20):
		var results := [
			Pathfinding.dijkstra_field(parallel_state, 0, 0, false, true, 1),
			Pathfinding._supply_loss_field(parallel_state, 0, 0, {}, false, [3, 4] as Array[int], true),
			ThreatField.new()._travel_days_field(parallel_state, 0, 0),
		]
		for query in range(results.size()):
			if var_to_bytes(results[query]) != parallel_expected[query]: mismatches += 1
	parallel_results[index] = mismatches

func parallel_readers() -> void:
	parallel_state = fixture()
	parallel_expected = [
		var_to_bytes(Pathfinding._dijkstra_field_gdscript(parallel_state, 0, 0, false, true, 1)),
		var_to_bytes(Pathfinding._supply_loss_field_gdscript(parallel_state, 0, 0, {}, false, [3, 4] as Array[int], true)),
		var_to_bytes(ThreatField.new()._travel_days_field_gdscript(parallel_state, 0, 0)),
	]
	check(NativeCompute.begin_frozen_batch(parallel_state, [0, 1, 2] as Array[int], true, true), "shared worker batch starts")
	parallel_results.resize(4)
	var ids: Array[int] = []
	for index in range(parallel_results.size()):
		ids.append(WorkerThreadPool.add_task(parallel_query.bind(index), false, "Native frozen equality"))
	for id in ids: WorkerThreadPool.wait_for_task_completion(id)
	for index in range(parallel_results.size()): check(int(parallel_results[index]) == 0, "worker %d returned exact fields for every query" % index)
	queries(parallel_state)
	NativeCompute.end_frozen_batch(parallel_state)

func compare_trade(state: GameState, graph: Dictionary, allowed: PackedByteArray) -> void:
	for operational in [false, true]:
		for blocked in [{}, {GameState.edge_key(0, 4): true}]:
			var starts: Array[int] = [3, 0, 3]
			var besieged := {3: true}
			var expected := TradeNetwork._dijkstra_field_gdscript(state, graph, starts, allowed, operational, besieged, blocked)
			var actual := TradeNetwork._dijkstra_field(state, graph, starts, allowed, operational, besieged, blocked)
			same(expected, actual, "trade operational=%s blocked=%s" % [operational, blocked])

func trade_batches() -> void:
	var state := fixture()
	var graph := TradeNetwork._build_graph(state)
	var allowed := PackedByteArray()
	allowed.resize(state.cities.size())
	allowed.fill(1)
	compare_trade(state, graph, allowed)
	NativeCompute.set_profiling_for_tests(true)
	check(NativeCompute.begin_trade_batch(state, graph), "trade batch starts")
	check(not NativeCompute.begin_trade_batch(state, graph), "overlapping trade batch is rejected")
	compare_trade(state, graph, allowed)
	allowed[10] = 0
	compare_trade(state, graph, allowed)
	check(int(NativeCompute.profile_snapshot().get("trade_batch_pack_count", 0)) == 1, "trade weights prepared once for ideal and operational queries")
	NativeCompute.end_trade_batch(state)
	NativeCompute.set_profiling_for_tests(false)
	var starts: Array[int] = [0]
	var before := TradeNetwork._dijkstra_field(state, graph, starts, allowed, true, {}, {})
	state.edges[0].precise_distance = 4.75
	state.edges[0].travel_time_multiplier = 1.75
	state.edges[1].max_manpower = 0
	var after := TradeNetwork._dijkstra_field(state, graph, starts, allowed, true, {}, {})
	check(var_to_bytes(before) != var_to_bytes(after), "standalone trade observes capacity and cost edits after retirement")
	compare_trade(state, graph, allowed)
	var old_native: RefCounted = NativeCompute._trade_graph(state, graph).graph
	# Trade graph construction has its own adjacency and edge lookup. A new
	# source Dictionary with the same dimensions must configure fresh CSR.
	state.edges[0].city_b = 8
	var replacement := TradeNetwork._build_graph(state)
	var new_native: RefCounted = NativeCompute._trade_graph(state, replacement).graph
	check(old_native != new_native, "replacement trade source graph retires prior CSR")
	compare_trade(state, replacement, allowed)

func run() -> void:
	NativeCompute.set_backend_for_tests("native")
	for mirror in [false, true]:
		direct_control_edits(mirror)
		var state := fixture(mirror)
		frozen_queries(state)
		live_edits(state)
		reset_same_instance(state)
	parallel_readers()
	trade_batches()
	NativeCompute.clear_caches_for_tests()
	for message in failures: printerr("NATIVE_FROZEN_FAIL ", message)
	print("NATIVE_FROZEN_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
