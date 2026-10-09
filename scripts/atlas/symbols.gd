extends Node2D
## Native CanvasItem port of fantasy.ts drawGlyph and forest canopy shapes.
## AGPL-3.0-only. Reference plan input separates planning and rendering parity.
const Maths = preload("res://scripts/atlas/math.gd")
const INK := Color(58.0/255,45.0/255,34.0/255)
const PAPER := Color(236.0/255,224.0/255,193.0/255)
var data: Dictionary
var glyphs: Array = []
var forest := PackedByteArray()
var detail_zoom := 1.0
var layer := "all"
var visible_world := Rect2(-100000,-100000,200000,200000)

func quadratic(a: Vector2,b: Vector2,c: Vector2,steps: int = 12) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(steps+1):
		var t := float(i)/steps; p.append(a*(1-t)*(1-t)+b*2*t*(1-t)+c*t*t)
	return p

func curve_path(parts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for part in parts:
		var p := quadratic(part[0],part[1],part[2])
		for i in range(0 if out.is_empty() else 1,p.size()): out.append(p[i])
	return out

func pine(center: Vector2,r: float) -> PackedVector2Array:
	var top := center+Vector2(0,-1.55*r); var right := center+Vector2(r,.3*r); var left := center+Vector2(-r,.3*r)
	return curve_path([[top,center+Vector2(.35*r,-.45*r),right],[right,center+Vector2(0,1.15*r),left],[left,center+Vector2(-.35*r,-.45*r),top]])

func circle(center: Vector2,r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in range(33): p.append(center+Vector2(cos(i*TAU/32),sin(i*TAU/32))*r)
	return p

func _draw() -> void:
	if data.is_empty(): return
	var gs := 1.0 if detail_zoom<=1.35 else pow(detail_zoom/1.35,-.22)
	var mesh: Dictionary = data.mesh; var env: Dictionary = data.environment
	var spacing: float = mesh.spacing; var seed_value := Maths.sub_seed(int(data.seed),"glyphs")
	var kinds := [1,3,2] if layer in ["all","forest","crowns"] else []
	for kind in kinds:
		var shapes: Array = []; var crowns: Array = []
		for i in range(forest.size()):
			if forest[i]!=kind: continue
			var visible := false
			for sh in [-2048.,0.,2048.]:
				if visible_world.grow(spacing*2).has_point(Vector2(mesh.x[i]+sh,mesh.y[i])): visible = true; break
			if not visible: continue
			var boundary := false; var coast := false
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var j: int = mesh.adj[k]
				if forest[j]!=kind: boundary = true
				if env.water[j]!=0: coast = true
			var center := Vector2(mesh.x[i],mesh.y[i]); var h1 := Maths.hash2(i,1,seed_value)
			var radius := spacing*1.35
			if boundary:
				radius = spacing*(.62+.32*h1)*(.62 if coast else 1.0)
				center += Vector2(Maths.hash2(i,2,seed_value)-.5,Maths.hash2(i,3,seed_value)-.5)*spacing*.6
			for shift in [-2048.0,0.0,2048.0]:
				var c := center+Vector2(shift,0)
				if not visible_world.grow(radius*2).has_point(c): continue
				shapes.append(pine(c,radius) if kind==2 and boundary else circle(c,radius))
			if not boundary:
				var count := 1
				for tier in [2.0,3.5,6.0]:
					if detail_zoom>=tier*.95: count += 1
				for t in range(count):
					if t==0 and Maths.hash2(i,4,seed_value)>=(.72 if kind==3 else .6): continue
					var spread := .6 if t==0 else 1.05
					var jx := Maths.hash2(i,2 if t==0 else 10+t*2,seed_value); var jy := Maths.hash2(i,3 if t==0 else 11+t*2,seed_value)
					var c := Vector2(mesh.x[i],mesh.y[i])+Vector2(jx-.5,jy-.5)*spacing*spread
					for shift in [-2048.,0.,2048.]:
						crowns.append({"center":c+Vector2(shift,0),"radius":spacing*(.3+.14*(h1 if t==0 else Maths.hash2(i,20+t,seed_value)))*gs})
		var canopy := Color8(150,165,108) if kind==1 else Color8(118,140,104) if kind==2 else Color8(118,145,90)
		# Source uses all outlines then all fills, hiding internal canopy borders.
		if layer!="crowns":
			for p in shapes: draw_polyline(p,Color(INK,.85),1.1*gs,true)
			for p in shapes: draw_colored_polygon(p,canopy)
		for crown in crowns if layer!="forest" else []:
			var c: Vector2 = crown.center; var r: float = crown.radius
			var p := PackedVector2Array([c+Vector2(-r*.75,r*.35),c+Vector2(0,-r*.95),c+Vector2(r*.75,r*.35)]) if kind==2 else circle(c,r)
			draw_set_transform(Vector2(r*.32,r*.32)); draw_colored_polygon(p,Color(INK,.22)); draw_set_transform(Vector2.ZERO)
			draw_colored_polygon(p,canopy)
			if kind==2: draw_polyline(p,Color(INK,.6),.55*gs,true)
			else: draw_arc(c,r,PI,TAU,16,Color(INK,.6),.55*gs,true)
	for glyph in glyphs if layer in ["all","glyphs"] else []:
		if glyph.z>detail_zoom: continue
		for shift in [-2048.0,0.0,2048.0]:
			if not visible_world.grow(glyph.s*2).has_point(Vector2(glyph.x+shift,glyph.y)): continue
			draw_glyph(glyph,Vector2(glyph.x+shift,glyph.y),gs)

func draw_glyph(g: Dictionary,c: Vector2,gs: float) -> void:
	var s: float = g.s*gs; var kind := int(g.kind)
	if kind==0:
		var lean: float = (-sin(2*g.a)*.32*g.c+(g.v-.5)*.22)*s
		var co := cos(float(g.a)); var ws: float = g.s*(1+g.c*(.18*co*co-.14*(1-co*co)))*gs
		var peak := c+Vector2(lean,-s*1.15); var left := c+Vector2(-ws,0); var right := c+Vector2(ws,0)
		var outline := curve_path([[left,c+Vector2(-ws*.5+lean*.5,-s*.55),peak],[peak,c+Vector2(ws*.45+lean*.5,-s*.6),right]])
		var face := outline.duplicate(); face.append_array(quadratic(right,c+Vector2(0,s*.12),left))
		draw_colored_polygon(face,PAPER)
		var shadow := curve_path([[peak,c+Vector2(ws*.05+lean*.3,-s*.45),c+Vector2(ws*.12,s*.04)],[c+Vector2(ws*.12,s*.04),c+Vector2(ws*.6,s*.06),right],[right,c+Vector2(ws*.45+lean*.5,-s*.6),peak]])
		draw_colored_polygon(shadow,Color8(128,104,76,122)); draw_polyline(outline,Color(INK,.95),(.7+.035*g.s)*gs,true)
		draw_polyline(quadratic(peak,c+Vector2(ws*.05+lean*.3,-s*.45),c+Vector2(ws*.12,-s*.05)),Color(INK,.7),.5*gs,true)
		var hatch := maxi(2,int(floor(g.s/2.6+.5)))
		for i in range(1,hatch+1):
			var a := peak.lerp(right,float(i)/(hatch+1))
			draw_line(a+Vector2(-s*.05,s*.02),a+Vector2(-s*.22,s*.26),Color(INK,.7),.5*gs,true)
	elif kind==1:
		var p := quadratic(c+Vector2(-s,0),c+Vector2(0,-s*1.1),c+Vector2(s,0))
		draw_colored_polygon(p,PAPER); draw_polyline(p,Color(INK,.85),.7*gs,true)
		draw_line(c+Vector2(s*.25,-s*.35),c+Vector2(s*.55,-s*.05),Color(INK,.85),.5*gs,true)
	elif kind==5: draw_polyline(quadratic(c+Vector2(-3,0)*gs,c+Vector2(-.75,-1.95)*gs,c+Vector2(2.6,-.22)*gs),Color(INK,.5),.55*gs,true)
	elif kind==6:
		for line in [[Vector2(-1.25,-1.25),Vector2(-.45,0)],[Vector2(0,-1.85),Vector2.ZERO],[Vector2(1.25,-1.25),Vector2(.45,0)]]:
			draw_line(c+line[0]*gs,c+line[1]*gs,Color(INK,.45),.45*gs,true)
