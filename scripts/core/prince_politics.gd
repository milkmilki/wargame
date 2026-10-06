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
	return not member.is_empty() and bool(member.get("alive", true)) and not bool(member.get("title_disabled", false)) and int(member.get("enfeoffed_nation_id", -1)) < 0

static func eligible_for_nation(member: Dictionary, nation_id: int) -> bool:
	var payer := int(member.get("title_payer_id", -1))
	return eligible(member) and (payer < 0 or payer == nation_id)

static func ensure_generation(state: GameState, nation_id: int) -> void:
	var nation := state.nations[nation_id]
	if nation.succession_identity or not nation.alive:
		return
	FamilyTree.ensure_nation_lineage(state, nation_id)
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	if not nation.prince_person_ids.is_empty():
		RoyalTitles.set_member(state, members[nation.ruler_person_id], "children_initialized", true)
		return
	for id in initialize_children(state, nation_id, nation.ruler_person_id):
		if eligible_for_nation(members[id], nation_id) and not _busy(state, nation_id, id):
			nation.prince_person_ids.append(id)
	nation.crown_prince_person_id = nation.prince_person_ids[0] if not nation.prince_person_ids.is_empty() else -1
	nation.succession_competition_closed = false
	for id in nation.prince_person_ids:
		members[id]["crown"] = id == nation.crown_prince_person_id
	RoyalTitles.grant_generation(state, nation_id)
	state.family_revision += 1

static func initialize_children(state: GameState, nation_id: int, parent_id: int, family_salt: int = 0) -> Array[int]:
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	var parent: Dictionary = members[parent_id]
	var existing := RoyalTitles.children(members, parent_id)
	if bool(parent.get("children_initialized", false)):
		return existing
	RoyalTitles.set_member(state, parent, "children_initialized", true)
	# 老家谱的零子嗣标记同样是已经抽取的结果。
	if existing.is_empty() and not bool(parent.get("title_children_generated", false)):
		var count := int(RoyalTitles.CHILD_COUNTS[RulerProfile.stable_index(state.world_seed, nation_id, "royal/children", RoyalTitles.CHILD_COUNTS.size(), parent_id)])
		for order in range(count):
			existing.append(_create_person(state, nation_id, parent_id, order, family_salt))
	return existing

static func _create_person(state: GameState, nation_id: int, parent_id: int, order: int, family_salt: int = 0) -> int:
	var nation := state.nations[nation_id]
	var id := state.next_family_person_id
	state.next_family_person_id += 1
	var salt := nation.ruler_revision * 1009 + family_salt + order * 31 + 700001
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	if members.has(parent_id):
		var child_ids := RoyalTitles.children(members, parent_id)
		child_ids.append(id)
		members[parent_id]["child_ids"] = child_ids
	var name := WorldNaming.person_name_for(state.world_seed, nation_id, salt)
	members[id] = {"id": id, "name": name, "parent_id": parent_id, "child_ids": [], "children_initialized": false, "titles": [], "nation_ids": [],
		"archetype": RulerProfile.archetype_for(state.world_seed, nation_id, salt),
		"traits": RulerProfile.traits_for(state.world_seed, nation_id, salt),
		"birth_order": order, "alive": true, "enfeoffed_nation_id": -1}
	state.family_revision += 1
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
		if eligible_for_nation(person(state, nation.id, nation.crown_prince_person_id), nation.id):
			army.political_person_id = nation.crown_prince_person_id
		return
	var candidates: Array[int] = []
	var total := 0
	for id in nation.prince_person_ids:
		var member := person(state, nation.id, id)
		if eligible_for_nation(member, nation.id):
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

static func _peaceful_subject_of(state: GameState, subject: int, overlord: int) -> bool:
	var seen := {}
	while subject >= 0 and subject < state.nations.size() and state.suzerainty.has(subject):
		if seen.has(subject) or not state.nations[subject].alive or state.is_in_civil_war(subject):
			return false
		seen[subject] = true
		subject = int(state.suzerainty[subject].overlord_id)
		if subject == overlord: return true
	return false

