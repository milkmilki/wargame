extends SceneTree
## Simulation 贸易/财政预测缓存等价守卫。
##
## 1. 两个同 seed 世界逐日走相同的同步运行路径，只切换缓存开关，并比较
##    递归序列化后的完整 GameState；
## 2. 静态世界跨日只构建一次 trade structure，且完整 settlement token 不变时
##    复用 trade result + gold_flows；
## 3. 单独修改一个动态依赖（国库）必须只令 settlement miss，结构仍命中。

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var days := _env_int("TRADE_FORECAST_EQUIV_DAYS", 60)
	var nations := _env_int("TRADE_FORECAST_EQUIV_NATIONS", 8)
	var cities := _env_int("TRADE_FORECAST_EQUIV_CITIES", 32)
	var baseline := _make_simulation(nations, cities, true)
	var cached := _make_simulation(nations, cities, false)
	var compared_days := 0
	for _day in range(days):
		baseline._advance_day(false)
		cached._advance_day(false)
		compared_days += 1
		var baseline_fingerprint := _state_fingerprint(baseline.state)
		var cached_fingerprint := _state_fingerprint(cached.state)
		_check(
			baseline_fingerprint == cached_fingerprint,
			"daily_full_state_equivalence/day_%d" % baseline.state.day,
			"baseline_bytes=%d cached_bytes=%d" % [
				baseline_fingerprint.size(), cached_fingerprint.size(),
			]
		)
		if baseline_fingerprint != cached_fingerprint:
			break
		if baseline.state.winner != -1 or cached.state.winner != -1:
			break

	_check(compared_days > 0, "daily_full_state_equivalence/exercised")
	_check(
		baseline.trade_structure_build_total > 0
			and baseline.trade_forecast_build_total > 0,
		"disabled_cache/builds_every_request",
		_counter_detail(baseline)
	)
	_check(
		baseline.trade_structure_cache_hit_total == 0
			and baseline.trade_forecast_cache_hit_total == 0,
		"disabled_cache/no_hits",
		_counter_detail(baseline)
	)
	_check(
		cached.trade_structure_cache_hit_total > 0
			and cached.trade_forecast_cache_hit_total > 0,
		"enabled_cache/records_hits",
		_counter_detail(cached)
	)
	_check(
		cached.trade_structure_build_total
			< baseline.trade_structure_build_total
			and cached.trade_forecast_build_total
				< baseline.trade_forecast_build_total,
		"enabled_cache/reduces_builds",
		"baseline=%s cached=%s" % [
			_counter_detail(baseline), _counter_detail(cached),
		]
	)
	_check(
		baseline.trade_structure_build_total
			== baseline.trade_forecast_build_total
			and cached.trade_structure_build_total
				+ cached.trade_structure_cache_hit_total
				== cached.trade_forecast_build_total
					+ cached.trade_forecast_cache_hit_total,
		"counters/every_request_accounted",
		"baseline=%s cached=%s" % [
			_counter_detail(baseline), _counter_detail(cached),
		]
	)

	_test_static_cross_day_hits()
	_test_single_dependency_miss()
	_test_war_preparation_shared_forecast()

	print("=== 贸易预测缓存等价校验 (%d国/%d城/%d天) ===" % [
		nations, cities, compared_days,
	])
	print("基线计数 %s" % _counter_detail(baseline))
	print("缓存计数 %s" % _counter_detail(cached))
	if _failures.is_empty():
		print("TRADE_FORECAST_CACHE_EQUIVALENT checks=%d" % _checks)
	else:
		for failure in _failures:
			push_error("TRADE_FORECAST_CACHE_FAIL: " + failure)
		print("TRADE_FORECAST_CACHE_DIVERGED checks=%d failures=%d" % [
			_checks, _failures.size(),
		])
	baseline.free()
	cached.free()
	quit(0 if _failures.is_empty() else 1)


func _make_simulation(
	nation_count: int,
	city_count: int,
	disable_cache: bool
) -> Simulation:
	var world := GameState.new()
	world.generate_world(12345, nation_count, city_count)
	var sim := Simulation.new()
	sim.trade_forecast_cache_disabled = disable_cache
	root.add_child(sim)
	sim.setup(world)
	return sim


func _test_static_cross_day_hits() -> void:
	var sim := _make_simulation(4, 20, false)
	# setup() already built one structure + one forecast for the initial food
	# snapshot and warmed both caches. Capture counters immediately after
	# setup as baseline, then assert that every subsequent operation
	# on an unchanged world is a pure hit with no additional builds.
	var baseline_structure_builds := sim.trade_structure_build_total
	var baseline_structure_hits := sim.trade_structure_cache_hit_total
	var baseline_forecast_builds := sim.trade_forecast_build_total
	var baseline_forecast_hits := sim.trade_forecast_cache_hit_total
	var first: Dictionary = sim._forecast_trade_and_gold_flows()
	for _day in range(5):
		sim.state.day += 1
		sim.state.month = sim.state.day / Simulation.DAYS_PER_MONTH
		var repeated: Dictionary = sim._forecast_trade_and_gold_flows()
		_check(
			repeated["trade"] == first["trade"]
				and repeated["gold_flows"] == first["gold_flows"],
			"static_world/cross_day_result_%d" % sim.state.day
		)
	_check(
		sim.trade_structure_build_total == baseline_structure_builds
			and sim.trade_forecast_build_total == baseline_forecast_builds,
		"static_world/no_extra_builds",
		("baseline_structure_build=%d baseline_structure_hit=%d"
			+ " baseline_forecast_build=%d baseline_forecast_hit=%d final=%s") % [
				baseline_structure_builds,
				baseline_structure_hits,
				baseline_forecast_builds,
				baseline_forecast_hits,
				_counter_detail(sim),
			]
	)
	_check(
		sim.trade_structure_cache_hit_total
			== baseline_structure_hits + 6
			and sim.trade_forecast_cache_hit_total
				== baseline_forecast_hits + 6,
		"static_world/exact_hit_counts",
		_counter_detail(sim)
	)
	sim.free()


