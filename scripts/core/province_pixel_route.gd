extends RefCounted
## Refine a failed coarse road on the original terrain pixels. Territory stays
## the saved categorical province grid; this graph is used only for movement.
static func find(ids: PackedInt32Array, grid: Vector2i, start: Vector2, end: Vector2, a: int, b: int, options: Dictionary) -> PackedVector2Array:
	if options.has("segment_validator"): return _native_find(ids,grid,start,end,a,b,options)
	var result := _find(ids, grid, start, end, a, b, options, 4)
	if result.is_empty(): return _find(ids, grid, start, end, a, b, options, 1)
	return result

static func _find(ids: PackedInt32Array, grid: Vector2i, start: Vector2, end: Vector2, a: int, b: int, options: Dictionary, scale: int) -> PackedVector2Array:
	var started := Time.get_ticks_msec()
	var empty := PackedVector2Array()
	var image: Image = options.get("image")
	if image == null: return empty
	var size := Vector2i(maxi(1, image.get_width() / scale), maxi(1, image.get_height() / scale))
	var cache_key := "pixel_data_%d" % scale
	if not options.has(cache_key):
		var rgba: Image = image.duplicate()
		rgba.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		rgba.convert(Image.FORMAT_RGBA8)
		options[cache_key] = rgba.get_data()
	var data: PackedByteArray = options[cache_key]
	var first := Vector2i(start * Vector2(size)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var last := Vector2i(end * Vector2(size)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var source := first.y * size.x + first.x
	var target := last.y * size.x + last.x
	if data[source * 4 + 3] <= 128 or data[target * 4 + 3] <= 128: return empty
	# An exhausted search proves the complete reachable component. Reuse that
	# proof when other dock samples ask for another unreachable point on the
	# same shore. A capped/incomplete search must never populate this cache.
	if not options.has("pixel_closed_components"): options["pixel_closed_components"] = {}
	var closed: Dictionary = options.pixel_closed_components
	var component_key := "%d:%d:%d:%s" % [mini(a, b), maxi(a, b), scale, str(options.get("maximum_height", TerrainMapGenerator.ROAD_MAXIMUM_HEIGHT_DIFFERENCE))]
	for component in closed.get(component_key, []):
		if component.has(source) != component.has(target): return empty
	var aspect := float(options.get("aspect", 1.0)) * size.y / size.x
	var previous := {source: -1}
	var costs := {source: 0.0}
	var heap: Array[Vector3] = []
	TerrainMapGenerator._province_heap_push(heap, Vector3(0, source, 0))
	var rivers: Array[PackedVector2Array] = []
	rivers.assign(options.get("river_paths", []))
	var no_positions: Array[Vector2] = []
	var signature := hash(rivers)
	var found := false
	while not heap.is_empty() and costs.size() <= 300000:
		var entry: Vector3 = TerrainMapGenerator._province_heap_pop(heap)
		var current := int(entry.y)
		if entry.z > float(costs[current]) + 0.0001: continue
		if current == target: found = true; break
		var p := Vector2i(current % size.x, current / size.x)
		var altitude := (float(data[current * 4 + 3]) - 128.0) / 127.0
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var q: Vector2i = p + offset
			if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y: continue
			var index := q.y * size.x + q.x
			if data[index * 4 + 3] <= 128: continue
			var cell := Vector2i(Vector2(q) / Vector2(size) * Vector2(grid))
			if ids[cell.y * grid.x + cell.x] not in [a, b]: continue
			var height := (float(data[index * 4 + 3]) - 128.0) / 127.0
			if absf(height - altitude) > float(options.get("maximum_height", TerrainMapGenerator.ROAD_MAXIMUM_HEIGHT_DIFFERENCE)): continue
			var cost := float(costs[current]) + (aspect if offset.x != 0 else 1.0) * (1.0 + 7.0 * absf(height - altitude))
			if cost >= float(costs.get(index, INF)) - 0.0001: continue
			var uv := (Vector2(p) + Vector2.ONE * 0.5) / Vector2(size)
			var next_uv := (Vector2(q) + Vector2.ONE * 0.5) / Vector2(size)
			if scale > 1:
				if not TerrainMapGenerator._safe_road_shortcut(uv, next_uv, options): continue
			elif TerrainMapGenerator._road_dictionary_crosses_rivers({"map_path": PackedVector2Array([uv, next_uv])}, no_positions, rivers, signature): continue
			previous[index] = current
			costs[index] = cost
			var heuristic := absf(q.x - last.x) * aspect + absf(q.y - last.y)
			TerrainMapGenerator._province_heap_push(heap, Vector3(cost + heuristic, index, cost))
	if OS.get_environment("HYDROLOGY_DIAGNOSE") == "1": print("PIXEL_ROUTE ", a, "/", b, " nodes=", costs.size(), " found=", found, " ms=", Time.get_ticks_msec()-started)
	if not found and heap.is_empty():
		if not closed.has(component_key): closed[component_key] = []
		closed[component_key].append(costs)
	if not found: return empty
	var raw := PackedVector2Array([end])
	var cursor := target
	while cursor >= 0:
		raw.append((Vector2(cursor % size.x, cursor / size.x) + Vector2.ONE * 0.5) / Vector2(size))
		cursor = previous[cursor]
	raw.append(start)
	raw.reverse()
	var result := PackedVector2Array([start])
	var anchor := 0
	while anchor < raw.size() - 1:
		var next := -1
		if not options.has("segment_validator"): next=TerrainMapGenerator._furthest_checked_shortcut(raw, anchor, ids, grid, a, b, options)
		if options.has("segment_validator"):
			var validator: Callable = options.segment_validator
			next = -1
			# Exponential brackets bound shortcut checks on long fine-pixel routes.
			var stride:=1;var failed:=raw.size()
			while anchor+stride<raw.size():
				var candidate:=anchor+stride
				if not validator.call(raw[anchor],raw[candidate],a,b): failed=candidate;break
				next=candidate;stride*=2
			var low:=maxi(anchor+1,next+1);var high:=mini(raw.size()-1,failed-1)
			while low<=high:
				var middle:=(low+high)/2
				if validator.call(raw[anchor],raw[middle],a,b): next=middle;low=middle+1
				else: high=middle-1
		if next < 0: return empty
		result.append(raw[next])
		anchor = next
	return result

static func _native_find(ids: PackedInt32Array,grid: Vector2i,start: Vector2,end: Vector2,a: int,b: int,options: Dictionary) -> PackedVector2Array:
	var source: Image=options.image;var size:=source.get_size()
	if not options.has("province_bounds"):
		var bounds: Dictionary={}
		for y in range(grid.y):
			for x in range(grid.x):
				var id:=ids[y*grid.x+x]
				var cell:=Rect2i(x,y,1,1)
				bounds[id]=bounds[id].merge(cell) if bounds.has(id) else cell
		options.province_bounds=bounds
	if not options.province_bounds.has(a) or not options.province_bounds.has(b): return PackedVector2Array()
	var rect: Rect2i=options.province_bounds[a].merge(options.province_bounds[b])
	var lo:=Vector2i(Vector2(rect.position)*Vector2(size)/Vector2(grid))
	var hi:=Vector2i((Vector2(rect.end)*Vector2(size)/Vector2(grid)).ceil()).clamp(Vector2i.ZERO,size)
	if not options.has("fine_rgba"):
		var image: Image=source.duplicate();image.convert(Image.FORMAT_RGBA8);options.fine_rgba=image.get_data()
	var data: PackedByteArray=options.fine_rgba
	var graph:=preload("res://scripts/core/atlas_fine_astar.gd").new()
	graph.region=Rect2i(lo,hi-lo);graph.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER
	graph.alpha=data;graph.width=size.x;graph.aspect=float(options.get("aspect",1))*size.y/size.x
	graph.maximum_height=float(options.get("maximum_height",1));graph.update()
	for y in range(lo.y,hi.y):
		var row:=mini(grid.y-1,y*grid.y/size.y)*grid.x
		var blocked:=-1
		for x in range(lo.x,hi.x+1):
			var solid:=x<hi.x and (data[(y*size.x+x)*4+3]<=128 or ids[row+mini(grid.x-1,x*grid.x/size.x)] not in [a,b])
			if solid and blocked<0: blocked=x
			if not solid and blocked>=0: graph.fill_solid_region(Rect2i(blocked,y,x-blocked,1),true);blocked=-1
	var first:=Vector2i(start*Vector2(size)).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var last:=Vector2i(end*Vector2(size)).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var nodes:=graph.get_id_path(first,last)
	if nodes.is_empty(): return PackedVector2Array()
	var raw:=PackedVector2Array([start])
	for node in nodes: raw.append((Vector2(node)+Vector2.ONE*0.5)/Vector2(size))
	raw.append(end)
	var path:=PackedVector2Array([start]);var anchor:=0
	var validator: Callable=options.segment_validator
	while anchor<raw.size()-1:
		var best:=-1;var stride:=1;var failed:=raw.size()
		while anchor+stride<raw.size():
			var candidate:=anchor+stride
			if not validator.call(raw[anchor],raw[candidate],a,b): failed=candidate;break
			best=candidate;stride*=2
		var low:=maxi(anchor+1,best+1);var high:=mini(raw.size()-1,failed-1)
		while low<=high:
			var middle:=(low+high)/2
			if validator.call(raw[anchor],raw[middle],a,b): best=middle;low=middle+1
			else: high=middle-1
		if best<0: return PackedVector2Array()
		path.append(raw[best]);anchor=best
	return path
