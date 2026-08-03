extends SceneTree
## item 17：批量统计战斗测试（≥10,000 场）。手动运行，不纳入每次快速回归。
##
## item 8：每 tick 消费一次 shared_roll（共同烈度）和一次 tactical_entropy；后者通过
## 无 id、无顺序、拆分不变的侧物理指纹分别派生 ±5% 战术修正。交换 A/B 会交换修正；
## 完全同构侧因等变性要求自动得到相同修正。验证项：
##   ① A/B 位置对称：交换两侧 → 胜方镜像交换、双方伤亡互换（严格逐位）；
##   ② 战术随机独立且无侧位偏置，交换指纹严格交换修正；
##   ③ 优势方胜率：任意随机兵力/攻防阵容，兵力优势方胜率必须极高且稳定；
##   ④ 随机性不掩盖明显兵力优势：20% 优势方保持稳定统计优势；
##   ⑤ 拆分不改结果：把一侧拆成多支小军，总伤亡与胜负不变；
##   ⑥ 受限正面拆分不变：固定 1×10000/2×5000 与随机 2~10 支逐轮一致；
##   ⑦ 地形优势符合预期：高危地形对进攻方的压制单调且方向正确；
##   ⑧ 固定种子完全复现：同输入同种子逐位一致。
## 运行：Godot --headless --script res://tests/combat_statistics.gd

const BATTLE_COUNT: int = 10000

var _fail_msgs: Array[String] = []


func _init() -> void:
	var started := Time.get_ticks_msec()
	_test_position_symmetry()
	_test_tactical_randomness()
	_test_advantage_winrate()
	_test_randomness_never_beats_advantage()
	_test_split_invariance()
	_test_constrained_frontage_split_invariance()
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


# ② 独立战术随机：不同侧指纹通常得到不同修正，长期无 A/B 偏置，交换输入严格交换输出。
func _test_tactical_randomness() -> void:
	var distinct := 0
	var a_higher := 0
	var b_higher := 0
	var exchange_ok := true
	var in_range := true
	var equal_signature_ok := true
	for entropy in range(BATTLE_COUNT):
		var ab := Combat.side_tactical_modifiers(
			entropy,
			77,
			101,
			202
		)
		var ba := Combat.side_tactical_modifiers(
			entropy,
			77,
			202,
			101
		)
		if not (
			is_equal_approx(ab.x, ba.y)
			and is_equal_approx(ab.y, ba.x)
		):
			exchange_ok = false
		if (
			ab.x < 1.0 - Combat.SIDE_RANDOM_RANGE - 0.000001
			or ab.x > 1.0 + Combat.SIDE_RANDOM_RANGE + 0.000001
			or ab.y < 1.0 - Combat.SIDE_RANDOM_RANGE - 0.000001
			or ab.y > 1.0 + Combat.SIDE_RANDOM_RANGE + 0.000001
		):
			in_range = false
		if not is_equal_approx(ab.x, ab.y):
			distinct += 1
			if ab.x > ab.y:
				a_higher += 1
			else:
				b_higher += 1
		var same := Combat.side_tactical_modifiers(
			entropy,
			77,
			303,
			303
		)
		if not is_equal_approx(same.x, same.y):
			equal_signature_ok = false
	var a_share := float(a_higher) / float(maxi(distinct, 1))
	if (
		distinct < int(float(BATTLE_COUNT) * 0.95)
		or a_share < 0.45
		or a_share > 0.55
		or not exchange_ok
		or not in_range
		or not equal_signature_ok
	):
		_fail(
			"② 战术随机异常：distinct=%d A高占比=%.4f exchange=%s range=%s equal=%s"
				% [
					distinct,
					a_share,
					str(exchange_ok),
					str(in_range),
					str(equal_signature_ok),
				]
		)
	print(
		"② 独立战术随机：不同修正 %d/%d，A较高占比 %.4f，交换等变"
			% [distinct, BATTLE_COUNT, a_share]
	)


# ③ 优势方胜率：随机阵容中兵力优势方（含攻防）应有极高且稳定的胜率。
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
		_fail("③ 优势方胜率过低：%.4f（%d/%d），应≥0.95" % [rate, strong_wins, counted])
	print("③ 优势方胜率=%.4f（%d/%d，1.3~2.0倍兵力+攻防优势）" % [rate, strong_wins, counted])