func _test_single_dependency_miss() -> void:
	var sim := _make_simulation(4, 20, false)
	var before: Dictionary = sim._forecast_trade_and_gold_flows()
	var structure_builds_before := sim.trade_structure_build_total
	var structure_hits_before := sim.trade_structure_cache_hit_total
	var forecast_builds_before := sim.trade_forecast_build_total
	var forecast_hits_before := sim.trade_forecast_cache_hit_total

	# 国库是粮食进口可负担量的动态依赖，但不影响路线结构。
	sim.state.nations[0].treasury_gold += 1
	var after: Dictionary = sim._forecast_trade_and_gold_flows()
	var direct_trade := TradeNetwork.build(sim.state)
	var direct_flows := Simulation.monthly_gold_flows(sim.state)
	_check(
		after["trade"] == direct_trade
			and after["gold_flows"] == direct_flows,
		"dependency_miss/recomputed_value_matches_direct"
	)
	_check(
		sim.trade_structure_build_total == structure_builds_before
			and sim.trade_structure_cache_hit_total
				== structure_hits_before + 1,
		"dependency_miss/reuses_structure",
		_counter_detail(sim)
	)
	_check(
		sim.trade_forecast_build_total == forecast_builds_before + 1
			and sim.trade_forecast_cache_hit_total == forecast_hits_before,
		"dependency_miss/rebuilds_settlement",
		"before=%s after=%s" % [str(before), str(after)]
	)
	sim.free()


func _test_war_preparation_shared_forecast() -> void:
	var sim := _make_simulation(4, 20, false)
	for nation in sim.state.nations:
		nation.war_preparation_target_nation = (nation.id + 1) % (
			sim.state.nations.size()
		)
	var structure_builds_at_setup := sim.trade_structure_build_total
	var forecast_builds_at_setup := sim.trade_forecast_build_total
	var evaluation_cache := sim._seed_trade_forecast({})
	var structure_builds_before := sim.trade_structure_build_total
	var forecast_builds_before := sim.trade_forecast_build_total
	sim._refresh_war_preparation_viability(evaluation_cache)
	_check(
		sim.trade_structure_build_total == structure_builds_before
			and sim.trade_forecast_build_total == forecast_builds_before,
		"war_preparation/shared_forecast_no_extra_builds",
		_counter_detail(sim)
	)
	# setup() already built one structure + one forecast via the initial
	# food snapshot. _seed_trade_forecast is a pure cache hit, so the seed
	# count matches setup counts.
	_check(
		structure_builds_at_setup >= 1 and forecast_builds_at_setup >= 1
			and structure_builds_before == structure_builds_at_setup
			and forecast_builds_before == forecast_builds_at_setup,
		"war_preparation/one_seed_for_multiple_nations",
		_counter_detail(sim)
	)
	sim.free()


func _counter_detail(sim: Simulation) -> String:
	return "structure_build=%d structure_hit=%d forecast_build=%d forecast_hit=%d" % [
		sim.trade_structure_build_total,
		sim.trade_structure_cache_hit_total,
		sim.trade_forecast_build_total,
		sim.trade_forecast_cache_hit_total,
	]


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	var message := label
	if not detail.is_empty():
		message += " :: " + detail
	_failures.append(message)


## 将完整运行态递归转换为无对象身份的确定性 Variant，再做无损序列化。
## 相比手写少数字段，这能捕获贸易预测差异经 AI 扩散到任意持久状态的情况。
func _state_fingerprint(state: GameState) -> PackedByteArray:
	return var_to_bytes(_snapshot_value(state))


func _snapshot_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			return _snapshot_object(value as Object)
		TYPE_ARRAY:
			var array_result: Array = []
			for item in value as Array:
				array_result.append(_snapshot_value(item))
			return array_result
		TYPE_DICTIONARY:
			var entries: Array = []
			for key in (value as Dictionary):
				var encoded_key: Variant = _snapshot_value(key)
				entries.append([
					str(encoded_key), encoded_key,
					_snapshot_value((value as Dictionary)[key]),
				])
			entries.sort_custom(func(a: Array, b: Array) -> bool:
				return str(a[0]) < str(b[0])
			)
			var dictionary_result: Array = ["Dictionary"]
			for entry in entries:
				dictionary_result.append([entry[1], entry[2]])
			return dictionary_result
		_:
			return value


func _snapshot_object(value: Object) -> Variant:
	if value == null:
		return null
	if value is RandomNumberGenerator:
		return ["RandomNumberGenerator", value.seed, value.state]
	var script_path := ""
	var script_value: Variant = value.get_script()
	if script_value is Script:
		script_path = (script_value as Script).resource_path
	var properties: Array = []
	var names: Array[String] = []
	for property_value in value.get_property_list():
		var property: Dictionary = property_value
		var name := str(property.get("name", ""))
		if (
			name == "script"
			or int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE == 0
		):
			continue
		names.append(name)
	names.sort()
	for name in names:
		properties.append([name, _snapshot_value(value.get(name))])
	var meta_names := value.get_meta_list()
	meta_names.sort()
	for meta_name in meta_names:
		properties.append([
			"@meta:" + str(meta_name),
			_snapshot_value(value.get_meta(meta_name)),
		])
	return [value.get_class(), script_path, properties]


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
