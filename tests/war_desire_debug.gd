extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func run() -> void:
	root.size = Vector2i(1280, 720)
	var rules := DiplomacyAI.new()
	check(rules.has_method("war_desire_breakdown"), "diagnostic API exists")
	if not rules.has_method("war_desire_breakdown"):
		finish()
		return
	var state := fixture()
	state.day = 1000
	state.nations[0].strategic_region_anchor_city_id = 5
	state.nations[0].manpower_pool = 1000000
	state.cities[0].food_per_half_year = 100000
	state.cities[0].food_storage = 1000000
	state.cities[0].manpower_per_month = 1000
	state._add_edge(0, 5)
	var score := DiplomacyAI.war_desire(state, 0, 5)
	var cache := {}
	DiplomacyAI.war_desire(state, 0, 5, cache)
	var rng_before := state.rng.state
	var snapshot_before := var_to_bytes(NativeSnapshotBuilder.build(state))
	var report: Dictionary = rules.call("war_desire_breakdown", state, 0, 5, cache)
	check(score != -INF and is_equal_approx(report.score, score), "diagnostic matches actual finite score")
	check(state.rng.state == rng_before, "diagnostic does not consume simulation randomness")
	check(var_to_bytes(NativeSnapshotBuilder.build(state)) == snapshot_before, "diagnostic does not modify persisted simulation state")
	var objective_sum := 0.0
	for term in report.objective.debug_terms.values():
		objective_sum += float(term)
	check(is_equal_approx(objective_sum, float(report.objective.value)), "objective details reconstruct the chosen state value even with a warm normal cache")
	var sum := float(report.positive_total) * float(report.benefit_multiplier) + float(report.aggression_bonus) - float(report.attitude_penalty) - float(report.overextension_penalty)
	check(is_equal_approx(sum, score), "all displayed terms reconstruct actual score")
	var veto: Dictionary = rules.call("war_desire_breakdown", state, 0, 4, cache)
	check(veto.score == -INF and str(veto.blocked_reason).contains("接壤"), "non-border country reports geographic veto")
	state.nations[0].manpower_pool = 0
	veto = rules.call("war_desire_breakdown", state, 0, 5, {})
	check(veto.score == -INF and str(veto.blocked_reason).contains("人力"), "manpower rejection has an explicit reason")
	state.nations[0].manpower_pool = 1000000
	state.set_diplomatic_relation(0, 5, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 5, GameState.DiplomaticRelation.NEUTRAL, 360)
	veto = rules.call("war_desire_breakdown", state, 0, 5, {})
	check(veto.score == -INF and str(veto.blocked_reason).contains("停战"), "truce rejection has an explicit deadline")
	state.day += 360
	state.nations[0].ruler_archetype = RulerProfile.CONQUEROR
	state.nations[0].ruler_revision += 1
	report = rules.call("war_desire_breakdown", state, 0, 5, {})
	check(float(report.benefit_multiplier) == 2.0 and is_equal_approx(report.score, DiplomacyAI.war_desire(state, 0, 5)), "conqueror diagnostic matches doubled benefit")
	state.set_diplomatic_relation(0, 5, GameState.DiplomaticRelation.WAR)
	report = rules.call("war_desire_breakdown", state, 0, 5, cache)
	check(report.score == -INF and not str(report.blocked_reason).is_empty(), "war relation invalidates cached score and explains rejection")
	state.set_diplomatic_relation(0, 5, GameState.DiplomaticRelation.NEUTRAL)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)
	renderer.set_world_layer_visible(false)
	renderer.select_nation(0)
	await process_frame
	await process_frame
	var panel := renderer.detail_panel()
	var section := panel.section("nation.debug_war")
	check(section != null and not section.expanded, "debug defaults collapsed")
	if section != null:
		check(section.body.get_child_count() == 0, "collapsed debug does not construct reports")
		section.set_expanded(true)
		await process_frame
		await process_frame
		var lines := ""
		for label in section.body.get_children():
			lines += str(label.text)
		check(lines.contains("国5") and lines.contains("否决") and lines.contains("君主倍率") and lines.contains("州治价值 金产归一化"), "expanded debug shows targets, vetoes and detailed finite scores")
		for target_id in range(1, 6):
			check(lines.contains("国%d" % target_id), "all living target countries shown: %d" % target_id)
		renderer._cached_selection_detail_payload()
		MapRenderer.reset_nation_detail_section_build_count()
		renderer._cached_selection_detail_payload()
		check(MapRenderer.nation_detail_section_build_count() == 0, "unchanged debug payload reused")
		section.set_expanded(false)
		await process_frame
		await process_frame
		check(section.body.get_child_count() == 0, "collapsing debug discards diagnostic rows")
		section.set_expanded(true)
		await process_frame
		await process_frame
		check(simulation.paused, "debug folding does not change pause state")
		check(panel.scroll.get_v_scroll_bar().max_value > panel.scroll.size.y, "long diagnostics remain scrollable")
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel.get_global_rect()), "debug detail remains inside viewport")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshot="):
				panel.scroll.scroll_vertical = 100000
				await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(arg.trim_prefix("--screenshot=")) == OK, "debug screenshot saved")
		renderer.set_display_state(state, true)
		renderer.select_nation(0)
		await process_frame
		await process_frame
		check(panel.section("nation.debug_war") == null, "historical view does not compute live war desire")
	# A defender's reverse conquest must remove the defeated initiator from ordinary diagnostics.
	check(state.annex_nation(5, 0), "defender actually annexes initiator before diagnostic cleanup")
	simulation._resolve_eliminated_nation_capitulations()
	check(DiplomacyAI.war_desire_debug_lines(state, 0) == ["该国家已灭亡或为继承权临时身份，不评估普通备战"], "eliminated initiator has no ordinary preparation diagnostic")
	var winner_lines := "\n".join(DiplomacyAI.war_desire_debug_lines(state, 5))
	check(not winner_lines.contains("【国0（国0）】"), "surviving defender does not evaluate extinct initiator")
	renderer.free()
	simulation.free()
	finish()

func fixture() -> GameState:
	var state := GameState.new()
	for id in range(6):
		var nation := Nation.new()
		nation.id = id
		nation.name = "国%d" % id
		nation.capital_city_id = id
		state.nations.append(nation)
		var city := City.new()
		city.id = id
		city.name = "州%d" % id
		city.owner_nation = id
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.administrative_center_by_city.append(id)
		state.administrative_center_city_ids.append(id)
		state.region_ids.append(id)
		state.recognized_city_owners.append(id)
	for a in range(6):
		for b in range(a + 1, 6):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	return state

func finish() -> void:
	for failure in failures:
		push_error("WAR_DESIRE_DEBUG_FAIL: " + failure)
	print("WAR_DESIRE_DEBUG: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
