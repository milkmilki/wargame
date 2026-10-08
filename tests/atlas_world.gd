extends SceneTree
const SOURCE:="res://assets/terrain/eurasia_atlas_map_source.json"
const Roads=preload("res://scripts/core/atlas_road_network.gd")
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1;printerr("ATLAS_WORLD_FAIL ",message)
func run() -> void:
	var seed_value:=int(OS.get_environment("ATLAS_TEST_SEED"));if seed_value==0: seed_value=12345
	var state:=GameState.new()
	check(state.generate_world(seed_value,40,500,"",{},seed_value,"",SOURCE),state.last_generation_error)
	if failures: quit(1);return
	check(state.cities.size()==500 and state.nations.size()==40,"formal size")
	check(state.river_features.is_empty() and state.river_paths.is_empty(),"no runtime rivers")
	check(state.territory_structure_valid(),"territory audit")
	var image: Image=(load(state.current_terrain_map_path()) as Texture2D).get_image()
	var options: Dictionary={"image":image,"maximum_height":1.0}
	var provinces: Dictionary={"ids":state.province_ids,"size":state.province_map_size}
	for edge in state.edges:
		check(edge.kind not in [Edge.Kind.RIVER,Edge.Kind.LANDING],"no river transport")
		if edge.kind==Edge.Kind.LAND:
			check(Roads.path_valid(edge.map_path,provinces,edge.city_a,edge.city_b,options),"actual land path legal "+str(edge.city_a)+"/"+str(edge.city_b))
			check(MapVisualAtlas.visual_road_path(state,state.edges.find(edge))==edge.map_path,"render path equals simulation path")
			check(edge.road_tier in [Edge.RoadTier.LOCAL,Edge.RoadTier.MAIN],"explicit road tier")
	var template:=MapDefinition.from_state(state);check(MapDefinition.validate(template).is_empty(),"template validation")
	var saved:=FileAccess.open("res://.dbg/atlas-world-"+str(seed_value)+".json",FileAccess.WRITE);saved.store_string(JSON.stringify(template));saved.close()
	var restored:=GameState.new();restored.generate_from_map_definition(JSON.parse_string(JSON.stringify(template)),seed_value)
	check(restored.province_ids==state.province_ids,"template province IDs")
	check(restored.edges.size()==state.edges.size(),"template edge count")
	for i in range(state.edges.size()):
		check(restored.edges[i].map_path==state.edges[i].map_path and restored.edges[i].road_tier==state.edges[i].road_tier,"complete path/tier round trip")
	var again:=GameState.new();check(again.generate_world(seed_value,40,500,"",{},seed_value,"",SOURCE),"regeneration")
	check(again.province_ids==state.province_ids,"deterministic layout")
	for i in range(state.edges.size()): check(again.edges[i].map_path==state.edges[i].map_path and again.edges[i].road_tier==state.edges[i].road_tier,"deterministic roads")
	print("ATLAS_WORLD seed=",seed_value," cities=500 nations=40 edges=",state.edges.size()," failures=",failures)
	quit(1 if failures else 0)
