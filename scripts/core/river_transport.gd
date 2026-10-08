class_name RiverTransport
extends RefCounted
## Junctions belong to the routing graph, not to the city or military model.
const Navigation = preload("res://scripts/core/river_navigation.gd")
static func build(features: Array, docks: Array, image: Image, aspect: float, local_navigation: bool = false) -> Array[Dictionary]:
	var adjacency := {}
	var terminals := {}
	var positions := {}
	var dock_by_id := {}
	var feature_by_id := {}
	for feature in features: feature_by_id[int(feature.id)] = feature
	for dock in docks:
		var key := _key(dock.position)
		terminals[key] = int(dock.city_id)
		positions[key] = dock.position
		dock_by_id[int(dock.city_id)] = dock
	for river in MapFeatureContract.major_rivers(features):
		var path: PackedVector2Array = river.points
		var cuts: Array[Dictionary] = [{"progress": 0.0, "point": path[0]}, {"progress": float(path.size() - 1), "point": path[-1]}]
		for dock in docks:
			if int(dock.river_id) == int(river.id): cuts.append({"progress": float(dock.river_progress), "point": dock.position})
		cuts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.progress < b.progress)
		for i in range(cuts.size() - 1):
			var a: Dictionary = cuts[i]
			var b: Dictionary = cuts[i + 1]
			var points := section(path, a.progress, b.progress)
			if points.size() < 2: continue
			var difference := _height_range(points, image)
			if not local_navigation and not TerrainMapGenerator.river_link_is_navigable(difference): continue
			var ak := _key(a.point)
			var bk := _key(b.point)
			positions[ak] = a.point
			positions[bk] = b.point
			if not adjacency.has(ak): adjacency[ak] = []
			if not adjacency.has(bk): adjacency[bk] = []
			adjacency[ak].append({"to": bk, "points": points, "ref": {"river_id": int(river.id), "from": float(a.progress), "to": float(b.progress)}})
			var reverse := points.duplicate()
			reverse.reverse()
			adjacency[bk].append({"to": ak, "points": reverse, "ref": {"river_id": int(river.id), "from": float(b.progress), "to": float(a.progress)}})
	var roads: Array[Dictionary] = []
	var paired := {}
	for start in terminals:
		var city_a := int(terminals[start])
		var queue: Array[Dictionary] = [{"node": start, "path": PackedVector2Array([positions[start]]), "refs": []}]
		var visited := {start: true}
		var head := 0
		while head < queue.size():
			var current: Dictionary = queue[head]
			head += 1
			for link in adjacency.get(current.node, []):
				var next: String = link.to
				if visited.has(next): continue
				visited[next] = true
				var points: PackedVector2Array = current.path.duplicate()
				points.append_array((link.points as PackedVector2Array).slice(1))
				var refs: Array = current.refs.duplicate(true)
				refs.append(link.ref.duplicate())
				if not terminals.has(next):
					queue.append({"node": next, "path": points, "refs": refs})
					continue
				var city_b := int(terminals[next])
				if city_a >= city_b: continue
				var pair := Vector2i(city_a, city_b)
				if paired.has(pair): continue
				var difference := _height_range(points, image)
				var navigation := _assess_navigation(refs, feature_by_id, image, aspect) if local_navigation else {}
				if local_navigation:
					if not navigation.navigable: continue
				elif not TerrainMapGenerator.river_link_is_navigable(difference): continue
				paired[pair] = true
				var length := TerrainMapGenerator.metric_polyline_length(points, aspect)
				roads.append({"a": city_a, "b": city_b, "kind": Edge.Kind.RIVER, "map_path": points, "river_reaches": refs, "length": length, "distance": TerrainMapGenerator.distance_units_for_metric_length(length), "height_difference": difference, "land_ratio": 1.0, "cost": length, "backbone": true, "max_manpower": Edge.WATER_MANPOWER, "base_max_manpower": Edge.WATER_MANPOWER, "danger": TerrainMapGenerator._boundary_river_link_danger(points, difference, int(refs[0].river_id), city_a), "travel_time_multiplier": TerrainMapGenerator.RIVER_TRAVEL_TIME_MULTIPLIER, "supply_loss_multiplier": TerrainMapGenerator.RIVER_SUPPLY_LOSS_MULTIPLIER, "allows_holding": false})
				if local_navigation: roads[-1]["river_navigation"] = navigation
	return roads