static func _successor_candidate(state: GameState, nation_id: int, member: Dictionary, crown: bool = false) -> bool:
	if member.is_empty() or not bool(member.get("alive", true)) or bool(member.get("title_disabled", false)) or bool(member.get("synthetic_ancestor", false)) or not member.has("archetype"):
		return false
	var id := int(member.id)
	var nation := state.nations[nation_id]
	if id == nation.ruler_person_id: return false
	for conflict in state.succession_conflicts.values():
		if id in [conflict.challenger_person_id, conflict.crown_person_id]: return false
	var office := int(member.get("office_nation_id", -1))
	var fief := int(member.get("enfeoffed_nation_id", -1))
	if office >= 0 or fief >= 0:
		return office == fief and fief >= 0 and fief < state.nations.size() and state.nations[fief].ruler_person_id == id and state.nations[fief].family_tree_id == nation.family_tree_id and _peaceful_subject_of(state, fief, nation_id) and not state.succession_conflicts.has(fief)
	if not eligible_for_nation(member, nation_id) or _busy(state, nation_id, id): return false
	return crown or not nation.royal_titles_initialized or RoyalTitles.effective_rank(state, member) > 0

static func _birth_path(members: Dictionary, person_id: int, ancestor: int) -> Array[int]:
	var path: Array[int] = []
	var seen := {}
	while members.has(person_id) and person_id != ancestor and not seen.has(person_id):
		seen[person_id] = true
		path.push_front(int(members[person_id].get("birth_order", person_id)))
		person_id = int(members[person_id].get("parent_id", -1))
	return path

static func _path_less(first: Array[int], second: Array[int]) -> bool:
	for index in range(mini(first.size(), second.size())):
		if first[index] != second[index]: return first[index] < second[index]
	return first.size() < second.size()

## 查询只读；亲生子嗣列表和储君字段不承担旁支候选的存储。
static func select_successor(state: GameState, nation_id: int) -> Dictionary:
	var remote := {"person_id": -1, "source": "remote", "annex_nation_id": -1}
	var nation := state.nations[nation_id]
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).get("members", {})
	var crown: Dictionary = members.get(nation.crown_prince_person_id, {})
	if nation.prince_person_ids.has(nation.crown_prince_person_id) and int(crown.get("parent_id", -1)) == nation.ruler_person_id and _successor_candidate(state, nation_id, crown, true):
		return {"person_id": int(crown.id), "source": "crown", "annex_nation_id": int(crown.get("enfeoffed_nation_id", -1))}
	var links := {}
	for id in members:
		var parent := int(members[id].get("parent_id", -1))
		if not links.has(parent): links[parent] = []
		links[parent].append(int(id))
	var descendants := {}
	var frontier: Array[int] = [nation.ruler_person_id]
	var generation := 0
	while not frontier.is_empty():
		var next: Array[int] = []
		for id in frontier:
			for child in links.get(id, []):
				if child == nation.ruler_person_id or descendants.has(child): continue
				descendants[child] = generation + 1
				next.append(int(child))
		frontier = next
		generation += 1
	var direct: Array[int] = []
	for id in descendants:
		if _successor_candidate(state, nation_id, members[id]): direct.append(int(id))
	direct.sort_custom(func(a: int, b: int) -> bool:
		if descendants[a] != descendants[b]: return descendants[a] < descendants[b]
		var first := _birth_path(members, a, nation.ruler_person_id)
		var second := _birth_path(members, b, nation.ruler_person_id)
		return _path_less(first, second) if first != second else a < b)
	if not direct.is_empty():
		var heir: Dictionary = members[direct[0]]
		return {"person_id": int(heir.id), "source": "direct", "annex_nation_id": int(heir.get("enfeoffed_nation_id", -1))}
	var distance := {nation.ruler_person_id: 0}
	frontier = [nation.ruler_person_id]
	while not frontier.is_empty():
		var next: Array[int] = []
		for id in frontier:
			if not members.has(id): continue
			var neighbors: Array = (links.get(id, []) as Array).duplicate()
			neighbors.append(int(members[id].get("parent_id", -1)))
			for neighbor in neighbors:
				if members.has(neighbor) and not distance.has(neighbor):
					distance[neighbor] = int(distance[id]) + 1
					next.append(int(neighbor))
		frontier = next
	var collateral: Array[int] = []
	for id in members:
		if not descendants.has(id) and distance.has(id) and _successor_candidate(state, nation_id, members[id]): collateral.append(int(id))
	collateral.sort_custom(func(a: int, b: int) -> bool:
		if distance[a] != distance[b]: return distance[a] < distance[b]
		var first := maxi(int(members[a].get("title_rank", 0)), int(members[a].get("restorable_title_rank", 0)))
		var second := maxi(int(members[b].get("title_rank", 0)), int(members[b].get("restorable_title_rank", 0)))
		if first != second: return first > second
		return RoyalTitles._birth_less(members, a, b))
	if collateral.is_empty(): return remote
	var heir: Dictionary = members[collateral[0]]
	return {"person_id": int(heir.id), "source": "collateral", "annex_nation_id": int(heir.get("enfeoffed_nation_id", -1))}

