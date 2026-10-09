extends RefCounted
## Port of civ-atlas 103afd3 gen/civ/regions.ts. AGPL-3.0-only.
## River crossing cost is deliberately zero; freshwater still affects suitability.
const Maths = preload("res://scripts/atlas/math.gd")
const SettlementClimate = preload("res://scripts/atlas/climate_settlement.gd")

static func build(mesh: Dictionary,env: Dictionary,seed_value: int,region_area: float = 750.0) -> Dictionary:
	var n: int = mesh.n
	var adj: PackedInt32Array = mesh.adj; var start: PackedInt32Array = mesh.adj_start
	var lengths: PackedFloat32Array = mesh.lengths; var areas: PackedFloat32Array = mesh.areas
	var water := PackedByteArray(env.water); var suit := PackedFloat32Array(env.suitability)
	var elevation := PackedFloat32Array(env.elevation); var biome := PackedByteArray(env.biome)
	var flux := PackedFloat32Array(env.flux); var river_threshold: float = env.riverThreshold
	var cost := PackedFloat32Array(); cost.resize(adj.size())
	var seed_cost := PackedFloat32Array(); seed_cost.resize(adj.size())
	var step := sqrt(float(mesh.width)*float(mesh.height)/36000.0)*1.02
	for i in range(n):
		for k in range(start[i],start[i+1]):
			var j := adj[k]
			if water[i] != 0 or water[j] != 0: cost[k] = -1.0; seed_cost[k] = -1.0; continue
			var terrain := (step/550.0)*absf(elevation[j]-elevation[i])
			if biome[i] != biome[j]: terrain += 0.3*lengths[k]
			cost[k] = lengths[k]+terrain; seed_cost[k] = lengths[k]
	var land := landmasses(mesh,water)
	var base := Maths.sub_seed(seed_value,"civ-regions")
	var cells: Array[int] = []
	var tie := PackedFloat64Array(); tie.resize(n)
	for i in range(n):
		if water[i] == 0: cells.append(i); tie[i] = Maths.keyed(base,i)
	cells.sort_custom(func(a,b): return tie[a] < tie[b] if suit[a] == suit[b] else suit[a] > suit[b])
	var r0 := sqrt(region_area*0.85)*0.8*Maths.fpow(float(n)/(36000.0*0.944),0.07)
	var covered := PackedByteArray(); covered.resize(n)
	var stamp := PackedInt32Array(); stamp.resize(n); stamp.fill(-1)
	var dist := PackedFloat64Array(); dist.resize(n)
	var seeded := PackedByteArray(); seeded.resize(land.count)
	var seeds := PackedInt32Array(); var reaches := PackedFloat64Array()
	var climate_density: bool = env.get("params",{}).get("settlement_model","") in [SettlementClimate.VERSION,"climate_capacity_v5","climate_capacity_v4","climate_capacity_v3","climate_capacity_v2"]
	for pass_index in range(2):
		for s in cells:
			if pass_index == 0 and (covered[s] != 0 or flux[s] >= 6.0*river_threshold): continue
			if pass_index == 1 and seeded[land.of[s]] != 0: continue
			var id := seeds.size(); seeds.append(s); seeded[land.of[s]] = 1
			var f := clampf(Maths.fpow(13.0/(suit[s]+1.0),0.35),0.7,2.3)
			if climate_density: f = SettlementClimate.seed_radius(suit[s])
			reaches.append(Maths.fpow(f,0.8))
			var budget := r0*f*(0.85+0.3*Maths.keyed(base,s,1))
			covered[s] = 1; stamp[s] = id; dist[s] = 0.0
			var heap := Maths.Heap.new(); heap.push(s,0.0)
			while heap.size > 0:
				var i := heap.pop(); var d := heap.last_priority
				if d > dist[i]: continue
				covered[i] = 1
				for k in range(start[i],start[i+1]):
					if seed_cost[k] < 0.0: continue
					var j := adj[k]; var nd := d+seed_cost[k]
					if nd > budget: continue
					if stamp[j] != id or nd < dist[j]: stamp[j] = id; dist[j] = nd; heap.push(j,nd)
	var of := PackedInt32Array(); of.resize(n); of.fill(-1)
	var from := PackedInt32Array(); from.resize(n); from.fill(-1)
	dist.fill(INF)
	var heap := Maths.Heap.new()
	for r in range(seeds.size()): dist[seeds[r]] = 0.0; from[seeds[r]] = r; heap.push(seeds[r],0.0)
	while heap.size > 0:
		var i := heap.pop(); var d := heap.last_priority
		if d > dist[i] or of[i] >= 0: continue
		of[i] = from[i]
		var inv := 1.0/reaches[of[i]]
		for k in range(start[i],start[i+1]):
			if cost[k] < 0.0: continue
			var j := adj[k]; var nd := d+cost[k]*inv
			if nd < dist[j]: dist[j] = nd; from[j] = of[i]; heap.push(j,nd)
	var protected := PackedByteArray(); protected.resize(n)
	for s in seeds: protected[s] = 1
	normalize(mesh,of,protected)
	fix_fragments(mesh,of,seeds)
	# Dense productive lowlands need smaller provinces to survive cleanup;
	# otherwise the new close seeds are merged back into the old coarse layout.
	var merged := merge_small(mesh,of,seeds,areas,region_area*0.85*(0.12 if climate_density else 0.22))
	var new_id := PackedInt32Array(); new_id.resize(seeds.size()); new_id.fill(-1)
	var seats := PackedInt32Array()
	for r in range(seeds.size()):
		if merged[r] == 0: new_id[r] = seats.size(); seats.append(seeds[r])
	for i in range(n):
		if of[i] >= 0: of[i] = new_id[of[i]]
	return finish(mesh,env,of,seats,land.of)

