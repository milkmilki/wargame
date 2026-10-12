extends SceneTree
## Preserve Godot's exact permutation, including equal keys, without ID tie breaks.
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NATIVE_KEY_ORDER_FAIL ", label)

func compare(graph: RefCounted, keys: Array, label: String) -> void:
	var before := var_to_bytes(keys)
	var expected: Array[int] = []
	for index in range(keys.size()):
		expected.append(index)
	expected.sort_custom(func(a: int, b: int) -> bool:
		return EquivariantOrder._key_less(keys[a], keys[b]))
	var result: Dictionary = graph.call("query_key_order", keys)
	check(not result.has("error"), label + ": input accepted")
	if result.has("error"):
		return
	check(result.order == PackedInt32Array(expected), label + ": exact permutation")
	check(var_to_bytes(keys) == before, label + ": immutable inputs")

func run() -> void:
	if not NativeCompute.require_native():
		return
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	check(graph.has_method("query_key_order"), "native key order method exists")
	if not graph.has_method("query_key_order"):
		finish()
		return
	var random := RandomNumberGenerator.new()
	random.seed = 679032
	for count in [0, 1, 2, 15, 16, 17, 31, 64, 127, 523]:
		var ties := []
		for index in range(count):
			ties.append([1, 2, 3])
		compare(graph, ties, "all equal size %d" % count)
		for iteration in range(12):
			var keys := []
			for index in range(count):
				var row: Array[int] = []
				for field in range(random.randi_range(0, 16)):
					row.append(random.randi_range(-2, 2))
				if index % 4 == 0:
					row.append((1 << 60) + random.randi_range(0, 2))
				keys.append(row)
			compare(graph, keys, "random size %d/%d" % [count, iteration])
	compare(graph, [[-9223372036854775807 - 1], [9223372036854775807], [0], [-1]], "int64 endpoints")
	for keys in [[null], [3], ["bad"], [[0.5]], [[false]], [[null]]]:
		var result: Dictionary = graph.call("query_key_order", keys)
		check(result.has("error"), "malformed key rejected")
	integration()
	national_integration()
	finish()

func integration() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(78455)
	state.atlas_layout = {"model": "native-key-order-test"}
	state.armies.clear()
	for index in range(80):
		var army := Army.new()
		army.id = 80 - index
		army.owner_nation = index % state.nations.size()
		army.location_city = index % state.cities.size()
		army.size = 10000 + (index % 5) * 100
		army.max_size = 12000
		if index % 3 == 0:
			army.on_edge = true
			army.move_from = 0
			army.move_to = 1
			army.move_progress = 0.375
		state.armies.append(army)
	# Repeated physical states exercise equal-key ordering, independent of IDs.
	state.armies.append(state.armies[4])
	var expected := state.armies.duplicate()
	var keys := {}
	for army in expected:
		keys[army] = EquivariantOrder.mirror_orbit_army_key(state, army)
	expected.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder._key_less(keys[a], keys[b]))
	var before := var_to_bytes(preload("res://tests/support/native_runtime_fixture.gd").snapshot(state))
	var rng_before := state.rng.state
	NativeCompute.set_backend_for_tests("native")
	NativeCompute.set_profiling_for_tests(true)
	var actual := state.armies.duplicate()
	EquivariantOrder.sort_armies_by_mirror_orbit(actual, state)
	check(actual == expected, "complete army order preserves exact object identities")
	check(int(NativeCompute.profile_snapshot().get("key_order_native_call_count", 0)) == 1, "army batch uses one native ordering call")
	check(state.rng.state == rng_before and before == var_to_bytes(preload("res://tests/support/native_runtime_fixture.gd").snapshot(state)), "ordering leaves world and RNG unchanged")
	NativeCompute.set_profiling_for_tests(false)
	NativeCompute.set_backend_for_tests("compare")
	actual = state.armies.duplicate()
	EquivariantOrder.sort_armies_by_mirror_orbit(actual, state)
	check(actual == expected, "development compare backend preserves the entire order")
	NativeCompute.set_backend_for_tests("gdscript")
	actual = state.armies.duplicate()
	EquivariantOrder.sort_armies_by_mirror_orbit(actual, state)
	check(actual == expected, "GDScript reference backend remains available")

func national_integration() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(49732)
	state.atlas_layout = {"model": "national-key-order-test"}
	var armies: Array[Army] = []
	for index in range(96):
		var army := Army.new()
		army.id = 96 - index
		army.owner_nation = index % state.nations.size()
		army.location_city = index % state.cities.size()
		army.ai_target_city = [0, 1, -1, 1 << 35][index % 4]
		army.size = 14000 + index % 5
		army.max_size = 15000
		army.ai_action = index % 4
		army.ai_order_until_day = index % 7
		army.defensive_deployment_until_day = index % 3
		army.morale = .7 + (index % 2) * .1
		if index % 3 == 0:
			army.on_edge = true
			army.move_from = 0
			army.move_to = 1
			army.move_progress = .25
		armies.append(army)
	armies.append(armies[4])
	for mirrored in [false, true]:
		if mirrored:
			for city in state.cities:
				city.map_position.x = 1.0 - city.map_position.x
			EquivariantOrder._city_rank_cache.clear()
		for owner in range(state.nations.size()):
			for anchor in [-1, 0, 1 << 35]:
				var expected := armies.duplicate()
				expected.sort_custom(func(a: Army, b: Army) -> bool:
					return EquivariantOrder.army_less(state, owner, a, b, anchor))
				NativeCompute.set_backend_for_tests("native")
				NativeCompute.set_profiling_for_tests(true)
				var actual := armies.duplicate()
				EquivariantOrder.sort_armies(actual, state, owner, anchor)
				check(actual == expected, "national order matches legacy comparator, mirror=%s owner=%d anchor=%d" % [mirrored, owner, anchor])
				check(int(NativeCompute.profile_snapshot().get("key_order_native_call_count", 0)) == 1, "national batch uses one native integer-order call")
				NativeCompute.set_profiling_for_tests(false)
	NativeCompute.set_backend_for_tests("compare")
	var compare_order := armies.duplicate()
	EquivariantOrder.sort_armies(compare_order, state, 0)
	NativeCompute.set_backend_for_tests("gdscript")
	var reference := armies.duplicate()
	EquivariantOrder.sort_armies(reference, state, 0)
	check(compare_order == reference, "national development compare backend retains the complete reference order")

func finish() -> void:
	print("NATIVE_KEY_ORDER checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
