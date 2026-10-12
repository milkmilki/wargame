extends SceneTree
## Exercise the default Eurasia cache in the real frame-sliced daily entry.
const MAX_WARMUP_DAYS := Simulation.DAYS_PER_YEAR
const RUNTIME_DAYS := 5

func active_coalition_fronts(state: GameState) -> int:
	var armies := {}
	for army in state.armies: armies[army.id] = army
	var count := 0
	for front: CoalitionCampaignFront in state.campaign_fronts.values():
		if front.retiring or front.war_id < 0 or front.participant_nation_ids.size() < 2:
			continue
		if front.campaign_pair_id < 0 or not state.campaign_pairs.has(front.campaign_pair_id):
			continue
		for army_id in front.army_assignments:
			var army: Army = armies.get(army_id)
			if army != null and army.size > 0 and army.campaign_front_id == front.front_id and front.participant_nation_ids.has(army.owner_nation):
				count += 1
				break
	return count

func _initialize(): call_deferred("run")
func run():
	var payload: Dictionary = preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	var a := GameState.new(); a.generate_from_atlas(payload.duplicate(true))
	var b := GameState.new(); b.generate_from_atlas(payload.duplicate(true))
	var before := Simulation.new(); root.add_child(before); before.setup(a); before.paused = true
	before.ai_coalition_component_cache_disabled = true
	var after := Simulation.new(); root.add_child(after); after.setup(b); after.paused = true
	var log := DebugRunLog.new(); log.begin("tests/atlas_coalition_runtime.gd")
	log.world_started(b, {"max_warmup_days": MAX_WARMUP_DAYS, "runtime_days": RUNTIME_DAYS, "settlement_mask": payload.data.options.settlement_mask,
		"simulation_options": payload.simulation_options}, "coalition_runtime")
	# Natural declarations require MIN_NEUTRAL_DAYS (currently 90) before
	# preparation can finish. Wait for an actual armed multi-nation front rather
	# than assuming that the peaceful day-60 world contains a campaign.
	while b.day < MAX_WARMUP_DAYS and active_coalition_fronts(b) == 0:
		before._advance_day(false); after._advance_day(false)
		if a.day % 15 == 0: print("ATLAS_COALITION_RUNTIME_WARM ", a.day); await process_frame
	var same := var_to_bytes(NativeSnapshotBuilder.build(a)) == var_to_bytes(NativeSnapshotBuilder.build(b))
	var started_with_active_campaign := active_coalition_fronts(b) > 0
	var active_runtime_days := 0
	print("ATLAS_COALITION_RUNTIME_START day=", b.day, " active_coalition_fronts=", active_coalition_fronts(b))
	for day in range(RUNTIME_DAYS):
		before._advance_day(false); await after.advance_one_day()
		same = same and var_to_bytes(NativeSnapshotBuilder.build(a)) == var_to_bytes(NativeSnapshotBuilder.build(b))
		var active_fronts := active_coalition_fronts(b)
		if active_fronts > 0: active_runtime_days += 1
		log.checkpoint(b)
		print("ATLAS_COALITION_RUNTIME_DAY ", b.day, " equivalent=", same, " active_coalition_fronts=", active_fronts)
	var exercised_war := started_with_active_campaign and active_runtime_days > 0
	print("ATLAS_COALITION_RUNTIME_RESULT pid=", OS.get_process_id(), " day=", b.day,
		" equivalent=", same, " war=", exercised_war, " active_runtime_days=", active_runtime_days)
	if not same: printerr("ATLAS_COALITION_RUNTIME_FAIL complete daily state differs")
	if not exercised_war: printerr("ATLAS_COALITION_RUNTIME_FAIL no active campaign tested")
	before.free(); after.free(); quit(0 if same and exercised_war else 1)
