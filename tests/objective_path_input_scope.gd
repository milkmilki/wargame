extends SceneTree
var failures: Array[String] = []
var checks := 0
var saved_packs := 0
var selected := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func compare(state: GameState, actor: int, target: int, label: String):
	for context in [DiplomacyAI.ObjectiveContext.PREWAR, DiplomacyAI.ObjectiveContext.CAMPAIGN]:
		var before := var_to_bytes([state.rng.state, state.diplomatic_relations, state.suzerainty])
		NativeCompute.set_profiling_for_tests(true)
		var expected := DiplomacyAI._select_war_objective_from_inputs(state,actor,target,{},-1,false,{},false,context)
		var reference := NativeCompute.profile_snapshot()
		NativeCompute.set_profiling_for_tests(true)
		var actual := DiplomacyAI.select_war_objective(state,actor,target,{},-1,false,{},false,context)
		var profile := NativeCompute.profile_snapshot()
		saved_packs += int(reference.get("edge_inputs_native_pack_call_count",0)) - int(profile.get("edge_inputs_native_pack_call_count",0))
		selected += int(not actual.is_empty())
		check(var_to_bytes(actual) == var_to_bytes(expected), label + ": complete ordered objective equals standalone searches")
		check(NativeCompute._path_input_scope(state).is_empty(), label + ": query retires its input scope")
		check(int(profile.get("edge_inputs_native_pack_call_count",0)) <= int(reference.get("edge_inputs_native_pack_call_count",0)), label + ": scoped query never packs more road inputs")
		check(before == var_to_bytes([state.rng.state,state.diplomatic_relations,state.suzerainty]), label + ": political inputs and RNG unchanged")
func run():
	NativeCompute.set_backend_for_tests("native")
	var state := GameState.new()
	state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").eurasia_military())
	for actor in range(4):
		var targets := DiplomacyAI._direct_bordering_nation_ids(state, actor, {})
		if targets.is_empty(): continue
		var target := int(targets[0])
		compare(state,actor,target,"actor%d" % actor)
		check(NativeCompute.begin_path_input_scope(state), "outer scope starts")
		DiplomacyAI.select_war_objective(state,actor,target,{})
		check(not NativeCompute._path_input_scope(state).is_empty(), "nested query preserves caller's scope")
		NativeCompute.end_path_input_scope(state)
		state.set_diplomatic_relation(actor,target,GameState.DiplomaticRelation.WAR)
		compare(state,target,actor,"reverse wartime actor%d" % target)
	var start := state.nations[0].capital_city_id
	var before := Pathfinding.dijkstra_field(state,start,0,false,true)
	var edge: Edge
	for destination in before.prev:
		var origin := int(before.prev[destination])
		if origin >= 0:
			edge = state.edge_of(origin,int(destination))
			if edge != null: break
	check(edge != null, "live-edit guard selects a road used by the actual field")
	if edge == null: quit(1); return
	edge.max_manpower = 0
	edge.danger = .8
	check(var_to_bytes(before) != var_to_bytes(Pathfinding.dijkstra_field(state,start,0,false,true)), "retired scopes observe a route-changing direct edit")
	compare(state,0,1,"live capacity and cost edits")
	check(selected > 0, "real world exercises reachable targets")
	check(saved_packs > 0, "real objective queries eliminate repeated road packing")
	print("OBJECTIVE_INPUT_PACKS_SAVED ",saved_packs)
	NativeCompute.set_profiling_for_tests(false)
	for failure in failures: printerr("OBJECTIVE_PATH_INPUT_SCOPE_FAIL ",failure)
	print("OBJECTIVE_PATH_INPUT_SCOPE_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
