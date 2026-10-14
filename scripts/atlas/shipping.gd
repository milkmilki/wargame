extends RefCounted
## Post-generation commerce overlay. Never modifies administrative/land graphs.
const VERSION := "atlas-trade-shipping-v1"
const Roads = preload("res://scripts/atlas/roads.gd")
const Routes = preload("res://scripts/atlas/zhoufu_roads.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const Geometry = preload("res://scripts/atlas/road_geometry.gd")

static func build(data: Dictionary,hierarchy: Dictionary) -> Dictionary:
	var mesh: Dictionary=data.mesh; var environment: Dictionary=data.environment
	var sea := PackedByteArray(); sea.resize(mesh.n)
	for cell in range(mesh.n): sea[cell]=1 if environment.water[cell]==1 and environment.biome[cell]!=2 else 0
	var ports: Array[int] = []; var seeds: Array = []; var port_at := {}
	for id in range(hierarchy.cities.size()):
		var cell: int=hierarchy.cities[id].cell
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			if sea[mesh.adj[slot]]:
				ports.append(id); seeds.append(cell); port_at[cell]=true; break
	var costs := PackedFloat32Array(); costs.resize(mesh.adj.size()); costs.fill(-1.)
	for cell in range(mesh.n):
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var neighbor: int=mesh.adj[slot]
			if (sea[cell] and sea[neighbor]) or (port_at.has(cell) and sea[neighbor]) or (sea[cell] and port_at.has(neighbor)):
				costs[slot]=mesh.lengths[slot]
	var neighbors := Roads.neighbor_graph(mesh,seeds,costs)
	var chosen := Roads.urquhart(ports.size(),neighbors)
	var used := {}
	for link in chosen: used[Vector2i(link.a,link.b)]=true
	for link in Routes.spanning_forest(ports.size(),neighbors):
		if not used.has(Vector2i(link.a,link.b)): chosen.append(link)
	chosen.sort_custom(func(a,b):return int(a.b)<int(b.b) if a.a==b.a else int(a.a)<int(b.a))
	var slots := PackedByteArray(); slots.resize(mesh.adj.size())
	var city_at := PackedInt32Array(); city_at.resize(mesh.n); city_at.fill(-1)
	for id in range(seeds.size()): city_at[int(seeds[id])]=id
	var finder := Roads.Finder.new(mesh.n)
	var routes: Array = []
	for link in chosen:
		var route_costs := costs.duplicate()
		# Intermediate port cells cannot form an overland shortcut between seas.
		for port in range(seeds.size()):
			if port in [int(link.a),int(link.b)]: continue
			var cell: int=seeds[port]
			for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
				route_costs[slot]=-1.
				var back := Roads.slot_of(mesh,int(mesh.adj[slot]),cell)
				if back>=0: route_costs[back]=-1.
		var cells := finder.find(mesh,route_costs,slots,city_at,int(seeds[link.a]),int(seeds[link.b]))
		if cells.size()<3: continue
		var points := PackedVector2Array()
		for cell in cells:
			var point := Vector2(mesh.x[cell],mesh.y[cell])
			if not points.is_empty(): point.x=Sphere.near_x(point.x,points[-1].x,mesh.width)
			points.append(point)
		routes.append({"a":ports[link.a],"b":ports[link.b],"cells":cells,"path":points,"distance":Geometry.length_units(points)})
	var result := {"version":VERSION,"ports":ports,"routes":routes}
	result.fingerprint=var_to_bytes(routes).hex_encode().sha256_text()
	return result

static func edges(state: GameState) -> Array[Edge]:
	var result: Array[Edge] = []
	for route in state.atlas_layout.get("shipping",{}).get("routes",[]):
		var edge := Edge.new(); edge.city_a=mini(int(route.a),int(route.b)); edge.city_b=maxi(int(route.a),int(route.b))
		edge.kind=Edge.Kind.SEA; edge.max_manpower=Edge.WATER_MANPOWER; edge.base_max_manpower=Edge.WATER_MANPOWER
		edge.allows_holding=false; edge.precise_distance=float(route.distance); edge.distance=maxi(1,ceili(edge.precise_distance)); edge.spherical_path=true
		for point in route.path: edge.map_path.append(point/Vector2(2048,1024))
		if int(route.a)>int(route.b): edge.map_path.reverse()
		result.append(edge)
	return result
