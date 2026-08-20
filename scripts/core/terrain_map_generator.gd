class_name TerrainMapGenerator
extends RefCounted
## 从带 Alpha 的灰度高度图确定性生成城市位置和道路图。

const ANALYSIS_WIDTH: int = 256
## Copernicus source covers 73E..135.5E / 18N..54N. Keep that complete
## geographic rectangle as the runtime map instead of cropping to the land
## alpha bounds; the land mask still exclusively controls city placement.
const FULL_MAP_ASPECT_RATIO: float = 62.5 / 36.0  ## Legacy default for old map definitions.
## Packed map source contract: RGB=satellite color, Alpha=signed elevation.
## 1..128 is -8000..0m sea; 129..255 is positive land..6200m.
const SEA_LEVEL_ALPHA: float = 128.0 / 255.0
const ALPHA_THRESHOLD: float = SEA_LEVEL_ALPHA
const LUMA_THRESHOLD: float = 0.0  ## Compatibility parameter; RGB never drives geography.
const CANDIDATE_STRIDE: int = 2
const INTERIOR_RADIUS: int = 0
const RELIEF_RADIUS: int = 3
const RELIEF_SPACING_WEIGHT: float = 0.015
const REFERENCE_CITY_COUNT: int = 64
const MIN_CITY_SPACING_AT_REFERENCE: float = 0.075
const LOCAL_SPACING_MIN_FACTOR: float = 0.55
const LOCAL_SPACING_MAX_FACTOR: float = 2.25
const SPACING_RELAXATION_STEP: float = 0.96
const SPACING_RELAXATION_FLOOR: float = 0.72
const RIVER_BANK_MIN_DISTANCE: float = 0.006
const RIVER_BANK_IDEAL_DISTANCE: float = 0.020
const RIVER_BANK_MAX_DISTANCE: float = 0.060
const MAX_LOCAL_EDGE_LENGTH: float = 0.30
const ROAD_SAMPLE_COUNT: int = 48
const RIVER_COUNT: int = 2
const RIVER_MICRO_CURVE_AMPLITUDE: float = 0.010
const RIVER_LOCAL_SEARCH_RADIUS: int = 3
const RIVER_DOCK_MIN_PER_RIVER: int = 2
const RIVER_DOCK_SOUTH_MIN_PER_RIVER: int = 12
const RIVER_DOCK_SOUTH_EAST_MIN_X: float = 0.60
const RIVER_DOCK_SOUTH_EAST_MIN: int = 6
const RIVER_DOCK_SOUTH_MOUTH_MIN_X: float = 0.70
const RIVER_DOCK_SOUTH_MOUTH_MIN: int = 3
const RIVER_DOCK_FIXED_INTERVAL: float = 0.16
const RIVER_DOCK_LOWLAND_DENSITY: float = 2.20
const RIVER_DOCK_LOWLAND_ALTITUDE: float = 0.18
const RIVER_DOCK_EASTERN_MIN_X: float = 0.55
const RIVER_DOCK_EASTERN_MIN_PER_RIVER: int = 3
const RIVER_DOCK_RESERVATION_CITY_COUNT_THRESHOLD: int = 160
const RIVER_CROSSING_ENDPOINT_EPS: float = 0.0001
const RIVER_CROSSING_MERGE_EPS: float = 0.0001
const RIVER_DOCK_MIN_SPACING: float = 0.012
const RIVER_DOCK_CITY_MIN_SPACING: float = 0.022
const LANDING_DANGER_MIN: float = 0.90
const EDGE_DISTANCE_UNITS_PER_MAP_HEIGHT: float = 12.0
## 河运速度为同 distance 陆路的 1.2 倍，因此耗时为陆路的 1/1.2。
const RIVER_TRAVEL_TIME_MULTIPLIER: float = 1.0 / 1.2
const RIVER_SUPPLY_LOSS_MULTIPLIER: float = 0.25
const DEFAULT_DENSITY_PEAK_LATITUDE: float = 30.0
const DEFAULT_SOUTH_EDGE_DENSITY: float = 0.50
const DEFAULT_NORTH_EDGE_DENSITY: float = 0.20
## 地理成本在地形分析分辨率求解；边界显示由矢量简化与圆滑消除栅格台阶。
const PROVINCE_RASTER_SCALE: int = 1
## 连续域扭曲把规则 Voronoi 直线变成自然弯曲边界；振幅以地形分析像素计。
const PROVINCE_WARP_PRIMARY_AMPLITUDE: float = 2.6
const PROVINCE_WARP_SECONDARY_AMPLITUDE: float = 1.2
const PROVINCE_MOUNTAIN_ALTITUDE_ONSET: float = 0.42
const PROVINCE_MOUNTAIN_COST: float = 2.8
const PROVINCE_SLOPE_COST: float = 7.0
const PROVINCE_RIVER_CROSSING_COST: float = 7.5
## 邻接道路中只有地形最平缓的这一部分使用 20000 标准容量；其余开放陆路
## 以 10000 为主，避免省份对偶图被宽路淹没。
const ROAD_STANDARD_CAPACITY_SHARE: float = 0.25

static var _cache: Dictionary = {}


static func build(
	source_path: String,
	city_count: int,
	city_mask_path: String = "",
	city_density_settings: Dictionary = {}
) -> Dictionary:
	var mask_signature := city_mask_signature(city_mask_path)
	var density_settings := normalize_city_density_settings(
		city_density_settings
	)
	var cache_key := "settlement-v13-province-dual-roads:%s:%d:%s:%s" % [
		source_path, city_count, mask_signature,
		city_density_signature(density_settings),
	]
	if _cache.has(cache_key):
		return (_cache[cache_key] as Dictionary).duplicate(true)
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	assert(source != null and not source.is_empty(), "无法加载地形高度图：%s" % source_path)
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(float(source.get_height()) * float(ANALYSIS_WIDTH) / float(source.get_width()))),
		1
	)
	# Alpha is numerical elevation, not visual transparency. Never interpolate
	# it across coastlines when building the geography analysis grid.
	analysis.resize(ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_NEAREST)
	var land_geometry := _all_land_geometry(analysis)
	assert(land_geometry["count"] >= city_count * 16, "高度图有效陆地区域不足")
	var mask: PackedByteArray = land_geometry["mask"]
	var land_bounds: Rect2i = land_geometry["bounds"]
	var city_mask_result := build_city_candidate_mask(
		mask, analysis.get_size(), city_mask_path
	)
	assert(bool(city_mask_result.get("ok", false)), str(
		city_mask_result.get("error", "城市蒙版加载失败")
	))
	var city_mask: PackedByteArray = city_mask_result["mask"]
	var city_geometry := _mask_geometry(city_mask, analysis.get_size())
	assert(
		int(city_geometry["count"]) >= city_count,
		"白色蒙版内真实陆地不足以生成%d座城市" % city_count
	)
	var bounds := Rect2i(Vector2i.ZERO, analysis.get_size())
	var map_aspect_ratio := MapSource.aspect_ratio()
	var river_paths := _build_river_paths(
		analysis,
		mask,
		land_bounds
	)
	var samples := _sample_cities(
		analysis,
		city_mask,
		city_geometry["bounds"],
		bounds,
		city_count,
		river_paths,
		density_settings
	)
	# Settlement density and spacing are solved in the tight land domain, then
	# projected once into the complete geographic rectangle used by rendering.
	var full_positions: Array[Vector2] = []
	for pixel in samples["pixels"]:
		full_positions.append(_normalized_map_point(pixel, bounds))
	samples["positions"] = full_positions
	# 省份是地形/河流上的基础行政分区；道路只能消费省份接壤关系，
	# 不能反过来塑造省界，否则会形成“道路决定省界、省界又决定道路”的循环。
	var provinces := _build_province_raster(
		analysis,
		mask,
		bounds,
		samples["pixels"],
		river_paths
	)
	var road_result := _build_roads(
		analysis,
		mask,
		samples,
		map_aspect_ratio,
		provinces,
		river_paths
	)
	_attach_province_land_paths(
		road_result["roads"],
		provinces,
		samples["positions"],
		city_count
	)
	var transport := _build_river_transport(
		analysis,
		mask,
		bounds,
		samples,
		road_result["roads"],
		river_paths,
		city_count,
		map_aspect_ratio
	)
	var result := {
		"positions": samples["positions"],
		"pixels": samples["pixels"],
		"heights": samples["heights"],
		"reliefs": samples["reliefs"],
		"roads": transport["roads"],
		"docks": transport["docks"],
		"river_paths": transport["river_paths"],
		"bounds": bounds,
		"land_bounds": land_bounds,
		"image_size": analysis.get_size(),
		"source_region_normalized": Rect2(0.0, 0.0, 1.0, 1.0),
		"map_aspect_ratio": map_aspect_ratio,
		"province_map_size": provinces["size"],
		"province_ids": provinces["ids"],
		"city_mask_path": city_mask_path,
		"city_mask_signature": mask_signature,
		"city_density_settings": density_settings.duplicate(true),
	}
	_cache[cache_key] = result.duplicate(true)
	return result


static func default_city_density_settings() -> Dictionary:
	var latitude_bounds := MapSource.latitude_bounds()
	var profile := MapSource.city_density_profile()
	return {
		"latitude_min": latitude_bounds.x,
		"latitude_max": latitude_bounds.y,
		"density_peak_latitude": clampf(
			float(profile.get(
				"peak_latitude", DEFAULT_DENSITY_PEAK_LATITUDE
			)),
			latitude_bounds.x,
			latitude_bounds.y
		),
		"south_density": clampf(float(profile.get(
			"south_edge_multiplier", DEFAULT_SOUTH_EDGE_DENSITY
		)), 0.01, 1.0),
		"north_density": clampf(float(profile.get(
			"north_edge_multiplier", DEFAULT_NORTH_EDGE_DENSITY
		)), 0.01, 1.0),
	}


static func normalize_city_density_settings(
	settings: Dictionary
) -> Dictionary:
	var defaults := default_city_density_settings()
	var latitude_min := clampf(
		float(settings.get("latitude_min", defaults["latitude_min"])),
		-90.0, 90.0
	)
	var latitude_max := clampf(
		float(settings.get("latitude_max", defaults["latitude_max"])),
		-90.0, 90.0
	)
	if latitude_min > latitude_max:
		var swap := latitude_min
		latitude_min = latitude_max
		latitude_max = swap
	if is_equal_approx(latitude_min, latitude_max):
		latitude_max = minf(latitude_min + 0.1, 90.0)
		latitude_min = maxf(latitude_max - 0.1, -90.0)
	return {
		"latitude_min": latitude_min,
		"latitude_max": latitude_max,
		"density_peak_latitude": clampf(
			float(settings.get(
				"density_peak_latitude",
				defaults["density_peak_latitude"]
			)),
			latitude_min, latitude_max
		),
		"south_density": clampf(
			float(settings.get(
				"south_density", defaults["south_density"]
			)),
			0.01, 1.0
		),
		"north_density": clampf(
			float(settings.get(
				"north_density", defaults["north_density"]
			)),
			0.01, 1.0
		),
	}


static func city_density_signature(settings: Dictionary) -> String:
	return "%.3f:%.3f:%.3f:%.3f:%.3f" % [
		float(settings["latitude_min"]),
		float(settings["latitude_max"]),
		float(settings["density_peak_latitude"]),
		float(settings["south_density"]),
		float(settings["north_density"]),
	]


static func latitude_for_map_y(
	map_y: float, settings: Dictionary
) -> float:
	return lerpf(
		float(settings["latitude_max"]),
		float(settings["latitude_min"]),
		clampf(map_y, 0.0, 1.0)
	)


static func latitude_density_multiplier(
	latitude: float, settings: Dictionary
) -> float:
	var normalized := normalize_city_density_settings(settings)
	var south := float(normalized["latitude_min"])
	var north := float(normalized["latitude_max"])
	var peak := float(normalized["density_peak_latitude"])
	if latitude <= peak:
		var south_ratio := smoothstep(
			south, maxf(peak, south + 0.0001), latitude
		)
		return lerpf(
			float(normalized["south_density"]),
			1.0, south_ratio
		)
	var north_ratio := smoothstep(
		peak, maxf(north, peak + 0.0001), latitude
	)
	return lerpf(
		1.0, float(normalized["north_density"]), north_ratio
	)


static func city_mask_signature(path: String) -> String:
	var clean := path.strip_edges()
	if clean.is_empty():
		return "none"
	var global_path := (
		ProjectSettings.globalize_path(clean)
		if clean.begins_with("res://") or clean.begins_with("user://")
		else clean
	)
	return "%s:%d" % [clean, FileAccess.get_modified_time(global_path)]


static func load_city_mask_image(path: String) -> Dictionary:
	var clean := path.strip_edges()
	if clean.is_empty():
		return {"ok": true, "image": null, "path": ""}
	var image: Image = null
	if clean.begins_with("res://"):
		var texture := load(clean) as Texture2D
		if texture != null:
			image = texture.get_image()
	else:
		var global_path := (
			ProjectSettings.globalize_path(clean)
			if clean.begins_with("user://")
			else clean
		)
		if FileAccess.file_exists(global_path):
			image = Image.load_from_file(global_path)
	if image == null or image.is_empty():
		return {
			"ok": false,
			"error": "无法读取城市蒙版图片：%s" % clean,
		}
	return {"ok": true, "image": image, "path": clean}


static func build_city_candidate_mask(
	land_mask: PackedByteArray,
	target_size: Vector2i,
	city_mask_path: String
) -> Dictionary:
	var result := load_city_mask_image(city_mask_path)
	if not bool(result.get("ok", false)):
		return result
	var output := land_mask.duplicate()
	var image: Image = result.get("image")
	if image == null:
		return {"ok": true, "mask": output, "white_land_count": _count_mask(output)}
	image = image.duplicate()
	image.resize(target_size.x, target_size.y, Image.INTERPOLATE_NEAREST)
	var allowed_count := 0
	for y in range(target_size.y):
		for x in range(target_size.x):
			var index := y * target_size.x + x
			var color := image.get_pixel(x, y)
			var allowed := (
				land_mask[index] != 0
				and color.get_luminance() >= 0.5
			)
			output[index] = 1 if allowed else 0
			if allowed:
				allowed_count += 1
	return {
		"ok": true,
		"mask": output,
		"white_land_count": allowed_count,
		"path": city_mask_path,
	}


