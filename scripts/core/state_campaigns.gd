extends RefCounted
const Campaign = preload("res://scripts/model/state_campaign.gd")

static func prepare(state: GameState, actor: int, opponent: int, center: int) -> StateCampaign:
	if actor < 0 or opponent < 0 or actor >= state.nations.size() or opponent >= state.nations.size() or actor == opponent or not state.is_zhou_city(center) or not state.nations[actor].alive or not state.nations[opponent].alive: return null
	for value in state.state_campaigns.values().duplicate():
		var record: StateCampaign = value
		if record.lifecycle != Campaign.Lifecycle.PREPARING or record.initiator_nation_id != actor: continue
		if record.defender_nation_id == opponent and record.center_city_id == center: return record
		state.state_campaigns.erase(record.campaign_id)
	return new_record(state, actor, opponent, center)

static func new_record(state: GameState, actor: int, opponent: int, center: int) -> StateCampaign:
	var record := Campaign.new()
	record.campaign_id = state.next_state_campaign_id
	state.next_state_campaign_id += 1
	record.center_city_id = center
	record.initiator_nation_id = actor
	record.defender_nation_id = opponent
	record.attacker_members = [actor] as Array[int]
	record.defender_members = [opponent] as Array[int]
	record.started_day = state.day
	state.state_campaigns[record.campaign_id] = record
	return record

static func members_for(components: Array[Dictionary], war: int, members: Array[int]) -> Array[int]:
	for member in members:
		for component in components:
			if int(component.war_id) == war and (component.members as Array[int]).has(member):
				return (component.members as Array[int]).duplicate()
	return [] as Array[int]

static func activate(state: GameState, actor: int, opponent: int, center: int, war: int, components: Array[Dictionary]) -> StateCampaign:
	if war < 0 or not state.is_zhou_city(center) or not state.is_enemy(actor, opponent) or state.war_id_between(actor, opponent) != war: return null
	var attackers := members_for(components, war, [actor] as Array[int])
	var defenders := members_for(components, war, [opponent] as Array[int])
	if attackers.is_empty() or defenders.is_empty(): return null
	var record: StateCampaign = null
	for value in state.state_campaigns.values():
		var candidate: StateCampaign = value
		if candidate.center_city_id != center or candidate.lifecycle == Campaign.Lifecycle.ENDING: continue
		if (candidate.lifecycle == Campaign.Lifecycle.PREPARING and candidate.initiator_nation_id == actor and candidate.defender_nation_id == opponent) or (candidate.war_id == war and candidate.attacker_members == attackers and candidate.defender_members == defenders):
			record = candidate; break
	if record == null: record = new_record(state, actor, opponent, center)
	if record.lifecycle == Campaign.Lifecycle.PREPARING: record.defense_activation_pending = true
	record.lifecycle = Campaign.Lifecycle.ACTIVE
	record.war_id = war
	record.attacker_members = attackers
	record.defender_members = defenders
	var pair := state.find_campaign_pair(war, actor, opponent)
	record.pair_id = pair.pair_id if pair != null else -1
	ensure_defense(state, record)
	return record

static func attach(state: GameState, record: StateCampaign, front: CoalitionCampaignFront) -> void:
	if front == null: return
	var previous := state.campaign_front(record.offense_front_id if front.mode == CoalitionCampaignFront.Mode.OFFENSE else record.defense_front_id)
	if previous != null and previous != front: previous.state_campaign_ids.erase(record.campaign_id)
	if front.mode == CoalitionCampaignFront.Mode.OFFENSE: record.offense_front_id = front.front_id
	else: record.defense_front_id = front.front_id
	if not front.state_campaign_ids.has(record.campaign_id): front.state_campaign_ids.append(record.campaign_id)

