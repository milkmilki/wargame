extends SceneTree
## One backend per process, exact frozen EURASIA input states. Timing excludes audit.
## Capture: -- --capture --stages=0,330,600
## Measure: WARGAME_COMPUTE_BACKEND=gdscript/native -- --days=30 --stages=0,330,600
const Fixture=preload("res://tests/support/native_runtime_fixture.gd")
const DIRECTORY:="res://.dbg/native-runtime"
const BACKEND_PATH:="res://scripts/core/native_compute.gd"
var _backend:Script
var _selected_backend:="gdscript"
var _days:=30
var _stages:Array[int]=[0,330,600]
var _capture:=false

func _initialize()->void:
	call_deferred("run")

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--capture":_capture=true
		elif argument.begins_with("--days="):_days=int(argument.get_slice("=",1))
		elif argument.begins_with("--stages="):
			_stages.clear()
			for item in argument.get_slice("=",1).split(","):_stages.append(int(item))
	if ResourceLoader.exists(BACKEND_PATH):_backend=load(BACKEND_PATH)
	var requested:=OS.get_environment("WARGAME_COMPUTE_BACKEND")
	if not requested.is_empty():_selected_backend=requested
	if _capture:
		await capture()
		return
	if _backend==null:
		printerr("NATIVE_BENCH_RED missing runtime backend")
		quit(1)
		return
	if _selected_backend not in ["gdscript","native"]:
		printerr("NATIVE_BENCH_INVALID backend ",_selected_backend)
		quit(1)
		return
	select_backend(_selected_backend)
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+"/manifest.json"))
	if manifest.get("format","")!=Fixture.FORMAT:
		printerr("NATIVE_BENCH_INVALID missing or incompatible fixture manifest")
		quit(1)
		return
	var report:Dictionary={"backend":_selected_backend,"fixture_manifest":manifest,"current_source_sha256":preload("res://scripts/atlas/military_import.gd").source_fingerprint(),"engine":Engine.get_version_info(),"processor":OS.get_processor_name(),"cpu_count":OS.get_processor_count(),"dll_hashes":dll_hashes(),"build_manifests":build_manifests(),"pid":OS.get_process_id(),"days_per_stage":_days,"stages":[],"memory_start":OS.get_static_memory_usage()}
	for stage in _stages:
		var path:=DIRECTORY+"/day-%d.bin"%stage
		var descriptor:Dictionary=manifest.stages.get(str(stage),{})
		if descriptor.is_empty() or Fixture.hash_bytes(FileAccess.get_file_as_bytes(path))!=descriptor.file_sha256:
			printerr("NATIVE_BENCH_INVALID frozen file hash day=",stage)
			quit(1)
			return
		var codec:=Fixture.new()
		var state:=codec.unpack(FileAccess.open(path,FileAccess.READ).get_var(false))
		if state.day!=stage or Fixture.hash_bytes(var_to_bytes(Fixture.snapshot(state)))!=descriptor.state_sha256:
			printerr("NATIVE_BENCH_INVALID restored state digest day=",stage)
			quit(1)
			return
		var before:=var_to_bytes(Fixture.snapshot(state))
		var kernel_rows:=query_workload(state)
		if before!=var_to_bytes(Fixture.snapshot(state)):
			printerr("NATIVE_BENCH_FAIL pure queries mutated simulation state day=",stage)
			quit(1)
			return
		var simulation:=Simulation.new()
		root.add_child(simulation)
		simulation.setup(state)
		simulation.paused=true
		simulation.tick_phase_profiling_enabled=true
		_backend.call("set_profiling_for_tests",true)
		var durations:Array[int]=[]
		var monthly:Array[int]=[]
		var phase_totals:Dictionary={}
		for _day in range(_days):
			var started:=Time.get_ticks_usec()
			simulation._advance_day()
			var duration:=Time.get_ticks_usec()-started
			durations.append(duration)
			if state.day%30==0:monthly.append(duration)
			for key in simulation.tick_profile_last_usec:phase_totals[key]=int(phase_totals.get(key,0))+int(simulation.tick_profile_last_usec[key])
		var row:Dictionary={"start_day":stage,"end_day":state.day,"input_sha256":descriptor.state_sha256,"output_sha256":Fixture.hash_bytes(var_to_bytes(Fixture.snapshot(state))),"daily":summarize(durations),"monthly_peak_usec":monthly.max() if not monthly.is_empty() else 0,"phase_total_usec":phase_totals,"query_batches":kernel_rows,"native_profile":_backend.call("profile_snapshot"),"memory":OS.get_static_memory_usage()}
		report.stages.append(row)
		print("NATIVE_BENCH_STAGE ",JSON.stringify(row))
		simulation.queue_free()
		codec=null
		state=null
		await process_frame
	var report_path:=DIRECTORY+"/benchmark-%s-%d.json"%[_selected_backend,OS.get_process_id()]
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("NATIVE_BENCH_PASS report=",ProjectSettings.globalize_path(report_path))
	quit()

