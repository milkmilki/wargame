extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func army(state: GameState,id: int,owner: int,node: int,size: int) -> Army:
	var value:=Army.new();value.id=id;value.owner_nation=owner;value.location_city=node;value.move_from=node;value.size=size;value.max_size=15000
	state.armies.append(value);return value
func _init() -> void:
	var state:=preload("res://tests/support/grid_world.gd").new();state.generate_grid_world(7401)
	for a in range(state.nations.size()):
		for b in range(a+1,state.nations.size()):state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	var center:=int(state.administrative_center_city_ids[0]);var rear:=int(state.neighbors(center)[0])
	for city in state.cities:city.owner_nation=2
	state.cities[center].owner_nation=0;state.cities[rear].owner_nation=0
	state.nations[0].capital_city_id=center
	state.ownership_revision+=1;state.armies.clear();state.battles.clear()
	var front:=CoalitionCampaignFront.new();front.front_id=700;front.center_city_id=center;front.anchor_nation_id=0;front.mode=CoalitionCampaignFront.Mode.DEFENSE;front.participant_nation_ids=[0] as Array[int]
	front.war_id=state.set_war_objective(1,0,center,"defense regroup");state.campaign_fronts[700]=front
	var small:=army(state,700,0,rear,9000);small.campaign_front_id=700;small.campaign_war_id=front.war_id;front.army_assignments[700]=rear
	var attacker:=army(state,701,1,center,10000)
	var battle:=Battle.new();battle.id=700;battle.kind=Battle.Kind.SIEGE;battle.city=state.cities[center];battle.siege_attacker_nation=1;battle.side_a=[attacker] as Array[Army];state.battles.append(battle)
	var sim:=Simulation.new();sim.state=state
	sim._execute_coalition_defense(front)
	check(front.camp_city_id==rear,"nearest safe real fu is chosen before relief")
	check(front.phase==CoalitionCampaignFront.Phase.DEFENSE_REGROUP and not small.on_edge,"9000 is not strictly more than 0.9 times 10000")
	var recovery:=army(state,702,0,rear,15000);recovery.state=Army.State.RECOVERING;recovery.campaign_front_id=700;front.army_assignments[702]=rear
	sim._execute_coalition_defense(front)
	check(not small.on_edge,"recovering defeated force does not satisfy relief threshold")
	recovery.state=Army.State.IDLE
	sim._execute_coalition_defense(front)
	check(front.phase==CoalitionCampaignFront.Phase.RELIEVE_CENTER and small.on_edge and recovery.on_edge,"assembled sufficient force gets actual relief orders")
	sim._execute_coalition_defense(front)
	check(front.phase==CoalitionCampaignFront.Phase.RELIEVE_CENTER,"departed relief cohort stays committed despite empty rally")
	sim._release_edge(small);small.state=Army.State.FIGHTING;small.location_city=center;small.move_to=-1;small.move_from=center;small.morale=0.;small.battle_id=700
	sim._start_morale_retreat_from_city(small,center,center)
	check(front.phase==CoalitionCampaignFront.Phase.DEFENSE_REGROUP and (small.move_to==rear or (not small.path.is_empty() and small.path.back()==rear)),"defeated relief retreats to its fixed rear camp")
	state.cities[rear].owner_nation=1;state.ownership_revision+=1
	sim._execute_coalition_defense(front)
	check(front.camp_city_id==-1,"lost rear point invalidates rally without inventing an accessible traffic goal")
	state.cities[center].owner_nation=1;state.ownership_revision+=1
	sim._execute_coalition_defense(front)
	check(state.campaign_front(700)==null,"captured center ends its defense task")
	sim.free();print("CAMPAIGN_DEFENSE_REGROUP checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
