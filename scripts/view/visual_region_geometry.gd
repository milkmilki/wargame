class_name VisualRegionGeometry
extends RefCounted
## Converts the visual city-id field into closed, cached region geometry.

const DEFAULT_SIZE := Vector2i(2048, 2048)
const WORK_SIZE := Vector2i(512, 512)
const DISTANCE_RADIUS_PX := 4.0
const VORONOI := preload("res://scripts/view/visual_weighted_voronoi.gd")


static func build_visual_region_geometry(
		height_image: Image,
		city_seeds: Array[Dictionary],
		size: Vector2i = DEFAULT_SIZE
	) -> Dictionary:
	var safe_size := Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	var coarse := VORONOI.build_visual_city_ids(
		height_image, city_seeds, WORK_SIZE, 32.0, WORK_SIZE
	)
	return from_labels(height_image, city_seeds, safe_size, coarse, WORK_SIZE)


static func from_labels(height_image: Image, city_seeds: Array[Dictionary], safe_size: Vector2i, coarse: Dictionary, work_size: Vector2i) -> Dictionary:
	var coarse_ids: Image = coarse["city_ids"]
	var coarse_land: Image = coarse["land_mask"]
	var by_city := {}
	var adjacency := {}
	for seed_value in city_seeds:
		var seed := seed_value as Dictionary
		var city_id := int(seed.get("city_id", -1))
		if city_id >= 0:
			by_city[city_id] = []
			adjacency[city_id] = {}
	for y in range(work_size.y):
		for x in range(work_size.x):
			var city_id := _pixel_id(coarse_ids, x, y)
			if city_id < 0 or not by_city.has(city_id):
				continue
			for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var nx: int = x + direction.x
				var ny: int = y + direction.y
				var neighbor := -1
				if nx >= 0 and ny >= 0 and nx < work_size.x and ny < work_size.y:
					neighbor = _pixel_id(coarse_ids, nx, ny)
				if neighbor == city_id:
					continue
				if neighbor >= 0 and adjacency.has(city_id):
					adjacency[city_id][neighbor] = true
				var a := Vector2(x, y)
				var b := Vector2(x + 1, y)
				if direction == Vector2i.RIGHT:
					a = Vector2(x + 1, y)
					b = Vector2(x + 1, y + 1)
				elif direction == Vector2i.DOWN:
					a = Vector2(x + 1, y + 1)
					b = Vector2(x, y + 1)
				elif direction == Vector2i.LEFT:
					a = Vector2(x, y + 1)
					b = Vector2(x, y)
				# The orientation is only used to connect the edge graph; each
				# region receives its own copy of a shared administrative edge.
				(by_city[city_id] as Array).append([
					Vector2(a.x / work_size.x, a.y / work_size.y),
					Vector2(b.x / work_size.x, b.y / work_size.y),
					neighbor < 0,
				])
	var shared_vertices := _shared_boundary_vertices(by_city)
	var regions: Array[Dictionary] = []
	for city_id_value in by_city.keys():
		var city_id := int(city_id_value)
		var chains := _connect_segments(by_city[city_id] as Array)
		for chain_value in chains:
			var polygon := chain_value["points"] as PackedVector2Array
			if polygon.size() < 3:
				continue
			var smoothed := smooth_visual_boundary(polygon, {
				"max_offset": 2.0 / float(work_size.x),
				"shared_vertices": shared_vertices,
			})
			var region := {
				"city_id": city_id,
				"polygon": smoothed,
				"is_hole": false,
				"coastline": bool(chain_value.get("coastline", false)),
				"neighbors": PackedInt32Array(adjacency[city_id].keys()),
			}
			if validate_visual_region(region, coarse_land, adjacency):
				regions.append(region)
	var raster := rasterize_regions(regions, safe_size, coarse_land, height_image)
	raster["regions"] = regions
	raster["adjacency"] = adjacency
	raster["revision"] = hash([
			safe_size, regions, coarse["revision"],
	])
	return raster


