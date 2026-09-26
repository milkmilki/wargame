extends SceneTree

const LOOKUP := preload("res://scripts/view/province_visual_lookup.gd")


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var lut := LOOKUP.build_visual_lut(state)
	var shader_source := FileAccess.get_file_as_string(
		"res://scripts/view/terrain/strategic_terrain.gdshader"
	)
	var renderer_source := FileAccess.get_file_as_string(
		"res://scripts/view/terrain/strategic_terrain_renderer.gd"
	)
	var map_source := FileAccess.get_file_as_string(
		"res://scripts/view/strategic_map_3d.gd"
	)
	var valid := true
	valid = _check(
		lut.get_size() == Vector2i(state.cities.size(), 3),
		"political LUT must contain base, occupation, and gradient rows"
	) and valid
	for channel in [
		"visual_city_id_texture",
		"visual_land_mask_texture",
		"visual_region_edge_texture",
		"visual_coast_mask_texture",
	]:
		valid = _check(
			shader_source.contains(channel),
			"terrain shader does not sample " + channel
		) and valid
	valid = _check(
		renderer_source.contains("func set_visual_atlas_textures("),
		"terrain renderer has no shared visual-atlas texture interface"
	) and valid
	valid = _check(
		map_source.contains("_visual_city_id_texture"),
		"3D map does not retain the shared city ID texture"
	) and valid
	valid = _check(
		not map_source.contains("var unified_image := MapRenderer.build_region_fill_image_from_masks"),
		"3D diplomacy still rebuilds the 2048 political color image"
	) and valid
	valid = _check(
		shader_source.contains("visual_province_alpha = mix(")
			and shader_source.contains(
				"province_boundary.a, atlas_region_edge"
			),
		"3D province ink does not use the shared 2048 region edge"
	) and valid
	if not valid:
		quit(1)
		return
	print("VISUAL_ATLAS_SHADER_CONTRACT_OK")
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VISUAL_ATLAS_SHADER_CONTRACT_FAILED: " + message)
	return false
