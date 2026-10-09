extends RefCounted
const RoadGeometry = preload("res://scripts/atlas/road_geometry.gd")
## Initialization adapter only. Runtime ownership remains exclusively in GameState.
static func install(state: GameState,payload: Dictionary) -> void:
	assert(payload.get("model")=="atlas-military-v1")
	var data: Dictionary = payload.data; var h: Dictionary = payload.hierarchy; var graph: Dictionary = payload.graph
	payload = payload.duplicate()
	state._reset_world(int(data.seed))
	state.atlas_layout = payload.duplicate()
	state.uses_heightmap = true; state.map_aspect_ratio = 2.
	state.trade_enabled = false
	state.map_models = data.options.duplicate(true); state.map_models.administrative_model = h.model; state.map_models.road_model = payload.network.model
	state.generation_metadata = {"seed":data.seed,"model":payload.model,"upstream":data.upstream,"upstream_commit":data.get("upstream_commit",""),"timing":payload.timing,"distance_km":250.,"settlements":h.cities.size(),"nodes":graph.nodes.size(),"godot":Engine.get_version_info(),"source_sha256":source_fingerprint()}
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,payload.nations.size(),false)
	for id in range(graph.nodes.size()):
		var record: Dictionary = graph.nodes[id]; var city := City.new(); city.id = id
		city.map_position = Vector2(fposmod(record.position.x/2048.,1.),record.position.y/1024.)
		city.coord = Vector2i(record.position)
		city.name = "交通点%d"%id; city.short_name = String.chr(0x4e00+id)
		city.node_kind = City.NodeKind.TRAFFIC if record.role=="traffic" else City.NodeKind.SETTLEMENT
		city.politically_active = not city.is_traffic
		if id<h.cities.size():
			var source: Dictionary = h.cities[id]
			city.owner_nation = payload.ownership[source.region]
			city.manpower_per_month = source.budget[0]; city.gold_per_month = source.budget[1]; city.food_per_half_year = source.budget[2]
			city.food_storage = city.food_per_half_year*GameState.FOOD_CAPACITY_HALF_YEARS
			city.terrain_height = maxf(0.,data.environment.elevation[source.cell])/maxf(1.,data.environment.maxElevation)
			for slot in range(data.mesh.adj_start[source.cell],data.mesh.adj_start[source.cell+1]): city.terrain_relief = maxf(city.terrain_relief,absf(data.environment.elevation[data.mesh.adj[slot]]-data.environment.elevation[source.cell])/maxf(1.,data.environment.maxElevation))
			var parent_name: String = data.regions.get("names",[])[source.region] if data.regions.has("names") else "州%d"%source.region
			city.name = parent_name if source.role=="zhou" else "%s·府%d"%[parent_name,h.members[h.state_by_city[id]].find(id)]
			if payload.has("settlement_records"):
				var initial: Dictionary = payload.settlement_records[id]
				city.owner_nation = initial.owner; city.name = initial.name; city.short_name = initial.short_name
				city.manpower_per_month = initial.budget[0]; city.gold_per_month = initial.budget[1]; city.food_per_half_year = initial.budget[2]
				city.food_storage = city.food_per_half_year*GameState.FOOD_CAPACITY_HALF_YEARS
		state.cities.append(city); state.adjacency[id] = [] as Array[int]
	for record in graph.edges:
		var edge := Edge.new(); edge.city_a = mini(record.a,record.b); edge.city_b = maxi(record.a,record.b)
		edge.kind = Edge.Kind.LAND; edge.road_tier = Edge.RoadTier.MAIN if record.tier==1 else Edge.RoadTier.LOCAL
		edge.control_city_id = record.control_city; edge.max_manpower = int(record.get("max_manpower",Edge.TERRAIN_STANDARD_MANPOWER)); edge.base_max_manpower = int(record.get("base_max_manpower",edge.max_manpower))
		edge.travel_time_multiplier = float(record.get("travel_time_multiplier",1.)); edge.supply_loss_multiplier = float(record.get("supply_loss_multiplier",1.)); edge.allows_holding = bool(record.get("allows_holding",true))
		edge.is_backbone = record.protected
		edge.danger = float(record.get("danger",0.))
		for index in range(record.path.size()):
			var point: Vector2 = record.path[index]; edge.map_path.append(Vector2(point.x/2048.,point.y/1024.))
		if record.a>record.b: edge.map_path.reverse()
		edge.spherical_path = true; edge.precise_distance = RoadGeometry.length_units(record.path); edge.distance = maxi(1,ceili(edge.precise_distance))
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(edge.city_a,edge.city_b)] = edge
		(state.adjacency[edge.city_a] as Array[int]).append(edge.city_b); (state.adjacency[edge.city_b] as Array[int]).append(edge.city_a)
	for id in state.adjacency: (state.adjacency[id] as Array[int]).sort()
	state.province_map_size = Vector2i(2048,1024); state.province_ids = payload.district_pixels.duplicate()
	state._initialize_recognized_city_owners(); state._initialize_manpower_pools()
	state.rebuild_region_analysis(); state.rebuild_administrative_regions()
	state._initialize_city_garrisons_free(); state._initialize_capitals_and_warehouses(); state._initialize_city_loyalty(false)
	for id in range(state.nations.size()):
		var nation := state.nations[id]; var source: Dictionary = payload.nations[id]
		nation.name = source.name; nation.short_name = source.name.left(1)
		nation.color = Color8(source.color[0],source.color[1],source.color[2]); nation.ruler_name = "中性君主"
	state._generate_armies(); RegionalStrategy.initialize_targets(state); EmpireStatus.reconcile(state); state.refresh_derived()

static func source_fingerprint() -> String:
	var paths: Array[String] = []
	for directory in ["res://scripts/atlas/","res://scripts/model/","res://scripts/core/","res://scripts/state/","res://scripts/simulation/","res://scripts/ai/"]:
		var folder := DirAccess.open(directory)
		if folder==null: continue
		for file_name in folder.get_files():
			if file_name.ends_with(".gd"): paths.append(directory+file_name)
	paths.sort(); var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
	for path in paths: digest.update(path.to_utf8_buffer()); digest.update(FileAccess.get_file_as_bytes(path))
	return digest.finish().hex_encode()
