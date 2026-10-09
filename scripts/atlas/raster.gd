extends RefCounted
## civ-atlas raster.ts native full-world raster (no rivers or realistic gullies).
## AGPL-3.0-only. Floe breakup is a separate sea-ice display stage.
const Maths = preload("res://scripts/atlas/math.gd")
const Geometry = preload("res://scripts/atlas/surface_geometry.gd")
const Coverage = preload("res://scripts/atlas/raster_cover.gd")
const Tile = preload("res://scripts/atlas/tile_noise.gd")
const Planet = preload("res://scripts/atlas/world.gd")
const FloePixels = preload("res://scripts/atlas/ice_pixels.gd")

static func zeros(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n); return out

static func ice_nodes(world: Dictionary,geo) -> PackedFloat32Array:
	var mesh: Dictionary = world.mesh; var node := zeros(mesh.n)
	for i in range(mesh.n):
		if world.water[i]==1: node[i] = world.seaIce[i]; continue
		var sum_value := 0.0; var count := 0
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if world.water[j]==1: sum_value += world.seaIce[j]; count += 1
		node[i] = sum_value/count if count else 0
	var out := zeros(mesh.n); var inv: float = 1.0/(mesh.spacing*mesh.spacing*4)
	for i in range(mesh.n):
		var sw := 0.0; var sv := 0.0
		for k in range(mesh.adj_start[i]-1,mesh.adj_start[i+1]):
			var j: int = i if k<mesh.adj_start[i] else mesh.adj[k]
			var dx: float = mesh.xyz[3*j]-mesh.xyz[3*i]; var dy: float = mesh.xyz[3*j+1]-mesh.xyz[3*i+1]; var dz: float = mesh.xyz[3*j+2]-mesh.xyz[3*i+2]
			var t := maxf(0,1-geo.radius*geo.radius*(dx*dx+dy*dy+dz*dz)*inv); var weight := t*t+1e-6
			sw += weight; sv += weight*node[j]
		out[i] = sv/sw
	return out

static func cell_fields(world: Dictionary,geo) -> Dictionary:
	var mesh: Dictionary = world.mesh; var n: int = mesh.n
	var elev := zeros(n); var lake := zeros(n); var temp := zeros(n); var ground := zeros(n)
	for i in range(n):
		var e: float = world.elevation[i]; var water: int = world.water[i]
		elev[i] = e if water==1 else maxf(e,8)
		if water==2: lake[i] = 1; elev[i] = maxf(world.waterLevel[i],8)
		temp[i] = world.temperature[i]+.0065*maxf(0,0.0 if water==1 else elev[i])
		ground[i] = 0.0 if water==1 else maxf(0,world.waterLevel[i] if water==2 else e)
	var mad := zeros(n)
	for i in range(n):
		var sum_value := 0.0; var count: int = mesh.adj_start[i+1]-mesh.adj_start[i]
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]): sum_value += absf(ground[i]-ground[mesh.adj[k]])
		mad[i] = sum_value/count if count else 0
	var relief := Geometry.blur(mesh,mad,2); var amp := zeros(n); var coast := zeros(n); var rug := zeros(n)
	for i in range(n):
		var sea: bool = world.water[i]==1; var coastal := false
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if (world.water[mesh.adj[k]]==1)!=sea: coastal = true; break
		var la := minf(520,7+relief[i]*(.1+.9*Maths.smoothstep(40,350,relief[i])))
		var sea_amp: float = 30+.02*-world.elevation[i]
		amp[i] = la if not sea else minf(sea_amp,maxf(la,12)) if coastal else sea_amp
		coast[i] = 1 if coastal else .001 if sea else 0; rug[i] = Maths.smoothstep(60,450,relief[i])
	return {"elev":elev,"lake":lake,"temp":temp,"precip":world.precipitation,"amp":amp,"coast":coast,"rug":rug,"ice":ice_nodes(world,geo)}

