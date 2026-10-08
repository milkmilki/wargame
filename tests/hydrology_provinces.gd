extends SceneTree
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
func _init() -> void:
	var size := Vector2i(12, 8)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.6))
	var land := PackedByteArray()
	land.resize(size.x * size.y)
	land.fill(1)
	var points := PackedVector2Array()
	for y in range(size.y + 1): points.append(Vector2(6.0 / size.x, float(y) / size.y))
	var river := MapFeatureContract.make_river(0, points, "procedural_hydrology")
	var barriers := Hydro.barriers([river], size)
	var pixels: Array[Vector2i] = [Vector2i(2, 4)]
	var generator = load("res://scripts/core/terrain_map_generator.gd")
	var empty_paths: Array[Array] = []
	var provinces: Dictionary = generator.callv("_build_province_raster", [image, land, Rect2i(Vector2i.ZERO, size), pixels, empty_paths, 1.0, true, barriers])
	assert(not provinces.is_empty())
	for y in range(size.y):
		assert(provinces.ids[y * size.x + 2] == 0)
		assert(provinces.ids[y * size.x + 9] == -1)
	river.river_class = "minor"
	assert(Hydro.barriers([river], size).is_empty())
	# A finite river can be walked around at its source.
	river.river_class = "major"
	river.points = points.slice(2)
	provinces = generator.callv("_build_province_raster", [image, land, Rect2i(Vector2i.ZERO, size), pixels, empty_paths, 1.0, true, Hydro.barriers([river], size)])
	for owner in provinces.ids: assert(owner == 0)
	print("HYDROLOGY_PROVINCES_OK")
	quit()
