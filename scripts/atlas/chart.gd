extends RefCounted
## Original SphereChart / SphereMapChart; scalar doubles avoid Vector2 rounding.
## civ-atlas gen/geometry.ts 103afd3. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
var geo: RefCounted
var center: int
var map_chart := false
var x0: float
var y0: float
var kx: float
var ky: float
var cache := {}
func _init(g: RefCounted,c: int = 0,px: float = NAN,py: float = NAN) -> void:
	geo = g; center = c; map_chart = not is_nan(px)
	x0 = px if map_chart else float(geo.mesh.x[c]); y0 = py if map_chart else float(geo.mesh.y[c])
	kx = maxf(.1,Maths.round24(cos(PI/2-y0/geo.mesh.height*PI))); ky = geo.mesh.width/(2.*geo.mesh.height)
func project(qx: float,qy: float,qz: float) -> Array:
	var p: Variant = geo.mesh.xyz; var i := center
	var qe: float = qx*geo.ex[i]+qy*geo.ey[i]
	var qs: float = qx*geo.sx[i]+qy*geo.sy[i]+qz*geo.sz[i]
	var qc: float = qx*p[3*i]+qy*p[3*i+1]+qz*p[3*i+2]; var t := sqrt(qe*qe+qs*qs)
	if t<1e-15: return [0.,0.]
	var k: float = geo.radius*Maths.round24(atan2(t,qc))/t
	return [qe*k,qs*k]
func uv(cell: int) -> Array:
	if map_chart: return to_uv(geo.mesh.x[cell],geo.mesh.y[cell])
	if not cache.has(cell): cache[cell] = project(geo.mesh.xyz[3*cell],geo.mesh.xyz[3*cell+1],geo.mesh.xyz[3*cell+2])
	return cache[cell]
func u(cell: int) -> float: return uv(cell)[0]
func v(cell: int) -> float: return uv(cell)[1]
func to_uv(x: float,y: float) -> Array:
	if map_chart:
		var d := x-x0
		if d>geo.mesh.width/2: d -= geo.mesh.width
		elif d< -geo.mesh.width/2: d += geo.mesh.width
		return [d*kx,(y-y0)*ky]
	var q: Dictionary = geo.point_frame(x,y); return project(q.x,q.y,q.z)
func to_xy(e: float,s: float) -> Array:
	if map_chart: return [x0+e/kx,clampf(y0+s/ky,0,geo.mesh.height)]
	var result: Array = geo.move_cell(center,e,s)
	if result[0]-x0>geo.mesh.width/2: result[0] -= geo.mesh.width
	elif x0-result[0]>geo.mesh.width/2: result[0] += geo.mesh.width
	return result
static func weighted(g: RefCounted,cells: Array,weight: Callable) -> RefCounted:
	var sx := 0.; var sy := 0.; var sz := 0.
	for c in cells:
		var w: float = weight.call(c); sx += w*g.mesh.xyz[3*c]; sy += w*g.mesh.xyz[3*c+1]; sz += w*g.mesh.xyz[3*c+2]
	var length := sqrt(sx*sx+sy*sy+sz*sz); var anchor: int = cells[0] if not cells.is_empty() else 0
	if length>0 and not cells.is_empty():
		var pos: Array = g.from_vector(sx,sy,sz); anchor = g.nearest(pos[0],pos[1],anchor)
	return load("res://scripts/atlas/chart.gd").new(g,anchor)
