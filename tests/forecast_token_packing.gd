extends SceneTree
const Reference = preload("res://tests/support/forecast_token_reference.gd")
class LegacyTokens extends Simulation:
	func _trade_settlement_token(fingerprint: PackedByteArray, wartime: PackedByteArray = PackedByteArray()) -> PackedByteArray:
		return preload("res://tests/support/forecast_token_reference.gd")._trade_settlement_token(state,fingerprint,wartime)
	func _trade_summary_settlement_token(fingerprint: PackedByteArray, wartime: PackedByteArray = PackedByteArray()) -> PackedByteArray:
		return preload("res://tests/support/forecast_token_reference.gd")._trade_summary_settlement_token(state,fingerprint,wartime)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func token(sim: Simulation, summary: bool) -> PackedByteArray:
	return sim._trade_summary_settlement_token(PackedByteArray([1,2,3])) if summary else sim._trade_settlement_token(PackedByteArray([1,2,3]))
func legacy(sim: Simulation, summary: bool) -> PackedByteArray:
	return Reference._trade_summary_settlement_token(sim.state,PackedByteArray([1,2,3])) if summary else Reference._trade_settlement_token(sim.state,PackedByteArray([1,2,3]))
func dependency(sim: Simulation, change: Callable, restore: Callable, label: String):
	for summary in [false,true]:
		var old_before := legacy(sim,summary); var new_before := token(sim,summary)
		change.call()
		var old_after := legacy(sim,summary); var new_after := token(sim,summary)
		check((old_before==old_after)==(new_before==new_after), "same dependency partition: "+label)
		restore.call()
		check(token(sim,summary)==new_before and legacy(sim,summary)==old_before,"restored exact token: "+label)
func run():
	for seed_value in [1,7,2024]:
		var state := preload("res://tests/support/grid_world.gd").new();state.generate_world(seed_value,4,32)
		var sim := Simulation.new();sim.state = state
		for summary in [false,true]:
			var fields: Array = bytes_to_var(token(sim,summary))
			var packed := false
			for field in fields:
				if field is Array and field.size()>1 and field[0]=="cities_packed64":
					packed = field[1] is PackedInt64Array
			check(packed,"cities stored without per-city nested arrays")
		var city := state.cities[0];var nation := state.nations[0];var army := state.armies[0]
		for value in [0,1,-1,1<<32,(1<<54)+1,9223372036854775807]:
			var saved := city.food_storage
			dependency(sim,func():city.food_storage=value,func():city.food_storage=saved,"64-bit city food")
			saved=city.garrison_manpower
			dependency(sim,func():city.garrison_manpower=value,func():city.garrison_manpower=saved,"64-bit garrison")
		for value in [0.0,-0.0,.123456789012345,INF,-INF,NAN]:
			var saved := city.garrison_supply_ratio
			dependency(sim,func():city.garrison_supply_ratio=value,func():city.garrison_supply_ratio=saved,"float supply ratio")
		var saved_food := city.food_storage
		city.food_storage = 1<<54
		dependency(sim,func():city.food_storage+=1,func():city.food_storage=1<<54,"adjacent large integers stay distinct")
		city.food_storage = saved_food
		var saved_ratio := city.garrison_supply_ratio
		city.garrison_supply_ratio = .123456789012345
		dependency(sim,func():city.garrison_supply_ratio+=1e-14,func():city.garrison_supply_ratio=.123456789012345,"sub-float32 ratio changes stay distinct")
		city.garrison_supply_ratio = saved_ratio
		for change in ["disruption","city_order","family","ruler","army","stocks","day","suzerainty"]:
			var old_food := nation.granary_food;var old_size := army.size;var old_traits := nation.ruler_traits.duplicate();var old_day := state.day
			var old_disruption := city.war_disruption_until_day;var old_family := state.family_revision
			dependency(sim,func():
				match change:
					"disruption":city.war_disruption_until_day=state.day+5
					"city_order":state.cities.reverse()
					"family":state.family_revision+=1
					"ruler":nation.ruler_traits=["frugal"] as Array[String]
					"army":army.size+=400
					"stocks":nation.granary_food+=1
					"day":state.day+=1
					"suzerainty":state.suzerainty[1]={"overlord_id":0,"tribute_rate":.25,"civil_war":false}
			,func():
				state.day=old_day;city.war_disruption_until_day=old_disruption;state.family_revision=old_family
				nation.granary_food=old_food;army.size=old_size;nation.ruler_traits=old_traits
				state.suzerainty.clear()
				if change=="city_order":state.cities.reverse()
			,change)
		state.trade_enabled = true
		var oracle := LegacyTokens.new();oracle.state = state
		for mutation in range(6):
			match mutation:
				1:city.garrison_manpower+=13
				2:city.war_disruption_until_day=state.day+30
				3:city.food_storage+=17
				4:nation.treasury_gold+=19
				5:army.size+=101
			for summary in [false,true]:
				var expected := oracle._forecast_trade_and_gold_flows(summary).duplicate(true)
				var actual := sim._forecast_trade_and_gold_flows(summary)
				check(var_to_bytes(actual)==var_to_bytes(expected),"complete fiscal/settlement data agrees with old-token cache")
				check(var_to_bytes(sim._forecast_trade_and_gold_flows(summary))==var_to_bytes(expected),"warm cache agrees after mutation")
		oracle.free()
		sim.free()
	var empty := Simulation.new();empty.state=GameState.new()
	check(not token(empty,true).is_empty() and not token(empty,false).is_empty(),"empty worlds serialize safely")
	empty.free()
	print("FORECAST_TOKEN_PACKING checks=%d failures=%d"%[checks,failures.size()])
	for failure in failures:print("FAIL ",failure)
	quit(0 if failures.is_empty() else 1)
