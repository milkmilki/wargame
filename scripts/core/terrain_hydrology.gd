class_name TerrainHydrology
extends RefCounted
## Single-receiver drainage on province-grid vertices. Rivers occupy grid edges,
## so their authoritative geometry also defines province barriers without snapping.
const VERSION := "hydrology_v1.2"
const MINOR_FLOW := 32.0
## Initial 512 produced no major Eurasian reaches on the coarse packed DEM.
## Calibrate flow units, not the wet/dry distribution or transport acceptance.
const MAJOR_FLOW := 128.0
const MAX_PIT_RISE := 1.0 / 127.0
const MAX_PIT_AREA := 4
const STEPS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
static var _cache: Dictionary = {}

## Sample valley floors separately from climate/city terrain. A single nearest
## pixel can place an artificial dam across a narrow gorge during downsampling.
## This changes the drainage surface only, never the displayed elevation.
static func drainage_heights(source: Image, size: Vector2i) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(size.x * size.y)
	var scale := Vector2(source.get_size()) / Vector2(size)
	for y in range(size.y):
		for x in range(size.x):
			var low := 1.0
			for sy in range(8):
				for sx in range(8):
					var p := Vector2i((Vector2(x, y) + (Vector2(sx, sy) + Vector2.ONE * 0.5) / 8.0) * scale)
					p = p.clamp(Vector2i.ZERO, source.get_size() - Vector2i.ONE)
					low = minf(low, maxf((source.get_pixelv(p).a * 255.0 - 128.0) / 127.0, 0.0))
			result[y * size.x + x] = low
	return result

static func build(environment: Dictionary, aspect: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var key := str(environment.environment_id) + ":" + VERSION
	if _cache.has(key):
		var cached: Dictionary = _cache[key].duplicate()
		cached.cache_hit = true
		cached.elapsed_usec = Time.get_ticks_usec() - started
		return cached
	var cells: Vector2i = environment.size
	var size := cells + Vector2i.ONE
	var heights := PackedFloat32Array()
	var local := PackedFloat32Array()
	var sea := PackedByteArray()
	heights.resize(size.x * size.y)
	local.resize(heights.size())
	sea.resize(heights.size())
	var area_scale := aspect * 65536.0 / float(cells.x * cells.y)
	var drainage: PackedFloat32Array = environment.get("drainage_heights", environment.heights)
	for y in range(size.y):
		for x in range(size.x):
			var i := y * size.x + x
			var count := 0
			var lowest := INF
			var touches_sea := false
			for dy in [-1, 0]:
				for dx in [-1, 0]:
					var p := Vector2i(x + dx, y + dy)
					if not Rect2i(Vector2i.ZERO, cells).has_point(p): continue
					var c: int = p.y * cells.x + p.x
					touches_sea = touches_sea or environment.land[c] == 0
					lowest = minf(lowest, drainage[c])
					count += 1
					if environment.land[c] != 0:
						local[i] += environment.local_runoff[c] * area_scale * 0.25
			sea[i] = int(touches_sea)
			# The corner is a passage between its adjacent terrain cells. An
			# arithmetic mean seals low valleys with the neighboring mountain.
			heights[i] = lowest if count > 0 else 0.0
	var result := solve(heights, sea, local, size, aspect)
	result.hydrology_id = key.sha256_text()
	result.cache_hit = false
	result.elapsed_usec = Time.get_ticks_usec() - started
	if _cache.size() >= 8: _cache.erase(_cache.keys()[0])
	_cache[key] = result
	return result.duplicate()

static func solve(heights: PackedFloat32Array, sea: PackedByteArray, local: PackedFloat32Array, size: Vector2i, aspect: float) -> Dictionary:
	var count := heights.size()
	assert(count == size.x * size.y and sea.size() == count and local.size() == count)
	var routing := _condition(heights, sea, size)
	var downstream := PackedInt32Array()
	var rank := PackedInt32Array()
	downstream.resize(count)
	downstream.fill(-1)
	rank.resize(count)
	rank.fill(-1)
	var kinds: Array[String] = []
	kinds.resize(count)
	var queue := PackedInt32Array()
	var dx := aspect / float(size.x - 1)
	var dy := 1.0 / float(size.y - 1)
	for i in range(count):
		var p := Vector2i(i % size.x, i / size.x)
		if sea[i] != 0:
			kinds[i] = "sea"
			rank[i] = 0
			queue.append(i)
			continue
		var best := 0.0
		for step in STEPS:
			var q: Vector2i = p + step
			if not Rect2i(Vector2i.ZERO, size).has_point(q): continue
			var j: int = q.y * size.x + q.x
			var target := -1.0 if sea[j] != 0 else routing[j]
			var slope := (routing[i] - target) / (dx if step.x != 0 else dy)
			if slope > best:
				best = slope
				downstream[i] = j
		if downstream[i] >= 0:
			rank[i] = 0
			queue.append(i)
		elif p.x == 0 or p.y == 0 or p.x == size.x - 1 or p.y == size.y - 1:
			kinds[i] = "crop"
			rank[i] = 0
			queue.append(i)
	_route_flats(queue, downstream, rank, routing, sea, size)
	var basin_count := 0
	for i in range(count):
		if rank[i] >= 0: continue
		# A closed flat has one deterministic sink; all its water is retained.
		kinds[i] = "basin"
		rank[i] = 0
		_route_flats(PackedInt32Array([i]), downstream, rank, routing, sea, size)
		basin_count += 1
	var order: Array[int] = []
	for i in range(count): order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if sea[a] != sea[b]: return sea[a] < sea[b]
		if routing[a] != routing[b]: return routing[a] > routing[b]
		if rank[a] != rank[b]: return rank[a] > rank[b]
		return a < b)
	var flow := local.duplicate()
	for i in order:
		if downstream[i] >= 0: flow[downstream[i]] += flow[i]
	var result := _network(downstream, flow, kinds, size)
	result.merge({"size": size, "heights": heights, "routing_heights": routing, "downstream": downstream, "flow": flow, "local_runoff": local, "terminal_kind": kinds, "basin_count": basin_count, "version": VERSION})
	return result

