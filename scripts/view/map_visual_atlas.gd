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
	var land := _mask_channel(shared_masks.get("land_mask"), safe_size)
	if land == null:
		land = Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_RF)
		_fill_land(height_image, land, safe_size)
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
		coast = Image.create(
			safe_size.x, safe_size.y, false, Image.FORMAT_RF
		)
	var rivers := Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_RF)
	var roads := Image.create(safe_size.x, safe_size.y, false, Image.FORMAT_RF)
	if shared_city == null:
		_fill_city_ids(game_state, city_id, land, safe_size)
	if shared_masks.get("edge_mask") == null:
		_fill_edges(city_id, land, region_edge, coast, safe_size)
	elif shared_masks.get("coast_mask") == null:
		_fill_coast(land, coast, safe_size)
	_fill_rivers(game_state, rivers, safe_size)
	_fill_roads(game_state, roads, safe_size)
	return {
		"size": safe_size,
		"elevation": elevation,
		"land_mask": land,
		"city_id": city_id,
		"region_edge": region_edge,
		"coast_mask": coast,
		"river_mask": rivers,
		"road_mask": roads,
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


static func _fill_city_ids(
	game_state: GameState,
	city_id: Image,
	land: Image,
	size: Vector2i,
	visual_city_ids: Image = null
) -> void:
	if visual_city_ids != null and not visual_city_ids.is_empty():
		for y in range(size.y):
			var visual_y := clampi(
				y * visual_city_ids.get_height() / size.y,
				0, visual_city_ids.get_height() - 1
			)
			for x in range(size.x):
				if land.get_pixel(x, y).r < 0.5:
					continue
				var visual_x := clampi(
					x * visual_city_ids.get_width() / size.x,
					0, visual_city_ids.get_width() - 1
				)
				city_id.set_pixel(
					x, y, visual_city_ids.get_pixel(visual_x, visual_y)
				)
		return
	var source_size := game_state.province_map_size
	if source_size.x <= 0 or source_size.y <= 0:
		return
	for y in range(size.y):
		var source_y := clampi(y * source_size.y / size.y, 0, source_size.y - 1)
		for x in range(size.x):
			if land.get_pixel(x, y).r < 0.5:
				continue
			var source_x := clampi(x * source_size.x / size.x, 0, source_size.x - 1)
			var owner := game_state.province_ids[
				source_y * source_size.x + source_x
			]
			city_id.set_pixel(x, y, Color(float(owner), 0.0, 0.0, 1.0))


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
