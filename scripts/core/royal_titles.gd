class_name RoyalTitles
extends RefCounted
## 爵位只在授予国家有效；人物所属与历史爵号分别保存。
const COMMON := 0
const DUKE := 1
const COMMANDERY := 2
const PRINCE := 3
const CHILD_COUNTS := [0, 2, 3, 4, 5]
const NAMES := ["无爵", "国公", "郡王", "一字王"]
const PRINCELY_STATES := ["晋", "秦", "齐", "楚", "吴", "越", "宋"]

## 封号只依赖世界种子、人物和等级，不推进模拟随机源，也不检查重名。
static func name_for(world_seed: int, person_id: int, rank: int, origin: int = -1) -> String:
	if rank == COMMON:
		return NAMES[COMMON]
	if rank == PRINCE:
		return PRINCELY_STATES[WorldNaming.stable_index(world_seed, person_id, "royal/%d/prince" % origin, PRINCELY_STATES.size())] + "王"
	var title := ""
	for slot in range(2 if rank == COMMANDERY else 1):
		title += WorldNaming.GEOGRAPHIC_STEMS[WorldNaming.stable_index(world_seed, person_id, "royal/%d/%d/%d" % [origin, rank, slot], WorldNaming.GEOGRAPHIC_STEMS.size())]
	return title + ("王" if rank == COMMANDERY else "国公")

static func designation(state: GameState, member: Dictionary, rank: int) -> String:
	if rank == COMMON:
		return NAMES[COMMON]
	var title := str(member.get("virtual_title_name", ""))
	if not matches_rank(title, rank) and int(member.get("title_rank", 0)) == rank:
		title = str(member.get("current_title", ""))
	return title if matches_rank(title, rank) else name_for(state.world_seed, int(member.id), rank)

static func matches_rank(title: String, rank: int) -> bool:
	if rank == PRINCE:
		return title.length() == 2 and title.ends_with("王") and title.substr(0, 1) in PRINCELY_STATES
	return title.length() == 3 and title.ends_with("王" if rank == COMMANDERY else "国公")

static func children(members: Dictionary, parent_id: int) -> Array[int]:
	var result: Array[int] = []
	if members.has(parent_id) and members[parent_id].has("child_ids"):
		result.assign(members[parent_id].child_ids)
		result.sort_custom(func(a: int, b: int) -> bool: return _birth_less(members, a, b))
		return result
	for id in members:
		if int(members[id].get("parent_id", -1)) == parent_id:
			result.append(int(id))
	result.sort_custom(func(a: int, b: int) -> bool: return _birth_less(members, a, b))
	return result

static func _birth_less(members: Dictionary, a: int, b: int) -> bool:
	var first := int(members[a].get("birth_order", a))
	var second := int(members[b].get("birth_order", b))
	return first < second if first != second else a < b

static func set_member(state: GameState, member: Dictionary, key: String, value: Variant) -> void:
	if member.get(key) != value:
		member[key] = value
		state.family_revision += 1

## 关闭当前爵号档案，不改变人物的生死、政治资格或血缘。
static func end_title(state: GameState, member: Dictionary, reason: String) -> void:
	var history: Array = member.get("title_history", [])
	if not history.is_empty() and int(history.back().get("end_day", -1)) < 0:
		history.back()["end_day"] = state.day
		history.back()["end_reason"] = reason
		state.family_revision += 1
	set_member(state, member, "title_rank", COMMON)
	set_member(state, member, "title_origin_nation_id", -1)
	set_member(state, member, "virtual_title_name", "")
	set_member(state, member, "current_title", NAMES[COMMON])

static func _start_title(state: GameState, member: Dictionary, rank: int, origin: int, title: String) -> void:
	var history: Array = member.get("title_history", [])
	history.append({"origin_nation_id": origin, "origin_nation_name": WorldNaming.nation_display_name(state, origin),
		"title": title, "rank": rank, "start_day": state.day, "end_day": -1, "end_reason": ""})
	member["title_history"] = history
	state.family_revision += 1

