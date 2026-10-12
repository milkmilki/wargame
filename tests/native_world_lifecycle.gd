extends SceneTree
## Real manual day stepping must commit before the preview's world-swap gate resumes.
var _preview:Variant
var _simulation:Simulation
var _previous:GameState
var _replacement:GameState
var _step_finished:=false
var _swap_finished:=false
var _commit_seen:=false
var _commit_day:=-1
var _checks:=0
var _failures:Array[String]=[]

func _initialize()->void:
	call_deferred("run")

func check(condition:bool,message:String)->void:
	_checks+=1
	if not condition:_failures.append(message)

func _finish_step()->void:
	var succeeded:bool=await _simulation.advance_one_day()
	check(succeeded,"actual manual advance_one_day completes successfully")
	_step_finished=true

func _swap_after_pause()->void:
	await _preview._pause_previous_world()
	check(_commit_seen,"world-swap gate returns only after runtime commit signal")
	check(not _simulation.runtime_day_in_progress(),"world-swap gate returns after in-flight day guard clears")
	_preview.state=_replacement
	_swap_finished=true

func _on_commit(day:int)->void:
	check(_preview.state==_previous,"previous state remains active at the actual commit boundary")
	check(not _swap_finished,"replacement has not been published before old-day commit")
	_commit_seen=true
	_commit_day=day

func run()->void:
	NativeCompute.set_backend_for_tests("native")
	_previous=preload("res://tests/support/grid_world.gd").new()
	_previous.generate_world(12345,16,160)
	_replacement=preload("res://tests/support/grid_world.gd").new()
	_replacement.generate_world(67890,4,40)
	_simulation=Simulation.new()
	root.add_child(_simulation)
	_simulation.setup(_previous)
	_simulation.paused=true
	# Instantiate the real preview without its automatic map-generation _ready path.
	_preview=(load("res://atlas_military.tscn") as PackedScene).instantiate()
	_preview.state=_previous
	_preview.simulation=_simulation
	_simulation.runtime_day_committed.connect(_on_commit)
	_finish_step()
	check(_simulation.runtime_day_in_progress(),"real advance_one_day enters an asynchronous in-flight day")
	check(not _step_finished,"actual day step has yielded before lifecycle request")
	_swap_after_pause()
	check(not _swap_finished,"pause_previous_world waits for the running day")
	check(_preview.state==_previous,"replacement is withheld while old computation is in flight")
	check(_simulation.paused,"pause_previous_world prevents another automatic day")
	var deadline:=Time.get_ticks_msec()+30000
	while (not _swap_finished or not _step_finished) and Time.get_ticks_msec()<deadline:
		await process_frame
	check(_swap_finished and _step_finished,"running day and pending lifecycle request both finish")
	check(_commit_seen and _commit_day==1 and _previous.day==1,"exactly one real old-world day commits")
	check(_preview.state==_replacement and _replacement.day==0,"replacement becomes active with its own untouched day")
	check(not _simulation.runtime_day_in_progress(),"old simulation has no outstanding day after swap gate")
	check(_simulation.state==_previous,"old simulation remains bound to its original world until disposal")
	_preview.simulation=null
	_preview.free()
	_simulation.queue_free()
	await process_frame
	NativeCompute.clear_caches_for_tests()
	for failure in _failures:printerr("NATIVE_WORLD_LIFECYCLE_FAIL ",failure)
	print("NATIVE_WORLD_LIFECYCLE_RESULT checks=%d failures=%d commit_day=%d"%[_checks,_failures.size(),_commit_day])
	quit(0 if _failures.is_empty() else 1)