static func _shared_boundary_vertices(by_city: Dictionary) -> Dictionary:
	var vertices := {}
	for segments in by_city.values():
		for segment in segments:
			for endpoint in range(2):
				var point: Vector2 = segment[endpoint]
				var neighbor: Vector2 = segment[1 - endpoint]
				var key := _point_key(point)
				if not vertices.has(key):
					vertices[key] = {"point": point, "neighbors": {}, "coast": false}
				vertices[key]["neighbors"][_point_key(neighbor)] = neighbor
				vertices[key]["coast"] = vertices[key]["coast"] or bool(segment[2])
	var result := {}
	for key in vertices:
		var vertex: Dictionary = vertices[key]
		var point: Vector2 = vertex["point"]
		var neighbors: Array = vertex["neighbors"].values()
		# Pin junctions and coastline. Shared degree-two edges move once, so
		# both polygons and the river graph consume exactly the same vertices.
		if neighbors.size() == 2 and not vertex["coast"]:
			point = (neighbors[0] + point * 2.0 + neighbors[1]) * 0.25
		result[key] = point
	return result


static func validate_visual_region(
	region: Dictionary, land_mask: Image, adjacency: Dictionary
	) -> bool:
	var polygon := region.get("polygon", PackedVector2Array()) as PackedVector2Array
	if polygon.size() < 3 or int(region.get("city_id", -1)) < 0:
		return false
	for point in polygon:
		if point.x < -0.001 or point.x > 1.001 or point.y < -0.001 or point.y > 1.001:
			return false
	for index in range(polygon.size()):
		if polygon[index].distance_squared_to(
			polygon[(index + 1) % polygon.size()]
		) < 0.00000001:
			return false
	return _polygon_area(polygon) > 0.00000001


static func smooth_visual_boundary(
	polygon: PackedVector2Array, constraints: Dictionary
	) -> PackedVector2Array:
	if polygon.size() < 4:
		return polygon.duplicate()
	var max_offset := float(constraints.get("max_offset", 0.0))
	var result := PackedVector2Array()
	var shared: Dictionary = constraints.get("shared_vertices", {})
	for index in range(polygon.size()):
		var previous := polygon[(index - 1 + polygon.size()) % polygon.size()]
		var current := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		var target := (previous + current * 2.0 + next) * 0.25
		if shared.has(_point_key(current)):
			target = shared[_point_key(current)]
		if max_offset > 0.0:
			var delta := target - current
			if delta.length() > max_offset:
				target = current + delta.normalized() * max_offset
		result.append(target)
	return result


static func rasterize_regions(
	regions: Array[Dictionary], size: Vector2i, coarse_land: Image,
	height_image: Image
	) -> Dictionary:
	var ids := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	ids.fill(Color(-1.0, 0.0, 0.0, 1.0))
	var land := _build_land_mask(height_image, size)
	var coverage := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	var edge := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	for region_value in regions:
		var region := region_value as Dictionary
		var polygon := region["polygon"] as PackedVector2Array
		var city_id := float(region["city_id"])
		for y in range(size.y):
			var scan_y := (float(y) + 0.5) / size.y
			var intersections := PackedFloat32Array()
			for index in range(polygon.size()):
				var a := polygon[index]
				var b := polygon[(index + 1) % polygon.size()]
				if (a.y <= scan_y and b.y > scan_y) or (b.y <= scan_y and a.y > scan_y):
					intersections.append(a.x + (scan_y - a.y) * (b.x - a.x) / (b.y - a.y))
			intersections.sort()
			for pair in range(0, intersections.size() - 1, 2):
				var x0 := clampi(int(ceil(intersections[pair] * size.x - 0.5)), 0, size.x - 1)
				var x1 := clampi(int(floor(intersections[pair + 1] * size.x - 0.5)), 0, size.x - 1)
				for x in range(x0, x1 + 1):
					if land.get_pixel(x, y).r < 0.5:
						continue
					ids.set_pixel(x, y, Color(city_id, 0.0, 0.0, 1.0))
					coverage.set_pixel(x, y, Color.WHITE)
	_fill_region_edges(ids, edge)
	var distance := _build_distance_channel(ids, land, edge)
	return {
		"city_id": ids,
		"land_mask": land,
		"region_coverage": coverage,
		"region_distance": distance,
		"region_edge": edge,
	}


static func _fill_region_edges(ids: Image, edge: Image) -> void:
	var width := ids.get_width()
	var height := ids.get_height()
	var labels := ids.get_data().to_float32_array()
	var values := PackedFloat32Array()
	values.resize(width * height)
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			var city_id := labels[index]
			if city_id < 0.0:
				continue
			if (
				(x > 0 and labels[index - 1] != city_id)
				or (x + 1 < width and labels[index + 1] != city_id)
				or (y > 0 and labels[index - width] != city_id)
				or (y + 1 < height and labels[index + width] != city_id)
			):
				values[index] = 1.0
	edge.set_data(width, height, false, Image.FORMAT_RF, values.to_byte_array())


