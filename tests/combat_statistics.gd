extends SceneTree
## item 17：批量统计战斗测试（≥10,000 场）。手动运行，不纳入每次快速回归。
##
## 设计说明（诚实标注 item 8 取舍）：本项目已定「镜像公平 > 单场戏剧性」——
## 每 tick 只掷一次 shared_roll 并同乘双方火力，故骰值只改变战斗『烈度/速度』、
## 不改变『相对胜负』。因此固定阵容的单场野战是**确定性**的，随机性不会在单场内
## 把胜负从优势方手里夺走。这使 §17 的验证项呈现为如下**更强**的确定性不变量：
##   ① A/B 位置对称：交换两侧 → 胜方镜像交换、双方伤亡互换（严格逐位）；
##   ② 优势方胜率：任意随机兵力/攻防阵容，兵力优势方胜率必须极高且稳定；
##   ③ 随机性不掩盖兵力优势：显著优势(≥5%)方在所有种子下 100% 取胜；
##   ④ 拆分不改结果：把一侧拆成多支小军，总伤亡与胜负不变；
##   ⑤ 地形优势符合预期：高危地形对进攻方的压制单调且方向正确；
##   ⑥ 固定种子完全复现：同输入同种子逐位一致。
## 运行：Godot --headless --script res://tests/combat_statistics.gd

const BATTLE_COUNT: int = 10000

var _fail_msgs: Array[String] = []


func _init() -> void:
	var started := Time.get_ticks_msec()
	_test_position_symmetry()
	_test_advantage_winrate()
	_test_randomness_never_beats_advantage()
	_test_split_invariance()
	_test_terrain_monotonic()
	_test_seed_reproducibility()
	var elapsed := Time.get_ticks_msec() - started
	print("\n==== combat_statistics: %d 场/项，用时 %d ms ====" % [BATTLE_COUNT, elapsed])
	if _fail_msgs.is_empty():
		print("verdict=STATISTICS_PASS")
	else:
		print("verdict=STATISTICS_FAIL")
		for m in _fail_msgs:
			print("  [FAIL] " + m)
	quit(1 if not _fail_msgs.is_empty() else 0)


func _fail(msg: String) -> void:
	_fail_msgs.append(msg)


# ① A/B 位置对称：随机阵容交换两侧，胜方镜像交换、双方伤亡互换（严格逐位）。
func _test_position_symmetry() -> void:
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 20260802
	var mismatches := 0
	var draws := 0
	for i in range(BATTLE_COUNT):
		var sa := seed_rng.randi_range(500, 5000)
		var sb := seed_rng.randi_range(500, 5000)
		var atk_a := seed_rng.randi_range(8, 15)
		var atk_b := seed_rng.randi_range(8, 15)
		var def_a := seed_rng.randi_range(8, 15)
		var def_b := seed_rng.randi_range(8, 15)
		var danger := seed_rng.randf_range(0.0, 0.6)
		var battle_seed := 1 + i

		# 正向：A=(sa) B=(sb)
		var fwd := _make_battle(sa, atk_a, def_a, sb, atk_b, def_b, danger)
		var loss_fwd := _run(fwd, battle_seed)
		# 交换：A=(sb) B=(sa)
		var rev := _make_battle(sb, atk_b, def_b, sa, atk_a, def_a, danger)
		var loss_rev := _run(rev, battle_seed)

		if fwd.winner_side == 0:
			draws += 1
		# 胜方必须镜像交换（1↔2，0↔0），且两侧总伤亡互换。
		var winner_mirrored := (
			(fwd.winner_side == 1 and rev.winner_side == 2)
			or (fwd.winner_side == 2 and rev.winner_side == 1)
			or (fwd.winner_side == 0 and rev.winner_side == 0)
		)
		if not winner_mirrored or loss_fwd[0] != loss_rev[1] or loss_fwd[1] != loss_rev[0]:
			mismatches += 1
	if mismatches != 0:
		_fail("① 位置对称：%d/%d 场交换 A/B 后胜负或伤亡不镜像" % [mismatches, BATTLE_COUNT])
	print("① 位置对称：%d 场全部镜像（其中平局 %d）" % [BATTLE_COUNT, draws])


