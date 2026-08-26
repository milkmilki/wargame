class_name RebellionSystem
extends RefCounted
## 月度忠诚与叛乱策略。
##
## 本类不持有跨月状态：纯函数只读取 GameState，resolve_month() 先计算完整月度
## 快照再统一写回，最后才调用 GameState 的政治事务，避免城市遍历顺序改变结果。

const LOYALTY_MIN: float = 0.0
const LOYALTY_MAX: float = 100.0
const LOYALTY_DEFAULT: float = 75.0
const MONTHLY_LOYALTY_STEP: float = 5.0
const LOYALTY_MONTHLY_STEP: float = MONTHLY_LOYALTY_STEP
const LOYALTY_REBEL: float = 25.0

const REBELLION_PROGRESS_MONTHS: int = 3
const REBELLION_COOLDOWN_DAYS: int = 720
## 地方叛军建国后，母国与叛军至少交战一个游戏年，不能刚起兵便议和。
const REGIONAL_REBELLION_MIN_WAR_DAYS: int = 360

const FOREIGN_RULE_PENALTY: float = 45.0
const CAPITAL_BONUS: float = 10.0
const LOYALTY_SOFT_STABILITY_THRESHOLD: float = 55.0
const ADMIN_RADIUS_BASE: float = 6.1
const ADMIN_RADIUS_LOYALTY_SCALE: float = 5.0
const ADMIN_RADIUS_CENTRALIZE_SCALE: float = 2.0
const DISTANCE_BASE_PENALTY_PER_HOP: float = 2.0
const DISTANCE_BASE_PENALTY_MAX: float = 20.0
const DISTANCE_PENALTY_PER_HOP: float = 6.0
const DISTANCE_PENALTY_MAX: float = 36.0
const UNREACHABLE_DISTANCE_EXCESS_FLOOR: float = (
	float(DISTANCE_PENALTY_MAX) / DISTANCE_PENALTY_PER_HOP
)
const FLAT_LOYALTY_SCALE: float = 15.0
const UPKEEP_PRESSURE_SCALE: float = 35.0
const WAR_ZONE_PENALTY: float = 10.0
const WAR_DISRUPTION_PENALTY: float = 10.0
const UNPAID_MILITARY_PENALTY_MAX: float = 20.0
const LOW_LOYALTY_NEIGHBOR_PENALTY: float = 3.0
const LOW_LOYALTY_NEIGHBOR_PENALTY_MAX: float = 12.0

const GARRISON_UNIT: int = 5000
const GARRISON_BONUS_PER_UNIT: float = 2.0
const GARRISON_BONUS_MAX: float = 10.0
const VASSAL_TRIBUTE_PENALTY_MAX: float = 20.0
const VASSAL_DESPERATE_LOYALTY: float = 20.0
const VASSAL_DEFIANT_LOYALTY: float = 35.0
const VASSAL_DESPERATE_POWER_RATIO: float = 0.20
const VASSAL_DEFIANT_POWER_RATIO: float = 0.35
const VASSAL_REBEL_POWER_RATIO: float = 0.55
const _CACHE_PRESENT_KEY: StringName = &"__rebellion_cache_present"


