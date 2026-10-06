class_name DiplomacyAI
extends RefCounted
## 无训练外交 Utility AI。只生成双边候选，不直接修改 GameState。

enum Action {
	NONE,
	MAKE_PEACE,
	DECLARE_WAR,
	FORM_ALLIANCE,
	LEAVE_ALLIANCE,
	PREPARE_WAR,
	CANCEL_WAR_PREPARATION,
	ENFEOFF,
	CENTRALIZE,
	RETARGET_WAR_PREPARATION,
	ISSUE_ULTIMATUM,
}

enum FoodPosture {
	PEACE,
	GUARDED,
	OFFENSIVE_WAR,
	DEFENSIVE_WAR,
}

enum ObjectiveContext {
	PREWAR,
	CAMPAIGN,
}

const MIN_WAR_DAYS: int = 180
const PEACE_STALEMATE_DAYS: int = 720
const WAR_FATIGUE_REFERENCE_DAYS: int = 360
const MIN_NEUTRAL_DAYS: int = 90
const MIN_ALLIANCE_DAYS: int = 360
## 单国同时主动开战上限。诊断显示宣战「意愿分」恒在阈值 3× 以上，长和平期的
## 真因是该上限=1：一旦入战，其余所有战线被硬门槛拦死。放开到 3 以支持多线
## 饱和进攻的乱世感；经济/粮食仍逐国把关，统一时代只连续退火储备量，不移除底线。
const MAX_CONCURRENT_WARS: int = 3
const MAX_DEFENSIVE_ALLIES: int = 1
## 新结盟、主动备战与主动宣战只允许在国家领土接触图的两跳范围内。
## 一跳是直接接壤，二跳是共享一个邻国；已有关系、议和和防御盟约参战不受影响。
const MAX_DIPLOMATIC_DISTANCE_HOPS: int = 2
const PEACE_PROPOSE_SCORE: float = 1.25
const PEACE_ACCEPT_SCORE: float = 0.60
const PEACE_SITUATION_WEIGHT: float = 0.40
const PEACE_POWER_BALANCE_WEIGHT: float = 1.20
const PEACE_RESOURCE_ENDURANCE_WEIGHT: float = 1.00
const PEACE_EXTERNAL_THREAT_WEIGHT: float = 1.50
const PEACE_RESOURCE_REFERENCE_MONTHS: float = 24.0
const PEACE_MAX_BORDER_MASSING_RATIO: float = 1.50
const ALLIANCE_ACCEPT_SCORE: float = 1.00
## Strong peaceful suzerainty systems cannot form new defensive alliances.
const ALLIANCE_STRONG_AVERAGE_RATIO: float = 1.50
const ALLIANCE_STRONG_WORLD_SHARE: float = 0.20
const ALLIANCE_STRONG_SCORE_CAP: float = 0.75
const WAR_DECLARE_SCORE: float = 0.85
const OBSERVED_WAR_PREPARATION_THREAT_BONUS: float = 0.75
const PEACE_ESCALATION_START_DAYS: int = 180
const PEACE_ESCALATION_FULL_DAYS: int = 540
const PEACE_ESCALATION_MAX_BONUS: float = 0.75
## 守军薄弱补偿：常规价值（金/粮/人/战略/包围/争夺）拉不开差距时，主动倾向敌方
## 守军最少的接壤城，填补“攻势找不到目标”的空档。值域约 [0, 此上限]，故意小于
## 资源/战略权重，只在其他信号平手时决胜，不喧宾夺主推翻高价值目标。
const WEAK_GARRISON_OBJECTIVE_BONUS: float = 0.90
## 行政州统一偏好：已有立足点的州才加分，且随已控制比例平方增长。
## 最高值与首都、资源核心等战略项同阶，形成强倾向但不作为硬门槛。
const REGION_UNIFICATION_OBJECTIVE_BONUS: float = 6.0
const LEAVE_ALLIANCE_SCORE: float = 0.90
const ATTITUDE_PEACE_WEIGHT: float = 0.25
const ATTITUDE_ALLIANCE_WEIGHT: float = 0.35
const ATTITUDE_WAR_WEIGHT: float = 0.35
const ATTITUDE_LEAVE_WEIGHT: float = 0.50
const REVENGE_PER_LOST_SITUATION_POINT: float = 0.10
const REVENGE_SURRENDER_PENALTY: float = 0.85
const REVENGE_ATTITUDE_FLOOR: float = -1.25
## 母国把从自身分裂出去的地方叛军视为天然敌对政治实体；该项不随一次
## 议和消失，并通过态度统一影响结盟、宣战、退盟与再次议和。
const PARENT_REBEL_ATTITUDE: float = -1.25
const BORDER_ATTITUDE_PER_EDGE: float = 0.08
const BORDER_ATTITUDE_FLOOR: float = -0.48
const OBJECTIVE_ATTITUDE_PER_VALUE: float = 0.035
const OBJECTIVE_ATTITUDE_FLOOR: float = -0.55
const COMMON_ENEMY_ATTITUDE: float = 0.60
const ENEMY_ALLY_ATTITUDE: float = -0.90
# Existing economic and peace pacing; regional competition is independent.
const UNIFICATION_ERA_ONSET_YEARS: int = 2
const UNIFICATION_ERA_FULL_YEARS: int = 20
const TOTAL_WAR_MIN_PAYMENT_RATIO: float = 0.50
const TOTAL_WAR_GOLD_RUNWAY_MONTHS: float = 0.0
const TOTAL_WAR_FOOD_RUNWAY_YEARS: float = 0.25
const TOTAL_WAR_MANPOWER_SHARE: float = 0.0
const CAMPAIGN_RESERVE_MONTHS: int = 6
const FOOD_PER_CAPITA_MONTH: float = 0.0025
const MIN_MANPOWER_RESERVE: int = 5000
const MAX_MOBILIZATION_ARMIES: int = 4
const MONTHS_PER_YEAR: int = 12
const PEACE_STOCK_TARGET_YEARS: float = 1.5
const PEACE_STOCK_RECOVERY_YEARS: float = 3.0
const GUARDED_CAMPAIGN_YEARS: float = 2.0
const OFFENSIVE_CAMPAIGN_YEARS: float = 2.0
const DEFENSIVE_CAMPAIGN_YEARS: float = 1.0
const EMERGENCY_FOOD_MONTHS: int = 6
const DEFAULT_CAMPAIGN_SUPPLY_MULTIPLIER: float = 1.5
const MAX_REPORTED_RUNWAY_YEARS: float = 99.0
const WAR_PREPARATION_MAX_DAYS: int = 360
const WAR_PREPARATION_RESOURCE_GRACE_DAYS: int = 90
const WAR_PREPARATION_FORCE_SHARE: float = 0.25
## 取消备战后的重启冷却：取消后这么多天内该国不得再发起 PREPARE_WAR。与 MAX_DAYS 同阶。
## 打断「集结失败→取消→隔一个决策周期(30天)立即重开→再失败」的终局横跳正反馈。
const WAR_PREPARATION_CANCEL_COOLDOWN_DAYS: int = 360
## 集结超时后的「尽力而战」最低兵力比：已集结兵力达到 required_assault_troops 的此比例，
## 即使未凑齐完美门槛也在超时后立即发起攻势（用现有可用主战军团），而非无限空转/取消再重开。
const WAR_PREPARATION_BEST_EFFORT_RATIO: float = 0.5

## 分封（藩王系统增量 B3）调参。第一版尽量少参数，判据来自设计文档第 4、6 节：
## 核心是区域财政、粮产与治理压力，只在和平期分封。
const ENFEOFF_MIN_REGION_CITIES: int = 3       ## 候选封地最少城市数，避免碎封
const ENFEOFF_MAX_REGION_CITIES: int = 8       ## 主动生长上限；被切断飞地闭包可超过
const ENFEOFF_FOOD_BURDEN_RATIO_THRESHOLD: float = 0.10
## 「远」是相对该国疆域半径的，而非绝对跳数：距首都跳数 ≥ 本国最大跳数 × 此比例
## 才算外围（避免把绝对阈值套到小疆域国家上、导致永远找不到边疆种子）。
const ENFEOFF_FAR_HOP_FRACTION: float = 0.5
const ENFEOFF_MIN_OVERLORD_CITIES_AFTER: int = 6    ## 分封后宗主至少保留的陆城数
const ENFEOFF_GOVERNANCE_PRESSURE_THRESHOLD: float = 3.5
const ENFEOFF_GOVERNANCE_SCORE_WEIGHT: float = 0.75
const ENFEOFF_TARGET_DIRECT_CITIES_FIELD: String = "enfeoff_target_direct_cities"
const ENFEOFF_MAX_REGION_CITIES_FIELD: String = "enfeoff_max_region_cities"
const ENFEOFF_FOREIGN_FRONTIER_FIELD: String = "enfeoff_require_foreign_frontier"

## 削藩（藩王系统增量 C）调参。财政收益是主决策；高政治威胁是次级例外。
const CENTRALIZE_COOLDOWN_DAYS: int = 1825          ## 一次削藩后约5年内不再对同一藩王削藩
## 分封保护期：藩王被分封后至少存续这么多天才可被削藩。防止「分封→立即撤回」反复横跳
## （分封 created_day 与削藩 last_centralization_day 是两套字段，缺此门控时新藩王当即满足削藩）。
## 拉长到约 4 年：一次分封的政治重组需长期稳定，杜绝"封了又撤"的高频横跳。
const CENTRALIZE_MIN_VASSAL_AGE_DAYS: int = 1440
# 兼容旧诊断/测试的展示阈值；实际反抗判定由 RebellionSystem 统一负责。
const CENTRALIZE_RESIST_RATIO_THRESHOLD: float = 0.45
## 财政收益不为正时，只有达到此高威胁比才因政治风险削藩。该阈值显著高于反抗阈值，
## 因此威胁分支天然会进入内战，而不会让一般军力增长压过财政理性。
const CENTRALIZE_POLITICAL_THREAT_RATIO_THRESHOLD: float = 0.80

## A/B 与专项等价测试开关。关闭时逐次执行历史实现，不创建或命中
## tick-scope EncirclementIndex。生产默认启用。
static var encirclement_index_enabled: bool = true

static var _encirclement_index_builds: int = 0
static var _encirclement_cache_hits: int = 0
static var _encirclement_cache_misses: int = 0
static var _encirclement_legacy_evaluations: int = 0
static var _capital_hops_cache_builds: int = 0


static func reset_encirclement_cache_counters() -> void:
	_encirclement_index_builds = 0
	_encirclement_cache_hits = 0
	_encirclement_cache_misses = 0
	_encirclement_legacy_evaluations = 0
	_capital_hops_cache_builds = 0


static func encirclement_cache_counters() -> Dictionary:
	return {
		"index_builds": _encirclement_index_builds,
		"cache_hits": _encirclement_cache_hits,
		"cache_misses": _encirclement_cache_misses,
		"legacy_evaluations": _encirclement_legacy_evaluations,
		"capital_hops_builds": _capital_hops_cache_builds,
	}