## Continue the terrain window through network junctions, independently of
## feature cuts and dock placement. Each continuation is an actual river path.
static func _assess_navigation(refs: Array, by_id: Dictionary, image: Image, aspect: float) -> Dictionary:
	var path := PackedVector2Array()
	for ref in refs:
		var part := section(by_id[int(ref.river_id)].points,float(ref.from),float(ref.to))
		path.append_array(part if path.is_empty() else part.slice(1))
	var first: Dictionary=refs[0]
	var last: Dictionary=refs[-1]
	var prefixes := _extensions(int(first.river_id),float(first.from),-1.0 if first.to>=first.from else 1.0,Navigation.WINDOW_LENGTH,by_id,aspect,{})
	var suffixes := _extensions(int(last.river_id),float(last.to),1.0 if last.to>=last.from else -1.0,Navigation.WINDOW_LENGTH,by_id,aspect,{})
	var result := Navigation.assess(path,image,aspect)
	for prefix in prefixes:
		for suffix in suffixes:
			var context: PackedVector2Array=prefix.duplicate()
			context.reverse()
			context.append_array(path.slice(1))
			context.append_array(suffix.slice(1))
			var assessment := Navigation.assess(context,image,aspect)
			if assessment.max_local_height_difference>result.max_local_height_difference: result=assessment
	return result

static func _extensions(id: int, progress: float, direction: float, remaining: float, by_id: Dictionary, aspect: float, visited: Dictionary) -> Array[PackedVector2Array]:
	var path: PackedVector2Array=by_id[id].points
	var end := _offset_progress(path,progress,direction*remaining,aspect)
	var part := section(path,progress,end)
	var used := TerrainMapGenerator.metric_polyline_length(part,aspect)
	var result: Array[PackedVector2Array]=[]
	if used>=remaining-1e-7 or visited.has(id): return [part]
	var seen := visited.duplicate()
	seen[id]=true
	var key := _key(part[-1])
	for next_id in by_id:
		if seen.has(next_id) or str(by_id[next_id].get("river_class", "major")) != "major": continue
		var next: PackedVector2Array=by_id[next_id].points
		var start := -1.0
		var sign := 1.0
		if _key(next[0])==key: start=0.0
		elif _key(next[-1])==key: start=float(next.size()-1); sign=-1.0
		if start<0: continue
		for continuation in _extensions(next_id,start,sign,remaining-used,by_id,aspect,seen):
			var joined := part.duplicate()
			joined.append_array(continuation.slice(1))
			result.append(joined)
	if result.is_empty(): result.append(part)
	return result

static func _navigation_context(refs: Array, by_id: Dictionary, aspect: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(refs.size()):
		var ref: Dictionary = refs[i]
		var path: PackedVector2Array = by_id[int(ref.river_id)].points
		var a := float(ref.from)
		var b := float(ref.to)
		var direction := 1.0 if b >= a else -1.0
		if i == 0: a = _offset_progress(path,a,-direction*Navigation.WINDOW_LENGTH,aspect)
		if i == refs.size()-1: b = _offset_progress(path,b,direction*Navigation.WINDOW_LENGTH,aspect)
		var part := section(path,a,b)
		if not result.is_empty() and not part.is_empty(): part.remove_at(0)
		result.append_array(part)
	return result

static func _offset_progress(path: PackedVector2Array, progress: float, offset: float, aspect: float) -> float:
	var lengths := PackedFloat64Array([0.0])
	for i in range(path.size()-1):
		lengths.append(lengths[-1]+TerrainMapGenerator.metric_length_between(path[i],path[i+1],aspect))
	var index := mini(int(floor(progress)),path.size()-2)
	var distance := lerpf(lengths[index],lengths[index+1],progress-index)
	var target := clampf(distance+offset,0.0,lengths[-1])
	for i in range(lengths.size()-1):
		if target <= lengths[i+1]: return i + (target-lengths[i])/maxf(lengths[i+1]-lengths[i],1e-12)
	return path.size()-1

static func section(path: PackedVector2Array, from: float, to: float) -> PackedVector2Array:
	if from > to:
		var reversed := section(path, to, from)
		reversed.reverse()
		return reversed
	var result := PackedVector2Array([point_at(path, from)])
	for i in range(int(floor(from)) + 1, int(ceil(to))): result.append(path[i])
	var last := point_at(path, to)
	if not result[-1].is_equal_approx(last): result.append(last)
	return result

static func point_at(path: PackedVector2Array, progress: float) -> Vector2:
	var i := clampi(int(floor(progress)), 0, path.size() - 1)
	return path[i].lerp(path[mini(i + 1, path.size() - 1)], clampf(progress - i, 0.0, 1.0))

static func _key(point: Vector2) -> String:
	return "%d:%d" % [roundi(point.x * 1048576.0), roundi(point.y * 1048576.0)]

static func _height_range(points: PackedVector2Array, image: Image) -> float:
	var lo := INF
	var hi := -INF
	for point in points:
		var pixel := Vector2i(point * Vector2(image.get_size())).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
		var h := TerrainMapGenerator.packed_altitude(image.get_pixelv(pixel))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo
