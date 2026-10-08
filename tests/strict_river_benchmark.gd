extends SceneTree
func _init() -> void:
	OS.set_environment("WORLD_GENERATION_PROFILE","1")
	var source := OS.get_environment("HYDROLOGY_SOURCE")
	if source.is_empty(): source="res://assets/terrain/eurasia_strict_river_map_source.json"
	var seed_value := int(OS.get_environment("HYDROLOGY_SEED")) if not OS.get_environment("HYDROLOGY_SEED").is_empty() else 12345
	print("STRICT_BENCHMARK_START pid=", OS.get_process_id(), " seed=", seed_value, " world_index=0 source=", source)
	var generated := TerrainMapGenerator.build(MapSource.texture_path(source),500,"",{},seed_value,40,"",source)
	print("STRICT_BENCHMARK source=",source," ok=",generated.get("ok",true)," docks=",generated.get("docks",[]).size())
	if not generated.get("ok",true): print("STRICT_BENCHMARK_ERROR ", generated.get("error", "unknown"))
	FileAccess.open("res://.dbg/transport-generation-diagnostic.json", FileAccess.WRITE).store_string(JSON.stringify(generated.get("generation_metadata", {})))
	quit(0 if generated.get("ok",true) else 1)
