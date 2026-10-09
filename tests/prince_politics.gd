extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func run() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(24680)
	var nation := state.nations[0]
	var old_army := state.armies[0]
	var rng_before := state.rng.state
	PrincePolitics.ensure_generation(state, 0)
	var ids := nation.prince_person_ids.duplicate()
	check(ids.size() >= 2 and ids.size() <= 5, "two_to_five")
	check(nation.crown_prince_person_id == ids[0], "first_is_crown")
	check(old_army.political_person_id == -1, "old_armies_unchanged")
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	for id in ids:
		check(int(members[id].parent_id) == nation.ruler_person_id, "real_son")
		check(RulerProfile.is_valid_archetype(int(members[id].archetype)), "profile")
	PrincePolitics.ensure_generation(state, 0)
	check(nation.prince_person_ids == ids, "idempotent")
	check(state.rng.state == rng_before, "independent_rng")
	var counts := {}
	for army_id in range(10000):
		var army := Army.new()
		army.id = army_id
		army.owner_nation = 0
		PrincePolitics.assign_new_army(state, army)
		counts[army.political_person_id] = int(counts.get(army.political_person_id, 0)) + 1
	check(abs(int(counts.get(-1, 0)) - 5000) < 300, "half_central")
	check(int(counts.get(nation.crown_prince_person_id, 0)) > 1000, "fixed_crown_plus_weight")
	var crown := nation.crown_prince_person_id
	var profile: Dictionary = members[crown].duplicate(true)
	old_army.political_person_id = ids[-1]
	state.day = 800
	check(PrincePolitics.accede(state, 0), "accession")
	check(nation.ruler_person_id == crown, "reuse_crown_person")
	check(nation.ruler_name == str(profile.name), "reuse_name")
	check(nation.ruler_archetype == int(profile.archetype), "reuse_archetype")
	check(nation.ruler_traits == profile.traits, "reuse_traits")
	check(old_army.political_person_id == -1, "old_generation_centralized")
	check(nation.ruler_started_day == 800, "actual_accession_day")
	check(nation.prince_person_ids != ids, "new_generation")
	var brother := PrincePolitics.enfeoff_candidate(state, 0)
	if nation.royal_titles_initialized:
		check(not ids.has(brother), "dead_noble_brothers_excluded")
		check(int(members[brother].parent_id) == nation.ruler_person_id, "current_generation_candidate")
	else:
		check(ids.has(brother) and brother != crown, "brothers_first")
		check(int(members[brother].parent_id) == int(members[crown].parent_id), "brother_parent")
	nation.succession_competition_closed = true
	var new_army := Army.new()
	new_army.owner_nation = 0
	PrincePolitics.assign_new_army(state, new_army)
	check(new_army.political_person_id == -1, "closed_generation_central")
	for failure in failures:
		push_error("PRINCE_POLITICS_FAIL: " + failure)
	print("PRINCE_POLITICS: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
