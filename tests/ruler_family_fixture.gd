extends RefCounted
## Explicit test families for scenarios requiring real siblings or succession rivals.
## This helper never changes the natural birth distribution, seed, or world layout.

static func ensure_candidates(state: GameState, nation_id: int, min_count: int = 2) -> void:
	FamilyTree.ensure_nation_lineage(state, nation_id)
	var nation := state.nations[nation_id]
	var members: Dictionary = FamilyTree.tree_for_nation(state, nation_id).members
	var parent_id := nation.ruler_person_id
	var children := RoyalTitles.children(members, parent_id)
	var candidates: Array[int] = []
	for id in children:
		if PrincePolitics.eligible_for_nation(members[id], nation_id) and not PrincePolitics._busy(state, nation_id, id):
			candidates.append(id)
	while candidates.size() < min_count:
		var id := PrincePolitics._create_person(state, nation_id, parent_id, children.size())
		children.append(id)
		candidates.append(id)
	RoyalTitles.set_member(state, members[parent_id], "child_ids", children)
	RoyalTitles.set_member(state, members[parent_id], "children_initialized", true)
	nation.prince_person_ids.assign(children)
	if not candidates.has(nation.crown_prince_person_id):
		nation.crown_prince_person_id = candidates[0] if not candidates.is_empty() else -1
	for id in children:
		RoyalTitles.set_member(state, members[id], "crown", id == nation.crown_prince_person_id)
	RoyalTitles.grant_generation(state, nation_id)