static func _build_distance_channel(
	ids: Image, land: Image, edge: Image
) -> Image:
	var width := ids.get_width()
	var height := ids.get_height()
	var distances := PackedInt32Array()
	distances.resize(width * height)
	const INF := 1_000_000_000
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if land.get_pixel(x, y).r < 0.5:
				distances[index] = -1
			elif edge.get_pixel(x, y).r > 0.5:
				distances[index] = 0
			else:
				distances[index] = INF
	# Two passes approximate boundary distance on the four-neighbor grid.
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if distances[index] < 0:
				continue
			var best := distances[index]
			if x > 0 and distances[index - 1] >= 0:
				best = mini(best, distances[index - 1] + 1)
			if y > 0 and distances[index - width] >= 0:
				best = mini(best, distances[index - width] + 1)
			distances[index] = best
	for y in range(height - 1, -1, -1):
		for x in range(width - 1, -1, -1):
			var index := y * width + x
			if distances[index] < 0:
				continue
			var best := distances[index]
			if x + 1 < width and distances[index + 1] >= 0:
				best = mini(best, distances[index + 1] + 1)
			if y + 1 < height and distances[index + width] >= 0:
				best = mini(best, distances[index + width] + 1)
			distances[index] = best
	var result := Image.create(width, height, false, Image.FORMAT_RF)
	for y in range(height):
		for x in range(width):
			var value := distances[y * width + x]
			result.set_pixel(
				x, y,
				Color(
					-1.0 if value < 0 else clampf(
						float(value) / DISTANCE_RADIUS_PX, 0.0, 1.0
					),
					0.0, 0.0, 1.0
				)
			)
	return result



static func _connect_segments(segments: Array) -> Array[Dictionary]:
	var by_start := {}
	for index in range(segments.size()):
		var segment = segments[index]
		var key := _point_key(segment[0] as Vector2)
		if not by_start.has(key):
			by_start[key] = []
		(by_start[key] as Array).append(index)
	var result: Array[Dictionary] = []
	var used := {}
	for index in range(segments.size()):
		if used.has(index):
			continue
		var first: Array = segments[index]
		var points := PackedVector2Array([first[0], first[1]])
		var coastline := bool(first[2])
		used[index] = true
		var guard := 0
		while guard < segments.size():
			guard += 1
			var key := _point_key(points[-1])
			var next_index := -1
			for candidate_index in by_start.get(key, []):
				if not used.has(candidate_index):
					next_index = candidate_index
					break
			if next_index < 0:
				break
			var next_segment = segments[next_index]
			used[next_index] = true
			points.append(next_segment[1])
			coastline = coastline or bool(next_segment[2])
			if _point_key(points[-1]) == _point_key(points[0]):
				break
		if points.size() >= 3 and _point_key(points[-1]) == _point_key(points[0]):
			points.resize(points.size() - 1)
			result.append({"points": points, "coastline": coastline})
	return result


static func _point_key(point: Vector2) -> String:
	return "%d:%d" % [roundi(point.x * WORK_SIZE.x), roundi(point.y * WORK_SIZE.y)]


static func _pixel_id(image: Image, x: int, y: int) -> int:
	return int(round(image.get_pixel(x, y).r))


static func _build_land_mask(image: Image, size: Vector2i) -> Image:
	if image == null or image.is_empty():
		var all_land := Image.create(size.x, size.y, false, Image.FORMAT_L8)
		all_land.fill(Color.WHITE)
		return all_land
	var source := image
	if source.get_size() != size:
		source = source.duplicate()
		source.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	if source.get_format() == Image.FORMAT_RGBA8:
		var data := source.get_data()
		var alpha := PackedByteArray()
		alpha.resize(size.x * size.y)
		for index in range(alpha.size()):
			alpha[index] = 255 if data[index * 4 + 3] > 128 else 0
		return Image.create_from_data(
			size.x, size.y, false, Image.FORMAT_L8, alpha
		)
	var fallback := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	for y in range(size.y):
		for x in range(size.x):
			if TerrainMapGenerator.packed_is_land(source.get_pixel(x, y)):
				fallback.set_pixel(x, y, Color.WHITE)
	return fallback


static func _polygon_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
