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

# ---- 正面宽度 / 预备队（item 5：道路/地形/战斗类型决定同时参战兵力上限）----
## 一侧「正面宽度」= 同一时刻能投入前线交战的最大兵力。超出部分进入预备队：
## 预备队不贡献攻击、不受伤亡、不占用正面；前线部队损失后由预备队按序补入（下一回合自动重选）。
## 野战：正面 = 道路容量 edge.max_manpower（虎牢关式窄路 → 大军也只能少量展开，一夫当关）。
## 攻城：正面 = 城墙可展开兵力 SIEGE_FRONTAGE（城墙周长有限，无法全军压城）。
## 无边信息兜底用 FRONTAGE_FALLBACK。拆分不增加总正面（基于总兵力的前 N 名，与军队数量无关，item 12）。
const FRONTAGE_FALLBACK: int = 15000
const SIEGE_FRONTAGE: int = 15000

# ---- 士气 ----
const MORALE_START: float = 1.0
const MORALE_FLOOR: float = 0.0            ## 士气跌破此值该军崩溃（Army.morale 下界）
const MORALE_CASUALTY_K: float = 1.2       ## 伤亡比例对士气的侵蚀系数
const MORALE_BASE_DECAY: float = 0.01      ## 每回合基础士气衰减（保证战斗必然收敛结束）
const MORALE_STARVE_DECAY: float = 0.10    ## 断粮方每回合额外士气衰减——粮草特色
const MORALE_RECOVER: float = 0.15         ## 非交战、有粮军队每月士气恢复量（战后疲劳消退）
const MORALE_REINFORCE: float = 0.20       ## 增援集结上限系数：新友军对本侧既有成员的士气提振

# ---- 士气→战斗效率（item 2：士气是组织度而非第二血条）----
## 有效战斗力 = 名义战斗力 × combat_efficiency(morale)。
## efficiency = MIN + (1-MIN)*morale：满士气(1.0)→1.0（保持既有满士气标定不变），
## 零士气→MIN（仍能自卫但火力大幅下降，不再贡献完整伤害）。
const MIN_COMBAT_EFFICIENCY: float = 0.2
## 整侧溃败阈值（兵力加权派生士气）。不为 0：士气极低的一方在兵力归零前合理溃败。
const SIDE_ROUT_THRESHOLD: float = 0.15
## 单支军队溃退阈值：士气 <= 此值的军队视为已失去组织、退出前线（不再计入有效战力）。
const ARMY_ROUT_THRESHOLD: float = 0.05
## 单场战斗单侧「增援士气提振」的累计上限：防止靠反复添油把整条零士气战线救活。
const REINFORCE_MORALE_MAX: float = 0.20

# ---- 边地形：danger 是唯一真源 ----
const ATTACK_DANGER_K: float = 0.50        ## 攻击惩罚固定系数
const DEFENSE_DANGER_K: float = 0.40       ## 初始防御惩罚系数
const HOLDING_TAU_DAYS: float = 30.0       ## 驻防适应时间常数
## 关隘（chokepoint）连续曲线（item 9：去数值断崖）。danger≥ONSET 进入"隘口带"：攻击倍率
## 从 ONSET 处的常规线性值连续、单调地降到 danger=1.0 时的地板 FLOOR，不再在阈值处硬跳变。
## 由此「地形参数小幅变化只产生小幅结果变化」（无 0.001 跨阈战力减半），同时极端地形仍强力压制进攻。
const CHOKEPOINT_DANGER_ONSET: float = 0.85  ## 隘口带起点：danger≥此值攻击惩罚加速下探（连续，非跳变）
const CHOKEPOINT_ATTACK_FLOOR: float = 0.25  ## danger=1.0 时的攻击倍率地板（隘口最极端处）

