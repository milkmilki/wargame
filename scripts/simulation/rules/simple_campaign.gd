extends RefCounted
## Runtime tactical transitions. A raid wave consumes existing formations once.
const Front = preload("res://scripts/model/coalition_campaign_front.gd")
enum SiegeState { FIELD, BLOCKADE, ASSAULT }

static func siege_state(sim,battle: Battle) -> int:
	if battle.uses_field_combat_rules(): return SiegeState.FIELD
	var attacker := battle.siege_attacker_nation
	if attacker<0 and not battle.side_a.is_empty(): attacker=battle.side_a[0].owner_nation
	var front = sim.state.campaign_front_for(attacker,battle.city.id,Front.Mode.OFFENSE)
	var need: int = sim.state.campaign_attack_requirement(front.anchor_nation_id if front!=null else attacker,battle.city.id,false)
	return SiegeState.BLOCKADE if sim._siege_assault_manpower(battle)<need else SiegeState.ASSAULT

static func ready_force(sim,front: CoalitionCampaignFront,target: int,rally: int,kind: int) -> Dictionary:
	var armies: Array[Army]=[];var manpower:=0
	if rally<0:return {"armies":armies,"manpower":0}
	for army in sim._campaign_action_force(front,target,kind,rally).armies:
		if army.state==Army.State.IDLE and army.is_at_city_node(rally) and sim.state.army_effective_for_field_campaign(army): armies.append(army);manpower+=army.size
	return {"armies":armies,"manpower":manpower}

static func manage_siege(sim,front: CoalitionCampaignFront,battle: Battle) -> bool:
	restore_raid_tasks(sim,front)
	update_detachments(sim,front)
	var status:=siege_state(sim,battle)
	if status==SiegeState.FIELD:return false
	if status==SiegeState.BLOCKADE:
		if not sim._collect_ai_commands and not sim.state.campaign_raid_used(front): start_raids(sim,front,battle)
		front.phase=Front.Phase.BLOCKADE_RAID if has_active_raids(front) else Front.Phase.BLOCKADE_ONLY
	else:front.phase=Front.Phase.ASSAULT_CENTER
	var armies: Array[Army]=[];var size:=0
	for army in sim._campaign_plan_armies(front):
		if front.detachments.has(army.id) and int(front.detachments[army.id].status) in [Front.DetachmentStatus.OUTBOUND,Front.DetachmentStatus.RETURNING]:continue
		armies.append(army);size+=army.size
	return sim._dispatch_campaign_action(front,{"armies":armies,"manpower":size},front.center_city_id,ActionCandidate.Kind.ATTACK,front.phase)

static func has_active_raids(front: CoalitionCampaignFront) -> bool:
	for task in front.detachments.values():
		if int(task.status) in [Front.DetachmentStatus.OUTBOUND,Front.DetachmentStatus.RETURNING]: return true
	return false

static func army_on_raid(front: CoalitionCampaignFront,id: int) -> bool:
	return front.detachments.has(id) and int(front.detachments[id].status) in [Front.DetachmentStatus.OUTBOUND,Front.DetachmentStatus.RETURNING]

static func start_raids(sim,front: CoalitionCampaignFront,battle: Battle) -> void:
	if siege_state(sim,battle)!=SiegeState.BLOCKADE or not sim.state.mark_campaign_raid(front):return
	var candidates: Array[Army]=[]
	for army in battle.side_a:
		if sim.state.army_effective_for_field_campaign(army) and army.combat_morale()>Combat.ARMY_ROUT_THRESHOLD and army.campaign_front_id==front.front_id and not sim.ai_policy_overrides.has(army.owner_nation): candidates.append(army)
	candidates.sort_custom(func(a: Army,b: Army):return a.size>b.size if a.size!=b.size else EquivariantOrder.army_less(sim.state,front.anchor_nation_id,a,b,front.center_city_id))
	if candidates.size()<2:return
	# Largest existing unit stays in the siege; remaining units each get one fu.
	candidates.remove_at(0)
	var bloc: Array[int]=sim.state.alliance_bloc(front.anchor_nation_id)
	var targets: Array[int]=sim._zhou_enemy_fu_targets(front.anchor_nation_id,front.center_city_id,bloc,false)
	var used:={}
	for army in candidates:
		for target in targets:
			if used.has(target):continue
			var field:=Pathfinding.dijkstra_field(sim.state,front.center_city_id,army.owner_nation,false,true,target,army.max_size)
			var path:=Pathfinding.reconstruct(field.prev,front.center_city_id,target)
			if path.is_empty():continue
			# No real combat is in progress. Remove only this blockade participant.
			battle.side_a.erase(army);battle.reinforce_fresh_a.erase(army);battle.frontline_priority_a.erase(army)
			army.battle_id=-1;army.state=Army.State.IDLE
			var order:=ActionCandidate.make(ActionCandidate.Kind.ATTACK,2000.0,"封锁州治：单轮攻府",target)
			if sim._execute_ai_candidate(army,order,path,true):
				front.detachments[army.id]={"target":target,"status":Front.DetachmentStatus.OUTBOUND}
				front.army_assignments[army.id]=target;used[target]=true
			else:
				army.state=Army.State.FIGHTING;army.battle_id=battle.id;battle.side_a.append(army)
			break