static func validate_city_mask(
	source_path: String,
	city_mask_path: String,
	city_count: int
) -> Dictionary:
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	if source == null or source.is_empty():
		return {"ok": false, "error": "地图源纹理不可用。"}
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(float(source.get_height()) * float(ANALYSIS_WIDTH) / float(source.get_width()))), 1
	)
	analysis.resize(ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_NEAREST)
	var land_geometry := _all_land_geometry(analysis)
	var result := build_city_candidate_mask(
		land_geometry["mask"], analysis.get_size(), city_mask_path
	)
	if not bool(result.get("ok", false)):
		return result
	var available := int(result.get("white_land_count", 0))
	if available < city_count:
		return {
			"ok": false,
			"error": "蒙版白色陆地区域不足：可用%d格，请求%d城。" % [available, city_count],
		}
	return {"ok": true, "white_land_count": available, "path": city_mask_path}


static func _count_mask(mask: PackedByteArray) -> int:
	var count := 0
	for value in mask:
		if value != 0:
			count += 1
	return count


static func _mask_geometry(mask: PackedByteArray, size: Vector2i) -> Dictionary:
	var min_x := size.x
	var min_y := size.y
	var max_x := -1
	var max_y := -1
	var count := 0
	for y in range(size.y):
		for x in range(size.x):
			if mask[y * size.x + x] == 0:
				continue
			count += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return {
		"count": count,
		"bounds": Rect2i(
			min_x if count > 0 else 0,
			min_y if count > 0 else 0,
			maxi(max_x - min_x + 1, 1) if count > 0 else 1,
			maxi(max_y - min_y + 1, 1) if count > 0 else 1
		),
	}


static func is_land_map_position(
	source_path: String,
	map_position: Vector2
) -> bool:
	var texture := load(source_path) as Texture2D
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var x := clampi(
		int(floor(clampf(map_position.x, 0.0, 1.0) * image.get_width())),
		0, image.get_width() - 1
	)
	var y := clampi(
		int(floor(clampf(map_position.y, 0.0, 1.0) * image.get_height())),
		0, image.get_height() - 1
	)
	var pixel := image.get_pixel(x, y)
	return packed_is_land(pixel)


static func packed_is_land(color: Color) -> bool:
	return color.a > SEA_LEVEL_ALPHA + 0.5 / 255.0


static func packed_altitude(color: Color) -> float:
	if not packed_is_land(color):
		return 0.0
	return clampf((color.a * 255.0 - 129.0) / 126.0, 0.0, 1.0)


static func packed_signed_elevation(color: Color) -> float:
	var alpha_byte := color.a * 255.0
	if alpha_byte <= 128.5:
		return lerpf(-1.0, 0.0, clampf((alpha_byte - 1.0) / 127.0, 0.0, 1.0))
	return clampf((alpha_byte - 129.0) / 126.0, 0.0, 1.0)


static func map_segment_profile(
	source_path: String,
	from: Vector2,
	to: Vector2
) -> Dictionary:
	var texture := load(source_path) as Texture2D
	var image := texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		return {"height_difference": 0.0, "land_ratio": 0.0}
	var minimum := 1.0
	var maximum := 0.0
	var land_samples := 0
	for index in range(ROAD_SAMPLE_COUNT + 1):
		var ratio := float(index) / float(ROAD_SAMPLE_COUNT)
		var point := from.lerp(to, ratio)
		var x := clampi(int(floor(point.x * image.get_width())), 0, image.get_width() - 1)
		var y := clampi(int(floor(point.y * image.get_height())), 0, image.get_height() - 1)
		var color := image.get_pixel(x, y)
		var height := packed_altitude(color)
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		if packed_is_land(color):
			land_samples += 1
	return {
		"height_difference": maximum - minimum,
		"land_ratio": float(land_samples) / float(ROAD_SAMPLE_COUNT + 1),
	}


static func rebuild_provinces(
	source_path: String,
	city_positions: Array[Vector2],
	_edges: Array[Edge],
	normalized_rivers: Array[PackedVector2Array]
) -> Dictionary:
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	assert(source != null and not source.is_empty())
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(
			float(source.get_height()) * float(ANALYSIS_WIDTH)
				/ float(source.get_width())
		)),
		1
	)
	analysis.resize(
		ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_NEAREST
	)
	var land_geometry := _all_land_geometry(analysis)
	var mask: PackedByteArray = land_geometry["mask"]
	var bounds := Rect2i(Vector2i.ZERO, analysis.get_size())
	var city_pixels: Array[Vector2i] = []
	for position in city_positions:
		city_pixels.append(Vector2i(
			clampi(
				int(round(position.x * float(analysis.get_width() - 1))),
				0, analysis.get_width() - 1
			),
			clampi(
				int(round(position.y * float(analysis.get_height() - 1))),
				0, analysis.get_height() - 1
			)
		))
	var river_pixels: Array[Array] = []
	for river in normalized_rivers:
		var path: Array[Vector2i] = []
		for point in river:
			path.append(Vector2i(
				clampi(
					int(round(point.x * float(analysis.get_width() - 1))),
					0, analysis.get_width() - 1
				),
				clampi(
					int(round(point.y * float(analysis.get_height() - 1))),
					0, analysis.get_height() - 1
				)
			))
		river_pixels.append(path)
	return _build_province_raster(
		analysis, mask, bounds, city_pixels, river_pixels
	)