static func ensure_defense(state: GameState, record: StateCampaign) -> CoalitionCampaignFront:
	if record.lifecycle != Campaign.Lifecycle.ACTIVE or record.defender_members.is_empty(): return null
	var owner := state.cities[record.center_city_id].owner_nation
	if not record.defender_members.has(owner): return null
	var cached := state.campaign_front(record.defense_front_id)
	if cached != null and not cached.retiring and cached.participant_nation_ids == record.defender_members: return cached
	var front := state.campaign_front_for(owner, record.center_city_id, CoalitionCampaignFront.Mode.DEFENSE, record.war_id)
	if front == null:
		front = state.create_campaign_front(record.war_id, record.defender_members, owner, CoalitionCampaignFront.Mode.DEFENSE, record.center_city_id)
		front.phase = CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE
	attach(state, record, front)
	return front

static func cancel_preparation(state: GameState, actor: int) -> void:
	for value in state.state_campaigns.values().duplicate():
		var record: StateCampaign = value
		if record.lifecycle == Campaign.Lifecycle.PREPARING and record.initiator_nation_id == actor: state.state_campaigns.erase(record.campaign_id)

static func for_nation(state: GameState, nation: int, war: int, include_hidden: bool) -> Array[StateCampaign]:
	var result: Array[StateCampaign] = []
	for value in state.state_campaigns.values():
		var record: StateCampaign = value
		if war >= 0 and record.war_id != war: continue
		if record.visible_to(nation) or (include_hidden and (record.attacker_members.has(nation) or record.defender_members.has(nation))): result.append(record)
	result.sort_custom(func(a: StateCampaign, b: StateCampaign): return a.campaign_id < b.campaign_id)
	return result

static func defense_centers(state: GameState, members: Array[int], war: int) -> Dictionary:
	var result := {}
	for value in state.state_campaigns.values():
		var record: StateCampaign = value
		if record.lifecycle == Campaign.Lifecycle.ACTIVE and not record.incidental and record.war_id == war and record.defender_members == members and members.has(state.cities[record.center_city_id].owner_nation): result[record.center_city_id] = true
	return result

static func detach_front(state: GameState, front: CoalitionCampaignFront) -> void:
	for id in front.state_campaign_ids:
		var record: StateCampaign = state.state_campaigns.get(id)
		if record == null: continue
		if record.offense_front_id == front.front_id: record.offense_front_id = -1
		if record.defense_front_id == front.front_id: record.defense_front_id = -1
	front.state_campaign_ids.clear()

static func defense_activation_keys(state: GameState) -> Dictionary:
	var result := {}
	for value in state.state_campaigns.values():
		var record: StateCampaign = value
		if record.lifecycle == Campaign.Lifecycle.ACTIVE and record.defense_activation_pending:
			result["%d:%s" % [record.war_id, str(record.defender_members)]] = true
	return result

static func complete_defense_activation(state: GameState, war: int, members: Array[int]) -> void:
	for value in state.state_campaigns.values():
		var record: StateCampaign = value
		if record.war_id == war and record.defender_members == members: record.defense_activation_pending = false

static func finish_planning(state: GameState, activity: Dictionary) -> void:
	var selected := {}
	for value in state.campaign_pairs.values():
		for slot in (value as CoalitionCampaignPair).battlefields:
			var id := int(slot.get("state_campaign_id", -1))
			if id >= 0: selected[id] = true
	for value in state.state_campaigns.values():
		var record: StateCampaign = value
		if record.lifecycle != Campaign.Lifecycle.ACTIVE or record.incidental or selected.has(record.campaign_id): continue
		# Independent physical threats may need defense without an offensive slot.
		if record.offense_front_id < 0 and bool(state.campaign_defense_context(record.defender_members[0], record.center_city_id, record.war_id, activity).active):
			record.incidental = true
			continue
		end(state, record.campaign_id, "目标变更或未取得战场名额")

