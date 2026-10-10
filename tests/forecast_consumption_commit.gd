extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if not value: failures.append(label)
func run():
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_world(16301,4,36)
	state.suzerainty[1] = {"overlord_id":0,"tribute_rate":.25,"civil_war":false}
	state.suzerainty[2] = {"overlord_id":1,"tribute_rate":.25,"civil_war":false}
	for army in state.armies: army.supply_food_debt = .37
	for day in [0,29,30,179,180,359]:
		state.day = day
		for pending in [false,true]:
			var cache := {"__forecast_pending_supply":pending}
			var inputs := DiplomacyAI._resource_forecast_inputs(state,cache)
			for round_id in range(3):
				var nation_id := round_id
				DiplomacyAI.commit_force_change(state,nation_id,15000,cache)
				for member in state.food_pool_members(state.food_pool_holder(nation_id)):
					var input: Dictionary = inputs[member]
					input.gold_months = 12; input.food_months = 6
					check(input.has("consumption"),"accepted recruitment retains cumulative table day%d round%d member%d"%[day,round_id,member])
					if not input.has("consumption"): continue
					for elapsed in input.consumption:
						var expected := ResourceForecastRules._consumption_at({},input.consumers,false,float(input.field_food),0.,0.,elapsed)
						check(float(input.consumption[elapsed]) == expected,"exact grain rounding day%d elapsed%d"%[day,elapsed])
					var reference := input.duplicate(); reference.erase("consumption")
					for delta in [0.,.1,90.,-90.]:
						var change := {"field_food_delta":delta}
						if delta < 0: change.replace_consumers = true
						check(ResourceForecastRules.evaluate(input,change) == ResourceForecastRules.evaluate(reference,change),"full annual forecast matches per-army oracle")
				# Tables are isolated between pool members after accepted changes.
				check(not is_same(inputs[0].consumption,inputs[1].consumption) if inputs[0].has("consumption") else true,"pool member tables cannot overwrite one another")
	for failure in failures.slice(0,10): printerr("FORECAST_CONSUMPTION_COMMIT_FAIL ",failure)
	print("FORECAST_CONSUMPTION_COMMIT_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
