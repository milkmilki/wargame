extends SceneTree
## Versioned natural-feature contract. Rendering may derive smoother geometry,
## but must never mutate the authoritative paths consumed by map generation.

var _valid := true


func _init() -> void:
	var source := PackedVector2Array([
		Vector2(0.10, 0.30),
		Vector2(0.30, 0.30),
		Vector2(0.48, 0.36),
		Vector2(0.72, 0.41),
	])
	var source_copy := source.duplicate()
	var features := MapFeatureContract.from_legacy_river_paths([source])
	_assert(features.size() == 1, "legacy path did not migrate")
	var river: Dictionary = features[0]
	_assert(int(river.get("id", -1)) == 0, "river id is not stable")
	_assert(
		str(river.get("flow_direction", "")) == "points_downstream",
		"river flow direction is ambiguous"
	)
	_assert(
		str(river.get("source_kind", "")) == "generated_boundary",
		"river source kind is missing"
	)
	_assert(
		MapFeatureContract.validate_rivers(features).is_empty(),
		"valid river contract was rejected"
	)

	var rendered := MapFeatureContract.build_river_render_path(
		river, Vector2i(512, 288), 4
	)
	_assert(rendered.size() > source.size(), "render path was not subdivided")
	_assert(rendered[0].is_equal_approx(source[0]), "source endpoint moved")
	_assert(rendered[-1].is_equal_approx(source[-1]), "mouth endpoint moved")
	_assert(source == source_copy, "render derivation mutated authoritative path")

	var previous_width := -INF
	for index in range(rendered.size()):
		var progress := float(index) / float(rendered.size() - 1)
		var width := MapFeatureContract.width_at_progress(river, progress)
		_assert(width > 0.0, "river width must stay positive")
		_assert(width + 0.000001 >= previous_width, "default river narrows downstream")
		previous_width = width

	var records := MapFeatureContract.serialize_rivers(features)
	var round_trip := MapFeatureContract.deserialize_rivers(records)
	_assert(
		MapFeatureContract.authoritative_paths(round_trip) == [source],
		"river serialization changed authoritative geometry"
	)

	var duplicate_ids := [river.duplicate(true), river.duplicate(true)]
	_assert(
		MapFeatureContract.validate_rivers(duplicate_ids).contains("ID"),
		"duplicate river ids were accepted"
	)
	var malformed := records.duplicate(true)
	malformed[0]["points"][1][0] = "0.3"
	_assert(
		not MapFeatureContract.validate_serialized_rivers(malformed).is_empty(),
		"string coordinate was silently coerced"
	)
	if not _valid:
		quit(1)
		return
	print("MAP_FEATURE_CONTRACT_OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_valid = false
	push_error("MAP_FEATURE_CONTRACT_FAILED: " + message)