# ② 优势方胜率：随机阵容中兵力优势方（含攻防）应有极高且稳定的胜率。
func _test_advantage_winrate() -> void:
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 771010
	var strong_wins := 0
	var counted := 0
	for i in range(BATTLE_COUNT):
		# 强方兵力 1.3~2.0 倍且攻防不低于弱方，确保是真优势方。
		var weak := seed_rng.randi_range(800, 3000)
		var strong := int(weak * seed_rng.randf_range(1.3, 2.0))
		var danger := seed_rng.randf_range(0.0, 0.5)
		var battle := _make_battle(strong, 12, 12, weak, 10, 10, danger)
		_run(battle, 5000 + i)
		counted += 1
		if battle.winner_side == 1:
			strong_wins += 1
	var rate := float(strong_wins) / float(counted)
	if rate < 0.95:
		_fail("② 优势方胜率过低：%.4f（%d/%d），应≥0.95" % [rate, strong_wins, counted])
	print("② 优势方胜率=%.4f（%d/%d，1.3~2.0倍兵力+攻防优势）" % [rate, strong_wins, counted])


# ③ 随机性不掩盖兵力优势：显著优势(≥5%)方在所有种子下必胜（确定性，item 8 取舍）。
func _test_randomness_never_beats_advantage() -> void:
	var flips := 0
	for i in range(BATTLE_COUNT):
		var battle := _make_battle(2100, 10, 10, 2000, 10, 10, 0.1)
		_run(battle, 100000 + i)
		if battle.winner_side != 1:
			flips += 1
	if flips != 0:
		_fail("③ 随机性夺走兵力优势：%d/%d 场 5%%优势方未胜（shared_roll 应同乘双方、不改相对胜负）" % [flips, BATTLE_COUNT])
	print("③ 5%%兵力优势方确定性全胜：%d/%d（随机性不覆盖兵力优势）" % [BATTLE_COUNT, BATTLE_COUNT])


# ④ 拆分不改结果：把优势侧拆成多支小军，总伤亡与胜负不变（防套利 item12）。
func _test_split_invariance() -> void:
	var mismatches := 0
	var checks := BATTLE_COUNT / 5   # 拆分战斗较重，取 1/5 样本，仍 >=2000 场
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 424242
	for i in range(checks):
		var total := seed_rng.randi_range(2000, 6000)
		var enemy := seed_rng.randi_range(1500, 4000)
		var danger := seed_rng.randf_range(0.0, 0.4)
		var bs := 900000 + i

		var whole := _make_battle(total, 10, 10, enemy, 10, 10, danger)
		var loss_whole := _run(whole, bs)

		# 拆成 4 支等量小军（尾数补到第一支），物理多重集相同。
		var parts := _split_sizes(total, 4)
		var split := Battle.new()
		split.id = 0
		split.kind = Battle.Kind.FIELD
		split.edge = _edge(danger)
		split.contact_dist_a = 2.0
		split.contact_dist_b = 2.0
		var aid := 0
		for p in parts:
			split.side_a.append(_army(aid, 0, p, 10, 10)); aid += 1
		split.side_b.append(_army(100, 1, enemy, 10, 10))
		var loss_split := _run(split, bs)

		if whole.winner_side != split.winner_side or loss_whole[0] != loss_split[0] or loss_whole[1] != loss_split[1]:
			mismatches += 1
	if mismatches != 0:
		_fail("④ 拆分改变结果：%d/%d 场拆分后胜负或总伤亡不一致" % [mismatches, checks])
	print("④ 拆分不变性：%d 场拆分前后胜负与总伤亡逐位一致" % checks)


