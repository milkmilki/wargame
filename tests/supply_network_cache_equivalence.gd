extends SceneTree
## 等价性守卫：证明「补给网络指纹选择性失效」与「每天全量重建」旧逻辑逐军
## 逐字节等价。镜像测试对对称错误不敏感，故须独立守卫。两个同 seed 世界分别
## 用新/旧策略推进相同天数后，比对每支军队的补给相关状态（size/morale/
## supply_ratio/starving/supply_food_debt/supply_debt/state）必须完全一致。

func _init() -> void:
	var days := _env_int("SUPPLY_EQUIV_DAYS", 400)
	var nations := _env_int("SUPPLY_EQUIV_NATIONS", 40)
	var cities := _env_int("SUPPLY_EQUIV_CITIES", 160)

	var legacy_sim := _run_world(nations, cities, days, true)
	var cached_sim := _run_world(nations, cities, days, false)
	var legacy_state: GameState = legacy_sim.state
	var cached_state: GameState = cached_sim.state

	var mismatches := 0
	var checked := 0
	if legacy_state.armies.size() != cached_state.armies.size():
		print("军队数不一致 旧=%d 新=%d" % [
			legacy_state.armies.size(),
			cached_state.armies.size(),
		])
		mismatches += 1
	var by_id := {}
	for army in cached_state.armies:
		by_id[army.id] = army
	for legacy_army in legacy_state.armies:
		checked += 1
		var cached_army: Army = by_id.get(legacy_army.id)
		if cached_army == null:
			mismatches += 1
			if mismatches <= 10:
				print("新世界缺失 army=%d" % legacy_army.id)
			continue
		var fp_legacy := _army_fp(legacy_army)
		var fp_cached := _army_fp(cached_army)
		if fp_legacy != fp_cached:
			mismatches += 1
			if mismatches <= 10:
				print("army=%d 不一致\n  旧=%s\n  新=%s" % [
					legacy_army.id, fp_legacy, fp_cached,
				])

	print("=== 补给网络缓存等价校验 (%d国/%d城/推进%d天) ===" % [
		nations, cities, days,
	])
	print("对比军队=%d 不一致=%d" % [checked, mismatches])
	print("verdict=%s" % (
		"SUPPLY_CACHE_EQUIVALENT" if mismatches == 0 else "SUPPLY_CACHE_DIVERGED"
	))
	legacy_sim.free()
	cached_sim.free()
	quit(0 if mismatches == 0 else 1)


func _run_world(
	nations: int,
	cities: int,
	days: int,
	disable_cache: bool
) -> Simulation:
	var state := GameState.new()
	state.generate_world(12345, nations, cities)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.supply_network_cache_disabled = disable_cache
	for _d in range(days):
		if state.winner != -1:
			break
		sim._advance_day(false)
	return sim


## 军队补给相关状态指纹。浮点量量化到 1e6 避免打印精度噪声，但比较本身用
## 量化后整数——若两条路径浮点结果有任何真实偏差都会体现在量化位上。
func _army_fp(army: Army) -> String:
	return "sz=%d st=%d mor=%d sr=%d fd=%d sd=%d starv=%s" % [
		army.size,
		army.state,
		int(round(army.morale * 1000000.0)),
		int(round(army.supply_ratio * 1000000.0)),
		int(round(army.supply_food_debt * 1000000.0)),
		int(round(army.supply_debt * 1000000.0)),
		"1" if army.starving else "0",
	]


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
