extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := GameState.new()
	state.generate_grid_world(24680)
	FamilyTree.ensure_all(state)
	var sovereign := state.nations[0]
	var tree := FamilyTree.tree_for_nation(state, 0)
	var root_id := int(tree.get("root_person_id", -1))
	var members: Dictionary = tree.get("members", {})
	_check(root_id >= 0 and str(members[root_id]["name"]) == "？", "unknown_root")
	_check(
		sovereign.ruler_person_id >= 0
		and int(members[sovereign.ruler_person_id]["parent_id"]) == root_id,
		"initial_ruler_below_root"
	)

	var subject := Nation.new()
	subject.id = state.nations.size()
	subject.name = "河间王"
	subject.short_name = "河间王"
	subject.name_kind = WorldNaming.KIND_VASSAL
	subject.ruler_name = "张四"
	state.nations.append(subject)
	FamilyTree.record_enfeoffment(state, 0, subject.id)
	tree = FamilyTree.tree_for_nation(state, subject.id)
	members = tree["members"]
	_check(subject.family_tree_id == sovereign.family_tree_id, "shared_tree")
	_check(
		int(members[subject.ruler_person_id]["parent_id"])
		== int(members[sovereign.ruler_person_id]["parent_id"]),
		"enfeoffed_ruler_is_sibling"
	)
	_check(
		(members[subject.ruler_person_id]["titles"] as Array).has("河间王"),
		"vassal_title"
	)

	subject.name = "秦王"
	subject.short_name = "秦王"
	FamilyTree.record_current_title(state, subject.id)
	subject.name_kind = "dynasty"
	subject.name = "秦"
	subject.short_name = "秦"
	FamilyTree.record_current_title(state, subject.id)
	members = FamilyTree.tree_for_nation(state, subject.id)["members"]
	var subject_titles := members[subject.ruler_person_id]["titles"] as Array
	_check(
		subject_titles == ["河间王", "秦王", "秦帝"],
		"all_titles_are_kept_in_order"
	)

	var previous_person_id := sovereign.ruler_person_id
	sovereign.ruler_name = "张六"
	FamilyTree.record_succession(state, 0, previous_person_id)
	members = FamilyTree.tree_for_nation(state, 0)["members"]
	_check(
		int(members[sovereign.ruler_person_id]["parent_id"])
		== previous_person_id,
		"successor_is_child"
	)
	_test_real_enfeoffment_hook()

	if not _failures.is_empty():
		for failure in _failures:
			push_error("FAMILY_TREE_SMOKE_FAIL: " + failure)
		quit(1)
		return
	print("FAMILY_TREE_SMOKE_OK")
	quit(0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _test_real_enfeoffment_hook() -> void:
	var state := GameState.new()
	state.generate_grid_world(13579)
	FamilyTree.ensure_all(state)
	var subject_id := -1
	for city in state.land_cities_of(0):
		if city.id == state.nations[0].capital_city_id:
			continue
		subject_id = state.enfeoff(0, [city.id] as Array[int])
		if subject_id >= 0:
			break
	_check(subject_id >= 0, "real_enfeoffment_succeeds")
	if subject_id < 0:
		return
	var overlord := state.nations[0]
	var subject := state.nations[subject_id]
	var tree := FamilyTree.tree_for_nation(state, subject_id)
	var members: Dictionary = tree["members"]
	_check(subject.family_tree_id == overlord.family_tree_id, "real_enfeoffment_shared_tree")
	_check(
		int(members[subject.ruler_person_id]["parent_id"])
		== int(members[overlord.ruler_person_id]["parent_id"]),
		"real_enfeoffment_sibling"
	)
