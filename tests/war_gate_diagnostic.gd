extends SceneTree
## 宣战瓶颈诊断：推进到指定年份后，枚举所有存活国对，统计宣战为何不发生。
## 区分“硬门槛挡住”（无合法目标）vs“评分不足”（有目标但 war_desire 达不到线）。

func _init() -> void:
	var probe_year := _env_int("PROBE_YEAR", 20)
	var world_seed := _env_int("PROBE_SEED", 12345)
	var nations := _env_int("PROBE_NATIONS", 40)
	var state := GameState.new()
	state.generate_world(world_seed, nations)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	while state.day < probe_year * 365 and state.winner == -1:
		sim._advance_day()

	var alive := 0
	for n in state.nations:
		if n.alive:
			alive += 1
	# 统计联盟网密度
	var ally_pairs := 0
	var war_pairs := 0
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if state.is_allied(a, b):
				ally_pairs += 1
			elif state.is_enemy(a, b):
				war_pairs += 1

	# 逐对分析：为什么不能/不宣战
	var cache := {}
	var can_declare := 0          # 通过 can_declare_war 基本门槛
	var has_frontier := 0         # 且接壤
	var no_shared_ally := 0       # 且无共同盟友
	var passes_hard_gate := 0     # 全部硬门槛通过（war_desire != -INF）
	var above_war_line := 0       # 且 war_desire >= WAR_DECLARE_SCORE
	var best_desire := -1e9
	var era := DiplomacyAI.unification_era_factor(state)

	for a in range(state.nations.size()):
		if not state.nations[a].alive:
			continue
		for b in range(state.nations.size()):
			if a == b or not state.nations[b].alive:
				continue
			if not state.can_declare_war(a, b):
				continue
			can_declare += 1
			var frontier := DiplomacyAI._frontier_edges(state, a, b, cache)
			if frontier > 0:
				has_frontier += 1
			var shared := DiplomacyAI._has_shared_ally(state, a, b, cache)
			if not shared:
				no_shared_ally += 1
			var desire := DiplomacyAI.war_desire(state, a, b, cache)
			if desire > -1e30:
				passes_hard_gate += 1
				if desire > best_desire:
					best_desire = desire
				if desire >= DiplomacyAI.WAR_DECLARE_SCORE:
					above_war_line += 1

	print("=== 宣战瓶颈诊断 year=%d seed=%d ===" % [probe_year, world_seed])
	print("alive=%d ally_pairs=%d war_pairs=%d era_factor=%.3f" % [
		alive, ally_pairs, war_pairs, era,
	])
	# 备战状态统计：区分“没想宣战” vs “想了但卡在备战集结”
	var preparing := 0
	var prep_targets: Array[int] = []
	for n in state.nations:
		if n.alive and n.war_preparation_target_nation >= 0:
			preparing += 1
			prep_targets.append(n.id)
	print("处于备战中(war_preparation_target>=0)的国家数=%d ids=%s" % [
		preparing, str(prep_targets),
	])
	# 累计外交事件分布：一锤定音区分“从没想打” vs “备战了但超时取消” vs “宣战了但速和”
	var action_counts := {}
	var peace_count := 0
	var zero_transfer_peaces := 0
	var transferred_total := 0
	var transferred_max := 0
	var surrender_peaces := 0
	for event in state.diplomatic_history:
		var k := int(event.get("action", -1))
		action_counts[k] = int(action_counts.get(k, 0)) + 1
		if k != DiplomacyAI.Action.MAKE_PEACE:
			continue
		peace_count += 1
		var transferred := int(event.get("territories_transferred", 0))
		transferred_total += transferred
		transferred_max = maxi(transferred_max, transferred)
		if transferred == 0:
			zero_transfer_peaces += 1
		if int(event.get("surrendering_nation", -1)) >= 0:
			surrender_peaces += 1
	print("外交事件累计分布(action_kind:次数): %s" % str(action_counts))
	print("  (参考 DiplomacyAI.Action 枚举：NONE/MAKE_PEACE/DECLARE_WAR/FORM_ALLIANCE/LEAVE_ALLIANCE/PREPARE_WAR/CANCEL_WAR_PREPARATION)")
	print(
		"议和成果: peaces=%d zero_transfer=%d transferred_total=%d max=%d surrenders=%d"
		% [
			peace_count,
			zero_transfer_peaces,
			transferred_total,
			transferred_max,
			surrender_peaces,
		]
	)
	print("有序对(可宣战基本门槛 can_declare_war)=%d" % can_declare)
	print("  其中接壤(frontier>0)=%d" % has_frontier)
	print("  其中无共同盟友(no_shared_ally)=%d" % no_shared_ally)
	print("  通过全部硬门槛(war_desire!=-INF)=%d" % passes_hard_gate)
	print("  且评分>=宣战线%.2f 的=%d" % [DiplomacyAI.WAR_DECLARE_SCORE, above_war_line])
	print("通过硬门槛者的最高 war_desire=%.3f" % best_desire)
	if passes_hard_gate == 0:
		print("verdict=BLOCKED_BY_HARD_GATE")
	elif above_war_line == 0:
		print("verdict=BLOCKED_BY_SCORE best=%.3f line=%.2f" % [
			best_desire, DiplomacyAI.WAR_DECLARE_SCORE,
		])
	else:
		print("verdict=WAR_POSSIBLE count=%d" % above_war_line)
	sim.free()
	quit(0)


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return int(raw) if not raw.is_empty() else fallback
