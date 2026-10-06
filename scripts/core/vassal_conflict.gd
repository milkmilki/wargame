class_name VassalConflict
extends RefCounted
## One scoped political war for a single-tier suzerainty system.

static func for_nation(state: GameState, nation: int) -> Dictionary:
	for record in state.vassal_conflicts.values():
		if bool(record.get("active", false)) and (record.central.has(nation) or record.rebels.has(nation)): return record
	return {}

static func for_pair(state: GameState, a: int, b: int) -> Dictionary:
	var record := for_nation(state, a)
	if record.is_empty(): return {}
	if (record.central.has(a) and record.rebels.has(b)) or (record.rebels.has(a) and record.central.has(b)): return record
	return {}

static func leader(record: Dictionary, member: int) -> int:
	return int(record.central_leader) if record.central.has(member) else int(record.rebel_leader)

static func plan(state: GameState, subject: int) -> Dictionary:
	var rejected := {"mode": "reject", "reason": "invalid_or_busy", "subject_id": subject}
	if subject < 0 or subject >= state.nations.size() or not state.nations[subject].alive or not state.is_vassal(subject) or state.is_in_civil_war(subject): return rejected
	var root := state.overlord_of(subject)
	if root < 0 or root >= state.nations.size() or not state.nations[root].alive or not for_nation(state, root).is_empty() or not for_nation(state, subject).is_empty(): return rejected
	for member in [root, subject]:
		var capital := state.nations[int(member)].capital_city_id
		if capital < 0 or capital >= state.cities.size() or state.cities[capital].owner_nation != int(member): return rejected
	# Single-tier v1. Reject unsupported graphs rather than silently omit members.
	if state.is_vassal(root): return rejected
	var participants: Array[int] = [root]
	for member in state.subjects_of(root):
		if not state.subjects_of(member).is_empty() or state.is_in_civil_war(member): return rejected
		if state.nations[member].alive: participants.append(member)
	if state.land_cities_of(root).is_empty() or state.land_cities_of(subject).is_empty(): return rejected
	var result := {"mode": "independence", "reason": "geographic_isolation", "subject_id": subject, "central_leader": root,
		"rebel_leader": subject, "participants": participants, "central": [root], "rebels": [subject], "loyalty": {},
		"ownership_revision": state.ownership_revision, "diplomacy_revision": state.diplomacy_revision, "road_network_revision": state.road_network_revision}
	# Before allegiance, ordinary lawful access remains available, except the two
	# prospective opponents cannot borrow each other's territory.
	if not MilitaryReachability.contact(state, [root], [subject], [root, subject]) and not MilitaryReachability.contact(state, [subject], [root], [root, subject]):
		return result
	var central: Array[int] = [root]
	var rebels: Array[int] = [subject]
	for member in participants:
		if member == root or member == subject: continue
		var loyalty := RebellionSystem.vassal_loyalty(state, member)
		result.loyalty[member] = loyalty
		if loyalty <= RebellionSystem.LOYALTY_REBEL: rebels.append(member)
		else: central.append(member)
	for member in rebels:
		var capital := state.nations[int(member)].capital_city_id
		if capital < 0 or capital >= state.cities.size() or state.cities[capital].owner_nation != int(member): return rejected
	if not MilitaryReachability.contact(state, central, rebels, participants) and not MilitaryReachability.contact(state, rebels, central, participants):
		result.loyalty = {}
		return result
	result.mode = "war"
	result.reason = "faction_civil_war"
	result.central = central
	result.rebels = rebels
	return result