static func _build_province_raster(
	image: Image,
	land_mask: PackedByteArray,
	bounds: Rect2i,
	city_pixels: Array[Vector2i],
	river_paths: Array[Array]
) -> Dictionary:
	var width := bounds.size.x * PROVINCE_RASTER_SCALE
	var height := bounds.size.y * PROVINCE_RASTER_SCALE
	var raster_size := Vector2i(width, height)
	var ids := PackedInt32Array()
	ids.resize(width * height)
	ids.fill(-1)
	var land := PackedByteArray()
	land.resize(width * height)
	var altitude := PackedFloat32Array()
	altitude.resize(width * height)
	var river := PackedByteArray()
	river.resize(width * height)
	var metric_points := PackedVector2Array()
	metric_points.resize(width * height)
	var image_width := image.get_width()
	var warped_cities: Array[Vector2] = []
	for city_pixel in city_pixels:
		warped_cities.append(province_metric_point(
			Vector2(city_pixel - bounds.position)
		))
	for local_y in range(height):
		var image_y := bounds.position.y + clampi(
			local_y / PROVINCE_RASTER_SCALE,
			0,
			bounds.size.y - 1
		)
		for local_x in range(width):
			var index := local_y * width + local_x
			metric_points[index] = province_metric_point(
				(Vector2(local_x, local_y)
					+ Vector2(0.5, 0.5))
					/ float(PROVINCE_RASTER_SCALE)
			)
			var image_x := bounds.position.x + clampi(
				local_x / PROVINCE_RASTER_SCALE,
				0,
				bounds.size.x - 1
			)
			if land_mask[image_y * image_width + image_x] == 0:
				continue
			land[index] = 1
			altitude[index] = packed_altitude(
				image.get_pixel(image_x, image_y)
			)
	_build_province_river_mask(
		river,
		raster_size,
		bounds,
		river_paths
	)
	var distances := PackedFloat64Array()
	distances.resize(width * height)
	distances.fill(INF)
	var heap: Array[Vector3] = []
	for city_id in range(city_pixels.size()):
		var local := (
			city_pixels[city_id] - bounds.position
		) * PROVINCE_RASTER_SCALE
		var seed := Vector2i(
			clampi(local.x, 0, width - 1),
			clampi(local.y, 0, height - 1)
		)
		var seed_index := seed.y * width + seed.x
		if land[seed_index] == 0:
			continue
		distances[seed_index] = 0.0
		ids[seed_index] = city_id
		_province_heap_push(
			heap,
			Vector3(0.0, seed_index, city_id)
		)
	var offsets := [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	while not heap.is_empty():
		var entry: Vector3 = _province_heap_pop(heap)
		var current_index := int(entry.y)
		var owner := int(entry.z)
		var current_cost := entry.x
		if (
			owner != ids[current_index]
			or current_cost
				> distances[current_index] + 0.000001
		):
			continue
		var current := Vector2i(
			current_index % width,
			current_index / width
		)
		var current_metric := metric_points[current_index]
		for offset in offsets:
			var next: Vector2i = current + offset
			if (
				next.x < 0
				or next.y < 0
				or next.x >= width
				or next.y >= height
			):
				continue
			var next_index: int = next.y * width + next.x
			if land[next_index] == 0:
				continue
			var step_cost := province_geographic_step_cost(
				altitude[current_index],
				altitude[next_index],
				river[current_index] != river[next_index],
				0.0,
				current_metric.distance_to(
					metric_points[next_index]
				)
			)
			var candidate_cost := current_cost + step_cost
			# 相同成本下堆已按 owner/id 稳定排序，首次到达即为确定胜者。
			# 禁止后到 owner 覆盖，避免旧 owner 已向外传播后留下断开的标签岛。
			if candidate_cost < distances[next_index] - 0.000001:
				distances[next_index] = candidate_cost
				ids[next_index] = owner
				_province_heap_push(
					heap,
					Vector3(
						candidate_cost,
						next_index,
						owner
					)
				)
	for local_y in range(height):
		for local_x in range(width):
			var index := local_y * width + local_x
			if land[index] == 0 or ids[index] >= 0:
				continue
			var warped_point := metric_points[index]
			var best_city := -1
			var best_distance := INF
			for city_id in range(warped_cities.size()):
				var distance := warped_point.distance_squared_to(
					warped_cities[city_id]
				)
				if (
					distance < best_distance
					or (
						is_equal_approx(
							distance,
							best_distance
						)
						and city_id < best_city
					)
				):
					best_distance = distance
					best_city = city_id
			ids[index] = best_city
	return {
		"size": raster_size,
		"ids": ids,
	}


static func province_geographic_step_cost(
	from_altitude: float,
	to_altitude: float,
	crosses_river: bool,
	_road_strength: float,
	step_length: float
) -> float:
	var average_altitude := (
		from_altitude + to_altitude
	) * 0.5
	var mountain_factor := clampf(
		inverse_lerp(
			PROVINCE_MOUNTAIN_ALTITUDE_ONSET,
			0.88,
			average_altitude
		),
		0.0,
		1.0
	)
	var slope := absf(to_altitude - from_altitude)
	var terrain_cost := maxf(step_length, 0.01) * (
		1.0
		+ mountain_factor * PROVINCE_MOUNTAIN_COST
		+ slope * PROVINCE_SLOPE_COST
	)
	if crosses_river:
		terrain_cost += PROVINCE_RIVER_CROSSING_COST
	return maxf(terrain_cost, 0.01)


static func _build_province_river_mask(
	result: PackedByteArray,
	raster_size: Vector2i,
	bounds: Rect2i,
	river_paths: Array[Array]
) -> void:
	for path in river_paths:
		for point_value in path:
			var point: Vector2i = point_value
			var local := (
				point - bounds.position
			) * PROVINCE_RASTER_SCALE
			_mark_province_disk(
				result,
				raster_size,
				local,
				1,
				1.0
			)


static func _mark_province_disk(
	field: Variant,
	size: Vector2i,
	center: Vector2i,
	radius: int,
	value: float
) -> void:
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			var point := center + Vector2i(
				offset_x,
				offset_y
			)
			if (
				point.x < 0
				or point.y < 0
				or point.x >= size.x
				or point.y >= size.y
			):
				continue
			var distance := Vector2(
				offset_x,
				offset_y
			).length()
			if distance > float(radius) + 0.001:
				continue
			var falloff := (
				1.0
				if radius <= 1
				else 1.0
					- distance / float(radius + 1)
			)
			var index := point.y * size.x + point.x
			if field is PackedByteArray:
				field[index] = 1
			else:
				field[index] = maxf(
					float(field[index]),
					value * falloff
				)


static func _province_heap_entry_less(
	a: Vector3,
	b: Vector3
) -> bool:
	var cost_a := a.x
	var cost_b := b.x
	if not is_equal_approx(cost_a, cost_b):
		return cost_a < cost_b
	var owner_a := int(a.z)
	var owner_b := int(b.z)
	if owner_a != owner_b:
		return owner_a < owner_b
	return int(a.y) < int(b.y)


static func _province_heap_push(
	heap: Array[Vector3],
	entry: Vector3
) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _province_heap_entry_less(
			heap[index],
			heap[parent]
		):
			break
		var temporary: Vector3 = heap[index]
		heap[index] = heap[parent]
		heap[parent] = temporary
		index = parent


static func _province_heap_pop(
	heap: Array[Vector3]
) -> Vector3:
	var result: Vector3 = heap[0]
	var last: Vector3 = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if (
			left < heap.size()
			and _province_heap_entry_less(
				heap[left],
				heap[smallest]
			)
		):
			smallest = left
		if (
			right < heap.size()
			and _province_heap_entry_less(
				heap[right],
				heap[smallest]
			)
		):
			smallest = right
		if smallest == index:
			break
		var temporary: Vector3 = heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = temporary
		index = smallest
	return result


## 确定性的低频连续域扭曲。相邻采样点保持相邻，不引入随机飞地；
## 同时两组不同方向波叠加，避免边界呈现统一波纹。
static func province_metric_point(point: Vector2) -> Vector2:
	var primary := Vector2(
		sin(
			point.y * 0.137
				+ sin(point.x * 0.041) * 1.7
		),
		sin(
			point.x * 0.119
				+ cos(point.y * 0.047) * 1.5
		)
	) * PROVINCE_WARP_PRIMARY_AMPLITUDE
	var secondary := Vector2(
		sin((point.x + point.y) * 0.061 + 0.9),
		cos((point.x - point.y) * 0.057 - 0.6)
	) * PROVINCE_WARP_SECONDARY_AMPLITUDE
	return point + primary + secondary


static func _largest_land_component(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var eligible := PackedByteArray()
	eligible.resize(width * height)
	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			if packed_is_land(color):
				eligible[y * width + x] = 1
	var visited := PackedByteArray()
	visited.resize(width * height)
	var best: Array[int] = []
	var offsets := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for index in range(eligible.size()):
		if eligible[index] == 0 or visited[index] != 0:
			continue
		var queue: Array[int] = [index]
		var component: Array[int] = []
		visited[index] = 1
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			component.append(current)
			var point := Vector2i(current % width, current / width)
			for offset in offsets:
				var next: Vector2i = point + offset
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
					continue
				var next_index: int = next.y * width + next.x
				if eligible[next_index] == 0 or visited[next_index] != 0:
					continue
				visited[next_index] = 1
				queue.append(next_index)
		if component.size() > best.size():
			best = component
	var mask := PackedByteArray()
	mask.resize(width * height)
	var min_x := width
	var min_y := height
	var max_x := 0
	var max_y := 0
	for index in best:
		mask[index] = 1
		var x := index % width
		var y := index / width
		min_x = mini(min_x, x)
		min_y = mini(min_y, y)
		max_x = maxi(max_x, x)
		max_y = maxi(max_y, y)
	return {
		"mask": mask,
		"count": best.size(),
		"bounds": Rect2i(
			min_x,
			min_y,
			maxi(max_x - min_x + 1, 1),
			maxi(max_y - min_y + 1, 1)
		),
	}


static func _all_land_geometry(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var mask := PackedByteArray()
	mask.resize(width * height)
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	var count := 0
	for y in range(height):
		for x in range(width):
			if not packed_is_land(image.get_pixel(x, y)):
				continue
			mask[y * width + x] = 1
			count += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return {
		"mask": mask,
		"count": count,
		"bounds": Rect2i(
			min_x, min_y,
			maxi(max_x - min_x + 1, 1),
			maxi(max_y - min_y + 1, 1)
		),
	}


static func _sample_cities(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i,
	full_bounds: Rect2i,
	city_count: int,
	river_paths: Array[Array],
	city_density_settings: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	# 固定码头是河运骨架节点，必须先于普通城市占位。高城市密度下若
	# 先铺满城市，再要求码头避开城市，整段下游会找不到任何合法位置。
	var reserved_dock_positions: Array[Vector2] = []
	if city_count > RIVER_DOCK_RESERVATION_CITY_COUNT_THRESHOLD:
		reserved_dock_positions = _reserved_river_dock_positions(
			image, river_paths, full_bounds
		)
	var scale := Vector2(
		maxi(bounds.size.x, 1),
		maxi(bounds.size.y, 1)
	)
	var map_aspect := (
		float(maxi(bounds.size.x, 1))
		/ float(maxi(bounds.size.y, 1))
	)
	var base_spacing := minimum_city_spacing_for_count(city_count)
	for y in range(bounds.position.y, bounds.end.y, CANDIDATE_STRIDE):
		for x in range(bounds.position.x, bounds.end.x, CANDIDATE_STRIDE):
			if not _is_interior(mask, image.get_width(), image.get_height(), x, y):
				continue
			# 高密度地图的普通城市不能占用河槽；跨河节点只能由后续
			# 码头生成。默认地图保留既有确定性城市/经济分布。
			if (
				city_count > RIVER_DOCK_RESERVATION_CITY_COUNT_THRESHOLD
				and _pixel_in_river_channel(Vector2i(x, y), river_paths)
			):
				continue
			var relief := _local_relief(image, x, y, RELIEF_RADIUS)
			var height := packed_altitude(
				image.get_pixel(x, y)
			)
			var normalized := (
				Vector2(x, y) - Vector2(bounds.position)
			) / scale
			var full_normalized := _normalized_map_point(
				Vector2(x, y), full_bounds
			)
			if _near_reserved_dock_position(
				full_normalized, reserved_dock_positions, MapSource.aspect_ratio()
			):
				continue
			var latitude := latitude_for_map_y(
				full_normalized.y, city_density_settings
			)
			var latitude_density := latitude_density_multiplier(
				latitude, city_density_settings
			)
			var river_affinity := _river_bank_affinity(
				Vector2i(x, y),
				bounds,
				river_paths
			)
			var density := settlement_density(
				height,
				relief,
				normalized,
				river_affinity,
				latitude_density
			)
			candidates.append({
				"pixel": Vector2i(x, y),
				"height": height,
				"relief": relief,
				"density": density,
				"river_affinity": river_affinity,
				"latitude": latitude,
				"latitude_density": latitude_density,
				"spacing": clampf(
					base_spacing / sqrt(maxf(density, 0.01)),
					base_spacing * LOCAL_SPACING_MIN_FACTOR,
					base_spacing * LOCAL_SPACING_MAX_FACTOR
				),
			})
	assert(candidates.size() >= city_count, "平坦陆地候选点不足")
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var density_a := float(a["density"])
		var density_b := float(b["density"])
		if not is_equal_approx(density_a, density_b):
			return density_a > density_b
		var pa: Vector2i = a["pixel"]
		var pb: Vector2i = b["pixel"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	var first_index := 0
	var selected: Array[Dictionary] = [candidates[first_index]]
	var selected_pixels := {candidates[first_index]["pixel"]: true}
	var spacing_scale := 1.0
	while selected.size() < city_count:
		var best_index := -1
		var best_score := -INF
		for i in range(candidates.size()):
			var candidate := candidates[i]
			if selected_pixels.has(candidate["pixel"]):
				continue
			var candidate_norm := (
				Vector2(candidate["pixel"]) - Vector2(bounds.position)
			) / scale
			var candidate_metric := Vector2(
				candidate_norm.x * map_aspect,
				candidate_norm.y
			)
			var min_distance_sq := INF
			for chosen in selected:
				var chosen_norm := (
					Vector2(chosen["pixel"]) - Vector2(bounds.position)
				) / scale
				var chosen_metric := Vector2(
					chosen_norm.x * map_aspect,
					chosen_norm.y
				)
				min_distance_sq = minf(
					min_distance_sq,
					candidate_metric.distance_squared_to(chosen_metric)
				)
				var required_spacing := (
					(
						float(candidate["spacing"])
						+ float(chosen["spacing"])
					) * 0.5 * spacing_scale
				)
				if (
					candidate_metric.distance_squared_to(
						chosen_metric
					)
					< required_spacing * required_spacing
				):
					min_distance_sq = -INF
					break
			if min_distance_sq < 0.0:
				continue
			var score := (
				min_distance_sq * float(candidate["density"])
				- float(candidate["relief"]) * RELIEF_SPACING_WEIGHT
			)
			var candidate_pixel: Vector2i = candidate["pixel"]
			var best_pixel: Vector2i = (
				candidates[best_index]["pixel"]
				if best_index >= 0
				else Vector2i(2147483647, 2147483647)
			)
			if (
				score > best_score
				or (
					is_equal_approx(score, best_score)
					and (
						candidate_pixel.y < best_pixel.y
						or (
							candidate_pixel.y == best_pixel.y
							and candidate_pixel.x < best_pixel.x
						)
					)
				)
			):
				best_score = score
				best_index = i
		if best_index == -1:
			spacing_scale *= SPACING_RELAXATION_STEP
			if spacing_scale < SPACING_RELAXATION_FLOOR:
				# User masks may be narrow or fragmented. Once the normal spacing
				# floor is exhausted, keep farthest-point ordering but remove the
				# hard distance gate so an otherwise valid mask can still fill.
				spacing_scale = 0.0
			continue
		selected.append(candidates[best_index])
		selected_pixels[candidates[best_index]["pixel"]] = true
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2i = a["pixel"]
		var pb: Vector2i = b["pixel"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	var positions: Array[Vector2] = []
	var pixels: Array[Vector2i] = []
	var heights: Array[float] = []
	var reliefs: Array[float] = []
	for selected_city in selected:
		var pixel: Vector2i = selected_city["pixel"]
		positions.append(Vector2(
			float(pixel.x - bounds.position.x) / float(maxi(bounds.size.x - 1, 1)),
			float(pixel.y - bounds.position.y) / float(maxi(bounds.size.y - 1, 1))
		))
		pixels.append(pixel)
		heights.append(float(selected_city["height"]))
		reliefs.append(float(selected_city["relief"]))
	return {
		"positions": positions,
		"pixels": pixels,
		"heights": heights,
		"reliefs": reliefs,
	}


## 南河固定码头的预留带。前六个覆盖上中游，后六个硬性覆盖东部
## 低海拔河段，其中最后三个靠近河口；它们只负责让城市采样避让，
## 最终码头仍由统一的河程/地形逻辑在该空档内选择。
static func _reserved_river_dock_positions(
	image: Image,
	river_paths: Array[Array],
	bounds: Rect2i
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if river_paths.size() <= 1:
		return result
	var south_path: Array[Vector2i] = river_paths[1]
	var target_x_values: Array[float] = [
		0.14, 0.22, 0.30, 0.38, 0.46, 0.54,
		0.61, 0.64, 0.67, 0.71, 0.74, 0.77,
	]
	for target_x in target_x_values:
		var best_position := Vector2.ZERO
		var best_distance := INF
		for path_index in range(1, south_path.size() - 1):
			var pixel := south_path[path_index]
			if not packed_is_land(image.get_pixelv(pixel)):
				continue
			var position := _normalized_map_point(pixel, bounds)
			var distance := absf(position.x - target_x)
			if distance < best_distance:
				best_distance = distance
				best_position = position
		if best_distance < INF:
			result.append(best_position)
	return result


static func _near_reserved_dock_position(
	position: Vector2,
	reserved_positions: Array[Vector2],
	map_aspect_ratio: float
) -> bool:
	for reserved_position in reserved_positions:
		var delta := position - reserved_position
		delta.x *= map_aspect_ratio
		if delta.length() < RIVER_DOCK_CITY_MIN_SPACING:
			return true
	return false


static func minimum_city_spacing_for_count(city_count: int) -> float:
	return (
		MIN_CITY_SPACING_AT_REFERENCE
		* sqrt(
			float(REFERENCE_CITY_COUNT)
			/ float(maxi(city_count, 1))
		)
	)


## Legacy math helper retained for focused combat/terrain tests. Runtime packed
## map sources use packed_altitude() and never infer height from RGB luminance.
static func altitude_from_luminance(luminance: float) -> float:
	return 1.0 - clampf(luminance, 0.0, 1.0)


## 聚落密度的唯一评分源。海拔/起伏越低越适居，中东部与东南获得人口带加权，
## 河岸获得额外加权；返回值也用于反向缩放局部最小间距。
static func settlement_density(
	height: float,
	relief: float,
	normalized_position: Vector2,
	river_affinity: float,
	latitude_multiplier: float = 1.0
) -> float:
	var lowland := pow(
		1.0 - clampf(height, 0.0, 1.0),
		1.6
	)
	var eastness := smoothstep(
		0.10,
		0.95,
		clampf(normalized_position.x, 0.0, 1.0)
	)
	var southness := smoothstep(
		0.20,
		0.95,
		clampf(normalized_position.y, 0.0, 1.0)
	)
	var centrality := 1.0 - clampf(
		absf(normalized_position.x - 0.62) / 0.62,
		0.0,
		1.0
	)
	var geographic_density := clampf(
		0.35
			+ lowland * 1.00
			+ eastness * 0.55
			+ eastness * southness * 0.35
			+ centrality * 0.15
			+ clampf(river_affinity, 0.0, 1.0) * 0.70
			- clampf(relief, 0.0, 1.0) * 1.20,
		0.35,
		3.00
	)
	return clampf(
		geographic_density * clampf(latitude_multiplier, 0.01, 1.0),
		0.03, 3.00
	)


static func _river_bank_affinity(
	pixel: Vector2i,
	bounds: Rect2i,
	river_paths: Array[Array]
) -> float:
	if river_paths.is_empty():
		return 0.0
	var scale := Vector2(
		maxi(bounds.size.x, 1),
		maxi(bounds.size.y, 1)
	)
	var map_aspect := (
		float(maxi(bounds.size.x, 1))
		/ float(maxi(bounds.size.y, 1))
	)
	var normalized := (
		Vector2(pixel) - Vector2(bounds.position)
	) / scale
	var minimum_distance := INF
	for path in river_paths:
		for river_pixel_value in path:
			var river_pixel: Vector2i = river_pixel_value
			var river_normalized := (
				Vector2(river_pixel) - Vector2(bounds.position)
			) / scale
			var delta := normalized - river_normalized
			delta.x *= map_aspect
			minimum_distance = minf(
				minimum_distance,
				delta.length()
			)
	if minimum_distance < RIVER_BANK_MIN_DISTANCE:
		return 0.0
	if minimum_distance <= RIVER_BANK_IDEAL_DISTANCE:
		return inverse_lerp(
			RIVER_BANK_MIN_DISTANCE,
			RIVER_BANK_IDEAL_DISTANCE,
			minimum_distance
		)
	if minimum_distance >= RIVER_BANK_MAX_DISTANCE:
		return 0.0
	return 1.0 - inverse_lerp(
		RIVER_BANK_IDEAL_DISTANCE,
		RIVER_BANK_MAX_DISTANCE,
		minimum_distance
	)


static func _pixel_in_river_channel(
	pixel: Vector2i,
	river_paths: Array[Array]
) -> bool:
	for path in river_paths:
		for river_pixel_value in path:
			if pixel == Vector2i(river_pixel_value):
				return true
	return false


static func _is_interior(
	mask: PackedByteArray,
	width: int,
	height: int,
	x: int,
	y: int
) -> bool:
	for oy in range(-INTERIOR_RADIUS, INTERIOR_RADIUS + 1):
		for ox in range(-INTERIOR_RADIUS, INTERIOR_RADIUS + 1):
			var px := x + ox
			var py := y + oy
			if px < 0 or py < 0 or px >= width or py >= height:
				return false
			if mask[py * width + px] == 0:
				return false
	return true


static func _local_relief(image: Image, x: int, y: int, radius: int) -> float:
	var minimum := 1.0
	var maximum := 0.0
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var px := clampi(x + ox, 0, image.get_width() - 1)
			var py := clampi(y + oy, 0, image.get_height() - 1)
			var height := packed_altitude(image.get_pixel(px, py))
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
	return maximum - minimum


static func _build_roads(
	image: Image,
	mask: PackedByteArray,
	samples: Dictionary,
	map_aspect_ratio: float,
	provinces: Dictionary,
	river_paths: Array[Array]
) -> Dictionary:
	var pixels: Array[Vector2i] = samples["pixels"]
	var positions: Array[Vector2] = samples["positions"]
	# The packed source is square pixels but represents a non-square geographic
	# bbox. Use manifest aspect from the first topology decision onward.
	var topology_aspect := map_aspect_ratio
	var metric_positions := PackedVector2Array()
	for position in positions:
		metric_positions.append(Vector2(
			position.x * topology_aspect,
			position.y
		))
	var province_size: Vector2i = provinces["size"]
	var province_ids: PackedInt32Array = provinces["ids"]
	var shared_boundaries := province_shared_boundary_counts(
		province_ids, province_size
	)
	var adjacency_keys := shared_boundaries.keys()
	adjacency_keys.sort()
	var candidates: Array[Dictionary] = []
	for key_value in adjacency_keys:
		var key := int(key_value)
		var a := key / 10000
		var b := key % 10000
		if (
			a < 0 or b < 0
			or a >= pixels.size() or b >= pixels.size()
		):
			continue
		# 共享边界是道路拓扑的唯一真源。省份受地形成本影响可能为凹形，
		# 同一省 ID 还可能包含无城市的离岸碎片，因此必须确认两个城市种子
		# 在“两省联合域”内四连通；只在远端小岛接触不构成道路接壤。
		var map_path := PackedVector2Array()
		if not province_segment_stays_in_pair(
			province_ids, province_size, positions[a], positions[b], a, b
		):
			map_path = province_pair_path(
				province_ids, province_size, positions[a], positions[b], a, b
			)
			if map_path.size() < 2:
				continue
		var profile := _edge_profile(image, mask, pixels[a], pixels[b])
		var length := (
			metric_polyline_length(map_path, map_aspect_ratio)
			if map_path.size() >= 2
			else metric_positions[a].distance_to(metric_positions[b])
		)
		var candidate := {
			"a": a,
			"b": b,
			"length": length,
			"height_difference": profile["height_difference"],
			"land_ratio": profile["land_ratio"],
			"shared_boundary": int(shared_boundaries[key]),
			"cost": (
				length
				+ float(profile["height_difference"]) * 0.8
				+ (1.0 - float(profile["land_ratio"])) * 3.0
			),
		}
		if map_path.size() >= 2:
			candidate["map_path"] = map_path
		candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cost_a := float(a["cost"])
		var cost_b := float(b["cost"])
		if not is_equal_approx(cost_a, cost_b):
			return cost_a < cost_b
		return _pair_key(int(a["a"]), int(a["b"])) < _pair_key(int(b["a"]), int(b["b"]))
	)
	var selected: Array[Dictionary] = []
	var selected_keys := {}
	var parent: Array[int] = []
	parent.resize(pixels.size())
	for city_id in range(parent.size()):
		parent[city_id] = city_id
	# 省份对偶图可能因海岛分成多个陆地区域；每个区域各自生成一棵
	# 最小骨架树，区域之间交给海运/登陆系统，不制造假陆路。
	for candidate in candidates:
		var root_a := _root(parent, int(candidate["a"]))
		var root_b := _root(parent, int(candidate["b"]))
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		candidate["backbone"] = true
		selected.append(candidate)
		selected_keys[_pair_key(int(candidate["a"]), int(candidate["b"]))] = true

	for candidate in candidates:
		var key := _pair_key(int(candidate["a"]), int(candidate["b"]))
		if selected_keys.has(key):
			continue
		if (
			float(candidate["land_ratio"]) < 0.90
			or float(candidate["length"]) > MAX_LOCAL_EDGE_LENGTH
		):
			continue
		candidate["backbone"] = false
		selected.append(candidate)
		selected_keys[key] = true
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var diff_a := float(a["height_difference"])
		var diff_b := float(b["height_difference"])
		if not is_equal_approx(diff_a, diff_b):
			return diff_a < diff_b
		return _pair_key(int(a["a"]), int(a["b"])) < _pair_key(int(b["a"]), int(b["b"]))
	)
	var count := selected.size()
	var standard_capacity_count := int(round(
		float(count) * ROAD_STANDARD_CAPACITY_SHARE
	))
	for i in range(count):
		var road := selected[i]
		var percentile := float(i) / float(maxi(count - 1, 1))
		var max_manpower := (
			Edge.TERRAIN_STANDARD_MANPOWER
			if i < standard_capacity_count
			else Edge.TERRAIN_LOW_MANPOWER
		)
		road["max_manpower"] = max_manpower
		if bool(road.get("backbone", false)):
			road["max_manpower"] = maxi(
				int(road["max_manpower"]),
				Edge.TERRAIN_LOW_MANPOWER
			)
		road["base_max_manpower"] = maxi(
			int(road["max_manpower"]),
			Edge.MIN_MANPOWER
		)
		road["danger"] = clampf(percentile, 0.0, 1.0)
		road["length"] = metric_length_between(
			positions[int(road["a"])],
			positions[int(road["b"])],
			map_aspect_ratio
		)
		road["distance"] = distance_units_for_metric_length(
			float(road["length"])
		)
	var blocked_target := maxi(int(round(float(count) * 0.10)), 1)
	var blocked_count := 0
	for i in range(count - 1, -1, -1):
		var road := selected[i]
		if bool(road.get("backbone", false)):
			continue
		road["max_manpower"] = 0
		blocked_count += 1
		if blocked_count >= blocked_target:
			break
	_append_sea_component_backbone(
		selected, parent, image, mask, pixels, positions,
		map_aspect_ratio, river_paths
	)
	return {
		"roads": selected,
	}


## 合法陆路只形成陆地区域内的生成森林。这里用显式海运边连接不同区域，
## 不允许为了全图连通把跨海线伪装成 LAND。
static func _append_sea_component_backbone(
	roads: Array[Dictionary],
	parent: Array[int],
	image: Image,
	mask: PackedByteArray,
	pixels: Array[Vector2i],
	positions: Array[Vector2],
	map_aspect_ratio: float,
	river_paths: Array[Array]
) -> void:
	while true:
		var remaining_roots := {}
		for city_id in range(parent.size()):
			remaining_roots[_root(parent, city_id)] = true
		if remaining_roots.size() <= 1:
			break
		var best_a := -1
		var best_b := -1
		var best_length := INF
		var best_profile := {}
		for a in range(pixels.size()):
			for b in range(a + 1, pixels.size()):
				if _root(parent, a) == _root(parent, b):
					continue
				if _segment_crosses_pixel_river(
					pixels[a], pixels[b], river_paths
				):
					continue
				var length := metric_length_between(
					positions[a], positions[b], map_aspect_ratio
				)
				if length > best_length + 0.000001:
					continue
				var profile := _edge_profile(image, mask, pixels[a], pixels[b])
				if (
					length < best_length - 0.000001
					or (
						is_equal_approx(length, best_length)
						and _pair_key(a, b) < _pair_key(best_a, best_b)
					)
				):
					best_a = a
					best_b = b
					best_length = length
					best_profile = profile
		assert(best_a >= 0, "海区骨架必须存在不穿河道的SEA连接")
		var root_a := _root(parent, best_a)
		var root_b := _root(parent, best_b)
		parent[root_b] = root_a
		roads.append({
			"a": best_a,
			"b": best_b,
			"length": best_length,
			"height_difference": best_profile["height_difference"],
			"land_ratio": best_profile["land_ratio"],
			"cost": best_length,
			"backbone": true,
			"max_manpower": Edge.WATER_MANPOWER,
			"base_max_manpower": Edge.WATER_MANPOWER,
			"danger": 0.55,
			"distance": distance_units_for_metric_length(best_length),
			"kind": Edge.Kind.SEA,
			"travel_time_multiplier": RIVER_TRAVEL_TIME_MULTIPLIER,
			"supply_loss_multiplier": RIVER_SUPPLY_LOSS_MULTIPLIER,
			"allows_holding": false,
		})


static func _segment_crosses_pixel_river(
	from: Vector2i, to: Vector2i, river_paths: Array[Array]
) -> bool:
	for path in river_paths:
		for index in range(path.size() - 1):
			var hit = Geometry2D.segment_intersects_segment(
				Vector2(from), Vector2(to),
				Vector2(path[index]), Vector2(path[index + 1])
			)
			if hit == null:
				continue
			var point: Vector2 = hit
			if (
				point.distance_to(Vector2(from)) > 0.5
				and point.distance_to(Vector2(to)) > 0.5
			):
				return true
	return false


## 省份对偶图真源：只统计栅格四邻域共享边界；仅在角点接触不算接壤。
## 返回规范化 pair_key -> 共享栅格边数量。
static func province_shared_boundary_counts(
	province_ids: PackedInt32Array,
	size: Vector2i
) -> Dictionary:
	var result := {}
	if (
		size.x <= 0 or size.y <= 0
		or province_ids.size() != size.x * size.y
	):
		return result
	for y in range(size.y):
		for x in range(size.x):
			var owner := int(province_ids[y * size.x + x])
			if owner < 0:
				continue
			if x + 1 < size.x:
				_accumulate_province_boundary(
					result, owner,
					int(province_ids[y * size.x + x + 1])
				)
			if y + 1 < size.y:
				_accumulate_province_boundary(
					result, owner,
					int(province_ids[(y + 1) * size.x + x])
				)
	return result


static func _accumulate_province_boundary(
	counts: Dictionary, owner_a: int, owner_b: int
) -> void:
	if owner_b < 0 or owner_a == owner_b:
		return
	var key := _pair_key(owner_a, owner_b)
	counts[key] = int(counts.get(key, 0)) + 1


## 验证任一道路折线段只经过端点两省；按栅格尺度 2 倍超采样覆盖对角穿格。
static func province_segment_stays_in_pair(
	province_ids: PackedInt32Array,
	size: Vector2i,
	from: Vector2,
	to: Vector2,
	province_a: int,
	province_b: int
) -> bool:
	if (
		size.x <= 0 or size.y <= 0
		or province_ids.size() != size.x * size.y
	):
		return false
	var raster_from := Vector2(
		from.x * float(size.x), from.y * float(size.y)
	)
	var raster_to := Vector2(
		to.x * float(size.x), to.y * float(size.y)
	)
	var sample_count := maxi(
		int(ceil(maxf(
			absf(raster_to.x - raster_from.x),
			absf(raster_to.y - raster_from.y)
		) * 2.0)),
		1
	)
	for sample in range(sample_count + 1):
		var ratio := float(sample) / float(sample_count)
		var point := from.lerp(to, ratio)
		var x := clampi(int(floor(point.x * float(size.x))), 0, size.x - 1)
		var y := clampi(int(floor(point.y * float(size.y))), 0, size.y - 1)
		var owner := int(province_ids[y * size.x + x])
		if owner not in [province_a, province_b]:
			return false
	return true


## 为凹形接壤省份生成联合域内的正式道路折线。直线本来就合法时不保存冗余路径。
static func _attach_province_land_paths(
	roads: Array[Dictionary],
	provinces: Dictionary,
	positions: Array[Vector2],
	land_city_count: int
) -> void:
	var size: Vector2i = provinces["size"]
	var ids: PackedInt32Array = provinces["ids"]
	for road in roads:
		if (
			int(road.get("kind", Edge.Kind.LAND)) != Edge.Kind.LAND
			or int(road["a"]) >= land_city_count
			or int(road["b"]) >= land_city_count
		):
			continue
		var a := int(road["a"])
		var b := int(road["b"])
		if road.has("map_path") or province_segment_stays_in_pair(
			ids, size, positions[a], positions[b], a, b
		):
			continue
		var path := province_pair_path(
			ids, size, positions[a], positions[b], a, b
		)
		if path.size() >= 2:
			road["map_path"] = path
			var metric_length := metric_polyline_length(
				path, MapSource.aspect_ratio()
			)
			road["length"] = metric_length
			road["distance"] = distance_units_for_metric_length(metric_length)


static func metric_polyline_length(
	points: PackedVector2Array, map_aspect_ratio: float
) -> float:
	var result := 0.0
	for index in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		delta.x *= map_aspect_ratio
		result += delta.length()
	return result


## 在两个端点省份的联合栅格内做确定性 A*。返回归一化地图折线，首尾钉死城市中心。
static func province_pair_path(
	province_ids: PackedInt32Array,
	size: Vector2i,
	from: Vector2,
	to: Vector2,
	province_a: int,
	province_b: int
) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if (
		size.x <= 0 or size.y <= 0
		or province_ids.size() != size.x * size.y
	):
		return empty
	var start := Vector2i(
		clampi(int(floor(from.x * size.x)), 0, size.x - 1),
		clampi(int(floor(from.y * size.y)), 0, size.y - 1)
	)
	var goal := Vector2i(
		clampi(int(floor(to.x * size.x)), 0, size.x - 1),
		clampi(int(floor(to.y * size.y)), 0, size.y - 1)
	)
	var start_index := start.y * size.x + start.x
	var goal_index := goal.y * size.x + goal.x
	var distance := PackedFloat64Array()
	distance.resize(size.x * size.y)
	distance.fill(INF)
	var previous := PackedInt32Array()
	previous.resize(size.x * size.y)
	previous.fill(-1)
	var heap: Array[Vector3] = []
	distance[start_index] = 0.0
	_province_heap_push(heap, Vector3(0.0, start_index, 0.0))
	var offsets := [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	]
	while not heap.is_empty():
		var entry := _province_heap_pop(heap)
		var current_index := int(entry.y)
		var current_cost := float(entry.z)
		if current_cost > distance[current_index] + 0.000001:
			continue
		if current_index == goal_index:
			break
		var current := Vector2i(
			current_index % size.x, current_index / size.x
		)
		for offset_value in offsets:
			var offset: Vector2i = offset_value
			var next: Vector2i = current + offset
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var next_index: int = next.y * size.x + next.x
			var owner := int(province_ids[next_index])
			if owner not in [province_a, province_b]:
				continue
			var candidate := current_cost + 1.0
			if (
				candidate < distance[next_index] - 0.000001
				or (
					is_equal_approx(candidate, distance[next_index])
					and current_index < previous[next_index]
				)
			):
				distance[next_index] = candidate
				previous[next_index] = current_index
				var heuristic := Vector2(next).distance_to(Vector2(goal))
				_province_heap_push(
					heap, Vector3(candidate + heuristic, next_index, candidate)
				)
	if start_index != goal_index and previous[goal_index] < 0:
		return empty
	var raster_points: Array[Vector2i] = []
	var cursor := goal_index
	while cursor >= 0:
		raster_points.append(Vector2i(cursor % size.x, cursor / size.x))
		if cursor == start_index:
			break
		cursor = previous[cursor]
	if raster_points.is_empty() or raster_points[-1] != start:
		return empty
	raster_points.reverse()
	var raw := PackedVector2Array([from])
	for raster_point in raster_points:
		raw.append(
			(Vector2(raster_point) + Vector2(0.5, 0.5))
				/ Vector2(size)
		)
	raw.append(to)
	var result := PackedVector2Array([raw[0]])
	var anchor := 0
	while anchor < raw.size() - 1:
		var next_anchor := anchor + 1
		for candidate_index in range(raw.size() - 1, anchor, -1):
			if province_segment_stays_in_pair(
				province_ids, size, raw[anchor], raw[candidate_index],
				province_a, province_b
			):
				next_anchor = candidate_index
				break
		if next_anchor <= anchor:
			return empty
		result.append(raw[next_anchor])
		anchor = next_anchor
	return result


static func _build_river_transport(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i,
	samples: Dictionary,
	base_roads: Array[Dictionary],
	river_paths: Array[Array],
	city_count: int,
	map_aspect_ratio: float
) -> Dictionary:
	var dock_result := _find_river_docks(
		image,
		bounds,
		samples["pixels"],
		samples["positions"],
		base_roads,
		river_paths,
		city_count,
		map_aspect_ratio
	)
	var docks: Array[Dictionary] = dock_result["docks"]
	var crossings_by_road: Dictionary = dock_result[
		"crossings_by_road"
	]
	var blocked_crossing_roads: Dictionary = dock_result[
		"blocked_crossing_roads"
	]
	var city_positions: Array[Vector2] = samples["positions"]
	city_positions = city_positions.duplicate()
	for dock in docks:
		assert(
			int(dock["city_id"]) == city_positions.size(),
			"码头位置顺序必须与城市 id 一致"
		)
		city_positions.append(dock["position"])
	var landing_grid := _build_river_avoiding_landing_grid(
		mask, image.get_size(), river_paths
	)
	var roads: Array[Dictionary] = []
	for road_index in range(base_roads.size()):
		var road: Dictionary = base_roads[road_index]
		if int(road.get("kind", Edge.Kind.LAND)) == Edge.Kind.SEA:
			var sea_road := road.duplicate(true)
			sea_road["max_manpower"] = Edge.WATER_MANPOWER
			sea_road["allows_holding"] = false
			roads.append(sea_road)
			continue
		var crossings: Array = crossings_by_road.get(
			road_index,
			[]
		)
		if crossings.is_empty():
			if blocked_crossing_roads.has(road_index):
				assert(
					not bool(road.get("backbone", false)),
					"骨架跨河必须拆成A→渡口→B，禁止降级为SEA"
				)
				continue
			var land_road := road.duplicate(true)
			# 省份对偶候选永远是陆路；SEA 只能来自独立海区骨架。
			land_road["kind"] = Edge.Kind.LAND
			land_road["travel_time_multiplier"] = 1.0
			land_road["supply_loss_multiplier"] = 1.0
			land_road["allows_holding"] = true
			roads.append(land_road)
			continue
		crossings.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return float(a["road_t"]) < float(b["road_t"])
		)
		# 一条陆路只允许一个正式渡口，拓扑必须恒为 A→渡口→B。
		# 两岸段都重新在禁河网格内寻路，不能沿原折线保留第二个
		# 隐形穿河点，也不能生成两个码头间的平行 LANDING/RIVER 边。
		assert(crossings.size() == 1, "每条跨河陆路必须且只能有一个渡口")
		var previous_city := int(road["a"])
		for crossing in crossings:
			var dock_city := int(crossing["city_id"])
			var segment_path := _landing_path_avoiding_rivers(
				landing_grid, bounds,
				city_positions[previous_city], city_positions[dock_city]
			)
			roads.append(_landing_road_segment(
				road,
				previous_city,
				dock_city,
				city_positions,
				map_aspect_ratio,
				segment_path
			))
			previous_city = dock_city
		var final_path := _landing_path_avoiding_rivers(
			landing_grid, bounds,
			city_positions[previous_city], city_positions[int(road["b"])]
		)
		roads.append(_landing_road_segment(
			road,
			previous_city,
			int(road["b"]),
			city_positions,
			map_aspect_ratio,
			final_path
		))

	# 固定河程补充码头不依附既有穿河道路，用抢滩边接入最近陆城。
	for dock in docks:
		var direct_city := int(dock.get("direct_city", -1))
		if direct_city < 0:
			continue
		var dock_city := int(dock["city_id"])
		var metric_length := metric_length_between(
			city_positions[direct_city], city_positions[dock_city],
			map_aspect_ratio
		)
		roads.append({
			"a": direct_city,
			"b": dock_city,
			"length": metric_length,
			"distance": distance_units_for_metric_length(metric_length),
			"height_difference": absf(
				float(samples["heights"][direct_city]) - float(dock["height"])
			),
			"land_ratio": 1.0,
			"cost": metric_length,
			"backbone": true,
			"max_manpower": Edge.TERRAIN_LOW_MANPOWER,
			"base_max_manpower": Edge.TERRAIN_LOW_MANPOWER,
			"danger": LANDING_DANGER_MIN,
			"kind": Edge.Kind.LANDING,
			"travel_time_multiplier": 1.0,
			"supply_loss_multiplier": 1.0,
			"allows_holding": true,
		})

	var river_groups: Dictionary = dock_result["river_groups"]
	var active_paths: Array[PackedVector2Array] = []
	var occupied_pairs := {}
	for road in roads:
		occupied_pairs[_pair_key(
			int(road["a"]),
			int(road["b"])
		)] = true
	var river_ids := river_groups.keys()
	river_ids.sort()
	for river_id_value in river_ids:
		var river_id := int(river_id_value)
		var river_docks: Array = river_groups[river_id]
		if river_docks.size() < 2:
			continue
		river_docks.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return (
					float(a["river_progress"])
					< float(b["river_progress"])
				)
		)
		var path: Array[Vector2i] = river_paths[river_id]
		var normalized_path := _normalized_river_path(path, bounds)
		active_paths.append(normalized_path)
		for index in range(river_docks.size() - 1):
			var from_dock: Dictionary = river_docks[index]
			var to_dock: Dictionary = river_docks[index + 1]
			var from_city := int(from_dock["city_id"])
			var to_city := int(to_dock["city_id"])
			var pair_key := _pair_key(from_city, to_city)
			if occupied_pairs.has(pair_key):
				continue
			occupied_pairs[pair_key] = true
			var from_position: Vector2 = from_dock["position"]
			var to_position: Vector2 = to_dock["position"]
			# 河运边的几何必须就是两座码头之间的河道切片。只保存端点
			# 会让渲染、拾取和行军退回中心直线；河流稍有曲折时，东段
			# 就会与河道本体错开，看起来像河运道路中途消失。
			var river_map_path := _river_path_between_docks(
				normalized_path,
				from_position,
				to_position,
				float(from_dock["river_progress"]),
				float(to_dock["river_progress"])
			)
			var metric_length := metric_polyline_length(
				river_map_path, map_aspect_ratio
			)
			var river_edge := {
				"a": from_city,
				"b": to_city,
				"map_path": river_map_path,
				"length": metric_length,
				"height_difference": absf(
					float(from_dock["height"])
					- float(to_dock["height"])
				),
				"land_ratio": 1.0,
				"cost": metric_length,
				"backbone": true,
				"max_manpower": Edge.WATER_MANPOWER,
				"danger": _river_link_danger(
					image,
					path,
					float(from_dock["river_progress"]),
					float(to_dock["river_progress"])
				),
				"distance": distance_units_for_metric_length(
					metric_length
				),
				"kind": Edge.Kind.RIVER,
				"travel_time_multiplier":
					RIVER_TRAVEL_TIME_MULTIPLIER,
				"supply_loss_multiplier":
					RIVER_SUPPLY_LOSS_MULTIPLIER,
				"allows_holding": false,
			}
			roads.append(river_edge)
	assert(
		active_paths.size() == RIVER_COUNT,
		"正式地图必须生成两条具备至少两个码头的有效河运路线"
	)
	return {
		"roads": roads,
		"docks": docks,
		"river_paths": active_paths,
	}


## 按原始河程截取相邻码头间的正式折线。码头可能来自道路与河道的
## 亚像素交点，所以首尾使用码头精确位置，中间使用河道采样点。
static func _river_path_between_docks(
	river: PackedVector2Array,
	from_position: Vector2,
	to_position: Vector2,
	from_progress: float,
	to_progress: float
) -> PackedVector2Array:
	assert(river.size() >= 2, "河运边必须依附有效河道")
	assert(
		to_progress > from_progress,
		"相邻码头必须按递增河程连接"
	)
	var result := PackedVector2Array([from_position])
	for river_index in range(1, river.size() - 1):
		if (
			float(river_index) <= from_progress + 0.000001
			or float(river_index) >= to_progress - 0.000001
		):
			continue
		var point := river[river_index]
		if result[-1].distance_squared_to(point) > 0.000000000001:
			result.append(point)
	if result[-1].distance_squared_to(to_position) > 0.000000000001:
		result.append(to_position)
	else:
		result[-1] = to_position
	assert(result.size() >= 2, "相邻码头河道切片不能为空")
	return result


static func _build_river_paths(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i
) -> Array[Array]:
	var templates: Array[PackedVector2Array] = [
		PackedVector2Array([
			Vector2(0.10, 0.535),
			Vector2(0.27, 0.525),
			Vector2(0.44, 0.533),
			Vector2(0.61, 0.522),
			Vector2(0.78, 0.530),
			Vector2(0.94, 0.523),
		]),
		PackedVector2Array([
			Vector2(0.08, 0.665),
			Vector2(0.26, 0.660),
			Vector2(0.44, 0.656),
			Vector2(0.62, 0.652),
			Vector2(0.80, 0.648),
			Vector2(0.97, 0.644),
		]),
	]
	var paths: Array[Array] = []
	for river_index in range(mini(RIVER_COUNT, templates.size())):
		var template := templates[river_index]
		var path := _build_monotonic_river_path(
			image, mask, bounds, template, river_index
		)
		if path.size() >= 2:
			var mouth_point := path[-1]
			var sea_point := Vector2i(mouth_point.x + 1, mouth_point.y)
			if (
				packed_is_land(image.get_pixelv(mouth_point))
				and
				sea_point.x < image.get_width()
				and mask[sea_point.y * image.get_width() + sea_point.x] == 0
			):
				path.append(sea_point)
			paths.append(path)
	return paths


## 西向东单调河道：近水平模板叠加小振幅确定性曲线，地形只在窄带内微调。
static func _build_monotonic_river_path(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i,
	template: PackedVector2Array,
	river_index: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start_x := clampi(
		int(round(lerpf(bounds.position.x, bounds.end.x - 1, template[0].x))),
		bounds.position.x, bounds.end.x - 1
	)
	var end_x := clampi(
		int(round(lerpf(bounds.position.x, bounds.end.x - 1, template[-1].x))),
		start_x + 1, bounds.end.x - 1
	)
	var previous_y := -1
	for x in range(start_x, end_x + 1):
		var normalized_x := inverse_lerp(
			float(bounds.position.x), float(maxi(bounds.end.x - 1, bounds.position.x + 1)), float(x)
		)
		var micro_curve := (
			sin(normalized_x * TAU * 4.0 + float(river_index) * 1.7)
			+ sin(normalized_x * TAU * 9.0 + float(river_index) * 0.8) * 0.35
		) * RIVER_MICRO_CURVE_AMPLITUDE
		var target_y := int(round(lerpf(
			float(bounds.position.y), float(bounds.end.y - 1),
			clampf(_river_template_y(template, normalized_x) + micro_curve, 0.0, 1.0)
		)))
		if previous_y >= 0:
			target_y = clampi(target_y, previous_y - 1, previous_y + 1)
		var best_y := -1
		var best_score := INF
		for offset in range(-RIVER_LOCAL_SEARCH_RADIUS, RIVER_LOCAL_SEARCH_RADIUS + 1):
			var y := clampi(target_y + offset, bounds.position.y, bounds.end.y - 1)
			if mask[y * image.get_width() + x] == 0:
				continue
			if previous_y >= 0 and absi(y - previous_y) > 1:
				continue
			var score := (
				absf(float(y - target_y)) * 3.0
				+ packed_altitude(image.get_pixel(x, y)) * 0.8
				+ _pixel_relief(image, x, y) * 4.0
			)
			if score < best_score:
				best_score = score
				best_y = y
		if best_y < 0:
			if not result.is_empty():
				# 第一次离开连续陆地即为河口：记录首个海面点后结束，
				# 禁止跳过海面再连接更东边陆地形成“飞线”。
				result.append(Vector2i(x, previous_y))
				break
			continue
		var point := Vector2i(x, best_y)
		if result.is_empty() or point != result[-1]:
			result.append(point)
		previous_y = best_y
	return result


static func _river_template_y(
	template: PackedVector2Array,
	normalized_x: float
) -> float:
	if normalized_x <= template[0].x:
		return template[0].y
	for index in range(template.size() - 1):
		var from := template[index]
		var to := template[index + 1]
		if normalized_x > to.x:
			continue
		var ratio := clampf(
			(normalized_x - from.x)
				/ maxf(to.x - from.x, 0.0001),
			0.0,
			1.0
		)
		return lerpf(from.y, to.y, ratio)
	return template[-1].y


static func _find_river_docks(
	image: Image,
	bounds: Rect2i,
	city_pixels: Array[Vector2i],
	city_positions: Array[Vector2],
	roads: Array[Dictionary],
	river_paths: Array[Array],
	city_count: int,
	map_aspect_ratio: float
) -> Dictionary:
	var docks: Array[Dictionary] = []
	var crossings_by_road := {}
	var river_groups := {}
	var raw_crossings_by_road := {}
	var candidates_by_river := {}
	for river_id in range(river_paths.size()):
		var path: Array[Vector2i] = river_paths[river_id]
		var candidates: Array[Dictionary] = []
		for road_index in range(roads.size()):
			var road := roads[road_index]
			if int(road.get("kind", Edge.Kind.LAND)) == Edge.Kind.SEA:
				continue
			var road_crossings := _road_river_crossings(
				city_pixels,
				road,
				road_index,
				path,
				river_id,
				bounds,
				map_aspect_ratio
			)
			for crossing in road_crossings:
				var crossing_pixel: Vector2 = crossing["pixel_position"]
				var crossing_x := clampi(int(round(crossing_pixel.x)), 0, image.get_width() - 1)
				var crossing_y := clampi(int(round(crossing_pixel.y)), 0, image.get_height() - 1)
				crossing["height"] = packed_altitude(
					image.get_pixel(crossing_x, crossing_y)
				)
				if not raw_crossings_by_road.has(road_index):
					raw_crossings_by_road[road_index] = []
				(raw_crossings_by_road[road_index] as Array).append(
					crossing
				)
				# 关闭道路只参与“永不得被运行时重新开启为穿河陆路”判定，
				# 不为它额外生成码头。
				if int(road["max_manpower"]) > 0:
					candidates.append(crossing)
		candidates_by_river[river_id] = candidates

	# A crossing too close to any ordinary city invalidates that whole road as
	# a dock road. Otherwise selecting another crossing of the same meandering
	# road could still leave an overlapping landing segment.
	var city_spacing_rejected_roads := {}
	for candidates_value in candidates_by_river.values():
		for candidate in candidates_value:
			var candidate_position: Vector2 = candidate["position"]
			for city_position in city_positions:
				var city_delta := candidate_position - city_position
				city_delta.x *= map_aspect_ratio
				if city_delta.length() < RIVER_DOCK_CITY_MIN_SPACING:
					city_spacing_rejected_roads[int(candidate["road_index"])] = true
					break
	for river_id in candidates_by_river:
		var retained: Array[Dictionary] = []
		for candidate in candidates_by_river[river_id]:
			if not city_spacing_rejected_roads.has(int(candidate["road_index"])):
				retained.append(candidate)
		candidates_by_river[river_id] = retained

	var selected_dock_roads := _select_dock_crossing_roads(
		candidates_by_river,
		roads,
		city_positions,
		map_aspect_ratio
	)
	var accepted_positions: Array[Vector2] = []
	var resolved_crossing_roads := {}
	# A straight road can intersect a meandering river more than once.  If one
	# crossing is too close to an existing dock, retaining only the other
	# crossing would leave a visible landing segment cutting across the river.
	# Reject that entire road after candidate collection instead.
	var spacing_rejected_roads := {}
	for river_id in range(river_paths.size()):
		var candidates: Array[Dictionary] = candidates_by_river.get(
			river_id,
			[]
		)
		candidates.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return (
					float(a["river_progress"])
					< float(b["river_progress"])
				)
		)
		if candidates.size() < 2:
			continue
		for candidate in candidates:
			var candidate_road_index := int(candidate["road_index"])
			if (
			not selected_dock_roads.has(candidate_road_index)
			or resolved_crossing_roads.has(candidate_road_index)
			):
				continue
			resolved_crossing_roads[candidate_road_index] = true
			# 道路与河线的亚像素交点可能落在两个河道采样点之间。
			# 抢滩路径若以该交点为终点，会先经过相邻河道顶点，再沿河
			# 重叠一小段。统一吸附到最近河道顶点，保证仅在端点接河。
			var river_path: Array[Vector2i] = river_paths[river_id]
			var snapped_river_index := clampi(
				int(round(float(candidate["river_progress"]))),
				1, river_path.size() - 2
			)
			var snapped_pixel := river_path[snapped_river_index]
			var candidate_position := _normalized_map_point(
				Vector2(snapped_pixel), bounds
			)
			candidate["river_progress"] = float(snapped_river_index)
			candidate["pixel_position"] = Vector2(snapped_pixel)
			candidate["position"] = candidate_position
			var overlaps_existing := false
			for accepted_position in accepted_positions:
				var spacing_delta := candidate_position - accepted_position
				spacing_delta.x *= map_aspect_ratio
				if spacing_delta.length() < RIVER_DOCK_MIN_SPACING:
					overlaps_existing = true
					break
			if overlaps_existing:
				spacing_rejected_roads[candidate_road_index] = true
				continue
			var pixel_position: Vector2 = candidate[
				"pixel_position"
			]
			var x := clampi(
				int(round(pixel_position.x)),
				0,
				image.get_width() - 1
			)
			var y := clampi(
				int(round(pixel_position.y)),
				0,
				image.get_height() - 1
			)
			candidate["city_id"] = city_count + docks.size()
			candidate["height"] = packed_altitude(
				image.get_pixel(x, y)
			)
			candidate["relief"] = _local_relief(
				image,
				x,
				y,
				RELIEF_RADIUS
			)
			var road: Dictionary = roads[
				int(candidate["road_index"])
			]
			candidate["road_a"] = int(road["a"])
			candidate["road_b"] = int(road["b"])
			# 已被普通选择器命中的骨架渡口同样是强制节点。若不标记，
			# 后续 32 码头视觉裁剪会把它当作普通码头删除，使骨架路
			# 重新变成无渡口穿河。
			if bool(road.get("backbone", false)):
				candidate["mandatory_crossing"] = true
			docks.append(candidate)
			accepted_positions.append(candidate_position)
			if not crossings_by_road.has(
				int(candidate["road_index"])
			):
				crossings_by_road[
					int(candidate["road_index"])
				] = []
			(crossings_by_road[
				int(candidate["road_index"])
			] as Array).append(candidate)
			if not river_groups.has(river_id):
				river_groups[river_id] = []
			(river_groups[river_id] as Array).append(candidate)
	if not spacing_rejected_roads.is_empty():
		var retained_docks: Array[Dictionary] = []
		for dock in docks:
			if spacing_rejected_roads.has(int(dock["road_index"])):
				continue
			dock["city_id"] = city_count + retained_docks.size()
			retained_docks.append(dock)
		docks = retained_docks
		crossings_by_road.clear()
		river_groups.clear()
		for dock in docks:
			var road_index := int(dock["road_index"])
			var river_id := int(dock["river_id"])
			if not crossings_by_road.has(road_index):
				crossings_by_road[road_index] = []
			(crossings_by_road[road_index] as Array).append(dock)
			if not river_groups.has(river_id):
				river_groups[river_id] = []
			(river_groups[river_id] as Array).append(dock)
	accepted_positions.clear()
	for dock in docks:
		accepted_positions.append(dock["position"])
	_force_backbone_crossing_docks(
		docks, crossings_by_road, river_groups, accepted_positions,
		raw_crossings_by_road, roads, image, bounds,
		city_positions, river_paths, city_count, map_aspect_ratio
	)
	_supplement_fixed_interval_docks(
		docks, river_groups, accepted_positions,
		image, bounds, city_positions, river_paths,
		city_count, map_aspect_ratio
	)
	_trim_optional_docks(
		docks, crossings_by_road, river_groups, city_count, 32
	)
	var blocked_crossing_roads := {}
	for road_index_value in raw_crossings_by_road:
		var road_index := int(road_index_value)
		if not crossings_by_road.has(road_index):
			blocked_crossing_roads[road_index] = true
	return {
		"docks": docks,
		"crossings_by_road": crossings_by_road,
		"blocked_crossing_roads": blocked_crossing_roads,
		"river_groups": river_groups,
	}


## 总码头超出视觉上限时，只裁普通密度码头；强制骨架渡口和固定补充码头保留。
static func _trim_optional_docks(
	docks: Array[Dictionary],
	crossings_by_road: Dictionary,
	river_groups: Dictionary,
	city_count: int,
	maximum_count: int
) -> void:
	while docks.size() > maximum_count:
		var remove_index := -1
		for index in range(docks.size() - 1, -1, -1):
			var dock: Dictionary = docks[index]
			if bool(dock.get("mandatory_crossing", false)):
				continue
			if bool(dock.get("supplemental", false)):
				continue
			var river_id := int(dock["river_id"])
			var group: Array = river_groups.get(river_id, [])
			var minimum := (
				RIVER_DOCK_SOUTH_MIN_PER_RIVER
				if river_id == 1 else RIVER_DOCK_MIN_PER_RIVER
			)
			if group.size() <= minimum:
				continue
			if river_id == 1:
				var dock_x := float((dock["position"] as Vector2).x)
				if (
					dock_x >= RIVER_DOCK_SOUTH_MOUTH_MIN_X
					and _count_docks_at_or_east(
						group, RIVER_DOCK_SOUTH_MOUTH_MIN_X
					) <= RIVER_DOCK_SOUTH_MOUTH_MIN
				):
					continue
				if (
					dock_x >= RIVER_DOCK_SOUTH_EAST_MIN_X
					and _count_docks_at_or_east(
						group, RIVER_DOCK_SOUTH_EAST_MIN_X
					) <= RIVER_DOCK_SOUTH_EAST_MIN
				):
					continue
			remove_index = index
			break
		if remove_index < 0:
			break
		docks.remove_at(remove_index)
		# 下一轮配额判定必须读取删除后的实时分组。若沿用裁剪前的
		# river_groups，连续删除会一直看到旧的“东段仍有 6 个”，
		# 最终把南河下游裁到配额以下。
		river_groups.clear()
		for remaining_dock in docks:
			var remaining_river_id := int(remaining_dock["river_id"])
			if not river_groups.has(remaining_river_id):
				river_groups[remaining_river_id] = []
			(river_groups[remaining_river_id] as Array).append(remaining_dock)
	for index in range(docks.size()):
		docks[index]["city_id"] = city_count + index
	crossings_by_road.clear()
	river_groups.clear()
	for dock in docks:
		var river_id := int(dock["river_id"])
		if not river_groups.has(river_id):
			river_groups[river_id] = []
		(river_groups[river_id] as Array).append(dock)
		var road_index := int(dock.get("road_index", -1))
		if road_index < 0:
			continue
		if not crossings_by_road.has(road_index):
			crossings_by_road[road_index] = []
		(crossings_by_road[road_index] as Array).append(dock)


## 骨架跨河不得降级为 SEA。若普通密度/间距筛选未选中交点，沿同一河道
## 搜索最近合法点，强制生成渡口，使道路仍统一拆为 A→渡口→B。
static func _force_backbone_crossing_docks(
	docks: Array[Dictionary],
	crossings_by_road: Dictionary,
	river_groups: Dictionary,
	accepted_positions: Array[Vector2],
	raw_crossings_by_road: Dictionary,
	roads: Array[Dictionary],
	image: Image,
	bounds: Rect2i,
	city_positions: Array[Vector2],
	river_paths: Array[Array],
	city_count: int,
	map_aspect_ratio: float
) -> void:
	var road_indices := raw_crossings_by_road.keys()
	road_indices.sort()
	for road_index_value in road_indices:
		var road_index := int(road_index_value)
		if crossings_by_road.has(road_index):
			continue
		var road: Dictionary = roads[road_index]
		if not bool(road.get("backbone", false)):
			continue
		var raw: Array = raw_crossings_by_road[road_index]
		raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["road_t"]) < float(b["road_t"])
		)
		for raw_crossing in raw:
			var river_id := int(raw_crossing["river_id"])
			var path: Array[Vector2i] = river_paths[river_id]
			var origin_index := clampi(
				int(round(float(raw_crossing["river_progress"]))),
				1, path.size() - 2
			)
			var best_index := -1
			var best_offset := path.size()
			for path_index in range(1, path.size() - 1):
				var offset := absi(path_index - origin_index)
				if offset > best_offset:
					continue
				var pixel := path[path_index]
				if not packed_is_land(image.get_pixelv(pixel)):
					continue
				var position := _normalized_map_point(pixel, bounds)
				if not _dock_position_spacing_valid(
					position, city_positions, accepted_positions,
					map_aspect_ratio
				):
					continue
				if offset < best_offset or (offset == best_offset and path_index < best_index):
					best_offset = offset
					best_index = path_index
			assert(best_index >= 0, "骨架跨河必须能生成合法渡口，禁止降级为SEA")
			var pixel := path[best_index]
			var position := _normalized_map_point(pixel, bounds)
			var dock: Dictionary = raw_crossing.duplicate(true)
			dock["city_id"] = city_count + docks.size()
			dock["river_progress"] = float(best_index)
			dock["pixel_position"] = Vector2(pixel)
			dock["position"] = position
			dock["height"] = packed_altitude(image.get_pixelv(pixel))
			dock["relief"] = _local_relief(image, pixel.x, pixel.y, RELIEF_RADIUS)
			dock["road_a"] = int(road["a"])
			dock["road_b"] = int(road["b"])
			dock["mandatory_crossing"] = true
			docks.append(dock)
			accepted_positions.append(position)
			if not crossings_by_road.has(road_index):
				crossings_by_road[road_index] = []
			(crossings_by_road[road_index] as Array).append(dock)
			if not river_groups.has(river_id):
				river_groups[river_id] = []
			(river_groups[river_id] as Array).append(dock)
			break


static func _dock_position_spacing_valid(
	position: Vector2,
	city_positions: Array[Vector2],
	dock_positions: Array[Vector2],
	map_aspect_ratio: float
) -> bool:
	for city_position in city_positions:
		var delta := position - city_position
		delta.x *= map_aspect_ratio
		if delta.length() < RIVER_DOCK_CITY_MIN_SPACING:
			return false
	for dock_position in dock_positions:
		var delta := position - dock_position
		delta.x *= map_aspect_ratio
		if delta.length() < RIVER_DOCK_MIN_SPACING:
			return false
	return true


## 道路交叉候选不足时，按河程最大空档补码头；南河独立保证更高密度。
## 补充码头通过 direct_city 生成抢滩边，不依赖某条道路恰好穿河。
static func _supplement_fixed_interval_docks(
	docks: Array[Dictionary],
	river_groups: Dictionary,
	accepted_positions: Array[Vector2],
	image: Image,
	bounds: Rect2i,
	city_positions: Array[Vector2],
	river_paths: Array[Array],
	city_count: int,
	map_aspect_ratio: float
) -> void:
	for river_id in range(river_paths.size()):
		var required := (
			RIVER_DOCK_SOUTH_MIN_PER_RIVER
			if river_id == 1
			else RIVER_DOCK_MIN_PER_RIVER
		)
		if not river_groups.has(river_id):
			river_groups[river_id] = []
		var group: Array = river_groups[river_id]
		var path: Array[Vector2i] = river_paths[river_id]
		while (
			group.size() < required
			or (
				river_id == 1
				and (
					_count_docks_at_or_east(group, RIVER_DOCK_SOUTH_EAST_MIN_X)
						< RIVER_DOCK_SOUTH_EAST_MIN
					or _count_docks_at_or_east(group, RIVER_DOCK_SOUTH_MOUTH_MIN_X)
						< RIVER_DOCK_SOUTH_MOUTH_MIN
				)
			)
		):
			var required_x := 0.0
			if river_id == 1:
				if _count_docks_at_or_east(
					group, RIVER_DOCK_SOUTH_MOUTH_MIN_X
				) < RIVER_DOCK_SOUTH_MOUTH_MIN:
					required_x = RIVER_DOCK_SOUTH_MOUTH_MIN_X
				elif _count_docks_at_or_east(
					group, RIVER_DOCK_SOUTH_EAST_MIN_X
				) < RIVER_DOCK_SOUTH_EAST_MIN:
					required_x = RIVER_DOCK_SOUTH_EAST_MIN_X
			var best_index := -1
			var best_score := -INF
			var best_position := Vector2.ZERO
			var best_city := -1
			for path_index in range(1, path.size() - 1):
				var pixel := path[path_index]
				if not packed_is_land(image.get_pixelv(pixel)):
					continue
				var position := _normalized_map_point(pixel, bounds)
				if position.x < required_x:
					continue
				var spacing_valid := true
				for city_position in city_positions:
					var city_delta := position - city_position
					city_delta.x *= map_aspect_ratio
					if city_delta.length() < RIVER_DOCK_CITY_MIN_SPACING:
						spacing_valid = false
						break
				if not spacing_valid:
					continue
				var minimum_dock_distance := INF
				for dock_value in group:
					var dock: Dictionary = dock_value
					var dock_delta := position - Vector2(dock["position"])
					dock_delta.x *= map_aspect_ratio
					minimum_dock_distance = minf(
						minimum_dock_distance, dock_delta.length()
					)
				if minimum_dock_distance < RIVER_DOCK_MIN_SPACING:
					continue
				var nearest_city := _nearest_same_bank_city(
					position, city_positions, river_paths, bounds,
					city_count, map_aspect_ratio
				)
				if nearest_city < 0:
					continue
				var altitude := packed_altitude(image.get_pixelv(pixel))
				var lowland_bonus := (
					1.0 - smoothstep(0.0, RIVER_DOCK_LOWLAND_ALTITUDE, altitude)
				) * 0.025
				var eastern_bonus := maxf(position.x - RIVER_DOCK_EASTERN_MIN_X, 0.0) * 0.02
				var score := minimum_dock_distance + lowland_bonus + eastern_bonus
				if score > best_score:
					best_score = score
					best_index = path_index
					best_position = position
					best_city = nearest_city
			if best_index < 0:
				break
			var pixel := path[best_index]
			var dock := {
				"city_id": city_count + docks.size(),
				"river_id": river_id,
				"river_progress": float(best_index),
				"pixel_position": Vector2(pixel),
				"position": best_position,
				"height": packed_altitude(image.get_pixelv(pixel)),
				"relief": _local_relief(image, pixel.x, pixel.y, RELIEF_RADIUS),
				"road_index": -1,
				"road_a": best_city,
				"road_b": best_city,
				"road_t": 0.0,
				"direct_city": best_city,
				"supplemental": true,
			}
			docks.append(dock)
			group.append(dock)
			accepted_positions.append(best_position)


static func _nearest_same_bank_city(
	dock_position: Vector2,
	city_positions: Array[Vector2],
	river_paths: Array[Array],
	bounds: Rect2i,
	city_count: int,
	map_aspect_ratio: float
) -> int:
	var best_city := -1
	var best_distance := INF
	for city_id in range(city_count):
		var city_position := city_positions[city_id]
		var crosses_before_dock := false
		for river_path in river_paths:
			for river_index in range(river_path.size() - 1):
				var river_from := _normalized_map_point(
					Vector2(river_path[river_index]), bounds
				)
				var river_to := _normalized_map_point(
					Vector2(river_path[river_index + 1]), bounds
				)
				var hit = Geometry2D.segment_intersects_segment(
					city_position, dock_position, river_from, river_to
				)
				if hit != null and Vector2(hit).distance_to(dock_position) > 0.0001:
					crosses_before_dock = true
					break
			if crosses_before_dock:
				break
		if crosses_before_dock:
			continue
		var delta := dock_position - city_position
		delta.x *= map_aspect_ratio
		var distance := delta.length_squared()
		if distance < best_distance:
			best_distance = distance
			best_city = city_id
	return best_city


static func _count_docks_at_or_east(
	docks: Array, minimum_x: float
) -> int:
	var result := 0
	for dock_value in docks:
		var dock: Dictionary = dock_value
		if float((dock["position"] as Vector2).x) >= minimum_x:
			result += 1
	return result


static func _select_dock_crossing_roads(
	candidates_by_river: Dictionary,
	roads: Array[Dictionary],
	city_positions: Array[Vector2],
	map_aspect_ratio: float
) -> Dictionary:
	var selected := {}
	var crossing_roads := {}
	for candidates_value in candidates_by_river.values():
		for candidate in candidates_value:
			crossing_roads[int(candidate["road_index"])] = true
	var river_ids := candidates_by_river.keys()
	river_ids.sort()
	for river_id_value in river_ids:
		var candidates: Array[Dictionary] = (
			candidates_by_river[river_id_value]
		)
		candidates.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return (
					float(a["river_progress"])
						< float(b["river_progress"])
				)
		)
		if candidates.is_empty():
			continue
		var cumulative := PackedFloat32Array()
		cumulative.resize(candidates.size())
		var total_distance := 0.0
		for candidate_index in range(1, candidates.size()):
			var delta: Vector2 = (
				candidates[candidate_index]["position"]
				- candidates[candidate_index - 1]["position"]
			)
			delta.x *= map_aspect_ratio
			var altitude := float(candidates[candidate_index].get(
				"height", 0.0
			))
			var lowland_ratio := 1.0 - smoothstep(
				0.0, RIVER_DOCK_LOWLAND_ALTITUDE, altitude
			)
			var density_weight := lerpf(
				1.0, RIVER_DOCK_LOWLAND_DENSITY, lowland_ratio
			)
			total_distance += delta.length() * density_weight
			cumulative[candidate_index] = total_distance
		var target_count := clampi(
			int(floor(total_distance / RIVER_DOCK_FIXED_INTERVAL)) + 1,
			mini(
				(
					RIVER_DOCK_SOUTH_MIN_PER_RIVER
					if int(river_id_value) == 1
					else RIVER_DOCK_MIN_PER_RIVER
				),
				candidates.size()
			),
			candidates.size()
		)
		var chosen_candidates := {}
		for target_index in range(target_count):
			var target_distance := (
				(float(target_index) + 0.5)
				* total_distance / float(maxi(target_count, 1))
			)
			var best_candidate := -1
			var best_error := INF
			for candidate_index in range(candidates.size()):
				var road_index := int(candidates[candidate_index]["road_index"])
				if chosen_candidates.has(candidate_index) or selected.has(road_index):
					continue
				var error := absf(cumulative[candidate_index] - target_distance)
				if error < best_error:
					best_error = error
					best_candidate = candidate_index
			if best_candidate >= 0:
				chosen_candidates[best_candidate] = true
				selected[int(candidates[best_candidate]["road_index"])] = true
		var eastern: Array[Dictionary] = []
		for candidate in candidates:
			var position: Vector2 = candidate["position"]
			if (
				position.x >= RIVER_DOCK_EASTERN_MIN_X
				and float(candidate.get("height", 1.0))
					<= RIVER_DOCK_LOWLAND_ALTITUDE
			):
				eastern.append(candidate)
		eastern.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["river_progress"]) < float(b["river_progress"])
		)
		var eastern_selected := 0
		for candidate in eastern:
			if selected.has(int(candidate["road_index"])):
				eastern_selected += 1
		for candidate in eastern:
			if eastern_selected >= RIVER_DOCK_EASTERN_MIN_PER_RIVER:
				break
			var road_index := int(candidate["road_index"])
			if not selected.has(road_index):
				selected[road_index] = true
				eastern_selected += 1
	var node_count := 0
	for road in roads:
		node_count = maxi(
			node_count,
			maxi(int(road["a"]), int(road["b"])) + 1
		)
	var parent: Array[int] = []
	parent.resize(node_count)
	for node in range(node_count):
		parent[node] = node
	for road_index in range(roads.size()):
		var road := roads[road_index]
		if (
			int(road["max_manpower"]) <= 0
			or (
				crossing_roads.has(road_index)
				and not selected.has(road_index)
			)
		):
			continue
		_river_union_find_join(
			parent,
			int(road["a"]),
			int(road["b"])
		)
	var crossing_indices := crossing_roads.keys()
	crossing_indices.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var road_a: Dictionary = roads[int(a)]
			var road_b: Dictionary = roads[int(b)]
			var backbone_a := bool(road_a.get("backbone", false))
			var backbone_b := bool(road_b.get("backbone", false))
			if backbone_a != backbone_b:
				return backbone_a
			if not is_equal_approx(
				float(road_a["cost"]),
				float(road_b["cost"])
			):
				return float(road_a["cost"]) < float(road_b["cost"])
			return int(a) < int(b)
	)
	# 正式地图开局按空间四分区分国。先在各国内部补足最少渡口，
	# 避免河道移动后全图仍连通、但单个国家领土被河流切成孤岛。
	var initial_owner := _initial_nation_owner_by_position(
		city_positions
	)
	var nation_parent: Array[int] = []
	nation_parent.resize(node_count)
	for node in range(node_count):
		nation_parent[node] = node
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		var city_a := int(road["a"])
		var city_b := int(road["b"])
		if (
			int(road["max_manpower"]) <= 0
			or initial_owner[city_a] != initial_owner[city_b]
			or (
				crossing_roads.has(road_index)
				and not selected.has(road_index)
			)
		):
			continue
		_river_union_find_join(
			nation_parent,
			city_a,
			city_b
		)
	for road_index_value in crossing_indices:
		var road_index := int(road_index_value)
		if selected.has(road_index):
			continue
		var road: Dictionary = roads[road_index]
		var city_a := int(road["a"])
		var city_b := int(road["b"])
		if initial_owner[city_a] != initial_owner[city_b]:
			continue
		if (
			_river_union_find_root(nation_parent, city_a)
				== _river_union_find_root(nation_parent, city_b)
		):
			continue
		selected[road_index] = true
		_river_union_find_join(
			nation_parent,
			city_a,
			city_b
		)

	# 在国家内部连通的基础上，再恢复全图连通所需的最少 crossing。
	parent.fill(0)
	for node in range(node_count):
		parent[node] = node
	for road_index in range(roads.size()):
		var road: Dictionary = roads[road_index]
		if (
			int(road["max_manpower"]) <= 0
			or (
				crossing_roads.has(road_index)
				and not selected.has(road_index)
			)
		):
			continue
		_river_union_find_join(
			parent,
			int(road["a"]),
			int(road["b"])
		)
	for road_index_value in crossing_indices:
		var road_index := int(road_index_value)
		if selected.has(road_index):
			continue
		var road: Dictionary = roads[road_index]
		var city_a := int(road["a"])
		var city_b := int(road["b"])
		if (
			_river_union_find_root(parent, city_a)
				== _river_union_find_root(parent, city_b)
		):
			continue
		selected[road_index] = true
		_river_union_find_join(parent, city_a, city_b)
	return selected


