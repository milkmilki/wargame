class_name SuccessionRules
extends RefCounted

const PREPARATION_LIMIT: int = 360
const NO_PROGRESS_LIMIT: int = 180

static func fail(state: GameState, conflict: SuccessionConflict, reason: String, battle_id: int = -1) -> bool:
	if conflict.pending_outcome != SuccessionConflict.Outcome.NONE: return false
	conflict.pending_outcome = SuccessionConflict.Outcome.SUPPRESSED
	conflict.resolution_reason = reason
	record(state, conflict, "result_locked", {"reason": reason, "battle_id": battle_id})
	return true

static func defense_requirement(state: GameState, conflict: SuccessionConflict) -> int:
	var challengers := 0
	for army in state.armies:
		if conflict.army_ids.has(army.id) and effective(army) and army.is_at_city_node(conflict.camp_city_id): challengers += army.size
	return ceili(challengers * RulerProfile.campaign_requirement_multiplier(PrincePolitics.profile(state, conflict.nation_id, conflict.crown_person_id)))

static func attack_requirement(state: GameState, conflict: SuccessionConflict) -> int:
	var defenders := 0
	for army in state.armies:
		if conflict.crown_army_ids.has(army.id) and effective(army): defenders += army.size
	var raw := state.campaign_siege_requirement(conflict.rebel_nation_id, conflict.capital_city_id)
	return ceili((raw + defenders) * RulerProfile.campaign_requirement_multiplier(PrincePolitics.profile(state, conflict.nation_id, conflict.challenger_person_id)))

static func observe_progress(state: GameState, conflict: SuccessionConflict) -> void:
	var positions := {}
	for army in state.armies:
		if conflict.side_for(army.id) == 0: continue
		positions[army.id] = [army.location_city, army.on_edge,
			army.move_from if army.on_edge else -1, army.move_to if army.on_edge else -1,
			army.move_progress if army.on_edge else 0.0]
	var battles := {}
	for battle in state.battles:
		if not battle.finished and conflict.contains_battle(battle): battles[battle.id] = battle.round_no
	var garrison := state.cities[conflict.capital_city_id].garrison_manpower
	if conflict.last_progress_day < 0 or positions != conflict.progress_positions or battles != conflict.progress_battles or garrison < conflict.progress_garrison:
		conflict.last_progress_day = state.day
	conflict.progress_positions = positions
	conflict.progress_battles = battles
	conflict.progress_garrison = garrison

static func batch_context(state: GameState) -> Dictionary:
	var owners := {}
	var stationed := {}
	for army in state.armies:
		if army.size <= 0:
			continue
		if not owners.has(army.owner_nation):
			owners[army.owner_nation] = [] as Array[Army]
		owners[army.owner_nation].append(army)
		var node := army.current_city_node()
		if node >= 0:
			if not stationed.has(node):
				stationed[node] = [] as Array[Army]
			stationed[node].append(army)
	return {"owners": owners, "stationed": stationed, "fields": {}}

static func effective(army: Army) -> bool:
	return army.size > 0 and not army.starving and army.combat_morale() > Combat.ARMY_ROUT_THRESHOLD and army.state not in [Army.State.RECOVERING, Army.State.RETREATING]

static func available(state: GameState, army: Army) -> bool:
	return effective(army) and army.state == Army.State.IDLE and not army.on_edge and army.battle_id < 0 and army.campaign_war_id < 0 and army.campaign_front_id < 0 and not state.nations[army.owner_nation].war_preparation_army_ids.has(army.id)

static func camp_valid(state: GameState, conflict: SuccessionConflict) -> bool:
	var camp := conflict.camp_city_id
	if camp < 0 or camp >= state.cities.size() or state.cities[camp].owner_nation != conflict.nation_id or not state.is_fu_city(camp) or state.administrative_center_of(camp) != conflict.capital_city_id or state.city_under_siege(camp):
		return false
	for army in state.armies:
		if army.size > 0 and army.is_at_city_node(camp) and not conflict.army_ids.has(army.id):
			return false
	return true

