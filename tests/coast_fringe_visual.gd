extends SceneTree
## Pixel-level coast gate. Render only terrain, then inspect pixels near the
## packed 0m coastline. No bright low-saturation fringe may be introduced.

const COAST_COLOR_CHANGE_THRESHOLD := 0.008
## White unclaimed land has less contrast against light nation coast colors
## than the removed dark-blue fallback. Geometry and inland false positives
## remain strict; this ratio only measures visible screenshot color delta.
const MIN_ALIGNED_CONTOUR_CHANGE_RATIO := 0.65


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
	var frame_with_all_boundaries := root.get_texture().get_image()
	var frame := frame_with_all_boundaries
	# Difference the exact production render with coast ink disabled. A valid
	# coastline must change color on the same interpolated 0m mesh contour that
	# controls political land/sea fill. The land-side country color may brighten,
	# darken or shift hue; a province-raster coast would miss many samples.
	map_3d._terrain.set_boundary_lod(0.0, 0.0, 0.0)
	await process_frame
	await process_frame
	var frame_without_boundaries := root.get_texture().get_image()
	map_3d._terrain.set_boundary_lod(0.0, 1.0, 0.0)
	await process_frame
	await process_frame
	frame = root.get_texture().get_image()
	var frame_without_coast := frame_without_boundaries
	var packed := (load(GameState.terrain_map_path()) as Texture2D).get_image()
	var coast_samples := 0
	var aligned_contour_samples := 0
	var aligned_contour_changed := 0
	var inland_false_positive_samples := 0
	var inland_false_positive_changed := 0
	var political_boundary_samples := 0
	var political_boundary_bright_gray := 0
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
			for screen_y in range(center.y - 5, center.y + 6):
				for screen_x in range(center.x - 5, center.x + 6):
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
					coast_samples += 1
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
					aligned_contour_changed += 1
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
					aligned_contour_changed += 1
	# The explicit UV2 coast-domain marker must suppress low-elevation inland
	# slopes. At the 384 mesh a 3px coast can legitimately span more than one
	# projected grid cell, so only classify vertices with a 7x7 all-land
	# neighborhood as interior. Toggling coast may not change those pixels.
	for grid_y in range(4, mesh_resolution.y - 4, 5):
		for grid_x in range(4, mesh_resolution.x - 4, 5):
			var index := grid_y * mesh_resolution.x + grid_x
			if map_3d._terrain._height_samples[index] < 0.0:
				continue
			var interior := true
			for offset_y in range(-3, 4):
				for offset_x in range(-3, 4):
					var nearby := (grid_y + offset_y) * mesh_resolution.x + grid_x + offset_x
					if map_3d._terrain._height_samples[nearby] < 0.0:
						interior = false
			if not interior:
				continue
			var uv := Vector2(
				float(grid_x) / float(mesh_resolution.x - 1),
				float(grid_y) / float(mesh_resolution.y - 1)
			)
			var screen := map_3d._camera.unproject_position(
				map_3d._terrain.map_to_world(uv)
			)
			var pixel := Vector2i(int(round(screen.x)), int(round(screen.y)))
			if (
				pixel.x < 0 or pixel.y < 0
				or pixel.x >= frame.get_width() or pixel.y >= frame.get_height()
			):
				continue
			inland_false_positive_samples += 1
			var with_coast := frame.get_pixelv(pixel)
			var without_coast := frame_without_coast.get_pixelv(pixel)
			if _rgb_change(with_coast, without_coast) > COAST_COLOR_CHANGE_THRESHOLD:
				inland_false_positive_changed += 1
	var political_geometry := MapRenderer.build_province_boundary_segments(state)
	for boundary_key in ["province", "country"]:
		var segments: PackedVector2Array = political_geometry[boundary_key]
		var stride := maxi((segments.size() / 2) / 800, 1)
		for segment_index in range(0, segments.size() / 2, stride):
			var midpoint := (
				segments[segment_index * 2]
				+ segments[segment_index * 2 + 1]
			) * 0.5
			var screen := map_3d._camera.unproject_position(
				map_3d._terrain.map_to_world(midpoint)
			)
			var center := Vector2i(int(round(screen.x)), int(round(screen.y)))
			for screen_y in range(center.y - 2, center.y + 3):
				for screen_x in range(center.x - 2, center.x + 3):
					if (
						screen_x < 0 or screen_y < 0
						or screen_x >= frame.get_width()
						or screen_y >= frame.get_height()
					):
						continue
					political_boundary_samples += 1
					var color := frame_with_all_boundaries.get_pixel(
						screen_x, screen_y
					)
					var without_boundary := frame_without_boundaries.get_pixel(
						screen_x, screen_y
					)
					if (
						_rgb_change(color, without_boundary)
							> COAST_COLOR_CHANGE_THRESHOLD
						and color.v > without_boundary.v + 0.02
						and color.s < 0.32
					):
						political_boundary_bright_gray += 1
	var aligned_ratio := (
		float(aligned_contour_changed) / float(maxi(aligned_contour_samples, 1))
	)
	if (
		coast_samples <= 0
		or aligned_contour_samples < 100
		or aligned_ratio < MIN_ALIGNED_CONTOUR_CHANGE_RATIO
		or inland_false_positive_samples < 100
		or inland_false_positive_changed > 0
		or political_boundary_samples < 100
		or political_boundary_bright_gray > 0
	):
		var output := OS.get_environment("WW_VISUAL_OUTPUT")
		if not output.is_empty():
			frame_with_all_boundaries.save_png(output)
		push_error("COAST_FRINGE_FAILED samples=%d contour=%d changed=%d ratio=%.3f inland=%d/%d boundary_gray=%d/%d mesh_neg=%d mesh_land=%d hcross=%d vcross=%d" % [coast_samples, aligned_contour_samples, aligned_contour_changed, aligned_ratio, inland_false_positive_changed, inland_false_positive_samples, political_boundary_bright_gray, political_boundary_samples, negative_mesh_heights, nonnegative_mesh_heights, horizontal_crossings, vertical_crossings])
		quit(1)
		return
	print("COAST_FRINGE_OK samples=%d contour=%d changed=%d ratio=%.3f inland=%d/%d boundary_gray=%d/%d" % [coast_samples, aligned_contour_samples, aligned_contour_changed, aligned_ratio, inland_false_positive_changed, inland_false_positive_samples, political_boundary_bright_gray, political_boundary_samples])
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
	# The country-color coast is a 3px land-side band. Search two screen pixels
	# around the exact projected 0m point so subpixel rounding can land on either
	# side without weakening the requirement that the contour itself is nearby.
	var maximum_rgb_change := 0.0
	for screen_y in range(center.y - 2, center.y + 3):
		for screen_x in range(center.x - 2, center.x + 3):
			if (
				screen_x < 0 or screen_y < 0
				or screen_x >= frame.get_width()
				or screen_y >= frame.get_height()
			):
				continue
			var with_coast := frame.get_pixel(screen_x, screen_y)
			var without_coast := frame_without_coast.get_pixel(screen_x, screen_y)
			maximum_rgb_change = maxf(
				maximum_rgb_change, _rgb_change(with_coast, without_coast)
			)
	return 2 if maximum_rgb_change > COAST_COLOR_CHANGE_THRESHOLD else 1


func _rgb_change(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))
