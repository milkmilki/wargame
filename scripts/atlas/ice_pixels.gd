extends RefCounted
## civ-atlas seaice.ts seaIcePixels, native sphere Voronoi floes. AGPL-3.0-only.
## Sites are cached by integer coordinate instead of allocating a bounded cube;
## scalar/F32 values, 27-site order and ties are preserved.
const Maths = preload("res://scripts/atlas/math.gd")
const Simplex = preload("res://scripts/atlas/simplex.gd")

static func hash3(x: int,y: int,z: int,seed_value: int) -> float:
	var value := int(float(x)*374761393.0+float(y)*668265263.0+float(z)*1442695041.0+seed_value)&0xffffffff
	value = ((value^(value>>13))*1274126177)&0xffffffff; value ^= value>>16
	return float(value)/4294967296.0

class Floes:
	var length: float; var seed_value: int; var sites := {}
	var edge_x := 0.0; var edge_y := 0.0; var edge_z := 0.0
	func _init(scale_value: float,seed_input: int) -> void: length = scale_value; seed_value = seed_input
	func site(c: Vector3i) -> PackedFloat32Array:
		if sites.has(c): return sites[c]
		# Same coercion and F32 stores as the source cube table.
		var h1 := Maths.hash3(c.x,c.y,c.z,seed_value); var h2 := Maths.hash3(c.x,c.y,c.z,seed_value+1)
		var h := Maths.f32(Maths.hash3(c.x,c.y,c.z,seed_value+2))
		var p := PackedFloat32Array([(c.x+.1+.8*h1)*length,(c.y+.1+.8*fmod(h1*4096,1))*length,(c.z+.1+.8*h2)*length,h,int(fmod(h*7.31,1)*255+.5)])
		sites[c] = p; return p
	func block(x: float,y: float,z: float) -> Vector3i: return Vector3i(int(floor(x/length))-1,int(floor(y/length))-1,int(floor(z/length))-1)
	func nearest(base: Vector3i,x: float,y: float,z: float) -> Vector3i:
		var best := INF; var chosen := base
		for k in range(3):
			for j in range(3):
				for i in range(3):
					var coordinate := base+Vector3i(i,j,k); var p := site(coordinate)
					var dx := p[0]-x; var dy := p[1]-y; var dz := p[2]-z; var distance := dx*dx+dy*dy+dz*dz
					if distance<best: best = distance; chosen = coordinate
		return chosen
	func edge_distance(base: Vector3i,chosen: Vector3i,x: float,y: float,z: float) -> float:
		var p := site(chosen); var best := INF
		for k in range(3):
			for j in range(3):
				for i in range(3):
					var coordinate := base+Vector3i(i,j,k)
					if coordinate==chosen: continue
					var q := site(coordinate); var dx := p[0]-q[0]; var dy := p[1]-q[1]; var dz := p[2]-q[2]
					var distance := sqrt(dx*dx+dy*dy+dz*dz)
					if distance<1e-6: continue
					var d := ((x-(p[0]+q[0])/2)*dx+(y-(p[1]+q[1])/2)*dy+(z-(p[2]+q[2])/2)*dz)/distance
					if d<best: best = d; edge_x = dx/distance; edge_y = dy/distance; edge_z = dz/distance
		return best
	func coverage(distance: float,gap: float,ex: float,ey: float,sx: float,sy: float,sz: float,cl: float) -> float:
		var ne := edge_x*ex+edge_y*ey; var ns := edge_x*sx+edge_y*sy+edge_z*sz
		var t2 := maxf(.05,ne*ne+ns*ns); var px2 := maxf(ne*ne*cl*cl+ns*ns,4e-4*t2)
		return clampf((distance/sqrt(t2)-gap)*sqrt(t2/px2)+.5,0,1)

class NoiseGrid:
	var w: int; var h: int; var gw: int; var radius: float
	var grid := PackedFloat32Array(); var warp_a; var warp_b; var edge
	var big; var node_sites := {}
	func _init(width: int,height: int,seed_value: int) -> void:
		w = width; h = height; gw = int(ceil(w/4.0))+1; radius = float(w)/TAU
		grid.resize(gw*(int(ceil(h/4.0))+1)*3); grid.fill(NAN)
		warp_a = Simplex.new(Maths.sub_seed(seed_value,"seaice-warp-a")); warp_b = Simplex.new(Maths.sub_seed(seed_value,"seaice-warp-b")); edge = Simplex.new(Maths.sub_seed(seed_value,"seaice-edge"))
	func frame(x: float,y: float) -> Array:
		var lon := x/w*2*PI-PI; var lat := PI/2-y/h*PI; var cl := cos(lat); var sl := sin(lat); var co := cos(lon); var so := sin(lon)
		return [radius*cl*co,radius*cl*so,radius*sl,-so,co,0.0,sl*co,sl*so,-cl]
	func node(x: int,y: int) -> int:
		var o := (y*gw+x)*3
		if not is_nan(grid[o]): return o
		var p := frame(x*4+.5,y*4+.5)
		grid[o] = edge.fbm(p[0]/48,p[1]/48,p[2]/48,3)
		grid[o+1] = warp_a.at(p[0]/26,p[1]/26,p[2]/26); grid[o+2] = warp_b.at(p[0]/26,p[1]/26,p[2]/26)
		return o
	func site_at(x: int,y: int,o: int) -> Vector3i:
		var key := y*gw+x
		if node_sites.has(key): return node_sites[key]
		var p := frame(x*4+.5,y*4+.5); var a := 3.2*grid[o+1]; var b := 3.2*grid[o+2]
		var ux: float = p[0]+a*p[3]+b*p[6]; var uy: float = p[1]+a*p[4]+b*p[7]; var uz: float = p[2]+a*p[5]+b*p[8]
		var coordinate: Vector3i = big.nearest(big.block(ux,uy,uz),ux,uy,uz); node_sites[key] = coordinate; return coordinate

