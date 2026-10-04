extends SceneTree

const Chain = preload("res://tests/succession_chain.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func launched() -> Dictionary:
	var state: GameState = Chain.fixture()
	var nation := state.nations[0]
	var prince := nation.prince_person_ids[1]
	PrincePolitics.person(state, 0, prince).archetype = RulerProfile.CONQUEROR
	var rebel := state.create_army(0, 1, 15000)
	rebel.political_person_id = prince
	var crown := state.create_army(0, 0, 1000)
	crown.political_person_id = nation.crown_prince_person_id
	var central := state.create_army(0, 0, 15000)
	central.political_person_id = -1
	check(SuccessionRules.begin_preparation(state, 0, prince), "begin")
	var conflict: SuccessionConflict = state.succession_conflicts[0]
	check(SuccessionRules.launch(state, conflict), "launch")
	var sim := Simulation.new()
	sim.setup(state)
	return {"state": state, "sim": sim, "conflict": conflict, "rebel": rebel, "crown": crown, "central": central}

func run() -> void:
	var x := launched()
	var state: GameState = x.state
	var sim: Simulation = x.sim
	var conflict: SuccessionConflict = x.conflict
	var rebel: Army = x.rebel
	var crown: Army = x.crown
	var neutral_view := AiWorldView.build(state, 0)
	check(neutral_view.enemy_cities.is_empty() and not neutral_view.friendly_armies.has(crown), "normal_ai_excludes_internal_front_and_participants")
	check(not sim._execute_ai_candidate(x.central, ActionCandidate.make(ActionCandidate.Kind.ATTACK, 2000, "neutral", conflict.camp_city_id)), "central_cannot_attack_camp")
	check(state.create_army(conflict.rebel_nation_id, conflict.camp_city_id, 1000) == null, "temporary_identity_no_recruitment")
	check(not state.accept_submission(0, conflict.rebel_nation_id) and not state.annex_nation(0, conflict.rebel_nation_id), "temporary_identity_no_political_absorption")
	check(not bool(UltimatumRules.evaluate(state, 0, conflict.rebel_nation_id).eligible), "temporary_identity_no_ultimatum")
	var original := state.nation_monthly_military_upkeep(0)
	var flows := Simulation.monthly_gold_flows(state)
	check(int(flows[conflict.rebel_nation_id].field_army_upkeep) == 0, "no_duplicate_rebel_upkeep")
	check(original == GameState.army_monthly_upkeep(rebel.size) + GameState.army_monthly_upkeep(crown.size) + GameState.army_monthly_upkeep(x.central.size), "original_pays_all_armies_once")
	state.nations[0].military_payment_ratio = 0.2
	state.refresh_derived()
	check(is_equal_approx(rebel.funding_multiplier, 0.6) and is_equal_approx(crown.funding_multiplier, 0.6), "same_funding")
	check(is_equal_approx(rebel.ruler_attack_multiplier, 5.0), "prince_multiplier_after_refresh")
	var cache := {}
	var inputs := DiplomacyAI._resource_forecast_inputs(state, cache)
	check(int(inputs[0].troops) == rebel.size + crown.size + x.central.size, "forecast_financial_bucket")
	check(int(inputs[conflict.rebel_nation_id].troops) == 0, "forecast_no_duplicate")
	var survivor := state.create_army(0, 2, 1000)
	survivor.political_person_id = conflict.challenger_person_id
	# A real field battle may not be removed by political cleanup.
	var battle := state.new_battle(Battle.Kind.FIELD)
	sim._enter_battle(battle, rebel, 1)
	sim._enter_battle(battle, crown, 2)
	sim._enter_battle(battle, x.central, 2)
	check(not battle.has_army(x.central), "central_cannot_reinforce")
	conflict.pending_outcome = SuccessionConflict.Outcome.SUPPRESSED
	check(not SuccessionRules.finish(state, conflict), "wait_real_field")
	battle.finished = true
	sim._release_army_from_administrative_battle(rebel, battle)
	sim._release_army_from_administrative_battle(crown, battle)
	check(SuccessionRules.finish(state, conflict), "suppression_cleanup")
	check(not bool(PrincePolitics.person(state, 0, conflict.challenger_person_id).alive), "challenger_dead")
	check(survivor.political_person_id == -1, "all_challenger_group_centralized_even_uncommitted")
	check(crown.political_person_id == conflict.crown_person_id and not state.nations[0].succession_competition_closed, "crown_group_survives_suppression")
	check(state.war_relation_ids.is_empty() and state.campaign_fronts.is_empty(), "internal_references_removed")
	sim.free()
	# An external battle is preserved during administrative termination.
	x = launched()
	state = x.state
	sim = x.sim
	conflict = x.conflict
	var enemy := Nation.new()
	enemy.id = state.nations.size()
	state.nations.append(enemy)
	var outsider := Army.new()
	outsider.id = state._next_army_id
	state._next_army_id += 1
	outsider.owner_nation = enemy.id
	outsider.size = 1000
	outsider.location_city = 2
	state.armies.append(outsider)
	battle = state.new_battle(Battle.Kind.FIELD)
	sim._enter_battle(battle, x.rebel, 1)
	sim._enter_battle(battle, outsider, 2)
	check(sim._succession_battle_context(battle) == null, "external_battle_not_internal")
	conflict.pending_outcome = SuccessionConflict.Outcome.ADMINISTRATIVE
	sim._update_succession_conflicts()
	check(not battle.finished and battle.has_army(x.rebel) and x.rebel.battle_id == battle.id, "external_battle_preserved")
	check(x.rebel.owner_nation == 0 and x.rebel.political_person_id == -1, "external_participant_returned_without_reset")
	check(bool(PrincePolitics.person(state, 0, conflict.challenger_person_id).alive), "administrative_no_death")
	sim.free()
	# Accession waits for the internal result, then uses that existing person.
	x = launched()
	state = x.state
	sim = x.sim
	conflict = x.conflict
	state.day = RulerProfile.succession_due_day(state.nations[0], state.world_seed)
	var old := state.nations[0].ruler_person_id
	sim._resolve_ruler_successions()
	check(conflict.succession_delayed and state.nations[0].ruler_person_id == old, "accession_delayed")
	conflict.pending_outcome = SuccessionConflict.Outcome.CROWN_CHANGED
	sim._update_succession_conflicts()
	check(state.nations[0].ruler_person_id == conflict.challenger_person_id and state.nations[0].ruler_started_day == state.day, "actual_accession_date")
	sim.free()
	for failure in failures:
		push_error("SUCCESSION_LIFECYCLE_FAIL: " + failure)
	print("SUCCESSION_LIFECYCLE: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
