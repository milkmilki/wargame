extends SceneTree
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("ATLAS_MASKED_SMOKE_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var path := "res://.dbg/atlas-military-eurasia-mask.bin"
	var payload: Dictionary
	if FileAccess.file_exists(path): payload=FileAccess.open(path,FileAccess.READ).get_var(false)
	else:
		var base := preload("res://scripts/atlas/generator.gd").generate(1,1.,Callable(),{"terrain_model":"earth","rainfall_model":"seasonal_circulation_v5","settlement_model":"climate_capacity_v6","settlement_mask":Mask.EURASIA})
		payload=preload("res://scripts/atlas/military_map.gd").prepare(base)
	check(payload.data.options.settlement_mask==Mask.EURASIA,"actual test input is the requested regional world")
	var state := GameState.new(); state.generate_from_atlas(payload)
	var sim := Simulation.new(); sim.setup(state); sim.paused=true
	var timings := []
	for day in range(35):
		var started := Time.get_ticks_usec(); sim._advance_day(); timings.append((Time.get_ticks_usec()-started)/1000.)
		check(state.territory_structure_valid(),"territory day %d"%state.day)
		check(state._battle_group_structure_valid(),"battle groups day %d"%state.day)
		var occupancy := {}
		for army in state.armies:
			if army.size<=0: continue
			check(state.nations[army.owner_nation].alive,"live army owner")
			if army.on_edge:
				var key := GameState.edge_key(army.move_from,army.move_to); occupancy[key]=occupancy.get(key,0)+1
				check(state.edge_of(army.move_from,army.move_to)!=null and army.move_progress>=0. and army.move_progress<=1.00001,"physical army position")
			if army.battle_id>=0:
				var battle := state.battle_by_id(army.battle_id)
				check(battle!=null and not battle.finished and battle.has_army(army),"battle binding")
		for edge in state.edges: check(edge.passing_count==int(occupancy.get(GameState.edge_key(edge.city_a,edge.city_b),0)),"road occupancy")
		for nation in state.nations: check(nation.treasury_gold>=0 and nation.manpower_pool>=0 and nation.granary_food>=0,"resource stocks")
		if failures: break
	var report := {"seed":state.world_seed,"mask":Mask.EURASIA,"day":state.day,"nodes":state.cities.size(),"settlements":state.land_cities().size(),"armies":state.armies.size(),"battles":state.battles.size(),"daily_compute_ms":timings,"failures":failures}
	FileAccess.open("res://.dbg/atlas-masked-military-smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ATLAS_MASKED_MILITARY_SMOKE day=",state.day," failures=",failures," daily_compute_ms=",timings)
	sim.free(); quit(1 if failures else 0)
