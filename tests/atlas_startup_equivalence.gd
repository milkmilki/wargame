extends SceneTree
## Full native generated inputs, not only city counts or a visual approximation.
var failures := 0
func _initialize():
	var directory := "res://.dbg/startup-cold"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--startup-evidence="): directory=arg.trim_prefix("--startup-evidence=")
	var before: Dictionary=FileAccess.open("res://.dbg/startup-baseline/payload.bin",FileAccess.READ).get_var()
	var after: Dictionary=FileAccess.open(directory+"/payload.bin",FileAccess.READ).get_var()
	for field in ["mesh","environment","regions","cities","roads","ownership","nations","places"]:
		if var_to_bytes(before.data[field])!=var_to_bytes(after.data[field]): failures+=1; printerr("STARTUP_EQUIVALENCE_FAIL data.",field)
	for field in ["raster","hierarchy","graph","ownership","district_pixels","settlement_adjacency","strategic_routes","territorial_pairs"]:
		if var_to_bytes(before[field])!=var_to_bytes(after[field]): failures+=1; printerr("STARTUP_EQUIVALENCE_FAIL ",field)
	print("ATLAS_STARTUP_EQUIVALENCE failures=",failures); quit(1 if failures else 0)
