extends SceneTree

const SOURCE := "user://projection_test.json"

func _init() -> void:
	var manifest := MapSource.load_manifest()
	manifest["bbox_wgs84"] = [-12.0, 18.0, 136.0, 57.0]
	manifest["projection"] = "web_mercator"
	_write(manifest)
	assert(absf(MapSource.aspect_ratio(SOURCE) - 2.8790009154) < 0.000001)
	assert(MapSource.projection_type() == "equirectangular")
	assert(absf(MapSource.map_to_lonlat(0.5, 0.0, SOURCE)[1] - 57.0) < 1e-6)
	assert(absf(MapSource.map_to_lonlat(0.5, 1.0, SOURCE)[1] - 18.0) < 1e-6)
	assert(absf(MapSource.map_to_lonlat(0.5, 0.5, SOURCE)[1] - 40.2259661872) < 1e-6)
	var density := TerrainMapGenerator.default_city_density_settings(SOURCE)
	assert(absf(TerrainMapGenerator.latitude_for_map_y(0.5, density, SOURCE) - 40.2259661872) < 1e-6)
	var state := GameState.new()
	state.uses_heightmap = true
	state.map_source_manifest = SOURCE
	state.city_density_settings = density
	var center_city := City.new()
	center_city.map_position = Vector2(0.5, 0.5)
	assert(absf(RegionalStrategy.city_latitude(state, center_city) - 40.2259661872) < 1e-6)
	density["latitude_min"] = -90.0
	density["latitude_max"] = 90.0
	density = TerrainMapGenerator.normalize_city_density_settings(density, SOURCE)
	assert(absf(density.latitude_max - MapSource.MERCATOR_LATITUDE_LIMIT) < 1e-9)
	assert(absf(TerrainMapGenerator.latitude_for_map_y(0.5, density, SOURCE)) < 1e-6)
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	assert(absf(TerrainMapGenerator.projected_pixel_aspect(image, SOURCE) - 2.8790009154) < 1e-6)
	assert(TerrainMapGenerator.projected_pixel_aspect(image, MapSource.DEFAULT_MANIFEST) == 1.0)
	# A diagonal two-city fixture changes ownership when horizontal travel is
	# correctly more expensive than vertical travel on the square Mercator PNG.
	image.fill(Color(1.0, 1.0, 1.0, 129.0 / 255.0))
	var land := PackedByteArray()
	land.resize(256 * 256)
	land.fill(1)
	var city_pixels: Array[Vector2i] = [Vector2i(64, 64), Vector2i(192, 192)]
	var no_rivers: Array[Array] = []
	var square := TerrainMapGenerator._build_province_raster(image, land, Rect2i(0, 0, 256, 256), city_pixels, no_rivers, 1.0, true)
	var projected := TerrainMapGenerator._build_province_raster(image, land, Rect2i(0, 0, 256, 256), city_pixels, no_rivers, TerrainMapGenerator.projected_pixel_aspect(image, SOURCE), true)
	assert(square.ids[64 * 256 + 170] == 0)
	assert(projected.ids[64 * 256 + 170] == 1)
	assert(not -1 in projected.ids, "有种子的连续陆地不能因堆精度留下空洞")
	var shared := TerrainMapGenerator.province_shared_boundary_counts(PackedInt32Array([1, 2]), Vector2i(2, 1))
	assert(TerrainMapGenerator.provinces_share_boundary(shared, 1, 2))
	assert(TerrainMapGenerator.provinces_share_boundary(shared, 2, 1))
	assert(not TerrainMapGenerator.provinces_share_boundary(shared, 1, 3))
	var cities := [[12.5, 41.9, 0.16554054054, 0.45680645848],
		[51.4, 35.7, 0.42837837838, 0.61173539668],
		[108.9, 34.3, 0.81689189189, 0.64498335668]]
	for city in cities:
		var uv := MapSource.lonlat_to_map(city[0], city[1], SOURCE)
		assert(absf(uv[0] - city[2]) < 1e-9 and absf(uv[1] - city[3]) < 1e-9)
	for longitude in [-12.0, 0.0, 51.4, 108.9, 136.0]:
		for latitude in [18.0, 34.3, 40.2259661872, 57.0]:
			var uv := MapSource.lonlat_to_map(longitude, latitude, SOURCE)
			var lonlat := MapSource.map_to_lonlat(uv[0], uv[1], SOURCE)
			assert(absf(lonlat[0] - longitude) <= 1e-6)
			assert(absf(lonlat[1] - latitude) <= 1e-6)
	manifest["projection"] = "unknown"
	_write(manifest)
	assert(not MapSource.validate_manifest(SOURCE).is_empty())
	manifest["projection"] = "web_mercator"
	manifest["bbox_wgs84"] = [-12.0, 18.0, 136.0, 90.0]
	_write(manifest)
	assert(not MapSource.validate_manifest(SOURCE).is_empty())
	DirAccess.remove_absolute(SOURCE)
	print("PASS map_projection")
	quit()

func _write(manifest: Dictionary) -> void:
	var file := FileAccess.open(SOURCE, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
