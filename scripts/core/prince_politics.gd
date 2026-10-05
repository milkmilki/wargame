class_name PrincePolitics
extends RefCounted

static func command_weight(archetype: int) -> int:
	if archetype in [RulerProfile.CONQUEROR, RulerProfile.REFORMER, RulerProfile.TYRANT]:
		return 3
	if archetype in [RulerProfile.INEPT, RulerProfile.PUPPET]:
		return 1
	return 2

static func person(state: GameState, nation_id: int, person_id: int) -> Dictionary:
	return FamilyTree.tree_for_nation(state, nation_id).get("members", {}).get(person_id, {})

static func eligible(member: Dictionary) -> bool:
	return not member.is_empty() and bool(member.get("alive", true)) and int(member.get("enfeoffed_nation_id", -1)) < 0

static func ensure_generation(state: GameState, nation_id: int) -> void:
	var nation := state.nations[nation_id]
	if nation.succession_identity or not nation.prince_person_ids.is_empty():
		return
	FamilyTree.ensure_nation_lineage(state, nation_id)
	var count := 2 + RulerProfile.stable_index(state.world_seed, nation_id, "prince/count", 4, nation.ruler_revision)
	for order in range(count):
		nation.prince_person_ids.append(_create_person(state, nation_id, nation.ruler_person_id, order))
	nation.crown_prince_person_id = nation.prince_person_ids[0]
	nation.succession_competition_closed = false
	state.family_revision += 1

static func _create_person(state: GameState, nation_id: int, parent_id: int, order: int) -> int:
	var nation := state.nations[nation_id]
	var id := state.next_family_person_id
	state.next_family_person_id += 1
	var salt := nation.ruler_revision * 1009 + order * 31 + 700001
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	var name := WorldNaming.person_name_for(state.world_seed, nation_id, salt)
	members[id] = {"id": id, "name": name, "parent_id": parent_id, "titles": [], "nation_ids": [],
		"archetype": RulerProfile.archetype_for(state.world_seed, nation_id, salt),
		"traits": RulerProfile.traits_for(state.world_seed, nation_id, salt),
		"birth_order": order, "alive": true, "enfeoffed_nation_id": -1}
	return id

static func profile(state: GameState, nation_id: int, person_id: int) -> Dictionary:
	var member := person(state, nation_id, person_id)
	return {"ruler_archetype": int(member.get("archetype", RulerProfile.BALANCED)), "ruler_traits": member.get("traits", [])}

static func assign_new_army(state: GameState, army: Army) -> void:
	army.political_person_id = -1
	var nation := state.nations[army.owner_nation]
	ensure_generation(state, nation.id)
	var conflict: SuccessionConflict = state.succession_conflicts.get(nation.id)
	if nation.succession_competition_closed or (conflict != null and conflict.launched()):
		return
	var ticket := RulerProfile.stable_index(state.world_seed, nation.id, "prince/army", 100, army.id)
	if ticket < 50:
		return
	if ticket < 60:
		if eligible(person(state, nation.id, nation.crown_prince_person_id)):
			army.political_person_id = nation.crown_prince_person_id
		return
	var candidates: Array[int] = []
	var total := 0
	for id in nation.prince_person_ids:
		var member := person(state, nation.id, id)
		if eligible(member):
			candidates.append(id)
			total += command_weight(int(member.archetype))
	if total <= 0:
		return
	var weighted := RulerProfile.stable_index(state.world_seed, nation.id, "prince/army_weight", total, army.id)
	for id in candidates:
		weighted -= command_weight(int(person(state, nation.id, id).archetype))
		if weighted < 0:
			army.political_person_id = id
			return

static func centralize(state: GameState, nation_id: int, person_ids: Array[int]) -> void:
	for army in state.armies:
		if army.owner_nation == nation_id and person_ids.has(army.political_person_id):
			army.political_person_id = -1

static func accede(state: GameState, nation_id: int) -> bool:
	ensure_generation(state, nation_id)
	var nation := state.nations[nation_id]
	var member := person(state, nation_id, nation.crown_prince_person_id)
	if not eligible(member):
		return false
	person(state, nation_id, nation.ruler_person_id)["alive"] = false
	centralize(state, nation_id, nation.prince_person_ids)
	nation.ruler_person_id = nation.crown_prince_person_id
	nation.ruler_name = str(member.name)
	nation.ruler_archetype = int(member.archetype)
	nation.ruler_traits.assign(member.traits)
	nation.ruler_revision += 1
	nation.ruler_started_day = state.day
	nation.trade_policy = RulerProfile.trade_policy_for(nation)
	FamilyTree.record_current_title(state, nation_id)
	nation.prince_person_ids.clear()
	ensure_generation(state, nation_id)
	return true

