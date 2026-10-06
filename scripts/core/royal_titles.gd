class_name RoyalTitles
extends RefCounted
## 爵位以人物为真源；血缘、现职、待恢复资格和供养国家分别记录。
const COMMON := 0
const DUKE := 1
const COMMANDERY := 2
const PRINCE := 3
const CHILD_COUNTS := [0, 2, 3, 4, 5]
const NAMES := ["无爵", "国公", "郡王", "一字王"]

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

static func _grant(state: GameState, member: Dictionary, rank: int, payer: int, branch: int, adult: bool) -> void:
	var previous_rank := int(member.get("title_rank", 0))
	set_member(state, member, "title_managed", true)
	set_member(state, member, "title_rank", rank)
	set_member(state, member, "title_payer_id", payer)
	set_member(state, member, "title_branch_id", branch)
	set_member(state, member, "title_adult", adult)
	set_member(state, member, "title_disabled", false)
	set_member(state, member, "current_title", NAMES[rank])
	if rank > 0:
		var titles: Array = member.get("titles", [])
		if not titles.has(NAMES[rank]):
			titles.append(NAMES[rank])
			member["titles"] = titles
			state.family_revision += 1
	# 加授/继承升等时，只提升尚未成家的低爵孩子，保留成年家支的独立身份。
	if rank > previous_rank and bool(member.get("title_children_generated", false)):
		var members: Dictionary = FamilyTree.tree_for_nation(state, payer).get("members", {})
		for id in children(members, int(member.id)):
			var child: Dictionary = members[id]
			if bool(child.get("title_adult", false)) or not bool(child.get("alive", true)) or bool(child.get("crown", false)) or int(child.get("enfeoffed_nation_id", -1)) >= 0 or int(child.get("title_payer_id", -1)) != payer:
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
	if not nation.royal_titles_initialized:
		return
	var ruler := PrincePolitics.person(state, nation_id, nation.ruler_person_id)
	var is_fief := int(ruler.get("enfeoffed_nation_id", -1)) == nation_id
	if nation.state_level == EmpireStatus.EMPIRE and not state.is_vassal(nation_id):
		is_fief = false
	var rank := maxi(int(ruler.get("restorable_title_rank", 0)) - 1, 0) if is_fief else (
		PRINCE if nation.ruler_person_id == nation.empire_founder_person_id else COMMANDERY)
	for id in nation.prince_person_ids:
		var member := PrincePolitics.person(state, nation_id, id)
		if member.is_empty() or not bool(member.get("alive", true)):
			continue
		var default_branch := int(ruler.get("title_branch_id", nation.ruler_person_id)) if is_fief else id
		var branch := int(member.get("title_branch_id", default_branch))
		if id == nation.crown_prince_person_id:
			if int(member.get("enfeoffed_nation_id", -1)) >= 0:
				continue
			_grant(state, member, COMMON, nation_id, branch, false)
			set_member(state, member, "crown", true)
			continue
		if int(member.get("enfeoffed_nation_id", -1)) >= 0:
			# 太祖晋帝时补授已有实封儿子的待恢复资格，不支付双份俸禄。
			if nation.ruler_person_id == nation.empire_founder_person_id and int(member.get("parent_id", -1)) == nation.ruler_person_id and EmpireStatus.peaceful_root(state, int(member.enfeoffed_nation_id)) == EmpireStatus.peaceful_root(state, nation_id):
				set_member(state, member, "restorable_title_rank", PRINCE)
				var subject_id := int(member.enfeoffed_nation_id)
				if subject_id < state.nations.size() and state.nations[subject_id].alive and not state.nations[subject_id].royal_titles_initialized:
					state.nations[subject_id].royal_titles_initialized = true
					state.family_revision += 1
			continue
		if not PrincePolitics.eligible_for_nation(member, nation_id) or PrincePolitics._busy(state, nation_id, id):
			continue
		if int(member.get("title_grant_ruler_id", -1)) == nation.ruler_person_id and int(member.get("title_grant_rank", -1)) == rank and not bool(member.get("crown", false)):
			continue
		set_member(state, member, "crown", false)
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
		if bool(child.get("title_managed", false)):
			continue
		_grant(state, child, maxi(int(member.title_rank) - 1, 0), payer, int(member.title_branch_id), false)

static func effective_rank(state: GameState, member: Dictionary) -> int:
	var payer := int(member.get("title_payer_id", -1))
	if not bool(member.get("alive", true)) or bool(member.get("title_disabled", false)) or payer < 0 or payer >= state.nations.size() or not state.nations[payer].alive:
		return COMMON
	if int(member.get("enfeoffed_nation_id", -1)) >= 0 or bool(member.get("crown", false)):
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
	return bool(member.get("alive", true)) and bool(member.get("title_managed", false)) and not bool(member.get("title_disabled", false)) and int(member.get("title_payer_id", -1)) == nation_id and int(member.get("title_branch_id", -1)) == branch and int(member.get("enfeoffed_nation_id", -1)) < 0 and int(member.get("office_nation_id", -1)) < 0 and not bool(member.get("crown", false)) and not PrincePolitics._busy(state, nation_id, int(member.id))

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
				_grant(state, members[heir], rank, nation_id, int(deceased.branch), bool(members[heir].get("title_adult", false)))
		for deceased in unresolved:
			var pool: Dictionary = pools.get(int(deceased.branch), {})
			var heir := _nearest_collateral(members, links, int(deceased.id), pool)
			if heir >= 0:
				claimed[heir] = true
				pool.erase(heir)
				_grant(state, members[heir], rank, nation_id, int(deceased.branch), bool(members[heir].get("title_adult", false)))


