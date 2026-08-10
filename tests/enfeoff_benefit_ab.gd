extends SceneTree
## 分封收益 A/B 对照：同种子分别跑分封 ON/OFF 的长期演化，比较统一速度与集中度。
##
## 关键：分封会新增藩王 Nation，直接按 Nation 统计会被机制本身扭曲（藩王被当成
## 「独立敌国」，存活国数虚高、集中度虚低）。因此所有指标一律「按宗藩体系（root）
## 聚合」——宗主与其全部藩王视为同一个政治体系。这才是分封是否「划算」的公平口径。
##
## 统一判定：全图存活城市的 suzerainty_root 收敛到 1 个（一个体系控盘），
## 而非 GameState.winner（分封后宗主+藩王共存，winner 永不触发，是纯机制假象）。
##
## 指标（均按 root 聚合、多种子取均值）：
##   unify_day    : 达成体系统一的世界日；未达成记为 DAYS（越小越快统一）
##   unify_rate   : 达成体系统一的种子比例
##   alive_systems: 终局存活体系数（越小越集中）
##   top_share    : 终局最大体系城市占比
##   hhi          : Σ(每体系城市占比)²，1.0=独霸，1/N=均衡
##   enfeoffs     : 该组累计发生的分封次数（OFF 组应为 0，做健全性校验）

func _init() -> void:
	var nations := _env_int("EB_NATIONS", 8)
	var cities := _env_int("EB_CITIES", 80)
	var days := _env_int("EB_DAYS", 2400)
	var seeds := _env_int("EB_SEEDS", 6)

	print("=== 分封收益 A/B (%d国/%d城/%d天/%d种子) ===" % [
		nations, cities, days, seeds,
	])
	var on := _run_group(nations, cities, days, seeds, true)
	var off := _run_group(nations, cities, days, seeds, false)
	print("分封ON : 统一率=%.2f 统一日均值=%.0f 存活体系=%.2f 最大占比=%.3f HHI=%.4f 分封次数=%.1f" % [
		on["unify_rate"], on["unify_day"], on["alive_systems"],
		on["top_share"], on["hhi"], on["enfeoffs"],
	])
	print("分封OFF: 统一率=%.2f 统一日均值=%.0f 存活体系=%.2f 最大占比=%.3f HHI=%.4f 分封次数=%.1f" % [
		off["unify_rate"], off["unify_day"], off["alive_systems"],
		off["top_share"], off["hhi"], off["enfeoffs"],
	])
	print("差异(ON-OFF): 统一率 %+.2f  统一日 %+.0f  存活体系 %+.2f  最大占比 %+.3f  HHI %+.4f" % [
		on["unify_rate"] - off["unify_rate"],
		on["unify_day"] - off["unify_day"],
		on["alive_systems"] - off["alive_systems"],
		on["top_share"] - off["top_share"],
		on["hhi"] - off["hhi"],
	])
	# 健全性：OFF 组不得发生任何分封。
	var sane: bool = off["enfeoffs"] == 0.0
	# 收益判定：分封若「加速统一」（统一日更小或统一率更高）则视为正收益。
	var faster: bool = (
		on["unify_rate"] > off["unify_rate"]
		or (
			_approx(on["unify_rate"], off["unify_rate"])
			and on["unify_day"] < off["unify_day"]
		)
	)
	print("verdict=%s%s" % [
		"ENFEOFF_SPEEDS_UNIFICATION" if faster else "ENFEOFF_NEUTRAL_OR_SLOWER",
		"" if sane else " (WARN: OFF_GROUP_ENFEOFFED)",
	])
	quit(0)


func _run_group(
	nations: int,
	cities: int,
	days: int,
	seeds: int,
	enfeoff_on: bool
) -> Dictionary:
	var unify_day_sum := 0.0
	var unify_count := 0
	var alive_sum := 0.0
	var top_sum := 0.0
	var hhi_sum := 0.0
	var enfeoff_sum := 0.0
	for s in range(seeds):
		var state := GameState.new()
		state.generate_world(1000 + s * 7919, nations, cities)
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(state)
		sim.enfeoff_enabled = enfeoff_on
		var unify_day := days
		for d in range(days):
			sim._advance_day(false)
			# 体系统一判定：全图城市 root 收敛到 1。
			if _system_unified(state):
				unify_day = d + 1
				break
		if unify_day < days:
			unify_count += 1
		unify_day_sum += float(unify_day)
		var agg := _aggregate_by_system(state)
		alive_sum += float(agg["alive"])
		top_sum += float(agg["top_share"])
		hhi_sum += float(agg["hhi"])
		enfeoff_sum += float(_count_enfeoffs(state))
		sim.free()
	var inv := 1.0 / float(maxi(seeds, 1))
	return {
		"unify_rate": float(unify_count) * inv,
		"unify_day": unify_day_sum * inv,
		"alive_systems": alive_sum * inv,
		"top_share": top_sum * inv,
		"hhi": hhi_sum * inv,
		"enfeoffs": enfeoff_sum * inv,
	}


## 全图存活城市是否全部归属同一个宗藩体系（root 收敛到 1）。
func _system_unified(state: GameState) -> bool:
	var root_seen := -1
	for city in state.cities:
		var owner := city.owner_nation
		if owner < 0:
			continue
		var r := state.suzerainty_root(owner)
		if root_seen == -1:
			root_seen = r
		elif r != root_seen:
			return false
	return root_seen != -1


## 按宗藩体系（root）聚合城市占比，返回存活体系数 / 最大占比 / HHI。
func _aggregate_by_system(state: GameState) -> Dictionary:
	var counts := {}
	var total := 0
	for city in state.cities:
		var owner := city.owner_nation
		if owner < 0:
			continue
		var r := state.suzerainty_root(owner)
		counts[r] = int(counts.get(r, 0)) + 1
		total += 1
	var alive := 0
	var top := 0
	var hhi := 0.0
	for r in counts:
		var c := int(counts[r])
		if c > 0:
			alive += 1
		top = maxi(top, c)
		var share := float(c) / float(maxi(total, 1))
		hhi += share * share
	return {
		"alive": alive,
		"top_share": float(top) / float(maxi(total, 1)),
		"hhi": hhi,
	}


## 当前局面累计发生的分封次数 = 存在的宗藩关系条数（每次分封新增一条）。
func _count_enfeoffs(state: GameState) -> int:
	return state.suzerainty.size()


func _approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
