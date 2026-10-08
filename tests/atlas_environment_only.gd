extends SceneTree

var SOURCE: String = OS.get_environment("ATLAS_SOURCE") if not OS.get_environment("ATLAS_SOURCE").is_empty() else "res://assets/terrain/eurasia_atlas_baseline_map_source.json"

func _init() -> void: call_deferred("run")

func run() -> void:
	var state := GameState.new()
	assert(state.generate_world(12345, 40, 500, "", {}, 12345, "", SOURCE), state.last_generation_error)
	assert(state.river_features.is_empty(), "environment-only water must not become runtime rivers")
	assert(state.river_paths.is_empty(), "environment-only water must not become visible paths")
	assert(state.land_cities().size() == 500)
	for city in state.cities: assert(not city.is_dock, "environment-only mode must not reserve river docks")
	for edge in state.edges: assert(edge.kind not in [Edge.Kind.RIVER, Edge.Kind.LANDING])
	assert(state.generation_metadata.get("major_reaches", 0) > 0, "environment water must still be evaluated")
	assert(state.territory_structure_valid())
	var template := MapDefinition.from_state(state)
	var restored := GameState.new()
	restored.generate_from_map_definition(template, 12345)
	assert(restored.river_features.is_empty() and restored.river_paths.is_empty())
	assert(restored.province_ids == state.province_ids)
	if MapSource.atlas_roads(SOURCE):
		var file:=FileAccess.open("res://.dbg/atlas-world-12345.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(template))
	print("ATLAS_ENVIRONMENT_ONLY_PASS cities=", state.cities.size(), " edges=", state.edges.size())
	quit()