# ④ 随机性不掩盖明显兵力优势：20% 优势方在 ±5% 战术波动下仍应稳定取胜。
func _test_randomness_never_beats_advantage() -> void:
	var flips := 0
	for i in range(BATTLE_COUNT):
		var battle := _make_battle(2400, 10, 10, 2000, 10, 10, 0.1)
		_run(battle, 100000 + i)
		if battle.winner_side != 1:
			flips += 1
	if flips != 0:
		_fail("④ 随机性覆盖明显兵力优势：%d/%d 场 20%%优势方未胜" % [flips, BATTLE_COUNT])
	print("④ 20%%兵力优势方全胜：%d/%d（±5%%战术随机不覆盖明显优势）" % [BATTLE_COUNT, BATTLE_COUNT])


# ⑤ 拆分不改结果：把优势侧拆成多支小军，总伤亡与胜负不变（防套利 item12）。
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
		split.tactical_key_a = _stats_side_key(
			total,
			10,
			10
		)
		split.tactical_key_b = _stats_side_key(
			enemy,
			10,
			10
		)
		var aid := 0
		for p in parts:
			split.side_a.append(_army(aid, 0, p, 10, 10)); aid += 1
		split.side_b.append(_army(100, 1, enemy, 10, 10))
		var loss_split := _run(split, bs)

		if whole.winner_side != split.winner_side or loss_whole[0] != loss_split[0] or loss_whole[1] != loss_split[1]:
			mismatches += 1
	if mismatches != 0:
		_fail("⑤ 拆分改变结果：%d/%d 场拆分后胜负或总伤亡不一致" % [mismatches, checks])
	print("⑤ 拆分不变性：%d 场拆分前后胜负与总伤亡逐位一致" % checks)


# ⑥ 受限正面拆分不变：显式覆盖完整预备队轮换，不只验证无限正面。
func _test_constrained_frontage_split_invariance() -> void:
	var fixed_whole := _make_battle(
		10000, 10, 10,
		10000, 10, 10,
		0.0,
		5000
	)
	var fixed_split := _make_split_battle(
		10000,
		[5000, 5000] as Array[int],
		10,
		10,
		10000,
		10,
		10,
		0.0,
		5000
	)
	var fixed_whole_trace := _run_trace(fixed_whole, 860001)
	var fixed_split_trace := _run_trace(fixed_split, 860001)
	var fixed_diff := _trace_difference(
		fixed_whole_trace,
		fixed_split_trace
	)
	if not bool(fixed_diff["equal"]):
		_fail(
			(
				"⑥ 固定窄正面拆分改变轨迹："
				+ "winner=%s casualties=%s rounds=%s "
				+ "attack_max=%.6f morale_max=%.9f"
			) % [
				str(fixed_diff["winner"]),
				str(fixed_diff["casualties"]),
				str(fixed_diff["rounds"]),
				float(fixed_diff["attack_max"]),
				float(fixed_diff["morale_max"]),
			]
		)

	var checks := BATTLE_COUNT / 5
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 20260803
	var mismatch_winner := 0
	var mismatch_casualties := 0
	var mismatch_rounds := 0
	var mismatch_attack := 0
	var mismatch_morale := 0
	var max_attack_diff := 0.0
	var max_morale_diff := 0.0
	for i in range(checks):
		var part_count := seed_rng.randi_range(2, 10)
		var total := seed_rng.randi_range(
			maxi(6000, part_count * 1000),
			30000
		)
		var frontage := seed_rng.randi_range(
			5000,
			mini(15000, total - 1)
		)
		var enemy := seed_rng.randi_range(5000, 25000)
		var attack := seed_rng.randi_range(8, 14)
		var defense := seed_rng.randi_range(8, 14)
		var enemy_attack := seed_rng.randi_range(8, 14)
		var enemy_defense := seed_rng.randi_range(8, 14)
		var danger := seed_rng.randf_range(0.0, 0.6)
		var battle_seed := 870000 + i
		var whole := _make_battle(
			total,
			attack,
			defense,
			enemy,
			enemy_attack,
			enemy_defense,
			danger,
			frontage
		)
		var split := _make_split_battle(
			total,
			_split_sizes(total, part_count),
			attack,
			defense,
			enemy,
			enemy_attack,
			enemy_defense,
			danger,
			frontage
		)
		var whole_trace := _run_trace(whole, battle_seed)
		var split_trace := _run_trace(split, battle_seed)
		var diff := _trace_difference(whole_trace, split_trace)
		if bool(diff["winner"]):
			mismatch_winner += 1
		if bool(diff["casualties"]):
			mismatch_casualties += 1
		if bool(diff["rounds"]):
			mismatch_rounds += 1
		if float(diff["attack_max"]) > 0.000001:
			mismatch_attack += 1
		if float(diff["morale_max"]) > 0.000000001:
			mismatch_morale += 1
		max_attack_diff = maxf(
			max_attack_diff,
			float(diff["attack_max"])
		)
		max_morale_diff = maxf(
			max_morale_diff,
			float(diff["morale_max"])
		)
	var mismatch_any := maxi(
		mismatch_winner,
		maxi(
			mismatch_casualties,
			maxi(
				mismatch_rounds,
				maxi(mismatch_attack, mismatch_morale)
			)
		)
	)
	if mismatch_any != 0:
		_fail(
			(
				"⑥ 随机窄正面拆分改变轨迹："
				+ "winner=%d casualties=%d rounds=%d "
				+ "attack=%d morale=%d/%d，max=%.6f/%.9f"
			) % [
				mismatch_winner,
				mismatch_casualties,
				mismatch_rounds,
				mismatch_attack,
				mismatch_morale,
				checks,
				max_attack_diff,
				max_morale_diff,
			]
		)
	print(
		(
			"⑥ 受限正面拆分：固定 1×10000/2×5000；"
			+ "随机 %d 场(2~10支)，胜负/伤亡/逐轮火力/士气/时长逐位一致"
		) % checks
	)


