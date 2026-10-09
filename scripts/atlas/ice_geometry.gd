extends RefCounted
## Original oriented marching squares / iceCross / chaikinLoop, fantasy.ts.
## 103afd3, AGPL-3.0-only. Ice is environmental; no routes are generated.
const Contours = preload("res://scripts/atlas/contours.gd")
const Fields = preload("res://scripts/atlas/paint_fields.gd")
const Zoom = preload("res://scripts/atlas/zoom_geometry.gd")
var raster: Dictionary
var w: int
var h: int
var mask: PackedByteArray
var seen := PackedByteArray()
var exits: Array = []
var cross_cache := {}
func _init(r: Dictionary,m: PackedByteArray) -> void:
	raster = r; w = r.w; h = r.h; mask = m; seen.resize(2*w*(h+2))
	var mid: Array = [[.5,0.],[1.,.5],[.5,1.],[0.,.5]]; var corner: Array = [[0.,0.],[1.,0.],[1.,1.],[0.,1.]]; var bits := [8,4,2,1]; var ends := [[0,1],[1,2],[3,2],[0,3]]
	for c in range(16):
		var row: Array = [-1,-1,-1,-1]
		for a in range(4):
			var b: int = Contours.EXIT[c][a]
			if b<a: continue
			var ca: int = ends[a][0 if c&bits[ends[a][0]] else 1]; var dx: float = mid[b][0]-mid[a][0]; var dy: float = mid[b][1]-mid[a][1]
			if (corner[ca][0]-mid[a][0])*dy-(corner[ca][1]-mid[a][1])*dx>0: row[a] = b
			else: row[b] = a
		exits.append(row)
func at(x: int,row: int) -> int: return 0 if row==0 or row==h+1 else mask[(row-1)*w+x]
func case_at(x: int,row: int) -> int: return (at(x,row)<<3)|(at((x+1)%w,row)<<2)|(at((x+1)%w,row+1)<<1)|at(x,row+1)
func edge(x: int,row: int,side: int) -> int: return (row*w+x)*2 if side==0 else ((row+1)*w+x)*2 if side==2 else (row*w+x)*2+1 if side==3 else (row*w+(x+1)%w)*2+1
func field(k: int) -> float:
	if cross_cache.has(k): return cross_cache[k]
	var x := k%w; var y := k/w; var total := 0; var count := 0
	for dy in range(-1,2):
		if y+dy<0 or y+dy>=h: continue
		for dx in range(-1,2):
			var q := (y+dy)*w+posmod(x+dx,w)
			if raster.water[q]!=1: continue
			total += mask[q]; count += 1
	var value := (mask[k]+(total/float(count) if count else float(mask[k])))/2; cross_cache[k] = value; return value
func add(id: int,pts: Array,kinds: Array) -> void:
	var e := id>>1; var x := e%w; var row := (e-x)/w; var vertical := id&1; var rb := row+1 if vertical else row; var t := .5; var kind := 0
	if row>0 and row<h+1 and rb>0 and rb<h+1:
		var a := (row-1)*w+x; var b := a+w if vertical else (row-1)*w+(x+1)%w
		if raster.water[a]==1 and raster.water[b]==1: t = clampf((.5-field(a))/(field(b)-field(a)),.02,.98)
		kind = 1 if raster.water[b if mask[a] else a]==1 else 2
	pts.append(x+.5 if vertical else x+.5+t); pts.append(row-.5+t if vertical else row-.5); kinds.append(kind)
func walk(x: int,row: int,side: int) -> Dictionary:
	var pts: Array = []; var kinds: Array = []; var start := edge(x,row,side); seen[start] = 1; add(start,pts,kinds)
	for _guard in range(seen.size()):
		var ex: int = exits[case_at(x,row)][side]
		if ex<0: break
		var e := edge(x,row,ex)
		if e==start: break
		seen[e] = 1; add(e,pts,kinds)
		if ex==0: row -= 1; side = 2
		elif ex==2: row += 1; side = 0
		elif ex==1: x = (x+1)%w; side = 3
		else: x = posmod(x-1,w); side = 1
	for i in range(2,pts.size(),2): pts[i] -= w*floor((pts[i]-pts[i-2])/w+.5)
	var back: float = pts[0]-w*floor((pts[0]-pts[-2])/w+.5); var wrap := roundi((back-pts[0])/w); var ink := PackedByteArray(); ink.resize(kinds.size())
	for i in range(kinds.size()): ink[i] = int(kinds[i]==1 or kinds[(i+1)%kinds.size()]==1)
	var p := PackedFloat32Array(pts)
	for _pass in range(2):
		if ink.size()<3: break
		var out := PackedFloat32Array(); out.resize(p.size()*2); var flags := PackedByteArray(); flags.resize(ink.size()*2)
		for i in range(ink.size()):
			var j := (i+1)%ink.size(); var bx: float = p[j*2]+(wrap*w if j==0 else 0)
			out[i*4] = .75*p[i*2]+.25*bx; out[i*4+1] = .75*p[i*2+1]+.25*p[j*2+1]; out[i*4+2] = .25*p[i*2]+.75*bx; out[i*4+3] = .25*p[i*2+1]+.75*p[j*2+1]; flags[i*2] = ink[i]; flags[i*2+1] = ink[i]|ink[j]
		p = out; ink = flags
	return {"pts":p,"ink":ink,"wrap":wrap}
func lines() -> Array:
	var out: Array = []
	for row in range(h+1):
		for x in range(w):
			var c := case_at(x,row)
			if c==0 or c==15: continue
			for side in range(4):
				if exits[c][side]>=0 and not seen[edge(x,row,side)]: out.append(walk(x,row,side))
	return out
static func build(r: Dictionary) -> Dictionary:
	var m: PackedByteArray = Fields.ice_field(r).mask
	var planner = load("res://scripts/atlas/ice_geometry.gd").new(r,m); var lines: Array = planner.lines(); var borders: Array = []
	for line in lines:
		var p: PackedFloat32Array = line.pts.duplicate(); p.append(p[0]+line.wrap*r.w); p.append(p[1])
		borders.append({"pts":p,"left":0,"right":1,"closed":line.wrap==0})
	return {"lines":lines,"textures":Zoom.textures(Zoom.build(borders,4.,r.w,r.h))}
