extends RefCounted
## civ-atlas 103afd3 gen/tectonics.ts default random planet. AGPL-3.0-only.
## Authored sketch/terrain edits are outside this independent prototype.
const Maths = preload("res://scripts/atlas/math.gd")
const Geometry = preload("res://scripts/atlas/surface_geometry.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const Continents = preload("res://scripts/atlas/continents.gd")

static func floats(n: int) -> PackedFloat32Array:
	var result := PackedFloat32Array(); result.resize(n); return result

static func band(d: float,w: float) -> float:
	var t := d/w; return 0.0 if t>4 or t < -4 else Maths.fexp(-t*t)

static func distance_field(mesh: Dictionary,geo,sources: Array,strength: Callable) -> Dictionary:
	var dist := PackedFloat64Array(); dist.resize(mesh.n); dist.fill(INF)
	var value := floats(mesh.n); var src := PackedInt32Array(); src.resize(mesh.n); src.fill(-1)
	var heap := Maths.Heap.new()
	for s in sources: dist[s] = 0; value[s] = strength.call(s); src[s] = s; heap.push(s,0)
	while not heap.empty():
		var i := heap.pop(); var d := heap.last_priority
		if d>dist[i]: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]; var nd: float = d+geo.lengths[k]
			if nd<dist[j]: dist[j] = nd; value[j] = value[i]; src[j] = src[i]; heap.push(j,nd)
	return {"dist":PackedFloat32Array(Array(dist)),"str":value,"src":src}

static func side_of(i: int,conv: Dictionary,plate: PackedInt32Array,side: PackedByteArray) -> int:
	var s: int = conv.src[i]; return side[s] if s>=0 and plate[s]==plate[i] else 0

static func crust(k: int,pick: Dictionary) -> int:
	return 2 if pick.continental[k] else 1 if pick.micro[k] else 0

