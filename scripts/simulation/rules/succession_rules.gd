class_name SuccessionRules
extends RefCounted
const NO_PROGRESS_LIMIT: int = 180

static func batch_context(state: GameState) -> Dictionary:
	var owners := {}
	for army in state.armies:
		if army.size <= 0 or army.is_city_garrison: continue
		if not owners.has(army.owner_nation): owners[army.owner_nation] = []
		owners[army.owner_nation].append(army)
	return {"owners": owners}

static func proposal(state: GameState, nation_id: int, person_id: int, _committed: Array[int] = [], context: Dictionary = {}, _fixed_camp: int = -1) -> Dictionary:
	var nation := state.nations[nation_id]
	if nation.succession_identity or not nation.alive or nation.succession_competition_closed or not state.wars_of(nation_id).is_empty() or state.is_in_civil_war(nation_id): return {}
	if not PrincePolitics.eligible_for_nation(PrincePolitics.person(state, nation_id, nation.crown_prince_person_id), nation_id): return {}
	if person_id == nation.crown_prince_person_id or not nation.prince_person_ids.has(person_id) or not PrincePolitics.eligible_for_nation(PrincePolitics.person(state, nation_id, person_id), nation_id): return {}
	if context.is_empty(): context = batch_context(state)
	var C := 0
	var V := 0
	var attackers: Array[int] = []
	var defenders: Array[int] = []
	for army: Army in context.owners.get(nation_id, []):
		if army.political_person_id == person_id:
			C += army.size
			attackers.append(army.id)
		elif army.political_person_id == nation.crown_prince_person_id:
			V += army.size
			defenders.append(army.id)
	var requirement := ceili(V * RulerProfile.campaign_requirement_multiplier(PrincePolitics.profile(state, nation_id, person_id)))
	if C <= 0 or C < requirement: return {}
	return {"army_ids": attackers, "crown_army_ids": defenders, "troops": C, "V": V, "R": 0, "requirement": requirement}

static func begin_preparation(state: GameState, nation_id: int, person_id: int, _info: Dictionary = {}) -> bool:
	# Revalidate even caller-provided proposals: no stale monthly eligibility.
	if state.succession_conflicts.has(nation_id): return false
	var info := proposal(state, nation_id, person_id)
	if info.is_empty(): return false
	var nation := state.nations[nation_id]
	var conflict := SuccessionConflict.new()
	conflict.nation_id = nation_id
	conflict.challenger_person_id = person_id
	conflict.crown_person_id = nation.crown_prince_person_id
	conflict.ruler_person_id = nation.ruler_person_id
	conflict.ruler_revision = nation.ruler_revision
	conflict.started_day = state.day
	conflict.last_progress_day = state.day
	conflict.qualification = info.duplicate(true)
	conflict.army_ids.assign(info.army_ids)
	conflict.crown_army_ids.assign(info.crown_army_ids)
	conflict.battle = Battle.new()
	conflict.battle.id = state.next_internal_battle_id
	state.next_internal_battle_id += 1
	var seed := RulerProfile.stable_hash(state.world_seed, nation_id, "internal_succession", nation.ruler_revision)
	conflict.battle.ensure_opening_dice(seed, true)
	for army in state.armies:
		var side := 1 if conflict.army_ids.has(army.id) else (2 if conflict.crown_army_ids.has(army.id) else 0)
		if side == 0: continue
		var copy := CombatLog._army_from_snapshot(CombatLog._side_snapshot([army] as Array[Army])[0])
		var profile := PrincePolitics.profile(state, nation_id, person_id if side == 1 else conflict.crown_person_id)
		copy.ruler_attack_multiplier = RulerProfile.attack_multiplier(profile)
		copy.ruler_defense_multiplier = RulerProfile.defense_multiplier(profile)
		copy.ruler_morale_multiplier = RulerProfile.morale_multiplier(profile)
		copy.campaign_war_id = -1
		copy.campaign_front_id = -1
		copy.state = Army.State.FIGHTING
		(conflict.battle.side_a if side == 1 else conflict.battle.side_b).append(copy)
	state.succession_conflicts[nation_id] = conflict
	record(state, conflict, "launch", conflict.display_report().merged(info))
	return true