static func proposal(state: GameState, nation_id: int, person_id: int, committed: Array[int] = [], context: Dictionary = {}, fixed_camp: int = -1) -> Dictionary:
	var nation := state.nations[nation_id]
	var capital := nation.capital_city_id
	if nation.succession_identity or not nation.alive or nation.succession_competition_closed or capital < 0 or not state.is_zhou_city(capital) or state.cities[capital].owner_nation != nation_id or state.city_under_siege(capital) or not state.wars_of(nation_id).is_empty() or state.is_in_civil_war(nation_id):
		return {}
	if person_id == nation.crown_prince_person_id or not nation.prince_person_ids.has(person_id) or not PrincePolitics.eligible_for_nation(PrincePolitics.person(state, nation_id, person_id), nation_id):
		return {}
	var armies: Array[Army] = []
	var V := 0
	if context.is_empty():
		context = batch_context(state)
	for army: Army in context.owners.get(nation_id, []):
		var node := army.current_city_node()
		if army.political_person_id == nation.crown_prince_person_id and effective(army) and node >= 0 and state.administrative_center_of(node) == capital and available(state, army):
			V += army.size
		var eligible_commitment := committed.has(army.id) and army.state in [Army.State.IDLE, Army.State.MOVING] and army.battle_id < 0 and army.campaign_war_id < 0 and army.campaign_front_id < 0 and not nation.war_preparation_army_ids.has(army.id)
		if army.political_person_id == person_id and (available(state, army) if committed.is_empty() else eligible_commitment) and effective(army):
			armies.append(army)
	if armies.is_empty():
		return {}
	var best := {}
	var field_cache: Dictionary = context.fields
	for camp in state.administrative_members(capital):
		if fixed_camp >= 0 and camp != fixed_camp:
			continue
		if not state.is_fu_city(camp) or state.cities[camp].owner_nation != nation_id or state.city_under_siege(camp):
			continue
		var occupied := false
		for stationed: Army in context.stationed.get(camp, []):
			occupied = occupied or stationed.owner_nation != nation_id or stationed.political_person_id != person_id
		if occupied:
			continue
		# Only this Fu will defect. Preview the same territorial bonus as the siege.
		var fu_count := maxi(state.administrative_members(capital).size() - 1, 1)
		var R := ceili(maxi(state.cities[capital].garrison_manpower, 0) * (3.0 - 2.0 / fu_count))
		var requirement := ceili((R + V) * RulerProfile.campaign_requirement_multiplier(PrincePolitics.profile(state, nation_id, person_id)))
		var reachable: Array[int] = []
		var troops := 0
		for army in armies:
			var start := army.current_city_node()
			if start < 0:
				start = army.move_to if army.on_edge else army.location_city
			var key := Vector3i(nation_id, start, army.max_size)
			if not field_cache.has(key):
				field_cache[key] = Pathfinding.dijkstra_field(state, start, nation_id, false, true, -1, army.max_size)
			if float(field_cache[key].dist.get(camp, INF)) < INF:
				var camp_key := Vector3i(nation_id, camp, army.max_size)
				if not field_cache.has(camp_key):
					field_cache[camp_key] = Pathfinding.dijkstra_field(state, camp, nation_id, false, true, -1, army.max_size)
				if float(field_cache[camp_key].dist.get(capital, INF)) == INF:
					continue
				reachable.append(army.id)
				troops += army.size
		if troops >= requirement and not reachable.is_empty() and (best.is_empty() or troops > int(best.troops) or (troops == int(best.troops) and camp < int(best.camp))):
			best = {"camp": camp, "capital": capital, "army_ids": reachable, "troops": troops, "R": R, "V": V, "requirement": requirement}
	return best

static func begin_preparation(state: GameState, nation_id: int, person_id: int, info: Dictionary = {}) -> bool:
	if state.succession_conflicts.has(nation_id):
		return false
	if info.is_empty():
		info = proposal(state, nation_id, person_id)
	if info.is_empty():
		return false
	var conflict := SuccessionConflict.new()
	conflict.nation_id = nation_id
	conflict.challenger_person_id = person_id
	conflict.crown_person_id = state.nations[nation_id].crown_prince_person_id
	conflict.capital_city_id = int(info.capital)
	conflict.camp_city_id = int(info.camp)
	conflict.army_ids.assign(info.army_ids)
	conflict.started_day = state.day
	conflict.qualification = info.duplicate(true)
	state.succession_conflicts[nation_id] = conflict
	record(state, conflict, "prepare", info)
	return true

