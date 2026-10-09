extends RefCounted
## civ-atlas raster.ts sphereGrid/sphereCover/arcZ. AGPL-3.0-only.
## Volumetric spherical barycentrics; no alternate projection triangulation.
static func grid(w: int,h: int) -> Dictionary:
	var cl := PackedFloat32Array(); cl.resize(w); var sl := cl.duplicate()
	var ct := PackedFloat32Array(); ct.resize(h); var st := ct.duplicate()
	for x in range(w):
		var lon := (x+.5)/w*2*PI-PI; cl[x] = cos(lon); sl[x] = sin(lon)
	for y in range(h):
		var lat := PI/2-(y+.5)/h*PI; ct[y] = cos(lat); st[y] = sin(lat)
	return {"w":w,"h":h,"cosLon":cl,"sinLon":sl,"cosLat":ct,"sinLat":st}

static func arc_z(p: Array,q: Array,n: Array,ext: Array) -> void:
	var nn: float = n[0]*n[0]+n[1]*n[1]+n[2]*n[2]
	if nn<=0: return
	var t2: float = n[2]*n[2]/nn
	if t2>=1: return
	var mx: float = -n[2]*n[0]; var my: float = -n[2]*n[1]; var mz: float = nn-n[2]*n[2]
	var s1: float = (p[1]*mz-p[2]*my)*n[0]+(p[2]*mx-p[0]*mz)*n[1]+(p[0]*my-p[1]*mx)*n[2]
	var s2: float = (my*q[2]-mz*q[1])*n[0]+(mz*q[0]-mx*q[2])*n[1]+(mx*q[1]-my*q[0])*n[2]
	var top := sqrt(1-t2)
	if s1>=0 and s2>=0 and top>ext[0]: ext[0] = top
	if s1<=0 and s2<=0 and -top<ext[1]: ext[1] = -top

static func cross(a: Array,b: Array) -> Array:
	return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]

static func to_y(z: float,h: int) -> float: return (PI/2-asin(clampf(z,-1,1)))/PI*h-.5
static func to_x(lon: float,w: int) -> float: return (lon+PI)/TAU*w-.5

static func build(mesh: Dictionary,w: int,h: int) -> Dictionary:
	var g := grid(w,h); var xyz: PackedFloat32Array = mesh.xyz; var triangles: PackedInt32Array = mesh.triangles
	var tri := PackedInt32Array(); tri.resize(w*h); var wa := PackedFloat32Array(); wa.resize(w*h); var wb := wa.duplicate()
	for t in range(triangles.size()/3):
		var a := triangles[3*t]; var b := triangles[3*t+1]; var c := triangles[3*t+2]
		var pa := [xyz[3*a],xyz[3*a+1],xyz[3*a+2]]; var pb := [xyz[3*b],xyz[3*b+1],xyz[3*b+2]]; var pc := [xyz[3*c],xyz[3*c+1],xyz[3*c+2]]
		var n1 := cross(pa,pb); var n2 := cross(pb,pc); var n3 := cross(pc,pa)
		var volume: float = pa[0]*n2[0]+pa[1]*n2[1]+pa[2]*n2[2]
		if volume==0: continue
		var ext := [maxf(pa[2],maxf(pb[2],pc[2])),minf(pa[2],minf(pb[2],pc[2]))]
		arc_z(pa,pb,n1,ext); arc_z(pb,pc,n2,ext); arc_z(pc,pa,n3,ext)
		if volume<0:
			for axis in range(3): n1[axis] = -n1[axis]; n2[axis] = -n2[axis]; n3[axis] = -n3[axis]
		var north: bool = n1[2]>=0 and n2[2]>=0 and n3[2]>=0; var south: bool = n1[2]<=0 and n2[2]<=0 and n3[2]<=0
		var y0 := 0 if north else maxi(0,int(ceil(to_y(ext[0],h)))-1)
		var y1 := h-1 if south else mini(h-1,int(floor(to_y(ext[1],h)))+1)
		var x0 := 0; var x1 := w-1
		if not north and not south and maxf(absf(pa[2]),maxf(absf(pb[2]),absf(pc[2])))<.999:
			var lon := [atan2(pa[1],pa[0]),atan2(pb[1],pb[0]),atan2(pc[1],pc[0])]; lon.sort()
			var gap1: float = lon[1]-lon[0]; var gap2: float = lon[2]-lon[1]; var gap3: float = lon[0]+TAU-lon[2]
			var largest := maxf(gap1,maxf(gap2,gap3))
			if largest>PI*1.1:
				var lo: float = lon[0] if gap3==largest else lon[1] if gap1==largest else lon[2]
				var hi: float = lon[2] if gap3==largest else lon[0]+TAU if gap1==largest else lon[1]+TAU
				var xa := int(ceil(to_x(lo,w)))-1; var xb := int(floor(to_x(hi,w)))+1
				if xb-xa<w: x0 = xa; x1 = xb
		for y in range(y0,y1+1):
			var cl: float = g.cosLat[y]; var sl: float = g.sinLat[y]
			var e1: float = n1[2]*sl; var e2: float = n2[2]*sl; var e3: float = n3[2]*sl; var row := y*w
			for xx in range(x0,x1+1):
				var x := posmod(xx,w); var qx: float = cl*g.cosLon[x]; var qy: float = cl*g.sinLon[x]
				var dc: float = n1[0]*qx+n1[1]*qy+e1
				if dc<0: continue
				var da: float = n2[0]*qx+n2[1]*qy+e2
				if da<0: continue
				var db: float = n3[0]*qx+n3[1]*qy+e3
				if db<0: continue
				var sum_value := da+db+dc
				if sum_value<=0: continue
				var k := row+x; tri[k] = t+1; wa[k] = da/sum_value; wb[k] = db/sum_value
	var holes := 0
	for y in range(h):
		for x in range(w):
			var k := y*w+x
			if tri[k]!=0: continue
			holes += 1; var j := y*w+(x-1 if x>0 else w-1); tri[k] = tri[j]; wa[k] = wa[j]; wb[k] = wb[j]
	return {"tri":tri,"wa":wa,"wb":wb,"holes":holes,"grid":g}
