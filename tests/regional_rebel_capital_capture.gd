extends SceneTree
const Direct = preload("res://tests/direct_center_camp.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(two_states: bool = false) -> Dictionary:
	var state := Direct.fixture()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	var rebel := state.start_regional_rebellion(0, [6, 7] as Array[int])
	check(rebel >= 0, "uprising uses real full-state transaction")
	if two_states:
		# Partition the fixture after the valid single-state uprising, to model
		# a surviving second state without passing an illegal cross-state list.
		state.administrative_center_by_city[7] = 7
		state.administrative_center_city_ids.append(7)
		state.administrative_region_revision += 1
	# Exercise the virtual-garrison stage after field defenders have withdrawn.
	state.armies.clear()
	state.nations[rebel].manpower_pool = 0
	state.set_war_objective(0, rebel, 6, "地方叛军驻地攻城回归")
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	return {"state": state, "sim": sim, "rebel": rebel}

func take_city(data: Dictionary, owner: int, source: int, target: int) -> Army:
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var army := Direct.army(state, owner, source, 60000)
	army.attack = 1000
	army.defense = 1000
	army.supply_ratio = 1.0
	army.campaign_war_id = state.war_id_between(0, data.rebel)
	army.occupation_claimant_nation = owner
	army.move_to = target
	army.move_progress = 1.0
	army.on_edge = true
	state.cities[target].garrison_manpower = 3000
	sim._arrive_at_node(army)
	var battle := sim._siege_battle_of(state.cities[target])
	check(battle != null, "real arrival starts siege")
	if battle != null:
		for tick in range(30):
			state.day += 1
			sim._advance_siege(battle)
			if battle.finished: break
		check(battle.finished and battle.winner_side == 1, "real combat wins siege")
	return army

func test_retake(two_states: bool, elapsed: int) -> void:
	var data := fixture(two_states)
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	state.day += elapsed
	var war := state.war_id_between(0, rebel)
	var army := take_city(data, 0, 1, 6)
	check(state.cities[6].owner_nation == 0, "unrecognized rebel capital is actually recaptured")
	check(state.recognized_owner_of(6) == 0 and state.cities[6].occupation_sponsor_nation == -1, "recapture preserves mother's legal title and removes occupation")
	check(army.state == Army.State.IDLE and not army.diplomatic_repatriation, "victor remains in captured city without false repatriation")
	sim._evict_stranded_hostile_armies()
	check(army.location_city == 6 and army.state == Army.State.IDLE, "daily eviction does not undo victory")
	if two_states:
		check(state.cities[7].owner_nation == rebel and state.nations[rebel].alive, "other rebel state survives capital loss")
		check(state.is_enemy(0, rebel), "unfinished uprising keeps actual war")
	else:
		check(state.cities[7].owner_nation == 0, "same-state dependent city defects with rebel center")
		sim._resolve_eliminated_nation_capitulations()
		state.prune_rebellions()
		ChronicleRules.finalize_pending(state)
		check(not state.nations[rebel].alive and not state.is_enemy(0, rebel), "military elimination releases war even before minimum peace duration")
		check(army.campaign_war_id == -1, "completed uprising releases winner's war binding")
		check(state.chronicle_events.filter(func(event): return event.get("kind", "") == "external_war" and event.get("war_id", -1) == war).is_empty(), "local uprising does not duplicate its political result as an external war")
		check(state.chronicle_events.filter(func(event): return event.get("kind", "") == "rebellion" and event.get("actor_ids", []).has(rebel)).size() == 1, "completed uprising writes one political result")
		var event_count := state.chronicle_events.size()
		sim._resolve_eliminated_nation_capitulations()
		state.prune_rebellions()
		ChronicleRules.finalize_pending(state)
		check(state.chronicle_events.size() == event_count, "repeated cleanup settles final events once")
	sim.free()

func test_rebel_counterattack() -> void:
	var data := fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	var war := state.war_id_between(0, rebel)
	state._add_edge(6, 0)
	var army := take_city(data, rebel, 6, 0)
	sim._resolve_eliminated_nation_capitulations()
	state.prune_rebellions()
	ChronicleRules.finalize_pending(state)
	check(not state.nations[0].alive and state.nations[rebel].alive, "defending rebel counterattack eliminates declaring mother country")
	for city in state.cities:
		if city.id in [0, 1, 2, 6, 7]: check(city.owner_nation == rebel and state.recognized_owner_of(city.id) == rebel, "rebel victory receives actual territory and legal title")
	check(not state.is_enemy(0, rebel) and army.campaign_war_id == -1, "reverse victory releases war and army binding")
	check(army.state != Army.State.RETREATING, "reverse winner remains in captured capital")
	check(state.chronicle_events.filter(func(event): return event.get("kind", "") == "external_war" and event.get("war_id", -1) == war).is_empty(), "reverse uprising also uses one political result")
	check(state.chronicle_events.filter(func(event): return event.get("kind", "") == "rebellion" and event.get("actor_ids", []).has(rebel) and event.get("result", "") == "recognized").size() == 1, "defending rebel victory records recognition once")
	var event_count := state.chronicle_events.size()
	sim._resolve_eliminated_nation_capitulations()
	state.prune_rebellions()
	ChronicleRules.finalize_pending(state)
	check(state.chronicle_events.size() == event_count, "reverse cleanup records once")
	sim.free()

func test_recognized_capital() -> void:
	var data := fixture()
	var state: GameState = data.state
	var sim: Simulation = data.sim
	var rebel: int = data.rebel
	state.day += 400
	check(sim._execute_diplomatic_action({"kind": DiplomacyAI.Action.MAKE_PEACE, "a": 0, "b": rebel, "reason": "承认后首都投降回归"}), "recognition uses actual peace resolution")
	check(not bool(state.rebellions[rebel].active) and state.recognized_owner_of(6) == rebel, "recognized nation has its own legal title")
	state.set_diplomatic_relation(0, rebel, GameState.DiplomaticRelation.WAR)
	var army := take_city(data, 0, 1, 6)
	check(state.cities[6].owner_nation == 0 and state.recognized_owner_of(6) == 0 and not state.is_enemy(0, rebel), "recognized sovereign capital retains capitulation and peace")
	check(army.state != Army.State.RETREATING, "recognized capital victor is not falsely repatriated")
	sim.free()

func run() -> void:
	for elapsed in [0, 400]:
		for two_states in [false, true]: test_retake(two_states, elapsed)
	test_rebel_counterattack()
	test_recognized_capital()
	for failure in failures: push_error("REGIONAL_REBEL_CAPTURE_FAIL: " + failure)
	print("REGIONAL_REBEL_CAPTURE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
