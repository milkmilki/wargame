extends SceneTree
## Province adjacency uses intersections with the original river polyline.
## Fixtures avoid exact center touches; tangency policy is a separate contract.
const Hydrology = preload("res://scripts/core/terrain_hydrology.gd")
const CELLS := Vector2i(10, 8)
var _failures: Array[String] = []
var _completed := false

func _init() -> void:
	call_deferred("_run")
	# An assertion inside the old grid-only implementation aborts that call stack.
	# A second deferred callback still exits the test instead of hanging forever.
	call_deferred("_verify_completion")

func _verify_completion() -> void:
	if not _completed:
		printerr("HYDROLOGY_VECTOR_BARRIERS_FAIL: arbitrary river geometry aborted barrier construction")
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("HYDROLOGY_VECTOR_BARRIERS_FAIL: ", message)

func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	# Independent proper-intersection oracle. No rounding or grid-edge conversion.
	return (b - a).cross(c - a) * (b - a).cross(d - a) < 0.0 and (d - c).cross(a - c) * (d - c).cross(b - c) < 0.0

func _expected(points: PackedVector2Array) -> Dictionary:
	var result := {}
	var count := CELLS.x * CELLS.y
	for y in range(CELLS.y):
		for x in range(CELLS.x):
			var p := Vector2i(x, y)
			var a := (Vector2(p) + Vector2(0.5, 0.5)) / Vector2(CELLS)
			for step in [Vector2i.RIGHT, Vector2i.DOWN]:
				var q: Vector2i = p + step
				if not Rect2i(Vector2i.ZERO, CELLS).has_point(q):
					continue
				var b := (Vector2(q) + Vector2(0.5, 0.5)) / Vector2(CELLS)
				for i in range(points.size() - 1):
					if _crosses(a, b, points[i], points[i + 1]):
						var first := p.y * CELLS.x + p.x
						var second := q.y * CELLS.x + q.x
						result[mini(first, second) * count + maxi(first, second)] = true
	return result

func _component_count(blocked: Dictionary) -> int:
	var land := PackedByteArray()
	land.resize(CELLS.x * CELLS.y)
	land.fill(1)
	var ids := Hydrology.components(land, CELLS, blocked)
	var unique := {}
	for id in ids:
		unique[id] = true
	return unique.size()

func _assert_geometry(label: String, points: PackedVector2Array, expected_components: int) -> Dictionary:
	var original := points.duplicate()
	var feature := {"river_class": "major", "points": points}
	var blocked := Hydrology.barriers([feature], CELLS)
	var expected := _expected(points)
	_check(not expected.is_empty(), label + " fixture crosses province adjacency edges")
	_check(_component_count(expected) == expected_components, label + " oracle geometry has the intended connectivity")
	_check(blocked.size() == expected.size(), "%s blocks exactly the crossed edges: actual=%d expected=%d" % [label, blocked.size(), expected.size()])
	for key in expected:
		_check(blocked.has(key), "%s missed vector intersection at edge %s" % [label, key])
	_check(feature.points == original, label + " preserves authoritative unsnapped river geometry")
	var components := _component_count(blocked)
	_check(components == expected_components, "%s connected components: actual=%d expected=%d" % [label, components, expected_components])
	print("VECTOR_BARRIER_DIAGNOSTIC fixture=%s edges=%d components=%d" % [label, blocked.size(), components])
	return blocked

func _run() -> void:
	var diagonal := PackedVector2Array([Vector2(0.17, 0.0), Vector2(0.83, 1.0)])
	var bent := PackedVector2Array([Vector2(0.14, 0.0), Vector2(0.43, 0.31), Vector2(0.39, 0.68), Vector2(0.71, 1.0)])
	var partial := PackedVector2Array([Vector2(0.23, 0.18), Vector2(0.49, 0.52), Vector2(0.77, 1.0)])
	_assert_geometry("complete_diagonal", diagonal, 2)
	var major := _assert_geometry("complete_bent", bent, 2)
	_assert_geometry("inland_source_can_be_bypassed", partial, 1)
	var minor := {"river_class": "minor", "points": diagonal}
	var minor_only := Hydrology.barriers([minor], CELLS)
	_check(minor_only.is_empty(), "minor rivers do not block province adjacency")
	_check(_component_count(minor_only) == 1, "minor rivers do not separate land components")
	var mixed := Hydrology.barriers([{"river_class": "major", "points": bent}, minor], CELLS)
	_check(mixed == major, "adding a minor river leaves major barriers unchanged")
	_completed = true
	if not _failures.is_empty():
		quit(1)
		return
	print("HYDROLOGY_VECTOR_BARRIERS_OK")
	quit()