static func end(state: GameState, id: int, reason: String) -> void:
	var record: StateCampaign = state.state_campaigns.get(id)
	if record == null or record.lifecycle == Campaign.Lifecycle.ENDING: return
	if record.lifecycle == Campaign.Lifecycle.PREPARING:
		state.state_campaigns.erase(id); return
	record.lifecycle = Campaign.Lifecycle.ENDING
	record.defense_activation_pending = false
	record.pair_id = -1
	record.ending_day = state.day
	record.end_reason = reason
	var exclusive := {}
	for front_id in [record.offense_front_id, record.defense_front_id]:
		var front := state.campaign_front(front_id)
		if front != null and not has_active_reference(state, front):
			exclusive[front_id] = true
			front.retiring = not defense_needed(state, front)
	for army in state.armies:
		if exclusive.has(army.campaign_front_id): record.ending_army_ids.append(army.id)
	record.ending_army_ids.sort()

static func defense_needed(state: GameState, front: CoalitionCampaignFront) -> bool:
	return front.mode == CoalitionCampaignFront.Mode.DEFENSE and front.participant_nation_ids.has(state.cities[front.center_city_id].owner_nation) and bool(state.campaign_defense_context(front.anchor_nation_id, front.center_city_id, front.war_id).active)

static func has_active_reference(state: GameState, front: CoalitionCampaignFront) -> bool:
	for id in front.state_campaign_ids:
		var record: StateCampaign = state.state_campaigns.get(id)
		if record != null and record.lifecycle == Campaign.Lifecycle.ACTIVE: return true
	return false

static func transfer_front(state: GameState, old: CoalitionCampaignFront, kept: CoalitionCampaignFront) -> void:
	for id in old.state_campaign_ids.duplicate():
		var record: StateCampaign = state.state_campaigns.get(id)
		if record != null: attach(state, record, kept)
	old.state_campaign_ids.clear()

static func supports_component(state: GameState, front: CoalitionCampaignFront, members: Array[int]) -> bool:
	if front.state_campaign_ids.is_empty(): return true
	for id in front.state_campaign_ids:
		var record: StateCampaign = state.state_campaigns.get(id)
		if record == null: continue
		var side := record.attacker_members if front.mode == CoalitionCampaignFront.Mode.OFFENSE else record.defender_members
		for member in members:
			if side.has(member): return true
	return false

static func siege_references(record: StateCampaign, battle: Battle) -> bool:
	var attacker := false; var defender := false
	for army in battle.side_a + battle.side_b:
		attacker = attacker or record.attacker_members.has(army.owner_nation)
		defender = defender or record.defender_members.has(army.owner_nation)
	# A virtual garrison has no Army binding; its real city owner is the other side.
	return (attacker and (defender or record.defender_members.has(battle.city.owner_nation))) or (defender and record.attacker_members.has(battle.city.owner_nation))

static func collect_endings(state: GameState) -> void:
	if state.state_campaigns.is_empty(): return
	var endings: Array[StateCampaign] = []
	for value in state.state_campaigns.values():
		var record: StateCampaign = value
		if record.lifecycle == Campaign.Lifecycle.ENDING: endings.append(record)
	if endings.is_empty(): return
	var busy := {}
	var independent_defenses := {}
	var live_sieges := {}
	var live_battles := {}
	var armies_by_id := {}
	for battle in state.battles:
		if battle.finished: continue
		live_battles[battle.id] = true
		if battle.kind == Battle.Kind.SIEGE and battle.city != null:
			var center := state.administrative_center_of(battle.city.id)
			if not live_sieges.has(center): live_sieges[center] = []
			live_sieges[center].append(battle)
		for army in battle.side_a + battle.side_b:
			if army.campaign_front_id >= 0: busy[army.campaign_front_id] = true
	for army in state.armies:
		armies_by_id[army.id] = army
		if army.campaign_front_id >= 0 and army.on_edge: busy[army.campaign_front_id] = true
	for record in endings:
		var moving: Array[int] = []
		for id in record.ending_army_ids:
			var army: Army = armies_by_id.get(id)
			if army == null or army.size <= 0: continue
			if army.campaign_front_id >= 0 and army.campaign_front_id not in [record.offense_front_id, record.defense_front_id]: continue
			if army.on_edge or live_battles.has(army.battle_id) or (army.state in [Army.State.MOVING, Army.State.RETREATING] and army.ai_action == ActionCandidate.Kind.RETREAT and not army.path.is_empty()): moving.append(id)
		record.ending_army_ids = moving
		var pending := not moving.is_empty()
		for battle in live_sieges.get(record.center_city_id, []):
			if siege_references(record, battle): pending = true; break
		for id in [record.offense_front_id, record.defense_front_id]:
			var front := state.campaign_front(id)
			if front == null or has_active_reference(state, front): continue
			if busy.has(id): pending = true; continue
			if defense_needed(state, front):
				front.retiring = false
				independent_defenses[front.front_id] = front
				continue
			state.release_campaign_front(id)
		if pending: continue
		for id in [record.offense_front_id, record.defense_front_id]:
			var front := state.campaign_front(id)
			if front != null: front.state_campaign_ids.erase(record.campaign_id)
		for pair_value in state.campaign_pairs.values():
			for slot in (pair_value as CoalitionCampaignPair).battlefields:
				if int(slot.get("state_campaign_id", -1)) == record.campaign_id: slot["state_campaign_id"] = -1
		state.state_campaigns.erase(record.campaign_id)
	if not independent_defenses.is_empty():
		var components := state.coalition_campaign_components()
		var activity := state.campaign_defense_activity_index()
		for front in independent_defenses.values():
			if front.state_campaign_ids.is_empty(): adopt_defense(state, front, components, activity)

