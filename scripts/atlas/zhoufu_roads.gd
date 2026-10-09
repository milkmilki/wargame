extends RefCounted
## Atlas terrain routes with immutable administrative links and shared edge costs.
const Maths = preload("res://scripts/atlas/math.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const MODEL := "atlas-zhoufu-roads-v1"

static func costs(mesh: Dictionary,env: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(mesh.adj.size())
	for cell in range(mesh.n):
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if not Roads.passable(env,cell) or not Roads.passable(env,next): out[slot] = -1.; continue
			var a := maxf(0.,env.elevation[cell]); var b := maxf(0.,env.elevation[next])
			var length: float = mesh.lengths[slot]
			var slope := absf(a-b)/maxf(.000001,length*40000./mesh.width)/2.5
			out[slot] = length*minf(40.,1.+slope*slope)*(1.+(a+b)/6000.)*(Roads.BIOME_COST[env.biome[cell]]+Roads.BIOME_COST[env.biome[next]])*.5
	return out

static func find(mesh: Dictionary,cost: PackedFloat32Array,slots: PackedByteArray,city_at: PackedInt32Array,start: int,goal: int,parent_of: PackedInt32Array,parent: int = -1) -> PackedInt32Array:
	var distance := PackedFloat64Array(); distance.resize(mesh.n); distance.fill(INF)
	var previous := PackedInt32Array(); previous.resize(mesh.n); previous.fill(-1)
	var heap := Maths.Heap.new(); distance[start] = 0.; heap.push(start,.5*Sphere.distance(mesh,start,goal))
	while not heap.empty():
		var cell := heap.pop()
		if heap.last_priority>distance[cell]+.5*Sphere.distance(mesh,cell,goal)+.000001: continue
		var d := distance[cell]
		if cell==goal: break
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if cost[slot]<0. or (parent>=0 and parent_of[next]!=parent): continue
			var value := float(cost[slot])*(.5 if slots[slot]>0 else 1.)*(2. if city_at[next]<0 else 1.)
			var nd := d+value
			if nd<distance[next]: distance[next] = nd; previous[next] = cell; heap.push(next,nd+.5*Sphere.distance(mesh,next,goal))
	var path := PackedInt32Array()
	if not is_finite(distance[goal]): return path
	var cell := goal
	while cell>=0: path.append(cell); cell = previous[cell]
	path.reverse(); return path

static func mark(mesh: Dictionary,slots: PackedByteArray,path: PackedInt32Array,kind: String) -> void:
	for index in range(1,path.size()):
		var a := path[index-1]; var b := path[index]
		var slot := Roads.slot_of(mesh,a,b); var back := Roads.slot_of(mesh,b,a)
		var grade := 1 if kind=="road" else 2
		if slots[slot]>0: grade = mini(grade,slots[slot])
		slots[slot] = grade; slots[back] = grade

static func pieces(mesh: Dictionary,slots: PackedByteArray) -> Array:
	var routes: Array = []
	for cell in range(mesh.n):
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if next<=cell or slots[slot]==0: continue
			routes.append({"cells":PackedInt32Array([cell,next]),"kind":"road" if slots[slot]==1 else "trail","built":0})
	return routes

static func build(mesh: Dictionary,env: Dictionary,regions: Dictionary,h: Dictionary) -> Dictionary:
	var cost := costs(mesh,env); var slots := PackedByteArray(); slots.resize(mesh.adj.size())
	var terrain_danger := PackedFloat32Array(); terrain_danger.resize(mesh.adj.size())
	for slot in range(cost.size()): terrain_danger[slot] = clampf((float(cost[slot])/maxf(.000001,mesh.lengths[slot])-1.)/39.,0.,1.) if cost[slot]>=0. else 0.
	var city_at := PackedInt32Array(); city_at.resize(mesh.n); city_at.fill(-1)
	for c in range(h.cities.size()): city_at[h.cities[c].cell] = c
	var connections: Array = []
	for link in h.mandatory_connections:
		var path := find(mesh,cost,slots,city_at,h.cities[link.a].cell,h.cities[link.b].cell,regions.of,link.parent)
		assert(path.size()>=2,"Prefecture must be reachable before installation")
		mark(mesh,slots,path,"trail")
		var connection: Dictionary = link.duplicate(); connection.cells = path; connection.kind = "trail"; connections.append(connection)
	var protected_slots := slots.duplicate()
	var all: Array = []; var majors: Array = []
	for c in range(h.cities.size()):
		all.append(c)
		if h.cities[c].major: majors.append(c)
	var jobs: Array = []
	for ids in [majors,all]:
		var source: Array = []
		for c in ids: source.append(h.cities[c].cell)
		var links := Roads.neighbor_graph(mesh,source,cost)
		var forest := spanning_forest(ids.size(),links)
		var forest_keys := {}
		for link in forest: forest_keys[link.a*ids.size()+link.b] = true
		var chosen := Roads.urquhart(ids.size(),links); var used := {}
		for link in chosen: used[link.a*ids.size()+link.b] = true
		for link in forest:
			if not used.has(link.a*ids.size()+link.b): chosen.append(link)
		for link in chosen:
			jobs.append({"a":ids[link.a],"b":ids[link.b],"w":link.w,"kind":"road" if ids==majors else "trail","backbone":forest_keys.has(link.a*ids.size()+link.b)})
	jobs.sort_custom(func(a,b):
		if a.kind!=b.kind: return a.kind=="road"
		if a.w!=b.w: return a.w<b.w
		return a.b<b.b if a.a==b.a else a.a<b.a)
	for job in jobs:
		var path := find(mesh,cost,slots,city_at,h.cities[job.a].cell,h.cities[job.b].cell,regions.of)
		assert(path.size()>=2,"Candidate endpoints belong to the same passable component")
		mark(mesh,slots,path,job.kind)
		if job.backbone: mark(mesh,protected_slots,path,job.kind)
		var connection: Dictionary = job.duplicate(); connection.cells = path; connections.append(connection)
	var routes := Roads.drop_parallel(mesh,pieces(mesh,slots),slots,city_at,protected_slots)
	for connection in connections:
		var intact := true
		for index in range(1,connection.cells.size()):
			if slots[Roads.slot_of(mesh,connection.cells[index-1],connection.cells[index])]==0: intact = false; break
		if not intact: connection.cells = Roads.network_path(mesh,slots,connection.cells[0],connection.cells[-1])
	return {"model":MODEL,"slots":slots,"terrain_danger":terrain_danger,"protected_slots":protected_slots,"routes":routes,"connections":connections}

static func spanning_forest(count: int,links: Array) -> Array:
	var parent := PackedInt32Array()
	for i in range(count): parent.append(i)
	var sorted: Array = links.duplicate()
	sorted.sort_custom(func(a,b):
		if a.w!=b.w: return a.w<b.w
		return a.b<b.b if a.a==b.a else a.a<b.a)
	var result: Array = []
	for link in sorted:
		var a: int = link.a; var b: int = link.b
		while parent[a]!=a: a = parent[a]
		while parent[b]!=b: b = parent[b]
		if a==b: continue
		parent[maxi(a,b)] = mini(a,b); result.append(link)
	return result
