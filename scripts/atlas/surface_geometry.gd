extends RefCounted
## SphereGeometry helpers used by native environment generation. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Simplex = preload("res://scripts/atlas/simplex.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
var mesh: Dictionary
var radius: float
var ex := PackedFloat64Array(); var ey := PackedFloat64Array()
var sx := PackedFloat64Array(); var sy := PackedFloat64Array(); var sz := PackedFloat64Array()
var lengths := PackedFloat64Array()

func from_vector(qx: float,qy: float,qz: float) -> Array:
	var length := sqrt(qx*qx+qy*qy+qz*qz); var lon := Maths.round24(atan2(qy,qx))
	var lat := Maths.round24(asin(clampf(qz/length,-1,1))) if length>0 else 0.0
	var x: float = (lon+PI)/TAU*mesh.width
	if x>=mesh.width: x -= mesh.width
	elif x<0: x += mesh.width
	return [x,(PI/2-lat)/PI*mesh.height]

func point_frame(x: float,y: float) -> Dictionary:
	var lon: float = x/mesh.width*TAU-PI; var lat: float = PI/2-y/mesh.height*PI
	var slon := Maths.round24(sin(lon)); var clon := Maths.round24(cos(lon))
	var slat := Maths.round24(sin(lat)); var clat := Maths.round24(cos(lat))
	return {"x":clat*clon,"y":clat*slon,"z":slat,"slon":slon,"clon":clon,"slat":slat,"clat":clat}

func point_distance(ax: float,ay: float,bx: float,by: float) -> float:
	var a := point_frame(ax,ay); var b := point_frame(bx,by)
	var dx: float = a.x-b.x; var dy: float = a.y-b.y; var dz: float = a.z-b.z
	return radius*sqrt(dx*dx+dy*dy+dz*dz)

func point_dot(ax: float,ay: float,bx: float,by: float,ve: float,vs: float) -> float:
	var a := point_frame(ax,ay); var b := point_frame(bx,by)
	var dx: float = b.x-a.x; var dy: float = b.y-a.y; var dz: float = b.z-a.z
	var length := sqrt(dx*dx+dy*dy+dz*dz); if length==0: length = 1
	return (ve*(-a.slon*dx+a.clon*dy)+vs*(a.slat*a.clon*dx+a.slat*a.slon*dy-a.clat*dz))/length

func move_cell(i: int,e1: float,s1: float,e2: float = 0,s2: float = 0,e3: float = 0,s3: float = 0) -> Array:
	var e := e1+e2+e3; var s := s1+s2+s3; var length := sqrt(e*e+s*s)
	if length==0: return [mesh.x[i],mesh.y[i]]
	var ct := Maths.round24(cos(length/radius)); var st := Maths.round24(sin(length/radius))/length
	return from_vector(mesh.xyz[3*i]*ct+(e*ex[i]+s*sx[i])*st,mesh.xyz[3*i+1]*ct+(e*ey[i]+s*sy[i])*st,mesh.xyz[3*i+2]*ct+s*sz[i]*st)

func nearest(x: float,y: float,hint: int) -> int:
	var p := point_frame(x,y); var c := clampi(hint,0,mesh.n-1)
	var bd := point_distance_squared(c,p)
	# Delaunay neighbor descent reaches the nearest point; use strict source tie rule.
	while true:
		var next := -1
		for k in range(mesh.adj_start[c],mesh.adj_start[c+1]):
			var j: int = mesh.adj[k]; var d := point_distance_squared(j,p)
			if d<bd: bd = d; next = j
		if next<0: return c
		c = next
	return c

func point_distance_squared(i: int,p: Dictionary) -> float:
	var dx: float = mesh.xyz[3*i]-p.x; var dy: float = mesh.xyz[3*i+1]-p.y; var dz: float = mesh.xyz[3*i+2]-p.z
	return dx*dx+dy*dy+dz*dz

func near_to(i: int,x: float,y: float,reach: float) -> float:
	var d2 := point_distance_squared(i,point_frame(x,y)); var unit := absf(reach)/radius
	return radius*sqrt(d2) if d2<=unit*unit else -1.0

func cells_near_point(x: float,y: float,reach: float) -> PackedInt32Array:
	var p := point_frame(x,y); var unit := absf(reach)/radius; var out := PackedInt32Array()
	for i in range(mesh.n):
		if point_distance_squared(i,p)<=unit*unit: out.append(i)
	return out