# ⑦ 地形优势符合预期：进攻方攻击倍率随地形危险度单调不增，极端地形显著压制。
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
		_fail("⑦ 地形倍率非单调：attack_multiplier 随危险度上升出现回升")
	# 极端 vs 平地：高危地形对进攻方应有明确压制。
	if not (Combat.attack_multiplier(0.95) < Combat.attack_multiplier(0.0) - 0.2):
		_fail("⑦ 极端地形压制不足：danger0.95=%.3f 应显著低于平地=%.3f" % [
			Combat.attack_multiplier(0.95), Combat.attack_multiplier(0.0)])
	print("⑦ 地形单调压制：attack_multiplier(0)=%.3f → (0.95)=%.3f，%d 点采样单调不增" % [
		Combat.attack_multiplier(0.0), Combat.attack_multiplier(0.95), samples + 1])


# ⑧ 固定种子完全复现：同一阵容同一种子跑两遍，逐位一致。
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
		_fail("⑧ 复现失败：%d/%d 场同种子两遍结果不一致" % [diffs, BATTLE_COUNT])
	print("⑧ 固定种子完全复现：%d 场两遍逐位一致" % BATTLE_COUNT)


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


func _edge(danger: float, frontage: int = 45000) -> Edge:
	var e := Edge.new()
	e.city_a = 0
	e.city_b = 1
	e.distance = 4
	e.danger = danger
	e.max_manpower = frontage
	return e


func _make_battle(
	sa: int, atk_a: int, def_a: int,
	sb: int, atk_b: int, def_b: int,
	danger: float,
	frontage: int = 45000
) -> Battle:
	var b := Battle.new()
	b.id = 0
	b.kind = Battle.Kind.FIELD
	b.edge = _edge(danger, frontage)
	b.contact_dist_a = 2.0
	b.contact_dist_b = 2.0
	b.tactical_key_a = _stats_side_key(sa, atk_a, def_a)
	b.tactical_key_b = _stats_side_key(sb, atk_b, def_b)
	b.side_a.append(_army(0, 0, sa, atk_a, def_a))
	b.side_b.append(_army(1, 1, sb, atk_b, def_b))
	return b


