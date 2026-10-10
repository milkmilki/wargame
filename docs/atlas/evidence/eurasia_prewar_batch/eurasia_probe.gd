extends SceneTree
const Codec=preload("res://.dbg/state_codec.gd")
func _initialize(): call_deferred("run")
func audit(state: GameState):
	assert(state.territory_structure_valid(),"Territory invariant")
	assert(state._battle_group_structure_valid(),"Battle group invariant")
	assert(state.suzerainty_structure_valid(),"Suzerainty invariant")
	var occupancy := {}; var ids := {}
	for army in state.armies:
		assert(not ids.has(army.id),"Duplicate army ID"); ids[army.id]=true
		assert(army.size>=0 and army.size<=army.max_size,"Army size")
		if army.size<=0: continue
		assert(army.owner_nation>=0 and army.owner_nation<state.nations.size() and state.nations[army.owner_nation].alive,"Army owner")
		if army.on_edge:
			assert(state.edge_of(army.move_from,army.move_to)!=null,"Army edge")
			var key := GameState.edge_key(army.move_from,army.move_to)
			occupancy[key]=int(occupancy.get(key,0))+1
		if army.battle_id>=0:
			var battle:=state.battle_by_id(army.battle_id)
			assert(battle!=null and not battle.finished and battle.has_army(army),"Battle binding")
		elif army.state==Army.State.FIGHTING: assert(false,"Fighting without battle")
		if army.campaign_front_id>=0:
			var front:=state.campaign_front(army.campaign_front_id)
			assert(front!=null and front.war_id==army.campaign_war_id and front.participant_nation_ids.has(army.owner_nation),"Front binding")
	for edge in state.edges:
		assert(edge.passing_count==int(occupancy.get(GameState.edge_key(edge.city_a,edge.city_b),0)),"Road occupancy")
	for nation in state.nations:
		assert(nation.treasury_gold>=0 and nation.manpower_pool>=0 and nation.granary_food>=0,"Nation stocks")
func run():
	var sim: Simulation=Codec.new().restore("res://.dbg/eurasia-frozen-day720.bin")
	root.add_child(sim); sim.paused=true; sim.tick_phase_profiling_enabled=true
	var digest:=HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(var_to_bytes(NativeSnapshotBuilder.build(sim.state)))
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/eurasia-frozen-manifest.json"))
	var expected: String=manifest.sha256
	assert(sim.state.atlas_layout.data.options.settlement_mask==preload("res://scripts/atlas/settlement_mask.gd").EURASIA,"Actual Eurasia performance world")
	assert(digest.finish().hex_encode()==expected,"Identical complete initial state")
	var file:=FileAccess.open("res://.dbg/eurasia-profile-"+OS.get_environment("FROZEN_TAG")+".jsonl",FileAccess.WRITE)
	for day in range(30):
		sim._advance_day(false)
		var before:=Time.get_ticks_usec(); audit(sim.state); var audit_us:=Time.get_ticks_usec()-before
		digest=HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(var_to_bytes(NativeSnapshotBuilder.build(sim.state)))
		var row: Dictionary={"day":sim.state.day,"profile":sim.tick_profile_last_usec.duplicate(),"sha256":digest.finish().hex_encode(),"audit_us":audit_us,"armies":sim.state.armies.size(),"fronts":sim.state.campaign_fronts.size(),"war_relations":sim.state.war_relation_ids.size()}
		file.store_line(JSON.stringify(row)); file.flush()
		print("FROZEN_DAY ",sim.state.day," ",row.profile.total/1000.); await process_frame
	file.close(); sim.free(); quit()
