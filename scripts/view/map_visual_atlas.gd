class_name MapVisualAtlas
extends RefCounted
## Shared heightmap-UV visual data for both 2D and 3D map renderers.

const SIZE := Vector2i(2048, 2048)
const PROVINCE_VISUAL_LOOKUP := preload(
	"res://scripts/view/province_visual_lookup.gd"
)


static func build_visual_atlas(
	game_state: GameState,
	height_image: Image,
	size: Vector2i = SIZE,
	visual_city_ids: Image = null,
	shared_masks: Dictionary = {}
) -> Dictionary:
	var safe_size := Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	var elevation := _height_channel(height_image, safe_size)
	var land := _land_channel(height_image, safe_size)
	if land == null:
		land = _mask_channel(shared_masks.get("land_mask"), safe_size)
	if land == null:
		land = Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_L8)
	var shared_city := _mask_channel(visual_city_ids, safe_size)
	var city_id := shared_city
	if city_id == null:
		city_id = Image.create(
			safe_size.x, safe_size.y, false, Image.FORMAT_RF
		)
		city_id.fill(Color(-1.0, 0.0, 0.0, 1.0))
	var region_edge := _mask_channel(
		shared_masks.get("edge_mask"), safe_size
	)
	if region_edge == null:
		region_edge = Image.create(
			safe_size.x, safe_size.y, false, Image.FORMAT_RF
		)
	var coast := _mask_channel(shared_masks.get("coast_mask"), safe_size)
	if coast == null:
		coast = _coast_channel(land, safe_size)
	var rivers := Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_RF)
	var roads := Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_RF)
	if shared_masks.get("edge_mask") == null:
		_fill_edges(city_id, land, region_edge, coast, safe_size)
	_fill_rivers(game_state, rivers, safe_size)
	_fill_roads(game_state, roads, safe_size)
	return {
		"size": safe_size,
		"revision": build_revision(game_state),
		"elevation": elevation,
		"land_mask": land,
		"city_id": city_id,
		"region_edge": region_edge,
		"coast_mask": coast,
		"river_mask": rivers,
		"road_mask": roads,
	}


static func build_revision(game_state: GameState) -> Dictionary:
	if game_state == null:
		return {
			"topology": 0,
			"ownership": 0,
			"diplomacy": 0,
			"roads": 0,
			"rivers": 0,
		}
	var river_source: Variant = (
		game_state.river_features
		if not game_state.river_features.is_empty()
		else game_state.river_paths
	)
	return {
		"topology": hash([
			game_state.province_map_size,
			game_state.province_ids,
		]),
		"ownership": game_state.ownership_revision,
		"diplomacy": game_state.diplomacy_revision,
		"roads": game_state.road_network_revision,
		"rivers": hash(river_source),
	}


static func sample_height_uv(atlas: Dictionary, uv: Vector2) -> float:
	var value: Variant = atlas.get("elevation")
	if not value is Image:
		return 0.0
	var image := value as Image
	var color := _sample_image(image, uv)
	return (
		TerrainMapGenerator.packed_signed_elevation(color)
		if image.get_format() != Image.FORMAT_RF else color.r
	)


static func sample_city_id_uv(atlas: Dictionary, uv: Vector2) -> int:
	if _sample_channel(atlas.get("land_mask"), uv, 0.0) < 0.5:
		return -1
	return int(round(_sample_channel(atlas.get("city_id"), uv, -1.0)))


static func build_political_lut(
	game_state: GameState, view_nation_id: int = -1
) -> Image:
	return PROVINCE_VISUAL_LOOKUP.build_visual_lut(
		game_state, view_nation_id
	)


static func visual_river_path(
	game_state: GameState, river_id: int
) -> PackedVector2Array:
	var features: Array = game_state.river_features
	if features.is_empty():
		features = MapFeatureContract.from_legacy_river_paths(
			game_state.river_paths
		)
	for feature_value in features:
		var feature := feature_value as Dictionary
		if int(feature.get("id", -1)) == river_id:
			return MapFeatureContract.build_high_precision_river_path(
				feature, SIZE
			)
	return PackedVector2Array()


static func visual_road_path(
	game_state: GameState, edge_index: int
) -> PackedVector2Array:
	if edge_index < 0 or edge_index >= game_state.edges.size():
		return PackedVector2Array()
	var edge: Edge = game_state.edges[edge_index]
	return edge.map_points(
		game_state.cities[edge.city_a].map_position,
		game_state.cities[edge.city_b].map_position
	).duplicate()


static func _fill_land(
	height_image: Image, land: Image, size: Vector2i
) -> void:
	if height_image == null or height_image.is_empty():
		return
	for y in range(size.y):
		var source_y := clampi(
			int(floor((float(y) + 0.5) * height_image.get_height() / size.y)),
			0, height_image.get_height() - 1
		)
		for x in range(size.x):
			var source_x := clampi(
				int(floor((float(x) + 0.5) * height_image.get_width() / size.x)),
				0, height_image.get_width() - 1
			)
			var color := height_image.get_pixel(source_x, source_y)
			if TerrainMapGenerator.packed_is_land(color):
				land.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))


