class_name Simulation
extends Node
## 模拟系统：实时驱动时间。行军/战斗/占领/军粮分配每天推进；
## 资源生产、补员、外交与非战斗士气恢复每月结算。
## 只写 GameState，调用 Pathfinding / Combat。表现层只读，不在此处理渲染。

# ---- 时间（天/月分层）----
## 基础 tick = 1 天。军粮月耗通过小数债摊到每天，经济生产等仍每 DAYS_PER_MONTH 天结算。
const DAYS_PER_MONTH: int = 30
const DAYS_PER_HALF_YEAR: int = 180        ## 半年 = 180 天（粮食注入周期）
# ---- 行军时长（平衡规格 R1：纯距离线性）----
const MARCH_DAYS_MIN: float = 10.0         ## 任意边最短行军 10 天（distance=1）
const MARCH_DAYS_PER_DISTANCE_STEP: float = 5.0
const MISSING_EDGE_TRAVEL_DAYS: float = 30.0
var seconds_per_day: float = 1.0           ## 默认 1 秒 = 1 天
var paused: bool = false
const SPEED_MIN: float = 0.25
const SPEED_MAX: float = 4.0

# ---- 粮食 / 饥饿 调参常量（§6.7）----
const FOOD_PER_CAPITA: float = 0.0025      ## 每人月耗（400 人耗 1 粮）
const MAX_SUPPLY_MULT: float = 3.0         ## 消耗倍率上限（最大 3 倍）
const STARVE_RATE: float = 0.5             ## 完全断粮时每月减员比例
const SUPPLY_MORALE_LOSS_MAX: float = 0.20 ## 完全断粮时每月士气损失；部分缺粮按缺口比例缩放
const HOLDING_TARGET_PROGRESS: float = 0.35 ## 从己方端点出发，驻防在边的己方侧
const HOLDING_STARVE_DECAY: int = 2        ## 完全断粮时每天损失的驻防适应天数
const CITY_GARRISON_CAPACITY_PER_MANPOWER: float = 1000.0
const CITY_GARRISON_FOOD_PENALTY_RATE: float = 0.20
const CITY_GARRISON_FOOD_PENALTY_MAX: float = 0.30
const CITY_WAR_DISRUPTION_DAYS: int = 365
const CITY_WAR_OUTPUT_MULTIPLIER: float = 0.50
## 撤退驻城恢复每月消耗：复用普通驻军月耗口径（size × FOOD_PER_CAPITA）。
## 资源不足时按实际供给比例恢复；士气回满或本城粮尽后解除 RECOVERING。
const RECOVERY_FOOD_PER_CAPITA: float = FOOD_PER_CAPITA
## 规格 R3：被围粮仓城市每日消耗本地库存；普通城市无粮仓，被围即失去外部补给。
const SIEGE_CITY_FOOD_PER_DAY: int = 1     ## 被围城每日粮草消耗系数
# ---- 占领 ----
const CITY_FORT_CAPTURE_MULTIPLIER: float = 0.50
const CITY_FORT_RECOVERY_DAYS: int = 365
const CAPITAL_FOOD_CAPTURE_RATE: float = 0.30 ## 首都失守时库存缴获比例，其余损毁
# ---- 遭遇战触发 ----
## 边内接触阈值（以边长归一化的 move_progress 为单位，即 [0,1] 区间）。
## 双方沿同边推进，当各自「以 city_a 为原点的归一化位置」之差 <= 此值（或相向已交错）才触发。
const CONTACT_EPS: float = 0.15
## 增援抵达半径（item 4）：已开战后，后续逼近的军队（含 MOVING）必须行进到距己方战线
## 归一化距离 <= 此值才算「抵达战场」并加入战斗。抵达前继续行军、不贡献攻击/不受伤亡/不占 frontage。
## eta = 剩余归一化距离 × edge_travel_days(edge)，由 move_progress 每日推进兑现。
const REINFORCEMENT_RADIUS: float = 0.15
const AI_DECISION_INTERVAL_DAYS: int = 10
const GRID_AI_DECISION_INTERVAL_DAYS: int = 5
const DIPLOMACY_DECISION_INTERVAL_DAYS: int = DAYS_PER_MONTH
const NEW_ARMY_SIZE: int = 5000
const NARROW_ROUTE_FORMATION_SIZE: int = Edge.MIN_MANPOWER
const DISBAND_SIZE_MAX: int = 499
const REINFORCE_PER_ARMY_PER_MONTH: int = 750
const PEACETIME_MANPOWER_RESERVE: int = 5000
const PEACETIME_STRENGTH_RATIO: float = 0.30
const FOOD_SECURITY_RESERVE_MONTHS: int = 6
const FOOD_RESERVE_RECOVERY_MONTHS: int = 6
const DEMOBILIZATION_STEP_MIN: int = 500
const WAR_MOBILIZATION_DAYS: int = 180
const CAMPAIGN_OFFENSIVE_INTERVAL_DAYS: int = 30
const CAMPAIGN_OFFENSIVE_COMMIT_DAYS: int = 45
const CAMPAIGN_ARROW_DURATION_DAYS: int = 20
const PREPARATION_MAX_ORDERS_PER_CYCLE: int = 3
const CAMPAIGN_MAX_TARGETS: int = 3
const CAMPAIGN_ATTACK_ENTER_RATIO: float = 1.00
const CAMPAIGN_TARGET_COMMIT_RATIO: float = 1.00
const CAMPAIGN_STAGED_TROOP_RATIO: float = 0.75
const CAMPAIGN_PARALLEL_SURPLUS_STEP_RATIO: float = 0.50
const CAMPAIGN_THEATER_MAX_TRANSFER_COST: float = 12.0
const CAMPAIGN_PREPARED_ECHELONS: int = 2
const OFFENSIVE_BONUS_MAX_PREPARATION_DAYS: int = DAYS_PER_HALF_YEAR
const OFFENSIVE_BONUS_MAX_MULTIPLIER: float = 2.0
const CAMPAIGN_POST_CAPTURE_DEFENSE_RATIO: float = 1.10
const CAMPAIGN_POST_CAPTURE_MORALE_MIN: float = 0.65
const CAMPAIGN_POST_CAPTURE_SUPPLY_MIN: float = 0.75
const DEFENSIVE_DEPLOYMENT_LOCK_DAYS: int = 90
const LIGHT_ONLY_OFFENSIVE_MAX_ARMIES: int = 2
const CAMPAIGN_BORROWED_LINE_MAX_ARMIES: int = 1
const SMALL_NATION_SURVIVAL_MAX_CITIES: int = 4
const SMALL_NATION_MOBILE_RESERVE_ARMIES: int = 1
const EMERGENCY_RECRUITMENT_MIN_RUNWAY_YEARS: float = 0.25

var state: GameState
var _time_acc: float = 0.0
var _ai_strategy_cache: Dictionary = {}    ## nation_id -> StrategicMapSnapshot
var _ai_strategy_revision: Dictionary = {} ## nation_id -> [ownership, diplomacy, fortification]
var _threat_travel_cache: Dictionary = {}  ## "start:max_size" -> 只依赖静态道路的行军天数字段
var _ai_path_field_cache: Dictionary = {}
var _ai_supply_source_cache: Dictionary = {}
var _ai_supply_network_cache: Dictionary = {}
var _monthly_supply_source_cache: Dictionary = {}
var _monthly_supply_network_cache: Dictionary = {}
## 每日补给可达性缓存（item 10 滚动结算专用）：每天开头清空重建，
## 使月中被切断/恢复的补给线当天即被感知，而不必等到月度经济结算。
var _daily_supply_source_cache: Dictionary = {}
var _daily_supply_network_cache: Dictionary = {}
var _ai_last_decision_day: int = -1
var _collect_ai_commands: bool = false
var _ai_command_buffer: Array[AiCommandIntent] = []
var _ai_planned_armies: Dictionary = {}
var _ai_planned_first_legs: Dictionary = {}
var _ai_command_sequence: Dictionary = {}
var _ai_snapshot_armies: Dictionary = {}
var ai_last_command_commit_failures: int = 0
var ai_command_commit_failure_total: int = 0
var ai_command_commit_failure_log: Array[String] = []
## 测试/基准注入点：nation_id -> Callable(state, nation_id, simulation)。
## 正式游戏保持为空，所有国家均使用 Utility AI。
var ai_policy_overrides: Dictionary = {}
## A/B 基准注入点：nation_id -> 正常进攻单军最低战力占比；正式游戏使用 UtilityAI 默认值。
var ai_assault_participant_ratio_overrides: Dictionary = {}
## A/B 注入点：false 关闭“同层级主力优先”，平局仍使用镜像等变物理序。
var ai_tactical_decision_order_overrides: Dictionary = {}
## A/B 注入点：false 关闭粮道桥梁/割点的守备与增援需求。
var ai_supply_corridor_defense_overrides: Dictionary = {}
## A/B 注入点：false 复现攻击候选不检查实际通行路径的旧逻辑。
var ai_executable_attack_paths_overrides: Dictionary = {}
## A/B 注入点：true 复现由 nation_id 隐式生成 AI 性格的旧逻辑。
var ai_legacy_id_personality_overrides: Dictionary = {}
## 每个 AI 决策轮次轮换统一提交顺序，避免固定国家永久先提交。
var rotate_ai_nation_order: bool = true
## A/B 基准注入点：false 保留修改前的静态进攻评分。
var ai_strategic_planning_overrides: Dictionary = {}
## A/B 基准注入点：false 保留修改前的 60 天传播威胁守备策略。
var ai_adaptive_garrison_overrides: Dictionary = {}
## 隔离军事状态机测试时可关闭；正式游戏始终保持 true。
var diplomacy_enabled: bool = true

func setup(game_state: GameState) -> void:
	state = game_state
	_normalize_city_fortifications()
	state.refresh_derived()
	_ai_strategy_cache.clear()
	_ai_strategy_revision.clear()
	_threat_travel_cache.clear()
	_ai_path_field_cache.clear()
	_ai_supply_source_cache.clear()
	_ai_supply_network_cache.clear()
	_monthly_supply_source_cache.clear()
	_monthly_supply_network_cache.clear()
	_daily_supply_source_cache.clear()
	_daily_supply_network_cache.clear()
	_ai_last_decision_day = -1
	ai_last_command_commit_failures = 0
	ai_command_commit_failure_total = 0
	ai_command_commit_failure_log.clear()
	_clear_ai_command_collection()


func _process(delta: float) -> void:
	if state == null or paused or state.winner != -1:
		return
	_time_acc += delta
	while _time_acc >= seconds_per_day:
		_time_acc -= seconds_per_day
		_advance_day()
		if state.winner != -1:
			break


func set_speed_multiplier(mult: float) -> void:
	## mult 表示"相对默认速度"的倍率。seconds_per_day = 1/mult。
	var m := clampf(mult, SPEED_MIN, SPEED_MAX)
	seconds_per_day = 1.0 / m


func speed_multiplier() -> float:
	return 1.0 / seconds_per_day


## 当前天已流逝的比例 [0,1)。仅供表现层做 tick 间插值，不参与任何逻辑。
func day_fraction() -> float:
	if paused or state == null or state.winner != -1:
		return 0.0
	return clampf(_time_acc / seconds_per_day, 0.0, 1.0)

# ================================================================== 天推进

func _advance_day() -> void:
	state.day += 1
	state.month = state.day / DAYS_PER_MONTH
	state.prune_campaign_visual_events()
	_expire_offensive_bonuses()
	_recover_city_fortifications()
	# 每月结算资源生产、补员与外交；普通军粮在下方每日重新分配。
	if state.day % DAYS_PER_MONTH == 0:
		_resolve_economy()
		_resolve_reinforcements()
		_resolve_diplomacy()
	_resolve_line_edge_assignment_emergencies()
	# 日供应量与路径、兵力、共享库存竞争同日更新；月耗通过 Army.supply_food_debt
	# 按 1/30 累积到整粮后扣除，不放大整数库存。
	_resolve_supply()
	if state.day % DAYS_PER_MONTH == 0:
		_monthly_supply_source_cache.clear()
		_monthly_supply_network_cache.clear()
		_recover_morale()
	# 断粮后果读取刚计算的当日满足率，按 1/30 累计士气与减员。
	_apply_supply_pressure()
	ArmyCoordinator.merge_colocated(state)
	var ai_decision_interval := (
		AI_DECISION_INTERVAL_DAYS
		if state.uses_heightmap
		else GRID_AI_DECISION_INTERVAL_DAYS
	)
	if state.day % ai_decision_interval == 0 or _ai_last_decision_day == -1:
		_ai_assign_targets()
	_advance_campaign_echelons()
	_advance_priority_city_defense_echelons()
	_advance_movement()
	_resolve_eliminated_nation_capitulations()
	_advance_holding_adaptation()
	_drain_siege_food()   # 规格 R3：被围城每日耗粮（补给孤岛的粮草时钟）
	_refresh_war_flags()
	_check_victory()
	state.refresh_derived()


static func offensive_preparation_multiplier(
	preparation_days: int
) -> float:
	var ratio := clampf(
		float(maxi(preparation_days, 0))
			/ float(OFFENSIVE_BONUS_MAX_PREPARATION_DAYS),
		0.0,
		1.0
	)
	return lerpf(1.0, OFFENSIVE_BONUS_MAX_MULTIPLIER, ratio)


static func offensive_bonus_duration_days(
	preparation_days: int
) -> int:
	return clampi(
		preparation_days,
		0,
		OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
	)


func _campaign_preparation_days(nation_id: int) -> int:
	var nation := state.nations[nation_id]
	if nation.campaign_preparation_started_day < 0:
		nation.campaign_preparation_started_day = (
			nation.campaign_last_offensive_day
			if nation.campaign_last_offensive_day >= 0
			else state.day
		)
	return maxi(
		state.day - nation.campaign_preparation_started_day,
		0
	)


func _clear_campaign_preparation_plan(nation_id: int) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_preparation_targets.clear()
	nation.campaign_preparation_assignments.clear()
	nation.campaign_preparation_group_assignments.clear()
	nation.campaign_full_preparation_targets.clear()
	nation.campaign_preparation_started_day = -1
	nation.campaign_preparation_multiplier = 1.0


func _campaign_projected_assault_ratio(
	nation_id: int,
	objective_city: int,
	preparation_days: int,
	threat: ThreatField = null,
	assigned_only: bool = false
) -> float:
	if objective_city < 0 or objective_city >= state.cities.size():
		return 0.0
	var attack_power := 0.0
	var staged_armies := (
		_campaign_preparation_staged_armies(
			nation_id,
			objective_city
		)
		if assigned_only
		else _campaign_staged_armies(
			nation_id,
			objective_city
		)
	)
	for army in staged_armies:
		attack_power += ArmyPower.effective(army)
	attack_power *= offensive_preparation_multiplier(
		preparation_days
	)
	var direct_defense := 0.0
	for defender in state.armies_at_city(objective_city):
		if state.is_enemy(nation_id, defender.owner_nation):
			direct_defense += ArmyPower.effective(defender)
	var defense_power := direct_defense
	if threat != null:
		defense_power = maxf(
			defense_power,
			threat.threat_at(objective_city)
		)
	if state.recognized_owner_of(objective_city) != nation_id:
		defense_power += ArmyPower.city_defense(
			state.cities[objective_city]
		)
	return attack_power / maxf(defense_power, 1.0)


func _campaign_attack_ratio_threshold(nation_id: int) -> float:
	return CAMPAIGN_ATTACK_ENTER_RATIO / clampf(
		state.nations[nation_id].ai_aggression,
		0.5,
		1.5
	)


func _campaign_minimum_staged_troops(
	nation_id: int,
	target_city: int
) -> int:
	if (
		state.uses_heightmap
		and state.nations[nation_id]
			.campaign_preparation_group_assignments.has(
				target_city
			)
	):
		return 1
	return maxi(
		int(ceil(
			float(
				DiplomacyAI.required_assault_troops(
					state,
					nation_id,
					target_city
				)
			) * CAMPAIGN_STAGED_TROOP_RATIO
		)),
		1
	)


func _campaign_offensive_interval(nation_id: int) -> int:
	var aggression := clampf(
		state.nations[nation_id].ai_aggression,
		0.5,
		1.5
	)
	return int(round(
		float(CAMPAIGN_OFFENSIVE_INTERVAL_DAYS)
			/ aggression
	))


static func city_fort_strength_after_capture(
	full_strength: int,
	elapsed_days: int
) -> int:
	var maximum := maxi(full_strength, 0)
	if maximum <= 0:
		return 0
	var damaged := clampi(
		int(round(
			float(maximum) * CITY_FORT_CAPTURE_MULTIPLIER
		)),
		0,
		maximum
	)
	if damaged >= maximum or elapsed_days <= 0:
		return damaged
	if elapsed_days >= CITY_FORT_RECOVERY_DAYS:
		return maximum
	var progress := clampf(
		float(elapsed_days)
			/ float(CITY_FORT_RECOVERY_DAYS),
		0.0,
		1.0
	)
	# 整数城防在一年到期前不得因四舍五入提前回满。
	return clampi(
		int(floor(lerpf(
			float(damaged),
			float(maximum),
			progress
		))),
		damaged,
		maximum - 1
	)


static func city_fort_vulnerability(
	city: City,
	current_day: int
) -> float:
	if city == null or city.fort_last_capture_day < 0:
		return 0.0
	return 1.0 - clampf(
		float(maxi(
			current_day - city.fort_last_capture_day,
			0
		)) / float(CITY_FORT_RECOVERY_DAYS),
		0.0,
		1.0
	)


func _normalize_city_fortifications() -> void:
	for city in state.cities:
		city.fort_strength_max = maxi(
			city.fort_strength_max,
			city.fort_strength
		)


func _recover_city_fortifications() -> void:
	var fortification_changed := false
	for city in state.cities:
		city.fort_strength_max = maxi(
			city.fort_strength_max,
			city.fort_strength
		)
		if city.fort_last_capture_day < 0:
			continue
		var recovered := city_fort_strength_after_capture(
			city.fort_strength_max,
			maxi(
				state.day - city.fort_last_capture_day,
				0
			)
		)
		if recovered != city.fort_strength:
			city.fort_strength = recovered
			fortification_changed = true
	if fortification_changed:
		state.fortification_revision += 1
	# 已建立的围城也必须读取恢复后的当前工事，不能永久冻结在开战日。
	for battle in state.battles:
		if (
			battle.finished
			or battle.kind != Battle.Kind.SIEGE
			or battle.city == null
			or battle.city.fort_last_capture_day < 0
		):
			continue
		battle.siege_required = Combat.siege_required_manpower(
			battle.city.fort_strength
		)


func _expire_offensive_bonuses() -> void:
	for army in state.armies:
		if (
			army.offensive_bonus_until_day >= 0
			and state.day >= army.offensive_bonus_until_day
		):
			army.offensive_attack_multiplier = 1.0
			army.offensive_bonus_until_day = -1

# ------------------------------------------------------------------ 1. 经济

func _resolve_economy() -> void:
	for city in state.cities:
		var nation := state.nations[city.owner_nation]
		nation.treasury_gold += city_gold_output(
			state,
			city
		)
		nation.manpower_pool += city.manpower_per_month
	_resolve_military_finance()
	if state.day % DAYS_PER_HALF_YEAR == 0:
		var produced: Array[int] = []
		produced.resize(state.nations.size())
		produced.fill(0)
		for city in state.cities:
			produced[city.owner_nation] += city_food_output(
				state,
				city
			)
		for nation in state.nations:
			state.deposit_food(nation.id, produced[nation.id])


static func city_food_output(
	game_state: GameState,
	city: City
) -> int:
	var garrison_output := city_food_output_for_garrison(
		city,
		city_garrison_troops(game_state, city)
	)
	return _apply_city_war_disruption(
		game_state,
		city,
		garrison_output
	)


static func city_gold_output(
	game_state: GameState,
	city: City
) -> int:
	return _apply_city_war_disruption(
		game_state,
		city,
		city.gold_per_month
	)


static func city_war_disrupted(
	game_state: GameState,
	city: City
) -> bool:
	return game_state.day < city.war_disruption_until_day


static func _apply_city_war_disruption(
	game_state: GameState,
	city: City,
	output: int
) -> int:
	if not city_war_disrupted(game_state, city):
		return maxi(output, 0)
	return maxi(int(floor(
		float(output)
			* CITY_WAR_OUTPUT_MULTIPLIER
	)), 0)


static func city_food_output_for_garrison(
	city: City,
	garrison_troops: int
) -> int:
	var capacity := maxf(
		float(city.manpower_per_month)
			* CITY_GARRISON_CAPACITY_PER_MANPOWER,
		1.0
	)
	var penalty := minf(
		CITY_GARRISON_FOOD_PENALTY_MAX,
		float(maxi(garrison_troops, 0))
			/ capacity
			* CITY_GARRISON_FOOD_PENALTY_RATE
	)
	return maxi(int(floor(
		float(city.food_per_half_year)
			* (1.0 - penalty)
	)), 0)


static func city_garrison_troops(
	game_state: GameState,
	city: City
) -> int:
	var result := 0
	for army in game_state.armies:
		if (
			army.size > 0
			and army.owner_nation == city.owner_nation
			and not army.on_edge
			and army.location_city == city.id
		):
			result += army.size
	return result


static func city_garrison_food_loss(
	game_state: GameState,
	city: City,
	additional_troops: int = 0
) -> int:
	var current_troops := city_garrison_troops(
		game_state,
		city
	)
	return (
		_apply_city_war_disruption(
			game_state,
			city,
			city_food_output_for_garrison(
				city,
				current_troops
			)
		)
		- _apply_city_war_disruption(
			game_state,
			city,
			city_food_output_for_garrison(
				city,
				current_troops
					+ maxi(additional_troops, 0)
			)
		)
	)


func _resolve_military_finance() -> void:
	for nation in state.nations:
		var upkeep := state.nation_monthly_military_upkeep(
			nation.id
		)
		var paid := mini(nation.treasury_gold, upkeep)
		nation.treasury_gold -= paid
		nation.last_military_upkeep = upkeep
		nation.unpaid_military_upkeep = upkeep - paid
		nation.military_payment_ratio = (
			1.0
			if upkeep <= 0
			else clampf(
				float(paid) / float(upkeep),
				0.0,
				1.0
			)
		)


# ------------------------------------------------------------------ 1b. 全国人口补员

func _resolve_reinforcements() -> void:
	for nation in state.nations:
		var at_war := not state.wars_of(nation.id).is_empty()
		var food_report := _food_security_report(nation.id)
		var food_manpower_budget := _food_growth_manpower_budget(food_report)
		if food_manpower_budget <= 0:
			continue
		var protected_reserve := (
			PEACETIME_MANPOWER_RESERVE
			if not at_war
			else 0
		)
		var available_manpower := maxi(
			nation.manpower_pool - protected_reserve,
			0
		)
		available_manpower = mini(available_manpower, food_manpower_budget)
		if available_manpower <= 0:
			continue
		var plans: Array = []
		var total_deficit := 0
		for army in state.armies:
			if not _can_reinforce_army(army) or army.owner_nation != nation.id:
				continue
			var target_size := army.max_size
			if not at_war:
				target_size = int(ceil(
					float(army.max_size) * PEACETIME_STRENGTH_RATIO
				))
			var deficit := mini(
				maxi(target_size - army.size, 0),
				REINFORCE_PER_ARMY_PER_MONTH
			)
			if deficit <= 0:
				continue
			plans.append({
				"army": army,
				"deficit": deficit,
				"grant": 0,
				"priority": _reinforcement_priority(army),
			})
			total_deficit += deficit
		if plans.is_empty():
			continue
		plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var army_a: Army = a["army"]
			var army_b: Army = b["army"]
			var priority_a := int(a["priority"])
			var priority_b := int(b["priority"])
			if priority_a != priority_b:
				return priority_a > priority_b
			var fill_a := float(army_a.size) / float(maxi(army_a.max_size, 1))
			var fill_b := float(army_b.size) / float(maxi(army_b.max_size, 1))
			if not is_equal_approx(fill_a, fill_b):
				return fill_a < fill_b
			return EquivariantOrder.army_less(
				state,
				nation.id,
				army_a,
				army_b
			)
		)
		var budget := mini(available_manpower, total_deficit)
		if budget >= total_deficit:
			for plan in plans:
				plan["grant"] = plan["deficit"]
		else:
			var remainder := budget
			var index := 0
			while index < plans.size() and remainder > 0:
				var priority := int(plans[index]["priority"])
				var end := index
				var tier_deficit := 0
				while (
					end < plans.size()
					and int(plans[end]["priority"]) == priority
				):
					tier_deficit += int(plans[end]["deficit"])
					end += 1
				var tier_budget := mini(remainder, tier_deficit)
				var tier_granted := 0
				for i in range(index, end):
					var share := int(floor(
						float(tier_budget)
						* float(plans[i]["deficit"])
						/ float(maxi(tier_deficit, 1))
					))
					plans[i]["grant"] = share
					tier_granted += share
				var tier_remainder := tier_budget - tier_granted
				for i in range(index, end):
					if tier_remainder <= 0:
						break
					if int(plans[i]["grant"]) >= int(plans[i]["deficit"]):
						continue
					plans[i]["grant"] = int(plans[i]["grant"]) + 1
					tier_remainder -= 1
				remainder -= tier_budget
				index = end
		var spent := 0
		for plan in plans:
			var grant: int = plan["grant"]
			var army: Army = plan["army"]
			army.size += grant
			spent += grant
		nation.manpower_pool -= spent


func _reinforcement_priority(army: Army) -> int:
	if army.state == Army.State.HOLDING:
		return 3
	var city_id := army.location_city
	if city_id < 0 and army.move_to >= 0:
		city_id = army.move_to
	if city_id < 0 or city_id >= state.cities.size():
		return 0
	var city := state.cities[city_id]
	if (
		city.id == state.nations[army.owner_nation].capital_city_id
		or city.has_warehouse
	):
		return 4
	if city.is_food_hub or city.is_manpower_hub or city.at_war:
		return 3
	return 1


func _can_reinforce_army(army: Army) -> bool:
	if army.size <= 0 or army.size >= army.max_size:
		return false
	if army.state in [Army.State.FIGHTING, Army.State.RETREATING]:
		return false
	if army.state not in [
		Army.State.IDLE,
		Army.State.MOVING,
		Army.State.RECOVERING,
		Army.State.HOLDING,
	]:
		return false
	return Pathfinding.can_reach_manpower_hub(state, army)

# ------------------------------------------------------------------ 2. 粮食 + 饥饿

func _resolve_supply() -> void:
	# 每日重新计算位置、路线、兵力和共享库存竞争。月需求先除以 30 累加到
	# Army.supply_food_debt，只有满整粮时实际扣库存，避免逐日 ceil 放大。
	_daily_supply_source_cache.clear()
	_daily_supply_network_cache.clear()
	var plans: Array = []   # [{army, sources, demand}]
	var demand_by_nation: Array[int] = []
	demand_by_nation.resize(state.nations.size())
	demand_by_nation.fill(0)
	for army in state.armies:
		if army.size <= 0 or army.state == Army.State.RECOVERING:
			continue
		var siege_garrison := _siege_garrison_battle_of(army)
		if siege_garrison != null and siege_garrison.city.food_storage > 0:
			# 被围守军的粮食消耗真源是每日围城时钟。
			army.starving = false
			army.supply_ratio = 1.0
			army.supply_food_debt = 0.0
			continue
		var sources := _cached_supply_sources(
			army,
			_daily_supply_source_cache,
			_daily_supply_network_cache
		)
		var route_loss := _weighted_supply_loss(sources)
		var mult: float = MAX_SUPPLY_MULT
		if not sources.is_empty():
			mult = minf(1.0 + route_loss, MAX_SUPPLY_MULT)
		var base := int(ceil(army.size * FOOD_PER_CAPITA))
		base = maxi(base, 1)
		var monthly_demand := int(ceil(base * mult))
		demand_by_nation[army.owner_nation] += monthly_demand
		army.supply_food_debt += (
			float(monthly_demand) / float(DAYS_PER_MONTH)
		)
		var demand := int(floor(army.supply_food_debt + 0.000001))
		if demand > 0:
			army.supply_food_debt -= float(demand)
		plans.append({ "army": army, "sources": sources, "demand": demand })
	for nation in state.nations:
		nation.last_food_demand = demand_by_nation[nation.id]
		if state.day % DAYS_PER_MONTH == 0:
			nation.food_demand_ema = (
				float(nation.last_food_demand)
				if nation.food_demand_ema <= 0.0
				else lerpf(
					nation.food_demand_ema,
					float(nation.last_food_demand),
					0.5
				)
			)

	# 按物理序执行同日库存竞争，避免 state.armies 创建顺序决定谁先取粮。
	plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var army_a: Army = a["army"]
		var army_b: Army = b["army"]
		return EquivariantOrder.mirror_orbit_army_less(
			state,
			army_a,
			army_b
		)
	)
	for p in plans:
		var a: Army = p["army"]
		var demand: int = p["demand"]
		if demand <= 0:
			var has_food := _supply_sources_have_food(p["sources"])
			a.starving = not has_food
			a.supply_ratio = 1.0 if has_food else 0.0
			continue
		var supplied := _withdraw_weighted_supply(
			p["sources"],
			demand,
			a.owner_nation
		)
		var shortfall := demand - supplied
		if shortfall > 0:
			a.starving = true
			a.supply_ratio = 1.0 - float(shortfall) / float(demand)
		else:
			a.starving = false
			a.supply_ratio = 1.0

