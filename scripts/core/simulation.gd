class_name Simulation
extends Node
## 模拟系统：实时驱动时间，按天推进全部游戏逻辑（行军/战斗/占领每天；经济/粮食/士气恢复每月结算）。
## 只写 GameState，调用 Pathfinding / Combat。表现层只读，不在此处理渲染。

# ---- 时间（天/月分层）----
## 基础 tick = 1 天。行军/战斗/攻城按天推进；经济/粮草/士气恢复每 DAYS_PER_MONTH 天结算一次。
const DAYS_PER_MONTH: int = 30             ## 一月 = 30 天（经济/粮草/士气恢复结算周期）
const DAYS_PER_HALF_YEAR: int = 180        ## 半年 = 180 天（粮食注入周期）
# ---- 行军时长（平衡规格 R1：纯距离线性）----
const MARCH_DAYS_MIN: float = 10.0         ## 任意边最短行军 10 天（distance=1）
const MARCH_DAYS_MAX: float = 30.0         ## 任意边最长行军 30 天（distance>=5）
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
## 撤退驻城恢复每月消耗：复用普通驻军月耗口径（size × FOOD_PER_CAPITA）。
## 资源不足时按实际供给比例恢复；士气回满或本城粮尽后解除 RECOVERING。
const RECOVERY_FOOD_PER_CAPITA: float = FOOD_PER_CAPITA
## 规格 R3：被围粮仓城市每日消耗本地库存；普通城市无粮仓，被围即失去外部补给。
const SIEGE_CITY_FOOD_PER_DAY: int = 1     ## 被围城每日粮草消耗系数
# ---- 占领 ----
const CITY_DEFENSE_AFTER_CAPTURE: int = 10 ## 城破后防御重置下限
const CAPITAL_FOOD_CAPTURE_RATE: float = 0.30 ## 首都失守时库存缴获比例，其余损毁
# ---- 遭遇战触发 ----
## 边内接触阈值（以边长归一化的 move_progress 为单位，即 [0,1] 区间）。
## 双方沿同边推进，当各自「以 city_a 为原点的归一化位置」之差 <= 此值（或相向已交错）才触发。
const CONTACT_EPS: float = 0.15
const AI_DECISION_INTERVAL_DAYS: int = 5
const DIPLOMACY_DECISION_INTERVAL_DAYS: int = DAYS_PER_MONTH
const NEW_ARMY_SIZE: int = 5000
const DISBAND_SIZE_MAX: int = 499
const REINFORCE_PER_ARMY_PER_MONTH: int = 750
const PEACETIME_MANPOWER_RESERVE: int = 5000
const PEACETIME_STRENGTH_RATIO: float = 0.30
const FOOD_SECURITY_RESERVE_MONTHS: int = 6
const FOOD_RESERVE_RECOVERY_MONTHS: int = 6
const PEACETIME_BORDER_MIN_SIZE: int = 1500
const PEACETIME_EMERGENCY_MIN_SIZE: int = 500
const DEMOBILIZATION_STEP_MIN: int = 500
const WAR_MOBILIZATION_DAYS: int = 180
const GARRISON_CREATE_DEFICIT_MIN: float = 2500.0
const CAMPAIGN_OFFENSIVE_INTERVAL_DAYS: int = 90
const CAMPAIGN_OFFENSIVE_COMMIT_DAYS: int = 45
const CAMPAIGN_ARROW_DURATION_DAYS: int = 20
const PREPARATION_MAX_ORDERS_PER_CYCLE: int = 3

var state: GameState
var _time_acc: float = 0.0
var _ai_strategy_cache: Dictionary = {}    ## nation_id -> StrategicMapSnapshot
var _ai_strategy_revision: Dictionary = {} ## nation_id -> [ownership_revision, diplomacy_revision]
var _ai_last_decision_day: int = -1
## 测试/基准注入点：nation_id -> Callable(state, nation_id, simulation)。
## 正式游戏保持为空，所有国家均使用 Utility AI。
var ai_policy_overrides: Dictionary = {}
## A/B 基准注入点：nation_id -> 正常进攻单军最低战力占比；正式游戏使用 UtilityAI 默认值。
var ai_assault_participant_ratio_overrides: Dictionary = {}
## A/B 注入点：false 复现同优先级军队按 id 而非主力优先决策。
var ai_tactical_decision_order_overrides: Dictionary = {}
## A/B 注入点：false 关闭粮道桥梁/割点的守备与增援需求。
var ai_supply_corridor_defense_overrides: Dictionary = {}
## A/B 注入点：false 复现攻击候选不检查实际通行路径的旧逻辑。
var ai_executable_attack_paths_overrides: Dictionary = {}
## A/B 基准注入点：false 保留修改前的静态进攻评分。
var ai_strategic_planning_overrides: Dictionary = {}
## A/B 基准注入点：false 保留修改前的 60 天传播威胁守备策略。
var ai_adaptive_garrison_overrides: Dictionary = {}
## 隔离军事状态机测试时可关闭；正式游戏始终保持 true。
var diplomacy_enabled: bool = true


func setup(game_state: GameState) -> void:
	state = game_state
	state.refresh_derived()
	_ai_strategy_cache.clear()
	_ai_strategy_revision.clear()
	_ai_last_decision_day = -1


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
	# 每月结算：经济 / 粮草 / 士气恢复（数值口径与原按月一致，仅还原到每 30 天一次）
	if state.day % DAYS_PER_MONTH == 0:
		_resolve_economy()
		_resolve_reinforcements()
		_resolve_supply()
		_recover_morale()
		_resolve_diplomacy()
	ArmyCoordinator.merge_colocated(state)
	if state.day % AI_DECISION_INTERVAL_DAYS == 0 or _ai_last_decision_day == -1:
		_ai_assign_targets()
	_advance_movement()
	_advance_holding_adaptation()
	_drain_siege_food()   # 规格 R3：被围城每日耗粮（补给孤岛的粮草时钟）
	_refresh_war_flags()
	_check_victory()
	state.refresh_derived()

# ------------------------------------------------------------------ 1. 经济