static func _land_channel(height_image: Image, size: Vector2i) -> Image:
	if height_image == null or height_image.is_empty():
		return null
	var source := height_image
	if source.get_size() != size:
		source = source.duplicate()
		source.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	if source.get_format() != Image.FORMAT_RGBA8:
		var fallback := Image.create(size.x, size.y, false, Image.FORMAT_L8)
		_fill_land(source, fallback, size)
		return fallback
	var source_bytes := source.get_data()
	var land_bytes := PackedByteArray()
	land_bytes.resize(size.x * size.y)
	for pixel_index in range(land_bytes.size()):
		land_bytes[pixel_index] = (
			255 if source_bytes[pixel_index * 4 + 3] > 128 else 0
		)
	return Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_L8, land_bytes
	)


static func _fill_edges(
	city_id: Image,
	land: Image,
	region_edge: Image,
	coast: Image,
	size: Vector2i
) -> void:
	for y in range(size.y):
		for x in range(size.x):
			if land.get_pixel(x, y).r < 0.5:
				continue
			var owner := int(round(city_id.get_pixel(x, y).r))
			for offset_value in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var offset: Vector2i = offset_value
				var sample := Vector2i(x, y) + offset
				if sample.x < 0 or sample.y < 0 or sample.x >= size.x or sample.y >= size.y:
					coast.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))
					continue
				if land.get_pixel(sample.x, sample.y).r < 0.5:
					coast.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))
				elif int(round(city_id.get_pixel(sample.x, sample.y).r)) != owner:
					region_edge.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))


static func _fill_coast(land: Image, coast: Image, size: Vector2i) -> void:
	for y in range(size.y):
		for x in range(size.x):
			if land.get_pixel(x, y).r < 0.5:
				continue
			if (
				x == 0 or y == 0 or x + 1 == size.x or y + 1 == size.y
				or land.get_pixel(x - 1, y).r < 0.5
				or land.get_pixel(x + 1, y).r < 0.5
				or land.get_pixel(x, y - 1).r < 0.5
				or land.get_pixel(x, y + 1).r < 0.5
			):
				coast.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))


static func _coast_channel(land: Image, size: Vector2i) -> Image:
	var source := land
	if source.get_format() != Image.FORMAT_L8:
		source = source.duplicate()
		source.convert(Image.FORMAT_L8)
	var land_bytes := source.get_data()
	var coast_bytes := PackedByteArray()
	coast_bytes.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var index := y * size.x + x
			if land_bytes[index] < 128:
				continue
			if (
				x == 0 or y == 0 or x + 1 == size.x or y + 1 == size.y
				or land_bytes[index - 1] < 128
				or land_bytes[index + 1] < 128
				or land_bytes[index - size.x] < 128
				or land_bytes[index + size.x] < 128
			):
				coast_bytes[index] = 255
	return Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_L8, coast_bytes
	)


static func _fill_rivers(
	game_state: GameState, mask: Image, size: Vector2i
) -> void:
	var features: Array = game_state.river_features
	if features.is_empty():
		features = MapFeatureContract.from_legacy_river_paths(game_state.river_paths)
	for feature_value in features:
		var feature := feature_value as Dictionary
		var path := MapFeatureContract.build_high_precision_river_path(
			feature, size
		)
		_rasterize_path(mask, path, size, 1)


static func _fill_roads(
	game_state: GameState, mask: Image, size: Vector2i
) -> void:
	for edge in game_state.edges:
		var path := edge.map_points(
			game_state.cities[edge.city_a].map_position,
			game_state.cities[edge.city_b].map_position
		)
		_rasterize_path(mask, path, size, 1)


static func _rasterize_path(
	mask: Image, path: PackedVector2Array, size: Vector2i, radius: int
) -> void:
	for index in range(path.size() - 1):
		var a := path[index] * Vector2(size)
		var b := path[index + 1] * Vector2(size)
		var steps := maxi(int(ceil(a.distance_to(b))), 1)
		for step in range(steps + 1):
			var point := a.lerp(b, float(step) / float(steps))
			var center := Vector2i(floori(point.x), floori(point.y))
			for dy in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					var pixel := center + Vector2i(dx, dy)
					if pixel.x >= 0 and pixel.y >= 0 and pixel.x < size.x and pixel.y < size.y:
						mask.set_pixel(pixel.x, pixel.y, Color(1.0, 0.0, 0.0, 1.0))


static func _sample_channel(value: Variant, uv: Vector2, fallback: float) -> float:
	if not value is Image:
		return fallback
	var image := value as Image
	if image.is_empty():
		return fallback
	return _sample_image(image, uv).r


static func _sample_image(image: Image, uv: Vector2) -> Color:
	var x := clampi(int(floor(clampf(uv.x, 0.0, 1.0) * image.get_width())), 0, image.get_width() - 1)
	var y := clampi(int(floor(clampf(uv.y, 0.0, 1.0) * image.get_height())), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


static func _height_channel(height_image: Image, size: Vector2i) -> Image:
	if height_image == null or height_image.is_empty():
		return Image.create(size.x, size.y, false, Image.FORMAT_RF)
	if height_image.get_size() == size:
		return height_image
	var resized := height_image.duplicate()
	resized.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return resized


static func _mask_channel(value: Variant, size: Vector2i) -> Image:
	if not value is Image:
		return null
	var source := value as Image
	if source.is_empty():
		return null
	if source.get_size() == size:
		return source
	var resized := source.duplicate()
	resized.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return resized