## 每日滚动施加刚完成的粮食分配结果：士气/减员按 1/DAYS_PER_MONTH 摊派，
## 线路、部分短缺、兵力变化和共享库存竞争都已在本日 _resolve_supply 中体现。
## 逐军独立、无跨军求和/无 id/无 RNG → 天然镜像等变，不引入公平风险。
func _apply_supply_pressure() -> void:
	var morale_broken: Array[Army] = []
	for army in state.armies:
		if army.size <= 0 or army.state == Army.State.RECOVERING:
			continue
		var siege_garrison := _siege_garrison_battle_of(army)
		if siege_garrison != null and siege_garrison.city.food_storage > 0:
			# 被围守军的粮食时钟是 _drain_siege_food；此处不重复施压（补给孤岛）。
			army.starving = false
			continue
		var shortage := 1.0 - army.supply_ratio
		if _accrue_supply_pressure(army, shortage):
			morale_broken.append(army)
	for army in morale_broken:
		_retreat(army)
	_purge_dead_armies()


## 对单支军队施加当日断粮后果（纯逐军逻辑，无状态依赖/无 id/无 RNG → 天然镜像等变）。
## shortage∈[0,1]：士气按 SUPPLY_MORALE_LOSS_MAX/30 摊派、减员按 debt 整人化累计。
## 返回是否在本日「士气自正值边沿跌至 0」→ 由调用方收集触发溃逃。
func _accrue_supply_pressure(army: Army, shortage: float) -> bool:
	army.starving = shortage > 0.0001
	if shortage <= 0.0001:
		return false
	var old_morale := army.morale
	army.morale = maxf(
		army.morale - SUPPLY_MORALE_LOSS_MAX * shortage / float(DAYS_PER_MONTH),
		Combat.MORALE_FLOOR
	)
	# 减员按日累计到 supply_debt，满整人才扣、余额留存——避免逐日 ceil 造成的取整放大。
	army.supply_debt += shortage * float(army.size) * STARVE_RATE / float(DAYS_PER_MONTH)
	var loss := int(floor(army.supply_debt))
	if loss > 0:
		army.size -= loss
		army.supply_debt -= float(loss)
	# 只在士气从正值跌至 0 的瞬间触发溃逃（与旧口径一致）；FIGHTING 由战斗自身处置。
	return (
		old_morale > Combat.MORALE_FLOOR
		and army.morale <= Combat.MORALE_FLOOR
		and army.state in [Army.State.IDLE, Army.State.MOVING, Army.State.HOLDING]
		and army.size > 0
	)


# ------------------------------------------------------------------ 2b. 士气恢复

## 普通非交战、有粮军队按原规则恢复；战败后 RECOVERING 军队只能驻城，
## 每月消耗所在城市粮食恢复，直至士气回满或该城粮尽。
func _recover_morale() -> void:
	for army in state.armies:
		if army.size <= 0 or army.state in [Army.State.FIGHTING, Army.State.RETREATING]:
			continue
		if army.state == Army.State.RECOVERING:
			_recover_garrisoned_army(army)
			continue
		if army.starving:
			continue
		var recovery_multiplier := morale_recovery_payment_multiplier(
			state.nations[
				army.owner_nation
			].military_payment_ratio
		)
		army.morale = minf(
			army.morale
				+ Combat.MORALE_RECOVER
					* recovery_multiplier,
			1.0
		)


static func morale_recovery_payment_multiplier(
	payment_ratio: float
) -> float:
	return (
		0.5
		+ 0.5 * clampf(payment_ratio, 0.0, 1.0)
	)


func _recover_garrisoned_army(army: Army) -> void:
	var city_id := army.location_city
	if city_id < 0 or city_id >= state.cities.size():
		army.state = Army.State.IDLE
		army.forced_retreat = false
		return
	var city := state.cities[city_id]
	# 驻城期间若城市已失守，重新撤往最近友城，不能在敌城恢复。
	if not state.has_military_access(army.owner_nation, city.owner_nation):
		_start_morale_retreat_from_city(army, city_id, city_id)
		return
	var sources := _cached_supply_sources(
		army,
		_monthly_supply_source_cache,
		_monthly_supply_network_cache
	)
	var route_loss := _weighted_supply_loss(sources)
	var full_month_demand := maxi(int(ceil(float(army.size) * RECOVERY_FOOD_PER_CAPITA)), 1)
	var recovery_multiplier := morale_recovery_payment_multiplier(
		state.nations[
			army.owner_nation
		].military_payment_ratio
	)
	var target_gain := minf(
		Combat.MORALE_RECOVER * recovery_multiplier,
		1.0 - army.morale
	)
	var base_demand := maxi(
		int(ceil(float(full_month_demand) * target_gain / Combat.MORALE_RECOVER)),
		1
	)
	var demand := int(ceil(
		float(base_demand) * minf(1.0 + route_loss, MAX_SUPPLY_MULT)
	)) if not sources.is_empty() else base_demand
	var supplied := _withdraw_weighted_supply(
		sources,
		demand,
		army.owner_nation
	)
	army.starving = supplied < demand
	if supplied > 0:
		army.morale = minf(
			army.morale + target_gain * float(supplied) / float(demand),
			1.0
		)
	if army.morale >= 1.0 - 0.0001:
		army.morale = 1.0
		army.state = Army.State.IDLE
		army.forced_retreat = false
		army.starving = false
	elif not _supply_sources_have_food(sources):
		# 无可达粮仓或粮仓耗尽也是强制驻守的终止条件；保留当前未满士气。
		army.state = Army.State.IDLE
		army.forced_retreat = false


func _supply_sources_have_food(sources: Array[Dictionary]) -> bool:
	for source in sources:
		var city_id := int(source["city_id"])
		if (
			city_id >= 0
			and city_id < state.cities.size()
			and state.cities[city_id].food_storage > 0
		):
			return true
	return false


func _cached_supply_sources(
	army: Army,
	cache: Dictionary,
	network_cache: Dictionary
) -> Array[Dictionary]:
	var position_key := (
		"E:%d:%d:%d"
		% [
			army.move_from,
			army.move_to,
			int(round(army.move_progress * 10000.0)),
		]
		if army.on_edge and army.move_to != -1
		else "C:%d" % army.location_city
	)
	var key := "%d:%s" % [army.owner_nation, position_key]
	if not cache.has(key):
		if not network_cache.has(army.owner_nation):
			network_cache[army.owner_nation] = (
				Pathfinding.build_supply_network(
					state,
					army.owner_nation
				)
			)
		cache[key] = Pathfinding.supply_sources_from_network(
			state,
			army,
			network_cache[army.owner_nation]
		)
	return cache[key]


func _weighted_supply_loss(sources: Array[Dictionary]) -> float:
	if sources.is_empty():
		return INF
	var total_weight := 0.0
	var weighted_loss := 0.0
	for source in sources:
		var city_id := int(source["city_id"])
		if city_id < 0 or city_id >= state.cities.size():
			continue
		var stock := state.cities[city_id].food_storage
		if stock <= 0:
			continue
		var loss := float(source["loss"])
		var weight := _supply_source_weight(stock, loss)
		total_weight += weight
		weighted_loss += loss * weight
	return weighted_loss / maxf(total_weight, 0.001)


func _withdraw_weighted_supply(
	sources: Array[Dictionary],
	demand: int,
	order_nation: int
) -> int:
	var remaining := maxi(demand, 0)
	var supplied := 0
	while remaining > 0:
		var weighted: Array[Dictionary] = []
		var total_weight := 0.0
		for source in sources:
			var city_id := int(source["city_id"])
			if city_id < 0 or city_id >= state.cities.size():
				continue
			var city := state.cities[city_id]
			if city.food_storage <= 0:
				continue
			var weight := _supply_source_weight(
				city.food_storage, float(source["loss"])
			)
			total_weight += weight
			weighted.append({
				"city": city,
				"weight": weight,
				"city_id": city_id,
			})
		if weighted.is_empty() or total_weight <= 0.0:
			break
		var distributed := 0
		var remainders: Array[Dictionary] = []
		for entry in weighted:
			var exact := float(remaining) * float(entry["weight"]) / total_weight
			var share := mini(
				int(floor(exact)),
				(entry["city"] as City).food_storage
			)
			if share > 0:
				(entry["city"] as City).food_storage -= share
				distributed += share
			remainders.append({
				"city": entry["city"],
				"city_id": entry["city_id"],
				"fraction": exact - floor(exact),
			})
		remaining -= distributed
		supplied += distributed
		if remaining <= 0:
			break
		remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(
				float(a["fraction"]), float(b["fraction"])
			):
				return float(a["fraction"]) > float(b["fraction"])
			return EquivariantOrder.city_id_less(
				state,
				order_nation,
				int(a["city_id"]),
				int(b["city_id"])
			)
		)
		var residual_distributed := 0
		for entry in remainders:
			if remaining <= 0:
				break
			var city: City = entry["city"]
			if city.food_storage <= 0:
				continue
			city.food_storage -= 1
			remaining -= 1
			supplied += 1
			residual_distributed += 1
		if distributed == 0 and residual_distributed == 0:
			break
	return supplied


static func _supply_source_weight(stock: int, route_loss: float) -> float:
	return (
		float(maxi(stock, 0))
		/ sqrt(maxf(1.0 + route_loss, 0.001))
	)

# ------------------------------------------------------------------ 2c. 被围城粮草时钟（每日）

## 规格 R3：被围城每日消耗本城存粮（补给孤岛，无法外部补充）。
## 存粮耗尽（food_storage<=0）后，守军城防加成大幅衰减由 Combat 侧按 food_storage 判定，
## 叠加断粮士气加速崩溃 → 城市战斗力大幅下降。
func _drain_siege_food() -> void:
	for battle in state.battles:
		if battle.finished or battle.kind != Battle.Kind.SIEGE or battle.city == null:
			continue
		var city := battle.city
		if city.food_storage > 0:
			city.food_storage = maxi(city.food_storage - SIEGE_CITY_FOOD_PER_DAY, 0)
		if battle.has_garrison:
			var has_food := city.food_storage > 0
			for defender in battle.side_b:
				if defender.size <= 0:
					continue
				defender.starving = not has_food
				defender.supply_ratio = 1.0 if has_food else 0.0


func _siege_garrison_battle_of(army: Army) -> Battle:
	if army.state != Army.State.FIGHTING or army.battle_id == -1:
		return null
	var battle := state.battle_by_id(army.battle_id)
	if battle == null or battle.finished or battle.kind != Battle.Kind.SIEGE:
		return null
	if not battle.has_garrison or not battle.side_b.has(army):
		return null
	return battle


## 每日推进持久边境防区状态，不等待十日一次的正式地图 AI 决策。
func _resolve_line_edge_assignment_emergencies() -> void:
	var army_by_id := {}
	for army in state.armies:
		if army.size > 0:
			army_by_id[army.id] = army
	for nation in state.nations:
		var sectors: Dictionary = nation.frontier_defense_sectors
		for city_id_value in sectors.keys().duplicate():
			var city_id := int(city_id_value)
			var sector: FrontierDefenseSector = sectors[city_id]
			if (
				city_id < 0
				or city_id >= state.cities.size()
				or state.cities[city_id].owner_nation
					!= nation.id
			):
				sector.state = FrontierDefenseSector.State.RETREATING
				_retreat_lost_frontier_sector(
					sector,
					army_by_id
				)
				sectors.erase(city_id)
				continue
			if state.city_under_siege(city_id):
				if sector.state in [
					FrontierDefenseSector.State.NORMAL,
					FrontierDefenseSector.State.RESTORING,
				]:
					sector.state = (
						FrontierDefenseSector.State.RECALLING
					)
				else:
					sector.state = (
						FrontierDefenseSector.State.DEFENDING
					)
				_recall_frontier_sector(sector, army_by_id)
				continue
			if sector.state in [
				FrontierDefenseSector.State.RECALLING,
				FrontierDefenseSector.State.DEFENDING,
			]:
				sector.state = FrontierDefenseSector.State.RESTORING
			if sector.state == FrontierDefenseSector.State.RESTORING:
				_restore_frontier_sector(sector, army_by_id)
		nation.frontier_defense_sectors = sectors


func _recall_frontier_sector(
	sector: FrontierDefenseSector,
	army_by_id: Dictionary
) -> void:
	for slot_index in range(1, sector.slot_count()):
		var army: Army = army_by_id.get(
			sector.assigned_army_at(slot_index)
		)
		if army == null or army.state == Army.State.FIGHTING:
			continue
		if army.is_at_city_node(sector.city_id):
			if army.state != Army.State.IDLE:
				_settle_idle(army, sector.city_id)
			continue
		var recall := ActionCandidate.make(
			ActionCandidate.Kind.RETREAT,
			2000.0,
			"填线防区：城市%d受攻，槽%d军%d立即回城"
				% [sector.city_id, slot_index, army.id],
			sector.city_id
		)
		recall.minimum_commit_days = AI_DECISION_INTERVAL_DAYS
		recall.defensive_deployment = true
		if army.on_edge and sector.city_id in [
			army.move_from,
			army.move_to,
		]:
			recall.target_edge_a = army.move_from
			recall.target_edge_b = army.move_to
			_redirect_edge_army_to_endpoint(
				army,
				sector.city_id,
				recall
			)
		elif army.state == Army.State.IDLE:
			recall.kind = ActionCandidate.Kind.REINFORCE
			_execute_ai_candidate(army, recall)


func _restore_frontier_sector(
	sector: FrontierDefenseSector,
	army_by_id: Dictionary
) -> void:
	var restored := true
	for slot_index in range(1, sector.slot_count()):
		var edge_neighbor := sector.edge_for_slot(slot_index)
		var army: Army = army_by_id.get(
			sector.assigned_army_at(slot_index)
		)
		if army == null:
			continue
		if (
			army.state == Army.State.HOLDING
			and edge_neighbor in [army.move_from, army.move_to]
			and sector.city_id in [army.move_from, army.move_to]
		):
			continue
		restored = false
		if (
			army.state != Army.State.IDLE
			or army.location_city != sector.city_id
		):
			continue
		var edge := state.edge_of(sector.city_id, edge_neighbor)
		if (
			edge == null
			or edge.max_manpower <= 0
			or not edge.allows_holding
			or state.cities[edge_neighbor].owner_nation
				== sector.owner_nation
		):
			continue
		var hold := ActionCandidate.make(
			ActionCandidate.Kind.HOLD,
			2000.0,
			"填线防区：城市%d防守成功，军%d恢复边槽%d"
				% [sector.city_id, army.id, slot_index],
			edge_neighbor
		)
		hold.target_edge_a = sector.city_id
		hold.target_edge_b = edge_neighbor
		hold.minimum_commit_days = AI_DECISION_INTERVAL_DAYS
		hold.defensive_deployment = true
		_execute_ai_candidate(army, hold)
	if restored:
		sector.state = FrontierDefenseSector.State.NORMAL


func _retreat_lost_frontier_sector(
	sector: FrontierDefenseSector,
	army_by_id: Dictionary
) -> void:
	for army_id in sector.assigned_army_ids:
		var army: Army = army_by_id.get(int(army_id))
		if army == null:
			continue
		army.clear_line_assignment()
		if (
			army.on_edge
			and sector.city_id in [army.move_from, army.move_to]
		):
			_retreat(army)
			if army.size > 0:
				var retreat_target := (
					army.path[-1]
					if not army.path.is_empty()
					else army.move_to
				)
				var retreat_order := ActionCandidate.make(
					ActionCandidate.Kind.RETREAT,
					2000.0,
					"填线防区：锚点城市%d失守，军%d协同撤退"
						% [sector.city_id, army.id],
					retreat_target
				)
				retreat_order.minimum_commit_days = (
					AI_DECISION_INTERVAL_DAYS
				)
				_record_ai_order(army, retreat_order)
		elif army.is_at_city_node(sector.city_id):
			_start_morale_retreat_from_city(
				army,
				sector.city_id,
				sector.city_id
			)


func _redirect_edge_army_to_endpoint(
	army: Army,
	target_city: int,
	candidate: ActionCandidate
) -> bool:
	if (
		not army.on_edge
		or army.move_to == -1
		or target_city not in [army.move_from, army.move_to]
	):
		return false
	if target_city == army.move_from:
		var old_from := army.move_from
		army.move_from = army.move_to
		army.move_to = old_from
		army.move_progress = 1.0 - army.move_progress
	army.state = Army.State.MOVING
	army.forced_retreat = false
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.path.clear()
	_record_ai_order(army, candidate)
	return true


func _advance_holding_adaptation() -> void:
	for army in state.armies:
		if army.size <= 0 or army.state != Army.State.HOLDING:
			continue
		var held_edge := state.edge_of(
			army.move_from,
			army.move_to
		)
		if held_edge == null or not held_edge.allows_holding:
			_leave_holding(army)
			continue
		if army.supply_ratio >= 1.0 - 0.0001:
			army.holding_days += 1
		elif army.supply_ratio <= 0.0001:
			army.holding_days = maxi(army.holding_days - HOLDING_STARVE_DECAY, 0)
		# 部分补给：既不增长也不衰减。

# ------------------------------------------------------------------ 2.5 外交

func _resolve_diplomacy() -> void:
	if not diplomacy_enabled or state.day % DIPLOMACY_DECISION_INTERVAL_DAYS != 0:
		return
	_refresh_war_preparation_viability()
	for action in DiplomacyAI.choose_actions(state):
		_execute_diplomatic_action(action)


## 失去全部城市的国家立即向所有交战国投降。该规则属于战争结算，
## 不经过和平意愿评分、不等待月度外交 tick，也不保留多国战争残余关系。
func _resolve_eliminated_nation_capitulations() -> void:
	for surrendering in range(state.nations.size()):
		if not state.cities_of(surrendering).is_empty():
			continue
		var opponents := _war_opponents_including_eliminated(
			surrendering
		)
		for victor in opponents:
			if not state.is_enemy(surrendering, victor):
				continue
			_execute_diplomatic_action({
				"kind": DiplomacyAI.Action.MAKE_PEACE,
				"a": victor,
				"b": surrendering,
				"surrendering_nation": surrendering,
				"reason": (
					"国%d全境失守，向交战国%d投降"
					% [surrendering, victor]
				),
			})


func _war_opponents_including_eliminated(nation_id: int) -> Array[int]:
	var opponents: Array[int] = []
	for other_id in range(state.nations.size()):
		if other_id != nation_id and state.is_enemy(nation_id, other_id):
			opponents.append(other_id)
	return opponents


func _refresh_war_preparation_viability() -> void:
	for nation in state.nations:
		if nation.war_preparation_target_nation < 0:
			nation.war_preparation_unready_since_day = -1
			continue
		var ready := DiplomacyAI.war_preparation_resources_ready(
			state,
			nation.id
		)
		if ready:
			nation.war_preparation_unready_since_day = -1
		elif nation.war_preparation_unready_since_day < 0:
			nation.war_preparation_unready_since_day = state.day


func _execute_diplomatic_action(action: Dictionary) -> bool:
	var kind := int(action.get("kind", DiplomacyAI.Action.NONE))
	var nation_a := int(action.get("a", -1))
	var nation_b := int(action.get("b", -1))
	var reason := str(action.get("reason", ""))
	if (
		nation_a < 0
		or nation_b < 0
		or nation_a >= state.nations.size()
		or nation_b >= state.nations.size()
	):
		return false
	var changed := false
	var war_outcome_a := 0.0
	var war_outcome_b := 0.0
	var territories_transferred := 0
	match kind:
		DiplomacyAI.Action.MAKE_PEACE:
			if state.is_enemy(nation_a, nation_b):
				war_outcome_a = DiplomacyAI.war_situation_score(
					state,
					nation_a,
					nation_b
				)
				war_outcome_b = DiplomacyAI.war_situation_score(
					state,
					nation_b,
					nation_a
				)
				changed = state.set_diplomatic_relation(
					nation_a,
					nation_b,
					GameState.DiplomaticRelation.NEUTRAL,
					GameState.DEFAULT_TRUCE_DAYS
				)
				if changed:
					_end_bilateral_hostilities(nation_a, nation_b)
					var transferred := state.recognize_occupied_territory(
						nation_a, nation_b
					)
					territories_transferred = transferred.size()
					if not transferred.is_empty():
						reason += "；和平协议确认%d座城市的领土转移" % transferred.size()
					state.clear_war_objective(nation_a, nation_b)
					_clear_finished_war_mobilization(nation_a)
					_clear_finished_war_mobilization(nation_b)
		DiplomacyAI.Action.DECLARE_WAR:
			if state.can_declare_war(nation_a, nation_b):
				var defenders: Array[int] = [nation_b]
				for ally_id in state.allies_of(nation_b):
					if not defenders.has(ally_id):
						defenders.append(ally_id)
				for defender_id in defenders:
					if (
						defender_id == nation_a
						or state.is_enemy(nation_a, defender_id)
						or state.is_allied(nation_a, defender_id)
					):
						continue
					state.set_diplomatic_relation(
						nation_a,
						defender_id,
						GameState.DiplomaticRelation.WAR
					)
				changed = state.is_enemy(nation_a, nation_b)
				var objective_city := int(action.get("objective_city", -1))
				if changed and objective_city >= 0:
					state.set_war_objective(
						nation_a,
						nation_b,
						objective_city,
						str(action.get("objective_reason", ""))
					)
				if changed:
					var preparation_days := 0
					var preparation_started := (
						state.nations[nation_a]
							.war_preparation_started_day
					)
					if preparation_started >= 0:
						preparation_days = maxi(
							state.day - preparation_started,
							0
						)
					_start_war_mobilization(
						nation_a,
						int(action.get("mobilization_armies", -1))
					)
					for defender_id in defenders:
						if state.is_enemy(nation_a, defender_id):
							_clear_war_preparation(defender_id)
							_start_war_mobilization(defender_id)
					_clear_war_preparation(nation_a, false)
					_launch_campaign_offensive(
						nation_a,
						objective_city,
						preparation_days
					)
		DiplomacyAI.Action.FORM_ALLIANCE:
			if (
				state.relation_between(nation_a, nation_b)
				== GameState.DiplomaticRelation.NEUTRAL
			):
				changed = state.set_diplomatic_relation(
					nation_a,
					nation_b,
					GameState.DiplomaticRelation.ALLIED
				)
		DiplomacyAI.Action.LEAVE_ALLIANCE:
			if state.is_allied(nation_a, nation_b) and nation_a != nation_b:
				changed = state.set_diplomatic_relation(
					nation_a,
					nation_b,
					GameState.DiplomaticRelation.NEUTRAL
				)
				if changed:
					_repatriate_after_access_revoked(nation_a, nation_b)
		DiplomacyAI.Action.PREPARE_WAR:
			if state.can_declare_war(nation_a, nation_b):
				changed = _start_war_preparation(nation_a, nation_b, action)
		DiplomacyAI.Action.CANCEL_WAR_PREPARATION:
			if state.nations[nation_a].war_preparation_target_nation >= 0:
				_clear_war_preparation(nation_a)
				changed = true
	if not changed:
		return false
	var event := {
		"day": state.day,
		"action": kind,
		"nation_a": nation_a,
		"nation_b": nation_b,
		"reason": reason,
	}
	if action.has("objective_city"):
		event["objective_city"] = int(action["objective_city"])
		event["objective_reason"] = str(action.get("objective_reason", ""))
	if action.has("mobilization_armies"):
		event["mobilization_armies"] = int(action["mobilization_armies"])
	if action.has("surrendering_nation"):
		event["surrendering_nation"] = int(action["surrendering_nation"])
	if kind == DiplomacyAI.Action.MAKE_PEACE:
		event["war_outcome_a"] = war_outcome_a
		event["war_outcome_b"] = war_outcome_b
		event["territories_transferred"] = territories_transferred
	state.diplomatic_history.append(event)
	_record_diplomatic_action(nation_a, kind, nation_b, reason)
	_record_diplomatic_action(nation_b, kind, nation_a, reason)
	_ai_strategy_cache.clear()
	_ai_strategy_revision.clear()
	return true


func _start_war_preparation(
	nation_id: int,
	target_id: int,
	action: Dictionary
) -> bool:
	var objective_city := int(action.get("objective_city", -1))
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or state.cities[objective_city].owner_nation != target_id
	):
		return false
	var nation := state.nations[nation_id]
	nation.war_preparation_target_nation = target_id
	nation.war_preparation_objective_city = objective_city
	nation.war_preparation_started_day = state.day
	nation.war_preparation_reason = str(action.get("objective_reason", ""))
	nation.war_preparation_unready_since_day = -1
	_clear_campaign_attack_plan(nation_id)
	var requested_armies := int(action.get("mobilization_armies", 0))
	var current_troops := DiplomacyAI._troop_count(state, nation_id)
	nation.war_mobilization_target_troops = maxi(
		nation.war_mobilization_target_troops,
		current_troops + requested_armies * NEW_ARMY_SIZE
	)
	nation.war_mobilization_until_day = maxi(
		nation.war_mobilization_until_day,
		state.day + DiplomacyAI.WAR_PREPARATION_MAX_DAYS
	)
	nation.war_mobilization_reason = (
		"战前动员%d军，向城市%d方向集结"
		% [requested_armies, objective_city]
	)
	return true


func _clear_war_preparation(
	nation_id: int,
	clear_mobilization: bool = true
) -> void:
	var nation := state.nations[nation_id]
	nation.war_preparation_target_nation = -1
	nation.war_preparation_objective_city = -1
	nation.war_preparation_started_day = -1
	nation.war_preparation_reason = ""
	nation.war_preparation_unready_since_day = -1
	if clear_mobilization:
		_clear_campaign_attack_plan(nation_id)
	if clear_mobilization and state.wars_of(nation_id).is_empty():
		nation.war_mobilization_target_troops = 0
		nation.war_mobilization_until_day = -1
		nation.war_mobilization_reason = ""


func _start_war_mobilization(nation_id: int, requested_armies: int = -1) -> void:
	var nation := state.nations[nation_id]
	var posture := DiplomacyAI.food_posture(state, nation_id)
	var capacity := DiplomacyAI.mobilization_capacity(
		state,
		nation_id,
		posture
	)
	if requested_armies >= 0:
		capacity = mini(capacity, requested_armies)
	var current_troops := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			current_troops += army.size
	var target := current_troops + capacity * NEW_ARMY_SIZE
	var food_plan := DiplomacyAI.war_food_report(
		state,
		nation_id,
		target,
		posture
	)
	nation.war_mobilization_target_troops = maxi(
		nation.war_mobilization_target_troops,
		target
	)
	nation.war_mobilization_until_day = maxi(
		nation.war_mobilization_until_day,
		state.day + WAR_MOBILIZATION_DAYS
	)
	nation.war_mobilization_reason = (
		"粮食储备支持额外动员%d军，目标总兵力%d；年结余%.0f，可支撑%.1f年"
		% [
			capacity,
			nation.war_mobilization_target_troops,
			food_plan["target_annual_balance"],
			food_plan["target_runway_years"],
		]
	)


