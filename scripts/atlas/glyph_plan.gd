extends RefCounted
## civ-atlas fantasy.ts planGlyphs, equirectangular projection. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const Fields = preload("res://scripts/atlas/paint_fields.gd")
const FORESTS = {9:[1,.43],13:[1,.52],5:[2,.44],10:[2,.36],14:[3,.32]}

static func zeros(n: int) -> PackedFloat32Array:
	var result := PackedFloat32Array(); result.resize(n); return result

static func land_blur(mesh: Dictionary,source: PackedFloat32Array,land: PackedByteArray,passes: int) -> PackedFloat32Array:
	var a := source.duplicate(); var b := zeros(mesh.n)
	for _pass in range(passes):
		for i in range(mesh.n):
			if not land[i]: b[i] = a[i]; continue
			var sum_value := float(a[i]); var count := 1
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var j: int = mesh.adj[k]
				if land[j]: sum_value += a[j]; count += 1
			b[i] = sum_value/count
		var temp := a; a = b; b = temp
	return a

static func base_level(world: Dictionary,elevation: PackedFloat32Array,land: PackedByteArray) -> PackedFloat32Array:
	var mesh: Dictionary = world.mesh; var gw := int(ceil(world.width/8.0)); var gh := int(ceil(world.height/8.0))+1
	var sums := zeros(gw*gh); var count := sums.duplicate()
	for i in range(mesh.n):
		if not land[i]: continue
		var k := int(floor(mesh.y[i]/8.0))*gw+int(floor(mesh.x[i]/8.0)); sums[k] += elevation[i]; count[k] += 1
	var stretch := zeros(gh)
	for row in range(gh): stretch[row] = 1.0/maxf(.001,sin((row+.5)/(gh-1)*PI))
	for _pass in range(2): Fields.blur(sums,gw,gh,5,stretch); Fields.blur(count,gw,gh,5,stretch)
	var out := zeros(mesh.n)
	for i in range(mesh.n):
		if not land[i]: continue
		var fx: float = mesh.x[i]/8.0-.5; var fy := clampf(mesh.y[i]/8.0-.5,0,gh-1.001)
		var xa := int(floor(fx)); var y0 := int(floor(fy)); var tx := fx-xa; var ty := fy-y0
		var sum_value := 0.0; var total := 0.0
		for dy in range(2):
			for dx in range(2):
				var weight := (tx if dx else 1-tx)*(ty if dy else 1-ty)
				var k := (y0+dy)*gw+posmod(xa+dx,gw); sum_value += sums[k]*weight; total += count[k]*weight
		out[i] = sum_value/total if total>1e-6 else elevation[i]
	return out

static func crest(mesh: Dictionary,field: PackedFloat32Array,land: PackedByteArray,i: int) -> bool:
	var lower := 0; var degree := 0
	for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
		var j: int = mesh.adj[k]
		if not land[j]: continue
		degree += 1
		if field[j]<field[i]: lower += 1
	return degree>0 and float(lower)/degree>=.66

static func ridge_axis(mesh: Dictionary,level: PackedByteArray,stamp: PackedInt32Array,i: int) -> Array:
	var ring: Array[int] = []; stamp[i] = i
	for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
		var j: int = mesh.adj[k]
		if stamp[j]!=i: stamp[j] = i; ring.append(j)
	var first_ring := ring.size()
	for q in range(first_ring):
		var current := ring[q]
		for k in range(mesh.adj_start[current],mesh.adj_start[current+1]):
			var j: int = mesh.adj[k]
			if stamp[j]!=i: stamp[j] = i; ring.append(j)
	var sxx := 0.0; var syy := 0.0; var sxy := 0.0
	for j in ring:
		if level[j]<level[i]: continue
		var dx: float = Sphere.near_x(mesh.x[j],mesh.x[i],mesh.width)-mesh.x[i]; var dy: float = mesh.y[j]-mesh.y[i]
		sxx += dx*dx; syy += dy*dy; sxy += dx*dy
	var trace_value := sxx+syy
	if trace_value<=0: return [0.0,0.0]
	return [.5*atan2(2*sxy,sxx-syy),sqrt((sxx-syy)*(sxx-syy)+4*sxy*sxy)/trace_value]

