extends SceneTree
## Event boundaries may yield frames; movement/contact transactions and their
## RNG order must remain identical to the synchronous physical Atlas graph.
const LegacyEvents = preload("res://tests/support/legacy_atlas_event_simulation.gd")
class CountedState extends GameState:
	var edge_queries := 0
	func edge_of(a: int, b: int) -> Edge:
		edge_queries += 1
		return super.edge_of(a, b)
class CountedSimulation extends Simulation:
	var travel_checks := 0
	var stationary_checks := 0
	func _is_travelling(army: Army) -> bool:
		travel_checks += 1
		if army.state == Army.State.IDLE: stationary_checks += 1
		return super._is_travelling(army)
var failures: Array[String] = []
var checks := 0
var frames := 0

func _initialize() -> void:
	process_frame.connect(func(): frames += 1)
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func run() -> void:
	for kind in ["junction", "opposite_edge", "siege", "convoy", "convoy_idle", "convoy_staggered"]:
		await compare_case(kind)
	await compare_wrapper()
	await external_order_after_yield()
	check_non_arrivals_skip_junction_predicates()
	await road_revision_after_yield()
	for message in failures: printerr("ATLAS_EVENT_SLICING_FAIL ", message)
	print("ATLAS_EVENT_SLICING_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fixture(kind: String) -> GameState:
	var state := CountedState.new()
	state._reset_world(77931)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 2, false)
	state.day = 100
	var traffic_count := 128 if kind.begins_with("convoy") else 4
	for id in range(4 + traffic_count):
		var city := City.new()
		city.id = id
		city.name = "event-city-%d" % id
		city.map_position = Vector2(float(id) / (4 + traffic_count), 0.5)
		city.food_storage = 100000
		city.owner_nation = 1 if id == 1 else 0
		if id >= 4:
			city.node_kind = City.NodeKind.TRAFFIC
			city.owner_nation = -1
			city.politically_active = false
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.administrative_center_by_city.append(id if id < 4 else -1)
	state.administrative_center_city_ids = [0, 1, 2, 3] as Array[int]
	state.nations[0].capital_city_id = 0
	state.nations[1].capital_city_id = 1
	state._initialize_recognized_city_owners()
	state.atlas_layout = {
		"model": "atlas-event-test", "territorial_pairs": [Vector2i(0, 1)],
		"settlement_adjacency": {0: [1, 2, 3], 1: [0], 2: [0, 3], 3: [0, 2]},
		"strategic_routes": {},
	}
	add_edge(state, 0, 4, 0, 0.01)
	add_edge(state, 1, 4, 1, 0.01)
	add_edge(state, 2, 4, 2, 0.01)
	for id in range(4, state.cities.size() - 1):
		add_edge(state, id, id + 1, 2, 0.0002)
	add_edge(state, state.cities.size() - 1, 3, 3, 0.0002)
	if not kind.begins_with("convoy"):
		state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
		state.set_war_objective(0, 1, 1, "event slicing fixture")
	if kind == "junction":
		add_army(state, 0, 0, [4, 1])
		add_army(state, 1, 1, [4, 0])
		add_army(state, 0, 2, [4, 1])
	elif kind == "opposite_edge":
		add_army(state, 0, 0, [4, 1])
		add_army(state, 1, 4, [0])
	elif kind == "siege":
		state.cities[1].garrison_manpower = 15000
		add_army(state, 0, 2, [4, 1])
	else:
		var path: Array[int] = []
		for node in range(4, state.cities.size()): path.append(node)
		path.append(3)
		for _index in range(128): add_army(state, 0, 2, path)
	if kind == "convoy_idle":
		for _index in range(600):
			var idle := Army.new(); idle.id = state.armies.size(); idle.owner_nation = 0
			idle.size = 100; idle.max_size = 100; idle.location_city = 3
			idle.state = Army.State.IDLE; state.armies.append(idle)
	# This stale real army must be removed by the production post-movement
	# cleanup, preserving array order and bindings in both implementations.
	var dead := Army.new()
	dead.id = state.armies.size()
	dead.owner_nation = 0
	dead.location_city = 0
	dead.size = 0
	state.armies.append(dead)
	return state

func check_non_arrivals_skip_junction_predicates() -> void:
	var state := fixture("convoy_idle")
	var sim := CountedSimulation.new()
	sim.state = state
	for army in state.armies:
		if army.size > 0 and army.state == Army.State.MOVING:
			sim._begin_next_leg(army)
			army.move_progress = 0.25
	var before := NativeSnapshotBuilder.build(state)
	sim.travel_checks = 0
	sim._detect_atlas_junction_contacts()
	check(sim.travel_checks == 0, "non-arrivals must skip expensive junction predicates")
	check(NativeSnapshotBuilder.build(state) == before, "skipped junction candidates preserve state and RNG")
	sim.free()

