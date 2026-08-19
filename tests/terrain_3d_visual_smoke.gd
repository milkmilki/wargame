extends SceneTree
## Deterministic screenshot probe for the strategic terrain map.

const TIMEOUT_MSEC: int = 15000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var width := int(OS.get_environment("WW_VISUAL_WIDTH"))
	var height := int(OS.get_environment("WW_VISUAL_HEIGHT"))
	root.size = Vector2i(
		width if width > 0 else 1280,
		height if height > 0 else 720
	)
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

	var started := Time.get_ticks_msec()
	while (
		map_3d._terrain == null
		or map_3d._terrain.land_cell_count() <= 0
	):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("TERRAIN_3D_VISUAL_TIMEOUT")
			quit(1)
			return
		await process_frame
	var zoom_factor := float(OS.get_environment("WW_VISUAL_ZOOM"))
	if zoom_factor > 0.0:
		var center_x := float(OS.get_environment("WW_VISUAL_CENTER_X"))
		var center_y := float(OS.get_environment("WW_VISUAL_CENTER_Y"))
		var center := Vector2(
			center_x if center_x > 0.0 else 0.5,
			center_y if center_y > 0.0 else 0.5
		)
		var center_world := map_3d._terrain.map_to_world(center)
		map_3d._camera_target = Vector3(
			center_world.x,
			0.0,
			center_world.z
		)
		map_3d._camera_distance = clampf(
			map_3d._camera_distance * zoom_factor,
			StrategicMap3D.CAMERA_MIN_DISTANCE,
			StrategicMap3D.CAMERA_MAX_DISTANCE
		)
		map_3d._apply_camera_transform()
	await process_frame
	await process_frame

	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if output.is_empty():
		output = "/tmp/world-war-terrain-3d.png"
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("TERRAIN_3D_VISUAL_EMPTY")
		quit(1)
		return
	var error := image.save_png(output)
	if error != OK:
		push_error("TERRAIN_3D_VISUAL_SAVE_FAILED:%d" % error)
		quit(1)
		return
	print(
		"TERRAIN_3D_VISUAL_OK path=",
		output,
		" size=",
		image.get_width(),
		"x",
		image.get_height()
	)
	map_3d.free()
	overlay.free()
	simulation.free()
	quit(0)
