extends SceneTree
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("ATLAS_MASKED_SMOKE_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var days := 35
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--atlas-smoke-days="): days=int(argument.get_slice("=",1))
	var payload: Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	check(payload.data.options.settlement_mask==Mask.EURASIA,"actual test input is the requested regional world")
	var state := GameState.new(); state.generate_from_atlas(payload)
	var sim := Simulation.new(); sim.setup(state); sim.paused=true
	var timings := []
	for day in range(days):
		var started := Time.get_ticks_usec(); sim._advance_day(); timings.append((Time.get_ticks_usec()-started)/1000.)
		check(state.territory_structure_valid(),"territory day %d"%state.day)
		check(state._battle_group_structure_valid(),"battle groups day %d"%state.day)
		var occupancy := {}
		for army in state.armies:
			if army.size<=0: continue
			check(state.nations[army.owner_nation].alive or state.nations[army.owner_nation].succession_identity,"live army owner or legal succession military identity")
			if army.on_edge:
				var key := GameState.edge_key(army.move_from,army.move_to); occupancy[key]=occupancy.get(key,0)+1
				check(state.edge_of(army.move_from,army.move_to)!=null and army.move_progress>=0. and army.move_progress<=1.00001,"physical army position")
			if army.battle_id>=0:
				var battle := state.battle_by_id(army.battle_id)
				check(battle!=null and not battle.finished and battle.has_army(army),"battle binding")
		for edge in state.edges: check(edge.passing_count==int(occupancy.get(GameState.edge_key(edge.city_a,edge.city_b),0)),"road occupancy")
		for nation in state.nations: check(nation.treasury_gold>=0 and nation.manpower_pool>=0 and nation.granary_food>=0,"resource stocks")
		if failures: break
		if state.day%120==0: print("ATLAS_MASKED_SMOKE_PROGRESS day=",state.day);await process_frame
	var hashes := {}
	for path in ["scripts/core/pathfinding.gd","scripts/simulation/simulation.gd","scripts/state/game_state.gd","tests/atlas_masked_military_smoke.gd"]: hashes[path]=FileAccess.get_sha256("res://"+path)
	var report := {"pid":OS.get_process_id(),"source_hashes":hashes,"trade":state.trade_enabled,"rulers":state.random_ruler_profiles_enabled(),"seed":state.world_seed,"mask":Mask.EURASIA,"day":state.day,"nodes":state.cities.size(),"settlements":state.land_cities().size(),"armies":state.armies.size(),"battles":state.battles.size(),"daily_compute_ms":timings,"failures":failures}
	FileAccess.open("res://.dbg/atlas-masked-military-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ATLAS_MASKED_MILITARY_SMOKE day=",state.day," failures=",failures," daily_compute_ms=",timings)
	sim.free(); quit(1 if failures else 0)
