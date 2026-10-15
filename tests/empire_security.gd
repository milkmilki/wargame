extends SceneTree
const Grid = preload("res://tests/support/grid_world.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture() -> GameState:
	var state := Grid.new()
	state.generate_grid_world(47020, false)
	state.day = 1000
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.treasury_gold = 1000000
		nation.manpower_pool = 1000000
		state.cities[nation.capital_city_id].food_storage = 1000000
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	state.region_ids.fill(0)
	state.region_analysis_revision += 1
	RegionalStrategy.invalidate_geometry(state)
	RegionalStrategy.initialize_targets(state)
	return state

func center_of(state: GameState, owner: int) -> int:
	for id in state.administrative_center_city_ids:
		if state.cities[id].owner_nation == owner: return id
	return -1

func promote(state: GameState, owner: int) -> void:
	state.region_ids.fill(-1)
	for city in state.land_cities_of(owner):
		state.region_ids[city.id] = 17
	EmpireStatus.reconcile(state)

func test_defense() -> void:
	var state := fixture()
	var center := center_of(state, 0)
	var city := state.cities[center]
	var stock := city.garrison_manpower
	var manpower := state.nations[0].manpower_pool
	var rng_before := state.rng.state
	var revision := state.garrison_revision
	promote(state, 0)
	check(state.nations[0].state_level == EmpireStatus.EMPIRE, "real one-region recognition promotes the sovereign")
	check(state.city_garrison_capacity(center) == 30000, "imperial core state capital has twice the normal guard capacity")
	check(city.garrison_manpower == stock and state.nations[0].manpower_pool == manpower,
		"promotion creates no guards or free manpower")
	check(state.garrison_revision > revision, "promotion invalidates capacity-dependent caches")
	city.garrison_supply_ratio = 1.0
	for other in state.administrative_center_city_ids:
		if other != center: state.cities[other].garrison_manpower = state.city_garrison_capacity(other)
	state.reinforce_city_garrisons_monthly()
	check(city.garrison_manpower == stock + 1500, "imperial guard grows through the existing monthly reinforcement limit")
	check(state.nations[0].manpower_pool == manpower - 1500, "real reinforcement spends exactly the recruited national manpower")
	var ordinary_cost := Simulation.city_garrison_cost_report(state,0,center,15000,{center:0})
	var imperial_cost := Simulation.city_garrison_cost_report(state,0,center,30000,{center:0})
	check(imperial_cost.food_demand > ordinary_cost.food_demand and imperial_cost.gold_upkeep > ordinary_cost.gold_upkeep,
		"larger actual imperial guards pay higher food and gold upkeep")
	state.nations[0].manpower_pool = 0
	state.reinforce_city_garrisons_monthly()
	check(city.garrison_manpower == stock + 1500, "no manpower means no imperial reinforcement")
	state.nations[0].manpower_pool = 100000
	city.garrison_supply_ratio = 0.0
	state.reinforce_city_garrisons_monthly()
	check(city.garrison_manpower == stock + 1500, "no food supply means no imperial reinforcement")
	city.garrison_supply_ratio = 1.0
	var siege := Battle.new(); siege.id = 990; siege.kind = Battle.Kind.SIEGE; siege.city = city
	state.battles.append(siege)
	state.reinforce_city_garrisons_monthly()
	check(city.garrison_manpower == stock + 1500, "an active siege blocks imperial monthly reinforcement")
	state.battles.clear()
	city.garrison_manpower = 29999
	state.reinforce_city_garrisons_monthly()
	check(city.garrison_manpower == 30000, "monthly reinforcement stops at the doubled establishment")
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
	state.suzerainty[1] = {"overlord_id":0, "civil_war":false}
	state.suzerainty[2] = {"overlord_id":1, "civil_war":false}
	check(state.city_garrison_capacity(center_of(state, 1)) == 30000, "peaceful direct subject inherits imperial core defense")
	check(state.city_garrison_capacity(center_of(state, 2)) == 30000, "peaceful indirect subject inherits imperial core defense")
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.ALLIED)
	check(state.city_garrison_capacity(center_of(state, 3)) == 15000, "ordinary allies do not inherit imperial defense")
	var original_guard := state.cities[center_of(state,1)].garrison_manpower
	state.suzerainty[1].civil_war = true
	check(state.city_garrison_capacity(center_of(state, 1)) == 15000, "rebellious subject loses inherited capacity")
	check(state.city_garrison_capacity(center_of(state, 2)) == 15000, "rebellious ancestor breaks indirect imperial protection")
	check(state.cities[center_of(state,1)].garrison_manpower == original_guard, "loss of protection does not delete previously recruited guards")
	state.suzerainty[1].civil_war = false
	var occupied := center_of(state, 3)
	for id in state.administrative_members(occupied): state.cities[id].owner_nation = 0
	check(state.city_garrison_capacity(occupied) == 15000, "unrecognized foreign occupation gains no imperial core bonus")
	state.nations[1].alive = false
	check(state.city_garrison_capacity(center_of(state, 2)) == 15000, "a dead intermediary cannot convey imperial protection")
	check(state.rng.state == rng_before, "recognition and capacity queries preserve the simulation random stream")