static func advance(state: GameState, conflict: SuccessionConflict) -> void:
	if conflict.pending_outcome != SuccessionConflict.Outcome.NONE: return
	var nation := state.nations[conflict.nation_id]
	if not nation.alive or nation.ruler_person_id != conflict.ruler_person_id or nation.ruler_revision != conflict.ruler_revision or not PrincePolitics.eligible_for_nation(PrincePolitics.person(state, nation.id, conflict.challenger_person_id), nation.id) or not PrincePolitics.eligible_for_nation(PrincePolitics.person(state, nation.id, conflict.crown_person_id), nation.id):
		conflict.pending_outcome = SuccessionConflict.Outcome.ADMINISTRATIVE
		conflict.resolution_reason = "participant_or_generation_invalid"
		return
	if state.day <= conflict.started_day or conflict.last_advanced_day >= state.day: return
	conflict.last_advanced_day = state.day
	var before := CombatLog._side_snapshot(conflict.battle.side_a) + CombatLog._side_snapshot(conflict.battle.side_b)
	var enabled := Combat.battle_log_enabled
	var log_count := Combat.battle_log.size()
	Combat.battle_log_enabled = true
	Combat.resolve_round(conflict.battle, state.day)
	Combat.battle_log_enabled = enabled
	for index in range(log_count, Combat.battle_log.size()):
		var entry: Dictionary = Combat.battle_log[index].duplicate(true)
		entry["context"] = "internal_succession"
		entry["nation_id"] = nation.id
		conflict.round_logs.append(entry)
	# Private records never enter map combat streams, regardless of logging setting.
	Combat.battle_log.resize(log_count)
	var after := CombatLog._side_snapshot(conflict.battle.side_a) + CombatLog._side_snapshot(conflict.battle.side_b)
	if before != after: conflict.last_progress_day = state.day
	if conflict.battle.finished:
		conflict.pending_outcome = SuccessionConflict.Outcome.CROWN_CHANGED if conflict.battle.winner_side == 1 else SuccessionConflict.Outcome.SUPPRESSED
		conflict.resolution_reason = "field_victory" if conflict.battle.winner_side == 1 else "field_defeat"
	elif state.day - conflict.last_progress_day >= NO_PROGRESS_LIMIT: fail(state, conflict, "no_progress")

static func fail(state: GameState, conflict: SuccessionConflict, reason: String, battle_id: int = -1) -> bool:
	if conflict.pending_outcome != SuccessionConflict.Outcome.NONE: return false
	conflict.pending_outcome = SuccessionConflict.Outcome.SUPPRESSED
	conflict.resolution_reason = reason
	record(state, conflict, "result_locked", {"reason": reason, "battle_id": battle_id})
	return true

static func record(state: GameState, conflict: SuccessionConflict, event: String, details: Dictionary = {}) -> void:
	state.succession_events.append({"day": state.day, "nation_id": conflict.nation_id, "person_id": conflict.challenger_person_id, "crown_person_id": conflict.crown_person_id, "event": event, "details": details.duplicate(true)})

