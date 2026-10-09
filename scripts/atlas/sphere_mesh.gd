extends RefCounted
## civ-atlas 103afd3 geometry.ts sphere Poisson / stereographic Delaunay.
## AGPL-3.0-only. Scalar doubles avoid Vector3's premature Float32 rounding.
const Maths = preload("res://scripts/atlas/math.gd")
const Triangulation = preload("res://scripts/atlas/delaunator.gd")
const WIDTH := 2048.0
const HEIGHT := 1024.0

static func near_x(x: float,reference: float,width: float) -> float:
	return x-width*floor((x-reference)/width+0.5)

static func sphere_mean(mesh: Dictionary,a: int,b: int,c: int = -1) -> Array:
	var p: PackedFloat32Array = mesh.xyz
	var sx := p[3*a]+p[3*b]; var sy := p[3*a+1]+p[3*b+1]; var sz := p[3*a+2]+p[3*b+2]
	if c>=0: sx += p[3*c]; sy += p[3*c+1]; sz += p[3*c+2]
	var length := sqrt(sx*sx+sy*sy+sz*sz)
	if length==0: length = 1
	var x: float = ((atan2(sy,sx)+PI)/TAU)*mesh.width
	if x>=mesh.width: x -= mesh.width
	return [x,((PI/2-asin(clampf(sz/length,-1,1)))/PI)*mesh.height]

static func build(seed_value: int, cells: int = 36000) -> Dictionary:
	var radius := WIDTH / TAU
	var spacing := sqrt((4.0*PI*radius*radius*0.66)/float(cells))
	var xyz := PackedFloat32Array(Array(poisson(spacing/radius,Maths.Stream.new(Maths.sub_seed(seed_value,"mesh")))))
	var n := xyz.size()/3
	var x := PackedFloat32Array(); x.resize(n)
	var y := PackedFloat32Array(); y.resize(n)
	for i in range(n):
		var longitude := Maths.round24(atan2(xyz[3*i+1],xyz[3*i]))
		var latitude := Maths.round24(asin(clampf(xyz[3*i+2],-1.0,1.0)))
		var fx := Maths.f32(((longitude+PI)/TAU)*WIDTH)
		x[i] = 0.0 if fx >= WIDTH else fx
		y[i] = ((PI/2.0-latitude)/PI)*HEIGHT
	var spherical := triangulate(xyz)
	var raw: PackedInt32Array = spherical.triangles
	var triangles := PackedInt32Array()
	for wrapped in [true,false]:
		for t in range(0,raw.size(),3):
			var span := maxf(x[raw[t]],maxf(x[raw[t+1]],x[raw[t+2]]))-minf(x[raw[t]],minf(x[raw[t+1]],x[raw[t+2]]))
			if (span > WIDTH/2.0) != wrapped: continue
			triangles.append(raw[t]); triangles.append(raw[t+1]); triangles.append(raw[t+2])
	var mesh := {"n":n,"width":WIDTH,"height":HEIGHT,"spacing":spacing,"xyz":xyz,"x":x,"y":y,
		"triangles":triangles,"adj_start":spherical.adj_start,"adj":spherical.adj}
	mesh.lengths = edge_lengths(mesh)
	mesh.areas = cell_areas(mesh)
	return mesh

static func poisson(r: float, rng) -> PackedFloat64Array:
	var r2 := r*r; var reach2 := (3.01*r)*(3.01*r); var grid := 3.02*r
	var xyz := PackedFloat64Array(); var active := PackedInt32Array(); var buckets := {}
	var z0: float = 2.0*rng.next()-1.0; var a0: float = TAU*rng.next()
	var q0 := sqrt(maxf(0.0,1.0-z0*z0))
	put(xyz,buckets,grid,q0*Maths.round24(cos(a0)),q0*Maths.round24(sin(a0)),z0)
	active.append(0)
	while not active.is_empty():
		var ai: int = floori(rng.next()*active.size()); var p := active[ai]
		var px := xyz[3*p]; var py := xyz[3*p+1]; var pz := xyz[3*p+2]
		var ux := -py; var uy := px; var uz := 0.0
		if absf(pz) > 0.9: ux = 0.0; uy = -pz; uz = py
		var length := sqrt(ux*ux+uy*uy+uz*uz)
		ux /= length; uy /= length; uz /= length
		var vx := py*uz-pz*uy; var vy := pz*ux-px*uz; var vz := px*uy-py*ux
		var near := PackedFloat64Array()
		var gx := floori((px+1.0)/grid); var gy := floori((py+1.0)/grid); var gz := floori((pz+1.0)/grid)
		for a in range(gx-1,gx+2):
			for b in range(gy-1,gy+2):
				for c in range(gz-1,gz+2):
					var ids: Array = buckets.get(Vector3i(a,b,c),[])
					for id in ids:
						var x := xyz[3*id]; var y := xyz[3*id+1]; var z := xyz[3*id+2]
						if (x-px)*(x-px)+(y-py)*(y-py)+(z-pz)*(z-pz) <= reach2:
							near.append(x); near.append(y); near.append(z)
		var placed := false
		for _k in range(24):
			var angle: float = rng.next()*TAU; var d: float = r*(1.0+rng.next())
			var ca := Maths.round24(cos(angle)); var sa := Maths.round24(sin(angle))
			var x := px+d*(ca*ux+sa*vx); var y := py+d*(ca*uy+sa*vy); var z := pz+d*(ca*uz+sa*vz)
			length = sqrt(x*x+y*y+z*z); x /= length; y /= length; z /= length
			var far := true
			for i in range(0,near.size(),3):
				var dx := near[i]-x; var dy := near[i+1]-y; var dz := near[i+2]-z
				if dx*dx+dy*dy+dz*dz < r2: far = false; break
			if not far: continue
			active.append(put(xyz,buckets,grid,x,y,z))
			near.append(x); near.append(y); near.append(z); placed = true
		if not placed:
			active[ai] = active[-1]; active.resize(active.size()-1)
	return xyz

