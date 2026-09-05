extends SceneTree
## Boundary smoothing is a render-only derivation from the authoritative raster.


func _init() -> void:
	var valid := true
	var state := GameState.new()
	state.province_map_size = Vector2i(4, 3)
	state.province_ids = PackedInt32Array([
		0, 0, 1, -1,
		0, 2, 1, -1,
		2, 2, 1, -1,
	])
	var source_copy := state.province_ids.duplicate()
	var topology := MapRenderer.build_province_boundary_topology(state)
	valid = _check(bool(topology.get("render_only", false)), "render-only marker missing") and valid
	valid = _check(
		int(topology.get("contract_version", -1)) == 1,
		"boundary contract version missing"
	) and valid
	valid = _check(
		topology.get("source_size", Vector2i.ZERO) == state.province_map_size,
		"boundary source size missing"
	) and valid
	valid = _check(
		int(topology.get("source_hash", 0)) == hash(source_copy),
		"boundary source hash does not match"
	) and valid
	valid = _check(
		state.province_ids == source_copy,
		"boundary smoothing mutated authoritative province ids"
	) and valid
	valid = _check(
		(topology.get("province", PackedVector2Array()) as PackedVector2Array).size() > 0,
		"province boundary geometry is empty"
	) and valid
	if not valid:
		quit(1)
		return
	print("BOUNDARY_RENDER_CONTRACT_OK")
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("BOUNDARY_RENDER_CONTRACT_FAILED: " + message)
	return false
