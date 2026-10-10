extends SceneTree
## Manual long-run audit (not part of the quick regression suite).
## --audit-years=30; 360 simulation days/year. Evidence stays under .dbg/.
const DIRECTORY := "res://.dbg/atlas-eurasia-thirty-year"
var state: GameState
var sim: Simulation
var run_log := DebugRunLog.new()
var event_file: FileAccess
var hard_errors: Array = []
var watch_counts := {}
var warnings: Array = []
var army_motion := {}
var front_motion := {}
var war_motion := {}
var war_seen := {}
var ended_wars := {}
var front_seen := {}
var battle_seen := {}
var army_seen := {}
var nation_max_armies := {}
var max_armies := 0
var max_fronts := 0
var max_battles := 0
var max_wars := 0
var initial_alive := 0
var started := 0
var years := 30
var peak_day_ms := 0
var simulation_usec := 0
var audit_usec := 0
var source_hashes := {}
var profile_file: FileAccess
func model_parameters() -> Dictionary:
	return {"atlas_ai_strategic_interval_days":sim.atlas_ai_strategic_interval_days,
		"atlas_ai_batch_days":sim.atlas_ai_batch_days,"ai_staggered_decisions":sim.ai_staggered_decisions,"settlement_mask":state.atlas_layout.data.options.get("settlement_mask",{})}
func _initialize(): call_deferred("run")
func event(kind: String,details: Dictionary):
	var row := details.duplicate(); row.kind=kind; row.day=state.day; row.seed=state.world_seed
	event_file.store_line(JSON.stringify(row)); event_file.flush()
func fail(code: String,details: Dictionary = {}):
	var row := details.duplicate(); row.code=code; hard_errors.append(row); event("error",row)
	printerr("AUDIT_ERROR day=",state.day," ",JSON.stringify(row))
func warn(code: String,key: String,details: Dictionary):
	var stamp := code+":"+key
	if watch_counts.has(stamp): return
	watch_counts[stamp]=state.day
	var row := details.duplicate(); row.code=code; row.day=state.day; warnings.append(row); event("candidate",row)
func army_row(army: Army) -> Dictionary:
	return {"id":army.id,"nation":army.owner_nation,"size":army.size,"state":army.state,"city":army.location_city,"on_edge":army.on_edge,"from":army.move_from,"to":army.move_to,"progress":army.move_progress,"path":army.path,"target":army.ai_target_city,"action":army.ai_action,"starving":army.starving,"supply":army.supply_ratio,"battle":army.battle_id,"war":army.campaign_war_id,"front":army.campaign_front_id}
func front_row(front: CoalitionCampaignFront) -> Dictionary:
	var armies: Array=[]
	for army in state.armies:
		if army.campaign_front_id==front.front_id and army.size>0: armies.append(army_row(army))
	return {"id":front.front_id,"war":front.war_id,"center":front.center_city_id,"anchor":front.anchor_nation_id,"members":front.participant_nation_ids,"mode":front.mode,"phase":front.phase,"camp":front.camp_city_id,"staging":front.staging_city_id,"targets":front.tactical_target_city_ids,"retiring":front.retiring,"failed_until":front.failed_until_day,"armies":armies}
func snapshot(name_value: String):
	FileAccess.open(DIRECTORY+"/"+name_value+".snapshot",FileAccess.WRITE).store_var(NativeSnapshotBuilder.build(state),false)