func group_centroids(groups: PackedInt32Array,count: int,size_values: PackedFloat32Array) -> Dictionary:
	var sum_values := PackedFloat64Array(); sum_values.resize(3*count)
	for i in range(mesh.n):
		for axis in range(3): sum_values[3*groups[i]+axis] += mesh.xyz[3*i+axis]
	var x := PackedFloat32Array(); x.resize(count); var y := x.duplicate()
	for k in range(count):
		if size_values[k]<=0 or sum_values[3*k]*sum_values[3*k]+sum_values[3*k+1]*sum_values[3*k+1]+sum_values[3*k+2]*sum_values[3*k+2]==0: continue
		var p := from_vector(sum_values[3*k],sum_values[3*k+1],sum_values[3*k+2]); x[k] = p[0]; y[k] = p[1]
	return {"x":x,"y":y}

func plate_motion(vx: PackedFloat32Array,vy: PackedFloat32Array,cx: PackedFloat32Array,cy: PackedFloat32Array,spin: PackedFloat32Array) -> PackedFloat32Array:
	var omega := PackedFloat32Array(); omega.resize(3*vx.size())
	for k in range(vx.size()):
		var a := point_frame(cx[k],cy[k])
		var tx: float = -a.slon*vx[k]+a.slat*a.clon*vy[k]; var ty: float = a.clon*vx[k]+a.slat*a.slon*vy[k]; var tz: float = -a.clat*vy[k]
		var sp := sqrt(vx[k]*vx[k]+vy[k]*vy[k])*spin[k]
		omega[3*k] = a.y*tz-a.z*ty+sp*a.x; omega[3*k+1] = a.z*tx-a.x*tz+sp*a.y; omega[3*k+2] = a.x*ty-a.y*tx+sp*a.z
	return omega

func motion_at(omega: PackedFloat32Array,k: int,i: int) -> Array:
	var wx := omega[3*k]; var wy := omega[3*k+1]; var wz := omega[3*k+2]
	var px: float = mesh.xyz[3*i]; var py: float = mesh.xyz[3*i+1]; var pz: float = mesh.xyz[3*i+2]
	var vx3 := wy*pz-wz*py; var vy3 := wz*px-wx*pz; var vz3 := wx*py-wy*px
	return [vx3*ex[i]+vy3*ey[i],vx3*sx[i]+vy3*sy[i]+vz3*sz[i]]

func _init(value: Dictionary) -> void:
	mesh = value; radius = float(mesh.width)/TAU
	for array in [ex,ey,sx,sy,sz]: array.resize(mesh.n)
	for i in range(mesh.n):
		var px: float = mesh.xyz[3*i]; var py: float = mesh.xyz[3*i+1]; var pz: float = mesh.xyz[3*i+2]
		var rho := sqrt(px*px+py*py)
		if rho<1e-12: ex[i] = 0; ey[i] = 1; sx[i] = 1 if pz>0 else -1; continue
		ex[i] = -py/rho; ey[i] = px/rho; sx[i] = pz*px/rho; sy[i] = pz*py/rho; sz[i] = -rho
	lengths.resize(mesh.adj.size())
	for i in range(mesh.n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]): lengths[k] = Sphere.distance(mesh,i,mesh.adj[k])

func latitude(i: int) -> float: return 90.0-180.0*mesh.y[i]/mesh.height

func edge_dot(i: int,j: int,ve: float,vs: float) -> float:
	var dx: float = mesh.xyz[3*j]-mesh.xyz[3*i]; var dy: float = mesh.xyz[3*j+1]-mesh.xyz[3*i+1]; var dz: float = mesh.xyz[3*j+2]-mesh.xyz[3*i+2]
	var length := sqrt(dx*dx+dy*dy+dz*dz)
	if length==0: length = 1
	return ((ve*ex[i]+vs*sx[i])*dx+(ve*ey[i]+vs*sy[i])*dy+vs*sz[i]*dz)/length

func wind_cuts(water: PackedByteArray) -> PackedFloat64Array:
	var counts := PackedFloat64Array(); counts.resize(6*256)
	for i in range(mesh.n):
		if water[i]==1: continue
		var band := mini(5,int(floor(mesh.y[i]*6.0/mesh.height))); var column := mini(255,int(floor(mesh.x[i]*256.0/mesh.width)))
		counts[band*256+column] += 1
	var cuts := PackedFloat64Array(); cuts.resize(6)
	for b in range(6):
		var best := 0; var best_value := INF
		for c in range(256):
			var value := 0.0
			for k in range(-12,13): value += counts[b*256+posmod(c+k,256)]
			if value<best_value: best_value = value; best = c
		cuts[b] = (best+.5)*mesh.width/256.0
	return cuts