# ⑤ 地形优势符合预期：进攻方攻击倍率随地形危险度单调不增，极端地形显著压制。
func _test_terrain_monotonic() -> void:
	var prev := 2.0
	var monotonic := true
	var samples := 200
	for i in range(samples + 1):
		var d := float(i) / float(samples)   # 0..1
		var m := Combat.attack_multiplier(d)
		if m > prev + 1e-9:
			monotonic = false
		prev = m
	if not monotonic:
		_fail("⑤ 地形倍率非单调：attack_multiplier 随危险度上升出现回升")
	# 极端 vs 平地：高危地形对进攻方应有明确压制。
	if not (Combat.attack_multiplier(0.95) < Combat.attack_multiplier(0.0) - 0.2):
		_fail("⑤ 极端地形压制不足：danger0.95=%.3f 应显著低于平地=%.3f" % [
			Combat.attack_multiplier(0.95), Combat.attack_multiplier(0.0)])
	print("⑤ 地形单调压制：attack_multiplier(0)=%.3f → (0.95)=%.3f，%d 点采样单调不增" % [
		Combat.attack_multiplier(0.0), Combat.attack_multiplier(0.95), samples + 1])


# ⑥ 固定种子完全复现：同一阵容同一种子跑两遍，逐位一致。
func _test_seed_reproducibility() -> void:
	var diffs := 0
	for i in range(BATTLE_COUNT):
		var b1 := _make_battle(2500, 11, 10, 2300, 10, 11, 0.25)
		var l1 := _run(b1, 333000 + i)
		var b2 := _make_battle(2500, 11, 10, 2300, 10, 11, 0.25)
		var l2 := _run(b2, 333000 + i)
		if b1.winner_side != b2.winner_side or l1 != l2:
			diffs += 1
	if diffs != 0:
		_fail("⑥ 复现失败：%d/%d 场同种子两遍结果不一致" % [diffs, BATTLE_COUNT])
	print("⑥ 固定种子完全复现：%d 场两遍逐位一致" % BATTLE_COUNT)


# ------------------------------------------------------------------ 构造辅助

func _army(aid: int, nation: int, size: int, atk: int, def_v: int) -> Army:
	var a := Army.new()
	a.id = aid
	a.owner_nation = nation
	a.size = size
	a.attack = atk
	a.defense = def_v
	a.morale = 1.0
	return a


func _edge(danger: float) -> Edge:
	var e := Edge.new()
	e.city_a = 0
	e.city_b = 1
	e.distance = 4
	e.danger = danger
	e.max_manpower = 45000
	return e


func _make_battle(
	sa: int, atk_a: int, def_a: int,
	sb: int, atk_b: int, def_b: int,
	danger: float
) -> Battle:
	var b := Battle.new()
	b.id = 0
	b.kind = Battle.Kind.FIELD
	b.edge = _edge(danger)
	b.contact_dist_a = 2.0
	b.contact_dist_b = 2.0
	b.side_a.append(_army(0, 0, sa, atk_a, def_a))
	b.side_b.append(_army(1, 1, sb, atk_b, def_b))
	return b


## 跑完一场战斗，返回 [side_a 总伤亡, side_b 总伤亡]。
func _run(battle: Battle, battle_seed: int) -> Array:
	var start_a := battle.side_size(battle.side_a)
	var start_b := battle.side_size(battle.side_b)
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_seed
	var guard := 0
	while not battle.finished and guard < 1000:
		Combat.resolve_round(battle, rng)
		guard += 1
	return [start_a - battle.side_size(battle.side_a), start_b - battle.side_size(battle.side_b)]


## 将 total 拆成 n 份，尾数并入第一份（保持整数总量守恒）。
func _split_sizes(total: int, n: int) -> Array[int]:
	var base := total / n
	var out: Array[int] = []
	for i in range(n):
		out.append(base)
	out[0] += total - base * n
	return out
