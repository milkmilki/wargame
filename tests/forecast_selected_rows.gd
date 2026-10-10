extends SceneTree
const Reference = preload("res://tests/support/forecast_inputs_reference.gd")
class CountBuilder extends DiplomacyAI.ForecastInputBuilder:
	var city_calls := 0
	var center_calls := 0
	var visited_cities: Array[int] = []
	var visited_centers: Array[int] = []
	func city(value: City) -> void:
		city_calls += 1; visited_cities.append(value.id); super.city(value)
	func center(value: int) -> void:
		center_calls += 1; visited_centers.append(value); super.center(value)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures.append(label)
func run():
	for seed_value in [1,7,2024]:
		for civil in [false,true]:
			var state := preload("res://tests/support/grid_world.gd").new(); state.generate_world(seed_value,4,36)
			state.suzerainty[1] = {"overlord_id":0,"tribute_rate":.25,"civil_war":civil}
			state.suzerainty[2] = {"overlord_id":1,"tribute_rate":.25,"civil_war":false}
			# Keep the original center traversal order, including repeated entries.
			state.administrative_center_city_ids.reverse()
			if not state.administrative_center_city_ids.is_empty(): state.administrative_center_city_ids.append(state.administrative_center_city_ids[0])
			for pending in [false,true]:
				var reference := Reference.new(state,{"__forecast_pending_supply":pending})
				while reference.phase<4: reference.step()
				var cache := {"__forecast_pending_supply":pending}
				DiplomacyAI._ensure_evaluation_cache_current(state,cache)
				var inputs: Array[Dictionary] = []
				for _nation in state.nations: inputs.append({})
				for requested in [3,1,0,2]:
					var work := DiplomacyAI._forecast_input_work_ids(state,inputs,requested)
					if work.is_empty(): continue
					var builder := CountBuilder.new(state,cache,work,inputs)
					while builder.phase<4: builder.step()
					var selected_cities := 0; var selected_centers := 0
					var expected_cities: Array[int] = []; var expected_centers: Array[int] = []
					for city in state.cities:
						if work.has(city.owner_nation): selected_cities += 1; expected_cities.append(city.id)
					for id in state.administrative_center_city_ids:
						if work.has(state.cities[id].owner_nation): selected_centers += 1; expected_centers.append(id)
					check(builder.city_calls == selected_cities,"only selected raw-owner cities visited")
					check(builder.center_calls == selected_centers,"only selected centers visited with duplicates")
					check(builder.visited_cities == expected_cities,"original selected city order")
					check(builder.visited_centers == expected_centers,"original selected center order")
					inputs = builder.inputs; cache.resource_forecast_inputs = inputs
					for id in work: check(inputs[id] == reference.inputs[id],"numerical input equals independent eager reference")
				check(inputs == reference.inputs,"all pools match reference")
				check(cache.has("forecast_scan_rows"),"scan index retained within batch")
				if cache.has("forecast_scan_rows"):
					var prior: Dictionary = cache.forecast_scan_rows
					cache.erase("resource_forecast_inputs")
					DiplomacyAI._resource_forecast_inputs(state,cache,3)
					check(is_same(prior,cache.forecast_scan_rows),"same batch reuses node index")
					state.day += 1
					DiplomacyAI._resource_forecast_inputs(state,cache,3)
					check(not is_same(prior,cache.forecast_scan_rows),"new day invalidates node index")
					state.day -= 1
	var proxy_state := preload("res://tests/support/grid_world.gd").new(); proxy_state.generate_world(7,4,36)
	var proxy := Nation.new(); proxy.id = 4; proxy.succession_identity = true; proxy.capital_city_id = -1; proxy_state.nations.append(proxy)
	var conflict := SuccessionConflict.new(); conflict.nation_id = 0; conflict.rebel_nation_id = 4; proxy_state.succession_conflicts[0] = conflict
	var proxy_cache := {}
	for mutation in ["proxy","ownership","centers","new_day"]:
		if mutation == "ownership":
			proxy_state.cities[0].owner_nation = 3; proxy_state.ownership_revision += 1
		if mutation == "centers":
			proxy_state.administrative_center_city_ids.reverse(); proxy_state.administrative_region_revision += 1
		if mutation == "new_day": proxy_state.day += 1
		var baseline := Reference.new(proxy_state,{})
		while baseline.phase<4: baseline.step()
		check(DiplomacyAI._resource_forecast_inputs(proxy_state,proxy_cache) == baseline.inputs,"fresh full inputs after "+mutation)
	var empty := GameState.new(); var empty_cache := {}
	check(DiplomacyAI._resource_forecast_inputs(empty,empty_cache).is_empty(),"empty world")
	for failure in failures: printerr("FORECAST_SELECTED_ROWS_FAIL ",failure)
	print("FORECAST_SELECTED_ROWS_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