static func launch(state: GameState, conflict: SuccessionConflict) -> bool:
	if conflict.launched() or state.day - conflict.started_day >= PREPARATION_LIMIT:
		return false
	var info := proposal(state, conflict.nation_id, conflict.challenger_person_id, conflict.army_ids, {}, conflict.camp_city_id)
	if info.is_empty() or int(info.capital) != conflict.capital_city_id or not camp_valid(state, conflict):
		return false
	var arrived: Array[Army] = []
	var troops := 0
	for army in state.armies:
		if conflict.army_ids.has(army.id) and army.owner_nation == conflict.nation_id and army.political_person_id == conflict.challenger_person_id and available(state, army) and army.is_at_city_node(conflict.camp_city_id):
			arrived.append(army)
			troops += army.size
	if troops < int(info.requirement) or arrived.is_empty() or not bool(DiplomacyAI.resource_forecast(state, conflict.nation_id).food_feasible):
		conflict.qualification = info.duplicate(true)
		conflict.qualification["arrived"] = troops
		return false
	conflict.qualification = info.duplicate(true)
	conflict.qualification["arrived"] = troops
	var rebel := Nation.new()
	rebel.id = state.nations.size()
	rebel.succession_identity = true
	rebel.name = str(PrincePolitics.person(state, conflict.nation_id, conflict.challenger_person_id).name) + "军"
	rebel.short_name = rebel.name
	rebel.color = state.nations[conflict.nation_id].color.lightened(0.2)
	rebel.ruler_name = str(PrincePolitics.person(state, conflict.nation_id, conflict.challenger_person_id).name)
	rebel.family_tree_id = state.nations[conflict.nation_id].family_tree_id
	rebel.ruler_person_id = conflict.challenger_person_id
	var ruler := PrincePolitics.profile(state, conflict.nation_id, conflict.challenger_person_id)
	rebel.ruler_archetype = ruler.ruler_archetype
	rebel.ruler_traits.assign(ruler.ruler_traits)
	state.nations.append(rebel)
	conflict.rebel_nation_id = rebel.id
	# One controller-only transaction: no capital, legal title, treasury or manpower transfer.
	var result := state.transfer_city_control(conflict.camp_city_id, rebel.id, -1, GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL, "succession_camp")
	if not bool(result.get("ok", false)):
		state.nations.pop_back()
		conflict.rebel_nation_id = -1
		return false
	conflict.war_id = state.next_war_id
	state.next_war_id += 1
	state.war_relation_ids[state._diplomacy_key(rebel.id, conflict.nation_id)] = conflict.war_id
	for army in state.armies:
		if conflict.army_ids.has(army.id) and not arrived.has(army):
			army.path.clear()
			army.ai_target_city = -1
			army.ai_action = ActionCandidate.Kind.HOLD
	conflict.army_ids.clear()
	state.nations[conflict.nation_id].battle_groups = state.nations[conflict.nation_id].battle_groups.filter(func(group: BattleGroup) -> bool:
		for army in arrived:
			if group.id == army.battle_group_id:
				return false
		return true)
	for army in arrived:
		conflict.army_ids.append(army.id)
		state.transfer_army_ownership(army, rebel.id)
		state.assign_main_army_to_independent_command(army)
	for army in state.armies:
		var node := army.current_city_node()
		if army.owner_nation == conflict.nation_id and army.political_person_id == conflict.crown_person_id and available(state, army) and node >= 0 and state.administrative_center_of(node) == conflict.capital_city_id:
			conflict.crown_army_ids.append(army.id)
	var offense := state.create_campaign_front(conflict.war_id, [rebel.id] as Array[int], rebel.id, CoalitionCampaignFront.Mode.OFFENSE, conflict.capital_city_id)
	offense.camp_city_id = conflict.camp_city_id
	offense.staging_city_id = conflict.camp_city_id
	conflict.offense_front_id = offense.front_id
	var defense := state.create_campaign_front(conflict.war_id, [conflict.nation_id] as Array[int], conflict.nation_id, CoalitionCampaignFront.Mode.DEFENSE, conflict.capital_city_id)
	defense.staging_city_id = conflict.capital_city_id
	conflict.defense_front_id = defense.front_id
	for army in state.armies:
		var side := conflict.side_for(army.id)
		if side == 0:
			continue
		var front := offense if side == 1 else defense
		front.army_assignments[army.id] = front.staging_city_id
		army.campaign_front_id = front.front_id
		army.campaign_war_id = conflict.war_id
	state.diplomacy_revision += 1
	state.refresh_derived()
	observe_progress(state, conflict)
	record(state, conflict, "launch", {"troops": troops, "R": info.R, "V": info.V})
	return true

static func record(state: GameState, conflict: SuccessionConflict, event: String, details: Dictionary = {}) -> void:
	state.succession_events.append({"day": state.day, "nation_id": conflict.nation_id, "person_id": conflict.challenger_person_id, "event": event, "details": details.duplicate(true)})