# ---- 攻城累积（item 6/7：连续围城曲线 + 量纲统一的封锁需求）----
const SIEGE_PROGRESS_REQUIRED: float = 100.0 ## 破城所需累积进度（满 100 破城）
## 破城所需兵力（siege_required_manpower）= 执行有效封锁所需的最低兵力，item 6：仅由工事强度推导，
## 与守军人数无关——守军的作用在城下决斗阶段消耗攻方，而非抬高封锁门槛。这样「驻军被击败后，
## 城防仍存在但来自 fort_strength」（item 6 验收），有无守军封锁需求不出现数量级跳变。
const FORT_MANPOWER_PER_POINT: int = 100     ## 每点工事强度等效的封锁兵力（量纲桥：城防点→兵力）
const SIEGE_REQUIRED_FLOOR: int = 1          ## 破城所需兵力下界，避免除零
# ---- item 7 连续围城曲线：manpower_ratio = attacker_effective / siege_required_manpower ----
## 去掉「5× 硬门槛」，改为随兵力比连续变化、无跳变、极大兵力收益递减的曲线：
##   ratio < STALL(0.5)         → 每日进度为负（缓慢倒退：无法完全封锁，工事修复）
##   STALL ≤ ratio < 1.0        → 极慢正推进（部分封锁）
##   ratio = 1.0                → 正常围城下限（SIEGE_DAYS_BASE 天）
##   1.0 ~ 2.0 正常、2.0 ~ 4.0 高效、>4.0 收益递减 → days 单调降向 SIEGE_DAYS_MIN
const SIEGE_RATIO_STALL: float = 0.5         ## 倒退/推进分界比（<0.5 进度倒退）
const SIEGE_DAYS_MIN: float = 3.0            ## 饱和进攻(ratio→∞)最短围城天数
const SIEGE_DAYS_BASE: float = 30.0          ## 正常围城下限天数（ratio=1 时）
## days = MIN + (BASE-MIN)/ratio 的饱和形式在 ratio=1 时取 BASE、ratio→∞ 时取 MIN、单调递减。
## ratio=1→30、ratio=2→16.5、ratio=4→9.75、ratio→∞→3：契合「1~2 正常、2~4 高效、>4 递减」。
const SIEGE_DAYS_DECAY: float = 27.0         ## = SIEGE_DAYS_BASE - SIEGE_DAYS_MIN
const SIEGE_REGRESS_PER_DAY: float = 0.5     ## ratio<STALL 时每日进度倒退量（最深，ratio=0 时）
const SIEGE_STARVE_DEF_MULT: float = 0.3     ## 粮尽守军城防加成衰减系数（战力大幅下降）
const SIEGE_INTERRUPTION_DECAY_PER_DAY: float = 0.25 ## 守城/解围战每持续一天，攻城成果回退 0.25 点


# ---- 结构化战斗日志（item 15：调试与回放）----
## 默认关闭（零开销，满足"日志可关闭"）；启用后每个 resolve_round 末尾向 battle_log 追加
## 一条纯数据记录（无自然语言逻辑判断，满足"测试环境可读取"+"能定位战斗结果为何产生"）。
## 全静态：调用方（Simulation/测试）负责开关与清空。镜像安全——只读快照、不改任何战斗数值。
static var battle_log_enabled: bool = false
static var battle_log: Array[Dictionary] = []


static func clear_battle_log() -> void:
	battle_log.clear()


## 破城所需兵力（siege_required_manpower，item 6：恒为兵力量纲，仅由工事强度推导）。
## = 执行有效封锁所需的最低兵力，供围城比值分母与 AI 派兵门槛统一使用（唯一真源）。
##  - fort_strength：城墙/工事结构强度（城防点数量纲），经 FORT_MANPOWER_PER_POINT 换算成兵力。
## 不含守军人数：守军是城下决斗阶段的对手，被歼后本值不变（item 6 验收：城防来自 fort_strength）。
static func siege_required_manpower(fort_strength: int) -> int:
	var f := maxi(fort_strength, 0)
	return maxi(f * FORT_MANPOWER_PER_POINT, SIEGE_REQUIRED_FLOOR)