func _clear_finished_war_mobilization(nation_id: int) -> void:
	if not state.wars_of(nation_id).is_empty():
		return
	var nation := state.nations[nation_id]
	nation.war_mobilization_target_troops = 0
	nation.war_mobilization_until_day = -1
	nation.war_mobilization_reason = ""
	nation.campaign_last_offensive_day = -1
	nation.campaign_next_offensive_day = -1
	nation.campaign_offensive_count = 0
	nation.campaign_theater_anchor_city = -1
	nation.campaign_theater_started_day = -1
	_clear_campaign_preparation_plan(nation_id)
	nation.campaign_post_capture_plans.clear()
	_clear_campaign_attack_plan(nation_id)


func _record_diplomatic_action(
	nation_id: int,
	action: int,
	target_id: int,
	reason: String
) -> void:
	var nation := state.nations[nation_id]
	nation.ai_last_diplomatic_action = action
	nation.ai_last_diplomatic_target = target_id
	nation.ai_last_diplomatic_day = state.day
	nation.ai_last_diplomatic_reason = reason


func _end_bilateral_hostilities(nation_a: int, nation_b: int) -> void:
	for battle in state.battles:
		if battle.finished:
			continue
		var side_a_nation := (
			battle.side_a[0].owner_nation if not battle.side_a.is_empty() else -1
		)
		var side_b_nation := (
			battle.side_b[0].owner_nation if not battle.side_b.is_empty() else -1
		)
		var city_owner := battle.city.owner_nation if battle.city != null else -1
		var bilateral := (
			(side_a_nation == nation_a and side_b_nation == nation_b)
			or (side_a_nation == nation_b and side_b_nation == nation_a)
			or (
				battle.kind == Battle.Kind.SIEGE
				and (
					(side_a_nation == nation_a and city_owner == nation_b)
					or (side_a_nation == nation_b and city_owner == nation_a)
				)
			)
		)
		if not bilateral:
			continue
		for army in battle.side_a + battle.side_b:
			if army.size <= 0:
				army.battle_id = -1
				continue
			if (
				army.location_city >= 0
				and army.location_city < state.cities.size()
				and state.cities[army.location_city].owner_nation == army.owner_nation
			):
				_settle_idle(army, army.location_city)
			elif battle.city != null and battle.city.owner_nation == army.owner_nation:
				_settle_idle(army, battle.city.id)
			elif army.on_edge and army.move_to != -1:
				army.state = Army.State.MOVING
				army.battle_id = -1
				army.path.clear()
			else:
				_retreat_to_friendly(army)
		battle.finished = true
		battle.winner_side = 0
	state.battles = state.battles.filter(func(b: Battle) -> bool: return not b.finished)
	for army in state.armies:
		if army.size <= 0 or army.owner_nation not in [nation_a, nation_b]:
			continue
		if army.ai_target_city >= 0:
			var target_owner := state.cities[army.ai_target_city].owner_nation
			if (
				(army.owner_nation == nation_a and target_owner == nation_b)
				or (army.owner_nation == nation_b and target_owner == nation_a)
			):
				army.path.clear()
				army.ai_target_city = -1
				army.ai_order_until_day = state.day


func _repatriate_after_access_revoked(
	nation_a: int,
	nation_b: int
) -> void:
	for army in state.armies:
		if army.size <= 0 or army.owner_nation not in [nation_a, nation_b]:
			continue
		var former_ally := nation_b if army.owner_nation == nation_a else nation_a
		var in_former_ally_territory := (
			army.location_city >= 0
			and army.location_city < state.cities.size()
			and state.cities[army.location_city].owner_nation == former_ally
		)
		var route_uses_former_ally := false
		for city_id in army.path:
			if state.cities[city_id].owner_nation == former_ally:
				route_uses_former_ally = true
				break
		if not in_former_ally_territory and not route_uses_former_ally:
			continue
		army.path.clear()
		army.ai_target_city = -1
		army.ai_order_until_day = state.day
		if army.on_edge and army.move_to != -1:
			_retreat(army)
		else:
			_retreat_to_friendly(army)
# ------------------------------------------------------------------ 3. AI 决策


func _ai_assign_targets() -> void:
	_ai_supply_source_cache.clear()
	_ai_supply_network_cache.clear()
	_ai_last_decision_day = state.day
	var nation_order := _ai_nation_ids_for_day(
		state.nations.size(),
		state.day,
		rotate_ai_nation_order,
		(
			AI_DECISION_INTERVAL_DAYS
			if state.uses_heightmap
			else GRID_AI_DECISION_INTERVAL_DAYS
		)
	)
	var managed_nations: Array[int] = []
	var force_contexts := {}
	for nation_id in nation_order:
		var nation := state.nations[nation_id]
		if not nation.alive:
			continue
		_reconcile_strategic_roles(nation_id)
		if ai_policy_overrides.has(nation.id):
			var policy: Callable = ai_policy_overrides[nation.id]
			policy.call(state, nation.id, self)
			continue
		managed_nations.append(nation_id)
		var view := _build_ai_view(nation_id)
		var snapshot := _strategy_snapshot_for(view)
		var threat := ThreatField.build(
			view,
			_threat_travel_cache
		)
		force_contexts[nation_id] = {
			"view": view,
			"snapshot": snapshot,
			"threat": threat,
			"defense_plan": CityDefensePlan.build(
				view,
				snapshot,
				threat
			),
		}
	# 军制调整只消耗本国资源；所有国家先基于同一时刻的冻结上下文决策。
	for nation_id in managed_nations:
		var context: Dictionary = force_contexts[nation_id]
		_ai_manage_force_structure(
			context["view"],
			context["snapshot"],
			context["threat"],
			context["defense_plan"]
		)
	# 军事规划复用 tick 开始时的冻结上下文；军制变化从下一次决策起生效。
	var military_contexts := force_contexts
	var snapshot_army_ids := {}
	for nation_id in managed_nations:
		var context: Dictionary = military_contexts[nation_id]
		var snapshot_view: AiWorldView = context["view"]
		for army in snapshot_view.friendly_armies:
			snapshot_army_ids[army.id] = true
	_begin_ai_command_collection(snapshot_army_ids)
	var coordinators := {}
	var defense_plans := {}
	for nation_id in managed_nations:
		var context: Dictionary = military_contexts[nation_id]
		var view: AiWorldView = context["view"]
		var coordinator := ArmyCoordinator.new()
		for army in view.friendly_armies:
			if (
				army.ai_target_city != -1
				and army.state in [
					Army.State.MOVING,
					Army.State.FIGHTING,
				]
			):
				coordinator.reserve(army.ai_target_city, army)
			elif army.state == Army.State.HOLDING:
				var friendly_endpoint := army.move_from
				if not state.has_military_access(
					nation_id,
					state.cities[friendly_endpoint].owner_nation
				):
					friendly_endpoint = army.move_to
				var other_endpoint := (
					army.move_to
					if friendly_endpoint == army.move_from
					else army.move_from
				)
				coordinator.reserve_edge(
					friendly_endpoint,
					other_endpoint,
					army
				)
		coordinators[nation_id] = coordinator
		defense_plans[nation_id] = context["defense_plan"]
	for nation_id in managed_nations:
		var nation := state.nations[nation_id]
		var defense_plan: CityDefensePlan = defense_plans[nation_id]
		var coordinator: ArmyCoordinator = coordinators[nation_id]
		if nation.war_preparation_target_nation >= 0:
			_assign_offensive_staging_orders(
				nation_id,
				nation.war_preparation_objective_city,
				defense_plan,
				coordinator,
				true,
				false
			)
		elif not state.wars_of(nation_id).is_empty():
			_manage_campaign_offensive(
				nation_id,
				defense_plan,
					coordinator,
					(
						military_contexts[nation_id]["threat"]
						as ThreatField
					)
			)
	for nation_id in managed_nations:
		var context: Dictionary = military_contexts[nation_id]
		var nation := state.nations[nation_id]
		var view: AiWorldView = context["view"]
		var snapshot: StrategicMapSnapshot = context["snapshot"]
		var threat: ThreatField = context["threat"]
		var coordinator: ArmyCoordinator = coordinators[nation_id]
		var defense_plan: CityDefensePlan = defense_plans[nation_id]
		var minimum_participant_ratio := float(
			ai_assault_participant_ratio_overrides.get(
				nation_id,
				UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO
			)
		)
		var strongest_first := bool(
			ai_tactical_decision_order_overrides.get(nation_id, true)
		)
		var decision_order := _sort_ai_decision_order(
			state,
			view.friendly_armies,
			snapshot,
			strongest_first
		)
		for army in decision_order:
			var campaign_target := int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			)
			var campaign_locked := (
				campaign_target >= 0
				and (
					nation.war_preparation_target_nation >= 0
					or (
						campaign_target < state.cities.size()
						and state.is_enemy(
							nation_id,
							state.cities[
								campaign_target
							].owner_nation
						)
					)
				)
			)
			if campaign_locked:
				var defense_anchor := army.location_city
				if (
					army.state == Army.State.HOLDING
					and army.move_to != -1
				):
					defense_anchor = _campaign_army_origin(
						army,
						nation_id
					)
				if defense_plan.urgent_defense_at(
					defense_anchor
				):
					campaign_locked = false
			if (
				campaign_locked
				and army.size > 0
				and not _ai_planned_armies.has(army.id)
			):
				if (
					campaign_target >= 0
					and state.is_enemy(
						nation_id,
						state.cities[
							campaign_target
						].owner_nation
					)
					and nation.campaign_launched_armies.has(
						army.id
					)
					and _army_ready_for_campaign_target(
						army,
						nation_id,
						campaign_target
					)
				):
					var continue_campaign := (
						ActionCandidate.make(
							ActionCandidate.Kind.ATTACK,
							2000.0,
							(
								"继续执行国家战役计划："
								+ "军%d攻击城市%d"
							) % [
								army.id,
								campaign_target,
							],
							campaign_target
						)
					)
					continue_campaign.minimum_commit_days = (
						CAMPAIGN_OFFENSIVE_COMMIT_DAYS
					)
					if _execute_ai_candidate(
						army,
						continue_campaign
					):
						coordinator.reserve(
							campaign_target,
							army
						)
			if (
				army.size <= 0
				or _ai_planned_armies.has(army.id)
				or campaign_locked
			):
				continue
			if army.is_line_role():
				var line_candidate := (
					defense_plan.candidate_for(
						army,
						coordinator
					)
				)
				if (
					line_candidate != null
					and line_candidate.kind
						!= ActionCandidate.Kind.NONE
					and _execute_ai_candidate(
						army,
						line_candidate
					)
				):
					if (
						line_candidate.kind
							== ActionCandidate.Kind.HOLD
					):
						coordinator.reserve_edge(
							line_candidate.target_edge_a,
							line_candidate.target_edge_b,
							army
						)
					elif line_candidate.target_city != -1:
						coordinator.reserve(
							line_candidate.target_city,
							army
						)
				continue
			var candidate := UtilityAI.choose(
				view,
				snapshot,
				threat,
				coordinator,
				army,
				minimum_participant_ratio,
				defense_plan
			)
			if candidate.kind == ActionCandidate.Kind.NONE:
				continue
			if _execute_ai_candidate(army, candidate):
				if candidate.kind == ActionCandidate.Kind.HOLD:
					coordinator.reserve_edge(
						candidate.target_edge_a,
						candidate.target_edge_b,
						army
					)
				elif candidate.target_city != -1:
					coordinator.reserve(candidate.target_city, army)
	_commit_ai_command_collection(nation_order)


func _reconcile_strategic_roles(nation_id: int) -> void:
	if nation_id < 0 or nation_id >= state.nations.size():
		return
	var nation := state.nations[nation_id]
	var valid_groups := {}
	for group in nation.battle_groups:
		valid_groups[group.id] = true
	var armies: Array[Army] = []
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			armies.append(army)
	armies.sort_custom(func(a: Army, b: Army) -> bool:
		if a.max_size != b.max_size:
			return a.max_size > b.max_size
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b
		)
	)
	var light_by_group := {}
	var heavy_by_group := {}
	for army in armies:
		if (
			army.battle_group_id < 0
			or not valid_groups.has(army.battle_group_id)
		):
			army.battle_group_id = -1
			continue
		var group_id := army.battle_group_id
		if army.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE:
			var light_count := int(light_by_group.get(group_id, 0))
			if light_count >= BattleGroup.MAX_LIGHT_ARMIES:
				army.battle_group_id = -1
				continue
			light_by_group[group_id] = light_count + 1
		elif army.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
			var heavy_count := int(heavy_by_group.get(group_id, 0))
			if heavy_count >= BattleGroup.MAX_HEAVY_ARMIES:
				army.battle_group_id = -1
				continue
			heavy_by_group[group_id] = heavy_count + 1
	for army in armies:
		if (
			army.max_size < GameState.INITIAL_HEAVY_ARMY_SIZE
			or army.battle_group_id >= 0
		):
			continue
		var destination := -1
		for group in nation.battle_groups:
			if int(heavy_by_group.get(group.id, 0)) == 0:
				destination = group.id
				break
		if destination < 0:
			var group := state.create_battle_group(nation_id)
			destination = group.id
			valid_groups[destination] = true
		if state.assign_army_to_battle_group(army, destination):
			heavy_by_group[destination] = 1
	for army in armies:
		if army.battle_group_id >= 0:
			army.strategic_role = Army.StrategicRole.MAIN
			army.clear_line_assignment()
		else:
			army.strategic_role = Army.StrategicRole.LINE
	var army_by_id := {}
	for army in armies:
		army_by_id[army.id] = army
	for army_id in (
		nation.campaign_preparation_assignments.keys().duplicate()
	):
		var target_city := int(
			nation.campaign_preparation_assignments[army_id]
		)
		var expected_group := int(
			nation.campaign_preparation_group_assignments.get(
				target_city,
				-1
			)
		)
		var assigned_army: Army = army_by_id.get(army_id)
		if (
			assigned_army != null
			and assigned_army.battle_group_id == expected_group
			and expected_group >= 0
		):
			continue
		nation.campaign_preparation_assignments.erase(army_id)


func _build_ai_view(nation_id: int) -> AiWorldView:
	var view := AiWorldView.build(
		state,
		nation_id,
		_ai_path_field_cache,
		_ai_supply_network_cache
	)
	view.strategic_planning_enabled = bool(
		ai_strategic_planning_overrides.get(nation_id, true)
	)
	view.adaptive_garrison_enabled = bool(
		ai_adaptive_garrison_overrides.get(nation_id, true)
	)
	view.supply_corridor_defense_enabled = bool(
		ai_supply_corridor_defense_overrides.get(nation_id, true)
	)
	view.executable_attack_paths_enabled = bool(
		ai_executable_attack_paths_overrides.get(nation_id, true)
	)
	view.legacy_id_personality_enabled = bool(
		ai_legacy_id_personality_overrides.get(nation_id, false)
	)
	return view


func _strategy_snapshot_for(view: AiWorldView) -> StrategicMapSnapshot:
	var revision := [
		state.ownership_revision,
		state.diplomacy_revision,
		state.fortification_revision,
	]
	if (
		not _ai_strategy_cache.has(view.nation_id)
		or _ai_strategy_revision.get(view.nation_id, []) != revision
	):
		_ai_strategy_cache[view.nation_id] = StrategicMapSnapshot.build(view)
		_ai_strategy_revision[view.nation_id] = revision
	return _ai_strategy_cache[view.nation_id]


static func _ai_nation_ids_for_day(
	nation_count: int,
	day: int,
	rotate_order: bool = true,
	decision_interval_days: int = AI_DECISION_INTERVAL_DAYS
) -> Array[int]:
	var result: Array[int] = []
	if nation_count <= 0:
		return result
	var decision_round := day / maxi(decision_interval_days, 1)
	var start := posmod(decision_round, nation_count) if rotate_order else 0
	for offset in range(nation_count):
		result.append((start + offset) % nation_count)
	return result


static func _sort_ai_decision_order(
	game_state: GameState,
	armies: Array[Army],
	snapshot: StrategicMapSnapshot,
	strongest_first: bool
) -> Array[Army]:
	var result: Array[Army] = armies.duplicate()
	result.sort_custom(func(a: Army, b: Army) -> bool:
		var a_front := (
			snapshot.frontier_cities.has(a.location_city)
			or snapshot.potential_frontier_cities.has(a.location_city)
		)
		var b_front := (
			snapshot.frontier_cities.has(b.location_city)
			or snapshot.potential_frontier_cities.has(b.location_city)
		)
		if a_front != b_front:
			return a_front and not b_front
		if (
			strongest_first
			and not is_equal_approx(
				ArmyPower.effective(a), ArmyPower.effective(b)
			)
		):
			return ArmyPower.effective(a) > ArmyPower.effective(b)
		return EquivariantOrder.army_less(
			game_state,
			snapshot.nation_id,
			a,
			b
		)
	)
	return result


func _ai_manage_force_structure(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	defense_plan: CityDefensePlan = null
) -> bool:
	if not state.uses_heightmap:
		return _split_army_for_narrow_objective(
			view,
			state.nations[view.nation_id]
		)
	_reconcile_strategic_roles(view.nation_id)
	if defense_plan == null:
		defense_plan = CityDefensePlan.build(
			view,
			snapshot,
			threat
		)
	var nation := state.nations[view.nation_id]
	var line_armies := 0
	var current_troops := 0
	for army in view.friendly_armies:
		current_troops += army.size
		if army.is_line_role():
			line_armies += 1
	var wars := state.wars_of(view.nation_id)
	var small_nation_survival := (
		not wars.is_empty()
		and view.friendly_cities.size()
			<= SMALL_NATION_SURVIVAL_MAX_CITIES
	)
	var active_war_mobilization := (
		not wars.is_empty()
		and state.day <= nation.war_mobilization_until_day
		and nation.war_mobilization_target_troops
			> current_troops
	)
	var city_line_target := defense_plan.line_city_slots
	var total_line_target := (
		city_line_target + defense_plan.line_edge_slots
	)
	if small_nation_survival:
		city_line_target = maxi(
			city_line_target,
			view.friendly_cities.size()
		)
		total_line_target = maxi(
			total_line_target,
			city_line_target
		)
	var emergency_recruitment := (
		small_nation_survival
		or active_war_mobilization
	)
	var food_report := _food_security_report(
		view.nation_id,
		view.friendly_armies
	)
	var food_pressure := bool(food_report["needs_demobilization"])
	var food_growth_budget := _food_growth_manpower_budget(
		food_report
	)
	if food_pressure and not emergency_recruitment:
		if _demobilize_for_food_security(
			view,
			threat,
			food_report,
			total_line_target
				+ nation.battle_groups.size() * 3
		):
			return true
	var protected_reserve := (
		PEACETIME_MANPOWER_RESERVE
		if state.wars_of(view.nation_id).is_empty()
		else 0
	)
	var available_manpower := (
		state.nations[view.nation_id].manpower_pool - protected_reserve
	)
	var recruitment := {}
	if line_armies < city_line_target:
		recruitment = {
			"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
			"group_id": -1,
			"reason": "补充城市填线槽",
		}
	else:
		var first_group_has_members := false
		for group in nation.battle_groups:
			if not state.battle_group_members(
				view.nation_id,
				group.id
			).is_empty():
				first_group_has_members = true
				break
		if not first_group_has_members:
			recruitment = _next_battle_group_recruitment(
				view.nation_id
			)
		elif line_armies < total_line_target:
			recruitment = {
				"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
				"group_id": -1,
				"reason": "补充边境填线槽",
			}
		else:
			recruitment = _next_battle_group_recruitment(
				view.nation_id,
				(
					nation.battle_groups.size()
						< CAMPAIGN_MAX_TARGETS
					and (
						nation.war_preparation_target_nation >= 0
						or
						not wars.is_empty()
					)
				)
			)
	var missing_formation_size := int(
		recruitment.get("size", 0)
	)
	var food_recruitment_allowed := (
		not food_pressure
		and food_growth_budget >= missing_formation_size
	)
	if emergency_recruitment:
		food_recruitment_allowed = (
			int(food_report["stock"]) > 0
			and (
				float(food_report["monthly_surplus"]) >= 0.0
				or float(food_report["runway_years"])
					>= EMERGENCY_RECRUITMENT_MIN_RUNWAY_YEARS
			)
		)
	if (
		missing_formation_size > 0
		and available_manpower >= missing_formation_size
		and food_recruitment_allowed
	):
		var creation_site := -1
		var capital_id := nation.capital_city_id
		if _is_available_recruitment_hub(
			view.nation_id,
			capital_id,
			small_nation_survival
		):
			creation_site = capital_id
		else:
			for warehouse in state.warehouse_cities_of(
				view.nation_id
			):
				if _is_available_recruitment_hub(
					view.nation_id,
					warehouse.id,
					small_nation_survival
				):
					creation_site = warehouse.id
					break
		if creation_site != -1:
			var recruitment_reason := str(
				recruitment.get(
					"reason",
					"资源结余扩军"
				)
			)
			if emergency_recruitment:
				recruitment_reason = (
					"战争生存动员%d编制"
					% missing_formation_size
				)
			return _create_army_for_nation(
				view.nation_id,
				creation_site,
				missing_formation_size,
				recruitment_reason,
				small_nation_survival,
				int(recruitment.get("group_id", -1))
			) != null
	return false


func _next_battle_group_recruitment(
	nation_id: int,
	allow_new_group: bool = true
) -> Dictionary:
	var nation := state.nations[nation_id]
	for group in nation.battle_groups:
		var light_count := 0
		var heavy_count := 0
		for member in state.battle_group_members(
			nation_id,
			group.id
		):
			if member.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE:
				light_count += 1
			elif member.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
				heavy_count += 1
		if light_count < BattleGroup.MAX_LIGHT_ARMIES:
			return {
				"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
				"group_id": group.id,
				"reason": "战团%d补充第%d支轻军" % [
					group.id,
					light_count + 1,
				],
			}
		if heavy_count < BattleGroup.MAX_HEAVY_ARMIES:
			return {
				"size": GameState.INITIAL_HEAVY_ARMY_SIZE,
				"group_id": group.id,
				"reason": "战团%d补充重军" % group.id,
			}
	if not allow_new_group:
		return {}
	var group := state.create_battle_group(nation_id)
	return {
		"size": GameState.INITIAL_LIGHT_ARMY_SIZE,
		"group_id": group.id,
		"reason": "创建战团%d并补充第一支轻军" % group.id,
	}


func _split_army_for_narrow_objective(
	view: AiWorldView,
	nation: Nation
) -> bool:
	var objective_city := (
		nation.war_preparation_objective_city
	)
	if objective_city < 0:
		objective_city = nation.campaign_plan_primary_city
	if objective_city < 0:
		for enemy_id in state.wars_of(nation.id):
			var objective := state.war_objective(
				nation.id,
				enemy_id
			)
			if (
				not objective.is_empty()
				and int(objective.get("attacker", -1))
					== nation.id
			):
				objective_city = int(
					objective.get("city_id", -1)
				)
				break
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or not state.is_enemy(
			nation.id,
			state.cities[objective_city].owner_nation
		)
	):
		return false
	var candidates: Array[Army] = []
	for army in view.friendly_armies:
		if (
			army.state == Army.State.IDLE
			and army.size > 0
			and not army.starving
			and army.morale >= 0.5
			and army.supply_ratio >= 0.75
			and army.max_size
				> NARROW_ROUTE_FORMATION_SIZE
		):
			candidates.append(army)
	candidates.sort_custom(func(a: Army, b: Army) -> bool:
			if a.max_size != b.max_size:
				return a.max_size > b.max_size
			return EquivariantOrder.army_less(
				state,
				view.nation_id,
				a,
				b,
				objective_city
			)
	)
	for army in candidates:
		var wide_field := Pathfinding.dijkstra_field(
			state,
			army.location_city,
			nation.id,
			false,
			true,
			objective_city,
			army.max_size
		)
		if (
			float(
				wide_field["dist"].get(
					objective_city,
					INF
				)
			) < INF
		):
			continue
		var narrow_field := Pathfinding.dijkstra_field(
			state,
			army.location_city,
			nation.id,
			false,
			true,
			objective_city,
			NARROW_ROUTE_FORMATION_SIZE
		)
		if (
			float(
				narrow_field["dist"].get(
					objective_city,
					INF
				)
			) == INF
		):
			continue
		var route := Pathfinding.reconstruct(
			narrow_field["prev"],
			army.location_city,
			objective_city
		)
		if route.is_empty():
			continue
		var bottleneck := army.max_size
		var from_city := army.location_city
		for to_city in route:
			var edge := state.edge_of(
				from_city,
				to_city
			)
			if edge == null:
				bottleneck = 0
				break
			bottleneck = mini(
				bottleneck,
				edge.max_manpower
			)
			from_city = to_city
		if (
			bottleneck < Edge.MIN_MANPOWER
			or bottleneck >= army.max_size
			or army.max_size % bottleneck != 0
		):
			continue
		var assigned_target := int(
			nation.campaign_attack_assignments.get(
				army.id,
				-1
			)
		)
		var parts := state.split_army(
			army,
			bottleneck
		)
		if parts.is_empty():
			continue
		for part in parts:
			part.ai_action = (
				ActionCandidate.Kind.SPLIT_ARMY
			)
			part.ai_order_created_day = state.day
			part.ai_order_reason = (
				"为通过%d人容量道路，将军%d拆为%d支%d人编制"
				% [
					bottleneck,
					army.id,
					parts.size(),
					bottleneck,
				]
			)
			if assigned_target >= 0:
				nation.campaign_attack_assignments[
					part.id
				] = assigned_target
				if nation.campaign_attack_echelons.has(army.id):
					nation.campaign_attack_echelons[part.id] = int(
						nation.campaign_attack_echelons[army.id]
					)
				if nation.campaign_launched_armies.has(army.id):
					nation.campaign_launched_armies[part.id] = true
		nation.ai_last_force_action = (
			ActionCandidate.Kind.SPLIT_ARMY
		)
		nation.ai_last_force_day = state.day
		nation.ai_last_force_reason = (
			parts[0].ai_order_reason
		)
		return true
	return false


func _clear_campaign_attack_plan(nation_id: int) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_attack_assignments.clear()
	nation.campaign_attack_echelons.clear()
	nation.campaign_active_echelons.clear()
	nation.campaign_launched_armies.clear()
	nation.campaign_echelon_started_days.clear()
	nation.campaign_launched_attack_multiplier = 1.0
	nation.campaign_launched_bonus_days = 0
	nation.campaign_plan_targets.clear()
	nation.campaign_plan_wave = -1
	nation.campaign_plan_primary_city = -1


