extends RefCounted
## 独立检查真源引用和财政人数，供长跑逐日使用。
static func inspect(state: GameState) -> Array[String]:
	var errors: Array[String] = []
	var expected := {}
	for nation in state.nations:
		expected[nation.id] = [0, 0, 0, 0]
		if nation.state_level == 1 and (nation.empire_recognized_day < 0 or PrincePolitics.person(state, nation.id, nation.empire_founder_person_id).is_empty()):
			errors.append("missing founder nation=%d" % nation.id)
	for tree in state.family_trees.values():
		for member in tree.members.values():
			var rank := int(member.get("title_rank", 0))
			if rank < 0 or rank > 3:
				errors.append("invalid rank person=%d" % int(member.id))
			if not member.get("title_managed", false): continue
			var payer := int(member.get("title_payer_id", -1))
			if payer < 0 or payer >= state.nations.size() or state.nations[payer].family_tree_id != int(tree.id) or not tree.members.has(int(member.get("title_branch_id", -1))):
				errors.append("invalid branch/payer person=%d" % int(member.id))
				continue
			if not bool(member.get("alive", true)) or bool(member.get("title_disabled", false)) or not state.nations[payer].alive: continue
			var office := int(member.get("office_nation_id", -1))
			var in_office: bool = office >= 0 and state.nations[office].alive
			if member.get("crown", false) or int(member.get("enfeoffed_nation_id", -1)) >= 0 or in_office:
				if rank > 0: errors.append("double title person=%d" % int(member.id))
				continue
			if rank > 0: expected[payer][rank] += 1
			if not bool(member.get("title_adult", false)) and not RoyalTitles.children(tree.members, int(member.id)).is_empty():
				errors.append("waiting family reproduced person=%d" % int(member.id))
	for nation in state.nations:
		var actual := RoyalTitles.report(state, nation.id)
		if actual.counts != expected[nation.id] or actual.basis_points != expected[nation.id][3] * 30 + expected[nation.id][2] * 20 + expected[nation.id][1] * 10:
			errors.append("stale census nation=%d" % nation.id)
	return errors
