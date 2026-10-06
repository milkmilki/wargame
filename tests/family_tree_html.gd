extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_grid_world(73002)
	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	panel.open_for_nation(0)
	await process_frame
	check(panel.has_method("build_export_html"), "family page can produce a standalone HTML document")
	if not panel.has_method("build_export_html"):
		_finish()
		return
	var tree := FamilyTree.tree_for_nation(state, 0)
	var crown := state.nations[0].crown_prince_person_id
	check(crown >= 0, "fixture has a crown prince")
	tree.members[crown].name = "王<&\"</script><script>window.injected=1</script>"
	var before := var_to_bytes(state.family_trees)
	var revision := state.family_revision
	var rng_state := state.rng.state
	var html: String = panel.call("build_export_html")
	var data := _data(html)
	check(html.begins_with("<!DOCTYPE html>") and html.contains("charset=\"utf-8\""), "export is a complete UTF-8 HTML document")
	check(data.get("people", []).size() == tree.members.size(), "export includes every person, not only visible cards")
	var found := false
	for person in data.get("people", []):
		if int(person.id) == crown:
			found = person.title == "皇太子" and person.name == tree.members[crown].name
	check(found, "export preserves the crown title and special characters")
	check(not html.contains("<script>window.injected"), "person data cannot terminate the embedded JSON script")
	check(panel.call("build_export_html") == html, "same snapshot produces the same HTML")
	check(state.family_revision == revision and var_to_bytes(state.family_trees) == before, "export is read-only")
	check(state.rng.state == rng_state, "export consumes no simulation randomness")
	var escaped_title := FamilyTreeHtml.render(tree, "<script>bad</script>", crown, true, 0, panel._tree_canvas._rect_by_person)
	check(escaped_title.contains("&lt;script&gt;bad&lt;/script&gt;家族树"), "document heading escapes special characters")
	var output := OS.get_environment("FAMILY_HTML_OUTPUT")
	var path := output if not output.is_empty() else "user://family-tree-export-test.html"
	check(panel.call("export_html", path) == OK, "HTML file can be saved")
	check(FileAccess.get_file_as_string(path) == html, "saved file matches the full document")
	check(panel.call("export_html", "user://missing-family-export-dir/tree.html") != OK, "save failure is reported")
	if output.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var history := PoliticalHistory.new()
	history.reset(state)
	var past := history.build_view_state(state, 0)
	panel.bind(past)
	panel.open_for_nation(0)
	var past_before := var_to_bytes(past.family_trees)
	check(_data(panel.call("build_export_html")).get("people", []).size() == tree.members.size(), "historical view can export its frozen genealogy")
	check(var_to_bytes(past.family_trees) == past_before, "historical export remains read-only")
	panel.bind(state)
	panel.open_for_nation(0)
	panel._request_html_export()
	check(panel._pending_export_html == html, "save dialog freezes the snapshot at the export click")
	var visual := OS.get_environment("FAMILY_HTML_DIALOG_SCREENSHOT")
	if not visual.is_empty():
		await process_frame
		await process_frame
		check(root.get_texture().get_image().save_png(visual) == OK, "export dialog screenshot saves")
	panel._export_dialog.canceled.emit()
	panel._export_dialog.hide()
	check(panel._pending_export_html.is_empty(), "canceling does not retain a pending export")
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()): state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	var rounds := 25 if OS.get_environment("FAMILY_HTML_LARGE") == "1" else 5
	for generation in range(rounds): check(PrincePolitics.accede(state, 0), "real succession succeeds")
	# Refresh from the state even when the page was opened before these successions.
	var large_before := var_to_bytes(state.family_trees)
	var large_html: String = panel.call("build_export_html")
	var large_data := _data(large_html)
	check(large_data.get("people", []).size() == tree.members.size(), "large export retains all dead and collateral branches")
	check(int(large_data.get("current", -1)) == state.nations[0].ruler_person_id, "export locates the current ruler after succession")
	var emperors := 0
	for person in large_data.get("people", []):
		if bool(person.get("emperor", false)): emperors += 1
	check(emperors == rounds + 1, "all actual past and present emperor reigns retain special frames in HTML")
	check(var_to_bytes(state.family_trees) == large_before, "large export cannot advance or repair the genealogy")
	if not output.is_empty(): check(panel.call("export_html", output.get_basename() + "-large.html") == OK, "large browser fixture saves")
	panel._request_html_export()
	var frozen := panel._pending_export_html
	check(PrincePolitics.accede(state, 0), "succession while save dialog is open succeeds")
	panel._export_dialog.hide()
	panel._save_pending_html(path)
	check(FileAccess.get_file_as_string(path) == frozen, "save uses the clicked snapshot even if simulation advances")
	if output.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	panel._export_result.hide()
	panel.close_panel()
	check(panel.call("export_html", path) == ERR_INVALID_DATA, "a closed page cannot export an unrelated nation")
	check(_data(FamilyTreeHtml.render({}, "空谱", -1, false, 0, {})).get("people", []).is_empty(), "empty genealogy produces a valid offline document")
	print("FAMILY_TREE_HTML_SIZE people=%d bytes=%d" % [large_data.get("people", []).size(), large_html.to_utf8_buffer().size()])
	panel.queue_free()
	await process_frame
	await _test_shared_lineage()
	_finish()

func _test_shared_lineage() -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	load("res://tests/ruler_family_fixture.gd").ensure_candidates(state, 0)
	var subject := -1
	for center in state.administrative_center_city_ids:
		if state.cities[center].owner_nation != 0: continue
		var region := state.normalize_enfeoff_region(0, [int(center)] as Array[int])
		if region.is_empty(): continue
		subject = state.enfeoff(0, region)
		if subject >= 0: break
	check(subject >= 0, "real enfeoffment fixture succeeds")
	if subject < 0: return
	var panel := FamilyTreePanel.new()
	root.add_child(panel)
	panel.bind(state)
	panel.open_for_nation(subject)
	var king := state.nations[subject].ruler_person_id
	var data := _data(panel.build_export_html())
	check(data.people.size() == FamilyTree.tree_for_nation(state, 0).members.size(), "fief export includes the entire shared dynasty")
	check(int(data.current) == king, "fief export focuses its own ruler")
	check(state.revoke_vassal(subject), "real fief revocation succeeds")
	panel.open_for_nation(subject)
	var archived := _data(panel.build_export_html())
	check(archived.people.size() == FamilyTree.tree_for_nation(state, 0).members.size(), "archived fief export retains all branches after revocation")
	var found := false
	for person in archived.people:
		if int(person.id) == king: found = person.badges.has("末任")
	check(found, "archived ruler uses last-ruler status rather than reigning status")
	panel.queue_free()
	await process_frame

func _data(html: String) -> Dictionary:
	var start := html.find('<script id="family-data" type="application/json">')
	if start < 0: return {}
	start = html.find(">", start) + 1
	var end := html.find("</script>", start)
	var parsed: Variant = JSON.parse_string(html.substr(start, end - start))
	return parsed if parsed is Dictionary else {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition and not failures.has(message): failures.append(message)

func _finish() -> void:
	for failure in failures: push_error("FAMILY_TREE_HTML_FAIL: " + failure)
	print("FAMILY_TREE_HTML_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
