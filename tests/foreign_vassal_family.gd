extends SceneTree

var failures: Array[String] = []
var opened: int = 0
var closed: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(94603)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	state.nations[0].ruler_name = "张一"
	state.nations[1].ruler_name = "李一"
	# The fixture changes dynasty names after generation; update its pre-generated sons too.
	for id in state.nations[1].prince_person_ids:
		var member := PrincePolitics.person(state, 1, id)
		member.name = "李" + str(id)
	FamilyTree.ensure_all(state)
	var foreign_tree := state.nations[1].family_tree_id
	var foreign_person := state.nations[1].ruler_person_id
	_check(state.accept_submission(0, 1), "foreign ruler submits")
	_check(foreign_tree != state.nations[0].family_tree_id, "foreign trees distinct")
	state.day = RulerProfile.succession_due_day(state.nations[1], state.world_seed)
	state._random_ruler_profiles_enabled = true
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._resolve_ruler_successions()
	_check(state.nations[1].ruler_name.begins_with("李") and state.nations[1].family_tree_id == foreign_tree, "foreign succession keeps own dynasty")
	var tree := FamilyTree.tree_for_nation(state, 1)
	_check(int(tree.members[state.nations[1].ruler_person_id].parent_id) == foreign_person, "foreign successor remains descendant")
	var subject_id := -1
	for center_id in state.administrative_center_city_ids:
		if state.cities[center_id].owner_nation == 1 and center_id != state.nations[1].capital_city_id:
			subject_id = state.enfeoff(1, [center_id])
			if subject_id >= 0:
				break
	_check(subject_id >= 0, "foreign vassal can enfeoff relatives")
	if subject_id >= 0:
		_check(state.nations[subject_id].family_tree_id == foreign_tree and state.nations[subject_id].ruler_name.begins_with("李"), "new relative belongs to foreign dynasty")
	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	panel.panel_opened.connect(func(): opened += 1)
	panel.panel_closed.connect(func(): closed += 1)
	panel.open_for_nation(0)
	if not panel.has_method("navigate_to"):
		_check(false, "missing tree navigation")
	else:
		panel.call("navigate_to", 1)
		_check(panel._nation_id == 1 and panel._tree_canvas.current_person_id == state.nations[1].ruler_person_id, "foreign tree navigation")
		panel.call("navigate_back")
		_check(panel._nation_id == 0 and opened == 1 and closed == 0, "back does not reopen pause scope")
	panel.close_panel()
	_check(opened == 1 and closed == 1, "one pause lifecycle")
	var snapshot := NativeSnapshotBuilder.build(state)
	_check(snapshot.schema_version == 20 and snapshot.has("family_trees") and snapshot.nations.has("family_tree_ids"), "lineage persisted in schema20")
	panel.queue_free()
	sim.queue_free()
	await process_frame
	if failures.is_empty():
		print("FOREIGN_VASSAL_FAMILY_OK")
		quit(0)
	else:
		for failure in failures:
			push_error("FOREIGN_VASSAL_FAMILY_FAIL: " + failure)
		quit(1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