func add_edge(state: GameState, a: int, b: int, control: int, distance: float) -> void:
	var edge := Edge.new()
	edge.city_a = mini(a, b); edge.city_b = maxi(a, b)
	edge.control_city_id = control
	edge.precise_distance = distance
	edge.map_path = PackedVector2Array([state.cities[edge.city_a].map_position,
		state.cities[edge.city_b].map_position])
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(a, b)] = edge
	(state.adjacency[a] as Array[int]).append(b)
	(state.adjacency[b] as Array[int]).append(a)

func add_army(state: GameState, owner: int, start: int, path: Array) -> void:
	var army := Army.new()
	army.id = state.armies.size()
	army.owner_nation = owner
	army.size = 15000
	army.max_size = 15000
	army.morale = army.max_morale
	army.location_city = start
	army.move_from = start
	army.state = Army.State.MOVING
	army.ai_action = ActionCandidate.Kind.ATTACK if state.cities[path[-1]].owner_nation != owner else ActionCandidate.Kind.REINFORCE
	army.ai_target_city = path[-1]
	army.path.assign(path)
	state.armies.append(army)

func compare_case(kind: String) -> void:
	var sync_state := fixture(kind)
	var sliced_state := fixture(kind)
	check(NativeSnapshotBuilder.build(sync_state) == NativeSnapshotBuilder.build(sliced_state), kind + " identical starting state")
	var sync := LegacyEvents.new(); sync.state = sync_state; sync.paused = true
	var sliced := CountedSimulation.new(); sliced.state = sliced_state; sliced.paused = true
	root.add_child(sync); root.add_child(sliced)
	for army in sync_state.armies:
		if army.size > 0 and army.state == Army.State.MOVING: sync._begin_next_leg(army)
	for army in sliced_state.armies:
		if army.size > 0 and army.state == Army.State.MOVING: sliced._begin_next_leg(army)
	if kind == "convoy_staggered":
		for army in sync_state.armies:
			if army.size > 0 and army.id % 2 == 0: army.move_progress = 0.413
		for army in sliced_state.armies:
			if army.size > 0 and army.id % 2 == 0: army.move_progress = 0.413
	(sync_state as CountedState).edge_queries = 0
	(sliced_state as CountedState).edge_queries = 0
	var original_count := sync_state.armies.size()
	var count_before := frames
	sync._advance_atlas_movement()
	check(frames == count_before, kind + " synchronous integration never yields")
	await sliced._advance_atlas_movement(not OS.get_cmdline_user_args().has("--baseline-repro"))
	var event_frames := frames - count_before
	if kind == "convoy_staggered":
		check((sliced_state as CountedState).edge_queries < (sync_state as CountedState).edge_queries * 0.9,
			"unrelated arrivals must not repeatedly query unchanged travelling roads")
		print("STAGGERED_EDGE_QUERIES before=", (sync_state as CountedState).edge_queries,
			" after=", (sliced_state as CountedState).edge_queries)
	check(NativeSnapshotBuilder.build(sync_state) == NativeSnapshotBuilder.build(sliced_state), kind + " events preserve full state, RNG and creation order")
	if kind == "convoy_idle":
		check(sliced.travel_checks < original_count * sliced_state.cities.size() * 1.5,
			"junction queries must reuse current event candidates instead of rescanning idle armies")
		check(sliced.stationary_checks <= 600 * 3,
			"traffic traversal must not repeatedly inspect 600 stationary garrisons")
	if kind.begins_with("convoy"):
		check(event_frames > 0, "large arrival batch yields process frames inside the day")
		for army in sliced_state.armies:
			if army.size > 0: check(army.location_city == 3 and army.state == Army.State.IDLE,
				"convoy reaches destination through 128 junctions in one day")
	elif kind in ["junction", "opposite_edge"]:
		check(sliced_state.battles.size() == 1, kind + " enemies cannot pass without a real field battle")
		if not sliced_state.battles.is_empty():
			check(sliced_state.battles[0].kind == Battle.Kind.FIELD, kind + " traffic contact is field combat")
			if kind == "junction": check(sliced_state.battles[0].traffic_node_id == 4, "junction field battle has physical anchor")
	else:
		check(not sliced_state.battles.is_empty() and sliced_state.battles[0].kind == Battle.Kind.SIEGE,
			"arrival invokes real siege transaction and creates a new battle")
	# Exercise the production battle resolution and dead-array cleanup once,
	# rather than mocking either transaction in the slicing comparison.
	sync._resolve_battles(); sync._purge_dead_armies()
	sliced._resolve_battles(); sliced._purge_dead_armies()
	check(NativeSnapshotBuilder.build(sync_state) == NativeSnapshotBuilder.build(sliced_state), kind + " battle resolution, RNG and removal preserve full state")
	check(sliced_state.armies.size() < original_count, kind + " production cleanup removes dead army")
	occupancy_check(sliced_state, kind)
	print("ATLAS_EVENT_CASE ", kind, " event_frames=", event_frames,
		" armies=", sliced_state.armies.size(), " battles=", sliced_state.battles.size(), " travel_checks=", sliced.travel_checks)
	sync.free(); sliced.free()

