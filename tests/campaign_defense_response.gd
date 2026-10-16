extends SceneTree
const Direct = preload("res://tests/direct_center_camp.gd")
const Simple = preload("res://scripts/simulation/rules/simple_campaign.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("DEFENSE_RESPONSE_FAIL ",message)
func fixture() -> Dictionary:
	var state := Direct.fixture()
	var record := state.activate_state_campaign(0,1,3,state.war_id_between(0,1))
	var sim := Simulation.new(); sim.setup(state)
	var front := state.campaign_front(record.defense_front_id)
	var key := "%d:%s" % [front.war_id,str(front.participant_nation_ids)]
	sim._coalition_campaign_next_due_day[key] = state.day + 10
	return {"state":state,"sim":sim,"front":front,"key":key}
func run() -> void:
	test_new_threat()
	test_ready_relief()
	test_replenished_relief()
	test_live_field_reinforcement()
	print("CAMPAIGN_DEFENSE_RESPONSE checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func test_new_threat() -> void:
	var f := fixture(); var state: GameState=f.state; var sim: Simulation=f.sim
	var front: CoalitionCampaignFront=f.front
	var guard := Direct.army(state,1,3)
	guard.campaign_front_id=front.front_id; guard.campaign_war_id=front.war_id; front.army_assignments[guard.id]=3
	front.reported_requirement=15000
	var reserve := Direct.army(state,1,4,30000)
	var threat := Direct.army(state,0,2,45000)
	var attack := Direct.front(state,[threat] as Array[Army]); attack.camp_city_id=2
	var before := state.rng.state
	Simple.poll(sim)
	check(int(sim._coalition_campaign_next_due_day[f.key])<=state.day+1,"new physical threat schedules next-day allocation instead of ten-day wait")
	check(not reserve.on_edge and state.rng.state==before,"poll only schedules; no extra commands or random draws")
	state.day+=1; sim._manage_coalition_campaigns()
	check(reserve.campaign_front_id==front.front_id and reserve.on_edge and reserve.ai_target_city==3,"next-day planning sends available real reinforcements")
	var due := int(sim._coalition_campaign_next_due_day[f.key])
	Simple.poll(sim)
	check(int(sim._coalition_campaign_next_due_day[f.key])==due,"unchanged covered threat does not wake planner every day")
	sim.free()
func test_replenished_relief() -> void:
	var f := fixture(); var state: GameState=f.state; var sim: Simulation=f.sim
	var front: CoalitionCampaignFront=f.front
	siege(state,Direct.army(state,0,3))
	var reserve := Direct.army(state,1,4,9000)
	reserve.campaign_front_id=front.front_id; reserve.campaign_war_id=front.war_id; front.army_assignments[reserve.id]=4
	front.phase=CoalitionCampaignFront.Phase.DEFENSE_REGROUP; front.camp_city_id=4
	front.reported_requirement=state.campaign_field_minimum_manpower(1,15000)
	Simple.poll(sim)
	check(int(sim._coalition_campaign_next_due_day[f.key])==state.day+10,"understrength camp retains ordinary planning schedule")
	reserve.size=15000
	Simple.poll(sim)
	check(int(sim._coalition_campaign_next_due_day[f.key])<=state.day+1,"same formations replenishing across relief threshold wake next-day launch")
	sim._coalition_campaign_next_due_day[f.key]=state.day+10
	Simple.poll(sim)
	check(int(sim._coalition_campaign_next_due_day[f.key])==state.day+10,"unchanged ready camp does not retry every day after a failed path")
	sim.free()
func siege(state: GameState, attacker: Army) -> Battle:
	var battle := state.new_battle(Battle.Kind.SIEGE); battle.city=state.cities[3]
	battle.siege_attacker_nation=0; battle.side_a.append(attacker)
	attacker.state=Army.State.FIGHTING; attacker.battle_id=battle.id
	return battle
func test_ready_relief() -> void:
	var f := fixture(); var state: GameState=f.state; var sim: Simulation=f.sim
	var front: CoalitionCampaignFront=f.front
	var attacker := Direct.army(state,0,3)
	siege(state,attacker)
	var reserve := Direct.army(state,1,4)
	reserve.campaign_front_id=front.front_id; reserve.campaign_war_id=front.war_id; front.army_assignments[reserve.id]=4
	front.phase=CoalitionCampaignFront.Phase.DEFENSE_REGROUP; front.camp_city_id=4
	front.reported_requirement=state.campaign_field_minimum_manpower(1,15000)
	Simple.poll(sim)
	check(int(sim._coalition_campaign_next_due_day[f.key])<=state.day+1,"assembled relief wakes the planner without waiting another ten days")
	state.day+=1; sim._manage_coalition_campaigns()
	check(front.phase==CoalitionCampaignFront.Phase.RELIEVE_CENTER and reserve.on_edge and reserve.ai_target_city==3,"ready relief actually departs at next planning boundary")
	sim.free()
func test_live_field_reinforcement() -> void:
	var f := fixture(); var state: GameState=f.state; var sim: Simulation=f.sim
	var front: CoalitionCampaignFront=f.front
	var attacker := Direct.army(state,0,3,45000)
	var battle := siege(state,attacker)
	var guard := Direct.army(state,1,3,30000)
	guard.state=Army.State.FIGHTING; guard.battle_id=battle.id
	guard.campaign_front_id=front.front_id; guard.campaign_war_id=front.war_id
	front.army_assignments[guard.id]=3; battle.side_b.append(guard); battle.side_b_defends_city=true
	var reinforcement := Direct.army(state,1,4)
	reinforcement.campaign_front_id=front.front_id; reinforcement.campaign_war_id=front.war_id
	front.army_assignments[reinforcement.id]=3
	sim._order_campaign_army(reinforcement,front,3,ActionCandidate.Kind.REINFORCE)
	sim._execute_coalition_defense(front)
	check(front.phase==CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE and reinforcement.ai_target_city==3,"ongoing city field defense keeps its arriving reinforcement")
	var routed := Direct.army(state,1,3,1000)
	routed.campaign_front_id=front.front_id; routed.campaign_war_id=front.war_id
	front.army_assignments[routed.id]=3
	sim._start_morale_retreat_from_city(routed,3,3)
	check(front.phase==CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE,"one retreating unit does not recall the front while another guard still fights")
	reinforcement.move_progress=1.0; sim._arrive_at_node(reinforcement)
	check(battle.has_army(reinforcement) and reinforcement.state==Army.State.FIGHTING,"late reinforcement physically joins the ongoing defense field battle")
	sim.free()
