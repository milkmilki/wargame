extends RefCounted
## Numeric, cached geometry of the existing TradeNetwork regions; no new rules.
const Borders = preload("res://scripts/atlas/borders.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Zoom = preload("res://scripts/atlas/zoom_geometry.gd")
const Wash = preload("res://scripts/atlas/wash.gd")

## Display the published network without starting another trade search.
## Many hub pairs share roads; each physical segment is drawn only once.
static func route_segments(state: GameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state == null or not state.trade_enabled:
		return result
	var corridors := {}
	var graph: Dictionary=state.atlas_trade_cache.get("graph",{})
	if graph.is_empty(): graph=TradeNetwork._build_trade_graph(state)
	for route in state.trade_routes:
		var path: Array = route.get("city_path", [])
		var blocked := int(route.get("status", TradeNetwork.RouteStatus.ACTIVE)) == TradeNetwork.RouteStatus.BLOCKED
		var seen := {}
		for index in range(1, path.size()):
			var a := int(path[index - 1])
			var b := int(path[index])
			if a < 0 or b < 0 or a >= state.cities.size() or b >= state.cities.size():
				continue
			var key := GameState.edge_key(a, b)
			if seen.has(key):
				continue
			var edge: Edge = graph.edge_lookup.get(GameState.edge_key(a,b),null)
			if edge == null:
				continue
			seen[key] = true
			if not corridors.has(key):
				var points := PackedVector2Array()
				for normalized in edge.map_points(state.cities[edge.city_a].map_position, state.cities[edge.city_b].map_position):
					var point: Vector2 = normalized * Vector2(2048, 1024)
					if not points.is_empty():
						point.x += roundf((points[-1].x - point.x) / 2048.) * 2048.
						if point.is_equal_approx(points[-1]):
							continue
					points.append(point)
				corridors[key] = {"edge_key": key, "path": points, "route_count": 0, "active_count": 0}
			corridors[key].route_count += 1
			if not blocked:
				corridors[key].active_count += 1
	var keys := corridors.keys()
	keys.sort()
	for key in keys:
		if corridors[key].path.size() >= 2:
			result.append(corridors[key])
	return result

static func calculate(input: Dictionary) -> Dictionary:
	var lines := Borders.build(input.chains,input.owners,input.mesh,input.raster,input.region_of)
	var index := Zoom.build(lines)
	var labels := PackedInt32Array(); labels.resize(input.provinces.size()); labels.fill(-2)
	for k in range(labels.size()):
		var district: int=input.provinces[k]
		if district>=0 and district<input.owners.size(): labels[k]=input.owners[district]
	Geometry.band_labels(labels,2048,1024,lines,input.weak)
	var colors: Array=[]
	var palette_size:=int(input.count)
	for owner in input.owners: palette_size=maxi(palette_size,int(owner)+1)
	for id in range(palette_size): colors.append(Color.from_hsv(fposmod(id*.61803398875,1.),.38,.78))
	return {"lines":lines,"labels":labels,"index":index,"segments":Zoom.texture_data(index),"edge":Wash.edge_data(labels,2048,1024),"color":Wash.color_data(labels,2048,1024,colors),"colors":colors}

class Routes extends Node2D:
	const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
	const PAPER := Color(.98, .94, .83, .90)
	const INK := Color(.36, .20, .07, .94)
	const GOLD := Color(1., .76, .27)
	const CLOSED := Color(.48, .40, .32, .8)
	var scheduler: Node
	var geometry_pool := {}
	var segments: Array = []
	var stroke_layers: Array = []
	var markers: Array = []
	var build_count := 0
	var view_zoom := 1.
	var visible_world := Rect2(-4096, -1024, 8192, 3072)

	func set_segments(value: Array) -> void:
		if segments == value:
			return
		segments = value
		build_count += 1
		markers.clear()
		var groups: Array = [[], [], []]
		for segment in segments:
			var tier := 2 if segment.active_count == 0 else 1 if segment.active_count >= 4 else 0
			groups[tier].append(segment.path)
			markers.append(_midpoint(segment.path, tier))
		if stroke_layers.is_empty():
			for tier in range(3):
				for pass_index in range(3):
					var stroke := Persistent.new()
					stroke.scheduler = scheduler
					stroke.pool = geometry_pool
					stroke.z_index = -1
					var width: float = [[5., 3., 1.6], [6.2, 4., 2.4], [3.8, 1.8, .9]][tier][pass_index]
					var color := PAPER if pass_index == 0 else CLOSED if tier == 2 else INK if pass_index == 1 else GOLD
					var dash := 3. if tier == 2 and pass_index > 0 else 8. if pass_index == 2 else 0.
					stroke.style(width, color, dash, 6. if tier == 2 else 5., -1.)
					add_child(stroke)
					stroke_layers.append(stroke)
		for index in range(stroke_layers.size()):
			stroke_layers[index].set_paths(groups[index / 3])
			stroke_layers[index].set_zoom(view_zoom)
			stroke_layers[index].set_view(visible_world)
		# Old monthly networks must not accumulate in this layer's mesh pool.
		var used := {}
		for stroke in stroke_layers:
			used[stroke.key] = true
		for key in geometry_pool.keys():
			if not used.has(key):
				geometry_pool.erase(key)
		queue_redraw()

	func set_view(value: float, rect: Rect2) -> void:
		var changed := not is_equal_approx(view_zoom, value)
		if not changed and visible_world == rect:
			return
		view_zoom = maxf(.1, value)
		visible_world = rect
		for stroke in stroke_layers:
			stroke.set_zoom(view_zoom)
			stroke.set_view(rect)
		if changed:
			queue_redraw()

	static func _midpoint(path: PackedVector2Array, tier: int) -> Dictionary:
		var length := 0.
		for index in range(1, path.size()):
			length += path[index - 1].distance_to(path[index])
		var remaining := length * .5
		for index in range(1, path.size()):
			var delta := path[index] - path[index - 1]
			var distance := delta.length()
			if distance > 0. and remaining <= distance:
				return {"point": path[index - 1] + delta * (remaining / distance), "direction": delta / distance, "length": length, "tier": tier}
			remaining -= distance
		return {}

	func _draw() -> void:
		var pen := 1. / maxf(.1, view_zoom)
		for shift in [-2048., 0., 2048.]:
			draw_set_transform(Vector2(shift, 0))
			for marker in markers:
				if marker.is_empty() or marker.length * view_zoom < 48.:
					continue
				var axis: Vector2 = marker.direction * pen
				var normal := Vector2(-axis.y, axis.x)
				var point: Vector2 = marker.point
				if marker.tier == 2:
					draw_line(point + axis * 3. + normal * 3., point - axis * 3. - normal * 3., CLOSED, 1.5 * pen, true)
					draw_line(point + axis * 3. - normal * 3., point - axis * 3. + normal * 3., CLOSED, 1.5 * pen, true)
					continue
				# Commerce is two-way; these are exchange marks, not invented cargo flows.
				for direction in [-1., 1.]:
					var tip: Vector2 = point + axis * 5. * direction
					var tail: Vector2 = tip - axis * 3.5 * direction
					var chevron := PackedVector2Array([tail + normal * 2.4, tip, tail - normal * 2.4])
					draw_polyline(chevron, PAPER, 3.4 * pen, true)
					draw_polyline(chevron, INK, 1.4 * pen, true)
		draw_set_transform(Vector2.ZERO)

class Hubs extends Node2D:
	var points := PackedVector2Array()
	var view_zoom := 1.
	func set_points(value: PackedVector2Array):
		if points==value: return
		points=value; queue_redraw()
	func set_zoom(value: float):
		if is_equal_approx(value,view_zoom): return
		view_zoom=value; queue_redraw()
	func _draw():
		var pen:=1./maxf(.1,view_zoom)
		for shift in [-2048.,0.,2048.]:
			draw_set_transform(Vector2(shift,0))
			for p in points:
				draw_circle(p,5.5*pen,Color(.22,.12,.06))
				draw_circle(p,3.7*pen,Color(.98,.77,.30))
				draw_arc(p,8.*pen,0,TAU,24,Color(.27,.15,.05),pen,true)
		draw_set_transform(Vector2.ZERO)
