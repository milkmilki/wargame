extends RefCounted
## Original fantasy.ts traceMask, elevCross and chaikinPts (103afd3).
## Marching squares wraps horizontally and leaves pole endpoints open. AGPL-3.0-only.
const EXIT = [[-1,-1,-1,-1],[-1,-1,3,2],[-1,2,1,-1],[-1,3,-1,1],[1,0,-1,-1],[1,0,3,2],[2,-1,0,-1],[3,-1,-1,0],[3,-1,-1,0],[2,-1,0,-1],[3,2,1,0],[1,0,-1,-1],[-1,3,-1,1],[-1,2,1,-1],[-1,-1,3,2],[-1,-1,-1,-1]]
var w: int
var h: int
var mask: PackedByteArray
var cross: Callable
var seen := PackedByteArray()
var lines: Array = []
func _init(width: int,height: int,inside: PackedByteArray,interpolate: Callable) -> void:
	w = width; h = height; mask = inside; cross = interpolate; seen.resize(2*w*h)
static func trace(width: int,height: int,inside: PackedByteArray,interpolate: Callable = Callable()) -> Array:
	return load("res://scripts/atlas/contours.gd").new(width,height,inside,interpolate).run()
static func elevation_cross(elev: Variant,a: int,b: int) -> float:
	var ea: float = elev[a]; var eb: float = elev[b]
	return clampf(ea/(ea-eb),.02,.98) if (ea<0)!=(eb<0) and ea!=eb else .5
func case_at(x: int,y: int) -> int:
	var x1 := (x+1)%w; return (mask[y*w+x]<<3)|(mask[y*w+x1]<<2)|(mask[(y+1)*w+x1]<<1)|mask[(y+1)*w+x]
func edge_of(x: int,y: int,side: int) -> int: return (y*w+x)*2 if side==0 else ((y+1)*w+x)*2 if side==2 else (y*w+x)*2+1 if side==3 else (y*w+(x+1)%w)*2+1
func pos(id: int,out: Array) -> void:
	var e := id>>1; var x := e%w; var y := (e-x)/w; var vertical := id&1; var a := y*w+x; var b := a+w if vertical else y*w+(x+1)%w; var t: float = cross.call(a,b) if cross.is_valid() else .5
	out.append(x+.5 if vertical else x+.5+t); out.append(y+.5+t if vertical else y+.5)
func walk(id: int,x: int,y: int,side: int) -> void:
	var pts: Array = []; pos(id,pts); seen[id] = 1; var start := id
	while true:
		var ex: int = EXIT[case_at(x,y)][side]
		if ex<0: break
		var e := edge_of(x,y,ex)
		if e==start: pos(e,pts); break
		if seen[e]: break
		seen[e] = 1; pos(e,pts)
		if ex==0:
			if y==0: break
			y -= 1; side = 2
		elif ex==2:
			if y+1>=h-1: break
			y += 1; side = 0
		elif ex==1: x = (x+1)%w; side = 3
		else: x = posmod(x-1,w); side = 1
	for i in range(2,pts.size(),2):
		if pts[i]-pts[i-2]>w/2.: pts[i] -= w
		elif pts[i-2]-pts[i]>w/2.: pts[i] += w
	if pts.size()>=4: lines.append(PackedFloat32Array(pts))
func run() -> Array:
	for y in [0,h-1]:
		for x in range(w):
			var k: int = y*w+x; var id := k*2
			if seen[id] or mask[k]==mask[y*w+(x+1)%w]: continue
			walk(id,x,0 if y==0 else h-2,0 if y==0 else 2)
	for y in range(h-1):
		for x in range(w):
			var k := y*w+x
			if not seen[k*2] and mask[k]!=mask[y*w+(x+1)%w]: walk(k*2,x,y,0)
			if not seen[k*2+1] and mask[k]!=mask[k+w]: walk(k*2+1,x,y,3)
	return lines
static func chaikin(p: PackedFloat32Array) -> PackedFloat32Array:
	if p.size()<6: return p
	var closed := p[0]==p[-2] and p[1]==p[-1]; var out: Array = []
	if not closed: out.append(p[0]); out.append(p[1])
	for i in range(0,p.size()-2,2): out.append_array([.75*p[i]+.25*p[i+2],.75*p[i+1]+.25*p[i+3],.25*p[i]+.75*p[i+2],.25*p[i+1]+.75*p[i+3]])
	if closed: out.append(out[0]); out.append(out[1])
	else: out.append(p[-2]); out.append(p[-1])
	return PackedFloat32Array(out)