static func _route_flats(queue: PackedInt32Array, downstream: PackedInt32Array, rank: PackedInt32Array, heights: PackedFloat32Array, sea: PackedByteArray, size: Vector2i) -> void:
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var p := Vector2i(i % size.x, i / size.x)
		for step in STEPS:
			var q: Vector2i = p + step
			if not Rect2i(Vector2i.ZERO, size).has_point(q): continue
			var j: int = q.y * size.x + q.x
			if rank[j] < 0 and sea[j] == 0 and heights[j] == heights[i]:
				downstream[j] = i
				rank[j] = rank[i] + 1
				queue.append(j)

## Priority flood discovers spill levels; only tiny, shallow components are filled.
## Larger depressions retain their original heights and become inland terminals.
static func _condition(heights: PackedFloat32Array, sea: PackedByteArray, size: Vector2i) -> PackedFloat32Array:
	var filled := heights.duplicate()
	var seen := PackedByteArray()
	seen.resize(heights.size())
	var heap: Array = []
	for i in range(heights.size()):
		var x := i % size.x
		var y := i / size.x
		if sea[i] != 0 or x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
			seen[i] = 1
			_push(heap, Vector2(heights[i], i))
	while not heap.is_empty():
		var entry := _pop(heap)
		var i := int(entry.y)
		var p := Vector2i(i % size.x, i / size.x)
		for step in STEPS:
			var q: Vector2i = p + step
			if not Rect2i(Vector2i.ZERO, size).has_point(q): continue
			var j: int = q.y * size.x + q.x
			if seen[j] != 0: continue
			seen[j] = 1
			filled[j] = maxf(heights[j], entry.x)
			_push(heap, Vector2(filled[j], j))
	seen.fill(0)
	var result := heights.duplicate()
	for i in range(heights.size()):
		if seen[i] != 0 or filled[i] <= heights[i] + 0.0000001: continue
		var group := PackedInt32Array([i])
		seen[i] = 1
		var rise := 0.0
		var head := 0
		while head < group.size():
			var j := group[head]
			head += 1
			rise = maxf(rise, filled[j] - heights[j])
			var p := Vector2i(j % size.x, j / size.x)
			for step in STEPS:
				var q: Vector2i = p + step
				if not Rect2i(Vector2i.ZERO, size).has_point(q): continue
				var k: int = q.y * size.x + q.x
				if seen[k] == 0 and filled[k] > heights[k] + 0.0000001:
					seen[k] = 1
					group.append(k)
		if group.size() <= MAX_PIT_AREA and rise <= MAX_PIT_RISE + 0.0000001:
			for j in group: result[j] = filled[j]
	return result

