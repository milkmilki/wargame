extends SceneTree
## Regression for continuous main-river sampling and feasible dock coverage.
## Uses the actual province_ids transport input, never retired face geometry.
const Generator = preload("res://scripts/core/terrain_map_generator.gd")
const SIZE := Vector2i(32, 32)
const SAMPLING_PATH := "res://scripts/core/river_dock_sampling.gd"
var failures: Array[String] = []
var sampling: Script
var generator: Script = Generator

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_DOCK_COVERAGE_FAIL: ", message)

func river(id: int, a: Vector2, b: Vector2, kind: String = "major") -> Dictionary:
	return MapFeatureContract.make_river(id, PackedVector2Array([a, b]), MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY, 0.85, 0.85, -1, PackedInt32Array(), kind, "sea")

func provinces(horizontal: bool = false) -> Dictionary:
	var ids := PackedInt32Array()
	ids.resize(SIZE.x * SIZE.y)
	for y in range(SIZE.y):
		for x in range(SIZE.x): ids[y * SIZE.x + x] = 0 if (y < 16 if horizontal else x < 16) else 1
	return {"size": SIZE, "ids": ids}

func samples(features: Array, horizontal: bool = false, aspect: float = 1.0) -> Array[Vector2]:
	var input: Dictionary = generator.callv("_hydrology_transport_input", [provinces(horizontal), features, true, aspect, true])
	var result: Array[Vector2] = []
	for reach in input.rivers:
		for sample in reach.dock_samples:
			result.append(reach.path[sample.path_index].lerp(reach.path[sample.path_index + 1], sample.ratio))
	return result

func has_point(points: Array[Vector2], point: Vector2) -> bool:
	for candidate in points:
		if candidate.distance_to(point) < 0.000001: return true
	return false

func same_points(a: Array[Vector2], b: Array[Vector2], label: String) -> void:
	var missing := 0
	var added := 0
	for p in a:
		if not has_point(b, p): missing += 1
	for p in b:
		if not has_point(a, p): added += 1
	check(missing == 0 and added == 0, "%s preserves candidate positions; missing=%d added=%d" % [label, missing, added])

