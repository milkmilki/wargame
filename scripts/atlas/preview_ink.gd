extends Node2D
## Native atlas route-chain/display ink. AGPL-3.0-only.
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
const VisibleLines = preload("res://scripts/atlas/visible_lines.gd")
const Persistent = preload("res://scripts/atlas/persistent_strokes.gd")
var high_performance := false
var persistent_layers: Array = []
var persistent_key: Array = []
var geometry_pool := {}
var scheduler: Node
var data: Dictionary
var borders: Array = []
var route_lines: Dictionary = {}
var show_borders := true
var show_roads := true
var pen := 1.0
var stroke_cache: Dictionary = {}
var stroke_key := ""
var view_zoom := 1.0
var visible_world := Rect2(0,0,2048,1024)
var cached_world := Rect2()
var source_key: Array = []
var path_index := {}
var stroke_build_count := 0

func prepare_strokes() -> void:
	var key := "%d:%d:%.8f:%.8f"%[hash(borders),hash(route_lines),pen,view_zoom]
	if key==stroke_key and cached_world.encloses(visible_world): return
	var sources := [hash(borders),hash(route_lines)]
	if sources!=source_key:
		source_key = sources; path_index.clear()
		var paths: Array = []
		for border in borders: paths.append(Geometry.points(border.pts))
		path_index.borders = VisibleLines.index(paths)
		for kind in ["trail","road"]: path_index[kind] = VisibleLines.index(route_lines.get(kind,[]))
	cached_world = visible_world.grow(192./maxf(.1,view_zoom))
	stroke_key = key; stroke_cache.clear()
	stroke_build_count += 1
	var lines: Array = []; var pens: Array = [[],[],[]]
	for path in VisibleLines.select(path_index.borders,cached_world):
		lines.append(path)
		for dash in Strokes.dashes(path,5*pen,3*pen,true): pens[dash.tier].append(dash.path)
	var aa := .55/view_zoom
	stroke_cache.border_under = Strokes.build(lines,3.8*pen,aa); stroke_cache.border_pens = []
	for tier in range(3): stroke_cache.border_pens.append(Strokes.build(pens[tier],[1.45,2.05,2.75][tier]*pen,aa))
	for kind in ["trail","road"]:
		var dashes: Array = []; var routes: Array = VisibleLines.select(path_index[kind],cached_world)
		for path in routes:
			for dash in Strokes.dashes(path,(2.2 if kind=="trail" else 4.6)*pen,(2.4 if kind=="trail" else 2.6)*pen): dashes.append(dash.path)
		stroke_cache[kind+"_under"] = Strokes.build(routes,(2. if kind=="trail" else 2.8)*pen,aa)
		stroke_cache[kind] = Strokes.build(dashes,(.8 if kind=="trail" else 1.2)*pen,aa)

func wrapped_mesh(mesh: ArrayMesh,color: Color) -> void:
	if mesh.get_surface_count()==0: return
	for shift in [-2048.,0.,2048.]: draw_set_transform(Vector2(shift,0)); draw_mesh(mesh,null,Transform2D.IDENTITY,color)
	draw_set_transform(Vector2.ZERO)

