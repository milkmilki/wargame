extends RefCounted
## civ-atlas 103afd3 render/civ/borders.ts trace/merge/coast/finish. AGPL-3.0-only.
const Maths = preload("res://scripts/atlas/math.gd")
const Geo = preload("res://scripts/atlas/sphere_mesh.gd")

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

class Tracer:
	var mesh: Dictionary; var node_of := {}; var nx: Array[float] = []; var ny: Array[float] = []
	var la: Array[int] = []; var lb: Array[int] = []; var ll: Array[int] = []; var lr: Array[int] = []
	var links: Array = []; var deg := PackedInt32Array(); var used := PackedByteArray()
	var left: Array[int] = []; var right: Array[int] = []; var n0: Array[int] = []; var n1: Array[int] = []
	var start: Array[int] = [0]; var points: Array[float] = []
	func _init(value: Dictionary) -> void: mesh = value
	func node(key: int,p: Array) -> int:
		if node_of.has(key): return node_of[key]
		var id := nx.size(); node_of[key] = id; nx.append(p[0]); ny.append(p[1]); links.append([]); return id
	func mid(a: int,b: int) -> int:
		return node(mini(a,b)*int(mesh.n)+maxi(a,b),Geo.sphere_mean(mesh,a,b))
	func left_of(a: int,b: int,cell: int) -> bool:
		return (Geo.near_x(nx[b],nx[a],mesh.width)-nx[a])*(mesh.y[cell]-ny[a])-(ny[b]-ny[a])*(Geo.near_x(mesh.x[cell],nx[a],mesh.width)-nx[a])>0
	func link(a: int,b: int,l: int,r: int) -> void:
		var id := la.size(); la.append(a); lb.append(b); ll.append(l); lr.append(r); links[a].append(id); links[b].append(id)
	func walk(first: int,edge: int) -> void:
		var current := first; var li := edge; var p0 := points.size()
		var fwd := la[li]==current; left.append(ll[li] if fwd else lr[li]); right.append(lr[li] if fwd else ll[li])
		points.append(nx[current]); points.append(ny[current])
		while true:
			used[li] = 1; current = lb[li] if la[li]==current else la[li]
			points.append(nx[current]); points.append(ny[current])
			if deg[current]!=2 or current==first: break
			var next := -1
			for k in links[current]:
				if not used[k]: next = k
			if next<0: break
			li = next
		var closed := current==first and deg[first]==2
		n0.append(-1 if closed else first); n1.append(-1 if closed else current)
		for i in range(p0+2,points.size(),2): points[i] = Geo.near_x(points[i],points[i-2],mesh.width)
		start.append(points.size()/2)

static func trace(mesh: Dictionary,label: PackedInt32Array) -> Dictionary:
	var state := Tracer.new(mesh); var triangles: PackedInt32Array = mesh.triangles
	for t in range(0,triangles.size(),3):
		var v := [triangles[t],triangles[t+1],triangles[t+2]]
		var l := [label[v[0]],label[v[1]],label[v[2]]]; var diff: Array[int] = []
		for e in range(3):
			if l[e]>=0 and l[(e+1)%3]>=0 and l[e]!=l[(e+1)%3]: diff.append(e)
		if diff.is_empty(): continue
		if diff.size()==2:
			var e1 := diff[0]; var e2 := diff[1]; var odd := e2 if (e1+1)%3==e2 else e1; var other := (odd+1)%3
			var m1 := state.mid(v[e1],v[(e1+1)%3]); var m2 := state.mid(v[e2],v[(e2+1)%3])
			if state.left_of(m1,m2,v[odd]): state.link(m1,m2,l[odd],l[other])
			else: state.link(m1,m2,l[other],l[odd])
		else:
			var center := state.node(int(mesh.n)*int(mesh.n)+t/3,sphere_mean(mesh,v[0],v[1],v[2]))
			for e in diff:
				var midpoint := state.mid(v[e],v[(e+1)%3])
				if state.left_of(midpoint,center,v[e]): state.link(midpoint,center,l[e],l[(e+1)%3])
				else: state.link(midpoint,center,l[(e+1)%3],l[e])
	state.deg.resize(state.nx.size()); state.used.resize(state.la.size())
	for i in range(state.deg.size()): state.deg[i] = state.links[i].size()
	for a in range(state.deg.size()):
		if state.deg[a]==2: continue
		for k in state.links[a]:
			if not state.used[k]: state.walk(a,k)
	for i in range(state.la.size()):
		if not state.used[i]: state.walk(state.la[i],i)
	var inc_links: Array = []; for _i in range(state.deg.size()): inc_links.append([])
	for c in range(state.left.size()):
		if state.n0[c]>=0: inc_links[state.n0[c]].append(c)
		if state.n1[c]>=0 and state.n1[c]!=state.n0[c]: inc_links[state.n1[c]].append(c)
	var inc_start := PackedInt32Array([0]); var inc := PackedInt32Array()
	for list in inc_links: inc.append_array(PackedInt32Array(list)); inc_start.append(inc.size())
	return {"count":state.left.size(),"left":PackedInt32Array(state.left),"right":PackedInt32Array(state.right),
		"n0":PackedInt32Array(state.n0),"n1":PackedInt32Array(state.n1),"start":PackedInt32Array(state.start),
		"pts":PackedFloat32Array(state.points),"nodeDeg":state.deg,"incStart":inc_start,"inc":inc,"wrap":mesh.width}

