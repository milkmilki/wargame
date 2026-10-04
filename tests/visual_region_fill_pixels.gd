extends SceneTree

const TERRAIN_SHADER := preload(
	"res://scripts/view/terrain/strategic_terrain.gdshader"
)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(128, 128)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	viewport.add_child(environment_node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0.0, 2.0, 0.0)
	camera.rotation.x = -PI * 0.5
	viewport.add_child(camera)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh.mesh = quad
	mesh.rotation.x = -PI * 0.5
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	var blank := _solid_texture(Color.TRANSPARENT)
	for parameter in [
		"province_id_texture", "province_boundary_texture",
		"country_boundary_texture", "country_color_texture",
		"visual_region_edge_texture", "visual_coast_mask_texture",
	]:
		material.set_shader_parameter(parameter, blank)
	material.set_shader_parameter("visual_land_mask_texture", _solid_texture(Color.WHITE))
	material.set_shader_parameter("visual_region_coverage_texture", _solid_texture(Color.WHITE))
	var ids := Image.create(16, 16, false, Image.FORMAT_RF)
	var distance := Image.create(16, 16, false, Image.FORMAT_RF)
	for y in range(16):
		for x in range(16):
			ids.set_pixel(x, y, Color(0.0 if x < 8 else 1.0, 0.0, 0.0, 1.0))
			var value := clampf((absf(float(x) - 7.5) - 0.5) / 4.0, 0.0, 1.0)
			distance.set_pixel(x, y, Color(value, 0.0, 0.0, 1.0))
	var lut := Image.create(2, 3, false, Image.FORMAT_RGBA8)
	lut.set_pixel(0, 0, Color(0.85, 0.15, 0.1, 1.0))
	lut.set_pixel(1, 0, Color(0.1, 0.8, 0.2, 1.0))
	material.set_shader_parameter("visual_city_id_texture", ImageTexture.create_from_image(ids))
	material.set_shader_parameter("visual_region_distance_texture", ImageTexture.create_from_image(distance))
	material.set_shader_parameter("province_visual_lut", ImageTexture.create_from_image(lut))
	material.set_shader_parameter("unified_region_fill_enabled", 1.0)
	material.set_shader_parameter("province_strength", 1.0)
	material.set_shader_parameter("country_fill_fade_enabled", 0.0)
	material.set_shader_parameter("local_boundaries_enabled", 0.0)
	material.set_shader_parameter("coast_boundary_strength", 0.0)
	material.set_shader_parameter("country_boundary_strength", 0.0)
	mesh.material_override = material
	viewport.add_child(mesh)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var valid := true
	for interior_x in [32, 96]:
		var base := image.get_pixel(interior_x, 64)
		var first := 56 if interior_x < 64 else 64
		for x in range(first, first + 8):
			var sample := image.get_pixel(x, 64)
			if Vector3(sample.r, sample.g, sample.b).distance_to(
				Vector3(base.r, base.g, base.b)
			) > 0.03:
				push_error("VISUAL_REGION_FILL_PIXELS_FAILED edge faded at x=%d" % x)
				valid = false
		if maxf(base.r, maxf(base.g, base.b)) - minf(base.r, minf(base.g, base.b)) < 0.2:
			push_error("VISUAL_REGION_FILL_PIXELS_FAILED political fill is blank")
			valid = false
	image.save_png(OS.get_temp_dir().path_join("visual-region-fill-pixels.png"))
	if valid:
		print("VISUAL_REGION_FILL_PIXELS_OK")
	viewport.free()
	quit(0 if valid else 1)


func _solid_texture(color: Color) -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