static func finish(state: GameState, conflict: SuccessionConflict) -> bool:
	if conflict.pending_outcome == SuccessionConflict.Outcome.NONE: return false
	var nation := state.nations[conflict.nation_id]
	var challenger := PrincePolitics.person(state, nation.id, conflict.challenger_person_id)
	var crown := PrincePolitics.person(state, nation.id, conflict.crown_person_id)
	var challenger_title := str(challenger.get("current_title", "无爵宗室"))
	var crown_previous_title := str(crown.get("virtual_title_name", ""))
	if conflict.pending_outcome == SuccessionConflict.Outcome.ADMINISTRATIVE:
		state.succession_conflicts.erase(nation.id)
		_record_result(state, conflict, challenger_title, str(challenger.get("name", "皇子")), str(crown.get("name", "太子")), crown_previous_title)
		return true
	if conflict.pending_outcome == SuccessionConflict.Outcome.CROWN_CHANGED:
		PrincePolitics.set_heir(state, nation.id, conflict.challenger_person_id)
		nation.succession_competition_closed = true
	elif conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED:
		challenger["alive"] = false
		PrincePolitics.centralize(state, nation.id, [conflict.challenger_person_id] as Array[int])
	# Cancellation carries no political winner and cannot close a new ruler's contest.
	if nation.succession_competition_closed: PrincePolitics.centralize(state, nation.id, nation.prince_person_ids)
	state.succession_conflicts.erase(nation.id)
	if conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED: RoyalTitles.settle_death(state, nation.id, conflict.challenger_person_id)
	RoyalTitles.grant_generation(state, nation.id)
	PrincePolitics.set_heir(state, nation.id, nation.crown_prince_person_id)
	state.family_revision += 1
	_record_result(state, conflict, challenger_title, str(challenger.get("name", "皇子")), str(crown.get("name", "太子")), crown_previous_title)
	return true

static func _record_result(state: GameState, conflict: SuccessionConflict, challenger_title: String, challenger_name: String, crown_name: String, crown_previous_title: String) -> void:
	var opening := "%d年 %s%s兵变，" % [int(state.day / 360) + 1, challenger_title, challenger_name]
	var result_text := opening + "皇太子%s平之" % crown_name
	var former_crown := {}
	if conflict.pending_outcome == SuccessionConflict.Outcome.CROWN_CHANGED:
		var member := PrincePolitics.person(state, conflict.nation_id, conflict.crown_person_id)
		var rank := RoyalTitles.effective_rank(state, member)
		former_crown = {"person_id": conflict.crown_person_id, "name": crown_name,
			"status": "untitled", "title": "", "rank": rank}
		var disposition := "废太子%s未授爵" % crown_name
		var fief := int(member.get("enfeoffed_nation_id", -1))
		if not bool(member.get("alive", true)):
			former_crown.status = "dead"
			disposition = "废太子%s已故，未再授爵" % crown_name
		elif fief >= 0 and fief < state.nations.size() and state.nations[fief].alive:
			former_crown.status = "enfeoffed"
			former_crown.title = WorldNaming.nation_display_name(state, fief)
			disposition = "废太子%s仍领实封%s" % [crown_name, former_crown.title]
		elif rank > 0:
			former_crown.title = RoyalTitles.designation(state, member, rank)
			former_crown.status = "retained" if former_crown.title == crown_previous_title else "granted"
			disposition = "废太子%s%s%s" % [crown_name, "仍为" if former_crown.status == "retained" else "封为", former_crown.title]
		result_text = opening + "废皇太子%s，改立%s为皇太子；%s" % [crown_name, challenger_name, disposition]
	elif conflict.pending_outcome == SuccessionConflict.Outcome.ADMINISTRATIVE:
		result_text = opening + "因人物或君主代次变化而取消"
	elif conflict.resolution_reason == "no_progress":
		result_text = opening + "久无进展，事败"
	elif conflict.resolution_reason == "field_defeat":
		result_text = opening + "野战败于皇太子%s，事败" % crown_name
	record(state, conflict, "finish", {"outcome": conflict.pending_outcome, "delayed": conflict.succession_delayed,
		"reason": conflict.resolution_reason, "challenger_title": challenger_title, "former_crown": former_crown, "internal_battle": conflict.display_report(), "round_logs": conflict.round_logs})
	state.chronicle_events.append({"day": state.day, "year": int(state.day / 360) + 1, "kind": "succession",
		"actor_ids": [conflict.nation_id], "person_ids": [conflict.challenger_person_id, conflict.crown_person_id],
		"result": "success" if conflict.pending_outcome == SuccessionConflict.Outcome.CROWN_CHANGED else "failure",
		"challenger_title": challenger_title, "former_crown": former_crown, "text": result_text})
