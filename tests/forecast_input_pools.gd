extends SceneTree
const Reference = preload("res://tests/support/forecast_inputs_reference.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if not value: failures.append(label)
func eager(state: GameState,pending: bool = false) -> Array[Dictionary]:
	var builder := Reference.new(state,{"__forecast_pending_supply":pending})
	while builder.phase<4: builder.step()
	return builder.inputs
func run():
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_world(17401,4,36)
	state.suzerainty[1] = {"overlord_id":0,"tribute_rate":.25,"civil_war":false}
	state.suzerainty[2] = {"overlord_id":1,"tribute_rate":.25,"civil_war":false}
	for pending in [false,true]:
		var expected := eager(state,pending)
		var cache := {"__forecast_pending_supply":pending}
		DiplomacyAI.resource_forecast(state,1,-1,-1,cache)
		var inputs: Array[Dictionary] = cache.resource_forecast_inputs
		check(inputs[3].is_empty(),"unrelated pool stays unprepared")
		for id in [0,1,2]: check(inputs[id] == expected[id],"complete multilevel pool matches eager reference")
		DiplomacyAI.commit_force_change(state,1,15000,cache)
		var committed: Dictionary = inputs[1].duplicate(true)
		DiplomacyAI.resource_forecast(state,3,-1,-1,cache)
		check(cache.resource_forecast_inputs[1] == committed,"new pool preserves prior accepted conservative demand")
		check(cache.resource_forecast_inputs[3] == expected[3],"independent pool matches eager reference")
		check(DiplomacyAI._resource_forecast_inputs(state,cache).size() == 4,"default helper still materializes all inputs")
	state.suzerainty[1].civil_war = true
	var expected := eager(state)
	var cache := {}
	DiplomacyAI.resource_forecast(state,1,-1,-1,cache)
	check(cache.resource_forecast_inputs[0].is_empty() and cache.resource_forecast_inputs[3].is_empty(),"civil war separates shared pools")
	check(cache.resource_forecast_inputs[1] == expected[1] and cache.resource_forecast_inputs[2] == expected[2],"civil-war subtree has complete matching inputs")
	var proxy := Nation.new(); proxy.id = 4; proxy.succession_identity = true; proxy.capital_city_id = -1; state.nations.append(proxy)
	var conflict := SuccessionConflict.new(); conflict.nation_id = 0; conflict.rebel_nation_id = 4; state.succession_conflicts[0] = conflict
	expected = eager(state); cache = {}
	DiplomacyAI.resource_forecast(state,0,-1,-1,cache)
	check(not cache.resource_forecast_inputs[4].is_empty(),"financial proxy belongs to requested pool even without a city")
	check(cache.resource_forecast_inputs[4] == expected[4],"proxy inputs match full eager reference")
	var first: Dictionary = cache.resource_forecast_inputs[0]
	await DiplomacyAI.resource_forecast_inputs_over_frames(state,cache,self,1)
	check(cache.resource_forecast_inputs[1] == expected[1] and cache.resource_forecast_inputs[2] == expected[2],"sliced preparation fills a complete civil-war pool")
	check(is_same(first,cache.resource_forecast_inputs[0]),"sliced preparation preserves existing input objects")
	var full := await DiplomacyAI.resource_forecast_inputs_over_frames(state,cache,self)
	check(full == expected,"default sliced helper completes all remaining pools")
	state.day += 1
	DiplomacyAI.resource_forecast(state,3,-1,-1,cache)
	check(cache.resource_forecast_inputs[0].is_empty(),"new day invalidates old partial aggregates")
	var empty := GameState.new(); var empty_cache := {}
	check(DiplomacyAI._resource_forecast_inputs(empty,empty_cache).is_empty() and empty_cache.has("resource_forecast_inputs"),"empty world retains eager cache contract")
	for seed_value in [17,17401,12345]:
		var sample := preload("res://tests/support/grid_world.gd").new(); sample.generate_world(seed_value,4,36)
		for sample_day in [0,29,179,360]:
			sample.day = sample_day
			for pending in [false,true]:
				var baseline := eager(sample,pending); var batch := {"__forecast_pending_supply":pending}
				for id in [3,1,0,2]:
					DiplomacyAI.resource_forecast(sample,id,-1,-1,batch)
					check(batch.resource_forecast_inputs[id] == baseline[id],"stable numeric inputs across seeds, dates and out-of-order requests")
				check(DiplomacyAI._resource_forecast_inputs(sample,batch) == baseline,"completed batch matches unchanged eager implementation")
	for failure in failures: printerr("FORECAST_INPUT_POOLS_FAIL ",failure)
	print("FORECAST_INPUT_POOLS_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