func daily_audit():
	if not state.territory_structure_valid(): fail("territory_invariant")
	if not state._battle_group_structure_valid(): fail("battle_group_invariant")
	if not state.suzerainty_structure_valid(): fail("suzerainty_invariant",{"reason":state.suzerainty_structure_error()})
	var ids := {}; var occupancy := {}; var counts := {}
	for army in state.armies:
		if ids.has(army.id): fail("duplicate_army",{"id":army.id})
		ids[army.id]=true; army_seen[army.id]=true
		if army.size<0 or army.size>army.max_size: fail("army_size",army_row(army))
		if army.size<=0: continue
		counts[army.owner_nation]=int(counts.get(army.owner_nation,0))+1
		# Succession identities intentionally own military forces without cities.
		if army.owner_nation<0 or army.owner_nation>=state.nations.size() or (not state.nations[army.owner_nation].alive and not state.nations[army.owner_nation].succession_identity): fail("dead_army_owner",army_row(army))
		if not is_finite(army.morale) or not is_finite(army.supply_ratio) or army.morale<0. or army.supply_ratio<0. or army.supply_ratio>1.00001: fail("army_numeric",army_row(army))
		if army.location_city<0 or army.location_city>=state.cities.size(): fail("army_location",army_row(army))
		if army.on_edge:
			var key := GameState.edge_key(army.move_from,army.move_to); occupancy[key]=int(occupancy.get(key,0))+1
			if state.edge_of(army.move_from,army.move_to)==null or not is_finite(army.move_progress) or army.move_progress<0. or army.move_progress>1.00001: fail("army_road",army_row(army))
		if army.battle_id>=0:
			var battle := state.battle_by_id(army.battle_id)
			if battle==null or battle.finished or not battle.has_army(army): fail("army_battle_binding",army_row(army))
		elif army.state==Army.State.FIGHTING: fail("fighting_without_battle",army_row(army))
		if army.campaign_war_id>=0 and not state.nation_participates_in_war_id(army.owner_nation,army.campaign_war_id): fail("stale_army_war",army_row(army))
		if army.campaign_front_id>=0:
			var front := state.campaign_front(army.campaign_front_id)
			if front==null or front.war_id!=army.campaign_war_id or not front.participant_nation_ids.has(army.owner_nation): fail("army_front_binding",army_row(army))
		var signature := hash([army.state,army.location_city,army.on_edge,army.move_from,army.move_to,roundi(army.move_progress*1000000),army.path])
		var previous: Dictionary=army_motion.get(army.id,{"signature":signature,"day":state.day})
		if previous.signature!=signature: previous={"signature":signature,"day":state.day}
		army_motion[army.id]=previous
		if army.state in [Army.State.MOVING,Army.State.RETREATING] and state.day-int(previous.day)>=30: warn("motion_unchanged_30_days",str(army.id),army_row(army))
	for edge in state.edges:
		if edge.passing_count!=int(occupancy.get(GameState.edge_key(edge.city_a,edge.city_b),0)): fail("road_occupancy",{"a":edge.city_a,"b":edge.city_b,"actual":edge.passing_count,"expected":occupancy.get(GameState.edge_key(edge.city_a,edge.city_b),0)})
	for nation in state.nations:
		if nation.treasury_gold<0 or nation.manpower_pool<0 or nation.granary_food<0: fail("nation_stocks",{"nation":nation.id,"gold":nation.treasury_gold,"manpower":nation.manpower_pool,"food":nation.granary_food})
		nation_max_armies[nation.id]=maxi(int(nation_max_armies.get(nation.id,0)),int(counts.get(nation.id,0)))
		if int(counts.get(nation.id,0))>state.max_army_count(nation.id): warn("army_count_above_current_cap",str(nation.id),{"nation":nation.id,"armies":counts[nation.id],"cap":state.max_army_count(nation.id)})
	var active_wars := {}
	for key in state.war_relation_ids:
		var parts: PackedStringArray=str(key).split(":"); var left := int(parts[0]); var right := int(parts[1]); var id := int(state.war_relation_ids[key])
		if not state.is_enemy(left,right) or not state.nations[left].alive or not state.nations[right].alive: fail("stale_war_relation",{"key":key,"war":id})
		active_wars[id]=true; war_seen[id]=true
	for front in state.campaign_fronts.values():
		front_seen[front.front_id]=true
		if front.center_city_id<0 or front.center_city_id>=state.cities.size() or state.administrative_center_of(front.center_city_id)!=front.center_city_id: fail("front_center",{"front":front.front_id,"center":front.center_city_id})
		if not active_wars.has(front.war_id): fail("stale_front_war",{"front":front.front_id,"war":front.war_id})
	for battle in state.battles:
		battle_seen[battle.id]=true
		if battle.finished: continue
		for army in battle.side_a+battle.side_b:
			if army.size>0 and (not ids.has(army.id) or army.battle_id!=battle.id): fail("battle_army_binding",{"battle":battle.id,"army":army.id,"binding":army.battle_id})
	max_armies=maxi(max_armies,state.armies.size()); max_fronts=maxi(max_fronts,state.campaign_fronts.size()); max_battles=maxi(max_battles,state.battles.size()); max_wars=maxi(max_wars,active_wars.size())
