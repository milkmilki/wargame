extends SceneTree
## 真实单国场景：傀儡君主完成分封后自然推演，验证低凝聚力先解锁私战，
## 连续一年后整个宗藩体系统一解体，且新独立国家具备完整政治与粮仓状态。

const END_DAY: int = (
	Simulation.DIPLOMACY_DECISION_INTERVAL_DAYS
	+ GameState.VASSAL_SYSTEM_DISSOLUTION_DAYS
)


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
	if (
		state.nations[0].ruler_archetype != RulerProfile.PUPPET
		or not state.nations[0].ruler_traits.is_empty()
	):
		push_error("ZHOU_SCENE_RULER_NOT_PUPPET")
		quit(1)
		return
	var initial_core_reached := false
	var initial_subject_ids: Array[int] = []
	while state.day < END_DAY:
		scenario.simulation._advance_day(false)
		if state.day == Simulation.DIPLOMACY_DECISION_INTERVAL_DAYS:
			initial_core_reached = (
				state.land_cities_of(0).size()
					== DiplomacyAI.PUPPET_DIRECT_CORE_CITIES
				and state.suzerainty_cohesion(0)
					< GameState.VASSAL_PRIVATE_WAR_COHESION_THRESHOLD
				and state.suzerainty_dissolution_days_remaining(0)
					== GameState.VASSAL_SYSTEM_DISSOLUTION_DAYS
			)
			initial_subject_ids = state.suzerainty_members(0)
			initial_subject_ids.erase(0)
	var private_war_events := 0
	var dissolution_day := -1
	var dissolved_members: Array[int] = []
	for event in state.diplomatic_history:
		if str(event.get("kind", "")) == "suzerainty_dissolved":
			dissolution_day = int(event.get("day", -1))
			dissolved_members.assign(event.get("member_nations", []))
			continue
		if (
			int(event.get("action", -1)) == DiplomacyAI.Action.DECLARE_WAR
			and int(event.get("war_scope", -1))
				== GameState.WarScope.VASSAL_PRIVATE
		):
			private_war_events += 1
	var surviving_subjects_promoted := true
	var independent_warehouses_ready := true
	for subject_id in initial_subject_ids:
		if subject_id < 0 or subject_id >= state.nations.size():
			continue
		var nation := state.nations[subject_id]
		if not nation.alive:
			continue
		surviving_subjects_promoted = (
			surviving_subjects_promoted
			and nation.name_kind != WorldNaming.KIND_VASSAL
		)
		independent_warehouses_ready = (
			independent_warehouses_ready
			and nation.capital_city_id >= 0
			and nation.capital_city_id in nation.warehouse_city_ids
		)
	var no_private_war_state := true
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			no_private_war_state = (
				no_private_war_state
				and not state.is_private_war(nation_a, nation_b)
			)
	var dissolved_alliance_complete := true
	for first_index in range(dissolved_members.size()):
		for second_index in range(first_index + 1, dissolved_members.size()):
			dissolved_alliance_complete = (
				dissolved_alliance_complete
				and state.is_allied(
					dissolved_members[first_index],
					dissolved_members[second_index]
				)
			)
	var expected_dissolution_day := (
		Simulation.DIPLOMACY_DECISION_INTERVAL_DAYS
		+ GameState.VASSAL_SYSTEM_DISSOLUTION_DAYS
	)
	var surviving_nations := 0
	for nation in state.nations:
		if nation.alive:
			surviving_nations += 1
	var ok := (
		initial_core_reached
		and not initial_subject_ids.is_empty()
		and private_war_events >= 1
		and dissolution_day == expected_dissolution_day
		and dissolved_members.size() >= 2
		and dissolved_members.size() <= initial_subject_ids.size() + 1
		and state.suzerainty.is_empty()
		and state.suzerainty_low_cohesion_since_day.is_empty()
		and surviving_subjects_promoted
		and independent_warehouses_ready
		and no_private_war_state
		and dissolved_alliance_complete
		and state.suzerainty_structure_valid()
	)
	print(
		"ZHOU_SUZERAINTY_DISSOLUTION_%s day=%d expected=%d initial_subjects=%d members=%d private_wars=%d surviving=%d"
		% [
			"OK" if ok else "FAILED",
			dissolution_day,
			expected_dissolution_day,
			initial_subject_ids.size(),
			dissolved_members.size(),
			private_war_events,
			surviving_nations,
		]
	)
	quit(0 if ok else 1)
