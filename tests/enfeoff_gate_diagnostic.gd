extends SceneTree
## 分封瓶颈诊断：推进到指定年份后，枚举所有存活非藩王国家，逐条统计分封门控
## 的通过率，定位「分封在自然演化中几乎不发生」的真正瓶颈条件。
##
## 门控链（全部为 AND）：
##   非藩王 → 冷却已过 → 中央处于和平 → 候选封地≥MIN城 → 分封后仍留足核心 → 负担比≥阈
## 输出各阶段的幸存国家数，最后一段掉得最多的即瓶颈。

func _init() -> void:
	var probe_year := _env_int("PROBE_YEAR", 8)
	var world_seed := _env_int("PROBE_SEED", 12345)
	var nations := _env_int("PROBE_NATIONS", 10)
	var cities := _env_int("PROBE_CITIES", 100)
	var state := GameState.new()
	state.generate_world(world_seed, nations, cities)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	while state.day < probe_year * 365 and state.winner == -1:
		sim._advance_day()

	var cache := {}
	var alive := 0
	var non_vassal := 0
	var cooldown_ok := 0
	var peace_ok := 0
	var region_ok := 0
	var core_retained := 0
	var burden_pass := 0
	var burden_samples: Array[float] = []
	var region_sizes: Array[int] = []

	for n in state.nations:
		if not n.alive:
			continue
		alive += 1
		var oid := n.id
		if state.is_vassal(oid):
			continue
		non_vassal += 1
		var recent := DiplomacyAI._recent_enfeoff_day(state, oid)
		if recent >= 0 and state.day - recent < DiplomacyAI.ENFEOFF_DECISION_COOLDOWN_DAYS:
			continue
		cooldown_ok += 1
		if DiplomacyAI._overlord_under_war_pressure(state, oid, cache):
			continue
		peace_ok += 1
		var region := DiplomacyAI._grow_enfeoff_region(state, oid, cache)
		region_sizes.append(region.size())
		if region.size() < DiplomacyAI.ENFEOFF_MIN_REGION_CITIES:
			continue
		region_ok += 1
		if (
			state.land_cities_of(oid).size() - region.size()
				< DiplomacyAI.ENFEOFF_MIN_OVERLORD_CITIES_AFTER
		):
			continue
		core_retained += 1
		var burden := DiplomacyAI.evaluate_region_burden(state, oid, region)
		var ratio := float(burden["burden_ratio"])
		burden_samples.append(ratio)
		if ratio >= DiplomacyAI.ENFEOFF_BURDEN_RATIO_THRESHOLD:
			burden_pass += 1

	print("=== 分封门控诊断 seed=%d %d国%d城 推进%d年 ===" % [
		world_seed, nations, cities, probe_year,
	])
	print("存活国=%d" % alive)
	print("① 非藩王           : %d" % non_vassal)
	print("② 且冷却已过       : %d" % cooldown_ok)
	print("③ 且中央处于和平   : %d   <- 和平前置" % peace_ok)
	print("④ 且候选封地≥%d城   : %d   <- 区域生成" % [
		DiplomacyAI.ENFEOFF_MIN_REGION_CITIES, region_ok,
	])
	print("⑤ 且分封后留足核心 : %d" % core_retained)
	print("⑥ 且负担比≥%.2f     : %d   <- 最终触发" % [
		DiplomacyAI.ENFEOFF_BURDEN_RATIO_THRESHOLD, burden_pass,
	])
	if not region_sizes.is_empty():
		var rmin := region_sizes[0]
		var rmax := region_sizes[0]
		var rsum := 0
		for r in region_sizes:
			rmin = mini(rmin, r)
			rmax = maxi(rmax, r)
			rsum += r
		print("候选封地城数(通过③的国家): min=%d max=%d avg=%.1f n=%d" % [
			rmin, rmax, float(rsum) / float(region_sizes.size()), region_sizes.size(),
		])
	if not burden_samples.is_empty():
		var bmin := burden_samples[0]
		var bmax := burden_samples[0]
		var bsum := 0.0
		for b in burden_samples:
			bmin = minf(bmin, b)
			bmax = maxf(bmax, b)
			bsum += b
		print("负担比样本(通过⑤的国家): min=%.3f max=%.3f avg=%.3f n=%d" % [
			bmin, bmax, bsum / float(burden_samples.size()), burden_samples.size(),
		])
	else:
		print("负担比样本: 无（在④或⑤已全部掉光）")
	sim.free()
	quit(0)


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