static func _initial_nation_owner_by_position(
	city_positions: Array[Vector2]
) -> Array[int]:
	var owner: Array[int] = []
	owner.resize(city_positions.size())
	owner.fill(-1)
	var ordered: Array[int] = []
	for city_id in range(city_positions.size()):
		ordered.append(city_id)
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var pa := city_positions[a]
		var pb := city_positions[b]
		if not is_equal_approx(pa.x, pb.x):
			return pa.x < pb.x
		return pa.y < pb.y
	)
	var side_size := city_positions.size() / 2
	for side in range(2):
		var side_cities: Array[int] = []
		for index in range(
			side * side_size,
			(side + 1) * side_size
		):
			side_cities.append(ordered[index])
		side_cities.sort_custom(func(a: int, b: int) -> bool:
			var pa := city_positions[a]
			var pb := city_positions[b]
			if not is_equal_approx(pa.y, pb.y):
				return pa.y < pb.y
			return pa.x < pb.x
		)
		for index in range(side_cities.size()):
			var row_half := (
				0
				if index < side_cities.size() / 2
				else 1
			)
			owner[side_cities[index]] = row_half * 2 + side
	return owner


static func _river_union_find_root(
	parent: Array[int],
	node: int
) -> int:
	var current := node
	while parent[current] != current:
		parent[current] = parent[parent[current]]
		current = parent[current]
	return current