class Merger:
	var rc: Dictionary; var owner: PackedInt32Array; var selected := PackedByteArray(); var degree := PackedInt32Array(); var used := PackedByteArray()
	var buffer: Array[float] = []; var out: Array = []
	func _init(value: Dictionary,owners: PackedInt32Array) -> void:
		rc = value; owner = owners; selected.resize(rc.count); used.resize(rc.count); degree.resize(rc.nodeDeg.size())
		for c in range(rc.count):
			if owner[rc.left[c]]==owner[rc.right[c]]: continue
			selected[c] = 1
			if rc.n0[c]>=0: degree[rc.n0[c]] += 1; degree[rc.n1[c]] += 1
	func append_chain(c: int,fwd: bool) -> void:
		var s: int = rc.start[c]; var e: int = rc.start[c+1]; var skip := 0 if buffer.is_empty() else 1; var shift := 0.0
		if not buffer.is_empty():
			var x: float = rc.pts[s*2] if fwd else rc.pts[(e-1)*2]; shift = Geo.near_x(x,buffer[-2],rc.wrap)-x
		for i in range(s+skip,e) if fwd else range(e-1-skip,s-1,-1):
			buffer.append(rc.pts[i*2]+shift); buffer.append(rc.pts[i*2+1])
	func walk(from: int,c0: int) -> void:
		buffer.clear(); var c := c0; var at := from; var forward: bool = rc.n0[c]==at
		var l := owner[rc.left[c]] if forward else owner[rc.right[c]]
		var r := owner[rc.right[c]] if forward else owner[rc.left[c]]
		while true:
			used[c] = 1; forward = rc.n0[c]==at; append_chain(c,forward); at = rc.n1[c] if forward else rc.n0[c]
			if degree[at]!=2 or at==from: break
			var nc := -1
			for k in range(rc.incStart[at],rc.incStart[at+1]):
				var q: int = rc.inc[k]
				if selected[q] and not used[q]: nc = q
			if nc<0: break
			c = nc
		var closed := at==from and degree[from]==2
		out.append({"pts":PackedFloat32Array(buffer),"closed":closed,"left":l,"right":r,"end0":not closed and rc.nodeDeg[from]==1,"end1":not closed and rc.nodeDeg[at]==1})

static func merge(rc: Dictionary,owner: PackedInt32Array) -> Array:
	var state := Merger.new(rc,owner)
	for c in range(rc.count):
		if not state.selected[c] or state.used[c] or rc.n0[c]>=0: continue
		state.used[c] = 1; state.buffer.clear(); state.append_chain(c,true)
		state.out.append({"pts":PackedFloat32Array(state.buffer),"closed":true,"left":owner[rc.left[c]],"right":owner[rc.right[c]],"end0":false,"end1":false})
	for c in range(rc.count):
		if not state.selected[c] or state.used[c]: continue
		for end in [rc.n0[c],rc.n1[c]]:
			if state.used[c] or state.degree[end]==2: continue
			state.walk(end,c)
	for c in range(rc.count):
		if state.selected[c] and not state.used[c]: state.walk(rc.n0[c],c)
	return state.out

static func smooth_flat(points: PackedFloat32Array,closed: bool,rounds: int) -> PackedFloat32Array:
	var p := points.duplicate()
	for _round in range(rounds):
		var m := p.size()/2
		if m<3: break
		var q := PackedFloat32Array()
		if not closed: q.append(p[0]); q.append(p[1])
		for i in range(m-1):
			q.append(.75*p[2*i]+.25*p[2*i+2]); q.append(.75*p[2*i+1]+.25*p[2*i+3])
			q.append(.25*p[2*i]+.75*p[2*i+2]); q.append(.25*p[2*i+1]+.75*p[2*i+3])
		if not closed: q.append(p[-2]); q.append(p[-1])
		else: q.append(q[0]+(p[-2]-p[0])); q.append(q[1])
		p = q
	return p

