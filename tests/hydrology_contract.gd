extends SceneTree
func _init() -> void:
	var minor := MapFeatureContract.make_river(0, PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.2, 0.2)]))
	minor["river_class"] = "minor"
	minor["terminal_kind"] = "basin"
	var records := MapFeatureContract.serialize_rivers([minor])
	var restored := MapFeatureContract.deserialize_rivers(records)
	assert(restored[0].get("river_class", "") == "minor", "Minor classification lost on save")
	assert(restored[0].get("terminal_kind", "") == "basin")
	assert(MapFeatureContract.validate_rivers(restored).is_empty())
	print("HYDROLOGY_CONTRACT_OK")
	quit()
