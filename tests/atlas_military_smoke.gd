extends SceneTree
const Map = preload("res://scripts/atlas/military_map.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_SMOKE_FAIL ",message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var days := 365
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--atlas-smoke-days="): days = int(argument.get_slice("=",1))
	var base: Dictionary = preload("res://tests/atlas_military_inputs.gd").base()
	var payload := Map.prepare(base)
	var cache := FileAccess.open("res://.dbg/atlas-military-earth.bin",FileAccess.WRITE); cache.store_var(payload,false); cache.close()
	var state := GameState.new(); state.generate_from_atlas(payload)
	var sim := Simulation.new(); sim.setup(state); sim.paused = true
	var run_log := DebugRunLog.new(); run_log.begin("tests/atlas_military_smoke.gd"); run_log.world_started(state,{"days":days,"model":payload.model},"atlas_seed1_40_nations")
	var started := Time.get_ticks_msec()
	for _day in range(days):
		if state.day%30==0: print("ATLAS_SMOKE_PROGRESS day=",state.day," elapsed_ms=",Time.get_ticks_msec()-started)
		sim._advance_day(); run_log.checkpoint(state)
		check(state.territory_structure_valid(),"territory day %d"%state.day)
		check(state._battle_group_structure_valid(),"battle groups day %d"%state.day)
		var occupancy := {}
		for army in state.armies:
			check(army.size>=0,"negative army")
			if army.size<=0: continue
			if army.on_edge:
				var key := GameState.edge_key(army.move_from,army.move_to); occupancy[key] = occupancy.get(key,0)+1
				check(state.edge_of(army.move_from,army.move_to)!=null and army.move_progress>=0. and army.move_progress<=1.00001,"physical army position")
			if army.battle_id>=0:
				var battle := state.battle_by_id(army.battle_id)
				check(battle!=null and not battle.finished and battle.has_army(army),"battle binding")
		for edge in state.edges: check(edge.passing_count==int(occupancy.get(GameState.edge_key(edge.city_a,edge.city_b),0)),"road occupancy")
		for nation in state.nations: check(nation.treasury_gold>=0 and nation.manpower_pool>=0 and nation.granary_food>=0,"stocks")
		if failures>0: break
	print("ATLAS_MILITARY_SMOKE day=",state.day," failures=",failures," elapsed_ms=",Time.get_ticks_msec()-started)
	run_log.close(state)
	sim.free(); quit(1 if failures else 0)
