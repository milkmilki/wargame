extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_grid_world(73002)
	var nation := state.nations[0]
	var surname := nation.ruler_name.substr(0, 1)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	for id in nation.prince_person_ids:
		check(str(members[id].name).begins_with(surname), "natural children inherit their parent's surname")
	var original_children := nation.prince_person_ids.duplicate()
	if not original_children.is_empty():
		var child := int(original_children.back())
		members[child].name = "王" + str(members[child].name).substr(1)
		var history := PoliticalHistory.new()
		history.reset(state)
		var recorded := str(members[child].name)
		FamilyTree.tree_for_nation(state, 0).erase("surname")
		FamilyTree.ensure_all(state)
		check(str(members[child].name).begins_with(surname), "old live genealogy repairs mismatched surnames")
		check(nation.prince_person_ids == original_children, "surname repair preserves existing children and identities")
		var past := history.build_view_state(state, 0)
		FamilyTree.ensure_all(past)
		check(PrincePolitics.person(past, 0, child).name == recorded, "historical genealogy remains read-only during surname repair")
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()): state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	for generation in range(5):
		check(PrincePolitics.accede(state, 0), "real accession succeeds")
		check(nation.ruler_name.begins_with(surname), "successive rulers retain their dynasty surname")
	for member in members.values():
		if str(member.name) not in ["？", "未载名"]:
			check(str(member.name).begins_with(surname), "all virtual collateral descendants retain the dynasty surname")
	# Force the real accession fallback by exhausting existing candidates.
	for id in members:
		if int(id) != nation.ruler_person_id:
			members[id]["alive"] = false
	check(PrincePolitics.accede(state, 0), "real remote accession succeeds")
	check(nation.ruler_name.begins_with(surname), "remote accession through unnamed ancestors retains the dynasty surname")

	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	check(panel.open_for_nation(0), "family page opens")
	await process_frame
	await process_frame
	var canvas: Control = panel._tree_canvas
	var scroll := canvas.get_parent() as ScrollContainer
	var rects: Dictionary = canvas._rect_by_person
	check(rects.size() == members.size(), "layout includes the complete archived and living genealogy")
	for rect: Rect2 in rects.values():
		check(Rect2(Vector2.ZERO, canvas.custom_minimum_size).encloses(rect), "every card stays inside scrollable canvas bounds")
	var draws := [0]
	canvas.draw.connect(func(): draws[0] += 1)
	await process_frame
	draws[0] = 0
	scroll.scroll_horizontal = 0 if scroll.scroll_horizontal > 0 else int(canvas.custom_minimum_size.x)
	scroll.scroll_vertical = 0 if scroll.scroll_vertical > 0 else int(canvas.custom_minimum_size.y)
	await process_frame
	await process_frame
	check(draws[0] > 0, "scrolling redraws newly visible cards after viewport culling")
	check(canvas.font is FontVariation and canvas.font.variation_embolden > 0, "canvas uses an emboldened font")
	check(canvas.font.base_font.get_font_name().contains("FangSong") if OS.get_name() == "Windows" else true, "Windows family page loads the actual FangSong font")
	check(panel._title.get_theme_color("font_color") == Color.BLACK, "page heading uses black text")
	for child in panel._relations.get_children():
		if child is Label or child is Button:
			check(child.get_theme_color("font_color") == Color.BLACK, "sidebar uses black text")
	panel._set_mode(1)
	await process_frame
	check(not scroll.visible and panel._history_scroll.visible, "history mode releases the whole tree viewport")
	panel._set_mode(0)
	await process_frame
	check(scroll.visible and not panel._history_scroll.visible, "tree mode restores the whole tree viewport")
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if not output.is_empty():
		check(root.get_texture().get_image().save_png(output) == OK, "family page screenshot")
	panel.queue_free()
	await process_frame
	for failure in failures: push_error("FAMILY_TREE_REPAIRS_FAIL: " + failure)
	print("FAMILY_TREE_REPAIRS_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message): failures.append(message)
