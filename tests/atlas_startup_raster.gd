extends SceneTree
func _initialize():
	var raster=load("res://scripts/atlas/raster.gd")
	if not raster.get_script_method_list().any(func(method): return method.name=="pixel_band"):
		printerr("ATLAS_STARTUP_RASTER_FAIL independent pixel bands are available"); quit(1); return
	var before: Dictionary=FileAccess.open("res://.dbg/startup-baseline/payload.bin",FileAccess.READ).get_var()
	var world: Dictionary=before.data.environment.duplicate(); world.mesh=before.data.mesh; world.params=before.data.params
	var failures := 0
	for parallel in [false,true]:
		var generated: Dictionary=raster.build(world,true,parallel)
		generated=load("res://scripts/atlas/military_map.gd").seat_land_raster(generated,before.data,before.hierarchy)
		if var_to_bytes(generated)!=var_to_bytes(before.raster): failures+=1; printerr("ATLAS_STARTUP_RASTER_FAIL full pixels, poles, seam and ice differ: parallel=",parallel)
	print("ATLAS_STARTUP_RASTER failures=",failures); quit(1 if failures else 0)