static func _river_union_find_join(
	parent: Array[int],
	a: int,
	b: int
) -> void:
	var root_a := _river_union_find_root(parent, a)
	var root_b := _river_union_find_root(parent, b)
	if root_a != root_b:
		parent[root_b] = root_a


static func _road_river_crossings(
	city_pixels: Array[Vector2i],
	road: Dictionary,
	road_index: int,
	path: Array[Vector2i],
	river_id: int,
	bounds: Rect2i,
	map_aspect_ratio: float
) -> Array[Dictionary]:
	var crossings: Array[Dictionary] = []
	var road_points: Array[Vector2] = []
	var map_path: PackedVector2Array = road.get(
		"map_path", PackedVector2Array()
	)
	if map_path.size() >= 2:
		for map_point in map_path:
			road_points.append(
				Vector2(bounds.position)
					+ map_point * Vector2(bounds.size)
					- Vector2(0.5, 0.5)
			)
		road_points[0] = Vector2(city_pixels[int(road["a"])])
		road_points[-1] = Vector2(city_pixels[int(road["b"])])
	else:
		road_points = [
			Vector2(city_pixels[int(road["a"])]),
			Vector2(city_pixels[int(road["b"])]),
		]
	var normalized_points := PackedVector2Array()
	for road_point in road_points:
		normalized_points.append(_normalized_map_point(road_point, bounds))
	var cumulative := PackedFloat32Array([0.0])
	var total_length := 0.0
	for road_segment in range(normalized_points.size() - 1):
		total_length += metric_length_between(
			normalized_points[road_segment],
			normalized_points[road_segment + 1],
			map_aspect_ratio
		)
		cumulative.append(total_length)
	if total_length <= 0.001:
		return crossings
	for road_segment in range(road_points.size() - 1):
		var road_start := road_points[road_segment]
		var road_end := road_points[road_segment + 1]
		for path_index in range(path.size() - 1):
			var river_start := Vector2(path[path_index])
			var river_end := Vector2(path[path_index + 1])
			var hit = Geometry2D.segment_intersects_segment(
				road_start, road_end, river_start, river_end
			)
			if hit == null:
				continue
			var point: Vector2 = hit
			var normalized_hit := _normalized_map_point(point, bounds)
			var road_t := (
				float(cumulative[road_segment])
					+ metric_length_between(
						normalized_points[road_segment], normalized_hit,
						map_aspect_ratio
					)
			) / total_length
			if (
				road_t <= RIVER_CROSSING_ENDPOINT_EPS
				or road_t >= 1.0 - RIVER_CROSSING_ENDPOINT_EPS
			):
				continue
			crossings.append({
				"road_index": road_index,
				"road_t": road_t,
				"river_id": river_id,
				"river_progress": float(path_index)
					+ _segment_fraction(point, river_start, river_end),
				"pixel_position": point,
				"position": _normalized_map_point(point, bounds),
			})
	crossings.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(
				float(a["road_t"]),
				float(b["road_t"])
			):
				return float(a["road_t"]) < float(b["road_t"])
			return (
				float(a["river_progress"])
				< float(b["river_progress"])
			)
	)
	var merged: Array[Dictionary] = []
	for crossing in crossings:
		if (
			not merged.is_empty()
			and absf(
				float(crossing["road_t"])
					- float(merged[-1]["road_t"])
			) <= RIVER_CROSSING_MERGE_EPS
		):
			continue
		merged.append(crossing)
	return merged


