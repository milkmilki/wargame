extends SceneTree
const MODULE := "res://scripts/core/terrain_land_components.gd"
var model: Script
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("TERRAIN_LAND_COMPONENTS_FAIL: ", message)

func owner(result: Dictionary, pixel: Vector2i) -> int:
	return model.call("at", result, (Vector2(pixel) + Vector2.ONE * 0.5) / Vector2(result.size))

func run() -> void:
	if not ResourceLoader.exists(MODULE):
		check(false, "fine-resolution land components module is missing")
		finish()
		return
	model = load(MODULE) as Script
	var land := Color(1, 1, 1, 129.0 / 255.0)
	var water := Color(1, 1, 1, 128.0 / 255.0)
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(land)
	for y in range(32): image.set_pixel(16, y, water)
	var divided: Dictionary = model.call("build", image)
	var west := owner(divided, Vector2i(8, 10))
	var east := owner(divided, Vector2i(24, 10))
	check(west >= 0 and east >= 0 and west != east, "one-pixel sea channel separates both land masses")
	check(divided.areas.size() == 2, "complete channel produces exactly two components")
	check(divided.areas.get(west, 0) == 512 and divided.areas.get(east, 0) == 480, "run-length areas conserve original land pixels")
	check(divided.mainland == west, "largest original land mass is the mainland")
	check(owner(divided, Vector2i(16, 10)) == -1, "alpha 128 is sea and cannot be assigned a component")
	check(model.call("at", divided, Vector2(-0.01, 0.5)) == -1 and model.call("at", divided, Vector2(1.0, 0.5)) == -1, "outside-map queries remain unassigned")
	# A 4x4 center-sampled province raster entirely misses this channel.
	var coarse_all_land := true
	for y in range(4):
		for x in range(4):
			if image.get_pixel(x * 8 + 4, y * 8 + 4).a <= 128.0 / 255.0: coarse_all_land = false
	check(coarse_all_land, "fixture truly aliases to one coarse-grid land mass")
	# Edit the same Image instance, not just its resource path. Content must
	# participate in the cache identity and old results must remain stable.
	image.set_pixel(16, 10, land)
	var bridged: Dictionary = model.call("build", image)
	check(owner(bridged, Vector2i(8, 10)) == owner(bridged, Vector2i(24, 10)), "one-pixel orthogonal bridge reconnects the original land masses")
	check(bridged.areas.size() == 1 and bridged.areas.values()[0] == 993, "bridge adds exactly one land pixel")
	check(owner(divided, Vector2i(8, 10)) != owner(divided, Vector2i(24, 10)), "cached prior result does not mutate after source edits")
	image.set_pixel(16, 10, water)
	var restored: Dictionary = model.call("build", image)
	check(owner(restored, Vector2i(8, 10)) != owner(restored, Vector2i(24, 10)), "restoring a sea pixel restores disconnected cached content")
	var diagonal := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	diagonal.fill(water)
	diagonal.set_pixel(2, 2, land)
	diagonal.set_pixel(3, 3, land)
	var diagonals: Dictionary = model.call("build", diagonal)
	check(diagonals.areas.size() == 2 and owner(diagonals, Vector2i(2, 2)) != owner(diagonals, Vector2i(3, 3)), "diagonal contact does not create a four-neighbor land passage")
	diagonal.set_pixel(3, 2, land)
	var elbow: Dictionary = model.call("build", diagonal)
	check(elbow.areas.size() == 1 and elbow.areas.values()[0] == 3, "orthogonal elbow unifies adjacent row runs")
	diagonal.fill(water)
	var sea: Dictionary = model.call("build", diagonal)
	check(sea.mainland == -1 and sea.areas.is_empty() and owner(sea, Vector2i(2, 2)) == -1, "all-sea source has no phantom mainland")
	finish()

func finish() -> void:
	print("TERRAIN_LAND_COMPONENTS: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
