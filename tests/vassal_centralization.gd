extends SceneTree
const Factions = preload("res://tests/vassal_faction_conflict.gd")
var checks := 0
var failures: Array[String] = []

class PeacefulSimulation extends Simulation:
	func _resolve_monthly_rebellions() -> void: pass
	func _resolve_ruler_successions() -> void: pass

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func army(state: GameState, owner: int, troops: int) -> Army:
	var unit: Army = null
	while troops>0:
		unit = Army.new()
		unit.id = state._next_army_id
		state._next_army_id += 1
		unit.owner_nation = owner
		unit.size = mini(troops,15000); unit.max_size = 15000
		unit.location_city = state.nations[owner].capital_city_id
		unit.attack = 10; unit.defense = 10
		unit.morale = 2; unit.max_morale = 2
		state.armies.append(unit)
		state.assign_main_army_to_independent_command(unit)
		troops -= unit.size
	return unit

func troops_of(state: GameState,owner: int) -> int:
	var total := 0
	for unit in state.armies:
		if unit.owner_nation==owner: total+=unit.size
	return total

func fixture(root_troops: int = 100000, subject_troops: int = 50000) -> GameState:
	var state := Factions.fixture()
	state.day = 2000
	for city in state.cities: city.loyalty = 100
	army(state,0,root_troops); army(state,1,subject_troops)
	return state

func target_action(state: GameState) -> Dictionary:
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(state,actions,{}, {})
	for action in actions:
		if action.a==0 and action.b==1: return action
	return {}

func make_rebellious(state: GameState) -> void:
	for city in state.land_cities_of(1):
		city.loyalty = RebellionSystem.LOYALTY_REBEL
		city.rebellion_progress = RebellionSystem.REBELLION_PROGRESS_MONTHS
	state.nations[0].last_rebellion_day = -1
	state.nations[1].last_rebellion_day = -1

func test_resistance() -> void:
	var state := fixture(100000,49999)
	check(not RebellionSystem.must_resist_centralization(state,1),"loyal ordinary subjects have no compulsory resistance")
	state.armies.back().size += 1
	check(not RebellionSystem.must_resist_centralization(state,1),"the former half-power boundary no longer forces resistance")
	check(not RebellionSystem.should_vassal_rebel(state,1),"strength alone does not trigger spontaneous rebellion")
	var rng_before := state.rng.state
	var soldiers_before := troops_of(state,0)+troops_of(state,1)
	var gold_before := state.nations[0].treasury_gold+state.nations[1].treasury_gold
	var sim := Simulation.new(); sim.setup(state)
	check(sim._execute_diplomatic_action({"kind":DiplomacyAI.Action.CENTRALIZE,"a":0,"b":1,"resist":true,"reason":"stale compulsory resistance preview"}),
		"execution rechecks actual loyalty instead of trusting an obsolete compulsory-resistance preview")
	check(not state.nations[1].alive and not state.is_in_civil_war(1),"a loyal ordinary subject accepts peaceful centralization at the former threshold")
	check(troops_of(state,0)==soldiers_before and troops_of(state,1)==0,"peaceful centralization transfers existing armies without spawning uprising troops")
	check(state.nations[0].treasury_gold==gold_before and state.nations[1].treasury_gold==0,"peaceful centralization transfers treasury once")
	check(state.rng.state==rng_before,"peaceful centralization does not draw uprising randomness")
	sim.free()
	state = fixture(100000,0)
	state.nations[1].ruler_archetype = RulerProfile.CONQUEROR
	check(RebellionSystem.must_resist_centralization(state,1),"weak conquerors retain their existing compulsory resistance")
	sim = Simulation.new(); sim.setup(state)
	check(sim._execute_diplomatic_action({"kind":DiplomacyAI.Action.CENTRALIZE,"a":0,"b":1,"resist":false}),"conqueror centralization executes")
	var new_troops := 0
	for unit in state.armies:
		if unit.owner_nation==1: new_troops += unit.size
	check(new_troops==30000,"conquerors retain double uprising manpower")
	sim.free()

