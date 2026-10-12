extends SceneTree
const Rules=preload("res://scripts/simulation/rules/simple_campaign.gd")
var failures:=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;push_error(message)
func _init() -> void:
	var state:=preload("res://tests/support/grid_world.gd").new();state.generate_grid_world(7401)
	for a in range(state.nations.size()):
		for b in range(a+1,state.nations.size()):state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	var center:=int(state.administrative_center_city_ids[0])
	state.cities[center].owner_nation=1;state.cities[center].garrison_manpower=15000
	var members:=state.administrative_members(center)
	for id in members:state.cities[id].owner_nation=1
	state.ownership_revision+=1
	var war:=state.set_war_objective(0,1,center,"single wave")
	state.armies.clear();state.battles.clear()
	var front:=CoalitionCampaignFront.new();front.front_id=500;front.center_city_id=center;front.anchor_nation_id=0;front.war_id=war;front.participant_nation_ids=[0] as Array[int]
	state.campaign_fronts[500]=front
	var battle:=Battle.new();battle.id=500;battle.kind=Battle.Kind.SIEGE;battle.city=state.cities[center];battle.siege_attacker_nation=0
	for index in range(3):
		var army:=Army.new();army.id=500+index;army.owner_nation=0;army.size=6000+index*1000;army.max_size=15000;army.location_city=center;army.move_from=center
		army.state=Army.State.FIGHTING;army.battle_id=500;army.campaign_front_id=500;army.campaign_war_id=war
		state.armies.append(army);front.army_assignments[army.id]=center;battle.side_a.append(army)
	state.battles.append(battle)
	var sim:=Simulation.new();sim.state=state
	check(Rules.siege_state(sim,battle)==Rules.SiegeState.BLOCKADE,"current siege requires fu control")
	var defender:=Army.new();defender.id=999;defender.owner_nation=1;defender.size=1000;battle.side_b.append(defender)
	Rules.start_raids(sim,front,battle)
	check(not state.campaign_raid_used(front) and front.detachments.is_empty(),"real city field battle cannot dispatch or consume a wave")
	battle.side_b.clear()
	state.cities[center].garrison_manpower=1
	Rules.start_raids(sim,front,battle)
	check(not state.campaign_raid_used(front) and front.detachments.is_empty(),"normal assault cannot draw off formations or consume raid wave")
	state.cities[center].garrison_manpower=15000
	Rules.start_raids(sim,front,battle)
	check(state.campaign_raid_used(front),"one wave consumed in persistent war/state record")
	check(battle.side_a.has(state.armies[2]),"largest formation remains in siege")
	check(front.detachments.size()<=members.size()-1 and state.armies.size()==3,"no new armies and at most one unit per remaining fu")
	check(not front.detachments.is_empty(),"available units actually depart for fu")
	var count:=front.detachments.size();Rules.start_raids(sim,front,battle)
	check(front.detachments.size()==count,"same siege never dispatches a second wave")
	var replacement:=CoalitionCampaignFront.new();replacement.war_id=war;replacement.center_city_id=center;replacement.participant_nation_ids=[0] as Array[int]
	check(state.campaign_raid_used(replacement),"front recreation does not refresh wave")
	replacement.front_id=501;replacement.anchor_nation_id=0;state.campaign_fronts[501]=replacement
	Rules.restore_raid_tasks(sim,replacement)
	check(replacement.detachments.size()==count,"front recreation restores fixed detachment tasks")
	state.campaign_fronts.erase(500);front=replacement
	var id:=int(front.detachments.keys()[0]);var task:Dictionary=front.detachments[id];var unit:Army=state.armies.filter(func(a):return a.id==id)[0]
	sim._release_edge(unit);unit.state=Army.State.IDLE;unit.location_city=int(task.target);unit.move_from=unit.location_city;unit.move_to=-1;unit.path.clear()
	state.cities[unit.location_city].owner_nation=0;state.ownership_revision+=1
	Rules.poll(sim)
	check(int(task.status)==CoalitionCampaignFront.DetachmentStatus.RETURNING and unit.ai_target_city==center,"captured fu immediately orders return before strategic batch")
	check(unit.campaign_war_id==war and unit.campaign_front_id==501,"return preserves war and campaign identity")
	state.merge_war_ids(war+100,war);war+=100
	check(state.campaign_raid_used(front),"war merge preserves already-used raid")
	var old:=NativeSnapshotBuilder.build(state);old.schema_version=26
	check(not NativeSnapshotBuilder.succession_validation_error(old).is_empty(),"schema26 rejected by new runtime rules")
	var snapshot:=NativeSnapshotBuilder.build(state)
	check(snapshot.has("campaign_raid_records"),"wave records included in native snapshot")
	check(snapshot.campaign_fronts.has("detachments"),"task progress included in native snapshot")
	sim._release_edge(unit);unit.state=Army.State.IDLE;unit.move_to=-1;unit.move_from=unit.location_city;unit.path.clear()
	var manual:=sim.order_army_to(unit,center)
	check(bool(manual.ok) and unit.campaign_front_id==-1 and int(task.status)==CoalitionCampaignFront.DetachmentStatus.FAILED,"manual command cancels raid task rather than being overwritten by return poll")
	var partial:Dictionary=sim._campaign_action_force(front,center,ActionCandidate.Kind.ATTACK,center)
	check(Rules.ready_force(sim,front,center,center,ActionCandidate.Kind.ATTACK).manpower==0,"fighting blockade participants are not idle rally force")
	sim.free();print("CAMPAIGN_SINGLE_WAVE failures=",failures);quit(0 if failures==0 else 1)