static func enfeoff_candidate(state: GameState, nation_id: int) -> int:
	ensure_generation(state, nation_id)
	var nation := state.nations[nation_id]
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	var parent := int(members[nation.ruler_person_id].parent_id)
	var brothers: Array[int] = []
	for id in members:
		if int(id) != nation.ruler_person_id and members[id].has("archetype") and int(members[id].parent_id) == parent and eligible(members[id]) and not _busy(state, nation_id, int(id)):
			brothers.append(int(id))
	brothers.sort_custom(func(a: int, b: int) -> bool:
		var oa := int(members[a].get("birth_order", a))
		var ob := int(members[b].get("birth_order", b))
		return oa < ob if oa != ob else a < b)
	if not brothers.is_empty():
		return brothers[0]
	for id in nation.prince_person_ids:
		if id != nation.crown_prince_person_id and eligible(members[id]) and not _busy(state, nation_id, id):
			return id
	return _create_person(state, nation_id, parent, members.size())

static func _busy(state: GameState, nation_id: int, person_id: int) -> bool:
	var tree_id := state.nations[nation_id].family_tree_id
	for nation in state.nations:
		if nation.family_tree_id != tree_id:
			continue
		# 共享族谱不代表可以分封另一国家的君主或当代皇子。
		if nation.id != nation_id and nation.alive and (
			person_id == nation.ruler_person_id
			or person_id == nation.crown_prince_person_id
			or nation.prince_person_ids.has(person_id)
		):
			return true
		var conflict: SuccessionConflict = state.succession_conflicts.get(nation.id)
		if conflict != null and person_id in [conflict.challenger_person_id, conflict.crown_person_id]:
			return true
	return false

static func military_index(state: GameState) -> Dictionary:
	var result := {}
	for army in state.armies:
		if army.size <= 0:
			continue
		var owner := state.financial_nation_of(army.owner_nation)
		if not result.has(owner):
			result[owner] = {}
		result[owner][army.political_person_id] = int(result[owner].get(army.political_person_id, 0)) + army.size
	return result

static func report(state: GameState, nation_id: int, troops: Dictionary = {}) -> Dictionary:
	var nation := state.nations[nation_id]
	var princes: Array[Dictionary] = []
	var total := 0
	for size in troops.values():
		total += int(size)
	for id in nation.prince_person_ids:
		var member := person(state, nation_id, id)
		princes.append({"id": id, "name": member.get("name", ""), "archetype": member.get("archetype", RulerProfile.BALANCED),
			"traits": (member.get("traits", []) as Array).duplicate(), "alive": member.get("alive", true), "enfeoffed": int(member.get("enfeoffed_nation_id", -1)) >= 0,
			"crown": id == nation.crown_prince_person_id, "troops": int(troops.get(id, 0)), "share": float(troops.get(id, 0)) / maxi(total, 1)})
	var conflict: SuccessionConflict = state.succession_conflicts.get(nation_id)
	var status := "本代竞争结束" if nation.succession_competition_closed else "未发动争夺"
	if conflict != null:
		status = "继承权战争" if conflict.launched() else "秘密集结"
		if conflict.succession_delayed:
			status += "（继位延期）"
	var result := ""
	for index in range(state.succession_events.size() - 1, -1, -1):
		var event := state.succession_events[index]
		if int(event.nation_id) == nation_id and event.event == "finish":
			result = {SuccessionConflict.Outcome.CROWN_CHANGED: "改立太子", SuccessionConflict.Outcome.SUPPRESSED: "起事被镇压", SuccessionConflict.Outcome.ADMINISTRATIVE: "外部干扰，争夺结束"}.get(int(event.details.outcome), "")
			break
	return {"princes": princes, "central": int(troops.get(-1, 0)), "total": total, "status": status, "result": result,
		"qualification": conflict.qualification.duplicate(true) if conflict != null else {}}

static func display_lines(report_data: Dictionary) -> Array[String]:
	var lines: Array[String] = ["%s    中央直属 %d人" % [report_data.status, report_data.central]]
	var qualification: Dictionary = report_data.get("qualification", {})
	if not qualification.is_empty():
		lines.append("起事门槛 %d人（R=%d，V=%d）    已到场 %d人" % [qualification.requirement, qualification.R, qualification.V, qualification.get("arrived", 0)])
	if not str(report_data.get("result", "")).is_empty():
		lines.append("最近争夺：" + str(report_data.result))
	for prince in report_data.princes:
		var traits := PackedStringArray()
		for trait_id in prince.traits:
			traits.append(RulerProfile.trait_name(str(trait_id)))
		var profile_text := RulerProfile.archetype_name(int(prince.archetype)) + (" / " + "、".join(traits) if not traits.is_empty() else "")
		var status := "太子" if prince.crown else "皇子"
		if not prince.alive:
			status = "已故"
		elif prince.enfeoffed:
			status = "已分封"
		lines.append("%s %s · %s    掌军 %d人（%.1f%%）" % [status, prince.name, profile_text, prince.troops, float(prince.share) * 100.0])
	return lines
