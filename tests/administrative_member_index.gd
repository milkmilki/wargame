extends SceneTree
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("ADMIN_MEMBER_FAIL ",message)
func scalar(state: GameState, center: int) -> Array[int]:
	var result: Array[int] = []
	if not state.is_zhou_city(center):return result
	for id in range(state.administrative_center_by_city.size()):
		if state.administrative_center_by_city[id]==center:result.append(id)
	return result
func compare(state: GameState):
	for center in range(-1,state.administrative_center_by_city.size()+1):
		check(state.administrative_members(center)==scalar(state,center),"member values and order match direct scan")
func builds(state: GameState) -> int:
	var value: Variant = state.get("_administrative_member_cache_builds")
	return 0 if value == null else int(value)
func run():
	var state := GameState.new()
	state.administrative_center_by_city=PackedInt32Array([0,0,0,3,3,3,-1,7,7])
	compare(state)
	check(builds(state)==1,"first valid query builds one shared partition index")
	for repeat in range(20):compare(state)
	check(builds(state)==1,"warm queries avoid rebuilding the whole partition index")
	var owned := state.administrative_members(0)
	owned.clear();owned.append(999)
	check(state.administrative_members(0)==[0,1,2],"returned arrays belong to the caller")
	state.administrative_center_by_city[2]=3
	compare(state)
	check(builds(state)==2,"same-buffer direct edit invalidates without a revision bump")
	state.administrative_center_by_city=state.administrative_center_by_city.duplicate()
	compare(state)
	check(builds(state)==2,"equal replacement partition reuses the index")
	state.administrative_center_by_city[3]=0
	compare(state)
	check(state.administrative_members(3).is_empty(),"center removal is observed by the live center predicate")
	state.administrative_center_by_city.resize(2)
	compare(state)
	state.administrative_center_by_city=PackedInt32Array()
	compare(state)
	state._reset_world(49611)
	check(builds(state)==0,"world reset releases the previous index and build count")
	state.administrative_center_by_city=PackedInt32Array([0,0,2,2])
	compare(state)
	check(builds(state)==1,"regenerated partition creates its own index")
	var rng_before:=state.rng.state
	var random := RandomNumberGenerator.new();random.seed=49611
	for sample in range(60):
		var count := random.randi_range(1,96)
		state.administrative_center_by_city.resize(count)
		for id in range(count):state.administrative_center_by_city[id]=random.randi_range(-1,count+2)
		for center in range(0,count,8):state.administrative_center_by_city[center]=center
		compare(state)
	check(state.rng.state==rng_before,"read-only member queries do not advance the simulation RNG")
	var threaded := GameState.new()
	threaded.administrative_center_by_city.resize(1024)
	for id in range(1024):threaded.administrative_center_by_city[id]=id/64*64
	var outputs: Array=[];outputs.resize(128)
	var job := WorkerThreadPool.add_group_task(func(index: int):
		outputs[index]=threaded.administrative_members(index%16*64)
	,128,4)
	WorkerThreadPool.wait_for_group_task_completion(job)
	for index in range(128):check(outputs[index]==scalar(threaded,index%16*64),"concurrent first-use requests match the scalar query")
	check(builds(threaded)==1,"concurrent first-use requests publish one complete index")
	print("ADMINISTRATIVE_MEMBER_INDEX checks=",checks," failures=",failures)
	quit(1 if failures else 0)
