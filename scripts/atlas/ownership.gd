extends RefCounted
## Static preview-only rule mirrored by the pinned reference exporter.
## No population, diplomacy, combat, trade or historical simulation.
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")

static func color(hue: float) -> Array:
	var result: Array = []
	for n in [5,3,1]:
		var k := fmod(n+hue*6,6); var channel := .76-.76*.36*maxf(0,minf(k,minf(4-k,1)))
		result.append(int(floor(channel*255+.5)))
	return result

static func build(mesh: Dictionary,regions: Dictionary,cities: Array,target: int = 40,populated_only: bool = false) -> Dictionary:
	var count: int = regions.count; var candidates: Array[int] = []; var present := {}
	for city in cities:
		var r := int(city.region)
		if not present.has(r): present[r] = true; candidates.append(r)
	for r in range(count):
		if not populated_only and not present.has(r): candidates.append(r)
	var seats: Array[int] = []
	if not candidates.is_empty(): seats.append(candidates[0])
	while seats.size()<mini(target,candidates.size()):
		var best := -1; var score := -1.0
		for r in candidates:
			if seats.has(r): continue
			var d := INF
			for s in seats: d = minf(d,Sphere.distance(mesh,regions.seat[r],regions.seat[s]))
			if d>score: score = d; best = r
		seats.append(best)
	var owners := PackedInt32Array(); owners.resize(count); owners.fill(-1)
	var dist := PackedFloat64Array(); dist.resize(count); dist.fill(INF); var queue: Array = []
	for o in range(seats.size()): dist[seats[o]] = 0; owners[seats[o]] = o; queue.append({"r":seats[o],"d":0.0,"owner":o})
	while not queue.is_empty():
		queue.sort_custom(func(a,b):
			if a.d!=b.d: return a.d>b.d
			if a.owner!=b.owner: return a.owner>b.owner
			return a.r>b.r)
		var current: Dictionary = queue.pop_back()
		if current.d!=dist[current.r] or current.owner!=owners[current.r]: continue
		for k in range(regions.adjStart[current.r],regions.adjStart[current.r+1]):
			if regions.adjKind[k]>=3: continue
			var next := int(regions.adj[k]); var d: float = current.d+regions.adjLen[k]
			if d<dist[next]: dist[next] = d; owners[next] = current.owner; queue.append({"r":next,"d":d,"owner":current.owner})
	var components := {}
	for r in range(count):
		var component := int(regions.landmass[r])
		if not components.has(component): components[component] = []
		components[component].append(r)
	for rs in components.values():
		var owned := false
		for r in rs:
			if owners[r]>=0: owned = true; break
		if owned or seats.is_empty(): continue
		var owner := 0; var best := INF
		for r in rs:
			for o in range(seats.size()):
				var d := Sphere.distance(mesh,regions.seat[r],regions.seat[seats[o]])
				if d<best: best = d; owner = o
		for r in rs: owners[r] = owner
	var nations: Array = []
	for i in range(seats.size()):
		var hue := fmod(i*.61803398875,1)
		nations.append({"name":"%s%d"%[["岚","苍","澜","景","宁","岳","临","云"][i%8],i/8+1],"seat":seats[i],"hue":hue,"color":color(hue)})
	return {"ownership":owners,"nations":nations}
