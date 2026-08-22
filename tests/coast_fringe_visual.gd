extends SceneTree
## Pixel-level coast gate. Render only terrain, then inspect pixels near the
## packed 0m coastline. No bright low-saturation fringe may be introduced.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(12345)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var overlay := MapRenderer.new()
	root.add_child(overlay)
	overlay.setup(state, simulation)
	overlay.set_world_layer_visible(false)
	var map_3d := StrategicMap3D.new()
	root.add_child(map_3d)
	map_3d.setup(state, simulation, overlay)
	map_3d.set_province_strength(1.0)
	var started := Time.get_ticks_msec()
	while map_3d._terrain == null or map_3d._terrain.land_cell_count() <= 0:
		if Time.get_ticks_msec() - started > 15000:
			push_error("COAST_FRINGE_TIMEOUT")
			quit(1)
			return
		await process_frame
	map_3d._content.visible = false
	await process_frame
	await process_frame
	var frame := root.get_texture().get_image()
	# Difference the exact production render with coast ink disabled. A valid
	# coastline must darken pixels on the same interpolated 0m mesh contour that
	# controls political land/sea fill; a province-raster coast would miss many
	# of these samples even if it happened to avoid a bright fringe.
	map_3d._terrain.set_boundary_lod(0.0, 0.0, 0.0)
	await process_frame
	await process_frame
	var frame_without_coast := root.get_texture().get_image()
	map_3d._terrain.set_boundary_lod(0.0, 1.0, 0.0)
	await process_frame
	await process_frame
	frame = root.get_texture().get_image()
	var packed := (load(GameState.terrain_map_path()) as Texture2D).get_image()
	var bright_gray := 0
	var coast_samples := 0
	var aligned_contour_samples := 0
	var aligned_contour_inked := 0
	var sampled_screen_pixels := {}
	for y in range(1, packed.get_height() - 1, 8):
		for x in range(1, packed.get_width() - 1, 8):
			var land := TerrainMapGenerator.packed_is_land(packed.get_pixel(x, y))
			var touches_other := false
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if TerrainMapGenerator.packed_is_land(packed.get_pixelv(Vector2i(x, y) + offset)) != land:
					touches_other = true
					break
			if not touches_other:
				continue
			var map_position := Vector2((float(x) + 0.5) / packed.get_width(), (float(y) + 0.5) / packed.get_height())
			var screen := map_3d._camera.unproject_position(map_3d._terrain.map_to_world(map_position))
			var center := Vector2i(int(round(screen.x)), int(round(screen.y)))
			for screen_y in range(center.y - 2, center.y + 3):
				for screen_x in range(center.x - 2, center.x + 3):
					if (
						screen_x < 0 or screen_y < 0
						or screen_x >= frame.get_width()
						or screen_y >= frame.get_height()
					):
						continue
					var key := screen_y * frame.get_width() + screen_x
					if sampled_screen_pixels.has(key):
						continue
					sampled_screen_pixels[key] = true
					var color := frame.get_pixel(screen_x, screen_y)
					coast_samples += 1
					# Full political colors are saturated/dark. A bright, nearly
					# neutral pixel within two screen pixels of 0m is leaked primer.
					if color.v > 0.48 and color.s < 0.32:
						bright_gray += 1
	var mesh_resolution := map_3d._terrain.resolution
	var negative_mesh_heights := 0
	var nonnegative_mesh_heights := 0
	var horizontal_crossings := 0
	var vertical_crossings := 0
	for mesh_height in map_3d._terrain._height_samples:
		if mesh_height < 0.0:
			negative_mesh_heights += 1
		else:
			nonnegative_mesh_heights += 1
	for grid_y in range(mesh_resolution.y):
		for grid_x in range(mesh_resolution.x - 1):
			var left_index := grid_y * mesh_resolution.x + grid_x
			var right_index := left_index + 1
			if (map_3d._terrain._height_samples[left_index] >= 0.0) != (map_3d._terrain._height_samples[right_index] >= 0.0):
				horizontal_crossings += 1
			var horizontal_result := _measure_mesh_contour_sample(
				map_3d, frame, frame_without_coast, grid_x, grid_y,
				grid_x + 1, grid_y, left_index, right_index
			)
			if horizontal_result > 0:
				aligned_contour_samples += 1
				if horizontal_result > 1:
					aligned_contour_inked += 1
	for grid_y in range(mesh_resolution.y - 1):
		for grid_x in range(mesh_resolution.x):
			var top_index := grid_y * mesh_resolution.x + grid_x
			var bottom_index := top_index + mesh_resolution.x
			if (map_3d._terrain._height_samples[top_index] >= 0.0) != (map_3d._terrain._height_samples[bottom_index] >= 0.0):
				vertical_crossings += 1
			var vertical_result := _measure_mesh_contour_sample(
				map_3d, frame, frame_without_coast, grid_x, grid_y,
				grid_x, grid_y + 1, top_index, bottom_index
			)
			if vertical_result > 0:
				aligned_contour_samples += 1
				if vertical_result > 1:
					aligned_contour_inked += 1
	var aligned_ratio := (
		float(aligned_contour_inked) / float(maxi(aligned_contour_samples, 1))
	)
	if (
		coast_samples <= 0
		or bright_gray > 0
		or aligned_contour_samples < 100
		or aligned_ratio < 0.80
	):
		var output := OS.get_environment("WW_VISUAL_OUTPUT")
		if not output.is_empty():
			frame.save_png(output)
		push_error("COAST_FRINGE_FAILED samples=%d bright_gray=%d contour=%d inked=%d ratio=%.3f mesh_neg=%d mesh_land=%d hcross=%d vcross=%d" % [coast_samples, bright_gray, aligned_contour_samples, aligned_contour_inked, aligned_ratio, negative_mesh_heights, nonnegative_mesh_heights, horizontal_crossings, vertical_crossings])
		quit(1)
		return
	print("COAST_FRINGE_OK samples=%d bright_gray=%d contour=%d inked=%d ratio=%.3f" % [coast_samples, bright_gray, aligned_contour_samples, aligned_contour_inked, aligned_ratio])
	map_3d.free()
	overlay.free()
	simulation.free()
	quit(0)