static func _grant(state: GameState, member: Dictionary, rank: int, payer: int, branch: int, adult: bool, inherited_title: String = "") -> void:
	var previous_rank := int(member.get("title_rank", 0))
	var same_origin := int(member.get("title_origin_nation_id", -1)) == payer
	var title := inherited_title if rank > 0 and not inherited_title.is_empty() else (designation(state, member, rank) if same_origin else name_for(state.world_seed, int(member.id), rank, payer))
	var changed := previous_rank != rank or not same_origin or str(member.get("virtual_title_name", "")) != title
	if changed and previous_rank > 0:
		end_title(state, member, "retitled")
	set_member(state, member, "title_managed", true)
	set_member(state, member, "title_rank", rank)
	set_member(state, member, "title_payer_id", payer)
	# 零级待继承子嗣同样保留本国家支来源，但不生成爵号档案或俸禄。
	set_member(state, member, "title_origin_nation_id", payer)
	set_member(state, member, "title_branch_id", branch)
	set_member(state, member, "title_adult", adult)
	set_member(state, member, "title_disabled", false)
	if rank > 0:
		set_member(state, member, "virtual_title_name", title)
		if changed: _start_title(state, member, rank, payer, title)
	set_member(state, member, "current_title", title)
	if rank > 0:
		var titles: Array = member.get("titles", [])
		if not titles.has(title):
			titles.append(title)
			member["titles"] = titles
			state.family_revision += 1
	# 加授/继承升等时，只提升尚未成家的低爵孩子，保留成年家支的独立身份。
	if rank > previous_rank and bool(member.get("title_children_generated", false)):
		var members: Dictionary = FamilyTree.tree_for_nation(state, payer).get("members", {})
		for id in children(members, int(member.id)):
			var child: Dictionary = members[id]
			if bool(child.get("title_adult", false)) or not bool(child.get("alive", true)) or int(child.get("enfeoffed_nation_id", -1)) >= 0 or int(child.get("title_payer_id", -1)) != payer or int(child.get("title_origin_nation_id", -1)) not in [-1, payer]:
				continue
			if int(child.get("title_rank", 0)) < rank - 1:
				_grant(state, child, rank - 1, payer, branch, false)

static func reconcile(state: GameState) -> void:
	if state == null or state.has_meta("historical_prince_reports") or state.has_meta("ruler_accession_in_progress"):
		return
	if int(state.get_meta("royal_reconcile_revision", -1)) == state.family_revision:
		return
	for nation in state.nations:
		if not nation.alive or nation.succession_identity:
			continue
		if nation.state_level == EmpireStatus.EMPIRE and not nation.royal_titles_initialized:
			nation.royal_titles_initialized = true
			state.family_revision += 1
		grant_generation(state, nation.id)
	# Reproduction happens only in the adult cohort, once per actual family.
	for tree in state.family_trees.values():
		var members: Dictionary = tree.members
		for id in members.keys():
			var member: Dictionary = members[id]
			if effective_rank(state, member) > 0 and bool(member.get("title_adult", false)):
				_generate_children(state, member)
	state.set_meta("royal_reconcile_revision", state.family_revision)

static func grant_generation(state: GameState, nation_id: int) -> void:
	var nation := state.nations[nation_id]
	if not nation.royal_titles_initialized or nation.succession_identity:
		return
	var rank := PRINCE if nation.ruler_person_id == nation.empire_founder_person_id else COMMANDERY
	for id in nation.prince_person_ids:
		var member := PrincePolitics.person(state, nation_id, id)
		if not PrincePolitics.eligible_for_nation(member, nation_id) or PrincePolitics._busy(state, nation_id, id):
			continue
		if int(member.get("title_grant_ruler_id", -1)) == nation.ruler_person_id and int(member.get("title_grant_rank", -1)) == rank:
			continue
		var branch := int(member.get("title_branch_id", id)) if int(member.get("title_origin_nation_id", -1)) == nation_id else id
		_grant(state, member, rank, nation_id, branch, true)
		set_member(state, member, "title_grant_ruler_id", nation.ruler_person_id)
		set_member(state, member, "title_grant_rank", rank)