## 纯围城阶段单日进度增量（确定性，无掷骰）。item 7：连续曲线，无 5× 硬门槛、无跳变。
##  ratio = attacker_effective / siege_required_manpower（后者由 siege_required_manpower() 给出）。
##  - ratio < SIEGE_RATIO_STALL(0.5)：返回负值（缓慢倒退，无法完全封锁，越弱退得越快）。
##  - ratio ≥ 0.5：days = MIN + DECAY/ratio，进度 = REQUIRED/days；ratio=1→30 天、ratio→∞→3 天。
## 极大兵力收益递减（days 饱和到 MIN），不产生无限线性加速。
static func siege_daily_progress(attacker_effective: int, siege_required: int) -> float:
	var base := float(maxi(siege_required, SIEGE_REQUIRED_FLOOR))
	var ratio := float(maxi(attacker_effective, 0)) / base
	if ratio < SIEGE_RATIO_STALL:
		# 兵力严重不足：进度线性倒退，ratio→0 时退速最大 SIEGE_REGRESS_PER_DAY，ratio→0.5 时归零。
		return -SIEGE_REGRESS_PER_DAY * (SIEGE_RATIO_STALL - ratio) / SIEGE_RATIO_STALL
	var days := SIEGE_DAYS_MIN + SIEGE_DAYS_DECAY / ratio
	return SIEGE_PROGRESS_REQUIRED / days


## 守军或解围军打断攻城时，既有工事和破城成果按中断天数线性损失。
static func siege_progress_after_interruption(progress: float, days: int = 1) -> float:
	return maxf(
		progress - SIEGE_INTERRUPTION_DECAY_PER_DAY * float(maxi(days, 0)),
		0.0
	)


## danger 对攻击力的固定惩罚，不随驻防时间变化。item 9：全程连续、单调、无阈值跳变。
##  danger∈[0, ONSET)：常规线性 1 - ATTACK_DANGER_K·danger（moderate 地形标定不变，danger=0.5→0.75）。
##  danger∈[ONSET, 1]：隘口带——从 ONSET 处的常规线性值连续下探到 danger=1 的地板 FLOOR。
## 两段在 danger=ONSET 处取值相同（C0 连续），故不存在「浮点跨阈战力减半」。
static func attack_multiplier(danger: float) -> float:
	var normalized := clampf(danger, 0.0, 1.0)
	var linear := 1.0 - ATTACK_DANGER_K * normalized
	if normalized < CHOKEPOINT_DANGER_ONSET:
		return clampf(linear, 0.0, 1.0)
	# 隘口带内按 [ONSET,1] 归一化的进度 t，从 ONSET 处线性值插值到地板 FLOOR（连续、单调递减）。
	var onset_value := 1.0 - ATTACK_DANGER_K * CHOKEPOINT_DANGER_ONSET
	var t := (normalized - CHOKEPOINT_DANGER_ONSET) / maxf(1.0 - CHOKEPOINT_DANGER_ONSET, 1e-6)
	return clampf(lerpf(onset_value, CHOKEPOINT_ATTACK_FLOOR, t), 0.0, 1.0)


## 防御方对地形的适应：惩罚随连续驻防天数指数衰减并无限趋近 0，但永不产生正加成。
static func defense_multiplier(danger: float, holding_days: float) -> float:
	var d := clampf(danger, 0.0, 1.0)
	var days := maxf(holding_days, 0.0)
	return clampf(1.0 - DEFENSE_DANGER_K * d * exp(-days / HOLDING_TAU_DAYS), 0.0, 1.0)


