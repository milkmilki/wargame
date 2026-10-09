extends SceneTree

var failures: Array[String] = []
func _init() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(24680)
	for a in state.nations:
		for b in state.nations:
			if a.id != b.id:
				state.set_diplomatic_relation(a.id, b.id, GameState.DiplomaticRelation.NEUTRAL)
	state.armies.clear()
	var nation := state.nations[0]
	var center := nation.capital_city_id
	for member in state.administrative_members(center):
		state.cities[member].owner_nation = 0
		state.recognized_city_owners[member] = 0
	state.cities[center].garrison_manpower = 500
	state.cities[center].food_storage = 10000000
	state.refresh_derived()
	return state
func run() -> void:
	var state := fixture()
	var nation := state.nations[0]
	var challenger := nation.prince_person_ids[1]
	PrincePolitics.person(state, 0, challenger).archetype = RulerProfile.CONQUEROR
	var attacker := state.create_army(0, nation.capital_city_id, 15000)
	attacker.political_person_id = challenger
	var crown := state.create_army(0, nation.capital_city_id, 5000)
	crown.political_person_id = nation.crown_prince_person_id
	var central := state.create_army(0, nation.capital_city_id, 15000)
	central.political_person_id = -1
	var info := SuccessionRules.proposal(state, 0, challenger)
	check(not info.is_empty(), "legal_fu_and_force")
	if not info.is_empty():
		check(int(info.V) == 5000, "only_local_crown")
		check(int(info.requirement) == ceili((int(info.R) + 5000) * 0.5), "conqueror_half")
		check(SuccessionRules.begin_preparation(state, 0, challenger), "begin")
		var conflict: SuccessionConflict = state.succession_conflicts[0]
		check(conflict.army_ids == [attacker.id], "only_challenger")
		attacker.location_city = conflict.camp_city_id
		check(SuccessionRules.launch(state, conflict), "launch")
		check(state.cities[conflict.camp_city_id].owner_nation == conflict.rebel_nation_id, "camp_defected")
		check(state.recognized_owner_of(conflict.camp_city_id) == 0, "legal_owner_unchanged")
		check(state.financial_nation_of(attacker.owner_nation) == 0, "same_finance")
		check(not state.armies_hostile(attacker, central), "central_neutral")
		check(state.armies_hostile(attacker, crown), "crown_hostile")
		check(not state.can_declare_war(conflict.rebel_nation_id, 1), "no_external_diplomacy")
		var old_ruler := nation.ruler_person_id
		conflict.pending_outcome = SuccessionConflict.Outcome.CROWN_CHANGED
		check(SuccessionRules.finish(state, conflict), "finish")
		check(nation.crown_prince_person_id == challenger and nation.ruler_person_id == old_ruler, "change_crown_not_emperor")
		check(attacker.owner_nation == 0 and attacker.political_person_id == -1, "army_return")
		check(nation.succession_competition_closed, "competition_closed")
		check(state.cities[conflict.camp_city_id].owner_nation == 0, "camp_restored")
		check(state.succession_conflicts.is_empty(), "context_released")
	for failure in failures:
		push_error("SUCCESSION_CONFLICT_FAIL: " + failure)
	print("SUCCESSION_CONFLICT: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