static func adopt_offense(state: GameState, front: CoalitionCampaignFront, components: Array[Dictionary]) -> StateCampaign:
	for id in front.state_campaign_ids:
		var record: StateCampaign = state.state_campaigns.get(id)
		if record != null and record.lifecycle == Campaign.Lifecycle.ACTIVE and record.attacker_members.has(front.anchor_nation_id):
			attach(state, record, front); ensure_defense(state, record); return record
	var opponent := state.cities[front.center_city_id].owner_nation
	if not state.is_enemy(front.anchor_nation_id, opponent):
		opponent = -1
		for member in state.administrative_members(front.center_city_id):
			var owner := state.cities[member].owner_nation
			if state.is_enemy(front.anchor_nation_id, owner) and state.war_id_between(front.anchor_nation_id, owner) == front.war_id:
				opponent = owner; break
	if opponent < 0: return null
	var record := activate(state, front.anchor_nation_id, opponent, front.center_city_id, front.war_id, components)
	if record != null:
		record.incidental = false
		attach(state, record, front)
	return record

static func adopt_defense(state: GameState, front: CoalitionCampaignFront, components: Array[Dictionary], activity: Dictionary) -> void:
	var context := state.campaign_defense_context(front.anchor_nation_id, front.center_city_id, front.war_id, activity)
	if not bool(context.active): return
	var enemies := {}
	for force in (activity.get("forces", {}) as Dictionary).get(front.center_city_id, []): enemies[int(force.owner)] = true
	for camp in (activity.get("camps", {}) as Dictionary).get(front.center_city_id, []): enemies[int(camp.owner)] = true
	for owner in (activity.get("sieges", {}) as Dictionary).get(front.center_city_id, []): enemies[int(owner)] = true
	for city in context.enemy_fu_ids: enemies[state.cities[city].owner_nation] = true
	var ids := enemies.keys(); ids.sort()
	for owner in ids:
		if not state.is_enemy(front.anchor_nation_id, owner) or state.war_id_between(front.anchor_nation_id, owner) != front.war_id: continue
		var covered := false
		for id in front.state_campaign_ids:
			var existing: StateCampaign = state.state_campaigns.get(id)
			if existing != null and existing.lifecycle != Campaign.Lifecycle.PREPARING and existing.attacker_members.has(owner): covered = true; break
		if covered: continue
		var next_id := state.next_state_campaign_id
		var record := activate(state, owner, front.anchor_nation_id, front.center_city_id, front.war_id, components)
		if record != null:
			if record.campaign_id >= next_id: record.incidental = true
			attach(state, record, front)

