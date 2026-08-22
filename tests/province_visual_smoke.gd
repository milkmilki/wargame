extends SceneTree
## 纯省界视觉烟测：隐藏军队与 HUD，放大地图以检查有机边界和平滑线条。


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(12345)
	state.armies.clear()
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)
	var requested_zoom := float(OS.get_environment("WW_VISUAL_ZOOM"))
	renderer._map_zoom = (
		clampf(
			requested_zoom, MapRenderer.MAP_ZOOM_MIN, MapRenderer.MAP_ZOOM_MAX
		)
		if requested_zoom > 0.0
		else 1.35
	)
	renderer.queue_redraw()
	await process_frame
	await process_frame
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if not output.is_empty():
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.save_png(output) != OK:
			push_error("PROVINCE_VISUAL_SCREENSHOT_FAILED")
			quit(1)
			return
	print("PROVINCE_VISUAL_OK zoom=%.2f" % renderer._map_zoom)
	renderer.free()
	simulation.free()
	quit(0)