static func start(state: GameState, subject: int, multiplier: int = 1) -> bool:
	var proposed := plan(state, subject)
	state.last_vassal_conflict_result = proposed.duplicate(true)
	if proposed.mode == "reject": return false
	var root := int(proposed.central_leader)
	var graph := state.suzerainty.duplicate(true)
	var separating: Array = [subject] if proposed.mode == "independence" else proposed.rebels
	var shares := {}
	var stock := state._food_pool_stock(root)
	var total := state._food_pool_food_output(root)
	var capitals := {}
	for member in separating:
		var capital := state.nations[int(member)].capital_city_id
		if capital < 0 or capital >= state.cities.size(): return false
		capitals[int(member)] = capital
		shares[int(member)] = state._proportional_share(stock, state._food_pool_food_output(int(member)), total)
		if proposed.mode == "independence": graph.erase(int(member))
		else:
			graph[int(member)].civil_war = true
			graph[int(member)].last_centralization_day = state.day
	var relations: Array[Dictionary] = []
	if proposed.mode == "independence":
		for other in proposed.participants:
			if int(other) != subject: relations.append({"nation_a": subject, "nation_b": int(other), "relation": GameState.DiplomaticRelation.NEUTRAL, "truce_days": GameState.DEFAULT_TRUCE_DAYS})
	else:
		for i in range(proposed.participants.size()):
			for j in range(i + 1, proposed.participants.size()):
				var a := int(proposed.participants[i])
				var b := int(proposed.participants[j])
				var same: bool = proposed.central.has(a) == proposed.central.has(b)
				relations.append({"nation_a": a, "nation_b": b, "relation": GameState.DiplomaticRelation.ALLIED if same else GameState.DiplomaticRelation.WAR, "truce_days": 0})
	var war_id := state.next_war_id
	var result := state.apply_territory_transaction([], capitals, int(proposed.ownership_revision), graph, relations)
	if not result.ok:
		state.last_vassal_conflict_result = {"mode": "reject", "reason": result.get("error", "transaction_failed"), "subject_id": subject}
		return false
	# Shares are measured against one old stock, never successively rounded pools.
	for member in separating:
		var withdrawn := state._withdraw_food_from_warehouses(state.nations[root], int(shares[int(member)]))
		state.cities[int(capitals[int(member)])].food_storage += withdrawn
		state.nations[int(member)].last_rebellion_day = state.day
	state.nations[root].last_rebellion_day = state.day
	state.suzerainty_low_cohesion_since_day.erase(root)
	if proposed.mode == "war":
		var record := {"war_id": war_id, "central_leader": root, "rebel_leader": subject, "central": proposed.central.duplicate(), "rebels": proposed.rebels.duplicate(), "loyalty": proposed.loyalty.duplicate(true), "started_day": state.day, "active": true, "outcome": ""}
		state.vassal_conflicts[war_id] = record
		for a in record.central:
			for b in record.rebels:
				state.war_relation_ids[state._diplomacy_key(int(a), int(b))] = war_id
		ChronicleRules.begin_war(state, war_id, record.rebels, record.central)
		state._spawn_rebellion_uprising_armies(subject, multiplier)
		proposed.war_id = war_id
		var loyalties: Array[String] = []
		for member in record.loyalty: loyalties.append("%s %.1f" % [WorldNaming.nation_display_name(state, int(member)), float(record.loyalty[member])])
		_append_event(state, "vassal_faction_started", proposed, "%s起事，中央方：%s；反叛方：%s；藩王忠诚：%s" % [FamilyTree.title_for_nation(state, subject) + state.nations[subject].ruler_name, _names(state, record.central), _names(state, record.rebels), "、".join(loyalties)])
	else:
		WorldNaming.promote_vassal_to_sovereign(state, subject)
		FamilyTree.record_current_title(state, subject)
		for other in proposed.participants:
			if int(other) != subject: state.truce_until_day[state._diplomacy_key(subject, int(other))] = state.day + GameState.DEFAULT_TRUCE_DAYS
		_append_event(state, "vassal_isolated_independence", proposed, "%s因地理隔离脱离%s独立，未发动内战" % [WorldNaming.nation_display_name(state, subject), WorldNaming.nation_display_name(state, root)])
	state.last_vassal_conflict_result = proposed.duplicate(true)
	state.refresh_derived()
	return true

static func _names(state: GameState, members: Array) -> String:
	var names: Array[String] = []
	for member in members: names.append(WorldNaming.nation_display_name(state, int(member)))
	return "、".join(names)

static func _append_event(state: GameState, kind: String, details: Dictionary, text: String) -> void:
	var event := details.duplicate(true)
	event.kind = kind
	event.day = state.day
	event.year = int(state.day / 360) + 1
	event.text = "%d年 %s" % [int(state.day / 360) + 1, text]
	event.actor_ids = [int(details.get("central_leader", -1)), int(details.get("rebel_leader", -1))]
	state.chronicle_events.append(event)
	state.diplomatic_history.append(event.duplicate(true))

