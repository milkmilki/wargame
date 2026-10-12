extends SceneTree
## Runs in the editor/debug engine and in the exported Windows release probe.
## Error probes are isolated subprocesses; they never rename the game's DLL.
var failures := 0

func _initialize() -> void:
	var mode := "normal"
	var expect_release := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--probe="):
			mode = argument.trim_prefix("--probe=")
		if argument == "--expect-release":
			expect_release = true
	if expect_release:
		check(not OS.has_feature("debug"), "probe uses a real release template")
		check(NativeCompute.backend() == "native", "release forces native despite development environment")
	if mode != "normal":
		_run_error_probe(mode)
		return
	check(NativeCompute.require_native(), "native extension loads")
	check(ClassDB.class_exists("NativeGraphSnapshot"), "native snapshot registered")
	if ClassDB.class_exists("NativeGraphSnapshot"):
		var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
		check(graph.call("api_version") == 5, "native API version 5")
		for method in ["configure", "query_travel", "query_path", "query_trade", "query_connectivity", "make_access_mask", "patch_access_mask", "query_connectivity_filtered", "pack_edge_inputs", "pack_owner_inputs", "query_administrative_fields", "query_key_order", "pack_trade_city_inputs"]:
			check(graph.has_method(method), "native method " + method)
		check(graph.call("configure", PackedInt32Array([0, 0]), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedFloat64Array([0.0, 0.0, 0.5, 0.0, 0.0])), "empty-edge snapshot configures")
		var city := City.new()
		city.id = (1 << 54) + 1
		city.food_storage = (1 << 54) + 3
		city.garrison_manpower = (1 << 35) + 1
		city.garrison_supply_ratio = -0.0
		city.war_disruption_until_day = 51
		for include_food in [false, true]:
			var records := PackedInt64Array([city.id, city.garrison_manpower, 1])
			var ratios := PackedFloat64Array()
			if include_food:
				records.insert(1, city.food_storage)
				ratios.append(city.garrison_supply_ratio)
			var packed: Dictionary = graph.call("pack_trade_city_inputs", [city], 50, include_food)
			check(var_to_bytes(packed) == var_to_bytes({"records": records, "ratios": ratios}), "release forecast packing preserves wide integers and signed zero")
		for count in [0, 1, 16, 17, 64]:
			var keys := []
			var expected: Array[int] = []
			for index in range(count):
				keys.append([index % 3, (1 << 60) + index % 2])
				expected.append(index)
			expected.sort_custom(func(a: int, b: int) -> bool:
				return EquivariantOrder._key_less(keys[a], keys[b]))
			var result: Dictionary = graph.call("query_key_order", keys)
			check(not result.has("error") and result.get("order") == PackedInt32Array(expected), "native key permutation size %d" % count)
	var descriptor := ConfigFile.new()
	check(descriptor.load(NativeCompute.EXTENSION_PATH) == OK, "extension descriptor included")
	check(descriptor.get_value("configuration", "entry_symbol", "") == "runtime_graph_library_init", "descriptor entry symbol")
	check(descriptor.get_value("configuration", "compatibility_minimum", "") == "4.7.1", "descriptor minimum engine")
	for target in ["debug", "release"]:
		check(descriptor.get_value("libraries", "windows.%s.x86_64" % target, "") == "res://native/runtime_graph/bin/runtime_graph.windows.template_%s.x86_64.dll" % target, "descriptor selects " + target + " DLL")
	print("NATIVE_EXTENSION_CONTRACT failures=", failures, " debug=", OS.has_feature("debug"), " backend=", NativeCompute.backend())
	quit(1 if failures else 0)

func _run_error_probe(mode: String) -> void:
	if not OS.has_feature("debug"):
		push_error("Fixture error probes require the debug engine")
		quit(3)
		return
	var source := FileAccess.get_file_as_string("res://scripts/core/native_compute.gd")
	source = source.replace("class_name NativeCompute\n", "")
	if mode == "api_mismatch":
		source = source.replace("const API_VERSION := 5", "const API_VERSION := 999")
	elif mode == "missing":
		NativeCompute.clear_caches_for_tests()
		if ClassDB.class_exists("NativeGraphSnapshot"):
			GDExtensionManager.unload_extension(NativeCompute.EXTENSION_PATH)
		check(not ClassDB.class_exists("NativeGraphSnapshot"), "missing probe unloaded existing class")
		var descriptor_path := "res://native/runtime_graph/.cache/contract_missing.gdextension"
		var descriptor := FileAccess.open(descriptor_path, FileAccess.WRITE)
		descriptor.store_string('[configuration]\nentry_symbol="runtime_graph_library_init"\ncompatibility_minimum="4.7.1"\n[libraries]\nwindows.x86_64="res://native/runtime_graph/.cache/absent_contract.dll"\n')
		descriptor.close()
		source = source.replace(NativeCompute.EXTENSION_PATH, descriptor_path)
	else:
		push_error("Unknown error probe " + mode)
		quit(3)
		return
	var fixture_path := "res://native/runtime_graph/.cache/native_contract_%s.gd" % mode
	var fixture := FileAccess.open(fixture_path, FileAccess.WRITE)
	fixture.store_string(source)
	fixture.close()
	var adapter: GDScript = load(fixture_path)
	adapter.call("set_backend_for_tests", "native")
	var accepted: bool = adapter.call("require_native")
	if accepted:
		push_error("Native error probe silently accepted " + mode)
		quit(3)
		return
	# require_native schedules quit(1) and emits its actionable error message.
	print("NATIVE_EXTENSION_EXPECTED_FAILURE mode=", mode, " backend=", adapter.call("backend"))

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: ", description)
