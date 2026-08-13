extends SceneTree
## 地形据守系数 A/B 对照：同种子分别跑「敌对前线边地形加成用凸曲线 ON/OFF」的长期演化，
## 量化 Combat.terrain_hold_bias 接入 StrategicMapSnapshot.value_of_edge 的实际防御收益。
##
## 唯一差异：StrategicMapSnapshot.terrain_hold_bias_enabled
##   ON  (B组) = 前线边加成 = (terrain_hold_bias(danger,0)-1)×4（凸曲线，隘口带加速）
##   OFF (A组) = 退回历史线性 danger*2.0
## 两者在 danger=0/1 端点幅度对齐，差异仅曲线形状（中段更低、隘口更陡）。value_of_edge
## 是选边/防区/驻守评分的共同主项，故地形经此单一真源影响全部防御决策，无双重计数。
## 其余世界种子、国数、城数、天数完全一致，故指标差异纯粹归因于地形加成曲线。
##
## 地形系数是防御性改动（让守方更愿据守险要边）。用多维指标互相印证，避免单一指标误判：
##   ownership_flips: 全程城市易手累计次数（ownership_revision 终值）。越低=领土越稳。
##   alive_nations  : 终局存活国数。越高=弱国越能守住（防御收益的直接体现）。
##   top_share      : 终局最大国城市占比。越低=越抑制单极碾压。
##   hhi            : Σ(每国城市占比)²。越低=越均衡。
##   wars           : 终局交战关系对数。辅助识别「僵局」——若易手骤降但战争高企，
##                    说明是互相顿兵坚城的对峙，而非真实防御力提升。
##
## 判定：地形系数「有防御正收益」= 易手更少 AND 存活国不减少（排除僵局假象）。
##
## 用法（默认 12 国 / 160 城 / 1800 天 / 5 种子）：
##   Godot --headless --path <项目> --script res://tests/terrain_defense_ab.gd
##   TD_NATIONS=20 TD_DAYS=2400 TD_SEEDS=8 Godot ... --script res://tests/terrain_defense_ab.gd

func _init() -> void:
	var nations := _env_int("TD_NATIONS", 12)
	var cities := _env_int("TD_CITIES", 160)
	var days := _env_int("TD_DAYS", 1800)
	var seeds := _env_int("TD_SEEDS", 5)

	print("=== 地形据守系数 A/B (%d国/%d城/%d天/%d种子) ===" % [
		nations, cities, days, seeds,
	])
	# 先跑 OFF(A组基线)，再跑 ON(B组)，结束后复位开关到生产默认值。
	var off := _run_group(nations, cities, days, seeds, false)
	var on := _run_group(nations, cities, days, seeds, true)
	StrategicMapSnapshot.terrain_hold_bias_enabled = true

	print("A组 地形OFF(线性): 易手=%.1f 存活国=%.2f 最大占比=%.3f HHI=%.4f 战争对=%.1f" % [
		off["flips"], off["alive"], off["top_share"], off["hhi"], off["wars"],
	])
	print("B组 地形ON (据守溢价): 易手=%.1f 存活国=%.2f 最大占比=%.3f HHI=%.4f 战争对=%.1f" % [
		on["flips"], on["alive"], on["top_share"], on["hhi"], on["wars"],
	])
	print("差异(B-A): 易手 %+.1f (%+.1f%%)  存活国 %+.2f  最大占比 %+.3f  HHI %+.4f  战争对 %+.1f" % [
		on["flips"] - off["flips"],
		_pct(on["flips"], off["flips"]),
		on["alive"] - off["alive"],
		on["top_share"] - off["top_share"],
		on["hhi"] - off["hhi"],
		on["wars"] - off["wars"],
	])

	# 收益判定：易手显著下降（领土更稳）且存活国不减少（非顿兵僵局导致的假稳定）。
	var fewer_flips: bool = on["flips"] < off["flips"]
	var not_fewer_alive: bool = on["alive"] >= off["alive"] - 0.001
	var verdict := "TERRAIN_NEUTRAL"
	if fewer_flips and not_fewer_alive:
		verdict = "TERRAIN_IMPROVES_DEFENSE"
	elif fewer_flips and not not_fewer_alive:
		verdict = "TERRAIN_FEWER_FLIPS_BUT_STALEMATE"
	elif not fewer_flips:
		verdict = "TERRAIN_NO_STABILITY_GAIN"
	print("verdict=%s" % verdict)
	quit(0)


func _run_group(
	nations: int,
	cities: int,
	days: int,
	seeds: int,
	terrain_on: bool
) -> Dictionary:
	StrategicMapSnapshot.terrain_hold_bias_enabled = terrain_on
	var flips_sum := 0.0
	var alive_sum := 0.0
	var top_sum := 0.0
	var hhi_sum := 0.0
	var wars_sum := 0.0
	for s in range(seeds):
		var state := GameState.new()
		state.generate_world(1000 + s * 7919, nations, cities)
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(state)
		# 关闭分封：地形据守系数是局部防御性微调，信号微弱。分封会新增藩王 Nation 并制造
		# 全局领土动荡（强噪声），且使 owner_nation 聚合失真。关闭后本 AB 成为地形系数的
		# 干净受控实验——所有指标差异只归因于选边评分曲线，而非分封博弈。
		sim.enfeoff_enabled = false
		for _d in range(days):
			sim._advance_day(false)
			if state.winner != -1:
				break
		flips_sum += float(state.ownership_revision)
		var agg := _aggregate(state)
		alive_sum += float(agg["alive"])
		top_sum += float(agg["top_share"])
		hhi_sum += float(agg["hhi"])
		wars_sum += float(_count_wars(state))
		sim.free()
	var inv := 1.0 / float(maxi(seeds, 1))
	return {
		"flips": flips_sum * inv,
		"alive": alive_sum * inv,
		"top_share": top_sum * inv,
		"hhi": hhi_sum * inv,
		"wars": wars_sum * inv,
	}


## 按国家聚合存活城市：存活国数 / 最大占比 / HHI。地形系数不引入藩王机制，
## 故直接按 owner_nation 统计即可（与分封 AB 的 root 聚合口径不同，此处无需 root）。
func _aggregate(state: GameState) -> Dictionary:
	var counts := {}
	var total := 0
	for city in state.cities:
		var owner := city.owner_nation
		if owner < 0:
			continue
		counts[owner] = int(counts.get(owner, 0)) + 1
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
	return {
		"alive": alive,
		"top_share": float(top) / float(maxi(total, 1)),
		"hhi": hhi,
	}


## 终局交战关系对数：遍历国家对，统计处于 WAR 的无序对数量。
func _count_wars(state: GameState) -> int:
	var wars := 0
	var n := state.nations.size()
	for a in range(n):
		for b in range(a + 1, n):
			if state.is_enemy(a, b):
				wars += 1
	return wars


func _pct(a: float, b: float) -> float:
	if absf(b) < 0.0001:
		return 0.0
	return (a - b) / b * 100.0


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
