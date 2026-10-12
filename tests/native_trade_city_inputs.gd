extends SceneTree
## Native forecast inputs retain exact integer and floating-point bytes.
class RawCity extends RefCounted:
	var id: Variant = 0
	var garrison_manpower: Variant = 10
	var war_disruption_until_day: Variant = 50
	var food_storage: Variant = 100
	var garrison_supply_ratio: Variant = 1.0

var checks := 0
var failures := 0

func _initialize(): call_deferred("run")

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("TRADE_CITY_INPUT_FAIL ",message)

func oracle(cities: Array, day: int, include_food: bool) -> Dictionary:
	var records := PackedInt64Array()
	var ratios := PackedFloat64Array()
	for city in cities:
		records.append(city.id)
		if include_food: records.append(city.food_storage)
		records.append(city.garrison_manpower)
		records.append(int(day < city.war_disruption_until_day))
		if include_food: ratios.append(city.garrison_supply_ratio)
	return {"records":records,"ratios":ratios}

func run():
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	if graph == null or not graph.has_method("pack_trade_city_inputs"):
		check(false,"native trade city input packer is registered")
		finish();return
	var cities: Array = []
	var integers := [0,1,-1,1<<35,(1<<54)+1,9223372036854775807,-9223372036854775807]
	var ratios := [0.0,-0.0,.123456789012345,INF,-INF,NAN]
	for index in range(64):
		var city := City.new()
		city.id = integers[index % integers.size()]
		city.food_storage = integers[(index+1) % integers.size()]
		city.garrison_manpower = integers[(index+2) % integers.size()]
		city.war_disruption_until_day = integers[(index+3) % integers.size()]
		city.garrison_supply_ratio = ratios[index % ratios.size()]
		cities.append(city)
	for count in [0,1,16,64]:
		var batch := cities.slice(0,count)
		for day in integers:
			for include_food in [false,true]:
				var expected := oracle(batch,day,include_food)
				var actual: Dictionary = graph.call("pack_trade_city_inputs",batch,day,include_food)
				check(var_to_bytes(actual)==var_to_bytes(expected),"complete record bytes, count=%d day=%d full=%s" %[count,day,include_food])
	cities.reverse()
	for include_food in [false,true]:
		var expected := oracle(cities,51,include_food)
		var actual: Dictionary = graph.call("pack_trade_city_inputs",cities,51,include_food)
		check(var_to_bytes(actual)==var_to_bytes(expected),"array order and repeated IDs retained")
	var first: City = cities[0]
	first.id += 1
	first.food_storage = (1<<54)+3
	first.garrison_manpower += 1
	first.war_disruption_until_day = 51
	first.garrison_supply_ratio = -0.0
	for day in [50,51,52]:
		for include_food in [false,true]:
			check(var_to_bytes(graph.call("pack_trade_city_inputs",cities,day,include_food))==var_to_bytes(oracle(cities,day,include_food)),"direct edits and exact disruption expiry are live")
	for batch in [[null],[{}],[Nation.new()],[RefCounted.new()]]:
		check((graph.call("pack_trade_city_inputs",batch,0,true) as Dictionary).has("error"),"malformed model rejected")
	for property in ["id","garrison_manpower","war_disruption_until_day","food_storage","garrison_supply_ratio"]:
		var bad := RawCity.new()
		bad.set(property,"invalid")
		check((graph.call("pack_trade_city_inputs",[bad],0,true) as Dictionary).has("error"),"invalid "+property+" rejected")
	var summary_only := RawCity.new()
	summary_only.food_storage = "unused"
	summary_only.garrison_supply_ratio = "unused"
	check(var_to_bytes(graph.call("pack_trade_city_inputs",[summary_only],49,false))==var_to_bytes(oracle([summary_only],49,false)),"summary does not read food or ratio")
	var before := var_to_bytes(oracle(cities,51,true))
	for mode in ["native","compare","gdscript"]:
		NativeCompute.set_backend_for_tests(mode)
		check(var_to_bytes(NativeCompute.trade_city_inputs([summary_only],49,false))==var_to_bytes(oracle([summary_only],49,false)),"adapter summary skips unused fields in "+mode)
		for include_food in [false,true]:
			NativeCompute.set_profiling_for_tests(true)
			var result := NativeCompute.trade_city_inputs(cities,51,include_food)
			check(var_to_bytes(result)==var_to_bytes(oracle(cities,51,include_food)),"adapter retains exact bytes in "+mode)
			if mode != "gdscript":
				check(int(NativeCompute.profile_snapshot().get("trade_city_inputs_native_call_count",0))==1,"one native call per complete city batch")
			NativeCompute.set_profiling_for_tests(false)
	check(var_to_bytes(oracle(cities,51,true))==before,"packing does not change city model inputs")
	NativeCompute.set_backend_for_tests("native")
	finish()

func finish():
	print("NATIVE_TRADE_CITY_INPUTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
