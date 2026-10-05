extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_grouped_war_count()
	_test_war_desire_limit()
	_test_conqueror_requirements()
	print("WAR_COUNT_AND_CONQUEROR_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)


func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func _test_grouped_war_count() -> void:
	var state := fixture()
	for defender in [1, 2, 3]:
		state.set_diplomatic_relation(0, defender, GameState.DiplomaticRelation.WAR)
		state.set_war_objective(0, defender, defender, "grouped", 100)
	check(state.wars_of(0).size() == 3, "enemy list must retain every opponent")
	check(state.has_method("active_war_count"), "grouped war count query exists")
	if not state.has_method("active_war_count"):
		return
	check(int(state.call("active_war_count", 0)) == 1, "three allied opponents count as one war")
	var cache := {}
	check(DiplomacyAI._cached_war_count(state, 0, cache) == 1, "diplomatic evaluation uses grouped count")
	state.set_diplomatic_relation(0, 4, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0, 4, 4, "separate", 101)
	check(int(state.call("active_war_count", 0)) == 2, "independent wars remain separate")
	check(DiplomacyAI._cached_war_count(state, 0, cache) == 2, "count cache follows declaration")
	state.merge_war_ids(100, 101)
	check(int(state.call("active_war_count", 0)) == 1, "merging wars updates count")
	check(DiplomacyAI._cached_war_count(state, 0, cache) == 1, "count cache follows merging")
	state.nations[3].alive = false
	check(int(state.call("active_war_count", 0)) == 1, "one fallen member does not end surviving war")
	for defender in [1, 2, 4]:
		state.set_diplomatic_relation(0, defender, GameState.DiplomaticRelation.NEUTRAL)
	check(int(state.call("active_war_count", 0)) == 0, "peace and dead opponents do not count")
	for defender in [1, 2]:
		state.set_diplomatic_relation(0, defender, GameState.DiplomaticRelation.WAR)
		state.war_relation_ids.erase(state._diplomacy_key(0, defender))
	check(int(state.call("active_war_count", 0)) == 2, "unidentified hostile pairs are not collapsed into one war")


func _test_war_desire_limit() -> void:
	var state := fixture()
	state.day = 1000
	state.nations[0].strategic_region_anchor_city_id = 5
	state.nations[0].treasury_gold = 1000000
	state.nations[0].manpower_pool = 1000000
	state.cities[0].gold_per_month = 1000
	state.cities[0].food_per_half_year = 100000
	state.cities[0].food_storage = 1000000
	state._add_edge(0, 5)
	for enemy_id in [1, 2, 3]:
		state.set_diplomatic_relation(0, enemy_id, GameState.DiplomaticRelation.WAR)
		state.set_war_objective(0, enemy_id, enemy_id, "same war", 100)
	var cache := {}
	var one_war_score := DiplomacyAI.war_desire(state, 0, 5, cache)
	check(one_war_score != -INF, "one three-member war does not block evaluating another neighbor")
	state.set_war_objective(0, 2, 2, "second war", 101)
	var two_war_score := DiplomacyAI.war_desire(state, 0, 5, cache)
	check(is_equal_approx(one_war_score - two_war_score, 0.75), "overextension adds 0.75 per war, not per enemy")
	state.set_war_objective(0, 3, 3, "third war", 102)
	check(DiplomacyAI.war_desire(state, 0, 5, cache) == -INF, "three independent wars block a fourth after cache invalidation")


func _test_conqueror_requirements() -> void:
	var state := fixture()
	state.administrative_center_by_city[2] = 1
	state.administrative_region_revision += 1
	state.cities[2].owner_nation = 1
	state.cities[1].garrison_manpower = 100001
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var enemy := Army.new()
	enemy.id = 20
	enemy.owner_nation = 1
	enemy.location_city = 1
	enemy.size = 12000
	enemy.max_size = 15000
	state.armies.append(enemy)
	var ordinary_r := state.campaign_siege_requirement(0, 1)
	var ordinary_launch := state.campaign_minimum_launch_requirement(0, 1)
	var ordinary_prewar := state.campaign_prewar_launch_requirement(0, 1, 1)
	var ordinary_assault := DiplomacyAI.objective_assault_troops(state, 0, 1)
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	check(is_equal_approx(RulerProfile.attack_multiplier(state.nations[0]), 5.0), "conqueror attack is fivefold")
	check(is_equal_approx(RulerProfile.defense_multiplier(state.nations[0]), 5.0), "conqueror defense is fivefold")
	check(state.campaign_siege_requirement(0, 1) == ordinary_r, "raw R remains a garrison value")
	check(state.campaign_reinforcement_threat(0, 1) == 12000, "raw V remains real enemy manpower")
	check(state.campaign_minimum_launch_requirement(0, 1) == ceili(float(ordinary_launch) * 0.5), "staging launch requires half rounded up")
	check(state.campaign_prewar_launch_requirement(0, 1, 1) == ceili(float(ordinary_prewar) * 0.5), "prewar threshold uses same half demand")
	check(DiplomacyAI.objective_assault_troops(state, 0, 1) == ceili(float(ordinary_assault) * 0.5), "diplomacy assault demand matches action threshold")
	check(state.campaign_attack_requirement(0, 1, false) == ceili(float(ordinary_r) * 0.5), "active siege halves R without adding V")
	var simulation := Simulation.new()
	simulation.state = state
	var front := CoalitionCampaignFront.new()
	front.anchor_nation_id = 0
	front.center_city_id = 1
	front.participant_nation_ids = [0]
	front.mode = CoalitionCampaignFront.Mode.OFFENSE
	check(simulation._front_requirement(front) == ceili(float(ordinary_assault) * 0.5), "war allocator scales R plus V once")
	state.cities[1].garrison_manpower = 1000
	check(simulation._front_requirement(front) == Simulation.CAMPAIGN_MIN_FRONT_MANPOWER, "allocation retains minimum front manpower")
	var army := Army.new()
	army.owner_nation = 0
	army.attack = 10
	army.defense = 10
	var battle := Battle.new()
	battle.side_a = [army]
	simulation._sync_battle_ruler_modifiers(battle)
	check(is_equal_approx(army.combat_attack(), 50.0) and is_equal_approx(army.ruler_defense_multiplier, 5.0), "live battle sync receives fivefold attack and defense")
	state.nations[0].ruler_archetype = RulerProfile.BALANCED
	simulation._sync_battle_ruler_modifiers(battle)
	check(is_equal_approx(army.ruler_attack_multiplier, 1.0) and is_equal_approx(army.ruler_defense_multiplier, 1.0), "succession removes conqueror combat bonuses")
	check(state.campaign_attack_requirement(0, 1) == state.campaign_siege_requirement(0, 1) + 12000, "ordinary successor restores full manpower demand")
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	state.set_diplomatic_relation(0, 4, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(4, 1, GameState.DiplomaticRelation.WAR)
	var shared := state.create_campaign_front(100, [0, 4], 0,
		CoalitionCampaignFront.Mode.OFFENSE, 1)
	army.id = 21
	army.owner_nation = 4
	army.size = 1500
	army.max_size = 1500
	army.morale = 1.0
	army.location_city = 1
	army.state = Army.State.FIGHTING
	army.campaign_front_id = shared.front_id
	shared.army_assignments[army.id] = 1
	state.armies.append(army)
	battle.id = 10
	battle.kind = Battle.Kind.SIEGE
	battle.city = state.cities[1]
	battle.siege_attacker_nation = 4
	state.battles.append(battle)
	simulation._advance_siege(battle, {1: [army]})
	check(battle.round_no == 1, "allied first arrival uses shared front policy instead of returning to blockade")
	check(is_equal_approx(army.ruler_attack_multiplier, 1.0), "allied army does not inherit conqueror combat power")
	simulation.free()


func fixture() -> GameState:
	var state := GameState.new()
	for id in range(6):
		var nation := Nation.new()
		nation.id = id
		nation.capital_city_id = id
		state.nations.append(nation)
		var city := City.new()
		city.id = id
		city.owner_nation = id
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.administrative_center_by_city.append(id)
		state.administrative_center_city_ids.append(id)
		state.region_ids.append(id)
		state.recognized_city_owners.append(id)
	for a in range(6):
		for b in range(a + 1, 6):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	return state