func _ensure_campaign_attack_plan(
	nation_id: int,
	primary_city: int
) -> bool:
	var nation := state.nations[nation_id]
	var desired_wave := nation.campaign_offensive_count + 1
	if (
		nation.campaign_plan_wave == desired_wave
		and nation.campaign_plan_primary_city == primary_city
		and not nation.campaign_attack_assignments.is_empty()
		and _campaign_primary_assignment_ready(
			nation_id,
			primary_city
		)
	):
		return true
	_clear_campaign_attack_plan(nation_id)
	if (
		primary_city < 0
		or primary_city >= state.cities.size()
	):
		return false
	if (
		state.uses_heightmap
		and nation.campaign_preparation_group_assignments.has(
			primary_city
		)
	):
		return _build_campaign_attack_plan_from_preparation(
			nation_id,
			nation.campaign_preparation_targets
		)
	var attackers := _campaign_staged_armies(
		nation_id,
		primary_city
	)
	var primary_required := DiplomacyAI.required_assault_troops(
		state,
		nation_id,
		primary_city
	)
	var primary_limit := int(ceil(
		float(primary_required)
			* CAMPAIGN_TARGET_COMMIT_RATIO
	))
	var primary_committed := 0
	var remaining: Array[Army] = []
	for army in attackers:
		if primary_committed < primary_limit:
			nation.campaign_attack_assignments[army.id] = (
				primary_city
			)
			primary_committed += army.size
		else:
			remaining.append(army)
	if primary_committed < primary_required:
		_clear_campaign_attack_plan(nation_id)
		return false
	nation.campaign_plan_targets.append(primary_city)

	if (
		CAMPAIGN_MAX_TARGETS > 1
		and not remaining.is_empty()
	):
		var target_nation := (
			state.cities[primary_city].owner_nation
		)
		var eligible_by_target := {}
		var size_by_target := {}
		for army in remaining:
			var origin := _campaign_army_origin(
				army,
				nation_id
			)
			if origin < 0:
				continue
			for neighbor in state.neighbors(origin):
				var edge := state.edge_of(origin, neighbor)
				if (
					neighbor == primary_city
					or edge == null
					or edge.max_manpower <= 0
					or state.cities[neighbor].owner_nation
						!= target_nation
				):
					continue
				if not eligible_by_target.has(neighbor):
					eligible_by_target[neighbor] = (
						[] as Array[Army]
					)
					size_by_target[neighbor] = 0
				(
					eligible_by_target[neighbor]
					as Array[Army]
				).append(army)
				size_by_target[neighbor] = int(
					size_by_target[neighbor]
				) + army.size
		var view := _build_ai_view(nation_id)
		var snapshot := _strategy_snapshot_for(view)
		var secondary_city := -1
		var secondary_score := -INF
		var target_ids := eligible_by_target.keys()
		EquivariantOrder.sort_city_ids(
			target_ids,
			state,
			nation_id,
			primary_city
		)
		for target_id_value in target_ids:
			var target_id := int(target_id_value)
			var required := (
				DiplomacyAI.required_assault_troops(
					state,
					nation_id,
					target_id
				)
			)
			if int(size_by_target[target_id]) < required:
				continue
			var score := snapshot.value_of_city(target_id)
			if (
				score > secondary_score
				or (
					is_equal_approx(
						score,
						secondary_score
					)
					and (
							EquivariantOrder.city_id_less(
								state,
								nation_id,
								target_id,
								secondary_city,
								primary_city
							)
					)
				)
			):
				secondary_score = score
				secondary_city = target_id
		if secondary_city >= 0:
			var secondary_required := (
				DiplomacyAI.required_assault_troops(
					state,
					nation_id,
					secondary_city
				)
			)
			var secondary_limit := int(ceil(
				float(secondary_required)
					* CAMPAIGN_TARGET_COMMIT_RATIO
			))
			var secondary_committed := 0
			for army in (
				eligible_by_target[secondary_city]
				as Array[Army]
			):
				if secondary_committed >= secondary_limit:
					break
				nation.campaign_attack_assignments[
					army.id
				] = secondary_city
				secondary_committed += army.size
			nation.campaign_plan_targets.append(
				secondary_city
			)
	# 已进入集结区但未承担第二方向的军队全部作为主目标后续梯队，
	# 避免首轮失败后重新等待 90 天国家级攻势周期。
	for army in remaining:
		if not nation.campaign_attack_assignments.has(army.id):
			nation.campaign_attack_assignments[army.id] = primary_city
	_build_campaign_echelons(nation_id)
	nation.campaign_plan_wave = desired_wave
	nation.campaign_plan_primary_city = primary_city
	return true


func _build_campaign_echelons(nation_id: int) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_attack_echelons.clear()
	nation.campaign_active_echelons.clear()
	nation.campaign_launched_armies.clear()
	nation.campaign_echelon_started_days.clear()
	for target_city in nation.campaign_plan_targets:
		var assigned: Array[Army] = []
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and int(
					nation.campaign_attack_assignments.get(
						army.id,
						-1
					)
				) == target_city
			):
				assigned.append(army)
		var prioritized := _sort_campaign_priority(
			assigned, nation_id, target_city
		)
		assigned.clear()
		for army in prioritized:
			if _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			):
				assigned.append(army)
		for army in prioritized:
			if not assigned.has(army):
				assigned.append(army)
		var required := DiplomacyAI.required_assault_troops(
			state,
			nation_id,
			target_city
		)
		var echelon := 0
		var echelon_troops := 0
		for army in assigned:
			nation.campaign_attack_echelons[army.id] = echelon
			echelon_troops += army.size
			if echelon_troops >= required:
				echelon += 1
				echelon_troops = 0
		nation.campaign_active_echelons[target_city] = -1


func _campaign_primary_assignment_ready(
	nation_id: int,
	primary_city: int
) -> bool:
	var nation := state.nations[nation_id]
	var ready_troops := 0
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) != primary_city
			or not _army_ready_for_campaign_target(
				army,
				nation_id,
				primary_city
			)
		):
			continue
		ready_troops += army.size
	if (
		state.uses_heightmap
		and nation.campaign_preparation_group_assignments.has(
			primary_city
		)
	):
		return ready_troops > 0
	return ready_troops >= (
		DiplomacyAI.required_assault_troops(
			state,
			nation_id,
			primary_city
		)
	)


func _campaign_staged_armies(
	nation_id: int,
	target_city: int
) -> Array[Army]:
	var result: Array[Army] = []
	var staging := DiplomacyAI.staging_cities_for_objective(
		state,
		nation_id,
		target_city
	)
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		if (
			army.state == Army.State.IDLE
			and staging.has(army.location_city)
		) or (
			army.state == Army.State.HOLDING
			and (
				(
					army.move_from == target_city
					and staging.has(army.move_to)
				)
				or (
					army.move_to == target_city
					and staging.has(army.move_from)
				)
			)
		):
			result.append(army)
	return _sort_campaign_priority(result, nation_id, target_city)


## 战役集结优先级：兵力多者优先，等兵力时按“距目标更近者优先”。
## 距离取整数边长最短路（求和精确、与松弛顺序无关），是镜像不变量，
## 因此镜像对称世界里左右两军会做出镜像一致的梯队编排；
## 相同兵力且等距时按势力局部物理位置收尾，保证镜像等变。
func _sort_campaign_priority(
	armies: Array[Army],
	nation_id: int,
	target_city: int
) -> Array[Army]:
	var field := Pathfinding.dijkstra_field(
		state,
		target_city,
		nation_id,
		false,
		false,
		target_city
	)
	var dist: Dictionary = field["dist"]
	var distance_of := func(army: Army) -> float:
		return float(dist.get(
			_campaign_army_origin(army, nation_id),
			INF
		))
	var sorted: Array[Army] = armies.duplicate()
	sorted.sort_custom(func(a: Army, b: Army) -> bool:
		if a.size != b.size:
			return a.size > b.size
		var da: float = distance_of.call(a)
		var db: float = distance_of.call(b)
		if not is_equal_approx(da, db):
			return da < db
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b,
			target_city
		)
	)
	return sorted


func _campaign_army_origin(
	army: Army,
	nation_id: int
) -> int:
	if army.state == Army.State.IDLE:
		return army.location_city
	if army.state != Army.State.HOLDING:
		return -1
	var origin := army.move_from
	if not state.has_military_access(
		nation_id,
		state.cities[origin].owner_nation
	):
		origin = army.move_to
	return origin


func _can_use_army_for_offensive(
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator,
	army: Army,
	target_city: int
) -> bool:
	if defense_plan == null:
		return true
	if state.uses_heightmap:
		return defense_plan.can_join_offensive(
			army,
			target_city
		)
	return (
		coordinator == null
		or defense_plan.can_redeploy(army, coordinator)
	)


func _can_assign_campaign_preparation_army(
	nation_id: int,
	army: Army,
	target_city: int
) -> bool:
	var nation := state.nations[nation_id]
	if (
		state.uses_heightmap
		and nation.campaign_preparation_group_assignments.has(
			target_city
		)
		and army.battle_group_id
			!= int(
				nation.campaign_preparation_group_assignments[
					target_city
				]
			)
	):
		return false
	var preparation_target := int(
		nation.campaign_preparation_assignments.get(
			army.id,
			-1
		)
	)
	if preparation_target >= 0:
		return preparation_target == target_city
	var attack_target := int(
		nation.campaign_attack_assignments.get(
			army.id,
			-1
		)
	)
	return (
		attack_target < 0
		or attack_target == target_city
		or nation.campaign_launched_armies.has(army.id)
	)


func _assign_campaign_preparation_army(
	nation_id: int,
	army: Army,
	target_city: int
) -> void:
	var nation := state.nations[nation_id]
	var attack_target := int(
		nation.campaign_attack_assignments.get(
			army.id,
			-1
		)
	)
	if attack_target >= 0 and attack_target != target_city:
		nation.campaign_attack_assignments.erase(army.id)
		nation.campaign_attack_echelons.erase(army.id)
		nation.campaign_launched_armies.erase(army.id)
	if army.is_line_role():
		army.clear_line_assignment()
	nation.campaign_preparation_assignments[army.id] = target_city


func _campaign_theater_required_manpower(
	nation_id: int
) -> int:
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and army.max_size
				== GameState.INITIAL_HEAVY_ARMY_SIZE
		):
			return GameState.INITIAL_HEAVY_ARMY_SIZE
	return GameState.INITIAL_LIGHT_ARMY_SIZE


func _campaign_objective_in_current_theater(
	nation_id: int,
	proposed_city: int
) -> int:
	var nation := state.nations[nation_id]
	var anchor := nation.campaign_theater_anchor_city
	if (
		anchor < 0
		or anchor >= state.cities.size()
		or proposed_city < 0
		or proposed_city >= state.cities.size()
	):
		return proposed_city
	if (
		state.is_enemy(
			nation_id,
			state.cities[anchor].owner_nation
		)
		and not DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			anchor
		).is_empty()
	):
		return anchor
	var view := _build_ai_view(nation_id)
	var snapshot := _strategy_snapshot_for(view)
	var field := view.path_field(
		anchor,
		-1,
		false,
		false,
		-1,
		_campaign_theater_required_manpower(nation_id)
	)
	var distances: Dictionary = field["dist"]
	var proposed_distance := float(
		distances.get(proposed_city, INF)
	)
	if (
		proposed_distance
			<= CAMPAIGN_THEATER_MAX_TRANSFER_COST
		and not DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			proposed_city
		).is_empty()
	):
		return proposed_city
	var best_city := -1
	var best_score := -INF
	for city in state.cities:
		if (
			not state.is_enemy(
				nation_id,
				city.owner_nation
			)
			or DiplomacyAI.staging_cities_for_objective(
				state,
				nation_id,
				city.id
			).is_empty()
		):
			continue
		var distance := float(
			distances.get(city.id, INF)
		)
		if distance > CAMPAIGN_THEATER_MAX_TRANSFER_COST:
			continue
		var score := (
			snapshot.value_of_offense(city.id)
			- distance * 0.15
		)
		if (
			score > best_score
			or (
				is_equal_approx(score, best_score)
				and EquivariantOrder.city_id_less(
					state,
					nation_id,
					city.id,
					best_city,
					anchor
				)
			)
		):
			best_city = city.id
			best_score = score
	return best_city if best_city >= 0 else proposed_city


func _ensure_campaign_preparation_plan(
	nation_id: int,
	primary_city: int,
	defense_plan: CityDefensePlan = null,
	coordinator: ArmyCoordinator = null
) -> bool:
	var nation := state.nations[nation_id]
	var plan_valid := (
		not nation.campaign_preparation_targets.is_empty()
		and nation.campaign_preparation_targets.has(primary_city)
	)
	if plan_valid:
		for target_city in nation.campaign_preparation_targets:
			if (
				target_city < 0
				or target_city >= state.cities.size()
				or not state.is_enemy(
					nation_id,
					state.cities[target_city].owner_nation
				)
			):
				plan_valid = false
				break
	if plan_valid and state.uses_heightmap:
		plan_valid = _sync_campaign_group_members(nation_id)
	if plan_valid:
		return true

	_clear_campaign_preparation_plan(nation_id)
	if (
		primary_city < 0
		or primary_city >= state.cities.size()
		or not state.is_enemy(
			nation_id,
			state.cities[primary_city].owner_nation
		)
	):
		return false
	var view := _build_ai_view(nation_id)
	var snapshot := _strategy_snapshot_for(view)
	var threat := ThreatField.build(
		view,
		_threat_travel_cache
	)
	var theater_field := view.path_field(
		primary_city,
		-1,
		false,
		false,
		-1,
		_campaign_theater_required_manpower(nation_id)
	)
	var theater_distances: Dictionary = theater_field["dist"]
	var target_candidates: Array[int] = [primary_city]
	for target_city in snapshot.priority_enemy_cities:
		if target_candidates.size() >= CAMPAIGN_MAX_TARGETS:
			break
		if (
			target_city == primary_city
			or not state.is_enemy(
				nation_id,
				state.cities[target_city].owner_nation
			)
			or DiplomacyAI.staging_cities_for_objective(
				state,
				nation_id,
				target_city
			).is_empty()
			or float(
				theater_distances.get(target_city, INF)
			) > CAMPAIGN_THEATER_MAX_TRANSFER_COST
		):
			continue
		target_candidates.append(target_city)
	if state.uses_heightmap:
		return _assign_battle_groups_to_campaign_targets(
			nation_id,
			target_candidates,
			defense_plan,
			coordinator
		)

	var available: Array[Army] = []
	for army in state.armies:
		var origin := _campaign_army_origin(army, nation_id)
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or origin < 0
			or army.state not in [
				Army.State.IDLE,
				Army.State.HOLDING,
			]
			or state.day < army.defensive_deployment_until_day
		):
			continue
		available.append(army)

	var available_troops := 0
	for army in available:
		available_troops += army.size
	var primary_staged_required := _campaign_minimum_staged_troops(
		nation_id,
		primary_city
	)
	var primary_surplus := maxi(
		available_troops - primary_staged_required,
		0
	)
	var parallel_capacity := clampi(
		1 + int(floor(
			float(primary_surplus)
				/ (
					float(maxi(primary_staged_required, 1))
					* CAMPAIGN_PARALLEL_SURPLUS_STEP_RATIO
				)
		)),
		1,
		CAMPAIGN_MAX_TARGETS
	)
	var borrowed_line_armies := 0
	for target_index in range(target_candidates.size()):
		var target_city := target_candidates[target_index]
		var staging := DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			target_city
		)
		if staging.is_empty():
			continue
		var ranked: Array[Dictionary] = []
		for army in available:
			if not _can_assign_campaign_preparation_army(
				nation_id,
				army,
				target_city
			):
				continue
			if not _can_use_army_for_offensive(
				defense_plan,
				coordinator,
				army,
				target_city
			):
				continue
			var origin := _campaign_army_origin(
				army,
				nation_id
			)
			if origin < 0:
				continue
			var field := view.path_field(
				origin,
				nation_id,
				false,
				true,
				-1,
				army.max_size
			)
			var best_distance := INF
			for staging_city in staging:
				best_distance = minf(
					best_distance,
					float(
						field["dist"].get(
							staging_city,
							INF
						)
					)
				)
			if best_distance == INF:
				continue
			ranked.append({
				"army": army,
				"distance": best_distance,
			})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var army_a: Army = a["army"]
			var army_b: Army = b["army"]
			if (
				state.uses_heightmap
				and army_a.max_size != army_b.max_size
			):
				return army_a.max_size > army_b.max_size
			if (
				army_a.is_main_battle_role()
				!= army_b.is_main_battle_role()
			):
				return army_a.is_main_battle_role()
			var distance_a := float(a["distance"])
			var distance_b := float(b["distance"])
			if not is_equal_approx(distance_a, distance_b):
				return distance_a < distance_b
			if army_a.size != army_b.size:
				return army_a.size > army_b.size
			return EquivariantOrder.army_less(
				state,
				nation_id,
				army_a,
				army_b,
				target_city
			)
		)
		var selected: Array[Army] = []
		var selected_troops := 0
		var future_target_slots := mini(
			mini(
				target_candidates.size(),
				parallel_capacity
			) - target_index - 1,
			maxi(available.size() - 1, 0)
		)
		var selection_limit := maxi(
			available.size() - maxi(future_target_slots, 0),
			1
		)
		if not state.uses_heightmap:
			var grid_target_limit := int(ceil(
				float(_campaign_minimum_staged_troops(
					nation_id,
					target_city
				)) * CAMPAIGN_TARGET_COMMIT_RATIO
			))
			var grid_direct_defense := 0.0
			for defender in state.armies_at_city(target_city):
				if state.is_enemy(
					nation_id,
					defender.owner_nation
				):
					grid_direct_defense += ArmyPower.effective(
						defender
					)
			var grid_target_defense := maxf(
				grid_direct_defense,
				threat.threat_at(target_city)
			)
			if (
				state.recognized_owner_of(target_city)
					!= nation_id
			):
				grid_target_defense += ArmyPower.city_defense(
					state.cities[target_city]
				)
			var grid_preparation_days := (
				_campaign_offensive_interval(nation_id)
				if nation.campaign_last_offensive_day >= 0
				else 0
			)
			var grid_target_power := (
				grid_target_defense
				* _campaign_attack_ratio_threshold(nation_id)
				/ offensive_preparation_multiplier(
					grid_preparation_days
				)
			)
			var grid_selected_power := 0.0
			for entry in ranked:
				if (
					selected.size() >= selection_limit
					or (
						selected_troops >= grid_target_limit
						and grid_selected_power
							>= grid_target_power
					)
				):
					break
				var grid_army: Army = entry["army"]
				selected.append(grid_army)
				selected_troops += grid_army.size
				grid_selected_power += ArmyPower.effective(
					grid_army
				)
			if selected_troops <= 0:
				continue
			nation.campaign_preparation_targets.append(
				target_city
			)
			for grid_army in selected:
				_assign_campaign_preparation_army(
					nation_id,
					grid_army,
					target_city
				)
				available.erase(grid_army)
			continue
		var ranked_heavy: Array[Dictionary] = []
		var ranked_light: Array[Dictionary] = []
		for entry in ranked:
			var ranked_army: Army = entry["army"]
			if (
				ranked_army.max_size
					== GameState.INITIAL_HEAVY_ARMY_SIZE
			):
				ranked_heavy.append(entry)
			elif (
				ranked_army.max_size
					== GameState.INITIAL_LIGHT_ARMY_SIZE
			):
				ranked_light.append(entry)
		var rank_equivalent := func(
			a: Dictionary,
			b: Dictionary
		) -> bool:
			var army_a: Army = a["army"]
			var army_b: Army = b["army"]
			return (
				is_equal_approx(
					float(a["distance"]),
					float(b["distance"])
				)
				and army_a.size == army_b.size
				and not EquivariantOrder.army_less(
					state,
					nation_id,
					army_a,
					army_b,
					target_city
				)
				and not EquivariantOrder.army_less(
					state,
					nation_id,
					army_b,
					army_a,
					target_city
				)
			)
		if ranked_heavy.is_empty():
			var fallback_limit := mini(
				LIGHT_ONLY_OFFENSIVE_MAX_ARMIES,
				mini(ranked_light.size(), selection_limit)
			)
			for fallback_entry in ranked_light:
				if selected.size() >= fallback_limit:
					break
				var fallback_army: Army = fallback_entry["army"]
				var borrows_line := (
					defense_plan != null
					and defense_plan.assigned_city_for(
						fallback_army
					) >= 0
				)
				if (
					borrows_line
					and borrowed_line_armies
						>= CAMPAIGN_BORROWED_LINE_MAX_ARMIES
				):
					continue
				selected.append(fallback_army)
				selected_troops += fallback_army.size
				if borrows_line:
					borrowed_line_armies += 1
		else:
			for heavy_entry in ranked_heavy:
				var spearhead: Army = heavy_entry["army"]
				selected.append(spearhead)
				selected_troops += spearhead.size
		if (
			not ranked_heavy.is_empty()
			and not ranked_light.is_empty()
		):
			var support_candidates: Array[Dictionary] = []
			for light_entry in ranked_light:
				var light_army: Army = light_entry["army"]
				var borrows_line := (
					defense_plan != null
					and defense_plan.assigned_city_for(
						light_army
					) >= 0
				)
				if (
					borrows_line
					and borrowed_line_armies
						>= CAMPAIGN_BORROWED_LINE_MAX_ARMIES
				):
					continue
				support_candidates.append(light_entry)
			var support_is_unique: bool = (
				support_candidates.size() == 1
				or not rank_equivalent.call(
					support_candidates[0],
					support_candidates[1]
				)
			) if not support_candidates.is_empty() else false
			if support_is_unique and not support_candidates.is_empty():
				var support: Army = (
					support_candidates[0]["army"]
				)
				selected.append(support)
				selected_troops += support.size
				if (
					defense_plan != null
					and defense_plan.assigned_city_for(
						support
					) >= 0
				):
					borrowed_line_armies += 1
		if (
			selected_troops <= 0
			or (
				target_city != primary_city
				and target_index >= parallel_capacity
			)
		):
			continue
		nation.campaign_preparation_targets.append(
			target_city
		)
		for army in selected:
			_assign_campaign_preparation_army(
				nation_id,
				army,
				target_city
			)
			available.erase(army)
	if nation.campaign_preparation_targets.is_empty():
		return false
	nation.campaign_preparation_started_day = (
		nation.campaign_last_offensive_day
		if nation.campaign_last_offensive_day >= 0
		else state.day
	)
	return true


func _assign_battle_groups_to_campaign_targets(
	nation_id: int,
	target_candidates: Array[int],
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator
) -> bool:
	_reconcile_strategic_roles(nation_id)
	var nation := state.nations[nation_id]
	var view := _build_ai_view(nation_id)
	var used_groups := {}
	for target_city in target_candidates:
		var staging := DiplomacyAI.staging_cities_for_objective(
			state,
			nation_id,
			target_city
		)
		if staging.is_empty():
			continue
		var best_group_id := -1
		var best_members: Array[Army] = []
		var best_power := -1.0
		var best_distance := INF
		for group in nation.battle_groups:
			if used_groups.has(group.id):
				continue
			var group_members := state.battle_group_members(
				nation_id,
				group.id
			)
			if group_members.is_empty():
				continue
			var members: Array[Army] = []
			var group_power := 0.0
			var group_distance := 0.0
			for army in group_members:
				var origin := _campaign_army_origin(
					army,
					nation_id
				)
				if (
					origin < 0
					or army.state not in [
						Army.State.IDLE,
						Army.State.HOLDING,
					]
					or state.day
						< army.defensive_deployment_until_day
					or not _can_assign_campaign_preparation_army(
						nation_id,
						army,
						target_city
					)
					or not _can_use_army_for_offensive(
						defense_plan,
						coordinator,
						army,
						target_city
					)
				):
					continue
				var field := view.path_field(
					origin,
					nation_id,
					false,
					true,
					-1,
					army.max_size
				)
				var member_distance := INF
				for staging_city in staging:
					member_distance = minf(
						member_distance,
						float(
							field["dist"].get(
								staging_city,
								INF
							)
						)
					)
				if member_distance == INF:
					continue
				members.append(army)
				group_power += ArmyPower.effective(army)
				group_distance = maxf(
					group_distance,
					member_distance
				)
			if members.size() != group_members.size():
				continue
			if (
				group_power > best_power
				or (
					is_equal_approx(group_power, best_power)
					and (
						group_distance < best_distance
						or (
							is_equal_approx(
								group_distance,
								best_distance
							)
							and (
								best_group_id < 0
								or group.id < best_group_id
							)
						)
					)
				)
			):
				best_group_id = group.id
				best_members = members
				best_power = group_power
				best_distance = group_distance
		if best_group_id < 0:
			continue
		nation.campaign_preparation_targets.append(target_city)
		nation.campaign_preparation_group_assignments[
			target_city
		] = best_group_id
		used_groups[best_group_id] = true
		for army in best_members:
			_assign_campaign_preparation_army(
				nation_id,
				army,
				target_city
			)
	if nation.campaign_preparation_targets.is_empty():
		return false
	nation.campaign_preparation_started_day = (
		nation.campaign_last_offensive_day
		if nation.campaign_last_offensive_day >= 0
		else state.day
	)
	return true


func _sync_campaign_group_members(nation_id: int) -> bool:
	var nation := state.nations[nation_id]
	if (
		nation.campaign_preparation_group_assignments.size()
			!= nation.campaign_preparation_targets.size()
	):
		return false
	var desired_assignments := {}
	for target_city in nation.campaign_preparation_targets:
		if not nation.campaign_preparation_group_assignments.has(
			target_city
		):
			return false
		var group_id := int(
			nation.campaign_preparation_group_assignments[
				target_city
			]
		)
		if state.battle_group_by_id(nation_id, group_id) == null:
			return false
		for member in state.battle_group_members(
			nation_id,
			group_id
		):
			desired_assignments[member.id] = target_city
	for army_id in (
		nation.campaign_preparation_assignments.keys().duplicate()
	):
		if not desired_assignments.has(army_id):
			nation.campaign_preparation_assignments.erase(army_id)
	for army_id in desired_assignments:
		nation.campaign_preparation_assignments[army_id] = int(
			desired_assignments[army_id]
		)
	return true


func _campaign_preparation_staged_armies(
	nation_id: int,
	target_city: int
) -> Array[Army]:
	var nation := state.nations[nation_id]
	var result: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and int(
				nation.campaign_preparation_assignments.get(
					army.id,
					-1
				)
			) == target_city
			and _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			)
		):
			result.append(army)
	return _sort_campaign_priority(
		result,
		nation_id,
		target_city
	)


func _campaign_preparation_staged_troops(
	nation_id: int,
	target_city: int
) -> int:
	var total := 0
	for army in _campaign_preparation_staged_armies(
		nation_id,
		target_city
	):
		total += army.size
	return total


