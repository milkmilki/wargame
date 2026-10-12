extends SceneTree
## Whole-state exactness: serial or frame-sliced, actual EURASIA, schema 28 and RNG.
const Fixture=preload("res://tests/support/native_runtime_fixture.gd")
const BACKEND_PATH:="res://scripts/core/native_compute.gd"
var _backend:Script

func _initialize()->void:
	call_deferred("run")

func run()->void:
	if not ResourceLoader.exists(BACKEND_PATH):
		printerr("NATIVE_RUNTIME_RED missing runtime backend")
		quit(1)
		return
	_backend=load(BACKEND_PATH)
	var days:=30
	var seeds:Array[int]=[1]
	var sliced:=false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--days="):days=int(argument.get_slice("=",1))
		elif argument.begins_with("--seeds="):
			seeds.clear()
			for item in argument.get_slice("=",1).split(","):seeds.append(int(item))
		elif argument=="--sliced":sliced=true
	for seed_value in seeds:
		_backend.call("set_backend_for_tests","gdscript")
		var payload:Dictionary=preload("res://tests/atlas_military_inputs.gd").eurasia_military(seed_value)
		var first:=GameState.new()
		first.generate_from_atlas(payload.duplicate(true))
		var second:=GameState.new()
		second.generate_from_atlas(payload.duplicate(true))
		var error:=Fixture.validate_world(first,seed_value)
		if not error.is_empty():
			printerr("NATIVE_RUNTIME_INVALID ",error)
			quit(1)
			return
		var log:=DebugRunLog.new()
		log.begin("tests/native_runtime_equivalence.gd")
		log.world_started(first,{"days":days,"seeds":seeds,"sliced":sliced,"model":payload.model},"native_runtime_equivalence")
		var oracle:=Simulation.new()
		root.add_child(oracle)
		oracle.setup(first)
		oracle.paused=true
		var subject:=Simulation.new()
		root.add_child(subject)
		_backend.call("set_backend_for_tests","native")
		subject.setup(second)
		subject.paused=true
		if not same_state(first,second):
			printerr("NATIVE_RUNTIME_FAIL initial state seed=",seed_value)
			quit(1)
			return
		for _day in range(days):
			_backend.call("set_backend_for_tests","gdscript")
			if sliced:await oracle.advance_one_day()
			else:oracle._advance_day()
			_backend.call("set_backend_for_tests","native")
			if sliced:await subject.advance_one_day()
			else:subject._advance_day()
			if not same_state(first,second):
				DirAccess.make_dir_recursive_absolute("res://.dbg/native-runtime")
				FileAccess.open("res://.dbg/native-runtime/failed-gdscript.bin",FileAccess.WRITE).store_var(Fixture.snapshot(first),false)
				FileAccess.open("res://.dbg/native-runtime/failed-native.bin",FileAccess.WRITE).store_var(Fixture.snapshot(second),false)
				printerr("NATIVE_RUNTIME_FAIL seed=%d day=%d"%[seed_value,first.day])
				quit(1)
				return
			if first.day%120==0: print("NATIVE_RUNTIME_PROGRESS seed=%d day=%d"%[seed_value,first.day])
		print("NATIVE_RUNTIME_SEED_PASS seed=%d days=%d sliced=%s sha256=%s"%[seed_value,days,sliced,Fixture.hash_bytes(var_to_bytes(Fixture.snapshot(first)))])
		oracle.queue_free()
		subject.queue_free()
		await process_frame
	print("NATIVE_RUNTIME_PASS seeds=%s days=%d schema=%d sliced=%s"%[seeds,days,NativeSnapshotBuilder.SCHEMA_VERSION,sliced])
	quit()

func same_state(first:GameState,second:GameState)->bool:
	return var_to_bytes(Fixture.snapshot(first))==var_to_bytes(Fixture.snapshot(second))
