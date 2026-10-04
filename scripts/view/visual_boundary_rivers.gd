extends RefCounted
## Visual-only routes on the shared polygon edge graph. Never edits river features.

const GUIDE_SIZE := 128
const MAX_ENDPOINT_DISTANCE_UV := 0.125


static func build_paths(
	regions: Array, features: Array, size: Vector2i, land: Image = null
) -> Dictionary:
	var graph := _build_graph(regions, land)
	var components := _connected_components(graph)
	var paths := {}
	var missing := PackedInt32Array()
	for value in features:
		var feature := value as Dictionary
		var river_id := int(feature.get("id", -1))
		var source: PackedVector2Array = feature.get("points", PackedVector2Array())
		# Imported/hydrological rivers are not defined by administrative boundaries.
		if feature.get("source_kind", "") != MapFeatureContract.SOURCE_GENERATED_BOUNDARY:
			paths[river_id] = MapFeatureContract.build_high_precision_river_path(feature, size)
			continue
		var path := _route(graph, source, size, components)
		paths[river_id] = path
		if path.size() < 2:
			missing.append(river_id)
	return {"paths": paths, "missing_river_ids": missing}


static func _build_graph(regions: Array, land: Image) -> AStar2D:
	var segments := {}
	for value in regions:
		var region := value as Dictionary
		var polygon: PackedVector2Array = region.get("polygon", PackedVector2Array())
		var city_id := int(region.get("city_id", -1))
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			var ka := _key(a)
			var kb := _key(b)
			if ka == kb:
				continue
			var key := ka + "/" + kb if ka < kb else kb + "/" + ka
			if not segments.has(key):
				segments[key] = {"a": a, "b": b, "owners": {}}
			segments[key]["owners"][city_id] = true
	var graph := AStar2D.new()
	var nodes := {}
	for segment in segments.values():
		# One owner is a coastline/outer edge, not an administrative river bed.
		if segment["owners"].size() != 2:
			continue
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		if not _segment_is_land(a, b, land):
			continue
		var endpoints := PackedInt64Array()
		for point in [a, b]:
			var key := _key(point)
			if not nodes.has(key):
				var id := nodes.size()
				nodes[key] = id
				graph.add_point(id, point)
			endpoints.append(nodes[key])
		graph.connect_points(endpoints[0], endpoints[1])
	return graph


static func _route(
	graph: AStar2D, source: PackedVector2Array, size: Vector2i, components: Array = []
) -> PackedVector2Array:
	if source.size() < 2 or graph.get_point_count() < 2:
		return PackedVector2Array()
	var scale := Vector2(size)
	var endpoint_limit_squared := pow(MAX_ENDPOINT_DISTANCE_UV * maxi(size.x, size.y), 2.0)
	if components.is_empty():
		components = _connected_components(graph)
	var start := -1
	var finish := -1
	var best_error := INF
	# Select endpoints together. The individually nearest coastal vertex can
	# be an isolated fragment even when a connected mouth lies a few pixels away.
	for component in components:
		var from_id := -1
		var to_id := -1
		var from_error := INF
		var to_error := INF
		for id in component:
			var point := graph.get_point_position(id)
			var a := ((point - source[0]) * scale).length_squared()
			var b := ((point - source[-1]) * scale).length_squared()
			if a < from_error:
				from_error = a
				from_id = id
			if b < to_error:
				to_error = b
				to_id = id
		if from_id == to_id or maxf(from_error, to_error) > endpoint_limit_squared:
			continue
		if from_error + to_error < best_error:
			best_error = from_error + to_error
			start = from_id
			finish = to_id
	if start < 0 or finish < 0:
		return PackedVector2Array()
	var guide := _guide_distances(source)
	for id in graph.get_point_ids():
		var point := graph.get_point_position(id)
		var x := clampi(int(point.x * GUIDE_SIZE), 0, GUIDE_SIZE - 1)
		var y := clampi(int(point.y * GUIDE_SIZE), 0, GUIDE_SIZE - 1)
		var distance := float(guide[y * GUIDE_SIZE + x])
		graph.set_point_weight_scale(id, 1.0 + distance * distance)
	# Graph edges are the polygon segments: do not independently smooth or
	# resample with Catmull-Rom, which would take the river off the boundary.
	return graph.get_point_path(start, finish)


static func _connected_components(graph: AStar2D) -> Array:
	var result := []
	var visited := {}
	for id in graph.get_point_ids():
		if visited.has(id):
			continue
		var component := PackedInt64Array([id])
		visited[id] = true
		var cursor := 0
		while cursor < component.size():
			var current := component[cursor]
			cursor += 1
			for next in graph.get_point_connections(current):
				if not visited.has(next):
					visited[next] = true
					component.append(next)
		result.append(component)
	return result


static func _guide_distances(source: PackedVector2Array) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(GUIDE_SIZE * GUIDE_SIZE)
	distances.fill(GUIDE_SIZE * 2)
	for index in range(source.size() - 1):
		var a := source[index] * GUIDE_SIZE
		var b := source[index + 1] * GUIDE_SIZE
		var steps := maxi(int(ceil(a.distance_to(b))), 1)
		for step in range(steps + 1):
			var point := a.lerp(b, float(step) / steps)
			var x := clampi(int(point.x), 0, GUIDE_SIZE - 1)
			var y := clampi(int(point.y), 0, GUIDE_SIZE - 1)
			distances[y * GUIDE_SIZE + x] = 0
	for y in range(GUIDE_SIZE):
		for x in range(GUIDE_SIZE):
			var index := y * GUIDE_SIZE + x
			if x > 0:
				distances[index] = mini(distances[index], distances[index - 1] + 1)
			if y > 0:
				distances[index] = mini(distances[index], distances[index - GUIDE_SIZE] + 1)
	for y in range(GUIDE_SIZE - 1, -1, -1):
		for x in range(GUIDE_SIZE - 1, -1, -1):
			var index := y * GUIDE_SIZE + x
			if x + 1 < GUIDE_SIZE:
				distances[index] = mini(distances[index], distances[index + 1] + 1)
			if y + 1 < GUIDE_SIZE:
				distances[index] = mini(distances[index], distances[index + GUIDE_SIZE] + 1)
	return distances


static func _key(point: Vector2) -> String:
	return "%d:%d" % [roundi(point.x * 1000000.0), roundi(point.y * 1000000.0)]


static func _segment_is_land(a: Vector2, b: Vector2, land: Image) -> bool:
	if land == null:
		return true
	var size := land.get_size()
	var steps := maxi(int(ceil(((b - a) * Vector2(size)).length())), 1)
	for step in range(steps + 1):
		var uv := a.lerp(b, float(step) / steps)
		var x := clampi(int(uv.x * size.x), 0, size.x - 1)
		var y := clampi(int(uv.y * size.y), 0, size.y - 1)
		if land.get_pixel(x, y).r < 0.5:
			return false
	return true
