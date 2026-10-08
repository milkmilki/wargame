extends SceneTree
## Exercise the real transport graph: a local slope cannot disappear at a
## feature boundary or at a dock placed on a confluence.
const Transport = preload("res://scripts/core/river_transport.gd")
const Navigation = preload("res://scripts/core/river_navigation.gd")
var failures: Array[String] = []

func _init() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("CANONICAL_NAVIGATION_CONTEXT_FAIL: ", message)

func dem(kind: String) -> Image:
	var image := Image.create(4096, 16, false, Image.FORMAT_RGBA8)
	for x in range(image.get_width()):
		var height := 0.85
		if kind == "cliff": height = 0.10 if x < 2040 else (0.25 if x < 2056 else 0.40)
		if kind == "gentle": height = 0.10 + 0.70 * float(x) / 4095.0
		for y in range(image.get_height()):
			image.set_pixel(x, y, Color(1, 1, 1, (128.0 + 127.0 * height) / 255.0))
	return image

func river(id: int, points: Array, downstream: int = -1, upstream: PackedInt32Array = PackedInt32Array()) -> Dictionary:
	return MapFeatureContract.make_river(id, PackedVector2Array(points), MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY, 0.72, 1.18, downstream, upstream)

func dock(city: int, river_id: int, progress: float, point: Vector2) -> Dictionary:
	return {"city_id": city, "river_id": river_id, "river_progress": progress, "position": point}

func has_pair(roads: Array, a: int, b: int) -> bool:
	for road in roads:
		if int(road.a) == mini(a, b) and int(road.b) == maxi(a, b): return true
	return false

func run() -> void:
	var source := Vector2(0.05, 0.5)
	var junction := Vector2(0.5, 0.5)
	var mouth := Vector2(0.95, 0.5)
	var whole := [river(0, [source, mouth])]
	var split := [river(0, [source, junction], 1), river(1, [junction, mouth], -1, PackedInt32Array([0]))]
	var whole_docks := [dock(0, 0, 0.0, source), dock(1, 0, 0.5, junction), dock(2, 0, 1.0, mouth)]
	var split_docks := [dock(0, 0, 0.0, source), dock(1, 1, 0.0, junction), dock(2, 1, 1.0, mouth)]
	var cliff := dem("cliff")
	var assessment := Navigation.assess(PackedVector2Array([source, mouth]), cliff, 1.0)
	check(not assessment.navigable and assessment.max_local_height_difference > 0.29, "fixture contains a >0.2 height change inside one 0.012 window")
	var unsplit_roads := Transport.build(whole, whole_docks, cliff, 1.0, true)
	check(unsplit_roads.is_empty(), "dock inside an unsplit steep reach must not reopen either side")
	var split_roads := Transport.build(split, split_docks, cliff, 1.0, true)
	check(split_roads.is_empty(), "splitting the identical river at the dock must preserve blocked navigation")
	# Even when no dock lies exactly on the boundary, the assessment window
	# around the nearby dock must continue onto the downstream feature.
	var near := Vector2(2047.0 / 4096.0, 0.5)
	var near_docks := [dock(0, 0, 0.0, source), dock(1, 0, (near.x - source.x) / (junction.x - source.x), near)]
	check(Transport.build(split, near_docks, cliff, 1.0, true).is_empty(), "a nearby terminal cannot truncate its height window at a feature boundary")
	var confluence := split.duplicate(true)
	confluence[1].upstream_ids = PackedInt32Array([0, 2])
	confluence.append(river(2, [Vector2(0.5, 0.8), junction], 1))
	var confluence_docks := split_docks.duplicate(true)
	confluence_docks.append(dock(3, 2, 0.0, Vector2(0.5, 0.8)))
	var joined_roads := Transport.build(confluence, confluence_docks, cliff, 1.0, true)
	check(not has_pair(joined_roads, 0, 1) and not has_pair(joined_roads, 1, 2), "confluence dock must not reopen the two sides of the trunk cliff")
	# An arbitrary sequence of short features cannot reset the local window.
	var short_features: Array = []
	var short_docks: Array = []
	for i in range(9):
		var point := Vector2(0.484 + 0.004 * i, 0.5)
		if i < 8:
			short_features.append(river(i, [point, point + Vector2(0.004, 0)], i + 1 if i < 7 else -1, PackedInt32Array([i - 1]) if i > 0 else PackedInt32Array()))
		short_docks.append(dock(i, mini(i, 7), 0.0 if i < 8 else 1.0, point))
	var short_roads := Transport.build(short_features, short_docks, cliff, 1.0, true)
	check(not has_pair(short_roads, 3, 4) and not has_pair(short_roads, 4, 5), "window extends across multiple short features on both sides of the cliff")
	for kind in ["high", "gentle"]:
		var image := dem(kind)
		var roads := Transport.build(split, split_docks, image, 1.0, true)
		check(has_pair(roads, 0, 1) and has_pair(roads, 1, 2), kind + " terrain remains navigable across feature boundaries")
		for road in roads:
			var edge := Edge.new()
			edge.kind = Edge.Kind.RIVER
			edge.max_height_difference = road.height_difference
			edge.river_navigation = road.river_navigation
			check(edge.river_is_navigable(), kind + " terrain stays navigable in runtime Edge")
	check(Transport.build(whole, [whole_docks[0], whole_docks[2]], dem("gentle"), 1.0, false).is_empty(), "legacy mode retains whole-reach height restriction")
	print("CANONICAL_NAVIGATION_CONTEXT_DIAGNOSTIC unsplit=%d split=%d confluence=%d short=%d" % [unsplit_roads.size(), split_roads.size(), joined_roads.size(), short_roads.size()])
	print("CANONICAL_NAVIGATION_CONTEXT: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
