extends SceneTree

const Chain = preload("res://tests/succession_chain.gd")
var failures: Array[String] = []
func _init() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
func run() -> void:
	var state: GameState = Chain.fixture()
	var nation := state.nations[0]
	var crown := nation.crown_prince_person_id
	var army := state.create_army(0, 0, 5000)
	army.political_person_id = crown
	var snapshot := NativeSnapshotBuilder.build(state)
	check(snapshot.schema_version == 21, "schema21")
	check(NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(), "valid_strict_politics_schema")
	var incompatible := snapshot.duplicate(true)
	incompatible.schema_version = 19
	check(not NativeSnapshotBuilder.succession_validation_error(incompatible).is_empty(), "old_schema_rejected")
	var corrupt := snapshot.duplicate(true)
	corrupt.nations.prince_offsets[1] = 100000
	check(not NativeSnapshotBuilder.succession_validation_error(corrupt).is_empty(), "corrupt_offsets_rejected")
	corrupt = snapshot.duplicate(true)
	corrupt.nations.crown_prince_ids[0] = 100000
	check(not NativeSnapshotBuilder.succession_validation_error(corrupt).is_empty(), "corrupt_person_rejected")
	check(snapshot.armies.political_person_id[0] == crown and snapshot.nations.crown_prince_ids[0] == crown, "references_recorded")
	check(snapshot.nations.prince_offsets[1] == nation.prince_person_ids.size(), "prince_offsets")
	var invalid_army_owner := snapshot.duplicate(true)
	invalid_army_owner.armies.owner[0] = 99999
	check(not NativeSnapshotBuilder.succession_validation_error(invalid_army_owner).is_empty(), "invalid_army_owner_rejected")
	var invalid_patron := snapshot.duplicate(true)
	invalid_patron.armies.political_person_id[0] = 99999
	check(not NativeSnapshotBuilder.succession_validation_error(invalid_patron).is_empty(), "invalid_army_patron_rejected")
	var invalid_conflict := snapshot.duplicate(true)
	invalid_conflict.succession_conflicts = [{
		"nation_id": 0, "challenger_person_id": crown, "crown_person_id": crown,
		"capital_city_id": 99999, "camp_city_id": 0, "rebel_nation_id": -1,
		"army_ids": [], "crown_army_ids": []
	}]
	check(not NativeSnapshotBuilder.succession_validation_error(invalid_conflict).is_empty(), "invalid_conflict_city_rejected")
	var fingerprint := var_to_bytes(snapshot)
	army.political_person_id = -1
	check(var_to_bytes(NativeSnapshotBuilder.build(state)) != fingerprint, "political_fingerprint")
	army.political_person_id = crown
	var history := PoliticalHistory.new()
	history.reset(state)
	var name := nation.ruler_name
	var profile := nation.ruler_archetype
	state.day = 30
	PrincePolitics.accede(state, 0)
	history.maybe_capture(state)
	var view := history.build_view_state(state, 0)
	check(view.nations[0].crown_prince_person_id == crown and view.nations[0].ruler_name == name and view.nations[0].ruler_archetype == profile, "old_persons_frozen")
	var report: Dictionary = view.get_meta("historical_prince_reports")[0]
	check(int(report.princes[0].troops) == 5000, "historical_troops_frozen")
	check(not FamilyTree.tree_for_nation(view, 0).members.has(nation.prince_person_ids[0]), "future_generation_absent")
	var sections := MapRenderer.historical_nation_detail_sections(view, 0)
	check(sections.any(func(section: Dictionary) -> bool: return section.id == "history.princes"), "history_display")
	var ids := nation.prince_person_ids.duplicate()
	view.nations[0].prince_person_ids.clear()
	check(nation.prince_person_ids == ids, "view_does_not_alias_live")
	for failure in failures:
		push_error("SUCCESSION_HISTORY_FAIL: " + failure)
	print("SUCCESSION_HISTORY: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