func _assign_offensive_staging_orders(
	nation_id: int,
	objective_city: int,
	defense_plan: CityDefensePlan,
	coordinator: ArmyCoordinator,
	build_campaign_plan: bool,
	assigned_only: bool
) -> bool:
	var staging := DiplomacyAI.staging_cities_for_objective(
		state, nation_id, objective_city
	)
	if staging.is_empty():
		return false
	if state.uses_heightmap:
		var nation := state.nations[nation_id]
		if not nation.campaign_preparation_group_assignments.has(
			objective_city
		):
			if not _assign_battle_groups_to_campaign_targets(
				nation_id,
				[objective_city] as Array[int],
				defense_plan,
				coordinator
			):
				return false
		assigned_only = true
	var path_view := (
		defense_plan.view
		if defense_plan != null
		else _build_ai_view(nation_id)
	)
	var committed_heavy := 0
	var committed_light := 0
	if not assigned_only:
		var objective_token := "目标城市%d" % objective_city
		for committed_army in state.armies:
			if (
				committed_army.owner_nation != nation_id
				or committed_army.size <= 0
				or not committed_army.ai_order_reason.contains(
					objective_token
				)
				or (
					committed_army.state == Army.State.IDLE
					and not staging.has(
						committed_army.location_city
					)
				)
			):
				continue
			if (
				committed_army.max_size
					== GameState.INITIAL_HEAVY_ARMY_SIZE
			):
				committed_heavy += 1
			elif (
				committed_army.max_size
					== GameState.INITIAL_LIGHT_ARMY_SIZE
			):
				committed_light += 1
	var changed := false
	var orders := 0
	for staging_city in staging:
		if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
			break
		if _edge_has_friendly_holder_or_order(
			nation_id, staging_city, objective_city
		):
			continue
		var staging_armies: Array[Army] = []
		for army in state.armies:
			if (
				army.owner_nation != nation_id
				or army.size <= 0
				or army.state != Army.State.IDLE
				or army.location_city != staging_city
				or (
					assigned_only
						and not _can_assign_campaign_preparation_army(
							nation_id,
							army,
							objective_city
						)
				)
				or state.day < army.defensive_deployment_until_day
				or not _can_use_army_for_offensive(
					defense_plan,
					coordinator,
					army,
					objective_city
				)
			):
				continue
			staging_armies.append(army)
		staging_armies.sort_custom(
			func(a: Army, b: Army) -> bool:
				if a.max_size != b.max_size:
					return a.max_size > b.max_size
				return EquivariantOrder.army_less(
					state,
					nation_id,
					a,
					b,
					objective_city
				)
		)
		for army in staging_armies:
			if (
				not assigned_only
				and army.max_size
					== GameState.INITIAL_LIGHT_ARMY_SIZE
				and committed_light >= committed_heavy
			):
				continue
			var hold := ActionCandidate.make(
				ActionCandidate.Kind.HOLD,
				1000.0,
				"战前集结：在己方侧监视目标城市%d" % objective_city,
				objective_city
			)
			hold.target_edge_a = staging_city
			hold.target_edge_b = objective_city
			hold.minimum_commit_days = DiplomacyAI.WAR_PREPARATION_MIN_DAYS
			if _execute_ai_candidate(army, hold):
				if assigned_only:
					_assign_campaign_preparation_army(
						nation_id,
						army,
						objective_city
					)
				changed = true
				orders += 1
				if not assigned_only:
					if (
						army.max_size
							== GameState.INITIAL_HEAVY_ARMY_SIZE
					):
						committed_heavy += 1
					elif (
						army.max_size
							== GameState.INITIAL_LIGHT_ARMY_SIZE
					):
						committed_light += 1
			break
	var staged := (
		_campaign_preparation_staged_troops(
			nation_id,
			objective_city
		)
		if assigned_only
		else DiplomacyAI.staged_troops_for_objective(
			state,
			nation_id,
			objective_city
		)
	)
	var required := DiplomacyAI.required_assault_troops(
		state,
		nation_id,
		objective_city
	)
	if assigned_only:
		var nation := state.nations[nation_id]
		if (
			state.uses_heightmap
				and nation.war_preparation_target_nation >= 0
			and nation.campaign_preparation_group_assignments.has(
				objective_city
			)
		):
			required = 0
			var group_id := int(
				nation.campaign_preparation_group_assignments[
					objective_city
				]
			)
			for member in state.battle_group_members(
				nation_id,
				group_id
			):
				required += member.size
			required = maxi(required, 1)
		else:
			required = _campaign_minimum_staged_troops(
				nation_id,
				objective_city
			)
	var sustained_required := (
		required
		if assigned_only
		else required * CAMPAIGN_PREPARED_ECHELONS
	)
	if staged >= sustained_required:
		if build_campaign_plan:
			_ensure_campaign_attack_plan(
				nation_id,
				objective_city
			)
		return changed
	if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
		return changed
	var candidates: Array[Dictionary] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.IDLE
			or staging.has(army.location_city)
			or (
				assigned_only
					and not _can_assign_campaign_preparation_army(
						nation_id,
						army,
						objective_city
					)
			)
			or state.day < army.defensive_deployment_until_day
			or not _can_use_army_for_offensive(
				defense_plan,
				coordinator,
				army,
				objective_city
			)
		):
			continue
		var field := path_view.path_field(
			army.location_city,
			nation_id,
			false,
			true,
			-1,
			army.max_size
		)
		var best_city := -1
		var best_distance := INF
		for staging_city in staging:
			var distance := float(field["dist"][staging_city])
			if distance < best_distance:
				best_distance = distance
				best_city = staging_city
		if best_city == -1 or best_distance == INF:
			continue
		candidates.append({
			"army": army,
			"best_city": best_city,
			"best_distance": best_distance,
		})
	# 距集结出发地更近者优先增援：距离取自镜像对称的静态最短路
	# （Dijkstra 的 dist 与松弛顺序无关，镜像世界左右严格相等），
	# 消除“先创建者（低 id）先动”的偏置，保证左右选出互为镜像的援军。
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var army_a: Army = a["army"]
		var army_b: Army = b["army"]
		if army_a.max_size != army_b.max_size:
			return army_a.max_size > army_b.max_size
		var da: float = a["best_distance"]
		var db: float = b["best_distance"]
		if not is_equal_approx(da, db):
			return da < db
		return EquivariantOrder.army_less(
			state,
			nation_id,
			army_a,
			army_b,
			objective_city
		)
	)
	for entry in candidates:
		if (
			orders >= PREPARATION_MAX_ORDERS_PER_CYCLE
			or staged >= sustained_required
		):
			break
		var army: Army = entry["army"]
		var best_city: int = entry["best_city"]
		if (
			not assigned_only
			and army.max_size
				== GameState.INITIAL_LIGHT_ARMY_SIZE
			and committed_light >= committed_heavy
		):
			continue
		var reinforce := ActionCandidate.make(
			ActionCandidate.Kind.REINFORCE,
			900.0,
			"战前集结：向目标城市%d的进攻出发地%d调兵"
				% [objective_city, best_city],
			best_city
		)
		reinforce.minimum_commit_days = DiplomacyAI.WAR_PREPARATION_MIN_DAYS
		if _execute_ai_candidate(army, reinforce):
			if assigned_only:
				_assign_campaign_preparation_army(
					nation_id,
					army,
					objective_city
				)
			changed = true
			orders += 1
			staged += army.size
			if not assigned_only:
				if (
					army.max_size
						== GameState.INITIAL_HEAVY_ARMY_SIZE
				):
					committed_heavy += 1
				elif (
					army.max_size
						== GameState.INITIAL_LIGHT_ARMY_SIZE
				):
					committed_light += 1
	var actual_staged := (
		_campaign_preparation_staged_troops(
			nation_id,
			objective_city
		)
		if assigned_only
		else DiplomacyAI.staged_troops_for_objective(
			state,
			nation_id,
			objective_city
		)
	)
	if actual_staged >= sustained_required:
		if build_campaign_plan:
			_ensure_campaign_attack_plan(
				nation_id,
				objective_city
			)
		return changed
	if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
		return changed
	var holders: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.HOLDING
			or (
				assigned_only
					and not _can_assign_campaign_preparation_army(
						nation_id,
						army,
						objective_city
					)
			)
			or state.day < army.defensive_deployment_until_day
			or _army_ready_for_campaign_target(
				army,
				nation_id,
				objective_city
			)
			or not _can_use_army_for_offensive(
				defense_plan,
				coordinator,
				army,
				objective_city
			)
		):
			continue
		var friendly_endpoint := army.move_from
		if not state.has_military_access(
			nation_id, state.cities[friendly_endpoint].owner_nation
		):
			friendly_endpoint = army.move_to
		holders.append(army)
	holders.sort_custom(func(a: Army, b: Army) -> bool:
			if a.size != b.size:
				return a.size > b.size
			return EquivariantOrder.army_less(
				state,
				nation_id,
				a,
				b,
				objective_city
			)
	)
	for army in holders:
		if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
			break
		if (
			not assigned_only
			and army.max_size
				== GameState.INITIAL_LIGHT_ARMY_SIZE
			and committed_light >= committed_heavy
		):
			continue
		var friendly_endpoint := army.move_from
		if not state.has_military_access(
			nation_id, state.cities[friendly_endpoint].owner_nation
		):
			friendly_endpoint = army.move_to
		var withdraw := ActionCandidate.make(
			ActionCandidate.Kind.RETREAT,
			850.0,
			"战前重部署：从次要边境撤回，转向目标城市%d集结"
				% objective_city,
			friendly_endpoint
		)
		withdraw.minimum_commit_days = AI_DECISION_INTERVAL_DAYS
		if _execute_ai_candidate(army, withdraw):
			if assigned_only:
				_assign_campaign_preparation_army(
					nation_id,
					army,
					objective_city
				)
			changed = true
			orders += 1
			if not assigned_only:
				if (
					army.max_size
						== GameState.INITIAL_HEAVY_ARMY_SIZE
				):
					committed_heavy += 1
				elif (
					army.max_size
						== GameState.INITIAL_LIGHT_ARMY_SIZE
				):
					committed_light += 1
	return changed


func _build_campaign_attack_plan_from_preparation(
	nation_id: int,
	targets: Array[int]
) -> bool:
	var nation := state.nations[nation_id]
	_clear_campaign_attack_plan(nation_id)
	var ordered_targets := targets.duplicate()
	EquivariantOrder.sort_city_ids(
		ordered_targets,
		state,
		nation_id
	)
	for target_city in ordered_targets:
		var staged_troops := (
			_campaign_preparation_staged_troops(
				nation_id,
				target_city
			)
		)
		var persistent_group := (
			state.uses_heightmap
			and nation.campaign_preparation_group_assignments.has(
				target_city
			)
		)
		if (
			target_city < 0
			or target_city >= state.cities.size()
			or not state.is_enemy(
				nation_id,
				state.cities[target_city].owner_nation
			)
			or staged_troops <= 0
			or (
				not persistent_group
				and staged_troops
					< _campaign_minimum_staged_troops(
						nation_id,
						target_city
					)
			)
		):
			continue
		nation.campaign_plan_targets.append(target_city)
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and int(
					nation.campaign_preparation_assignments.get(
						army.id,
						-1
					)
				) == target_city
			):
				nation.campaign_attack_assignments[army.id] = (
					target_city
				)
	if nation.campaign_plan_targets.is_empty():
		return false
	_build_campaign_echelons(nation_id)
	nation.campaign_plan_wave = (
		nation.campaign_offensive_count + 1
	)
	nation.campaign_plan_primary_city = (
		nation.campaign_plan_targets[0]
	)
	return true


func _launch_campaign_offensive(
	nation_id: int,
	objective_city: int,
	preparation_days: int = -1,
	prepared_targets: Array[int] = []
) -> bool:
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or not state.is_enemy(
			nation_id, state.cities[objective_city].owner_nation
		)
	):
		return false
	if prepared_targets.is_empty():
		var required := DiplomacyAI.required_assault_troops(
			state, nation_id, objective_city
		)
		var staged := DiplomacyAI.staged_troops_for_objective(
			state, nation_id, objective_city
		)
		if staged < required:
			return false
		if not _ensure_campaign_attack_plan(
			nation_id,
			objective_city
		):
			return false
	elif not _build_campaign_attack_plan_from_preparation(
		nation_id,
		prepared_targets
	):
		return false
	var nation := state.nations[nation_id]
	var organization_cost := _campaign_offensive_gold_cost(
		nation_id
	)
	if (
		organization_cost <= 0
		or nation.treasury_gold < organization_cost
	):
		return false
	if preparation_days < 0:
		preparation_days = _campaign_preparation_days(
			nation_id
		)
	var offensive_multiplier := offensive_preparation_multiplier(
		preparation_days
	)
	var offensive_bonus_days := offensive_bonus_duration_days(
		preparation_days
	)
	nation.campaign_preparation_multiplier = offensive_multiplier
	var launched := false
	var launched_origins := {}
	var plan_targets := nation.campaign_plan_targets.duplicate()
	EquivariantOrder.sort_city_ids(
		plan_targets,
		state,
		nation_id,
		objective_city
	)
	for target_city in plan_targets:
		if not state.is_enemy(
			nation_id,
			state.cities[target_city].owner_nation
		):
			continue
		var target_required := (
			_campaign_minimum_staged_troops(
				nation_id,
				target_city
			)
		)
		var target_attackers: Array[Army] = []
		var target_size := 0
		for army in state.armies:
			if (
				army.owner_nation != nation_id
				or army.size <= 0
				or int(
					nation.campaign_attack_assignments.get(
						army.id,
						-1
					)
				) != target_city
				or int(
					nation.campaign_attack_echelons.get(
						army.id,
						0
					)
				) != 0
				or not _army_ready_for_campaign_target(
					army,
					nation_id,
					target_city
				)
			):
				continue
			target_attackers.append(army)
			target_size += army.size
		if target_size < target_required:
			continue
		target_attackers.sort_custom(
			func(a: Army, b: Army) -> bool:
					if a.size != b.size:
						return a.size > b.size
					return EquivariantOrder.army_less(
						state,
						nation_id,
						a,
						b,
						target_city
				)
		)
		var target_committed := 0
		var origin_cities: Array[int] = []
		for army in target_attackers:
			var origin_city := _campaign_army_origin(
				army,
				nation_id
			)
			var attack := ActionCandidate.make(
				ActionCandidate.Kind.ATTACK,
				2000.0,
				(
					"国家战役第%d波：军%d按计划准备%d天，"
					+ "以%.2f倍攻击城市%d"
				) % [
					nation.campaign_offensive_count + 1,
					army.id,
					preparation_days,
					offensive_multiplier,
					target_city,
				],
				target_city
			)
			attack.minimum_commit_days = (
				CAMPAIGN_OFFENSIVE_COMMIT_DAYS
			)
			attack.offensive_attack_multiplier = (
				offensive_multiplier
			)
			attack.offensive_bonus_days = (
				offensive_bonus_days
			)
			if _execute_ai_candidate(army, attack):
				target_committed += army.size
				launched = true
				nation.campaign_launched_armies[army.id] = true
				if (
					origin_city >= 0
					and not origin_cities.has(
						origin_city
					)
				):
					origin_cities.append(origin_city)
			if target_committed >= int(ceil(
				float(target_required)
					* CAMPAIGN_TARGET_COMMIT_RATIO
			)):
				break
		if not origin_cities.is_empty():
			launched_origins[target_city] = origin_cities
			nation.campaign_active_echelons[target_city] = 0
			nation.campaign_echelon_started_days[target_city] = (
				state.day
			)
	if launched:
		nation.treasury_gold -= organization_cost
		nation.last_offensive_gold_cost = organization_cost
		nation.last_offensive_gold_day = state.day
		nation.campaign_launched_attack_multiplier = (
			offensive_multiplier
		)
		nation.campaign_launched_bonus_days = (
			offensive_bonus_days
		)
		nation.campaign_last_offensive_day = state.day
		nation.campaign_theater_anchor_city = objective_city
		nation.campaign_theater_started_day = state.day
		_clear_campaign_preparation_plan(nation_id)
		nation.campaign_next_offensive_day = (
			state.day + _campaign_offensive_interval(nation_id)
		)
		nation.campaign_offensive_count += 1
		var launched_targets := launched_origins.keys()
		EquivariantOrder.sort_city_ids(
			launched_targets,
			state,
			nation_id,
			objective_city
		)
		for target_city_value in launched_targets:
			var target_city := int(target_city_value)
			if (
				offensive_bonus_days
					>= OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
			):
				nation.campaign_post_capture_plans[
					target_city
				] = {
					"preparation_days":
						offensive_bonus_days,
					"expires_day":
						state.day + offensive_bonus_days,
				}
			state.add_campaign_visual_event(
				nation_id,
				target_city,
				launched_origins[target_city],
				nation.campaign_offensive_count,
				CAMPAIGN_ARROW_DURATION_DAYS
			)
	return launched


static func offensive_organization_gold_cost(
	participants: Array[Army]
) -> int:
	var total := 0
	for army in participants:
		if army != null and army.size > 0:
			total += GameState.offensive_army_gold_cost(
				army.size
			)
	return total


func _campaign_offensive_gold_cost(nation_id: int) -> int:
	var nation := state.nations[nation_id]
	var participants: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or not nation.campaign_attack_assignments.has(
				army.id
			)
		):
			continue
		var target_city := int(
			nation.campaign_attack_assignments.get(
				army.id,
				-1
			)
		)
		if (
			not nation.campaign_plan_targets.has(target_city)
			or target_city < 0
			or target_city >= state.cities.size()
			or not state.is_enemy(
				nation_id,
				state.cities[target_city].owner_nation
			)
		):
			continue
		participants.append(army)
	return offensive_organization_gold_cost(participants)


## 既有战役计划的执行续接。前梯队进入目标城市后即开放下一梯队，让道路容量
## 自然形成连续纵队；若前梯队提前失去作战能力，仍沿用次日接替规则。
func _advance_campaign_echelons() -> void:
	for nation in state.nations:
		if not nation.alive or nation.campaign_plan_targets.is_empty():
			continue
		var targets := nation.campaign_plan_targets.duplicate()
		EquivariantOrder.sort_city_ids(
			targets,
			state,
			nation.id
		)
		for target_city_value in targets:
			var target_city := int(target_city_value)
			if (
				target_city < 0
				or target_city >= state.cities.size()
				or not state.is_enemy(
					nation.id,
					state.cities[target_city].owner_nation
				)
			):
				_remove_campaign_target(nation.id, target_city)
				continue
			var active_echelon := int(
				nation.campaign_active_echelons.get(
					target_city,
					-1
				)
			)
			if active_echelon < 0:
				continue
			if _campaign_echelon_operational(
				nation.id,
				target_city,
				active_echelon
			):
				# 同梯队可能因首段道路容量暂未出发；容量释放后继续执行同一命令。
				_launch_campaign_echelon_members(
					nation.id,
					target_city,
					active_echelon,
					false,
					false
				)
				if _campaign_echelon_engaged_at_target(
					nation.id,
					target_city,
					active_echelon
				):
					_launch_campaign_echelon_members(
						nation.id,
						target_city,
						active_echelon + 1,
						true,
						false
					)
				continue
			_launch_campaign_echelon_members(
				nation.id,
				target_city,
				active_echelon + 1,
				true,
				true
			)


func _campaign_echelon_engaged_at_target(
	nation_id: int,
	target_city: int,
	echelon: int
) -> bool:
	var nation := state.nations[nation_id]
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.FIGHTING
			or not nation.campaign_launched_armies.has(army.id)
			or int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) != target_city
			or int(
				nation.campaign_attack_echelons.get(
					army.id,
					-1
				)
			) != echelon
		):
			continue
		var battle := state.battle_by_id(army.battle_id)
		if (
			battle != null
			and not battle.finished
			and battle.kind == Battle.Kind.SIEGE
			and battle.city != null
			and battle.city.id == target_city
		):
			return true
	return false


func _campaign_echelon_operational(
	nation_id: int,
	target_city: int,
	echelon: int
) -> bool:
	var nation := state.nations[nation_id]
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and nation.campaign_launched_armies.has(army.id)
			and int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) == target_city
			and int(
				nation.campaign_attack_echelons.get(
					army.id,
					-1
				)
			) == echelon
			and army.state in [
				Army.State.MOVING,
				Army.State.FIGHTING,
			]
		):
			return true
	return false


func _launch_campaign_echelon_members(
	nation_id: int,
	target_city: int,
	echelon: int,
	followup: bool,
	require_sufficient: bool
) -> bool:
	var nation := state.nations[nation_id]
	var attackers: Array[Army] = []
	var ready_troops := 0
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or nation.campaign_launched_armies.has(army.id)
			or int(
				nation.campaign_attack_assignments.get(
					army.id,
					-1
				)
			) != target_city
			or int(
				nation.campaign_attack_echelons.get(
					army.id,
					-1
				)
			) != echelon
			or not _army_ready_for_campaign_target(
				army,
				nation_id,
				target_city
			)
		):
			continue
		attackers.append(army)
		ready_troops += army.size
	if attackers.is_empty():
		return false
	var required := _campaign_minimum_staged_troops(
		nation_id,
		target_city
	)
	if require_sufficient and ready_troops < required:
		return false
	attackers.sort_custom(func(a: Army, b: Army) -> bool:
		if a.size != b.size:
			return a.size > b.size
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b,
			target_city
		)
	)
	var launched := false
	var origin_cities: Array[int] = []
	for army in attackers:
		var origin_city := _campaign_army_origin(
			army,
			nation_id
		)
		var attack := ActionCandidate.make(
			ActionCandidate.Kind.ATTACK,
			2000.0,
			(
				"持续攻势第%d梯队：军%d接替前梯队攻击城市%d"
				% [echelon + 1, army.id, target_city]
				if followup
				else "国家战役第%d梯队：军%d继续攻击城市%d"
					% [echelon + 1, army.id, target_city]
			),
			target_city
		)
		attack.minimum_commit_days = CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		attack.offensive_attack_multiplier = (
			nation.campaign_launched_attack_multiplier
		)
		attack.offensive_bonus_days = (
			nation.campaign_launched_bonus_days
		)
		if not _execute_ai_candidate(army, attack):
			continue
		nation.campaign_launched_armies[army.id] = true
		launched = true
		if origin_city >= 0 and not origin_cities.has(origin_city):
			origin_cities.append(origin_city)
	if not launched:
		return false
	nation.campaign_active_echelons[target_city] = echelon
	nation.campaign_echelon_started_days[target_city] = state.day
	state.add_campaign_visual_event(
		nation_id,
		target_city,
		origin_cities,
		nation.campaign_offensive_count,
		CAMPAIGN_ARROW_DURATION_DAYS
	)
	return true


## 对正在围攻的重点城市持续派遣纵深预备队。这里不保存平行的防御任务表：
## Army.ai_target_city 是在途任务真源，战斗与道路占用则直接从 GameState 派生。
func _advance_priority_city_defense_echelons() -> void:
	var sieges: Array[Battle] = []
	var context_by_nation := {}
	for battle in state.battles:
		if (
			not battle.finished
			and battle.kind == Battle.Kind.SIEGE
			and battle.city != null
			and not battle.side_a.is_empty()
		):
			sieges.append(battle)
	sieges.sort_custom(func(a: Battle, b: Battle) -> bool:
		var gap_a := _siege_local_defense_gap(a)
		var gap_b := _siege_local_defense_gap(b)
		if not is_equal_approx(gap_a, gap_b):
			return gap_a > gap_b
		return EquivariantOrder.mirror_orbit_city_less(
			state,
			a.city.id,
			b.city.id
		)
	)
	for siege in sieges:
		var city_id := siege.city.id
		var nation_id := siege.city.owner_nation
		if (
			nation_id < 0
			or nation_id >= state.nations.size()
			or not state.nations[nation_id].alive
		):
			continue
		if not context_by_nation.has(nation_id):
			var revision := [
				state.ownership_revision,
				state.diplomacy_revision,
				state.fortification_revision,
			]
			var cached_snapshot: StrategicMapSnapshot = null
			if (
				_ai_strategy_cache.has(nation_id)
				and _ai_strategy_revision.get(
					nation_id,
					[]
				) == revision
			):
				cached_snapshot = _ai_strategy_cache[nation_id]
			context_by_nation[nation_id] = {
				"view": null,
				"snapshot": cached_snapshot,
				"threat": null,
			}
		var context: Dictionary = context_by_nation[nation_id]
		var snapshot: StrategicMapSnapshot = context["snapshot"]
		if snapshot == null:
			var initial_view := _build_ai_view(nation_id)
			snapshot = _strategy_snapshot_for(initial_view)
			context["view"] = initial_view
			context["snapshot"] = snapshot
		var priority_defense := _is_priority_defense_city(
			nation_id,
			city_id,
			snapshot
		)
		if not priority_defense:
			continue
		var attack_power := 0.0
		for army in siege.side_a:
			if army.size > 0:
				attack_power += ArmyPower.effective(army)
		var committed_power := ArmyPower.city_defense(siege.city)
		for army in siege.side_b:
			if army.size > 0 and army.owner_nation == nation_id:
				committed_power += ArmyPower.effective(army)
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and army.state == Army.State.MOVING
				and army.ai_action in [
					ActionCandidate.Kind.REINFORCE,
					ActionCandidate.Kind.RETREAT,
				]
				and army.ai_target_city == city_id
			):
				committed_power += ArmyPower.effective(army)
		# 已在途的梯队足以填平当前战斗缺口时，无需重建完整国家防区。
		if committed_power >= attack_power:
			continue
		var view: AiWorldView = context["view"]
		if view == null:
			view = _build_ai_view(nation_id)
			context["view"] = view
		var threat: ThreatField = context["threat"]
		if threat == null:
			threat = ThreatField.build(
				view,
				_threat_travel_cache
			)
			context["threat"] = threat
		var defense_plan := CityDefensePlan.build(
			view,
			snapshot,
			threat
		)
		_advance_priority_city_defense(
			siege,
			defense_plan
		)


func _siege_local_defense_gap(siege: Battle) -> float:
	if siege == null or siege.city == null:
		return 0.0
	var nation_id := siege.city.owner_nation
	var attack_power := 0.0
	for army in siege.side_a:
		if army.size > 0:
			attack_power += ArmyPower.effective(army)
	var committed_power := ArmyPower.city_defense(siege.city)
	for army in siege.side_b:
		if army.size > 0 and army.owner_nation == nation_id:
			committed_power += ArmyPower.effective(army)
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and army.state == Army.State.MOVING
			and army.ai_target_city == siege.city.id
			and army.ai_action in [
				ActionCandidate.Kind.REINFORCE,
				ActionCandidate.Kind.RETREAT,
			]
		):
			committed_power += ArmyPower.effective(army)
	return maxf(attack_power - committed_power, 0.0)


func _is_priority_defense_city(
	nation_id: int,
	city_id: int,
	snapshot: StrategicMapSnapshot
) -> bool:
	var city := state.cities[city_id]
	return (
		city_id == state.nations[nation_id].capital_city_id
		or city.has_warehouse
		or city.is_food_hub
		or city.is_manpower_hub
		or snapshot.critical_supply_cities.has(city_id)
		or snapshot.value_of_city(city_id)
			>= CityDefensePlan.MUST_HOLD_CITY_VALUE_FLOOR
	)


func _advance_priority_city_defense(
	siege: Battle,
	defense_plan: CityDefensePlan
) -> void:
	var city_id := siege.city.id
	var nation_id := siege.city.owner_nation
	var coordinator := ArmyCoordinator.new()
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		if (
			army.ai_target_city >= 0
			and army.state in [
				Army.State.MOVING,
				Army.State.FIGHTING,
			]
		):
			coordinator.reserve(army.ai_target_city, army)
		elif army.state == Army.State.HOLDING and army.move_to != -1:
			var friendly_endpoint := army.move_from
			if not state.has_military_access(
				nation_id,
				state.cities[friendly_endpoint].owner_nation
			):
				friendly_endpoint = army.move_to
			var other_endpoint := (
				army.move_to
				if friendly_endpoint == army.move_from
				else army.move_from
			)
			coordinator.reserve_edge(
				friendly_endpoint,
				other_endpoint,
				army
			)
	var attack_power := 0.0
	for army in siege.side_a:
		if army.size > 0:
			attack_power += ArmyPower.effective(army)
	var committed_power := ArmyPower.city_defense(siege.city)
	for army in siege.side_b:
		if army.size > 0 and army.owner_nation == nation_id:
			committed_power += ArmyPower.effective(army)
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army.size > 0
			and army.state == Army.State.MOVING
			and army.ai_action in [
				ActionCandidate.Kind.REINFORCE,
				ActionCandidate.Kind.RETREAT,
			]
			and army.ai_target_city == city_id
		):
			committed_power += ArmyPower.effective(army)
	var required_power := maxf(
		attack_power,
		defense_plan.requirement_at(city_id)
	)
	if committed_power >= required_power:
		return
	var candidates: Array[Dictionary] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.IDLE
			or army.location_city == city_id
			or not defense_plan.can_redeploy(army, coordinator)
		):
			continue
		var field := defense_plan.view.path_field(
			army.location_city,
			nation_id,
			false,
			true,
			-1,
			army.max_size
		)
		var distance := float(field["dist"].get(city_id, INF))
		if distance == INF:
			continue
		candidates.append({
			"army": army,
			"distance": distance,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var distance_a := float(a["distance"])
		var distance_b := float(b["distance"])
		if not is_equal_approx(distance_a, distance_b):
			return distance_a < distance_b
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a["army"] as Army,
			b["army"] as Army,
			city_id
		)
	)
	for entry in candidates:
		if committed_power >= required_power:
			break
		var army: Army = entry["army"]
		var reinforce := ActionCandidate.make(
			ActionCandidate.Kind.REINFORCE,
			2000.0,
			"重点城市%d大会战：纵深预备队军%d流水增援"
				% [city_id, army.id],
			city_id
		)
		reinforce.minimum_commit_days = CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		reinforce.defensive_deployment = true
		if not _execute_ai_candidate(army, reinforce):
			continue
		var nation := state.nations[nation_id]
		nation.campaign_attack_assignments.erase(army.id)
		nation.campaign_attack_echelons.erase(army.id)
		nation.campaign_launched_armies.erase(army.id)
		coordinator.reserve(city_id, army)
		committed_power += ArmyPower.effective(army)