static func blur_sphere(source: PackedFloat32Array,w: int,h: int,r: int,cos_lat: PackedFloat32Array) -> void:
	var temp := zeros(w*h); var max_radius := (w-1)>>1
	for y in range(h):
		var rx := mini(max_radius,int(floor(r/maxf(cos_lat[y],.001)+.5))); var inv := 1.0/(2*rx+1); var row := y*w; var acc := 0.0
		for x in range(-rx,rx+1): acc += source[row+posmod(x,w)]
		for x in range(w):
			temp[row+x] = acc*inv; acc += source[row+posmod(x+rx+1,w)]-source[row+posmod(x-rx,w)]
	var acc := PackedFloat64Array(); acc.resize(w)
	for y in range(-r,r+1):
		for x in range(w): acc[x] += temp[clampi(y,0,h-1)*w+x]
	var inv := 1.0/(2*r+1)
	for y in range(h):
		for x in range(w):
			source[y*w+x] = acc[x]*inv; acc[x] += temp[mini(h-1,y+r+1)*w+x]-temp[maxi(0,y-r)*w+x]

static func base(world: Dictionary) -> Dictionary:
	var mesh: Dictionary = world.mesh; var geo := Geometry.new(mesh); var f := cell_fields(world,geo)
	var w: int = mesh.width; var h: int = mesh.height; var cover := Coverage.build(mesh,w,h)
	var field := zeros(w*h); var cell := PackedInt32Array(); cell.resize(w*h)
	for k in range(w*h):
		var t: int = cover.tri[k]-1
		if t<0: continue
		var a: int = mesh.triangles[3*t]; var b: int = mesh.triangles[3*t+1]; var c: int = mesh.triangles[3*t+2]
		var ua: float = cover.wa[k]; var ub: float = cover.wb[k]; var uc := 1-ua-ub
		field[k] = ua*f.elev[a]+ub*f.elev[b]+uc*f.elev[c]
		cell[k] = (a if ua>=uc else c) if ua>=ub else (b if ub>=uc else c)
	var planes := zeros(mesh.triangles.size()/3*21)
	var fields := [f.lake,f.amp,f.coast,f.temp,f.precip,f.rug,f.ice]
	for t in range(mesh.triangles.size()/3):
		var a: int = mesh.triangles[3*t]; var b: int = mesh.triangles[3*t+1]; var c: int = mesh.triangles[3*t+2]
		for q in range(7):
			var o := t*21+q*3; planes[o] = fields[q][a]-fields[q][c]; planes[o+1] = fields[q][b]-fields[q][c]; planes[o+2] = fields[q][c]
	var radius := maxi(1,int(floor(mesh.spacing*.35+.5)))
	blur_sphere(field,w,h,radius,cover.grid.cosLat); blur_sphere(field,w,h,radius,cover.grid.cosLat)
	cover.elev = field; cover.cell = cell; cover.planes = planes; return cover

class Sampler:
	var x := 0.0; var y := 0.0; var z := 0.0; var w0 := 0.0; var w1 := 0.0; var w2 := 0.0
	var co := cos(.61); var si := sin(.61)
	func sample(tile: PackedFloat32Array,size: int,f: float,offset: float) -> float:
		var value := 0.0; var mask := size-1
		for p in range(3):
			var weight := w0 if p==0 else w1 if p==1 else w2
			if weight<=0: continue
			var u := y*f if p==0 else z*f if p==1 else x*f; var v := z*f if p==0 else x*f if p==1 else y*f
			var su := 0.0; var sv := 0.0
			if p==0: su = co*u-si*v+offset; sv = si*u+co*v+.37*offset+17.9
			elif p==1: su = co*u-si*v+1.31*offset+131.3; sv = si*u+co*v+.73*offset+7.7
			else: su = co*u-si*v+.59*offset+61.1; sv = si*u+co*v+1.13*offset+233.9
			var ui := int(floor(su)); var vi := int(floor(sv)); var tx := su-ui; var ty := sv-vi
			var a := tile[(vi&mask)*size+(ui&mask)]; var b := tile[(vi&mask)*size+((ui+1)&mask)]
			var c := tile[((vi+1)&mask)*size+(ui&mask)]; var d := tile[((vi+1)&mask)*size+((ui+1)&mask)]
			var top := a+(b-a)*tx; value += weight*(top+(c+(d-c)*tx-top)*ty)
		return value

static func sample_wrapped(field: PackedFloat32Array,w: int,h: int,x: float,y: float) -> float:
	y = clampf(y,0,h-1); var xf := int(floor(x)); var tx := x-xf; var x0 := posmod(xf,w); var x1 := (x0+1)%w
	var y0 := int(floor(y)); var y1 := mini(h-1,y0+1); var ty := y-y0
	var top := field[y0*w+x0]+(field[y0*w+x1]-field[y0*w+x0])*tx
	var bot := field[y1*w+x0]+(field[y1*w+x1]-field[y1*w+x0])*tx
	return top+(bot-top)*ty