static func road_lines(map_data: Dictionary) -> Dictionary:
	if map_data.has("traffic_graph"):
		var shared := {"road":[],"trail":[]}
		for edge in map_data.traffic_graph.edges: shared["road" if edge.tier==1 else "trail"].append(edge.path)
		return shared
	var out := {}; var mesh: Dictionary = map_data.mesh
	var stops := {}; for city in map_data.cities: stops[int(city.cell)] = true
	for kind in ["road","trail"]:
		var links := {}
		for route in map_data.roads:
			if route.kind!=kind: continue
			for t in range(1,route.cells.size()):
				var a := int(route.cells[t-1]); var b := int(route.cells[t])
				if not links.has(a): links[a] = []
				if not links.has(b): links[b] = []
				if not links[a].has(b): links[a].append(b)
				if not links[b].has(a): links[b].append(a)
		var used := {}; var lines: Array = []; var nodes: Array = links.keys(); nodes.sort()
		for stop_pass in [true,false]:
			for a in nodes:
				if stop_pass and not (stops.has(a) or links[a].size()!=2): continue
				for b in links[a]:
					var key: int = mini(a,b)*int(mesh.n)+maxi(a,b)
					if used.has(key): continue
					var cells: Array = [a]; var previous: int = a; var current: int = b; used[key] = true
					while true:
						cells.append(current)
						if current==a or stops.has(current) or links[current].size()!=2: break
						var next: int = links[current][1] if links[current][0]==previous else links[current][0]
						var k := mini(current,next)*int(mesh.n)+maxi(current,next)
						if used.has(k): break
						used[k] = true; previous = current; current = next
					var p := PackedVector2Array()
					for cell in cells:
						var x := float(mesh.x[cell])
						if not p.is_empty(): x -= mesh.width*floor((x-p[-1].x)/mesh.width+.5)
						p.append(Vector2(x,mesh.y[cell]))
					lines.append(Geometry.chaikin(p,false,3))
		out[kind] = lines
	return out

func _draw() -> void:
	if data.is_empty(): return
	if high_performance:
		update_persistent(); return
	prepare_strokes()
	if show_borders:
		wrapped_mesh(stroke_cache.border_under,Color8(246,236,210,153))
		for tier in range(3): wrapped_mesh(stroke_cache.border_pens[tier],Color8(58,32,20,230))
	if show_roads:
		for kind in ["trail","road"]:
			wrapped_mesh(stroke_cache[kind+"_under"],Color8(246,236,210,77 if kind=="trail" else 115))
			wrapped_mesh(stroke_cache[kind],Color8(74,46 if kind=="trail" else 42,28 if kind=="trail" else 24,179 if kind=="trail" else 230))

func update_persistent() -> void:
	var sources := [hash(borders),hash(route_lines)]
	if sources!=persistent_key:
		var first := persistent_layers.is_empty()
		var paths: Array = []
		for border in borders: paths.append(Geometry.points(border.pts))
		if first:
			add_stroke(paths,3.8,Color8(246,236,210,153),0,0,false,true)
			add_stroke(paths,2.75,Color8(58,32,20,230),5,3,true,true)
			for kind in ["trail","road"]:
				add_stroke(route_lines.get(kind,[]),2. if kind=="trail" else 2.8,Color8(246,236,210,77 if kind=="trail" else 115),0,0,false,false)
				add_stroke(route_lines.get(kind,[]),.8 if kind=="trail" else 1.2,Color8(74,46 if kind=="trail" else 42,28 if kind=="trail" else 24,179 if kind=="trail" else 230),2.2 if kind=="trail" else 4.6,2.4 if kind=="trail" else 2.6,false,false)
		else:
			if sources[0]!=persistent_key[0]:
				for i in range(2): persistent_layers[i].set_paths(paths)
			if sources[1]!=persistent_key[1]:
				for i in range(2,6): persistent_layers[i].set_paths(route_lines.get("trail" if i<4 else "road",[]))
		persistent_key = sources
		var live := {}
		for layer in persistent_layers: live[layer.key] = true
		for key in geometry_pool.keys():
			if not live.has(key): geometry_pool.erase(key)
	for layer in persistent_layers:
		layer.visible = show_borders if layer.get_meta("border") else show_roads
		layer.set_zoom(view_zoom); layer.set_view(visible_world)

func add_stroke(paths: Array,width: float,color: Color,dash: float,gap: float,vary: bool,border: bool) -> void:
	var layer := Persistent.new(); layer.scheduler = scheduler; layer.pool = geometry_pool; layer.style(width,color,dash,gap,-.22,vary); layer.set_paths(paths); layer.set_meta("border",border)
	add_child(layer); persistent_layers.append(layer)