func run() -> void:
	if not ResourceLoader.exists(SAMPLING_PATH):
		check(false, "continuous RiverDockSampling module is missing")
		finish()
		return
	sampling = load(SAMPLING_PATH) as Script
	var arguments := 0
	for method in generator.get_script_method_list():
		if method.name == "_hydrology_transport_input": arguments = method.args.size()
	if arguments < 5:
		check(false, "full_network transport input argument is missing")
		finish()
		return
	var bend := [MapFeatureContract.make_river(0, PackedVector2Array([Vector2(0.1, 0.2), Vector2(0.16, 0.2), Vector2(0.16, 0.32)]), MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)]
	var bend_samples: Array = sampling.call("samples", bend, 2.0)
	check(bend_samples.size() == 40, "0.240 projected river has exactly 40 uniform candidates through a bend")
	var wrong_bend := 0
	for i in range(bend_samples.size()):
		var arc := 0.003 + i * 0.006
		var expected := Vector2(0.1 + arc / 2.0, 0.2) if arc < 0.12 else Vector2(0.16, 0.2 + arc - 0.12)
		if bend_samples[i].position.distance_to(expected) > 0.000001: wrong_bend += 1
	check(wrong_bend == 0, "polyline vertices do not reset the projected sampling phase")
	var whole := [river(0, Vector2(0.5, 0.1), Vector2(0.5, 0.9))]
	var whole_samples := samples(whole)
	var missing := 0
	for i in range(133):
		if not has_point(whole_samples, Vector2(0.5, 0.103 + i * 0.006)): missing += 1
	check(missing == 0, "complete major river has every 0.006 arc sample")
	var split := [river(11, Vector2(0.5, 0.1), Vector2(0.5, 0.237)), river(12, Vector2(0.5, 0.237), Vector2(0.5, 0.613)), river(13, Vector2(0.5, 0.613), Vector2(0.5, 0.9))]
	same_points(whole_samples, samples(split), "artificial reach splitting")
	split.reverse()
	same_points(whole_samples, samples(split), "reordered artificial reaches")
	var tiny: Array = []
	for i in range(12): tiny.append(river(20 + i, Vector2(0.5, 0.2 + i * 0.002), Vector2(0.5, 0.2 + (i + 1) * 0.002)))
	same_points(samples([river(0, Vector2(0.5, 0.2), Vector2(0.5, 0.224))]), samples(tiny), "sub-spacing artificial reaches")
	var short_samples := samples([river(0, Vector2(0.5, 0.4001), Vector2(0.5, 0.4019))])
	check(short_samples.size() == 1 and has_point(short_samples, Vector2(0.5, 0.401)), "entire short main river has exactly one midpoint candidate")
	var short_split := samples([river(1, Vector2(0.5, 0.4001), Vector2(0.5, 0.4008)), river(2, Vector2(0.5, 0.4008), Vector2(0.5, 0.4019))])
	check(short_split.size() == 1 and has_point(short_split, Vector2(0.5, 0.401)), "splitting a short river retains its single midpoint")
	check(samples([river(99, Vector2(0.5, 0.1), Vector2(0.5, 0.9), "minor")]).is_empty(), "minor rivers never receive dock candidates")
	var projected := samples([river(0, Vector2(0.1, 0.5), Vector2(0.22, 0.5))], true, 2.0)
	missing = 0
	for i in range(40):
		if not has_point(projected, Vector2(0.1 + (0.003 + i * 0.006) / 2.0, 0.5)): missing += 1
	check(missing == 0, "candidate spacing uses projected distance instead of square PNG distance")
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, (128.0 + 127.0 * 0.85) / 255.0))
	var cities: Array[Vector2] = [Vector2(0.15, 0.5), Vector2(0.85, 0.5)]
	var input: Dictionary = generator.callv("_hydrology_transport_input", [provinces(), whole, true, 1.0, true])
	var occupied: Array[Vector2] = cities.duplicate()
	var selected := Generator._select_boundary_river_docks(image, input.rivers[0], input.graph.segments, cities, occupied, 2, 1.0, [0, 1])
	var upstream := 0
	var downstream := 0
	var coverage := {}
	for dock in selected.docks:
		if dock.position.y < 0.1 + 0.8 / 3.0: upstream += 1
		if dock.position.y > 0.9 - 0.8 / 3.0: downstream += 1
		check(dock.height > 0.8, "accepted upstream/downstream docks really occupy high terrain")
		coverage[int(floor((dock.position.y - 0.1) / 0.036))] = true
	check(upstream > 0 and downstream > 0, "high but flat upstream and downstream both admit actual docks")
	var feasible := {}
	for candidate in selected.candidates: feasible[int(floor((candidate.position.y - 0.1) / 0.036))] = true
	var uncovered := 0
	for window in feasible:
		if not coverage.has(window): uncovered += 1
	check(uncovered == 0, "each feasible flat-river 0.036 window receives a dock; uncovered=%d" % uncovered)
	# Both coverage windows can be served: choose .003 and .039. A greedy
	# extra dock at .033 in the already-covered first window wrongly blocks
	# the only candidate .039 in the second window (spacing is .012).
	var fixture := {"river_id": 50, "path": PackedVector2Array([Vector2(0.5, 0.1), Vector2(0.5, 0.172)]), "edge_indices": [], "hydrological": true, "strict_transport": true, "full_network": true, "dock_samples": []}
	var graph: Array[Dictionary] = []
	for arc in [0.003, 0.033, 0.039]:
		fixture.dock_samples.append({"path_index": 0, "ratio": arc / 0.072, "graph_index": graph.size()})
		graph.append({"a": 0, "b": 1, "cell_a": Vector2i(15, int((0.1 + arc) * SIZE.y)), "cell_b": Vector2i(16, int((0.1 + arc) * SIZE.y))})
	occupied = cities.duplicate()
	var priority := Generator._select_boundary_river_docks(image, fixture, graph, cities, occupied, 2, 1.0, [0, 1])
	var covered_second := false
	for dock in priority.docks:
		if dock.position.y >= 0.136: covered_second = true
	check(covered_second, "uncovered feasible window has priority over redundant dock in an already-covered window")
	print("RIVER_DOCK_COVERAGE_DIAGNOSTIC candidates=%d highland_docks=%d upstream=%d downstream=%d feasible_windows=%d uncovered=%d" % [whole_samples.size(), selected.docks.size(), upstream, downstream, feasible.size(), uncovered])
	finish()

func finish() -> void:
	print("RIVER_DOCK_COVERAGE: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