## 解算一场战斗的一个回合，就地修改 battle 与其中军队的 size / 士气。
## 结束（一方崩溃或被歼灭）时置 battle.finished=true 与 winner_side(1/2)。
## shared_roll：本 tick 全局共享的战场波动骰值（item 8「共享战场随机因素」，天气/能见度/
## 战斗激烈程度）。>=0 时直接采用该值——同一 tick 内所有战斗共用同一骰，镜像成对的
## 战斗因此抽到相同波动、结果互为镜像。传 -1（默认）时退化为从 rng 逐场抽取（保留既有单测语义）。
static func resolve_round(
	battle: Battle,
	rng: RandomNumberGenerator,
	shared_roll: int = -1
) -> void:
	battle.prune_dead()
	var size_a := battle.side_size(battle.side_a)
	var size_b := battle.side_size(battle.side_b)
	# 任一方已空：对称裁决（双方同时空判平局，不再默认 side_b 胜）。
	if size_a <= 0 or size_b <= 0:
		battle.finished = true
		battle.winner_side = decide_winner(size_a <= 0, size_b <= 0, false, false, 0.0, 0.0)
		return

	battle.round_no += 1
	# item 15：回合起始士气快照（morale_before），用于日志对比 morale_after。
	var log_morale_before_a := battle.side_morale(battle.side_a) if battle_log_enabled else 0.0
	var log_morale_before_b := battle.side_morale(battle.side_b) if battle_log_enabled else 0.0
	var log_reinforced_a := battle.reinforce_fresh_a.size() if battle_log_enabled else 0
	var log_reinforced_b := battle.reinforce_fresh_b.size() if battle_log_enabled else 0

	# 规范化两侧内部顺序（镜像等变的关键）：一切战斗数学（火力/防御/士气聚合、伤亡摊分）
	# 都按数组顺序做浮点求和，而浮点加法不满足结合律——同一军队多重集若插入顺序不同，
	# 求和会差 ~1 ULP，经除法与取整放大成 1 兵差、再经士气侵蚀累积破坏镜像。
	# 按纯物理键（兵力/攻/防/士气，全降序）规范排序后，聚合与摊分仅依赖物理多重集、
	# 与加入历史无关：镜像成对的两侧因物理量相同而得到逐位一致的求和。全物理键、无 id 依赖。
	_canonicalize_side(battle.side_a)
	_canonicalize_side(battle.side_b)

	# 本 tick 新增援军的士气提振：把两侧各自「本 tick 全部新增兵力」作为整体统一结算一次，
	# 结算后清空。拆分成多支依次加入不会重复获得士气（item 12）；同质双方对称加入结果对称。
	settle_reinforcement_morale(battle.side_a, battle.reinforce_fresh_a)
	settle_reinforcement_morale(battle.side_b, battle.reinforce_fresh_b)
	battle.reinforce_fresh_a.clear()
	battle.reinforce_fresh_b.clear()

	var danger := battle.edge.danger if battle.edge != null else 0.0
	var attack_pen_a := 1.0
	var attack_pen_b := 1.0
	var defense_pen_a := 1.0
	var defense_pen_b := 1.0
	if battle.kind == Battle.Kind.FIELD:
		var terrain_attack_penalty := attack_multiplier(danger)
		if battle.holding_side == 1:
			attack_pen_b = terrain_attack_penalty
		elif battle.holding_side == 2:
			attack_pen_a = terrain_attack_penalty
		else:
			attack_pen_a = terrain_attack_penalty
			attack_pen_b = terrain_attack_penalty
		defense_pen_a = defense_multiplier(danger, battle.holding_days if battle.holding_side == 1 else 0.0)
		defense_pen_b = defense_multiplier(danger, battle.holding_days if battle.holding_side == 2 else 0.0)

	# 攻城：驻城守军（side_b）获得城防加成（仅当 side_b 确为守军时）。
	# 加成来自工事结构强度 fort_strength（city_defense_modifier 语义，非驻军人数，item 6）。
	# 粮尽（城 food_storage<=0）时城防加成大幅衰减（规格 R3：战力大幅下降）。
	var garrison_b := 0
	if battle.kind == Battle.Kind.SIEGE and battle.has_garrison and battle.city != null:
		garrison_b = battle.city.fort_strength
		if battle.city.food_storage <= 0:
			garrison_b = int(round(garrison_b * SIEGE_STARVE_DEF_MULT))

	# 正面宽度（item 5）：超出道路/城墙容量的兵力为预备队，本回合不出力、不受伤亡。
	# 参战比例 = min(总兵力, frontage)/总兵力；对双方各自计算（同一条战线共享 frontage 上限）。
	var frontage := combat_frontage(battle)
	var engaged_a := frontage_engaged_ratio(size_a, frontage)
	var engaged_b := frontage_engaged_ratio(size_b, frontage)

	# 同一回合共享战场波动。保留逐回合随机变化，但不让 side_a/side_b 身份决定运气。
	# shared_roll>=0：采用本 tick 全局共享骰（镜像成对战斗抽到同一波动）；否则逐场抽取。
	var battle_roll := (
		clampi(shared_roll, DICE_MIN, DICE_MAX)
		if shared_roll >= 0
		else rng.randi_range(DICE_MIN, DICE_MAX)
	)
	var roll_multiplier := 1.0 + battle_roll * DICE_STEP
	# 火力只由前线部队贡献（× engaged 比例）：窄路上大军无法全数展开（一夫当关）。
	var fire_a := (
		_side_attack(battle.side_a)
		* engaged_a
		* attack_pen_a
		* roll_multiplier
	)
	var fire_b := (
		_side_attack(battle.side_b)
		* engaged_b
		* attack_pen_b
		* roll_multiplier
	)

	# 各方平均有效防御（含地形惩罚；守方叠加城防）
	var def_a := _side_avg_defense(battle.side_a, size_a) * defense_pen_a
	var def_b := _side_avg_defense(battle.side_b, size_b) * defense_pen_b + garrison_b

	# 本回合伤亡：受对方火力，被己方有效防御减伤（守恒与上限交由 distribute_casualties）
	var loss_a := fire_b / K_ROUND * (DEF_REF / (DEF_REF + def_a))
	var loss_b := fire_a / K_ROUND * (DEF_REF / (DEF_REF + def_b))
	# 预备队不受伤亡（item 5）：本方伤亡上限 = 本方前线参战兵力（超出者在阵后未接敌）。
	loss_a = minf(loss_a, float(size_a) * engaged_a)
	loss_b = minf(loss_b, float(size_b) * engaged_b)

	# 伤亡按最大余数法守恒分配到各军（item 3），返回各侧实际总伤亡（整数、已守恒、已 cap）。
	var actual_a := _apply_losses(battle.side_a, loss_a)
	var actual_b := _apply_losses(battle.side_b, loss_b)

	# 士气侵蚀：作用到每支参战军队（Army.morale 为真源）。
	# 侵蚀量 = 本方「实际伤亡比」×MORALE_CASUALTY_K + 基础衰减 + 本军断粮额外衰减（粮草特色）。
	# 用实际整数伤亡而非理论浮点，保证与真实减员一致；同质双方实际伤亡相等→侵蚀相等→镜像对称。
	var erode_a := (float(actual_a) / float(size_a)) * MORALE_CASUALTY_K + MORALE_BASE_DECAY
	var erode_b := (float(actual_b) / float(size_b)) * MORALE_CASUALTY_K + MORALE_BASE_DECAY
	_erode_side_morale(battle.side_a, erode_a)
	_erode_side_morale(battle.side_b, erode_b)

	# 结束判定：兵力归零 → 歼灭；侧士气（兵力加权派生）跌破 SIDE_ROUT_THRESHOLD → 溃败撤退。
	var dead_a := battle.side_size(battle.side_a) <= 0
	var dead_b := battle.side_size(battle.side_b) <= 0
	var mor_a := battle.side_morale(battle.side_a)
	var mor_b := battle.side_morale(battle.side_b)
	var broke_a := mor_a <= SIDE_ROUT_THRESHOLD
	var broke_b := mor_b <= SIDE_ROUT_THRESHOLD
	if dead_a or dead_b or broke_a or broke_b:
		battle.finished = true
		# 对称指标裁决（item 1）：与 a/b 位置、军队 id、遍历顺序无关；完全对称判平局。
		battle.winner_side = decide_winner(
			dead_a, dead_b, broke_a, broke_b,
			_side_residual(battle.side_a), _side_residual(battle.side_b)
		)

	# item 15：结构化战斗日志（纯数据快照，可关闭、测试可读、不参与任何逻辑判断）。
	if battle_log_enabled:
		var rout_reason := "none"
		if battle.finished:
			if dead_a or dead_b:
				rout_reason = "annihilation"
			elif broke_a or broke_b:
				rout_reason = "morale_rout"
			else:
				rout_reason = "empty_side"
		battle_log.append({
			"battle_id": battle.id,
			"round_no": battle.round_no,
			"kind": battle.kind,
			"participants_a": battle.side_a.size(),
			"participants_b": battle.side_b.size(),
			"frontline_strength_a": int(round(float(size_a) * engaged_a)),
			"frontline_strength_b": int(round(float(size_b) * engaged_b)),
			"reserve_strength_a": size_a - int(round(float(size_a) * engaged_a)),
			"reserve_strength_b": size_b - int(round(float(size_b) * engaged_b)),
			"effective_attack_a": fire_a,
			"effective_attack_b": fire_b,
			"effective_defense_a": def_a,
			"effective_defense_b": def_b,
			"shared_random_modifier": roll_multiplier,
			"side_random_modifier": 1.0,   # item 8 独立侧骰已放弃（镜像公平优先），恒为 1
			"terrain_modifier_a": attack_pen_a,
			"terrain_modifier_b": attack_pen_b,
			"supply_modifier_a": (SIEGE_STARVE_DEF_MULT if _side_any_starving(battle.side_a) else 1.0),
			"supply_modifier_b": (SIEGE_STARVE_DEF_MULT if _side_any_starving(battle.side_b) else 1.0),
			"casualties_a": actual_a,
			"casualties_b": actual_b,
			"morale_before_a": log_morale_before_a,
			"morale_before_b": log_morale_before_b,
			"morale_after_a": battle.side_morale(battle.side_a),
			"morale_after_b": battle.side_morale(battle.side_b),
			"reinforcements_arrived_a": log_reinforced_a,
			"reinforcements_arrived_b": log_reinforced_b,
			"rout_reason": rout_reason,
			"winner_or_draw": battle.winner_side,
		})


