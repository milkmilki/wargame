extends SceneTree
func _initialize(): call_deferred("run")
func snapshot(state: GameState) -> Array:
	var armies:=NativeSnapshotBuilder._build_armies(state)
	var edges:=NativeSnapshotBuilder._build_edges(state)
	return [state.day,state.rng.state,state.diplomatic_relations,state.war_relation_ids,
		NativeSnapshotBuilder._build_nations(state),state.nations.map(func(n):return [n.name,n.short_name,n.environment_kind,n.state_level]),armies.snapshot,
		NativeSnapshotBuilder._build_battles(state,edges.indices,armies.indices),NativeSnapshotBuilder._build_campaign_fronts(state),
		NativeSnapshotBuilder._build_campaign_pairs(state),state.campaign_raid_records,
		state.nations.map(func(n):return n.battle_groups.map(func(g):return [g.id,g.reserve_target_city])),
		state.cities.map(func(c):return [c.owner_nation,state.recognized_owner_of(c.id),c.occupation_sponsor_nation,c.food_storage,c.garrison_manpower,c.garrison_supply_ratio]),
		state.armies.map(func(a):return a.route_origin_city_id),state.suzerainty]
func run():
	var days:=365
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--days="):days=int(argument.get_slice("=",1))
	var payload=preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	var first:=GameState.new(); first.generate_from_atlas(payload.duplicate(true))
	var second:=GameState.new(); second.generate_from_atlas(payload.duplicate(true))
	var log := DebugRunLog.new(); log.begin("tests/atlas_runtime_equivalence.gd"); log.world_started(first,{"days":days,"model":payload.model},"atlas_runtime_equivalence")
	print("FORCE_EQ seed=",first.world_seed," nations=",first.nations.size()," nodes=",first.cities.size())
	var sync:=Simulation.new(); root.add_child(sync); sync.setup(first); sync.paused=true
	var sliced:=Simulation.new(); root.add_child(sliced); sliced.setup(second); sliced.paused=true; sliced.runtime_stage_profiling_enabled=true
	for i in range(days):
		sync._advance_day()
		await sliced.advance_one_day()
		if snapshot(first)!=snapshot(second):
			FileAccess.open("res://.dbg/campaign-eq-sync.json",FileAccess.WRITE).store_string(JSON.stringify(snapshot(first),"  "))
			FileAccess.open("res://.dbg/campaign-eq-sliced.json",FileAccess.WRITE).store_string(JSON.stringify(snapshot(second),"  "))
			printerr("FORCE_EQ_FAILED day=",first.day);quit(1);return
		if first.day%120==0:print("FORCE_EQ_PROGRESS day=",first.day)
	print("FORCE_EQ_PASS days=",days," peak_us=",JSON.stringify(sliced.runtime_span_peak_usec))
	sync.queue_free(); sliced.queue_free(); await process_frame; quit()