## 本国首都到各直辖城市的最少道路跳数。只走本国控制且容量为正的边。
## 返回 city_id -> hop_count；断联城市不出现在结果中。
static func capital_hops(state: GameState, nation_id: int) -> Dictionary:
	var result: Dictionary = {}
	if not _valid_living_nation(state, nation_id):
		return result
	var capital_id: int = state.nations[nation_id].capital_city_id
	if (
		capital_id < 0
		or capital_id >= state.cities.size()
		or state.cities[capital_id].owner_nation != nation_id
	):
		return result
	result[capital_id] = 0
	var queue: Array[int] = [capital_id]
	var cursor: int = 0
	while cursor < queue.size():
		var current: int = queue[cursor]
		cursor += 1
		var neighbors: Array[int] = state.neighbors(current).duplicate()
		neighbors.sort()
		for neighbor in neighbors:
			if result.has(neighbor):
				continue
			if state.cities[neighbor].owner_nation != nation_id:
				continue
			var edge: Edge = state.edge_of(current, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			result[neighbor] = int(result[current]) + 1
			queue.append(neighbor)
	return result


## 汇总实际位于城市节点的本国驻军，结果为 city_id -> manpower。边上军队不产生
## 行政压制；容量等待等尚未上路的军队仍在城内，因而可以压制骚乱。
static func _garrison_manpower_by_city(state: GameState) -> Dictionary:
	var result: Dictionary = {}
	if state == null:
		return result
	for army in state.armies:
		if (
			army.size <= 0
			or army.on_edge
			or army.location_city < 0
			or army.location_city >= state.cities.size()
			or state.cities[army.location_city].owner_nation
				!= army.owner_nation
		):
			continue
		result[army.location_city] = (
			int(result.get(army.location_city, 0)) + army.size
		)
	return result


## 君主可稳定直辖领土的行政半径。忠诚代表基层认同与执行力，
## 集权代表命令链条的可延展性；两者都只通过 RulerProfile 统一派生。
static func administrative_radius(
	profile_or_nation: Variant,
	traits: Array = []
) -> float:
	var loyalty_multiplier := RulerProfile.loyalty_multiplier(
		profile_or_nation,
		traits
	)
	var centralize_multiplier := RulerProfile.centralize_multiplier(
		profile_or_nation,
		traits
	)
	return maxf(
		1.0,
		ADMIN_RADIUS_BASE
			+ (loyalty_multiplier - 1.0) * ADMIN_RADIUS_LOYALTY_SCALE
			+ (
				centralize_multiplier - 1.0
			) * ADMIN_RADIUS_CENTRALIZE_SCALE
	)


## 行政半径之外的“超距”量。不可达飞地统一视作最高治理摩擦，
## 供忠诚扣分与分封治理压力复用同一语义。
static func administrative_distance_excess(
	hop_count: int,
	admin_radius: float
) -> float:
	if hop_count < 0:
		return maxf(
			admin_radius + 1.0,
			UNREACHABLE_DISTANCE_EXCESS_FLOOR
		)
	return maxf(float(hop_count) - admin_radius, 0.0)


## 距首都 hop_count 跳时，超出行政半径造成的稳定惩罚。
## 半径内不扣分；超半径后按每整跳阶梯递增，避免分数在半径边界抖动。
static func administrative_distance_penalty(
	hop_count: int,
	admin_radius: float
) -> float:
	if hop_count < 0:
		return DISTANCE_PENALTY_MAX
	if hop_count == 0:
		return 0.0
	var base_penalty := minf(
		float(maxi(hop_count - 1, 0)) * DISTANCE_BASE_PENALTY_PER_HOP,
		DISTANCE_BASE_PENALTY_MAX
	)
	var over_radius := administrative_distance_excess(
		hop_count,
		admin_radius
	)
	return minf(
		base_penalty + ceilf(over_radius) * DISTANCE_PENALTY_PER_HOP,
		DISTANCE_PENALTY_MAX
	)


## 给定 ruler 与当前平面忠诚修正后，离首都多少跳仍处于“够稳定”区。
## 该阈值只服务于 AI 和解释，不改变叛乱硬阈值与月度步长。
static func administrative_soft_stability_hops(
	profile_or_nation: Variant,
	soft_threshold: float = LOYALTY_SOFT_STABILITY_THRESHOLD,
	traits: Array = []
) -> float:
	var loyalty_multiplier := RulerProfile.loyalty_multiplier(
		profile_or_nation,
		traits
	)
	var flat_loyalty_bonus := (
		(loyalty_multiplier - 1.0) * FLAT_LOYALTY_SCALE
	)
	var upkeep_pressure := maxf(
		RulerProfile.upkeep_multiplier(profile_or_nation, traits) - 1.0,
		0.0
	) * UPKEEP_PRESSURE_SCALE
	var admin_radius := administrative_radius(
		profile_or_nation,
		traits
	)
	var base_value := (
		LOYALTY_DEFAULT
		+ flat_loyalty_bonus
		- upkeep_pressure
	)
	if base_value < soft_threshold:
		return 0.0
	var hop_count := 0
	while administrative_distance_penalty(
		hop_count + 1,
		admin_radius
	) <= base_value - soft_threshold:
		hop_count += 1
		if hop_count > 1024:
			break
	return float(hop_count)


## 城市的长期忠诚目标。返回值是纯快照，不改写 City。
## capital_hops 可注入同一 owner 的 BFS 结果；传空字典时本函数自行计算。
static func loyalty_target(
	state: GameState,
	city_id: int,
	capital_hops: Dictionary = {}
) -> Dictionary:
	if not _valid_city(state, city_id):
		return {
			"value": LOYALTY_MIN,
			"delta": 0.0,
			"reasons": ["invalid_city"] as Array[String],
			"target_nation": -1,
		}
	var city: City = state.cities[city_id]
	var owner_id: int = city.owner_nation
	if not _valid_living_nation(state, owner_id):
		return {
			"value": LOYALTY_MIN,
			"delta": LOYALTY_MIN - clampf(
				city.loyalty, LOYALTY_MIN, LOYALTY_MAX
			),
			"reasons": ["invalid_owner"] as Array[String],
			"target_nation": -1,
		}

	var reasons: Array[String] = ["baseline"]
	var reason_details: Array[String] = ["baseline"]
	var value: float = LOYALTY_DEFAULT
	var target_nation: int = _city_target_nation(state, city_id)
	# 法理与实控不一致时 target 默认取法理国；显式政治目标也走同一分项，
	# 从而不会把同一次占领惩罚重复计算两次。
	if target_nation != owner_id:
		value -= FOREIGN_RULE_PENALTY
		reasons.append("foreign_rule")
		reason_details.append(
			"foreign_rule -%.0f" % FOREIGN_RULE_PENALTY
		)

	var capital_id: int = state.nations[owner_id].capital_city_id
	if city_id == capital_id:
		value += CAPITAL_BONUS
		reasons.append("capital")
		reason_details.append("capital +%.0f" % CAPITAL_BONUS)

	# The public empty default falls back to the authoritative road graph. The
	# monthly helper tags an explicitly supplied (possibly empty) owner cache.
	var hops: Dictionary = capital_hops
	var cache_present: bool = bool(hops.get(_CACHE_PRESENT_KEY, false))
	if not cache_present and hops.is_empty():
		hops = RebellionSystem.capital_hops(state, owner_id)
	var hop_count := -1
	var admin_radius := administrative_radius(
		state.nations[owner_id]
	)
	var distance_penalty: float = DISTANCE_PENALTY_MAX
	if hops.has(city_id):
		hop_count = maxi(int(hops[city_id]), 0)
	distance_penalty = administrative_distance_penalty(
		hop_count,
		admin_radius
	)
	value -= distance_penalty
	if distance_penalty > 0.0:
		reasons.append("distance")
		var distance_excess := administrative_distance_excess(
			hop_count,
			admin_radius
		)
		if hop_count < 0:
			reason_details.append(
				"admin_radius %.1f, unreachable, excess %.1f, distance -%.0f"
				% [admin_radius, distance_excess, distance_penalty]
			)
		else:
			reason_details.append(
				"admin_radius %.1f, hop %d, over %.1f, distance -%.0f"
				% [admin_radius, hop_count, distance_excess, distance_penalty]
			)
	else:
		reason_details.append(
			"admin_radius %.1f, hop %d stable"
			% [admin_radius, maxi(hop_count, 0)]
		)

	if city.at_war:
		value -= WAR_ZONE_PENALTY
		reasons.append("war_disruption")
		reason_details.append(
			"war_disruption -%.0f" % WAR_ZONE_PENALTY
		)
	elif state.day < city.war_disruption_until_day:
		value -= WAR_DISRUPTION_PENALTY
		reasons.append("war_disruption")
		reason_details.append(
			"war_disruption -%.0f" % WAR_DISRUPTION_PENALTY
		)

	var payment_ratio: float = clampf(
		state.nations[owner_id].military_payment_ratio, 0.0, 1.0
	)
	var unpaid_penalty: float = (
		(1.0 - payment_ratio) * UNPAID_MILITARY_PENALTY_MAX
	)
	value -= unpaid_penalty
	if unpaid_penalty > 0.0:
		reasons.append("unpaid_military")
		reason_details.append(
			"unpaid_military -%.1f" % unpaid_penalty
		)
	# 昏君/暴君的低效与挥霍不仅通过欠饷间接传导，也直接形成全国
	# 财政信誉压力；其余君主的有效维护倍率接近 1，不产生额外扣分。
	var upkeep_pressure := maxf(
		RulerProfile.upkeep_multiplier(state.nations[owner_id]) - 1.0,
		0.0
	) * UPKEEP_PRESSURE_SCALE
	value -= upkeep_pressure
	if upkeep_pressure > 0.01:
		reasons.append("ruler_expenditure")
		reason_details.append(
			"ruler_expenditure -%.1f" % upkeep_pressure
		)

	var low_neighbors: int = _low_loyalty_neighbor_count(
		state, city_id, owner_id
	)
	var spread_penalty: float = minf(
		float(low_neighbors) * LOW_LOYALTY_NEIGHBOR_PENALTY,
		LOW_LOYALTY_NEIGHBOR_PENALTY_MAX
	)
	value -= spread_penalty
	if spread_penalty > 0.0:
		reasons.append("neighbor_unrest")
		reason_details.append(
			"neighbor_unrest -%.1f" % spread_penalty
		)

	# 君主只通过统一参数层改变长期稳定目标；昏庸/暴虐会把财政与
	# 民心压力传导到全国，改革者、勤政或魅力特质则提高认同。
	var ruler_stability := RulerProfile.loyalty_multiplier(
		state.nations[owner_id]
	)
	var ruler_delta := (
		ruler_stability - 1.0
	) * FLAT_LOYALTY_SCALE
	value += ruler_delta
	if absf(ruler_delta) > 0.01:
		reasons.append("ruler")
		reason_details.append("ruler %+0.1f" % ruler_delta)

	value = clampf(value, LOYALTY_MIN, LOYALTY_MAX)
	var current_loyalty: float = clampf(
		city.loyalty, LOYALTY_MIN, LOYALTY_MAX
	)
	return {
		"value": value,
		"delta": value - current_loyalty,
		"reasons": reasons,
		"reason_details": reason_details,
		"target_nation": target_nation,
		"hop_count": hop_count,
		"administrative_radius": admin_radius,
		"distance_excess": administrative_distance_excess(
			hop_count,
			admin_radius
		),
		"distance_penalty": distance_penalty,
		"soft_stability_threshold": LOYALTY_SOFT_STABILITY_THRESHOLD,
	}


## 计算一个月后的城市政治快照。hops_by_nation 的形状是
## nation_id -> {city_id: hops}，garrison_by_city 的值为驻军总兵力。
static func monthly_city_loyalty(
	state: GameState,
	city_id: int,
	hops_by_nation: Dictionary = {},
	garrison_by_city: Dictionary = {}
) -> Dictionary:
	if not _valid_city(state, city_id):
		return _invalid_monthly_snapshot(city_id)
	var city: City = state.cities[city_id]
	var owner_id: int = city.owner_nation
	if not _valid_living_nation(state, owner_id):
		return _invalid_monthly_snapshot(city_id)

	var owner_hops: Dictionary = {}
	if hops_by_nation.is_empty():
		owner_hops = capital_hops(state, owner_id)
	else:
		var provided_hops: Variant = hops_by_nation.get(owner_id, {})
		if provided_hops is Dictionary:
			owner_hops = (provided_hops as Dictionary).duplicate()
		owner_hops[_CACHE_PRESENT_KEY] = true
	var target: Dictionary = loyalty_target(
		state, city_id, owner_hops
	)
	var reasons: Array[String] = []
	for reason_value in target["reasons"]:
		reasons.append(str(reason_value))
	var reason_details: Array[String] = []
	for reason_value in target.get("reason_details", []):
		reason_details.append(str(reason_value))

	var garrison_manpower: int = _garrison_manpower(
		state, city_id, garrison_by_city
	)
	var garrison_bonus: float = minf(
		float(floori(float(garrison_manpower) / float(GARRISON_UNIT)))
			* GARRISON_BONUS_PER_UNIT,
		GARRISON_BONUS_MAX
	)
	if garrison_bonus > 0.0:
		reasons.append("garrison")
		reason_details.append("garrison +%.0f" % garrison_bonus)

	var previous_loyalty: float = clampf(
		city.loyalty, LOYALTY_MIN, LOYALTY_MAX
	)
	var desired_loyalty: float = clampf(
		float(target["value"]) + garrison_bonus,
		LOYALTY_MIN,
		LOYALTY_MAX
	)
	var applied_delta: float = clampf(
		desired_loyalty - previous_loyalty,
		-MONTHLY_LOYALTY_STEP,
		MONTHLY_LOYALTY_STEP
	)
	var loyalty: float = clampf(
		previous_loyalty + applied_delta,
		LOYALTY_MIN,
		LOYALTY_MAX
	)
	var unrest: float = clampf(
		LOYALTY_MAX - loyalty,
		LOYALTY_MIN,
		LOYALTY_MAX
	)
	var cooldown_until: int = city.rebellion_cooldown_until_day
	var eligible: bool = (
		not city.is_dock
		and loyalty <= LOYALTY_REBEL
		and state.day >= cooldown_until
	)
	var progress: int = city.rebellion_progress + 1 if eligible else 0
	var reason_text: String = "; ".join(reason_details)
	return {
		"city_id": city_id,
		"owner_nation": owner_id,
		"target_nation": int(target["target_nation"]),
		"previous_loyalty": previous_loyalty,
		"base_target_loyalty": float(target["value"]),
		"target_loyalty": desired_loyalty,
		"loyalty": loyalty,
		"delta": applied_delta,
		"trend": applied_delta,
		"unrest": unrest,
		"garrison_manpower": garrison_manpower,
		"garrison_bonus": garrison_bonus,
		"rebellion_progress": progress,
		"rebellion_cooldown_until_day": cooldown_until,
		"reasons": reasons,
		"reason_details": reason_details,
		"last_loyalty_reason": reason_text,
		"eligible": eligible,
	}


## 将满足条件的城市按“正容量道路相连且政治目标相同”划为确定性连通分量。
## candidate_ids 为空时扫描 parent 全境；传入时只在该集合内筛选。
static func collect_rebellion_regions(
	state: GameState,
	parent_id: int,
	candidate_ids: Array = []
) -> Array:
	var regions: Array = []
	if not _valid_living_nation(state, parent_id):
		return regions
	if state.is_in_civil_war(parent_id):
		return regions

	var requested: Dictionary = {}
	if candidate_ids.is_empty():
		for city in state.cities:
			if city.owner_nation == parent_id:
				requested[city.id] = true
	else:
		for city_value in candidate_ids:
			var requested_id: int = int(city_value)
			if _valid_city(state, requested_id):
				requested[requested_id] = true

	var active_city_ids: Dictionary = _active_rebellion_city_ids(
		state, parent_id
	)
	var eligible: Dictionary = {}
	var ordered_ids: Array[int] = []
	for city_value in requested.keys():
		var city_id: int = int(city_value)
		var city: City = state.cities[city_id]
		if (
			city.owner_nation != parent_id
			or city.is_dock
			or city.is_capital
			or city.loyalty > LOYALTY_REBEL
			or city.rebellion_progress < REBELLION_PROGRESS_MONTHS
			or state.day < city.rebellion_cooldown_until_day
			or active_city_ids.has(city_id)
			or _wartime_occupation_locked(state, city_id)
		):
			continue
		eligible[city_id] = true
		ordered_ids.append(city_id)
	ordered_ids.sort()

	var visited: Dictionary = {}
	for seed in ordered_ids:
		if visited.has(seed):
			continue
		var target_nation: int = state.cities[seed].loyalty_target_nation
		var region: Array[int] = []
		var queue: Array[int] = [seed]
		visited[seed] = true
		var cursor: int = 0
		while cursor < queue.size():
			var current: int = queue[cursor]
			cursor += 1
			region.append(current)
			var neighbors: Array[int] = state.neighbors(current).duplicate()
			neighbors.sort()
			for neighbor in neighbors:
				if not eligible.has(neighbor) or visited.has(neighbor):
					continue
				if (
					state.cities[neighbor].loyalty_target_nation
						!= target_nation
				):
					continue
				var edge: Edge = state.edge_of(current, neighbor)
				if edge == null or edge.max_manpower <= 0:
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		region.sort()
		regions.append(region)
	return regions


## 战时占领锁：正被军事占领（实控者非法理国）且占领方仍与法理国交战的
## 城市属于前线战果，只能靠军事结果或和约易主，不能在战争期间通过“忠诚复国”
## 机制凭空反正回敌国——这正是玩家反馈的“打下的城过一阵自己跳回原主”的根因。
## 和平后的文化归附（实控==法理，但政治目标为另一存活国）不受影响，仍可离心。
static func _wartime_occupation_locked(state: GameState, city_id: int) -> bool:
	if not _valid_city(state, city_id):
		return false
	var city: City = state.cities[city_id]
	var legal_owner: int = state.recognized_owner_of(city_id)
	if not _valid_nation(state, legal_owner) or legal_owner == city.owner_nation:
		return false
	# 实控方（占领者）仍与法理国交战：这是活跃前线，禁止民变式反正。
	if state.is_enemy(city.owner_nation, legal_owner):
		return true
	# 战争结算责任方（sponsor）与法理国交战时同样按活跃占领处理。
	var sponsor: int = city.occupation_sponsor_nation
	return _valid_nation(state, sponsor) and state.is_enemy(sponsor, legal_owner)


## 藩王忠诚取其直辖陆城忠诚均值，再扣除贡赋负担。无效对象返回 100，
## 使调用方 fail closed；内战中的藩王也不会被重复触发。
static func vassal_loyalty(
	state: GameState,
	subject_id: int
) -> float:
	if (
		not _valid_living_nation(state, subject_id)
		or not state.is_vassal(subject_id)
		or state.is_in_civil_war(subject_id)
	):
		return LOYALTY_MAX
	var overlord_id: int = state.overlord_of(subject_id)
	if not _valid_living_nation(state, overlord_id):
		return LOYALTY_MAX

	var total: float = 0.0
	var city_count: int = 0
	for city in state.cities:
		if city.owner_nation == subject_id and not city.is_dock:
			total += clampf(city.loyalty, LOYALTY_MIN, LOYALTY_MAX)
			city_count += 1
	if city_count <= 0:
		return LOYALTY_MAX

	var record: Dictionary = state.suzerainty_record(subject_id)
	var tribute_rate: float = clampf(
		float(record.get("tribute_rate", 0.0)), 0.0, 1.0
	)
	var tribute_penalty: float = (
		tribute_rate * VASSAL_TRIBUTE_PENALTY_MAX
	)
	return clampf(
		total / float(city_count) - tribute_penalty,
		LOYALTY_MIN,
		LOYALTY_MAX
	)


static func should_vassal_rebel(
	state: GameState,
	subject_id: int,
	loyalty: float = -1.0
) -> bool:
	if (
		not _valid_living_nation(state, subject_id)
		or not state.is_vassal(subject_id)
		or state.is_in_civil_war(subject_id)
	):
		return false
	var overlord_id: int = state.overlord_of(subject_id)
	if not _valid_living_nation(state, overlord_id):
		return false
	var effective_loyalty: float = (
		vassal_loyalty(state, subject_id)
		if loyalty < 0.0
		else clampf(loyalty, LOYALTY_MIN, LOYALTY_MAX)
	)
	if effective_loyalty > LOYALTY_REBEL:
		return false
	if not _vassal_low_loyalty_mature(state, subject_id):
		return false
	if (
		not _rebellion_cooldown_elapsed(state, subject_id)
		or not _rebellion_cooldown_elapsed(state, overlord_id)
	):
		return false
	var required_power_ratio: float = VASSAL_REBEL_POWER_RATIO
	if effective_loyalty < VASSAL_DESPERATE_LOYALTY:
		required_power_ratio = VASSAL_DESPERATE_POWER_RATIO
	elif effective_loyalty < VASSAL_DEFIANT_LOYALTY:
		required_power_ratio = VASSAL_DEFIANT_POWER_RATIO
	return (
		_nation_military_power(state, subject_id)
		/ maxf(_nation_military_power(state, overlord_id), 1.0)
		> required_power_ratio
	)


## 推进一次月度政治结算并返回本月成功提交的展示事件。GameState 的
## start_civil_war/start_regional_rebellion/restore_regional_loyalty_target
## 是事务入口；已有存活政治目标的地区优先复国/归附，不创造新 Nation。
static func resolve_month(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state == null:
		return events
	var initial_nation_count: int = state.nations.size()

	# 所有城市读取同一份月初快照，邻城扩散不受 city 数组迭代次序影响。
	var hops_by_nation: Dictionary = {}
	for nation in state.nations:
		if nation.alive:
			hops_by_nation[nation.id] = capital_hops(state, nation.id)
	var garrison_by_city: Dictionary = _garrison_manpower_by_city(state)
	var snapshots: Array[Dictionary] = []
	for city in state.cities:
		snapshots.append(monthly_city_loyalty(
			state, city.id, hops_by_nation, garrison_by_city
		))

	for snapshot in snapshots:
		var city_id: int = int(snapshot["city_id"])
		if not _valid_city(state, city_id):
			continue
		var city: City = state.cities[city_id]
		city.loyalty = float(snapshot["loyalty"])
		city.loyalty_target_nation = int(snapshot["target_nation"])
		city.loyalty_trend = float(snapshot["trend"])
		city.unrest = float(snapshot["unrest"])
		city.rebellion_progress = int(snapshot["rebellion_progress"])
		city.rebellion_cooldown_until_day = int(
			snapshot["rebellion_cooldown_until_day"]
		)
		city.last_loyalty_reason = str(snapshot["last_loyalty_reason"])
	_sync_nation_average_loyalty(state)

	# 藩王反叛先于地方分裂；成功反叛的 subject 本月不再被切出地方叛军。
	var vassal_candidates: Array[Dictionary] = []
	for subject_id in _ordered_vassal_ids(state):
		var loyalty: float = vassal_loyalty(state, subject_id)
		if should_vassal_rebel(state, subject_id, loyalty):
			vassal_candidates.append({
				"subject_id": subject_id,
				"overlord_id": state.overlord_of(subject_id),
				"loyalty": loyalty,
			})
	var consumed_nations: Dictionary = {}
	for candidate in vassal_candidates:
		var subject_id: int = int(candidate["subject_id"])
		var loyalty: float = float(candidate["loyalty"])
		var overlord_id: int = int(candidate["overlord_id"])
		if (
			consumed_nations.has(subject_id)
			or consumed_nations.has(overlord_id)
			or state.is_in_civil_war(subject_id)
		):
			continue
		if not state.start_civil_war(subject_id):
			continue
		consumed_nations[subject_id] = true
		consumed_nations[overlord_id] = true
		state.nations[overlord_id].last_rebellion_day = state.day
		state.nations[subject_id].last_rebellion_day = state.day
		var subject_cities: Array[int] = _land_city_ids_of(
			state, subject_id
		)
		events.append({
			"kind": "vassal_rebellion",
			"parent_id": overlord_id,
			"rebel_id": subject_id,
			"city_ids": subject_cities,
			"day": state.day,
			"reason": "vassal loyalty %.1f <= %.1f"
				% [loyalty, LOYALTY_REBEL],
		})

	for parent_id in range(initial_nation_count):
		if (
			consumed_nations.has(parent_id)
			or not _valid_living_nation(state, parent_id)
		):
			continue
		var regions: Array = collect_rebellion_regions(
			state, parent_id
		)
		for region_value in regions:
			var city_ids: Array[int] = []
			for city_value in region_value:
				city_ids.append(int(city_value))
			if city_ids.is_empty():
				continue
			var target_id: int = state.cities[city_ids[0]].loyalty_target_nation
			if (
				target_id != parent_id
				and _valid_living_nation(state, target_id)
			):
				if not state.restore_regional_loyalty_target(
					parent_id, target_id, city_ids
				):
					continue
				state.nations[parent_id].last_rebellion_day = state.day
				state.nations[target_id].last_rebellion_day = state.day
				for city_id in city_ids:
					var restored_city: City = state.cities[city_id]
					restored_city.rebellion_progress = 0
					restored_city.rebellion_cooldown_until_day = maxi(
						restored_city.rebellion_cooldown_until_day,
						state.day + REBELLION_COOLDOWN_DAYS
					)
					restored_city.loyalty_target_nation = target_id
					restored_city.last_loyalty_reason = "loyalty_target_restored"
				events.append({
					"kind": "loyalty_target_restored",
					"parent_id": parent_id,
					"target_id": target_id,
					"city_ids": city_ids.duplicate(),
					"day": state.day,
					"reason": "loyalty target restored after %d months"
						% REBELLION_PROGRESS_MONTHS,
				})
				continue
			var rebel_id: int = state.start_regional_rebellion(
				parent_id, city_ids
			)
			if rebel_id < 0:
				continue
			state.nations[parent_id].last_rebellion_day = state.day
			if _valid_nation(state, rebel_id):
				state.nations[rebel_id].last_rebellion_day = state.day
			for city_id in city_ids:
				var rebel_city: City = state.cities[city_id]
				rebel_city.rebellion_progress = 0
				rebel_city.rebellion_cooldown_until_day = maxi(
					rebel_city.rebellion_cooldown_until_day,
					state.day + REBELLION_COOLDOWN_DAYS
				)
				rebel_city.loyalty_target_nation = rebel_id
				rebel_city.last_loyalty_reason = "regional_rebellion"
			events.append({
				"kind": "regional_rebellion",
				"parent_id": parent_id,
				"rebel_id": rebel_id,
				"city_ids": city_ids.duplicate(),
				"day": state.day,
				"reason": "loyalty <= %.1f for %d months"
					% [LOYALTY_REBEL, REBELLION_PROGRESS_MONTHS],
			})
	_sync_nation_average_loyalty(state)
	return events


static func _city_target_nation(state: GameState, city_id: int) -> int:
	var city: City = state.cities[city_id]
	if _valid_nation(state, city.loyalty_target_nation):
		return city.loyalty_target_nation
	var recognized_owner: int = state.recognized_owner_of(city_id)
	if _valid_nation(state, recognized_owner):
		return recognized_owner
	if _valid_nation(state, city.owner_nation):
		return city.owner_nation
	return -1


static func _low_loyalty_neighbor_count(
	state: GameState,
	city_id: int,
	owner_id: int
) -> int:
	var count: int = 0
	var neighbors: Array[int] = state.neighbors(city_id).duplicate()
	neighbors.sort()
	for neighbor in neighbors:
		var edge: Edge = state.edge_of(city_id, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		var other: City = state.cities[neighbor]
		if (
			other.owner_nation == owner_id
			and other.loyalty <= LOYALTY_REBEL
		):
			count += 1
	return count


static func _garrison_manpower(
	state: GameState,
	city_id: int,
	garrison_by_city: Dictionary
) -> int:
	if not garrison_by_city.is_empty():
		var cached: Variant = garrison_by_city.get(city_id, 0)
		if cached is Array:
			var total: int = 0
			for army_value in cached:
				if army_value is Army:
					total += maxi((army_value as Army).size, 0)
			return total
		return maxi(int(cached), 0)
	var total: int = 0
	var owner_id: int = state.cities[city_id].owner_nation
	for army in state.armies:
		if (
			army.size > 0
			and not army.on_edge
			and army.location_city == city_id
			and army.owner_nation == owner_id
		):
			total += army.size
	return total


static func _active_rebellion_city_ids(
	state: GameState,
	parent_id: int
) -> Dictionary:
	var result: Dictionary = {}
	for rebel_value in state.rebellions.values():
		if not rebel_value is Dictionary:
			continue
		var record: Dictionary = rebel_value as Dictionary
		if (
			int(record.get("parent_id", -1)) != parent_id
			or not bool(record.get("active", true))
		):
			continue
		var core_value: Variant = record.get("core_city_ids", [])
		if not core_value is Array:
			continue
		var core_ids: Array = core_value as Array
		for city_value in core_ids:
			result[int(city_value)] = true
	return result


static func _land_city_ids_of(
	state: GameState,
	nation_id: int
) -> Array[int]:
	var result: Array[int] = []
	for city in state.cities:
		if city.owner_nation == nation_id and not city.is_dock:
			result.append(city.id)
	result.sort()
	return result


static func _ordered_vassal_ids(state: GameState) -> Array[int]:
	var result: Array[int] = []
	var depths: Dictionary = {}
	for subject_value in state.suzerainty.keys():
		var subject_id: int = int(subject_value)
		result.append(subject_id)
		var depth: int = 0
		var current: int = subject_id
		var seen: Dictionary = {}
		while state.is_vassal(current) and not seen.has(current):
			seen[current] = true
			depth += 1
			current = state.overlord_of(current)
		depths[subject_id] = depth
	result.sort_custom(func(a: int, b: int) -> bool:
		var depth_a: int = int(depths.get(a, 0))
		var depth_b: int = int(depths.get(b, 0))
		if depth_a != depth_b:
			return depth_a < depth_b
		return a < b
	)
	return result


static func _vassal_low_loyalty_mature(
	state: GameState,
	subject_id: int
) -> bool:
	for city in state.cities:
		if (
			city.owner_nation == subject_id
			and not city.is_dock
			and city.rebellion_progress >= REBELLION_PROGRESS_MONTHS
		):
			return true
	return false


static func _rebellion_cooldown_elapsed(
	state: GameState,
	nation_id: int
) -> bool:
	var last_day: int = state.nations[nation_id].last_rebellion_day
	return (
		last_day < 0
		or state.day - last_day >= REBELLION_COOLDOWN_DAYS
	)


static func _nation_military_power(
	state: GameState,
	nation_id: int
) -> float:
	var power: float = 0.0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			power += ArmyPower.effective(army)
	return power


static func _sync_nation_average_loyalty(state: GameState) -> void:
	var totals: Dictionary = {}
	var counts: Dictionary = {}
	for city in state.cities:
		if city.is_dock or not _valid_living_nation(state, city.owner_nation):
			continue
		totals[city.owner_nation] = (
			float(totals.get(city.owner_nation, 0.0))
			+ clampf(city.loyalty, LOYALTY_MIN, LOYALTY_MAX)
		)
		counts[city.owner_nation] = (
			int(counts.get(city.owner_nation, 0)) + 1
		)
	for nation in state.nations:
		if not nation.alive:
			continue
		var count: int = int(counts.get(nation.id, 0))
		nation.average_loyalty = (
			clampf(
				float(totals.get(nation.id, 0.0)) / float(count),
				LOYALTY_MIN,
				LOYALTY_MAX
			)
			if count > 0
			else LOYALTY_MAX
		)


static func _invalid_monthly_snapshot(city_id: int) -> Dictionary:
	return {
		"city_id": city_id,
		"owner_nation": -1,
		"target_nation": -1,
		"previous_loyalty": LOYALTY_MIN,
		"base_target_loyalty": LOYALTY_MIN,
		"target_loyalty": LOYALTY_MIN,
		"loyalty": LOYALTY_MIN,
		"delta": 0.0,
		"trend": 0.0,
		"unrest": LOYALTY_MAX,
		"garrison_manpower": 0,
		"garrison_bonus": 0.0,
		"rebellion_progress": 0,
		"rebellion_cooldown_until_day": 0,
		"reasons": ["invalid_city"] as Array[String],
		"last_loyalty_reason": "invalid_city",
		"eligible": false,
	}


static func _valid_city(state: GameState, city_id: int) -> bool:
	return state != null and city_id >= 0 and city_id < state.cities.size()


static func _valid_living_nation(
	state: GameState,
	nation_id: int
) -> bool:
	return (
		state != null
		and nation_id >= 0
		and nation_id < state.nations.size()
		and state.nations[nation_id].alive
	)


static func _valid_nation(state: GameState, nation_id: int) -> bool:
	return (
		state != null
		and nation_id >= 0
		and nation_id < state.nations.size()
	)