static func update_detachments(sim,front: CoalitionCampaignFront) -> void:
	for id in front.detachments:
		var task: Dictionary=front.detachments[id]
		if int(task.status) in [Front.DetachmentStatus.COMPLETE,Front.DetachmentStatus.FAILED]:continue
		var army: Army=sim._army_by_id(int(id))
		if army==null or army.size<=0 or army.campaign_front_id!=front.front_id or army.state in [Army.State.RETREATING,Army.State.RECOVERING]:task.status=Front.DetachmentStatus.FAILED;continue
		var target:=int(task.target)
		if int(task.status)==Front.DetachmentStatus.OUTBOUND:
			if sim.state.has_military_access(army.owner_nation,sim.state.cities[target].owner_nation) or not sim.state.is_enemy(army.owner_nation,sim.state.cities[target].owner_nation):task.status=Front.DetachmentStatus.RETURNING
			elif army.state==Army.State.IDLE and not army.on_edge and army.location_city!=target:
				# A lost/invalid route ends this mission; it is never assigned another fu.
				task.status=Front.DetachmentStatus.RETURNING
		if int(task.status)==Front.DetachmentStatus.RETURNING:
			if army.is_at_city_node(front.center_city_id):task.status=Front.DetachmentStatus.COMPLETE;continue
			if army.state==Army.State.FIGHTING:continue
			if army.on_edge:
				if army.ai_target_city!=front.center_city_id:sim._withdraw_campaign_army(army,front.center_city_id)
			elif army.state==Army.State.IDLE:
				if not sim._order_campaign_army(army,front,front.center_city_id,ActionCandidate.Kind.ATTACK) and not sim._campaign_army_at_or_advancing(army,front.center_city_id):
					task.status=Front.DetachmentStatus.FAILED

static func restore_raid_tasks(sim,front: CoalitionCampaignFront) -> void:
	var record: Dictionary=sim.state.campaign_raid_record(front)
	if record.is_empty():return
	for member in front.participant_nation_ids:
		if not record.members.has(member):record.members.append(member)
	for value in sim.state.campaign_raid_records:
		if int(value.war)!=front.war_id or int(value.center)!=front.center_city_id or not sim.state._campaign_members_overlap(front.participant_nation_ids,value.members):continue
		for id in value.get("tasks",{}):
			var task: Dictionary=value.tasks[id]
			front.detachments[id]=task
			if int(task.status) in [Front.DetachmentStatus.COMPLETE,Front.DetachmentStatus.FAILED]:continue
			var army: Army=sim._army_by_id(int(id))
			if army==null or not front.participant_nation_ids.has(army.owner_nation):continue
			var old: CoalitionCampaignFront=sim.state.campaign_front(army.campaign_front_id)
			if old==null or (old.mode==front.mode and old.center_city_id==front.center_city_id):
				army.campaign_front_id=front.front_id;army.campaign_war_id=front.war_id
				front.army_assignments[id]=int(task.target) if int(task.status)==Front.DetachmentStatus.OUTBOUND else front.center_city_id

