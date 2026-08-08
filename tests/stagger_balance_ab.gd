extends SceneTree
## 决策错峰的平衡性 A/B 对照：错峰只改各国「何时决策」的相位，不改决策逻辑本身，
## 但需排除它系统性偏向某相位国家、造成局势一边倒。同种子分别跑错峰 on/off 的长期
## 40 国演化，比较集中度（存活国数 / 最大国城市占比 / HHI）。多种子取均值消除单局偶然。
## HHI = Σ(每国城市占比)²，1.0=独霸，1/N=完全均衡。

func _init() -> void:
	var nations := _env_int("BAL_NATIONS", 40)
	var cities := _env_int("BAL_CITIES", 160)
	var days := _env_int("BAL_DAYS", 1800)
	var seeds := _env_int("BAL_SEEDS", 5)

	print("=== 决策错峰平衡性 A/B (%d国/%d城/%d天/%d种子) ===" % [
		nations, cities, days, seeds,
	])
	var on := _run_group(nations, cities, days, seeds, true)
	var off := _run_group(nations, cities, days, seeds, false)
	print("错峰ON : 存活国均值=%.1f 最大国占比均值=%.3f HHI均值=%.4f" % [
		on["alive"], on["top"], on["hhi"],
	])
	print("错峰OFF: 存活国均值=%.1f 最大国占比均值=%.3f HHI均值=%.4f" % [
		off["alive"], off["top"], off["hhi"],
	])
	print("差异: 存活国 %+.1f  最大国占比 %+.3f  HHI %+.4f" % [
		on["alive"] - off["alive"],
		on["top"] - off["top"],
		on["hhi"] - off["hhi"],
	])
	# 判定阈值：错峰若使 HHI 或最大国占比显著上升（>0.05），视为可能加剧一边倒。
	var skewed: bool = (on["hhi"] - off["hhi"]) > 0.05 or (on["top"] - off["top"]) > 0.05
	print("verdict=%s" % ("STAGGER_SKEWS_BALANCE" if skewed else "STAGGER_BALANCE_OK"))
	quit(0)


func _run_group(
	nations: int,
	cities: int,
	days: int,
	seeds: int,
	stagger: bool
) -> Dictionary:
	var alive_sum := 0.0
	var top_sum := 0.0
	var hhi_sum := 0.0
	for s in range(seeds):
		var state := GameState.new()
		state.generate_world(1000 + s * 7919, nations, cities)
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(state)
		sim.ai_staggered_decisions = stagger
		for _d in range(days):
			if state.winner != -1:
				break
			sim._advance_day(false)
		var counts := {}
		var total := 0
		for city in state.cities:
			counts[city.owner_nation] = int(counts.get(city.owner_nation, 0)) + 1
			total += 1
		var alive := 0
		var top := 0
		var hhi := 0.0
		for owner in counts:
			var c := int(counts[owner])
			if c > 0:
				alive += 1
			top = maxi(top, c)
			var share := float(c) / float(maxi(total, 1))
			hhi += share * share
		alive_sum += float(alive)
		top_sum += float(top) / float(maxi(total, 1))
		hhi_sum += hhi
		sim.free()
	return {
		"alive": alive_sum / float(maxi(seeds, 1)),
		"top": top_sum / float(maxi(seeds, 1)),
		"hhi": hhi_sum / float(maxi(seeds, 1)),
	}


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