static func build(mesh: Dictionary,params: Dictionary) -> Dictionary:
	var n: int = mesh.n; var width: float = mesh.width; var spacing: float = mesh.spacing
	var geo := Geometry.new(mesh); var rng := Maths.Stream.new(Maths.sub_seed(int(params.seed),"plates"))
	var want := maxi(3,int(floor(float(params.plates)+.5)))
	var seed_distance := .45*sqrt(4*PI*geo.radius*geo.radius/want); var seeds: Array = []
	for tries in range(want*400):
		if seeds.size()>=want: break
		var i := int(rng.next()*n); var ok := true
		for s in seeds:
			if Sphere.distance(mesh,s,i)<=seed_distance*(.5 if tries>want*200 else 1.0): ok = false; break
		if ok: seeds.append(i)
	var count := seeds.size(); var rate := floats(count)
	for k in range(count): rate[k] = clampf(Maths.fexp(.42*(rng.next()+rng.next()+rng.next()-1.5)*2),.5,1.9)
	var rough = geo.fbm(Maths.sub_seed(int(params.seed),"plate-rough"),5)
	var plate0 := PackedInt32Array(); plate0.resize(n); plate0.fill(-1)
	var cost := PackedFloat64Array(); cost.resize(n); cost.fill(INF); var heap := Maths.Heap.new()
	for k in range(count): plate0[seeds[k]] = k; cost[seeds[k]] = 0; heap.push(seeds[k],0)
	var closed := PackedByteArray(); closed.resize(n); var grow := PackedFloat64Array(); grow.resize(n)
	for j in range(n):
		var nv: float = .5+.5*rough.at(j,3.0/width); grow[j] = .12+2.4*nv*nv
	while not heap.empty():
		var i := heap.pop()
		if closed[i]: continue
		closed[i] = 1; var pk := plate0[i]
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if closed[j]: continue
			var c: float = cost[i]+geo.lengths[k]*grow[j]/rate[pk]
			if c<cost[j]: cost[j] = c; plate0[j] = pk; heap.push(j,c)
	var warp: Array = []
	for pair in [["warp-a",4],["warp-b",4],["warp-c",3],["warp-d",3],["warp-e",2]]: warp.append(geo.fbm(Maths.sub_seed(int(params.seed),pair[0]),pair[1]))
	var plate := PackedInt32Array(); plate.resize(n)
	for i in range(n):
		var q := geo.move_cell(i,.085*width*warp[0].at(i,2.2/width),.085*width*warp[1].at(i,2.2/width,1,5.2,1.3),.035*width*warp[2].at(i,6.5/width),.035*width*warp[3].at(i,6.5/width),.012*width*warp[4].at(i,18.0/width),.012*width*warp[4].at(i,18.0/width,1,7.1,-2.6))
		q[0] = fposmod(q[0],width); q[1] = clampf(q[1],0,mesh.height); plate[i] = plate0[geo.nearest(q[0],q[1],i)]
	Continents.fragments(mesh,plate,count)
	var vx := floats(count); var vy := floats(count); var density := floats(count); var area := floats(count)
	for i in range(n): area[plate[i]] += 1
	for k in range(count):
		var a := rng.next()*PI*2; var speed := .3+.7*rng.next()
		vx[k] = Maths.round24(cos(a))*speed; vy[k] = Maths.round24(sin(a))*speed; density[k] = rng.next()
	var cen := geo.group_centroids(plate,count,area); var spin := floats(count)
	var spin_seed := Maths.sub_seed(int(params.seed),"plate-spin")
	for k in range(count): spin[k] = 2*Maths.keyed(spin_seed,k)-1
	var omega := geo.plate_motion(vx,vy,cen.x,cen.y,spin)
	var polar_seed := Maths.sub_seed(int(params.seed),"polar-continent")
	var pole := (1 if Maths.keyed(polar_seed,1)<.5 else -1) if Maths.keyed(polar_seed,0)<.4 else 0
	var pick := Continents.pick(mesh,geo,plate,count,area,cen,params.landFraction,rng,pole)
	var continental := PackedByteArray(); continental.resize(count)
	for k in range(count): continental[k] = 1 if pick.continental[k] or pick.micro[k] else 0
	var convergence := floats(n); var side := PackedByteArray(); side.resize(n); var conv_sources: Array = []; var div_sources: Array = []
	for i in range(n):
		var pi := plate[i]; var sum_value := 0.0; var total := 0; var other := -1
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]; var pj := plate[j]
			if pj==pi: continue
			if other<0: other = pj
			var va := geo.motion_at(omega,pi,i); var vb := geo.motion_at(omega,pj,i)
			sum_value += geo.edge_dot(i,j,va[0]-vb[0],va[1]-vb[1]); total += 1
		if total==0: continue
		var c := sum_value/total; convergence[i] = c
		if c>.25:
			conv_sources.append(i); var ca := continental[pi]; var cb := continental[other]
			if ca and cb: side[i] = 3 if density[pi]<density[other] else 4
			elif ca!=cb: side[i] = 1 if ca else 2
			else: side[i] = 1 if density[pi]<density[other] else 2
		elif c < -.25: div_sources.append(i)
	var conv := distance_field(mesh,geo,conv_sources,func(i): return clampf(convergence[i]/.9,0,1))
	var div := distance_field(mesh,geo,div_sources,func(i): return clampf(-convergence[i]/.9,0,1))
	var shore: Array = []
	for i in range(n):
		var ci := crust(plate[i],pick)
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if crust(plate[mesh.adj[k]],pick)!=ci: shore.append(i); break
	var sh := distance_field(mesh,geo,shore,func(i): return convergence[i])
	var arch := floats(n); var has_arch := false
	for i in range(n):
		arch[i] = 1 if pick.archipelago[plate[i]] else 0
		if arch[i]>0: has_arch = true
	if has_arch: arch = Geometry.blur(mesh,arch,maxi(4,int(floor((30.0/spacing)*(30.0/spacing)+.5))))
	var coast_n = geo.fbm(Maths.sub_seed(int(params.seed),"land"),3,.6)
	var coast_f = geo.fbm(Maths.sub_seed(int(params.seed),"coast-fine"),4,.6)
	var rug_n = geo.fbm(Maths.sub_seed(int(params.seed),"rugged"),3)
	var shelf_isle = geo.fbm(Maths.sub_seed(int(params.seed),"shelf-isles"),3)
	var inset_n = geo.fbm(Maths.sub_seed(int(params.seed),"inset"),3)
	var island_n = geo.fbm(Maths.sub_seed(int(params.seed),"islands"),4)
	var bead_n = geo.noise(Maths.sub_seed(int(params.seed),"arc-beads"))
	var basin_n = geo.fbm(Maths.sub_seed(int(params.seed),"basins"),5)
	var fs := 2.6/width; var fc := 3.4/width; var b_values := floats(n); var land_field := floats(n)
	for i in range(n):
		var pk := plate[i]; var cr := crust(pk,pick); var cs: float = sh.str[i]
		var inset: float = (4+10*Maths.smoothstep(.1,-.2,cs)+34*Maths.smoothstep(-.1,-.6,cs))*(.55+.9*(.5+.5*inset_n.at(i,fc,1.3)))
		var sd: float = sh.dist[i]-inset if cr>0 else -sh.dist[i]-inset
		var b := Maths.round24(tanh(sd/(.05*width)))
		if cr==1: b = .8*b-.12
		b_values[i] = b
		var rug: float = .25+1.35*Maths.smoothstep(-.35,.45,rug_n.at(i,fc,.8,2.1,-6.3))
		var coast: float = .75*coast_n.at(i,fc)+.4*rug*coast_f.at(i,fc,7)
		var s := side_of(i,conv,plate,side); cs = conv.str[i]; var cd: float = conv.dist[i]
		var mtn := cs*band(cd,22) if s in [3,4] or (s==1 and b>0) else 0.0; var arc := 0.0
		if s==1 and b<.2:
			var beads := Maths.smoothstep(-.35,.45,bead_n.at_scale(i,38)+.35*island_n.at(i,fc,6))
			arc = cs*band(cd-11,maxf(5,.9*spacing))*beads
		var isle: float = arch[i]*Maths.smoothstep(.05,.55,island_n.at(i,fc,2.4,7.7,-3.3)) if arch[i]>0 else 0.0
		var rift: float = maxf(0,b)*div.str[i]*band(div.dist[i],14+23*div.str[i])
		var basin := (b-.45)*2*Maths.smoothstep(.2,.5,basin_n.at(i,fs,1.2,.4*coast,0)) if b>.45 else 0.0
		var shelf_z := Maths.smoothstep(-.8,-.4,b)*(1-Maths.smoothstep(-.15,.15,b))
		var s_isle := shelf_z*Maths.smoothstep(.2,.55,shelf_isle.at(i,fc,2.6,-1.7,4.4)) if shelf_z>0 else 0.0
		land_field[i] = .62*b+.4*coast+.16*mtn+1.1*arc+.6*isle+.55*s_isle-1.5*rift-.9*basin
	var hotspots: Array = []; var hot_at: Array = []; var n_hot := 2+int(rng.next()*4)
	for _h in range(n_hot):
		var best := -1
		for _tries in range(60):
			var i := int(rng.next()*n)
			if b_values[i] > -.45: continue
			var near := false
			for j in hot_at:
				if Sphere.distance(mesh,j,i)<180: near = true; break
			if near: continue
			if best<0 or sh.dist[i]>sh.dist[best]: best = i
		if best>=0: hot_at.append(best)
	for h in hot_at:
		var va := geo.motion_at(omega,plate[h],h); var vl := sqrt(va[0]*va[0]+va[1]*va[1]); if vl==0: vl = 1
		var dx: float = va[0]/vl; var dy: float = va[1]/vl
		var m := 5+int(rng.next()*5); var step := 12+rng.next()*7; var r0 := 8+rng.next()*4
		for k in range(m):
			var lat := (rng.next()-.5)*7; var q := geo.move_cell(h,dx*step*k,dy*step*k,-dy*lat,dx*lat)
			hotspots.append({"x":q[0],"y":q[1],"r":maxf(r0*(1-.55*k/m),.9*spacing),"a":1.45*(1-float(k)/(m*.75))})
	var hot := floats(n)
	for spot in hotspots:
		for i in geo.cells_near_point(spot.x,spot.y,3*spot.r):
			var g := band(geo.near_to(i,spot.x,spot.y,3*spot.r),spot.r)
			if spot.a>0: land_field[i] += spot.a*g
			hot[i] = maxf(hot[i],g*(.5+.5*clampf(spot.a,0,1)))
	var sorted := land_field.duplicate(); sorted.sort()
	var threshold := sorted[int(floor((1-clampf(params.landFraction,.02,.95))*(n-1)))]
	var land := PackedByteArray(); land.resize(n); var coast_src: Array = []; var sea_src: Array = []
	for i in range(n):
		land[i] = 1 if land_field[i]>threshold else 0
		if land[i]: coast_src.append(i)
		else: sea_src.append(i)
	var d_coast: PackedFloat32Array = distance_field(mesh,geo,coast_src,func(_i): return 0.0).dist
	var ridge_src: Array = []
	for i in div_sources:
		if not land[i] and b_values[i]<.1: ridge_src.append(i)
	var ridge := distance_field(mesh,geo,ridge_src,func(i): return clampf(-convergence[i]/.9,0,1))
	var sea_noise = geo.fbm(Maths.sub_seed(int(params.seed),"sea"),5); var shelf_n = geo.fbm(Maths.sub_seed(int(params.seed),"shelf"),3)
	var ocean := floats(n)
	for i in range(n):
		if land[i]: continue
		var age := clampf(ridge.dist[i]/160.0,0,1)
		var d: float = -2700-2700*sqrt(age)+500*ridge.str[i]*band(ridge.dist[i],14)
		d += 300*sea_noise.at(i,fs,2)+90*sea_noise.at(i,fs,9,3.3,-1.7)
		var active: float = conv.str[i]*band(conv.dist[i],30)
		var sw: float = (3+26*(1-active)*(.35+.65*Maths.smoothstep(-.4,.5,shelf_n.at(i,fs,1.6))))*(1.3 if b_values[i]>-.2 else .7)
		var dc := d_coast[i]; var shelf := -(30+150*dc/sw) if dc<sw else -(180+6500*Maths.smoothstep(0,24,dc-sw))
		d = maxf(d,shelf)
		if side_of(i,conv,plate,side)==1: d = maxf(d,-1600-2200*(1-conv.str[i]*band(conv.dist[i]-11,9)))
		d += 2600*hot[i]; ocean[i] = minf(-20,d)
	var smooth_depth := Geometry.blur(mesh,ocean,5); var trench := floats(n)
	for i in range(n):
		if not land[i] and side_of(i,conv,plate,side)==2: trench[i] = (3200+3300*conv.str[i])*conv.str[i]*band(conv.dist[i],maxf(9,.9*spacing))*Maths.smoothstep(2,14,d_coast[i])
	var trench_s := Geometry.blur(mesh,trench,1)
	for i in range(n): ocean[i] = 0 if land[i] else clampf(smooth_depth[i]-trench_s[i],-10500,-20)
	var d_sea: PackedFloat32Array = distance_field(mesh,geo,sea_src,func(_i): return 0.0).dist
	var base_u = geo.fbm(Maths.sub_seed(int(params.seed),"uplift"),5); var hills = geo.fbm(Maths.sub_seed(int(params.seed),"hills"),4)
	var old = geo.ridged(Maths.sub_seed(int(params.seed),"old-ranges"),5); var plat = geo.fbm(Maths.sub_seed(int(params.seed),"plateau"),4); var shield = geo.fbm(Maths.sub_seed(int(params.seed),"shield"),4)
	var uplift := floats(n); var plateau := floats(n); var mf: float = params.mountains
	for i in range(n):
		if not land[i]: continue
		var u: float = .016+.018*(base_u.at(i,fs,1.5)+1)
		u += .1*Maths.smoothstep(.3,.75,hills.at(i,fs,2.2,11,-3))
		var s := side_of(i,conv,plate,side); var cs: float = conv.str[i]; var cd: float = conv.dist[i]; var cf := 1.0 if b_values[i]>0 else .7
		if s in [3,4]: u += mf*1.65*cs*band(cd,7+9*cs)*cf
		elif s==1: u += mf*1.45*cs*band(cd-9,5+5*cs)*cf
		elif s==2: u += mf*.35*cs*band(cd,6)*cf
		var r: float = old.at(i,fs,1.9,3.1,-7.4)
		u += mf*.4*Maths.smoothstep(.78,.96,r)*Maths.smoothstep(.1,.55,hills.at(i,fs,.7,-5,2)+.3)
		u *= 1-.75*div.str[i]*band(div.dist[i],20)*cf; uplift[i] = u
		var pb := 0.0
		if s in [3,1] and cs>.25:
			var reach: float = (28 if s==3 else 16)+34*(.5+.5*plat.at(i,fs,1.1,4,0))
			var in_band := Maths.smoothstep(4,12,cd)*(1-Maths.smoothstep(reach,reach+16,cd))
			var along := Maths.smoothstep(-.25,.3,plat.at(i,fs,2.3,-8,1))
			pb = (3400 if s==3 else 2600)*mf*Maths.smoothstep(.25,.8,cs)*in_band*along
		pb += 1400*Maths.smoothstep(-.2,.3,shield.at(i,fs,1.2))*Maths.smoothstep(.1,.5,b_values[i])
		plateau[i] = pb*Maths.smoothstep(3,30,d_sea[i])
	return {"plateCount":count,"plate":plate,"plateVx":vx,"plateVy":vy,"plateOmega":omega,"plateContinental":continental,
		"convergence":convergence,"distConv":conv.dist,"strengthConv":conv.str,"distDiv":div.dist,"strengthDiv":div.str,
		"land":land,"oceanDepth":ocean,"uplift":uplift,"plateau":plateau}