static func landmasses(mesh: Dictionary,water: PackedByteArray) -> Dictionary:
	var of := PackedInt32Array(); of.resize(mesh.n); of.fill(-1)
	var sizes := PackedFloat64Array(); var first := PackedInt32Array()
	var count := 0
	for s in range(mesh.n):
		if water[s] != 0 or of[s] >= 0: continue
		var queue := PackedInt32Array([s]); of[s] = count; var area := 0.0; var qh := 0
		while qh < queue.size():
			var i := queue[qh]; qh += 1; area += mesh.areas[i]
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var j: int = mesh.adj[k]
				if water[j] == 0 and of[j] < 0: of[j] = count; queue.append(j)
		sizes.append(area); first.append(s); count += 1
	var order: Array[int] = []
	for i in range(count): order.append(i)
	order.sort_custom(func(a,b): return first[a] < first[b] if sizes[a] == sizes[b] else sizes[a] > sizes[b])
	var ranks := PackedInt32Array(); ranks.resize(count)
	for i in range(count): ranks[order[i]] = i
	for i in range(mesh.n):
		if of[i] >= 0: of[i] = ranks[of[i]]
	return {"count":count,"of":of}

static func normalize(mesh: Dictionary,of: PackedInt32Array,protected: PackedByteArray) -> void:
	for _pass in range(2):
		for i in range(mesh.n):
			var own := of[i]
			if own < 0 or protected[i] != 0: continue
			var tally := {}; var buddies := 0; var foes := 0
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var r := of[mesh.adj[k]]
				if r < 0: continue
				if r == own: buddies += 1
				else: foes += 1; tally[r] = tally.get(r,0)+1
			if foes < 2 or buddies > 2 or foes <= buddies: continue
			of[i] = best_neighbour(tally)

static func best_neighbour(tally: Dictionary) -> int:
	var best := -1; var count := -1
	for r in tally:
		if tally[r] > count or (tally[r] == count and r < best): best = r; count = tally[r]
	return best

static func fix_fragments(mesh: Dictionary,of: PackedInt32Array,seeds: PackedInt32Array) -> void:
	var reach := PackedByteArray(); reach.resize(mesh.n)
	var queue := PackedInt32Array()
	for r in range(seeds.size()):
		if of[seeds[r]] == r: reach[seeds[r]] = 1; queue.append(seeds[r])
	var qh := 0
	while qh < queue.size():
		var i := queue[qh]; qh += 1
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if reach[j] == 0 and of[j] == of[i]: reach[j] = 1; queue.append(j)
	var seen := PackedByteArray(); seen.resize(mesh.n)
	for _pass in range(8):
		var left := false; seen.fill(0)
		for s in range(mesh.n):
			if of[s] < 0 or reach[s] != 0 or seen[s] != 0: continue
			var r := of[s]; var comp := PackedInt32Array([s]); seen[s] = 1
			var tally := {}; qh = 0
			while qh < comp.size():
				var i := comp[qh]; qh += 1
				for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
					var j: int = mesh.adj[k]; var rj := of[j]
					if rj < 0: continue
					if rj == r:
						if seen[j] == 0 and reach[j] == 0: seen[j] = 1; comp.append(j)
					elif reach[j] != 0: tally[rj] = tally.get(rj,0)+1
			var best := best_neighbour(tally)
			if best < 0: left = true; continue
			for i in comp: of[i] = best; reach[i] = 1
		if not left: break

