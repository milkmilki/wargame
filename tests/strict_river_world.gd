extends SceneTree
const SOURCE := "res://assets/terrain/eurasia_strict_river_map_source.json"
const OLD_SOURCE := "res://assets/terrain/eurasia_hydrology_map_source.json"
const Banks = preload("res://scripts/core/river_province_constraints.gd")
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("STRICT_WORLD_FAIL ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
	var seeds := [2342006650,12345,23456,34567,45678,1470349411]
	if not OS.get_environment("HYDROLOGY_SEED").is_empty(): seeds = [int(OS.get_environment("HYDROLOGY_SEED"))]
	for seed_value in seeds:
		var old := GameState.new()
		check(old.generate_world(seed_value,40,500,"",{},seed_value,"",OLD_SOURCE),"baseline")
		var state := GameState.new()
		if not state.generate_world(seed_value,40,500,"",{},seed_value,"",SOURCE):
			check(false,state.last_generation_error)
			continue
		check(state.land_cities().size()==500 and state.nations.size()==40,"500/40")
		check(state.territory_structure_valid(),"initial territory and army bindings")
		var west := nearest_city(state,3.0,46.0)
		var middle := nearest_city(state,60.0,40.0)
		var east := nearest_city(state,108.9,34.3)
		check(reachable(state,west,middle) and reachable(state,middle,east),"west-central-east transport without sea")
		check(state.river_features==old.river_features,"river geometry changed")
		for i in range(500): check(state.cities[i].map_position==old.cities[i].map_position,"land city moved")
		var size := state.province_map_size
		var constraints := Banks.build(state.river_features,size,state.map_aspect_ratio)
		check(Banks.validate(state.province_ids,constraints).is_empty(),"same city opposite banks")
		var source := (load(state.current_terrain_map_path()) as Texture2D).get_image()
		source.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
		var land: PackedByteArray=TerrainMapGenerator._all_land_geometry(source).mask
		var blocked:=Hydro.barriers(state.river_features,size)
		var components:=Hydro.components(land,size,blocked)
		var seeded := {}
		for city in state.land_cities():
			var cell := Vector2i(city.map_position*Vector2(size))
			seeded[components[cell.y*size.x+cell.x]]=true
			check(Banks._connected(state.province_ids,size,cell,city.id,blocked),"disconnected province %d"%city.id)
		var gaps := []
		for i in range(land.size()):
			if land[i]!=0 and state.province_ids[i]<0 and seeded.has(components[i]): gaps.append(i)
		print("STRICT_WORLD seed=",seed_value," docks=",state.cities.size()-500," seeded_gaps=",gaps)
		check(gaps.is_empty(),"unassigned land in seeded region")
		var definition := MapDefinition.from_state(state)
		check(MapDefinition.validate(definition).is_empty(),"template invalid")
		var restored:=GameState.new()
		restored.generate_from_map_definition(definition,seed_value)
		check(MapDefinition.from_state(restored)==definition,"template round trip")
		FileAccess.open("res://.dbg/strict-world-%d.json"%seed_value,FileAccess.WRITE).store_string(JSON.stringify(definition))
	print("STRICT_RIVER_WORLD failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func nearest_city(state: GameState,lon: float,lat: float) -> int:
	var uv := MapSource.lonlat_to_map(lon,lat,SOURCE)
	var point := Vector2(uv[0],uv[1])
	var closest := -1
	var distance := INF
	for city in state.land_cities():
		var candidate := TerrainMapGenerator.metric_length_between(point,city.map_position,state.map_aspect_ratio)
		if candidate<distance: closest=city.id; distance=candidate
	return closest

func reachable(state: GameState,start: int,target: int) -> bool:
	var queue: Array[int]=[start]
	var seen := {start:true}
	var head := 0
	while head<queue.size():
		var current := queue[head]
		head+=1
		if current==target: return true
		for neighbor in state.neighbors(current):
			var edge: Edge=state.edge_of(current,neighbor)
			if edge.kind==Edge.Kind.SEA or edge.max_manpower<=0 or seen.has(neighbor): continue
			seen[neighbor]=true
			queue.append(neighbor)
	return false
