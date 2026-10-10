extends SceneTree
func _initialize(): call_deferred("run")
func snapshot(state: GameState) -> Array:
	return [state.day,state.rng.state,state.diplomatic_relations,
		state.nations.map(func(n): return [n.manpower_pool,n.treasury_gold,n.battle_groups.map(func(g): return g.id)]),
		state.cities.map(func(c): return [c.owner_nation,c.food_storage,c.garrison_manpower]),
		state.armies.map(func(a): return [a.id,a.owner_nation,a.size,a.max_size,a.location_city,a.move_from,a.move_to,a.move_progress,a.battle_group_id,a.ai_action,a.ai_target_city,a.supply_food_debt])]
func run():
	var payload=preload("res://tests/atlas_military_inputs.gd").military()
	var first:=GameState.new(); first.generate_from_atlas(payload.duplicate(true))
	var second:=GameState.new(); second.generate_from_atlas(payload.duplicate(true))
	var log := DebugRunLog.new(); log.begin("tests/atlas_runtime_equivalence.gd"); log.world_started(first,{"days":6,"model":payload.model},"atlas_runtime_equivalence")
	print("FORCE_EQ seed=",first.world_seed," nations=",first.nations.size()," nodes=",first.cities.size())
	var sync:=Simulation.new(); root.add_child(sync); sync.setup(first); sync.paused=true
	var sliced:=Simulation.new(); root.add_child(sliced); sliced.setup(second); sliced.paused=true; sliced.runtime_stage_profiling_enabled=true
	for i in range(6):
		sync._advance_day()
		await sliced.advance_one_day(); log.checkpoint(first)
		if snapshot(first)!=snapshot(second): printerr("FORCE_EQ_FAILED day=",first.day); quit(1); return
	print("FORCE_EQ_PASS days=6 peak_us=",JSON.stringify(sliced.runtime_span_peak_usec))
	sync.queue_free(); sliced.queue_free(); await process_frame; quit()
