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
	var packed := (load(GameState.terrain_map_path()) as Texture2D).get_image()
	var bright_gray := 0
	var coast_samples := 0
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
	if coast_samples <= 0 or bright_gray > 0:
		var output := OS.get_environment("WW_VISUAL_OUTPUT")
		if not output.is_empty():
			frame.save_png(output)
		push_error("COAST_FRINGE_FAILED samples=%d bright_gray=%d" % [coast_samples, bright_gray])
		quit(1)
		return
	print("COAST_FRINGE_OK samples=", coast_samples, " bright_gray=", bright_gray)
	map_3d.free()
	overlay.free()
	simulation.free()
	quit(0)