func monthly_audit():
	var fronts: Array=[]; var nations: Array=[]; var owners_by_nation := {}; var active_wars := {}
	for city in state.land_cities():
		if not owners_by_nation.has(city.owner_nation): owners_by_nation[city.owner_nation]=[]
		owners_by_nation[city.owner_nation].append(city.id)
	for front in state.campaign_fronts.values():
		var row := front_row(front); fronts.append(row)
		var positions: Array=[]
		for army in row.armies: positions.append([army.id,army.city,army.state,army.from,army.to,roundi(army.progress*1000000)])
		var signature := hash([front.phase,front.camp_city_id,front.tactical_target_city_ids,state.cities[front.center_city_id].owner_nation,positions])
		var previous: Dictionary=front_motion.get(front.front_id,{"signature":signature,"day":state.day})
		if previous.signature!=signature: previous={"signature":signature,"day":state.day}
		front_motion[front.front_id]=previous
		if state.day-int(previous.day)>=360: warn("front_unchanged_one_year",str(front.front_id),row)
	for nation in state.nations:
		nations.append({"id":nation.id,"alive":nation.alive,"cities":owners_by_nation.get(nation.id,[]).size(),"capital":nation.capital_city_id,"gold":nation.treasury_gold,"manpower":nation.manpower_pool,"food":nation.granary_food,"preparation_target":nation.war_preparation_target_nation,"preparation_since":nation.war_preparation_started_day})
		if nation.war_preparation_target_nation>=0 and nation.war_preparation_started_day>=0 and state.day-nation.war_preparation_started_day>=720: warn("war_preparation_two_years",str(nation.id),nations[-1])
	for value in state.war_relation_ids.values(): active_wars[int(value)]=true
	for id in active_wars:
		var members: Array=[]
		for nation in state.nations:
			if state.nation_participates_in_war_id(nation.id,id): members.append([nation.id,owners_by_nation.get(nation.id,[])])
		var signature := hash(members); var previous: Dictionary=war_motion.get(id,{"signature":signature,"day":state.day,"first_day":state.day})
		if previous.signature!=signature: previous.signature=signature; previous.day=state.day
		war_motion[id]=previous
		if state.day-int(previous.day)>=720: warn("war_no_territorial_change_two_years",str(id),{"war":id,"since":previous.day,"members":members})
	for id in war_motion:
		if not active_wars.has(id) and not ended_wars.has(id): ended_wars[id]=state.day; event("war_ended",{"war":id,"first_observed":war_motion[id].first_day})
	event("monthly",{"nations":nations,"fronts":fronts,"wars":active_wars.keys(),"armies":state.armies.size(),"battles":state.battles.size(),"ownership_revision":state.ownership_revision,"rng_state":str(state.rng.state)})
func report() -> Dictionary:
	var alive: Array=[]
	for nation in state.nations:
		if nation.alive: alive.append(nation.id)
	return {"seed":state.world_seed,"day":state.day,"target_days":years*Simulation.DAYS_PER_YEAR,"elapsed_ms":Time.get_ticks_msec()-started,"peak_day_ms":peak_day_ms,"mean_simulation_ms":float(simulation_usec)/maxi(1,state.day)/1000.,"mean_audit_ms":float(audit_usec)/maxi(1,state.day)/1000.,"source_hashes":source_hashes,"model_parameters":model_parameters(),"initial_nations":initial_alive,"alive_nations":alive,"wars_seen":war_seen.size(),"wars_ended":ended_wars.size(),"fronts_seen":front_seen.size(),"battles_seen":battle_seen.size(),"armies_seen":army_seen.size(),"max_armies":max_armies,"max_fronts":max_fronts,"max_battles":max_battles,"max_wars":max_wars,"nation_max_armies":nation_max_armies,"hard_errors":hard_errors,"candidates":warnings,"debug_run":ProjectSettings.globalize_path(run_log.path),"generation":state.generation_metadata,"mode":"headless_sync_daily","complete":state.day==years*Simulation.DAYS_PER_YEAR and hard_errors.is_empty()}
func write_status() -> void:
	# Serialize before opening the destination. Publish a complete replacement,
	# so interruption cannot truncate the last readable checkpoint to zero bytes.
	var text := JSON.stringify(report())
	var destination := ProjectSettings.globalize_path(DIRECTORY+"/status.json")
	var temporary := destination+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	assert(file != null,"Cannot write audit status")
	file.store_string(text); file.flush(); file.close()
	assert(DirAccess.rename_absolute(temporary,destination)==OK,"Cannot publish audit status")