func _resolve_economy() -> void:
	for city in state.cities:
		var nation := state.nations[city.owner_nation]
		nation.treasury_gold += city.gold_per_month
		nation.manpower_pool += city.manpower_per_month
	_resolve_war_finance()
	if state.day % DAYS_PER_HALF_YEAR == 0:
		var produced: Array[int] = []
		produced.resize(state.nations.size())
		produced.fill(0)
		for city in state.cities:
			produced[city.owner_nation] += city.food_per_half_year
		for nation in state.nations:
			state.deposit_food(nation.id, produced[nation.id])


func _resolve_war_finance() -> void:
	var deployed: Array[int] = []
	deployed.resize(state.nations.size())
	deployed.fill(0)
	for army in state.armies:
		if army.size > 0 and army.owner_nation >= 0 and army.owner_nation < deployed.size():
			deployed[army.owner_nation] += army.size
	for nation in state.nations:
		if state.wars_of(nation.id).is_empty():
			nation.last_war_upkeep = 0
			nation.unpaid_war_cost = 0
			continue
		var upkeep := int(ceil(
			float(deployed[nation.id]) / float(GameState.WAR_GOLD_TROOPS_PER_UNIT)
		))
		var paid := mini(nation.treasury_gold, upkeep)
		nation.treasury_gold -= paid
		nation.last_war_upkeep = upkeep
		nation.unpaid_war_cost = upkeep - paid


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
			return fill_a < fill_b or (is_equal_approx(fill_a, fill_b) and army_a.id < army_b.id)
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
	# 快照式：先算每支军队的需求与可达粮仓，再统一按库存/距离权重扣粮。
	var plans: Array = []   # [{army, sources, demand}]
	var morale_broken: Array[Army] = []
	var demand_by_nation: Array[int] = []
	demand_by_nation.resize(state.nations.size())
	demand_by_nation.fill(0)
	for army in state.armies:
		if army.size <= 0 or army.state == Army.State.RECOVERING:
			continue
		var siege_garrison := _siege_garrison_battle_of(army)
		if siege_garrison != null and siege_garrison.city.food_storage > 0:
			# 被围守军的粮食消耗真源是每日围城时钟；有粮时不再重复扣除月度军粮。
			army.starving = false
			army.supply_ratio = 1.0
			continue
		var sources := Pathfinding.supply_sources(state, army)
		var route_loss := _weighted_supply_loss(sources)
		var mult: float = MAX_SUPPLY_MULT
		if not sources.is_empty():
			mult = minf(1.0 + route_loss, MAX_SUPPLY_MULT)
		var base := int(ceil(army.size * FOOD_PER_CAPITA))
		base = maxi(base, 1)
		var demand := int(ceil(base * mult))
		plans.append({ "army": army, "sources": sources, "demand": demand })
		demand_by_nation[army.owner_nation] += demand
	for nation in state.nations:
		nation.last_food_demand = demand_by_nation[nation.id]
		nation.food_demand_ema = (
			float(nation.last_food_demand)
			if nation.food_demand_ema <= 0.0
			else lerpf(
				nation.food_demand_ema,
				float(nation.last_food_demand),
				0.5
			)
		)

	# 统一扣粮 + 减员
	for p in plans:
		var a: Army = p["army"]
		var demand: int = p["demand"]
		var supplied := _withdraw_weighted_supply(p["sources"], demand)
		var shortfall := demand - supplied
		if shortfall > 0:
			a.starving = true
			var old_morale := a.morale
			var shortage_ratio := float(shortfall) / float(demand)
			a.supply_ratio = 1.0 - shortage_ratio
			a.morale = maxf(a.morale - SUPPLY_MORALE_LOSS_MAX * shortage_ratio, Combat.MORALE_FLOOR)
			# 按缺口比例减员：完全断粮(shortfall==demand)时减 size*STARVE_RATE
			var loss := int(ceil(shortage_ratio * a.size * STARVE_RATE))
			a.size -= loss
			# 只在士气从正值跌至 0 的瞬间触发溃逃；RECOVERING 粮尽可按规则释放为自由态，
			# 不会因仍为 0 而在同一结算周期无限重入溃逃。
			if old_morale > Combat.MORALE_FLOOR and a.morale <= Combat.MORALE_FLOOR:
				if a.state in [Army.State.IDLE, Army.State.MOVING, Army.State.HOLDING] and a.size > 0:
					morale_broken.append(a)
		else:
			a.starving = false
			a.supply_ratio = 1.0

	for army in morale_broken:
		_retreat(army)
	_purge_dead_armies()

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
		army.morale = minf(army.morale + Combat.MORALE_RECOVER, 1.0)


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
	var sources := Pathfinding.supply_sources(state, army)
	var route_loss := _weighted_supply_loss(sources)
	var full_month_demand := maxi(int(ceil(float(army.size) * RECOVERY_FOOD_PER_CAPITA)), 1)
	var target_gain := minf(Combat.MORALE_RECOVER, 1.0 - army.morale)
	var base_demand := maxi(
		int(ceil(float(full_month_demand) * target_gain / Combat.MORALE_RECOVER)),
		1
	)
	var demand := int(ceil(
		float(base_demand) * minf(1.0 + route_loss, MAX_SUPPLY_MULT)
	)) if not sources.is_empty() else base_demand
	var supplied := _withdraw_weighted_supply(sources, demand)
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
	demand: int
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
			return (
				float(a["fraction"]) > float(b["fraction"])
				or (
					is_equal_approx(
						float(a["fraction"]), float(b["fraction"])
					)
					and int(a["city_id"]) < int(b["city_id"])
				)
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


func _advance_holding_adaptation() -> void:
	for army in state.armies:
		if army.size <= 0 or army.state != Army.State.HOLDING:
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
	for action in DiplomacyAI.choose_actions(state):
		_execute_diplomatic_action(action)


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
	match kind:
		DiplomacyAI.Action.MAKE_PEACE:
			if state.is_enemy(nation_a, nation_b):
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
					_start_war_mobilization(
						nation_a,
						int(action.get("mobilization_armies", -1))
					)
					for defender_id in defenders:
						if state.is_enemy(nation_a, defender_id):
							_clear_war_preparation(defender_id)
							_start_war_mobilization(defender_id)
					_clear_war_preparation(nation_a, false)
					_launch_campaign_offensive(nation_a, objective_city)
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
	_ai_last_decision_day = state.day
	for nation in state.nations:
		if not nation.alive:
			continue
		if ai_policy_overrides.has(nation.id):
			var policy: Callable = ai_policy_overrides[nation.id]
			policy.call(state, nation.id, self)
			continue
		var view := AiWorldView.build(state, nation.id)
		view.strategic_planning_enabled = bool(
			ai_strategic_planning_overrides.get(nation.id, true)
		)
		view.adaptive_garrison_enabled = bool(
			ai_adaptive_garrison_overrides.get(nation.id, true)
		)
		view.supply_corridor_defense_enabled = bool(
			ai_supply_corridor_defense_overrides.get(nation.id, true)
		)
		view.executable_attack_paths_enabled = bool(
			ai_executable_attack_paths_overrides.get(nation.id, true)
		)
		if (
			not _ai_strategy_cache.has(nation.id)
			or _ai_strategy_revision.get(nation.id, []) != [
				state.ownership_revision,
				state.diplomacy_revision,
			]
		):
			_ai_strategy_cache[nation.id] = StrategicMapSnapshot.build(view)
			_ai_strategy_revision[nation.id] = [
				state.ownership_revision,
				state.diplomacy_revision,
			]
		var snapshot: StrategicMapSnapshot = _ai_strategy_cache[nation.id]
		var threat := ThreatField.build(view)
		if _ai_manage_force_structure(view, snapshot, threat):
			view = AiWorldView.build(state, nation.id)
			view.strategic_planning_enabled = bool(
				ai_strategic_planning_overrides.get(nation.id, true)
			)
			view.adaptive_garrison_enabled = bool(
				ai_adaptive_garrison_overrides.get(nation.id, true)
			)
			view.supply_corridor_defense_enabled = bool(
				ai_supply_corridor_defense_overrides.get(nation.id, true)
			)
			view.executable_attack_paths_enabled = bool(
				ai_executable_attack_paths_overrides.get(nation.id, true)
			)
			threat = ThreatField.build(view)
		var strategic_orders_changed := false
		if nation.war_preparation_target_nation >= 0:
			strategic_orders_changed = _assign_offensive_staging_orders(
				nation.id,
				nation.war_preparation_objective_city
			)
		elif not state.wars_of(nation.id).is_empty():
			strategic_orders_changed = _manage_campaign_offensive(nation.id)
		if strategic_orders_changed:
			view = AiWorldView.build(state, nation.id)
			view.strategic_planning_enabled = bool(
				ai_strategic_planning_overrides.get(nation.id, true)
			)
			view.adaptive_garrison_enabled = bool(
				ai_adaptive_garrison_overrides.get(nation.id, true)
			)
			view.supply_corridor_defense_enabled = bool(
				ai_supply_corridor_defense_overrides.get(nation.id, true)
			)
			view.executable_attack_paths_enabled = bool(
				ai_executable_attack_paths_overrides.get(nation.id, true)
			)
			threat = ThreatField.build(view)
		var coordinator := ArmyCoordinator.new()
		var minimum_participant_ratio := float(
			ai_assault_participant_ratio_overrides.get(
				nation.id,
				UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO
			)
		)
		for army in view.friendly_armies:
			if army.ai_target_city != -1 and army.state in [Army.State.MOVING, Army.State.FIGHTING]:
				coordinator.reserve(army.ai_target_city, army)
			elif army.state == Army.State.HOLDING:
				var friendly_endpoint := army.move_from
				if not state.has_military_access(
					nation.id, state.cities[friendly_endpoint].owner_nation
				):
					friendly_endpoint = army.move_to
				coordinator.reserve(friendly_endpoint, army)
		var strongest_first := bool(
			ai_tactical_decision_order_overrides.get(nation.id, true)
		)
		var decision_order := _sort_ai_decision_order(
			view.friendly_armies, snapshot, strongest_first
		)
		for army in decision_order:
			if army.size <= 0:
				continue
			var candidate := UtilityAI.choose(
				view,
				snapshot,
				threat,
				coordinator,
				army,
				minimum_participant_ratio
			)
			if candidate.kind == ActionCandidate.Kind.NONE:
				continue
			if _execute_ai_candidate(army, candidate):
				if candidate.kind == ActionCandidate.Kind.HOLD:
					coordinator.reserve(candidate.target_edge_a, army)
				elif candidate.target_city != -1:
					coordinator.reserve(candidate.target_city, army)


static func _sort_ai_decision_order(
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
		return a.id < b.id
	)
	return result


func _ai_manage_force_structure(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField
) -> bool:
	var defended_cities := {}
	for city_id in snapshot.frontier_cities:
		defended_cities[city_id] = true
	for city_id in snapshot.potential_frontier_cities:
		defended_cities[city_id] = true
	var target_count := maxi(
		defended_cities.size() + 2,
		int(ceil(float(view.friendly_cities.size()) / 4.0))
	)
	var active_count := view.friendly_armies.size()
	var nation := state.nations[view.nation_id]
	var current_troops := 0
	for army in view.friendly_armies:
		current_troops += maxi(army.size, 0)
	var mobilization_needed := (
		(
			not state.wars_of(view.nation_id).is_empty()
			or nation.war_preparation_target_nation >= 0
		)
		and state.day <= nation.war_mobilization_until_day
		and current_troops < nation.war_mobilization_target_troops
	)
	var food_report := _food_security_report(view.nation_id)
	var food_pressure := bool(food_report["needs_demobilization"])
	var food_growth_budget := _food_growth_manpower_budget(
		food_report
	)
	if food_pressure:
		if _demobilize_for_food_security(
			view,
			snapshot,
			threat,
			food_report,
			target_count
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
	if (
		available_manpower >= NEW_ARMY_SIZE
		and not food_pressure
		and food_growth_budget >= NEW_ARMY_SIZE
	):
		var garrison_site := -1
		var largest_deficit := GARRISON_CREATE_DEFICIT_MIN
		for warehouse in view.warehouses:
			if not _is_available_recruitment_hub(view.nation_id, warehouse.id):
				continue
			var required := UtilityAI.required_logistics_garrison(
				view, snapshot, threat, warehouse.id
			)
			var deficit := required - UtilityAI.stationed_power_at(
				view, warehouse.id
			)
			if deficit > largest_deficit or (
				is_equal_approx(deficit, largest_deficit)
				and (garrison_site == -1 or warehouse.id < garrison_site)
			):
				largest_deficit = deficit
				garrison_site = warehouse.id
		if garrison_site != -1:
			return _create_army_for_nation(
				view.nation_id,
				garrison_site,
				"后勤中心守备缺口 %.0f，建立守备军" % largest_deficit
			) != null
	if active_count > target_count and not mobilization_needed:
		for army in view.friendly_armies:
			if (
				army.state == Army.State.IDLE
				and army.size <= DISBAND_SIZE_MAX
				and not snapshot.frontier_cities.has(army.location_city)
				and threat.threat_at(army.location_city) < ArmyPower.effective(army)
			):
				return _disband_army(army, "安全后方小规模冗余军队，解散返还人口")
	if (
		(active_count < target_count or mobilization_needed)
		and available_manpower >= NEW_ARMY_SIZE
		and not food_pressure
		and food_growth_budget >= NEW_ARMY_SIZE
	):
		var creation_site := -1
		var capital_id := state.nations[view.nation_id].capital_city_id
		if _is_available_recruitment_hub(view.nation_id, capital_id):
			creation_site = capital_id
		else:
			for warehouse in state.warehouse_cities_of(view.nation_id):
				if _is_available_recruitment_hub(view.nation_id, warehouse.id):
					creation_site = warehouse.id
					break
		if creation_site != -1:
			return _create_army_for_nation(
				view.nation_id,
				creation_site,
				(
					"战争粮食动员：当前兵力%d，目标%d"
					% [current_troops, nation.war_mobilization_target_troops]
					if mobilization_needed
					else "军队数 %d 低于战略需求 %d" % [
						active_count,
						target_count,
					]
				)
			) != null
	return false


func _assign_offensive_staging_orders(
	nation_id: int,
	objective_city: int
) -> bool:
	var staging := DiplomacyAI.staging_cities_for_objective(
		state, nation_id, objective_city
	)
	if staging.is_empty():
		return false
	var changed := false
	var orders := 0
	for staging_city in staging:
		if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
			break
		if _edge_has_friendly_holder_or_order(
			nation_id, staging_city, objective_city
		):
			continue
		for army in state.armies:
			if (
				army.owner_nation != nation_id
				or army.size <= 0
				or army.state != Army.State.IDLE
				or army.location_city != staging_city
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
				changed = true
				orders += 1
			break
	var staged := DiplomacyAI.staged_troops_for_objective(
		state, nation_id, objective_city
	)
	var required := DiplomacyAI.required_assault_troops(
		state, nation_id, objective_city
	)
	if staged >= required or orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
		return changed
	var candidates: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.IDLE
			or staging.has(army.location_city)
			or _is_critical_food_security_city(army.location_city)
		):
			continue
		candidates.append(army)
	candidates.sort_custom(func(a: Army, b: Army) -> bool:
		return a.id < b.id
	)
	for army in candidates:
		if (
			orders >= PREPARATION_MAX_ORDERS_PER_CYCLE
			or staged >= required
		):
			break
		var best_city := -1
		var best_distance := INF
		for staging_city in staging:
			var field := Pathfinding.dijkstra_field(
				state, army.location_city, nation_id, false, true
			)
			var distance := float(field["dist"][staging_city])
			if distance < best_distance:
				best_distance = distance
				best_city = staging_city
		if best_city == -1 or best_distance == INF:
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
			changed = true
			orders += 1
			staged += army.size
	if staged >= required or orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
		return changed
	var holders: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or army.size <= 0
			or army.state != Army.State.HOLDING
		):
			continue
		var friendly_endpoint := army.move_from
		if not state.has_military_access(
			nation_id, state.cities[friendly_endpoint].owner_nation
		):
			friendly_endpoint = army.move_to
		if (
			staging.has(friendly_endpoint)
			or _is_critical_food_security_city(friendly_endpoint)
		):
			continue
		holders.append(army)
	holders.sort_custom(func(a: Army, b: Army) -> bool:
		return a.size > b.size or (a.size == b.size and a.id < b.id)
	)
	for army in holders:
		if orders >= PREPARATION_MAX_ORDERS_PER_CYCLE:
			break
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
			changed = true
			orders += 1
	return changed


func _launch_campaign_offensive(
	nation_id: int,
	objective_city: int
) -> bool:
	if (
		objective_city < 0
		or objective_city >= state.cities.size()
		or not state.is_enemy(
			nation_id, state.cities[objective_city].owner_nation
		)
	):
		return false
	var staging := DiplomacyAI.staging_cities_for_objective(
		state, nation_id, objective_city
	)
	var required := DiplomacyAI.required_assault_troops(
		state, nation_id, objective_city
	)
	var staged := DiplomacyAI.staged_troops_for_objective(
		state, nation_id, objective_city
	)
	if staged < required:
		return false
	var attackers: Array[Army] = []
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		if (
			army.state == Army.State.IDLE
			and staging.has(army.location_city)
		) or (
			army.state == Army.State.HOLDING
			and (
				(army.move_from == objective_city and staging.has(army.move_to))
				or (army.move_to == objective_city and staging.has(army.move_from))
			)
		):
			attackers.append(army)
	attackers.sort_custom(func(a: Army, b: Army) -> bool:
		return a.size > b.size or (a.size == b.size and a.id < b.id)
	)
	var committed := 0
	var launched := false
	var origin_cities: Array[int] = []
	for army in attackers:
		var origin_city := army.location_city
		if army.state == Army.State.HOLDING:
			origin_city = army.move_from
			if not state.has_military_access(
				nation_id, state.cities[origin_city].owner_nation
			):
				origin_city = army.move_to
		var attack := ActionCandidate.make(
			ActionCandidate.Kind.ATTACK,
			2000.0,
			"国家战役第%d波：向目标城市%d发动预定攻势"
				% [
					state.nations[nation_id].campaign_offensive_count + 1,
					objective_city,
				],
			objective_city
		)
		attack.minimum_commit_days = CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		if _execute_ai_candidate(army, attack):
			committed += army.size
			launched = true
			if origin_city >= 0 and not origin_cities.has(origin_city):
				origin_cities.append(origin_city)
		if committed >= int(ceil(float(required) * 1.20)):
			break
	if launched:
		var nation := state.nations[nation_id]
		nation.campaign_last_offensive_day = state.day
		nation.campaign_next_offensive_day = (
			state.day + CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
		)
		nation.campaign_offensive_count += 1
		state.add_campaign_visual_event(
			nation_id,
			objective_city,
			origin_cities,
			nation.campaign_offensive_count,
			CAMPAIGN_ARROW_DURATION_DAYS
		)
	return launched


func _manage_campaign_offensive(nation_id: int) -> bool:
	var nation := state.nations[nation_id]
	if (
		nation.campaign_next_offensive_day >= 0
		and state.day < nation.campaign_next_offensive_day
	):
		return false
	var objective: Dictionary = {}
	var defender_id := -1
	for enemy_id in state.wars_of(nation_id):
		var candidate := state.war_objective(nation_id, enemy_id)
		if (
			not candidate.is_empty()
			and int(candidate.get("attacker", -1)) == nation_id
		):
			objective = candidate
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
		state.set_war_objective(
			nation_id,
			defender_id,
			objective_city,
			str(next["reason"])
		)
	if _launch_campaign_offensive(nation_id, objective_city):
		return true
	return _assign_offensive_staging_orders(nation_id, objective_city)


func _food_security_report(nation_id: int) -> Dictionary:
	var war_food := DiplomacyAI.war_food_report(state, nation_id)
	var monthly_production := float(war_food["monthly_food_production"])
	var monthly_demand := 0.0
	for army in state.armies:
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
	var supply := Pathfinding.nearest_supply_city(state, army)
	var route_loss := float(supply[1])
	var multiplier := MAX_SUPPLY_MULT
	if int(supply[0]) != -1:
		multiplier = minf(1.0 + route_loss, MAX_SUPPLY_MULT)
	var base := maxi(int(ceil(float(army.size) * FOOD_PER_CAPITA)), 1)
	return ceil(float(base) * multiplier)


func _demobilize_for_food_security(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	food_report: Dictionary,
	target_count: int
) -> bool:
	var candidates: Array[Army] = []
	for army in view.friendly_armies:
		if (
			army.state not in [Army.State.IDLE, Army.State.HOLDING]
			or army.location_city < 0
			or threat.threat_at(army.location_city) >= ArmyPower.effective(army)
		):
			continue
		var minimum_size := _food_security_minimum_size(army, snapshot)
		if army.size <= minimum_size:
			continue
		candidates.append(army)
	candidates.sort_custom(func(a: Army, b: Army) -> bool:
		var a_critical := _is_critical_food_security_city(a.location_city)
		var b_critical := _is_critical_food_security_city(b.location_city)
		if a_critical != b_critical:
			return not a_critical
		var a_border := (
			snapshot.frontier_cities.has(a.location_city)
			or snapshot.potential_frontier_cities.has(a.location_city)
			or a.state == Army.State.HOLDING
		)
		var b_border := (
			snapshot.frontier_cities.has(b.location_city)
			or snapshot.potential_frontier_cities.has(b.location_city)
			or b.state == Army.State.HOLDING
		)
		if a_border != b_border:
			return not a_border
		return a.size > b.size or (a.size == b.size and a.id < b.id)
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
		var minimum_size := _food_security_minimum_size(army, snapshot)
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
		if army.state == Army.State.IDLE and returned >= army.size:
			if not _disband_army(army, "和平裁军屯粮"):
				continue
		else:
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


func _food_security_minimum_size(
	army: Army,
	snapshot: StrategicMapSnapshot
) -> int:
	if _is_critical_food_security_city(army.location_city):
		return PEACETIME_BORDER_MIN_SIZE
	if (
		snapshot.frontier_cities.has(army.location_city)
		or snapshot.potential_frontier_cities.has(army.location_city)
		or army.state == Army.State.HOLDING
	):
		return PEACETIME_EMERGENCY_MIN_SIZE
	return 0


func _is_critical_food_security_city(city_id: int) -> bool:
	if city_id < 0 or city_id >= state.cities.size():
		return false
	var city := state.cities[city_id]
	return (
		city.is_capital
		or city.has_warehouse
		or city.is_food_hub
		or city.is_manpower_hub
	)


func _is_available_recruitment_hub(nation_id: int, city_id: int) -> bool:
	return (
		city_id >= 0 and city_id < state.cities.size()
		and state.cities[city_id].owner_nation == nation_id
		and state.cities[city_id].has_warehouse
		and not state.city_under_siege(city_id)
	)


func _create_army_for_nation(nation_id: int, city_id: int, reason: String = "") -> Army:
	if nation_id < 0 or nation_id >= state.nations.size():
		return null
	var nation := state.nations[nation_id]
	if (
		nation.manpower_pool < NEW_ARMY_SIZE
		or not _is_available_recruitment_hub(nation_id, city_id)
	):
		return null
	nation.manpower_pool -= NEW_ARMY_SIZE
	var army := state.create_army(nation_id, city_id, NEW_ARMY_SIZE)
	if army == null:
		nation.manpower_pool += NEW_ARMY_SIZE
		return null
	army.ai_action = ActionCandidate.Kind.CREATE_ARMY
	army.ai_order_created_day = state.day
	army.ai_order_reason = reason
	nation.ai_last_force_action = ActionCandidate.Kind.CREATE_ARMY
	nation.ai_last_force_day = state.day
	nation.ai_last_force_reason = reason
	return army


func _disband_army(army: Army, reason: String = "") -> bool:
	if (
		army == null or army.size <= 0 or army.state != Army.State.IDLE
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


func _execute_ai_candidate(army: Army, candidate: ActionCandidate) -> bool:
	if candidate.kind == ActionCandidate.Kind.HOLD:
		if army.state == Army.State.HOLDING:
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		if _edge_has_friendly_holder_or_order(
			army.owner_nation, army.location_city, candidate.target_city
		):
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
			army.state = Army.State.MOVING
			army.holding_days = 0
			army.hold_target_progress = -1.0
			army.path.clear()
			_record_ai_order(army, candidate)
			return true
		if army.state != Army.State.IDLE or candidate.target_city == -1:
			return false
		var field := Pathfinding.dijkstra_field(
			state,
			army.location_city,
			army.owner_nation,
			false,
			candidate.kind != ActionCandidate.Kind.ATTACK,
			candidate.target_city if candidate.kind == ActionCandidate.Kind.ATTACK else -1
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
		var retreat_field := Pathfinding.dijkstra_field(
			state, army.location_city, army.owner_nation, false, true
		)
		army.path = Pathfinding.reconstruct(
			retreat_field["prev"], army.location_city, candidate.target_city
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
		army.state = Army.State.IDLE
		army.path.clear()
		return false
	_record_ai_order(army, candidate)
	return true


func _record_ai_order(army: Army, candidate: ActionCandidate) -> void:
	army.ai_action = candidate.kind
	army.ai_target_city = candidate.target_city
	army.ai_order_created_day = state.day
	army.ai_order_until_day = state.day + candidate.minimum_commit_days
	army.ai_order_score = candidate.score
	army.ai_order_reason = candidate.reason


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

## 行军时长（天）= 纯距离线性映射（平衡规格 R1）。
## distance∈[1,5] → clamp(10+(d-1)*5, 10, 30)：最短 10 天、最长 30 天，随长度线性插值。
static func march_days(distance: int) -> float:
	return clampf(MARCH_DAYS_MIN + float(maxi(distance, 1) - 1) * 5.0, MARCH_DAYS_MIN, MARCH_DAYS_MAX)

func _advance_movement() -> void:
	# 1. 先推进所有 MOVING / RETREATING 军队（本步骤不处理"到达节点"）。
	#    关键时序：若在此就地 _arrive_at_node，先走到敌城的一方会在遭遇检测前离边进入攻城，
	#    导致相向而行的两军错身穿过、永不野战交火。故推进与到达必须分离。
	var holding_arrivals: Array[Army] = []
	for army in state.armies:
		if not _is_travelling(army) or army.size <= 0:
			continue   # FIGHTING 军队冻结在原地，不推进
		if army.move_to == -1:
			# 等待进入下一段（上月被 throughput 卡住）
			_begin_next_leg(army)
			if army.move_to == -1:
				continue
		var edge := state.edge_of(army.move_from, army.move_to)
		# 行军时长 = 纯距离线性映射（平衡规格 R1）：见 march_days()。
		# 每天推进 1/天数。注：speed_factor 与 danger 不再影响行军时长（规格要求纯长度线性）——
		# speed_factor 已成行军侧死字段；danger 仍用于战斗地形惩罚(combat)与寻路边权(pathfinding)。
		var travel_days := march_days(edge.distance)
		army.move_progress += 1.0 / travel_days   # 可能 >= 1.0（走到边末端），稍后统一判定到达
		if army.state == Army.State.MOVING and army.hold_target_progress >= 0.0:
			if army.move_progress >= army.hold_target_progress:
				army.move_progress = army.hold_target_progress
				holding_arrivals.append(army)

	# 2. 遭遇检测（在到达节点之前）：同边敌军按物理位置接触即交火。
	#    走到边末端（norm→1.0）的一方与任何相向敌军必接触 → 优先野战，杜绝错身。
	_detect_encounters()
	_block_passthrough()   # 敌占交战点卡位：禁止敌军不战穿过
	# 驻防转换必须晚于遭遇检测：两支敌军同日抵达同一驻防点时仍应先开战，不能同时变 HOLDING 后互相无视。
	for army in holding_arrivals:
		if army.state == Army.State.MOVING and army.battle_id == -1:
			_start_holding(army)

	# 3. 到达节点：处理普通行军与撤退行军。遭遇检测已在本步骤前覆盖两者。
	for army in state.armies:
		if _is_travelling(army) and army.size > 0 and army.move_to != -1 and army.move_progress >= 1.0:
			_arrive_at_node(army)

	# 4. 推进所有进行中的战斗各打一回合
	_resolve_battles()
	_purge_dead_armies()


## 尝试进入 path 的下一段边。throughput 仅限制同国同方向友军；反向与敌军独立。
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
	if edge == null or edge.max_throughput <= 0:
		# 路径失效或道路禁止大军通行：普通军等待 AI 重规划，撤退军立即改走合法路线。
		army.path.clear()
		if army.state == Army.State.RETREATING:
			if (
				from_city >= 0
				and from_city < state.cities.size()
				and state.cities[from_city].owner_nation == army.owner_nation
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
	if _friendly_same_direction_count(army.owner_nation, from_city, next_city) >= edge.max_throughput:
		# 只被同国同方向队列阻塞；反向友军和敌军均不占本方向名额。
		army.move_to = -1
		return
	army.path.pop_front()
	army.move_to = next_city
	army.move_progress = 0.0
	army.holding_days = 0
	army.resume_holding_after_battle = false
	edge.passing_count += 1
	edge.occupied = true
	army.on_edge = true


func _friendly_same_direction_count(nation_id: int, from_city: int, to_city: int) -> int:
	var count := 0
	for other in state.armies:
		if other.size <= 0 or other.owner_nation != nation_id:
			continue
		if not other.on_edge or other.move_to == -1:
			continue
		if other.move_from == from_city and other.move_to == to_city:
			count += 1
	return count


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
			if state.cities[arrived].owner_nation == army.owner_nation:
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
	keys.sort()   # 确定性顺序
	for key in keys:
		var group: Array = by_edge[key]
		group.sort_custom(func(x, y): return x.id < y.id)   # 确定性
		var edge := state.edge_of(group[0].move_from, group[0].move_to)
		if edge == null:
			continue

		# 已有战斗：接触到战线的军队按归侧规则加入
		if field_by_edge.has(key):
			var existing: Battle = field_by_edge[key]
			for army in group:
				if not existing.has_army(army) and _can_join_field_contact(army, existing, edge):
					_join_field_battle(existing, army, edge)
			continue

		if group.size() < 2:
			continue

		# 在所有「敌对且已接触」的对中，选归一化位置差最小的一对为交战核心
		var best_x: Army = null
		var best_y: Army = null
		var best_gap := INF
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
				if gap < best_gap:
					best_gap = gap
					best_x = x
					best_y = y
		if best_x == null:
			continue   # 本边无满足接触的敌对对 → 不开战（"边内可能不触发"）

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
		# 其余接触到战线的军队按归侧规则加入
		for army in group:
			if not battle.has_army(army) and _can_join_field_contact(army, battle, edge):
				_join_field_battle(battle, army, edge)


## 普通 MOVING 军沿用“同边同国即聚合”；HOLDING/RETREATING 只有实际接触战线才卷入。
func _can_join_field_contact(army: Army, battle: Battle, edge: Edge) -> bool:
	if army.state == Army.State.MOVING:
		return true
	var length := float(maxi(edge.distance, 1))
	var my_norm := _norm_pos(army, edge)
	var line_a := clampf(battle.contact_dist_a / length, 0.0, 1.0)
	var line_b := clampf(battle.contact_dist_b / length, 0.0, 1.0)
	return minf(absf(my_norm - line_a), absf(my_norm - line_b)) <= CONTACT_EPS


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
		var defenders := state.armies_at_city(city.id)
		# 规格 R4：进攻空城（无守军）时，若攻方兵力 < 城基础防御力，则无法围城——
		# 攻方不得占据空城，须自动向最近友方城撤离（无合法本国通道则溃散）。
		if defenders.is_empty() and attacker.size < city.defense:
			_retreat_to_friendly(attacker)
			return
		siege = state.new_battle(Battle.Kind.SIEGE)
		siege.edge = edge
		siege.city = city
		var length := float(maxi(edge.distance, 1))
		siege.contact_dist_a = length   # 围城方在城墙 dist=L（端点，无地形惩罚）
		siege.contact_dist_b = 0.0      # 守军城中 dist=0（端点，无地形惩罚）
		if not defenders.is_empty():
			var total_garrison := 0
			for defender in defenders:
				defender.state = Army.State.FIGHTING
				defender.battle_id = siege.id
				siege.side_b.append(defender)
				total_garrison += defender.size
			siege.has_garrison = true
			siege.garrison_ref = total_garrison   # 5× 门槛分母：全部驻军兵力快照
		else:
			siege.garrison_ref = city.defense    # 空城：以城防规模为等效守方基准
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
	for battle in state.battles:
		if battle.finished:
			continue
		if battle.kind == Battle.Kind.SIEGE:
			_advance_siege(battle)
		else:
			Combat.resolve_round(battle, state.rng)
			if battle.finished:
				_finish_field_battle(battle)
	state.battles = state.battles.filter(func(b: Battle) -> bool: return not b.finished)


## SIEGE 状态机（每天一 tick）。三阶段：
##  1) 守军抵抗：resolve_round 削守军。守军歼灭≠破城——转纯围城；攻方溃则围城失败。
##  2) 城下决斗：side_b 为敌对挑战者（无城防加成），分胜负后胜方独占围城。
##  3) 纯围城：无对抗，掷骰累积 siege_progress，达阈值破城易主。
func _advance_siege(battle: Battle) -> void:
	battle.prune_dead()
	_reconcile_siege_city_defenders(battle)
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
		Combat.resolve_round(battle, state.rng)
		if not battle.finished:
			return
		if battle.winner_side == 2:
			# 攻方被守军击退：真结束
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
		Combat.resolve_round(battle, state.rng)
		if not battle.finished:
			return
		if battle.winner_side == 1:
			# 围城方胜：挑战者撤退，围城继续
			for c in battle.side_b:
				if c.size > 0:
					_retreat(c)
				else:
					c.battle_id = -1
			battle.side_b.clear()
			battle.side_a = _withdraw_broken_armies(battle.side_a)
			if battle.side_a.is_empty():
				battle.finished = true
				battle.winner_side = 0
				return
			battle.finished = false
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
				battle.side_b.clear()
				battle.finished = true
				battle.winner_side = 2
			else:
				_promote_challengers(battle)
		return

	# 阶段 3：纯围城，确定性递减累积破城（规格 R2）。
	if not atk_alive:
		battle.finished = true
		battle.winner_side = 0   # 围城方尽墨，无人占领
		return
	# 兵力不足 5 倍时围城方强制撤离，禁止永久切断城市补给形成无进度僵局。
	var daily_progress := Combat.siege_daily_progress(
		battle.side_size(battle.side_a), battle.garrison_ref
	)
	if daily_progress <= 0.0:
		for attacker in battle.side_a:
			if attacker.size > 0:
				_withdraw_failed_siege(attacker, battle.city.id)
			else:
				attacker.battle_id = -1
		battle.side_a.clear()
		battle.finished = true
		battle.winner_side = 0
		return
	# 兵力越大围城越快（90→3 天）。基准快照使门槛在守军被歼后持续生效。
	battle.siege_progress += daily_progress
	if battle.siege_progress >= Combat.SIEGE_PROGRESS_REQUIRED:
		var captor := _strongest_alive(battle.side_a)
		for a in battle.side_a:
			a.battle_id = -1
			if a != captor and a.size > 0:
				_settle_idle(a, battle.city.id)
		if captor != null:
			_capture_city(captor, battle.city)
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
	var defenders := state.armies_at_city(battle.city.id)
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
		battle.has_garrison = true
		battle.garrison_ref = maxi(
			battle.garrison_ref,
			battle.side_size(battle.side_b)
		)


func _decay_interrupted_siege_progress(battle: Battle) -> void:
	battle.siege_progress = Combat.siege_progress_after_interruption(
		battle.siege_progress
	)


## 挑战者（side_b）接管围城：晋升为围城方（移入 side_a、置城墙位置），围城继续。
func _promote_challengers(battle: Battle) -> void:
	var new_besiegers: Array[Army] = []
	for c in battle.side_b:
		if c.size > 0 and c.morale > Combat.MORALE_FLOOR:
			new_besiegers.append(c)
		elif c.size > 0:
			_retreat(c)
		else:
			c.battle_id = -1
	battle.side_a = new_besiegers
	battle.side_b.clear()
	battle.contact_dist_a = float(maxi(battle.edge.distance, 1)) if battle.edge != null else 0.0
	# 守军已不在（挑战者接管的是纯围城）→ 基准回落到城防等效规模，5× 门槛按此判定。
	battle.garrison_ref = battle.city.defense if battle.city != null else battle.garrison_ref
	battle.has_garrison = false
	battle.finished = false
	battle.winner_side = 0


func _withdraw_broken_armies(side: Array[Army]) -> Array[Army]:
	var active: Array[Army] = []
	for army in side:
		if army.size <= 0:
			army.battle_id = -1
		elif army.morale <= Combat.MORALE_FLOOR:
			_retreat(army)
		else:
			active.append(army)
	return active


func _settle_or_recover_after_battle(army: Army, city_id: int) -> void:
	if army.morale <= Combat.MORALE_FLOOR:
		_start_recovering(army, city_id)
	else:
		_settle_idle(army, city_id)


func _finish_field_battle(battle: Battle) -> void:
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
			if a.morale <= Combat.MORALE_FLOOR:
				_retreat(a)          # 双方同时崩溃时，零士气胜方也不能继续追击
			else:
				_resume_after_battle(a)
		else:
			a.battle_id = -1


## 胜方继续行军：解除 FIGHTING，恢复 MOVING，沿原方向推进（仍占该边）。
func _resume_after_battle(army: Army) -> void:
	if army.forced_retreat:
		army.state = Army.State.RETREATING
	elif army.resume_holding_after_battle:
		army.state = Army.State.HOLDING
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
	_enter_battle(battle, army, target)
	var my_norm := _norm_pos(army, edge)
	var length := float(maxi(edge.distance, 1))
	var side_arr: Array[Army]
	if target == 1:
		battle.contact_dist_a = maxf(battle.contact_dist_a, my_norm * length)
		side_arr = battle.side_a
	else:
		battle.contact_dist_b = maxf(battle.contact_dist_b, my_norm * length)
		side_arr = battle.side_b
	# 增援集结：新友军加入提振本侧既有（疲劳）成员士气（EU4 式援军回气）
	Combat.reinforce_morale(side_arr, army)


func _enter_battle(battle: Battle, army: Army, side: int) -> void:
	if battle.kind == Battle.Kind.FIELD and army.state == Army.State.HOLDING:
		army.resume_holding_after_battle = true
	army.state = Army.State.FIGHTING
	army.battle_id = battle.id
	if side == 1:
		battle.side_a.append(army)
	else:
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

func _capture_city(army: Army, city: City) -> void:
	var old_owner := city.owner_nation
	var captured_food := city.food_storage if city.has_warehouse else 0
	var old_owner_valid := old_owner >= 0 and old_owner < state.nations.size()
	var captured_capital := old_owner_valid and state.nations[old_owner].capital_city_id == city.id
	if city.has_warehouse and old_owner_valid:
		state.remove_warehouse(old_owner, city.id)
	else:
		city.is_capital = false
		city.has_warehouse = false
	city.food_storage = 0
	city.owner_nation = army.owner_nation
	state.ownership_revision += 1
	city.defense = CITY_DEFENSE_AFTER_CAPTURE
	if captured_capital:
		state.relocate_capital(old_owner)
	var spoils := int(floor(float(captured_food) * CAPITAL_FOOD_CAPTURE_RATE))
	state.deposit_food(army.owner_nation, spoils)
	# 同城可能有多支静止/恢复军队，而围城入口历史上只取第一支守军。
	# 城市易主时统一驱逐其余旧城主驻军，禁止 RECOVERING 军队滞留敌城。
	for displaced in state.armies:
		if displaced == army or displaced.size <= 0 or displaced.owner_nation == army.owner_nation:
			continue
		if displaced.location_city != city.id:
			continue
		if displaced.state in [Army.State.IDLE, Army.State.RECOVERING]:
			_start_morale_retreat_from_city(displaced, city.id, city.id)
	army.state = Army.State.IDLE
	army.forced_retreat = false
	army.battle_id = -1
	army.location_city = city.id
	army.move_from = city.id
	army.move_to = -1
	army.move_progress = 0.0
	army.path.clear()

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
	if current_city != excluded_city_id and state.cities[current_city].owner_nation == army.owner_nation:
		_start_recovering(army, current_city)
		return
	var path := Pathfinding.nearest_friendly_city(state, army, excluded_city_id)
	if path.is_empty():
		army.size = 0   # 已无可达友城：溃散
		return
	army.path = path
	_begin_next_leg(army)


func _start_recovering(army: Army, city_id: int) -> void:
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


func _start_holding(army: Army) -> void:
	if not army.on_edge or army.move_to == -1:
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


## 规格 R4：弱攻方从空城前自动向最近友方城撤离（不占据敌城）。
## army 此时已抵达敌城节点(move_to=arrived)、边已释放。以 arrived 为锚点寻友城路径。
func _retreat_to_friendly(army: Army) -> void:
	var arrived := army.move_to
	army.move_from = arrived if arrived != -1 else army.move_from
	army.move_to = -1
	army.move_progress = 0.0
	army.state = Army.State.MOVING
	army.forced_retreat = false
	army.location_city = army.move_from
	var path := Pathfinding.nearest_friendly_city(state, army)
	if path.is_empty():
		# 无合法本国通道时不能滞留敌城或穿越敌城，按无路可退处理为溃散。
		army.size = 0
		return
	army.path = path
	_begin_next_leg(army)


func _withdraw_failed_siege(army: Army, city_id: int) -> void:
	_release_edge(army)
	army.battle_id = -1
	army.state = Army.State.MOVING
	army.forced_retreat = false
	army.holding_days = 0
	army.hold_target_progress = -1.0
	army.resume_holding_after_battle = false
	army.location_city = city_id
	army.move_from = city_id
	army.move_to = -1
	army.move_progress = 0.0
	army.path = Pathfinding.nearest_friendly_city(state, army, city_id)
	if army.path.is_empty():
		army.size = 0
		return
	_begin_next_leg(army)


## 释放该军占用的边通行槽。以 army.on_edge 为唯一判据，幂等（重复调用安全）。
func _release_edge(army: Army) -> void:
	if not army.on_edge:
		return
	army.on_edge = false
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge != null and edge.passing_count > 0:
		edge.passing_count -= 1
		edge.occupied = edge.passing_count > 0


func _edge_key_of(a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return lo * GameState.CITY_COUNT + hi


## 移除 size<=0 的军队，并释放它们占用的边。
func _purge_dead_armies() -> void:
	var survivors: Array[Army] = []
	for army in state.armies:
		if army.size > 0:
			survivors.append(army)
		else:
			_release_edge(army)   # 幂等释放
	state.armies = survivors
