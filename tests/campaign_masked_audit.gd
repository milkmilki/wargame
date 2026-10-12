extends SceneTree
## Fresh real-Earth masked runs; semantic warnings are reported, not hidden.
var state: GameState
var sim: Simulation
var failures: Array=[]
var directory: String
class CountedSimulation extends Simulation:
	var orders_by_day: Dictionary={}
	func _record_ai_order(army: Army,candidate: ActionCandidate) -> void:
		orders_by_day[state.day]=int(orders_by_day.get(state.day,0))+1
		super._record_ai_order(army,candidate)
func _initialize():call_deferred("run")
func run():
	var seed_value:=1;var days:=720
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):seed_value=int(arg.get_slice("=",1))
		if arg.begins_with("--days="):days=int(arg.get_slice("=",1))
	directory="res://.dbg/campaign-simple-audit-%d"%seed_value
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var payload:Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military(seed_value)
	state=GameState.new();state.generate_from_atlas(payload);sim=CountedSimulation.new();root.add_child(sim);sim.setup(state);sim.paused=true;sim.tick_phase_profiling_enabled=true
	var hashes:={}
	for path in ["scripts/simulation/rules/simple_campaign.gd","scripts/simulation/simulation.gd","scripts/core/combat.gd","scripts/core/pathfinding.gd","scripts/state/game_state.gd","scripts/model/coalition_campaign_front.gd","scripts/core/native_snapshot_builder.gd","tests/campaign_masked_audit.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	var manifest:={"pid":OS.get_process_id(),"seed":state.world_seed,"target_days":days,"trade":state.trade_enabled,"rulers":state.random_ruler_profiles_enabled(),"mask":payload.data.options.settlement_mask,"source_hashes":hashes,"godot":Engine.get_version_info()}
	FileAccess.open(directory+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  "))
	var times:=[];var commands:=[];var profiles:=[];var waves:={};var events:=FileAccess.open(directory+"/events.jsonl",FileAccess.WRITE)
	var max_fronts:=0;var max_armies:=0;var max_battles:=0;var transitions:={};var phases:={};var motion:={};var candidates:=[]
	for index in range(days):
		var started:=Time.get_ticks_usec();sim._advance_day();times.append((Time.get_ticks_usec()-started)/1000.)
		profiles.append(sim.tick_profile_last_usec.duplicate(true));commands.append((sim as CountedSimulation).orders_by_day.get(state.day,0))
		if not state.territory_structure_valid():failures.append({"day":state.day,"code":"territory"})
		if not state._battle_group_structure_valid():failures.append({"day":state.day,"code":"groups"})
		var occupancy:={}
		for army in state.armies:
			if army.size<=0:continue
			if not state.nations[army.owner_nation].alive and not state.nations[army.owner_nation].succession_identity:failures.append({"day":state.day,"code":"dead_owner","army":army.id})
			if army.on_edge:
				var key:=GameState.edge_key(army.move_from,army.move_to);occupancy[key]=int(occupancy.get(key,0))+1
			if army.battle_id>=0:
				var battle:=state.battle_by_id(army.battle_id)
				if battle==null or battle.finished or not battle.has_army(army):failures.append({"day":state.day,"code":"battle_binding","army":army.id})
			if army.campaign_front_id>=0:
				var front:=state.campaign_front(army.campaign_front_id)
				if front==null or front.war_id!=army.campaign_war_id or not front.participant_nation_ids.has(army.owner_nation):failures.append({"day":state.day,"code":"front_binding","army":army.id})
		for edge in state.edges:
			if edge.passing_count!=int(occupancy.get(GameState.edge_key(edge.city_a,edge.city_b),0)):failures.append({"day":state.day,"code":"road_occupancy","edge":[edge.city_a,edge.city_b]})
		for nation in state.nations:
			if nation.treasury_gold<0 or nation.granary_food<0 or nation.manpower_pool<0:failures.append({"day":state.day,"code":"stocks","nation":nation.id})
		for front in state.campaign_fronts.values():
			var units:=[]
			for army in state.armies:
				if army.campaign_front_id==front.front_id:units.append([army.id,army.state,army.location_city,army.move_to,roundi(army.move_progress*10000),army.size])
			var signature:=hash([front.phase,front.camp_city_id,front.detachments,state.cities[front.center_city_id].garrison_manpower,units])
			var previous:Dictionary=motion.get(front.front_id,{"signature":signature,"day":state.day})
			if previous.signature!=signature:previous={"signature":signature,"day":state.day}
			motion[front.front_id]=previous
			if state.day-int(previous.day)==180:candidates.append({"day":state.day,"code":"unchanged_front_180_days","front":front.front_id,"center":front.center_city_id,"phase":front.phase,"units":units})
			if int(phases.get(front.front_id,-1))!=front.phase:
				events.store_line(JSON.stringify({"day":state.day,"front":front.front_id,"war":front.war_id,"center":front.center_city_id,"phase":front.phase,"camp":front.camp_city_id,"tasks":front.detachments}));phases[front.front_id]=front.phase
				transitions[front.phase]=int(transitions.get(front.phase,0))+1
		for record in state.campaign_raid_records:
			var key:=str([record.war,record.center,record.day,record.members]);waves[key]=record.duplicate(true)
		max_fronts=maxi(max_fronts,state.campaign_fronts.size());max_armies=maxi(max_armies,state.armies.size());max_battles=maxi(max_battles,state.battles.size())
		if state.day%120==0:print("SIMPLE_AUDIT seed=",seed_value," day=",state.day," failures=",failures.size());await process_frame
		if not failures.is_empty():break
	var report:={"seed":state.world_seed,"days":state.day,"failures":failures,"candidates":candidates,"daily_ms":times,"profiles":profiles,"commands":commands,"max_fronts":max_fronts,"max_armies":max_armies,"max_battles":max_battles,"waves":waves.values(),"phase_transitions":transitions}
	FileAccess.open(directory+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	FileAccess.open(directory+"/final.snapshot",FileAccess.WRITE).store_var(NativeSnapshotBuilder.build(state),false)
	events.close();print("SIMPLE_AUDIT_DONE seed=",seed_value," day=",state.day," failures=",failures.size());sim.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