func downwind(i: int,ve: float,vs: float,cuts: PackedFloat64Array) -> float:
	var x: float = mesh.x[i]-cuts[mini(5,int(floor(mesh.y[i]*6.0/mesh.height)))]
	if x<0: x += mesh.width
	return x*ve+mesh.y[i]*vs

static func blur(mesh_value: Dictionary,source: PackedFloat32Array,passes: int) -> PackedFloat32Array:
	var a := source.duplicate(); var b := a.duplicate()
	for _pass in range(passes):
		for i in range(mesh_value.n):
			var sum_value := float(a[i]); var count := 1
			for k in range(mesh_value.adj_start[i],mesh_value.adj_start[i+1]): sum_value += a[mesh_value.adj[k]]; count += 1
			b[i] = sum_value/count
		var temp := a; a = b; b = temp
	return a

class Surface:
	var xyz: PackedFloat32Array; var r: float; var mode: int; var octaves: int; var persistence: float
	var noise
	func _init(mesh_value: Dictionary,seed_value: int,kind: int,count: int,weight: float) -> void:
		xyz = mesh_value.xyz; r = float(mesh_value.width)/TAU; noise = Simplex.new(seed_value)
		mode = kind; octaves = count; persistence = weight
	func sample(x: float,y: float,z: float) -> float:
		if mode==1: return noise.fbm(x,y,z,octaves,persistence)
		if mode==2: return noise.ridged(x,y,z,octaves,persistence)
		return noise.at(x,y,z)
	func at(i: int,f: float,g: float = 1,ox: float = 0,oy: float = 0) -> float:
		var factor := f*r*g; return sample(xyz[3*i]*factor+ox,xyz[3*i+1]*factor+oy,xyz[3*i+2]*factor)
	func at_scale(i: int,scale_value: float,ox: float = 0,oy: float = 0) -> float:
		var factor := r/scale_value; return sample(xyz[3*i]*factor+ox,xyz[3*i+1]*factor+oy,xyz[3*i+2]*factor)
	func stretched(i: int,f: float,sy_value: float) -> float:
		var factor := f*r; return sample(xyz[3*i]*factor,xyz[3*i+1]*factor,xyz[3*i+2]*factor*sy_value)

func noise(seed_value: int): return Surface.new(mesh,seed_value,0,1,.5)
func fbm(seed_value: int,octaves: int,persistence: float = .5): return Surface.new(mesh,seed_value,1,octaves,persistence)
func ridged(seed_value: int,octaves: int,persistence: float = .5): return Surface.new(mesh,seed_value,2,octaves,persistence)

func zonal_land(land: PackedByteArray,grid: float) -> Dictionary:
	var gw := int(ceil(mesh.width/grid)); var gh := int(ceil(mesh.height/grid))
	var g_land := PackedByteArray(); g_land.resize(gw*gh)
	for i in range(mesh.n):
		if land[i]: g_land[mini(gh-1,int(floor(mesh.y[i]/grid)))*gw+mini(gw-1,int(floor(mesh.x[i]/grid)))] = 1
	var dw := PackedFloat32Array(); dw.resize(gw*gh); var de := dw.duplicate()
	for row in range(gh):
		var scale_value := Maths.round24(cos(PI/2.0-(row+.5)*grid/mesh.height*PI))*grid
		var last := -1e9
		for c in range(2*gw):
			var cc := c%gw
			if g_land[row*gw+cc]: last = c
			if c>=gw: dw[row*gw+cc] = (c-last)*scale_value
		last = 1e9
		for c in range(2*gw-1,-1,-1):
			var cc := c%gw
			if g_land[row*gw+cc]: last = c
			if c<gw: de[row*gw+cc] = (last-c)*scale_value
	var west := PackedFloat32Array(); west.resize(mesh.n); var east := west.duplicate()
	for i in range(mesh.n):
		var g := mini(gh-1,int(floor(mesh.y[i]/grid)))*gw+mini(gw-1,int(floor(mesh.x[i]/grid)))
		west[i] = dw[g]; east[i] = de[g]
	return {"west":west,"east":east}