## item 15 辅助：本侧是否有断粮军队（供日志 supply_modifier 快照，纯读取）。
static func _side_any_starving(side: Array[Army]) -> bool:
	for a in side:
		if a.size > 0 and a.starving:
			return true
	return false


## 战斗胜负裁决（item 1，纯函数，无 RNG）。返回 1=side_a 胜 / 2=side_b 胜 / 0=平局。
## 判定顺序：① 兵力歼灭优先（仅一方全歼→另一方胜）；② 士气溃败（仅一方崩→另一方胜）；
## ③ 双方同时失败 → 按对称「剩余续战能力」residual 裁决，完全相等则平局。
## 关键性质：交换 (a,b) 输入 → 输出对称交换（1↔2，0 不变），故不存在「默认 A 方获胜」偏置；
## residual 是兵力×效率之和，与军队 id / 创建顺序 / 遍历顺序无关。
static func decide_winner(
	dead_a: bool, dead_b: bool,
	broke_a: bool, broke_b: bool,
	residual_a: float, residual_b: float
) -> int:
	if dead_a and not dead_b:
		return 2
	if dead_b and not dead_a:
		return 1
	if dead_a and dead_b:
		return _break_tie(residual_a, residual_b)
	if broke_a and not broke_b:
		return 2
	if broke_b and not broke_a:
		return 1
	return _break_tie(residual_a, residual_b)


