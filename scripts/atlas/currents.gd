extends RefCounted
## civ-atlas gen/currents.ts. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Geometry = preload("res://scripts/atlas/surface_geometry.gd")
const Climate = preload("res://scripts/atlas/climate.gd")
const WEST = [0,1.5,10,2.5,20,4,35,4,42,0,50,-5,62,-5,75,-2,90,0]
const EAST = [0,-3,8,-3.5,15,-6,28,-6,36,-3,42,0,48,5,56,8,66,7,76,3,90,0]

static func reach(d: float,r: float) -> float:
	if d>=r: return 0
	var t := 1-d/r; return t*t

static func gyre(a: float) -> float:
	if a<46: return Maths.round24(sin(PI*a/46.0))
	if a<72: return -.7*Maths.round24(sin(PI*(a-46.0)/26.0))
	return 0

static func build(mesh: Dictionary,water: PackedByteArray) -> Dictionary:
	var n: int = mesh.n; var geo := Geometry.new(mesh)
	var comp := PackedInt32Array(); comp.resize(n); comp.fill(-1); var big := PackedByteArray(); big.resize(n)
	var stack: Array[int] = []
	for s in range(n):
		if water[s]==1 or comp[s]>=0: continue
		var cells: Array[int] = []; comp[s] = s; stack.append(s)
		while not stack.is_empty():
			var c: int = stack.pop_back(); cells.append(c)
			for k in range(mesh.adj_start[c],mesh.adj_start[c+1]):
				var j: int = mesh.adj[k]
				if water[j]!=1 and comp[j]<0: comp[j] = s; stack.append(j)
		if cells.size()>=.002*n:
			for c in cells: big[c] = 1
	var zonal := geo.zonal_land(big,4); var sst := PackedFloat32Array(); sst.resize(n); var psi := sst.duplicate()
	for i in range(n):
		var lat := geo.latitude(i); var dw: float = zonal.west[i]*(40000.0/2048); var de: float = zonal.east[i]*(40000.0/2048)
		if not big[i]:
			var basin := dw+de; var shape := 0.0
			if basin>1e7: shape = 1
			elif basin>0: shape = (1-Maths.fexp(-dw/300.0))*de/basin*Maths.smoothstep(1000,3500,basin)
			psi[i] = (1 if lat>=0 else -1)*gyre(absf(lat))*shape
		if water[i]!=1: continue
		var wide := Maths.smoothstep(1000,3500,dw+de)
		if wide==0: continue
		var pw := Climate.piecewise(WEST,absf(lat)); var pe := Climate.piecewise(EAST,absf(lat))
		sst[i] = wide*pw*reach(dw,1500 if pw>0 else 1300)+wide*pe*reach(de,2200 if pe>0 else 1500)
	var sea := PackedFloat32Array(); sea.resize(n)
	for i in range(n): sea[i] = 1 if water[i]==1 else 0
	var num := Geometry.blur(mesh,sst,2); var den := Geometry.blur(mesh,sea,2)
	for i in range(n): sst[i] = num[i]/den[i] if water[i]==1 and den[i]>0 else 0
	var ps := Geometry.blur(mesh,psi,2); var u := sea.duplicate(); u.fill(0); var v := u.duplicate()
	for i in range(n):
		if water[i]!=1: continue
		var co := Maths.round24(cos(geo.latitude(i)*PI/180.0))
		var sxx := 0.0; var sxy := 0.0; var syy := 0.0; var sxp := 0.0; var syp := 0.0
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]; var dx: float = mesh.x[j]-mesh.x[i]; dx -= mesh.width*floor(dx/mesh.width+.5)
			var de := dx*co; var dn: float = mesh.y[i]-mesh.y[j]; var dp := ps[j]-ps[i]
			sxx += de*de; sxy += de*dn; syy += dn*dn; sxp += de*dp; syp += dn*dp
		var det := sxx*syy-sxy*sxy
		if absf(det)<1e-9: continue
		u[i] = -(syp*sxx-sxp*sxy)/det/.02; v[i] = -(sxp*syy-syp*sxy)/det/.02
	return {"sst":sst,"u":u,"v":v}
