extends SceneTree
## 一次性等价校验：证明 _frontier_edges 矩阵化改写与「逐对全表扫描」旧逻辑
## 对所有国家对返回完全相同的接壤边数。矩阵改写属纯性能优化，语义必须零偏差。
## 推进若干天制造真实的战争/结盟/占领态势后，逐对比对。

func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345, 40, 160)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	# 推进制造真实外交/占领态势（结盟、战争、易主都会改变接壤矩阵）。
	for _d in range(200):
		if state.winner != -1:
			break
		sim._advance_day(false)

	var n := state.nations.size()
	var mismatches := 0
	var checked := 0
	# 新逻辑：共享一个 evaluation_cache，首访即构建整张矩阵。
	var new_cache := {}
	for a in range(n):
		for b in range(n):
			if a == b:
				continue
			checked += 1
			var new_val := DiplomacyAI._frontier_edges(state, a, b, new_cache)
			var old_val := _old_frontier_edges(state, a, b)
			if new_val != old_val:
				mismatches += 1
				if mismatches <= 10:
					print("不一致 pair(%d,%d): 新=%d 旧=%d" % [a, b, new_val, old_val])

	print("=== frontier_edges 等价校验 (40国/160城/推进%d天) ===" % state.day)
	print("检查国家对=%d 不一致=%d" % [checked, mismatches])
	print("verdict=%s" % ("FRONTIER_EQUIVALENT" if mismatches == 0 else "FRONTIER_DIVERGED"))
	sim.free()
	quit(0 if mismatches == 0 else 1)


## 旧实现的逐对全表扫描逻辑（从改写前的 _frontier_edges 复制，作为对照基准）。
func _old_frontier_edges(state: GameState, nation_a: int, nation_b: int) -> int:
	var count := 0
	for edge in state.edges:
		if edge.max_manpower <= 0:
			continue
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if (
			(
				state.has_military_access(nation_a, owner_a)
				and owner_b == nation_b
			)
			or (
				state.has_military_access(nation_a, owner_b)
				and owner_a == nation_b
			)
		):
			count += 1
	return count
