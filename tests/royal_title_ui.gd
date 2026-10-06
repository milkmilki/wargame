extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_grid_world(73002)
	state._random_ruler_profiles_enabled = true
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()): state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	var sim := Simulation.new()
	sim.setup(state)
	var rounds := 25 if OS.get_environment("ROYAL_UI_LARGE") == "1" else 1
	for generation in range(rounds):
		state.day = RulerProfile.succession_due_day(state.nations[0], state.world_seed)
		sim._resolve_ruler_successions()
	var before := var_to_bytes(state.family_trees)
	var revision := state.family_revision
	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	var started := Time.get_ticks_usec()
	check(panel.open_for_nation(0), "royal tree opens")
	await process_frame
	await process_frame
	var canvas: Control = panel._tree_canvas
	var rects: Dictionary = canvas._rect_by_person
	var scroll := canvas.get_parent() as ScrollContainer
	var viewport_rect := Rect2(Vector2(scroll.scroll_horizontal, scroll.scroll_vertical), scroll.size)
	check(viewport_rect.intersects(rects[state.nations[0].ruler_person_id]), "large tree focuses current ruler")
	check(state.family_revision == revision and var_to_bytes(state.family_trees) == before, "opening tree is observational")
	var groups := 0
	for child in panel._relations.get_children():
		if child is VBoxContainer:
			groups += 1
			check(child.get_child_count() == 0 and not child.visible, "title groups defer population rendering")
	check(groups == 3, "all three tiers have separate collapsed groups")
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var census := RoyalTitles.report(state, 0)
	for rank in [3, 2, 1]:
		var content := VBoxContainer.new()
		panel._append_title_page(content, census.people[rank], 0)
		for index in range(mini(census.people[rank].size(), 40)):
			var id := int(census.people[rank][index])
			check((content.get_child(index) as Label).text.contains(str(members[id].current_title)), "expanded title list shows the concrete saved designation")
		content.free()
	check(state.family_revision == revision and var_to_bytes(state.family_trees) == before, "expanding title lists cannot rename people")
	for id in state.nations[0].prince_person_ids:
		check(not FamilyTree.display_title(members[id], id, 0).contains("皇子"), "card subtitle shows current title")
	var count := rects.size()
	print("ROYAL_TITLE_UI nodes=%d open_us=%d visible=%s" % [count, Time.get_ticks_usec() - started, str(viewport_rect)])
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if not output.is_empty():
		var rendered := root.get_texture().get_image()
		check(rendered != null and not rendered.is_empty() and rendered.save_png(output) == OK, "royal UI screenshot")
	panel.queue_free()
	sim.free()
	await process_frame
	for failure in failures: push_error("ROYAL_TITLE_UI_FAIL: " + failure)
	print("ROYAL_TITLE_UI_RESULT failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