func _remove_campaign_target(
	nation_id: int,
	target_city: int
) -> void:
	var nation := state.nations[nation_id]
	nation.campaign_plan_targets.erase(target_city)
	nation.campaign_active_echelons.erase(target_city)
	nation.campaign_echelon_started_days.erase(target_city)
	nation.campaign_post_capture_plans.erase(target_city)
	var army_ids := nation.campaign_attack_assignments.keys()
	for army_id_value in army_ids:
		var army_id := int(army_id_value)
		if int(
			nation.campaign_attack_assignments.get(
				army_id,
				-1
			)
		) != target_city:
			continue
		nation.campaign_attack_assignments.erase(army_id)
		nation.campaign_attack_echelons.erase(army_id)
		nation.campaign_launched_armies.erase(army_id)


func _army_ready_for_campaign_target(
	army: Army,
	nation_id: int,
	target_city: int
) -> bool:
	var staging := DiplomacyAI.staging_cities_for_objective(
		state,
		nation_id,
		target_city
	)
	if (
		army.state == Army.State.IDLE
		and staging.has(army.location_city)
	):
		return true
	return (
		army.state == Army.State.HOLDING
		and (
			(
				army.move_from == target_city
				and staging.has(army.move_to)
			)
			or (
				army.move_to == target_city
				and staging.has(army.move_from)
			)
		)
	)


func _grant_offensive_bonus(
	army: Army,
	multiplier: float,
	duration_days: int
) -> void:
	army.offensive_attack_multiplier = clampf(
		multiplier,
		1.0,
		OFFENSIVE_BONUS_MAX_MULTIPLIER
	)
	army.offensive_bonus_until_day = (
		state.day + maxi(duration_days, 0)
	)


func _manage_campaign_offensive(
	nation_id: int,
	defense_plan: CityDefensePlan = null,
	coordinator: ArmyCoordinator = null,
	threat: ThreatField = null
) -> bool:
	var nation := state.nations[nation_id]
	var can_launch := not (
		nation.campaign_next_offensive_day >= 0
		and state.day < nation.campaign_next_offensive_day
	)
	var objective: Dictionary = {}
	var defender_id := -1
	var owns_diplomatic_objective := false
	var enemy_ids := state.wars_of(nation_id)
	enemy_ids.sort_custom(func(a: int, b: int) -> bool:
		return EquivariantOrder.nation_less(
			state,
			nation_id,
			a,
			b
		)
	)
	# 仍在修复窗口内的本国法理失地优先于原进攻目标，形成真实反复争夺。
	for enemy_id in enemy_ids:
		var reclamation := DiplomacyAI.select_war_objective(
			state,
			nation_id,
			enemy_id
		)
		if reclamation.is_empty():
			continue
		var reclamation_city := int(reclamation["city_id"])
		if (
			state.recognized_owner_of(reclamation_city)
				== nation_id
			and Simulation.city_fort_vulnerability(
				state.cities[reclamation_city],
				state.day
			) > 0.0
		):
			objective = reclamation
			defender_id = enemy_id
			break
	if objective.is_empty():
		for enemy_id in enemy_ids:
			var candidate := state.war_objective(
				nation_id,
				enemy_id
			)
			if (
				not candidate.is_empty()
				and int(candidate.get("attacker", -1))
					== nation_id
			):
				objective = candidate
				defender_id = enemy_id
				owns_diplomatic_objective = true
				break
	# 防御战争没有本国发起的外交目标，但仍必须主动选择敌城组织反攻。
	if objective.is_empty():
		for enemy_id in enemy_ids:
			var counteroffensive := (
				DiplomacyAI.select_war_objective(
					state,
					nation_id,
					enemy_id
				)
			)
			if counteroffensive.is_empty():
				continue
			objective = counteroffensive
			defender_id = enemy_id
			break
	if objective.is_empty():
		return false
	var objective_city := int(objective["city_id"])
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or not state.is_enemy(
			nation_id, state.cities[objective_city].owner_nation
		)
	):
		var next := DiplomacyAI.select_war_objective(
			state, nation_id, defender_id
		)
		if next.is_empty():
			return false
		objective_city = int(next["city_id"])
		if owns_diplomatic_objective:
			state.set_war_objective(
				nation_id,
				defender_id,
				objective_city,
				str(next["reason"])
			)
	var theater_objective := (
		_campaign_objective_in_current_theater(
			nation_id,
			objective_city
		)
	)
	if theater_objective != objective_city:
		objective_city = theater_objective
		defender_id = state.cities[
			objective_city
		].owner_nation
		owns_diplomatic_objective = false
	if not _ensure_campaign_preparation_plan(
		nation_id,
		objective_city,
		defense_plan,
		coordinator
	):
		return false
	var preparation_days := _campaign_preparation_days(nation_id)
	nation.campaign_preparation_multiplier = (
		offensive_preparation_multiplier(preparation_days)
	)
	var preparation_targets := (
		nation.campaign_preparation_targets.duplicate()
	)
	EquivariantOrder.sort_city_ids(
		preparation_targets,
		state,
		nation_id,
		objective_city
	)
	var launch_targets: Array[int] = []
	if can_launch:
		if threat == null:
			threat = ThreatField.build(
				_build_ai_view(nation_id),
				_threat_travel_cache
			)
	for target_city in preparation_targets:
		var recent_legal_reclamation := (
			state.recognized_owner_of(target_city) == nation_id
			and Simulation.city_fort_vulnerability(
				state.cities[target_city],
				state.day
			) > 0.0
		)
		if not can_launch and not recent_legal_reclamation:
			continue
		var required := _campaign_minimum_staged_troops(
			nation_id,
			target_city
		)
		if _campaign_preparation_staged_troops(
			nation_id,
			target_city
		) < required:
			continue
		if threat == null:
			threat = ThreatField.build(
				_build_ai_view(nation_id),
				_threat_travel_cache
			)
		var projected_ratio := _campaign_projected_assault_ratio(
			nation_id,
			target_city,
			preparation_days,
			threat,
			true
		)
		var full_preparation_active := (
			nation.campaign_full_preparation_targets.has(
				target_city
			)
		)
		if (
			recent_legal_reclamation
			or (
				full_preparation_active
				and preparation_days
					>= OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
			)
			or (
				not full_preparation_active
				and projected_ratio
					>= _campaign_attack_ratio_threshold(
						nation_id
					)
			)
		):
			launch_targets.append(target_city)
		elif not nation.campaign_full_preparation_targets.has(
			target_city
		):
			nation.campaign_full_preparation_targets.append(
				target_city
			)
	if not launch_targets.is_empty():
		var launch_objective := (
			objective_city
			if launch_targets.has(objective_city)
			else launch_targets[0]
		)
		if _launch_campaign_offensive(
				nation_id,
				launch_objective,
				preparation_days,
				launch_targets
		):
			return true
	# 重整期不是空窗期：持续集结，但不覆盖仍在执行的当前梯队计划。
	var changed := false
	for target_city in preparation_targets:
		changed = (
			_assign_offensive_staging_orders(
				nation_id,
				target_city,
				defense_plan,
				coordinator,
				false,
				true
			)
			or changed
		)
	return changed


func _food_security_report(
	nation_id: int,
	nation_armies: Array[Army] = []
) -> Dictionary:
	var war_food := DiplomacyAI.war_food_report(state, nation_id)
	var monthly_production := float(war_food["monthly_food_production"])
	var monthly_demand := 0.0
	var armies_to_scan: Array[Army] = (
		nation_armies
		if not nation_armies.is_empty()
		else state.armies
	)
	for army in armies_to_scan:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		monthly_demand += _projected_army_food_demand(army)
	monthly_demand = maxf(
		monthly_demand,
		state.nations[nation_id].food_demand_ema
	)
	var stock := int(war_food["food_stock"])
	var reserve_target := int(war_food["stock_target"])
	var sustainable_demand := float(war_food["monthly_food_budget"])
	return {
		"posture": war_food["posture"],
		"monthly_production": monthly_production,
		"monthly_demand": monthly_demand,
		"monthly_surplus": monthly_production - monthly_demand,
		"annual_production": war_food["annual_food_production"],
		"annual_demand": monthly_demand * 12.0,
		"annual_surplus": (
			float(war_food["annual_food_production"])
			- monthly_demand * 12.0
		),
		"runway_years": war_food["current_runway_years"],
		"required_campaign_years": war_food["required_campaign_years"],
		"full_strength_annual_demand": war_food["full_strength_annual_demand"],
		"full_strength_annual_balance": war_food["full_strength_annual_balance"],
		"full_strength_runway_years": war_food["full_strength_runway_years"],
		"affordable_troops": war_food["affordable_troops"],
		"stock": stock,
		"reserve_target": reserve_target,
		"sustainable_demand": sustainable_demand,
		"required_savings": maxf(monthly_demand - sustainable_demand, 0.0),
		"needs_demobilization": monthly_demand > sustainable_demand + 0.01,
	}


func _food_growth_manpower_budget(food_report: Dictionary) -> int:
	var food_headroom := maxf(
		float(food_report["sustainable_demand"])
			- float(food_report["monthly_demand"])
			- 1.0,
		0.0
	)
	return int(floor(
		food_headroom / (FOOD_PER_CAPITA * MAX_SUPPLY_MULT)
	))


func _projected_army_food_demand(army: Army) -> float:
	var sources := _cached_supply_sources(
		army,
		_ai_supply_source_cache,
		_ai_supply_network_cache
	)
	var supply := (
		[
			int(sources[0]["city_id"]),
			float(sources[0]["loss"]),
		]
		if not sources.is_empty()
		else [-1, INF]
	)
	var route_loss := float(supply[1])
	var multiplier := MAX_SUPPLY_MULT
	if int(supply[0]) != -1:
		multiplier = minf(1.0 + route_loss, MAX_SUPPLY_MULT)
	var base := maxi(int(ceil(float(army.size) * FOOD_PER_CAPITA)), 1)
	return ceil(float(base) * multiplier)


func _demobilize_for_food_security(
	view: AiWorldView,
	threat: ThreatField,
	food_report: Dictionary,
	target_count: int
) -> bool:
	var candidates: Array[Army] = []
	for army in view.friendly_armies:
		if (
			army.state != Army.State.IDLE
			or army.location_city < 0
			or threat.threat_at(army.location_city) >= ArmyPower.effective(army)
		):
			continue
		candidates.append(army)
	candidates.sort_custom(func(a: Army, b: Army) -> bool:
		if a.size != b.size:
			return a.size > b.size
		return EquivariantOrder.army_less(
			state,
			view.nation_id,
			a,
			b
		)
	)
	if candidates.is_empty():
		return false
	var remaining_savings := float(food_report["required_savings"])
	var total_returned := 0
	var total_saved := 0.0
	var changed := false
	for army in candidates:
		if remaining_savings <= 0.01:
			break
		var minimum_size := int(ceil(
			float(army.max_size) * PEACETIME_STRENGTH_RATIO
		))
		var reducible := army.size - minimum_size
		if reducible <= 0:
			continue
		var demand := _projected_army_food_demand(army)
		var food_per_person := demand / float(maxi(army.size, 1))
		var requested := maxi(
			int(ceil(remaining_savings / maxf(food_per_person, 0.0001))),
			DEMOBILIZATION_STEP_MIN
		)
		var returned := mini(requested, reducible)
		if returned <= 0:
			continue
		var saved := food_per_person * float(returned)
		army.size -= returned
		state.nations[army.owner_nation].manpower_pool += returned
		army.ai_action = ActionCandidate.Kind.DISBAND_ARMY
		army.ai_order_created_day = state.day
		total_returned += returned
		total_saved += saved
		remaining_savings = maxf(remaining_savings - saved, 0.0)
		changed = true
	if not changed:
		return false
	var nation := state.nations[view.nation_id]
	nation.food_demand_ema = maxf(
		nation.food_demand_ema - total_saved,
		0.0
	)
	var reason := (
		(
			"军粮预算缩编：返还%d人，年结余%.0f，库存可撑%.1f年，"
			+ "态度%d要求%.1f年，目标保留%d军"
		) % [
			total_returned,
			food_report["annual_surplus"],
			food_report["runway_years"],
			food_report["posture"],
			food_report["required_campaign_years"],
			target_count,
		]
	)
	nation.ai_last_force_action = ActionCandidate.Kind.DISBAND_ARMY
	nation.ai_last_force_day = state.day
	nation.ai_last_force_reason = reason
	return true


func _is_available_recruitment_hub(
	nation_id: int,
	city_id: int,
	allow_besieged: bool = false
) -> bool:
	return (
		city_id >= 0 and city_id < state.cities.size()
		and state.cities[city_id].owner_nation == nation_id
		and state.cities[city_id].has_warehouse
		and (
			allow_besieged
			or not state.city_under_siege(city_id)
		)
	)


func _create_army_for_nation(
	nation_id: int,
	city_id: int,
	formation_size: int = GameState.INITIAL_LIGHT_ARMY_SIZE,
	reason: String = "",
	allow_besieged_hub: bool = false,
	battle_group_id: int = -1
) -> Army:
	if nation_id < 0 or nation_id >= state.nations.size():
		return null
	if formation_size not in [
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
	]:
		return null
	var nation := state.nations[nation_id]
	if (
		formation_size == GameState.INITIAL_HEAVY_ARMY_SIZE
		and state.battle_group_by_id(
			nation_id,
			battle_group_id
		) == null
	):
		return null
	var creation_cost := (
		GameState.formation_creation_gold_cost(
			formation_size
		)
	)
	if (
		nation.manpower_pool < formation_size
		or nation.treasury_gold < creation_cost
		or state.active_army_count(nation_id)
			>= state.max_army_count(nation_id)
		or not _is_available_recruitment_hub(
			nation_id,
			city_id,
			allow_besieged_hub
		)
	):
		return null
	nation.manpower_pool -= formation_size
	nation.treasury_gold -= creation_cost
	var army := state.create_army(
		nation_id,
		city_id,
		formation_size,
		formation_size
	)
	if army == null:
		nation.manpower_pool += formation_size
		nation.treasury_gold += creation_cost
		return null
	if (
		battle_group_id >= 0
		and not state.assign_army_to_battle_group(
			army,
			battle_group_id
		)
	):
		state.armies.erase(army)
		nation.manpower_pool += formation_size
		nation.treasury_gold += creation_cost
		return null
	army.ai_action = ActionCandidate.Kind.CREATE_ARMY
	army.ai_order_created_day = state.day
	army.ai_order_reason = (
		"%s；支付建制费%d金" % [
			reason,
			creation_cost,
		]
	)
	nation.ai_last_force_action = ActionCandidate.Kind.CREATE_ARMY
	nation.ai_last_force_day = state.day
	nation.ai_last_force_reason = army.ai_order_reason
	_reconcile_strategic_roles(nation_id)
	return army


func _disband_army(army: Army, reason: String = "") -> bool:
	if (
		army == null
		or army.size <= 0
		or army.state not in [
			Army.State.IDLE,
			Army.State.RECOVERING,
		]
		or army.location_city < 0 or army.location_city >= state.cities.size()
		or state.cities[army.location_city].owner_nation != army.owner_nation
	):
		return false
	var nation := state.nations[army.owner_nation]
	var returned := army.size
	nation.manpower_pool += returned
	army.ai_action = ActionCandidate.Kind.DISBAND_ARMY
	nation.ai_last_force_action = ActionCandidate.Kind.DISBAND_ARMY
	nation.ai_last_force_day = state.day
	nation.ai_last_force_reason = reason
	army.size = 0
	state.armies.erase(army)
	return true


func _begin_ai_command_collection(
	snapshot_army_ids: Dictionary = {}
) -> void:
	_clear_ai_command_collection()
	if snapshot_army_ids.is_empty():
		for army in state.armies:
			if army.size > 0:
				_ai_snapshot_armies[army.id] = true
	else:
		_ai_snapshot_armies = snapshot_army_ids.duplicate()
	_collect_ai_commands = true


func _clear_ai_command_collection() -> void:
	_collect_ai_commands = false
	_ai_command_buffer.clear()
	_ai_planned_armies.clear()
	_ai_planned_first_legs.clear()
	_ai_command_sequence.clear()
	_ai_snapshot_armies.clear()


func _queue_ai_candidate(army: Army, candidate: ActionCandidate) -> bool:
	if (
		army == null
		or army.size <= 0
		or not _ai_snapshot_armies.has(army.id)
		or _ai_planned_armies.has(army.id)
		or not _can_queue_ai_candidate(army, candidate)
	):
		return false
	var prepared_path: Array[int] = []
	var path_prevalidated := false
	if (
		army.state == Army.State.IDLE
		and candidate.kind in [
			ActionCandidate.Kind.ATTACK,
			ActionCandidate.Kind.REINFORCE,
			ActionCandidate.Kind.MERGE,
			ActionCandidate.Kind.RETREAT,
		]
	):
		var field := Pathfinding.dijkstra_field(
			state,
			army.location_city,
			army.owner_nation,
			false,
			candidate.kind != ActionCandidate.Kind.ATTACK,
			candidate.target_city
				if candidate.kind == ActionCandidate.Kind.ATTACK
				else -1,
			army.max_size
		)
		prepared_path = Pathfinding.reconstruct(
			field["prev"],
			army.location_city,
			candidate.target_city
		)
		if prepared_path.is_empty():
			return false
		path_prevalidated = true
	var first_leg := -1
	if army.state == Army.State.IDLE:
		if candidate.kind == ActionCandidate.Kind.HOLD:
			first_leg = candidate.target_city
		elif path_prevalidated:
			first_leg = prepared_path[0]
	if first_leg != -1:
		var first_edge := state.edge_of(army.location_city, first_leg)
		if first_edge == null or first_edge.max_manpower <= 0:
			return false
			if (
				candidate.kind == ActionCandidate.Kind.HOLD
				and not first_edge.allows_holding
			):
				return false
		var leg_key := _ai_first_leg_key(
			army.owner_nation,
			army.location_city,
			first_leg
		)
		var occupied_manpower := _friendly_same_direction_manpower(
			army.owner_nation,
			army.location_city,
			first_leg
		)
		var reserved_manpower := int(
			_ai_planned_first_legs.get(leg_key, 0)
		)
		if (
			occupied_manpower
			+ reserved_manpower
			+ army.max_size
			> first_edge.max_manpower
		):
			return false
		_ai_planned_first_legs[leg_key] = (
			reserved_manpower + army.max_size
		)
	var sequence := int(
		_ai_command_sequence.get(army.owner_nation, 0)
	)
	_ai_command_sequence[army.owner_nation] = sequence + 1
	_ai_command_buffer.append(AiCommandIntent.make(
		army,
		candidate,
		sequence,
		prepared_path,
		path_prevalidated
	))
	_ai_planned_armies[army.id] = true
	return true


func _can_queue_ai_candidate(
	army: Army,
	candidate: ActionCandidate
) -> bool:
	if candidate == null or candidate.kind == ActionCandidate.Kind.NONE:
		return false
	if candidate.kind == ActionCandidate.Kind.HOLD:
		if army.state == Army.State.HOLDING:
			var held_edge := state.edge_of(
				army.move_from,
				army.move_to
			)
			return held_edge != null and held_edge.allows_holding
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		var target_edge := state.edge_of(
			army.location_city,
			candidate.target_city
		)
		return target_edge != null and target_edge.allows_holding
	if candidate.kind in [
		ActionCandidate.Kind.ATTACK,
		ActionCandidate.Kind.REINFORCE,
		ActionCandidate.Kind.MERGE,
	]:
		if candidate.kind == ActionCandidate.Kind.ATTACK and army.state == Army.State.HOLDING:
			return (
				candidate.target_city == army.move_from
				or candidate.target_city == army.move_to
			)
		return (
			army.state == Army.State.IDLE
			and candidate.target_city >= 0
			and candidate.target_city < state.cities.size()
			and candidate.target_city != army.location_city
		)
	if candidate.kind == ActionCandidate.Kind.RETREAT:
		if army.state == Army.State.HOLDING:
			return (
				candidate.target_city == army.move_from
				or candidate.target_city == army.move_to
			)
		return (
			army.state == Army.State.IDLE
			and candidate.target_city >= 0
			and candidate.target_city < state.cities.size()
			and candidate.target_city != army.location_city
		)
	return false


func _commit_ai_command_collection(
	nation_order: Array[int]
) -> void:
	_collect_ai_commands = false
	ai_last_command_commit_failures = 0
	var nation_rank := {}
	for index in range(nation_order.size()):
		nation_rank[nation_order[index]] = index
	_ai_command_buffer.sort_custom(
		func(a: AiCommandIntent, b: AiCommandIntent) -> bool:
			if a.sequence != b.sequence:
				return a.sequence < b.sequence
			return (
				int(nation_rank.get(a.nation_id, 999999))
				< int(nation_rank.get(b.nation_id, 999999))
			)
	)
	for intent in _ai_command_buffer:
		if not _execute_ai_candidate(
			intent.army,
			intent.candidate,
			intent.prepared_path,
			intent.path_prevalidated
		):
			ai_last_command_commit_failures += 1
			ai_command_commit_failure_total += 1
			if ai_command_commit_failure_log.size() < 20:
				ai_command_commit_failure_log.append(
					(
						"day=%d army=%d nation=%d state=%d kind=%d target=%d "
						+ "reason=%s"
					) % [
						state.day,
						intent.army.id,
						intent.army.owner_nation,
						intent.army.state,
						intent.candidate.kind,
						intent.candidate.target_city,
						intent.candidate.reason,
					]
				)
	_clear_ai_command_collection()


static func _ai_first_leg_key(
	nation_id: int,
	from_city: int,
	to_city: int
) -> String:
	return "%d:%d:%d" % [nation_id, from_city, to_city]


func _execute_ai_candidate(
	army: Army,
	candidate: ActionCandidate,
	prepared_path: Array[int] = [],
	path_prevalidated: bool = false
) -> bool:
	if _collect_ai_commands:
		return _queue_ai_candidate(army, candidate)
	if candidate.kind == ActionCandidate.Kind.HOLD:
		if army.state == Army.State.HOLDING:
			var held_edge := state.edge_of(
				army.move_from,
				army.move_to
			)
			if held_edge == null or not held_edge.allows_holding:
				return false
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		var target_edge := state.edge_of(
			army.location_city,
			candidate.target_city
		)
		if target_edge == null or not target_edge.allows_holding:
			return false
		army.path = [candidate.target_city] as Array[int]
		army.hold_target_progress = HOLDING_TARGET_PROGRESS
	elif candidate.kind in [
		ActionCandidate.Kind.ATTACK,
		ActionCandidate.Kind.REINFORCE,
		ActionCandidate.Kind.MERGE,
	]:
		if candidate.kind == ActionCandidate.Kind.ATTACK and army.state == Army.State.HOLDING:
			if candidate.target_city == army.move_from:
				var old_from := army.move_from
				army.move_from = army.move_to
				army.move_to = old_from
				army.move_progress = 1.0 - army.move_progress
			elif candidate.target_city != army.move_to:
				return false
				_set_occupation_claimant_for_crossing(
					army,
					army.move_from,
					army.move_to
				)
			army.state = Army.State.MOVING
			army.holding_days = 0
			army.hold_target_progress = -1.0
			army.path.clear()
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		if path_prevalidated:
			army.path = prepared_path.duplicate()
		else:
			var field := Pathfinding.dijkstra_field(
				state,
				army.location_city,
				army.owner_nation,
				false,
				candidate.kind != ActionCandidate.Kind.ATTACK,
				candidate.target_city
					if candidate.kind == ActionCandidate.Kind.ATTACK
					else -1,
				army.max_size
			)
			army.path = Pathfinding.reconstruct(
				field["prev"], army.location_city, candidate.target_city
			)
		if army.path.is_empty():
			return false
		army.hold_target_progress = -1.0
	elif candidate.kind == ActionCandidate.Kind.RETREAT:
		if army.state == Army.State.HOLDING:
			if candidate.target_city == army.move_from:
				var old_from := army.move_from
				army.move_from = army.move_to
				army.move_to = old_from
				army.move_progress = 1.0 - army.move_progress
			elif candidate.target_city != army.move_to:
				return false
			army.state = Army.State.MOVING
			army.holding_days = 0
			army.hold_target_progress = -1.0
			army.path.clear()
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE:
			return false
		if path_prevalidated:
			army.path = prepared_path.duplicate()
		else:
			var retreat_field := Pathfinding.dijkstra_field(
				state,
				army.location_city,
				army.owner_nation,
				false,
				true,
				-1,
				army.max_size
			)
			army.path = Pathfinding.reconstruct(
				retreat_field["prev"],
				army.location_city,
				candidate.target_city
			)
		if army.path.is_empty():
			return false
		army.hold_target_progress = -1.0
	else:
		return false
	army.state = Army.State.MOVING
	army.move_from = army.location_city
	army.move_to = -1
	army.move_progress = 0.0
	_begin_next_leg(army)
	if army.move_to == -1:
		if path_prevalidated and not army.path.is_empty():
			# 冻结快照收集后，边上友军可能在统一提交阶段调头，
			# 使首段容量暂时满载。保留有效路径，沿用每日行军重试。
			_record_ai_order(army, candidate)
			return true
		army.state = Army.State.IDLE
		army.path.clear()
		return false
	_record_ai_order(army, candidate)
	return true


func _record_ai_order(army: Army, candidate: ActionCandidate) -> void:
	army.encounter_blocked = false
	army.ai_action = candidate.kind
	army.ai_target_city = candidate.target_city
	army.ai_order_created_day = state.day
	army.ai_order_until_day = state.day + candidate.minimum_commit_days
	army.ai_order_score = candidate.score
	army.ai_order_reason = candidate.reason
	if candidate.defensive_deployment:
		army.defensive_deployment_until_day = (
			state.day + DEFENSIVE_DEPLOYMENT_LOCK_DAYS
		)
		if (
			candidate.kind == ActionCandidate.Kind.RETREAT
			and candidate.target_edge_a >= 0
			and candidate.target_edge_b >= 0
		):
			army.defensive_blocked_edge_a = mini(
				candidate.target_edge_a,
				candidate.target_edge_b
			)
			army.defensive_blocked_edge_b = maxi(
				candidate.target_edge_a,
				candidate.target_edge_b
			)
		elif candidate.kind in [
			ActionCandidate.Kind.HOLD,
			ActionCandidate.Kind.REINFORCE,
		]:
			army.defensive_blocked_edge_a = -1
			army.defensive_blocked_edge_b = -1
	if candidate.offensive_bonus_days > 0:
		_grant_offensive_bonus(
			army,
			candidate.offensive_attack_multiplier,
			candidate.offensive_bonus_days
		)


func _edge_has_friendly_holder_or_order(nation_id: int, from_city: int, to_city: int) -> bool:
	var key := _edge_key_of(from_city, to_city)
	for army in state.armies:
		if army.size <= 0 or army.owner_nation != nation_id or army.move_to == -1:
			continue
		if _edge_key_of(army.move_from, army.move_to) != key:
			continue
		if army.state == Army.State.HOLDING or army.hold_target_progress >= 0.0:
			return true
	return false

# ------------------------------------------------------------------ 4. 行军 + 遭遇战

## 陆路基础行军时长；特殊边通过 edge_travel_days() 应用边级倍率。
## distance=1 为 10 天，此后每个真实距离单位增加 5 天，不设长距离上限。
static func march_days(distance: int) -> float:
	return (
		MARCH_DAYS_MIN
		+ float(maxi(distance, 1) - 1)
			* MARCH_DAYS_PER_DISTANCE_STEP
	)


static func edge_travel_days(edge: Edge) -> float:
	if edge == null:
		return MISSING_EDGE_TRAVEL_DAYS
	return maxf(
		march_days(edge.distance)
			* maxf(edge.travel_time_multiplier, 0.05),
		1.0
	)