static func _landing_road_segment(
	base: Dictionary,
	from_city: int,
	to_city: int,
	city_positions: Array[Vector2],
	map_aspect_ratio: float,
	map_path: PackedVector2Array = PackedVector2Array()
) -> Dictionary:
	var segment := base.duplicate(true)
	segment["a"] = from_city
	segment["b"] = to_city
	if map_path.size() >= 2:
		map_path[0] = city_positions[from_city]
		map_path[-1] = city_positions[to_city]
		segment["map_path"] = map_path
		segment["length"] = metric_polyline_length(
			map_path, map_aspect_ratio
		)
	else:
		segment.erase("map_path")
		segment["length"] = metric_length_between(
			city_positions[from_city],
			city_positions[to_city],
			map_aspect_ratio
		)
	segment["distance"] = distance_units_for_metric_length(
		float(segment["length"])
	)
	segment["danger"] = maxf(
		float(base["danger"]),
		LANDING_DANGER_MIN
	)
	segment["kind"] = Edge.Kind.LANDING
	segment["travel_time_multiplier"] = 1.0
	segment["supply_loss_multiplier"] = 1.0
	segment["allows_holding"] = true
	return segment


static func _build_river_avoiding_landing_grid(
	land_mask: PackedByteArray,
	size: Vector2i,
	river_paths: Array[Array]
) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in range(size.y):
		for x in range(size.x):
			if land_mask[y * size.x + x] == 0:
				grid.set_point_solid(Vector2i(x, y), true)
	for path in river_paths:
		for point in path:
			grid.set_point_solid(point, true)
	return grid