static func _network(downstream: PackedInt32Array, flow: PackedFloat32Array, kinds: Array[String], size: Vector2i) -> Dictionary:
	var upstream := PackedInt32Array()
	upstream.resize(flow.size())
	var classes := PackedByteArray()
	classes.resize(flow.size())
	for i in range(flow.size()):
		if downstream[i] >= 0 and flow[i] >= MINOR_FLOW:
			classes[i] = 2 if flow[i] >= MAJOR_FLOW else 1
			upstream[downstream[i]] += 1
	var starts := PackedByteArray()
	starts.resize(flow.size())
	for i in range(flow.size()):
		if classes[i] == 0: continue
		if upstream[i] != 1: starts[i] = 1
		var j := downstream[i]
		if classes[j] != 0 and classes[i] != classes[j]: starts[j] = 1
	var features: Array[Dictionary] = []
	var start_to_id := {}
	var end_nodes: Array[int] = []
	var blocked := {}
	for i in range(flow.size()):
		if starts[i] == 0: continue
		var points := PackedVector2Array()
		var node := i
		points.append(_uv(node, size))
		while downstream[node] >= 0:
			var target := downstream[node]
			if classes[i] == 2: _block_between_vertices(blocked, node, target, size)
			node = target
			points.append(_uv(node, size))
			if starts[node] != 0 or classes[node] == 0: break
		var id := features.size()
		start_to_id[i] = id
		end_nodes.append(node)
		var width := 0.25 if classes[i] == 1 else 0.72
		features.append({"schema_version": 2, "feature_kind": "river", "id": id, "source_kind": "procedural_hydrology", "flow_direction": "points_downstream", "river_class": "major" if classes[i] == 2 else "minor", "terminal_kind": kinds[node] if downstream[node] < 0 else "junction", "points": points, "source_width": width, "mouth_width": width * minf(1.6, sqrt(flow[node] / maxf(flow[i], 0.001))), "downstream_id": -1, "upstream_ids": PackedInt32Array()})
	for id in range(features.size()):
		var next := int(start_to_id.get(end_nodes[id], -1))
		features[id].downstream_id = next
		if next >= 0:
			var ids: PackedInt32Array = features[next].upstream_ids
			ids.append(id)
			features[next].upstream_ids = ids
	return {"features": features, "blocked_edges": blocked}

static func _uv(node: int, size: Vector2i) -> Vector2:
	return Vector2(node % size.x, node / size.x) / Vector2(size - Vector2i.ONE)

static func edge_key(a: int, b: int, count: int) -> int:
	return mini(a, b) * count + maxi(a, b)

static func components(land: PackedByteArray, size: Vector2i, blocked: Dictionary) -> PackedInt32Array:
	var ids := PackedInt32Array()
	ids.resize(land.size())
	ids.fill(-1)
	var next_id := 0
	for i in range(ids.size()):
		if land[i] == 0 or ids[i] >= 0: continue
		var queue := PackedInt32Array([i])
		ids[i] = next_id
		var head := 0
		while head < queue.size():
			var j := queue[head]
			head += 1
			var p := Vector2i(j % size.x, j / size.x)
			for step in STEPS:
				var q: Vector2i = p + step
				if not Rect2i(Vector2i.ZERO, size).has_point(q): continue
				var k: int = q.y * size.x + q.x
				if land[k] == 0 or ids[k] >= 0 or blocked.has(edge_key(j, k, ids.size())): continue
				ids[k] = next_id
				queue.append(k)
		next_id += 1
	return ids

static func _block_between_vertices(blocked: Dictionary, a: int, b: int, size: Vector2i) -> void:
	var p := Vector2i(mini(a % size.x, b % size.x), mini(a / size.x, b / size.x))
	var cells := size - Vector2i.ONE
	var first := -1
	var second := -1
	if a / size.x == b / size.x:
		if p.y > 0 and p.y < cells.y:
			first = (p.y - 1) * cells.x + p.x
			second = p.y * cells.x + p.x
	else:
		if p.x > 0 and p.x < cells.x:
			first = p.y * cells.x + p.x - 1
			second = p.y * cells.x + p.x
	if first >= 0: blocked[edge_key(first, second, cells.x * cells.y)] = true

static func barriers(features: Array, cells: Vector2i) -> Dictionary:
	var result := {}
	for feature in features:
		if str(feature.get("river_class", "major")) != "major": continue
		var points: PackedVector2Array = feature.points
		for i in range(points.size() - 1):
			var p := points[i] * Vector2(cells)
			var q := points[i + 1] * Vector2(cells)
			var first := Vector2i((p.min(q) - Vector2.ONE).floor()).max(Vector2i.ZERO)
			var last := Vector2i((p.max(q) + Vector2.ONE).ceil()).min(cells - Vector2i.ONE)
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var a := Vector2(x + 0.5, y + 0.5)
					var index := y * cells.x + x
					for step in [Vector2i.RIGHT, Vector2i.DOWN]:
						if not Rect2i(Vector2i.ZERO, cells).has_point(Vector2i(x, y) + step): continue
						if Geometry2D.segment_intersects_segment(p, q, a, a + Vector2(step)) != null:
							result[edge_key(index, index + step.y * cells.x + step.x, cells.x * cells.y)] = true
	return result

static func _push(heap: Array, item: Vector2) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if not _less(item, heap[p]): break
		heap[i] = heap[p]
		i = p
	heap[i] = item

static func _pop(heap: Array) -> Vector2:
	var result: Vector2 = heap[0]
	var last: Vector2 = heap.pop_back()
	if heap.is_empty(): return result
	var i := 0
	while i * 2 + 1 < heap.size():
		var child := i * 2 + 1
		if child + 1 < heap.size() and _less(heap[child + 1], heap[child]): child += 1
		if not _less(heap[child], last): break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return result

static func _less(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)
