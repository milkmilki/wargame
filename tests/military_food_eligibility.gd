extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(62012)
	state.armies.clear()
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
		nation.treasury_gold = 0
		nation.manpower_pool = 1000000
		nation.unpaid_military_upkeep = 100
		nation.military_payment_ratio = 0
	for city in state.cities:
		city.garrison_manpower = 0
		city.food_per_half_year = 6000
		city.food_storage = 100000 if city.has_warehouse else 0
	state.refresh_derived()
	var sim := Simulation.new()
	sim.setup(state)
	var capacity := DiplomacyAI.force_capacity_report(state, 0)
	_check(capacity.additional_armies > 0, "food and manpower support recruitment at zero cash")
	_check(not capacity.has("gold_total_capacity"), "cash military capacity removed")
	state.nations[0].treasury_gold = 1000000
	_check(DiplomacyAI.force_capacity_report(state, 0).additional_armies == capacity.additional_armies, "cash cannot change sustainable military count")
	state.nations[0].treasury_gold = 0
	var group := state.create_battle_group(0)
	var manpower := state.nations[0].manpower_pool
	var army := sim._create_army_for_nation(0, state.nations[0].capital_city_id, 15000, "food budget", false, group.id)
	_check(army != null and army.size == 15000, "zero cash creates a real formation")
	_check(state.nations[0].treasury_gold == 0 and state.nations[0].manpower_pool == manpower - 15000, "creation consumes manpower only")
	army.size = 10000
	sim._resolve_reinforcements()
	_check(army.size > 10000, "unpaid zero-cash field army refills")
	army.morale = 0.2
	sim._recover_morale()
	_check(is_equal_approx(army.morale, 0.2 + army.max_morale / Combat.MORALE_RECOVERY_DAYS), "unpaid ordinary recovery is full speed")
	army.state = Army.State.RECOVERING
	army.morale = 0.2
	sim._recover_morale()
	_check(is_equal_approx(army.morale, 0.2 + army.max_morale / Combat.MORALE_RECOVERY_DAYS), "unpaid retreat recovery is full speed with food")
	army.state = Army.State.IDLE
	var report := DiplomacyAI.resource_report(state, 0)
	_check(DiplomacyAI.offensive_resources_ready(state, 0, report), "arrears do not block declaration resources")
	_check(DiplomacyAI.war_preparation_resources_ready(state, 0), "arrears do not block preparation resources")
	var view := AiWorldView.build(state, 0)
	var assessment := sim._build_force_structure_assessment(view, {}, {})
	_check(not assessment.food_pressure, "cash deficit does not become food pressure")
	_check(not sim._try_force_structure_demobilization(view, ThreatField.build(view), state.nations[0], assessment), "arrears do not cause demobilization")
	for city in state.cities_of(0):
		city.food_storage = 0
		city.food_per_half_year = 0
	state.nations[0].treasury_gold = 1000000
	state.refresh_derived()
	_check(DiplomacyAI.force_capacity_report(state, 0).additional_armies == 0, "cash cannot buy military food eligibility")
	_check(not DiplomacyAI.war_preparation_resources_ready(state, 0), "food shortage still blocks preparation")
	var size_before := army.size
	sim._resolve_reinforcements()
	_check(army.size == size_before, "food shortage blocks refill")
	sim.free()
	for failure in failures:
		push_error(failure)
	print("MILITARY_FOOD_ELIGIBILITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