## 对称 tie-break：续战能力高者胜，完全相等判平局（0）。
static func _break_tie(residual_a: float, residual_b: float) -> int:
	if residual_a > residual_b:
		return 1
	if residual_b > residual_a:
		return 2
	return 0


## 规范化一侧内部顺序：按纯物理键降序（size, attack, defense, morale）就地排序。
## 目的是让后续所有浮点求和（火力/防御/士气/伤亡摊分）只依赖军队物理多重集、与加入历史无关，
## 从而在镜像下逐位一致。四键全等的两军物理上可互换，其残余相对顺序不影响任何求和结果。
static func _canonicalize_side(side: Array[Army]) -> void:
	side.sort_custom(func(a: Army, b: Army) -> bool:
		if a.size != b.size:
			return a.size > b.size
		if a.attack != b.attack:
			return a.attack > b.attack
		if a.defense != b.defense:
			return a.defense > b.defense
		return a.morale > b.morale
	)


## 一侧「剩余续战能力」= Σ 存活军队 size × combat_efficiency(morale)。对称、与顺序无关。
static func _side_residual(side: Array[Army]) -> float:
	var total := 0.0
	for a in side:
		if a.size > 0:
			total += float(a.size) * combat_efficiency(a.morale)
	return total


static func _side_attack(side: Array[Army]) -> float:
	var total := 0.0
	for a in side:
		if a.size > 0:
			total += (
				float(a.size)
				* float(a.attack)
				* maxf(a.offensive_attack_multiplier, 1.0)
				* combat_efficiency(a.morale)
			)
	return total


