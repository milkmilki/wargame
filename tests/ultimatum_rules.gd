extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var rules = load("res://scripts/ai/ultimatum_rules.gd")
	if rules == null:
		push_error("ULTIMATUM_RULES_FAIL: missing rules")
		quit(1)
		return
	_check(is_equal_approx(rules.score(4.0, 1.0, 1.0, 0.0, 0.0), 80.0), "four times reaches annex threshold")
	_check(rules.outcome_for_score(80.0, true) == rules.Outcome.ANNEX, "annex equality")
	_check(rules.outcome_for_score(80.0, false) == rules.Outcome.SUBMIT, "large polity only submits")
	_check(rules.outcome_for_score(55.0, true) == rules.Outcome.SUBMIT, "submission equality")
	_check(rules.outcome_for_score(54.99, true) == rules.Outcome.REFUSE, "below threshold refuses")
	_check(is_equal_approx(rules.score(4.0, 1.0, 1.0, 0.0, 0.0), rules.score(100000.0, 1.0, 1.0, 0.0, 0.0)), "military cap")
	_check(rules.score(100000.0, 1.0, 0.0, 15.0, -5.0) < 55.0, "environment blocks universal surrender")
	var state := GameState.new()
	state.generate_grid_world(94601)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	state.armies.clear()
	state.battles.clear()
	var staging := state.nations[0].capital_city_id
	var capital := state.nations[1].capital_city_id
	state.cities[capital].garrison_manpower = 1000
	var attacker := _army(100, 0, staging, 4000)
	state.armies.append(attacker)
	state.nations[0].war_preparation_staging_city_id = staging
	state.nations[0].war_preparation_army_ids = [100]
	var result: Dictionary = rules.evaluate(state, 0, 1)
	_check(result.eligible and is_equal_approx(result.attacker_power, 4000.0), "only physically assembled military counts")
	var original := result.duplicate(true)
	attacker.id = 999
	state.nations[0].war_preparation_army_ids = [999]
	for city in state.cities:
		city.coord.x = GameState.GRID - 1 - city.coord.x
		city.map_position.x = 1.0 - city.map_position.x
	_check(rules.evaluate(state, 0, 1) == original, "mirror and army id permutation leave score unchanged")
	attacker.id = 100
	state.nations[0].war_preparation_army_ids = [100]
	attacker.size = 2000
	_check(is_equal_approx(rules.evaluate(state, 0, 1).attacker_power, 2000.0), "partial army counts actual strength not nominal maximum")
	attacker.size = 4000
	var defender := _army(104, 1, capital, 1200)
	state.armies.append(defender)
	_check(is_equal_approx(rules.evaluate(state, 0, 1).defender_power, float(original.defender_power) + 1200.0), "polity stationed defender counts")
	defender.location_city = staging
	_check(is_equal_approx(rules.evaluate(state, 0, 1).defender_power, float(original.defender_power)), "defender outside polity is not credible support")
	var base_defense := float(result.defender_power)
	state.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
	var adjacent_ally := _army(101, 3, state.nations[3].capital_city_id, 10000)
	var distant_ally := _army(102, 2, state.nations[2].capital_city_id, 90000)
	state.armies.append(adjacent_ally)
	state.armies.append(distant_ally)
	result = rules.evaluate(state, 0, 1)
	_check(is_equal_approx(result.allied_support, base_defense * 0.5), "adjacent support bounded once")
	adjacent_ally.campaign_war_id = 20
	_check(is_zero_approx(rules.evaluate(state, 0, 1).allied_support), "distant and committed allies excluded")
	adjacent_ally.campaign_war_id = -1
	state.nations[3].war_preparation_army_ids = [101]
	_check(is_zero_approx(rules.evaluate(state, 0, 1).allied_support), "other preparation reservations excluded")
	state.nations[3].war_preparation_army_ids.clear()
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.NEUTRAL)
	attacker.state = Army.State.RECOVERING
	_check(not rules.evaluate(state, 0, 1).eligible, "recovering attacker cannot threaten")
	attacker.state = Army.State.IDLE
	attacker.supply_ratio = 0.0
	_check(not rules.evaluate(state, 0, 1).eligible, "starving attacker cannot threaten")
	attacker.supply_ratio = 1.0
	attacker.campaign_war_id = 20
	_check(not rules.evaluate(state, 0, 1).eligible, "commandeered preparation army cannot threaten")
	attacker.campaign_war_id = -1
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	attacker.ruler_attack_multiplier = 5.0
	attacker.ruler_defense_multiplier = 5.0
	result = rules.evaluate(state, 0, 1)
	_check(is_equal_approx(result.attacker_power, ArmyPower.effective(attacker)), "conqueror multiplier counted once")
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	_check(not rules.evaluate(state, 0, 1).eligible, "third party war prevents peaceful outcome")
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	state.rebellions[1] = {"active": false, "parent_id": 2}
	_check(not rules.evaluate(state, 0, 1).eligible, "unreleased rebellion identity prevents submission")
	state.rebellions.clear()
	state.nations[1].name_kind = WorldNaming.KIND_REBEL
	_check(not rules.evaluate(state, 0, 1).eligible, "unrecognized rebel title prevents submission")
	state.nations[1].name_kind = WorldNaming.KIND_WARRING_STATE
	state.suzerainty[1] = {"overlord_id": 2, "civil_war": false}
	_check(not rules.evaluate(state, 0, 1).eligible, "foreign vassal cannot change lord by ultimatum")
	if not failures.is_empty():
		for failure in failures:
			push_error("ULTIMATUM_RULES_FAIL: " + failure)
		quit(1)
	else:
		print("ULTIMATUM_RULES_OK")
		quit(0)

func _army(id: int, owner: int, city: int, size: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner
	army.location_city = city
	army.size = size
	army.max_size = size
	army.attack = 10
	army.defense = 10
	army.morale = 1.0
	army.supply_ratio = 1.0
	return army

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