static func finish(state: GameState, conflict: SuccessionConflict) -> bool:
	if conflict.pending_outcome == SuccessionConflict.Outcome.NONE:
		return false
	for battle in state.battles:
		if battle.finished:
			continue
		if conflict.pending_outcome == SuccessionConflict.Outcome.ADMINISTRATIVE:
			continue
		for army in battle.side_a + battle.side_b:
			if conflict.side_for(army.id) != 0:
				return false
	var nation := state.nations[conflict.nation_id]
	var challenger_name := str(PrincePolitics.person(state, nation.id, conflict.challenger_person_id).get("name", "皇子"))
	var crown_name := str(PrincePolitics.person(state, nation.id, conflict.crown_person_id).get("name", "太子"))
	var receiver := nation.id
	if not nation.alive:
		receiver = state.cities[conflict.capital_city_id].owner_nation
		if receiver < 0 or receiver >= state.nations.size() or receiver == conflict.rebel_nation_id:
			receiver = nation.id
	if conflict.pending_outcome == SuccessionConflict.Outcome.CROWN_CHANGED:
		nation.crown_prince_person_id = conflict.challenger_person_id
		nation.succession_competition_closed = true
	elif conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED:
		PrincePolitics.person(state, nation.id, conflict.challenger_person_id)["alive"] = false
		PrincePolitics.centralize(state, nation.id, [conflict.challenger_person_id] as Array[int])
	else:
		nation.succession_competition_closed = true
	for army in state.armies:
		if army.owner_nation == conflict.rebel_nation_id:
			state.transfer_army_ownership(army, receiver)
			if army.size > 0:
				state.assign_main_army_to_independent_command(army)
		if conflict.side_for(army.id) != 0:
			if army.campaign_war_id == conflict.war_id:
				army.campaign_war_id = -1
			if army.campaign_front_id in [conflict.offense_front_id, conflict.defense_front_id]:
				army.campaign_front_id = -1
			army.ai_target_city = -1
			army.ai_action = ActionCandidate.Kind.HOLD
			# The current edge remains real; only unstarted route legs are cancelled.
			if army.state not in [Army.State.RETREATING, Army.State.FIGHTING]:
				army.path.clear()
			if conflict.pending_outcome != SuccessionConflict.Outcome.SUPPRESSED or conflict.army_ids.has(army.id):
				army.political_person_id = -1
	if nation.succession_competition_closed:
		PrincePolitics.centralize(state, nation.id, nation.prince_person_ids)
	if conflict.rebel_nation_id >= 0:
		if state.cities[conflict.camp_city_id].owner_nation == conflict.rebel_nation_id:
			state.transfer_city_control(conflict.camp_city_id, receiver, -1, GameState.TerritoryStockDisposition.RETURN_TO_OLD_POOL, "succession_restore")
		state.war_relation_ids.erase(state._diplomacy_key(conflict.rebel_nation_id, nation.id))
		state.nations[conflict.rebel_nation_id].alive = false
		state.nations[conflict.rebel_nation_id].capital_city_id = -1
		state.nations[conflict.rebel_nation_id].battle_groups.clear()
	state.release_campaign_front(conflict.offense_front_id)
	state.release_campaign_front(conflict.defense_front_id)
	record(state, conflict, "finish", {"outcome": conflict.pending_outcome, "delayed": conflict.succession_delayed, "reason": conflict.resolution_reason})
	var result_text := "%d年 皇子%s兵变，%s平之" % [int(state.day / 360) + 1, challenger_name, crown_name]
	if conflict.pending_outcome == SuccessionConflict.Outcome.CROWN_CHANGED:
		result_text = "%d年 皇子%s兵变，改立%s为太子" % [int(state.day / 360) + 1, challenger_name, challenger_name]
	elif conflict.resolution_reason == "no_progress":
		result_text = "%d年 皇子%s兵变，久无进展，事败" % [int(state.day / 360) + 1, challenger_name]
	elif conflict.resolution_reason == "field_defeat":
		result_text = "%d年 皇子%s兵变，野战败于%s，事败" % [int(state.day / 360) + 1, challenger_name, crown_name]
	state.chronicle_events.append({"day": state.day, "year": int(state.day / 360) + 1, "kind": "succession", "actor_ids": [conflict.nation_id], "person_ids": [conflict.challenger_person_id, conflict.crown_person_id], "result": "success" if conflict.pending_outcome == SuccessionConflict.Outcome.CROWN_CHANGED else "failure", "text": result_text})
	state.succession_conflicts.erase(nation.id)
	if conflict.pending_outcome == SuccessionConflict.Outcome.SUPPRESSED:
		RoyalTitles.settle_death(state, nation.id, conflict.challenger_person_id)
	RoyalTitles.grant_generation(state, nation.id)
	# 授爵先看到原储君旗号，避免历史授爵缓存跳过其爵位恢复。
	for person_id in nation.prince_person_ids:
		RoyalTitles.set_member(state, PrincePolitics.person(state, nation.id, person_id), "crown", person_id == nation.crown_prince_person_id)
	state.family_revision += 1
	state.diplomacy_revision += 1
	state.refresh_derived()
	return true
