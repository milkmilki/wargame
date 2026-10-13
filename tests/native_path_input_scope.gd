extends SceneTree
const Factory = preload("res://tests/native_graph_equivalence.gd")
class CustomState extends GameState:
	pass
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("PATH_SCOPE_FAIL ",label)
func compare_path(state: GameState, start: int, nation: int, contested: bool, goal: int, danger: bool = true, blocked: Dictionary = {}, exit_city: int = -1) -> void:
	var expected := Pathfinding._dijkstra_field_gdscript(state,start,nation,contested,danger,goal,0,blocked,exit_city)
	var actual := Pathfinding.dijkstra_field(state,start,nation,contested,danger,goal,0,blocked,exit_city)
	check(var_to_bytes(expected) == var_to_bytes(actual), "exact path values, predecessors and order")
func worker_scope(state: GameState) -> Array:
	return [NativeCompute.begin_path_input_scope(state), NativeCompute._path_input_scope(state).is_empty()]
func run() -> void:
	var backend: Script = load("res://scripts/core/native_compute.gd")
	check(backend.has_method("begin_path_input_scope"),"explicit lazy path input scope exists")
	if failures > 0: quit(1); return
	var factory := Factory.new()
	var state: GameState = factory.fixture(false)
	factory.free()
	var rng_before := state.rng.state
	var custom := CustomState.new()
	custom.atlas_layout = state.atlas_layout
	check(not bool(backend.call("begin_path_input_scope",custom)),"custom access callbacks use live queries")
	if NativeCompute.backend() == "gdscript":
		check(not bool(backend.call("begin_path_input_scope",state)),"GDScript backend declines native scope")
		compare_path(state,0,0,true,1)
		print("PATH_INPUT_SCOPE checks=%d failures=%d" % [checks,failures])
		quit(0 if failures == 0 else 1)
		return
	NativeCompute.set_profiling_for_tests(true)
	check(bool(backend.call("begin_path_input_scope",state)),"scope begins")
	check(not NativeCompute.begin_frozen_batch(state,[0] as Array[int],true,true),"nested frozen batch cannot replace a path scope")
	check(NativeCompute._batch(state).is_empty(),"declined frozen batch leaves registry empty")
	check(NativeCompute.profile_snapshot().is_empty(),"an unused scope does not pack graph inputs")
	check(not bool(backend.call("begin_path_input_scope",state)),"nested scope cannot replace its owner")
	var thread := Thread.new()
	thread.start(worker_scope.bind(state))
	var worker: Array = thread.wait_to_finish()
	check(not worker[0] and worker[1],"workers cannot open or read a mutable main-thread scope")
	for nation in [-1,0,1,2]:
		for goal in [-1,1,2]:
			for start in [0,3,4]:
				compare_path(state,start,nation,false,goal)
	compare_path(state,4,0,false,1,true,{6:true},3)
	compare_path(state,4,0,false,-1,true,{},2)
	compare_path(state,4,0,false,2)
	var first := NativeCompute.profile_snapshot()
	check(int(first.get("edge_inputs_native_pack_call_count",0)) == 1,"same cost mode captured once")
	check(int(first.get("owner_inputs_native_pack_call_count",0)) == 1,"ownership captured once")
	compare_path(state,0,0,true,1)
	state.armies[0].on_edge = false
	compare_path(state,0,0,true,1)
	compare_path(state,0,0,false,-1,false)
	var expected := Pathfinding._supply_loss_field_gdscript(state,0,0,{},false,[] as Array[int],false)
	var actual := Pathfinding._supply_loss_field(state,0,0)
	check(var_to_bytes(expected) == var_to_bytes(actual),"supply mode and packed outputs remain exact")
	for logistics in [false,true]:
		for nation in [0,1,2]:
			var blocked := {GameState.edge_key(0,5):true}
			var origins: Array[int] = [3]
			expected = Pathfinding._supply_loss_field_gdscript(state,0,nation,blocked,true,origins,logistics)
			actual = Pathfinding._supply_loss_field(state,0,nation,blocked,true,origins,logistics)
			check(var_to_bytes(expected) == var_to_bytes(actual),"supply profiles keep origins, blockers and logistics separate")
	var later := NativeCompute.profile_snapshot()
	check(int(later.get("edge_inputs_native_pack_call_count",0)) == 3,"each distinct cost mode captured once")
	check(int(later.get("owner_inputs_native_pack_call_count",0)) == 1,"cost modes reuse ownership")
	backend.call("end_path_input_scope",state)
	check(bool(backend.call("begin_path_input_scope",state)),"scope starts before cache reset")
	NativeCompute.clear_caches_for_tests()
	check(bool(backend.call("begin_path_input_scope",state)),"cache reset also retires path scopes")
	backend.call("end_path_input_scope",state)
	NativeCompute.set_profiling_for_tests(false)
	state.edges[1].precise_distance = 3.75
	state.edges[1].danger = .6
	state.edges[1].control_city_id = 2
	state.edges[0].max_manpower = 0
	state.cities[3].owner_nation = 2
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
	compare_path(state,0,0,false,-1)
	check(bool(backend.call("begin_path_input_scope",state)),"next scope starts after direct edits")
	compare_path(state,0,0,false,-1)
	backend.call("end_path_input_scope",state)
	check(NativeCompute.begin_frozen_batch(state,[0,1,2] as Array[int],true,true),"existing frozen batch starts")
	check(not bool(backend.call("begin_path_input_scope",state)),"existing frozen batch retains ownership")
	backend.call("end_path_input_scope",state)
	check(not NativeCompute._batch(state).is_empty(),"ending an unowned scope leaves outer batch intact")
	NativeCompute.end_frozen_batch(state)
	check(bool(backend.call("begin_path_input_scope",state)),"unused scope can be invalidated")
	NativeCompute.invalidate_state(state)
	check(bool(backend.call("begin_path_input_scope",state)),"invalidation drops the old scope")
	backend.call("end_path_input_scope",state)
	check(state.rng.state == rng_before,"query scopes consume no RNG")
	print("PATH_INPUT_SCOPE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