static func _generate_children(state: GameState, member: Dictionary) -> void:
	if bool(member.get("title_children_generated", false)):
		set_member(state, member, "children_initialized", true)
		return
	var payer := int(member.title_payer_id)
	var members: Dictionary = FamilyTree.tree_for_nation(state, payer).members
	var existing := PrincePolitics.initialize_children(state, payer, int(member.id), int(member.id) * 7919)
	set_member(state, member, "title_children_generated", true)
	for id in existing:
		var child: Dictionary = members[id]
		if not bool(child.get("alive", true)) or int(child.get("enfeoffed_nation_id", -1)) >= 0 or PrincePolitics._busy(state, payer, id):
			continue
		if int(child.get("title_origin_nation_id", -1)) == payer or bool(child.get("title_adult", false)) or int(child.get("title_payer_id", payer)) != payer:
			continue
		_grant(state, child, maxi(int(member.title_rank) - 1, 0), payer, int(member.title_branch_id), false)

static func effective_rank(state: GameState, member: Dictionary) -> int:
	var payer := int(member.get("title_payer_id", -1))
	if not bool(member.get("alive", true)) or bool(member.get("title_disabled", false)) or payer < 0 or payer >= state.nations.size() or not state.nations[payer].alive:
		return COMMON
	if int(member.get("enfeoffed_nation_id", -1)) >= 0 or int(member.get("title_origin_nation_id", -1)) != payer:
		return COMMON
	if not state.nations[payer].royal_titles_initialized:
		return COMMON
	var office := int(member.get("office_nation_id", -1))
	if office >= 0 and office < state.nations.size() and state.nations[office].alive:
		return COMMON
	return int(member.get("title_rank", COMMON))

static func report(state: GameState, nation_id: int) -> Dictionary:
	var reports := census(state)
	return reports.get(nation_id, {"counts": [0, 0, 0, 0], "basis_points": 0, "people": [[], [], [], []]})

static func census(state: GameState) -> Dictionary:
	var cached: Dictionary = state.get_meta("royal_census", {})
	if cached.get("revision", []) == [state.family_revision, state.ownership_revision]:
		return cached.reports
	var reports := {}
	for nation in state.nations:
		reports[nation.id] = {"counts": [0, 0, 0, 0], "basis_points": 0, "people": [[], [], [], []]}
	for tree in state.family_trees.values():
		for member in tree.members.values():
			var rank := effective_rank(state, member)
			if rank <= 0:
				continue
			var entry: Dictionary = reports[int(member.title_payer_id)]
			entry.counts[rank] += 1
			entry.basis_points += rank * 10
			entry.people[rank].append(int(member.id))
	state.set_meta("royal_census", {"revision": [state.family_revision, state.ownership_revision], "reports": reports})
	return reports

static func _candidate(state: GameState, nation_id: int, member: Dictionary, branch: int) -> bool:
	return bool(member.get("alive", true)) and bool(member.get("title_managed", false)) and not bool(member.get("title_disabled", false)) and int(member.get("title_payer_id", -1)) == nation_id and int(member.get("title_branch_id", -1)) == branch and int(member.get("enfeoffed_nation_id", -1)) < 0 and int(member.get("office_nation_id", -1)) < 0 and int(member.get("title_origin_nation_id", -1)) == nation_id and not PrincePolitics._busy(state, nation_id, int(member.id))

static func _nearest_collateral(members: Dictionary, links: Dictionary, deceased: int, pool: Dictionary) -> int:
	if pool.is_empty():
		return -1
	var frontier: Array[int] = [deceased]
	var visited := {deceased: true}
	while not frontier.is_empty():
		var eligible: Array[int] = []
		for id in frontier:
			if pool.has(id): eligible.append(id)
		if not eligible.is_empty():
			eligible.sort_custom(func(a: int, b: int) -> bool: return _birth_less(members, a, b))
			return eligible[0]
		var next: Array[int] = []
		for id in frontier:
			var neighbors: Array = links.get(id, []).duplicate()
			neighbors.append(int(members[id].get("parent_id", -1)))
			for neighbor in neighbors:
				if members.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					next.append(int(neighbor))
		frontier = next
	return -1