func run():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--audit-years="): years=int(argument.get_slice("=",1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	# The prior run must be archived before restarting. Do not expose its final
	# report/snapshot as evidence for this new process while the first month runs.
	for name_value in ["report.json", "latest.snapshot", "final.snapshot"]:
		var previous_path: String = DIRECTORY+"/"+name_value
		if FileAccess.file_exists(previous_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(previous_path))
	var payload: Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military()
	state=GameState.new(); state.generate_from_atlas(payload)
	sim=Simulation.new(); root.add_child(sim); sim.setup(state); sim.paused=true
	sim.tick_phase_profiling_enabled=true; sim.runtime_stage_profiling_enabled=true; sim.ai_snapshot_substage_profiling_enabled=true
	for path in ["scripts/state/game_state.gd","scripts/simulation/simulation.gd","scripts/simulation/rules/supply_rules.gd","scripts/core/pathfinding.gd","scripts/ai/ai_world_view.gd","tests/atlas_long_audit.gd","scripts/ai/diplomacy_ai.gd","scripts/atlas/settlement_mask.gd","tests/atlas_military_inputs.gd"]:
		source_hashes[path]=FileAccess.get_sha256("res://"+path)
	initial_alive=state.nations.size(); started=Time.get_ticks_msec()
	event_file=FileAccess.open(DIRECTORY+"/events.jsonl",FileAccess.WRITE)
	profile_file=FileAccess.open(DIRECTORY+"/first-year-profile.jsonl",FileAccess.WRITE)
	run_log.begin("res://tests/atlas_long_audit.gd"); run_log.world_started(state,{"years":years,"days":years*Simulation.DAYS_PER_YEAR,"scene":"atlas_military.tscn","mode":"headless_sync","source_hashes":source_hashes},"atlas_thirty_year_audit")
	FileAccess.open(DIRECTORY+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify({"source_hashes":source_hashes,"model_parameters":model_parameters(),"godot_pid":OS.get_process_id(),"seed":state.world_seed,"initial_nations":state.nations.size(),"target_days":years*Simulation.DAYS_PER_YEAR,"days_per_year":Simulation.DAYS_PER_YEAR,"audit_script":"tests/atlas_long_audit.gd","debug_run":ProjectSettings.globalize_path(run_log.path),"generation":state.generation_metadata},"\t"))
	event("start",{"pid":OS.get_process_id(),"nations":state.nations.size(),"cities":state.cities.size(),"parameters":state.generation_metadata})
	write_status()
	for _day in range(years*Simulation.DAYS_PER_YEAR):
		var before := Time.get_ticks_usec(); sim._advance_day(); var duration := Time.get_ticks_usec()-before
		simulation_usec += duration; peak_day_ms=maxi(peak_day_ms,ceili(duration/1000.))
		if state.day<=365:
			var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(var_to_bytes(NativeSnapshotBuilder.build(state)))
			profile_file.store_line(JSON.stringify({"day":state.day,"armies":state.armies.size(),"fronts":state.campaign_fronts.size(),"profile":sim.tick_profile_last_usec.duplicate(),"sha256":digest.finish().hex_encode(),"simulation_us":duration})); profile_file.flush()
			if state.day==365:
				profile_file.close(); sim.tick_phase_profiling_enabled=false; sim.runtime_stage_profiling_enabled=false; sim.ai_snapshot_substage_profiling_enabled=false
		before = Time.get_ticks_usec(); daily_audit(); run_log.checkpoint(state); audit_usec += Time.get_ticks_usec()-before
		if state.day%30==0:
			monthly_audit(); print("AUDIT_PROGRESS day=",state.day," years=",snappedf(float(state.day)/360.,.01)," armies=",state.armies.size()," wars=",state.war_relation_ids.size()," fronts=",state.campaign_fronts.size()," elapsed_ms=",Time.get_ticks_msec()-started)
			write_status()
			await process_frame
		if state.day%360==0: snapshot("latest")
		if not hard_errors.is_empty(): snapshot("failure-day-%d"%state.day); break
	snapshot("final"); monthly_audit(); run_log.close(state)
	write_status()
	FileAccess.open(DIRECTORY+"/report.json",FileAccess.WRITE).store_string(JSON.stringify(report(),"\t")); event_file.close()
	if profile_file.is_open(): profile_file.close()
	print("AUDIT_COMPLETE " if bool(report().complete) else "AUDIT_STOPPED ",JSON.stringify(report()).substr(0,1000))
	root.remove_child(sim); sim.free(); quit(1 if not hard_errors.is_empty() else 0)