static func accede(state: GameState, nation_id: int) -> bool:
	var nation := state.nations[nation_id]
	if not nation.alive or nation.succession_identity:
		return false
	var conflict: SuccessionConflict = state.succession_conflicts.get(nation_id)
	if conflict != null and conflict.launched(): return false
	var previous := person(state, nation_id, nation.ruler_person_id)
	if previous.is_empty(): return false
	var choice := select_successor(state, nation_id)
	var source := str(choice.source)
	var old_id := nation.ruler_person_id
	var was_fief := int(previous.get("enfeoffed_nation_id", -1)) == nation_id
	var subject := int(choice.annex_nation_id)
	# 兼并的领土事务先提交；中途不晋帝、授爵或生育。
	state.set_meta("ruler_accession_in_progress", true)
	if subject >= 0 and not state.annex_nation(nation_id, subject, state.ownership_revision):
		state.remove_meta("ruler_accession_in_progress")
		return false
	var incoming := int(choice.person_id)
	if incoming < 0: incoming = _create_remote_successor(state, nation_id)
	var member := person(state, nation_id, incoming)
	var protected: Array[int] = [incoming]
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	for child in RoyalTitles.children(members, incoming):
		if bool(members[child].get("alive", true)): protected.append(child)
	var centralize_ids: Array[int] = nation.prince_person_ids.duplicate()
	centralize_ids.append_array(protected)
	centralize_ids.append(old_id)
	centralize(state, nation_id, centralize_ids)
	previous["alive"] = false
	previous["office_nation_id"] = -1
	member["crown"] = false
	member["title_rank"] = 0
	member["restorable_title_rank"] = int(previous.get("restorable_title_rank", 0)) if was_fief else 0
	member["enfeoffed_nation_id"] = -1
	if was_fief:
		member["enfeoffed_nation_id"] = nation_id
		member["title_branch_id"] = int(previous.get("title_branch_id", previous.get("id", nation.ruler_person_id)))
	member["title_disabled"] = false
	member["accession_source"] = source
	nation.ruler_person_id = incoming
	nation.ruler_name = str(member.name)
	nation.ruler_archetype = int(member.archetype)
	nation.ruler_traits.assign(member.traits)
	nation.ruler_revision += 1
	nation.ruler_started_day = state.day
	nation.trade_policy = RulerProfile.trade_policy_for(nation)
	FamilyTree.record_current_title(state, nation_id)
	RoyalTitles.advance_generation(state, nation_id, incoming, protected)
	nation.prince_person_ids.clear()
	nation.crown_prince_person_id = -1
	nation.succession_competition_closed = false
	state.family_revision += 1
	ensure_generation(state, nation_id)
	state.remove_meta("ruler_accession_in_progress")
	EmpireStatus.reconcile(state)
	var text := "%d年 %s%s继位" % [int(state.day / 360) + 1, "远支" if source == "remote" else ("宗室" if source == "collateral" else ""), member.name]
	if subject >= 0: text += "，原藩并入本国"
	state.chronicle_events.append({"day": state.day, "year": int(state.day / 360) + 1, "kind": "ruler_succession", "actor_ids": [nation_id], "person_ids": [old_id, incoming], "source": source, "annex_nation_id": subject, "text": text})
	return true

