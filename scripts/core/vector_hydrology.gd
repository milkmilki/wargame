class_name VectorHydrology
extends RefCounted
## The expensive DEM drainage is preprocessed once. Climate weights and river
## classes remain runtime inputs, so latitude overrides do not reuse stale rain.
const Hydrology = preload("res://scripts/core/terrain_hydrology.gd")
const VERSION := "vector_water_v2"
const HEADWATER_MIN_FLOW := 0.5
const HEADWATER_MIN_AREA := 64.0
static var _networks: Dictionary = {}

static func network(path: String) -> Dictionary:
	if not _networks.has(path):
		_networks[path] = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _networks[path]

## Flow thresholds define established channels, not a knife that cuts their
## connected low-flow headwaters off the map. Extend only the largest upstream
## catchment of each visible branch, without adding water or promoting classes.
static func visible_reaches(reaches: Array, flow: PackedFloat64Array) -> PackedByteArray:
	var largest := PackedInt32Array()
	largest.resize(reaches.size())
	largest.fill(-1)
	var visible := PackedByteArray()
	visible.resize(reaches.size())
	var queue := PackedInt32Array()
	for i in range(reaches.size()):
		var next := int(reaches[i].downstream_id)
		if next >= 0 and (largest[next] < 0 or float(reaches[i].catchment_area) > float(reaches[largest[next]].catchment_area)):
			largest[next] = i
		if flow[i] >= Hydrology.MINOR_FLOW:
			visible[i] = 1
			queue.append(i)
	var head := 0
	while head < queue.size():
		var upstream := largest[queue[head]]
		head += 1
		if upstream < 0 or visible[upstream] != 0: continue
		if flow[upstream] < HEADWATER_MIN_FLOW or float(reaches[upstream].catchment_area) < HEADWATER_MIN_AREA: continue
		visible[upstream] = 1
		queue.append(upstream)
	return visible

static func build(environment: Dictionary, aspect: float, path: String, external_inflow: bool, source: Image) -> Dictionary:
	var started := Time.get_ticks_usec()
	var data := network(path)
	var reaches: Array = data.reaches
	var flow := PackedFloat64Array()
	var degree := PackedInt32Array()
	flow.resize(reaches.size())
	degree.resize(reaches.size())
	for i in range(reaches.size()):
		var reach: Dictionary = reaches[i]
		for k in range(reach.climate_cells.size()):
			flow[i] += environment.local_runoff[int(reach.climate_cells[k])] * float(reach.climate_areas[k])
		if int(reach.downstream_id) >= 0: degree[int(reach.downstream_id)] += 1
	var inflow_count := 0
	if external_inflow:
		for inlet in data.get("boundary_inlets", []):
			flow[int(inlet.reach_id)] += float(inlet.estimated_flow)
			inflow_count += 1
	var order := PackedInt32Array()
	for i in range(reaches.size()):
		if degree[i] == 0: order.append(i)
	var head := 0
	while head < order.size():
		var i := order[head]
		head += 1
		var next := int(reaches[i].downstream_id)
		if next >= 0:
			flow[next] += flow[i]
			degree[next] -= 1
			if degree[next] == 0: order.append(next)
	assert(order.size() == reaches.size(), "Cached drainage contains a cycle")
	var features: Array[Dictionary] = []
	var ids := {}
	var visible := visible_reaches(reaches, flow)
	for i in range(reaches.size()):
		if visible[i] == 0: continue
		ids[i] = features.size()
		var points := PackedVector2Array()
		for p in reaches[i].points: points.append(Vector2(float(p[0]), float(p[1])))
		var major := flow[i] >= Hydrology.MAJOR_FLOW
		var minor_width := lerpf(0.35, 0.65, sqrt(clampf(flow[i] / Hydrology.MINOR_FLOW, 0.0, 1.0)))
		var feature := MapFeatureContract.make_river(features.size(), points, MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY, 0.72 if major else minor_width, 0.9 if major else minor_width, -1, PackedInt32Array(), "major" if major else "minor", str(reaches[i].terminal_kind))
		features.append(feature)
	for old_id in ids:
		var next := int(reaches[old_id].downstream_id)
		if next < 0: continue
		assert(ids.has(next), "Downstream discharge cannot decrease")
		var from_id := int(ids[old_id])
		var to_id := int(ids[next])
		features[from_id].downstream_id = to_id
		features[to_id].upstream_ids.append(from_id)
	# A compact support raster is sufficient for settlement scoring. It is never
	# used to redraw, snap, or reconstruct the authoritative vector river paths.
	var size: Vector2i = environment.size + Vector2i.ONE
	var supply := PackedFloat32Array()
	var heights := PackedFloat32Array()
	var kinds: Array[String] = []
	var dock_corridor := PackedByteArray()
	dock_corridor.resize(environment.size.x * environment.size.y)
	var dock_clearance := TerrainMapGenerator.RIVER_DOCK_CITY_MIN_SPACING
	supply.resize(size.x * size.y)
	heights.resize(supply.size())
	heights.fill(1.0)
	kinds.resize(supply.size())
	for old_id in ids:
		var feature: Dictionary = features[int(ids[old_id])]
		var points: PackedVector2Array = feature.points
		for k in range(points.size() - 1):
			if feature.river_class == "major":
				var margin := Vector2(dock_clearance / aspect, dock_clearance) * Vector2(environment.size)
				var first := Vector2i((points[k].min(points[k + 1]) * Vector2(environment.size) - margin).floor()).max(Vector2i.ZERO)
				var last := Vector2i((points[k].max(points[k + 1]) * Vector2(environment.size) + margin).ceil()).min(environment.size - Vector2i.ONE)
				for y in range(first.y, last.y + 1):
					for x in range(first.x, last.x + 1): dock_corridor[y * environment.size.x + x] = 1
			var steps := maxi(1, ceili(((points[k + 1] - points[k]) * Vector2(environment.size)).length() * 2.0))
			for step in range(steps + 1):
				var p := points[k].lerp(points[k + 1], float(step) / steps)
				var cell := Vector2i((p * Vector2(environment.size)).round()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
				var index := cell.y * size.x + cell.x
				var pixel := Vector2i(p * Vector2(source.get_size())).clamp(Vector2i.ZERO, source.get_size() - Vector2i.ONE)
				supply[index] = maxf(supply[index], flow[old_id])
				heights[index] = minf(heights[index], maxf((source.get_pixelv(pixel).a * 255.0 - 128.0) / 127.0, 0.0))
	return {"features": features, "blocked_edges": Hydrology.barriers(features, environment.size), "size": size, "flow": supply, "heights": heights, "terminal_kind": kinds, "basin_count": int(data.basin_count), "hydrology_id": (str(data.network_id) + environment.environment_id + VERSION + str(external_inflow)).sha256_text(), "version": VERSION, "elapsed_usec": Time.get_ticks_usec() - started, "cache_hit": false, "external_inflow_count": inflow_count, "dem_size": data.dem_size, "dock_corridor": dock_corridor}