static func poll(sim) -> void:
	for value in sim.state.campaign_fronts.values().duplicate():
		var front: CoalitionCampaignFront=value
		if front.retiring or front.center_city_id<0 or front.center_city_id>=sim.state.cities.size() or sim._succession_front_context(front)!=null:continue
		if front.mode==Front.Mode.OFFENSE:
			restore_raid_tasks(sim,front)
			update_detachments(sim,front)
			var battle: Battle=sim._siege_battle_of(sim.state.cities[front.center_city_id])
			if battle!=null and front.participant_nation_ids.has(battle.siege_attacker_nation):
				var status:=siege_state(sim,battle)
				if status==SiegeState.BLOCKADE:
					if not sim.state.campaign_raid_used(front):start_raids(sim,front,battle)
					front.phase=Front.Phase.BLOCKADE_RAID if has_active_raids(front) else Front.Phase.BLOCKADE_ONLY
				elif status==SiegeState.ASSAULT:front.phase=Front.Phase.ASSAULT_CENTER
		else:ensure_rally(sim,front)
	sim.state.prune_campaign_raid_records()

static func ensure_rally(sim,front: CoalitionCampaignFront) -> void:
	var state: GameState=sim.state
	var key: Array=[state.ownership_revision,state.diplomacy_revision,state.road_network_revision,hash(state.besieged_city_ids())]
	if front.rally_revision==key:return
	front.rally_revision=key
	if front.camp_city_id>=0 and front.camp_city_id<state.cities.size() and front.camp_city_id!=front.center_city_id and state.cities[front.camp_city_id].is_settlement() and not state.city_under_siege(front.camp_city_id) and state.has_military_access(front.anchor_nation_id,state.cities[front.camp_city_id].owner_nation):
		var blocked:=state.besieged_city_ids();blocked.erase(front.center_city_id)
		var field:=Pathfinding.dijkstra_field(state,front.center_city_id,front.anchor_nation_id,false,true,-1,0,blocked)
		if float(field.dist.get(front.camp_city_id,INF))<INF:return
	front.camp_city_id=Pathfinding.campaign_retreat_goal(state,front.anchor_nation_id,front.center_city_id,front.center_city_id)

static func defense(sim,front: CoalitionCampaignFront) -> bool:
	sim._cleanup_campaign_assignments(front);ensure_rally(sim,front)
	var state: GameState=sim.state
	if not state.has_military_access(front.anchor_nation_id,state.cities[front.center_city_id].owner_nation):state.release_campaign_front(front.front_id);return false
	var battle: Battle=sim._siege_battle_of(state.cities[front.center_city_id])
	var regrouping:=battle!=null or front.phase in [Front.Phase.DEFENSE_REGROUP,Front.Phase.RELIEVE_CENTER]
	if battle==null and front.phase==Front.Phase.RELIEVE_CENTER:
		regrouping=false
	var rally:=front.camp_city_id if regrouping else front.center_city_id
	if rally<0:return false
	var changed:=false
	if regrouping:
		var context: Dictionary=state.campaign_defense_context(front.anchor_nation_id,front.center_city_id,front.war_id,sim._coalition_defense_activity)
		var force:=ready_force(sim,front,front.center_city_id,rally,ActionCandidate.Kind.REINFORCE)
		if battle!=null and not battle.uses_field_combat_rules() and int(force.manpower)>=int(context.requirement) and not force.armies.is_empty():
			changed=sim._dispatch_campaign_action(front,force,front.center_city_id,ActionCandidate.Kind.REINFORCE,Front.Phase.RELIEVE_CENTER)
		else:
			# The launched cohort stays committed; an empty camp is not a loss.
			var relieving:=false
			if front.phase==Front.Phase.RELIEVE_CENTER:
				for army in sim._campaign_plan_armies(front):
					if sim._campaign_army_at_or_advancing(army,front.center_city_id,ActionCandidate.Kind.REINFORCE):relieving=true;break
			if not relieving:front.phase=Front.Phase.DEFENSE_REGROUP
	else:front.phase=Front.Phase.HOLD_AND_REINFORCE
	front.tactical_target_city_ids=[front.center_city_id] as Array[int]
	for army in sim._campaign_plan_armies(front):
		if army.state in [Army.State.FIGHTING,Army.State.RETREATING,Army.State.RECOVERING]:continue
		if front.phase==Front.Phase.RELIEVE_CENTER and sim._campaign_army_at_or_advancing(army,front.center_city_id,ActionCandidate.Kind.REINFORCE):continue
		if army.on_edge or army.state==Army.State.MOVING:
			if regrouping and front.phase!=Front.Phase.RELIEVE_CENTER and army.ai_target_city==front.center_city_id:
				front.army_assignments[army.id]=rally
				changed=sim._withdraw_campaign_army(army,rally) or changed
			continue
		changed=sim._order_campaign_army(army,front,rally,ActionCandidate.Kind.REINFORCE) or changed
	front.refresh_fingerprint(state);return changed