func compare_wrapper() -> void:
	var sync_state := fixture("convoy")
	var sliced_state := fixture("convoy")
	var sync := LegacyEvents.new(); sync.state = sync_state; sync.paused = true
	var sliced := Simulation.new(); sliced.state = sliced_state; sliced.paused = true
	root.add_child(sync); root.add_child(sliced)
	var count_before := frames
	sync._advance_movement()
	check(frames == count_before, "production synchronous wrapper never yields")
	await sliced._advance_movement_over_frames()
	check(frames - count_before > 1,
		"production frame wrapper yields within traffic traversal before its mandatory final frame")
	check(NativeSnapshotBuilder.build(sync_state) == NativeSnapshotBuilder.build(sliced_state),
		"production wrappers preserve entire world, ordered army removal and RNG")
	occupancy_check(sliced_state, "convoy_wrapper")
	print("ATLAS_EVENT_WRAPPER frames=", frames - count_before)
	sync.free(); sliced.free()

func occupancy_check(state: GameState, kind: String) -> void:
	var passing := {}
	for army in state.armies:
		if army.on_edge:
			var key := GameState.edge_key(army.move_from, army.move_to)
			passing[key] = int(passing.get(key, 0)) + 1
	for edge in state.edges:
		check(edge.passing_count == int(passing.get(GameState.edge_key(edge.city_a, edge.city_b), 0)),
			kind + " physical road occupation equals surviving army references")


func external_order_after_yield() -> void:
	var state := fixture("convoy_idle")
	var sim := Simulation.new(); sim.state = state; sim.paused = true
	root.add_child(sim)
	# This initially stationary army is absent from the initial road candidates.
	# A legitimate player order arrives while the day yields to the main loop.
	var newcomer := state.armies[128]
	newcomer.location_city = 2; newcomer.move_from = 2
	var issued := {"value":false}
	var callback := func():
		if not issued.value:
			issued.value = true
			check(bool(sim.order_army_to(newcomer, 3).get("ok", false)),
				"player order accepted while movement yields")
	process_frame.connect(callback)
	await sim._advance_atlas_movement(true)
	process_frame.disconnect(callback)
	check(issued.value and newcomer.location_city == 3 and newcomer.state == Army.State.IDLE,
		"new order participates in remaining day after candidate refresh")
	occupancy_check(state, "external_order")
	sim.free()

func road_revision_after_yield() -> void:
	var state := fixture("convoy")
	# A long directed leg remains unchanged while short convoys create events.
	# The real editor refuses bound road edits; force a revision here to verify
	# the movement cache's defensive invalidation and slot reassignment.
	state.edge_of(1, 4).precise_distance = 1.
	add_army(state, 1, 1, [4, 1])
	var long_haul := state.armies[-1]
	var sim := Simulation.new(); sim.state = state; sim.paused = true
	root.add_child(sim)
	for army in state.armies:
		if army.size > 0 and army.state == Army.State.MOVING: sim._begin_next_leg(army)
	var changed := {"value":false,"progress":0.}
	var callback := func():
		if not changed.value:
			changed.value = true; changed.progress = long_haul.move_progress
			state.edge_of(1, 4).precise_distance = 2.
			state.road_network_revision += 1
	process_frame.connect(callback)
	await sim._advance_atlas_movement(true)
	process_frame.disconnect(callback)
	var elapsed_before_change := float(changed.progress) * 10.
	var expected := float(changed.progress) + (1. - elapsed_before_change) / 20.
	check(changed.value and is_equal_approx(long_haul.move_progress, expected),
		"road revision invalidates unchanged leg durations across a frame yield")
	occupancy_check(state, "road_revision")
	sim.free()