static func finish(line: Dictionary) -> Dictionary:
	var p := smooth_flat(line.pts,line.closed,2); var q := p.duplicate(); var m := p.size()/2
	for i in range(1,m-1):
		var w := 1.0 if line.closed else minf(1.0,minf(i/10.0,(m-1-i)/10.0))
		var tx := p[(i+1)*2]-p[(i-1)*2]; var ty := p[(i+1)*2+1]-p[(i-1)*2+1]
		var length := sqrt(tx*tx+ty*ty); if length==0: length = 1
		var x := p[2*i]; var y := p[2*i+1]; var d := .55*w*(2*Maths.value_noise(x/5,y/5,71)-1)
		q[2*i] = x-ty/length*d; q[2*i+1] = y+tx/length*d
	if line.closed and m>1: q[-2] = q[0]+(p[-2]-p[0]); q[-1] = q[1]
	var result := line.duplicate(); result.pts = q; return result

static func raster_at(x: float,y: float,w: int,h: int) -> int:
	var py := int(floor(y))
	return -1 if py<0 or py>=h else py*w+mini(w-1,int(floor(x-w*floor(x/w))))

static func coast_tip(ex: float,ey: float,tx: float,ty: float,left: int,right: int,mesh: Dictionary,raster: Dictionary,region_of: PackedInt32Array,owner: PackedInt32Array) -> Array:
	var w: int = raster.w; var h: int = raster.h; var k0 := raster_at(ex,ey,w,h)
	if k0<0 or raster.water[k0]!=0: return []
	var c0: int = raster.cell[k0]; var candidates := [c0]
	for k in range(mesh.adj_start[c0],mesh.adj_start[c0+1]): candidates.append(mesh.adj[k])
	var la := -1; var ra := -1; var ld := INF; var rd := INF
	for c in candidates:
		var r := region_of[c]
		if r<0: continue
		var o := owner[r]
		if o!=left and o!=right: continue
		var dx := near_x(mesh.x[c],ex,w)-ex; var dy: float = mesh.y[c]-ey; var d := dx*dx+dy*dy
		if o==left and d<ld: ld = d; la = c
		if o==right and d<rd: rd = d; ra = c
	if la<0 or ra<0: return []
	var ax := near_x(mesh.x[la],ex,w); var bx := near_x(mesh.x[ra],ex,w)
	var dx: float = -(mesh.y[ra]-mesh.y[la]); var dy := bx-ax; var length := sqrt(dx*dx+dy*dy)
	if length<=0: return []
	dx /= length; dy /= length
	if dx*tx+dy*ty<0: dx = -dx; dy = -dy
	if (ax-ex)*-dy+(mesh.y[la]-ey)*dx<=0: return []
	for step in range(1,65):
		var x := ex+dx*step*.25; var y := ey+dy*step*.25; var k := raster_at(x,y,w,h)
		if k<0: return []
		if raster.water[k]!=0: return [x,y]
		var c: int = raster.cell[k]
		if c!=la and c!=ra and region_of[c]>=0: return []
	return []

static func to_coast(line: Dictionary,mesh: Dictionary,raster: Dictionary,region_of: PackedInt32Array,owner: PackedInt32Array) -> Dictionary:
	var p: PackedFloat32Array = line.pts; var m := p.size()/2
	if line.closed or not (line.end0 or line.end1) or m<2: return line
	var back := mini(m-1,4); var a: Array = []; var b: Array = []
	if line.end0: a = coast_tip(p[0],p[1],p[0]-p[back*2],p[1]-p[back*2+1],line.right,line.left,mesh,raster,region_of,owner)
	if line.end1: b = coast_tip(p[-2],p[-1],p[-2]-p[(m-1-back)*2],p[-1]-p[(m-1-back)*2+1],line.left,line.right,mesh,raster,region_of,owner)
	if a.is_empty() and b.is_empty(): return line
	var q := PackedFloat32Array(a); q.append_array(p); q.append_array(PackedFloat32Array(b))
	var result := line.duplicate(); result.pts = q; return result

static func build(chains: Dictionary,owners: PackedInt32Array,mesh: Dictionary,raster: Dictionary,region_of: PackedInt32Array) -> Array:
	var result: Array = []
	for line in merge(chains,owners): result.append(finish(to_coast(line,mesh,raster,region_of,owners)))
	return result
