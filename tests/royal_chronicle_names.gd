extends SceneTree

const Chain = preload("res://tests/succession_chain.gd")
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func rebellion(titles: bool, restored: bool = false) -> Dictionary:
	var state: GameState = Chain.fixture()
	var nation := state.nations[0]
	if titles:
		nation.state_level = EmpireStatus.EMPIRE
		nation.empire_founder_person_id = nation.ruler_person_id
		nation.royal_titles_initialized = true
		RoyalTitles.grant_generation(state, 0)
	var challenger := nation.prince_person_ids[1]
	var member := PrincePolitics.person(state, 0, challenger)
	member.archetype = RulerProfile.CONQUEROR
	if titles:
		RoyalTitles.set_member(state, member, "virtual_title_name", "晋王")
		RoyalTitles.set_member(state, member, "current_title", "晋王")
	var crown_member := PrincePolitics.person(state, 0, nation.crown_prince_person_id)
	if restored:
		RoyalTitles.set_member(state, crown_member, "virtual_title_name", "秦王")
		RoyalTitles.set_member(state, crown_member, "current_title", "秦王")
	var rebel := state.create_army(0, 1, 15000)
	rebel.political_person_id = challenger
	var crown := state.create_army(0, 0, 1000)
	crown.political_person_id = nation.crown_prince_person_id
	check(SuccessionRules.begin_preparation(state, 0, challenger), "real preparation")
	var conflict: SuccessionConflict = state.succession_conflicts[0]
	check(SuccessionRules.launch(state, conflict), "real launch")
	var sim := Simulation.new()
	sim.setup(state)
	return {"state": state, "sim": sim, "conflict": conflict, "rebel": rebel,
		"challenger": member, "old_crown": crown_member}

func run() -> void:
	var submitted := GameState.new()
	submitted.generate_grid_world(94601)
	for a in range(submitted.nations.size()):
		for b in range(a + 1, submitted.nations.size()):
			submitted.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var subject := submitted.nations[1]
	subject.name = "长"
	subject.short_name = "长"
	submitted.nations[2].name = "长王"
	submitted.nations[2].short_name = "长王"
	submitted.nations[2].alive = false
	var ruler_id := subject.ruler_person_id
	var ruler_name := subject.ruler_name
	var random_before := submitted.rng.state
	check(submitted.accept_submission(0, 1), "actual submission transaction")
	check(subject.name == "长王" and WorldNaming.nation_display_name(submitted, 1) == "长王", "archived name collision never adds numbers to submission title")
	check(subject.ruler_person_id == ruler_id and subject.ruler_name == ruler_name, "submission preserves ruler identity")
	check(PrincePolitics.person(submitted, 1, ruler_id).current_title == "长王", "family tree records the unnumbered real title")
	check(WorldNaming.assign_submitted_vassal_name(submitted, 1) == "长王", "repeated naming is stable")
	check(submitted.rng.state == random_before, "naming and submission do not consume simulation randomness")
	for restored in [false, true]:
		var x := rebellion(true, restored)
		var before_name: String = x.challenger.name
		var old_name: String = x.old_crown.name
		x.sim._capture_city(x.rebel, x.state.cities[0])
		x.sim._update_succession_conflicts()
		var event: Dictionary = x.state.chronicle_events.back()
		var final_title: String = x.old_crown.current_title
		check(str(event.text).contains("晋王" + before_name + "兵变") and not str(event.text).contains("皇子"), "success uses the original concrete title instead of generic prince")
		check(str(event.text).contains("废皇太子" + old_name) and str(event.text).contains("改立" + before_name + "为皇太子"), "success records both deposition and new crown")
		check(RoyalTitles.effective_rank(x.state, x.old_crown) == RoyalTitles.PRINCE and str(event.text).contains(final_title), "chronicle records the actual post-settlement grant")
		check(event.get("challenger_title", "") == "晋王" and event.get("former_crown", {}).get("title", "") == final_title, "historical structured title data is frozen")
		check(event.get("former_crown", {}).get("status", "") == ("retained"), "deposition retains the same title")
		check(str(event.text).contains("仍为"), "grant status is readable in the chronicle")
		var text_before: String = event.text
		x.old_crown.current_title = "其他封号"
		x.challenger.current_title = "无爵"
		x.old_crown.name = "后改姓名"
		x.sim._update_succession_conflicts()
		check(event.text == text_before and event.get("former_crown", {}).get("title", "") == final_title and x.state.chronicle_events.size() == 1, "later title changes never rewrite or duplicate the political event")
		x.sim.free()
	var ordinary := rebellion(false)
	ordinary.sim._capture_city(ordinary.rebel, ordinary.state.cities[0])
	ordinary.sim._update_succession_conflicts()
	var no_grant: Dictionary = ordinary.state.chronicle_events.back()
	check(str(no_grant.text).contains("无爵宗室" + str(ordinary.challenger.name) + "兵变"), "untitled challenger is identified without inventing a title")
	check(str(no_grant.text).contains("未授爵") and no_grant.get("former_crown", {}).get("status", "") == "untitled", "non-empire records no grant to former crown")
	ordinary.sim.free()
	for reason in ["field_defeat", "no_progress", ""]:
		var lost := rebellion(true)
		var original_name: String = lost.challenger.name
		SuccessionRules.fail(lost.state, lost.conflict, reason)
		lost.sim._update_succession_conflicts()
		var event: Dictionary = lost.state.chronicle_events.back()
		check(str(event.text).contains("晋王" + original_name + "兵变") and not bool(lost.challenger.alive), "failure retains the pre-death title")
		check(not str(event.text).contains("废皇太子") and event.get("former_crown", {}).is_empty(), "failed revolt never invents a crown deposition")
		lost.sim.free()
	var stopped := rebellion(true)
	stopped.conflict.pending_outcome = SuccessionConflict.Outcome.ADMINISTRATIVE
	stopped.sim._update_succession_conflicts()
	check(str(stopped.state.chronicle_events.back().text).contains("外部干扰") and bool(stopped.challenger.alive), "administrative termination is described as interruption")
	stopped.sim.free()
	for failure in failures: push_error("ROYAL_CHRONICLE_NAMES_FAIL: " + failure)
	print("ROYAL_CHRONICLE_NAMES_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
