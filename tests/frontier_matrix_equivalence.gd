extends SceneTree
## 等价校验：证明 _frontier_edges 矩阵与逐对领土边界参照实现
## 对所有国家对返回完全相同的接壤数。
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
			var reference_val := _reference_frontier_edges(state, a, b)
			if new_val != reference_val:
				mismatches += 1
				if mismatches <= 10:
					print(
						"不一致 pair(%d,%d): 矩阵=%d 参照=%d"
						% [a, b, new_val, reference_val]
					)

	print("=== frontier_edges 等价校验 (40国/160城/推进%d天) ===" % state.day)
	print("检查国家对=%d 不一致=%d" % [checked, mismatches])
	print("verdict=%s" % ("FRONTIER_EQUIVALENT" if mismatches == 0 else "FRONTIER_DIVERGED"))
	sim.free()
	quit(0 if mismatches == 0 else 1)


## 不经外交矩阵缓存的逐对参照实现。
func _reference_frontier_edges(
	state: GameState, nation_a: int, nation_b: int
) -> int:
	var count := 0
	for contact in state.territorial_border_pairs():
		var owner_a := state.cities[contact.x].owner_nation
		var owner_b := state.cities[contact.y].owner_nation
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
