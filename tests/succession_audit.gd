extends RefCounted

static func inspect(state: GameState) -> Dictionary:
	var errors: Array[String] = []
	var army_ids := {}
	var distribution := {"central": 0, "crown": 0, "other_princes": 0}
	for army in state.armies:
		if army.size <= 0:
			continue
		army_ids[army.id] = army
		var owner := state.financial_nation_of(army.owner_nation)
		if army.political_person_id < 0:
			distribution.central += 1
		elif not PrincePolitics.eligible_for_nation(PrincePolitics.person(state, owner, army.political_person_id), owner):
			errors.append("invalid political patron army=%d" % army.id)
		elif army.political_person_id == state.nations[owner].crown_prince_person_id:
			distribution.crown += 1
		else:
			distribution.other_princes += 1
		if state.is_succession_identity(army.owner_nation) and not state.army_reserved_for_succession(army):
			errors.append("uncommitted temporary army=%d" % army.id)
	var incumbents := {}
	for nation in state.nations:
		if nation.succession_identity:
			if nation.treasury_gold != 0 or nation.manpower_pool != 0 or not nation.warehouse_city_ids.is_empty():
				errors.append("temporary resources nation=%d" % nation.id)
			if nation.alive and state.succession_conflict_for_identity(nation.id) == null:
				errors.append("orphan temporary identity=%d" % nation.id)
		elif nation.alive:
			if incumbents.has(nation.ruler_person_id): errors.append("duplicate active ruler=%d" % nation.ruler_person_id)
			incumbents[nation.ruler_person_id] = nation.id
			var ruler := PrincePolitics.person(state, nation.id, nation.ruler_person_id)
			if not bool(ruler.get("alive", true)) or not bool(ruler.get("children_initialized", false)):
				errors.append("invalid ruler lifecycle nation=%d" % nation.id)
			if nation.crown_prince_person_id >= 0 and not nation.prince_person_ids.has(nation.crown_prince_person_id):
				errors.append("invalid crown candidate nation=%d" % nation.id)
			var seen := {}
			for person_id in nation.prince_person_ids:
				var member := PrincePolitics.person(state, nation.id, person_id)
				if member.is_empty() or int(member.parent_id) != nation.ruler_person_id or seen.has(person_id):
					errors.append("invalid prince generation nation=%d" % nation.id)
				seen[person_id] = true
	for value in state.succession_conflicts.values():
		var conflict := value as SuccessionConflict
		if not conflict.launched():
			continue
		var committed := {}
		for id in conflict.army_ids + conflict.crown_army_ids:
			if committed.has(id):
				errors.append("duplicate participant=%d" % id)
			committed[id] = true
		for battle in state.battles:
			if battle.finished or not conflict.contains_battle(battle):
				continue
			for army in battle.side_a + battle.side_b:
				if not army.is_city_garrison and conflict.side_for(army.id) == 0:
					errors.append("neutral joined internal battle=%d" % army.id)
	var events := {}
	var delayed := 0
	for event in state.succession_events:
		events[event.event] = int(events.get(event.event, 0)) + 1
		if event.event == "finish":
			var outcome := "outcome_%d" % int(event.details.outcome)
			events[outcome] = int(events.get(outcome, 0)) + 1
			delayed += int(event.details.delayed)
	return {"errors": errors, "distribution": distribution, "events": events, "delayed": delayed, "active": state.succession_conflicts.size()}