static func _landing_path_avoiding_rivers(
	grid: AStarGrid2D,
	bounds: Rect2i,
	from: Vector2,
	to: Vector2
) -> PackedVector2Array:
	var start := _normalized_to_analysis_pixel(from, bounds)
	var goal := _normalized_to_analysis_pixel(to, bounds)
	var start_was_solid := grid.is_point_solid(start)
	var goal_was_solid := grid.is_point_solid(goal)
	grid.set_point_solid(start, false)
	grid.set_point_solid(goal, false)
	var raw: Array[Vector2i] = []
	raw.assign(grid.get_id_path(start, goal))
	grid.set_point_solid(start, start_was_solid)
	grid.set_point_solid(goal, goal_was_solid)
	assert(not raw.is_empty(), "A/B两岸必须能分别寻路到强制渡口")
	var result := PackedVector2Array([from])
	for index in range(1, raw.size() - 1):
		var direction := raw[index] - raw[index - 1]
		var next_direction := raw[index + 1] - raw[index]
		if direction != next_direction:
			result.append(_normalized_map_point(Vector2(raw[index]), bounds))
	result.append(to)
	return result


static func _normalized_to_analysis_pixel(
	position: Vector2, bounds: Rect2i
) -> Vector2i:
	return Vector2i(
		clampi(
			int(round(position.x * float(bounds.size.x) + bounds.position.x - 0.5)),
			bounds.position.x, bounds.end.x - 1
		),
		clampi(
			int(round(position.y * float(bounds.size.y) + bounds.position.y - 0.5)),
			bounds.position.y, bounds.end.y - 1
		)
	)


