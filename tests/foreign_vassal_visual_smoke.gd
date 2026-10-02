extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(94605)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	if not state.accept_submission(0, 1):
		quit(1)
		return
	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	var directory := OS.get_environment("WW_VISUAL_OUTPUT")
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = dimensions
		panel.open_for_nation(0)
		await process_frame
		await process_frame
		if panel._relations.get_child_count() != 1:
			push_error("FOREIGN_VASSAL_VISUAL_FAIL: missing foreign link")
			quit(1)
			return
		var button := panel._relations.get_child(0) as Button
		if button.size.x <= 0.0 or button.size.x > 220.0:
			push_error("FOREIGN_VASSAL_VISUAL_FAIL: invalid sidebar width")
			quit(1)
			return
		if not directory.is_empty():
			var image := root.get_texture().get_image()
			if image == null or image.save_png(directory.path_join("foreign-vassal-%dx%d.png" % [dimensions.x, dimensions.y])) != OK:
				quit(1)
				return
		button.pressed.emit()
		await process_frame
		if panel._nation_id != 1 or panel._tree_canvas.tree.id != state.nations[1].family_tree_id:
			push_error("FOREIGN_VASSAL_VISUAL_FAIL: link did not switch tree")
			quit(1)
			return
		panel.navigate_back()
	panel.close_panel()
	print("FOREIGN_VASSAL_VISUAL_OK")
	quit(0)