func test_deterrence() -> void:
	var state := fixture()
	var cache := {}
	var ordinary := DiplomacyAI.war_desire_breakdown(state, 0, 1, cache)
	check(is_finite(float(ordinary.score)) and float(ordinary.score) >= DiplomacyAI.WAR_DECLARE_SCORE,
		"ordinary baseline can actually propose conquest")
	state.nations[1].state_level = EmpireStatus.EMPIRE
	state.garrison_revision += 1
	var imperial := DiplomacyAI.war_desire_breakdown(state, 0, 1, cache)
	check(is_finite(float(imperial.score)) and float(imperial.score) < float(ordinary.score) * 0.2,
		"an ordinary country heavily discounts attacking a comparable empire")
	check(float(imperial.score) < DiplomacyAI.WAR_DECLARE_SCORE,
		"comparable ordinary country avoids starting imperial war")
	var rng_before := state.rng.state
	check("\n".join(DiplomacyAI.war_desire_debug_lines(state,0)).contains("帝国威慑 ×0.10"),
		"country diagnostic explains the real imperial caution coefficient")
	check(state.rng.state == rng_before, "war desire diagnostics remain random-stream independent")
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(state, actions, {}, {}, 0, 1)
	check(not actions.any(func(action: Dictionary): return action.kind == DiplomacyAI.Action.PREPARE_WAR and action.b == 1),
		"real action collection does not prepare the discouraged imperial war")
	state.nations[0].state_level = EmpireStatus.EMPIRE
	state.garrison_revision += 1
	var equal_empires := DiplomacyAI.war_desire_breakdown(state, 0, 1, cache)
	check(float(equal_empires.score) > float(imperial.score) * 2.0, "imperial peers retain ordinary rivalry")
	state.nations[0].state_level = EmpireStatus.COUNTRY
	for army in state.armies:
		if army.owner_nation == 0:
			army.size = 1500000
			army.max_size = 1500000
	state.garrison_revision += 1
	var dominant := DiplomacyAI.war_desire_breakdown(state, 0, 1, cache)
	check(float(dominant.score) >= DiplomacyAI.WAR_DECLARE_SCORE, "overwhelming ordinary power may still challenge a weak empire")
	state.truce_until_day[state._diplomacy_key(0, 1)] = state.day + 90
	state.diplomacy_revision += 1
	check(DiplomacyAI.war_desire(state, 0, 1, cache) == -INF, "imperial policy cannot bypass an actual truce")
	print("EMPIRE_DETERRENCE_METRIC ordinary=", ordinary.score, " imperial=", imperial.score, " peer=", equal_empires.score, " dominant=", dominant.score)
	state = fixture()
	state.nations[2].state_level = EmpireStatus.EMPIRE
	state.suzerainty[1] = {"overlord_id":2,"civil_war":false}
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.ALLIED)
	var subject := DiplomacyAI.war_desire_breakdown(state,0,1)
	check(is_finite(float(subject.score)) and subject.protecting_empire_id==2 and is_equal_approx(float(subject.empire_caution_multiplier),0.1),
		"real war evaluation extends imperial deterrence to peaceful subjects")

func run() -> void:
	test_defense()
	test_deterrence()
	for failure in failures: printerr("EMPIRE_SECURITY_FAIL ", failure)
	print("EMPIRE_SECURITY_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
