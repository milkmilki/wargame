extends SceneTree

const TIMEOUT_MSEC: int = 30000


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://zhou_unified.tscn") as PackedScene
	if packed == null:
		push_error("ZHOU_UNIFIED_SCENE_MISSING")
		quit(1)
		return
	var scenario := packed.instantiate()
	root.add_child(scenario)
	var started := Time.get_ticks_msec()
	while scenario.state == null:
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			push_error("ZHOU_UNIFIED_SCENE_TIMEOUT")
			quit(1)
			return
		await process_frame
	var state: GameState = scenario.state
	scenario.simulation.paused = true
	var all_controlled := true
	var all_recognized := true
	for city in state.cities:
		if city.politically_active:
			all_controlled = all_controlled and city.owner_nation == 0
			all_recognized = (
				all_recognized and state.recognized_owner_of(city.id) == 0
			)
	var ok := (
		int(scenario.nation_count) == 1
		and str(scenario.initial_single_nation_name) == "周"
		and int(scenario.initial_single_nation_ruler_archetype)
			== RulerProfile.PUPPET
		and state.nations.size() == 1
		and state.land_cities().size() == GameState.TERRAIN_CITY_COUNT
		and WorldNaming.nation_display_name(state, 0) == "周"
		and state.nations[0].short_name == "周"
		and state.nations[0].name_kind == WorldNaming.KIND_DYNASTY
		and state.nations[0].ruler_archetype == RulerProfile.PUPPET
		and state.nations[0].ruler_traits.is_empty()
		and all_controlled
		and all_recognized
	)
	var enfeoff_started := Time.get_ticks_msec()
	while state.day < Simulation.DIPLOMACY_DECISION_INTERVAL_DAYS:
		await scenario.simulation._advance_day(true)
	var enfeoff_msec := Time.get_ticks_msec() - enfeoff_started
	var direct_cities := state.land_cities_of(0).size()
	var subjects := state.subjects_of(0).size()
	var private_capable := 0
	var private_bordering := 0
	var private_resource_ready := 0
	var finite_private_desire := 0
	var declared_private_desire := 0
	var best_private_desire := -INF
	var private_cache := {}
	for subject_id in state.subjects_of(0):
		if state.can_vassal_declare_private_war(subject_id):
			private_capable += 1
		var targets := DiplomacyAI._direct_bordering_nation_ids(
			state, subject_id, private_cache
		)
		if not targets.is_empty():
			private_bordering += 1
		var report := DiplomacyAI.resource_report(
			state, subject_id, private_cache
		)
		if DiplomacyAI.offensive_resources_ready(state, subject_id, report):
			private_resource_ready += 1
		for target_id in targets:
			if not state.can_declare_private_war(subject_id, target_id):
				continue
			var desire := DiplomacyAI.war_desire(
				state, subject_id, target_id, private_cache, true
			)
			if desire > -INF:
				finite_private_desire += 1
				best_private_desire = maxf(best_private_desire, desire)
				if desire >= DiplomacyAI.WAR_DECLARE_SCORE:
					declared_private_desire += 1
	var followup_actions := DiplomacyAI.choose_actions(state)
	var private_preparations := 0
	for action in followup_actions:
		if (
			int(action.get("kind", -1)) == DiplomacyAI.Action.PREPARE_WAR
			and int(action.get("war_scope", -1))
				== GameState.WarScope.VASSAL_PRIVATE
		):
			private_preparations += 1
	ok = (
		ok
		and direct_cities == DiplomacyAI.PUPPET_DIRECT_CORE_CITIES
		and subjects >= 2
		and state.suzerainty_cohesion(0)
			< GameState.VASSAL_PRIVATE_WAR_COHESION_THRESHOLD
		and private_capable > 0
	)
	print("ZHOU_UNIFIED_SCENE_%s cities=%d nations=%d name=%s" % [
		"OK" if ok else "FAILED",
		state.land_cities().size(),
		state.nations.size(),
		WorldNaming.nation_display_name(state, 0),
	])
	print("ZHOU_PUPPET_ENFEOFF direct=%d subjects=%d day=%d elapsed_ms=%d" % [
		direct_cities,
		subjects,
		state.day,
		enfeoff_msec,
	])
	print("ZHOU_VASSAL_PRIVATE_WAR cohesion=%.3f capable=%d bordering=%d resources=%d finite=%d willing=%d preparations=%d best=%.2f" % [
		state.suzerainty_cohesion(0),
		private_capable,
		private_bordering,
		private_resource_ready,
		finite_private_desire,
		declared_private_desire,
		private_preparations,
		best_private_desire,
	])
	quit(0 if ok else 1)
