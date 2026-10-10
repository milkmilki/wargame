extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_STARTUP_CLIMATE_FAIL ",message)
func _initialize():
	var model=load("res://scripts/atlas/seasonal_circulation.gd")
	check(model.get_script_method_list().any(func(method): return method.name=="steady_quarter"),"independent quarters are available for parallel generation")
	var fixture: Dictionary=FileAccess.open("res://tests/fixtures/atlas_startup_climate.bin",FileAccess.READ).get_var()
	for parallel in [false,true]:
		var options: Dictionary=fixture.options.duplicate(); options.parallel=parallel
		var actual: Dictionary=model.build_fields(fixture.heights,fixture.land,fixture.size,options)
		check(var_to_bytes(actual)==var_to_bytes(fixture.expected),"all seasonal fields, winds and metadata match the frozen pre-optimization model: parallel=%s"%parallel)
	print("ATLAS_STARTUP_CLIMATE failures=",failures); quit(1 if failures else 0)