static func _inherit(state: GameState, nation_id: int, deaths: Array[Dictionary]) -> void:
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	var claimed := {}
	var pools := {}
	var links := {}
	for id in members:
		var member: Dictionary = members[id]
		var parent := int(member.get("parent_id", -1))
		if not links.has(parent): links[parent] = []
		links[parent].append(int(id))
		var branch := int(member.get("title_branch_id", -1))
		if _candidate(state, nation_id, member, branch):
			if not pools.has(branch): pools[branch] = {}
			pools[branch][int(id)] = true
	for rank in [PRINCE, COMMANDERY, DUKE]:
		var unresolved: Array[Dictionary] = []
		for deceased in deaths:
			if int(deceased.rank) != rank:
				continue
			var heir := -1
			for id in children(members, int(deceased.id)):
				if not claimed.has(id) and (pools.get(int(deceased.branch), {}) as Dictionary).has(id):
					heir = id
					break
			if heir < 0:
				unresolved.append(deceased)
			else:
				claimed[heir] = true
				pools[int(deceased.branch)].erase(heir)
				_grant(state, members[heir], rank, nation_id, int(deceased.branch), bool(members[heir].get("title_adult", false)), str(deceased.get("title", designation(state, members[int(deceased.id)], rank))))
		for deceased in unresolved:
			var pool: Dictionary = pools.get(int(deceased.branch), {})
			var heir := _nearest_collateral(members, links, int(deceased.id), pool)
			if heir >= 0:
				claimed[heir] = true
				pool.erase(heir)
				_grant(state, members[heir], rank, nation_id, int(deceased.branch), bool(members[heir].get("title_adult", false)), str(deceased.get("title", designation(state, members[int(deceased.id)], rank))))


static func advance_generation(state: GameState, nation_id: int, incoming_ruler: int, protected_people: Array[int] = []) -> void:
	var nation := state.nations[nation_id]
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	var deaths: Array[Dictionary] = []
	var dead_ids: Array[int] = []
	# 异宗兼并仍保留原谱；失爵家支的生命周期随接收国换代。
	var domestic_members: Array[Dictionary] = []
	for tree in state.family_trees.values():
		for member in tree.members.values():
			if int(member.get("title_payer_id", -1)) == nation_id:
				domestic_members.append(member)
	for member in domestic_members:
		var id := int(member.id)
		if int(member.get("title_payer_id", -1)) != nation_id or not bool(member.get("title_managed", false)) or bool(member.get("title_disabled", false)) or not bool(member.get("alive", true)) or int(id) == incoming_ruler or protected_people.has(int(id)):
			continue
		if int(member.get("enfeoffed_nation_id", -1)) >= 0 or int(member.get("office_nation_id", -1)) >= 0 or PrincePolitics._busy(state, nation_id, int(id)):
			continue
		if bool(member.get("title_adult", false)):
			var rank := effective_rank(state, member)
			if rank > 0:
				deaths.append({"id": int(id), "rank": rank, "branch": int(member.title_branch_id), "title": designation(state, member, rank)})
			FamilyTree.record_death_title(state, member)
			end_title(state, member, "death")
			set_member(state, member, "alive", false)
			set_member(state, member, "title_settled", true)
			dead_ids.append(int(id))
		else:
			set_member(state, member, "title_adult", true)
	PrincePolitics.centralize(state, nation_id, dead_ids)
	_inherit(state, nation_id, deaths)
	nation.royal_generation += 1
	state.family_revision += 1

static func settle_death(state: GameState, nation_id: int, person_id: int) -> void:
	var member := PrincePolitics.person(state, nation_id, person_id)
	if bool(member.get("title_settled", false)) or not member.has("title_payer_id"):
		return
	set_member(state, member, "title_settled", true)
	var rank := int(member.get("title_rank", 0)) if int(member.get("title_origin_nation_id", -1)) == nation_id and int(member.get("title_payer_id", -1)) == nation_id else 0
	var title := designation(state, member, rank)
	FamilyTree.record_death_title(state, member)
	end_title(state, member, "death")
	if rank > 0:
		_inherit(state, nation_id, [{"id": person_id, "rank": rank, "branch": int(member.get("title_branch_id", person_id)), "title": title}])

