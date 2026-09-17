extends SceneTree
## Deterministic multi-branch family-tree screenshot used for visual regression.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.10, 0.09, 0.07, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var state := GameState.new()
	state.generate_grid_world(24680)
	FamilyTree.ensure_nation_lineage(state, 0)
	var nation := state.nations[0]
	nation.name = "汉"
	nation.short_name = "汉"
	nation.name_kind = WorldNaming.KIND_DYNASTY
	var tree_id := nation.family_tree_id
	state.family_trees[tree_id] = {
		"id": tree_id,
		"root_person_id": 0,
		"members": {
			0: _member(0, "？", -1, []),
			1: _member(1, "张太初", 0, ["汉帝"]),
			2: _member(2, "张景明", 0, ["秦王"]),
			3: _member(3, "张承安", 0, ["齐王"]),
			4: _member(4, "张弘业", 1, ["汉帝"]),
			5: _member(5, "张世宁", 2, ["秦王", "秦帝"]),
			6: _member(6, "张元恺", 3, ["齐王"]),
			7: _member(7, "张文昭", 4, ["汉帝"]),
			8: _member(8, "张怀瑾", 4, ["楚王"]),
			9: _member(9, "张允和", 5, ["秦帝"]),
			11: _member(11, "张廷玉", 6, ["齐王"]),
		},
	}
	nation.ruler_person_id = 7

	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	if not panel.open_for_nation(0):
		push_error("FAMILY_TREE_VISUAL_OPEN_FAILED")
		quit(1)
		return
	await process_frame
	await process_frame

	var canvas: Control = panel._tree_canvas
	var rects: Dictionary = canvas._rect_by_person
	var valid := rects.size() == 11
	for first_value in rects.keys():
		for second_value in rects.keys():
			var first := int(first_value)
			var second := int(second_value)
			if first >= second:
				continue
			valid = valid and not (
				(rects[first] as Rect2).intersects(rects[second] as Rect2)
			)
	if not valid:
		push_error("FAMILY_TREE_VISUAL_LAYOUT_INVALID")
		quit(1)
		return

	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if output.is_empty():
		output = "user://family-tree-sample.png"
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output) != OK:
		push_error("FAMILY_TREE_VISUAL_SCREENSHOT_FAILED")
		quit(1)
		return
	print("FAMILY_TREE_VISUAL_OK path=%s nodes=%d" % [output, rects.size()])
	quit(0)


func _member(
	person_id: int,
	person_name: String,
	parent_id: int,
	titles: Array[String]
) -> Dictionary:
	return {
		"id": person_id,
		"name": person_name,
		"parent_id": parent_id,
		"titles": titles,
		"nation_ids": [] as Array[int],
	}