static func advance_generation(state: GameState, nation_id: int, incoming_ruler: int, protected_people: Array[int] = []) -> void:
	var nation := state.nations[nation_id]
	if not nation.royal_titles_initialized:
		return
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	var deaths: Array[Dictionary] = []
	var dead_ids: Array[int] = []
	for id in members:
		var member: Dictionary = members[id]
		if int(member.get("title_payer_id", -1)) != nation_id or not bool(member.get("title_managed", false)) or bool(member.get("title_disabled", false)) or not bool(member.get("alive", true)) or int(id) == incoming_ruler or protected_people.has(int(id)):
			continue
		if int(member.get("enfeoffed_nation_id", -1)) >= 0 or int(member.get("office_nation_id", -1)) >= 0 or PrincePolitics._busy(state, nation_id, int(id)):
			continue
		if bool(member.get("title_adult", false)):
			deaths.append({"id": int(id), "rank": int(member.get("title_rank", 0)), "branch": int(member.title_branch_id)})
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
	_inherit(state, nation_id, [{"id": person_id, "rank": int(member.get("title_rank", 0)), "branch": int(member.get("title_branch_id", person_id))}])

static func enfeoff(state: GameState, old_nation: int, new_nation: int, person_id: int) -> void:
	var member := PrincePolitics.person(state, old_nation, person_id)
	var restored := int(member.get("title_rank", 0))
	set_member(state, member, "title_branch_id", int(member.get("title_branch_id", person_id)))
	set_member(state, member, "restorable_title_rank", restored)
	set_member(state, member, "title_rank", COMMON)
	set_member(state, member, "crown", false)
	set_member(state, member, "enfeoffed_nation_id", new_nation)
	set_member(state, member, "office_nation_id", new_nation)
	var subject := state.nations[new_nation]
	subject.royal_titles_initialized = state.nations[old_nation].royal_titles_initialized
	transfer_branch(state, old_nation, new_nation, person_id)

static func transfer_branch(state: GameState, old_nation: int, new_nation: int, root_id: int) -> void:
	var members: Dictionary = FamilyTree.tree_for_nation(state, old_nation).members
	var pending: Array[int] = [root_id]
	while not pending.is_empty():
		var id: int = pending.pop_back()
		var member: Dictionary = members[id]
		if id != root_id and (int(member.get("title_payer_id", old_nation)) != old_nation or PrincePolitics._busy(state, old_nation, id) or int(member.get("enfeoffed_nation_id", -1)) >= 0):
			continue
		if member.has("title_payer_id"):
			set_member(state, member, "title_payer_id", new_nation)
		pending.append_array(children(members, id))

static func annex(state: GameState, absorber: int, absorbed_ids: Dictionary) -> void:
	for absorbed in absorbed_ids:
		var former := state.nations[int(absorbed)]
		if former.absorbed_into_nation_id >= 0:
			continue
		former.absorbed_into_nation_id = absorber
		var same_tree := former.family_tree_id == state.nations[absorber].family_tree_id
		var members: Dictionary = FamilyTree.tree_for_nation(state, int(absorbed)).get("members", {})
		for member in members.values():
			if int(member.get("office_nation_id", -1)) == int(absorbed):
				set_member(state, member, "office_nation_id", -1)
				set_member(state, member, "enfeoffed_nation_id", -1)
			if int(member.get("title_payer_id", -1)) != int(absorbed) and int(member.id) != former.ruler_person_id:
				continue
			set_member(state, member, "crown", false)
			if same_tree and bool(member.get("alive", true)):
				if int(member.id) == former.ruler_person_id:
					_grant(state, member, int(member.get("restorable_title_rank", 0)), absorber, int(member.get("title_branch_id", member.id)), true)
				else:
					set_member(state, member, "title_payer_id", absorber)
					if int(member.id) == former.crown_prince_person_id:
						var parent: Dictionary = members.get(int(member.get("parent_id", -1)), {})
						_grant(state, member, maxi(int(parent.get("restorable_title_rank", 0)) - 1, 0), absorber, int(member.get("title_branch_id", member.id)), true)
				state.nations[absorber].royal_titles_initialized = state.nations[absorber].royal_titles_initialized or former.royal_titles_initialized
			else:
				set_member(state, member, "title_disabled", true)
				if int(member.get("title_rank", 0)) > 0:
					set_member(state, member, "title_rank", COMMON)
					set_member(state, member, "current_title", NAMES[COMMON])
		state.family_revision += 1

static func summary(state: GameState, nation_id: int) -> String:
	var entry := report(state, nation_id)
	return "宗室：一字王 %d · 郡王 %d · 国公 %d    额外宫廷支出 %.1f%%" % [entry.counts[3], entry.counts[2], entry.counts[1], float(entry.basis_points) / 100.0]