func capture()->void:
	select_backend("gdscript")
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var payload:Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military(1)
	var state:=GameState.new()
	state.generate_from_atlas(payload)
	var error:=Fixture.validate_world(state,1)
	if not error.is_empty():
		printerr("NATIVE_CAPTURE_INVALID ",error)
		quit(1)
		return
	var log:=DebugRunLog.new()
	log.begin("tests/native_runtime_benchmark.gd")
	log.world_started(state,{"stages":_stages,"backend":"gdscript","model":payload.model},"native_runtime_baseline")
	var manifest:Dictionary={"format":Fixture.FORMAT,"baseline_head":"1224b735d9ce69f047211e21706c50c4844fdca1","schema":NativeSnapshotBuilder.SCHEMA_VERSION,"world_seed":1,"initial_nations":40,"settlement_mask":state.map_models.settlement_mask,"trade_enabled":state.trade_enabled,"rulers_enabled":state.random_ruler_profiles_enabled(),"source_sha256":state.generation_metadata.source_sha256,"engine":Engine.get_version_info(),"processor":OS.get_processor_name(),"cpu_count":OS.get_processor_count(),"created_unix":Time.get_unix_time_from_system(),"stages":{},"baseline_daily_usec":[]}
	var simulation:=Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused=true
	var max_day:int=_stages.max()
	for day in range(max_day+1):
		if _stages.has(day):
			var codec:=Fixture.new()
			var frozen:Dictionary=codec.pack(state)
			var restored:GameState=codec.unpack(frozen)
			var digest:=Fixture.hash_bytes(var_to_bytes(Fixture.snapshot(state)))
			if digest!=Fixture.hash_bytes(var_to_bytes(Fixture.snapshot(restored))):
				FileAccess.open(DIRECTORY+"/codec-original.json",FileAccess.WRITE).store_string(JSON.stringify(Fixture.snapshot(state),"  "))
				FileAccess.open(DIRECTORY+"/codec-restored.json",FileAccess.WRITE).store_string(JSON.stringify(Fixture.snapshot(restored),"  "))
				printerr("NATIVE_CAPTURE_FAIL fixture roundtrip day=",day)
				quit(1)
				return
			var path:=DIRECTORY+"/day-%d.bin"%day
			FileAccess.open(path,FileAccess.WRITE).store_var(frozen,false)
			manifest.stages[str(day)]={"state_sha256":digest,"file_sha256":Fixture.hash_bytes(FileAccess.get_file_as_bytes(path)),"alive_nations":state.nations.filter(func(nation:Nation)->bool:return nation.alive).size(),"armies":state.armies.size(),"cities":state.cities.size(),"edges":state.edges.size()}
			FileAccess.open(DIRECTORY+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  "))
			print("NATIVE_CAPTURE_STAGE day=%d state_sha256=%s"%[day,digest])
		if day==max_day:break
		var started:=Time.get_ticks_usec()
		simulation._advance_day()
		manifest.baseline_daily_usec.append(Time.get_ticks_usec()-started)
		if state.day%60==0: print("NATIVE_CAPTURE_PROGRESS day=",state.day)
	FileAccess.open(DIRECTORY+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  "))
	print("NATIVE_CAPTURE_PASS stages=",_stages," baseline_daily=",JSON.stringify(summarize(manifest.baseline_daily_usec)))
	simulation.queue_free()
	await process_frame
	quit()

func query_workload(state:GameState)->Array:
	var result:Array=[]
	var owners:Array[int]=[]
	for nation in state.nations:
		if nation.alive and nation.capital_city_id>=0:owners.append(nation.id)
	var path_query:=func():
		for owner in owners:Pathfinding.dijkstra_field(state,state.nations[owner].capital_city_id,owner,false,true)
	var supply_query:=func():
		for owner in owners:Pathfinding._supply_loss_field(state,state.nations[owner].capital_city_id,owner)
	var threat_query:=func():
		var field:=ThreatField.new()
		for owner in owners:
			field.travel_distance_cache.clear()
			field._travel_days_field(state,state.nations[owner].capital_city_id,0)
	var trade_graph:=TradeNetwork._build_graph(state)
	var trade_query:=func():
		var allowed:=PackedByteArray()
		allowed.resize(state.cities.size())
		allowed.fill(1)
		for owner in owners:TradeNetwork._dijkstra_field(state,trade_graph,[state.nations[owner].capital_city_id] as Array[int],allowed,false,{},{})
	# _compute_connectivity consumes caller-prepared values in the real AI.
	# Record that caller cost separately; whole-day timing still includes it.
	var prepare_started:=Time.get_ticks_usec()
	var shared_values:=StrategicMapSnapshot.build_base_city_values(state)
	var shared_values_prepare_usec:=Time.get_ticks_usec()-prepare_started
	var connectivity_query:=func():
		for owner in owners:
			var snapshot:=StrategicMapSnapshot.new()
			snapshot._state=state
			snapshot.nation_id=owner
			snapshot.city_value=shared_values.duplicate()
			for city in state.cities:
				if city.owner_nation==owner:snapshot._total_friendly_value+=float(snapshot.city_value.get(city.id,0.0))
			snapshot._compute_connectivity()
	var queries:Dictionary={"path":path_query,"supply":supply_query,"threat":threat_query,"trade":trade_query,"connectivity":connectivity_query}
	for key in queries:
		var durations:Array[int]=[]
		_backend.call("set_profiling_for_tests",true)
		for _sample in range(4):
			var started:=Time.get_ticks_usec()
			if key in ["threat","path","supply","connectivity"]:
				var access_nations:Array[int]=[] as Array[int] if key in ["threat","connectivity"] else owners
				_backend.call("begin_frozen_batch",state,access_nations,key in ["threat","path"],key=="supply")
			if key=="trade":_backend.call("begin_trade_batch",state,trade_graph)
			(queries[key] as Callable).call()
			if key=="trade":_backend.call("end_trade_batch",state)
			if key in ["threat","path","supply","connectivity"]:_backend.call("end_frozen_batch",state)
			var duration:=Time.get_ticks_usec()-started
			if _sample>0:durations.append(duration)
		result.append({"module":key,"queries_per_batch":owners.size(),"timing":summarize(durations),"caller_prepare_usec":shared_values_prepare_usec if key=="connectivity" else 0,"timing_scope":"caller-prepared city values; copies, roots, graph packing and connectivity included" if key=="connectivity" else "batch preparation, query computation and result conversion included","native_profile":_backend.call("profile_snapshot")})
	return result

func select_backend(name:String)->void:
	if _backend!=null:_backend.call("set_backend_for_tests",name)

func summarize(samples:Array)->Dictionary:
	if samples.is_empty():return {}
	var ordered:Array=samples.duplicate()
	ordered.sort()
	var total:=0
	for value in samples:total+=int(value)
	return {"samples":samples.size(),"mean_usec":float(total)/float(samples.size()),"p95_usec":ordered[clampi(ceili(float(ordered.size())*.95)-1,0,ordered.size()-1)],"p99_usec":ordered[clampi(ceili(float(ordered.size())*.99)-1,0,ordered.size()-1)],"peak_usec":ordered.back(),"raw_usec":samples}

static func dll_hashes()->Dictionary:
	var result:Dictionary={}
	var directory:=DirAccess.open("res://native/runtime_graph/bin")
	if directory!=null:
		for file in directory.get_files():
			if file.ends_with(".dll"):result[file]=Fixture.hash_bytes(FileAccess.get_file_as_bytes("res://native/runtime_graph/bin/"+file))
	return result

static func build_manifests()->Dictionary:
	var result:Dictionary={}
	var directory:=DirAccess.open("res://native/runtime_graph/bin")
	if directory!=null:
		for file in directory.get_files():
			if file.ends_with(".build.json"):result[file]=JSON.parse_string(FileAccess.get_file_as_string("res://native/runtime_graph/bin/"+file))
	return result