## 本场战斗单侧「正面宽度」容量（item 5，纯函数）。野战取道路容量、攻城取城墙容量。
## 双方共享同一正面（同一条战线/同一段城墙）。返回值 <=0 时视为无限制（回退 FRONTAGE_FALLBACK）。
static func combat_frontage(battle: Battle) -> int:
	if battle.kind == Battle.Kind.SIEGE:
		return SIEGE_FRONTAGE
	if battle.edge != null and battle.edge.max_manpower > 0:
		return battle.edge.max_manpower
	return FRONTAGE_FALLBACK


## 一侧「实际参战比例」= min(总兵力, 正面容量) / 总兵力 ∈ (0,1]（item 5，纯函数）。
## 超出正面的兵力为预备队，本回合既不出力也不受伤亡。比例只依赖总兵力与正面，
## 与军队拆成几支无关（防拆分套利 item 12）：把 1×10000 拆成 10×1000，engaged 比例完全相同。
static func frontage_engaged_ratio(side_total: int, frontage: int) -> float:
	if side_total <= 0:
		return 0.0
	if frontage <= 0 or frontage >= side_total:
		return 1.0
	return float(frontage) / float(side_total)


## 士气→战斗效率（item 2，纯函数）。efficiency = MIN + (1-MIN)*morale：
## 满士气(1.0)→1.0（保持既有满士气标定不变，故满编满士气战斗数值与重构前一致）；
## 零士气→MIN_COMBAT_EFFICIENCY（仍能自卫但火力大幅下降，不再贡献完整伤害）。
## 单调线性、无阈值台阶，士气因此是「组织度/战斗意志」而非第二条生命值。
static func combat_efficiency(morale: float) -> float:
	return MIN_COMBAT_EFFICIENCY + (1.0 - MIN_COMBAT_EFFICIENCY) * clampf(morale, 0.0, 1.0)


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


## 将本回合总伤亡守恒地摊分到本侧各军并就地扣减 size（item 3）。返回实际扣减的总伤亡（整数）。
## 委托 distribute_casualties 保证：sum == min(round(total_loss), 总存活兵力)，每支 0<=伤亡<=size。
static func _apply_losses(side: Array[Army], total_loss: float) -> int:
	if total_loss <= 0.0:
		return 0
	var alive: Array[Army] = []
	var sizes: Array[int] = []
	for a in side:
		if a.size > 0:
			alive.append(a)
			sizes.append(a.size)
	if alive.is_empty():
		return 0
	var casualties := distribute_casualties(sizes, total_loss)
	var applied := 0
	for i in range(alive.size()):
		alive[i].size -= casualties[i]
		applied += casualties[i]
	return applied


