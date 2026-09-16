class_name FamilyTree
extends RefCounted
## 简易王族谱系。国家只持有 tree/person 引用，共享谱保存在 GameState。


static func ensure_all(state: GameState) -> void:
	if state == null:
		return
	for nation in state.nations:
		ensure_nation_lineage(state, nation.id)


static func ensure_nation_lineage(state: GameState, nation_id: int) -> void:
	if not _valid_nation(state, nation_id):
		return
	var nation := state.nations[nation_id]
	if (
		nation.family_tree_id >= 0
		and state.family_trees.has(nation.family_tree_id)
		and nation.ruler_person_id >= 0
	):
		record_current_title(state, nation_id)
		return
	var tree_id := state.next_family_tree_id
	state.next_family_tree_id += 1
	var root_id := _next_person_id(state)
	var ruler_id := _next_person_id(state)
	state.family_trees[tree_id] = {
		"id": tree_id,
		"root_person_id": root_id,
		"members": {
			root_id: _member(root_id, "？", -1, -1),
			ruler_id: _member(
				ruler_id, _person_name(nation.ruler_name), root_id, nation_id
			),
		},
	}
	nation.family_tree_id = tree_id
	nation.ruler_person_id = ruler_id
	record_current_title(state, nation_id)
	state.family_revision += 1


static func record_enfeoffment(
	state: GameState,
	overlord_id: int,
	subject_id: int
) -> void:
	if not _valid_nation(state, overlord_id) or not _valid_nation(state, subject_id):
		return
	ensure_nation_lineage(state, overlord_id)
	var overlord := state.nations[overlord_id]
	var subject := state.nations[subject_id]
	var tree: Dictionary = state.family_trees[overlord.family_tree_id]
	var members: Dictionary = tree["members"]
	var parent_id := int(tree["root_person_id"])
	if members.has(overlord.ruler_person_id):
		parent_id = int(members[overlord.ruler_person_id].get("parent_id", parent_id))
	var person_id := _next_person_id(state)
	members[person_id] = _member(
		person_id, _person_name(subject.ruler_name), parent_id, subject_id
	)
	subject.family_tree_id = overlord.family_tree_id
	subject.ruler_person_id = person_id
	record_current_title(state, subject_id)
	state.family_revision += 1


static func record_succession(
	state: GameState,
	nation_id: int,
	previous_person_id: int
) -> void:
	if not _valid_nation(state, nation_id):
		return
	ensure_nation_lineage(state, nation_id)
	var nation := state.nations[nation_id]
	var tree: Dictionary = state.family_trees[nation.family_tree_id]
	var members: Dictionary = tree["members"]
	var parent_id := previous_person_id
	if not members.has(parent_id):
		parent_id = int(tree["root_person_id"])
	var person_id := _next_person_id(state)
	members[person_id] = _member(
		person_id, _person_name(nation.ruler_name), parent_id, nation_id
	)
	nation.ruler_person_id = person_id
	record_current_title(state, nation_id)
	state.family_revision += 1


static func record_current_title(state: GameState, nation_id: int) -> void:
	if not _valid_nation(state, nation_id):
		return
	var nation := state.nations[nation_id]
	if not state.family_trees.has(nation.family_tree_id):
		return
	var tree: Dictionary = state.family_trees[nation.family_tree_id]
	var members: Dictionary = tree["members"]
	if not members.has(nation.ruler_person_id):
		return
	var title := title_for_nation(state, nation_id)
	if title.is_empty():
		return
	var member: Dictionary = members[nation.ruler_person_id]
	var titles: Array = member["titles"]
	if not titles.has(title):
		titles.append(title)
		state.family_revision += 1
	var nation_ids: Array = member["nation_ids"]
	if not nation_ids.has(nation_id):
		nation_ids.append(nation_id)


static func tree_for_nation(state: GameState, nation_id: int) -> Dictionary:
	if not _valid_nation(state, nation_id):
		return {}
	var tree_id := state.nations[nation_id].family_tree_id
	return state.family_trees.get(tree_id, {}) as Dictionary


static func title_for_nation(state: GameState, nation_id: int) -> String:
	if not _valid_nation(state, nation_id):
		return ""
	var nation := state.nations[nation_id]
	var display_name := WorldNaming.nation_display_name(state, nation_id)
	if str(nation.name_kind) == WorldNaming.KIND_VASSAL:
		return display_name
	if display_name.ends_with("帝"):
		return display_name
	return display_name + "帝"


static func _member(
	person_id: int,
	person_name: String,
	parent_id: int,
	nation_id: int
) -> Dictionary:
	var nation_ids: Array[int] = []
	if nation_id >= 0:
		nation_ids.append(nation_id)
	return {
		"id": person_id,
		"name": person_name,
		"parent_id": parent_id,
		"titles": [] as Array[String],
		"nation_ids": nation_ids,
	}


static func _next_person_id(state: GameState) -> int:
	var person_id := state.next_family_person_id
	state.next_family_person_id += 1
	return person_id


static func _person_name(value: String) -> String:
	var normalized := value.strip_edges()
	return normalized if not normalized.is_empty() else "？"


static func _valid_nation(state: GameState, nation_id: int) -> bool:
	return state != null and nation_id >= 0 and nation_id < state.nations.size()
