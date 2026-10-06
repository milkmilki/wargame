extends SceneTree

const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
const PoliticsAudit = preload("res://tests/succession_audit.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_grid_world(73004)
	state._random_ruler_profiles_enabled = true
	for generation in range(2):
		FamilyFixture.ensure_candidates(state, 0, 2)
		check(PrincePolitics.accede(state, 0), "fixture creates deeper real blood generations")
	var nation := state.nations[0]
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var old_id := nation.ruler_person_id
	for member in members.values():
		if int(member.id) != old_id: member["alive"] = false
		member["children_initialized"] = true
	nation.prince_person_ids.clear()
	nation.crown_prince_person_id = -1
	state.family_revision += 1
	var history := PoliticalHistory.new()
	history.reset(state)
	var sim := Simulation.new()
	sim.setup(state)
	state.day = RulerProfile.succession_due_day(nation, state.world_seed)
	sim._resolve_ruler_successions()
	var incoming := nation.ruler_person_id
	check(incoming != old_id and bool(members[incoming].get("remote_branch", false)), "real scheduled accession selects remote fallback")
	check(PoliticsAudit.inspect(state).errors.is_empty(), "scheduled fallback preserves political invariants")
	var validation_error := NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state))
	check(validation_error.is_empty(), "remote ancestor chain validates in schema24: " + validation_error)
	var snapshot := NativeSnapshotBuilder.build(state)
	for tree in snapshot.family_trees:
		if int(tree.id) != nation.family_tree_id: continue
		for member in tree.members:
			if int(member.id) == int(members[incoming].parent_id): member.parent_id = incoming
	check(NativeSnapshotBuilder.succession_validation_error(snapshot).contains("Cyclic family ancestry"), "native explicitly rejects cyclic remote ancestry")
	var view := history.build_view_state(state, 0)
	check(view.nations[0].ruler_person_id == old_id and not FamilyTree.tree_for_nation(view, 0).members.has(incoming), "history cannot borrow future remote branch")
	var before := var_to_bytes(state.family_trees)
	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	check(panel.open_for_nation(0), "remote family tree opens")
	await process_frame
	await process_frame
	check(var_to_bytes(state.family_trees) == before, "opening remote tree cannot mutate birth flags or ancestors")
	var canvas: Control = panel._tree_canvas
	var scroll := canvas.get_parent() as ScrollContainer
	var visible := Rect2(Vector2(scroll.scroll_horizontal, scroll.scroll_vertical), scroll.size)
	check(visible.intersects(canvas._rect_by_person[incoming]), "tree focuses actual remote ruler")
	var synthetic_count := members.values().filter(func(member): return bool(member.get("synthetic_ancestor", false)) and str(member.name) == "未载名").size()
	check(synthetic_count == 2, "missing remote ancestors have explicit labels and correct generation: " + str(synthetic_count))
	var output := OS.get_environment("WW_VISUAL_OUTPUT")
	if not output.is_empty():
		check(root.get_texture().get_image().save_png(output) == OK, "remote tree screenshot")
	panel.queue_free()
	sim.free()
	await process_frame
	for failure in failures: push_error("RULER_EXTINCTION_RUNTIME_FAIL: " + failure)
	print("RULER_EXTINCTION_RUNTIME_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
