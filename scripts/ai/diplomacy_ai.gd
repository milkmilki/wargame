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
}

enum FoodPosture {
	PEACE,
	GUARDED,
	OFFENSIVE_WAR,
	DEFENSIVE_WAR,
}

const MIN_WAR_DAYS: int = 180
const WAR_FATIGUE_REFERENCE_DAYS: int = 360
const MIN_NEUTRAL_DAYS: int = 90
const MIN_ALLIANCE_DAYS: int = 360
## 单国同时主动开战上限。诊断显示宣战「意愿分」恒在阈值 3× 以上，长和平期的
## 真因是该上限=1：一旦入战，其余所有战线被硬门槛拦死。放开到 3 以支持多线
## 饱和进攻的乱世感；经济/粮食仍逐国把关，统一时代只连续退火储备量，不移除底线。
const MAX_CONCURRENT_WARS: int = 3
const MAX_DEFENSIVE_ALLIES: int = 1
const PEACE_PROPOSE_SCORE: float = 1.25
const PEACE_ACCEPT_SCORE: float = 0.60
const PEACE_SITUATION_WEIGHT: float = 0.40
const PEACE_POWER_BALANCE_WEIGHT: float = 1.20
const PEACE_RESOURCE_ENDURANCE_WEIGHT: float = 1.00
const PEACE_EXTERNAL_THREAT_WEIGHT: float = 1.50
const PEACE_RESOURCE_REFERENCE_MONTHS: float = 24.0
const PEACE_MAX_BORDER_MASSING_RATIO: float = 1.50
const ALLIANCE_ACCEPT_SCORE: float = 1.00
const WAR_DECLARE_SCORE: float = 0.85
const OBSERVED_WAR_PREPARATION_THREAT_BONUS: float = 0.75
const PEACE_ESCALATION_START_DAYS: int = 180
const PEACE_ESCALATION_FULL_DAYS: int = 540
const PEACE_ESCALATION_MAX_BONUS: float = 0.75
const RECENT_CAPTURE_OBJECTIVE_BONUS: float = 4.0
const RECENT_RECLAMATION_OBJECTIVE_BONUS: float = 20.0
const LEAVE_ALLIANCE_SCORE: float = 0.90
const ATTITUDE_PEACE_WEIGHT: float = 0.25
const ATTITUDE_ALLIANCE_WEIGHT: float = 0.35
const ATTITUDE_WAR_WEIGHT: float = 0.35
const ATTITUDE_LEAVE_WEIGHT: float = 0.50
const REVENGE_PER_LOST_SITUATION_POINT: float = 0.10
const REVENGE_SURRENDER_PENALTY: float = 0.85
const REVENGE_ATTITUDE_FLOOR: float = -1.25
const BORDER_ATTITUDE_PER_EDGE: float = 0.08
const BORDER_ATTITUDE_FLOOR: float = -0.48
const OBJECTIVE_ATTITUDE_PER_VALUE: float = 0.035
const OBJECTIVE_ATTITUDE_FLOOR: float = -0.55
const COMMON_ENEMY_ATTITUDE: float = 0.60
const ENEMY_ALLY_ATTITUDE: float = -0.90
const UNIFICATION_COMPLETION_WEIGHT: float = 1.35
const UNIFICATION_RIVAL_SCARCITY_WEIGHT: float = 0.45
# 统一时代时钟：40 国均势被“互保联盟 + 盟友参战 + 战争疲劳议和”三重负反馈焊成
# 稳态，实验证明零星调数值无法收敛到统一。引入随游戏年份单调爬升的全局压力，
# 前 ONSET 年保持 0（保留自然外交演化），到 FULL 年满值，作为打破均势的总闸。
const UNIFICATION_ERA_ONSET_YEARS: int = 10
const UNIFICATION_ERA_FULL_YEARS: int = 40
const UNIFICATION_ERA_WEIGHT: float = 1.5
const TOTAL_WAR_MIN_PAYMENT_RATIO: float = 0.50
const TOTAL_WAR_GOLD_RUNWAY_MONTHS: float = 0.0
const TOTAL_WAR_FOOD_RUNWAY_YEARS: float = 0.25
const TOTAL_WAR_MANPOWER_SHARE: float = 0.0
const CAMPAIGN_RESERVE_MONTHS: int = 6
const FOOD_PER_CAPITA_MONTH: float = 0.0025
const MIN_GOLD_RESERVE: int = 200
const MIN_MANPOWER_RESERVE: int = 5000
const MAX_MOBILIZATION_ARMIES: int = 4
const MOBILIZATION_ARMY_SIZE: int = 5000
const MONTHS_PER_YEAR: int = 12
const PEACE_STOCK_TARGET_YEARS: float = 1.5
const PEACE_STOCK_RECOVERY_YEARS: float = 3.0
const GUARDED_CAMPAIGN_YEARS: float = 2.0
const OFFENSIVE_CAMPAIGN_YEARS: float = 2.0
const DEFENSIVE_CAMPAIGN_YEARS: float = 1.0
const EMERGENCY_FOOD_MONTHS: int = 6
const DEFAULT_CAMPAIGN_SUPPLY_MULTIPLIER: float = 1.5
const MAX_REPORTED_RUNWAY_YEARS: float = 99.0
const WAR_PREPARATION_MIN_DAYS: int = 30
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
## 核心是「区域所需 LINE 军粮耗 / 区域粮产」的负担比，只在和平期分封。
const ENFEOFF_MIN_REGION_CITIES: int = 3       ## 候选封地最少城市数，避免碎封
const ENFEOFF_MAX_REGION_CITIES: int = 8       ## 主动生长上限；被切断飞地闭包可超过
const ENFEOFF_BURDEN_RATIO_THRESHOLD: float = 0.60  ## 区域驻军粮耗/粮产超此值算「养不起」
## 「远」是相对该国疆域半径的，而非绝对跳数：距首都跳数 ≥ 本国最大跳数 × 此比例
## 才算外围（避免把绝对阈值套到小疆域国家上、导致永远找不到边疆种子）。
const ENFEOFF_FAR_HOP_FRACTION: float = 0.5
const ENFEOFF_MIN_OVERLORD_CITIES_AFTER: int = 6    ## 分封后宗主至少保留的陆城数
const ENFEOFF_DECISION_COOLDOWN_DAYS: int = 360     ## 同一宗主两次分封的最短间隔

## 削藩（藩王系统增量 C）调参。宗主和平期+军力优势才削藩；藩王按反抗比决定接受/反抗。
const CENTRALIZE_MIN_POWER_ADVANTAGE: float = 1.5   ## 宗主军力须为藩王的此倍以上才考虑削藩
const CENTRALIZE_COOLDOWN_DAYS: int = 1825          ## 一次削藩后约5年内不再对同一藩王削藩
## 分封保护期：藩王被分封后至少存续这么多天才可被削藩。防止「分封→立即撤回」反复横跳
## （分封 created_day 与削藩 last_centralization_day 是两套字段，缺此门控时新藩王当即满足削藩）。
## 拉长到约 4 年：一次分封的政治重组需长期稳定，杜绝"封了又撤"的高频横跳。
const CENTRALIZE_MIN_VASSAL_AGE_DAYS: int = 1440
## 反抗比 = 藩王军力 / 宗主可镇压军力；超此阈值藩王倾向反抗（内战），否则接受(和平撤藩)。
## 文档第18节：和平0.45。第一版宗主削藩本就要求和平，故用单一阈值。
const CENTRALIZE_RESIST_RATIO_THRESHOLD: float = 0.45