func _advance_movement() -> void:
	# 1. 先推进所有 MOVING / RETREATING 军队（本步骤不处理"到达节点"）。
	#    关键时序：若在此就地 _arrive_at_node，先走到敌城的一方会在遭遇检测前离边进入攻城，
	#    导致相向而行的两军错身穿过、永不野战交火。故推进与到达必须分离。
	var holding_arrivals: Array[Army] = []
	for army in state.armies:
		if not _is_travelling(army) or army.size <= 0:
			continue   # FIGHTING 军队冻结在原地，不推进
		var was_encounter_blocked := army.encounter_blocked
		army.encounter_blocked = false
		if was_encounter_blocked:
			continue
		if army.move_to == -1:
			# 等待进入下一段（上月被 capacity 卡住）
			_begin_next_leg(army)
			if army.move_to == -1:
				continue
		var edge := state.edge_of(army.move_from, army.move_to)
		var travel_days := edge_travel_days(edge)
		army.move_progress += 1.0 / travel_days   # 可能 >= 1.0（走到边末端），稍后统一判定到达
		if army.state == Army.State.MOVING and army.hold_target_progress >= 0.0:
			if army.move_progress >= army.hold_target_progress:
				army.move_progress = army.hold_target_progress
				holding_arrivals.append(army)

	# 2. 已到道路终点的溃退军先完成节点落位。否则它会在下一次遭遇检测中
	#    反复拦截刚击败自己的胜方，使双方永久卡在城市端点而无法触发攻城。
	for army in state.armies:
		if (
			army.state == Army.State.RETREATING
			and army.size > 0
			and army.move_to != -1
			and army.move_progress >= 1.0
		):
			_arrive_at_node(army)

	# 3. 遭遇检测（普通行军到达节点之前）：同边敌军按物理位置接触即交火。
	#    走到边末端（norm→1.0）的一方与任何相向敌军必接触 → 优先野战，杜绝错身。
	_detect_encounters()
	_block_passthrough()   # 敌占交战点卡位：禁止敌军不战穿过
	# 驻防转换必须晚于遭遇检测：两支敌军同日抵达同一驻防点时仍应先开战，不能同时变 HOLDING 后互相无视。
	for army in holding_arrivals:
		if army.state == Army.State.MOVING and army.battle_id == -1:
			_start_holding(army)

	# 4. 到达节点：处理普通行军；未到终点或重新寻路的撤退军保持在道路上。
	for army in state.armies:
		if _is_travelling(army) and army.size > 0 and army.move_to != -1 and army.move_progress >= 1.0:
			_arrive_at_node(army)

	# 5. 推进所有进行中的战斗各打一回合
	_resolve_battles()
	_purge_dead_armies()


## 尝试进入 path 的下一段边。capacity 仅限制同国同方向友军；反向与敌军独立。
## 前置约定：调用前 army.move_from 已锚定为当前所在城。
func _begin_next_leg(army: Army) -> void:
	var from_city := army.move_from
	if army.path.is_empty():
		if army.state == Army.State.RETREATING:
			_start_recovering(army, from_city)
		else:
			_settle_idle(army, from_city)
		return
	var next_city: int = army.path[0]
	var edge := state.edge_of(from_city, next_city)
	if edge == null or edge.max_manpower <= 0:
		# 路径失效或道路禁止大军通行：普通军等待 AI 重规划，撤退军立即改走合法路线。
		army.path.clear()
		if army.state == Army.State.RETREATING:
			if (
				from_city >= 0
				and from_city < state.cities.size()
				and state.has_military_access(
					army.owner_nation,
					state.cities[from_city].owner_nation
				)
			):
				_start_recovering(army, from_city)
				return
			army.path = Pathfinding.nearest_friendly_city(state, army)
			if army.path.is_empty():
				army.size = 0
			else:
				_begin_next_leg(army)
		else:
			_settle_idle(army, from_city)
		return
	var occupied_manpower := _friendly_same_direction_manpower(
		army.owner_nation,
		from_city,
		next_city
	)
	var forced_evacuation := (
		army.state == Army.State.RETREATING
		and from_city >= 0
		and from_city < state.cities.size()
		and not state.has_military_access(
			army.owner_nation,
			state.cities[from_city].owner_nation
		)
	)
	if (
		not forced_evacuation
		and occupied_manpower + army.max_size
			> edge.max_manpower
	):
		# 只累计同国同方向的满编兵力；反向友军和敌军不占本方向容量。
		army.move_to = -1
		return
	_set_occupation_claimant_for_crossing(
		army,
		from_city,
		next_city
	)
	army.path.pop_front()
	army.move_to = next_city
	army.move_progress = 0.0
	army.holding_days = 0
	army.resume_holding_after_battle = false
	edge.passing_count += 1
	edge.occupied = true
	army.on_edge = true


func _friendly_same_direction_manpower(
	nation_id: int,
	from_city: int,
	to_city: int
) -> int:
	var manpower := 0
	for other in state.armies:
		if other.size <= 0 or other.owner_nation != nation_id:
			continue
		if not other.on_edge or other.move_to == -1:
			continue
		if other.move_from == from_city and other.move_to == to_city:
			manpower += maxi(other.max_size, 0)
	return manpower


func _set_occupation_claimant_for_crossing(
	army: Army,
	from_city: int,
	to_city: int
) -> void:
	if (
		from_city < 0
		or from_city >= state.cities.size()
		or to_city < 0
		or to_city >= state.cities.size()
		or not state.is_enemy(
			army.owner_nation,
			state.cities[to_city].owner_nation
		)
	):
		return
	var origin_owner := state.cities[from_city].owner_nation
	if (
		origin_owner == army.owner_nation
		or state.is_allied(
			army.owner_nation,
			origin_owner
		)
	):
		army.occupation_claimant_nation = origin_owner
	else:
		army.occupation_claimant_nation = army.owner_nation


## 到达 move_to 节点：释放当前边，触发/加入围城或继续下一段。
func _arrive_at_node(army: Army) -> void:
	var arrived := army.move_to
	var edge := state.edge_of(army.move_from, arrived)
	_release_edge(army)   # 离开边：释放通行槽

	if army.state == Army.State.RETREATING:
		army.move_from = arrived
		army.move_to = -1
		army.move_progress = 0.0
		army.location_city = arrived
		if army.path.is_empty():
			if state.has_military_access(
				army.owner_nation,
				state.cities[arrived].owner_nation
			):
				_start_recovering(army, arrived)
			else:
				# 目的地在撤退途中失守：从当前位置重新寻找最近友城。
				_start_morale_retreat_from_city(army, arrived, arrived)
		else:
			_begin_next_leg(army)
		return

	var city := state.cities[arrived]
	# 该城正被围攻：任何抵达者都必须与围城战斗互动（敌对方→攻/守，城主援军→帮守/解围），
	# 不得旁观穿过。城被围时 owner 尚未易主，故不能只凭 is_enemy(owner) 判定。
	if _siege_battle_of(city) != null:
		_start_or_join_siege(army, city, edge)
		return
	if state.is_enemy(army.owner_nation, city.owner_nation):
		_start_or_join_siege(army, city, edge)
		return

	# 中立国不提供通行权；盟国允许穿越和临时驻留。
	if not state.has_military_access(army.owner_nation, city.owner_nation):
		army.move_from = arrived
		army.move_to = -1
		army.location_city = arrived
		army.path.clear()
		_retreat_to_friendly(army)
		return

	# 本国/盟国城市且无围城：继续下一段或驻扎。
	army.move_from = arrived
	army.move_to = -1
	army.location_city = arrived
	if army.path.is_empty():
		_settle_idle(army, arrived)
	else:
		_begin_next_leg(army)


func _is_travelling(army: Army) -> bool:
	return army.state in [Army.State.MOVING, Army.State.RETREATING]


func _is_edge_unit(army: Army) -> bool:
	return army.state in [Army.State.MOVING, Army.State.RETREATING, Army.State.HOLDING]


## 检测新遭遇（位置驱动的两两交战）：同边上的敌对军队，按物理位置判断是否接触。
##  - 相向：正向者推进到与反向者接近/交错才触发；相距远则不触发（边内可能不开战）。
##  - 同向：后军追上前军（位置差 <= CONTACT_EPS）才触发（修复"追逐永不开战"）。
## 一条边选归一化位置差最小的敌对接触对为核心，其余按归侧规则加入（第三方不与敌对同侧）。
func _detect_encounters() -> void:
	# 索引进行中的 FIELD 战斗（按边）
	var field_by_edge: Dictionary = {}
	for b in state.battles:
		if not b.finished and b.kind == Battle.Kind.FIELD and b.edge != null:
			field_by_edge[_edge_key_of(b.edge.city_a, b.edge.city_b)] = b

	# 按边聚合普通行军、溃逃军与驻防军。只有 MOVING 可主动发起接战。
	var by_edge: Dictionary = {}
	for army in state.armies:
		if not _is_edge_unit(army) or army.size <= 0 or army.move_to == -1:
			continue
		var key := _edge_key_of(army.move_from, army.move_to)
		if not by_edge.has(key):
			by_edge[key] = []
		by_edge[key].append(army)

	var keys := by_edge.keys()
	keys.sort_custom(func(a, b) -> bool:
		var group_a: Array = by_edge[a]
		var group_b: Array = by_edge[b]
		var edge_a := state.edge_of(
			(group_a[0] as Army).move_from,
			(group_a[0] as Army).move_to
		)
		var edge_b := state.edge_of(
			(group_b[0] as Army).move_from,
			(group_b[0] as Army).move_to
		)
		return EquivariantOrder.mirror_orbit_edge_less(
			state,
			edge_a,
			edge_b
		)
	)
	for key in keys:
		var group: Array = by_edge[key]
		group.sort_custom(func(x: Army, y: Army) -> bool:
			return EquivariantOrder.mirror_orbit_army_less(
				state,
				x,
				y
			)
		)
		var edge := state.edge_of(group[0].move_from, group[0].move_to)
		if edge == null:
			continue

		# 已有战斗：先按回合开始时冻结的战线位置筛出全部抵达者，再统一加入。
		# 逐支边判边加会让先加入者移动 contact_dist，进而改变后续军队资格，
		# 把 group 遍历顺序泄漏成同日“级联增援”。
		if field_by_edge.has(key):
			var existing: Battle = field_by_edge[key]
			var arrivals: Array[Army] = []
			for army in group:
				if (
					not existing.has_army(army)
					and _can_join_field_contact(
						army,
						existing,
						edge
					)
				):
					arrivals.append(army)
			for army in arrivals:
				_join_field_battle(existing, army, edge)
			continue

		if group.size() < 2:
			continue

		# 在所有「敌对且已接触」的对中选交战核心。主判据=归一化位置差 gap 最小（物理逼近程度）。
		# gap 相等时按纯物理/稳定身份判据裁决，绝不依赖 army.id 或遍历顺序（item 11 验收）：
		#   次判据=双方合计兵力更大者优先（更决定性的对撞先形成核心，镜像不变量）；
		#   再相等=镜像轨道上的实体物理键较小者优先。
		var best_x: Army = null
		var best_y: Army = null
		var best_gap := INF
		var best_size := -1
		var best_ambiguous := false
		var best_equivalent_contacts := {}
		for i in range(group.size()):
			for j in range(i + 1, group.size()):
				var x: Army = group[i]
				var y: Army = group[j]
				if x.state == Army.State.RETREATING and y.state == Army.State.RETREATING:
					continue   # 仅两支溃逃军都无主动交战意图；驻防军可截击溃逃军
				if not state.is_enemy(x.owner_nation, y.owner_nation):
					continue
				if not _edge_contact(x, y, edge):
					continue
				var gap := absf(_norm_pos(x, edge) - _norm_pos(y, edge))
				var psize := x.size + y.size
				# 词典序 argmin：gap 升 → 合计兵力降 → 镜像轨道实体键升。
				var better := false
				if best_x == null:
					better = true
				elif not is_equal_approx(gap, best_gap):
					better = gap < best_gap
				elif psize != best_size:
					better = psize > best_size
				else:
					better = EquivariantOrder.encounter_pair_less(
						state,
						x,
						y,
						best_x,
						best_y
					)
					if (
						not better
						and EquivariantOrder.encounter_pair_equivalent(
							state,
							x,
							y,
							best_x,
							best_y
						)
					):
						best_ambiguous = true
						var equivalent_contact := (
							_norm_pos(x, edge)
							+ _norm_pos(y, edge)
						) * 0.5
						for equivalent_army in [x, y]:
							if not best_equivalent_contacts.has(
								equivalent_army
							):
								best_equivalent_contacts[
									equivalent_army
								] = []
							best_equivalent_contacts[
								equivalent_army
							].append(equivalent_contact)
				if better:
					best_gap = gap
					best_size = psize
					best_x = x
					best_y = y
					best_ambiguous = false
					var best_contact := (
						_norm_pos(x, edge)
						+ _norm_pos(y, edge)
					) * 0.5
					best_equivalent_contacts = {
						x: [best_contact],
						y: [best_contact],
					}
		if best_x == null:
			continue   # 本边无满足接触的敌对对 → 不开战（"边内可能不触发"）
		if best_ambiguous:
			# 两个核心对在全部可观察物理键上完全同构时，不存在既确定
			# 又镜像等变的二选一。冻结在共同接触面，等待外部状态打破
			# 对称；不能读取数组顺序任取一对，也不能让军队继续穿透。
			for army in best_equivalent_contacts:
				var contacts: Array = best_equivalent_contacts[army]
				contacts.sort()
				var frozen_norm := 0.0
				for contact in contacts:
					frozen_norm += float(contact)
				frozen_norm /= float(maxi(contacts.size(), 1))
				army.move_progress = (
					frozen_norm
					if army.move_from == edge.city_a
					else 1.0 - frozen_norm
				)
				army.encounter_blocked = true
			continue

		var length := float(maxi(edge.distance, 1))
		var battle := state.new_battle(Battle.Kind.FIELD)
		battle.edge = edge
		battle.contact_dist_a = _norm_pos(best_x, edge) * length
		battle.contact_dist_b = _norm_pos(best_y, edge) * length
		if best_x.state == Army.State.HOLDING:
			battle.holding_side = 1
			battle.holding_days = float(best_x.holding_days)
		elif best_y.state == Army.State.HOLDING:
			battle.holding_side = 2
			battle.holding_days = float(best_y.holding_days)
		_enter_battle(battle, best_x, 1)
		_enter_battle(battle, best_y, 2)
		# 首日其余军队也必须按核心对刚建立时的冻结战线批量判定，
		# 不能让先加入者改变后续军队的抵达资格。
		var initial_arrivals: Array[Army] = []
		for army in group:
			if (
				not battle.has_army(army)
				and _can_join_field_contact(
					army,
					battle,
					edge
				)
			):
				initial_arrivals.append(army)
		for army in initial_arrivals:
			_join_field_battle(battle, army, edge)


## 增援抵达判定（item 4）：任何军队（含 MOVING）加入一场进行中的战斗，都必须已行进到
## 距「己方战线」归一化距离 <= REINFORCEMENT_RADIUS 才算抵达战场；否则继续行军（eta 未到）。
## 归侧战线：与本军同 nation 的一侧的 contact_dist（同国增援从己方后方接近己方战线）。
## 若无法判定同侧（第三国/两侧皆异族），取两战线中较近者兜底（一般由 _block_passthrough 拦截）。
func _can_join_field_contact(army: Army, battle: Battle, edge: Edge) -> bool:
	var length := float(maxi(edge.distance, 1))
	var my_norm := _norm_pos(army, edge)
	var line_a := clampf(battle.contact_dist_a / length, 0.0, 1.0)
	var line_b := clampf(battle.contact_dist_b / length, 0.0, 1.0)
	var na := battle.side_a[0].owner_nation if not battle.side_a.is_empty() else -1
	var nb := battle.side_b[0].owner_nation if not battle.side_b.is_empty() else -1
	var my_line := -1.0
	if army.owner_nation == na:
		my_line = line_a
	elif army.owner_nation == nb:
		my_line = line_b
	if my_line >= 0.0:
		return absf(my_norm - my_line) <= REINFORCEMENT_RADIUS
	return minf(absf(my_norm - line_a), absf(my_norm - line_b)) <= REINFORCEMENT_RADIUS


## 军队在边上「以 city_a 为原点」的归一化位置 ∈ [0,1]。
func _norm_pos(army: Army, edge: Edge) -> float:
	if army.move_from == edge.city_a:
		return clampf(army.move_progress, 0.0, 1.0)
	return clampf(1.0 - army.move_progress, 0.0, 1.0)


## 军队在边上的行进方向（+1: city_a→city_b；-1: 反向）。
func _edge_dir(army: Army, edge: Edge) -> int:
	return 1 if army.move_from == edge.city_a else -1


## 两军是否已在边上接触（可触发战斗）。
##  - 相向（方向相异）：正向者位置 >= 反向者位置 - EPS（接近或已交错）。
##  - 同向（方向相同）：位置差 <= EPS（后军追上前军）。
func _edge_contact(x: Army, y: Army, edge: Edge) -> bool:
	var px := _norm_pos(x, edge)
	var py := _norm_pos(y, edge)
	if _edge_dir(x, edge) == _edge_dir(y, edge):
		return absf(px - py) <= CONTACT_EPS
	var plus_pos := px if _edge_dir(x, edge) > 0 else py
	var minus_pos := py if _edge_dir(x, edge) > 0 else px
	return plus_pos >= minus_pos - CONTACT_EPS


## 敌占交战点卡位：任何 MOVING 军队若逼近同边上一场进行中 FIELD 战斗的交战线、
## 且与该战斗任一方敌对，则被冻结在交战线位置待机（不得穿过）。待该战斗结束后，
## 下一 tick 由 _detect_encounters 让其与幸存者开战——实现「同点必战、串行化」。
## （同 nation 军队不卡位——它们由 _join_field_battle 直接并入本侧。）
func _block_passthrough() -> void:
	for battle in state.battles:
		if battle.finished or battle.kind != Battle.Kind.FIELD or battle.edge == null:
			continue
		var edge := battle.edge
		var length := float(maxi(edge.distance, 1))
		var line_norm := clampf(maxf(battle.contact_dist_a, battle.contact_dist_b) / length, 0.0, 1.0)
		var na := battle.side_a[0].owner_nation if not battle.side_a.is_empty() else -1
		var nb := battle.side_b[0].owner_nation if not battle.side_b.is_empty() else -1
		for army in state.armies:
			if not _is_travelling(army) or army.size <= 0 or army.move_to == -1:
				continue
			if battle.has_army(army):
				continue
			if _edge_key_of(army.move_from, army.move_to) != _edge_key_of(edge.city_a, edge.city_b):
				continue
			# 同 nation 交给 _join_field_battle 处理；此处只卡「敌对且未并入」的第三国
			if army.owner_nation == na or army.owner_nation == nb:
				continue
			if not (state.is_enemy(army.owner_nation, na) or state.is_enemy(army.owner_nation, nb)):
				continue
			var my_norm := _norm_pos(army, edge)
			if absf(my_norm - line_norm) > CONTACT_EPS:
				continue
			# 卡位：夹到交战线前沿，冻结推进（保持 MOVING，下一 tick 待幸存者再战）。
			# 夹取用 min(现值) 避免把尚未抵达的军队「前拉」，只阻止越过、不瞬移。
			if army.move_from == edge.city_a:
				army.move_progress = clampf(line_norm, 0.0, army.move_progress)
			else:
				army.move_progress = clampf(1.0 - line_norm, 0.0, army.move_progress)


## 攻城入口：A 抵达被围/敌方城。规则：一城至多一个「围城 nation」占 side_a（不允许敌对他国并肩）。
##  - 无既有围城：有守军→建带守军 SIEGE；空城→建纯围城 SIEGE（side_b 空，累积破城）。
##  - 既有围城且与围城方同 nation：并入 side_a（多路攻城汇合）。
##  - 既有围城且与围城方敌对：
##     · 守军仍在(side_b 被守军占)：与守军同族者(城主援军)→入城帮守并入 side_b；真第三国→撤回友城。
##     · 纯围城阶段(守军已歼/空城)：进 side_b 与围城方城下决斗（城主援军解围亦走此路，修复"回援不触发"）。
func _start_or_join_siege(attacker: Army, city: City, edge: Edge) -> void:
	var siege := _siege_battle_of(city)
	if siege == null and not state.is_enemy(attacker.owner_nation, city.owner_nation):
		_retreat_to_friendly(attacker)
		return
	if siege != null and not siege.side_a.is_empty():
		var besieger := siege.side_a[0].owner_nation
		if (
			attacker.owner_nation != besieger
			and not state.is_enemy(attacker.owner_nation, besieger)
		):
			_retreat_to_friendly(attacker)
			return
	if siege == null:
		var defenders := (
			state.armies_available_to_defend_city(city.id)
		)
		if (
			defenders.is_empty()
			and state.recognized_owner_of(city.id)
				== attacker.owner_nation
		):
			_capture_city(
				attacker,
				city,
				attacker.owner_nation
			)
			return
		# item 7：不再设机制层「弱攻自动撤离」硬门槛——兵力不足时围城进度会按连续曲线
		# 停滞/倒退（见 _advance_siege），是否撤离交 AI 战略层裁量，避免攻/撤无限循环。
		siege = state.new_battle(Battle.Kind.SIEGE)
		siege.edge = edge
		siege.city = city
		_mark_city_war_disruption(city)
		var length := float(maxi(edge.distance, 1))
		siege.contact_dist_a = length   # 围城方在城墙 dist=L（端点，无地形惩罚）
		siege.contact_dist_b = 0.0      # 守军城中 dist=0（端点，无地形惩罚）
		if not defenders.is_empty():
			for defender in defenders:
					_enter_battle(siege, defender, 2)
			siege.has_garrison = true
		# 破城所需兵力仅由工事强度换算（item 6：不含守军人数，守军是城下决斗阶段的对手）。
		# 有无守军该值一致，消除数量级跳变；守军被歼后此值不变（城防来自 fort_strength）。
		siege.siege_required = Combat.siege_required_manpower(city.fort_strength)
		_enter_battle(siege, attacker, 1)
		return

	# 既有围城
	var besieger_nation: int = siege.side_a[0].owner_nation if not siege.side_a.is_empty() else attacker.owner_nation
	if attacker.owner_nation == besieger_nation:
		_enter_battle(siege, attacker, 1)   # 与围城方同 nation：多路汇合
		return
	# 到此 attacker 与围城方敌对
	if siege.has_garrison and siege.side_size(siege.side_b) > 0:
		# 守军仍在城中：与守军同族的城主援军入城帮守（并入 side_b，享城防加成）；
		# 真第三国无处容身（三方不可共存）→ 从目标城沿道路撤回友城。
		var defender_nation: int = siege.side_b[0].owner_nation
		if attacker.owner_nation == defender_nation:
			_enter_battle(siege, attacker, 2)
			return
		_retreat_to_friendly(attacker)
		return
	# 纯围城阶段：A 进 side_b 与围城方城下决斗（城主援军解围 / 敌对他国抢城均走此路）
	if not siege.side_b.is_empty() and siege.side_b[0].owner_nation != attacker.owner_nation:
		# side_b 已被另一挑战 nation 占据（罕见四方），A 从已抵达的城节点撤回最近友城。
		_retreat_to_friendly(attacker)
		return
	_enter_battle(siege, attacker, 2)


## 对每场进行中的战斗推进一个 tick：FIELD 打一回合；SIEGE 走专用状态机（守军歼灭≠破城）。
func _resolve_battles() -> void:
	# item 8：每 tick 只消费一次共享战场骰与一次战术熵。各战斗/各侧修正由物理指纹纯函数派生，
	# 不依赖 battle 数组顺序，也不会因军队拆分增加随机消费次数。
	var shared_roll := state.rng.randi_range(Combat.DICE_MIN, Combat.DICE_MAX)
	var tactical_entropy := int(state.rng.randi())
	for battle in state.battles:
		if battle.finished:
			continue
		if battle.kind == Battle.Kind.SIEGE:
			_advance_siege(
				battle,
				shared_roll,
				tactical_entropy
			)
		else:
			_resolve_combat_round(
				battle,
				shared_roll,
				tactical_entropy
			)
			if battle.finished:
				_finish_field_battle(battle)
	state.battles = state.battles.filter(func(b: Battle) -> bool: return not b.finished)


func _resolve_combat_round(
	battle: Battle,
	shared_roll: int,
	tactical_entropy: int
) -> void:
	_refresh_battle_frontline_priorities(battle)
	Combat.resolve_round(
		battle,
		state.rng,
		shared_roll,
		tactical_entropy,
		state.day
	)
	# Combat 只负责判定单军溃退并从战斗侧移出；Simulation 拥有路径与边占用，
	# 因此在同一回合立即从真实战场位置启动撤退。
	for army in battle.routed_a:
		if army.size > 0:
			_retreat(army)
		else:
			army.battle_id = -1
	for army in battle.routed_b:
		if army.size <= 0:
			army.battle_id = -1
		elif (
			battle.kind == Battle.Kind.SIEGE
			and battle.has_garrison
			and battle.city != null
			and army.owner_nation == battle.city.owner_nation
		):
			_retreat_defender(army, battle.city)
		else:
			_retreat(army)


func _refresh_battle_frontline_priorities(battle: Battle) -> void:
	var anchor_city := (
		battle.city.id
		if battle.city != null
		else -1
	)
	_fill_battle_frontline_priority(
		battle.side_a,
		battle.frontline_priority_a,
		anchor_city
	)
	_fill_battle_frontline_priority(
		battle.side_b,
		battle.frontline_priority_b,
		anchor_city
	)


func _fill_battle_frontline_priority(
	side: Array[Army],
	priority: Dictionary,
	anchor_city: int
) -> void:
	priority.clear()
	if side.is_empty():
		return
	var nation_id := side[0].owner_nation
	var ordered: Array[Army] = side.duplicate()
	ordered.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(
			state,
			nation_id,
			a,
			b,
			anchor_city
		)
	)
	for index in range(ordered.size()):
		priority[ordered[index]] = index


func _mark_city_war_disruption(city: City) -> void:
	city.war_disruption_until_day = maxi(
		city.war_disruption_until_day,
		state.day + CITY_WAR_DISRUPTION_DAYS
	)