static func apply(raster: Dictionary,seed_value: int) -> void:
	var w: int = raster.w; var h: int = raster.h
	var cl := PackedFloat32Array(); cl.resize(h); var sl := cl.duplicate(); var co := PackedFloat32Array(); co.resize(w); var so := co.duplicate()
	for x in range(w):
		var lon := (x+.5)/w*2*PI-PI; co[x] = cos(lon); so[x] = sin(lon)
	for y in range(h):
		var lat := PI/2-(y+.5)/h*PI; cl[y] = cos(lat); sl[y] = sin(lat)
	var hs := Maths.sub_seed(seed_value,"seaice-floes")
	if hs>=2147483648: hs -= 4294967296
	var big := Floes.new(17.0,hs); var small := Floes.new(7.0,hs+7)
	var noise := NoiseGrid.new(w,h,seed_value); noise.big = big
	var active := PackedByteArray(); var gw := noise.gw; var gh := int(ceil(h/4.0))+1; active.resize(gw*gh)
	var ice: PackedFloat32Array = raster.ice; var conc := PackedByteArray(); conc.resize(w*h); var tone := conc.duplicate()
	raster.iceConc = conc; raster.iceTone = tone
	for y in range(h):
		for x in range(w):
			if ice[y*w+x]>.002: active[(y/4)*gw+x/4] = 1
	var deep := maxf(.85,1-pow((.7-.5)/2.6,1.0/1.2))
	for j in range(gh-1):
		for i in range(gw-1):
			if not active[j*gw+i]: continue
			var y0 := j*4; var y1 := mini(h,y0+4); var x0 := i*4; var x1 := mini(w,x0+4)
			var a := noise.node(i,j); var b := noise.node(i+1,j); var c := noise.node(i,j+1); var d := noise.node(i+1,j+1)
			var whole_known := false; var whole_valid := false; var whole := Vector3i.ZERO
			for y in range(y0,y1):
				var ty := (y-y0)*.25
				var el := noise.grid[a]+(noise.grid[c]-noise.grid[a])*ty; var er := noise.grid[b]+(noise.grid[d]-noise.grid[b])*ty
				var al := noise.grid[a+1]+(noise.grid[c+1]-noise.grid[a+1])*ty; var ar := noise.grid[b+1]+(noise.grid[d+1]-noise.grid[b+1])*ty
				var bl := noise.grid[a+2]+(noise.grid[c+2]-noise.grid[a+2])*ty; var br := noise.grid[b+2]+(noise.grid[d+2]-noise.grid[b+2])*ty
				for x in range(x0,x1):
					var k := y*w+x; var c0 := ice[k]
					if c0<=.002: continue
					var tx := (x-x0)*.25; var e := el+(er-el)*tx
					var concentration := clampf(c0+.3*e*minf(1,c0*3)*(1-c0*.7),0,1); conc[k] = int(concentration*255+.5)
					if concentration<=.01: ice[k] = 0; continue
					var ex := -so[x]; var ey := co[x]; var sx := sl[y]*co[x]; var sy := sl[y]*so[x]; var sz := -cl[y]
					var wa := 3.2*(al+(ar-al)*tx); var wb := 3.2*(bl+(br-bl)*tx)
					var ux := noise.radius*cl[y]*co[x]+wa*ex+wb*sx; var uy := noise.radius*cl[y]*so[x]+wa*ey+wb*sy; var uz := noise.radius*sl[y]+wb*sz
					var v := 0.0; var tone_value := 0
					if concentration>=deep:
						v = 1
						if not whole_known:
							whole_known = true; whole = noise.site_at(i,j,a)
							whole_valid = whole==noise.site_at(i+1,j,b) and whole==noise.site_at(i,j+1,c) and whole==noise.site_at(i+1,j+1,d)
						var chosen := whole if whole_valid else big.nearest(big.block(ux,uy,uz),ux,uy,uz); tone_value = int(big.site(chosen)[4])
					else:
						if concentration>.3:
							var base := big.block(ux,uy,uz); var chosen := big.nearest(base,ux,uy,uz); var site := big.site(chosen)
							if site[3]<Maths.smoothstep(.3,.85,concentration):
								v = big.coverage(big.edge_distance(base,chosen,ux,uy,uz),2.6*pow(1-concentration,1.2)-.7,ex,ey,sx,sy,sz,cl[y]); tone_value = int(site[4])
						if v<1 and concentration>.1:
							var qx := ux*1.07+7.3; var qy := uy*1.07-3.1; var qz := uz*1.07+4.9
							var base := small.block(qx,qy,qz); var chosen := small.nearest(base,qx,qy,qz); var site := small.site(chosen)
							if site[3]<(concentration-.1)*1.3:
								var value := small.coverage(small.edge_distance(base,chosen,qx,qy,qz),.45+1.1*(1-concentration),ex,ey,sx,sy,sz,cl[y])
								if value>v: v = value; tone_value = int(site[4])
					ice[k] = v; tone[k] = tone_value
					if ice[k]>=.5: raster.biome[k] = 2
