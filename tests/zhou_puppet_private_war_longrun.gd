extends SceneTree
## 真实单国场景：傀儡君主完成分封后，不注入资源、不改藩王原型，
## 继续自然推演两年，验证低凝聚力宗藩能够从正常 AI 链路产生私人战争。

const END_DAY: int = 900


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://zhou_unified.tscn") as PackedScene
	if packed == null:
		push_error("ZHOU_PUPPET_PRIVATE_WAR_SCENE_MISSING")
		quit(1)
		return
	var scenario := packed.instantiate()
	root.add_child(scenario)
	while scenario.state == null:
		await process_frame
	var state: GameState = scenario.state
	scenario.simulation.paused = true
	state.nations[0].ruler_archetype = RulerProfile.PUPPET
	state.nations[0].ruler_traits.clear()
	var initial_core_reached := false
	while state.day < END_DAY:
		scenario.simulation._advance_day(false)
		if state.day == Simulation.DIPLOMACY_DECISION_INTERVAL_DAYS:
			initial_core_reached = (
				state.land_cities_of(0).size()
					== DiplomacyAI.PUPPET_DIRECT_CORE_CITIES
			)
	var private_war_events := 0
	var private_preparations := 0
	var private_cancellations := 0
	var pending_private_preparations := {}
	var cancellation_reasons: Array[String] = []
	var preparation_days: Array[int] = []
	var war_days: Array[int] = []
	for event in state.diplomatic_history:
		var kind := int(event.get("action", -1))
		var nation_a := int(event.get("nation_a", -1))
		var private_scope := (
			int(event.get("war_scope", -1))
				== GameState.WarScope.VASSAL_PRIVATE
		)
		if kind == DiplomacyAI.Action.DECLARE_WAR and private_scope:
			private_war_events += 1
			war_days.append(int(event.get("day", -1)))
			pending_private_preparations.erase(nation_a)
		elif kind == DiplomacyAI.Action.PREPARE_WAR and private_scope:
			private_preparations += 1
			preparation_days.append(int(event.get("day", -1)))
			pending_private_preparations[nation_a] = true
		elif (
			kind == DiplomacyAI.Action.CANCEL_WAR_PREPARATION
			and pending_private_preparations.has(nation_a)
		):
			private_cancellations += 1
			cancellation_reasons.append(str(event.get("reason", "")))
			pending_private_preparations.erase(nation_a)
	var active_private_wars := 0
	var active_preparation_ids: Array[int] = []
	for nation in state.nations:
		if (
			nation.alive
			and nation.war_preparation_target_nation >= 0
			and nation.war_preparation_scope
				== GameState.WarScope.VASSAL_PRIVATE
		):
			active_preparation_ids.append(nation.id)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			if state.is_private_war(nation_a, nation_b):
				active_private_wars += 1
	var ok := (
		initial_core_reached
		and state.suzerainty_cohesion(0)
			< GameState.VASSAL_PRIVATE_WAR_COHESION_THRESHOLD
		and private_war_events >= 3
	)
	print(
		"ZHOU_PUPPET_PRIVATE_WAR_%s day=%d cohesion=%.3f direct=%d subjects=%d preparations=%d wars=%d cancelled=%d pending=%d active=%d prep_days=%s war_days=%s"
		% [
			"OK" if ok else "FAILED",
			state.day,
			state.suzerainty_cohesion(0),
			state.land_cities_of(0).size(),
			state.subjects_of(0).size(),
			private_preparations,
			private_war_events,
			private_cancellations,
			active_preparation_ids.size(),
			active_private_wars,
			str(preparation_days),
			str(war_days),
		]
	)
	if not cancellation_reasons.is_empty():
		print("ZHOU_PUPPET_PRIVATE_WAR_CANCEL_REASONS ", cancellation_reasons)
	for nation_id_value in active_preparation_ids:
		var nation_id := int(nation_id_value)
		var nation := state.nations[nation_id]
		var objective_city := nation.war_preparation_objective_city
		var target_id := nation.war_preparation_target_nation
		var probe_actions: Array[Dictionary] = []
		DiplomacyAI._collect_existing_war_preparation(
			state, nation_id, probe_actions, {}, {}
		)
		print(
			"ZHOU_PUPPET_PRIVATE_WAR_PENDING nation=%d target=%d elapsed=%d troops=%d staged=%d required=%d ready=%s resources=%s groups=%d vassal_ready=%s target_ready=%s route=%s objective_owner=%d probe=%s"
			% [
				nation_id,
				target_id,
				state.day - nation.war_preparation_started_day,
				DiplomacyAI._troop_count(state, nation_id),
				DiplomacyAI.staged_troops_for_objective(
					state, nation_id, objective_city
				),
				DiplomacyAI.required_assault_troops(
					state, nation_id, objective_city
				),
				DiplomacyAI.war_preparation_ready(state, nation_id),
				DiplomacyAI.war_preparation_resources_ready(
					state, nation_id
				),
				nation.battle_groups.size(),
				state.can_vassal_declare_private_war(nation_id),
				state.can_declare_private_war(nation_id, target_id),
				not DiplomacyAI.staging_cities_for_objective(
					state, nation_id, objective_city
				).is_empty(),
				(
					state.cities[objective_city].owner_nation
					if objective_city >= 0 and objective_city < state.cities.size()
					else -1
				),
				str(probe_actions),
			]
		)
	quit(0 if ok else 1)
