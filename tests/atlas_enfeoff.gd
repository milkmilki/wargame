extends SceneTree
## Default Eurasia: real grant transaction plus unforced AI observation.
const Inputs = preload("res://tests/atlas_military_inputs.gd")
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
var checks := 0
var failures: Array[String] = []
var report := {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var payload := Inputs.eurasia_military()
	check(payload.data.options.settlement_mask == Mask.EURASIA, "actual regional input")
	var state := GameState.new()
	state.generate_from_atlas(payload)
	var sim := Simulation.new()
	sim.setup(state)
	check(state.world_seed == 1 and state.nations.size() == 40 and state.trade_enabled and state.random_ruler_profiles_enabled(), "default seed/countries/trade/rulers")
	check(sim.enfeoff_enabled and sim.diplomacy_enabled, "runtime enfeoffment and diplomacy enabled")
	report = {"pid":OS.get_process_id(),"seed":state.world_seed,"mask":Mask.EURASIA,"initial_nations":state.nations.size(),"nodes":state.cities.size(),"settlements":state.land_cities().size(),"trade":state.trade_enabled,"rulers":state.random_ruler_profiles_enabled()}
	var candidate_count := 0
	for nation in state.nations:
		if PrincePolitics.enfeoff_candidate(state,nation.id,false) >= 0:
			candidate_count += 1
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(state,actions,{}, {})
	report.initial_candidate_nations = candidate_count
	report.initial_ai_actions = actions.duplicate(true)
	# Separate fresh world: request a legal grant through the simulation executor,
	# without creating people, changing rulers, or moving any initial territory.
	test_transaction(payload)
	for day in range(365):
		sim._advance_day()
		check(state.territory_structure_valid(), "natural territory day %d" % state.day)
		check(state.suzerainty_structure_error().is_empty(), "natural vassal structure day %d" % state.day)
		check(state._battle_group_structure_valid(), "natural army commands day %d" % state.day)
		if not failures.is_empty(): break
		if state.day % 120 == 0:
			print("ATLAS_ENFEOFF_PROGRESS day=",state.day)
			await process_frame
	var grants := []
	for event in state.diplomatic_history:
		if int(event.get("action",-1)) == DiplomacyAI.Action.ENFEOFF:
			grants.append(event.duplicate(true))
	report.natural_day = state.day
	report.natural_grants = grants
	report.final_vassals = state.suzerainty.duplicate(true)
	report.final_nations = state.nations.size()
	report.checks = checks
	report.failures = failures
	var hashes := {}
	for path in ["scripts/state/game_state.gd","scripts/simulation/simulation.gd","scripts/ai/diplomacy_ai.gd","scripts/core/prince_politics.gd","scripts/core/family_tree.gd","tests/atlas_enfeoff.gd"]:
		hashes[path] = FileAccess.get_sha256("res://"+path)
	report.source_hashes = hashes
	FileAccess.open("res://.dbg/atlas-enfeoff-check.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ATLAS_ENFEOFF_RESULT pid=%d day=%d initial_candidates=%d initial_actions=%d natural_grants=%d checks=%d failures=%d" % [OS.get_process_id(),state.day,candidate_count,actions.size(),grants.size(),checks,failures.size()])
	sim.free()
	quit(0 if failures.is_empty() else 1)

func test_transaction(payload: Dictionary) -> void:
	var state := GameState.new()
	state.generate_from_atlas(payload)
	var sim := Simulation.new()
	sim.setup(state)
	var selected := -1
	var region: Array[int] = []
	for nation in state.nations:
		if PrincePolitics.enfeoff_candidate(state,nation.id,false) < 0: continue
		for center in state.administrative_center_city_ids:
			var candidate := state.normalize_enfeoff_region(nation.id,[center] as Array[int])
			if not candidate.is_empty() and state._can_enfeoff(nation.id,candidate):
				selected = nation.id
				region = candidate
				break
		if selected >= 0: break
	check(selected >= 0, "default map has a real prince and a legal complete fief")
	if selected < 0:
		sim.free()
		return
	var prince := PrincePolitics.enfeoff_candidate(state,selected,false)
	var original_capital := state.nations[selected].capital_city_id
	var original_nations := state.nations.size()
	var gold := state.nations[selected].treasury_gold
	var manpower := state.nations[selected].manpower_pool
	var food := state.nations[selected].granary_food
	var army_owners := {}
	for army in state.armies: army_owners[army.id] = army.owner_nation
	var action := {"kind":DiplomacyAI.Action.ENFEOFF,"a":selected,"b":selected,"region_cities":region,"reason":"Atlas legal grant test (requested, not natural AI)"}
	check(sim._execute_diplomatic_action(action), "real simulation grant commits")
	var subject := int(action.get("subject_nation",-1))
	check(subject == original_nations and state.nations.size() == original_nations+1, "one real subject nation created")
	if subject < 0:
		sim.free()
		return
	check(state.overlord_of(subject) == selected and state.nations[subject].ruler_person_id == prince, "existing prince becomes actual vassal ruler")
	check(state.nations[selected].capital_city_id == original_capital and state.cities[original_capital].owner_nation == selected, "overlord retains capital")
	for city_id in region:
		check(state.cities[city_id].owner_nation == subject and state.recognized_owner_of(city_id) == subject, "control and legal fief transferred together")
		var center := state.administrative_center_of(city_id)
		check(region.has(center), "grant retains complete fixed administrative state")
	check(state.nations[selected].treasury_gold+state.nations[subject].treasury_gold == gold, "grant conserves treasury")
	check(state.nations[selected].manpower_pool+state.nations[subject].manpower_pool == manpower, "grant conserves manpower")
	check(state.nations[selected].granary_food == food and state.nations[subject].granary_food == 0, "food remains in shared root stock")
	check(state.armies.size() == army_owners.size(), "grant does not create free armies")
	for army in state.armies: check(army.owner_nation == army_owners[army.id], "standing armies retain their owners")
	check(state.relation_between(selected,subject) == GameState.DiplomaticRelation.ALLIED, "peaceful vassal and overlord are allied")
	check(state.suzerainty_structure_error().is_empty() and state.territory_structure_valid() and state._battle_group_structure_valid(), "grant maintains all structural invariants")
	check(not state.diplomatic_history.is_empty() and int(state.diplomatic_history.back().get("subject_nation",-1)) == subject, "real diplomacy event records new subject")
	report.requested_grant = {"overlord":selected,"overlord_name":state.nation_display_name(selected),"subject":subject,"subject_name":state.nation_display_name(subject),"prince":prince,"region_cities":region,"subject_capital":state.nations[subject].capital_city_id,"natural":false}
	print("ATLAS_REQUESTED_GRANT ",report.requested_grant)
	sim.free()
