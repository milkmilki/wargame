extends SceneTree
## Generated maps and saved map definitions share one natural-feature schema,
## while version 3/4 river_paths remain readable without migration tooling.

var _valid := true


func _init() -> void:
	var original := GameState.new()
	original.generate_world(12345, 4, 68)
	_assert(
		original.river_features.size() == original.river_paths.size(),
		"generated river features and compatibility paths diverged"
	)
	_assert(
		MapFeatureContract.validate_rivers(original.river_features).is_empty(),
		"generator emitted an invalid river contract"
	)
	var definition := MapDefinition.from_state(original)
	_assert(definition.has("rivers"), "map definition omitted structured rivers")
	_assert(MapDefinition.validate(definition).is_empty(), "new map definition rejected")

	var restored := GameState.new()
	restored.generate_from_map_definition(definition, 12345)
	_assert(
		MapFeatureContract.authoritative_paths(restored.river_features)
			== original.river_paths,
		"structured river round trip changed topology paths"
	)

	var legacy := definition.duplicate(true)
	legacy["version"] = 4
	legacy.erase("rivers")
	_assert(MapDefinition.validate(legacy).is_empty(), "legacy map rejected")
	var legacy_restored := GameState.new()
	legacy_restored.generate_from_map_definition(legacy, 12345)
	_assert(
		MapFeatureContract.authoritative_paths(legacy_restored.river_features)
			== original.river_paths,
		"legacy river paths were not migrated"
	)
	var stale_path := original.river_paths[0].duplicate()
	stale_path[0] += Vector2(0.01, 0.0)
	original.river_paths[0] = stale_path
	var canonical_export := MapDefinition.from_state(original)
	_assert(
		MapDefinition.validate(canonical_export).is_empty(),
		"export trusted a stale compatibility river path"
	)
	if not _valid:
		quit(1)
		return
	print("MAP_FEATURE_ROUND_TRIP_OK rivers=", original.river_features.size())
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_valid = false
	push_error("MAP_FEATURE_ROUND_TRIP_FAILED: " + message)
