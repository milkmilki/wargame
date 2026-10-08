extends SceneTree
var failures:=0
func _init() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1;printerr("ATLAS_EDIT_FAIL ",message)
func run() -> void:
	var seed_value:=int(OS.get_environment("ATLAS_TEST_SEED"));if seed_value==0: seed_value=12345
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-world-"+str(seed_value)+".json"))
	var state:=GameState.new();state.generate_from_map_definition(data,seed_value)
	var old:=state.cities[0].map_position;var target:=old
	for delta in [Vector2(1.0/4096,0),Vector2(-1.0/4096,0),Vector2(0,1.0/4096),Vector2(0,-1.0/4096)]:
		if TerrainMapGenerator.is_land_map_position(state.current_terrain_map_path(),old+delta): target=old+delta;break
	check(target!=old,"legal edit candidate")
	var snapshot:=MapDefinition.from_state(state)
	state.armies[0].path=[1] as Array[int]
	var refused:=state.apply_city_editor_changes(0,{"map_x":target.x,"map_y":target.y})
	check(not refused.ok and MapDefinition.from_state(state)==snapshot,"bound movement prevents rebuild without mutation")
	state.armies[0].path.clear()
	var accepted:=state.apply_city_editor_changes(0,{"map_x":target.x,"map_y":target.y})
	check(accepted.ok,accepted.get("error","edit"))
	check(state.cities[0].map_position==target,"edit commits actual city position")
	check(state.river_features.is_empty() and state.river_paths.is_empty(),"edit never enables rivers")
	check(state.territory_structure_valid(),"edited territory audit")
	var source: Image=(load(state.current_terrain_map_path()) as Texture2D).get_image()
	var options: Dictionary={"image":source,"maximum_height":1.0}
	var provinces: Dictionary={"ids":state.province_ids,"size":state.province_map_size}
	for edge in state.edges:
		if edge.kind==Edge.Kind.LAND: check(load("res://scripts/core/atlas_road_network.gd").path_valid(edge.map_path,provinces,edge.city_a,edge.city_b,options),"edited canonical path legal")
	print("ATLAS_EDIT seed=",seed_value," failures=",failures);quit(1 if failures else 0)
