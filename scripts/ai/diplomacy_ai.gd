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


static func choose_actions(state: GameState) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var committed := {}
	var evaluation_cache := {}
	_collect_peace_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_collect_leave_alliance_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_collect_war_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	_collect_alliance_actions(
		state,
		actions,
		committed,
		evaluation_cache
	)
	return actions


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
	for enemy_id in state.wars_of(nation_id):
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
		state.allies_of(nation_id).size() >= MAX_DEFENSIVE_ALLIES
		or state.allies_of(target_id).size() >= MAX_DEFENSIVE_ALLIES
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
	var shared_threat := 0.0
	for other in state.nations:
		if other.id in [nation_id, target_id] or not other.alive:
			continue
		shared_threat = maxf(
			shared_threat,
			minf(
				threat_from_nation(
					state,
					nation_id,
					other.id,
					evaluation_cache
				),
				threat_from_nation(
					state,
					target_id,
					other.id,
					evaluation_cache
				)
			)
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
		or state.wars_of(nation_id).size() >= MAX_CONCURRENT_WARS
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
	var target_distraction := float(state.wars_of(target_id).size()) * 0.25
	var own_overextension := float(state.wars_of(nation_id).size()) * 0.75
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
	for city in state.cities_of(nation_id):
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
	var wars := state.wars_of(nation_id)
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
	var seen := {}
	for edge in state.edges:
		if edge.max_manpower <= 0:
			continue
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if (
			state.has_military_access(nation_id, owner_a)
			and owner_b >= 0
			and not state.has_military_access(nation_id, owner_b)
		):
			seen[owner_b] = true
		if (
			state.has_military_access(nation_id, owner_b)
			and owner_a >= 0
			and not state.has_military_access(nation_id, owner_a)
		):
			seen[owner_a] = true
	var result: Array[int] = []
	for other_id in seen:
		result.append(int(other_id))
	result.sort()
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
	for city in state.cities_of(nation_id):
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
		target_id
	)
	evaluation_cache[cache_key] = objective
	return objective


static func select_war_objective(
	state: GameState,
	nation_id: int,
	target_id: int
) -> Dictionary:
	var target_cities := state.cities_of(target_id)
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
		var encirclement_score := encirclement_value(
			state,
			city.id,
			target_id
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
	for enemy_id in state.wars_of(nation_id):
		if state.is_allied(ally_id, enemy_id):
			conflicting_commitments += 1
	var unilateral_wars := 0
	for enemy_id in state.wars_of(ally_id):
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
		if nation.war_preparation_target_nation >= 0:
			_collect_existing_war_preparation(
				state,
				nation.id,
				actions,
				committed,
				evaluation_cache
			)
			continue
		var best_target := -1
		var best_score := -INF
		for target in state.nations:
			if target.id == nation.id or committed.has(target.id) or not target.alive:
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
	if (
		not valid
		or resource_grace_expired
		or assembly_deadline_expired
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
	if not resources_ready:
		return
	if not preparation_ready:
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
	var power := 0.0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			power += ArmyPower.effective(army)
	var result := (
		power
		+ float(state.cities_of(nation_id).size()) * 1500.0
	)
	evaluation_cache[cache_key] = result
	return result


static func _troop_count(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "troops:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var total := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			total += army.size
	evaluation_cache[cache_key] = total
	return total


static func _full_strength_troop_count(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "full_troops:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var total := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			total += army.max_size
	evaluation_cache[cache_key] = total
	return total


static func _food_stock(
	state: GameState,
	nation_id: int,
	evaluation_cache: Dictionary = {}
) -> int:
	var cache_key := "food_stock:%d" % nation_id
	if evaluation_cache.has(cache_key):
		return int(evaluation_cache[cache_key])
	var total := 0
	for warehouse in state.warehouse_cities_of(nation_id):
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
	for ally_id in state.allies_of(nation_id):
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
	for enemy_id in state.wars_of(nation_a):
		if state.is_allied(nation_b, enemy_id):
			evaluation_cache[cache_key] = true
			return true
	for enemy_id in state.wars_of(nation_b):
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
