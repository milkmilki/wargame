extends SceneTree
## Renders the expanded city details at the standard desktop viewport and
## verifies that the draggable panel remains fully inside the visible area.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(92033)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)
	renderer.set_world_layer_visible(false)
	renderer.select_city(state.nations[0].capital_city_id)
	await process_frame
	await process_frame
	var panel := renderer._selection_detail_rect(
		renderer._selection_detail_line_count()
	)
	var viewport := Rect2(Vector2.ZERO, Vector2(root.size))
	if not viewport.encloses(panel):
		push_error("CITY_DETAIL_VISUAL_FAILED panel=%s viewport=%s" % [
			str(panel), str(viewport),
		])
		quit(1)
		return
	var output := OS.get_environment("WW_CITY_DETAIL_OUTPUT")
	if output.is_empty():
		output = "user://city-detail-visual.png"
	var image := root.get_texture().get_image()
	var error := image.save_png(output)
	if error != OK:
		push_error("CITY_DETAIL_VISUAL_SAVE_FAILED:%d" % error)
		quit(1)
		return
	print("CITY_DETAIL_VISUAL_OK path=%s panel=%s" % [output, str(panel)])
	renderer.free()
	simulation.free()
	quit(0)
