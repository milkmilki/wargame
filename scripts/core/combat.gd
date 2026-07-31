class_name Combat
extends RefCounted
## 战斗解算（全静态）。EU4 式多回合：每 tick 打一个回合（掷骰→伤亡→士气侵蚀），
## 士气先于兵力崩溃，故败方通常带残兵撤退。支持 N v M（火力按兵力聚合、伤亡按比例摊分）。
##
## 只负责一个回合的掷骰/伤亡/士气计算与 size 扣减，并在一方崩溃时置 battle.finished。
## 不负责 armies 增删 / passing_count / 占领 / 撤退落位——那些由 Simulation 处理。

const DEF_REF: float = 10.0                ## 防御减伤参考：减伤系数 = DEF_REF/(DEF_REF+eff_def)
const K_ROUND: float = 120.0               ## 单回合伤害除数（越大每回合伤亡越小，战斗越久）

# ---- 战场波动（双方共享，避免阵营顺序造成系统性运气差）----
const DICE_MIN: int = 0
const DICE_MAX: int = 9
const DICE_STEP: float = 0.15              ## 每点骰值放大火力比例（满骰 +135%）

# ---- 士气 ----
const MORALE_START: float = 1.0
const MORALE_FLOOR: float = 0.0            ## 士气跌破此值该方崩溃
const MORALE_CASUALTY_K: float = 1.2       ## 伤亡比例对士气的侵蚀系数
const MORALE_BASE_DECAY: float = 0.01      ## 每回合基础士气衰减（保证战斗必然收敛结束）
const MORALE_STARVE_DECAY: float = 0.10    ## 断粮方每回合额外士气衰减——粮草特色
const MORALE_RECOVER: float = 0.15         ## 非交战、有粮军队每月士气恢复量（战后疲劳消退）
const MORALE_REINFORCE: float = 0.20       ## 增援集结上限系数：新友军对本侧既有成员的士气提振

# ---- 边地形：danger 是唯一真源 ----
const ATTACK_DANGER_K: float = 0.50        ## 攻击惩罚固定系数
const DEFENSE_DANGER_K: float = 0.40       ## 初始防御惩罚系数
const HOLDING_TAU_DAYS: float = 30.0       ## 驻防适应时间常数

# ---- 攻城累积（平衡规格 R2：确定性递减，守军清空后进入纯围城阶段）----
const SIEGE_PROGRESS_REQUIRED: float = 100.0 ## 破城所需累积进度（满 100 破城）
const SIEGE_RATIO_MIN: float = 5.0           ## 有效推进的最低兵力倍数：攻/守基准 < 5 则围城僵持不推进
const SIEGE_DAYS_MIN: float = 3.0            ## 饱和进攻(r→∞)最短围城天数
const SIEGE_DAYS_BASE: float = 90.0          ## 基准围城天数（r=SIEGE_RATIO_MIN 时）
## 递减系数 = (BASE-MIN)*RATIO_MIN，使 days = MIN + K/r 在 r=5 时取 BASE、r→∞ 时取 MIN。
const SIEGE_DECAY_K: float = 435.0           ## (90-3)*5 = 435
const SIEGE_STARVE_DEF_MULT: float = 0.3     ## 粮尽守军城防加成衰减系数（战力大幅下降）
const SIEGE_INTERRUPTION_DECAY_PER_DAY: float = 0.25 ## 守城/解围战每持续一天，攻城成果回退 0.25 点


## 纯围城阶段单日进度增量（确定性，无掷骰）。ratio = 攻方兵力 / 守方基准。
##  - ratio < SIEGE_RATIO_MIN(5)：返回 0，围城僵持不推进（兵力不足以有效攻城）。
##  - ratio >= 5：围城天数 = clamp(MIN + K/ratio, MIN, BASE)；每日进度 = REQUIRED / 天数。
## 数值标定：ratio=5 → 90 天；ratio→∞ → 3 天，单调平滑递减。
static func siege_daily_progress(attacker_size: int, garrison_ref: int) -> float:
	var base := float(maxi(garrison_ref, 1))
	var ratio := float(maxi(attacker_size, 0)) / base
	if ratio < SIEGE_RATIO_MIN:
		return 0.0
	var days := clampf(SIEGE_DAYS_MIN + SIEGE_DECAY_K / ratio, SIEGE_DAYS_MIN, SIEGE_DAYS_BASE)
	return SIEGE_PROGRESS_REQUIRED / days


