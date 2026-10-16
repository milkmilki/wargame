extends RefCounted
## Atlas terrain routes with immutable administrative links and shared edge costs.
const Maths = preload("res://scripts/atlas/math.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const MODEL := "atlas-zhoufu-roads-v2"

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
	var network := {"model":MODEL,"slots":slots,"terrain_danger":terrain_danger,"protected_slots":protected_slots,"routes":routes,"connections":connections}
	# Global shortcuts and pruning do not preserve jurisdiction access. Repair
	# local land entries afterwards, before compressing the physical graph.
	network.jurisdiction_repair = ensure_jurisdiction_entries(mesh,h,network,cost)
	return network

static func _local_route_exists(mesh: Dictionary,slots: PackedByteArray,labels: PackedInt32Array,start: int,goal: int,a: int,b: int) -> bool:
	var seen := {start:true}; var queue: Array[int] = [start]
	while not queue.is_empty():
		var cell: int = queue.pop_back()
		if cell==goal: return true
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if slots[slot]>0 and not seen.has(next) and labels[next] in [a,b]:
				seen[next]=true; queue.append(next)
	return false

static func _root(parents: PackedInt32Array,id: int) -> int:
	while parents[id]!=id: id=parents[id]
	return id

static func _entry_less(a: Dictionary,b: Dictionary) -> bool:
	if a.weight!=b.weight: return a.weight<b.weight
	return a.b<b.b if a.a==b.a else a.a<b.a

static func _install_entry(mesh: Dictionary,network: Dictionary,slots: PackedByteArray,protected_slots: PackedByteArray,border: Dictionary,previous: PackedInt32Array) -> void:
	var path := PackedInt32Array(); var cursor: int = border.left
	while cursor>=0: path.append(cursor); cursor=previous[cursor]
	path.reverse(); cursor=border.right
	while cursor>=0: path.append(cursor); cursor=previous[cursor]
	mark(mesh,slots,path,"trail"); mark(mesh,protected_slots,path,"trail")
	network.connections.append({"a":border.a,"b":border.b,"kind":"trail","cells":path,"jurisdiction_entry":true})

## Local entries must support capturing a state from any neighboring state:
## connect its districts internally, then ensure one entry per state border.
static func ensure_jurisdiction_entries(mesh: Dictionary,h: Dictionary,network: Dictionary,cost: PackedFloat32Array) -> Dictionary:
	var labels: PackedInt32Array = h.district_of_cell
	var slots: PackedByteArray = network.slots
	var protected_slots: PackedByteArray = network.protected_slots
	var distance := PackedFloat64Array(); distance.resize(mesh.n); distance.fill(INF)
	var previous := PackedInt32Array(); previous.resize(mesh.n); previous.fill(-1)
	var heap := Maths.Heap.new()
	for city in h.cities:
		distance[city.cell]=0.; heap.push(city.cell,0.)
	while not heap.empty():
		var cell := heap.pop(); var d: float = heap.last_priority
		if d>distance[cell]: continue
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if cost[slot]<0. or labels[next]!=labels[cell]: continue
			var value := d+float(cost[slot])*(.5 if slots[slot]>0 else 1.)
			if value<distance[next]:
				distance[next]=value; previous[next]=cell; heap.push(next,value)
	var borders := {}
	for cell in range(mesh.n):
		if labels[cell]<0 or not is_finite(distance[cell]): continue
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if next<=cell or cost[slot]<0. or labels[next]<0 or labels[cell]==labels[next] or not is_finite(distance[next]): continue
			var a := mini(labels[cell],labels[next]); var b := maxi(labels[cell],labels[next])
			var key: int = a*h.cities.size()+b
			var weight: float = distance[cell]+cost[slot]+distance[next]
			# Sorted cell/slot traversal resolves equal-cost borders consistently.
			if not borders.has(key) or weight<float(borders[key].weight):
				borders[key]={"a":a,"b":b,"left":cell if labels[cell]==a else next,"right":next if labels[cell]==a else cell,"weight":weight}
	var centers: PackedInt32Array = h.center_by_city
	var parents := PackedInt32Array();for id in range(h.cities.size()):parents.append(id)
	var interior: Array = []; var exterior := {}
	var keys: Array = borders.keys(); keys.sort()
	for key in keys:
		var border: Dictionary = borders[key]
		if centers[border.a]==centers[border.b]:
			if _local_route_exists(mesh,slots,labels,h.cities[border.a].cell,h.cities[border.b].cell,border.a,border.b):
				var a:=_root(parents,border.a);var b:=_root(parents,border.b);parents[maxi(a,b)]=mini(a,b)
			else: interior.append(border)
		else:
			var pair:=Vector2i(mini(centers[border.a],centers[border.b]),maxi(centers[border.a],centers[border.b]))
			if not exterior.has(pair):exterior[pair]=[]
			exterior[pair].append(border)
	interior.sort_custom(_entry_less)
	var added := 0
	for border in interior:
		var a:=_root(parents,border.a);var b:=_root(parents,border.b)
		if a==b:continue
		parents[maxi(a,b)]=mini(a,b)
		if not _local_route_exists(mesh,slots,labels,h.cities[border.a].cell,h.cities[border.b].cell,border.a,border.b):
			_install_entry(mesh,network,slots,protected_slots,border,previous);added+=1
	var state_pairs:Array=exterior.keys();state_pairs.sort_custom(func(a:Vector2i,b:Vector2i):return a.y<b.y if a.x==b.x else a.x<b.x)
	for pair in state_pairs:
		var candidates:Array=exterior[pair];var ready:=false
		for border in candidates:
			if _local_route_exists(mesh,slots,labels,h.cities[border.a].cell,h.cities[border.b].cell,border.a,border.b):ready=true;break
		if ready:continue
		candidates.sort_custom(_entry_less)
		_install_entry(mesh,network,slots,protected_slots,candidates[0],previous);added+=1
	# Publish the repaired packed arrays back to their owning network.
	network.slots=slots
	network.protected_slots=protected_slots
	if added>0: network.routes=pieces(mesh,slots)
	return {"eligible_borders":borders.size(),"added_connections":added}

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