func _make_split_battle(
	total: int,
	parts: Array[int],
	attack: int,
	defense: int,
	enemy: int,
	enemy_attack: int,
	enemy_defense: int,
	danger: float,
	frontage: int
) -> Battle:
	var battle := Battle.new()
	battle.id = 0
	battle.kind = Battle.Kind.FIELD
	battle.edge = _edge(danger, frontage)
	battle.contact_dist_a = 2.0
	battle.contact_dist_b = 2.0
	battle.tactical_key_a = _stats_side_key(
		total,
		attack,
		defense
	)
	battle.tactical_key_b = _stats_side_key(
		enemy,
		enemy_attack,
		enemy_defense
	)
	for index in range(parts.size()):
		battle.side_a.append(
			_army(index, 0, parts[index], attack, defense)
		)
	battle.side_b.append(
		_army(100, 1, enemy, enemy_attack, enemy_defense)
	)
	return battle


func _stats_side_key(size: int, attack: int, defense: int) -> int:
	# 统计夹具没有 GameState 空间上下文，用阵容键代表稳定侧身份；交换阵容时键随阵容交换。
	return 1 + posmod(
		size * 73856093
			+ attack * 19349663
			+ defense * 83492791,
		2147483646
	)


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


func _run_trace(
	battle: Battle,
	battle_seed: int
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_seed
	Combat.clear_battle_log()
	Combat.battle_log_enabled = true
	var guard := 0
	while not battle.finished and guard < 1000:
		Combat.resolve_round(battle, rng)
		guard += 1
	var attack_a: Array[float] = []
	var attack_b: Array[float] = []
	var morale_a: Array[float] = []
	var morale_b: Array[float] = []
	var casualties_a := 0
	var casualties_b := 0
	for record in Combat.battle_log:
		attack_a.append(float(record["effective_attack_a"]))
		attack_b.append(float(record["effective_attack_b"]))
		morale_a.append(_record_force_morale(record, "a"))
		morale_b.append(_record_force_morale(record, "b"))
		casualties_a += int(record["casualties_a"])
		casualties_b += int(record["casualties_b"])
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()
	return {
		"winner": battle.winner_side,
		"casualties": [casualties_a, casualties_b],
		"rounds": guard,
		"attack_a": attack_a,
		"attack_b": attack_b,
		"morale_a": morale_a,
		"morale_b": morale_b,
	}


func _trace_difference(
	left: Dictionary,
	right: Dictionary
) -> Dictionary:
	var attack_max := maxf(
		_series_max_difference(left["attack_a"], right["attack_a"]),
		_series_max_difference(left["attack_b"], right["attack_b"])
	)
	var morale_max := maxf(
		_series_max_difference(left["morale_a"], right["morale_a"]),
		_series_max_difference(left["morale_b"], right["morale_b"])
	)
	var winner_diff: bool = (
		int(left["winner"]) != int(right["winner"])
	)
	var casualties_diff: bool = (
		left["casualties"] != right["casualties"]
	)
	var rounds_diff: bool = (
		int(left["rounds"]) != int(right["rounds"])
	)
	return {
		"equal":
			not winner_diff
			and not casualties_diff
			and not rounds_diff
			and attack_max <= 0.000001
			and morale_max <= 0.000000001,
		"winner": winner_diff,
		"casualties": casualties_diff,
		"rounds": rounds_diff,
		"attack_max": attack_max,
		"morale_max": morale_max,
	}


func _series_max_difference(left: Array, right: Array) -> float:
	var maximum := 0.0
	for index in range(mini(left.size(), right.size())):
		maximum = maxf(
			maximum,
			absf(float(left[index]) - float(right[index]))
		)
	return maximum


func _record_force_morale(
	record: Dictionary,
	side_name: String
) -> float:
	var morale_mass := 0.0
	var manpower := 0
	for key in [
		"participants_after_" + side_name,
		"routed_" + side_name,
	]:
		for army_data in record[key]:
			var size := int(army_data["size"])
			if size <= 0:
				continue
			morale_mass += (
				float(size) * float(army_data["morale"])
			)
			manpower += size
	return (
		morale_mass / float(manpower)
		if manpower > 0
		else 0.0
	)


## 将 total 拆成 n 份，尾数并入第一份（保持整数总量守恒）。
func _split_sizes(total: int, n: int) -> Array[int]:
	var base := total / n
	var out: Array[int] = []
	for i in range(n):
		out.append(base)
	out[0] += total - base * n
	return out
