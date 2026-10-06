class_name FamilyTree
extends RefCounted
## 简易王族谱系。国家只持有 tree/person 引用，共享谱保存在 GameState。


static func ensure_all(state: GameState) -> void:
	if state == null or state.has_meta("historical_prince_reports"):
		return
	for nation in state.nations:
		if not nation.alive or nation.succession_identity:
			continue
		ensure_nation_lineage(state, nation.id)
		PrincePolitics.ensure_generation(state, nation.id)


static func ensure_nation_lineage(state: GameState, nation_id: int) -> void:
	if not _valid_nation(state, nation_id) or state.has_meta("historical_prince_reports"):
		return
	var nation := state.nations[nation_id]
	if (
		nation.family_tree_id >= 0
		and state.family_trees.has(nation.family_tree_id)
		and nation.ruler_person_id >= 0
	):
		_ensure_surname(state, nation_id)
		record_current_title(state, nation_id)
		return
	var tree_id := state.next_family_tree_id
	state.next_family_tree_id += 1
	var root_id := _next_person_id(state)
	var ruler_id := _next_person_id(state)
	state.family_trees[tree_id] = {
		"id": tree_id,
		"surname": WorldNaming.ruler_surname(_person_name(nation.ruler_name)),
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
	subject_id: int,
	reused_person_id: int = -1
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
	var person_id := reused_person_id
	if person_id < 0:
		person_id = _next_person_id(state)
		subject.ruler_name = surname_for_nation(state, overlord_id) + _person_name(subject.ruler_name).substr(1)
		members[person_id] = _member(person_id, subject.ruler_name, parent_id, subject_id)
		if members.has(parent_id):
			var child_ids := RoyalTitles.children(members, parent_id)
			if not child_ids.has(person_id):
				child_ids.append(person_id)
			members[parent_id]["child_ids"] = child_ids
	else:
		var member: Dictionary = members[person_id]
		subject.ruler_name = str(member.name)
		subject.ruler_archetype = int(member.archetype)
		subject.ruler_traits.assign(member.traits)
		subject.trade_policy = RulerProfile.trade_policy_for(subject)
		member["enfeoffed_nation_id"] = subject_id
		PrincePolitics.centralize(state, overlord_id, [person_id] as Array[int])
	subject.family_tree_id = overlord.family_tree_id
	subject.ruler_person_id = person_id
	RoyalTitles.enfeoff(state, overlord_id, subject_id, person_id)
	record_current_title(state, subject_id)
	PrincePolitics.ensure_generation(state, subject_id)
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
	nation.ruler_name = surname_for_nation(state, nation_id) + _person_name(nation.ruler_name).substr(1)
	members[person_id] = _member(
		person_id, _person_name(nation.ruler_name), parent_id, nation_id
	)
	if members.has(parent_id):
		var child_ids := RoyalTitles.children(members, parent_id)
		if not child_ids.has(person_id):
			child_ids.append(person_id)
		members[parent_id]["child_ids"] = child_ids
	RoyalTitles.advance_generation(state, nation_id, person_id)
	if members.has(previous_person_id):
		members[previous_person_id]["alive"] = false
	PrincePolitics.centralize(state, nation_id, nation.prince_person_ids)
	nation.ruler_person_id = person_id
	nation.prince_person_ids.clear()
	record_current_title(state, nation_id)
	PrincePolitics.ensure_generation(state, nation_id)
	RoyalTitles.reconcile(state)
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
	RoyalTitles.set_member(state, member, "current_title", title)
	RoyalTitles.set_member(state, member, "office_nation_id", nation_id)
	RoyalTitles.set_member(state, member, "title_payer_id", nation_id)
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


static func surname_for_nation(state: GameState, nation_id: int) -> String:
	var tree := tree_for_nation(state, nation_id)
	if not str(tree.get("surname", "")).is_empty():
		return str(tree.surname)
	# 旧谱的初代君主最早入谱；未知先祖和补录祖链不作为姓氏来源。
	var members: Dictionary = tree.get("members", {})
	var ids := members.keys()
	ids.sort()
	for id in ids:
		var name := str(members[id].get("name", "？"))
		if name not in ["？", "未载名", ""]:
			return WorldNaming.ruler_surname(name)
	return WorldNaming.ruler_surname(state.nations[nation_id].ruler_name)


static func _ensure_surname(state: GameState, nation_id: int) -> void:
	var tree := tree_for_nation(state, nation_id)
	if tree.has("surname"):
		return
	var surname := surname_for_nation(state, nation_id)
	tree["surname"] = surname
	for member in tree.members.values():
		var name := str(member.get("name", "？"))
		if name not in ["？", "未载名", ""]:
			member["name"] = surname + name.substr(1)
	for nation in state.nations:
		if nation.family_tree_id == int(tree.id) and tree.members.has(nation.ruler_person_id):
			nation.ruler_name = str(tree.members[nation.ruler_person_id].name)
	state.family_revision += 1
	state.naming_revision += 1


static func title_for_nation(state: GameState, nation_id: int) -> String:
	if not _valid_nation(state, nation_id):
		return ""
	var nation := state.nations[nation_id]
	var display_name := WorldNaming.nation_display_name(state, nation_id)
	if str(nation.name_kind) == WorldNaming.KIND_VASSAL:
		return display_name
	if display_name.ends_with("帝"):
		return display_name
	return display_name + ("帝" if nation.state_level == EmpireStatus.EMPIRE else "君")


static func was_emperor(member: Dictionary) -> bool:
	if str(member.get("current_title", "")).ends_with("帝"):
		return true
	for title in member.get("titles", []):
		if str(title).ends_with("帝"):
			return true
	return false


static func display_title(member: Dictionary, person_id: int, root_person_id: int, state: GameState = null) -> String:
	if person_id == root_person_id or int(member.get("parent_id", -1)) < 0:
		return "先祖"
	if state != null and bool(member.get("alive", true)):
		var office := int(member.get("office_nation_id", -1))
		if office >= 0 and office < state.nations.size() and state.nations[office].alive and state.nations[office].ruler_person_id == person_id:
			return title_for_nation(state, office)
		if RoyalTitles.effective_rank(state, member) <= 0:
			return "无爵"
	if member.has("current_title"):
		return str(member.current_title)
	return "无爵"

static func affiliation_label(state: GameState, member: Dictionary, selected_nation: int) -> String:
	var owner := int(member.get("title_payer_id", -1))
	if owner < 0 or owner >= state.nations.size() or owner == selected_nation:
		return ""
	return "属" + WorldNaming.nation_display_name(state, owner)

static func title_history_lines(member: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var reasons := {"accession": "登基", "enfeoffment": "分封建国", "annexation": "并入他国", "death": "去世", "retitled": "改爵"}
	for record in member.get("title_history", []):
		result.append("%s · 来源%s（国%d） · 第%d天授爵 · %s" % [record.title, record.origin_nation_name, int(record.origin_nation_id), int(record.start_day),
			"现有爵位" if int(record.get("end_day", -1)) < 0 else "第%d天因%s终止" % [int(record.end_day), reasons.get(str(record.end_reason), str(record.end_reason))]])
	return result


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
		"children_initialized": false,
		"titles": [] as Array[String],
		"nation_ids": nation_ids,
		"title_payer_id": nation_id,
		"title_origin_nation_id": -1,
		"title_history": [],
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
