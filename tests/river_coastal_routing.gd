extends SceneTree
## Fine land remains usable when all corresponding coarse cell centers are sea.
const Generator = preload("res://scripts/core/terrain_map_generator.gd")
const SIZE := Vector2i(8, 8)
const SOURCE_SIZE := Vector2i(128, 128)
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_COASTAL_ROUTING_FAIL: ", message)

func fixture(split: bool, closes_channel: bool = false) -> Dictionary:
	var ids := PackedInt32Array()
	ids.resize(SIZE.x * SIZE.y)
	for y in range(SIZE.y):
		for x in range(SIZE.x): ids[y * SIZE.x + x] = 1 if split and x >= 4 else 0
	var image := Image.create(SOURCE_SIZE.x, SOURCE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 141.0 / 255.0))
	# Bay reaches south past the last coarse center y=120, but the four
	# original pixel rows y=124..127 provide a real, legal land passage.
	for y in range(128 if closes_channel else 124):
		for x in range(64, 80): image.set_pixel(x, y, Color(1, 1, 1, 120.0 / 255.0))
	return {"ids": ids, "image": image}

func route(f: Dictionary, from: Vector2, to: Vector2, split: bool, rivers: Array[PackedVector2Array] = []) -> PackedVector2Array:
	return Generator.province_pair_path(f.ids, SIZE, from, to, 0, 1 if split else 0, {}, {"strict": true, "pixel_fallback": true, "image": f.image, "aspect": 1.0, "river_paths": rivers})

func validate_path(path: PackedVector2Array, f: Dictionary, from: Vector2, to: Vector2, split: bool, label: String) -> void:
	check(path.size() >= 3, label + " finds a genuine coastal detour")
	if path.is_empty(): return
	check(path[0].distance_to(from) < 0.000001 and path[-1].distance_to(to) < 0.000001, label + " preserves exact city endpoints")
	check(path.size() < 12, label + " simplifies the pixel route rather than displaying every pixel step")
	var deepest := 0.0
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var steps := maxi(1, ceili(((b - a) * Vector2(SOURCE_SIZE)).length() * 8.0))
		for step in range(steps + 1):
			var point := a.lerp(b, float(step) / steps)
			deepest = maxf(deepest, point.y)
			var pixel := Vector2i(point * Vector2(SOURCE_SIZE)).clamp(Vector2i.ZERO, SOURCE_SIZE - Vector2i.ONE)
			if f.image.get_pixelv(pixel).a <= 128.0 / 255.0:
				check(false, label + " shortcut enters original DEM sea at %s" % pixel)
				return
			var cell := Vector2i(point * Vector2(SIZE)).clamp(Vector2i.ZERO, SIZE - Vector2i.ONE)
			var owner := int(f.ids[cell.y * SIZE.x + cell.x])
			if owner != 0 and not (split and owner == 1):
				check(false, label + " leaves the permitted province pair")
				return
	check(deepest >= 124.0 / 128.0, label + " actually uses the four-pixel coastal passage")

func run() -> void:
	var from := Vector2(32.5, 64.5) / Vector2(SOURCE_SIZE)
	var to := Vector2(96.5, 64.5) / Vector2(SOURCE_SIZE)
	for split in [false, true]:
		var f := fixture(split)
		var path := route(f, from, to, split)
		validate_path(path, f, from, to, split, "adjacent provinces" if split else "same province")
		var repeated := route(f, from, to, split)
		check(path == repeated, "pixel fallback remains deterministic")
		var closed := fixture(split, true)
		check(route(closed, from, to, split).is_empty(), "true full-height sea channel never receives a LAND path")
		# The only fine land corridor is owned by a third province; fallback
		# cannot expand its allowed territory simply to satisfy connectivity.
		var excluded := fixture(split)
		for x in range(SIZE.x): excluded.ids[7 * SIZE.x + x] = 2
		check(route(excluded, from, to, split).is_empty(), "coastal fallback cannot use a third province")
	var blocked := fixture(true)
	var main_river := PackedVector2Array([Vector2(0.5, 0), Vector2(0.5, 1)])
	check(route(blocked, from, to, true, [main_river]).is_empty(), "fine fallback does not cross a full-height main river")
	# A source mutation at the formerly open coast must not reuse stale path
	# or sampled-height data from the same Image object.
	var changed := fixture(false)
	var open_path := route(changed, from, to, false)
	for y in range(124, 128):
		for x in range(64, 80): changed.image.set_pixel(x, y, Color(1, 1, 1, 120.0 / 255.0))
	check(route(changed, from, to, false).is_empty(), "closing the same source image invalidates the formerly open route")
	print("RIVER_COASTAL_ROUTING_DIAGNOSTIC open_path_points=%d" % open_path.size())
	print("RIVER_COASTAL_ROUTING: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