static func distance_units_for_metric_length(metric_length: float) -> int:
	return maxi(
		int(round(
			maxf(metric_length, 0.0)
				* EDGE_DISTANCE_UNITS_PER_MAP_HEIGHT
		)),
		1
	)


static func metric_length_between(
	from_position: Vector2,
	to_position: Vector2,
	map_aspect_ratio: float
) -> float:
	var delta := to_position - from_position
	delta.x *= map_aspect_ratio
	return delta.length()


static func river_crossing_positions(
	from_position: Vector2,
	to_position: Vector2,
	paths: Array[PackedVector2Array]
) -> PackedVector2Array:
	var road_delta := to_position - from_position
	var road_length_sq := road_delta.length_squared()
	var crossings: Array[Dictionary] = []
	if road_length_sq <= 0.000001:
		return PackedVector2Array()
	for path in paths:
		for path_index in range(path.size() - 1):
			var hit = Geometry2D.segment_intersects_segment(
				from_position, to_position,
				path[path_index], path[path_index + 1]
			)
			if hit == null:
				continue
			var road_t := (
				(Vector2(hit) - from_position).dot(road_delta)
				/ road_length_sq
			)
			if (
				road_t > RIVER_CROSSING_ENDPOINT_EPS
				and road_t < 1.0 - RIVER_CROSSING_ENDPOINT_EPS
			):
				var duplicate := false
				for existing in crossings:
					if absf(float(existing["t"]) - road_t) <= 0.0001:
						duplicate = true
						break
				if not duplicate:
					crossings.append({"t": road_t, "position": Vector2(hit)})
	crossings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["t"]) < float(b["t"])
	)
	var result := PackedVector2Array()
	for crossing in crossings:
		result.append(crossing["position"])
	return result


static func altitude_at_map_position(
	source_path: String, map_position: Vector2
) -> float:
	var texture := load(source_path) as Texture2D
	if texture == null:
		return 0.0
	var image := texture.get_image()
	if image == null or image.is_empty():
		return 0.0
	var x := clampi(int(floor(clampf(map_position.x, 0.0, 1.0) * image.get_width())), 0, image.get_width() - 1)
	var y := clampi(int(floor(clampf(map_position.y, 0.0, 1.0) * image.get_height())), 0, image.get_height() - 1)
	return packed_altitude(image.get_pixel(x, y))


static func _river_link_danger(
	image: Image,
	path: Array[Vector2i],
	from_progress: float,
	to_progress: float
) -> float:
	var first := clampi(
		int(floor(from_progress)),
		0,
		path.size() - 1
	)
	var last := clampi(
		int(ceil(to_progress)),
		first + 1,
		path.size() - 1
	)
	var slope_total := 0.0
	var turn_total := 0.0
	var samples := 0
	for index in range(first, last):
		var a := path[index]
		var b := path[index + 1]
		slope_total += absf(
			packed_altitude(image.get_pixel(a.x, a.y))
			- packed_altitude(image.get_pixel(b.x, b.y))
		)
		if index + 2 <= last:
			var first_direction := Vector2(
				path[index + 1] - path[index]
			).normalized()
			var second_direction := Vector2(
				path[index + 2] - path[index + 1]
			).normalized()
			turn_total += (
				1.0
				- clampf(
					first_direction.dot(second_direction),
					-1.0,
					1.0
				)
			)
		samples += 1
	return clampf(
		0.12
			+ slope_total / float(maxi(samples, 1)) * 10.0
			+ turn_total / float(maxi(samples, 1)) * 0.18,
		0.12,
		0.60
	)


static func _normalized_river_path(
	path: Array[Vector2i],
	bounds: Rect2i
) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in path:
		result.append(_normalized_map_point(point, bounds))
	return result


static func _normalized_map_point(
	point: Vector2,
	bounds: Rect2i
) -> Vector2:
	return Vector2(
		(point.x - float(bounds.position.x) + 0.5)
			/ float(maxi(bounds.size.x, 1)),
		(point.y - float(bounds.position.y) + 0.5)
			/ float(maxi(bounds.size.y, 1))
	)


static func _segment_fraction(
	point: Vector2,
	from: Vector2,
	to: Vector2
) -> float:
	var delta := to - from
	if delta.length_squared() <= 0.000001:
		return 0.0
	return clampf(
		(point - from).dot(delta) / delta.length_squared(),
		0.0,
		1.0
	)


static func _pixel_relief(
	image: Image,
	x: int,
	y: int
) -> float:
	var center := packed_altitude(image.get_pixel(x, y))
	var result := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var px := clampi(x + ox, 0, image.get_width() - 1)
			var py := clampi(y + oy, 0, image.get_height() - 1)
			result = maxf(
				result,
				absf(
					center
					- packed_altitude(image.get_pixel(px, py))
				)
			)
	return result


static func _edge_profile(
	image: Image,
	mask: PackedByteArray,
	from: Vector2i,
	to: Vector2i
) -> Dictionary:
	var minimum := 1.0
	var maximum := 0.0
	var land_samples := 0
	for i in range(ROAD_SAMPLE_COUNT + 1):
		var t := float(i) / float(ROAD_SAMPLE_COUNT)
		var point := Vector2(from).lerp(Vector2(to), t)
		var x := clampi(int(round(point.x)), 0, image.get_width() - 1)
		var y := clampi(int(round(point.y)), 0, image.get_height() - 1)
		var height := packed_altitude(image.get_pixel(x, y))
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		if mask[y * image.get_width() + x] != 0:
			land_samples += 1
	return {
		"height_difference": maximum - minimum,
		"land_ratio": float(land_samples) / float(ROAD_SAMPLE_COUNT + 1),
	}


static func _pair_key(a: int, b: int) -> int:
	return mini(a, b) * 10000 + maxi(a, b)


static func _root(parent: Array[int], node: int) -> int:
	var current := node
	while parent[current] != current:
		parent[current] = parent[parent[current]]
		current = parent[current]
	return current
