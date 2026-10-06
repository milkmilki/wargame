extends SceneTree

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	var service = load("res://scripts/core/royal_titles.gd")
	if service == null:
		push_error("ROYAL_TITLES_FAIL: title service absent")
		quit(1)
		return
	var state := GameState.new()
	state.generate_grid_world(73002)
	var nation := state.nations[0]
	service.reconcile(state)
	check(service.report(state, 0).basis_points == 0, "country has no virtual stipend")
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	for index in range(land.size()):
		state.region_ids[land[index].id] = 10 if index < land.size() / 2 else 20
	EmpireStatus.reconcile(state)
	var members: Dictionary = FamilyTree.tree_for_nation(state, 0).members
	var count := 0
	var original_titles := {}
	for id in nation.prince_person_ids:
		if id == nation.crown_prince_person_id:
			check(int(members[id].get("title_rank", 0)) == 0, "crown has no stipend")
			continue
		count += 1
		check(members[id].title_rank == 3, "Taizu's non-crown sons receive highest tier")
		check_named_title(members[id])
		original_titles[id] = members[id].current_title
		check(members[id].title_children_generated, "adult family initialized even when childless")
		var children: Array = service.children(members, id)
		check(children.size() in [0, 2, 3, 4, 5], "uniform existing counts plus zero")
		for child in children:
			check(members[child].title_rank == 2 and not members[child].title_adult, "waiting child receives lower tier")
			check_named_title(members[child])
			check(service.children(members, child).is_empty(), "waiting child cannot reproduce")
	check(service.report(state, 0).counts[3] == count, "census includes all adult highest-tier sons")
	var before := state.next_family_person_id
	service.reconcile(state)
	check(state.next_family_person_id == before, "no child reroll on reconciliation")
	var old_adults: Array[int] = nation.prince_person_ids.duplicate()
	var crown := nation.crown_prince_person_id
	check(PrincePolitics.accede(state, 0), "real accession succeeds")
	for id in old_adults:
		if id != crown:
			check(not members[id].alive, "old adult cohort dies with current ruler")
			var living: Array = service.children(members, id).filter(func(child): return bool(members[child].alive))
			if not living.is_empty():
				check(members[living[0]].title_rank == 3, "eldest inherits only after father dies")
				check(members[living[0]].current_title == original_titles[id], "eldest inherits the exact original designation")
	check(nation.empire_founder_person_id != nation.ruler_person_id, "later emperor does not become Taizu")
	for id in nation.prince_person_ids:
		if id != nation.crown_prince_person_id:
			check(members[id].title_rank == 2, "later emperor sons receive middle tier")
			check_named_title(members[id])
	var census: Dictionary = service.report(state, 0)
	check(census.basis_points == census.counts[3] * 30 + census.counts[2] * 20 + census.counts[1] * 10, "basis-point cost uses effective census")
	for failure in failures:
		push_error("ROYAL_TITLES_FAIL: " + failure)
	print("ROYAL_TITLES_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func check_named_title(member: Dictionary) -> void:
	var title := str(member.get("current_title", ""))
	match int(member.title_rank):
		3: check(title in ["晋王", "秦王", "齐王", "楚王", "吴王", "越王", "宋王"], "highest tier uses a Spring and Autumn state designation")
		2: check(title.length() == 3 and title.ends_with("王") and title != "一字王", "middle tier uses two characters plus wang")
		1: check(title.length() == 3 and title.ends_with("国公"), "duke uses one character plus guogong")