class Placement:
	var placed: Array = []; var grid := {}; var width: float; var gw: int; var factor := 1.0
	func _init(w: float) -> void: width = w; gw = int(ceil(w/24.0))
	func index(id: int) -> void:
		var q: Dictionary = placed[id]; var key := int(floor(q.y/24))*gw+int(floor(q.x/24))
		if not grid.has(key): grid[key] = []
		grid[key].append(id)
	func add(x: float,y: float,r: float) -> void:
		placed.append({"x":x,"y":y,"r":r}); index(placed.size()-1)
	func reset() -> void:
		grid.clear()
		for id in range(placed.size()): index(id)
	func near(x: float,y: float,r: float) -> bool:
		var gx := int(floor(x/24)); var gy := int(floor(y/24))
		for yy in range(gy-2,gy+3):
			for xx in range(gx-2,gx+3):
				for id in grid.get(yy*gw+posmod(xx,gw),[]):
					var q: Dictionary = placed[id]; var need := maxf(r,q.r)*factor
					var dx := Sphere.near_x(q.x,x,width)-x; var dy: float = q.y-y
					if dx*dx+dy*dy<need*need: return true
		return false

static func glyph(x: float,y: float,kind: int,s: float,v: float,angle: float,confidence: float,cell: int,z: float) -> Dictionary:
	return {"x":x,"y":y,"kind":kind,"s":s,"v":v,"a":angle,"c":confidence,"cell":cell,"z":z}

