extends SceneTree
const Generator := preload("res://scripts/core/terrain_map_generator.gd")
const Hydro := preload("res://scripts/core/terrain_hydrology.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("ROAD_POSTPROCESS_FAIL: ", message)

func _init() -> void:
	var size := Vector2i(32, 32)
	var ids := PackedInt32Array()
	for y in range(size.y):
		for x in range(size.x): ids.append(0 if x < 16 else 1)
	var provinces := {"size": size, "ids": ids}
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 140.0 / 255.0))
	var options := {"image": image, "river_paths": [], "aspect": 1.0}
	var from := Vector2(4.5, 7.5) / Vector2(size)
	var to := Vector2(25.5, 23.5) / Vector2(size)
	var raw := Generator.province_pair_path(ids, size, from, to, 0, 1,
		{Hydro.edge_key(0, 1, size.x * size.y): true})
	check(raw.size() > 2, "reproduce formal grid route")
	var simplified := Generator.simplify_saved_road_path(raw, provinces, 0, 1, options)
	check(simplified == PackedVector2Array([from, to]), "flat formal route becomes an exact diagonal")
	check(raw.size() > 2, "simplification does not mutate saved baseline")
	var detour := PackedVector2Array([Vector2(.2, .5), Vector2(.2, .2), Vector2(.5, .2), Vector2(.8, .2), Vector2(.8, .5)])
	for kind in ["river", "sea", "cliff", "third_province"]:
		var terrain := image.duplicate()
		var labels := ids.duplicate()
		var rivers: Array[PackedVector2Array] = []
		if kind == "river":
			rivers.append(PackedVector2Array([Vector2(.5, .25), Vector2(.5, .75)]))
		elif kind == "third_province":
			for y in range(8, 24):
				for x in range(15, 17): labels[y * size.x + x] = 2
		else:
			for y in range(64, 192):
				terrain.set_pixel(128, y, Color(1, 1, 1, .4 if kind == "sea" else 200.0 / 255.0))
		var checks := {"image": terrain, "river_paths": rivers, "aspect": 1.0}
		var result := Generator.simplify_saved_road_path(detour, {"size": size, "ids": labels}, 0, 1, checks)
		check(result.size() > 2 and result.size() < detour.size(), kind + " keeps a real but simplified detour")
		for i in range(result.size() - 1):
			check(Generator._safe_road_shortcut(result[i], result[i+1], checks), kind + " retains terrain/river legality")
			check(Generator._segment_in_pair_exact(labels, size, result[i], result[i+1], 0, 1), kind + " stays in the two endpoint provinces")
	check(Generator.simplify_saved_road_path(PackedVector2Array([from, to]), provinces, 0, 1, options) == PackedVector2Array([from, to]), "two-point path is stable")
	print("HYDROLOGY_ROAD_PATH_POSTPROCESS: %d failures" % failures)
	quit(1 if failures else 0)
