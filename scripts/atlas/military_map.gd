extends RefCounted
const Hierarchy = preload("res://scripts/atlas/zhoufu.gd")
const Routes = preload("res://scripts/atlas/zhoufu_roads.gd")
const Traffic = preload("res://scripts/atlas/traffic_graph.gd")
const Ownership = preload("res://scripts/atlas/ownership.gd")
const Generator = preload("res://scripts/atlas/generator.gd")
const MODEL := "atlas-military-v1"
const Maths = preload("res://scripts/atlas/math.gd")
const RoadGeometry = preload("res://scripts/atlas/road_geometry.gd")

static func prepare(base: Dictionary,target_nations: int = 40) -> Dictionary:
	var data: Dictionary = base.data
	if data.cities.is_empty(): return {"error":"选定范围内没有满足城市阈值的州治，请扩大范围或降低城市阈值。"}
	var total_started := Time.get_ticks_msec()
	var started := Time.get_ticks_msec()
	var h := Hierarchy.build(data.mesh,data.environment,data.regions,data.cities,int(data.seed),float(data.options.city_threshold))
	# The upstream interpolated coastline can erase a small island altogether.
	# Keep a minimal visible land footprint at genuine land seeds; this changes
	# only the display raster, never elevation, climate, provinces or seat positions.
	var raster := seat_land_raster(base.raster,data,h)
	var hierarchy_ms := Time.get_ticks_msec()-started
	started = Time.get_ticks_msec()
	var roads := Routes.build(data.mesh,data.environment,data.regions,h)
	var graph := Traffic.build(data.mesh,h,roads)
	var strategic := settlement_adjacency(graph,h.cities.size())
	var roads_ms := Time.get_ticks_msec()-started
	var political := Ownership.build(data.mesh,data.regions,data.cities,target_nations,true)
	for parent in range(data.regions.count):
		if h.state_by_parent[parent]<0 and h.guardian_by_parent[parent]>=0:
			political.ownership[parent] = political.ownership[h.cities[h.guardian_by_parent[parent]].region]
	var district_pixels := PackedInt32Array(); district_pixels.resize(raster.cell.size()); district_pixels.fill(-1)
	for k in range(district_pixels.size()):
		if raster.water[k]!=0: continue
		var cell: int = raster.cell[k]; var district: int = h.district_of_cell[cell]
		if district<0:
			for slot in range(data.mesh.adj_start[cell],data.mesh.adj_start[cell+1]):
				district = h.district_of_cell[data.mesh.adj[slot]]
				if district>=0: break
		district_pixels[k] = district
	var smoothing := RoadGeometry.apply(graph,raster,district_pixels)
	var strategic_routes := settlement_routes(graph,h.cities.size())
	var pairs := {}; var territorial: Array[Vector2i] = []
	for cell in range(data.mesh.n):
		var a: int = h.district_of_cell[cell]
		if a<0: continue
		for slot in range(data.mesh.adj_start[cell],data.mesh.adj_start[cell+1]):
			var b: int = h.district_of_cell[data.mesh.adj[slot]]
			if b<0 or a==b: continue
			pairs[mini(a,b)*h.cities.size()+maxi(a,b)] = Vector2i(mini(a,b),maxi(a,b))
	var keys: Array = pairs.keys(); keys.sort()
	for key in keys: territorial.append(pairs[key])
	return {"model":MODEL,"data":data,"raster":raster,"display":base.display,"hierarchy":h,"network":roads,"graph":graph,
		"ownership":political.ownership,"nations":political.nations,"district_pixels":district_pixels,
		"settlement_adjacency":strategic,"strategic_routes":strategic_routes,"territorial_pairs":territorial,"timing":{"hierarchy_ms":hierarchy_ms,"roads_ms":roads_ms,"total_ms":Time.get_ticks_msec()-total_started,"smoothing":smoothing},"distance_km":250.0}

static func seat_land_raster(source: Dictionary,data: Dictionary,h: Dictionary) -> Dictionary:
	var result: Dictionary = source.duplicate()
	for field in ["water","cell","elev","biome"]: result[field] = source[field].duplicate()
	for city in h.cities:
		var point := Vector2(data.mesh.x[city.cell],data.mesh.y[city.cell])
		var x := posmod(floori(point.x),2048); var y := clampi(floori(point.y),0,1023)
		if result.water[y*2048+x]==0: continue
		for dy in range(-2,3):
			for dx in range(-2,3):
				if dx*dx+dy*dy>4 or y+dy<0 or y+dy>=1024: continue
				var k := (y+dy)*2048+posmod(x+dx,2048)
				if result.water[k]==0: continue
				result.water[k] = 0; result.cell[k] = city.cell
				result.elev[k] = maxf(8.,data.environment.elevation[city.cell]); result.biome[k] = data.environment.biome[city.cell]
	return result

static func settlement_adjacency(graph: Dictionary,count: int) -> Dictionary:
	var adjacency: Array = []; var result := {}
	for _node in graph.nodes: adjacency.append([])
	for edge in graph.edges: adjacency[edge.a].append(edge.b); adjacency[edge.b].append(edge.a)
	for city in range(count):
		var seen := {city:true}; var queue: Array = adjacency[city].duplicate(); var neighbors: Array[int] = []
		while not queue.is_empty():
			var node: int = queue.pop_back()
			if seen.has(node): continue
			seen[node] = true
			if node<count: neighbors.append(node); continue
			queue.append_array(adjacency[node])
		neighbors.sort(); result[city] = neighbors
	return result

static func settlement_routes(graph: Dictionary,count: int) -> Dictionary:
	var adjacency: Array = []; var routes := {}
	for _node in graph.nodes: adjacency.append([])
	for edge in graph.edges:
		var length := RoadGeometry.length_units(edge.path)
		adjacency[edge.a].append({"to":edge.b,"length":length}); adjacency[edge.b].append({"to":edge.a,"length":length})
	for source in range(count):
		var distance := {source:0.}; var previous := {}; var heap := Maths.Heap.new(); heap.push(source,0.)
		while not heap.empty():
			var node := heap.pop(); var d := heap.last_priority
			if d>distance[node]: continue
			if node<count and node!=source:
				if node<source: continue
				var path: Array[int] = [node]; var back := node
				while previous.has(back): back = previous[back]; path.append(back)
				path.reverse(); routes["%d:%d"%[source,node]] = path; continue
			for link in adjacency[node]:
				var nd: float = d+link.length
				if nd<float(distance.get(link.to,INF)): distance[link.to] = nd; previous[link.to] = node; heap.push(link.to,nd)
	return routes