func _measure_mesh_contour_sample(
	map_3d: StrategicMap3D,
	frame: Image,
	frame_without_coast: Image,
	x0: int, y0: int, x1: int, y1: int,
	index0: int, index1: int
) -> int:
	var height0 := map_3d._terrain._height_samples[index0]
	var height1 := map_3d._terrain._height_samples[index1]
	var side0 := height0 >= 0.0
	var side1 := height1 >= 0.0
	if side0 == side1:
		return 0
	var denominator := height0 - height1
	if is_zero_approx(denominator):
		return 0
	var ratio := clampf(height0 / denominator, 0.0, 1.0)
	var resolution := map_3d._terrain.resolution
	var uv0 := Vector2(
		float(x0) / float(resolution.x - 1),
		float(y0) / float(resolution.y - 1)
	)
	var uv1 := Vector2(
		float(x1) / float(resolution.x - 1),
		float(y1) / float(resolution.y - 1)
	)
	var uv := uv0.lerp(uv1, ratio)
	var world := Vector3(
		(uv.x - 0.5) * map_3d._terrain.world_size.x,
		0.0,
		(uv.y - 0.5) * map_3d._terrain.world_size.y
	)
	var screen := map_3d._camera.unproject_position(world)
	var center := Vector2i(int(round(screen.x)), int(round(screen.y)))
	var inked := false
	for screen_y in range(center.y - 1, center.y + 2):
		for screen_x in range(center.x - 1, center.x + 2):
			if (
				screen_x < 0 or screen_y < 0
				or screen_x >= frame.get_width()
				or screen_y >= frame.get_height()
			):
				continue
			var with_coast := frame.get_pixel(screen_x, screen_y)
			var without_coast := frame_without_coast.get_pixel(screen_x, screen_y)
			if (
				without_coast.r - with_coast.r > 0.008
				or without_coast.g - with_coast.g > 0.008
				or without_coast.b - with_coast.b > 0.008
			):
				inked = true
				break
		if inked:
			break
	return 2 if inked else 1