static func bootstrap(state: GameState, components: Array[Dictionary]) -> void:
	for value in state.campaign_fronts.values().duplicate():
		var front: CoalitionCampaignFront = value
		if not front.retiring and front.mode == CoalitionCampaignFront.Mode.OFFENSE and front.state_campaign_ids.is_empty() and state.is_zhou_city(front.center_city_id) and not members_for(components, front.war_id, front.participant_nation_ids).is_empty():
			adopt_offense(state, front, components)

static func reconcile(state: GameState, components: Array[Dictionary], activity: Dictionary) -> void:
	var ids := state.state_campaigns.keys(); ids.sort()
	var unique := {}
	for id in ids:
		var record: StateCampaign = state.state_campaigns[id]
		if record.lifecycle == Campaign.Lifecycle.ENDING: continue
		if record.lifecycle == Campaign.Lifecycle.PREPARING:
			var nation := state.nations[record.initiator_nation_id]
			if not nation.alive or not state.nations[record.defender_nation_id].alive or nation.war_preparation_target_nation != record.defender_nation_id or nation.war_preparation_objective_center_city != record.center_city_id:
				state.state_campaigns.erase(id)
			continue
		var offense := state.campaign_front(record.offense_front_id)
		var defense := state.campaign_front(record.defense_front_id)
		var attackers := members_for(components, record.war_id, offense.participant_nation_ids if offense != null and not offense.retiring else record.attacker_members)
		var defenders := members_for(components, record.war_id, defense.participant_nation_ids if defense != null and not defense.retiring else record.defender_members)
		if attackers.is_empty() or defenders.is_empty(): end(state, id, "战争退出"); continue
		var hostile := false
		for a in attackers:
			for b in defenders:
				if state.is_enemy(a, b) and state.war_id_between(a, b) == record.war_id: hostile = true
		if not hostile: end(state, id, "战争退出"); continue
		record.attacker_members = attackers
		record.defender_members = defenders
		var owner := state.cities[record.center_city_id].owner_nation
		if not attackers.has(owner) and not defenders.has(owner): end(state, id, "目标被第三方取得"); continue
		var pair := state.find_campaign_pair(record.war_id, attackers[0], defenders[0])
		record.pair_id = pair.pair_id if pair != null else -1
		if record.incidental and not bool(state.campaign_defense_context(defenders[0], record.center_city_id, record.war_id, activity).active):
			end(state, id, "威胁解除"); continue
		var key := "%d:%d:%s:%s" % [record.war_id, record.center_city_id, str(attackers), str(defenders)]
		if unique.has(key):
			var kept: StateCampaign = unique[key]
			kept.incidental = kept.incidental and record.incidental
			kept.defense_activation_pending = kept.defense_activation_pending or record.defense_activation_pending
			for front_id in [record.offense_front_id, record.defense_front_id]:
				var front := state.campaign_front(front_id)
				if front != null:
					front.state_campaign_ids.erase(id); attach(state, kept, front)
			state.state_campaigns.erase(id)
			for pair_value in state.campaign_pairs.values():
				for slot in (pair_value as CoalitionCampaignPair).battlefields:
					if int(slot.get("state_campaign_id", -1)) == id: slot["state_campaign_id"] = kept.campaign_id
			continue
		unique[key] = record
	for value in state.campaign_fronts.values().duplicate():
		var front: CoalitionCampaignFront = value
		if front.retiring or front.war_id < 0 or not state.is_zhou_city(front.center_city_id): continue
		# Only the ordinary coalition planner's actual components are supported.
		if members_for(components, front.war_id, front.participant_nation_ids).is_empty(): continue
		if front.mode == CoalitionCampaignFront.Mode.OFFENSE: adopt_offense(state, front, components)
		else: adopt_defense(state, front, components, activity)
	for value in state.state_campaigns.values():
		var record: StateCampaign = value
		if record.lifecycle == Campaign.Lifecycle.ACTIVE: ensure_defense(state, record)
