extends SceneTree
func _init() -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-world-12345.json"))
	data["map_models"]=MapSource.model_descriptor(data.map_source_manifest)
	data.map_models.road_version="atlas_city_graph_v0_fixture"
	var state:=GameState.new();state.generate_from_map_definition(data,12345)
	var failures:=0
	if MapDefinition.from_state(state).map_models.road_version!="atlas_city_graph_v0_fixture": failures+=1;printerr("ATLAS_TEMPLATE_FAIL actual saved algorithm version")
	var invalid:=data.duplicate(true);invalid.map_models=[]
	if MapDefinition.validate(invalid).is_empty(): failures+=1;printerr("ATLAS_TEMPLATE_FAIL reject non-dictionary model metadata")
	invalid=data.duplicate(true);invalid.edges[0].road_tier=NAN
	if MapDefinition.validate(invalid).is_empty(): failures+=1;printerr("ATLAS_TEMPLATE_FAIL reject non-finite tier")
	var legacy:=data.duplicate(true);legacy.erase("map_models")
	for edge in legacy.edges: edge.erase("road_tier")
	var old:=GameState.new();old.generate_from_map_definition(legacy,12345)
	if old.edges.size()!=state.edges.size(): failures+=1
	for i in range(old.edges.size()):
		if old.edges[i].map_path!=state.edges[i].map_path or old.edges[i].road_tier!=Edge.RoadTier.LEGACY: failures+=1
	print("ATLAS_TEMPLATE_MODELS failures=",failures);quit(1 if failures else 0)
