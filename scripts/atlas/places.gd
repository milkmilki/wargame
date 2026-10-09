extends RefCounted
## Geographic entities and deterministic names, gen/civ/places.ts 103afd3.
## Rivers are intentionally absent in this environmental-only preview. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Geo = preload("res://scripts/atlas/surface_geometry.gd")
const Chart = preload("res://scripts/atlas/chart.gd")
const Names = preload("res://scripts/atlas/names.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const KIND_ORDER = {"sea":0,"mountains":1,"river":2,"lake":3,"island":4,"desert":5}
var world: Dictionary
var mesh: Dictionary
var geo: RefCounted
var edge := PackedFloat32Array()
var area := PackedFloat32Array()
var cell_area: float
var spacing: float
var hint := 0
var pending: Array = []
var namer: RefCounted
var sea_base: int
var used := {}

static func build(w: Dictionary) -> Array:
	var planner = load("res://scripts/atlas/places.gd").new(w); return planner.find()
static func world_style(seed_value: int) -> String:
	var r := Maths.Stream.new(Maths.sub_seed(seed_value,"civ-places-style"))
	var tables: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas/western-names.json"))
	var eastern: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas/eastern-names.json"))
	var styles: Array = tables.styles+eastern.styles; return styles[floori(r.next()*styles.size())].id
func _init(w: Dictionary) -> void:
	world = w; mesh = w.mesh; geo = Geo.new(mesh); edge = PackedFloat32Array(Array(geo.lengths)); area = mesh.areas
	cell_area = mesh.width*mesh.height/36000.; spacing = sqrt(cell_area)*1.02
	namer = Names.new(Maths.sub_seed(world.params.seed,"civ-places-names"),world_style(world.params.seed)); sea_base = Maths.sub_seed(world.params.seed,"civ-places-sea")
func nearest(x: float,y: float) -> int: hint = geo.nearest(x,y,hint); return hint
func distance_field(mask: PackedByteArray) -> PackedFloat32Array:
	var dist := PackedFloat64Array(); dist.resize(mesh.n); dist.fill(INF); var heap := Maths.Heap.new()
	for i in range(mesh.n):
		if mask[i]: continue
		dist[i] = 0
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if mask[mesh.adj[k]]: heap.push(i,0); break
	while heap.size>0:
		var i := heap.pop(); var d: float = heap.last_priority
		if d>dist[i]: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if not mask[j]: continue
			var nd := d+edge[k]
			if nd<dist[j]: dist[j] = nd; heap.push(j,nd)
	var out := PackedFloat32Array(); out.resize(mesh.n)
	for i in range(mesh.n): out[i] = 0 if is_inf(dist[i]) else dist[i]
	return out
func components(mask: PackedByteArray) -> Array:
	var seen := PackedByteArray(); seen.resize(mesh.n); var out: Array = []
	for s in range(mesh.n):
		if not mask[s] or seen[s]: continue
		var q: Array = [s]; seen[s] = 1; var h := 0
		while h<q.size():
			var i: int = q[h]; h += 1
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var j: int = mesh.adj[k]
				if mask[j] and not seen[j]: seen[j] = 1; q.append(j)
		out.append(q)
	return out
func sum_area(cells: Array) -> float:
	var value := 0.
	for c in cells: value += area[c]
	return value
static func argmax(cells: Array,field: Variant) -> int:
	var best: int = cells[0]
	for c in cells:
		if field[c]>field[best] or (field[c]==field[best] and c<best): best = c
	return best
func axis(cells: Array,weight: Callable) -> Dictionary:
	var ch: RefCounted = Chart.weighted(geo,cells,weight); var total := 0.; var cx := 0.; var cy := 0.
	for c in cells:
		var w: float = weight.call(c); total += w; cx += w*ch.u(c); cy += w*ch.v(c)
	if total<=0: return {"ch":ch,"cx":ch.u(cells[0]),"cy":ch.v(cells[0]),"ux":1.,"uy":0.,"s1":0.,"s2":0.}
	cx /= total; cy /= total; var sxx := 0.; var syy := 0.; var sxy := 0.
	for c in cells:
		var w: float = weight.call(c); var dx: float = ch.u(c)-cx; var dy: float = ch.v(c)-cy
		sxx += w*dx*dx; syy += w*dy*dy; sxy += w*dx*dy
	sxx /= total; syy /= total; sxy /= total; var tr := sxx+syy; var det := sxx*syy-sxy*sxy
	var disc := sqrt(maxf(0,tr*tr/4-det)); var l1 := tr/2+disc; var l2 := maxf(0,tr/2-disc); var ux := sxy; var uy := l1-sxx
	if absf(ux)+absf(uy)<1e-9: ux = 1 if sxx>=syy else 0; uy = 0 if sxx>=syy else 1
	var length := sqrt(ux*ux+uy*uy); ux /= length; uy /= length
	if ux<0 or (ux==0 and uy<0): ux = -ux; uy = -uy
	return {"ch":ch,"cx":cx,"cy":cy,"ux":ux,"uy":uy,"s1":sqrt(l1),"s2":sqrt(l2)}
static func path_of(ch: RefCounted,points: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in range(0,points.size(),2): out.append_array(PackedFloat32Array(ch.to_xy(points[k],points[k+1])))
	return out
func spine(cells: Array,ax: Dictionary,weight: Callable) -> PackedFloat32Array:
	var ch: RefCounted = ax.ch; var vx: float = -ax.uy; var vy: float = ax.ux; var ts: Array = []
	for c in cells: ts.append((ch.u(c)-ax.cx)*ax.ux+(ch.v(c)-ax.cy)*ax.uy)
	ts.sort(); var t0: float = ts[floori(ts.size()*.05)]; var t1: float = ts[mini(ts.size()-1,floori(ts.size()*.95))]; var length := t1-t0; var nb := clampi(floori(length/(3.5*spacing)+.5),3,12)
	var sw := PackedFloat64Array(); sw.resize(nb); var so := sw.duplicate()
	for c in cells:
		var t: float = (ch.u(c)-ax.cx)*ax.ux+(ch.v(c)-ax.cy)*ax.uy
		if t<t0 or t>t1: continue
		var b := clampi(floori((t-t0)/maxf(1e-6,length)*nb),0,nb-1); var w: float = weight.call(c)
		sw[b] += w; so[b] += w*((ch.u(c)-ax.cx)*vx+(ch.v(c)-ax.cy)*vy)
	var off: Array = []
	for b in range(nb): off.append(so[b]/sw[b] if sw[b]>0 else NAN)
	for b in range(nb):
		if not is_nan(off[b]): continue
		var l := b-1; var r := b+1
		while l>=0 and is_nan(off[l]): l -= 1
		while r<nb and is_nan(off[r]): r += 1
		off[b] = (off[l]+off[r])/2 if l>=0 and r<nb else off[l] if l>=0 else off[r] if r<nb else 0.
	for _pass in range(2):
		var o := off.duplicate()
		for b in range(nb): o[b] = .25*off[maxi(0,b-1)]+.5*off[b]+.25*off[mini(nb-1,b+1)]
		off = o
	var pts: Array = []
	for b in range(nb):
		var t := t0+(b+.5)/nb*length; pts.append(ax.cx+ax.ux*t+vx*off[b]); pts.append(ax.cy+ax.uy*t+vy*off[b])
	return path_of(ch,pts)
func chord(ch: RefCounted,field: Variant,u: float,v: float,vertical: bool,margin: float,max_half: float) -> Array:
	var out: Array = []
	for dir in [-1,1]:
		var s := 0.
		while s<max_half:
			var ns := s+spacing*.5; var xy: Array = ch.to_xy(u if vertical else u+dir*ns,v+dir*ns if vertical else v)
			if field[nearest(xy[0],xy[1])]<margin: break
			s = ns
		out.append(s)
	return out
static func segment_distance(ch: RefCounted,p: Variant,px: float,py: float) -> float:
	var d := INF
	for k in range(2,p.size(),2):
		var a: Array = ch.to_uv(p[k-2],p[k-1]); var b: Array = ch.to_uv(p[k],p[k+1]); var dx: float = b[0]-a[0]; var dy: float = b[1]-a[1]; var length := dx*dx+dy*dy
		var t := clampf(((px-a[0])*dx+(py-a[1])*dy)/length,0,1) if length>0 else 0.
		d = minf(d,sqrt(pow(px-a[0]-t*dx,2)+pow(py-a[1]-t*dy,2)))
	return d
func later(kind: String,path: PackedFloat32Array,rank: int,size: float,cell: int,request: Dictionary) -> Dictionary:
	var p := {"kind":kind,"name":"","culture":-1,"path":path,"rank":rank,"size":size,"cell":cell}; pending.append({"p":p,"req":request,"index":pending.size()}); return p
func find() -> Array:
	if mesh.n==0: return []
	var out: Array = []; out.append_array(seas()); out.append_array(mountains()); out.append_array(areas("lake")); out.append_array(areas("island")); out.append_array(areas("desert")); name_all()
	for p in out: center_path(p.path)
	return out
func center_path(path: PackedFloat32Array) -> void:
	var length := 0.
	for k in range(2,path.size(),2): length += sqrt(pow(path[k]-path[k-2],2)+pow(path[k+1]-path[k-1],2))
	var xm: float = path[0]; var acc := 0.
	for k in range(2,path.size(),2):
		var dx: float = path[k]-path[k-2]; var dy: float = path[k+1]-path[k-1]; var l := sqrt(dx*dx+dy*dy)
		if acc+l>=length/2: xm = path[k-2]+((length/2-acc)/l*dx if l>0 else 0); break
		acc += l
	var shift: float = -mesh.width*floor(xm/mesh.width)
	for k in range(0,path.size(),2): path[k] += shift

func sea_path(c: int,dist: Variant) -> PackedFloat32Array:
	var d: float = dist[c]; var margin := maxf(2.2*spacing,.3*d); var ch := Chart.new(geo,c,mesh.x[c],mesh.y[c]); var u: float = ch.u(c); var v: float = ch.v(c)
	var h := chord(ch,dist,u,v,false,margin,d*3); var vert := chord(ch,dist,u,v,true,margin,d*3)
	return path_of(ch,[u,v-vert[0],u,v+(vert[1]-vert[0])/2,u,v+vert[1]]) if vert[0]+vert[1]>1.7*(h[0]+h[1]) else path_of(ch,[u-h[0],v,u+(h[1]-h[0])/2,v,u+h[1],v])
func separate(c: int,dist: Variant,open: PackedByteArray,stamp: PackedInt32Array) -> bool:
	var minimum: float = .62*dist[c]; var heap := Maths.Heap.new(); heap.push(c,-dist[c]); stamp[c] = c; var visits := 0
	while heap.size>0:
		var i := heap.pop()
		if dist[i]>dist[c] or (dist[i]==dist[c] and i<c): return false
		visits += 1
		if visits>40000: return false
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if stamp[j]==c or not open[j] or dist[j]<minimum: continue
			stamp[j] = c; heap.push(j,-dist[j])
	return true
func enclosure(c: int,dist: Variant) -> float:
	var ch := Chart.new(geo,c); var u: float = ch.u(c); var v: float = ch.v(c); var hit := 0
	for a in range(16):
		var ang := a/16.*TAU; var dx := Maths.round24(cos(ang)); var dy := Maths.round24(sin(ang)); var s: float = dist[c]*.8
		while s<=dist[c]*3.5:
			var xy := ch.to_xy(u+dx*s,v+dy*s)
			if world.water[nearest(xy[0],xy[1])]!=1: hit += 1; break
			s += spacing
	return hit/16.
func seas() -> Array:
	var open := PackedByteArray(); open.resize(mesh.n)
	for i in range(mesh.n): open[i] = int(world.water[i]==1 and world.seaIce[i]<.5)
	var dist := distance_field(open); var order: Array = []
	for i in range(mesh.n):
		if open[i] and dist[i]>=3.2*spacing: order.append(i)
	order.sort_custom(func(a,b): return a<b if dist[a]==dist[b] else dist[a]>dist[b])
	var stamp := PackedInt32Array(); stamp.resize(mesh.n); stamp.fill(-1); var picked: Array = []; var paths: Array = []; var filled := {}
	for c in order:
		if picked.size()>=14: break
		var near := false
		for p in picked:
			if Sphere.distance(mesh,c,p)<1.4*dist[p]: near = true; break
		if near or not separate(c,dist,open,stamp): continue
		picked.append(c); paths.append(sea_path(c,dist))
	for c in order:
		if picked.size()>=14 or dist[c]<45: break
		var far := true; var ch := Chart.new(geo,c)
		for i in range(picked.size()):
			var p: int = picked[i]; var r := maxf(dist[p],dist[c])
			if Sphere.distance(mesh,c,p)<1.8*r or segment_distance(ch,paths[i],ch.u(c),ch.v(c))<r: far = false; break
		if not far: continue
		picked.append(c); paths.append(sea_path(c,dist)); filled[c] = true
	if picked.is_empty(): return []
	var ranked := picked.duplicate(); ranked.sort_custom(func(a,b): return a<b if dist[a]==dist[b] else dist[a]>dist[b]); var oceans := {}
	for c in ranked:
		if dist[c]>=100 and dist[c]>=11*spacing and oceans.size()<4: oceans[c] = true
	if oceans.is_empty() and dist[ranked[0]]>=11*spacing: oceans[ranked[0]] = true
	var out: Array = []
	for c in picked:
		var d: float = dist[c]; var kind := "ocean" if oceans.has(c) else "bay" if d<27 and enclosure(c,dist)>=.6 else "sea"
		var rank := 1 if kind=="ocean" else (1 if d>=45 else 2 if d>=27 else 3) if kind=="sea" else 2 if d>=30 else 3
		if filled.has(c) and d<75: rank = maxi(rank,2)
		out.append(later("sea",paths[picked.find(c)],rank,d,c,{"t":"sea","kind":kind,"climate":"cold" if world.temperature[c]<2 else "warm" if world.temperature[c]>22 else "mild","dir":"" if kind=="bay" else direction(c)}))
	return out
func direction(c: int) -> String:
	var fx: float = mesh.x[c]/mesh.width; var fy: float = mesh.y[c]/mesh.height
	if absf(fx-.5)>150/360.: fx = .5
	var ex := absf(fx-.5); var ey := absf(fy-.5)*1.3
	if maxf(ex,ey)<.28: return ""
	return ("w" if fx<.5 else "e") if ex>ey else "n" if fy<.5 else "s"
func kmeans(ch: RefCounted,cells: Array,k: int) -> Array:
	var cx: Array = [ch.u(argmax(cells,world.elevation))]; var cy: Array = [ch.v(argmax(cells,world.elevation))]
	while cx.size()<k:
		var best: int = cells[0]; var bd := -1.
		for c in cells:
			var d := INF
			for j in range(cx.size()): d = minf(d,pow(ch.u(c)-cx[j],2)+pow(ch.v(c)-cy[j],2))
			if d>bd: bd = d; best = c
		cx.append(ch.u(best)); cy.append(ch.v(best))
	var label := PackedInt32Array(); label.resize(cells.size())
	for _it in range(10):
		var sx := PackedFloat64Array(); sx.resize(k); var sy := sx.duplicate(); var count := sx.duplicate()
		for i in range(cells.size()):
			var c: int = cells[i]; var bj := 0; var bd := INF
			for j in range(k):
				var d := pow(ch.u(c)-cx[j],2)+pow(ch.v(c)-cy[j],2)
				if d<bd: bd = d; bj = j
			label[i] = bj; sx[bj] += ch.u(c); sy[bj] += ch.v(c); count[bj] += 1
		for j in range(k):
			if count[j]: cx[j] = sx[j]/count[j]; cy[j] = sy[j]/count[j]
	var out: Array = []
	for j in range(k): out.append([])
	for i in range(cells.size()): out[label[i]].append(cells[i])
	return out.filter(func(p): return not p.is_empty())
func mountains() -> Array:
	var threshold := maxf(950,world.maxElevation*.17); var high := PackedByteArray(); high.resize(mesh.n)
	for i in range(mesh.n): high[i] = int(world.water[i]==0 and world.elevation[i]>=threshold)
	var pieces: Array = []
	var weight := func(c): return pow(world.elevation[c]-threshold+300,2)*area[c]
	for cells in components(high):
		var a := sum_area(cells)/cell_area
		if a<18: continue
		var ax := axis(cells,func(c): return area[c]); var k := clampi(floori(a/170+.5),2,4) if a>=170 and ax.s2/maxf(1e-6,ax.s1)>=.33 else 1
		for part in kmeans(ax.ch,cells,k) if k>1 else [cells]:
			var pa := sum_area(part)/cell_area
			if pa<18: continue
			var mass := 0.
			for c in part: mass += (world.elevation[c]-threshold+400)*(area[c]/cell_area)
			pieces.append({"cells":part,"area":pa,"mass":mass})
	pieces.sort_custom(func(a,b): return a.cells[0]<b.cells[0] if a.mass==b.mass else a.mass>b.mass); var out: Array = []
	for i in range(mini(18,pieces.size())):
		var m: Dictionary = pieces[i]; var ax := axis(m.cells,weight); var path := PackedFloat32Array(); var size := 0.
		if ax.s1/maxf(1e-6,ax.s2)>=1.7:
			path = spine(m.cells,ax,weight)
			for j in range(2,path.size(),2): size += geo.point_distance(path[j],path[j+1],path[j-2],path[j-1])
		else:
			var top := argmax(m.cells,world.elevation); var half := maxf(2*spacing,ax.s1*1.4); var xy: Array = ax.ch.to_xy((ax.ch.u(top)+ax.cx)/2,(ax.ch.v(top)+ax.cy)/2); var ch := Chart.new(geo,0,xy[0],xy[1]); var uv := ch.to_uv(xy[0],xy[1]); path = path_of(ch,[uv[0]-half,uv[1],uv[0],uv[1],uv[0]+half,uv[1]]); size = half*2
		var rank := 1 if i<7 and m.area>=50 else 2 if m.area>=28 else 3; var mid := (path.size()>>2)<<1; var anchor := nearest(path[mid],path[mid+1])
		out.append(later("mountains",path,rank,size,anchor,{"t":"direct","from":"mountain"}))
	return out
func areas(kind: String) -> Array:
	var mask := PackedByteArray(); mask.resize(mesh.n)
	for i in range(mesh.n): mask[i] = int(world.water[i]==2 and world.biome[i]!=3) if kind=="lake" else int(world.water[i]!=1) if kind=="island" else int(world.water[i]==0 and world.biome[i] in [6,7,11])
	var comps: Array = []; var largest := 0.
	for cells in components(mask):
		var a := sum_area(cells)/cell_area; comps.append({"cells":cells,"area":a}); largest = maxf(largest,a)
	var minimum := 3. if kind=="lake" else 9. if kind=="island" else 35.
	comps = comps.filter(func(c): return c.area>=minimum and (kind!="island" or c.area<=minf(2600,largest*.22)))
	comps.sort_custom(func(a,b): return a.cells[0]<b.cells[0] if a.area==b.area else a.area>b.area); comps = comps.slice(0,10 if kind=="lake" else 14 if kind=="island" else 6)
	if comps.is_empty(): return []
	var dist := distance_field(mask); var out: Array = []
	for i in range(comps.size()):
		var c: Dictionary = comps[i]; var a := argmax(c.cells,dist); var r := sqrt(c.area*cell_area/PI); var path := PackedFloat32Array([mesh.x[a],mesh.y[a]]); var rank := 3; var req := {}
		if kind=="lake": rank = 1 if (i<2 and c.area>=14) or (i<1 and c.area>=5) else 2 if c.area>=6 else 3; req = {"t":"derived","from":"sea","suffix":"湖","keep":["泽","泊"],"shortest":true}
		elif kind=="island": rank = 1 if c.area>=110 or (i<2 and c.area>=20) else 2 if c.area>=32 else 3; req = {"t":"derived","from":"mountain","suffix":"岛","keep":[],"shortest":true}
		else:
			var hot := 0; var cold := 0
			for cell in c.cells:
				if world.biome[cell]==11: hot += 1
				elif world.biome[cell]==6: cold += 1
			var other: int = c.cells.size()-hot-cold; var suffix := "沙漠" if hot>=other and hot>=cold else "荒原" if cold>other else "荒漠"
			rank = 1 if c.area>=200 else 2 if c.area>=80 else 3; req = {"t":"derived","from":"region","suffix":suffix,"keep":["漠","荒","原"]}
		if kind!="lake": path = axis_path(dist,a,axis(c.cells,func(cell): return area[cell]),r)
		out.append(later(kind,path,rank,r,a,req))
	return out
func axis_path(dist: Variant,a: int,ax: Dictionary,r: float) -> PackedFloat32Array:
	var ch: RefCounted = ax.ch; var x: float = ch.u(a); var y: float = ch.v(a); var mc := Chart.new(geo,a,mesh.x[a],mesh.y[a]); var mx: float = mc.u(a); var my: float = mc.v(a)
	var elong: float = ax.s1/maxf(1e-6,ax.s2); var ang := Maths.round24(atan2(ax.uy,ax.ux)); var margin := maxf(spacing*.8,dist[a]*.3); var max_half := maxf(r*1.6,ax.s1*2)
	if elong>=1.8 and absf(ang)>deg_to_rad(55):
		var v := chord(mc,dist,mx,my,true,margin,max_half); return path_of(mc,[mx,my-v[0],mx,my+(v[1]-v[0])/2,mx,my+v[1]])
	if elong>=1.8 and absf(ang)>deg_to_rad(12) and absf(ang)<deg_to_rad(40):
		var sides: Array = []
		for dir in [-1,1]:
			var s := 0.
			while s<max_half:
				var ns := s+spacing*.5; var xy: Array = ch.to_xy(x+dir*ax.ux*ns,y+dir*ax.uy*ns)
				if dist[nearest(xy[0],xy[1])]<margin: break
				s = ns
			sides.append(s)
		return path_of(ch,[x-ax.ux*sides[0],y-ax.uy*sides[0],x+ax.ux*(sides[1]-sides[0])/2,y+ax.uy*(sides[1]-sides[0])/2,x+ax.ux*sides[1],y+ax.uy*sides[1]])
	var h := chord(mc,dist,mx,my,false,margin,max_half); return path_of(mc,[mx-h[0],my,mx+(h[1]-h[0])/2,my,mx+h[1],my])

func name_all() -> void:
	var ordered := pending.duplicate()
	ordered.sort_custom(func(a,b): return a.index<b.index if a.p.cell==b.p.cell else a.p.cell<b.p.cell if a.p.kind==b.p.kind else KIND_ORDER[a.p.kind]<KIND_ORDER[b.p.kind])
	for item in ordered:
		var p: Dictionary = item.p; var req: Dictionary = item.req; var salt: int = KIND_ORDER[p.kind]
		if req.t=="sea": p.name = sea_name(p.cell,req); continue
		var stream = namer.keyed(req.from,[p.cell,salt]); var value: Dictionary = stream.next()
		if req.t=="direct":
			for _t in range(400):
				if not used.has(value.zh): break
				value = stream.next()
			p.name = value.zh
			if value.has("latin"): p.latin = value.latin
		else:
			var last := ""; var best := {}; var seen := 0
			for t in range(400):
				if seen>=(3 if req.get("shortest",false) else 1): break
				if t: value = stream.next()
				var core: String = value.zh; var generic: String = value.get("generic","")
				if not generic.is_empty() and core.ends_with(generic) and core.length()>generic.length(): core = core.left(core.length()-generic.length())
				if core.ends_with("之") and core.length()>1: core = core.left(-1)
				var zh: String = value.zh if not generic.is_empty() and generic in req.keep else core+req.suffix
				if not used.has(zh): last = zh
				if core.contains("之") or zh.length()>6 or zh.length()<2 or used.has(zh): continue
				seen += 1
				if best.is_empty() or zh.length()<best.zh.length(): best = {"zh":zh,"latin":value.get("latin","")}
			p.name = best.zh if not best.is_empty() else last
			if not best.is_empty() and not best.latin.is_empty(): p.latin = best.latin
		used[p.name] = true
	pending.clear()
func sea_name(cell: int,req: Dictionary) -> String:
	var r := Maths.Stream.new(floori(Maths.keyed(sea_base,cell)*4294967296.))
	for _t in range(40):
		var zh := ""; var dir: String = req.dir; var climate: String = req.climate; var words := ""
		if req.kind=="ocean":
			if not dir.is_empty() and r.next()<.45: zh = {"n":"北","s":"南","e":"东","w":"西"}[dir]+"大洋"
			else:
				words = "永冬 冰封 极光 霜冠 寒星" if climate=="cold" and r.next()<.7 else "暖流 珊瑚 翡翠 碧波 金阳" if climate=="warm" and r.next()<.5 else "长风 落日 晨曦 无垠 苍茫 沧浪 静澜 怒涛 远帆 星辉 鲸歌 云帆 天青 镜光 暮光 浩渺"
				zh = Names.pick(r,Array(words.split(" ")))+"洋"
		elif req.kind=="sea":
			if not dir.is_empty() and r.next()<.2: zh = {"n":"北","s":"南","e":"东","w":"西"}[dir]+"海"
			else:
				words = "冰 霜 雪 白 极光 寒冰 冰牙" if climate=="cold" and r.next()<.6 else "暖 珊瑚 翡翠 金沙 碧玉" if climate=="warm" and r.next()<.4 else "静 暮 翠 银 雾 潮 镜 玉 晴 云 碧 蔚 琉璃 寒鸦 白鲸 风暴 迷雾 群星 明月 潮声 长夜"
				zh = Names.pick(r,Array(words.split(" ")))+"海"
		else:
			words = "寒 冰 霜 白熊 海豹" if climate=="cold" and r.next()<.5 else "月牙 弯刀 静水 渔人 白帆 鹭 燕 鲸 雾 银 金 蓝 碧 镜 风 落霞 长滩 海豹 珍珠 贝壳 灯塔 归帆 渡鸦"
			zh = Names.pick(r,Array(words.split(" ")))+"湾"
		if not used.has(zh): used[zh] = true; return zh
	var suffix: String = "洋" if req.kind=="ocean" else "海" if req.kind=="sea" else "湾"; var i := 2
	while true:
		var zh := "第"+"二三四五六七八九十"[mini(8,i-2)]+suffix+(str(i) if i>10 else "")
		if not used.has(zh): used[zh] = true; return zh
		i += 1
	return ""