## Build annexation and faction peace in one transaction, then reuse normal
## annexation finalization for resources, armies, family titles and archives.
static func finish(state: GameState, record: Dictionary, winner: int, expected_revision: int = -1, captured_city: int = -1) -> bool:
	if record.is_empty() or not bool(record.get("active", false)): return false
	var loser := int(record.rebel_leader) if winner == int(record.central_leader) else int(record.central_leader)
	if winner not in [int(record.central_leader), int(record.rebel_leader)] or not state.nations[winner].alive or not state.nations[loser].alive: return false
	var graph := state.suzerainty.duplicate(true)
	var members: Array = record.central + record.rebels
	graph.erase(winner)
	graph.erase(loser)
	for member in members:
		if member == winner or member == loser or not state.nations[int(member)].alive: continue
		var edge: Dictionary = graph.get(int(member), {"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE, "created_day": state.day, "last_centralization_day": -1}).duplicate(true)
		edge.overlord_id = winner
		edge.civil_war = false
		graph[int(member)] = edge
	var operations: Array[Dictionary] = []
	for city in state.cities:
		var legal := state.recognized_owner_of(city.id)
		var internal := members.has(city.owner_nation) and members.has(legal) and (members.has(city.occupation_sponsor_nation) or city.occupation_sponsor_nation < 0)
		var controlled := city.owner_nation == loser
		var absorbed := legal == loser
		var sponsored := city.occupation_sponsor_nation == loser
		if not internal and not controlled and not absorbed and not sponsored: continue
		var controller := (winner if legal == loser else legal) if internal else (winner if controlled else city.owner_nation)
		var new_legal := winner if absorbed else legal
		operations.append({"city_id": city.id, "controller_id": controller, "legal_owner_id": new_legal,
			"sponsor_id": -1 if controller == new_legal else (winner if sponsored else city.occupation_sponsor_nation),
			"reset_political_target": absorbed or internal, "reason": "vassal_conflict_settled",
			"stock_policy": GameState.TerritoryStockDisposition.CAPTURE_SPOILS if city.id == captured_city else GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL})
	var relations: Array[Dictionary] = []
	for i in range(members.size()):
		for j in range(i + 1, members.size()):
			relations.append({"nation_a": int(members[i]), "nation_b": int(members[j]), "relation": GameState.DiplomaticRelation.ALLIED if members[i] != loser and members[j] != loser else GameState.DiplomaticRelation.NEUTRAL, "truce_days": 0})
	# Defer abort detection while the authoritative territory commit removes a leader.
	state.set_meta("vassal_conflict_settling", true)
	var result := state.apply_territory_transaction(operations, {}, expected_revision, graph, relations)
	if not result.ok:
		state.remove_meta("vassal_conflict_settling")
		return false
	FamilyTree.ensure_nation_lineage(state, loser)
	state._finalize_annexations(winner, {loser: true})
	state.remove_meta("vassal_conflict_settling")
	record.active = false
	record.outcome = "central_victory" if winner == int(record.central_leader) else "rebel_victory"
	record.ended_day = state.day
	record.winner = winner
	_release(state, record)
	WorldNaming.promote_vassal_to_sovereign(state, winner)
	FamilyTree.record_current_title(state, winner)
	state.suzerainty_low_cohesion_since_day.erase(winner)
	EmpireStatus.reconcile(state)
	_append_event(state, "vassal_faction_result", record, "%s内战获胜，吞并%s，其余存活藩王改隶，整场内战结束" % [WorldNaming.nation_display_name(state, winner), WorldNaming.nation_display_name(state, loser)])
	return true

static func _release(state: GameState, record: Dictionary) -> void:
	var war_id := int(record.war_id)
	for key in state.war_relation_ids.keys():
		if int(state.war_relation_ids[key]) == war_id:
			state.war_relation_ids.erase(key)
			state.war_objectives.erase(key)
	state.release_war_pool(war_id)
	state.sync_campaign_pairs(state.coalition_campaign_components())
	state._reconcile_battles_after_annexation()
	state.diplomacy_revision += 1
	state.refresh_derived()

static func reconcile(state: GameState) -> void:
	if state.has_meta("vassal_conflict_settling"): return
	for record in state.vassal_conflicts.values():
		if not bool(record.get("active", false)): continue
		if state.nations[int(record.central_leader)].alive and state.nations[int(record.rebel_leader)].alive:
			for side in ["central", "rebels"]:
				for member in record[side].duplicate():
					if state.nations[int(member)].alive: continue
					for other in record.central + record.rebels:
						if int(other) != int(member) and state.war_id_between(int(member), int(other)) == int(record.war_id):
							state.set_diplomatic_relation(int(member), int(other), GameState.DiplomaticRelation.NEUTRAL)
					record[side].erase(member)
					state.release_nation_war_pool(int(member), int(record.war_id))
			continue
		var graph := state.suzerainty.duplicate(true)
		var members: Array = record.central + record.rebels
		for member in members:
			if graph.has(int(member)): graph[int(member)].civil_war = false
		var relations: Array[Dictionary] = []
		for a in record.central:
			for b in record.rebels:
				var same := state.suzerainty_root(int(a)) == state.suzerainty_root(int(b))
				relations.append({"nation_a": int(a), "nation_b": int(b), "relation": GameState.DiplomaticRelation.ALLIED if same else GameState.DiplomaticRelation.NEUTRAL, "truce_days": GameState.DEFAULT_TRUCE_DAYS})
		var result := state.apply_territory_transaction([], {}, -1, graph, relations)
		if not result.ok: continue
		record.active = false
		record.outcome = "external_leader_loss"
		record.ended_day = state.day
		_release(state, record)
		_append_event(state, "vassal_faction_aborted", record, "内战首领被第三方消灭，注销内部战争，保留外部事务的领土归属")

static func records_validation_error(records: Variant, count: int, alive: Callable, relation: Callable, war_id_for: Callable, army_wars: Array, front_wars: Array) -> String:
	if not records is Dictionary: return "Invalid vassal conflict table"
	var assigned := {}
	for key in records:
		var record: Variant = records[key]
		if typeof(key) != TYPE_INT or not record is Dictionary: return "Invalid vassal conflict record"
		if int(record.get("war_id", -1)) != int(key) or int(key) < 0: return "Invalid vassal conflict war ID"
		for side in ["central", "rebels"]:
			if not record.get(side) is Array or record[side].is_empty(): return "Invalid vassal conflict side"
		var a := int(record.get("central_leader", -1))
		var b := int(record.get("rebel_leader", -1))
		if a == b or not record.central.has(a) or not record.rebels.has(b): return "Invalid vassal conflict leaders"
		var seen := {}
		for member in record.central + record.rebels:
			if typeof(member) != TYPE_INT or int(member) < 0 or int(member) >= count or seen.has(member): return "Overlapping or invalid vassal conflict members"
			seen[member] = true
			if bool(record.get("active", false)):
				if assigned.has(member): return "Nation participates in multiple vassal conflicts"
				assigned[member] = true
		if not bool(record.get("active", false)):
			if army_wars.has(int(key)) or front_wars.has(int(key)): return "Ended vassal conflict retains military binding"
			for x in record.central:
				for y in record.rebels:
					if int(war_id_for.call(int(x), int(y))) == int(key): return "Ended vassal conflict retains war relation"
			continue
		if not bool(alive.call(a)) or not bool(alive.call(b)): return "Active vassal conflict leader is dead"
		for x in record.central:
			for y in record.rebels:
				if not bool(alive.call(int(x))) or not bool(alive.call(int(y))): continue
				if int(relation.call(int(x), int(y))) != GameState.DiplomaticRelation.WAR or int(war_id_for.call(int(x), int(y))) != int(key): return "Vassal faction hostility and war ID disagree"
		for side in [record.central, record.rebels]:
			for x in side:
				for y in side:
					if x != y and bool(alive.call(int(x))) and bool(alive.call(int(y))) and int(relation.call(int(x), int(y))) != GameState.DiplomaticRelation.ALLIED: return "Vassal allies lack faction access"
	return ""

static func validation_error(state: GameState) -> String:
	var army_wars: Array = []
	var front_wars: Array = []
	for army in state.armies: army_wars.append(army.campaign_war_id)
	for front in state.campaign_fronts.values(): front_wars.append(front.war_id)
	var error := records_validation_error(state.vassal_conflicts, state.nations.size(), func(id: int): return state.nations[id].alive, state.relation_between, state.war_id_between, army_wars, front_wars)
	if not error.is_empty(): return error
	for record in state.vassal_conflicts.values():
		if not bool(record.get("active", false)): continue
		for member in record.central + record.rebels:
			if int(member) == int(record.central_leader) or not state.nations[int(member)].alive: continue
			if state.overlord_of(int(member)) != int(record.central_leader) or state.is_in_civil_war(int(member)) != record.rebels.has(member): return "Vassal faction and suzerainty disagree"
	return ""
