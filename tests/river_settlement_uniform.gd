extends SceneTree
## Settlement access to an established river is geometric, not discharge-ranked.
const MODULE_PATH := "res://scripts/core/river_settlement_support.gd"
const RADIUS := 0.04
const EPS := 0.0001
var failures: Array[String] = []
var model: RefCounted

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_SETTLEMENT_UNIFORM_FAIL: ", message)

func terrain(height: float = 0.1) -> Image:
	var result := Image.create(1024, 1024, false, Image.FORMAT_RGBAF)
	result.fill(Color(1.0, 1.0, 1.0, (128.0 + 127.0 * height) / 255.0))
	return result

func river(id: int, points: PackedVector2Array, kind: String = "minor", flow: float = 1.0) -> Dictionary:
	var result := MapFeatureContract.make_river(id, points, MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY, 0.35, 0.9, -1, PackedInt32Array(), kind, "sea")
	result["flow"] = flow
	return result

func index(features: Array, aspect: float = 2.8) -> Dictionary:
	return model.call("build_index", features, aspect)

func support(river_index: Dictionary, source: Image, position: Vector2) -> float:
	var value := float(model.call("support_at", river_index, source, position))
	check(is_finite(value) and value >= -EPS and value <= 1.0 + EPS, "support remains finite in [0,1] at %s: %s" % [position, value])
	return value

func run() -> void:
	# Missing implementation must be a test failure, not a preload parse error.
	if not ResourceLoader.exists(MODULE_PATH):
		check(false, "missing unified river support module")
		finish()
		return
	var script := load(MODULE_PATH) as Script
	if script == null or not script.can_instantiate():
		check(false, "unified river support module cannot instantiate")
		finish()
		return
	model = script.new()
	if not model.has_method("build_index") or not model.has_method("support_at"):
		check(false, "build_index/support_at API missing")
		finish()
		return
	check(not str(script.get_script_constant_map().get("VERSION", "")).is_empty(), "support algorithm has a cache version")
	var source := terrain()
	var points := PackedVector2Array([Vector2(0.1, 0.5), Vector2(0.9, 0.5)])
	var single := index([river(0, points)])
	check(single.has("radius"), "each support index carries its independent radius")
	if not single.has("radius"):
		finish()
		return
	var wide: Dictionary = model.call("build_index", [river(0, points)], 2.8, 0.08)
	check(support(single, source, Vector2(0.3,0.55)) == 0.0 and support(wide,source,Vector2(0.3,0.55)) > 0.0, "larger-radius index supports newly covered low banks without changing the smaller index")
	var near := Vector2(0.3, 0.5 + RADIUS * 0.25)
	var baseline := support(single, source, near)
	check(support(single, source, Vector2(0.3, 0.53)) > 0.1, "unresolved tributary envelope supports low land beyond former 0.025 radius")
	check(baseline > 0.8, "low flat near-bank land receives useful support without local rain input")
	check(absf(support(single, source, Vector2(0.3, 0.5)) - 1.0) < EPS, "river bank receives full support")
	check(absf(support(single, source, Vector2(0.7, near.y)) - baseline) < EPS, "upstream and downstream bank access are equal")
	for kind in ["minor", "major"]:
		for discharge in [0.5, 32.0, 128.0, 10000.0]:
			var variant := index([river(0, points, kind, discharge)])
			check(absf(support(variant, source, near) - baseline) < EPS, "%s discharge=%s does not change bank support" % [kind, discharge])
	var split := index([
		river(0, PackedVector2Array([points[0], Vector2(0.5, 0.5)])),
		river(1, PackedVector2Array([Vector2(0.5, 0.5), points[1]])),
	])
	var duplicate := index([river(0, points), river(1, points, "major", 9999.0)])
	for x in [0.3, 0.5, 0.7]:
		var query := Vector2(x, near.y)
		check(absf(support(split, source, query) - baseline) < EPS, "splitting a reach does not change support at x=%s" % x)
		check(absf(support(duplicate, source, query) - baseline) < EPS, "duplicate overlapping reaches do not add support at x=%s" % x)
	check(support(single, source, Vector2(0.4, 0.5 + RADIUS * 1.1)) == 0.0, "outside radius has no river support")
	check(support(index([]), source, near) == 0.0, "no river means no river support")
	# Rotation uses projected distance: a horizontal displacement is aspect times
	# its normalized PNG-coordinate length, while vertical units stay unchanged.
	var vertical := index([river(0, PackedVector2Array([Vector2(0.5, 0.1), Vector2(0.5, 0.9)]))])
	check(absf(support(vertical, source, Vector2(0.5 + RADIUS * 0.25 / 2.8, 0.3)) - baseline) < EPS, "equal projected bank distances have equal support")
	check(support(vertical, source, Vector2(0.5 + RADIUS * 1.1 / 2.8, 0.3)) == 0.0, "horizontal support radius respects map aspect")
	# A nearby elevated plateau is not equivalent to an accessible low riverbank.
	var high := terrain(0.2)
	for y in range(510, 515):
		for x in range(high.get_width()):
			high.set_pixel(x, y, Color(1.0, 1.0, 1.0, (128.0 + 127.0 * 0.1) / 255.0))
	check(support(single, high, near) == 0.0, "high bank cannot obtain low valley water merely by horizontal proximity")
	check(absf(support(single, terrain(0.7), near) - baseline) < EPS, "absolute elevation alone does not reduce accessible bank water")
	var rise_supports: Array[float] = []
	for rise in [0.002, 0.020, 0.040]:
		var raised := terrain(0.1 + rise)
		for y in range(510, 515):
			for x in range(raised.get_width()):
				raised.set_pixel(x, y, Color(1.0, 1.0, 1.0, (128.0 + 127.0 * 0.1) / 255.0))
		rise_supports.append(support(single, raised, near))
	check(absf(rise_supports[0] - baseline) < EPS, "small bank rise retains full distance-based supply")
	check(rise_supports[1] > 0.1 and rise_supports[1] < baseline - 0.1, "moderate bank rise smoothly reduces supply")
	check(rise_supports[2] < EPS, "limiting bank rise removes supply")
	# The polyline has only two high endpoints, but its interior crosses a low
	# valley. Querying midway must sample the actual nearest river point's DEM;
	# endpoint-only heights would incorrectly give this raised bank full support.
	var valley := terrain(0.12)
	for y in range(510, 515):
		for x in range(valley.get_width()):
			var river_height := 0.10 if x > 250 and x < 800 else 0.20
			valley.set_pixel(x, y, Color(1.0, 1.0, 1.0, (128.0 + 127.0 * river_height) / 255.0))
	check(absf(support(single, valley, Vector2(0.5, near.y)) - rise_supports[1]) < EPS, "segment interior uses local riverbed elevation rather than endpoint heights")
	print("RIVER_SETTLEMENT_DIAGNOSTIC flat_near_bank=", baseline)
	finish()

func finish() -> void:
	print("RIVER_SETTLEMENT_UNIFORM: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