static func build(world: Dictionary,apply_ice: bool = true) -> Dictionary:
	var b := base(world); var mesh: Dictionary = world.mesh; var w: int = mesh.width; var h: int = mesh.height; var n := w*h
	var detail := Tile.build(Maths.sub_seed(int(world.params.seed),"detail"),512,36,4,.55)
	var jitter := Tile.build(Maths.sub_seed(int(world.params.seed),"jitter"),256,18,3,.5)
	for i in range(detail.size()): detail[i] *= .25
	for i in range(jitter.size()): jitter[i] *= .29
	var elev := zeros(n); var temp := zeros(n); var precip := zeros(n); var water := PackedByteArray(); water.resize(n); var biome := water.duplicate(); var ice := zeros(n)
	var sampler := Sampler.new(); var radius: float = mesh.width/TAU; var last_triangle := 0
	var planes: PackedFloat32Array = b.planes
	for y in range(h):
		var cl: float = b.grid.cosLat[y]; var sl: float = b.grid.sinLat[y]; sampler.z = sl*radius
		var a2 := absf(sl)-.45; var w2r := a2*a2 if a2>0 else 0.0; var stretch := 1.0/maxf(cl,.05)
		for x in range(w):
			var k := y*w+x; var tv: int = b.tri[k]
			if tv>0: last_triangle = tv-1
			var o := last_triangle*21; var fx: float = b.wa[k]; var fy: float = b.wb[k]
			var lake := planes[o]*fx+planes[o+1]*fy+planes[o+2]; var amp := planes[o+3]*fx+planes[o+4]*fy+planes[o+5]; var cw := planes[o+6]*fx+planes[o+7]*fy+planes[o+8]
			var qx: float = cl*b.grid.cosLon[x]; var qy: float = cl*b.grid.sinLon[x]; sampler.x = qx*radius; sampler.y = qy*radius
			var a0 := absf(qx)-.45; var a1 := absf(qy)-.45
			sampler.w0 = a0*a0 if a0>0 else 0.0; sampler.w1 = a1*a1 if a1>0 else 0.0; sampler.w2 = w2r
			var norm := 1.0/sqrt(sampler.w0*sampler.w0+sampler.w1*sampler.w1+sampler.w2*sampler.w2)
			sampler.w0 *= norm; sampler.w1 *= norm; sampler.w2 *= norm
			var e: float = b.elev[k]; var d := sampler.sample(detail,512,1,0); var is_lake := lake+.12*d>.5; var ee := e
			if not is_lake:
				var eb := e
				if cw>.01:
					var rug := planes[o+15]*fx+planes[o+16]*fy+planes[o+17]; var amount := (1.2+3.5*rug)*Maths.smoothstep(.01,.5,cw)/.25
					var wx := sampler.sample(detail,512,1,211.3); var wy := sampler.sample(detail,512,1,53.9)
					if rug>.02: wx += 1.3*rug*sampler.sample(detail,512,1.0/3,101.7); wy += 1.3*rug*sampler.sample(detail,512,1.0/3,157.1)
					eb = sample_wrapped(b.elev,w,h,x+amount*wx*stretch,y+amount*wy)
				var dd := d
				if amp>60 and e>0: dd += .5*Maths.smoothstep(60,250,amp)*sampler.sample(detail,512,2.37,33.1)
				ee = eb+amp*dd
				if cw==0 and ee<2: ee = 2
			elev[k] = ee; var wtr := 2 if is_lake else 1 if ee<0 else 0; water[k] = wtr
			var j := sampler.sample(jitter,256,256.0/18/40,3.7)
			var t := planes[o+9]*fx+planes[o+10]*fy+planes[o+11]-.0065*maxf(0,0.0 if wtr==1 else ee)+1.2*j
			var pr := (planes[o+12]*fx+planes[o+13]*fy+planes[o+14])*(1+.22*j)
			temp[k] = t; precip[k] = pr; biome[k] = Planet.biome(t,pr,wtr,0)
			if wtr==1 and tv>0:
				var concentration := planes[o+18]*fx+planes[o+19]*fy+planes[o+20]
				if concentration>.002: ice[k] = concentration
	var result := {"w":w,"h":h,"scale":1.0,"elev":elev,"temp":temp,"precip":precip,"water":water,"biome":biome,"cell":b.cell,"ice":ice,"wrap":true}
	if apply_ice: FloePixels.apply(result,int(world.params.seed))
	return result
