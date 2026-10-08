extends SceneTree
## A province may wrap around a river source; its landing road must also go around.
const Generator = preload("res://scripts/core/terrain_map_generator.gd")
const Hydrology = preload("res://scripts/core/terrain_hydrology.gd")
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("HYDROLOGY_LANDING_BARRIERS_FAIL: ", message)

func _crosses(path: PackedVector2Array, river: PackedVector2Array) -> bool:
	for i in range(path.size() - 1):
		for j in range(river.size() - 1):
			var a := path[i]
			var b := path[i + 1]
			var c := river[j]
			var d := river[j + 1]
			if (b - a).cross(c - a) * (b - a).cross(d - a) < 0.0 and (d - c).cross(a - c) * (d - c).cross(b - c) < 0.0:
				return true
	return false

func _candidate_fixture(features: Array[Dictionary]) -> Dictionary:
	var size := Vector2i(10, 10)
	var ids := PackedInt32Array()
	ids.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			ids[y * size.x + x] = 0 if x < 5 else 1
	var provinces := {"size": size, "ids": ids}
	var boundary := Generator._hydrology_transport_input(provinces, features)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 129.0 / 255.0))
	var positions: Array[Vector2] = [Vector2(0.25, 0.55), Vector2(0.75, 0.55)]
	var samples := {"positions": positions, "heights": [0.1, 0.1]}
	var empty_roads: Array[Dictionary] = []
	var transport := Generator._build_boundary_river_transport(image, samples, empty_roads, provinces, boundary, 2, 1.0, 2)
	return {"boundary": boundary, "transport": transport}

func _close_river_candidates() -> void:
	var first := MapFeatureContract.make_river(0, PackedVector2Array([Vector2(0.48, 0.0), Vector2(0.48, 1.0)]), "procedural_hydrology")
	var second := MapFeatureContract.make_river(1, PackedVector2Array([Vector2(0.52, 0.0), Vector2(0.52, 1.0)]), "procedural_hydrology")
	var single := _candidate_fixture([first])
	_check(not single.boundary.graph.segments.is_empty(), "a single river crossing the province edge remains a legal dock candidate")
	_check(not single.transport.docks.is_empty(), "a single river still produces actual docks")
	# Each center-to-dock approach for one river crosses the other river first.
	# No intermediate coarse cell exists between these two close parallel channels.
	var paired := _candidate_fixture([first, second])
	_check(paired.boundary.graph.segments.is_empty(), "two close main rivers crossing the same center edge cannot create a two-bank dock")
	for river in paired.boundary.rivers:
		_check(river.dock_samples.is_empty(), "unsafe close-river candidates are excluded before selection")
	_check(paired.transport.docks.is_empty(), "unsafe close-river candidates produce no docks")
	# The same ambiguity can come from two bends of ONE polyline, not just two IDs.
	var hairpin := MapFeatureContract.make_river(0, PackedVector2Array([Vector2(0.48, 0.0), Vector2(0.48, 0.97), Vector2(0.52, 0.97), Vector2(0.52, 0.0)]), "procedural_hydrology")
	var bent := _candidate_fixture([hairpin])
	_check(bent.boundary.graph.segments.is_empty(), "a repeated crossing of the same river is not incorrectly exempted by river ID")
	_check(bent.transport.docks.is_empty(), "an unresolved hairpin crossing produces no docks")
	print("CLOSE_RIVER_DOCK_DIAGNOSTIC single_docks=", single.transport.docks.size(), " paired_docks=", paired.transport.docks.size(), " hairpin_docks=", bent.transport.docks.size())

func _run() -> void:
	_close_river_candidates()
	var size := Vector2i(10, 10)
	var ids := PackedInt32Array()
	var land := PackedByteArray()
	ids.resize(size.x * size.y)
	land.resize(ids.size())
	land.fill(1)
	for y in range(size.y):
		for x in range(size.x):
			ids[y * size.x + x] = 0 if x < 8 else 1
	var target_river := PackedVector2Array([Vector2(0.8, 0.0), Vector2(0.8, 1.0)])
	var other_river := PackedVector2Array([Vector2(0.5, 0.20), Vector2(0.5, 0.80)])
	var features: Array[Dictionary] = [
		MapFeatureContract.make_river(0, target_river, "procedural_hydrology"),
		MapFeatureContract.make_river(1, other_river, "procedural_hydrology"),
	]
	var positions: Array[Vector2] = [Vector2(0.25, 0.55), Vector2(0.95, 0.55)]
	var dock_position := Vector2(0.8, 0.55)
	var bank := Vector2i(7, 5)
	var blocked := Hydrology.barriers(features, size)
	var bank_center := (Vector2(bank) + Vector2(0.5, 0.5)) / Vector2(size)
	var legal := Generator.province_pair_path(ids, size, positions[0], bank_center, 0, 0, blocked)
	_check(legal.size() >= 2 and not _crosses(legal, other_river), "fixture has an existing legal same-province detour around the other river")
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.60))
	var provinces := {"size": size, "ids": ids}
	var boundary := Generator._hydrology_transport_input(provinces, features)
	var samples := {"positions": positions, "heights": [0.1, 0.1]}
	var dock := {"city_id": 2, "river_id": 0, "river_progress": 0.55, "position": dock_position, "height": 0.1, "bank_a": 0, "bank_b": 1, "cell_a": bank, "cell_b": Vector2i(8, 5)}
	var empty_roads: Array[Dictionary] = []
	var transport := Generator._build_boundary_river_transport(image, samples, empty_roads, provinces, boundary, 2, 1.0, 2, [dock], true)
	var found := false
	for road in transport.roads:
		if road.kind != Edge.Kind.LANDING or road.a != 0:
			continue
		found = true
		_check(road.map_path[0].is_equal_approx(positions[0]) and road.map_path[-1].is_equal_approx(dock_position), "landing route keeps city and destination dock endpoints")
		var crosses := _crosses(road.map_path, other_river)
		_check(not crosses, "LANDING route illegally crosses unrelated major river at (0.5, 0.55) instead of taking the available detour")
		print("LANDING_DIAGNOSTIC map_path=", road.map_path, " crosses_other_major=", crosses)
	_check(found, "the existing dock remains reachable from its bank city")
	# A validator must reject malformed imported/rebuilt landing roads too;
	# checking only ordinary LAND roads leaves the same bypass undetected.
	var illegal_roads: Array[Dictionary] = [
		{"a": 0, "b": 2, "kind": Edge.Kind.LANDING, "map_path": PackedVector2Array([positions[0], dock_position])},
		{"a": 1, "b": 2, "kind": Edge.Kind.LANDING, "map_path": PackedVector2Array([positions[1], dock_position])},
	]
	var invalid_transport := {"roads": illegal_roads, "docks": [dock]}
	var accepts_illegal := Generator._hydrology_transport_valid(invalid_transport, positions, image, land, {"features": features})
	_check(not accepts_illegal, "transport validation rejects LANDING shortcuts crossing an unrelated major river")
	print("LANDING_VALIDATION_DIAGNOSTIC accepted_illegal=", accepts_illegal)
	if not _failures.is_empty():
		quit(1)
		return
	print("HYDROLOGY_LANDING_BARRIERS_OK")
	quit()
