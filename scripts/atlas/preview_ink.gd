extends Node2D
## Native atlas route-chain/display ink. AGPL-3.0-only.
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
var data: Dictionary
var borders: Array = []
var route_lines: Dictionary = {}
var show_borders := true
var show_roads := true
var pen := 1.0
var stroke_cache: Dictionary = {}
var stroke_key := ""
var view_zoom := 1.0

func prepare_strokes() -> void:
	var key := "%d:%d:%.8f:%.8f"%[hash(borders),hash(route_lines),pen,view_zoom]
	if key==stroke_key: return
	stroke_key = key; stroke_cache.clear()
	var lines: Array = []; var pens: Array = [[],[],[]]
	for border in borders:
		var path := Geometry.points(border.pts); lines.append(path)
		for dash in Strokes.dashes(path,5*pen,3*pen,true): pens[dash.tier].append(dash.path)
	var aa := .55/view_zoom
	stroke_cache.border_under = Strokes.build(lines,3.8*pen,aa); stroke_cache.border_pens = []
	for tier in range(3): stroke_cache.border_pens.append(Strokes.build(pens[tier],[1.45,2.05,2.75][tier]*pen,aa))
	for kind in ["trail","road"]:
		var dashes: Array = []; var routes: Array = route_lines.get(kind,[])
		for path in routes:
			for dash in Strokes.dashes(path,(2.2 if kind=="trail" else 4.6)*pen,(2.4 if kind=="trail" else 2.6)*pen): dashes.append(dash.path)
		stroke_cache[kind+"_under"] = Strokes.build(routes,(2. if kind=="trail" else 2.8)*pen,aa)
		stroke_cache[kind] = Strokes.build(dashes,(.8 if kind=="trail" else 1.2)*pen,aa)

func wrapped_mesh(mesh: ArrayMesh,color: Color) -> void:
	if mesh.get_surface_count()==0: return
	for shift in [-2048.,0.,2048.]: draw_set_transform(Vector2(shift,0)); draw_mesh(mesh,null,Transform2D.IDENTITY,color)
	draw_set_transform(Vector2.ZERO)

static func road_lines(map_data: Dictionary) -> Dictionary:
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
	prepare_strokes()
	if show_borders:
		wrapped_mesh(stroke_cache.border_under,Color8(246,236,210,153))
		for tier in range(3): wrapped_mesh(stroke_cache.border_pens[tier],Color8(58,32,20,230))
	if show_roads:
		for kind in ["trail","road"]:
			wrapped_mesh(stroke_cache[kind+"_under"],Color8(246,236,210,77 if kind=="trail" else 115))
			wrapped_mesh(stroke_cache[kind],Color8(74,46 if kind=="trail" else 42,28 if kind=="trail" else 24,179 if kind=="trail" else 230))