## 守军或解围军打断攻城时，既有工事和破城成果按中断天数线性损失。
static func siege_progress_after_interruption(progress: float, days: int = 1) -> float:
	return maxf(
		progress - SIEGE_INTERRUPTION_DECAY_PER_DAY * float(maxi(days, 0)),
		0.0
	)


## danger 对攻击力的固定惩罚，不随驻防时间变化。
static func attack_multiplier(danger: float) -> float:
	return clampf(1.0 - ATTACK_DANGER_K * clampf(danger, 0.0, 1.0), 0.0, 1.0)


## 防御方对地形的适应：惩罚随连续驻防天数指数衰减并无限趋近 0，但永不产生正加成。
static func defense_multiplier(danger: float, holding_days: float) -> float:
	var d := clampf(danger, 0.0, 1.0)
	var days := maxf(holding_days, 0.0)
	return clampf(1.0 - DEFENSE_DANGER_K * d * exp(-days / HOLDING_TAU_DAYS), 0.0, 1.0)


## 解算一场战斗的一个回合，就地修改 battle 与其中军队的 size / 士气。
## 结束（一方崩溃或被歼灭）时置 battle.finished=true 与 winner_side(1/2)。
static func resolve_round(battle: Battle, rng: RandomNumberGenerator) -> void:
	battle.prune_dead()
	var size_a := battle.side_size(battle.side_a)
	var size_b := battle.side_size(battle.side_b)
	# 任一方已空：另一方获胜（歼灭/自然退出）
	if size_a <= 0 or size_b <= 0:
		battle.finished = true
		battle.winner_side = 1 if size_a > 0 else 2
		return

	battle.round_no += 1

	var danger := battle.edge.danger if battle.edge != null else 0.0
	var attack_pen_a := 1.0
	var attack_pen_b := 1.0
	var defense_pen_a := 1.0
	var defense_pen_b := 1.0
	if battle.kind == Battle.Kind.FIELD:
		attack_pen_a = attack_multiplier(danger)
		attack_pen_b = attack_multiplier(danger)
		defense_pen_a = defense_multiplier(danger, battle.holding_days if battle.holding_side == 1 else 0.0)
		defense_pen_b = defense_multiplier(danger, battle.holding_days if battle.holding_side == 2 else 0.0)

	# 攻城：驻城守军（side_b）获得城防加成（仅当 side_b 确为守军时）。
	# 粮尽（城 food_storage<=0）时城防加成大幅衰减（规格 R3：战力大幅下降）。
	var garrison_b := 0
	if battle.kind == Battle.Kind.SIEGE and battle.has_garrison and battle.city != null:
		garrison_b = battle.city.defense
		if battle.city.food_storage <= 0:
			garrison_b = int(round(garrison_b * SIEGE_STARVE_DEF_MULT))

	# 同一回合共享战场波动。保留逐回合随机变化，但不让 side_a/side_b 身份决定运气。
	var battle_roll := rng.randi_range(DICE_MIN, DICE_MAX)
	var roll_multiplier := 1.0 + battle_roll * DICE_STEP
	var fire_a := (
		_side_attack(battle.side_a)
		* attack_pen_a
		* roll_multiplier
	)
	var fire_b := (
		_side_attack(battle.side_b)
		* attack_pen_b
		* roll_multiplier
	)

	# 各方平均有效防御（含地形惩罚；守方叠加城防）
	var def_a := _side_avg_defense(battle.side_a, size_a) * defense_pen_a
	var def_b := _side_avg_defense(battle.side_b, size_b) * defense_pen_b + garrison_b

	# 本回合伤亡：受对方火力，被己方有效防御减伤
	var loss_a := fire_b / K_ROUND * (DEF_REF / (DEF_REF + def_a))
	var loss_b := fire_a / K_ROUND * (DEF_REF / (DEF_REF + def_b))
	loss_a = minf(loss_a, float(size_a))
	loss_b = minf(loss_b, float(size_b))

	_apply_losses(battle.side_a, loss_a, size_a)
	_apply_losses(battle.side_b, loss_b, size_b)

	# 士气侵蚀：作用到每支参战军队（Army.morale 为真源）。
	# 侵蚀量 = 本方伤亡比×MORALE_CASUALTY_K + 基础衰减 + 本军断粮额外衰减（粮草特色）。
	# 伤亡比按本侧整体计（同侧共担），断粮按各军自身状态（谁断粮谁掉得快）。
	var erode_a := (loss_a / float(size_a)) * MORALE_CASUALTY_K + MORALE_BASE_DECAY
	var erode_b := (loss_b / float(size_b)) * MORALE_CASUALTY_K + MORALE_BASE_DECAY
	_erode_side_morale(battle.side_a, erode_a)
	_erode_side_morale(battle.side_b, erode_b)

	# 结束判定：兵力归零 → 歼灭；侧士气（兵力加权派生）崩溃 → 撤退（带残兵）
	var dead_a := battle.side_size(battle.side_a) <= 0
	var dead_b := battle.side_size(battle.side_b) <= 0
	var mor_a := battle.side_morale(battle.side_a)
	var mor_b := battle.side_morale(battle.side_b)
	var broke_a := mor_a <= MORALE_FLOOR
	var broke_b := mor_b <= MORALE_FLOOR
	if dead_a or dead_b or broke_a or broke_b:
		battle.finished = true
		# 兵力歼灭优先决定胜负；否则士气先崩者败；同时崩溃则士气高者胜
		if dead_a and not dead_b:
			battle.winner_side = 2
		elif dead_b and not dead_a:
			battle.winner_side = 1
		elif broke_a and not broke_b:
			battle.winner_side = 2
		elif broke_b and not broke_a:
			battle.winner_side = 1
		else:
			battle.winner_side = 1 if mor_a >= mor_b else 2


