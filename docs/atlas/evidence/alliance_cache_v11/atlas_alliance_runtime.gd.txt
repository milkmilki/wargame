extends SceneTree
## The same native Eurasia input, original query versus shared topology,
## including frame-sliced readers and a genuine succession conflict.
const Legacy = preload("res://tests/support/legacy_alliance_state.gd")
func _initialize(): call_deferred("run")
func run():
	var payload: Dictionary = preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	var options: Dictionary = payload.get("simulation_options", {})
	var a := Legacy.new(); a.generate_from_atlas(payload.duplicate(true))
	var b := GameState.new(); b.generate_from_atlas(payload.duplicate(true))
	var before := Simulation.new(); root.add_child(before); before.setup(a); before.paused = true
	var after := Simulation.new(); root.add_child(after); after.setup(b); after.paused = true
	var log := DebugRunLog.new(); log.begin("tests/atlas_alliance_runtime.gd")
	log.world_started(b, {"days": 65, "settlement_mask": payload.data.options.settlement_mask,
		"simulation_options": options}, "alliance_runtime")
	for day in range(60):
		before._advance_day(false); after._advance_day(false)
		if a.day % 15 == 0: print("ATLAS_ALLIANCE_RUNTIME_WARM ", a.day); await process_frame
	var same := var_to_bytes(NativeSnapshotBuilder.build(a)) == var_to_bytes(NativeSnapshotBuilder.build(b))
	var seeded_war := false
	# Older default policies may still be peaceful at day60. Use a genuine
	# territorial contact and the public relationship transaction to exercise
	# a warm-cache invalidation, rather than passing without an external war.
	if b.coalition_campaign_components().is_empty():
		for contact in b.territorial_border_pairs():
			var owner_a := b.cities[contact.x].owner_nation
			var owner_b := b.cities[contact.y].owner_nation
			if owner_a < 0 or owner_b < 0 or owner_a == owner_b or b.is_allied(owner_a, owner_b): continue
			if not b.nations[owner_a].alive or not b.nations[owner_b].alive: continue
			a.set_diplomatic_relation(owner_a, owner_b, GameState.DiplomaticRelation.WAR)
			b.set_diplomatic_relation(owner_a, owner_b, GameState.DiplomaticRelation.WAR)
			before._ai_last_decision_day = -1; after._ai_last_decision_day = -1
			seeded_war = true
			break
	var exercised_war := not b.coalition_campaign_components().is_empty()
	var exercised_succession := not b.succession_conflicts.is_empty()
	for day in range(5):
		before._advance_day(false); await after.advance_one_day()
		same = same and var_to_bytes(NativeSnapshotBuilder.build(a)) == var_to_bytes(NativeSnapshotBuilder.build(b))
		exercised_war = exercised_war or not b.coalition_campaign_components().is_empty()
		exercised_succession = exercised_succession or not b.succession_conflicts.is_empty()
		log.checkpoint(b)
		print("ATLAS_ALLIANCE_RUNTIME_DAY ", b.day, " equivalent=", same)
	print("ATLAS_ALLIANCE_RUNTIME_RESULT pid=", OS.get_process_id(), " day=", b.day,
		" equivalent=", same, " war=", exercised_war, " succession=", exercised_succession, " seeded_war=", seeded_war)
	if not same: printerr("ATLAS_ALLIANCE_RUNTIME_FAIL complete daily state differs")
	var required_contexts := exercised_war and (exercised_succession or not bool(options.get("rulers_enabled", false)))
	if not required_contexts: printerr("ATLAS_ALLIANCE_RUNTIME_FAIL required contexts absent")
	before.free(); after.free(); quit(0 if same and required_contexts else 1)
