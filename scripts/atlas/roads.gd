extends RefCounted
## Port of civ-atlas 103afd3 gen/civ/routes.ts, static land routes only.
## AGPL-3.0-only. No chronology, river penalty, ports or shipping.
const Maths = preload("res://scripts/atlas/math.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const BIOME_COST = [1,1,1,1,1.25,1.2,1.15,1.15,1,1.1,1.25,1.3,1,1.1,1.4,1.5]

static func seat_cities(mesh: Dictionary,env: Dictionary,regions: Dictionary,threshold: float) -> Array:
	var cities: Array = []; var caps: Array = []
	for r in range(regions.count):
		var s := int(regions.seat[r])
		if float(env.suitability[s]) <= threshold or not passable(env,s): continue
		cities.append({"cell":s,"region":r,"major":false,"port":false,"founded":0})
		caps.append(float(regions.capacity[r]))
	if cities.is_empty(): return cities
	var land_area := 0.0
	for i in range(mesh.n):
		if env.water[i] == 0: land_area += mesh.areas[i]
	var want := maxi(1,int(floor(cities.size()/40.0+0.5)))
	var spacing := sqrt(land_area/want)*0.6
	var order: Array[int] = []; for i in range(cities.size()): order.append(i)
	order.sort_custom(func(a,b): return cities[a].cell<cities[b].cell if caps[a]==caps[b] else caps[a]>caps[b])
	var dist := PackedFloat64Array(); dist.resize(mesh.n); dist.fill(INF)
	var heap := Maths.Heap.new(); var picked := 0
	for c in order:
		if picked >= want: break
		var s: int = cities[c].cell
		if dist[s] < spacing: continue
		cities[c].major = true; picked += 1; dist[s] = 0; heap.clear(); heap.push(s,0)
		while not heap.empty():
			var i := heap.pop(); var d: float = heap.last_priority
			if d > dist[i]: continue
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var j: int = mesh.adj[k]
				if not passable(env,j): continue
				var nd: float = d+mesh.lengths[k]
				if nd < spacing and nd < dist[j]: dist[j] = nd; heap.push(j,nd)
	return cities

static func passable(env: Dictionary,i: int) -> bool:
	return env.water[i] == 0 and env.biome[i] != 3

static func neighbor_graph(mesh: Dictionary,src: Array,cost: PackedFloat32Array) -> Array:
	var dist := PackedFloat64Array(); dist.resize(mesh.n); dist.fill(INF)
	var label := PackedInt32Array(); label.resize(mesh.n); label.fill(-1)
	var heap := Maths.Heap.new()
	for c in range(src.size()):
		var s: int = src[c]
		if label[s] >= 0: continue
		dist[s] = 0; label[s] = c; heap.push(s,0)
	while not heap.empty():
		var i := heap.pop(); var d: float = heap.last_priority
		if d > dist[i]: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if cost[k] < 0: continue
			var j: int = mesh.adj[k]; var nd := d+cost[k]
			if nd < dist[j]: dist[j] = nd; label[j] = label[i]; heap.push(j,nd)
	var best := {}
	for i in range(mesh.n):
		if label[i] < 0: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if cost[k] < 0: continue
			var j: int = mesh.adj[k]
			if label[j] < 0 or label[j] == label[i]: continue
			var a := mini(label[i],label[j]); var b := maxi(label[i],label[j])
			var key := a*src.size()+b; var w := dist[i]+cost[k]+dist[j]
			if not best.has(key) or w < best[key].w: best[key] = {"a":a,"b":b,"w":w}
	var links: Array = best.values()
	links.sort_custom(func(a,b): return a.b<b.b if a.a==b.a else a.a<b.a)
	return links

static func longer(a: Dictionary,b: Dictionary) -> bool:
	if a.w != b.w: return a.w > b.w
	return a.b > b.b if a.a == b.a else a.a > b.a

static func urquhart(count: int,links: Array) -> Array:
	var nb: Array = []; for _i in range(count): nb.append({})
	for i in range(links.size()):
		var e: Dictionary = links[i]; nb[e.a][e.b] = i; nb[e.b][e.a] = i
	var drop := PackedByteArray(); drop.resize(links.size())
	for a in range(count):
		var neighbors: Array = []
		for b in nb[a]:
			if b>a: neighbors.append(b)
		neighbors.sort()
		for s in range(neighbors.size()):
			var b: int = neighbors[s]
			for t in range(s+1,neighbors.size()):
				var c: int = neighbors[t]
				if not nb[b].has(c): continue
				var m: int = nb[a][b]
				if longer(links[nb[a][c]],links[m]): m = nb[a][c]
				if longer(links[nb[b][c]],links[m]): m = nb[b][c]
				drop[m] = 1
	var kept: Array = []
	for i in range(links.size()):
		if not drop[i]: kept.append(links[i])
	return kept

static func slot_of(mesh: Dictionary,a: int,b: int) -> int:
	for k in range(mesh.adj_start[a],mesh.adj_start[a+1]):
		if mesh.adj[k] == b: return k
	return -1

class Finder:
	var g := PackedFloat64Array(); var prev := PackedInt32Array()
	var seen := PackedInt32Array(); var done := PackedInt32Array(); var stamp := 0
	var heap := Maths.Heap.new()
	func _init(n: int) -> void:
		g.resize(n); prev.resize(n); seen.resize(n); done.resize(n)
	func find(mesh: Dictionary,cost: PackedFloat32Array,on_road: PackedByteArray,city_at: PackedInt32Array,start: int,goal: int) -> PackedInt32Array:
		stamp += 1; seen[start] = stamp; g[start] = 0; prev[start] = -1; heap.clear()
		heap.push(start,0.5*Sphere.distance(mesh,start,goal))
		while not heap.empty():
			var i := heap.pop()
			if done[i] == stamp: continue
			done[i] = stamp
			if i == goal: break
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var c := float(cost[k])
				if c < 0: continue
				var j: int = mesh.adj[k]
				if done[j] == stamp: continue
				if on_road[i] and on_road[j]: c *= 0.5
				if city_at[j] < 0: c *= 2.0
				var ng := g[i]+c
				if seen[j] != stamp or ng < g[j]:
					seen[j] = stamp; g[j] = ng; prev[j] = i; heap.push(j,ng+0.5*Sphere.distance(mesh,j,goal))
		var path := PackedInt32Array()
		if done[goal] != stamp: return path
		var i := goal
		while i >= 0: path.append(i); i = prev[i]
		path.reverse(); return path

static func build(mesh: Dictionary,env: Dictionary,cities: Array) -> Dictionary:
	var n: int = mesh.n; var adj: PackedInt32Array = mesh.adj
	var cost := PackedFloat32Array(); cost.resize(adj.size())
	var elevation := PackedFloat32Array(env.elevation); var biome := PackedByteArray(env.biome)
	var km := 40000.0/float(mesh.width)
	for i in range(n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j := adj[k]
			if not passable(env,i) or not passable(env,j): cost[k] = -1; continue
			var length: float = mesh.lengths[k]
			var ei := maxf(0,elevation[i]); var ej := maxf(0,elevation[j])
			var sr := absf(ej-ei)/(length*km)/2.5
			var f := minf(40,1+sr*sr)*(1+(ei+ej)/2.0/3000.0)
			f *= (BIOME_COST[biome[i]]+BIOME_COST[biome[j]])/2.0
			cost[k] = length*f
	var city_at := PackedInt32Array(); city_at.resize(n); city_at.fill(-1)
	var all: Array = []; var majors: Array = []
	for c in range(cities.size()):
		city_at[cities[c].cell] = c
		if not passable(env,cities[c].cell): continue
		all.append(c)
		if cities[c].major: majors.append(c)
	var jobs: Array = []
	for ids in [majors,all]:
		var src: Array = []; for c in ids: src.append(cities[c].cell)
		var links := urquhart(src.size(),neighbor_graph(mesh,src,cost))
		for e in links: jobs.append({"a":ids[e.a],"b":ids[e.b],"w":e.w,"kind":"road" if ids==majors else "trail"})
	jobs.sort_custom(func(a,b):
		if a.kind != b.kind: return a.kind == "road"
		if a.w != b.w: return a.w < b.w
		return a.b < b.b if a.a == b.a else a.a < b.a)
	var on_road := PackedByteArray(); on_road.resize(n)
	var slots := PackedByteArray(); slots.resize(adj.size())
	var finder := Finder.new(n); var pieces: Array = []; var connections: Array = []
	for e in jobs:
		var path := finder.find(mesh,cost,on_road,city_at,cities[e.a].cell,cities[e.b].cell)
		if path.is_empty(): continue
		connections.append({"a":e.a,"b":e.b,"kind":e.kind,"cells":path})
		var cur := PackedInt32Array()
		for t in range(1,path.size()):
			var a := path[t-1]; var b := path[t]; var k := slot_of(mesh,a,b)
			if slots[k]:
				if cur.size() >= 2: pieces.append({"kind":e.kind,"cells":cur,"built":0})
				cur = PackedInt32Array(); continue
			var back := slot_of(mesh,b,a)
			slots[k] = 1 if e.kind == "road" else 2; slots[back] = slots[k]
			if cur.is_empty(): cur.append(a)
			cur.append(b)
		if cur.size() >= 2: pieces.append({"kind":e.kind,"cells":cur,"built":0})
		for c in path: on_road[c] = 1
	var routes := drop_parallel(mesh,pieces,slots,city_at)
	# Shared visual segments are deduplicated, while each connection retains a full path.
	# If a redundant spur was removed, rebuild its connection along the surviving network.
	for connection in connections:
		var intact := true
		for t in range(1,connection.cells.size()):
			if not slots[slot_of(mesh,connection.cells[t-1],connection.cells[t])]: intact = false; break
		if not intact: connection.cells = network_path(mesh,slots,connection.cells[0],connection.cells[-1])
	return {"routes":routes,"connections":connections,"slots":slots}

static func is_stop(mesh: Dictionary,slots: PackedByteArray,city_at: PackedInt32Array,i: int) -> bool:
	if city_at[i] >= 0: return true
	var degree := 0; var kinds := 0
	for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
		if not slots[k]: continue
		degree += 1; kinds |= 1 << slots[k]
	return degree != 2 or (kinds & (kinds-1)) != 0

static func set_slots(mesh: Dictionary,slots: PackedByteArray,chain: Dictionary,value: int) -> void:
	for t in range(chain.slots.size()):
		slots[chain.slots[t]] = value; slots[slot_of(mesh,chain.cells[t+1],chain.cells[t])] = value

static func network_path(mesh: Dictionary,slots: PackedByteArray,start: int,goal: int,limit: float = INF) -> PackedInt32Array:
	var dist := PackedFloat64Array(); dist.resize(mesh.n); dist.fill(INF)
	var prev := PackedInt32Array(); prev.resize(mesh.n); prev.fill(-1)
	var heap := Maths.Heap.new(); heap.push(start,0); dist[start] = 0
	while not heap.empty():
		var i := heap.pop(); var d: float = heap.last_priority
		if d > dist[i]: continue
		if i == goal:
			var path := PackedInt32Array(); var c := goal
			while c>=0: path.append(c); c = prev[c]
			path.reverse(); return path
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if not slots[k]: continue
			var j: int = mesh.adj[k]; var nd: float = d+mesh.lengths[k]
			if nd <= limit and nd < dist[j]: dist[j] = nd; prev[j] = i; heap.push(j,nd)
	return PackedInt32Array()

static func drop_parallel(mesh: Dictionary,pieces: Array,slots: PackedByteArray,city_at: PackedInt32Array,protected_slots: PackedByteArray = PackedByteArray()) -> Array:
	var nodes: Array = []; var seen := {}; var chains: Array = []
	for p in pieces:
		for c in p.cells:
			if not seen.has(c): seen[c] = true; nodes.append(c)
	nodes.sort()
	var used := PackedByteArray(); used.resize(slots.size())
	for a in nodes:
		if not is_stop(mesh,slots,city_at,a): continue
		for k0 in range(mesh.adj_start[a],mesh.adj_start[a+1]):
			if slots[k0] != 2 or used[k0]: continue
			var ch := {"cells":PackedInt32Array([a]),"slots":PackedInt32Array(),"len":0.0}
			var k := k0; var previous: int = a
			while true:
				var b: int = mesh.adj[k]; used[k] = 1; used[slot_of(mesh,b,previous)] = 1
				ch.cells.append(b); ch.slots.append(k); ch.len += mesh.lengths[k]
				if is_stop(mesh,slots,city_at,b): break
				var nk := -1
				for q in range(mesh.adj_start[b],mesh.adj_start[b+1]):
					if slots[q] and mesh.adj[q] != previous: nk = q
				if nk < 0 or used[nk] or slots[nk] != 2: break
				previous = b; k = nk
			if ch.cells.size() >= 3: chains.append(ch)
	chains.sort_custom(func(a,b): return a.cells[0]<b.cells[0] if a.len==b.len else a.len>b.len)
	for ch in chains:
		if ch.cells[0] == ch.cells[-1]: continue
		var protected := false
		for slot in ch.slots:
			if not protected_slots.is_empty() and protected_slots[slot]>0: protected = true; break
		if protected: continue
		set_slots(mesh,slots,ch,0)
		var alternative := network_path(mesh,slots,ch.cells[0],ch.cells[-1],1.6*ch.len)
		var redundant := not alternative.is_empty()
		if redundant:
			var near := {}
			for i in alternative:
				near[i] = true
				for k in range(mesh.adj_start[i],mesh.adj_start[i+1]): near[mesh.adj[k]] = true
			for t in range(1,ch.cells.size()-1):
				if not near.has(ch.cells[t]): redundant = false; break
		if not redundant: set_slots(mesh,slots,ch,2)
	var out: Array = []
	for p in pieces:
		var cur := PackedInt32Array()
		for t in range(1,p.cells.size()):
			var a: int = p.cells[t-1]; var b: int = p.cells[t]
			if not slots[slot_of(mesh,a,b)]:
				if cur.size()>=2: out.append({"kind":p.kind,"cells":cur,"built":0})
				cur = PackedInt32Array(); continue
			if cur.is_empty(): cur.append(a)
			cur.append(b)
		if cur.size()>=2: out.append({"kind":p.kind,"cells":cur,"built":0})
	# Godot sort is not stable: retain the insertion order explicitly.
	var result: Array = []
	for kind in ["road","trail"]:
		for p in out:
			if p.kind == kind: result.append(p)
	return result