static func build(world: Dictionary) -> Dictionary:
	var mesh: Dictionary = world.mesh; var n: int = mesh.n; var width: float = world.width; var spacing: float = mesh.spacing
	var seed_value := Maths.sub_seed(int(world.params.seed),"glyphs"); var glyphs: Array = []
	var land := PackedByteArray(); land.resize(n); var e0 := zeros(n)
	for i in range(n):
		if world.water[i]==0: land[i] = 1; e0[i] = maxf(0,world.elevation[i])
	var b4 := land_blur(mesh,e0,land,4); var b1 := land_blur(mesh,e0,land,1); var ridge := zeros(n); var slope := zeros(n)
	for i in range(n):
		if not land[i]: continue
		ridge[i] = e0[i]-b4[i]; var m := 0.0
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if land[j]: m = maxf(m,absf(b1[i]-b1[j])/Sphere.distance(mesh,i,j))
		slope[i] = m
	var base := base_level(world,e0,land); var max_e := maxf(1,world.maxElevation)
	var mountain_base := maxf(900,max_e*.16)*.8; var ridge_min := maxf(70,max_e*.022); var hill_min := maxf(260,max_e*.045); var prominence_min := maxf(150,max_e*.042)
	var b_main := land_blur(mesh,e0,land,9); var b_spur := land_blur(mesh,e0,land,2)
	var level := PackedByteArray(); level.resize(n); var mountains: Array[int] = []
	for i in range(n):
		if not land[i] or e0[i]<mountain_base: continue
		var prominence := e0[i]-base[i]
		if crest(mesh,b_main,land,i) and e0[i]-b_main[i]>ridge_min and prominence>prominence_min*.8: level[i] = 2
		elif crest(mesh,b_spur,land,i) and ridge[i]>ridge_min*.6 and prominence>prominence_min: level[i] = 1
		else: continue
		mountains.append(i)
	mountains.sort_custom(func(a,b):
		var sa: float = 1e5+e0[a] if level[a]==2 else e0[a]+ridge[a]
		var sb: float = 1e5+e0[b] if level[b]==2 else e0[b]+ridge[b]
		return a<b if sa==sb else sa>sb)
	var stamp := PackedInt32Array(); stamp.resize(n); stamp.fill(-1)
	var forest := PackedByteArray(); forest.resize(n); var salt := seed_value&0xffff
	var n85 := maxi(1,int(floor(width/85+.5))); var n26 := maxi(1,int(floor(width/26+.5)))
	for i in range(n):
		if not land[i] or not FORESTS.has(int(world.biome[i])): continue
		var f: Array = FORESTS[int(world.biome[i])]
		var nz := .62*Maths.value_noise_periodic(mesh.x[i]*n85/width,mesh.y[i]/85.0,salt,n85)+.38*Maths.value_noise_periodic(mesh.x[i]*n26/width,mesh.y[i]/26.0,salt+1,n26)
		if nz>f[1]: forest[i] = f[0]
	var comp := PackedInt32Array(); comp.resize(n); comp.fill(-1)
	for i in range(n):
		if not forest[i] or comp[i]>=0: continue
		var kind := forest[i]; var stack: Array[int] = [i]; var members: Array[int] = []; comp[i] = i
		while not stack.is_empty():
			var c: int = stack.pop_back(); members.append(c)
			for k in range(mesh.adj_start[c],mesh.adj_start[c+1]):
				var j: int = mesh.adj[k]
				if forest[j]==kind and comp[j]<0: comp[j] = i; stack.append(j)
		if members.size()<=2 and Maths.keyed(seed_value,i,2)<.6:
			for c in members: forest[c] = 0
	var hills: Array[int] = []; var dots: Array[int] = []; var dot_kind := PackedByteArray(); dot_kind.resize(n)
	for i in range(n):
		if not land[i] or forest[i]: continue
		if e0[i]>=hill_min and ridge[i]>0: hills.append(i)
		var b := int(world.biome[i])
		if b in [11,7]: dot_kind[i] = 5
		elif b in [8,12,4]: dot_kind[i] = 6
		else: continue
		dots.append(i)
	hills.sort_custom(func(a,b): return a<b if e0[b]+ridge[b]==e0[a]+ridge[a] else e0[a]+ridge[a]>e0[b]+ridge[b])
	var placement := Placement.new(width); var used := PackedByteArray(); used.resize(n)
	for tier in range(4):
		var z: float = [1,2,3.5,6][tier]; placement.factor = 1.0 if z<=1.35 else pow(z/1.35,-.22)
		if tier>0: placement.reset()
		for i in mountains:
			if used[i]: continue
			var te := clampf((e0[i]-mountain_base)/maxf(1,max_e-mountain_base),0,1); var tp := clampf((e0[i]-base[i])/(max_e*.3),0,1); var tr := clampf(ridge[i]/(max_e*.12),0,1)
			var main := level[i]==2
			var s := 4.6+8.4*sqrt(.6*te+.4*tp) if main else 3.5+4.2*sqrt(.6*te+.4*tp)*(.55+.45*tr)
			if tier==0 and not main and s<5.3: continue
			var radius := s*.62 if main else s*.9
			if placement.near(mesh.x[i],mesh.y[i],radius): continue
			placement.add(mesh.x[i],mesh.y[i],radius); used[i] = 1; var axis := ridge_axis(mesh,level,stamp,i)
			glyphs.append(glyph(mesh.x[i],mesh.y[i],0,s,Maths.keyed(seed_value,i,1),axis[0],axis[1],i,z))
		var boost := .55+.45*tier
		for i in hills:
			if used[i]: continue
			var probability := 0.0; var spread := 0.0
			if e0[i]>mountain_base and not level[i]: probability = .35 if slope[i]>18 else .12; spread = 4
			elif level[i]: probability = .5; spread = 1.8
			else: probability = .75*clampf((slope[i]-8)/30.0,0,1); spread = 2
			if Maths.keyed(seed_value,i,3)>=minf(.95,probability*boost): continue
			var s := 2.8+Maths.keyed(seed_value,i,4)*1.1+minf(.9,ridge[i]/450.0); var radius := s*spread
			if placement.near(mesh.x[i],mesh.y[i],radius): continue
			placement.add(mesh.x[i],mesh.y[i],radius); used[i] = 1
			glyphs.append(glyph(mesh.x[i],mesh.y[i],1,s,Maths.keyed(seed_value,i,5),0,0,i,z))
		for i in dots:
			if used[i]: continue
			var kind := dot_kind[i]; var density := .14 if kind==5 else .16
			if Maths.keyed(seed_value,i,6)>density*(1+.9*tier): continue
			var px: float = mesh.x[i]+(Maths.keyed(seed_value,i,7)-.5)*spacing*1.2; var py: float = mesh.y[i]+(Maths.keyed(seed_value,i,8)-.5)*spacing*1.2
			if px<0: px += width
			elif px>=width: px -= width
			var radius := 5.0 if kind==5 else 2.6
			if placement.near(px,py,radius): continue
			placement.add(px,py,radius); used[i] = 1; glyphs.append(glyph(px,py,kind,1,Maths.keyed(seed_value,i,9),0,0,i,z))
	for i in range(glyphs.size()): glyphs[i]["_order"] = i
	glyphs.sort_custom(func(a,b): return a._order<b._order if a.y==b.y else a.y<b.y)
	for g in glyphs: g.erase("_order")
	return {"glyphs":glyphs,"forest":forest}
