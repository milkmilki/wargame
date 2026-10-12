extends SceneTree
## Observation only: no manufactured princes, wars, territory or ruler profiles.
const Inputs = preload("res://tests/atlas_military_inputs.gd")
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
var rows := []
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func diagnose(state: GameState) -> Dictionary:
	var counts := {}
	var samples := []
	var cache := {}
	for nation in state.nations:
		if not nation.alive or nation.ruler_archetype == RulerProfile.PUPPET: continue
		var id := nation.id
		var reason := "eligible"
		var detail := {"nation":id,"ruler":nation.ruler_archetype,"cities":state.land_cities_of(id).size()}
		if PrincePolitics.enfeoff_candidate(state,id,false) < 0: reason="no_prince"
		elif state.is_vassal(id): reason="already_vassal"
		elif nation.war_preparation_target_nation >= 0: reason="preparing_war"
		elif DiplomacyAI._overlord_under_war_pressure(state,id,cache): reason="war_pressure"
		else:
			var region := DiplomacyAI.next_enfeoff_region(state,id,DiplomacyAI.ENFEOFF_MIN_OVERLORD_CITIES_AFTER,DiplomacyAI.ENFEOFF_MAX_REGION_CITIES,true,cache)
			detail.region = region
			if region.is_empty(): reason="no_complete_region_or_core"
			else:
				var hops := state.capital_hop_distances(id)
				var burden := DiplomacyAI.evaluate_region_burden(state,id,region,hops)
				var governance := DiplomacyAI.evaluate_region_governance_pressure(state,id,region,hops)
				var tendency := maxf(RulerProfile.enfeoff_multiplier(nation),0.)
				detail.fiscal = int(round(float(burden.garrison_gold_upkeep)*tendency))+int(burden.projected_tribute_income)-int(burden.direct_gold_income)
				detail.food = float(burden.burden_ratio)*tendency
				detail.governance = float(governance.pressure_score)*tendency
				if detail.fiscal<=0 and detail.food<DiplomacyAI.ENFEOFF_FOOD_BURDEN_RATIO_THRESHOLD and (int(governance.pressured_city_count)<1 or detail.governance<DiplomacyAI.ENFEOFF_GOVERNANCE_PRESSURE_THRESHOLD): reason="benefit_below_threshold"
		counts[reason] = int(counts.get(reason,0))+1
		detail.reason = reason
		samples.append(detail)
	return {"day":state.day,"counts":counts,"nations":samples}

func run() -> void:
	var state := GameState.new()
	var payload := Inputs.eurasia_military()
	state.generate_from_atlas(payload)
	var sim := Simulation.new(); sim.setup(state)
	assert(state.world_seed==1 and state.nations.size()==40 and payload.data.options.settlement_mask==Mask.EURASIA)
	var hashes := {}
	for path in ["scripts/ai/diplomacy_ai.gd","scripts/simulation/simulation.gd","scripts/state/game_state.gd","scripts/model/army.gd","scripts/core/combat.gd","scripts/core/prince_politics.gd","tests/atlas_ordinary_enfeoff.gd"]: hashes[path]=FileAccess.get_sha256("res://"+path)
	var before_rng := state.rng.state
	rows.append(diagnose(state)); assert(state.rng.state==before_rng)
	var events := []
	var seen := 0
	var stop_after_first := true
	var limit := 2160
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--days="): limit=int(argument.get_slice("=",1))
	while state.day<limit:
		sim._advance_day()
		if not state.territory_structure_valid() or not state.suzerainty_structure_error().is_empty() or not state._battle_group_structure_valid():
			failures.append("structural failure day %d"%state.day); break
		for index in range(seen,state.diplomatic_history.size()):
			var event: Dictionary=state.diplomatic_history[index]
			if int(event.get("action",-1))==DiplomacyAI.Action.ENFEOFF:
				var copy := event.duplicate(true)
				copy.overlord_name=state.nation_display_name(int(event.nation_a))
				copy.subject_name=state.nation_display_name(int(event.subject_nation))
				copy.subject_cities=state.land_cities_of(int(event.subject_nation)).map(func(c): return c.id)
				events.append(copy)
		seen=state.diplomatic_history.size()
		if state.day%30==0:
			before_rng=state.rng.state; rows.append(diagnose(state)); assert(state.rng.state==before_rng)
		if events.any(func(e): return int(e.ruler_archetype)!=RulerProfile.PUPPET) and stop_after_first: break
		if state.day%120==0:
			print("ORDINARY_ENFEOFF_PROGRESS day=",state.day," grants=",events.size());await process_frame
	var report := {"pid":OS.get_process_id(),"seed":state.world_seed,"mask":Mask.EURASIA,"trade":state.trade_enabled,"rulers":state.random_ruler_profiles_enabled(),"day":state.day,"requested_limit":limit,"stop_after_first_ordinary":stop_after_first,"source_hashes":hashes,"monthly_gates":rows,"events":events,"failures":failures}
	FileAccess.open("res://.dbg/atlas-ordinary-enfeoff.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ORDINARY_ENFEOFF_RESULT pid=%d day=%d grants=%d ordinary=%d failures=%d"%[OS.get_process_id(),state.day,events.size(),events.filter(func(e): return int(e.ruler_archetype)!=RulerProfile.PUPPET).size(),failures.size()])
	sim.free();quit(0 if failures.is_empty() else 1)