static func merge_small(mesh: Dictionary,of: PackedInt32Array,seeds: PackedInt32Array,areas: PackedFloat32Array,minimum: float) -> PackedByteArray:
	var size := PackedFloat64Array(); size.resize(seeds.size())
	var cells: Array = []
	for _r in seeds: cells.append([])
	for i in range(mesh.n):
		if of[i] >= 0: size[of[i]] += areas[i]; cells[of[i]].append(i)
	var merged := PackedByteArray(); merged.resize(seeds.size()); var small: Array[int] = []
	for r in range(seeds.size()):
		if size[r] < minimum: small.append(r)
	small.sort_custom(func(a,b): return a < b if size[a] == size[b] else size[a] < size[b])
	for r in small:
		if merged[r] != 0 or size[r] >= minimum: continue
		var tally := {}
		for i in cells[r]:
			for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
				var rj := of[mesh.adj[k]]
				if rj >= 0 and rj != r: tally[rj] = tally.get(rj,0)+1
		var best := best_neighbour(tally)
		if best < 0: continue
		for i in cells[r]: of[i] = best
		cells[best].append_array(cells[r]); cells[r] = []; size[best] += size[r]; size[r] = 0.0; merged[r] = 1
	return merged

static func finish(mesh: Dictionary,env: Dictionary,of: PackedInt32Array,seat: PackedInt32Array,land: PackedInt32Array) -> Dictionary:
	var count := seat.size(); var area := PackedFloat32Array(); area.resize(count)
	var capacity := PackedFloat32Array(); capacity.resize(count); var landmass := PackedInt32Array(); landmass.resize(count)
	var input_capacity := PackedFloat32Array(env.capacity)
	var area64 := PackedFloat64Array(); area64.resize(count)
	var capacity64 := PackedFloat64Array(); capacity64.resize(count)
	var elevation_sum := PackedFloat64Array(); elevation_sum.resize(count)
	var r_biome := PackedByteArray(); r_biome.resize(count); var r_elevation := PackedFloat32Array(); r_elevation.resize(count)
	var biome_areas: Array = []
	for _r in range(count):
		var values := PackedFloat64Array(); values.resize(16); biome_areas.append(values)
	var cells: Array = []; var edges := {}; var dist := PackedFloat64Array(); dist.resize(mesh.n); dist.fill(INF)
	for r in range(count): cells.append([]); landmass[r] = land[seat[r]]
	for i in range(mesh.n):
		var r := of[i]
		if r < 0: continue
		cells[r].append(i); area64[r] += mesh.areas[i]; capacity64[r] += input_capacity[i]
		elevation_sum[r] += env.elevation[i]*mesh.areas[i]; biome_areas[r][env.biome[i]] += mesh.areas[i]
	for r in range(count):
		area[r] = area64[r]; capacity[r] = capacity64[r]; r_elevation[r] = elevation_sum[r]/area64[r] if area64[r]>0 else 0
		var best := 0
		for b in range(1,16):
			if biome_areas[r][b]>biome_areas[r][best]: best = b
		r_biome[r] = best
	var heap := Maths.Heap.new()
	for s in seat: dist[s] = 0.0; heap.push(s,0.0)
	while heap.size > 0:
		var i := heap.pop(); var d := heap.last_priority
		if d > dist[i]: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if of[j] != of[i]: continue
			var nd: float = d+mesh.lengths[k]
			if nd < dist[j]: dist[j] = nd; heap.push(j,nd)
	for i in range(mesh.n):
		if of[i] < 0: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if j < i or of[j] < 0 or of[j] == of[i]: continue
			var a := mini(of[i],of[j]); var b := maxi(of[i],of[j]); var key := a*count+b
			if not edges.has(key): edges[key] = {"a":a,"b":b,"length":INF,"border":0.0,"pass":INF}
			var edge: Dictionary = edges[key]
			edge.length = minf(edge.length,dist[i]+mesh.lengths[k]+dist[j])
			edge.border += mesh.lengths[k]*0.577; edge.pass = minf(edge.pass,maxf(env.elevation[i],env.elevation[j]))
	# Preserve geographic sea adjacency metadata without creating visible/simulated sea routes.
	var step := sqrt(float(mesh.width)*float(mesh.height)/36000.)*1.02; var route_max := 30*step
	var sea_dist := PackedFloat64Array(); sea_dist.resize(mesh.n); sea_dist.fill(INF)
	var sea_label := PackedInt32Array(); sea_label.resize(mesh.n); sea_label.fill(-1); var sea_origin := sea_label.duplicate()
	var open := PackedByteArray(); open.resize(mesh.n); heap.clear()
	for i in range(mesh.n): open[i] = 1 if env.water[i]==1 and env.biome[i]!=2 and env.temperature[i]>= -8 else 0
	for i in range(mesh.n):
		if of[i]<0: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			if open[mesh.adj[k]]: sea_dist[i] = 0; sea_label[i] = of[i]; sea_origin[i] = i; heap.push(i,0); break
	while not heap.empty():
		var i := heap.pop(); var d := heap.last_priority
		if d>sea_dist[i]: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if not open[j]: continue
			var nd: float = d+mesh.lengths[k]
			if nd<sea_dist[j] and nd<=route_max: sea_dist[j] = nd; sea_label[j] = sea_label[i]; sea_origin[j] = sea_origin[i]; heap.push(j,nd)
	var sea_best := {}
	for i in range(mesh.n):
		if not open[i] or sea_label[i]<0: continue
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if sea_label[j]<0 or sea_label[j]==sea_label[i] or (open[j] and j<i): continue
			var d: float = sea_dist[i]+mesh.lengths[k]+sea_dist[j]
			if d>route_max: continue
			var a := mini(sea_label[i],sea_label[j]); var b := maxi(sea_label[i],sea_label[j]); var key := a*count+b
			if edges.has(key): continue
			var oa := sea_origin[i] if sea_label[i]==a else sea_origin[j]; var ob := sea_origin[j] if sea_label[i]==a else sea_origin[i]
			if not sea_best.has(key) or d<sea_best[key].d: sea_best[key] = {"d":d,"oa":oa,"ob":ob}
	var neighbours: Array = []
	for _r in range(count): neighbours.append([])
	for edge in edges.values():
		var ea: float = maxf(0.0,env.elevation[seat[edge.a]]); var eb: float = maxf(0.0,env.elevation[seat[edge.b]])
		var kind := 2 if edge.pass-maxf(ea,eb)>350.0 or edge.pass-minf(ea,eb)>1100.0 else 0
		neighbours[edge.a].append({"to":edge.b,"kind":kind,"length":edge.length,"border":edge.border})
		neighbours[edge.b].append({"to":edge.a,"kind":kind,"length":edge.length,"border":edge.border})
	for key in sea_best:
		var a: int = key/count; var b: int = key-a*count; var value: Dictionary = sea_best[key]
		var kind := 3 if value.d<=4*step else 4; var length: float = dist[value.oa]+value.d+dist[value.ob]
		neighbours[a].append({"to":b,"kind":kind,"length":length,"border":0.}); neighbours[b].append({"to":a,"kind":kind,"length":length,"border":0.})
	var adj_start := PackedInt32Array(); var adj := PackedInt32Array(); var adj_kind := PackedByteArray()
	var adj_len := PackedFloat32Array(); var adj_border := PackedFloat32Array(); var cell_start := PackedInt32Array(); var packed_cells := PackedInt32Array()
	for r in range(count):
		cell_start.append(packed_cells.size()); packed_cells.append_array(PackedInt32Array(cells[r]))
		adj_start.append(adj.size()); neighbours[r].sort_custom(func(a,b): return a.to < b.to)
		for neighbour in neighbours[r]:
			adj.append(neighbour.to); adj_kind.append(neighbour.kind); adj_len.append(neighbour.length); adj_border.append(neighbour.border)
	cell_start.append(packed_cells.size()); adj_start.append(adj.size())
	return {"count":count,"of":of,"seat":seat,"landmass":landmass,"area":area,"capacity":capacity,
		"cellStart":cell_start,"cells":packed_cells,"adjStart":adj_start,"adj":adj,"adjKind":adj_kind,"adjLen":adj_len,"adjBorder":adj_border,"biome":r_biome,"elevation":r_elevation}