static func enfeoff(state: GameState, old_nation: int, new_nation: int, person_id: int) -> void:
	var member := PrincePolitics.person(state, old_nation, person_id)
	transfer_branch(state, old_nation, new_nation, person_id)
	set_member(state, member, "title_adult", true)
	set_member(state, member, "crown", false)
	set_member(state, member, "enfeoffed_nation_id", new_nation)
	set_member(state, member, "office_nation_id", new_nation)

static func _move_member(state: GameState, member: Dictionary, nation_id: int, reason: String) -> void:
	if int(member.get("title_origin_nation_id", -1)) != nation_id:
		var rank := int(member.get("title_rank", 0))
		var origin := int(member.get("title_origin_nation_id", -1))
		var title := designation(state, member, rank)
		end_title(state, member, reason)
		if rank > 0:
			state.chronicle_events.append({"day": state.day, "year": int(state.day / 360) + 1, "kind": "title_ended",
				"actor_ids": [origin, nation_id], "person_ids": [int(member.id)], "reason": reason,
				"text": "%d年 %s%s因%s终止旧爵" % [int(state.day / 360) + 1, title, member.name, "分封建国" if reason == "enfeoffment" else "并入他国"]})
	set_member(state, member, "title_payer_id", nation_id)
	set_member(state, member, "title_managed", true)
	set_member(state, member, "title_branch_id", int(member.get("title_branch_id", member.id)))

static func transfer_branch(state: GameState, old_nation: int, new_nation: int, root_id: int) -> void:
	var members: Dictionary = FamilyTree.tree_for_nation(state, old_nation).members
	var pending: Array[int] = [root_id]
	var visited := {}
	while not pending.is_empty():
		var id: int = pending.pop_back()
		if visited.has(id): continue
		visited[id] = true
		var member: Dictionary = members[id]
		if id != root_id and (int(member.get("title_payer_id", old_nation)) != old_nation or PrincePolitics._busy(state, old_nation, id) or int(member.get("enfeoffed_nation_id", -1)) >= 0):
			continue
		_move_member(state, member, new_nation, "enfeoffment")
		pending.append_array(children(members, id))

static func annex(state: GameState, absorber: int, absorbed_ids: Dictionary) -> void:
	for absorbed in absorbed_ids:
		var former := state.nations[int(absorbed)]
		if former.absorbed_into_nation_id >= 0:
			continue
		former.absorbed_into_nation_id = absorber
		var affiliated: Array[Dictionary] = []
		# 之前兼并留下的异宗归档谱也可能属于本次败国，不能只看败国主谱。
		for tree in state.family_trees.values():
			for member in tree.members.values():
				if int(member.get("title_payer_id", -1)) == int(absorbed) or int(member.id) == former.ruler_person_id:
					affiliated.append(member)
		for member in affiliated:
			# 同谱跨国人物只按实际所属迁移，历史帝位不决定当前归属。
			if int(member.get("title_payer_id", -1)) != int(absorbed) and int(member.id) != former.ruler_person_id:
				continue
			if int(member.get("office_nation_id", -1)) == int(absorbed):
				set_member(state, member, "title_adult", true)
				set_member(state, member, "office_nation_id", -1)
				set_member(state, member, "enfeoffed_nation_id", -1)
			set_member(state, member, "crown", false)
			_move_member(state, member, absorber, "annexation")
			set_member(state, member, "current_title", NAMES[COMMON])
		state.family_revision += 1

static func summary(state: GameState, nation_id: int) -> String:
	var entry := report(state, nation_id)
	return "宗室：一字王 %d · 郡王 %d · 国公 %d    额外宫廷支出 %.1f%%" % [entry.counts[3], entry.counts[2], entry.counts[1], float(entry.basis_points) / 100.0]