static func _side_attack(side: Array[Army]) -> float:
	var total := 0.0
	for a in side:
		if a.size > 0:
			total += float(a.size) * float(a.attack)
	return total


static func _side_avg_defense(side: Array[Army], side_size: int) -> float:
	if side_size <= 0:
		return 0.0
	var wsum := 0.0
	for a in side:
		if a.size > 0:
			wsum += float(a.size) * float(a.defense)
	return wsum / float(side_size)


## 对一侧每支存活军队侵蚀士气。基础侵蚀同侧共担；断粮军队额外掉 MORALE_STARVE_DECAY。
## 直接写入 Army.morale（真源），clamp 到 [MORALE_FLOOR, 1]。
static func _erode_side_morale(side: Array[Army], base_erode: float) -> void:
	for a in side:
		if a.size <= 0:
			continue
		var e := base_erode
		if a.starving:
			e += MORALE_STARVE_DECAY
		a.morale = clampf(a.morale - e, MORALE_FLOOR, 1.0)


## 将本回合总伤亡按各军兵力比例摊分（大军承担更多绝对伤亡）。
static func _apply_losses(side: Array[Army], total_loss: float, side_size: int) -> void:
	if side_size <= 0 or total_loss <= 0.0:
		return
	for a in side:
		if a.size <= 0:
			continue
		var share := int(round(total_loss * float(a.size) / float(side_size)))
		a.size -= share


## 增援集结效应：一支新友军加入某侧时，按其相对兵力与自身士气提振本侧「既有成员」士气。
## fresh_weight = newcomer.size / 新侧总兵力 ∈ (0,1]；boost = MORALE_REINFORCE × newcomer.morale × fresh_weight。
## 只提振既有成员（不含新军自身），clamp 到 [MORALE_FLOOR, 1]。确定性、无 RNG。
## 语义：越大、越满员的援军带来越强的士气回稳；濒溃的援军几乎不回气。
## 前置约定：调用时 newcomer 已在 side 内，total 含新军；对既有成员用 a != newcomer 跳过。
static func reinforce_morale(side: Array[Army], newcomer: Army) -> void:
	var total := 0
	for a in side:
		if a.size > 0:
			total += a.size
	if total <= 0:
		return
	var fresh_weight := float(maxi(newcomer.size, 0)) / float(total)
	var boost := MORALE_REINFORCE * newcomer.morale * fresh_weight
	if boost <= 0.0:
		return
	for a in side:
		if a.size > 0 and a != newcomer:
			a.morale = clampf(a.morale + boost, MORALE_FLOOR, 1.0)