## SIEGE 状态机（每天一 tick）。三阶段：
##  1) 守军抵抗：resolve_round 削守军。守军歼灭≠破城——转纯围城；攻方溃则围城失败。
##  2) 城下决斗：side_b 为敌对挑战者（无城防加成），分胜负后胜方独占围城。
##  3) 纯围城：无对抗，掷骰累积 siege_progress，达阈值破城易主。
func _advance_siege(
	battle: Battle,
	shared_roll: int = -1,
	tactical_entropy: int = -1
) -> void:
	if battle.city != null:
		_mark_city_war_disruption(battle.city)
	battle.prune_dead()
	# 纯围城阶段也必须执行单军溃败阈值；不能因没有正面守军而让失去组织的
	# 围城军无限停留并贡献（哪怕为 0 的）封锁兵力。
	battle.side_a = _withdraw_broken_armies(battle.side_a)
	_reconcile_siege_city_defenders(battle)
	_refresh_battle_frontline_priorities(battle)
	var atk_alive := battle.side_size(battle.side_a) > 0

	# 阶段 1：守军抵抗
	if battle.has_garrison and battle.side_size(battle.side_b) > 0:
		if not atk_alive:
			# 围城方尽墨（多因断粮）→ 守军坚守，围城解除
			for d in battle.side_b:
				d.battle_id = -1
				if d.size > 0:
					_settle_idle(d, battle.city.id)
			battle.finished = true
			battle.winner_side = 2
			return
		_decay_interrupted_siege_progress(battle)
		_resolve_combat_round(
			battle,
			shared_roll,
			tactical_entropy
		)
		if not battle.finished:
			return
		if battle.winner_side != 1:
			# 攻方被守军击退，或双方同时崩溃判平局：进攻方未攻下→守方保城，攻方撤退。
			for a in battle.side_a:
				if a.size > 0:
					_retreat(a)
				else:
					a.battle_id = -1
			for d in battle.side_b:
				d.battle_id = -1
				if d.size > 0:
					_settle_or_recover_after_battle(d, battle.city.id)
			return
		# 守军溃散（winner_side==1）：不占领，清走守军，转纯围城
		for d in battle.side_b:
			if d.size > 0:
				_retreat_defender(d, battle.city)
			else:
				d.battle_id = -1
		battle.side_b.clear()
		battle.has_garrison = false
		battle.side_a = _withdraw_broken_armies(battle.side_a)
		if battle.side_a.is_empty():
			battle.finished = true
			battle.winner_side = 0
			return
		if _finish_legal_reclamation(battle):
			return
		battle.finished = false
		battle.winner_side = 0
		return

	# 阶段 2：城下决斗（side_b 为敌对挑战者，无城防加成）
	if battle.side_size(battle.side_b) > 0:
		if not atk_alive:
			# 围城方尽墨 → 挑战者接管围城
			_promote_challengers(battle)
			return
		_decay_interrupted_siege_progress(battle)
		_resolve_combat_round(
			battle,
			shared_roll,
			tactical_entropy
		)
		if not battle.finished:
			return
		if battle.winner_side == 1:
			# 围城方胜：挑战者撤退，围城继续
			for c in battle.side_b:
				if c.size > 0:
					_retreat(c)
				else:
					c.battle_id = -1
			_reset_empty_battle_side_b(battle)
			battle.side_a = _withdraw_broken_armies(battle.side_a)
			if battle.side_a.is_empty():
				battle.finished = true
				battle.winner_side = 0
				return
			battle.finished = false
			battle.winner_side = 0
		elif battle.winner_side == 0:
			# 平局（双方同时崩溃、续战能力相等）：城下双方都撤退，围城彻底解除，无人占城。
			for c in battle.side_b:
				if c.size > 0:
					_retreat(c)
				else:
					c.battle_id = -1
			for a in battle.side_a:
				if a.size > 0:
					_retreat(a)
				else:
					a.battle_id = -1
			battle.side_a.clear()
			battle.side_b.clear()
			battle.finished = true
			battle.winner_side = 0
		else:
			# 挑战者胜：原围城方撤退
			for a in battle.side_a:
				if a.size > 0:
					_retreat(a)
				else:
					a.battle_id = -1
			battle.side_a.clear()
			# 若胜方为城主（解围成功）→ 入城驻守、围城解除；否则晋升为新围城方继续攻城。
			var challenger_nation: int = battle.side_b[0].owner_nation if not battle.side_b.is_empty() else -1
			if challenger_nation == battle.city.owner_nation:
				for c in battle.side_b:
					c.battle_id = -1
					if c.size > 0:
						_settle_or_recover_after_battle(c, battle.city.id)
				_reset_empty_battle_side_b(battle)
				battle.finished = true
				battle.winner_side = 2
			else:
				_promote_challengers(battle)
		return

	# 阶段 3：纯围城，连续曲线累积破城（item 7：无 5× 硬门槛、无跳变）。
	if not atk_alive:
		battle.finished = true
		battle.winner_side = 0   # 围城方尽墨，无人占领
		return
	# 连续曲线：ratio≥1 正常推进、0.5~1 极慢（部分封锁）、<0.5 缓慢倒退。
	# 不再机制性强制撤离——兵力不足时保持围城/等待援军，去留由 AI 战略层按补给与威胁决策，
	# 避免「机制撤离 ↔ AI 再派」的攻/撤无限循环（item 7 验收）。进度夹在 [0, REQUIRED]。
	var daily_progress := Combat.siege_daily_progress(
		Combat.effective_siege_strength(
			battle.side_a,
			battle.frontline_priority_a
		),
		battle.siege_required
	)
	battle.siege_progress = clampf(
		battle.siege_progress + daily_progress,
		0.0,
		Combat.SIEGE_PROGRESS_REQUIRED
	)
	if battle.siege_progress >= Combat.SIEGE_PROGRESS_REQUIRED:
		var captor := _strongest_alive(battle.side_a)
		if captor != null:
			_capture_city(captor, battle.city)
		for a in battle.side_a:
			a.battle_id = -1
			if a != captor and a.size > 0:
				_settle_idle(a, battle.city.id)
		battle.finished = true
		battle.winner_side = 1


## 围城建立后仍可能有撤退军抵达、恢复军落位等状态转换。每个围城日都重新收集
## 目标城内未参战的本国驻军，确保任何有效守军都先进入战斗，不能被攻城进度跳过。
func _reconcile_siege_city_defenders(battle: Battle) -> void:
	if (
		battle.city == null
		or battle.city.id < 0
		or battle.city.id >= state.cities.size()
		or state.cities[battle.city.id] != battle.city
	):
		return
	var defenders := state.armies_available_to_defend_city(
		battle.city.id
	)
	if defenders.is_empty():
		return
	if (
		not battle.side_b.is_empty()
		and battle.side_b[0].owner_nation != battle.city.owner_nation
	):
		# 第三方已在城下挑战围城方；守军下一日再接续，避免三国混入同一战斗侧。
		return
	for defender in defenders:
		if battle.has_army(defender):
			continue
		_enter_battle(battle, defender, 2)
	if (
		not battle.side_b.is_empty()
		and battle.side_b[0].owner_nation == battle.city.owner_nation
	):
		# 后到守军入城帮守：加入城下决斗消耗攻方，但封锁需求 siege_required 仅由工事决定
		# （item 6：守军不抬高破城门槛），此处无需改动 battle.siege_required。
		battle.has_garrison = true


func _decay_interrupted_siege_progress(battle: Battle) -> void:
	battle.siege_progress = Combat.siege_progress_after_interruption(
		battle.siege_progress
	)


## 挑战者（side_b）接管围城：晋升为围城方（移入 side_a、置城墙位置），围城继续。
func _promote_challengers(battle: Battle) -> void:
	var new_besiegers: Array[Army] = []
	for c in battle.side_b:
		if (
			c.size > 0
			and c.morale > Combat.ARMY_ROUT_THRESHOLD
		):
			new_besiegers.append(c)
		elif c.size > 0:
			_retreat(c)
		else:
			c.battle_id = -1
	battle.side_a = new_besiegers
	battle.tactical_key_a = battle.tactical_key_b
	battle.reinforcement_morale_gained_a = (
		battle.reinforcement_morale_gained_b
	)
	battle.reinforce_fresh_a = battle.reinforce_fresh_b.duplicate()
	battle.frontline_priority_a = (
		battle.frontline_priority_b.duplicate()
	)
	_reset_empty_battle_side_b(battle)
	battle.contact_dist_a = float(maxi(battle.edge.distance, 1)) if battle.edge != null else 0.0
	# 挑战者接管的是纯围城；封锁需求仅由工事决定（item 6，与守军无关），显式重申以自证。
	battle.siege_required = (
		Combat.siege_required_manpower(battle.city.fort_strength)
		if battle.city != null
		else battle.siege_required
	)
	battle.has_garrison = false
	battle.finished = new_besiegers.is_empty()
	battle.winner_side = 0


func _reset_empty_battle_side_b(battle: Battle) -> void:
	battle.side_b.clear()
	battle.reinforce_fresh_b.clear()
	battle.routed_b.clear()
	battle.frontline_priority_b.clear()
	battle.reinforcement_morale_gained_b = 0.0
	battle.tactical_key_b = 0


func _withdraw_broken_armies(side: Array[Army]) -> Array[Army]:
	var active: Array[Army] = []
	for army in side:
		if army.size <= 0:
			army.battle_id = -1
		elif army.morale <= Combat.ARMY_ROUT_THRESHOLD:
			_retreat(army)              # 军队级溃退阈值：彻底失去组织者撤离
		else:
			active.append(army)
	return active


func _settle_or_recover_after_battle(army: Army, city_id: int) -> void:
	if army.morale <= Combat.MORALE_FLOOR:
		_start_morale_retreat_from_city(
			army,
			city_id
		)
	else:
		_settle_idle(army, city_id)


func _finish_field_battle(battle: Battle) -> void:
	# 平局（winner_side==0，双方同时失败且续战能力相等）：双方都脱离战斗撤退，无人占领/追击。
	if battle.winner_side == 0:
		_finish_field([], battle.side_a + battle.side_b)
		return
	var winners: Array[Army] = battle.side_a if battle.winner_side == 1 else battle.side_b
	var losers: Array[Army] = battle.side_b if battle.winner_side == 1 else battle.side_a
	_finish_field(winners, losers)


func _finish_field(winners: Array[Army], losers: Array[Army]) -> void:
	for a in losers:
		if a.size > 0:
			_retreat(a)              # 败方带残兵撤往最近友城
		else:
			a.battle_id = -1
	for a in winners:
		if a.size > 0:
			if a.morale <= Combat.SIDE_ROUT_THRESHOLD:
				_retreat(a)          # 双方同时崩溃时，低士气胜方也不能继续追击
			else:
				_resume_after_battle(a)
		else:
			a.battle_id = -1


## 胜方继续行军：解除 FIGHTING，恢复 MOVING，沿原方向推进（仍占该边）。
func _resume_after_battle(army: Army) -> void:
	if army.forced_retreat:
		army.state = Army.State.RETREATING
	elif army.resume_holding_after_battle:
		var edge := state.edge_of(army.move_from, army.move_to)
		army.state = (
			Army.State.HOLDING
			if edge != null and edge.allows_holding
			else Army.State.MOVING
		)
	else:
		army.state = Army.State.MOVING
	army.resume_holding_after_battle = false
	army.battle_id = -1


## 归侧加入既有 FIELD 战斗（两方制 + 可靠同国聚合）。
## 因 is_enemy 等价「异 nation」：同 side_a 的 nation → 并入 side_a；同 side_b 的 nation → 并入 side_b；
## 与两侧皆异族的第三国不介入（待当前这对分胜负后，下一 tick 再与幸存者接触）。
## 初始「是否开战」由核心对的 _edge_contact 位置判定把关；此处只处理「已开战后同国增援的归并」，
## 故不再要求近邻（修复：同边靠后的同国友军被 CONTACT_EPS 漏掉而无法聚合）。
func _join_field_battle(battle: Battle, army: Army, edge: Edge) -> void:
	if battle.side_a.is_empty() or battle.side_b.is_empty():
		return
	var na := battle.side_a[0].owner_nation
	var nb := battle.side_b[0].owner_nation
	var target := 0
	if army.owner_nation == na:
		target = 1
	elif army.owner_nation == nb:
		target = 2
	else:
		return
	if battle.holding_side == target:
		var side_before: Array[Army] = battle.side_a if target == 1 else battle.side_b
		var old_size := 0
		for member in side_before:
			if member.size > 0:
				old_size += member.size
		var new_total := old_size + maxi(army.size, 0)
		if new_total > 0:
			var newcomer_days := float(army.holding_days) if army.state == Army.State.HOLDING else 0.0
			battle.holding_days = (
				battle.holding_days * float(old_size)
				+ newcomer_days * float(maxi(army.size, 0))
			) / float(new_total)
	var my_norm := _norm_pos(army, edge)
	var length := float(maxi(edge.distance, 1))
	var my_distance := my_norm * length
	var own_line := (
		battle.contact_dist_a
		if target == 1
		else battle.contact_dist_b
	)
	var enemy_line := (
		battle.contact_dist_b
		if target == 1
		else battle.contact_dist_a
	)
	var advances_front := (
		absf(my_distance - enemy_line)
		< absf(own_line - enemy_line)
	)
	_enter_battle(battle, army, target)
	if target == 1:
		if advances_front:
			battle.contact_dist_a = my_distance
		battle.reinforce_fresh_a.append(army)
	else:
		if advances_front:
			battle.contact_dist_b = my_distance
		battle.reinforce_fresh_b.append(army)
	# 增援集结：登记为本 tick 新援军，士气提振在下一次 resolve_round 统一结算（防拆分套利 item 12）。


func _enter_battle(battle: Battle, army: Army, side: int) -> void:
	if battle.kind == Battle.Kind.FIELD and army.state == Army.State.HOLDING:
		army.resume_holding_after_battle = true
	army.state = Army.State.FIGHTING
	army.encounter_blocked = false
	army.battle_id = battle.id
	if side == 1:
		if battle.side_a.is_empty():
			battle.tactical_key_a = (
				EquivariantOrder.tactical_side_key(state, army)
			)
		battle.side_a.append(army)
	else:
		if battle.side_b.is_empty():
			battle.tactical_key_b = (
				EquivariantOrder.tactical_side_key(state, army)
			)
		battle.side_b.append(army)


func _strongest_alive(arr: Array[Army]) -> Army:
	var best: Army = null
	for a in arr:
		if a.size > 0 and (best == null or a.size > best.size):
			best = a
	return best


func _siege_battle_of(city: City) -> Battle:
	for b in state.battles:
		if not b.finished and b.kind == Battle.Kind.SIEGE and b.city == city:
			return b
	return null


## 守军战败后排除正在失守的城市，撤向距离最近的其他友方城市。
func _retreat_defender(defender: Army, city: City) -> void:
	_start_morale_retreat_from_city(defender, city.id, city.id)

# ------------------------------------------------------------------ 5. 占领

func _finish_legal_reclamation(battle: Battle) -> bool:
	if (
		battle.city == null
		or battle.side_a.is_empty()
	):
		return false
	var captor := _strongest_alive(battle.side_a)
	if (
		captor == null
		or state.recognized_owner_of(battle.city.id)
			!= captor.owner_nation
	):
		return false
	_capture_city(
		captor,
		battle.city,
		captor.owner_nation
	)
	for attacker in battle.side_a:
		attacker.battle_id = -1
		if attacker != captor and attacker.size > 0:
			_settle_idle(attacker, battle.city.id)
	battle.finished = true
	battle.winner_side = 1
	return true


func _capture_city(
	army: Army,
	city: City,
	owner_override: int = -1
) -> void:
	var old_owner := city.owner_nation
	var claimant := (
		owner_override
		if owner_override >= 0
		else _occupation_claimant_for_army(army)
	)
	var captured_food := city.food_storage if city.has_warehouse else 0
	var old_owner_valid := old_owner >= 0 and old_owner < state.nations.size()
	var captured_capital := old_owner_valid and state.nations[old_owner].capital_city_id == city.id
	if city.has_warehouse and old_owner_valid:
		state.remove_warehouse(old_owner, city.id)
	else:
		city.is_capital = false
		city.has_warehouse = false
	city.food_storage = 0
	city.owner_nation = claimant
	city.occupation_sponsor_nation = (
		-1
		if state.recognized_owner_of(city.id) == claimant
		else army.owner_nation
	)
	state.ownership_revision += 1
	# 控制区变化会重塑双方边境防区；下一日立即重建，不等待十日常规 AI 周期。
	_ai_last_decision_day = -1
	if claimant != old_owner:
		city.fort_strength_max = maxi(
			city.fort_strength_max,
			city.fort_strength
		)
		city.fort_last_capture_day = state.day
		city.fort_strength = city_fort_strength_after_capture(
			city.fort_strength_max,
			0
		)
	if captured_capital:
		state.relocate_capital(old_owner)
	var spoils := int(floor(float(captured_food) * CAPITAL_FOOD_CAPTURE_RATE))
	state.deposit_food(claimant, spoils)
	# 城市易主后，所有不再拥有通行权且尚未离开城市节点的军队都必须撤退。
	# 覆盖 IDLE/RECOVERING、容量阻塞的 MOVING/RETREATING 以及残留 FIGHTING 状态。
	for displaced in state.armies:
		if displaced == army or displaced.size <= 0:
			continue
		if not displaced.is_at_city_node(city.id):
			continue
		if state.has_military_access(
			displaced.owner_nation,
			claimant
		):
			continue
		_start_morale_retreat_from_city(
			displaced,
			city.id,
			city.id
		)
	army.state = Army.State.IDLE
	army.forced_retreat = false
	army.battle_id = -1
	army.location_city = city.id
	army.move_from = city.id
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()
	army.occupation_claimant_nation = -1
	_execute_campaign_post_capture_plan(army, city)


func _execute_campaign_post_capture_plan(
	army: Army,
	city: City
) -> void:
	if (
		army.owner_nation < 0
		or army.owner_nation >= state.nations.size()
		or city == null
	):
		return
	var nation := state.nations[army.owner_nation]
	if not nation.campaign_post_capture_plans.has(city.id):
		return
	var plan: Dictionary = (
		nation.campaign_post_capture_plans[city.id]
	)
	var preparation_days := int(
		plan.get("preparation_days", 0)
	)
	if preparation_days < OFFENSIVE_BONUS_MAX_PREPARATION_DAYS:
		nation.campaign_post_capture_plans.erase(city.id)
		return
	if state.day >= int(plan.get("expires_day", -1)):
		nation.campaign_post_capture_plans.erase(city.id)
		return
	nation.campaign_post_capture_plans.erase(city.id)
	var view := _build_ai_view(army.owner_nation)
	var threat := ThreatField.build(
		view,
		_threat_travel_cache
	)
	var stationed_without_captor := view.stationed_power_at(
		city.id,
		army
	)
	var required_garrison := (
		threat.threat_at(city.id)
		* CAMPAIGN_POST_CAPTURE_DEFENSE_RATIO
	)
	var next_step := _campaign_post_capture_target(
		army,
		city,
		threat
	)
	var bonus_active := (
		army.offensive_attack_multiplier > 1.0
		and army.offensive_bonus_until_day > state.day
	)
	if (
		not next_step.is_empty()
		and bonus_active
		and army.morale >= CAMPAIGN_POST_CAPTURE_MORALE_MIN
		and army.supply_ratio >= CAMPAIGN_POST_CAPTURE_SUPPLY_MIN
		and stationed_without_captor >= required_garrison
		and float(next_step["attack_ratio"])
			>= _campaign_attack_ratio_threshold(
				army.owner_nation
			)
	):
		var next_city := int(next_step["city_id"])
		var attack := ActionCandidate.make(
			ActionCandidate.Kind.ATTACK,
			2500.0 + float(next_step["score"]),
			(
				"满准备攻势第二阶段：城市%d已占领且守备充足，"
				+ "保留剩余加成立即攻击城市%d（战力比%.2f）"
			) % [
				city.id,
				next_city,
				next_step["attack_ratio"],
			],
			next_city
		)
		attack.minimum_commit_days = (
			CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		)
		if _execute_ai_candidate(army, attack):
			return
	if (
		not next_step.is_empty()
		and army.morale >= 0.50
		and army.supply_ratio >= 0.50
		and (
			stationed_without_captor
			+ ArmyPower.effective(army)
		) >= required_garrison
	):
		var border_city := int(next_step["city_id"])
		var hold := ActionCandidate.make(
			ActionCandidate.Kind.HOLD,
			2200.0 + float(next_step["score"]),
			(
				"满准备攻势第二阶段：城市%d已占领，"
				+ "主力前出驻守通往城市%d的边界"
			) % [city.id, border_city],
			border_city
		)
		hold.minimum_commit_days = (
			CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		)
		hold.defensive_deployment = true
		hold.target_edge_a = city.id
		hold.target_edge_b = border_city
		if _execute_ai_candidate(army, hold):
			return
	var garrison := ActionCandidate.make(
		ActionCandidate.Kind.HOLD,
		2000.0,
		(
			"满准备攻势第二阶段：城市%d守备不足，"
			+ "主力就地驻扎巩固占领"
		) % city.id,
		city.id
	)
	garrison.minimum_commit_days = DEFENSIVE_DEPLOYMENT_LOCK_DAYS
	garrison.defensive_deployment = true
	_record_ai_order(army, garrison)


func _campaign_post_capture_target(
	army: Army,
	city: City,
	threat: ThreatField
) -> Dictionary:
	var best: Dictionary = {}
	var neighbors := state.neighbors(city.id).duplicate()
	EquivariantOrder.sort_city_ids(
		neighbors,
		state,
		army.owner_nation,
		city.id
	)
	for target_id in neighbors:
		var edge := state.edge_of(city.id, target_id)
		if (
			edge == null
			or edge.max_manpower < army.max_size
			or not state.is_enemy(
				army.owner_nation,
				state.cities[target_id].owner_nation
			)
		):
			continue
		var target := state.cities[target_id]
		var defense_power := (
			threat.threat_at(target_id)
			+ ArmyPower.city_defense(target)
		)
		var attack_ratio := (
			ArmyPower.effective(army)
			/ maxf(defense_power, 1.0)
		)
		var strategic_value := (
			float(target.gold_per_month) * 0.10
			+ float(target.food_per_half_year) * 0.002
			+ float(target.manpower_per_month) * 0.10
			+ (5.0 if target.is_capital else 0.0)
			+ (3.0 if target.has_warehouse else 0.0)
			+ (2.0 if target.is_food_hub else 0.0)
			+ (2.0 if target.is_manpower_hub else 0.0)
		)
		var score := attack_ratio * 4.0 + strategic_value
		if (
			best.is_empty()
			or score > float(best["score"])
			or (
				is_equal_approx(score, float(best["score"]))
				and EquivariantOrder.city_id_less(
					state,
					army.owner_nation,
					target_id,
					int(best["city_id"]),
					city.id
				)
			)
		):
			best = {
				"city_id": target_id,
				"attack_ratio": attack_ratio,
				"defense_power": defense_power,
				"score": score,
			}
	return best


func _occupation_claimant_for_army(army: Army) -> int:
	if (
		army.occupation_claimant_nation >= 0
		and army.occupation_claimant_nation
			< state.nations.size()
	):
		return army.occupation_claimant_nation
	var origin_city := army.move_from
	if origin_city < 0 or origin_city >= state.cities.size():
		origin_city = army.location_city
	if origin_city >= 0 and origin_city < state.cities.size():
		var origin_owner := state.cities[origin_city].owner_nation
		if (
			origin_owner == army.owner_nation
			or state.is_allied(
				army.owner_nation,
				origin_owner
			)
		):
			return origin_owner
	return army.owner_nation

# ------------------------------------------------------------------ 6. 战争状态刷新

func _refresh_war_flags() -> void:
	# 边 occupied 由 passing_count 决定
	for e in state.edges:
		e.occupied = e.passing_count > 0
	# 城 at_war：与任一相邻敌国城市接壤。
	for city in state.cities:
		var war := false
		for nb in state.neighbors(city.id):
			if state.is_enemy(
				city.owner_nation,
				state.cities[nb].owner_nation
			):
				war = true
				break
		city.at_war = war

# ------------------------------------------------------------------ 7. 胜负

func _check_victory() -> void:
	var alive_nations: Array[int] = []
	for n in state.nations:
		var has_city := false
		for city in state.cities:
			if city.owner_nation == n.id:
				has_city = true
				break
		n.alive = has_city
		if has_city:
			alive_nations.append(n.id)
	if alive_nations.size() == 1:
		state.winner = alive_nations[0]
		paused = true

# ================================================================== 工具

func _settle_idle(army: Army, city_id: int) -> void:
	if (
		city_id >= 0
		and city_id < state.cities.size()
		and not state.has_military_access(
			army.owner_nation,
			state.cities[city_id].owner_nation
		)
	):
		_start_morale_retreat_from_city(
			army,
			city_id,
			city_id
		)
		return
	_release_edge(army)   # 无条件释放：仅当 on_edge 为真才实际减计数
	army.state = Army.State.IDLE
	army.forced_retreat = false
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.battle_id = -1
	army.location_city = city_id
	army.move_from = city_id
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()


## 士气崩溃撤退：从真实交战位置选择图距离最近的友方城市。
func _retreat(army: Army) -> void:
	army.battle_id = -1
	army.state = Army.State.RETREATING
	army.forced_retreat = true
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.path.clear()
	if army.on_edge and army.move_to != -1:
		var route := Pathfinding.nearest_friendly_route_from_edge(state, army)
		if route.is_empty():
			_release_edge(army)
			army.size = 0
			return
		var endpoint: int = route["endpoint"]
		var old_from := army.move_from
		var old_to := army.move_to
		var old_progress := clampf(army.move_progress, 0.0, 1.0)
		if endpoint == old_from:
			# 原地掉头：交换边方向并反转 progress，像素位置保持不变。
			army.move_from = old_to
			army.move_to = old_from
			army.move_progress = 1.0 - old_progress
		else:
			army.move_from = old_from
			army.move_to = old_to
			army.move_progress = old_progress
		army.location_city = endpoint
		army.path = route["path"]
		return
	var current_city := army.move_to if army.move_to != -1 else army.move_from
	if current_city == -1:
		current_city = army.location_city
	_start_morale_retreat_from_city(army, current_city)


## 从城市节点开始撤退。excluded_city_id 常用于排除正在失守/被围的当前城。
func _start_morale_retreat_from_city(
	army: Army,
	current_city: int,
	excluded_city_id: int = -1
) -> void:
	_release_edge(army)
	army.battle_id = -1
	army.state = Army.State.RETREATING
	army.forced_retreat = true
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.location_city = current_city
	army.move_from = current_city
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()
	if current_city < 0 or current_city >= state.cities.size():
		army.size = 0
		return
	if _annihilate_encircled_zero_morale_army(
		army,
		current_city
	):
		return
	if (
		current_city != excluded_city_id
		and state.has_military_access(
			army.owner_nation,
			state.cities[current_city].owner_nation
		)
	):
		_start_recovering(army, current_city)
		return
	var path := Pathfinding.nearest_friendly_city(
		state,
		army,
		excluded_city_id
	)
	if path.is_empty():
		army.size = 0   # 已无可达友城：溃散
		return
	army.path = path
	_begin_next_leg(army)


func _start_recovering(army: Army, city_id: int) -> void:
	if (
		city_id >= 0
		and city_id < state.cities.size()
		and not state.has_military_access(
			army.owner_nation,
			state.cities[city_id].owner_nation
		)
	):
		_start_morale_retreat_from_city(
			army,
			city_id,
			city_id
		)
		return
	_release_edge(army)
	army.state = Army.State.RECOVERING
	army.forced_retreat = true
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.battle_id = -1
	army.location_city = city_id
	army.move_from = city_id
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()


func _annihilate_encircled_zero_morale_army(
	army: Army,
	city_id: int
) -> bool:
	if (
		army == null
		or army.size <= 0
		or army.morale > Combat.MORALE_FLOOR
		or Pathfinding.has_friendly_retreat_route_from_city(
			state,
			army.owner_nation,
			city_id,
			army.max_size
		)
	):
		return false
	_release_edge(army)
	army.battle_id = -1
	army.path.clear()
	army.size = 0
	return true


func _start_holding(army: Army) -> void:
	if not army.on_edge or army.move_to == -1:
		return
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge == null or not edge.allows_holding:
		army.state = Army.State.MOVING
		army.hold_target_progress = -1.0
		army.holding_days = 0
		army.resume_holding_after_battle = false
		return
	army.state = Army.State.HOLDING
	army.forced_retreat = false
	army.hold_target_progress = -1.0
	army.holding_days = 0
	army.path.clear()


func _leave_holding(army: Army) -> void:
	if army.state != Army.State.HOLDING:
		return
	army.state = Army.State.MOVING
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false


## 从无法加入的围城节点向最近友城强制撤离。army 已抵达目标城且当前边已释放；
## RETREATING 保证它不受 AI 改写，并可立即离开敌城而不受友方方向容量阻塞。
func _retreat_to_friendly(army: Army) -> void:
	var arrived := army.move_to
	army.move_from = arrived if arrived != -1 else army.move_from
	army.move_to = -1
	army.move_progress = 0.0
	army.state = Army.State.RETREATING
	army.forced_retreat = true
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.location_city = army.move_from
	var path := Pathfinding.nearest_friendly_city(state, army)
	if path.is_empty():
		# 无合法本国通道时不能滞留敌城或穿越敌城，按无路可退处理为溃散。
		army.size = 0
		return
	army.path = path
	_begin_next_leg(army)


## 释放该军占用的边通行槽。以 army.on_edge 为唯一判据，幂等（重复调用安全）。
func _release_edge(army: Army) -> void:
	army.encounter_blocked = false
	if not army.on_edge:
		return
	army.on_edge = false
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge != null and edge.passing_count > 0:
		edge.passing_count -= 1
		edge.occupied = edge.passing_count > 0


func _edge_key_of(a: int, b: int) -> int:
	return GameState.edge_key(a, b)


## 移除 size<=0 的军队，并释放它们占用的边。
func _purge_dead_armies() -> void:
	var survivors: Array[Army] = []
	for army in state.armies:
		if army.size > 0:
			survivors.append(army)
		else:
			_release_edge(army)   # 幂等释放
	state.armies = survivors