## 伤亡整数守恒分配（item 3，纯函数，无 RNG）。用「最大余数法」：
##  1) 目标总伤亡 T = min(round(total_loss), Σsizes)（不能超过总存活兵力）；
##  2) 各军精确份额 = T × size/Σsizes，先发整数部分（且不超过各自 size）；
##  3) 剩余名额按 (小数余数, -size, index) 降序补发一人，跳过已达 size 上限者；
##  4) 循环补发直至 T 发完或所有军队均达 size 上限。
## 保证：sum(result) == min(round(total_loss), Σsizes)，且对每支 0<=result[i]<=sizes[i]。
## 与「军队对象数量」无关：拆分 sizes 不改变总伤亡（防拆分套利 item 12）。
static func distribute_casualties(sizes: Array[int], total_loss: float) -> Array[int]:
	var n := sizes.size()
	var result: Array[int] = []
	result.resize(n)
	result.fill(0)
	var pool := 0
	for s in sizes:
		pool += maxi(s, 0)
	if n == 0 or pool <= 0 or total_loss <= 0.0:
		return result
	var target := mini(int(round(total_loss)), pool)
	if target <= 0:
		return result
	# 步骤 2：整数部分 + 记录小数余数
	var remainders: Array[float] = []
	remainders.resize(n)
	var assigned := 0
	for i in range(n):
		var exact := total_loss * float(sizes[i]) / float(pool)
		var whole := mini(int(floor(exact)), sizes[i])
		result[i] = whole
		assigned += whole
		remainders[i] = exact - float(floor(exact))
	# 步骤 3-4：剩余名额按余数降序补发（cap 溢出跳过），确定性 tie-break。
	var leftover := target - assigned
	# 候选按 (余数降序, size 降序, index 升序) 排序——纯物理量，无军队 id 依赖。
	var order: Array[int] = []
	for i in range(n):
		order.append(i)
	order.sort_custom(func(x: int, y: int) -> bool:
		if not is_equal_approx(remainders[x], remainders[y]):
			return remainders[x] > remainders[y]
		if sizes[x] != sizes[y]:
			return sizes[x] > sizes[y]
		return x < y
	)
	while leftover > 0:
		var progressed := false
		for i in order:
			if leftover <= 0:
				break
			if result[i] < sizes[i]:
				result[i] += 1
				leftover -= 1
				progressed = true
		if not progressed:
			break   # 所有军队均达 size 上限（target 已被 pool 夹住，理论不会走到）
	return result


## 增援集结效应（item 2/12，纯函数，无 RNG）：把「本 tick 新增的全部援军」作为一个整体，
## 按其带来的有效兵力占当前本侧总兵力的比例，统一提振既有成员士气一次。
##   fresh_effective = Σ newcomer.size × newcomer.morale（濒溃援军几乎不回气）
##   boost = min(MORALE_REINFORCE × fresh_effective / total_current, REINFORCE_MORALE_MAX)
## 只提振「既有成员」（不含本批新军自身），clamp 到 [MORALE_FLOOR, 1]。
## 关键性质：boost 只依赖新增总有效兵力与当前总兵力——把一支援军拆成多支依次加入，
## 得到的 fresh_effective 与 total 完全相同，boost 一致，不能重复获得士气奖励（防拆分套利）。
## 单场累计还受 REINFORCE_MORALE_MAX 上限约束，极小援军无法反复添油救活零士气战线。
static func settle_reinforcement_morale(side: Array[Army], newcomers: Array[Army]) -> void:
	if newcomers.is_empty():
		return
	var total := 0
	for a in side:
		if a.size > 0:
			total += a.size
	if total <= 0:
		return
	var fresh_effective := 0.0
	for nc in newcomers:
		if nc.size > 0:
			fresh_effective += float(nc.size) * clampf(nc.morale, 0.0, 1.0)
	if fresh_effective <= 0.0:
		return
	var boost := minf(
		MORALE_REINFORCE * fresh_effective / float(total),
		REINFORCE_MORALE_MAX
	)
	if boost <= 0.0:
		return
	for a in side:
		if a.size > 0 and not newcomers.has(a):
			a.morale = clampf(a.morale + boost, MORALE_FLOOR, 1.0)
