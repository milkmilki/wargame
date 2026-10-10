extends SceneTree
## Real reserve orders must remain identical to cf80691 while balanced states
## avoid graph searches. The oracle changes only the balancing function.
const Grid = preload("res://tests/support/grid_world.gd")
const Legacy = preload("res://tests/support/legacy_reserve_simulation.gd")
var failures: Array[String] = []
var checks := 0

class CountingView extends AiWorldView:
	var fields := 0
	func path_field(start: int, allowed_nation: int = -1,
		block_contested_edges: bool = false, use_danger_weight: bool = true,
		allowed_goal: int = -1, required_manpower: int = 0) -> Dictionary:
		fields += 1
		return super.path_field(start, allowed_nation, block_contested_edges,
			use_danger_weight, allowed_goal, required_manpower)

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func run() -> void:
	for queued in [false, true]:
		for case in [
			["balanced", [0, 2, 4], false],
			["within_one", [0, 0, 2, 4], false],
			["unbalanced", [0, 0, 0, 0], true],
			["equal_targets", [0, 0, 0, 4], true],
			["fu_balanced", [1, 3, 4], false],
			["fu_unbalanced", [1, 1, 1, 1], true],
			["disconnected", [0, 0, 0], false],
			["no_permission", [0, 0, 0], false],
			["no_current_center", [6], true],
			["mobilization_claims", [0, 0, 0], false],
		]:
			compare_case(String(case[0]), case[1], bool(case[2]), queued)
	_atlas_cases()
	for failure in failures: printerr("ATLAS_DAILY_RESERVES_FAIL ", failure)
	print("ATLAS_DAILY_RESERVES_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func fixture(kind: String) -> GameState:
	var state := Grid.new()
	state.generate_world(77301, 3, 8)
	state.day = 100
	state.armies.clear()
	state.edges.clear()
	state.edge_lookup.clear()
	state.adjacency.clear()
	for city in state.cities:
		city.owner_nation = 1 if city.id == 5 else (2 if city.id == 7 else 0)
		city.map_position = Vector2(city.id / 8.0, 0.5)
		city.food_storage = 100000
		state.adjacency[city.id] = [] as Array[int]
	state.administrative_center_by_city = PackedInt32Array([0, 0, 2, 2, 4, 5, -1, 7])
	state.administrative_center_city_ids = [0, 2, 4, 5, 7] as Array[int]
	state.administrative_region_count = 5
	for pair in [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [1, 6]]:
		if kind == "disconnected" and pair == [1, 2]: continue
		state._add_edge(pair[0], pair[1])
	if kind == "no_permission": state.cities[1].owner_nation = 1
	state.nations[0].capital_city_id = 0
	state.nations[1].capital_city_id = 5
	state.nations[2].capital_city_id = 7
	state._initialize_recognized_city_owners()
	state.ownership_revision += 1
	state.road_network_revision += 1
	return state

func add_army(state: GameState, owner: int, city: int) -> void:
	var army := Army.new()
	army.id = state.armies.size()
	army.owner_nation = owner
	army.location_city = city
	army.move_from = city
	army.size = 15000
	army.max_size = 15000
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	state.armies.append(army)

func compare_case(label: String, positions: Array, expect_change: bool, queued: bool) -> void:
	var old_state := fixture(label)
	var new_state := fixture(label)
	for position in positions:
		add_army(old_state, 0, int(position))
		add_army(new_state, 0, int(position))
	_compare(label, old_state, new_state, 0, expect_change, queued,
		label in ["balanced", "within_one", "fu_balanced", "mobilization_claims"])

func _compare(label: String, old_state: GameState, new_state: GameState,
	owner: int, expect_change: bool, queued: bool, expect_no_search: bool) -> void:
	var old_sim := Legacy.new()
	# --baseline-repro deliberately runs the original implementation as the
	# candidate. Behavioral assertions pass, the avoidable-search guard fails.
	var new_sim: Simulation = Legacy.new() if OS.get_cmdline_user_args().has("--baseline-repro") else Simulation.new()
	old_sim.setup(old_state)
	new_sim.setup(new_state)
	var old_view := CountingView.new()
	var new_view := CountingView.new()
	old_view.state = old_state; old_view.nation_id = owner; old_view.day = old_state.day
	new_view.state = new_state; new_view.nation_id = owner; new_view.day = new_state.day
	var old_plan := CityDefensePlan.new(); old_plan.view = old_view
	var new_plan := CityDefensePlan.new(); new_plan.view = new_view
	var claims := {}
	var ids := {}
	for army in old_state.armies:
		ids[army.id] = true
		if label == "mobilization_claims": claims[army.id] = true
	if queued:
		old_sim._begin_ai_command_collection(ids)
		new_sim._begin_ai_command_collection(ids)
	var before := NativeSnapshotBuilder.build(old_state)
	check(before == NativeSnapshotBuilder.build(new_state), label + " equal inputs")
	var old_changed: bool = old_sim._balance_national_reserves(owner, old_plan, claims)
	var new_changed: bool = new_sim._balance_national_reserves(owner, new_plan, claims)
	check(old_changed == expect_change, label + " fixture produces expected real orders")
	check(new_changed == old_changed, label + " change result preserved")
	if queued:
		check(intents(old_sim) == intents(new_sim), label + " queued commands and full prepared paths preserved")
		old_sim._commit_ai_command_collection([owner] as Array[int])
		new_sim._commit_ai_command_collection([owner] as Array[int])
	check(NativeSnapshotBuilder.build(old_state) == NativeSnapshotBuilder.build(new_state),
		label + " complete simulation state including RNG, orders, paths, resources preserved")
	check(order_metadata(old_state) == order_metadata(new_state),
		label + " order explanations and deployment locks preserved")
	check(new_state.rng.state == before.rng_state, label + " reserve balancing does not consume RNG")
	if expect_no_search:
		check(new_view.fields == 0, label + " balanced reserves require no graph searches")
		if label != "mobilization_claims": check(old_view.fields > 0, label + " baseline reproduction performs avoidable graph searches")
	print("RESERVE_CASE ", label, " queued=", queued, " changed=", new_changed,
		" fields_before=", old_view.fields, " fields_after=", new_view.fields)
	old_sim.free(); new_sim.free()

func intents(sim: Simulation) -> Array:
	var rows := []
	for intent in sim._ai_command_buffer:
		rows.append([intent.army.id, intent.nation_id, intent.sequence, intent.prepared_path,
			intent.path_prevalidated, intent.candidate.kind, intent.candidate.target_city,
			intent.candidate.minimum_commit_days, intent.candidate.defensive_deployment,
			intent.candidate.score, intent.candidate.reason])
	return rows

func order_metadata(state: GameState) -> Array:
	var rows := []
	for army in state.armies:
		rows.append([army.id, army.ai_order_reason, army.defensive_deployment_until_day,
			army.defensive_blocked_edge_a, army.defensive_blocked_edge_b])
	return rows

func _atlas_cases() -> void:
	var payload: Dictionary = preload("res://tests/atlas_military_inputs.gd").military()
	var old_state := GameState.new(); old_state.generate_from_atlas(payload)
	var new_state := GameState.new(); new_state.generate_from_atlas(payload)
	var owner := -1
	var centers: Array[int] = []
	for nation in old_state.nations:
		centers.clear()
		for center in old_state.administrative_center_city_ids:
			if old_state.cities[center].owner_nation == nation.id: centers.append(center)
		if centers.size() >= 3: owner = nation.id; break
	check(owner >= 0, "actual Atlas world has multi-state reserve owner")
	if owner < 0: return
	old_state.armies.clear(); new_state.armies.clear()
	for center in centers:
		add_army(old_state, owner, center)
		add_army(new_state, owner, center)
	_compare("atlas_balanced", old_state, new_state, owner, false, true, true)
	# Select an actual traversable connection inside this country's physical
	# graph; no path-field or military order is mocked in this scenario.
	var source := -1
	for center in centers:
		var field := Pathfinding.dijkstra_field(old_state, center, owner, false, true)
		for target in centers:
			if target != center and float(field.dist.get(target, INF)) < INF:
				source = center
				break
		if source >= 0: break
	check(source >= 0, "actual Atlas owner has an accessible second state")
	if source < 0: return
	old_state.armies.clear(); new_state.armies.clear()
	for _index in range(6):
		add_army(old_state, owner, source)
		add_army(new_state, owner, source)
	_compare("atlas_unbalanced", old_state, new_state, owner, true, true, false)
