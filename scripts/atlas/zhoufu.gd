extends RefCounted
## Fixed administrative geometry for the independent Atlas military scenario.
## Parent regions and environmental inputs are read-only. All IDs are stable.
const Maths = preload("res://scripts/atlas/math.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
const MODEL := "atlas-zhoufu-v1"
const MEAN_BUDGET := [3000,28,680]

static func allocate(total: int, weights: Array) -> PackedInt32Array:
	var result := PackedInt32Array(); result.resize(weights.size())
	if weights.is_empty(): return result
	var sum := 0.0
	for weight in weights: sum += maxf(0.,float(weight))
	var remainder: Array = []; var assigned := 0
	for i in range(weights.size()):
		var exact := total*(maxf(0.,float(weights[i]))/sum if sum>0. else 1./weights.size())
		result[i] = floori(exact); assigned += result[i]
		remainder.append({"id":i,"fraction":exact-result[i]})
	remainder.sort_custom(func(a,b): return a.id<b.id if a.fraction==b.fraction else a.fraction>b.fraction)
	for i in range(total-assigned): result[remainder[i].id] += 1
	return result

static func grow(mesh: Dictionary, env: Dictionary, parent_of: PackedInt32Array, seeds: Array, parent: int = -1, passable_only: bool = false) -> PackedInt32Array:
	var labels := PackedInt32Array(); labels.resize(mesh.n); labels.fill(-1)
	var distance := PackedFloat64Array(); distance.resize(mesh.n); distance.fill(INF)
	var heap := Maths.Heap.new()
	for seed_value in seeds:
		var cell: int = seed_value.cell
		labels[cell] = seed_value.id; distance[cell] = 0.; heap.push(cell,0.)
	while not heap.empty():
		var cell := heap.pop(); var d := heap.last_priority
		if d>distance[cell]: continue
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if env.water[next]!=0 or (parent>=0 and parent_of[next]!=parent): continue
			if passable_only and not Roads.passable(env,next): continue
			var slope := absf(float(env.elevation[next])-float(env.elevation[cell]))/maxf(1.,mesh.lengths[slot]*40000./mesh.width)
			var nd: float = d+mesh.lengths[slot]*(1.+minf(39.,slope*slope/6.25))
			if nd<distance[next] or (nd==distance[next] and labels[cell]<labels[next]):
				distance[next] = nd; labels[next] = labels[cell]; heap.push(next,nd)
	return labels

static func build(mesh: Dictionary,env: Dictionary,regions: Dictionary,centers: Array,seed_value: int,threshold: float) -> Dictionary:
	var cities: Array = centers.duplicate(true)
	var state_by_parent := PackedInt32Array(); state_by_parent.resize(regions.count); state_by_parent.fill(-1)
	var state_parents := PackedInt32Array(); var center_by_city := PackedInt32Array(); var state_by_city := PackedInt32Array()
	var districts := PackedInt32Array(); districts.resize(mesh.n); districts.fill(-1)
	var members: Array = []; var mandatory: Array = []
	for c in range(centers.size()):
		var parent: int = centers[c].region
		state_by_parent[parent] = c; state_parents.append(parent)
		cities[c].role = "zhou"; center_by_city.append(c); state_by_city.append(c); members.append([c])
	# New settlements are appended, preserving all original center IDs.
	for state in range(centers.size()):
		var parent: int = state_parents[state]
		var seeds := [{"cell":cities[state].cell,"id":state}]
		var selected := prefectures(mesh,env,regions,parent,cities[state].cell,seed_value,threshold)
		for cell in selected: seeds.append({"cell":cell,"id":cities.size()+seeds.size()-1})
		var labels := grow(mesh,env,regions.of,seeds,parent)
		while seeds.size()>1:
			var sizes := {}; var remove := -1
			for offset in range(regions.cellStart[parent],regions.cellStart[parent+1]):
				var label: int = labels[regions.cells[offset]]
				sizes[label] = sizes.get(label,0)+1
			for index in range(1,seeds.size()):
				if int(sizes.get(seeds[index].id,0))<2: remove = index; break
			if remove<0: break
			seeds.remove_at(remove)
			for index in range(1,seeds.size()): seeds[index].id = cities.size()+index-1
			labels = grow(mesh,env,regions.of,seeds,parent)
		for index in range(1,seeds.size()):
			var id := cities.size()
			cities.append({"cell":seeds[index].cell,"region":parent,"major":false,"port":false,"founded":0,"role":"fu"})
			center_by_city.append(state); state_by_city.append(state); members[state].append(id)
			mandatory.append({"a":state,"b":id,"parent":parent,"protected":true})
		for cell in range(regions.cellStart[parent],regions.cellStart[parent+1]):
			var i: int = regions.cells[cell]
			if env.water[i]==0: districts[i] = labels[i] if labels[i]>=0 else state
	var guardian := guardians(mesh,env,regions,centers)
	for i in range(mesh.n):
		var parent: int = regions.of[i]
		if env.water[i]==0 and parent>=0 and state_by_parent[parent]<0: districts[i] = guardian[parent]
	var h := {"model":MODEL,"cities":cities,"state_by_parent":state_by_parent,"state_parents":state_parents,
		"center_by_city":center_by_city,"state_by_city":state_by_city,"district_of_cell":districts,
		"guardian_by_parent":guardian,"members":members,"mandatory_connections":mandatory,"seed":seed_value,"threshold":threshold}
	budgets(mesh,env,regions,h)
	return h

static func position(mesh: Dictionary,cell: int) -> Vector3:
	return Vector3(mesh.xyz[3*cell],mesh.xyz[3*cell+1],mesh.xyz[3*cell+2])

static func prefectures(mesh: Dictionary,env: Dictionary,regions: Dictionary,parent: int,center: int,seed_value: int,threshold: float) -> PackedInt32Array:
	var component := grow(mesh,env,regions.of,[{"cell":center,"id":center}],parent,true)
	var candidates: Array[int] = []; var total_length := 0.; var edge_count := 0
	for offset in range(regions.cellStart[parent],regions.cellStart[parent+1]):
		var cell: int = regions.cells[offset]
		if cell!=center and component[cell]>=0 and Roads.passable(env,cell) and env.suitability[cell]>threshold: candidates.append(cell)
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			if regions.of[mesh.adj[slot]]==parent: total_length += mesh.lengths[slot]; edge_count += 1
	if candidates.is_empty(): return PackedInt32Array()
	var separation := total_length/maxi(1,edge_count)
	var sphere_radius := float(mesh.width)/TAU
	var radius := sqrt(float(regions.area[parent])/PI)/sphere_radius
	var origin := position(mesh,center).normalized()
	var east := Vector3(-origin.y,origin.x,0.).normalized()
	if east.length_squared()<.1: east = Vector3(0.,1.,0.)
	var north := origin.cross(east).normalized()
	var phase := TAU*Maths.keyed(Maths.sub_seed(seed_value,"zhoufu-placement"),parent)
	var best := PackedInt32Array(); var best_offset := INF
	for scale_value in [.6,.45,.3]:
		for rotation in range(12):
			var selected := PackedInt32Array(); var displacement := 0.
			for corner in range(3):
				var angle: float = phase+rotation*PI/6.+corner*TAU/3.
				var tangent := east*cos(angle)+north*sin(angle)
				var target: Vector3 = origin*cos(radius*scale_value)+tangent*sin(radius*scale_value)
				var ranked: Array = []
				for cell in candidates:
					if cell in selected or Sphere.distance(mesh,cell,center)<separation: continue
					var allowed := true
					for previous in selected:
						if Sphere.distance(mesh,cell,previous)<separation: allowed = false; break
					if allowed: ranked.append({"cell":cell,"distance":position(mesh,cell).distance_squared_to(target),"suitability":env.suitability[cell]})
				ranked.sort_custom(func(a,b):
					if a.distance!=b.distance: return a.distance<b.distance
					return a.cell<b.cell if a.suitability==b.suitability else a.suitability>b.suitability)
				if not ranked.is_empty(): selected.append(ranked[0].cell); displacement += ranked[0].distance
			if selected.size()>best.size() or (selected.size()==best.size() and displacement<best_offset): best = selected; best_offset = displacement
	return best

static func guardians(mesh: Dictionary,env: Dictionary,regions: Dictionary,centers: Array) -> PackedInt32Array:
	var seeds: Array = []
	for c in range(centers.size()): seeds.append({"cell":centers[c].cell,"id":c})
	var labels := grow(mesh,env,regions.of,seeds)
	var result := PackedInt32Array(); result.resize(regions.count); result.fill(-1)
	for parent in range(regions.count):
		var cell: int = regions.seat[parent]; result[parent] = labels[cell]
		if result[parent]>=0: continue
		var best := INF
		for c in range(centers.size()):
			var distance := Sphere.distance(mesh,cell,centers[c].cell)
			if distance<best: best = distance; result[parent] = c
	return result

static func budgets(mesh: Dictionary,env: Dictionary,regions: Dictionary,h: Dictionary) -> void:
	var state_weights: Array = []; var city_weights: Array = []
	city_weights.resize(h.cities.size()); city_weights.fill(0.)
	for parent in h.state_parents:
		var weight := 0.
		for offset in range(regions.cellStart[parent],regions.cellStart[parent+1]):
			var cell: int = regions.cells[offset]
			if env.water[cell]!=0: continue
			var value: float = mesh.areas[cell]*maxf(0.,env.suitability[cell])
			weight += value; city_weights[h.district_of_cell[cell]] += value
		state_weights.append(weight)
	h.state_budgets = []
	for city in h.cities: city.budget = [0,0,0]
	for _s in h.state_parents: h.state_budgets.append([0,0,0])
	for kind in range(3):
		var totals := allocate(h.state_parents.size()*MEAN_BUDGET[kind],state_weights)
		for state in range(h.members.size()):
			h.state_budgets[state][kind] = totals[state]
			var weights: Array = []
			for c in h.members[state]: weights.append(city_weights[c])
			var shares := allocate(totals[state],weights)
			for index in range(shares.size()): h.cities[h.members[state][index]].budget[kind] = shares[index]