func test_ai() -> void:
	var state := fixture(100000,300000)
	var loyal_action := target_action(state)
	check(not loyal_action.is_empty() and not bool(loyal_action.get("resist",true)),"a loyal ordinary subject stronger than the root can peacefully accept centralization")
	make_rebellious(state)
	check(target_action(state).is_empty(),"ordinary overlord refuses a politically threatening but losing centralization war")
	state.nations[0].ruler_archetype = RulerProfile.TYRANT
	check(not target_action(state).is_empty(),"tyrant may risk an unfavorable centralization war")
	state.nations[0].ruler_archetype = RulerProfile.PUPPET
	check(target_action(state).is_empty(),"puppet overlord still does not centralize")
	state = fixture()
	make_rebellious(state)
	for city in state.land_cities_of(2): city.loyalty = 25
	army(state,2,200000)
	army(state,4,1000000)
	check(target_action(state).is_empty(),"rebelling fellow prince counts against the central side; ordinary external ally is excluded")
	army(state,3,400000)
	var before := var_to_bytes(NativeSnapshotBuilder.build(state))
	var action := target_action(state)
	check(not action.is_empty() and bool(action.get("resist",false)),"reachable loyal princes can make a strong-subject centralization winnable")
	check(var_to_bytes(NativeSnapshotBuilder.build(state))==before,"AI civil-war evaluation is read-only and random-stream independent")
	if not action.is_empty():
		army(state,1,2000000)
		var sim := Simulation.new(); sim.setup(state)
		check(not sim._execute_diplomatic_action(action),"AI execution rechecks win prospects when strength changes after collection")
		check(not state.is_in_civil_war(1),"stale AI action cannot start a newly hopeless civil war")
		sim.free()
	state = fixture(200000,100000)
	make_rebellious(state)
	check(not target_action(state).is_empty(),"ordinary overlord may centralize a strong subject with sufficient military advantage")
	for unit in state.armies:
		if unit.owner_nation==0: unit.state=Army.State.RECOVERING
	check(target_action(state).is_empty(),"recovering central armies do not count as forces available to launch a civil war")
	for unit in state.armies: unit.state=Army.State.IDLE
	state.nations[1].state_level = EmpireStatus.EMPIRE
	state.cities[state.nations[1].capital_city_id].garrison_manpower = 30000
	check(target_action(state).is_empty(),"actual imperial capital guards can make an otherwise favorable civil war too risky")
	check(not DiplomacyAI.centralization_assessment(state,-1).can_attempt,"invalid subject has no centralization forecast")
	for change in ["puppet", "external_war"]:
		state = fixture(200000,100000)
		make_rebellious(state)
		action = target_action(state)
		if change=="puppet": state.nations[0].ruler_archetype=RulerProfile.PUPPET
		else:
			state._add_edge(0,10)
			state.set_diplomatic_relation(0,5,GameState.DiplomaticRelation.WAR)
		var sim := Simulation.new(); sim.setup(state)
		check(not action.is_empty() and not sim._execute_diplomatic_action(action) and not state.is_in_civil_war(1),
			"AI commit rechecks the changed political gate: "+change)
		sim.free()

func test_actual_victory(winner: int) -> void:
	var state := fixture()
	make_rebellious(state)
	var sim := Simulation.new(); sim.setup(state)
	check(sim._execute_diplomatic_action({"kind":DiplomacyAI.Action.CENTRALIZE,"a":0,"b":1,"resist":false}),"actual centralization rechecks and starts an eligible low-loyalty rebellion")
	var war_id := state.war_id_between(0,1)
	var loser := 1 if winner==0 else 0
	var capital := state.nations[loser].capital_city_id
	var total_gold := state.nations[0].treasury_gold+state.nations[1].treasury_gold
	var captor: Army = null
	for unit in state.armies:
		if unit.owner_nation==winner: captor=unit; break
	check(captor!=null and war_id>=0,"both political sides have a real army and internal war")
	if captor==null: sim.free(); return
	captor.campaign_war_id = war_id
	captor.location_city = capital; captor.move_from = capital
	sim._capture_city(captor,state.cities[capital],winner)
	check(not state.nations[loser].alive and state.nations[winner].alive,"real capital capture resolves either central victory or prince counter-annexation")
	check(state.nations[winner].treasury_gold==total_gold and state.nations[loser].treasury_gold==0,"actual civil-war annexation transfers treasury once")
	check(not state.war_relation_ids.values().has(war_id),"actual victory releases the whole internal war")
	check(state.armies.all(func(unit):return unit.campaign_war_id!=war_id),"actual victory releases all military bindings")
	check(state.chronicle_events.filter(func(event):return event.get("kind","")=="vassal_faction_result").size()==1,"actual victory writes one political result")
	check(state.territory_structure_valid() and state.suzerainty_structure_valid() and state._battle_group_structure_valid(),"both actual victory directions preserve territory, politics and formations")
	var before := var_to_bytes(NativeSnapshotBuilder.build(state))
	sim._resolve_civil_war_capital_capture(loser,winner)
	check(var_to_bytes(NativeSnapshotBuilder.build(state))==before,"repeated capital resolution cannot repeat annexation or resource settlement")
	sim.free()

func test_persistence() -> void:
	var state := fixture(0,0)
	state.armies.clear()
	# On the old implementation this timer expires on the next real daily commit.
	for property in state.get_property_list():
		if property.name=="suzerainty_low_cohesion_since_day": state.set(property.name,{0:state.day-359})
	var graph := state.suzerainty.duplicate(true)
	var sim := PeacefulSimulation.new(); root.add_child(sim); sim.setup(state)
	sim.paused = true; sim.diplomacy_enabled = false
	for day in range(365): sim._advance_day()
	check(state.suzerainty==graph,"a low-direct-control realm persists beyond a full year of real daily commits")
	check(state.diplomatic_history.all(func(event):return event.get("kind","")!="suzerainty_dissolved"),"time alone never dissolves the realm or creates an independence alliance")
	check(state.suzerainty_structure_valid(),"persistent strong princes preserve political invariants")
	sim.free()

func run() -> void:
	test_resistance(); test_ai(); test_persistence()
	test_actual_victory(0); test_actual_victory(1)
	for failure in failures: printerr("VASSAL_CENTRALIZATION_FAIL ",failure)
	print("VASSAL_CENTRALIZATION checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