static func choose_actions(
	state: GameState,
	profile: Dictionary = {}
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var committed := {}
	var evaluation_cache := {}
	var profile_enabled := bool(profile.get("enabled", false))
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
	_collect_war_actions(
		state,
		actions,
		committed,
		evaluation_cache
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


static func _record_profile_stage(
	profile: Dictionary,
	stage: String,
	started_usec: int,
	enabled: bool
) -> void:
	if enabled:
		profile[stage] = Time.get_ticks_usec() - started_usec


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
		_distinct_enemy_coalition_count(state, nation_id) - 1,
		0
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
	var resource_report := resource_report(
		state,
		nation_id,
		evaluation_cache
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
	var aggression := clampf(
		state.nations[nation_id].ai_aggression,
		0.5,
		1.5
	)
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
	var attitude_component := attitude * ATTITUDE_PEACE_WEIGHT
	var score := (
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
	var result := {
		"score": score,
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
	var bloc_a := state.alliance_bloc(nation_a)
	var bloc_b := state.alliance_bloc(nation_b)
	var breakdown_a := _coalition_peace_breakdown(
		state,
		bloc_a,
		bloc_b,
		evaluation_cache
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
	var consent_a := score_a >= PEACE_ACCEPT_SCORE
	var consent_b := score_b >= PEACE_ACCEPT_SCORE
	return {
		"acceptable": (
			war_days >= MIN_WAR_DAYS
			and proposal_score >= PEACE_PROPOSE_SCORE
			and consent_a
			and consent_b
		),
		"consent_a": consent_a,
		"consent_b": consent_b,
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
			own_bloc
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
	nation_id: int
) -> int:
	return _distinct_enemy_coalition_count_for_bloc(
		state,
		state.alliance_bloc(nation_id)
	)


static func _distinct_enemy_coalition_count_for_bloc(
	state: GameState,
	own_bloc: Array[int]
) -> int:
	var enemy_blocs := {}
	for member_id in own_bloc:
		for enemy_id in state.wars_of(member_id):
			enemy_blocs[
				_nation_list_key(state.alliance_bloc(enemy_id))
			] = true
	return enemy_blocs.size()


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
	for city in state.cities:
		var legal_owner := state.recognized_owner_of(city.id)
		if legal_owner not in [nation_id, enemy_id]:
			continue
		var city_value := _military_city_value(city)
		bilateral_value += city_value
		var occupying_side := _occupation_side(
			state,
			city,
			nation_id,
			enemy_id
		)
		if occupying_side < 0 or occupying_side == legal_owner:
			continue
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
	var historical := _historical_attitude(
		state,
		nation_id,
		other_id,
		evaluation_cache
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
	var political := (
		float(common_enemies) * COMMON_ENEMY_ATTITUDE
		+ frontier_relief
		+ float(enemy_allies) * ENEMY_ALLY_ATTITUDE
	)
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


## 所有国家都以统一全图为终局目标。两国控制的地图份额越高、存活对手越少，
## 彼此作为最终竞争者的压力越大；该连续值同时抑制结盟并推动退盟和宣战。
static func unification_rivalry(
	state: GameState,
	nation_id: int,
	other_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
	if (
		nation_id == other_id
		or nation_id < 0
		or other_id < 0
		or nation_id >= state.nations.size()
		or other_id >= state.nations.size()
		or not state.nations[nation_id].alive
		or not state.nations[other_id].alive
	):
		return 0.0
	var cache_key := "unification:%d:%d" % [
		mini(nation_id, other_id),
		maxi(nation_id, other_id),
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	var controlled := 0
	for city in state.cities:
		if city.owner_nation in [nation_id, other_id]:
			controlled += 1
	var pair_share := (
		float(controlled) / float(maxi(state.cities.size(), 1))
	)
	var completion := clampf(
		(pair_share - 0.50) / 0.50,
		0.0,
		1.0
	)
	var alive_count := 0
	for nation in state.nations:
		if nation.alive:
			alive_count += 1
	var rival_scarcity := (
		1.0 / float(maxi(alive_count - 1, 1))
	)
	var result := (
		completion * UNIFICATION_COMPLETION_WEIGHT
		+ rival_scarcity * UNIFICATION_RIVAL_SCARCITY_WEIGHT
		+ unification_era_factor(state) * UNIFICATION_ERA_WEIGHT
	)
	evaluation_cache[cache_key] = result
	return result


## 统一时代时钟：只依赖 state.day，对所有国家一致。前 ONSET 年为 0（保留自然
## 外交演化期），随后线性爬升到 FULL 年的 1.0。作为 unification_rivalry 的时代分量，
## 同时推高宣战、抑制结盟、推动退盟——一个时钟拆掉“互保联盟”这把僵局主锁。
static func unification_era_factor(state: GameState) -> float:
	var years := float(state.day) / 365.0
	return clampf(
		(years - float(UNIFICATION_ERA_ONSET_YEARS))
		/ float(maxi(
			UNIFICATION_ERA_FULL_YEARS - UNIFICATION_ERA_ONSET_YEARS,
			1
		)),
		0.0,
		1.0
	)


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
		+ 0.50 * clampf(
			float(city.fort_strength_max) / 30.0,
			0.0,
			1.0
		)
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
	var cache_key := "alliance:%d:%d" % [
		nation_id,
		target_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	if state.relation_between(nation_id, target_id) != GameState.DiplomaticRelation.NEUTRAL:
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
	var common_enemies := _common_enemy_count(
		state,
		nation_id,
		target_id,
		evaluation_cache
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
	var border_bonus := (
		0.25
		if _frontier_edges(
			state,
			nation_id,
			target_id,
			evaluation_cache
		) > 0
		else 0.0
	)
	var shared_threat := _shared_threat(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	var balance_affinity := maxf(1.0 - imbalance, 0.0) * 0.55
	var frontier_release := _alliance_frontier_release_value(
		state,
		nation_id,
		target_id,
		evaluation_cache
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
	var result := (
		0.35
		+ float(common_enemies) * 1.5
		+ minf(shared_threat * 0.35, 0.80)
		+ border_bonus
		+ balance_affinity
		+ frontier_release
		+ attitude * ATTITUDE_ALLIANCE_WEIGHT
		- unification_pressure
	)
	evaluation_cache[cache_key] = result
	return result


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
	var cache_key := "war_desire:%d:%d" % [
		nation_id,
		target_id,
	]
	if evaluation_cache.has(cache_key):
		return float(evaluation_cache[cache_key])
	if (
		not state.can_alliance_declare_war(nation_id, target_id)
		or _cached_wars_of(
			state,
			nation_id,
			evaluation_cache
		).size() >= MAX_CONCURRENT_WARS
		or _frontier_edges(
			state,
			nation_id,
			target_id,
			evaluation_cache
		) <= 0
		or _has_shared_ally(
			state,
			nation_id,
			target_id,
			evaluation_cache
		)
	):
		evaluation_cache[cache_key] = -INF
		return -INF
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
		evaluation_cache[cache_key] = -INF
		return -INF
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
		evaluation_cache[cache_key] = -INF
		return -INF
	var objective := _cached_war_objective(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	if objective.is_empty():
		evaluation_cache[cache_key] = -INF
		return -INF
	# 共同防御联盟不参加成员主动发动的战争；进攻方只能计算本国战力。
	var own_power := _national_power(
		state,
		nation_id,
		evaluation_cache
	)
	var target_power := _coalition_power(
		state,
		target_id,
		evaluation_cache
	)
	var ratio := own_power / maxf(target_power, 1.0)
	var target_distraction := float(_cached_wars_of(
		state,
		target_id,
		evaluation_cache
	).size()) * 0.25
	var own_overextension := float(_cached_wars_of(
		state,
		nation_id,
		evaluation_cache
	).size()) * 0.75
	var border_value := minf(
		float(
			_frontier_edges(
				state,
				nation_id,
				target_id,
				evaluation_cache
			)
		) * 0.10,
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
	var result := (
		ratio
		+ target_distraction
		+ border_value
		+ reserve_quality
		+ objective_value
		+ mobilization_value
		+ aggression_bonus
		- attitude * ATTITUDE_WAR_WEIGHT
		+ unification_pressure
		+ peace_escalation
		- own_overextension
	)
	evaluation_cache[cache_key] = result
	return result


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
	return clampf(
		state.nations[nation_id].ai_aggression,
		0.5,
		1.5
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
	if _frontier_edges(
		state,
		nation_id,
		target_id,
		evaluation_cache
	) <= 0:
		evaluation_cache[cache_key] = 0.0
		return 0.0
	var frontier_cities := {}
	for edge in state.edges:
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a == nation_id and owner_b == target_id:
			frontier_cities[edge.city_a] = true
		elif owner_b == nation_id and owner_a == target_id:
			frontier_cities[edge.city_b] = true
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
	var border_power := 0.0
	for other in state.nations:
		if (
			not other.alive
			or other.id in [observer_id, current_enemy_id]
			or state.is_allied(observer_id, other.id)
			or state.is_enemy(observer_id, other.id)
		):
			continue
		var other_frontier_cities := {}
		for edge in state.edges:
			if edge.max_manpower <= 0:
				continue
			var owner_a := state.cities[edge.city_a].owner_nation
			var owner_b := state.cities[edge.city_b].owner_nation
			if owner_a == observer_id and owner_b == other.id:
				other_frontier_cities[edge.city_b] = true
			elif owner_b == observer_id and owner_a == other.id:
				other_frontier_cities[edge.city_a] = true
		if other_frontier_cities.is_empty():
			continue
		for army in state.armies:
			if army.owner_nation != other.id or army.size <= 0:
				continue
			var massed := (
				army.location_city >= 0
				and other_frontier_cities.has(army.location_city)
			)
			if (
				not massed
				and army.on_edge
				and army.move_to >= 0
			):
				massed = (
					other_frontier_cities.has(army.move_from)
					or other_frontier_cities.has(army.move_to)
				)
			if massed:
				border_power += ArmyPower.effective(army)
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
	return result


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
	var cache_key := "resource:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var nation := state.nations[nation_id]
	var troops := _troop_count(
		state,
		nation_id,
		evaluation_cache
	)
	var monthly_income := 0
	for city in _cached_cities_of(
		state,
		nation_id,
		evaluation_cache
	):
		monthly_income += Simulation.city_gold_output(
			state,
			city
		)
	var food_plan := war_food_report(
		state,
		nation_id,
		troops,
		-1,
		evaluation_cache
	)
	var monthly_food_production := float(food_plan["monthly_food_production"])
	var monthly_war_cost := (
		state.nation_monthly_military_upkeep(nation_id)
	)
	var monthly_gold_balance := monthly_income - monthly_war_cost
	var monthly_gold_deficit := maxi(-monthly_gold_balance, 0)
	var monthly_food_demand := int(ceil(
		float(food_plan["current_monthly_demand"])
	))
	var gold_required := (
		maxi(
			monthly_gold_deficit * CAMPAIGN_RESERVE_MONTHS,
			MIN_GOLD_RESERVE
		)
		if monthly_gold_deficit > 0
		else 0
	)
	var food_required := maxi(
		monthly_food_demand * CAMPAIGN_RESERVE_MONTHS,
		1
	)
	var manpower_required := maxi(
		MIN_MANPOWER_RESERVE,
		int(ceil(float(troops) * 0.15))
	)
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
		"monthly_gold_income": monthly_income,
		"monthly_war_cost": monthly_war_cost,
		"monthly_gold_balance": monthly_gold_balance,
		"gold_runway_months": gold_runway_months,
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
		"ready": (
			nation.unpaid_military_upkeep <= 0
			and (
				monthly_gold_balance >= 0
				or gold_runway_months >= CAMPAIGN_RESERVE_MONTHS
			)
			and manpower_ratio >= 1.0
			and (
				float(food_plan["current_annual_balance"]) >= 0.0
				or float(food_plan["current_runway_years"])
					>= DEFENSIVE_CAMPAIGN_YEARS
			)
		),
	}
	evaluation_cache[cache_key] = result
	return result


## 宣战资源门槛随统一时代连续退火。era=0 时严格等价于 resource_report.ready；
## era=1 时保留总体战生存底线，避免大战后的所有国家因和平期储备规则永久停战。
static func offensive_resources_ready(
	state: GameState,
	nation_id: int,
	report: Dictionary
) -> bool:
	var nation := state.nations[nation_id]
	var era := unification_era_factor(state)
	var required_payment := lerpf(
		1.0,
		TOTAL_WAR_MIN_PAYMENT_RATIO,
		era
	)
	var gold_runway := lerpf(
		float(CAMPAIGN_RESERVE_MONTHS),
		TOTAL_WAR_GOLD_RUNWAY_MONTHS,
		era
	)
	var manpower_share := lerpf(
		0.15,
		TOTAL_WAR_MANPOWER_SHARE,
		era
	)
	var manpower_floor := int(round(lerpf(
		float(MIN_MANPOWER_RESERVE),
		float(MIN_MANPOWER_RESERVE) / 5.0,
		era
	)))
	var required_manpower := maxi(
		manpower_floor,
		int(ceil(float(report["troops"]) * manpower_share))
	)
	var food_runway := lerpf(
		DEFENSIVE_CAMPAIGN_YEARS,
		TOTAL_WAR_FOOD_RUNWAY_YEARS,
		era
	)
	return (
		nation.military_payment_ratio >= required_payment
		and (
			int(report["monthly_gold_balance"]) >= 0
			or float(report["gold_runway_months"]) >= gold_runway
		)
		and nation.manpower_pool >= required_manpower
		and (
			float(report["annual_food_balance"]) >= 0.0
			or float(report["food_runway_years"]) >= food_runway
		)
	)


## 目标军力的粮食门槛使用与统一时代一致的动态战役窗口。原 report 中的
## monthly_food_budget 固定按 2 年摊销库存，因此在此按动态窗口重算可支配月预算。
static func offensive_food_sustainable(
	state: GameState,
	food_plan: Dictionary
) -> bool:
	var required_years := lerpf(
		OFFENSIVE_CAMPAIGN_YEARS,
		TOTAL_WAR_FOOD_RUNWAY_YEARS,
		unification_era_factor(state)
	)
	var expendable_stock := maxf(
		float(food_plan["food_stock"])
			- float(food_plan["emergency_food_reserve"]),
		0.0
	)
	var monthly_budget := (
		float(food_plan["monthly_food_production"])
		+ expendable_stock
			/ maxf(required_years * float(MONTHS_PER_YEAR), 1.0)
	)
	return (
		float(food_plan["target_monthly_demand"]) <= monthly_budget + 0.01
		and (
			float(food_plan["target_annual_balance"]) >= 0.0
			or float(food_plan["target_runway_years"]) >= required_years
		)
	)


## 开始备战要求完整战略储备；备战中的动员本身会消耗这部分人力，因此继续
## 可行性改用生存线，避免“按计划动员 -> 储备下降 -> 自动取消”的自相矛盾。
static func war_preparation_resources_ready(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	var nation := state.nations[nation_id]
	var report := resource_report(state, nation_id, evaluation_cache)
	var emergency_manpower := maxi(
		MIN_MANPOWER_RESERVE / 5,
		int(ceil(float(report["troops"]) * TOTAL_WAR_MANPOWER_SHARE))
	)
	var era := unification_era_factor(state)
	return (
		nation.military_payment_ratio >= lerpf(
			1.0,
			TOTAL_WAR_MIN_PAYMENT_RATIO,
			era
		)
		and (
			int(report["monthly_gold_balance"]) >= 0
			or float(report["gold_runway_months"])
				>= lerpf(
					float(CAMPAIGN_RESERVE_MONTHS),
					TOTAL_WAR_GOLD_RUNWAY_MONTHS,
					era
				)
		)
		and nation.manpower_pool >= emergency_manpower
		and (
			float(report["annual_food_balance"]) >= 0.0
			or float(report["food_runway_years"])
				>= lerpf(
					DEFENSIVE_CAMPAIGN_YEARS,
					TOTAL_WAR_FOOD_RUNWAY_YEARS,
					era
				)
		)
	)


static func mobilization_capacity(
	state: GameState,
	nation_id: int,
	posture: int = FoodPosture.OFFENSIVE_WAR,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "mobilization:%d:%d" % [
		nation_id,
		posture,
	]
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var manpower_units := int(floor(
		float(maxi(
			state.nations[nation_id].manpower_pool - MIN_MANPOWER_RESERVE,
			0
		)) / float(MOBILIZATION_ARMY_SIZE)
	))
	var formation_gold_cost := (
		GameState.formation_creation_gold_cost(
			MOBILIZATION_ARMY_SIZE
		)
	)
	var protected_gold := (
		0
		if posture in [
			FoodPosture.OFFENSIVE_WAR,
			FoodPosture.DEFENSIVE_WAR,
		]
		else MIN_GOLD_RESERVE
	)
	var gold_units := int(floor(
		float(maxi(
			state.nations[nation_id].treasury_gold
				- protected_gold,
			0
		)) / float(maxi(formation_gold_cost, 1))
	))
	var max_units := clampi(
		mini(manpower_units, gold_units),
		0,
		MAX_MOBILIZATION_ARMIES
	)
	var current_troops := _troop_count(
		state,
		nation_id,
		evaluation_cache
	)
	var affordable_units := 0
	for units in range(1, max_units + 1):
		var target_troops := current_troops + units * MOBILIZATION_ARMY_SIZE
		var plan := war_food_report(
			state,
			nation_id,
			target_troops,
			posture,
			evaluation_cache
		)
		if not bool(plan["target_sustainable"]):
			break
		affordable_units = units
	evaluation_cache[cache_key] = affordable_units
	return affordable_units


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
	if not evaluation_cache.has("frontier_matrix_built"):
		_build_frontier_matrix(state, evaluation_cache)
	var result: Array[int] = []
	for other in state.nations:
		if (
			other.id != nation_id
			and not state.has_military_access(
				nation_id,
				other.id
			)
			and _frontier_edges(
				state,
				nation_id,
				other.id,
				evaluation_cache
			) > 0
		):
			result.append(other.id)
	evaluation_cache[cache_key] = result
	return result


static func war_food_report(
	state: GameState,
	nation_id: int,
	target_troops: int = -1,
	posture: int = -1,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
	var nation := state.nations[nation_id]
	var current_troops := _troop_count(
		state,
		nation_id,
		evaluation_cache
	)
	if target_troops < 0:
		target_troops = current_troops
	if posture < 0:
		posture = food_posture(
			state,
			nation_id,
			evaluation_cache
		)
	var cache_key := "food:%d:%d:%d" % [
		nation_id,
		target_troops,
		posture,
	]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var monthly_production := 0.0
	if not evaluation_cache.has("garrison_by_city"):
		evaluation_cache["garrison_by_city"] = Simulation.build_garrison_index(state)
	var garrison_by_city: Dictionary = evaluation_cache["garrison_by_city"]
	for city in _cached_cities_of(
		state,
		nation_id,
		evaluation_cache
	):
		monthly_production += (
			float(Simulation.city_food_output(state, city, garrison_by_city))
				/ 6.0
		)
	var current_monthly_demand := maxf(
		nation.food_demand_ema,
		float(current_troops)
			* FOOD_PER_CAPITA_MONTH
			* DEFAULT_CAMPAIGN_SUPPLY_MULTIPLIER
	)
	var food_per_troop := (
		current_monthly_demand / float(current_troops)
		if current_troops > 0
		else FOOD_PER_CAPITA_MONTH * DEFAULT_CAMPAIGN_SUPPLY_MULTIPLIER
	)
	var target_monthly_demand := float(target_troops) * food_per_troop
	var full_strength_troops := _full_strength_troop_count(
		state,
		nation_id,
		evaluation_cache
	)
	var full_strength_monthly_demand := (
		float(full_strength_troops) * food_per_troop
	)
	var annual_production := monthly_production * float(MONTHS_PER_YEAR)
	var current_annual_demand := current_monthly_demand * float(MONTHS_PER_YEAR)
	var target_annual_demand := target_monthly_demand * float(MONTHS_PER_YEAR)
	var full_strength_annual_demand := (
		full_strength_monthly_demand * float(MONTHS_PER_YEAR)
	)
	var stock := float(
		_food_stock(
			state,
			nation_id,
			evaluation_cache
		)
	)
	var current_annual_balance := annual_production - current_annual_demand
	var target_annual_balance := annual_production - target_annual_demand
	var full_strength_annual_balance := (
		annual_production - full_strength_annual_demand
	)
	var current_runway := _food_runway_years(stock, current_annual_balance)
	var target_runway := _food_runway_years(stock, target_annual_balance)
	var full_strength_runway := _food_runway_years(
		stock,
		full_strength_annual_balance
	)
	var required_years := _required_campaign_years(posture)
	var emergency_reserve := current_monthly_demand * float(
		EMERGENCY_FOOD_MONTHS
	)
	var monthly_budget := 0.0
	var stock_target := emergency_reserve
	if posture in [FoodPosture.PEACE, FoodPosture.GUARDED]:
		stock_target = target_annual_demand * PEACE_STOCK_TARGET_YEARS
		var monthly_recovery := maxf(
			stock_target - stock,
			0.0
		) / (PEACE_STOCK_RECOVERY_YEARS * float(MONTHS_PER_YEAR))
		monthly_budget = maxf(monthly_production - monthly_recovery, 0.0)
	else:
		var expendable_stock := maxf(stock - emergency_reserve, 0.0)
		monthly_budget = (
			monthly_production
			+ expendable_stock
				/ (required_years * float(MONTHS_PER_YEAR))
		)
	var affordable_troops := int(floor(
		monthly_budget / maxf(food_per_troop, 0.0001)
	))
	var result := {
		"posture": posture,
		"current_troops": current_troops,
		"target_troops": target_troops,
		"full_strength_troops": full_strength_troops,
		"monthly_food_production": monthly_production,
		"annual_food_production": annual_production,
		"food_stock": int(stock),
		"food_per_troop_month": food_per_troop,
		"current_monthly_demand": current_monthly_demand,
		"target_monthly_demand": target_monthly_demand,
		"full_strength_monthly_demand": full_strength_monthly_demand,
		"current_annual_demand": current_annual_demand,
		"target_annual_demand": target_annual_demand,
		"full_strength_annual_demand": full_strength_annual_demand,
		"current_annual_balance": current_annual_balance,
		"target_annual_balance": target_annual_balance,
		"full_strength_annual_balance": full_strength_annual_balance,
		"current_runway_years": current_runway,
		"target_runway_years": target_runway,
		"full_strength_runway_years": full_strength_runway,
		"required_campaign_years": required_years,
		"emergency_food_reserve": int(ceil(emergency_reserve)),
		"stock_target": int(ceil(stock_target)),
		"monthly_food_budget": monthly_budget,
		"affordable_troops": affordable_troops,
		"target_sustainable": (
			target_monthly_demand <= monthly_budget + 0.01
			and (
				target_annual_balance >= 0.0
				or target_runway >= required_years
			)
		),
	}
	evaluation_cache[cache_key] = result
	return result


static func _required_campaign_years(posture: int) -> float:
	match posture:
		FoodPosture.OFFENSIVE_WAR:
			return OFFENSIVE_CAMPAIGN_YEARS
		FoodPosture.DEFENSIVE_WAR:
			return DEFENSIVE_CAMPAIGN_YEARS
		FoodPosture.GUARDED:
			return GUARDED_CAMPAIGN_YEARS
		_:
			return PEACE_STOCK_RECOVERY_YEARS


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
		mini(available, current + MAX_MOBILIZATION_ARMIES * MOBILIZATION_ARMY_SIZE)
	)
	evaluation_cache[cache_key] = result
	return result


static func _cached_war_objective(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary
) -> Dictionary:
	var cache_key := "objective:%d:%d" % [
		nation_id,
		target_id,
	]
	if evaluation_cache.has(cache_key):
		return evaluation_cache[cache_key]
	var objective := select_war_objective(
		state,
		nation_id,
		target_id,
		evaluation_cache
	)
	evaluation_cache[cache_key] = objective
	return objective


static func select_war_objective(
	state: GameState,
	nation_id: int,
	target_id: int,
	evaluation_cache: Dictionary = {}
) -> Dictionary:
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
	var max_gold := 1
	var max_food := 1
	var max_manpower := 1
	var required_capacity := objective_staging_capacity()
	for city in target_cities:
		max_gold = maxi(max_gold, city.gold_per_month)
		max_food = maxi(max_food, city.food_per_half_year)
		max_manpower = maxi(max_manpower, city.manpower_per_month)
	var best: Dictionary = {}
	for city in target_cities:
		var own_links := 0
		for neighbor in state.neighbors(city.id):
			var edge := state.edge_of(city.id, neighbor)
			if (
				edge != null
				and edge.max_manpower
					>= required_capacity
				and state.has_military_access(
					nation_id, state.cities[neighbor].owner_nation
				)
			):
				own_links += 1
		if own_links == 0:
			continue
		var gold_value := 1.5 * float(city.gold_per_month) / float(max_gold)
		var food_value := 1.2 * float(city.food_per_half_year) / float(max_food)
		var manpower_value := 1.3 * float(city.manpower_per_month) / float(max_manpower)
		var strategic_value := (
			float(own_links) * 1.25
			+ (3.0 if city.is_capital else 0.0)
			+ (2.0 if city.has_warehouse else 0.0)
			+ (4.0 if city.is_food_hub else 0.0)
			+ (4.0 if city.is_manpower_hub else 0.0)
		)
		var encirclement_cache_key := (
			"encirclement:%d:%d" % [
				city.id,
				target_id,
			]
		)
		var encirclement_score := 0.0
		if evaluation_cache.has(encirclement_cache_key):
			encirclement_score = float(
				evaluation_cache[encirclement_cache_key]
			)
		else:
			encirclement_score = encirclement_value(
				state,
				city.id,
				target_id
			)
			evaluation_cache[encirclement_cache_key] = (
				encirclement_score
			)
		strategic_value += encirclement_score
		var fort_vulnerability := Simulation.city_fort_vulnerability(
			city,
			state.day
		)
		var legal_reclamation := (
			state.recognized_owner_of(city.id) == nation_id
		)
		var contest_value := fort_vulnerability * (
			RECENT_RECLAMATION_OBJECTIVE_BONUS
			if legal_reclamation
			else RECENT_CAPTURE_OBJECTIVE_BONUS
		)
		var value := (
			gold_value
			+ food_value
			+ manpower_value
			+ strategic_value
			+ contest_value
		)
		if (
			best.is_empty()
			or value > float(best["value"])
			or (
				is_equal_approx(value, float(best["value"]))
					and EquivariantOrder.city_id_less(
						state,
						nation_id,
						city.id,
						int(best["city_id"])
					)
			)
		):
			best = {
				"city_id": city.id,
				"value": value,
				"reason": (
					"城市%d%s（金%d/月、粮%d/半年、人%d/月、战略值%.2f、包围值%.2f、争夺值%.2f）"
					% [
						city.id,
						(
							"【粮食核心】" if city.is_food_hub else ""
						) + (
							"【人口核心】" if city.is_manpower_hub else ""
						) + (
							"【近期失地】"
							if legal_reclamation
								and fort_vulnerability > 0.0
							else (
								"【城防受损】"
								if fort_vulnerability > 0.0
								else ""
							)
						),
						city.gold_per_month,
						city.food_per_half_year,
						city.manpower_per_month,
						strategic_value,
						encirclement_score,
						contest_value,
					]
				),
			}
	return best


static func leave_alliance_desire(
	state: GameState,
	nation_id: int,
	ally_id: int,
	evaluation_cache: Dictionary = {}
) -> float:
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
			# 削藩内战不走普通议和：宗藩内战只能由明确政治结果（占首都通吃）终结。
			if state.is_suzerainty_pair(a, b) and (
				state.is_in_civil_war(a) or state.is_in_civil_war(b)
			):
				continue
			var bloc_a := state.alliance_bloc(a)
			var bloc_b := state.alliance_bloc(b)
			var war_key := _coalition_pair_key(bloc_a, bloc_b)
			if processed_wars.has(war_key):
				continue
			processed_wars[war_key] = true
			var war_days := _coalition_war_days(
				state,
				bloc_a,
				bloc_b
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
	bloc_b: Array[int]
) -> int:
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
	return state.day - started_day if found else 0


static func _commit_alliance_bloc(
	state: GameState,
	nation_id: int,
	committed: Dictionary
) -> void:
	for member_id in state.alliance_bloc(nation_id):
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
			# 宗主与藩王的 ALLIED 是宗藩政治义务，不可通过普通退盟解除
			# （解除只能来自明确政治事件，如独立战争）。跳过这类对。
			if state.is_suzerainty_pair(a, b):
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
			_commit_alliance_bloc(state, a, committed)
			_commit_alliance_bloc(state, b, committed)


static func _collect_alliance_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary
) -> void:
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if (
				committed.has(a)
				or committed.has(b)
				or not state.nations[a].alive
				or not state.nations[b].alive
				or state.relation_between(a, b)
					!= GameState.DiplomaticRelation.NEUTRAL
				or state.nations[a].war_preparation_target_nation >= 0
				or state.nations[b].war_preparation_target_nation >= 0
			):
				continue
			var score_a := alliance_willingness(
				state,
				a,
				b,
				evaluation_cache
			)
			var score_b := alliance_willingness(
				state,
				b,
				a,
				evaluation_cache
			)
			if score_a < ALLIANCE_ACCEPT_SCORE or score_b < ALLIANCE_ACCEPT_SCORE:
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
			_commit_alliance_bloc(state, a, committed)
			_commit_alliance_bloc(state, b, committed)


static func _collect_war_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary,
	evaluation_cache: Dictionary
) -> void:
	for nation in state.nations:
		if committed.has(nation.id) or not nation.alive:
			continue
		# 藩王不主动宣战：进攻性外交与开战决策统一由宗主代理（藩王作战体系简化）。
		# 藩王对外战争由宗主的联盟宣战自动带入（宗藩对外 ALLIED、共同体化）。
		if state.is_vassal(nation.id):
			continue
		if nation.war_preparation_target_nation >= 0:
			_collect_existing_war_preparation(
				state,
				nation.id,
				actions,
				committed,
				evaluation_cache
			)
			continue
		# 取消备战冷却：刚取消过备战的国家在冷却期内不得重新发起，打断终局横跳正反馈。
		if (
			nation.war_preparation_cancelled_day >= 0
			and state.day - nation.war_preparation_cancelled_day
				< WAR_PREPARATION_CANCEL_COOLDOWN_DAYS
		):
			continue
		if (
			_cached_wars_of(
				state,
				nation.id,
				evaluation_cache
			).size()
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
		):
			continue
		var best_target := -1
		var best_score := -INF
		for target_id in _bordering_nation_ids(
			state,
			nation.id,
			evaluation_cache
		):
			var target := state.nations[target_id]
			if committed.has(target.id) or not target.alive:
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
		if best_target == -1 or best_score < WAR_DECLARE_SCORE:
			continue
		var objective := _cached_war_objective(
			state,
			nation.id,
			best_target,
			evaluation_cache
		)
		var report := resource_report(
			state,
			nation.id,
			evaluation_cache
		)
		if (
			objective.is_empty()
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
			+ mobilization_armies * MOBILIZATION_ARMY_SIZE
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
			"objective_city": int(objective["city_id"]),
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
		_commit_alliance_bloc(state, nation.id, committed)
		_commit_alliance_bloc(state, best_target, committed)


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
	var valid := (
		target_id >= 0
		and target_id < state.nations.size()
		and state.nations[target_id].alive
		and state.can_alliance_declare_war(nation_id, target_id)
		and objective_city >= 0
		and objective_city < state.cities.size()
		and state.cities[objective_city].owner_nation == target_id
		and not staging_cities_for_objective(
			state,
			nation_id,
			objective_city
		).is_empty()
	)
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
		nation_id
	)
	var assembly_deadline_expired := (
		elapsed >= WAR_PREPARATION_MAX_DAYS
		and not preparation_ready
	)
	# 治本：集结超时但仍是合法目标、且已集结到「足够发起」的最低兵力时，改为尽力而战——
	# 用现有可用主战军团立即宣战，而不是无限空转/取消再重开。避免终局残编战团凑不齐
	# required_assault_troops 的完美门槛而永远打不出去（军队因此零移动）。
	var best_effort_launch := (
		valid
		and not resource_grace_expired
		and assembly_deadline_expired
		and staged_troops_for_objective(state, nation_id, objective_city)
			>= int(ceil(
				float(required_assault_troops(state, nation_id, objective_city))
				* WAR_PREPARATION_BEST_EFFORT_RATIO
			))
	)
	if (
		not best_effort_launch
		and (
			not valid
			or resource_grace_expired
			or assembly_deadline_expired
		)
	):
		actions.append({
			"kind": Action.CANCEL_WAR_PREPARATION,
			"a": nation_id,
			"b": target_id,
			"reason": (
				"目标失效、进攻道路中断、资源连续不足%d天或%d天内无法完成集结，取消对国%d的战争准备"
				% [
					WAR_PREPARATION_RESOURCE_GRACE_DAYS,
					WAR_PREPARATION_MAX_DAYS,
					target_id,
				]
			),
		})
		committed[nation_id] = true
		return
	if not resources_ready and not best_effort_launch:
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
	var mobilization_armies := maxi(
		int(ceil(
			float(
				nation.war_mobilization_target_troops
				- _troop_count(state, nation_id, evaluation_cache)
			) / float(MOBILIZATION_ARMY_SIZE)
		)),
		0
	)
	actions.append({
		"kind": Action.DECLARE_WAR,
		"a": nation_id,
		"b": target_id,
		"objective_city": objective_city,
		"objective_reason": nation.war_preparation_reason,
		"mobilization_armies": mobilization_armies,
		"reason": (
			"完成%d天战争准备，目标城市%d方向已集结%d人，立即宣战并发动攻势"
			% [
				elapsed,
				objective_city,
				staged_troops_for_objective(state, nation_id, objective_city),
			]
		),
	})
	_commit_alliance_bloc(state, nation_id, committed)
	_commit_alliance_bloc(state, target_id, committed)


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
	for candidate in state.nations:
		if (
			candidate.id in [nation_id, war_target_id]
			or not candidate.alive
			or committed.has(candidate.id)
			or state.is_allied(candidate.id, war_target_id)
		):
			continue
		var score_a := alliance_willingness(
			state,
			nation_id,
			candidate.id,
			evaluation_cache
		)
		var score_b := alliance_willingness(
			state,
			candidate.id,
			nation_id,
			evaluation_cache
		)
		var score := minf(score_a, score_b)
		if (
			score_a < ALLIANCE_ACCEPT_SCORE
			or score_b < ALLIANCE_ACCEPT_SCORE
		):
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
							candidate.id,
							best_target
						)
				)
			)
		):
			best_score = score
			best_target = candidate.id
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


static func war_preparation_ready(state: GameState, nation_id: int) -> bool:
	var nation := state.nations[nation_id]
	if (
		nation.war_preparation_target_nation < 0
		or nation.war_preparation_objective_city < 0
		or state.day - nation.war_preparation_started_day
			< WAR_PREPARATION_MIN_DAYS
	):
		return false
	if (
		state.uses_heightmap
		and nation.campaign_preparation_group_assignments.has(
			nation.war_preparation_objective_city
		)
	):
		var assigned_armies: Array[Army] = []
		for army in state.armies:
			if (
				army.owner_nation == nation_id
				and army.size > 0
				and int(
					nation.campaign_preparation_assignments.get(
						army.id,
						-1
					)
				) == nation.war_preparation_objective_city
			):
				assigned_armies.append(army)
		if assigned_armies.is_empty():
			return false
		var staging := staging_cities_for_objective(
			state,
			nation_id,
			nation.war_preparation_objective_city
		)
		for army in assigned_armies:
			var staged := (
				army.state in [
					Army.State.IDLE,
					Army.State.RECOVERING,
				]
				and staging.has(army.location_city)
			) or (
				army.state == Army.State.HOLDING
				and (
					(
						army.move_from
							== nation.war_preparation_objective_city
						and staging.has(army.move_to)
					)
					or (
						army.move_to
							== nation.war_preparation_objective_city
						and staging.has(army.move_from)
					)
				)
			)
			if not staged:
				return false
		return true
	return (
		staged_troops_for_objective(
			state,
			nation_id,
			nation.war_preparation_objective_city
		)
		>= required_assault_troops(
			state,
			nation_id,
			nation.war_preparation_objective_city
		)
	)


static func staging_cities_for_objective(
	state: GameState,
	nation_id: int,
	objective_city: int
) -> Array[int]:
	var result: Array[int] = []
	var required_capacity := objective_staging_capacity()
	for neighbor in state.neighbors(objective_city):
		var edge := state.edge_of(neighbor, objective_city)
		if (
			edge != null
			and edge.max_manpower
				>= required_capacity
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
	return result


static func objective_staging_capacity() -> int:
	return Edge.MIN_MANPOWER


static func staged_troops_for_objective(
	state: GameState,
	nation_id: int,
	objective_city: int
) -> int:
	var staging := staging_cities_for_objective(
		state, nation_id, objective_city
	)
	var total := 0
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		if (
			army.state in [Army.State.IDLE, Army.State.RECOVERING]
			and staging.has(army.location_city)
		):
			total += army.size
		elif (
			army.state == Army.State.HOLDING
			and (
				(army.move_from == objective_city and staging.has(army.move_to))
				or (army.move_to == objective_city and staging.has(army.move_from))
			)
		):
			total += army.size
	return total


static func required_assault_troops(
	state: GameState,
	nation_id: int,
	objective_city: int
) -> int:
	var objective_requirement := objective_assault_troops(
		state,
		nation_id,
		objective_city
	)
	if objective_requirement <= 0:
		return objective_requirement
	var recent_legal_reclamation := (
		state.recognized_owner_of(objective_city) == nation_id
		and Simulation.city_fort_vulnerability(
			state.cities[objective_city],
			state.day
		) > 0.0
	)
	if recent_legal_reclamation:
		return objective_requirement
	return maxi(
		objective_requirement,
		int(ceil(float(_troop_count(state, nation_id)) * WAR_PREPARATION_FORCE_SHARE))
	)


static func objective_assault_troops(
	state: GameState,
	nation_id: int,
	objective_city: int
) -> int:
	if objective_city < 0 or objective_city >= state.cities.size():
		return 0
	var defenders := 0
	for army in state.armies:
		if (
			army.size > 0
			and army.owner_nation != nation_id
			and army.location_city == objective_city
			and army.state in [Army.State.IDLE, Army.State.RECOVERING]
		):
			defenders += army.size
	# 攻城派兵门槛（item 6/7 唯一真源，与 UtilityAI 同源）：歼灭守军 + 维持封锁×余量。
	# 形成可接受的局部优势即发起，持久围城的连续推进曲线由战斗状态机承担（item 7：无 5× 硬门槛）。
	var fort_strength := state.cities[
		objective_city
	].fort_strength
	var recent_legal_reclamation := (
		state.recognized_owner_of(objective_city) == nation_id
		and Simulation.city_fort_vulnerability(
			state.cities[objective_city],
			state.day
		) > 0.0
	)
	if recent_legal_reclamation:
		# 近期失地在击败占领军后会直接完成法理收复，不需要再次破坏本国工事。
		fort_strength = 0
	var siege_requirement := UtilityAI.assault_commit_threshold(
		defenders,
		fort_strength
	)
	return siege_requirement


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
		(cities_by_nation[city.owner_nation] as Array[City]).append(
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


static func _cached_wars_of(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> Array[int]:
	var cache_key := "wars:%d" % nation_id
	if not evaluation_cache.has(cache_key):
		evaluation_cache[cache_key] = state.wars_of(nation_id)
	return evaluation_cache[cache_key] as Array[int]


static func _cached_allies_of(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary
) -> Array[int]:
	var cache_key := "allies:%d" % nation_id
	if not evaluation_cache.has(cache_key):
		evaluation_cache[cache_key] = state.allies_of(nation_id)
	return evaluation_cache[cache_key] as Array[int]


static func _food_stock(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "food_stock:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	# 藩王已无独立粮仓（粮食归共享粮仓）；读其宗藩体系粮池持有者的库存作为可用粮。
	var holder_id := state.food_pool_holder(nation_id)
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
	target_nation: int
) -> float:
	if (
		target_nation < 0
		or target_nation >= state.nations.size()
		or target_city < 0
		or target_city >= state.cities.size()
	):
		return 0.0
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
	# 是外交/威胁场的头号开销。矩阵键沿用 "frontier:a:b"，语义完全一致：
	# pair(a,b) = 一端归 b、另一端可被 a 军事通行（a 本国或其盟友）的边数。
	if not evaluation_cache.has("frontier_matrix_built"):
		_build_frontier_matrix(state, evaluation_cache)
	return int(evaluation_cache.get("frontier:%d:%d" % [nation_a, nation_b], 0))


static func _build_frontier_matrix(
	state: GameState,
	evaluation_cache: Dictionary
) -> void:
	evaluation_cache["frontier_matrix_built"] = true
	# 预计算每国的「可通行观察者」集合：本国 + 其盟友（结盟上限低，规模极小）。
	var accessors_of := {}
	for nation in state.nations:
		var accessors: Array[int] = [nation.id]
		for ally_id in state.allies_of(nation.id):
			if ally_id != nation.id:
				accessors.append(ally_id)
		accessors_of[nation.id] = accessors
	for edge in state.edges:
		if edge.max_manpower <= 0:
			continue
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a < 0 or owner_b < 0:
			continue
		if owner_a == owner_b:
			# 旧逻辑对同主边亦计入：pair(a, owner) 命中当 a 可通行 owner。
			# 保留该行为以维持字节等价（观察者含 owner 本身及其盟友）。
			for x in (accessors_of.get(owner_a, [owner_a]) as Array):
				_bump_frontier(evaluation_cache, int(x), owner_a)
			continue
		# 跨主边：(观察者 X 可通行 owner_a) → 目标 owner_b 贡献 +1，反向亦然。
		for x in (accessors_of.get(owner_a, [owner_a]) as Array):
			_bump_frontier(evaluation_cache, int(x), owner_b)
		for x in (accessors_of.get(owner_b, [owner_b]) as Array):
			_bump_frontier(evaluation_cache, int(x), owner_a)


static func _bump_frontier(
	evaluation_cache: Dictionary,
	observer: int,
	target: int
) -> void:
	var key := "frontier:%d:%d" % [observer, target]
	evaluation_cache[key] = int(evaluation_cache.get(key, 0)) + 1


# ------------------------------------------------------------------ 分封（藩王系统 B3）
# 判据源自设计文档第 4、6 节：分封的本质是「把养不起自己驻军的偏远边疆，
# 连同防务责任一起交给地方政权」。因此核心信号是区域负担比，
# 而非「国家太大」这类虚构的行政容量。执行仍由 GameState.enfeoff 完成，
# 本层只负责「统一规划」：评估并产出候选动作。

## 纯派生评估：一片区域对宗主的负担画像。无副作用。
## burden_ratio = 区域边疆线「所需」LINE 军的月粮耗 / 区域城市的等效月粮产。
## 关键：分子是「地理应然的防务需求」（接敌边满编所需驻军），而非「当前实际驻军」——
## 因为中央打仗时会把兵抽到主战场，偏远边疆的实际驻军往往极少，用实然驻军会让
## 负担比恒低、分封永不触发。文档第 4 节原文即「地块所需 line 军队的粮食损耗」。
## >阈值表示：这片边疆连守住自己所需的驻军都养不起，中央在长期倒贴其防务。
static func evaluate_region_burden(
	state: GameState,
	nation_id: int,
	city_ids: Array[int]
) -> Dictionary:
	var region := {}
	for city_id in city_ids:
		region[city_id] = true
	var monthly_food_output := 0.0
	var required_defense_troops := 0
	var garrison_troops := 0
	var gold_output := 0
	var manpower_output := 0
	for city_id in city_ids:
		if city_id < 0 or city_id >= state.cities.size():
			continue
		var city := state.cities[city_id]
		# 半年粮产折算为月产（与经济结算口径一致，DAYS_PER_HALF_YEAR 一次入库）。
		monthly_food_output += float(city.food_per_half_year) / 6.0
		gold_output += city.gold_per_month
		manpower_output += city.manpower_per_month
		# 该城通往「非本国可通行」邻城的每条正容量边，都是一段需长期驻守的边疆线；
		# 其 max_manpower 即守住这段边所需的满编 LINE 兵力（应然防务需求）。
		for neighbor in state.neighbors(city_id):
			var edge := state.edge_of(city_id, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			var neighbor_owner := state.cities[neighbor].owner_nation
			if neighbor_owner >= 0 and not state.has_military_access(nation_id, neighbor_owner):
				required_defense_troops += edge.max_manpower
	# 实然驻军仅供解释展示，不作判据。
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		var node := army.current_city_node()
		if node >= 0 and region.has(node):
			garrison_troops += army.size
	var monthly_food_demand := float(required_defense_troops) * Simulation.FOOD_PER_CAPITA
	var burden_ratio := (
		monthly_food_demand / monthly_food_output
		if monthly_food_output > 0.0
		else INF
	)
	return {
		"city_ids": city_ids,
		"monthly_food_output": monthly_food_output,
		"monthly_food_demand": monthly_food_demand,
		"required_defense_troops": required_defense_troops,
		"garrison_troops": garrison_troops,
		"gold_output": gold_output,
		"manpower_output": manpower_output,
		"burden_ratio": burden_ratio,
	}


## 从最远的边疆城为种子，沿道路连续地生长一片候选封地（确定性 BFS）。
## 只纳入本国陆城、不含首都、避免超过上限。返回 city_ids（可能为空）。
static func _grow_enfeoff_region(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> Array[int]:
	var nation := state.nations[nation_id]
	var capital := nation.capital_city_id
	if capital < 0:
		return [] as Array[int]
	var hops := _capital_hop_distances(state, nation_id)
	# 「远」相对本国疆域半径：取本国最大跳数的一定比例为外围门槛。
	var max_hop := 0
	for h_value in hops.values():
		max_hop = maxi(max_hop, int(h_value))
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
		if not _city_is_frontier(state, nation_id, city.id):
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
		and region.size() < ENFEOFF_MAX_REGION_CITIES
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
			if region.size() >= ENFEOFF_MAX_REGION_CITIES:
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
	return state.enfeoff_region_closure(
		nation_id,
		region
	)


## 各城到本国首都的道路跳数（确定性 BFS，只走本国可通行边）。缓存于 evaluation_cache。
static func _capital_hop_distances(
	state: GameState,
	nation_id: int
) -> Dictionary:
	var nation := state.nations[nation_id]
	var capital := nation.capital_city_id
	var dist := {}
	if capital < 0:
		return dist
	dist[capital] = 0
	var queue: Array[int] = [capital]
	var cursor := 0
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		var current_dist := int(dist[current])
		var sorted_neighbors: Array[int] = state.neighbors(current).duplicate()
		sorted_neighbors.sort()
		for neighbor in sorted_neighbors:
			if dist.has(neighbor):
				continue
			if state.cities[neighbor].owner_nation != nation_id:
				continue
			var edge := state.edge_of(current, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			dist[neighbor] = current_dist + 1
			queue.append(neighbor)
	return dist


## 该城是否为本国边疆城：至少有一条正容量边通往非本国可通行的城。
static func _city_is_frontier(
	state: GameState,
	nation_id: int,
	city_id: int
) -> bool:
	for neighbor in state.neighbors(city_id):
		var edge := state.edge_of(city_id, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		var neighbor_owner := state.cities[neighbor].owner_nation
		if neighbor_owner >= 0 and not state.has_military_access(nation_id, neighbor_owner):
			return true
	return false


## 中央是否正在承受严重外战压力：有实际前线的对外战争，或军费已在拖欠。
static func _overlord_under_war_pressure(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> bool:
	var nation := state.nations[nation_id]
	if nation.military_payment_ratio < 1.0:
		return true
	for enemy_id in state.wars_of(nation_id):
		if _frontier_edges(state, nation_id, enemy_id, evaluation_cache) > 0:
			return true
	return false


## 生成分封候选动作。第一版规则（尽量少变量、先跑起来）：
##   非藩王 且 冷却已过 且 处于和平 且 候选区负担比超阈 且 分封后留足核心 → 分封。
## 注：与设计文档第 6 节相反，这里要求「和平」而非「正在外战」——战时把前线连同
## 尚弱的藩王一起甩出会导致边疆崩溃，且与削藩「宗主须和平」对称，逻辑更自洽。
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
		# 藩王不得再分封（第一版不做多级自动分封）；已在本 tick 有动作的国家跳过。
		if state.is_vassal(overlord_id) or committed.has(overlord_id):
			continue
		# 冷却：距上次分封任一藩王不足冷却期则跳过。
		if _recent_enfeoff_day(state, overlord_id) >= 0 and (
			state.day - _recent_enfeoff_day(state, overlord_id)
				< ENFEOFF_DECISION_COOLDOWN_DAYS
		):
			continue
		# 只有和平时期才分封：战时把前线连同弱藩王一起甩出去反而会导致边疆崩溃，
		# 且与削藩「宗主须和平」对称——分封与削藩都是和平期的政治重组，逻辑自洽。
		if _overlord_under_war_pressure(state, overlord_id, evaluation_cache):
			continue
		var region := _grow_enfeoff_region(state, overlord_id, evaluation_cache)
		if region.size() < ENFEOFF_MIN_REGION_CITIES:
			continue
		# 分封后宗主必须保留足够核心领土。
		if (
			state.land_cities_of(overlord_id).size() - region.size()
				< ENFEOFF_MIN_OVERLORD_CITIES_AFTER
		):
			continue
		var burden := evaluate_region_burden(state, overlord_id, region)
		if float(burden["burden_ratio"]) < ENFEOFF_BURDEN_RATIO_THRESHOLD:
			continue
		actions.append({
			"kind": Action.ENFEOFF,
			"a": overlord_id,
			"b": overlord_id,
			"region_cities": region,
			"reason": "和平期偏远边疆负担比%.2f超阈，分封以转移地方防务" % float(
				burden["burden_ratio"]
			),
		})
		committed[overlord_id] = true


## 该宗主最近一次分封任一藩王的世界日；从未分封返回 -1。
static func _recent_enfeoff_day(state: GameState, overlord_id: int) -> int:
	var latest := -1
	for subject_id in state.subjects_of(overlord_id):
		var created := int(state.suzerainty_record(subject_id).get("created_day", -1))
		if created > latest:
			latest = created
	return latest


# ------------------------------------------------------------------ 削藩（藩王系统 C2）
# 宗主在和平期、对藩王有军力优势且冷却已过时发起削藩。藩王按「反抗比」即时决定：
# 反抗比 = 藩王军力 / 宗主可镇压军力。低于阈值则接受（和平撤藩），高则反抗（内战）。
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


## 生成削藩候选动作。规则（文档 17、18 节）：
##   宗主非藩王、处于和平、对该藩王军力优势达标、冷却已过、当前无内战 → 削藩。
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
		if state.is_vassal(overlord_id) or committed.has(overlord_id):
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
			# 军力优势：宗主可镇压军力须达藩王的倍数阈值。
			var subject_power := _national_power(state, subject_id, evaluation_cache)
			var suppression := _suppression_power(state, overlord_id, evaluation_cache)
			if suppression < subject_power * CENTRALIZE_MIN_POWER_ADVANTAGE:
				continue
			var resist_ratio := subject_power / maxf(suppression, 1.0)
			var will_resist := resist_ratio > CENTRALIZE_RESIST_RATIO_THRESHOLD
			actions.append({
				"kind": Action.CENTRALIZE,
				"a": overlord_id,
				"b": subject_id,
				"resist": will_resist,
				"resist_ratio": resist_ratio,
				"reason": (
					"和平期对藩王%d削藩：反抗比%.2f，%s"
					% [
						subject_id,
						resist_ratio,
						"藩王将反抗，转削藩内战" if will_resist else "藩王接受，和平撤藩直辖",
					]
				),
			})
			committed[overlord_id] = true
			committed[subject_id] = true
			break  # 一个宗主每 tick 最多对一个藩王削藩