static func _capital_hops_cached(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	var cache_key := "capital_hops:%d" % nation_id
	if evaluation_cache.has(cache_key):
		var cached: Variant = evaluation_cache[cache_key]
		if cached is Dictionary:
			return cached as Dictionary
		return {}
	var hops := RebellionSystem.capital_hops(state, nation_id)
	evaluation_cache[cache_key] = hops
	_capital_hops_cache_builds += 1
	return hops


## A/B 与专项等价测试开关。关闭时 _city_defender_troop_index 恢复到
## legacy 的逐 attacker O(A) 全军扫描；默认启用共享 tick-scope 索引。
static var city_defender_index_disabled: bool = false

## 结盟完整评分会计算方向性战争目标，40 国月结中这是主要尖峰。预筛仅使用
## 完整评分的严格上界；关闭开关用于动作等价门禁。
static var alliance_acceptance_prefilter_disabled: bool = false
static var _alliance_acceptance_prefilter_checks: int = 0
static var _alliance_acceptance_prefilter_prunes: int = 0
static var campaign_v_index_disabled: bool = false
static var _campaign_v_index_builds: int = 0
static var _campaign_v_index_hits: int = 0
static var _campaign_v_legacy_scans: int = 0

static var _city_defender_index_builds: int = 0
static var _city_defender_index_hits: int = 0
static var _city_defender_index_legacy_scans: int = 0


static func reset_city_defender_index_counters() -> void:
	_city_defender_index_builds = 0
	_city_defender_index_hits = 0
	_city_defender_index_legacy_scans = 0


static func city_defender_index_counters() -> Dictionary:
	return {
		"builds": _city_defender_index_builds,
		"hits": _city_defender_index_hits,
		"legacy_scans": _city_defender_index_legacy_scans,
	}


static func reset_defender_index_counters() -> void:
	reset_city_defender_index_counters()


static func defender_index_counters() -> Dictionary:
	return city_defender_index_counters()


static func reset_alliance_acceptance_prefilter_counters() -> void:
	_alliance_acceptance_prefilter_checks = 0
	_alliance_acceptance_prefilter_prunes = 0


static func alliance_acceptance_prefilter_counters() -> Dictionary:
	return {
		"checks": _alliance_acceptance_prefilter_checks,
		"prunes": _alliance_acceptance_prefilter_prunes,
	}


static func reset_campaign_v_index_counters() -> void:
	_campaign_v_index_builds = 0
	_campaign_v_index_hits = 0
	_campaign_v_legacy_scans = 0


static func campaign_v_index_counters() -> Dictionary:
	return {
		"builds": _campaign_v_index_builds,
		"hits": _campaign_v_index_hits,
		"legacy_scans": _campaign_v_legacy_scans,
	}


static func _build_city_defender_owner_index(
	state: GameState,
	evaluation_cache: Dictionary
) -> Dictionary:
	var cache_key := "__global_defender_troops"
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	_city_defender_index_builds += 1
	var city_owner_troops := {}
	for army in state.armies:
		if army.size <= 0:
			continue
		if army.location_city < 0:
			continue
		if not army.state in [Army.State.IDLE, Army.State.RECOVERING]:
			continue
		var city_owners: Dictionary = city_owner_troops.get(
			army.location_city, {}
		)
		city_owners[army.owner_nation] = (
			int(city_owners.get(army.owner_nation, 0))
			+ army.size
		)
		city_owner_troops[army.location_city] = city_owners
	evaluation_cache[cache_key] = city_owner_troops
	return city_owner_troops


static func choose_actions(
	state: GameState,
	profile: Dictionary = {},
	use_structure_cache: bool = true,
	seeded_evaluation_cache: Dictionary = {}
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var committed := {}
	var evaluation_cache := seeded_evaluation_cache.duplicate()
	if not use_structure_cache:
		evaluation_cache["__disable_structure_cache"] = true
	var profile_enabled := bool(profile.get("enabled", false))
	if profile_enabled:
		evaluation_cache["__profile"] = profile
	var profile_started := (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	_collect_peace_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_record_profile_stage(
		profile,
		"diplomacy_peace",
		profile_started,
		profile_enabled
	)
	profile_started = Time.get_ticks_usec() if profile_enabled else 0
	_collect_existing_war_preparation_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_record_profile_stage(
		profile,
		"diplomacy_war_preparation",
		profile_started,
		profile_enabled
	)
	profile_started = Time.get_ticks_usec() if profile_enabled else 0
	_collect_leave_alliance_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_record_profile_stage(
		profile,
		"diplomacy_leave_alliance",
		profile_started,
		profile_enabled
	)
	profile_started = Time.get_ticks_usec() if profile_enabled else 0
	_collect_enfeoff_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_record_profile_stage(
		profile,
		"diplomacy_enfeoff",
		profile_started,
		profile_enabled
	)
	profile_started = Time.get_ticks_usec() if profile_enabled else 0
	_collect_war_actions(
		state,
		actions,
		committed,
		evaluation_cache,
		0,
		-1,
		false
	)
	_record_profile_stage(
		profile,
		"diplomacy_war",
		profile_started,
		profile_enabled
	)
	profile_started = Time.get_ticks_usec() if profile_enabled else 0
	_collect_alliance_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_record_profile_stage(
		profile,
		"diplomacy_alliance",
		profile_started,
		profile_enabled
	)
	profile_started = Time.get_ticks_usec() if profile_enabled else 0
	_collect_centralization_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_record_profile_stage(
		profile,
		"diplomacy_centralization",
		profile_started,
		profile_enabled
	)
	return actions


## 运行时版本保持与 choose_actions 完全相同的收集/提交顺序，只在阶段边界及
## 单国战争评估后让出主循环。外交计算主要是 GDScript 图搜索；把整个调用塞进
## 单个 worker 仍可能长期占用解释器与内存带宽，无法保证渲染及时获得执行机会。
static func choose_actions_over_frames(
	state: GameState,
	use_structure_cache: bool = true,
	seeded_evaluation_cache: Dictionary = {},
	slice_budget_usec: int = 6000
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var committed := {}
	var evaluation_cache := seeded_evaluation_cache.duplicate()
	if not use_structure_cache:
		evaluation_cache["__disable_structure_cache"] = true
	var slice_started := Time.get_ticks_usec()
	_collect_peace_actions(state, actions, committed, evaluation_cache)
	slice_started = await _yield_diplomacy_slice(
		slice_started, slice_budget_usec
	)
	for nation_index in range(state.nations.size()):
		_collect_existing_war_preparation_actions(
			state,
			actions,
			committed,
			evaluation_cache,
			nation_index,
			nation_index + 1
		)
		slice_started = await _yield_diplomacy_slice(
			slice_started, slice_budget_usec
		)
	_collect_leave_alliance_actions(
		state, actions, committed, evaluation_cache
	)
	slice_started = await _yield_diplomacy_slice(
		slice_started, slice_budget_usec
	)
	_collect_enfeoff_actions(state, actions, committed, evaluation_cache)
	slice_started = await _yield_diplomacy_slice(
		slice_started, slice_budget_usec
	)
	for nation_index in range(state.nations.size()):
		_collect_war_actions(
			state,
			actions,
			committed,
			evaluation_cache,
			nation_index,
			nation_index + 1,
			false
		)
		slice_started = await _yield_diplomacy_slice(
			slice_started, slice_budget_usec
		)
	for nation_index in range(state.nations.size()):
		_collect_alliance_actions(
			state,
			actions,
			committed,
			evaluation_cache,
			nation_index,
			nation_index + 1
		)
		slice_started = await _yield_diplomacy_slice(
			slice_started, slice_budget_usec
		)
	_collect_centralization_actions(
		state, actions, committed, evaluation_cache
	)
	return actions


static func _yield_diplomacy_slice(
	slice_started: int,
	slice_budget_usec: int
) -> int:
	if (
		slice_budget_usec > 0
		and Time.get_ticks_usec() - slice_started >= slice_budget_usec
	):
		await (Engine.get_main_loop() as SceneTree).process_frame
		return Time.get_ticks_usec()
	return slice_started


static func _record_profile_stage(
	profile: Dictionary,
	stage: String,
	started_usec: int,
	enabled: bool
) -> void:
	if enabled:
		profile[stage] = Time.get_ticks_usec() - started_usec


static func _record_evaluation_profile(
	evaluation_cache: Dictionary,
	stage: String,
	started_usec: int
) -> void:
	var profile: Dictionary = evaluation_cache.get(
		"__profile",
		{}
	)
	if profile.is_empty():
		return
	profile[stage] = (
		int(profile.get(stage, 0))
		+ Time.get_ticks_usec() - started_usec
	)


static func peace_willingness(state: GameState, nation_id: int, enemy_id: int) -> float:
	return float(
		peace_willingness_breakdown(
			state,
			nation_id,
			enemy_id
		)["score"]
	)


static func peace_willingness_breakdown(
	state: GameState,
	nation_id: int,
	enemy_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	var cache_key := "peace:%d:%d" % [
		nation_id,
		enemy_id,
	]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	if not state.is_enemy(nation_id, enemy_id):
		return {"score": -INF}
	var part_started := (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var own_power := _national_power(
		state,
		nation_id,
		evaluation_cache
	)
	var enemy_power := _national_power(
		state,
		enemy_id,
		evaluation_cache
	)
	var power_balance := (
		(own_power - enemy_power)
		/ maxf(maxf(own_power, enemy_power), 1.0)
	)
	var war_days := state.day - state.relation_since(nation_id, enemy_id)
	var extra_wars := maxi(
		_distinct_enemy_coalition_count(
			state,
			nation_id,
			evaluation_cache
		) - 1,
		0
	)
	_record_evaluation_profile(
		evaluation_cache,
		"peace_power_wars",
		part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var no_front := (
		1.0
		if _frontier_edges(
			state,
			nation_id,
			enemy_id,
			evaluation_cache
		) == 0
		else 0.0
	)
	var situation_score := war_situation_score(
		state,
		nation_id,
		enemy_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache,
		"peace_situation",
		part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var resource_report := resource_report(
		state,
		nation_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache,
		"peace_resources",
		part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var gold_endurance := clampf(
		float(resource_report["gold_runway_months"])
			/ PEACE_RESOURCE_REFERENCE_MONTHS,
		0.0,
		1.0
	)
	var food_endurance := clampf(
		float(resource_report["food_coverage_months"])
			/ PEACE_RESOURCE_REFERENCE_MONTHS,
		0.0,
		1.0
	)
	var resource_endurance := minf(
		gold_endurance,
		food_endurance
	)
	var resource_pressure := (
		1.0 - 2.0 * resource_endurance
	)
	if state.nations[nation_id].unpaid_military_upkeep > 0:
		resource_pressure += 1.0
	var external_threat := _neutral_border_massing_ratio(
		state,
		nation_id,
		enemy_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache,
		"peace_external_threat",
		part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var aggression := state.effective_ai_aggression(nation_id)
	var war_fatigue := (
		float(war_days) / float(WAR_FATIGUE_REFERENCE_DAYS)
	)
	# 统一时代衰减战争疲劳：均势期战争疲劳随时间无界推高求和，是“打起来却灭不掉国”
	# 的主因。时代成熟后，占优方（power_balance>0）的时间疲劳逐步归零，战争必须以
	# 逆转、资源崩溃或一方灭亡收敛；劣势方仍保留原求和意愿。
	if power_balance > 0.0:
		war_fatigue *= 1.0 - unification_era_factor(state)
	var situation_component := (
		-situation_score * PEACE_SITUATION_WEIGHT
	)
	var power_component := (
		-power_balance * PEACE_POWER_BALANCE_WEIGHT
	)
	var resource_component := (
		resource_pressure * PEACE_RESOURCE_ENDURANCE_WEIGHT
	)
	var international_component := (
		external_threat * PEACE_EXTERNAL_THREAT_WEIGHT
	)
	var attitude := diplomatic_attitude(
		state,
		nation_id,
		enemy_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache,
		"peace_attitude",
		part_started
	)
	var attitude_component := attitude * ATTITUDE_PEACE_WEIGHT
	var base_score := (
		war_fatigue
		+ situation_component
		+ power_component
		+ resource_component
		+ international_component
		+ attitude_component
		+ float(extra_wars) * 0.75
		+ no_front
		- (aggression - 1.0) * 0.50
	)
	# 君主只缩放议和的软意愿；战争时长、双方接受线及资源生存判据仍由
	# 各自的硬门槛独立约束，不能靠性格绕过。
	var peace_multiplier := RulerProfile.peace_multiplier(
		state.nations[nation_id]
	)
	var score := base_score * peace_multiplier
	var result := {
		"score": score,
		"base_score": base_score,
		"peace_multiplier": peace_multiplier,
		"war_fatigue": war_fatigue,
		"situation_score": situation_score,
		"situation_component": situation_component,
		"power_balance": power_balance,
		"power_component": power_component,
		"resource_endurance": resource_endurance,
		"resource_component": resource_component,
		"external_threat": external_threat,
		"international_component": international_component,
		"attitude": attitude,
		"attitude_component": attitude_component,
		"extra_wars": extra_wars,
		"no_front": no_front,
		"aggression": aggression,
	}
	evaluation_cache[cache_key] = result
	return result


static func peace_assessment(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	if not state.is_enemy(nation_a, nation_b):
		return {
			"acceptable": false,
			"score_a": -INF,
			"score_b": -INF,
			"combined_score": -INF,
			"proposer": -1,
			"responder": -1,
		}
	if state.regional_rebellion_peace_locked(nation_a, nation_b):
		return {
			"acceptable": false,
			"score_a": -INF,
			"score_b": -INF,
			"combined_score": -INF,
			"proposer": -1,
			"responder": -1,
			"rebellion_war_locked": true,
		}
	var part_started := (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var bloc_a := _cached_alliance_bloc(
		state, nation_a, evaluation_cache
	)
	var bloc_b := _cached_alliance_bloc(
		state, nation_b, evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache,
		"peace_blocs",
		part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var breakdown_a := _coalition_peace_breakdown(
		state,
		bloc_a,
		bloc_b,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache,
		"peace_coalition_breakdown",
		part_started
	)
	var breakdown_b := _coalition_peace_breakdown(
		state,
		bloc_b,
		bloc_a,
		evaluation_cache
	)
	var score_a := float(breakdown_a["score"])
	var score_b := float(breakdown_b["score"])
	var proposer := -1
	var responder := -1
	if not is_equal_approx(score_a, score_b):
		proposer = nation_a if score_a > score_b else nation_b
		responder = nation_b if proposer == nation_a else nation_a
	var proposal_score := maxf(score_a, score_b)
	var combined_score := score_a + score_b
	var war_started_day := state.day
	for member_a in bloc_a:
		for member_b in bloc_b:
			if state.is_enemy(member_a, member_b):
				war_started_day = mini(
					war_started_day,
					state.relation_since(member_a, member_b)
				)
	var war_days := state.day - war_started_day
	var stalemate := (
		war_days >= PEACE_STALEMATE_DAYS
		and absf(float(breakdown_a.get("situation_score", 0.0))) <= 0.75
		and absf(float(breakdown_b.get("situation_score", 0.0))) <= 0.75
	)
	var consent_a := score_a >= PEACE_ACCEPT_SCORE or stalemate
	var consent_b := score_b >= PEACE_ACCEPT_SCORE or stalemate
	return {
		"acceptable": (
			war_days >= MIN_WAR_DAYS
			and proposal_score >= PEACE_PROPOSE_SCORE
			and consent_a
			and consent_b
		),
		"consent_a": consent_a,
		"consent_b": consent_b,
		"stalemate": stalemate,
		"score_a": score_a,
		"score_b": score_b,
		"willingness_a": score_a,
		"willingness_b": score_b,
		"breakdown_a": breakdown_a,
		"breakdown_b": breakdown_b,
		"bloc_a": bloc_a,
		"bloc_b": bloc_b,
		"combined_score": combined_score,
		"proposer": proposer,
		"responder": responder,
	}


static func _coalition_peace_breakdown(
	state: GameState,
	own_bloc: Array[int],
	enemy_bloc: Array[int],
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	var own_key := _nation_list_key(own_bloc)
	var enemy_key := _nation_list_key(enemy_bloc)
	var cache_key := "coalition_peace:%s:%s" % [own_key, enemy_key]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var weighted_score := 0.0
	var weighted_attitude := 0.0
	var weighted_power_component := 0.0
	var weighted_extra_war_component := 0.0
	var weighted_no_front_component := 0.0
	var own_weight_total := 0.0
	var member_scores := {}
	for member_id in own_bloc:
		var own_weight := maxf(
			_national_power(state, member_id, evaluation_cache),
			1.0
		)
		var member_score := 0.0
		var member_attitude := 0.0
		var member_power_component := 0.0
		var member_extra_war_component := 0.0
		var member_no_front_component := 0.0
		var enemy_weight_total := 0.0
		for enemy_id in enemy_bloc:
			if not state.is_enemy(member_id, enemy_id):
				continue
			var enemy_weight := maxf(
				_national_power(state, enemy_id, evaluation_cache),
				1.0
			)
			var breakdown := peace_willingness_breakdown(
				state,
				member_id,
				enemy_id,
				evaluation_cache
			)
			member_score += float(breakdown["score"]) * enemy_weight
			member_attitude += float(
				breakdown.get("attitude", 0.0)
			) * enemy_weight
			member_power_component += float(
				breakdown.get("power_component", 0.0)
			) * enemy_weight
			member_extra_war_component += (
				float(breakdown.get("extra_wars", 0)) * 0.75
				* enemy_weight
			)
			member_no_front_component += float(
				breakdown.get("no_front", 0.0)
			) * enemy_weight
			enemy_weight_total += enemy_weight
		if enemy_weight_total <= 0.0:
			continue
		member_score /= enemy_weight_total
		member_attitude /= enemy_weight_total
		member_power_component /= enemy_weight_total
		member_extra_war_component /= enemy_weight_total
		member_no_front_component /= enemy_weight_total
		member_scores[member_id] = member_score
		weighted_score += member_score * own_weight
		weighted_attitude += member_attitude * own_weight
		weighted_power_component += member_power_component * own_weight
		weighted_extra_war_component += (
			member_extra_war_component * own_weight
		)
		weighted_no_front_component += (
			member_no_front_component * own_weight
		)
		own_weight_total += own_weight
	var score := (
		weighted_score / own_weight_total
		if own_weight_total > 0.0
		else -INF
	)
	var own_power := 0.0
	for member_id in own_bloc:
		own_power += _national_power(
			state,
			member_id,
			evaluation_cache
		)
	var enemy_power := 0.0
	for enemy_id in enemy_bloc:
		enemy_power += _national_power(
			state,
			enemy_id,
			evaluation_cache
		)
	var coalition_power_balance := (
		(own_power - enemy_power)
		/ maxf(maxf(own_power, enemy_power), 1.0)
	)
	var coalition_power_component := (
		-coalition_power_balance * PEACE_POWER_BALANCE_WEIGHT
	)
	var coalition_extra_wars := maxi(
		_distinct_enemy_coalition_count_for_bloc(
			state,
			own_bloc,
			evaluation_cache
		) - 1,
		0
	)
	var coalition_no_front := 1.0
	for member_id in own_bloc:
		for enemy_id in enemy_bloc:
			if _frontier_edges(
				state,
				member_id,
				enemy_id,
				evaluation_cache
			) > 0:
				coalition_no_front = 0.0
				break
		if coalition_no_front <= 0.0:
			break
	if own_weight_total > 0.0:
		score += (
			coalition_power_component
			- weighted_power_component / own_weight_total
			+ float(coalition_extra_wars) * 0.75
			- weighted_extra_war_component / own_weight_total
			+ coalition_no_front
			- weighted_no_front_component / own_weight_total
		)
	var result := {
		"score": score,
		"attitude": (
			weighted_attitude / own_weight_total
			if own_weight_total > 0.0
			else 0.0
		),
		"members": own_bloc.duplicate(),
		"member_scores": member_scores,
		"power_balance": coalition_power_balance,
		"power_component": coalition_power_component,
		"extra_wars": coalition_extra_wars,
		"no_front": coalition_no_front,
	}
	evaluation_cache[cache_key] = result
	return result


static func _distinct_enemy_coalition_count(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "enemy_coalition_count:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	return _distinct_enemy_coalition_count_for_bloc(
		state,
		_cached_alliance_bloc(
			state, nation_id, evaluation_cache
		),
		evaluation_cache
	)


static func _distinct_enemy_coalition_count_for_bloc(
	state: GameState,
	own_bloc: Array[int],
	evaluation_cache: Dictionary = {}
) -> int:
	var own_key := _nation_list_key(own_bloc)
	var cache_key := "enemy_coalition_count_bloc:%s" % own_key
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var enemy_blocs := {}
	for member_id in own_bloc:
		for enemy_id in _cached_wars_of(
			state, member_id, evaluation_cache
		):
			enemy_blocs[
				_nation_list_key(_cached_alliance_bloc(
					state, enemy_id, evaluation_cache
				))
			] = true
	var result := enemy_blocs.size()
	if not bool(evaluation_cache.get(
		"__disable_structure_cache", false
	)):
		evaluation_cache[cache_key] = result
		for member_id in own_bloc:
			evaluation_cache[
				"enemy_coalition_count:%d" % member_id
			] = result
	return result


static func war_situation_score(
	state: GameState,
	nation_id: int,
	enemy_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "situation:%d:%d" % [
		nation_id,
		enemy_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var score := 0.0
	var bilateral_value := 0.0
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		var controller := state.cities[center_id].owner_nation
		for city_id in _cached_administrative_members(
			state, center_id, evaluation_cache
		):
			var legal_owner := state.recognized_owner_of(city_id)
			if legal_owner not in [nation_id, enemy_id]:
				continue
			var city_value := _military_city_value(state.cities[city_id])
			bilateral_value += city_value
			if controller == nation_id and legal_owner == enemy_id:
				score += city_value
			elif controller == enemy_id and legal_owner == nation_id:
				score -= city_value
	# Docks have no administrative seat and retain node-level war value.
	for city in state.cities:
		if not city.is_dock:
			continue
		var legal_owner := state.recognized_owner_of(city.id)
		if legal_owner not in [nation_id, enemy_id]:
			continue
		var city_value := _military_city_value(city)
		bilateral_value += city_value
		var occupying_side := _occupation_side(
			state, city, nation_id, enemy_id
		)
		if occupying_side == nation_id and legal_owner == enemy_id:
			score += city_value
		elif occupying_side == enemy_id and legal_owner == nation_id:
			score -= city_value
	var result := (
		score * 4.0 / maxf(bilateral_value, 1.0)
	)
	evaluation_cache[cache_key] = result
	return result


## 方向性外交态度：正值表示合作倾向，负值表示敌对倾向。
## 三层分量只读取可观察事实，外交动作本身仍由各自效用和硬约束决定。
static func diplomatic_attitude(
	state: GameState,
	nation_id: int,
	other_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	return float(
		diplomatic_attitude_breakdown(
			state,
			nation_id,
			other_id,
			evaluation_cache
		)["score"]
	)


static func diplomatic_attitude_breakdown(
	state: GameState,
	nation_id: int,
	other_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	if (
		nation_id == other_id
		or nation_id < 0
		or other_id < 0
		or nation_id >= state.nations.size()
		or other_id >= state.nations.size()
	):
		return {
			"score": 0.0,
			"historical": 0.0,
			"military": 0.0,
			"political": 0.0,
		}
	var cache_key := "attitude:%d:%d" % [
		nation_id,
		other_id,
	]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var part_started := (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var historical := _historical_attitude(
		state,
		nation_id,
		other_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache, "attitude_history", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var frontier_count := _frontier_edges(
		state,
		nation_id,
		other_id,
		evaluation_cache
	)
	var border_component := maxf(
		-float(frontier_count) * BORDER_ATTITUDE_PER_EDGE,
		BORDER_ATTITUDE_FLOOR
	)
	var objective := _cached_war_objective(
		state,
		nation_id,
		other_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache, "attitude_frontier_objective", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var objective_value := float(objective.get("value", 0.0))
	var objective_component := maxf(
		-objective_value * OBJECTIVE_ATTITUDE_PER_VALUE,
		OBJECTIVE_ATTITUDE_FLOOR
	)
	var military := border_component + objective_component
	var common_enemies := _common_enemy_count(
		state,
		nation_id,
		other_id,
		evaluation_cache
	)
	var enemy_allies := _enemy_alliance_count(
		state,
		nation_id,
		other_id,
		evaluation_cache
	)
	var frontier_relief := (
		0.0
		if state.is_enemy(nation_id, other_id)
		else _alliance_frontier_release_value(
			state,
			nation_id,
			other_id,
			evaluation_cache
		)
	)
	_record_evaluation_profile(
		evaluation_cache, "attitude_political", part_started
	)
	var political := (
		float(common_enemies) * COMMON_ENEMY_ATTITUDE
		+ frontier_relief
		+ float(enemy_allies) * ENEMY_ALLY_ATTITUDE
	)
	var parent_rebel_component := (
		PARENT_REBEL_ATTITUDE
		if state.regional_rebellion_parent(other_id) == nation_id
		else 0.0
	)
	political += parent_rebel_component
	var result := {
		"score": historical + military + political,
		"historical": historical,
		"military": military,
		"political": political,
		"border_edges": frontier_count,
		"border_component": border_component,
		"objective_city": int(objective.get("city_id", -1)),
		"objective_value": objective_value,
		"objective_component": objective_component,
		"common_enemies": common_enemies,
		"enemy_allies": enemy_allies,
		"frontier_relief": frontier_relief,
		"parent_rebel_component": parent_rebel_component,
	}
	evaluation_cache[cache_key] = result
	return result


static func _historical_attitude(
	state: GameState,
	nation_id: int,
	other_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "history:%d:%d" % [
		nation_id,
		other_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	if not bool(evaluation_cache.get(
		"__disable_structure_cache", false
	)):
		_build_historical_attitude_matrix(
			state, evaluation_cache
		)
		return float(evaluation_cache.get(cache_key, 0.0))
	var revenge := 0.0
	for event in state.diplomatic_history:
		if (
			int(event.get("action", Action.NONE))
				!= Action.MAKE_PEACE
		):
			continue
		var event_a := int(event.get("nation_a", -1))
		var event_b := int(event.get("nation_b", -1))
		var bloc_a: Array = event.get("bloc_a", [event_a])
		var bloc_b: Array = event.get("bloc_b", [event_b])
		var nation_on_a := bloc_a.has(nation_id)
		var nation_on_b := bloc_b.has(nation_id)
		if not (
			(nation_on_a and bloc_b.has(other_id))
			or (nation_on_b and bloc_a.has(other_id))
		):
			continue
		var outcome := (
			float(event.get("war_outcome_a", 0.0))
				if nation_on_a
			else float(event.get("war_outcome_b", 0.0))
		)
		var defeat := maxf(
			-outcome * REVENGE_PER_LOST_SITUATION_POINT,
			0.0
		)
		if int(event.get("surrendering_nation", -1)) == nation_id:
			defeat = maxf(defeat, REVENGE_SURRENDER_PENALTY)
		revenge += defeat
	var result := maxf(-revenge, REVENGE_ATTITUDE_FLOOR)
	evaluation_cache[cache_key] = result
	return result


## 单遍外交历史构建所有方向性的复仇态度。旧实现对每个国家对重扫完整历史；
## 一次月度外交评估内历史冻结，故可把每条集团和平事件直接展开到双方成员对。
static func _build_historical_attitude_matrix(
	state: GameState,
	evaluation_cache: Dictionary
) -> void:
	if evaluation_cache.has("historical_attitude_matrix_built"):
		return
	evaluation_cache["historical_attitude_matrix_built"] = true
	var revenge_by_pair := {}
	for event in state.diplomatic_history:
		if int(event.get("action", Action.NONE)) != Action.MAKE_PEACE:
			continue
		var event_a := int(event.get("nation_a", -1))
		var event_b := int(event.get("nation_b", -1))
		var bloc_a: Array = event.get("bloc_a", [event_a])
		var bloc_b: Array = event.get("bloc_b", [event_b])
		var outcome_a := float(event.get("war_outcome_a", 0.0))
		var outcome_b := float(event.get("war_outcome_b", 0.0))
		var surrendering := int(event.get("surrendering_nation", -1))
		for nation_value in bloc_a:
			var nation_id := int(nation_value)
			var defeat := maxf(
				-outcome_a * REVENGE_PER_LOST_SITUATION_POINT,
				0.0
			)
			if surrendering == nation_id:
				defeat = maxf(defeat, REVENGE_SURRENDER_PENALTY)
			if defeat <= 0.0:
				continue
			for other_value in bloc_b:
				var key := "%d:%d" % [nation_id, int(other_value)]
				revenge_by_pair[key] = (
					float(revenge_by_pair.get(key, 0.0)) + defeat
				)
		for nation_value in bloc_b:
			var nation_id := int(nation_value)
			var defeat := maxf(
				-outcome_b * REVENGE_PER_LOST_SITUATION_POINT,
				0.0
			)
			if surrendering == nation_id:
				defeat = maxf(defeat, REVENGE_SURRENDER_PENALTY)
			if defeat <= 0.0:
				continue
			for other_value in bloc_a:
				var key := "%d:%d" % [nation_id, int(other_value)]
				revenge_by_pair[key] = (
					float(revenge_by_pair.get(key, 0.0)) + defeat
				)
	for pair_key_value in revenge_by_pair:
		var pair_key := str(pair_key_value)
		evaluation_cache["history:%s" % pair_key] = maxf(
			-float(revenge_by_pair[pair_key]),
			REVENGE_ATTITUDE_FLOOR
		)


static func _enemy_alliance_count(
	state: GameState,
	nation_id: int,
	other_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "enemy_allies:%d:%d" % [
		nation_id,
		other_id,
	]
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var count := 0
	for enemy_id in _cached_wars_of(
		state,
		nation_id,
		evaluation_cache
	):
		if enemy_id != other_id and state.is_allied(other_id, enemy_id):
			count += 1
	evaluation_cache[cache_key] = count
	return count


## 统一竞争只来自经营区域的领土利益，不随全图时间或存活国数量增强。
static func unification_rivalry(
	state: GameState,
	nation_id: int,
	other_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "unification:%d:%d:%d:%d:%d" % [
		mini(nation_id, other_id), maxi(nation_id, other_id),
		state.regional_strategy_revision, state.ownership_revision, state.diplomacy_revision,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var result := RegionalStrategy.rivalry(state, nation_id, other_id)
	evaluation_cache[cache_key] = result
	return result


## Existing resource and peace pacing; not used to create regional rivalry.
static func unification_era_factor(state: GameState) -> float:
	return clampf((float(state.day) / 365.0 - UNIFICATION_ERA_ONSET_YEARS)
		/ float(UNIFICATION_ERA_FULL_YEARS - UNIFICATION_ERA_ONSET_YEARS), 0.0, 1.0)


static func _occupation_side(
	state: GameState,
	city: City,
	nation_id: int,
	enemy_id: int
) -> int:
	if city.occupation_sponsor_nation in [nation_id, enemy_id]:
		return city.occupation_sponsor_nation
	if (
		city.owner_nation == nation_id
		or state.is_allied(city.owner_nation, nation_id)
	):
		return nation_id
	if (
		city.owner_nation == enemy_id
		or state.is_allied(city.owner_nation, enemy_id)
	):
		return enemy_id
	return -1


static func _military_city_value(city: City) -> float:
	return (
		1.0
		+ (2.0 if city.is_capital else 0.0)
		+ (1.0 if city.has_warehouse else 0.0)
		+ (0.75 if city.is_food_hub else 0.0)
		+ (0.75 if city.is_manpower_hub else 0.0)
		+ (0.50 if city.is_dock else 0.0)
	)


static func peace_reasons(
	state: GameState,
	nation_id: int,
	enemy_id: int,
	evaluation_cache: Dictionary = {}
) -> Array[String]:
	var reasons: Array[String] = []
	var report := resource_report(
		state,
		nation_id,
		evaluation_cache
	)
	var food_plan := war_food_report(
		state,
		nation_id,
		-1,
		-1,
		evaluation_cache
	)
	var nation := state.nations[nation_id]
	var breakdown := peace_willingness_breakdown(
		state,
		nation_id,
		enemy_id,
		evaluation_cache
	)
	if (
		breakdown.has("situation_score")
		and float(breakdown["situation_score"]) < -0.01
	):
		reasons.append(
			"重要军事城市失守，战局分 %.2f"
			% float(breakdown["situation_score"])
		)
	if (
		breakdown.has("power_balance")
		and float(breakdown["power_balance"]) < -0.10
	):
		reasons.append(
			"当前军力处于劣势 %.0f%%"
			% (-float(breakdown["power_balance"]) * 100.0)
		)
	if (
		breakdown.has("external_threat")
		and float(breakdown["external_threat"]) > 0.05
	):
		reasons.append(
			"中立邻国在边境集结，威胁比 %.2f，需要调转战线"
			% float(breakdown["external_threat"])
		)
	if (
		nation.unpaid_military_upkeep > 0
		or (
			int(report["monthly_gold_balance"]) < 0
			and float(report["gold_runway_months"]) < CAMPAIGN_RESERVE_MONTHS
		)
	):
		if nation.unpaid_military_upkeep > 0:
			reasons.append(
				"国库%d金，本月军费实际缺口%d"
				% [
					nation.treasury_gold,
					nation.unpaid_military_upkeep,
				]
			)
		else:
			reasons.append(
				"月入%d、军费%d，国库%d金仅能支撑%.1f个月"
				% [
					report["monthly_gold_income"],
					report["monthly_war_cost"],
					nation.treasury_gold,
					report["gold_runway_months"],
				]
			)
	if (
		float(food_plan["target_runway_years"])
			< float(food_plan["required_campaign_years"])
		or int(report["food_stock"])
			< int(food_plan["emergency_food_reserve"])
	):
		reasons.append(
			"粮草年结余%.0f，库存%d，仅能支撑约%.1f年（计划%.1f年）"
			% [
				food_plan["target_annual_balance"],
				report["food_stock"],
				food_plan["target_runway_years"],
				food_plan["required_campaign_years"],
			]
		)
	var emergency_manpower := maxi(
		1000,
		int(ceil(float(report["troops"]) * 0.05))
	)
	if nation.manpower_pool < emergency_manpower:
		reasons.append(
			"可用人力 %d 低于应急线 %d"
			% [nation.manpower_pool, emergency_manpower]
		)
	var objective := state.war_objective(nation_id, enemy_id)
	if not objective.is_empty():
		var objective_city := int(objective["city_id"])
		var attacker := int(objective["attacker"])
		if (
			objective_city >= 0
			and objective_city < state.cities.size()
			and state.cities[objective_city].owner_nation == attacker
		):
			reasons.append(
				(
					"本国战争目标城市 %d 已被控制"
					if attacker == nation_id
					else "敌国战争目标城市 %d 已失守"
				) % objective_city
			)
	return reasons


static func alliance_willingness(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var cache_key := "alliance:%d:%d" % [
		nation_id,
		target_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var part_started := (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	if state.relation_between(nation_id, target_id) != GameState.DiplomaticRelation.NEUTRAL:
		return -INF
	if not within_diplomatic_range(
		state, nation_id, target_id, evaluation_cache
	):
		evaluation_cache[cache_key] = -INF
		return -INF
	if (
		_cached_allies_of(
			state,
			nation_id,
			evaluation_cache
		).size() >= MAX_DEFENSIVE_ALLIES
		or _cached_allies_of(
			state,
			target_id,
			evaluation_cache
		).size() >= MAX_DEFENSIVE_ALLIES
	):
		return -INF
	if state.day - state.relation_since(nation_id, target_id) < MIN_NEUTRAL_DAYS:
		return -INF
	if _alliance_has_active_conflict(
		state,
		nation_id,
		target_id,
		evaluation_cache
	):
		return -INF
	_record_evaluation_profile(
		evaluation_cache, "alliance_gate", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var own_power := _national_power(
		state,
		nation_id,
		evaluation_cache
	)
	var target_power := _national_power(
		state,
		target_id,
		evaluation_cache
	)
	var imbalance := absf(log(maxf(own_power, 1.0) / maxf(target_power, 1.0)))
	_record_evaluation_profile(
		evaluation_cache, "alliance_common_power", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var shared_threat := _shared_threat(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache, "alliance_shared_threat", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var balance_affinity := maxf(1.0 - imbalance, 0.0) * 0.55
	var frontier_release := _alliance_frontier_release_value(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache, "alliance_frontier_release", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var attitude := diplomatic_attitude(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	var unification_pressure := unification_rivalry(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	_record_evaluation_profile(
		evaluation_cache, "alliance_attitude_unification", part_started
	)
	var base_result := (
		0.35
		+ minf(shared_threat * 0.35, 0.80)
		+ balance_affinity
		+ frontier_release
		+ attitude * ATTITUDE_ALLIANCE_WEIGHT
		- unification_pressure
	)
	var result := base_result * RulerProfile.alliance_multiplier(
		state.nations[nation_id]
	)
	result = minf(result, _alliance_strength_score_cap(state, nation_id, target_id, evaluation_cache))
	evaluation_cache[cache_key] = result
	return result


static func _alliance_strength_score_cap(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary
) -> float:
	const CACHE_KEY := "alliance_strength_caps"
	if not evaluation_cache.has(CACHE_KEY):
		_build_nation_aggregates(state, evaluation_cache)
		var roots: Dictionary = RegionalStrategy.control(state)["roots"]
		var powers := {}
		var total := 0.0
		for nation in state.nations:
			if not nation.alive:
				continue
			var root_id := int(roots.get(nation.id, nation.id))
			var power := _national_power(state, nation.id, evaluation_cache)
			powers[root_id] = float(powers.get(root_id, 0.0)) + power
			total += power
		var strong_threshold := minf(
			total / float(maxi(powers.size(), 1)) * ALLIANCE_STRONG_AVERAGE_RATIO,
			total * ALLIANCE_STRONG_WORLD_SHARE
		)
		var caps := {}
		for nation in state.nations:
			var root_id := int(roots.get(nation.id, nation.id))
			caps[nation.id] = (
				ALLIANCE_STRONG_SCORE_CAP
				if total > 0.0 and float(powers.get(root_id, 0.0)) >= strong_threshold
				else INF
			)
		evaluation_cache[CACHE_KEY] = caps
	var caps: Dictionary = evaluation_cache[CACHE_KEY]
	return minf(float(caps.get(nation_id, INF)), float(caps.get(target_id, INF)))


## 保守的结盟接受门槛。先计算不依赖战争目标评分的完整态度，再省略始终非正的
## 目标敌意。所得仍是严格上界，却能在构建昂贵目标评分前淘汰更多不可能的结盟。
static func _alliance_can_reach_acceptance(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	if alliance_acceptance_prefilter_disabled:
		return true
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var cache_key := "alliance_acceptance_possible:%d:%d" % [
		nation_id, target_id,
	]
	var upper_bound_key := "alliance_acceptance_upper_bound:%d:%d" % [
		nation_id, target_id,
	]
	if evaluation_cache.has(cache_key):
		return bool(evaluation_cache[cache_key])
	_alliance_acceptance_prefilter_checks += 1
	if (
		state.relation_between(nation_id, target_id)
			!= GameState.DiplomaticRelation.NEUTRAL
		or not within_diplomatic_range(
			state, nation_id, target_id, evaluation_cache
		)
		or _cached_allies_of(
			state, nation_id, evaluation_cache
		).size() >= MAX_DEFENSIVE_ALLIES
		or _cached_allies_of(
			state, target_id, evaluation_cache
		).size() >= MAX_DEFENSIVE_ALLIES
		or state.day - state.relation_since(nation_id, target_id)
			< MIN_NEUTRAL_DAYS
		or _alliance_has_active_conflict(
			state, nation_id, target_id, evaluation_cache
		)
	):
		evaluation_cache[cache_key] = false
		evaluation_cache[upper_bound_key] = -INF
		_alliance_acceptance_prefilter_prunes += 1
		return false
	var strength_cap := _alliance_strength_score_cap(state, nation_id, target_id, evaluation_cache)
	if strength_cap < ALLIANCE_ACCEPT_SCORE:
		evaluation_cache[cache_key] = false
		evaluation_cache[upper_bound_key] = strength_cap
		_alliance_acceptance_prefilter_prunes += 1
		return false
	var common_enemies := _common_enemy_count(
		state, nation_id, target_id, evaluation_cache
	)
	var own_power := _national_power(state, nation_id, evaluation_cache)
	var target_power := _national_power(state, target_id, evaluation_cache)
	var imbalance := absf(log(
		maxf(own_power, 1.0) / maxf(target_power, 1.0)
	))
	var frontier_count := _frontier_edges(
		state, nation_id, target_id, evaluation_cache
	)
	var shared_threat := _shared_threat(
		state, nation_id, target_id, evaluation_cache
	)
	var frontier_release := _alliance_frontier_release_value(
		state, nation_id, target_id, evaluation_cache
	)
	var unification_pressure := unification_rivalry(
		state, nation_id, target_id, evaluation_cache
	)
	var historical := _historical_attitude(
		state, nation_id, target_id, evaluation_cache
	)
	var border_component := maxf(
		-float(frontier_count) * BORDER_ATTITUDE_PER_EDGE,
		BORDER_ATTITUDE_FLOOR
	)
	var enemy_allies := _enemy_alliance_count(
		state, nation_id, target_id, evaluation_cache
	)
	var parent_rebel_component := (
		PARENT_REBEL_ATTITUDE
		if state.regional_rebellion_parent(target_id) == nation_id
		else 0.0
	)
	var maximum_attitude := (
		historical
		+ border_component
		+ float(common_enemies) * COMMON_ENEMY_ATTITUDE
		+ frontier_release
		+ float(enemy_allies) * ENEMY_ALLY_ATTITUDE
		+ parent_rebel_component
	)
	var upper_bound := (
		0.35
		+ minf(shared_threat * 0.35, 0.80)
		+ maxf(1.0 - imbalance, 0.0) * 0.55
		+ frontier_release
		+ maximum_attitude * ATTITUDE_ALLIANCE_WEIGHT
		- unification_pressure
	) * RulerProfile.alliance_multiplier(state.nations[nation_id])
	evaluation_cache[upper_bound_key] = upper_bound
	var possible := upper_bound >= ALLIANCE_ACCEPT_SCORE
	evaluation_cache[cache_key] = possible
	if not possible:
		_alliance_acceptance_prefilter_prunes += 1
	return possible


static func _shared_threat(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary
) -> float:
	var cache_key := "shared_threat:%d:%d" % [
		mini(nation_a, nation_b),
		maxi(nation_a, nation_b),
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var result := 0.0
	var candidate_ids := {}
	for other_id in _cached_wars_of(
		state,
		nation_a,
		evaluation_cache
	):
		candidate_ids[other_id] = true
	for other_id in _cached_wars_of(
		state,
		nation_b,
		evaluation_cache
	):
		candidate_ids[other_id] = true
	for other_id in _bordering_nation_ids(
		state,
		nation_a,
		evaluation_cache
	):
		candidate_ids[other_id] = true
	for other_id in _bordering_nation_ids(
		state,
		nation_b,
		evaluation_cache
	):
		candidate_ids[other_id] = true
	for other_id_value in candidate_ids:
		var other_id := int(other_id_value)
		if (
			other_id in [nation_a, nation_b]
			or not state.nations[other_id].alive
		):
			continue
		result = maxf(
			result,
			minf(
				threat_from_nation(
					state,
					nation_a,
					other_id,
					evaluation_cache
				),
				threat_from_nation(
					state,
					nation_b,
					other_id,
					evaluation_cache
				)
			)
		)
	evaluation_cache[cache_key] = result
	return result


static func war_desire(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var cache_key := "war_desire:%d:%d" % [nation_id, target_id]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var part_started := (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	if not can_initiate_war_at_range(state, nation_id, target_id, evaluation_cache):
		return _reject_war_desire(evaluation_cache, cache_key, "非宗藩接壤目标，或码头远征兜底未满足")
	if not _cached_can_alliance_declare_war(state, nation_id, target_id, evaluation_cache):
		var reason := "集团外交关系或停战限制"
		if state.is_enemy(nation_id, target_id):
			reason = "已经交战，不重复备战"
		elif state.is_allied(nation_id, target_id):
			reason = "当前为盟国"
		elif state.day < state.truce_until(nation_id, target_id):
			reason = "停战至第%d日" % state.truce_until(nation_id, target_id)
		return _reject_war_desire(evaluation_cache, cache_key, reason)
	if _cached_war_count(state, nation_id, evaluation_cache) >= MAX_CONCURRENT_WARS:
		return _reject_war_desire(evaluation_cache, cache_key, "达到%d场战争上限" % MAX_CONCURRENT_WARS)
	if _has_shared_ally(state, nation_id, target_id, evaluation_cache):
		return _reject_war_desire(evaluation_cache, cache_key, "双方存在共同盟友")
	_record_evaluation_profile(
		evaluation_cache, "war_gate", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var report := resource_report(
		state,
		nation_id,
		evaluation_cache
	)
	if not offensive_resources_ready(
		state,
		nation_id,
		report
	):
		return _reject_war_desire(evaluation_cache, cache_key, "当前军制粮食预测不可行" if not bool(report.forecast.food_feasible) else "人力储备不足")
	var campaign_troops := _campaign_troop_target(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	var food_plan := war_food_report(
		state,
		nation_id,
		campaign_troops,
		FoodPosture.OFFENSIVE_WAR,
		evaluation_cache
	)
	if not offensive_food_sustainable(state, food_plan):
		return _reject_war_desire(evaluation_cache, cache_key, "候选进攻军制的360天粮食预测不可行")
	_record_evaluation_profile(
		evaluation_cache, "war_resources_food", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var objective := _cached_war_objective(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	if objective.is_empty():
		return _reject_war_desire(evaluation_cache, cache_key, "无经营区域允许且有合法可达集结入口的州治目标")
	if not _ruler_allows_war_objective(state, nation_id, int(objective.get("city_id", -1))):
		return _reject_war_desire(evaluation_cache, cache_key, "君主禁攻或经营区域不允许该目标")
	_record_evaluation_profile(
		evaluation_cache, "war_objective", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	# 共同防御联盟不参加成员主动发动的战争；进攻方只能计算本国战力。
	var own_power := _national_power(
		state,
		nation_id,
		evaluation_cache
	)
	var target_power := _coalition_power(
		state, target_id, evaluation_cache
	)
	var ratio := own_power / maxf(target_power, 1.0)
	var target_distraction := float(_cached_war_count(
		state,
		target_id,
		evaluation_cache
	)) * 0.25
	var own_overextension := float(_cached_war_count(
		state,
		nation_id,
		evaluation_cache
	)) * 0.75
	var border_value := minf(
		float(_frontier_edges(
			state, nation_id, target_id, evaluation_cache
		)) * 0.10,
		0.50
	)
	var reserve_quality := minf(
		float(food_plan["target_runway_years"])
			/ OFFENSIVE_CAMPAIGN_YEARS,
		1.5
	) * 0.20
	var objective_value := minf(float(objective["value"]) * 0.05, 0.50)
	var mobilization_value := float(
		mobilization_capacity(
			state,
			nation_id,
			FoodPosture.OFFENSIVE_WAR,
			evaluation_cache
		)
	) * 0.15
	_record_evaluation_profile(
		evaluation_cache, "war_power_scoring", part_started
	)
	part_started = (
		Time.get_ticks_usec()
		if evaluation_cache.has("__profile")
		else 0
	)
	var aggression_bonus := (
		_ai_aggression(state, nation_id) - 1.0
	)
	var attitude := diplomatic_attitude(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	var unification_pressure := unification_rivalry(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	var peace_escalation := neutral_peace_escalation(
		state,
		nation_id,
		target_id
	)
	_record_evaluation_profile(
		evaluation_cache, "war_attitude_unification", part_started
	)
	# 只放大战争的正向价值；外交态度和多线作战仍是原值惩罚。
	var positive_benefit := (
		ratio
		+ target_distraction
		+ border_value
		+ reserve_quality
		+ objective_value
		+ mobilization_value
		+ unification_pressure
		+ _cached_integration_war_bonus(state, nation_id, target_id, evaluation_cache)
		+ peace_escalation
	)
	var result := _war_desire_score(
		positive_benefit,
		aggression_bonus,
		attitude * ATTITUDE_WAR_WEIGHT,
		own_overextension,
		_cached_war_benefit_multiplier(state, nation_id, evaluation_cache)
	)
	if bool(evaluation_cache.get("__war_desire_debug", false)):
		evaluation_cache["breakdown:" + cache_key] = {
			"score": result, "blocked_reason": "", "objective": objective.duplicate(true),
			"own_power": own_power, "target_power": target_power,
			"positive_terms": {
				"军力比": ratio, "敌方分心": target_distraction,
				"边疆接触": border_value, "粮食续航": reserve_quality,
				"州治价值折算": objective_value, "可动员能力": mobilization_value,
				"区域竞争": unification_pressure,
				"区域整合": _cached_integration_war_bonus(state, nation_id, target_id, evaluation_cache),
				"长期中立升级": peace_escalation,
			},
			"positive_total": positive_benefit,
			"benefit_multiplier": _cached_war_benefit_multiplier(state, nation_id, evaluation_cache),
			"aggression_bonus": aggression_bonus, "attitude": attitude,
			"attitude_penalty": attitude * ATTITUDE_WAR_WEIGHT,
			"attitude_breakdown": diplomatic_attitude_breakdown(state, nation_id, target_id, evaluation_cache).duplicate(true),
			"overextension_penalty": own_overextension,
		}
	evaluation_cache[cache_key] = result
	return result


static func _reject_war_desire(cache: Dictionary, key: String, reason: String) -> float:
	cache[key] = -INF
	if bool(cache.get("__war_desire_debug", false)):
		cache["breakdown:" + key] = {"score": -INF, "blocked_reason": reason}
	return -INF


## Same short-circuit evaluation as the AI; no counterfactual score after a veto.
static func war_desire_breakdown(state: GameState, nation_id: int, target_id: int, cache: Dictionary = {}) -> Dictionary:
	if state == null or nation_id < 0 or target_id < 0 or nation_id >= state.nations.size() or target_id >= state.nations.size() or nation_id == target_id:
		return {"score": -INF, "blocked_reason": "无效国家或自身目标"}
	_ensure_evaluation_cache_current(state, cache)
	cache["__war_desire_debug"] = true
	var key := "war_desire:%d:%d" % [nation_id, target_id]
	if not cache.has("breakdown:" + key):
		cache.erase(key)
	war_desire(state, nation_id, target_id, cache)
	return (cache["breakdown:" + key] as Dictionary).duplicate(true)


static func war_desire_debug_lines(state: GameState, nation_id: int) -> Array[String]:
	var lines: Array[String] = []
	if nation_id < 0 or nation_id >= state.nations.size():
		return lines
	var nation := state.nations[nation_id]
	lines.append("第%d日当前状态重算 · 阈值 %.2f · 非上次外交批次回放" % [state.day, WAR_DECLARE_SCORE])
	lines.append("意愿 = 收益合计 × 君主倍率 + 侵略性修正 − 态度×0.35 − 战争数×0.75")
	if not nation.alive or nation.succession_identity:
		return ["该国家已灭亡或为继承权临时身份，不评估普通备战"]
	if state.is_vassal(nation_id):
		lines.append("国家行动门禁：藩国不自主发起普通备战，以下仅为双边意愿")
	if nation.war_preparation_target_nation >= 0 and nation.war_preparation_target_nation < state.nations.size():
		lines.append("当前已对%s备战：第%d日开始；既有备战按实际集结资格推进，不重新要求意愿过线" % [state.nations[nation.war_preparation_target_nation].name, nation.war_preparation_started_day])
	if nation.war_preparation_cancelled_day >= 0 and state.day - nation.war_preparation_cancelled_day < WAR_PREPARATION_CANCEL_COOLDOWN_DAYS:
		lines.append("国家行动门禁：取消备战冷却至第%d日" % (nation.war_preparation_cancelled_day + WAR_PREPARATION_CANCEL_COOLDOWN_DAYS))
	if nation.war_preparation_target_nation >= 0:
		var center := nation.war_preparation_objective_center_city
		var v := state.campaign_prewar_reinforcement_threat(nation_id, nation.war_preparation_target_nation, center)
		lines.append("人数：野战最低%d · 围城需求%d · 备战目标%d · 实际到场%d" % [
			state.campaign_field_minimum_manpower(nation_id, v),
			state.campaign_attack_requirement(nation_id, center, false),
			state.campaign_prewar_launch_requirement(nation_id, nation.war_preparation_target_nation, center),
			war_preparation_arrived_troops(state, nation_id)])
	var cache := {}
	var candidates := _expansion_bordering_nation_ids(state, nation_id, cache).duplicate()
	if candidates.is_empty():
		candidates = _expedition_target_nation_ids(state, nation_id, cache, ObjectiveContext.PREWAR)
	var best_target := -1
	var best_score := -INF
	for target in state.nations:
		if target.id == nation_id or not target.alive or target.succession_identity:
			continue
		var report := war_desire_breakdown(state, nation_id, target.id, cache)
		lines.append("【%s（国%d）】%s" % [target.name, target.id, "地理候选" if candidates.has(target.id) else "非地理候选"])
		if not str(report.blocked_reason).is_empty():
			lines.append("意愿 -INF · 否决：%s；评分项未执行" % report.blocked_reason)
			continue
		if float(report.score) > best_score or (is_equal_approx(float(report.score), best_score) and (best_target < 0 or EquivariantOrder.nation_less(state, nation_id, target.id, best_target))):
			best_target = target.id
			best_score = float(report.score)
		lines.append("意愿 %.3f · %s" % [report.score, "达到备战阈值" if float(report.score) >= WAR_DECLARE_SCORE else "低于备战阈值"])
		lines.append("目标：%s · 原始价值 %.3f" % [state.cities[int(report.objective.city_id)].name, report.objective.value])
		lines.append(str(report.objective.reason))
		for label in report.objective.get("debug_terms", {}):
			lines.append("州治价值 %s：%+.3f" % [label, report.objective.debug_terms[label]])
		lines.append("军力：本国 %.1f / 守方含盟友 %.1f" % [report.own_power, report.target_power])
		for label in report.positive_terms:
			lines.append("收益 %s：%+.3f" % [label, report.positive_terms[label]])
		lines.append("收益小计 %.3f × 君主倍率 %.2f；侵略性修正 %+.3f" % [report.positive_total, report.benefit_multiplier, report.aggression_bonus])
		var attitude: Dictionary = report.attitude_breakdown
		lines.append("态度 %.3f（历史 %+.3f、军事 %+.3f、政治 %+.3f）×0.35：扣分 %+.3f" % [report.attitude, attitude.historical, attitude.military, attitude.political, report.attitude_penalty])
		lines.append("态度条目：边疆 %+.3f、目标利益 %+.3f、共同敌国%d、敌国盟友%d、边防释放 %+.3f、叛乱母国 %+.3f" % [attitude.border_component, attitude.objective_component, attitude.common_enemies, attitude.enemy_allies, attitude.frontier_relief, attitude.parent_rebel_component])
		lines.append("多线作战扣分 %.3f；最终 %.3f" % [report.overextension_penalty, report.score])
	if best_target >= 0:
		lines.append("当前最高双边意愿：%s %.3f（%s）；仍受上述国家行动门禁和外交批次占用限制" % [state.nations[best_target].name, best_score, "过线" if best_score >= WAR_DECLARE_SCORE else "未过线"])
	else:
		lines.append("当前无可评分的普通备战目标")
	return lines


static func _cached_integration_war_bonus(
	state: GameState, nation_id: int, target_id: int, evaluation_cache: Dictionary
) -> float:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var key := "integration_war_bonus:%d:%d" % [nation_id, target_id]
	if not evaluation_cache.has(key):
		evaluation_cache[key] = RegionalStrategy.integration_war_bonus(state, nation_id, target_id)
	return float(evaluation_cache[key])


static func _war_desire_score(
	positive_benefit: float,
	aggression_bonus: float,
	attitude_penalty: float,
	overextension_penalty: float,
	benefit_multiplier: float
) -> float:
	return (
		positive_benefit * benefit_multiplier
		+ aggression_bonus
		- attitude_penalty
		- overextension_penalty
	)


static func _cached_war_benefit_multiplier(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> float:
	var cache_key := "ruler_war_benefit:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var multiplier := RulerProfile.war_benefit_multiplier(
		state.nations[nation_id]
	)
	evaluation_cache[cache_key] = multiplier
	return multiplier


## 与 GameState.can_alliance_declare_war 完全相同的检查，但复用同一轮外交
## 已缓存的联盟集团。旧入口每评估一个边境对象都会从头重建双方联盟分量，
## 80 国时把一次月度候选收集放大成大量重复 O(N²) 扫描。
static func _cached_can_alliance_declare_war(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary
) -> bool:
	var cache_key := "can_alliance_war:%d:%d" % [nation_a, nation_b]
	if evaluation_cache.has(cache_key):
		return bool(evaluation_cache[cache_key])
	if not state.can_declare_war(nation_a, nation_b):
		evaluation_cache[cache_key] = false
		return false
	var attackers := _cached_alliance_bloc(
		state, nation_a, evaluation_cache
	)
	var defenders := _cached_alliance_bloc(
		state, nation_b, evaluation_cache
	)
	if attackers.is_empty() or defenders.is_empty():
		evaluation_cache[cache_key] = false
		return false
	for attacker in attackers:
		for defender in defenders:
			if (
				attacker == defender
				or state.is_allied(attacker, defender)
				or (
					not state.is_enemy(attacker, defender)
					and (
						state.relation_between(attacker, defender)
							!= GameState.DiplomaticRelation.NEUTRAL
						or state.day < state.truce_until(attacker, defender)
					)
				)
			):
				evaluation_cache[cache_key] = false
				return false
	evaluation_cache[cache_key] = true
	return true


static func neutral_peace_escalation(
	state: GameState,
	nation_id: int,
	target_id: int
) -> float:
	if (
		state.relation_between(nation_id, target_id)
			!= GameState.DiplomaticRelation.NEUTRAL
	):
		return 0.0
	var neutral_days := maxi(
		state.day - state.relation_since(nation_id, target_id),
		0
	)
	var escalation_range := maxi(
		PEACE_ESCALATION_FULL_DAYS
			- PEACE_ESCALATION_START_DAYS,
		1
	)
	var ratio := clampf(
		float(neutral_days - PEACE_ESCALATION_START_DAYS)
			/ float(escalation_range),
		0.0,
		1.0
	)
	return ratio * PEACE_ESCALATION_MAX_BONUS


static func _ai_aggression(
	state: GameState,
	nation_id: int
) -> float:
	return state.effective_ai_aggression(nation_id)


## Active conquest follows the ruler's business region; legal recovery remains valid.
static func _ruler_allows_war_objective(
	state: GameState,
	nation_id: int,
	objective_city: int
) -> bool:
	if nation_id < 0 or nation_id >= state.nations.size():
		return false
	if objective_city >= 0 and objective_city < state.cities.size() and not VassalConflict.for_pair(state, nation_id, state.cities[objective_city].owner_nation).is_empty(): return true
	return RegionalStrategy.allows_objective(state, nation_id, objective_city) and (
		RulerProfile.offensive_allowed(state.nations[nation_id])
		or RegionalStrategy.allows_objective(state, nation_id, objective_city, true)
	)


## 结盟后双方不再需要在共同边境互相戒备。用该边境上已经投入的实际战力占
## 全国战力的比例衡量可释放价值，使联盟服务于主战场，而不是仅依赖固定接壤加分。
static func _alliance_frontier_release_value(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "frontier_release:%d:%d" % [
		nation_id,
		target_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	# 批量缓存会看见封闭道路和纯地理邻接；释放守军只对当前存在
	# 可通行军事前线的国家对成立，必须与逐对路径共用同一门槛。
	if _frontier_edges(
		state,
		nation_id,
		target_id,
		evaluation_cache
	) <= 0:
		evaluation_cache[cache_key] = 0.0
		return 0.0
	var frontier_cities := {}
	for contact in state.territorial_border_pairs():
		var owner_a := state.cities[contact.x].owner_nation
		var owner_b := state.cities[contact.y].owner_nation
		if owner_a == nation_id and owner_b == target_id:
			frontier_cities[contact.x] = true
		elif owner_b == nation_id and owner_a == target_id:
			frontier_cities[contact.y] = true
	var committed_power := 0.0
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		if (
			army.state == Army.State.IDLE
			and frontier_cities.has(army.location_city)
		) or (
			army.state == Army.State.HOLDING
			and army.move_to != -1
			and (
				frontier_cities.has(army.move_from)
				or frontier_cities.has(army.move_to)
			)
		):
			committed_power += ArmyPower.effective(army)
	var national_power := _national_power(
		state,
		nation_id,
		evaluation_cache
	)
	var result := minf(
		committed_power / maxf(national_power, 1.0),
		0.75
	)
	evaluation_cache[cache_key] = result
	return result


## 只统计当前敌国之外的中立第三国在本国边境实际部署的战力。
## 这是“需要调转战线”的可观察证据，不使用第三国总兵力代替边境集结。
static func _neutral_border_massing_ratio(
	state: GameState,
	observer_id: int,
	current_enemy_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "neutral_massing:%d:%d" % [
		observer_id,
		current_enemy_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	if not evaluation_cache.has("border_massing_matrix_built"):
		_build_border_massing_matrix(state, evaluation_cache)
	var observer_cache_key := "neutral_massing_observer:%d" % observer_id
	var cache_by_observer := (
		state.is_enemy(observer_id, current_enemy_id)
		and not bool(evaluation_cache.get(
			"__disable_structure_cache", false
		))
	)
	if cache_by_observer and evaluation_cache.has(observer_cache_key):
		var cached := float(evaluation_cache[observer_cache_key])
		evaluation_cache[cache_key] = cached
		return cached
	var border_power := 0.0
	for other in state.nations:
		if (
			not other.alive
			or other.id in [observer_id, current_enemy_id]
			or state.is_allied(observer_id, other.id)
			or state.is_enemy(observer_id, other.id)
		):
			continue
		border_power += float(evaluation_cache.get(
			"border_massing_power:%d:%d"
				% [observer_id, other.id],
			0.0
		))
	var result := minf(
		border_power
			/ maxf(
				_national_power(
					state,
					observer_id,
					evaluation_cache
				),
				1.0
			),
		PEACE_MAX_BORDER_MASSING_RATIO
	)
	evaluation_cache[cache_key] = result
	if cache_by_observer:
		evaluation_cache[observer_cache_key] = result
	return result


## 单次建立“观察国 -> 第三国”的边境集结战力矩阵。旧实现对每个
## observer/current_enemy 组合重复扫描 E 条边和 A 支军队；矩阵严格保留
## “军队位于第三国一侧边境城或相邻边上”的原判定。
static func _build_border_massing_matrix(
	state: GameState,
	evaluation_cache: Dictionary
) -> void:
	evaluation_cache["border_massing_matrix_built"] = true
	var frontier_cities_by_pair := {}
	var observers_by_other := {}
	for contact in state.territorial_border_pairs():
		var owner_a := state.cities[contact.x].owner_nation
		var owner_b := state.cities[contact.y].owner_nation
		if owner_a < 0 or owner_b < 0 or owner_a == owner_b:
			continue
		for entry in [
			[owner_a, owner_b, contact.y],
			[owner_b, owner_a, contact.x],
		]:
			var observer_id := int(entry[0])
			var other_id := int(entry[1])
			var pair_key := "%d:%d" % [observer_id, other_id]
			if not frontier_cities_by_pair.has(pair_key):
				frontier_cities_by_pair[pair_key] = {}
				if not observers_by_other.has(other_id):
					observers_by_other[other_id] = (
						[] as Array[int]
					)
				(
					observers_by_other[other_id]
						as Array[int]
				).append(observer_id)
			(
				frontier_cities_by_pair[pair_key]
					as Dictionary
			)[int(entry[2])] = true
	for army in state.armies:
		if army.size <= 0:
			continue
		for observer_id in (
			observers_by_other.get(
				army.owner_nation,
				[] as Array[int]
			) as Array[int]
		):
			var pair_key := "%d:%d" % [
				observer_id,
				army.owner_nation,
			]
			var frontier_cities: Dictionary = (
				frontier_cities_by_pair[pair_key]
			)
			var massed := (
				army.location_city >= 0
				and frontier_cities.has(army.location_city)
			)
			if (
				not massed
				and army.on_edge
				and army.move_to >= 0
			):
				massed = (
					frontier_cities.has(army.move_from)
					or frontier_cities.has(army.move_to)
				)
			if not massed:
				continue
			var power_key := (
				"border_massing_power:%d:%d"
					% [observer_id, army.owner_nation]
			)
			evaluation_cache[power_key] = (
				float(evaluation_cache.get(power_key, 0.0))
				+ ArmyPower.effective(army)
			)


static func threat_from_nation(
	state: GameState,
	observer_id: int,
	other_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "threat:%d:%d" % [
		observer_id,
		other_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	if observer_id == other_id or state.is_allied(observer_id, other_id):
		evaluation_cache[cache_key] = 0.0
		return 0.0
	if state.is_enemy(observer_id, other_id):
		evaluation_cache[cache_key] = 3.0
		return 3.0
	var border_count := _frontier_edges(
		state,
		observer_id,
		other_id,
		evaluation_cache
	)
	if border_count <= 0:
		evaluation_cache[cache_key] = 0.0
		return 0.0
	var power_ratio := (
		_coalition_power(
			state,
			other_id,
			evaluation_cache
		)
		/ maxf(
			_coalition_power(
				state,
				observer_id,
				evaluation_cache
			),
			1.0
		)
	)
	var report := resource_report(
		state,
		other_id,
		evaluation_cache
	)
	var readiness := 0.5 if bool(report["ready"]) else 0.0
	var intent_bonus := (
		OBSERVED_WAR_PREPARATION_THREAT_BONUS
		if state.nations[
			other_id
		].war_preparation_target_nation == observer_id
		else 0.0
	)
	var result := (
		power_ratio
		+ readiness
		+ minf(float(border_count) * 0.05, 0.25)
		+ intent_bonus
	)
	evaluation_cache[cache_key] = result
	return result


static func resource_report(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var cache_key := "resource:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var nation := state.nations[nation_id]
	var troops := _troop_count(
		state,
		nation_id,
		evaluation_cache
	)
	const GOLD_FLOWS_CACHE_KEY := "monthly_gold_flows"
	if not evaluation_cache.has(GOLD_FLOWS_CACHE_KEY):
		evaluation_cache[GOLD_FLOWS_CACHE_KEY] = (
			Simulation.monthly_gold_flows(state)
		)
	var gold_flows: Array[Dictionary] = (
		evaluation_cache[GOLD_FLOWS_CACHE_KEY]
	)
	var gold_flow: Dictionary = gold_flows[nation_id]
	var trade_report := _trade_report(
		state, nation_id, evaluation_cache
	)
	# 新版 monthly_gold_flows 会直接并入贸易；旧版没有这些字段。若流量表
	# 已含贸易则以流量表为准；否则才把快照/预测净额补入，避免重复计算。
	var gold_flow_has_trade := (
		gold_flow.has("trade_net_income")
		or gold_flow.has("trade_tax_income")
		or gold_flow.has("food_trade_income")
		or gold_flow.has("food_trade_expense")
	)
	var gold_flow_trade_balance := int(
		gold_flow.get(
			"trade_net_income",
			int(gold_flow.get("trade_tax_income", 0))
				+ int(gold_flow.get("food_trade_income", 0))
				- int(gold_flow.get("food_trade_expense", 0))
		)
	)
	var monthly_trade_gold := (
		gold_flow_trade_balance
		if gold_flow_has_trade
		else int(trade_report["monthly_trade_gold"])
	)
	var monthly_trade_tax_income := (
		int(gold_flow.get("trade_tax_income", 0))
		if gold_flow_has_trade
		else int(trade_report["monthly_trade_tax_income"])
	)
	var monthly_food_trade_income := (
		int(gold_flow.get("food_trade_income", 0))
		if gold_flow_has_trade
		else int(trade_report["monthly_food_trade_income"])
	)
	var monthly_trade_food_cost := (
		int(gold_flow.get("food_trade_expense", 0))
		if gold_flow_has_trade
		else int(trade_report["monthly_trade_food_cost"])
	)
	var monthly_trade_income := (
		monthly_trade_tax_income + monthly_food_trade_income
		if gold_flow_has_trade
		else int(trade_report["monthly_trade_income"])
	)
	var monthly_city_income := int(
		gold_flow["city_income"]
	)
	var monthly_tribute_income := int(
		gold_flow["tribute_received"]
	)
	var monthly_tribute_expense := int(
		gold_flow["tribute_paid"]
	)
	var monthly_income := (
		int(gold_flow["net_income"])
		+ (0 if gold_flow_has_trade else monthly_trade_gold)
	)
	# 储备策略必须看到与本报告相同的贸易口径。只复制当前国家的一行，
	# 不改写 Simulation 提供的共享流量缓存。
	var policy_gold_flows: Array[Dictionary] = gold_flows.duplicate()
	var policy_gold_flow: Dictionary = gold_flow.duplicate()
	policy_gold_flow["net_income"] = monthly_income
	var food_plan := war_food_report(
		state,
		nation_id,
		troops,
		-1,
		evaluation_cache
	)
	var monthly_food_production := float(food_plan["monthly_food_production"])
	var monthly_war_cost := int(
		gold_flow["military_upkeep"]
	)
	var monthly_gold_balance := (
		int(gold_flow["balance"])
		+ (0 if gold_flow_has_trade else monthly_trade_gold)
	)
	policy_gold_flow["balance"] = monthly_gold_balance
	policy_gold_flows[nation_id] = policy_gold_flow
	var monthly_gold_deficit := maxi(-monthly_gold_balance, 0)
	var gold_reserve := Simulation.gold_reserve_policy(
		state, nation_id, policy_gold_flows, evaluation_cache
	)
	var monthly_food_demand := int(ceil(
		float(food_plan["current_monthly_demand"])
	))
	var gold_required := int(gold_reserve.get(
		"reserve_target", 0
	))
	var food_required := maxi(int(food_plan.forecast.food_target), 1)
	var manpower_required := maxi(
		MIN_MANPOWER_RESERVE,
		int(ceil(float(troops) * 0.15))
	)
	var manpower_capacity := state.manpower_pool_capacity(nation_id)
	if manpower_capacity > 0:
		manpower_required = mini(manpower_required, manpower_capacity)
	var food_stock := _food_stock(
		state,
		nation_id,
		evaluation_cache
	)
	var gold_ratio := (
		MAX_REPORTED_RUNWAY_YEARS
		if gold_required <= 0
		else float(nation.treasury_gold) / float(gold_required)
	)
	var gold_runway_months := (
		MAX_REPORTED_RUNWAY_YEARS * float(MONTHS_PER_YEAR)
		if monthly_gold_deficit <= 0
		else float(nation.treasury_gold) / float(monthly_gold_deficit)
	)
	var food_ratio := float(food_stock) / float(food_required)
	var manpower_ratio := float(nation.manpower_pool) / float(manpower_required)
	var food_coverage_months := float(food_plan["current_runway_years"]) * 12.0
	var food_production_ratio := (
		monthly_food_production / maxf(float(monthly_food_demand), 1.0)
	)
	var result := {
		"troops": troops,
		"forecast": food_plan["forecast"],
		"food_plan": food_plan,
		"court_expense_rate": gold_flow.get("court_expense_rate", 0.0),
		"court_expense_due": gold_flow.get("court_expense_due", 0),
		"monthly_city_gold_income": monthly_city_income,
		"monthly_tribute_income": monthly_tribute_income,
		"monthly_tribute_expense": monthly_tribute_expense,
		"monthly_trade_gold": monthly_trade_gold,
		"monthly_trade_balance": monthly_trade_gold,
		"monthly_trade_tax_income": monthly_trade_tax_income,
		"monthly_food_trade_income": monthly_food_trade_income,
		"monthly_trade_income": monthly_trade_income,
		"monthly_trade_food_cost": monthly_trade_food_cost,
		"monthly_food_import": int(
			trade_report["monthly_food_import"]
		),
		"monthly_food_export": int(
			trade_report["monthly_food_export"]
		),
		"trade_route_count": int(
			trade_report["trade_route_count"]
		),
		"blocked_trade_route_count": int(
			trade_report["blocked_trade_route_count"]
		),
		"monthly_gold_income": monthly_income,
		"monthly_war_cost": monthly_war_cost,
		"monthly_gold_balance": monthly_gold_balance,
		"gold_runway_months": gold_runway_months,
		"gold_reserve_months": int(gold_reserve.get("reserve_months", 0)),
		"gold_reserve_target": gold_required,
		"gold_reserve_gap": int(gold_reserve.get("reserve_gap", 0)),
		"gold_reserve_baseline_income": int(gold_reserve.get("baseline_monthly_income", monthly_income)),
		"gold_budget_monthly_balance": int(
			gold_reserve.get("budget_monthly_balance", monthly_gold_balance)
		),
		"gold_target_monthly_savings": int(
			gold_reserve.get("target_monthly_savings", 0)
		),
		"monthly_food_demand": monthly_food_demand,
		"monthly_food_production": monthly_food_production,
		"gold_required": gold_required,
		"food_required": food_required,
		"manpower_required": manpower_required,
		"food_stock": food_stock,
		"food_coverage_months": food_coverage_months,
		"food_production_ratio": food_production_ratio,
		"reserve_ratio": minf(gold_ratio, minf(food_ratio, manpower_ratio)),
		"annual_food_balance": food_plan["current_annual_balance"],
		"food_runway_years": food_plan["current_runway_years"],
		"full_strength_annual_demand": food_plan["full_strength_annual_demand"],
		"full_strength_annual_balance": food_plan["full_strength_annual_balance"],
		"full_strength_runway_years": food_plan["full_strength_runway_years"],
		"ready": manpower_ratio >= 1.0 and bool(food_plan["forecast"]["food_feasible"]),
	}
	evaluation_cache[cache_key] = result
	return result


## 外交评估缓存中的财政、贸易和国家聚合均按 nation_id 索引。分帧计算
## 让出主循环后若分封或叛乱新增国家，整批派生值必须一起失效，不能混用
## 变化前后的数组与逐国报告。
static func _ensure_evaluation_cache_current(
	state: GameState,
	evaluation_cache: Dictionary
) -> void:
	const REVISION_KEY := "__evaluation_state_revision"
	var revision: Array[int] = [
		state.get_instance_id(),
		state.day,
		state.nations.size(),
		state.ownership_revision,
		state.diplomacy_revision,
		state.trade_revision,
		state.regional_strategy_revision,
		state.region_analysis_revision,
		state.administrative_region_revision,
		state.road_network_revision,
	]
	var cached_revision: Variant = evaluation_cache.get(
		REVISION_KEY, null
	)
	var stale: bool = (
		cached_revision != null and cached_revision != revision
	)
	if cached_revision == null and evaluation_cache.has(
		"monthly_gold_flows"
	):
		var flows_value: Variant = evaluation_cache["monthly_gold_flows"]
		stale = (
			flows_value is Array
			and (flows_value as Array).size() != state.nations.size()
		)
	if stale:
		var control_entries := {}
		for key_value in evaluation_cache.keys():
			var key := str(key_value)
			if key.begins_with("__") and key != REVISION_KEY:
				control_entries[key_value] = evaluation_cache[key_value]
		evaluation_cache.clear()
		for key_value in control_entries:
			evaluation_cache[key_value] = control_entries[key_value]
	evaluation_cache[REVISION_KEY] = revision


## 外交报告优先复用已结算的 Nation 月度快照；世界尚未做过贸易月结时，
## 直接读取无副作用、且不依赖 Simulation 的 TradeNetwork 派生结果。
static func _trade_report(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	var cache_key := "trade_report:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var nation := state.nations[nation_id]
	var snapshot_available := (
		state.trade_revision > 0
		or not state.trade_routes.is_empty()
		or nation.last_trade_gold != 0
		or nation.last_trade_route_count != 0
	)
	var result := {
		"monthly_trade_gold": 0,
		"monthly_trade_tax_income": 0,
		"monthly_food_trade_income": 0,
		"monthly_trade_income": 0,
		"monthly_trade_food_cost": 0,
		"monthly_food_import": 0,
		"monthly_food_export": 0,
		"trade_route_count": 0,
		"blocked_trade_route_count": 0,
		"from_snapshot": snapshot_available,
	}
	if snapshot_available:
		# 月度贸易只产生路线金；粮食和人力不在贸易阶段自动转换。
		result["monthly_trade_gold"] = nation.last_trade_gold
		result["monthly_trade_income"] = nation.last_trade_gold
		result["trade_route_count"] = nation.last_trade_route_count
		result["blocked_trade_route_count"] = _cached_trade_route_count(
			state.trade_routes, state.nations.size(), nation_id, true,
			evaluation_cache, "published"
		)
	else:
		const TRADE_NETWORK_CACHE_KEY := "trade_network_result"
		if not evaluation_cache.has(TRADE_NETWORK_CACHE_KEY):
			evaluation_cache[TRADE_NETWORK_CACHE_KEY] = (
				TradeNetwork.build(state)
			)
		var trade_network: Dictionary = (
			evaluation_cache[TRADE_NETWORK_CACHE_KEY]
		)
		var trade_income := _trade_nation_value(
			trade_network, "nation_trade_gold", nation_id
		)
		var trade_tax_income := _trade_nation_value(
			trade_network, "nation_trade_tax", nation_id
		)
		result["monthly_trade_gold"] = trade_income
		result["monthly_trade_tax_income"] = trade_tax_income
		result["monthly_trade_income"] = trade_income
		var routes: Array = trade_network.get("routes", [])
		result["trade_route_count"] = _cached_trade_route_count(
			routes, state.nations.size(), nation_id, false,
			evaluation_cache, "forecast"
		)
		result["blocked_trade_route_count"] = _cached_trade_route_count(
			routes, state.nations.size(), nation_id, true,
			evaluation_cache, "forecast"
		)
	evaluation_cache[cache_key] = result
	return result


static func _trade_nation_value(
	trade_network: Dictionary,
	key: String,
	nation_id: int
) -> int:
	var values: Array = trade_network.get(key, [])
	return int(values[nation_id]) if nation_id < values.size() else 0


## 同一轮资源评估会依次查询许多国家。旧实现每个国家分别扫完整路线表两次；
## 这里一次汇总全部国家的 active/blocked 数量，后续查询 O(1)。国内路线的
## nation_a == nation_b 仍只计一次，与旧逐国 contains 判定严格一致。
static func _cached_trade_route_count(
	routes: Array,
	nation_count: int,
	nation_id: int,
	blocked_only: bool,
	evaluation_cache: Dictionary,
	cache_scope: String
) -> int:
	if nation_id < 0 or nation_id >= nation_count:
		return 0
	var cache_key := "trade_route_counts:%s" % cache_scope
	if not evaluation_cache.has(cache_key):
		var active: Array[int] = []
		var blocked: Array[int] = []
		active.resize(nation_count)
		active.fill(0)
		blocked.resize(nation_count)
		blocked.fill(0)
		for route_value in routes:
			var route: Dictionary = route_value
			var counts := (
				blocked
				if (
					int(route.get("status", TradeNetwork.STATUS_ACTIVE))
					== TradeNetwork.STATUS_BLOCKED
				)
				else active
			)
			var nation_a := int(route.get("nation_a", -1))
			var nation_b := int(route.get("nation_b", -1))
			if nation_a >= 0 and nation_a < nation_count:
				counts[nation_a] += 1
			if nation_b >= 0 and nation_b < nation_count and nation_b != nation_a:
				counts[nation_b] += 1
		evaluation_cache[cache_key] = {
			"active": active,
			"blocked": blocked,
		}
	var totals: Dictionary = evaluation_cache[cache_key]
	var values: Array[int] = (
		totals["blocked"] if blocked_only else totals["active"]
	)
	return values[nation_id]


## 宣战资源门槛随统一时代连续退火。era=0 时严格等价于 resource_report.ready；
## era=1 时保留总体战生存底线，避免大战后的所有国家因和平期储备规则永久停战。
static func offensive_resources_ready(state: GameState, nation_id: int, report: Dictionary) -> bool:
	var nation := state.nations[nation_id]
	var era := unification_era_factor(state)
	var required := maxi(int(round(lerpf(float(MIN_MANPOWER_RESERVE), float(MIN_MANPOWER_RESERVE) / 5.0, era))), int(ceil(float(report.troops) * lerpf(0.15, TOTAL_WAR_MANPOWER_SHARE, era))))
	required = mini(required, state.manpower_pool_capacity(nation_id))
	return nation.manpower_pool >= required and bool(report.forecast.food_feasible)


static func offensive_food_sustainable(_state: GameState, food_plan: Dictionary) -> bool:
	return bool(food_plan.forecast.food_feasible)


static func war_preparation_resources_ready(state: GameState, nation_id: int, evaluation_cache: Dictionary = {}) -> bool:
	var report := resource_report(state, nation_id, evaluation_cache)
	var nation := state.nations[nation_id]
	var required := maxi(MIN_MANPOWER_RESERVE / 5, int(ceil(float(report.troops) * TOTAL_WAR_MANPOWER_SHARE)))
	var forecast := resource_forecast(state, nation_id, -1, FoodPosture.OFFENSIVE_WAR, evaluation_cache)
	return nation.manpower_pool >= required and bool(forecast.food_feasible)


static func mobilization_capacity(
	state: GameState,
	nation_id: int,
	posture: int = FoodPosture.OFFENSIVE_WAR,
	evaluation_cache: Dictionary = {}
) -> int:
	return mini(
		int(force_capacity_report(
			state, nation_id, posture, evaluation_cache
		)["additional_armies"]),
		MAX_MOBILIZATION_ARMIES
	)


static func force_capacity_report(
	state: GameState, nation_id: int, posture: int = -1, evaluation_cache: Dictionary = {}
) -> Dictionary:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	if posture < 0:
		posture = food_posture(state, nation_id, evaluation_cache)
	var key := "force_capacity:%d:%d" % [nation_id, posture]
	if evaluation_cache.has(key):
		return evaluation_cache[key]
	var input: Dictionary = _resource_forecast_inputs(state, evaluation_cache)[nation_id]
	var nation := state.nations[nation_id]
	var size := GameState.INITIAL_HEAVY_ARMY_SIZE
	var count := int(input.army_count)
	var reserve := int(input.manpower_target)
	var manpower_limit := maxi(nation.manpower_pool - reserve, 0) / size
	var slot_limit := maxi(state.max_army_count(nation_id) - count, 0)
	var max_growth := mini(slot_limit, manpower_limit)
	var additional := 0
	var reason := "manpower" if manpower_limit < slot_limit else "army_slots"
	var upper := max_growth
	while additional < upper:
		var growth := 1 if additional == 0 else (additional + upper + 1) / 2
		var check := resource_forecast(state, nation_id, int(input.troops) + growth * size, posture, evaluation_cache, {"base_upkeep_delta": growth * GameState.army_monthly_upkeep(size), "field_food_delta": growth * ReinforcementPhase._grant_food_delta(0, size, float(input.food_multiplier))})
		if not bool(check.food_growth_allowed):
			reason = "food"
			upper = growth - 1
		else:
			additional = growth
	# Compatibility capacity fields now describe the joint forecast budget,
	# not a second independent multi-year food gate.
	var food_total := count + additional
	var result := {
		"current_armies": count, "sustainable_armies": count + additional,
		"supportable_armies": count + additional, "additional_armies": additional,
		"manpower_limit": manpower_limit,
		"food_limit": maxi(food_total - count, 0),
		"army_slot_limit": slot_limit,
		"food_total_capacity": food_total, "limiting_resource": reason,
		"manpower_reserve": reserve, "posture": posture,
	}
	evaluation_cache[key] = result
	return result


static func food_posture(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "food_posture:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var wars := _cached_wars_of(
		state,
		nation_id,
		evaluation_cache
	)
	if not wars.is_empty():
		for enemy_id in wars:
			var objective := state.war_objective(nation_id, enemy_id)
			if (
				not objective.is_empty()
				and int(objective.get("attacker", -1)) == nation_id
			):
				evaluation_cache[cache_key] = (
					FoodPosture.OFFENSIVE_WAR
				)
				return FoodPosture.OFFENSIVE_WAR
		evaluation_cache[cache_key] = FoodPosture.DEFENSIVE_WAR
		return FoodPosture.DEFENSIVE_WAR
	if state.nations[nation_id].war_mobilization_target_troops > 0:
		evaluation_cache[cache_key] = FoodPosture.GUARDED
		return FoodPosture.GUARDED
	var own_power := _coalition_power(
		state,
		nation_id,
		evaluation_cache
	)
	# 是否存在与本国势力接壤、且战力≥75% 的非盟国。原实现对每个国家都扫全
	# 边表判接壤（O(N×E)），是大地图 AI 决策日的头号热点；改为一次遍历边表
	# 收集接壤非盟国集合（O(E)），再逐邻查战力。结果为存在性判断，与遍历
	# 顺序无关，确定性不变。
	for other_id in _bordering_nation_ids(state, nation_id, evaluation_cache):
		if _coalition_power(
			state,
			other_id,
			evaluation_cache
		) >= own_power * 0.75:
			evaluation_cache[cache_key] = FoodPosture.GUARDED
			return FoodPosture.GUARDED
	evaluation_cache[cache_key] = FoodPosture.PEACE
	return FoodPosture.PEACE


## 一次遍历边表收集与本国势力（本国+盟国领土）接壤的非盟外国 id。等价于
## 对所有 B 判定 _frontier_edges(nation_id, B) > 0，但复杂度从 O(N×E) 降至 O(E)。
static func _bordering_nation_ids(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Array[int]:
	var cache_key := "borders:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var topology_cache := _ensure_frontier_matrix_cache(
		state, evaluation_cache
	)
	var by_observer: Array = topology_cache.get(
		"frontier_neighbors_by_observer", []
	)
	var result: Array[int] = []
	if nation_id >= 0 and nation_id < by_observer.size():
		result = (by_observer[nation_id] as Array[int]).duplicate()
	evaluation_cache[cache_key] = result
	return result


## 主动宣战只认发起国自己的领土边界。联盟领土仍进入 _frontier_edges，
## 供威胁、通行和共同防御使用，但不能替盟国创造新的主动宣战对象。
static func _direct_bordering_nation_ids(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Array[int]:
	var cache_key := "direct_borders:%d:%d:%d:%d:%d" % [
		state.get_instance_id(), nation_id, state.ownership_revision,
		state.diplomacy_revision, state.road_network_revision,
	]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var topology_cache := _ensure_frontier_matrix_cache(
		state, evaluation_cache
	)
	var by_owner: Array = topology_cache.get(
		"territorial_neighbors_by_owner", []
	)
	var result: Array[int] = []
	if nation_id >= 0 and nation_id < by_owner.size():
		result = (by_owner[nation_id] as Array[int]).duplicate()
	evaluation_cache[cache_key] = result
	return result


static func _expansion_members(
	state: GameState, nation_id: int, cache: Dictionary
) -> Array[int]:
	_ensure_evaluation_cache_current(state, cache)
	var key := "expansion_members:%d" % nation_id
	if not cache.has(key):
		var control := RegionalStrategy.control(state)
		var root := int(control["roots"].get(nation_id, nation_id))
		var members: Array[int] = []
		for member_id in control["root_members"].get(root, []):
			if state.nations[member_id].alive:
				members.append(member_id)
		cache[key] = members
	return cache[key] as Array[int]


static func _expansion_bordering_nation_ids(
	state: GameState, nation_id: int, cache: Dictionary = {}
) -> Array[int]:
	var members := _expansion_members(state, nation_id, cache)
	var key := "expansion_borders:%d" % nation_id
	if not cache.has(key):
		var neighbors: Array = _ensure_frontier_matrix_cache(state, cache)["territorial_neighbor_sets"]
		var flags := {}
		for member_id in members:
			for target_id in neighbors[member_id]:
				if not members.has(target_id) and not state.has_military_access(nation_id, target_id):
					flags[target_id] = true
		var result: Array[int] = []
		result.assign(flags.keys())
		result.sort_custom(func(a: int, b: int) -> bool:
			return EquivariantOrder.nation_less(state, nation_id, a, b)
		)
		cache[key] = result
	return cache[key] as Array[int]


static func _prewar_reachable_cities(
	state: GameState, nation_id: int, cache: Dictionary
) -> Dictionary:
	var key := "prewar_reachable:%d:%d" % [nation_id, state.day]
	if cache.has(key):
		return cache[key]
	# Sources describe possible deployment, not committed or battle-ready C.
	var sources_key := "prewar_source_nodes:%d" % state.day
	if not cache.has(sources_key):
		var by_owner := {}
		for city in state.cities:
			if city.owner_nation >= 0 and city.politically_active and not city.is_dock:
				if not by_owner.has(city.owner_nation):
					by_owner[city.owner_nation] = {}
				by_owner[city.owner_nation][city.id] = true
		for army in state.armies:
			var node := army.move_to if army.on_edge else army.location_city
			if army.size <= 0 or node < 0 or node >= state.cities.size() or not state.has_military_access(army.owner_nation, state.cities[node].owner_nation):
				continue
			if not by_owner.has(army.owner_nation):
				by_owner[army.owner_nation] = {}
			by_owner[army.owner_nation][node] = true
		cache[sources_key] = by_owner
	var reachable := {}
	var fields: Dictionary = cache.get("prewar_path_fields", {})
	var sources: Dictionary = cache[sources_key].get(nation_id, {})
	for source_id in sources:
		if reachable.has(source_id):
			continue
		var field := AiWorldView.cached_path_field(state, state.day, fields, source_id, nation_id, false, false)
		for city_id in field["dist"]:
			if float(field["dist"][city_id]) < INF:
				reachable[city_id] = true
	cache["prewar_path_fields"] = fields
	cache[key] = reachable
	return reachable


static func _prewar_source_reaches(
	state: GameState, nation_id: int, city_id: int, cache: Dictionary
) -> bool:
	if state.cities[city_id].owner_nation == nation_id and state.cities[city_id].politically_active and not state.cities[city_id].is_dock:
		return true
	return _prewar_reachable_cities(state, nation_id, cache).has(city_id)


## No-land-border fallback. Accessible own/allied docks may lead to the first
## foreign dock owner, but the water route itself never becomes a border.
static func _expedition_target_nation_ids(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {},
	context: ObjectiveContext = ObjectiveContext.CAMPAIGN
) -> Array[int]:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var cache_key := "expedition_targets:%d:%d" % [nation_id, context]
	if evaluation_cache.has(cache_key):
		return (evaluation_cache[cache_key] as Array[int]).duplicate()
	var targets := {}
	var visited := {}
	var queue: Array[int] = []
	var sources: Array[int] = [nation_id]
	if context == ObjectiveContext.PREWAR:
		sources = _expansion_members(state, nation_id, evaluation_cache)
	for city in state.cities:
		if city.is_dock and sources.has(city.owner_nation) and state.has_military_access(nation_id, city.owner_nation) and (
			context != ObjectiveContext.PREWAR or _prewar_source_reaches(state, nation_id, city.id, evaluation_cache)
		):
			visited[city.id] = true
			queue.append(city.id)
	var cursor := 0
	while cursor < queue.size():
		var dock_id := queue[cursor]
		cursor += 1
		for neighbor in state.neighbors(dock_id):
			if not state.cities[neighbor].is_dock:
				continue
			var water_edge := state.edge_of(dock_id, neighbor)
			if (
				water_edge == null
				or water_edge.max_manpower <= 0
				or water_edge.kind not in [Edge.Kind.RIVER, Edge.Kind.SEA]
			):
				continue
			var owner := state.cities[neighbor].owner_nation
			if state.has_military_access(nation_id, owner):
				if not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
			elif (
				owner >= 0
				and owner < state.nations.size()
				and state.nations[owner].alive
			):
				targets[owner] = true
	var result: Array[int] = []
	for target_value in targets:
		result.append(int(target_value))
	result.sort_custom(func(a: int, b: int) -> bool:
		return EquivariantOrder.nation_less(state, nation_id, a, b)
	)
	evaluation_cache[cache_key] = result
	return result.duplicate()


static func can_initiate_war_at_range(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	var direct_neighbors := _expansion_bordering_nation_ids(
		state, nation_id, evaluation_cache
	)
	if direct_neighbors.has(target_id):
		return true
	# Expedition targets are a fallback, never an addition to available land
	# borders. This prevents river powers from opening every front at once.
	if not direct_neighbors.is_empty():
		return false
	return _expedition_target_nation_ids(
		state, nation_id, evaluation_cache, ObjectiveContext.PREWAR
	).has(target_id)


## 国家外交距离使用领土接触图，而不是会随地图缩放变化的屏幕/坐标距离。
## 直接接壤为 1 跳，经一个存活国家中转为 2 跳；关系建立后不会因疆域变化
## 自动拆除，防御盟约拉入战争也不重新套此主动外交门禁。
static func within_diplomatic_range(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	if (
		state == null
		or nation_a < 0 or nation_b < 0
		or nation_a >= state.nations.size()
		or nation_b >= state.nations.size()
		or nation_a == nation_b
		or not state.nations[nation_a].alive
		or not state.nations[nation_b].alive
	):
		return false
	var range_cache := _diplomacy_topology_cache_store(evaluation_cache)
	_ensure_diplomatic_range_cache(state, range_cache)
	var masks: Array = range_cache.get(
		"diplomatic_range_masks", []
	)
	return (
		nation_a < masks.size()
		and nation_b < (masks[nation_a] as PackedByteArray).size()
		and (masks[nation_a] as PackedByteArray)[nation_b] != 0
	)


static func _diplomatic_range_nation_ids(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Array[int]:
	var range_cache := _diplomacy_topology_cache_store(evaluation_cache)
	_ensure_diplomatic_range_cache(state, range_cache)
	var masks: Array = range_cache.get(
		"diplomatic_range_masks", []
	)
	var result: Array[int] = []
	if nation_id < 0 or nation_id >= masks.size():
		return result
	var reachable: PackedByteArray = masks[nation_id]
	for target_id in range(reachable.size()):
		if reachable[target_id] != 0:
			result.append(target_id)
	return result


static func _diplomacy_topology_cache_store(
	evaluation_cache: Dictionary
) -> Dictionary:
	var shared: Variant = evaluation_cache.get(
		"__diplomacy_topology_cache", null
	)
	return shared as Dictionary if shared is Dictionary else evaluation_cache


static func _ensure_diplomatic_range_cache(
	state: GameState,
	evaluation_cache: Dictionary,
	provided_neighbor_sets: Array[Dictionary] = []
) -> void:
	var revision: Array[int] = [
		state.get_instance_id(),
		state.ownership_revision,
		state.diplomacy_revision,
		state.road_network_revision,
		state.cities.size(),
		state.nations.size(),
		state.edges.size(),
	]
	if (
		evaluation_cache.get("diplomatic_range_revision", []) == revision
		and evaluation_cache.has("diplomatic_range_masks")
	):
		return
	_build_diplomatic_range_masks(
		state, evaluation_cache, provided_neighbor_sets
	)
	evaluation_cache["diplomatic_range_revision"] = revision


static func _build_diplomatic_range_masks(
	state: GameState,
	evaluation_cache: Dictionary,
	provided_neighbor_sets: Array[Dictionary] = []
) -> void:
	var nation_count := state.nations.size()
	var territory_neighbor_sets := provided_neighbor_sets
	if territory_neighbor_sets.is_empty():
		territory_neighbor_sets.resize(nation_count)
		for nation_id in range(nation_count):
			territory_neighbor_sets[nation_id] = {}
		for contact in state.territorial_border_pairs():
			var owner_a := state.cities[contact.x].owner_nation
			var owner_b := state.cities[contact.y].owner_nation
			if (
				owner_a < 0 or owner_a >= nation_count
				or owner_b < 0 or owner_b >= nation_count
				or owner_a == owner_b
			):
				continue
			territory_neighbor_sets[owner_a][owner_b] = true
			territory_neighbor_sets[owner_b][owner_a] = true
	var diplomatic_range_masks: Array[PackedByteArray] = []
	diplomatic_range_masks.resize(nation_count)
	for observer in range(nation_count):
		var reachable := PackedByteArray()
		reachable.resize(nation_count)
		reachable.fill(0)
		var distance := PackedInt32Array()
		distance.resize(nation_count)
		distance.fill(-1)
		distance[observer] = 0
		var queue: Array[int] = [observer]
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			if distance[current] >= MAX_DIPLOMATIC_DISTANCE_HOPS:
				continue
			for neighbor_value in territory_neighbor_sets[current]:
				var neighbor := int(neighbor_value)
				if (
					neighbor == observer
					or not state.nations[neighbor].alive
					or distance[neighbor] >= 0
				):
					continue
				distance[neighbor] = distance[current] + 1
				reachable[neighbor] = 1
				queue.append(neighbor)
		diplomatic_range_masks[observer] = reachable
	evaluation_cache["diplomatic_range_masks"] = diplomatic_range_masks
	evaluation_cache["diplomatic_range_revision"] = [
		state.get_instance_id(),
		state.ownership_revision,
		state.road_network_revision,
		state.cities.size(),
		state.nations.size(),
		state.edges.size(),
	]


## A batch owns these aggregates and its accepted resource commitments.
static func resource_forecast(
	state: GameState, nation_id: int, target_troops: int = -1,
	posture: int = -1, evaluation_cache: Dictionary = {}, override: Dictionary = {}
) -> Dictionary:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var inputs := _resource_forecast_inputs(state, evaluation_cache)
	var input: Dictionary = inputs[nation_id]
	var nation := state.nations[nation_id]
	if posture < 0:
		posture = food_posture(state, nation_id, evaluation_cache)
	var peace := posture in [FoodPosture.PEACE, FoodPosture.GUARDED]
	var current := int(input.troops)
	if target_troops < 0:
		target_troops = current
	var forecast_key := "forecast:%d:%d:%d" % [nation_id, target_troops, posture]
	if override.is_empty() and evaluation_cache.has(forecast_key):
		return evaluation_cache[forecast_key]
	input = input.duplicate()
	var bonus := int(input.reserve_months_bonus)
	input.gold_months = maxi((36 if peace else 6) + bonus, 0)
	input.food_months = maxi((18 if peace else 6) + bonus, 0)
	var change := {}
	var deployment_food_delta := 0.0
	# A proposed offensive deployment cannot assume every army will retain
	# its peacetime local supply loss. Existing wars keep observed deployment.
	if posture == FoodPosture.OFFENSIVE_WAR and _cached_wars_of(state, nation_id, evaluation_cache).is_empty():
		deployment_food_delta = maxf(current * FOOD_PER_CAPITA_MONTH * DEFAULT_CAMPAIGN_SUPPLY_MULTIPLIER * float(input.food_multiplier) - float(input.nation_field_food), 0)
	if target_troops != current:
		var unit_food := float(input.nation_field_food) / maxi(current, 1)
		if target_troops > current:
			unit_food = maxf(unit_food, FOOD_PER_CAPITA_MONTH * Simulation.MAX_SUPPLY_MULT * float(input.food_multiplier))
			input.harvest = maxf(float(input.harvest) - float(input.harvest_loss), 0)
		change.field_food_delta = (target_troops - current) * unit_food
		if target_troops < current:
			change.replace_consumers = true
		var delta := target_troops - current
		var base_delta := int(ceil(float(delta) / GameState.WAR_GOLD_TROOPS_PER_UNIT))
		if delta > 0:
			var formations := delta / GameState.INITIAL_HEAVY_ARMY_SIZE
			base_delta = formations * GameState.army_monthly_upkeep(GameState.INITIAL_HEAVY_ARMY_SIZE) + GameState.army_monthly_upkeep(delta % GameState.INITIAL_HEAVY_ARMY_SIZE)
		var projected_base := maxi(int(input.base_upkeep) + base_delta, 0)
		change.upkeep_delta = Simulation._ruler_adjusted_upkeep(projected_base, float(input.upkeep_multiplier)) - int(input.field_upkeep)
	change.merge(override, true)
	if deployment_food_delta > 0:
		change.field_food_delta = float(change.get("field_food_delta", 0)) + deployment_food_delta
	if override.has("base_upkeep_delta"):
		change.upkeep_delta = Simulation._ruler_adjusted_upkeep(maxi(int(input.base_upkeep) + int(override.base_upkeep_delta), 0), float(input.upkeep_multiplier)) - int(input.field_upkeep)
	var report := ResourceForecastRules.evaluate(input, change)
	report.input = input
	report.change = change
	if override.is_empty():
		evaluation_cache[forecast_key] = report
	return report

static func _resource_forecast_inputs(state: GameState, cache: Dictionary) -> Array[Dictionary]:
	if cache.has("resource_forecast_inputs"):
		return cache.resource_forecast_inputs
	if not cache.has("monthly_gold_flows"):
		cache.monthly_gold_flows = Simulation.monthly_gold_flows(state)
	var flows: Array[Dictionary] = cache.monthly_gold_flows
	var armies := ReinforcementRules.bucket_armies_by_nation(state, true)
	var garrison_index := Simulation.build_garrison_index(state)
	var conservative_index := garrison_index.duplicate()
	var garrison_food := {}
	for city in state.cities:
		if city.owner_nation < 0 or city.is_dock:
			continue
		conservative_index[city.id] = int(ceil(float(city.manpower_per_month) * Simulation.CITY_GARRISON_CAPACITY_PER_MANPOWER * Simulation.CITY_GARRISON_FOOD_PENALTY_MAX / Simulation.CITY_GARRISON_FOOD_PENALTY_RATE))
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		var city := state.cities[center_id]
		if city.owner_nation >= 0:
			garrison_food[city.owner_nation] = int(garrison_food.get(city.owner_nation, 0)) + int(Simulation.city_garrison_cost_report(state, city.owner_nation, center_id, city.garrison_manpower, state.capital_hop_distances(city.owner_nation)).food_demand)
	var inputs: Array[Dictionary] = []
	var pools := {}
	for nation in state.nations:
		var ruler_modifiers := RulerProfile.modifiers(nation)
		var field := 0.0
		var troops := 0
		var base_upkeep := 0
		var consumers: Array = []
		var owned: Array = armies.get(nation.id, [])
		var refill := 0
		var consumption_multiplier := float(ruler_modifiers[RulerProfile.KEY_FOOD_CONSUMPTION])
		for army in owned:
			if army.size <= 0:
				continue
			troops += army.size
			base_upkeep += GameState.army_monthly_upkeep(army.size)
			var rate := float(TradeNetwork._projected_army_monthly_food_demand(army, nation, consumption_multiplier))
			field += rate
			consumers.append({"rate": rate, "debt": army.supply_food_debt})
			refill += mini(maxi(army.max_size - army.size, 0), ReinforcementRules.monthly_reinforcement_cap(army))
		var garrison := int(garrison_food.get(nation.id, 0))
		var settled := maxf(float(nation.last_food_demand), nation.food_demand_ema) - garrison
		var factor := maxf(settled, field) / maxf(field, 1)
		for consumer in consumers:
			consumer.rate = float(consumer.rate) * factor
		field *= factor
		var harvest := 0
		var conservative := 0
		for city in _cached_cities_of(state, nation.id, cache):
			harvest += Simulation.city_food_output(state, city, garrison_index, ruler_modifiers)
			conservative += Simulation.city_food_output(state, city, conservative_index, ruler_modifiers)
		var trade := _trade_report(state, nation.id, cache)
		var flow: Dictionary = flows[nation.id]
		var pool_id := state.food_pool_holder(nation.id)
		if not pools.has(pool_id):
			pools[pool_id] = {"field": 0.0, "garrison": 0, "harvest": 0, "trade": 0, "exports": 0, "consumers": []}
		var pool: Dictionary = pools[pool_id]
		pool.field += field
		pool.garrison += garrison
		pool.harvest += harvest
		pool.trade += int(trade.monthly_food_import) - int(trade.monthly_food_export)
		pool.exports += int(trade.monthly_food_export)
		pool.consumers.append_array(consumers)
		inputs.append({
			"day": state.day, "gold": nation.treasury_gold,
			"pending_supply_days": int(cache.get("__forecast_pending_supply", false)),
			"income": int(flow.net_income), "court": int(flow.court_expense_due),
			"upkeep": int(flow.military_upkeep), "field_upkeep": int(flow.field_army_upkeep),
			"necessary_gold": int(flow.court_expense_due) + int(flow.military_upkeep) + int(flow.tribute_paid) + int(flow.food_trade_expense) + int(flow.manpower_trade_expense),
			"troops": troops, "base_upkeep": base_upkeep, "army_count": owned.size(), "nation_field_food": field, "harvest_loss": maxi(harvest - conservative, 0),
			"manpower_target": mini(state.manpower_pool_capacity(nation.id), maxi(MIN_MANPOWER_RESERVE, maxi(int(ceil(troops * 0.15)), refill))),
			"food_multiplier": consumption_multiplier, "upkeep_multiplier": float(ruler_modifiers[RulerProfile.KEY_UPKEEP]),
			"reserve_months_bonus": int(ruler_modifiers[RulerProfile.KEY_RESERVE_MONTHS]),
		})
	for nation in state.nations:
		var pool_id := state.food_pool_holder(nation.id)
		var pool: Dictionary = pools[pool_id]
		var input: Dictionary = inputs[nation.id]
		input.field_food = pool.field
		input.garrison_food = pool.garrison
		input.harvest = pool.harvest
		input.trade_food = pool.trade
		input.export_food = pool.exports
		input.consumers = pool.consumers
		if not pool.has("consumption"):
			var consumption := {}
			var first_event := (state.day / 30 + 1) * 30
			var pending_days := int(input.pending_supply_days)
			var elapsed_days: Array[int] = [pending_days, 359 + pending_days, 360 + pending_days]
			for event in range(first_event, state.day + 361, 30):
				elapsed_days.append(maxi(event - state.day - 1, 0) + pending_days)
				elapsed_days.append(event - state.day + pending_days)
			for elapsed in elapsed_days:
				if not consumption.has(elapsed):
					var amount := 0.0
					for consumer in pool.consumers:
						amount += floor(float(consumer.rate) * elapsed / 30.0 + float(consumer.debt) + 0.000001)
					if pool.consumers.is_empty():
						amount = floor(float(pool.field) * elapsed / 30.0 + 0.000001)
					consumption[elapsed] = amount
			pool.consumption = consumption
		input.consumption = pool.consumption
		input.food = _food_stock(state, pool_id, cache)
		input.food_capacity = state.food_storage_capacity(pool_id)
	cache.resource_forecast_inputs = inputs
	return inputs

static func commit_force_change(state: GameState, nation_id: int, added_troops: int, cache: Dictionary, changes: Array = []) -> void:
	if not cache.has("resource_forecast_inputs"):
		return
	var inputs: Array[Dictionary] = cache.resource_forecast_inputs
	var input: Dictionary = inputs[nation_id]
	var rate := maxi(added_troops, 0) * FOOD_PER_CAPITA_MONTH * Simulation.MAX_SUPPLY_MULT * float(input.food_multiplier)
	var upkeep_delta := GameState.army_monthly_upkeep(added_troops)
	var new_count := 0
	var full_delta := 0
	var power_delta := 0.0
	if not changes.is_empty():
		upkeep_delta = 0
		rate = 0
		for change in changes:
			var army: Army = change.army
			var old_size := int(change.old_size)
			rate += ReinforcementPhase._grant_food_delta(old_size, army.size, float(input.food_multiplier))
			upkeep_delta += GameState.army_monthly_upkeep(army.size) - GameState.army_monthly_upkeep(old_size)
			power_delta += ArmyPower.effective(army) * float(army.size - old_size) / maxi(army.size, 1)
			if old_size == 0:
				new_count += 1
				full_delta += army.max_size
	var holder := state.food_pool_holder(nation_id)
	for member in state.food_pool_members(holder):
		inputs[member].field_food += rate
		# Keep pre-existing per-army fractional debts when accepting a candidate.
		inputs[member].consumers = (inputs[member].consumers as Array).duplicate()
		inputs[member].consumers.append({"rate": rate, "debt": 0.0, "increment": true})
		inputs[member].erase("consumption")
		inputs[member].harvest = maxf(float(inputs[member].harvest) - float(input.harvest_loss), 0)
	input.harvest_loss = 0
	input.nation_field_food += rate
	input.troops += added_troops
	input.base_upkeep += upkeep_delta
	input.army_count += new_count
	input.gold = state.nations[nation_id].treasury_gold
	var field := Simulation._ruler_adjusted_upkeep(int(input.base_upkeep), float(input.upkeep_multiplier))
	input.necessary_gold += field - int(input.field_upkeep)
	input.upkeep += field - int(input.field_upkeep)
	input.field_upkeep = field
	cache["troops:%d" % nation_id] = int(input.troops)
	if cache.has("full_troops:%d" % nation_id):
		cache["full_troops:%d" % nation_id] += full_delta
	if cache.has("power:%d" % nation_id):
		cache["power:%d" % nation_id] += power_delta
	cache.monthly_gold_flows = (cache.monthly_gold_flows as Array[Dictionary]).duplicate()
	var flow: Dictionary = cache.monthly_gold_flows[nation_id].duplicate()
	cache.monthly_gold_flows[nation_id] = flow
	flow.balance -= field - int(flow.field_army_upkeep)
	flow.military_upkeep += field - int(flow.field_army_upkeep)
	flow.field_army_upkeep = field
	for key in cache.keys():
		if str(key).begins_with("forecast:") or str(key).begins_with("food:") or str(key).begins_with("food_capacity:") or str(key).begins_with("force_capacity:") or str(key).begins_with("resource:") or str(key).begins_with("coalition_power:") or str(key).begins_with("food_posture:"):
			cache.erase(key)

static func war_food_report(
	state: GameState, nation_id: int, target_troops: int = -1,
	posture: int = -1, evaluation_cache: Dictionary = {}, compute_capacity: bool = false
) -> Dictionary:
	var current := _troop_count(state, nation_id, evaluation_cache)
	if target_troops < 0:
		target_troops = current
	if posture < 0:
		posture = food_posture(state, nation_id, evaluation_cache)
	var key := "food:%d:%d:%d:%d" % [nation_id, target_troops, posture, int(compute_capacity)]
	if evaluation_cache.has(key):
		return evaluation_cache[key]
	var forecast := resource_forecast(state, nation_id, target_troops, posture, evaluation_cache)
	var input: Dictionary = forecast.input
	var demand := float(input.field_food) + float(input.garrison_food) + float(forecast.change.get("field_food_delta", 0))
	var production := float(input.harvest) / 6.0 + float(input.trade_food)
	var low := 0
	var high := state.max_army_count(nation_id) * GameState.INITIAL_HEAVY_ARMY_SIZE
	if not compute_capacity:
		low = current
		high = current
	var capacity_key := "food_capacity:%d:%d" % [nation_id, posture]
	if evaluation_cache.has(capacity_key):
		low = int(evaluation_cache[capacity_key])
		high = low
	while low < high:
		var candidate := (low + high + 1) / 2
		var check := resource_forecast(state, nation_id, candidate, posture, evaluation_cache)
		var viable := int(check.food_deficit) == 0
		if posture in [FoodPosture.PEACE, FoodPosture.GUARDED]:
			viable = viable and float(check.food_end) >= minf(float(check.input.food), float(check.food_target)) + float(check.food_gap) / 3.0
		if viable:
			low = candidate
		else:
			high = candidate - 1
	if compute_capacity:
		evaluation_cache[capacity_key] = low
	var full := _full_strength_troop_count(state, nation_id, evaluation_cache)
	var full_forecast := resource_forecast(state, nation_id, full, posture, evaluation_cache)
	var annual_balance := (production - demand) * 12.0
	var current_balance := (production - float(input.field_food) - float(input.garrison_food)) * 12.0
	var full_demand := float(input.field_food) + float(input.garrison_food) + float(full_forecast.change.get("field_food_delta", 0))
	var full_balance := (float(full_forecast.input.harvest) / 6.0 + float(input.trade_food) - full_demand) * 12.0
	var pool_troops := 0
	for member in state.food_pool_members(state.food_pool_holder(nation_id)):
		pool_troops += int(_resource_forecast_inputs(state, evaluation_cache)[member].troops)
	var result := {
		"posture": posture, "current_troops": current, "target_troops": target_troops,
		"pool_holder": state.food_pool_holder(nation_id),
		"pool_members": state.food_pool_members(state.food_pool_holder(nation_id)),
		"pool_current_troops": pool_troops, "full_strength_troops": full,
		"monthly_food_production": production, "annual_food_production": production * 12.0,
		"monthly_trade_food_import": maxi(int(input.trade_food), 0),
		"monthly_trade_food_export": maxi(-int(input.trade_food), 0),
		"monthly_trade_food_balance": int(input.trade_food),
		"food_stock": int(input.food), "food_per_troop_month": maxf(float(input.nation_field_food) / maxi(current, 1), FOOD_PER_CAPITA_MONTH * Simulation.MAX_SUPPLY_MULT * RulerProfile.food_consumption_multiplier(state.nations[nation_id])),
		"current_monthly_demand": float(input.field_food) + float(input.garrison_food),
		"target_monthly_demand": demand, "full_strength_monthly_demand": full_demand,
		"current_annual_demand": (float(input.field_food) + float(input.garrison_food)) * 12.0,
		"target_annual_demand": demand * 12.0, "full_strength_annual_demand": full_demand * 12.0,
		"current_annual_balance": current_balance,
		"target_annual_balance": annual_balance, "full_strength_annual_balance": full_balance,
		"current_runway_years": _food_runway_years(float(input.food), current_balance),
		"target_runway_years": _food_runway_years(float(input.food), annual_balance),
		"full_strength_runway_years": _food_runway_years(float(input.food), full_balance),
		"required_campaign_years": 1.0, "emergency_food_reserve": int(forecast.food_target),
		"stock_target": int(forecast.food_target), "monthly_food_budget": production - float(forecast.food_savings),
		"affordable_troops": low, "target_sustainable": int(forecast.food_deficit) == 0,
		"forecast": forecast,
	}
	evaluation_cache[key] = result
	return result




static func _food_runway_years(stock: float, annual_balance: float) -> float:
	if annual_balance >= 0.0:
		return MAX_REPORTED_RUNWAY_YEARS
	return minf(
		stock / maxf(-annual_balance, 0.0001),
		MAX_REPORTED_RUNWAY_YEARS
	)


static func _campaign_troop_target(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "campaign_troops:%d:%d" % [
		nation_id,
		target_id,
	]
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var current := _troop_count(
		state,
		nation_id,
		evaluation_cache
	)
	var enemy := _troop_count(
		state,
		target_id,
		evaluation_cache
	)
	var desired := maxi(current, int(ceil(float(enemy) * 1.10)))
	var available := current + maxi(
		state.nations[nation_id].manpower_pool - MIN_MANPOWER_RESERVE,
		0
	)
	var result := mini(
		desired,
		mini(
			available,
			current
				+ MAX_MOBILIZATION_ARMIES
					* GameState.INITIAL_HEAVY_ARMY_SIZE
		)
	)
	evaluation_cache[cache_key] = result
	return result


static func _cached_war_objective(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary,
	legal_reclamation_only: bool = false
) -> Dictionary:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var profile_started := (
		Time.get_ticks_usec() if evaluation_cache.has("__profile") else 0
	)
	var cache_key := "objective:%d:%d:%d:%d:%d:%d:%d:%d:%d" % [
		nation_id,
		target_id,
		state.regional_strategy_revision,
		1 if legal_reclamation_only else 0,
		state.ownership_revision,
		state.diplomacy_revision,
		state.road_network_revision,
		state.administrative_region_revision,
		state.garrison_revision,
	]
	if bool(evaluation_cache.get("__war_desire_debug", false)):
		cache_key += ":debug"
	if evaluation_cache.has(cache_key):
		_record_evaluation_profile(
			evaluation_cache, "objective_cache_hit", profile_started
		)
		return evaluation_cache[cache_key]
	var objective := select_war_objective(
		state,
		nation_id,
		target_id,
		evaluation_cache,
		-1,
		legal_reclamation_only
	)
	evaluation_cache[cache_key] = objective
	_record_evaluation_profile(
		evaluation_cache, "objective_cache_build", profile_started
	)
	return objective


static func select_war_objective(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {},
	excluded_city: int = -1,
	legal_reclamation_only: bool = false,
	excluded_centers: Dictionary = {},
	camp_counterattack: bool = false,
	context: ObjectiveContext = ObjectiveContext.PREWAR
) -> Dictionary:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var target_cities := (
		_cached_cities_of(
			state,
			target_id,
			evaluation_cache
		)
		if not evaluation_cache.is_empty()
		else state.cities_of(target_id)
	)
	if target_cities.is_empty():
		return {}
	var center_set := {}
	for target_city in target_cities:
		if (
			legal_reclamation_only
			and state.recognized_owner_of(target_city.id) != nation_id
		):
			continue
		var center_id := state.administrative_center_of(target_city.id)
		if center_id >= 0 and not center_set.has(center_id) and not excluded_centers.has(center_id) and (
			(camp_counterattack and RulerProfile.offensive_allowed(state.nations[nation_id]) and state.is_enemy(nation_id, target_id))
			or RegionalStrategy.allows_objective(state, nation_id, center_id, legal_reclamation_only)
		):
			center_set[center_id] = true
	var center_ids: Array[int] = []
	center_ids.assign(center_set.keys())
	EquivariantOrder.sort_city_ids(center_ids, state, nation_id)
	if center_ids.is_empty():
		return {}
	var bordering_centers: Array[int] = []
	for center_id in center_ids:
		if _administrative_center_borders_owned_land(
			state, nation_id, center_id, evaluation_cache, context
		):
			bordering_centers.append(center_id)
	# Proposals use their explicit territorial scope; water expeditions remain
	# a fallback when that scope has no land entry into the target states.
	var allow_expedition := bordering_centers.is_empty()
	if not allow_expedition:
		center_ids = bordering_centers
	var max_gold := 1
	var max_food := 1
	var max_manpower := 1
	var defender_index := _city_defender_troop_index(
		state, nation_id, evaluation_cache
	)
	var administrative_aggregates := (
		_administrative_objective_aggregate_index(
			state, evaluation_cache
		)
	)
	var candidates: Array[Dictionary] = []
	var max_reachable_garrison := 1
	for center_id in center_ids:
		var tactical_city := _administrative_proposal_target(
			state,
			nation_id,
			target_id,
			center_id,
			excluded_city,
			legal_reclamation_only,
			evaluation_cache,
			allow_expedition,
			context
		)
		if tactical_city < 0:
			continue
		var own_links := _objective_staging_cities(
			state, nation_id, tactical_city, evaluation_cache, context
		).size()
		if own_links <= 0:
			continue
		var aggregate: Dictionary = administrative_aggregates.get(
			center_id, {}
		)
		var totals := Vector3i(
			aggregate.get("totals", Vector3i.ZERO)
		)
		var owner_counts: Dictionary = aggregate.get("owner_counts", {})
		var controlled := int(owner_counts.get(nation_id, 0))
		var member_count := int(aggregate.get("member_count", 0))
		var has_food_hub := bool(aggregate.get("has_food_hub", false))
		var has_manpower_hub := bool(
			aggregate.get("has_manpower_hub", false)
		)
		var administrative_betweenness := float(
			aggregate.get("betweenness", 0.0)
		)
		max_gold = maxi(max_gold, totals.x)
		max_food = maxi(max_food, totals.y)
		max_manpower = maxi(max_manpower, totals.z)
		max_reachable_garrison = maxi(
			max_reachable_garrison,
			int(defender_index.get(tactical_city, 0))
		)
		candidates.append({
			"center_id": center_id,
			"tactical_city_id": tactical_city,
			"links": own_links,
			"totals": totals,
			"controlled": controlled,
			"member_count": member_count,
			"has_food_hub": has_food_hub,
			"has_manpower_hub": has_manpower_hub,
			"betweenness": administrative_betweenness,
		})
	var best: Dictionary = {}
	for candidate in candidates:
		var center_id := int(candidate["center_id"])
		var tactical_city := int(candidate["tactical_city_id"])
		var city := state.cities[center_id]
		var totals: Vector3i = candidate["totals"]
		var own_links := int(candidate["links"])
		var gold_value := 1.5 * float(totals.x) / float(max_gold)
		var food_value := 1.2 * float(totals.y) / float(max_food)
		var manpower_value := 1.3 * float(totals.z) / float(max_manpower)
		var strategic_value := (
			float(own_links) * 1.25
			+ (3.0 if city.is_capital else 0.0)
			+ (2.0 if city.has_warehouse else 0.0)
			+ (10.0 if bool(candidate["has_food_hub"]) else 0.0)
			+ (10.0 if bool(candidate["has_manpower_hub"]) else 0.0)
		)
		var encirclement_score := encirclement_value(
			state,
			tactical_city,
			target_id,
			evaluation_cache
		)
		strategic_value += encirclement_score
		# 守军空虚补偿：守军越少（相对本国接壤敌城的最强守军）加分越高。这让攻势在
		# 常规价值拉不开差距时主动倒向最好打的敌城，避免“找不到目标就空转”。
		var defender_troops := int(defender_index.get(tactical_city, 0))
		var weak_garrison_value := (
			1.0 - float(defender_troops)
				/ float(max_reachable_garrison)
		) * WEAK_GARRISON_OBJECTIVE_BONUS
		var controlled_share := (
			float(int(candidate["controlled"]))
			/ float(maxi(int(candidate["member_count"]), 1))
		)
		var region_unification_value := (
			REGION_UNIFICATION_OBJECTIVE_BONUS
			* controlled_share * controlled_share
		)
		var node_betweenness_value := float(candidate["betweenness"])
		var value := (
			gold_value
			+ food_value
			+ manpower_value
			+ strategic_value
			+ weak_garrison_value
			+ region_unification_value
			+ node_betweenness_value
		)
		if (
			best.is_empty()
			or value > float(best["value"])
			or (
				is_equal_approx(value, float(best["value"]))
					and EquivariantOrder.city_id_less(
						state,
						nation_id,
						center_id,
						int(best["city_id"])
					)
			)
		):
			best = {
				"city_id": center_id,
				"administrative_center_city_id": center_id,
				"tactical_city_id": tactical_city,
				"value": value,
				"reason": (
					"州治%d%s（州金%d/月、州粮%d/半年、州人%d/月、战略值%.2f、包围值%.2f、目标守军%d空虚值%.2f、州统一值%.2f、交通中心值%.2f）"
					% [
						city.id,
						(
							"【粮食核心】"
							if bool(candidate["has_food_hub"]) else ""
						) + (
							"【人口核心】"
							if bool(candidate["has_manpower_hub"]) else ""
						),
						totals.x,
						totals.y,
						totals.z,
						strategic_value,
						encirclement_score,
						defender_troops,
						weak_garrison_value,
						region_unification_value,
						node_betweenness_value,
					]
				),
			}
			if bool(evaluation_cache.get("__war_desire_debug", false)):
				best["debug_terms"] = {
					"金产归一化": gold_value, "粮产归一化": food_value,
					"人产归一化": manpower_value,
					"集结入口": float(own_links) * 1.25,
					"首都": 3.0 if city.is_capital else 0.0,
					"粮仓": 2.0 if city.has_warehouse else 0.0,
					"粮食核心": 10.0 if bool(candidate["has_food_hub"]) else 0.0,
					"人口核心": 10.0 if bool(candidate["has_manpower_hub"]) else 0.0,
					"包围": encirclement_score, "守军薄弱": weak_garrison_value,
					"本州整合": region_unification_value,
					"交通中心": node_betweenness_value,
				}
	return best


## A diplomacy batch freezes ownership, outputs and region topology. Build the
## state-level parts of objective scoring once instead of re-summing every
## administrative member for every directed nation pair.
static func _administrative_objective_aggregate_index(
	state: GameState,
	evaluation_cache: Dictionary
) -> Dictionary:
	var cache_key := "administrative_objective_aggregates:%d:%d:%d:%d" % [
		state.get_instance_id(), state.ownership_revision,
		state.administrative_region_revision, state.trade_revision,
	]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var result := {}
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		result[center_id] = {
			"totals": Vector3i.ZERO,
			"member_count": 0,
			"has_food_hub": false,
			"has_manpower_hub": false,
			"betweenness": 0.0,
			"owner_counts": {},
		}
	for city in state.cities:
		var center_id := state.administrative_center_of(city.id)
		if not result.has(center_id):
			continue
		var aggregate: Dictionary = result[center_id]
		var totals: Vector3i = aggregate["totals"]
		totals.x += maxi(city.gold_per_month, 0)
		totals.y += maxi(city.food_per_half_year, 0)
		totals.z += maxi(city.manpower_per_month, 0)
		aggregate["totals"] = totals
		aggregate["member_count"] = int(aggregate["member_count"]) + 1
		aggregate["has_food_hub"] = (
			bool(aggregate["has_food_hub"]) or city.is_food_hub
		)
		aggregate["has_manpower_hub"] = (
			bool(aggregate["has_manpower_hub"]) or city.is_manpower_hub
		)
		aggregate["betweenness"] = (
			float(aggregate["betweenness"])
			+ StrategicMapSnapshot.node_betweenness_city_value(
				state, city.id
			)
		)
		var owner_counts: Dictionary = aggregate["owner_counts"]
		owner_counts[city.owner_nation] = (
			int(owner_counts.get(city.owner_nation, 0)) + 1
		)
	evaluation_cache[cache_key] = result
	return result


static func _objective_staging_cities(
	state: GameState,
	nation_id: int,
	city_id: int,
	cache: Dictionary,
	context: ObjectiveContext,
	allow_expedition: bool = true
) -> Array[int]:
	if context == ObjectiveContext.PREWAR:
		return war_preparation_staging_cities(state, nation_id, city_id, cache, allow_expedition)
	if not allow_expedition:
		return staging_cities_for_objective(state, nation_id, city_id, cache)
	return war_staging_cities_for_objective(state, nation_id, city_id, cache)


static func _administrative_entry_candidates(
	state: GameState,
	nation_id: int,
	target_id: int,
	center_city_id: int,
	excluded_city: int,
	legal_reclamation_only: bool,
	evaluation_cache: Dictionary,
	allow_expedition: bool,
	context: ObjectiveContext
) -> Array[int]:
	var candidates: Array[int] = []
	if not state.is_zhou_city(center_city_id):
		return candidates
	for city_id in _cached_administrative_members(
		state, center_city_id, evaluation_cache
	):
		if city_id == excluded_city or state.cities[city_id].owner_nation != target_id:
			continue
		if legal_reclamation_only and state.recognized_owner_of(city_id) != nation_id:
			continue
		if not _objective_staging_cities(
			state, nation_id, city_id, evaluation_cache, context, allow_expedition
		).is_empty():
			candidates.append(city_id)
	return candidates


static func _administrative_frontier_fu(
	state: GameState,
	candidates: Array[int],
	center_city_id: int,
	attacker_bloc: Array[int]
) -> Array[int]:
	var result: Array[int] = []
	for candidate in candidates:
		if candidate == center_city_id:
			continue
		for neighbor in state.territorial_border_neighbors(candidate):
			if attacker_bloc.has(state.cities[neighbor].owner_nation):
				result.append(candidate)
				break
	return result


static func _administrative_proposal_target(
	state: GameState,
	nation_id: int,
	target_id: int,
	center_city_id: int,
	excluded_city: int,
	legal_reclamation_only: bool,
	evaluation_cache: Dictionary,
	allow_expedition: bool,
	context: ObjectiveContext
) -> int:
	var candidates := _administrative_entry_candidates(
		state, nation_id, target_id, center_city_id, excluded_city,
		legal_reclamation_only, evaluation_cache, allow_expedition, context
	)
	if candidates.is_empty():
		return -1
	var frontier := _administrative_frontier_fu(
		state, candidates, center_city_id,
		_expansion_members(state, nation_id, evaluation_cache) if context == ObjectiveContext.PREWAR else _cached_alliance_bloc(state, nation_id, evaluation_cache)
	)
	if not frontier.is_empty():
		candidates = frontier
	elif candidates.has(center_city_id):
		return center_city_id
	EquivariantOrder.sort_city_subset(candidates, state, nation_id, center_city_id)
	return candidates[0]


static func administrative_tactical_target(
	state: GameState,
	nation_id: int,
	target_id: int,
	center_city_id: int,
	excluded_city: int = -1,
	legal_reclamation_only: bool = false,
	evaluation_cache: Dictionary = {},
	allow_expedition: bool = false
) -> int:
	var candidates := _administrative_entry_candidates(
		state, nation_id, target_id, center_city_id, excluded_city,
		legal_reclamation_only, evaluation_cache, allow_expedition,
		ObjectiveContext.CAMPAIGN
	)
	if candidates.is_empty():
		return -1
	var attacker_bloc := _cached_alliance_bloc(state, nation_id, evaluation_cache)
	var center_controlled := attacker_bloc.has(state.cities[center_city_id].owner_nation)
	var required := state.campaign_field_minimum_manpower(nation_id,
		_cached_campaign_reinforcement_threat(state, nation_id, center_city_id, evaluation_cache))
	var existing_plan: CoalitionCampaignFront = state.campaign_front_for(
		nation_id, center_city_id, CoalitionCampaignFront.Mode.OFFENSE
	)
	var committed := (
		0
		if existing_plan == null
		else state.campaign_committed_manpower(nation_id, center_city_id)
	)
	if (
		not center_controlled
		and candidates.has(center_city_id)
		and committed >= required
	):
		return center_city_id
	# 州治已控时清理敌府；兵力不足时只夺与己方战争集团接壤的府。
	var frontier_fu := _administrative_frontier_fu(state, candidates, center_city_id, attacker_bloc)
	if not frontier_fu.is_empty():
		candidates = frontier_fu
	else:
		candidates.erase(center_city_id)
	if candidates.is_empty():
		return center_city_id if not center_controlled and committed >= required else -1
	EquivariantOrder.sort_city_subset(
		candidates, state, nation_id, center_city_id
	)
	return candidates[0]


static func _administrative_center_borders_owned_land(
	state: GameState,
	nation_id: int,
	center_city_id: int,
	evaluation_cache: Dictionary = {},
	context: ObjectiveContext = ObjectiveContext.CAMPAIGN
) -> bool:
	var cache_key := "administrative_border:%d:%d:%d" % [
		nation_id, center_city_id, context,
	]
	if evaluation_cache.has(cache_key):
		return bool(evaluation_cache[cache_key])
	var owners: Array[int] = [nation_id]
	if context == ObjectiveContext.PREWAR:
		owners = _expansion_members(state, nation_id, evaluation_cache)
	for member_id in _cached_administrative_members(
		state, center_city_id, evaluation_cache
	):
		for neighbor in state.territorial_border_neighbors(member_id):
			if owners.has(state.cities[neighbor].owner_nation):
				evaluation_cache[cache_key] = true
				return true
	evaluation_cache[cache_key] = false
	return false


static func region_unification_objective_bonus(
	state: GameState,
	nation_id: int,
	city_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	if (
		state == null
		or nation_id < 0
		or nation_id >= state.nations.size()
		or city_id < 0
		or city_id >= state.cities.size()
	):
		return 0.0
	var center_id := state.administrative_center_of(city_id)
	if center_id < 0:
		return 0.0
	var cache_key := "administrative_control:%d:%d:%d" % [
		nation_id,
		state.ownership_revision,
		state.administrative_region_revision,
	]
	var counts_by_center: Dictionary = evaluation_cache.get(cache_key, {})
	if counts_by_center.is_empty():
		for member_center_value in state.administrative_center_city_ids:
			var member_center := int(member_center_value)
			var counts := Vector2i.ZERO
			for member_id in _cached_administrative_members(
				state, member_center, evaluation_cache
			):
				counts.y += 1
				if state.cities[member_id].owner_nation == nation_id:
					counts.x += 1
			counts_by_center[member_center] = counts
		evaluation_cache[cache_key] = counts_by_center
	var target_counts := Vector2i(
		counts_by_center.get(center_id, Vector2i.ZERO)
	)
	if target_counts.x <= 0 or target_counts.y <= 0:
		return 0.0
	var controlled_share := clampf(
		float(target_counts.x) / float(target_counts.y), 0.0, 1.0
	)
	return REGION_UNIFICATION_OBJECTIVE_BONUS * controlled_share * controlled_share


## 原目标被占、易手或道路封闭时，直接在同一敌国可达城市里选择守军最少者。
## 这是完整价值评分之外的兜底层，确保“攻势找不到目标”时优先攻击空虚城市。
static func replacement_war_preparation_objective(
	state: GameState,
	nation_id: int,
	target_id: int,
	current_city: int,
	evaluation_cache: Dictionary = {},
	legal_reclamation_only: bool = false
) -> Dictionary:
	var objective := select_war_objective(
		state,
		nation_id,
		target_id,
		evaluation_cache,
		current_city,
		legal_reclamation_only
	)
	if objective.is_empty():
		return objective
	var tactical_city := int(objective.get("tactical_city_id", -1))
	var defender_index := _city_defender_troop_index(
		state, nation_id, evaluation_cache
	)
	objective["defender_troops"] = int(
		defender_index.get(tactical_city, 0)
	)
	objective["staging_links"] = war_preparation_staging_cities(
		state, nation_id, tactical_city, evaluation_cache
	).size()
	return objective


## 目标城当前实际驻守敌军兵力索引（IDLE/RECOVERING）。一次外交评估只扫描
## 全军一次，避免目标评分退化为 O(城市×军队)。
static func _city_defender_troop_index(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	var cache_key := "city_defender_troops:%d" % nation_id
	if evaluation_cache.has(cache_key):
		_city_defender_index_hits += 1
		return evaluation_cache[cache_key]
	if (
		not city_defender_index_disabled
		and not evaluation_cache.is_empty()
	):
		var global: Dictionary = _build_city_defender_owner_index(
			state,
			evaluation_cache
		)
		var result := {}
		for city_id in global:
			var city_owners: Dictionary = global[city_id]
			var total := 0
			for owner in city_owners:
				if int(owner) != nation_id:
					total += int(city_owners[owner])
			if total > 0:
				result[int(city_id)] = total
		evaluation_cache[cache_key] = result
		return result
	_city_defender_index_legacy_scans += 1
	var result := {}
	for army in state.armies:
		if (
			army.size > 0
			and army.owner_nation != nation_id
			and army.location_city >= 0
			and army.state in [Army.State.IDLE, Army.State.RECOVERING]
		):
			result[army.location_city] = (
				int(result.get(army.location_city, 0)) + army.size
			)
	if not evaluation_cache.is_empty():
		evaluation_cache[cache_key] = result
	return result


static func leave_alliance_desire(
	state: GameState,
	nation_id: int,
	ally_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var cache_key := "leave_alliance:%d:%d" % [
		nation_id,
		ally_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	if not state.is_allied(nation_id, ally_id) or nation_id == ally_id:
		return -INF
	if state.day - state.relation_since(nation_id, ally_id) < MIN_ALLIANCE_DAYS:
		return -INF
	var common_enemies := _common_enemy_count(
		state,
		nation_id,
		ally_id,
		evaluation_cache
	)
	var own_power := _national_power(
		state,
		nation_id,
		evaluation_cache
	)
	var ally_power := _national_power(
		state,
		ally_id,
		evaluation_cache
	)
	var domination_risk := maxf(
		ally_power / maxf(own_power, 1.0) - 2.25,
		0.0
	) * 0.75
	var conflicting_commitments := 0
	for enemy_id in _cached_wars_of(
		state,
		nation_id,
		evaluation_cache
	):
		if state.is_allied(ally_id, enemy_id):
			conflicting_commitments += 1
	var unilateral_wars := 0
	for enemy_id in _cached_wars_of(
		state,
		ally_id,
		evaluation_cache
	):
		if not state.is_enemy(nation_id, enemy_id):
			unilateral_wars += 1
	var duration_days := state.day - state.relation_since(nation_id, ally_id)
	var established_trust := minf(float(duration_days) / 1800.0, 0.50)
	var attitude := diplomatic_attitude(
		state,
		nation_id,
		ally_id,
		evaluation_cache
	)
	var unification_pressure := unification_rivalry(
		state,
		nation_id,
		ally_id,
		evaluation_cache
	)
	var result := (
		domination_risk
		+ float(conflicting_commitments) * 1.5
		+ float(unilateral_wars) * 0.20
		+ unification_pressure
		+ _cached_integration_war_bonus(state, nation_id, ally_id, evaluation_cache)
		- attitude * ATTITUDE_LEAVE_WEIGHT
		- float(common_enemies) * 0.75
		- established_trust
	)
	evaluation_cache[cache_key] = result
	return result


static func _collect_peace_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary
) -> void:
	var processed_wars := {}
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if committed.has(a) or committed.has(b) or not state.is_enemy(a, b):
				continue
			if not VassalConflict.for_pair(state, a, b).is_empty(): continue
			if state.is_succession_identity(a) or state.is_succession_identity(b):
				continue
			if state.regional_rebellion_peace_locked(a, b):
				continue
			# 削藩内战不走普通议和：宗藩内战只能由明确政治结果（占首都通吃）终结。
			if state.is_suzerainty_pair(a, b) and (
				state.is_in_civil_war(a) or state.is_in_civil_war(b)
			):
				continue
			var bloc_a := _cached_alliance_bloc(
				state, a, evaluation_cache
			)
			var bloc_b := _cached_alliance_bloc(
				state, b, evaluation_cache
			)
			var war_key := _coalition_pair_key(bloc_a, bloc_b)
			if processed_wars.has(war_key):
				continue
			processed_wars[war_key] = true
			var war_days := _coalition_war_days(
				state,
				bloc_a,
				bloc_b,
				evaluation_cache
			)
			if war_days < MIN_WAR_DAYS:
				continue
			var assessment := peace_assessment(
				state,
				a,
				b,
				evaluation_cache
			)
			if not bool(assessment["acceptable"]):
				continue
			var score_a := float(assessment["score_a"])
			var score_b := float(assessment["score_b"])
			var reasons_a := peace_reasons(
				state,
				a,
				b,
				evaluation_cache
			)
			var reasons_b := peace_reasons(
				state,
				b,
				a,
				evaluation_cache
			)
			var reason_a := (
				"战争疲劳"
				if reasons_a.is_empty()
				else "、".join(reasons_a)
			)
			var reason_b := (
				"战争疲劳"
				if reasons_b.is_empty()
				else "、".join(reasons_b)
			)
			var attitude_a := float(
				assessment["breakdown_a"]["attitude"]
			)
			var attitude_b := float(
				assessment["breakdown_b"]["attitude"]
			)
			actions.append({
				"kind": Action.MAKE_PEACE,
				"a": a,
				"b": b,
				"bloc_a": bloc_a,
				"bloc_b": bloc_b,
				"score": float(assessment["combined_score"]) * 0.5,
				"reason": (
					"联盟战争持续%d天；集团%s：%s；集团%s：%s；"
					+ "集团态度%.2f/%.2f，整体意愿%.2f/%.2f，合计%.2f"
				) % [
					war_days,
					str(bloc_a),
					reason_a,
					str(bloc_b),
					reason_b,
					attitude_a,
					attitude_b,
					score_a,
					score_b,
					assessment["combined_score"],
				],
			})
			for member_id in bloc_a:
				committed[member_id] = true
			for member_id in bloc_b:
				committed[member_id] = true


static func _coalition_pair_key(
	bloc_a: Array[int],
	bloc_b: Array[int]
) -> String:
	var key_a := _nation_list_key(bloc_a)
	var key_b := _nation_list_key(bloc_b)
	return (
		"%s|%s" % [key_a, key_b]
		if key_a < key_b
		else "%s|%s" % [key_b, key_a]
	)


static func _nation_list_key(nation_ids: Array[int]) -> String:
	var parts: Array[String] = []
	for nation_id in nation_ids:
		parts.append(str(nation_id))
	return ",".join(parts)


static func _coalition_war_days(
	state: GameState,
	bloc_a: Array[int],
	bloc_b: Array[int],
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "coalition_war_days:%s" % (
		_coalition_pair_key(bloc_a, bloc_b)
	)
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var started_day := state.day
	var found := false
	for member_a in bloc_a:
		for member_b in bloc_b:
			if not state.is_enemy(member_a, member_b):
				continue
			started_day = mini(
				started_day,
				state.relation_since(member_a, member_b)
			)
			found = true
	var result := state.day - started_day if found else 0
	if not bool(evaluation_cache.get(
		"__disable_structure_cache", false
	)):
		evaluation_cache[cache_key] = result
	return result


static func _commit_alliance_bloc(
	state: GameState,
	nation_id: int,
	committed: Dictionary,
	evaluation_cache: Dictionary
) -> void:
	for member_id in _cached_alliance_bloc(
		state, nation_id, evaluation_cache
	):
		committed[member_id] = true


static func _collect_leave_alliance_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary
) -> void:
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if committed.has(a) or committed.has(b) or not state.is_allied(a, b):
				continue
			# 同一宗藩体系内的 ALLIED 是制度性共同体关系，不是普通盟约。
			# 宗主、直属藩王和兄弟藩王只能通过削藩内战改变关系。
			if state.is_same_suzerainty_system(a, b):
				continue
			var score_a := leave_alliance_desire(
				state,
				a,
				b,
				evaluation_cache
			)
			var score_b := leave_alliance_desire(
				state,
				b,
				a,
				evaluation_cache
			)
			var actor := a if score_a >= score_b else b
			var target := b if actor == a else a
			var score := maxf(score_a, score_b)
			if score < LEAVE_ALLIANCE_SCORE:
				continue
			var attitude := diplomatic_attitude(
				state,
				actor,
				target,
				evaluation_cache
			)
			var unification_pressure := unification_rivalry(
				state,
				actor,
				target,
				evaluation_cache
			)
			actions.append({
				"kind": Action.LEAVE_ALLIANCE,
				"a": actor,
				"b": target,
				"score": score,
				"reason": (
					"外交态度%.2f、统一竞争压力%.2f，退盟收益%.2f"
					% [attitude, unification_pressure, score]
				),
			})
			_commit_alliance_bloc(state, a, committed, evaluation_cache)
			_commit_alliance_bloc(state, b, committed, evaluation_cache)


static func _collect_alliance_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary,
	start_nation_index: int = 0,
	end_nation_index: int = -1
) -> void:
	var end_index := (
		state.nations.size()
		if end_nation_index < 0
		else mini(end_nation_index, state.nations.size())
	)
	for a in range(maxi(start_nation_index, 0), end_index):
		for b in _diplomatic_range_nation_ids(
			state, a, evaluation_cache
		):
			if b <= a:
				continue
			if (
				committed.has(a)
				or committed.has(b)
				or not state.nations[a].alive
				or not state.nations[b].alive
				or state.nations[a].succession_identity
				or state.nations[b].succession_identity
				or state.relation_between(a, b)
					!= GameState.DiplomaticRelation.NEUTRAL
				or state.nations[a].war_preparation_target_nation >= 0
				or state.nations[b].war_preparation_target_nation >= 0
			):
				continue
			if (
				not _alliance_can_reach_acceptance(
					state, a, b, evaluation_cache
				)
				or not _alliance_can_reach_acceptance(
					state, b, a, evaluation_cache
				)
			):
				continue
			var score_a := alliance_willingness(
				state,
				a,
				b,
				evaluation_cache
			)
			if score_a < ALLIANCE_ACCEPT_SCORE:
				continue
			var score_b := alliance_willingness(
				state,
				b,
				a,
				evaluation_cache
			)
			if score_b < ALLIANCE_ACCEPT_SCORE:
				continue
			var attitude_a := diplomatic_attitude(
				state,
				a,
				b,
				evaluation_cache
			)
			var attitude_b := diplomatic_attitude(
				state,
				b,
				a,
				evaluation_cache
			)
			actions.append({
				"kind": Action.FORM_ALLIANCE,
				"a": a,
				"b": b,
				"score": minf(score_a, score_b),
				"reason": (
					"缔结共同防御与军事通行条约，"
					+ "双边态度%.2f/%.2f、结盟意愿%.2f/%.2f"
				) % [attitude_a, attitude_b, score_a, score_b],
			})
			_commit_alliance_bloc(state, a, committed, evaluation_cache)
			_commit_alliance_bloc(state, b, committed, evaluation_cache)


## 已经进入备战的国家拥有跨月战略承诺，必须先于本月新战争提案处理。
## 否则低 id 国家先提交新目标会反复占用 committed，令后续国家的成熟备战饥饿。
static func _collect_existing_war_preparation_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary,
	start_nation_index: int = 0,
	end_nation_index: int = -1
) -> void:
	var end_index := (
		state.nations.size()
		if end_nation_index < 0
		else mini(end_nation_index, state.nations.size())
	)
	for nation_index in range(maxi(start_nation_index, 0), end_index):
		var nation := state.nations[nation_index]
		if (
			committed.has(nation.id)
			or not nation.alive
			or nation.war_preparation_target_nation < 0
		):
			continue
		var preparation_started := (
			Time.get_ticks_usec()
			if evaluation_cache.has("__profile")
			else 0
		)
		_collect_existing_war_preparation(
			state,
			nation.id,
			actions,
			committed,
			evaluation_cache
		)
		_record_evaluation_profile(
			evaluation_cache,
			"war_existing_preparation",
			preparation_started
		)


static func _collect_war_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary,
	start_nation_index: int = 0,
	end_nation_index: int = -1,
	collect_existing_preparations: bool = true
) -> void:
	var end_index := (
		state.nations.size()
		if end_nation_index < 0
		else mini(end_nation_index, state.nations.size())
	)
	for nation_index in range(maxi(start_nation_index, 0), end_index):
		var nation := state.nations[nation_index]
		if committed.has(nation.id) or not nation.alive or nation.succession_identity:
			continue
		if nation.war_preparation_target_nation >= 0:
			if collect_existing_preparations:
				_collect_existing_war_preparation(
					state,
					nation.id,
					actions,
					committed,
					evaluation_cache
				)
			continue
		# 藩王不独立发动战争；宗藩体系的对外战争由宗主及联盟共同承担。
		if state.is_vassal(nation.id):
			continue
		# 取消备战冷却：刚取消过备战的国家在冷却期内不得重新发起，打断终局横跳正反馈。
		if (
			nation.war_preparation_cancelled_day >= 0
			and state.day - nation.war_preparation_cancelled_day
				< WAR_PREPARATION_CANCEL_COOLDOWN_DAYS
		):
			continue
		var part_started := (
			Time.get_ticks_usec()
			if evaluation_cache.has("__profile")
			else 0
		)
		var precheck_failed := (
			_cached_war_count(
				state,
				nation.id,
				evaluation_cache
			)
				>= MAX_CONCURRENT_WARS
			or not offensive_resources_ready(
				state,
				nation.id,
				resource_report(
					state,
					nation.id,
					evaluation_cache
				)
			)
		)
		_record_evaluation_profile(
			evaluation_cache, "war_collect_precheck", part_started
		)
		if precheck_failed:
			continue
		part_started = (
			Time.get_ticks_usec()
			if evaluation_cache.has("__profile")
			else 0
		)
		var best_target := -1
		var best_score := -INF
		var bordering_nations := _expansion_bordering_nation_ids(
			state, nation.id, evaluation_cache
		)
		if bordering_nations.is_empty():
			bordering_nations = _expedition_target_nation_ids(
				state, nation.id, evaluation_cache, ObjectiveContext.PREWAR
			)
		for target_id in bordering_nations:
			var target := state.nations[target_id]
			if committed.has(target.id) or not target.alive or target.succession_identity:
				continue
			var score := war_desire(
				state,
				nation.id,
				target.id,
				evaluation_cache
			)
			if score > best_score or (
				is_equal_approx(score, best_score)
				and (
					best_target == -1
					or EquivariantOrder.nation_less(
						state,
						nation.id,
						target.id,
						best_target
					)
				)
			):
				best_score = score
				best_target = target.id
		_record_evaluation_profile(
			evaluation_cache, "war_collect_candidates", part_started
		)
		if best_target == -1 or best_score < WAR_DECLARE_SCORE:
			continue
		part_started = (
			Time.get_ticks_usec()
			if evaluation_cache.has("__profile")
			else 0
		)
		var objective := _cached_war_objective(
			state,
			nation.id,
			best_target,
			evaluation_cache,
			false
		)
		var report := resource_report(
			state,
			nation.id,
			evaluation_cache
		)
		if (
			objective.is_empty()
			or not _ruler_allows_war_objective(
				state,
				nation.id,
				int(objective.get("city_id", -1))
			)
			or not offensive_resources_ready(
				state,
				nation.id,
				report
			)
		):
			continue
		var mobilization_armies := mobilization_capacity(
			state,
			nation.id,
			FoodPosture.OFFENSIVE_WAR,
			evaluation_cache
		)
		var campaign_troops := (
			int(report["troops"])
			+ mobilization_armies * GameState.INITIAL_HEAVY_ARMY_SIZE
		)
		var food_plan := war_food_report(
			state,
			nation.id,
			campaign_troops,
			FoodPosture.OFFENSIVE_WAR,
			evaluation_cache
		)
		var attitude := diplomatic_attitude(
			state,
			nation.id,
			best_target,
			evaluation_cache
		)
		var unification_pressure := unification_rivalry(
			state,
			nation.id,
			best_target,
			evaluation_cache
		)
		var peace_escalation := neutral_peace_escalation(
			state,
			nation.id,
			best_target
		)
		actions.append({
			"kind": Action.PREPARE_WAR,
			"a": nation.id,
			"b": best_target,
			"score": best_score,
			"objective_city": int(objective["tactical_city_id"]),
			"objective_center_city": int(objective["city_id"]),
			"objective_reason": str(objective["reason"]),
			"mobilization_armies": mobilization_armies,
			"reason": (
				(
					"准备对国%d发动战争，目标%s；储备金%d/%d、粮%d/%d、人%d/%d；"
					+ "目标兵力%d，年粮结余%.0f，可支撑%.1f年；"
					+ "现有编制全满年结余%.0f，可支撑%.1f年；"
					+ "外交态度%.2f、统一竞争压力%.2f、长期和平压力%.2f；"
					+ "先集结并额外动员%d军；战争收益%.2f"
				)
				% [
					best_target,
					objective["reason"],
					nation.treasury_gold,
					report["gold_required"],
					report["food_stock"],
					report["food_required"],
					nation.manpower_pool,
					report["manpower_required"],
					campaign_troops,
					food_plan["target_annual_balance"],
					food_plan["target_runway_years"],
					food_plan["full_strength_annual_balance"],
					food_plan["full_strength_runway_years"],
					attitude,
					unification_pressure,
					peace_escalation,
					mobilization_armies,
					best_score,
				]
			),
		})
		_record_evaluation_profile(
			evaluation_cache, "war_collect_finalize", part_started
		)
		_commit_alliance_bloc(
			state, nation.id, committed, evaluation_cache
		)
		_commit_alliance_bloc(
			state, best_target, committed, evaluation_cache
		)


static func _collect_existing_war_preparation(
	state: GameState,
	nation_id: int,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary = {}
) -> void:
	var nation := state.nations[nation_id]
	var target_id := nation.war_preparation_target_nation
	var objective_city := nation.war_preparation_objective_city
	var objective_center := nation.war_preparation_objective_center_city
	if objective_center < 0:
		objective_center = state.administrative_center_of(objective_city)
	# 备战是战略状态，不依赖瞬时道路容量或边境屯兵。目标国仍是合法敌手时，
	# 先在同国改选一个可达的薄弱城市；如果整个边境暂时封闭则保持备战等待，
	# 绝不因道路状态发出取消，从根上消除“封路→取消→恢复→重开”的横跳。
	var target_nation_valid := (
		target_id >= 0
		and target_id < state.nations.size()
		and state.nations[target_id].alive
		and can_initiate_war_at_range(
			state, nation_id, target_id, evaluation_cache
		)
		and state.can_alliance_declare_war(nation_id, target_id)
	)
	var objective_valid := (
		target_nation_valid
		and objective_city >= 0
		and objective_city < state.cities.size()
		and state.cities[objective_city].owner_nation == target_id
		and _ruler_allows_war_objective(
			state, nation_id, objective_city
		)
	)
	var region_valid := RegionalStrategy.allows_objective(state, nation_id, objective_center)
	var has_route := (
		objective_valid
		and not war_preparation_staging_cities(
			state,
			nation_id,
			objective_city,
			evaluation_cache
		).is_empty()
	)
	if objective_valid and has_route:
		var current_staging := war_preparation_staging_cities(
			state,
			nation_id,
			objective_city,
			evaluation_cache,
		)
		if (
			nation.war_preparation_objective_center_city != objective_center
			or not current_staging.has(
				nation.war_preparation_staging_city_id
			)
		):
			actions.append({
				"kind": Action.RETARGET_WAR_PREPARATION,
				"a": nation_id,
				"b": target_id,
				"objective_city": objective_city,
				"objective_center_city": objective_center,
				"objective_reason": nation.war_preparation_reason,
				"reason": "州域或道路变化，重新冻结战前集结点",
			})
			committed[nation_id] = true
			return
	if target_nation_valid and (not objective_valid or not has_route):
		var replacement := replacement_war_preparation_objective(
			state,
			nation_id,
			target_id,
			objective_city,
			evaluation_cache,
			false
		)
		if not replacement.is_empty():
			actions.append({
				"kind": Action.RETARGET_WAR_PREPARATION,
				"a": nation_id,
				"b": target_id,
				"objective_city": int(replacement["tactical_city_id"]),
				"objective_center_city": int(replacement["city_id"]),
				"objective_reason": str(replacement["reason"]),
				"reason": (
					"原备战目标城市%d不可用，保持对国%d备战并改向%s"
					% [objective_city, target_id, replacement["reason"]]
				),
			})
			committed[nation_id] = true
			return
	var elapsed := state.day - nation.war_preparation_started_day
	var resources_ready := war_preparation_resources_ready(
		state,
		nation_id,
		evaluation_cache
	)
	var resource_grace_expired := (
		nation.war_preparation_unready_since_day >= 0
		and state.day
			- nation.war_preparation_unready_since_day
			>= WAR_PREPARATION_RESOURCE_GRACE_DAYS
	)
	var preparation_ready := war_preparation_ready(
		state,
		nation_id,
		evaluation_cache
	)
	# 超时兜底与宣战提交共用资格：半额备战目标、当前野战门槛及资源／路线／外交。
	var best_effort_launch := (
		not preparation_ready
		and war_preparation_launch_allowed(state, nation_id, evaluation_cache)
	)
	if (
		not best_effort_launch
		and (
			not target_nation_valid
			or resource_grace_expired
			or not region_valid
		)
	):
		actions.append({
			"kind": Action.CANCEL_WAR_PREPARATION,
			"a": nation_id,
			"b": target_id,
			"reason": (
				"目标国失效或己方人力／粮食连续不足%d天，取消对国%d的战争准备；道路、敌军屯兵和集结进度不触发取消"
				% [
					WAR_PREPARATION_RESOURCE_GRACE_DAYS,
					target_id,
				]
			),
		})
		committed[nation_id] = true
		return
	# 没有任何可达目标时保持战略备战；道路恢复或边境易手后会自动重选。
	if not objective_valid or not has_route:
		return
	if not resources_ready:
		return
	if not preparation_ready and not best_effort_launch:
		if _collect_preparation_alliance(
			state,
			nation_id,
			target_id,
			actions,
			committed,
			evaluation_cache
		):
			return
		return
	if not _ruler_allows_war_objective(
		state, nation_id, objective_city
	):
		return
	var mobilization_armies := maxi(
		int(ceil(
			float(
				nation.war_mobilization_target_troops
				- _troop_count(state, nation_id, evaluation_cache)
			) / float(GameState.INITIAL_HEAVY_ARMY_SIZE)
		)),
		0
	)
	actions.append({
		"kind": Action.ISSUE_ULTIMATUM,
		"a": nation_id,
		"b": target_id,
		"objective_city": objective_city,
		"objective_center_city": objective_center,
		"objective_reason": nation.war_preparation_reason,
		"mobilization_armies": mobilization_armies,
		"reason": (
			"完成%d天战争准备，目标城市%d方向已集结%d人，发出通牒，拒绝后宣战"
			% [
				elapsed,
				objective_city,
				war_preparation_arrived_troops(
					state, nation_id, evaluation_cache
				),
			]
		),
	})
	_commit_alliance_bloc(
		state, nation_id, committed, evaluation_cache
	)
	_commit_alliance_bloc(
		state, target_id, committed, evaluation_cache
	)


static func _collect_preparation_alliance(
	state: GameState,
	nation_id: int,
	war_target_id: int,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary = {}
) -> bool:
	var best_target := -1
	var best_score := -INF
	var bounded_candidates: Array[Dictionary] = []
	for candidate_id in _diplomatic_range_nation_ids(
		state, nation_id, evaluation_cache
	):
		var candidate := state.nations[candidate_id]
		if (
			candidate.id in [nation_id, war_target_id]
			or not candidate.alive
			or committed.has(candidate.id)
			or state.is_allied(candidate.id, war_target_id)
			or not within_diplomatic_range(
				state, nation_id, candidate.id, evaluation_cache
			)
		):
			continue
		if (
			not _alliance_can_reach_acceptance(
				state, nation_id, candidate.id, evaluation_cache
			)
			or not _alliance_can_reach_acceptance(
				state, candidate.id, nation_id, evaluation_cache
			)
		):
			continue
		var mutual_upper_bound := minf(
			float(evaluation_cache.get(
				"alliance_acceptance_upper_bound:%d:%d"
				% [nation_id, candidate.id],
				INF
			)),
			float(evaluation_cache.get(
				"alliance_acceptance_upper_bound:%d:%d"
				% [candidate.id, nation_id],
				INF
			))
		)
		bounded_candidates.append({
			"nation_id": candidate.id,
			"upper_bound": mutual_upper_bound,
		})
	bounded_candidates.sort_custom(func(
		left: Dictionary, right: Dictionary
	) -> bool:
		var left_bound := float(left["upper_bound"])
		var right_bound := float(right["upper_bound"])
		if left_bound != right_bound:
			return left_bound > right_bound
		return EquivariantOrder.nation_less(
			state,
			nation_id,
			int(left["nation_id"]),
			int(right["nation_id"])
		)
	)
	for bounded_candidate in bounded_candidates:
		var candidate_id := int(bounded_candidate["nation_id"])
		var upper_bound := float(bounded_candidate["upper_bound"])
		if upper_bound < best_score and not is_equal_approx(
			upper_bound, best_score
		):
			break
		var score_a := alliance_willingness(
			state,
			nation_id,
			candidate_id,
			evaluation_cache
		)
		if score_a < ALLIANCE_ACCEPT_SCORE:
			continue
		var score_b := alliance_willingness(
			state,
			candidate_id,
			nation_id,
			evaluation_cache
		)
		var score := minf(score_a, score_b)
		if score_b < ALLIANCE_ACCEPT_SCORE:
			continue
		if (
			score > best_score
			or (
				is_equal_approx(score, best_score)
				and (
					best_target == -1
						or EquivariantOrder.nation_less(
							state,
							nation_id,
							candidate_id,
							best_target
						)
				)
			)
		):
			best_score = score
			best_target = candidate_id
	if best_target < 0:
		return false
	actions.append({
		"kind": Action.FORM_ALLIANCE,
		"a": nation_id,
		"b": best_target,
		"score": best_score,
		"reason": (
			"备战国%d期间与非目标国%d结盟，释放中立边境守军投入目标国%d方向"
			% [nation_id, best_target, war_target_id]
		),
	})
	committed[nation_id] = true
	committed[best_target] = true
	return true


static func war_preparation_launch_allowed(state: GameState, nation_id: int, cache: Dictionary = {}) -> bool:
	var nation := state.nations[nation_id]
	var target := nation.war_preparation_target_nation
	var objective := nation.war_preparation_objective_city
	if target < 0 or target >= state.nations.size() or objective < 0 or objective >= state.cities.size() or nation.war_preparation_started_day < 0:
		return false
	if not state.nations[target].alive or state.cities[objective].owner_nation != target or not _ruler_allows_war_objective(state, nation_id, objective):
		return false
	if not state.can_alliance_declare_war(nation_id, target) or not RegionalStrategy.allows_objective(state, nation_id, nation.war_preparation_objective_center_city):
		return false
	if nation.war_preparation_objective_center_city != state.administrative_center_of(objective):
		return false
	if not can_initiate_war_at_range(state, nation_id, target, cache) or not war_preparation_staging_cities(state, nation_id, objective, cache).has(nation.war_preparation_staging_city_id):
		return false
	if not war_preparation_resources_ready(state, nation_id, cache):
		return false
	if war_preparation_arrived_troops(state, nation_id, cache) < state.campaign_field_minimum_manpower(nation_id,
		state.campaign_prewar_reinforcement_threat(nation_id, target, nation.war_preparation_objective_center_city)):
		return false
	if war_preparation_ready(state, nation_id, cache):
		return true
	var unready := nation.war_preparation_unready_since_day
	return state.day - nation.war_preparation_started_day >= WAR_PREPARATION_MAX_DAYS \
		and (unready < 0 or state.day - unready < WAR_PREPARATION_RESOURCE_GRACE_DAYS) \
		and war_preparation_arrived_troops(state, nation_id, cache) > 0 \
		and war_preparation_arrived_troops(state, nation_id, cache) >= ceili(float(required_assault_troops(state, nation_id, objective, cache)) * WAR_PREPARATION_BEST_EFFORT_RATIO)


static func war_preparation_ready(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	var nation := state.nations[nation_id]
	if (
		nation.war_preparation_target_nation < 0
		or nation.war_preparation_objective_city < 0
	):
		return false
	var objective_center := nation.war_preparation_objective_center_city
	if objective_center < 0:
		objective_center = state.administrative_center_of(
			nation.war_preparation_objective_city
		)
	if not state.is_zhou_city(objective_center):
		return false
	var staging := war_preparation_staging_cities(
		state,
		nation_id,
		nation.war_preparation_objective_city,
		evaluation_cache,
	)
	if (
		nation.war_preparation_staging_city_id < 0
		or not staging.has(nation.war_preparation_staging_city_id)
	):
		return false
	return war_preparation_arrived_troops(
		state, nation_id, evaluation_cache
	) >= (
		state.campaign_prewar_launch_requirement(
			nation_id,
			nation.war_preparation_target_nation,
			objective_center,
		)
	)


static func war_preparation_arrived_troops(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	if nation_id < 0 or nation_id >= state.nations.size():
		return 0
	var cache_key := "war_preparation_arrived:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var nation := state.nations[nation_id]
	var staging_city_id := nation.war_preparation_staging_city_id
	if staging_city_id < 0:
		return 0
	var army_ids := {}
	for army_id in nation.war_preparation_army_ids:
		army_ids[army_id] = true
	var result := 0
	for army in state.armies:
		if (
			army.owner_nation == nation_id
			and army_ids.has(army.id)
			and army.campaign_war_id < 0 and army.campaign_front_id < 0
			and state.army_effective_for_field_campaign(army)
			and army.state == Army.State.IDLE
			and army.is_at_city_node(staging_city_id)
		):
			result += army.size
	evaluation_cache[cache_key] = result
	return result


static func staging_cities_for_objective(
	state: GameState,
	nation_id: int,
	objective_city: int,
	evaluation_cache: Dictionary = {}
) -> Array[int]:
	var cache_key := "staging:%d:%d:%d:%d:%d" % [
		nation_id,
		objective_city,
		state.ownership_revision,
		state.diplomacy_revision,
		state.road_network_revision,
	]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key] as Array[int]
	var result: Array[int] = []
	for neighbor in state.neighbors(objective_city):
		var edge := state.edge_of(neighbor, objective_city)
		if (
			edge != null
			and edge.max_manpower > 0
			and state.has_military_access(
				nation_id, state.cities[neighbor].owner_nation
			)
		):
			result.append(neighbor)
	# A local dock crossing is a political border between its two land banks.
	# Stage on the accessible bank instead of requiring access to the dock node,
	# whose owner is chosen from either side. Territorial neighbors never walk a
	# RIVER/SEA chain, so this does not turn downstream docks into land borders.
	for neighbor in state.territorial_border_neighbors(objective_city):
		var support_edges := state.territorial_border_support_edges(
			neighbor, objective_city
		)
		if (
			support_edges.size() == 2
			and support_edges[0].kind == Edge.Kind.LANDING
			and support_edges[1].kind == Edge.Kind.LANDING
			and support_edges[0].max_manpower > 0
			and support_edges[1].max_manpower > 0
			and not result.has(neighbor)
			and state.has_military_access(
				nation_id, state.cities[neighbor].owner_nation
			)
		):
			result.append(neighbor)
	EquivariantOrder.sort_city_subset(
		result,
		state,
		nation_id,
		objective_city
	)
	evaluation_cache[cache_key] = result
	return result


static func _dock_expedition_staging_cities(
	state: GameState,
	nation_id: int,
	objective_city: int,
	evaluation_cache: Dictionary = {},
	context: ObjectiveContext = ObjectiveContext.CAMPAIGN
) -> Array[int]:
	var result: Array[int] = []
	var cache_key := "expedition_staging:%d:%d:%d:%d:%d:%d" % [
		nation_id,
		objective_city,
		state.ownership_revision,
		state.diplomacy_revision,
		state.road_network_revision,
		context,
	]
	if evaluation_cache.has(cache_key):
		return (evaluation_cache[cache_key] as Array[int]).duplicate()
	if (
		objective_city < 0 or objective_city >= state.cities.size()
		or state.cities[objective_city].is_dock
	):
		evaluation_cache[cache_key] = result
		return result
	var target_nation := state.cities[objective_city].owner_nation
	if target_nation < 0 or target_nation == nation_id:
		evaluation_cache[cache_key] = result
		return result
	var target_docks := {}
	for neighbor in state.neighbors(objective_city):
		var landing := state.edge_of(objective_city, neighbor)
		if (
			landing != null
			and landing.kind == Edge.Kind.LANDING
			and landing.max_manpower > 0
			and state.cities[neighbor].is_dock
			and state.cities[neighbor].owner_nation == target_nation
		):
			target_docks[neighbor] = true
	if target_docks.is_empty():
		evaluation_cache[cache_key] = result
		return result
	var visited: Dictionary = target_docks.duplicate()
	var queue: Array[int] = []
	for dock_value in target_docks:
		queue.append(int(dock_value))
	var cursor := 0
	while cursor < queue.size():
		var dock_id := queue[cursor]
		cursor += 1
		for neighbor in state.neighbors(dock_id):
			if visited.has(neighbor) or not state.cities[neighbor].is_dock:
				continue
			var water_edge := state.edge_of(dock_id, neighbor)
			if (
				water_edge == null
				or water_edge.max_manpower <= 0
				or water_edge.kind not in [Edge.Kind.RIVER, Edge.Kind.SEA]
			):
				continue
			var owner := state.cities[neighbor].owner_nation
			if (
				owner != target_nation
				and not state.has_military_access(nation_id, owner)
			):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	var sources: Array[int] = [nation_id]
	if context == ObjectiveContext.PREWAR:
		sources = _expansion_members(state, nation_id, evaluation_cache)
	for dock_value in visited:
		var dock_id := int(dock_value)
		if sources.has(state.cities[dock_id].owner_nation) and state.has_military_access(nation_id, state.cities[dock_id].owner_nation):
			result.append(dock_id)
	EquivariantOrder.sort_city_ids(result, state, nation_id, objective_city)
	evaluation_cache[cache_key] = result
	return result.duplicate()


static func war_staging_cities_for_objective(
	state: GameState,
	nation_id: int,
	objective_city: int,
	evaluation_cache: Dictionary = {}
) -> Array[int]:
	var direct := staging_cities_for_objective(
		state, nation_id, objective_city, evaluation_cache
	)
	if not direct.is_empty():
		return direct
	return _dock_expedition_staging_cities(
		state, nation_id, objective_city, evaluation_cache
	)


static func war_preparation_staging_cities(
	state: GameState,
	nation_id: int,
	objective_city: int,
	evaluation_cache: Dictionary = {},
	allow_expedition: bool = true
) -> Array[int]:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var result: Array[int] = []
	if objective_city < 0 or objective_city >= state.cities.size():
		return result
	var key := "prewar_staging:%d:%d:%d:%d" % [nation_id, objective_city, int(allow_expedition), state.day]
	if evaluation_cache.has(key):
		return evaluation_cache[key] as Array[int]
	var members := _expansion_members(state, nation_id, evaluation_cache)
	var candidates := staging_cities_for_objective(state, nation_id, objective_city, evaluation_cache)
	for city_id in candidates:
		if members.has(state.cities[city_id].owner_nation) and _prewar_source_reaches(state, nation_id, city_id, evaluation_cache):
			result.append(city_id)
	if result.is_empty() and allow_expedition:
		for city_id in _dock_expedition_staging_cities(state, nation_id, objective_city, evaluation_cache, ObjectiveContext.PREWAR):
			if _prewar_source_reaches(state, nation_id, city_id, evaluation_cache):
				result.append(city_id)
	evaluation_cache[key] = result
	return result


static func required_assault_troops(
	state: GameState,
	nation_id: int,
	objective_city: int,
	evaluation_cache: Dictionary = {}
) -> int:
	if nation_id >= 0 and nation_id < state.nations.size():
		var nation := state.nations[nation_id]
		var center_id := state.administrative_center_of(objective_city)
		if (
			nation.war_preparation_target_nation >= 0
			and center_id >= 0
		):
			return state.campaign_prewar_launch_requirement(
				nation_id,
				nation.war_preparation_target_nation,
				center_id,
			)
	var objective_requirement := objective_assault_troops(
		state,
		nation_id,
		objective_city,
		evaluation_cache
	)
	if objective_requirement <= 0:
		return objective_requirement
	return objective_requirement


static func objective_assault_troops(
	state: GameState,
	nation_id: int,
	objective_city: int,
	evaluation_cache: Dictionary = {}
) -> int:
	if objective_city < 0 or objective_city >= state.cities.size():
		return 0
	var center_id := state.administrative_center_of(objective_city)
	if center_id < 0:
		return 0
	return state.campaign_offense_manpower(nation_id,
		_cached_campaign_siege_requirement(state, nation_id, center_id, evaluation_cache),
		_cached_campaign_reinforcement_threat(
			state, nation_id, center_id, evaluation_cache
		)
	)


static func _cached_campaign_siege_requirement(
	state: GameState, attacker_id: int, center_id: int, evaluation_cache: Dictionary
) -> int:
	if bool(evaluation_cache.get("__disable_structure_cache", false)):
		return state.campaign_siege_requirement(attacker_id, center_id)
	var bloc := _cached_alliance_bloc(state, attacker_id, evaluation_cache)
	var representative := bloc[0] if not bloc.is_empty() else attacker_id
	var garrison := state.cities[center_id].garrison_manpower if center_id >= 0 and center_id < state.cities.size() else 0
	var key := "campaign_r:%d:%d:%d:%d:%d:%d:%d" % [representative, center_id,
		state.ownership_revision, state.diplomacy_revision, state.garrison_revision,
		state.administrative_region_revision, garrison]
	if not evaluation_cache.has(key):
		evaluation_cache[key] = state.campaign_siege_requirement(attacker_id, center_id, bloc)
	return int(evaluation_cache[key])


static func _cached_campaign_reinforcement_threat(
	state: GameState,
	attacker_id: int,
	center_city_id: int,
	evaluation_cache: Dictionary
) -> int:
	if (
		campaign_v_index_disabled
		or bool(evaluation_cache.get("__disable_structure_cache", false))
	):
		_campaign_v_legacy_scans += 1
		return state.campaign_reinforcement_threat(
			attacker_id, center_city_id
		)
	var cache_key := "campaign_v_index:%d" % attacker_id
	if evaluation_cache.has(cache_key):
		_campaign_v_index_hits += 1
		return int((evaluation_cache[cache_key] as Dictionary).get(
			center_city_id, 0
		))
	var threat_by_center := {}
	for army in state.armies:
		if (
			not state.army_effective_for_field_campaign(army)
			or army.is_city_garrison
			or not state.is_enemy(attacker_id, army.owner_nation)
		):
			continue
		var centers := {}
		if army.on_edge:
			for city_id in [army.move_from, army.move_to]:
				var center_id := state.administrative_center_of(city_id)
				if center_id >= 0:
					centers[center_id] = true
		elif army.location_city >= 0:
			var center_id := state.administrative_center_of(
				army.location_city
			)
			if center_id >= 0:
				centers[center_id] = true
		for center_value in centers:
			var center_id := int(center_value)
			threat_by_center[center_id] = (
				int(threat_by_center.get(center_id, 0)) + army.size
			)
	evaluation_cache[cache_key] = threat_by_center
	_campaign_v_index_builds += 1
	return int(threat_by_center.get(center_city_id, 0))


static func _national_power(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "power:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	_build_nation_aggregates(state, evaluation_cache)
	return float(evaluation_cache.get(cache_key, 0.0))


static func _troop_count(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "troops:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	_build_nation_aggregates(state, evaluation_cache)
	return int(evaluation_cache.get(cache_key, 0))


static func _full_strength_troop_count(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "full_troops:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	_build_nation_aggregates(state, evaluation_cache)
	return int(evaluation_cache.get(cache_key, 0))


static func _build_nation_aggregates(
	state: GameState,
	evaluation_cache: Dictionary
) -> void:
	if evaluation_cache.has("nation_aggregates_built"):
		return
	evaluation_cache["nation_aggregates_built"] = true
	var power: Array[float] = []
	var troops: Array[int] = []
	var full_troops: Array[int] = []
	var cities_by_nation := {}
	power.resize(state.nations.size())
	power.fill(0.0)
	troops.resize(state.nations.size())
	troops.fill(0)
	full_troops.resize(state.nations.size())
	full_troops.fill(0)
	for nation in state.nations:
		cities_by_nation[nation.id] = [] as Array[City]
	for city in state.cities:
		if city.owner_nation < 0 or city.owner_nation >= state.nations.size():
			continue
		(cities_by_nation[state.financial_nation_of(city.owner_nation)] as Array[City]).append(
			city
		)
	for army in state.armies:
		if army.size <= 0:
			continue
		var owner := army.owner_nation
		power[owner] += ArmyPower.effective(army)
		troops[owner] += army.size
		full_troops[owner] += army.max_size
	for nation in state.nations:
		var nation_id := nation.id
		var owned_cities: Array[City] = cities_by_nation[nation_id]
		evaluation_cache["owned_cities:%d" % nation_id] = (
			owned_cities
		)
		evaluation_cache["power:%d" % nation_id] = (
			power[nation_id]
			+ float(owned_cities.size()) * 1500.0
		)
		evaluation_cache["troops:%d" % nation_id] = (
			troops[nation_id]
		)
		evaluation_cache["full_troops:%d" % nation_id] = (
			full_troops[nation_id]
		)


static func _cached_cities_of(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> Array[City]:
	var cache_key := "owned_cities:%d" % nation_id
	if not evaluation_cache.has(cache_key):
		_build_nation_aggregates(state, evaluation_cache)
	return (
		evaluation_cache.get(
			cache_key,
			[] as Array[City]
		) as Array[City]
	)


static func _cached_administrative_members(
	state: GameState,
	center_city_id: int,
	evaluation_cache: Dictionary
) -> Array[int]:
	var cache_key := "administrative_members:%d:%d" % [
		state.administrative_region_revision,
		center_city_id,
	]
	if not evaluation_cache.has(cache_key):
		evaluation_cache[cache_key] = state.administrative_members(
			center_city_id
		)
	return evaluation_cache[cache_key] as Array[int]


static func _cached_wars_of(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> Array[int]:
	var cache_key := "wars:%d" % nation_id
	if not evaluation_cache.has(cache_key):
		evaluation_cache[cache_key] = state.wars_of(nation_id)
	return evaluation_cache[cache_key] as Array[int]


static func _cached_war_count(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> int:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var cache_key := "active_war_count:%d" % nation_id
	if not evaluation_cache.has(cache_key):
		evaluation_cache[cache_key] = state.active_war_count(nation_id)
	return int(evaluation_cache[cache_key])


static func _cached_alliance_bloc(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> Array[int]:
	if bool(evaluation_cache.get(
		"__disable_structure_cache", false
	)):
		return state.alliance_bloc(nation_id)
	var cache_key := "alliance_bloc:%d:%d:%d" % [nation_id, state.ownership_revision, state.diplomacy_revision]
	if not evaluation_cache.has(cache_key):
		# 单国集团无需构造全局冲突感知并查集。大规模和平开局中这是
		# 绝大多数情况；allies 列表本轮已缓存，结果与 alliance_bloc 一致。
		if _cached_allies_of(
			state, nation_id, evaluation_cache
		).is_empty():
			evaluation_cache[cache_key] = [nation_id] as Array[int]
			return evaluation_cache[cache_key] as Array[int]
		var bloc := state.alliance_bloc(nation_id)
		for member_id in bloc:
			evaluation_cache[
				"alliance_bloc:%d:%d:%d" % [member_id, state.ownership_revision, state.diplomacy_revision]
			] = bloc
	return evaluation_cache.get(
		cache_key,
		[] as Array[int]
	) as Array[int]


static func _cached_allies_of(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> Array[int]:
	var cache_key := "allies:%d:%d:%d" % [nation_id, state.ownership_revision, state.diplomacy_revision]
	if not evaluation_cache.has(cache_key):
		evaluation_cache[cache_key] = state.allies_of(nation_id)
	return evaluation_cache[cache_key] as Array[int]


static func _food_stock(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var holder_id := state.food_pool_holder(nation_id)
	var cache_key := "food_stock:%d" % holder_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	# 藩王已无独立粮仓（粮食归共享粮仓）；读其宗藩体系粮池持有者的库存作为可用粮。
	var total := 0
	for warehouse in state.warehouse_cities_of(holder_id):
		total += warehouse.food_storage
	evaluation_cache[cache_key] = total
	return total


static func _target_cut_ratio(
	state: GameState,
	target_city: int,
	target_nation: int
) -> float:
	return float(
		_target_encirclement_effect(
			state,
			target_city,
			target_nation
		)["cut_city_ratio"]
	)


static func encirclement_value(
	state: GameState,
	target_city: int,
	target_nation: int,
	evaluation_cache: Dictionary = {}
) -> float:
	if (
		state == null
		or target_nation < 0
		or target_nation >= state.nations.size()
		or target_city < 0
		or target_city >= state.cities.size()
	):
		return 0.0
	if encirclement_index_enabled:
		var cache_key := "__encirclement_index:%d" % target_nation
		var index: EncirclementIndex = evaluation_cache.get(cache_key)
		if index == null:
			index = EncirclementIndex.new(state, target_nation)
			evaluation_cache[cache_key] = index
			_encirclement_index_builds += 1
		if index.has_cached(target_city):
			_encirclement_cache_hits += 1
		else:
			_encirclement_cache_misses += 1
		return index.value_for(target_city)
	_encirclement_legacy_evaluations += 1
	var effect := _target_encirclement_effect(
		state,
		target_city,
		target_nation
	)
	return (
		float(effect["cut_city_ratio"]) * 6.0
		+ float(effect["cut_troop_ratio"]) * 8.0
		+ _isolated_garrison_power_ratio(
			state,
			target_city,
			target_nation
		) * 8.0
	)


static func _target_encirclement_effect(
	state: GameState,
	target_city: int,
	target_nation: int
) -> Dictionary:
	var capital := state.nations[target_nation].capital_city_id
	if capital < 0 or capital == target_city:
		return {
			"cut_city_ratio": 0.0,
			"cut_troop_ratio": 0.0,
		}
	var reachable := {capital: true}
	var queue: Array[int] = [capital]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor in state.neighbors(current):
			if neighbor == target_city or reachable.has(neighbor):
				continue
			var edge := state.edge_of(current, neighbor)
			if (
				edge == null
				or edge.max_manpower <= 0
				or not state.has_military_access(
					target_nation,
					state.cities[neighbor].owner_nation
				)
			):
				continue
			reachable[neighbor] = true
			queue.append(neighbor)
	var total := 0
	var cut := 0
	for city in state.cities:
		if city.owner_nation != target_nation or city.id == target_city:
			continue
		total += 1
		if not reachable.has(city.id):
			cut += 1
	var total_power := 0.0
	var cut_power := 0.0
	for army in state.armies:
		if army.owner_nation != target_nation or army.size <= 0:
			continue
		var power := ArmyPower.effective(army)
		total_power += power
		var node_city := army.current_city_node()
		if (
			node_city >= 0
			and node_city != target_city
			and not reachable.has(node_city)
		):
			cut_power += power
	return {
		"cut_city_ratio": (
			float(cut) / float(maxi(total, 1))
		),
		"cut_troop_ratio": (
			cut_power / maxf(total_power, 1.0)
		),
	}


static func _isolated_garrison_power_ratio(
	state: GameState,
	city_id: int,
	nation_id: int
) -> float:
	var total_power := 0.0
	var isolated_power := 0.0
	var retreat_route_by_capacity := {}
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		var power := ArmyPower.effective(army)
		total_power += power
		if army.current_city_node() != city_id:
			continue
		var required_manpower := maxi(army.max_size, 1)
		if not retreat_route_by_capacity.has(
			required_manpower
		):
			retreat_route_by_capacity[required_manpower] = (
				Pathfinding.has_friendly_retreat_route_from_city(
					state,
					nation_id,
					city_id,
					required_manpower
				)
			)
		if not bool(
			retreat_route_by_capacity[required_manpower]
		):
			isolated_power += power
	return isolated_power / maxf(total_power, 1.0)


static func _coalition_power(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var cache_key := "coalition:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var power := _national_power(
		state,
		nation_id,
		evaluation_cache
	)
	for ally_id in _cached_allies_of(
		state,
		nation_id,
		evaluation_cache
	):
		power += _national_power(
			state,
			ally_id,
			evaluation_cache
		) * 0.75
	evaluation_cache[cache_key] = power
	return power


static func _common_enemy_count(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "common_enemy:%d:%d" % [
		mini(nation_a, nation_b),
		maxi(nation_a, nation_b),
	]
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var count := 0
	for other in state.nations:
		if (
			other.id != nation_a
			and other.id != nation_b
			and other.alive
			and state.is_enemy(nation_a, other.id)
			and state.is_enemy(nation_b, other.id)
		):
			count += 1
	evaluation_cache[cache_key] = count
	return count


static func _alliance_has_active_conflict(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	var cache_key := "alliance_conflict:%d:%d" % [
		mini(nation_a, nation_b),
		maxi(nation_a, nation_b),
	]
	if evaluation_cache.has(cache_key):
		return bool(evaluation_cache[cache_key])
	for enemy_id in _cached_wars_of(
		state,
		nation_a,
		evaluation_cache
	):
		if state.is_allied(nation_b, enemy_id):
			evaluation_cache[cache_key] = true
			return true
	for enemy_id in _cached_wars_of(
		state,
		nation_b,
		evaluation_cache
	):
		if state.is_allied(nation_a, enemy_id):
			evaluation_cache[cache_key] = true
			return true
	evaluation_cache[cache_key] = false
	return false


static func _has_shared_ally(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	var cache_key := "shared_ally:%d:%d" % [
		mini(nation_a, nation_b),
		maxi(nation_a, nation_b),
	]
	if evaluation_cache.has(cache_key):
		return bool(evaluation_cache[cache_key])
	for other in state.nations:
		if (
			other.id != nation_a
			and other.id != nation_b
			and state.is_allied(nation_a, other.id)
			and state.is_allied(nation_b, other.id)
		):
			evaluation_cache[cache_key] = true
			return true
	evaluation_cache[cache_key] = false
	return false


static func _frontier_edges(
	state: GameState,
	nation_a: int,
	nation_b: int,
	evaluation_cache: Dictionary = {}
) -> int:
	# 首次调用时一次遍历边表填满全部国家对的接壤边数矩阵（O(E)），后续查表 O(1)。
	# 原实现每对国家都全表扫描（每次 O(E)），同一 AI tick 内被数千次冷调用，
	# 是外交/威胁场的头号开销。矩阵按 observer*N+target 索引，语义保持为：
	# pair(a,b) = 一端归 b、另一端可被 a 军事通行（a 本国或其盟友）的边数。
	var topology_cache := _ensure_frontier_matrix_cache(
		state, evaluation_cache
	)
	var nation_count := state.nations.size()
	var matrix: PackedInt32Array = topology_cache.get(
		"frontier_matrix", PackedInt32Array()
	)
	if (
		nation_a < 0 or nation_a >= nation_count
		or nation_b < 0 or nation_b >= nation_count
		or matrix.size() != nation_count * nation_count
	):
		return 0
	return int(matrix[nation_a * nation_count + nation_b])


static func _ensure_frontier_matrix_cache(
	state: GameState, evaluation_cache: Dictionary
) -> Dictionary:
	var topology_cache := _diplomacy_topology_cache_store(
		evaluation_cache
	)
	var revision: Array[int] = [
		state.get_instance_id(),
		state.ownership_revision,
		state.diplomacy_revision,
		state.road_network_revision,
		state.cities.size(),
		state.nations.size(),
		state.edges.size(),
	]
	var matrix_value: Variant = topology_cache.get(
		"frontier_matrix", null
	)
	if (
		topology_cache.get("frontier_matrix_revision", []) != revision
		or not matrix_value is PackedInt32Array
		or (matrix_value as PackedInt32Array).size()
			!= state.nations.size() * state.nations.size()
	):
		_build_frontier_matrix(state, topology_cache)
		topology_cache["frontier_matrix_revision"] = revision
	return topology_cache


static func _build_frontier_matrix(
	state: GameState,
	evaluation_cache: Dictionary
) -> void:
	evaluation_cache["frontier_matrix_built"] = true
	var nation_count := state.nations.size()
	var matrix := PackedInt32Array()
	matrix.resize(nation_count * nation_count)
	matrix.fill(0)
	var territory_neighbor_sets: Array[Dictionary] = []
	territory_neighbor_sets.resize(nation_count)
	for nation_id in range(nation_count):
		territory_neighbor_sets[nation_id] = {}
	# 预计算每国的「可通行观察者」集合：本国 + 其盟友（结盟上限低，规模极小）。
	var accessors_of: Array[Array] = []
	accessors_of.resize(nation_count)
	for nation in state.nations:
		accessors_of[nation.id] = [nation.id] as Array[int]
	# 一次扫描无序国家对建立双向军事通行。不能用 allies_of()，因为它会
	# 过滤死国，而 has_military_access() 的历史查询语义不要求观察国存活。
	for nation_a in range(nation_count):
		for nation_b in range(nation_a + 1, nation_count):
			if not state.is_allied(nation_a, nation_b):
				continue
			accessors_of[nation_a].append(nation_b)
			accessors_of[nation_b].append(nation_a)
	for contact in state.territorial_border_pairs():
		var owner_a := state.cities[contact.x].owner_nation
		var owner_b := state.cities[contact.y].owner_nation
		if (
			owner_a < 0 or owner_a >= nation_count
			or owner_b < 0 or owner_b >= nation_count
		):
			continue
		if owner_a != owner_b:
			territory_neighbor_sets[owner_a][owner_b] = true
			territory_neighbor_sets[owner_b][owner_a] = true
		if owner_a == owner_b:
			for x in accessors_of[owner_a]:
				_bump_frontier(matrix, nation_count, int(x), owner_a)
			continue
		# 跨主边：(观察者 X 可通行 owner_a) → 目标 owner_b 贡献 +1，反向亦然。
		for x in accessors_of[owner_a]:
			_bump_frontier(matrix, nation_count, int(x), owner_b)
		for x in accessors_of[owner_b]:
			_bump_frontier(matrix, nation_count, int(x), owner_a)
	var neighbors_by_observer: Array[Array] = []
	neighbors_by_observer.resize(nation_count)
	var neighbors_by_owner: Array[Array] = []
	neighbors_by_owner.resize(nation_count)
	for observer in range(nation_count):
		var filtered: Array[int] = []
		for target in range(nation_count):
			if (
				target != observer
				and matrix[observer * nation_count + target] > 0
				and not state.has_military_access(observer, target)
			):
				filtered.append(target)
		neighbors_by_observer[observer] = filtered
		var direct: Array[int] = []
		for target_value in territory_neighbor_sets[observer]:
			var target := int(target_value)
			if not state.has_military_access(observer, target):
				direct.append(target)
		direct.sort_custom(func(a: int, b: int) -> bool:
			return EquivariantOrder.nation_less(state, observer, a, b)
		)
		neighbors_by_owner[observer] = direct
	_ensure_diplomatic_range_cache(
		state, _diplomacy_topology_cache_store(evaluation_cache),
		territory_neighbor_sets
	)
	evaluation_cache["frontier_matrix"] = matrix
	evaluation_cache["frontier_neighbors_by_observer"] = (
		neighbors_by_observer
	)
	evaluation_cache["territorial_neighbors_by_owner"] = neighbors_by_owner
	evaluation_cache["territorial_neighbor_sets"] = territory_neighbor_sets


static func _bump_frontier(
	matrix: PackedInt32Array,
	nation_count: int,
	observer: int,
	target: int
) -> void:
	if (
		observer < 0 or observer >= nation_count
		or target < 0 or target >= nation_count
	):
		return
	var index := observer * nation_count + target
	matrix[index] += 1


# ------------------------------------------------------------------ 分封（藩王系统 B3）
# 分封只评估财政与治理收益，地方野战军不随封地转移。

## 纯派生评估：一片区域的产出与分封财政反事实。
static func evaluate_region_burden(
	state: GameState,
	nation_id: int,
	city_ids: Array[int],
	capital_hops: Dictionary = {}
) -> Dictionary:
	var region := {}
	for city_id in city_ids:
		region[city_id] = true
	var monthly_food_output := 0.0
	var required_defense_troops := 0
	var garrison_troops := 0
	var garrison_gold_upkeep := 0
	var monthly_food_demand := 0
	var distance_food_demand := 0
	var direct_gold_income := 0
	var projected_vassal_gold_income := 0
	var manpower_output := 0
	for city_id in city_ids:
		if city_id < 0 or city_id >= state.cities.size():
			continue
		var city := state.cities[city_id]
		# 半年粮产折算为月产（与经济结算口径一致，DAYS_PER_HALF_YEAR 一次入库）。
		monthly_food_output += float(city.food_per_half_year) / 6.0
		var city_gold := Simulation.city_gold_output(
			state,
			city
		)
		direct_gold_income += city_gold
		projected_vassal_gold_income += int(floor(
			float(city_gold)
			* Simulation
				.VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER
		))
		manpower_output += city.manpower_per_month
		if state.is_zhou_city(city_id):
			var required := state.city_garrison_capacity(city_id)
			var cost := Simulation.city_garrison_cost_report(
				state, nation_id, city_id, required, capital_hops
			)
			required_defense_troops += required
			garrison_troops += maxi(city.garrison_manpower, 0)
			garrison_gold_upkeep += int(cost["gold_upkeep"])
			monthly_food_demand += int(cost["food_demand"])
			distance_food_demand += int(cost["distance_food_demand"])
	var burden_ratio := (
		float(distance_food_demand) / monthly_food_output
		if monthly_food_output > 0.0
		else (INF if distance_food_demand > 0 else 0.0)
	)
	var projected_tribute_income := int(floor(
		float(projected_vassal_gold_income)
		* GameState.DEFAULT_TRIBUTE_RATE
	))
	var monthly_fiscal_benefit := (
		garrison_gold_upkeep + projected_tribute_income
		- direct_gold_income
	)
	return {
		"city_ids": city_ids,
		"monthly_food_output": monthly_food_output,
		"monthly_food_demand": monthly_food_demand,
		"required_defense_troops": required_defense_troops,
		"garrison_troops": garrison_troops,
		"garrison_gold_upkeep": garrison_gold_upkeep,
		"gold_output": direct_gold_income,
		"manpower_output": manpower_output,
		"burden_ratio": burden_ratio,
		"distance_food_demand": distance_food_demand,
		"direct_gold_income": direct_gold_income,
		"projected_vassal_gold_income":
			projected_vassal_gold_income,
		"projected_tribute_income":
			projected_tribute_income,
		"monthly_fiscal_benefit":
			monthly_fiscal_benefit,
	}


## 纯派生评估：候选封区里有多少城市已超出宗主行政半径且目标忠诚低于软稳定线。
## 这描述的是“中央继续直辖的治理摩擦”，而非军事前线或财政收益。
static func evaluate_region_governance_pressure(
	state: GameState,
	nation_id: int,
	city_ids: Array[int],
	capital_hops: Dictionary = {}
) -> Dictionary:
	var report := {
		"city_ids": city_ids.duplicate(),
		"administrative_radius": 0.0,
		"soft_threshold": RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD,
		"pressured_city_count": 0,
		"pressured_excess": 0.0,
		"pressure_score": 0.0,
		"city_reports": [] as Array[Dictionary],
	}
	if (
		state == null
		or nation_id < 0
		or nation_id >= state.nations.size()
		or not state.nations[nation_id].alive
	):
		return report
	var hops := capital_hops
	if hops.is_empty():
		hops = RebellionSystem.capital_hops(state, nation_id)
	var admin_radius := RebellionSystem.administrative_radius(
		state.nations[nation_id]
	)
	report["administrative_radius"] = admin_radius
	for city_id in city_ids:
		if city_id < 0 or city_id >= state.cities.size():
			continue
		var city := state.cities[city_id]
		if city.owner_nation != nation_id or city.is_dock:
			continue
		var target := RebellionSystem.loyalty_target(
			state,
			city_id,
			hops
		)
		var hop_count := int(target.get("hop_count", -1))
		var target_value := float(target.get("value", RebellionSystem.LOYALTY_MIN))
		var distance_excess := float(target.get(
			"distance_excess",
			RebellionSystem.administrative_distance_excess(
				hop_count,
				admin_radius
			)
		))
		var pressure_component := (
			distance_excess
			+ maxf(
				RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD
					- target_value,
				0.0
			) / RebellionSystem.DISTANCE_PENALTY_PER_HOP
		)
		var pressured := (
			distance_excess > 0.0
			and target_value < RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD
		)
		if pressured:
			report["pressured_city_count"] = int(report["pressured_city_count"]) + 1
			report["pressured_excess"] = float(report["pressured_excess"]) + distance_excess
			report["pressure_score"] = (
				float(report["pressure_score"])
				+ pressure_component
			)
		(report["city_reports"] as Array[Dictionary]).append({
			"city_id": city_id,
			"hop_count": hop_count,
			"target_loyalty": target_value,
			"distance_excess": distance_excess,
			"pressure_component": pressure_component,
			"pressured": pressured,
		})
	return report


## 从最远的边疆城为种子，沿道路连续地生长一片候选封地（确定性 BFS）。
## 只纳入本国陆城、不含首都、避免超过上限。返回 city_ids（可能为空）。
static func _grow_enfeoff_region(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {},
	max_region_cities: int = ENFEOFF_MAX_REGION_CITIES,
	require_foreign_frontier: bool = true
) -> Array[int]:
	var nation := state.nations[nation_id]
	var capital := nation.capital_city_id
	if capital < 0:
		return [] as Array[int]
	var hops := _capital_hops_cached(
		state,
		nation_id,
		evaluation_cache
	)
	# 「远」相对本国疆域半径：取本国最大跳数的一定比例为外围门槛。
	var max_hop := 0
	for city in state.land_cities_of(nation_id):
		max_hop = maxi(max_hop, int(hops.get(city.id, -1)))
	var min_hops := maxi(1, int(ceil(float(max_hop) * ENFEOFF_FAR_HOP_FRACTION)))
	# 种子：本国非首都陆城中，距首都跳数最大且接敌（边疆）的城。
	var seed := -1
	var seed_hops := -1
	for city in state.land_cities_of(nation_id):
		if city.is_capital or city.id == capital:
			continue
		var h := int(hops.get(city.id, -1))
		if h < min_hops:
			continue
		if (
			require_foreign_frontier
			and not _city_is_frontier(state, nation_id, city.id)
		):
			continue
		if h > seed_hops or (
			h == seed_hops
			and EquivariantOrder.city_id_less(state, nation_id, city.id, seed)
		):
			seed_hops = h
			seed = city.id
	if seed < 0:
		return [] as Array[int]
	# 从种子沿道路向「更靠近首都的方向不优先」生长：优先纳入跳数同样较大的邻城，
	# 保证封地是一片连续的外围区域，且不轻易切断宗主核心。
	var region: Array[int] = [seed]
	var in_region := {seed: true}
	var frontier_queue: Array[int] = [seed]
	while (
		not frontier_queue.is_empty()
		and region.size() < max_region_cities
	):
		# 在当前边界里选跳数最大的城扩张（确定性打破平局），偏向外围。
		var best_idx := 0
		for i in range(1, frontier_queue.size()):
			var a := frontier_queue[i]
			var b := frontier_queue[best_idx]
			var ha := int(hops.get(a, -1))
			var hb := int(hops.get(b, -1))
			if ha > hb or (
				ha == hb
				and EquivariantOrder.city_id_less(state, nation_id, a, b)
			):
				best_idx = i
		var current: int = frontier_queue[best_idx]
		frontier_queue.remove_at(best_idx)
		var neighbor_ids := state.neighbors(current)
		var sorted_neighbors: Array[int] = neighbor_ids.duplicate()
		sorted_neighbors.sort()
		for neighbor in sorted_neighbors:
			if region.size() >= max_region_cities:
				break
			if in_region.has(neighbor):
				continue
			var ncity := state.cities[neighbor]
			# 只纳入本国、非首都、非码头、且离首都够远的城，保持外围连续。
			if (
				ncity.owner_nation != nation_id
				or ncity.is_capital
				or ncity.is_dock
				or int(hops.get(neighbor, -1)) < min_hops
			):
				continue
			var edge := state.edge_of(current, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			in_region[neighbor] = true
			region.append(neighbor)
			frontier_queue.append(neighbor)
	region.sort()
	# Convert the city-growth candidate to complete administrative states.  A
	# partial state is never emitted as a vassal action.
	var complete_states := state.expand_enfeoff_to_administrative_states(
		nation_id,
		region
	)
	if complete_states.is_empty() or complete_states.size() > max_region_cities:
		return [] as Array[int]
	return state.normalize_enfeoff_region(nation_id, complete_states)


## 统一的下一封区规划入口。普通分封与复合分封动作均从当前真实领土状态
## 重新规划，确保前一次分封改变道路拓扑后不会沿用过期候选。
static func next_enfeoff_region(
	state: GameState,
	nation_id: int,
	target_direct_cities: int,
	max_region_cities: int = ENFEOFF_MAX_REGION_CITIES,
	require_foreign_frontier: bool = true,
	evaluation_cache: Dictionary = {}
) -> Array[int]:
	if (
		state == null
		or nation_id < 0
		or nation_id >= state.nations.size()
		or not state.nations[nation_id].alive
		or target_direct_cities < 1
		or max_region_cities < 1
	):
		return [] as Array[int]
	var max_grant := (
		state.land_cities_of(nation_id).size() - target_direct_cities
	)
	if max_grant <= 0:
		return [] as Array[int]
	var region := _grow_enfeoff_region(
		state,
		nation_id,
		evaluation_cache,
		mini(max_region_cities, max_grant),
		require_foreign_frontier
	)
	if region.is_empty():
		# After a peace settlement the frontier seed may be split across states.
		# Fall back to a complete non-capital state so enfeoffment does not become
		# permanently disabled just because no city-growth seed is eligible.
		var centers: Array[int] = []
		for center_value in state.administrative_center_city_ids:
			centers.append(int(center_value))
		EquivariantOrder.sort_city_ids(centers, state, nation_id)
		for center_id in centers:
			if state.cities[center_id].is_capital:
				continue
			var candidate := state.normalize_enfeoff_region(
				nation_id,
				[center_id]
			)
			if (
				not candidate.is_empty()
				and candidate.size() <= mini(max_region_cities, max_grant)
			):
				region = candidate
				break
	if enfeoff_land_city_count(state, region) > max_grant:
		return [] as Array[int]
	return region


static func enfeoff_land_city_count(
	state: GameState,
	city_ids: Array[int]
) -> int:
	var count := 0
	for city_id in city_ids:
		if (
			city_id >= 0
			and city_id < state.cities.size()
			and not state.cities[city_id].is_dock
		):
			count += 1
	return count


static func puppet_capital_state_city_ids(
	state: GameState,
	nation_id: int
) -> Array[int]:
	if (
		state == null
		or nation_id < 0
		or nation_id >= state.nations.size()
	):
		return [] as Array[int]
	var capital_id := state.nations[nation_id].capital_city_id
	var center_id := state.administrative_center_of(capital_id)
	if center_id < 0:
		return [] as Array[int]
	return state.administrative_members(center_id)

## 该城是否为本国边疆城：至少有一条正容量边通往非本国可通行的城。
static func _city_is_frontier(
	state: GameState,
	nation_id: int,
	city_id: int
) -> bool:
	for neighbor in state.territorial_border_neighbors(city_id):
		var neighbor_owner := state.cities[neighbor].owner_nation
		if neighbor_owner >= 0 and not state.has_military_access(nation_id, neighbor_owner):
			return true
	return false


## 中央是否正在承受严重外战压力。欠饷不在此否决：分封可能正是卸下
## 偏远守军成本、恢复财政的政治手段。
static func _overlord_under_war_pressure(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	for enemy_id in state.wars_of(nation_id):
		if _frontier_edges(state, nation_id, enemy_id, evaluation_cache) > 0:
			return true
	return false


## 生成分封候选动作：
##   非藩王、分封后留足核心，且满足以下任一长期收益：
##   1. 倾向加权的守军军费减负 + 预计贡赋 - 失去直辖收入 > 0；
##   2. 超行政半径的守军附加粮耗 / 本地产粮超过负担阈值；
##   3. 远地治理压力超过阈值。
## 有真实外战前线或既有备战承诺时不分封；欠饷本身不否决减负重组。
static func _collect_enfeoff_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary
) -> void:
	for nation in state.nations:
		if not nation.alive:
			continue
		var overlord_id := nation.id
		if PrincePolitics.enfeoff_candidate(state, overlord_id, false) < 0:
			continue
		var puppet_rule := nation.ruler_archetype == RulerProfile.PUPPET
		# 藩王不得再分封（第一版不做多级自动分封）；已在本 tick 有动作的国家跳过。
		if (
			state.is_vassal(overlord_id)
			or committed.has(overlord_id)
			or nation.war_preparation_target_nation >= 0
		):
			continue
		# 只有和平时期才分封：战时把前线连同弱藩王一起甩出去反而会导致边疆崩溃，
		# 且与削藩「宗主须和平」对称——分封与削藩都是和平期的政治重组，逻辑自洽。
		if _overlord_under_war_pressure(
			state, overlord_id, evaluation_cache
		):
			continue
		var owned_city_count := state.land_cities_of(overlord_id).size()
		var puppet_core: Array[int] = []
		if puppet_rule:
			puppet_core = puppet_capital_state_city_ids(
				state, overlord_id
			)
		var puppet_core_complete := not puppet_core.is_empty()
		for city_id in puppet_core:
			if (
				state.cities[city_id].owner_nation != overlord_id
				or state.recognized_owner_of(city_id) != overlord_id
			):
				puppet_core_complete = false
				break
		if puppet_rule and not puppet_core_complete:
			continue
		var minimum_core := (
			puppet_core.size()
			if puppet_rule else ENFEOFF_MIN_OVERLORD_CITIES_AFTER
		)
		var max_grant := owned_city_count - minimum_core
		var max_region_cities := (
			owned_city_count
			if puppet_rule else ENFEOFF_MAX_REGION_CITIES
		)
		var region := next_enfeoff_region(
			state,
			overlord_id,
			minimum_core,
			max_region_cities,
			not puppet_rule,
			evaluation_cache
		)
		var region_land_cities := enfeoff_land_city_count(state, region)
		# Administrative states are already the minimum political unit; a
		# one-city state is valid and must not be rejected as a府-only fief.
		var minimum_region := 1
		if region_land_cities < minimum_region or region_land_cities > max_grant:
			continue
		# 分封后宗主必须保留足够核心领土。
		if (
			owned_city_count - region_land_cities < minimum_core
		):
			continue
		var hops := _capital_hops_cached(
			state,
			overlord_id,
			evaluation_cache
		)
		var burden := evaluate_region_burden(
			state, overlord_id, region, hops
		)
		var governance := evaluate_region_governance_pressure(
			state,
			overlord_id,
			region,
			hops
		)
		var enfeoff_tendency := maxf(
			RulerProfile.enfeoff_multiplier(nation), 0.0
		)
		var perceived_garrison_relief := int(round(
			float(burden["garrison_gold_upkeep"]) * enfeoff_tendency
		))
		var fiscal_benefit := (
			perceived_garrison_relief
			+ int(burden["projected_tribute_income"])
			- int(burden["direct_gold_income"])
		)
		var effective_food_burden := (
			float(burden["burden_ratio"]) * enfeoff_tendency
		)
		var governance_city_count := int(
			governance["pressured_city_count"]
		)
		var governance_pressure_score := float(governance["pressure_score"])
		var effective_governance_pressure := (
			governance_pressure_score * enfeoff_tendency
		)
		var food_burden_justifies := (
			effective_food_burden >= ENFEOFF_FOOD_BURDEN_RATIO_THRESHOLD
		)
		var governance_justifies := (
			governance_city_count >= 1
			and effective_governance_pressure
				>= ENFEOFF_GOVERNANCE_PRESSURE_THRESHOLD
		)
		if (
			fiscal_benefit <= 0
			and not food_burden_justifies
			and not governance_justifies
			and not puppet_rule
		):
			continue
		var motive_parts: Array[String] = []
		if puppet_rule:
			motive_parts.append(
				"傀儡君主主动缩减直辖，仅保留首都所在州%d城"
				% minimum_core
			)
		if governance_justifies:
			motive_parts.append(
				"治理压力：偏远州%d城超行政半径（半径%.1f，倾向后压力%.2f）"
				% [
					governance_city_count,
					float(governance["administrative_radius"]),
					effective_governance_pressure,
				]
			)
		if food_burden_justifies:
			motive_parts.append(
				"远地守军附加粮耗%d/月（负担比%.2f，倾向后%.2f）"
				% [
					int(burden["distance_food_demand"]),
					float(burden["burden_ratio"]),
					effective_food_burden,
				]
			)
		if fiscal_benefit > 0:
			motive_parts.append(
				"财政月增益%+d（倾向后守军减负%d+贡赋%d-直辖%d）"
				% [
					fiscal_benefit,
					perceived_garrison_relief,
					int(burden["projected_tribute_income"]),
					int(burden["direct_gold_income"]),
				]
			)
		var motive := (
			"、".join(motive_parts)
			if not motive_parts.is_empty()
			else (
			"财政月增益%+d（倾向后守军减负%d+贡赋%d-直辖%d）"
			% [
				fiscal_benefit,
				perceived_garrison_relief,
				int(burden["projected_tribute_income"]),
				int(burden["direct_gold_income"]),
			]
			if fiscal_benefit > 0
			else "治理压力触发"
			)
		)
		var enfeoff_action := {
			"kind": Action.ENFEOFF,
			"a": overlord_id,
			"b": overlord_id,
			"region_cities": region,
			"governance_pressure": governance,
			"enfeoff_tendency": enfeoff_tendency,
			"effective_food_burden": effective_food_burden,
			"perceived_fiscal_benefit": fiscal_benefit,
			"score": (
				maxf(float(fiscal_benefit), 0.0)
				+ maxf(
					effective_food_burden
						- ENFEOFF_FOOD_BURDEN_RATIO_THRESHOLD,
					0.0
				) * 100.0
				+ effective_governance_pressure
					* ENFEOFF_GOVERNANCE_SCORE_WEIGHT
			),
			"reason": "和平期偏远地区%s，分封以转移守军与治理负担" % motive,
		}
		if puppet_rule:
			enfeoff_action[ENFEOFF_TARGET_DIRECT_CITIES_FIELD] = minimum_core
			enfeoff_action[ENFEOFF_MAX_REGION_CITIES_FIELD] = (
				max_region_cities
			)
			enfeoff_action[ENFEOFF_FOREIGN_FRONTIER_FIELD] = false
		actions.append(enfeoff_action)
		committed[overlord_id] = true


# ------------------------------------------------------------------ 削藩（藩王系统 C2）
# 宗主在和平期、撤藩财政收益为正或藩王已成高威胁且冷却已过时发起削藩。
# 是否反抗统一委托 RebellionSystem，以忠诚、持续时间、冷却和军力共同决定。
# 执行仍由 Simulation 完成；本层只产出候选动作并预判藩王反应，附在动作里供展示。

## 宗主当前可用于镇压内战的军力：总军力扣除被其它实战线占用的兵力。
## 第一版：宗主削藩本就要求和平（无实战前线），故可镇压 ≈ 全部军力。
## 仍按「扣除与非宗藩敌国交战占用」派生，为将来宗主多线状态保留正确性。
static func _suppression_power(
	state: GameState,
	overlord_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	# 与任何非本宗藩体系的敌国交战时，占用的前线兵力不计入可镇压力。
	# 和平时该集合为空，可镇压力 = 全部军力。
	var tied_up := 0.0
	for enemy_id in state.wars_of(overlord_id):
		if state.suzerainty_root(enemy_id) == state.suzerainty_root(overlord_id):
			continue  # 宗藩体系内部（如正在进行的其它内战）不在此扣除
		tied_up += _national_power(state, enemy_id, evaluation_cache)
	return maxf(_national_power(state, overlord_id, evaluation_cache) - tied_up, 1.0)


## 藩王反抗比 = 藩王军力 / 宗主可镇压军力。越高越敢反抗。
static func vassal_resist_ratio(
	state: GameState,
	subject_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	var overlord_id := state.overlord_of(subject_id)
	if overlord_id < 0:
		return 0.0
	var subject_power := _national_power(state, subject_id, evaluation_cache)
	var suppression := _suppression_power(state, overlord_id, evaluation_cache)
	return subject_power / maxf(suppression, 1.0)


## 撤藩对宗主的月度财政反事实。藩王城市恢复直辖后失去 1.5 倍治理加成；其军队
## 全部并入中央。藩王原有的下级藩属会转投宗主，故其贡赋继续计入撤藩后收入。
static func evaluate_centralization_fiscal_benefit(
	state: GameState,
	subject_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	_ensure_evaluation_cache_current(state, evaluation_cache)
	var overlord_id := state.overlord_of(subject_id)
	if (
		overlord_id < 0
		or subject_id < 0
		or subject_id >= state.nations.size()
	):
		return {
			"projected_direct_income": 0,
			"inherited_subordinate_tribute": 0,
			"lost_subject_tribute": 0,
			"inherited_military_upkeep": 0,
			"monthly_fiscal_benefit": 0,
		}
	const GOLD_FLOWS_CACHE_KEY := "monthly_gold_flows"
	if not evaluation_cache.has(GOLD_FLOWS_CACHE_KEY):
		evaluation_cache[GOLD_FLOWS_CACHE_KEY] = (
			Simulation.monthly_gold_flows(state)
		)
	var gold_flows: Array[Dictionary] = (
		evaluation_cache[GOLD_FLOWS_CACHE_KEY]
	)
	var subject_flow: Dictionary = gold_flows[subject_id]
	var projected_direct_income := 0
	for city in state.cities_of(subject_id):
		projected_direct_income += (
			Simulation.city_gold_output_before_governance(
				state,
				city
			)
		)
	var inherited_subordinate_tribute := int(
		subject_flow["tribute_received"]
	)
	var lost_subject_tribute := int(
		subject_flow["tribute_paid"]
	)
	var inherited_military_upkeep := int(
		subject_flow["military_upkeep"]
	)
	return {
		"projected_direct_income": projected_direct_income,
		"inherited_subordinate_tribute":
			inherited_subordinate_tribute,
		"lost_subject_tribute": lost_subject_tribute,
		"inherited_military_upkeep":
			inherited_military_upkeep,
		"monthly_fiscal_benefit": (
			projected_direct_income
			+ inherited_subordinate_tribute
			- lost_subject_tribute
			- inherited_military_upkeep
		),
	}


## 生成削藩候选动作。规则（文档 17、18 节）：
##   宗主非藩王、处于和平、冷却已过、当前无内战，且撤藩财政收益为正 → 削藩。
##   财政不划算时，仅高政治威胁比可例外触发；军力比不再作为宗主优势硬门槛。
## 暴君无视财政/威胁收益门槛，但仍须满足和平、藩王年龄与削藩冷却。
## 动作附带预判：resist=true 表示藩王将反抗（执行时开内战），否则和平撤藩。
static func _collect_centralization_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary
) -> void:
	for nation in state.nations:
		if not nation.alive:
			continue
		var overlord_id := nation.id
		if state.is_vassal(overlord_id) or committed.has(overlord_id) or not VassalConflict.for_nation(state, overlord_id).is_empty():
			continue
		# 傀儡君主的核心效果是持续分封；任内不会反向削藩。
		if nation.ruler_archetype == RulerProfile.PUPPET:
			continue
		# 削藩须和平：与分封同样要求中央无实战压力（攘外必先安内的对称）。
		if _overlord_under_war_pressure(state, overlord_id, evaluation_cache):
			continue
		for subject_id in state.subjects_of(overlord_id):
			if committed.has(subject_id) or state.is_in_civil_war(subject_id):
				continue
			# 分封保护期：刚分封的藩王在稳定期内不得削藩，消除「封了又撤」的反复横跳。
			var created_day := int(
				state.suzerainty_record(subject_id).get("created_day", -1)
			)
			if created_day >= 0 and state.day - created_day < CENTRALIZE_MIN_VASSAL_AGE_DAYS:
				continue
			# 冷却：距上次对该藩王削藩不足冷却期则跳过。
			var last_day := int(
				state.suzerainty_record(subject_id).get("last_centralization_day", -1)
			)
			if last_day >= 0 and state.day - last_day < CENTRALIZE_COOLDOWN_DAYS:
				continue
			var fiscal := (
				evaluate_centralization_fiscal_benefit(
					state,
					subject_id,
					evaluation_cache
				)
			)
			var subject_power := _national_power(state, subject_id, evaluation_cache)
			var suppression := _suppression_power(state, overlord_id, evaluation_cache)
			var resist_ratio := subject_power / maxf(suppression, 1.0)
			var fiscal_benefit := int(
				fiscal["monthly_fiscal_benefit"]
			)
			var political_threat := (
				resist_ratio
					* RulerProfile.centralize_multiplier(nation)
				>= CENTRALIZE_POLITICAL_THREAT_RATIO_THRESHOLD
			)
			var tyrant_centralization := (
				nation.ruler_archetype == RulerProfile.TYRANT
			)
			if (
				fiscal_benefit <= 0
				and not political_threat
				and not tyrant_centralization
			):
				continue
			var will_resist := (
				RebellionSystem.must_resist_centralization(state, subject_id)
				or RebellionSystem.should_vassal_rebel(state, subject_id)
			)
			var motive := (
				"撤藩月增益%+d（直辖%d+下级贡赋%d-原贡赋%d-接军费%d）"
				% [
					fiscal_benefit,
					int(fiscal["projected_direct_income"]),
					int(fiscal["inherited_subordinate_tribute"]),
					int(fiscal["lost_subject_tribute"]),
					int(fiscal["inherited_military_upkeep"]),
				]
				if fiscal_benefit > 0
				else (
					"暴君强令收归直辖"
					if tyrant_centralization
					else "政治威胁比%.2f达到高危阈值"
						% resist_ratio
				)
			)
			actions.append({
				"kind": Action.CENTRALIZE,
				"a": overlord_id,
				"b": subject_id,
				"resist": will_resist,
				"resist_ratio": resist_ratio,
				"monthly_fiscal_benefit":
					fiscal_benefit,
				"reason": (
					"和平期对藩王%d削藩：%s；反抗比%.2f，%s"
					% [
						subject_id,
						motive,
						resist_ratio,
						"藩王将反抗，转削藩内战" if will_resist else "藩王接受，和平撤藩直辖",
					]
				),
			})
			committed[overlord_id] = true
			committed[subject_id] = true
			break  # 一个宗主每 tick 最多对一个藩王削藩