static func _create_remote_successor(state: GameState, nation_id: int) -> int:
	var tree := FamilyTree.tree_for_nation(state, nation_id)
	var members: Dictionary = tree.members
	var current := state.nations[nation_id].ruler_person_id
	var depth := 0
	var seen := {}
	while members.has(current) and int(members[current].get("parent_id", -1)) >= 0 and not seen.has(current):
		seen[current] = true
		current = int(members[current].parent_id)
		depth += 1
	var parent := int(tree.root_person_id)
	for generation in range(maxi(depth - 1, 0)):
		var id := _create_person(state, nation_id, parent, RoyalTitles.children(members, parent).size(), parent * 7919)
		members[id].merge({"name": "未载名", "alive": false, "children_initialized": true, "synthetic_ancestor": true}, true)
		parent = id
	var incoming := _create_person(state, nation_id, parent, RoyalTitles.children(members, parent).size(), parent * 7919)
	members[incoming]["remote_branch"] = true
	return incoming

static func enfeoff_candidate(state: GameState, nation_id: int, initialize: bool = true) -> int:
	if initialize: ensure_generation(state, nation_id)
	var nation := state.nations[nation_id]
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).get("members", {})
	if not members.has(nation.ruler_person_id): return -1
	var parent := int(members[nation.ruler_person_id].parent_id)
	var brothers: Array[int] = []
	for id in members:
		if int(id) != nation.ruler_person_id and members[id].has("archetype") and int(members[id].parent_id) == parent and eligible_for_nation(members[id], nation_id) and not _busy(state, nation_id, int(id)):
			brothers.append(int(id))
	brothers.sort_custom(func(a: int, b: int) -> bool:
		var oa := int(members[a].get("birth_order", a))
		var ob := int(members[b].get("birth_order", b))
		return oa < ob if oa != ob else a < b)
	if not brothers.is_empty():
		return brothers[0]
	for id in nation.prince_person_ids:
		if id != nation.crown_prince_person_id and eligible_for_nation(members[id], nation_id) and not _busy(state, nation_id, id):
			return id
	# 没有现成人选就不分封；不能借分封入口补造已固定生育结果的兄弟。
	return -1

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
			"title": FamilyTree.display_title(member, id, int(FamilyTree.tree_for_nation(state, nation_id).get("root_person_id", -1))),
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
		"has_crown": eligible_for_nation(person(state, nation_id, nation.crown_prince_person_id), nation_id),
		"qualification": conflict.qualification.duplicate(true) if conflict != null else {}}

static func display_lines(report_data: Dictionary) -> Array[String]:
	var lines: Array[String] = ["%s    中央直属 %d人" % [report_data.status, report_data.central]]
	if not bool(report_data.get("has_crown", true)): lines.append("无储君 · 到期按宗室继承规则择嗣")
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
		var status := "储君" if prince.crown else str(prince.get("title", "无爵"))
		if not prince.alive:
			status += "（已故）"
		lines.append("%s %s · %s    掌军 %d人（%.1f%%）" % [status, prince.name, profile_text, prince.troops, float(prince.share) * 100.0])
	return lines