static func put(xyz: PackedFloat64Array,buckets: Dictionary,grid: float,x: float,y: float,z: float) -> int:
	var id := xyz.size()/3
	xyz.append(x); xyz.append(y); xyz.append(z)
	var key := Vector3i(floori((x+1.0)/grid),floori((y+1.0)/grid),floori((z+1.0)/grid))
	if not buckets.has(key): buckets[key] = []
	buckets[key].push_front(id)
	return id

static func triangulate(xyz: PackedFloat32Array) -> Dictionary:
	var n := xyz.size()/3; var p0 := 0
	for i in range(1,n):
		if xyz[3*i+2] < xyz[3*p0+2]: p0 = i
	var vx := xyz[3*p0]; var vy := xyz[3*p0+1]; var vz := xyz[3*p0+2]
	var kx := -vy; var ky := vx; var sn := sqrt(kx*kx+ky*ky); var cs := -vz
	if sn > 1e-12: kx /= sn; ky /= sn
	var coords := PackedFloat64Array(); var back := PackedInt32Array(); var local := PackedInt32Array(); local.resize(n); local.fill(-1)
	for i in range(n):
		if i == p0: continue
		var x := xyz[3*i]; var y := xyz[3*i+1]; var z := xyz[3*i+2]
		var qx := x; var qy := y; var qz := z
		if sn > 1e-12:
			var kdp := kx*x+ky*y
			qx = x*cs+ky*z*sn+kx*kdp*(1.0-cs)
			qy = y*cs-kx*z*sn+ky*kdp*(1.0-cs)
			qz = z*cs+(kx*y-ky*x)*sn
		elif cs < 0.0: qy = -y; qz = -z
		coords.append(qx/(1.0+qz)); coords.append(qy/(1.0+qz)); local[i] = back.size(); back.append(i)
	var del := Triangulation.new(); del.build(coords)
	var triangles := PackedInt32Array()
	for index in del.triangles: triangles.append(back[index])
	for h in range(del.hull.size()):
		triangles.append(back[del.hull[h]]); triangles.append(back[del.hull[(h+1)%del.hull.size()]]); triangles.append(p0)
	var inedges := PackedInt32Array(); inedges.resize(n-1); inedges.fill(-1)
	for e in range(del.halfedges.size()):
		var point: int = del.triangles[e-2 if e%3 == 2 else e+1]
		if del.halfedges[e] == -1 or inedges[point] == -1: inedges[point] = e
	var hull_index := PackedInt32Array(); hull_index.resize(n-1); hull_index.fill(-1)
	for h in range(del.hull.size()): hull_index[del.hull[h]] = h
	var adj_start := PackedInt32Array(); var adj := PackedInt32Array()
	for i in range(n):
		adj_start.append(adj.size())
		if i == p0:
			for id in del.hull: adj.append(back[id])
			continue
		var li := local[i]; var e0 := inedges[li]; var e := e0
		if e0 != -1:
			while true:
				var q: int = del.triangles[e]; adj.append(back[q])
				e = e-2 if e%3 == 2 else e+1
				if del.triangles[e] != li: break
				e = del.halfedges[e]
				if e == -1:
					var h: int = del.hull[(hull_index[li]+1)%del.hull.size()]
					if h != q: adj.append(back[h])
					break
				if e == e0: break
		if hull_index[li] >= 0: adj.append(p0)
	adj_start.append(adj.size())
	return {"triangles":triangles,"adj_start":adj_start,"adj":adj}

static func distance(mesh: Dictionary,i: int,j: int) -> float:
	var p: PackedFloat32Array = mesh.xyz
	var a := 3*i; var b := 3*j
	var dx := p[a]-p[b]; var dy := p[a+1]-p[b+1]; var dz := p[a+2]-p[b+2]
	return WIDTH/TAU*sqrt(dx*dx+dy*dy+dz*dz)

static func edge_lengths(mesh: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(mesh.adj.size())
	for i in range(mesh.n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]): out[k] = distance(mesh,i,mesh.adj[k])
	return out

static func cell_areas(mesh: Dictionary) -> PackedFloat32Array:
	var p: PackedFloat32Array = mesh.xyz; var tris: PackedInt32Array = mesh.triangles
	var out := PackedFloat32Array(); out.resize(mesh.n)
	var r2 := (WIDTH/TAU)*(WIDTH/TAU)
	for t in range(0,tris.size(),3):
		var a := 3*tris[t]; var b := 3*tris[t+1]; var c := 3*tris[t+2]
		var ax := p[a]; var ay := p[a+1]; var az := p[a+2]
		var bx := p[b]; var by := p[b+1]; var bz := p[b+2]
		var cx := p[c]; var cy := p[c+1]; var cz := p[c+2]
		var triple := ax*(by*cz-bz*cy)+ay*(bz*cx-bx*cz)+az*(bx*cy-by*cx)
		var denom := 1.0+ax*bx+ay*by+az*bz+bx*cx+by*cy+bz*cz+cx*ax+cy*ay+cz*az
		var area := (2.0*Maths.round24(atan2(absf(triple),denom))*r2)/3.0
		for id in [tris[t],tris[t+1],tris[t+2]]: out[id] += area
	return out
