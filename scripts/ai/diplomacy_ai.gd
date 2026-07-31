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
const FORCED_PEACE_DAYS: int = 900
const MIN_NEUTRAL_DAYS: int = 180
const MIN_ALLIANCE_DAYS: int = 360
const MAX_CONCURRENT_WARS: int = 1
const MAX_DEFENSIVE_ALLIES: int = 1
const PEACE_ACCEPT_SCORE: float = 1.25
const ALLIANCE_ACCEPT_SCORE: float = 1.00
const WAR_DECLARE_SCORE: float = 1.35
const LEAVE_ALLIANCE_SCORE: float = 0.90
const CAMPAIGN_RESERVE_MONTHS: int = 6
const FOOD_PER_CAPITA_MONTH: float = 0.0025
const MIN_GOLD_RESERVE: int = 100
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
const WAR_PREPARATION_FORCE_SHARE: float = 0.25


static func choose_actions(state: GameState) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var committed := {}
	_collect_peace_actions(state, actions, committed)
	_collect_leave_alliance_actions(state, actions, committed)
	_collect_war_actions(state, actions, committed)
	_collect_alliance_actions(state, actions, committed)
	return actions


static func peace_willingness(state: GameState, nation_id: int, enemy_id: int) -> float:
	if not state.is_enemy(nation_id, enemy_id):
		return -INF
	var own_power := _national_power(state, nation_id)
	var enemy_power := _national_power(state, enemy_id)
	var ratio := enemy_power / maxf(own_power, 1.0)
	var war_days := state.day - state.relation_since(nation_id, enemy_id)
	var extra_wars := maxi(state.wars_of(nation_id).size() - 1, 0)
	var no_front := 1.0 if _frontier_edges(state, nation_id, enemy_id) == 0 else 0.0
	var crises := peace_reasons(state, nation_id, enemy_id)
	return (
		float(war_days) / 360.0
		+ maxf(ratio - 1.0, 0.0) * 1.5
		- minf(maxf(1.0 / maxf(ratio, 0.01) - 1.0, 0.0), 1.0)
		+ float(extra_wars) * 0.75
		+ no_front
		+ float(crises.size()) * 1.25
	)


static func peace_reasons(
	state: GameState,
	nation_id: int,
	enemy_id: int
) -> Array[String]:
	var reasons: Array[String] = []
	var report := resource_report(state, nation_id)
	var food_plan := war_food_report(state, nation_id)
	var nation := state.nations[nation_id]
	if (
		nation.unpaid_war_cost > 0
		or (
			int(report["monthly_gold_balance"]) < 0
			and float(report["gold_runway_months"]) < CAMPAIGN_RESERVE_MONTHS
		)
	):
		if nation.unpaid_war_cost > 0:
			reasons.append(
				"国库%d金，本月军费实际缺口%d"
				% [nation.treasury_gold, nation.unpaid_war_cost]
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
				"战争目标城市 %d 已被国%d控制"
				% [objective_city, attacker]
			)
	return reasons


static func alliance_willingness(state: GameState, nation_id: int, target_id: int) -> float:
	if state.relation_between(nation_id, target_id) != GameState.DiplomaticRelation.NEUTRAL:
		return -INF
	if (
		state.allies_of(nation_id).size() >= MAX_DEFENSIVE_ALLIES
		or state.allies_of(target_id).size() >= MAX_DEFENSIVE_ALLIES
	):
		return -INF
	if state.day - state.relation_since(nation_id, target_id) < MIN_NEUTRAL_DAYS:
		return -INF
	if _alliance_has_active_conflict(state, nation_id, target_id):
		return -INF
	var common_enemies := _common_enemy_count(state, nation_id, target_id)
	var own_power := _national_power(state, nation_id)
	var target_power := _national_power(state, target_id)
	var imbalance := absf(log(maxf(own_power, 1.0) / maxf(target_power, 1.0)))
	var border_bonus := 0.25 if _frontier_edges(state, nation_id, target_id) > 0 else 0.0
	var shared_threat := 0.0
	for other in state.nations:
		if other.id in [nation_id, target_id] or not other.alive:
			continue
		shared_threat = maxf(
			shared_threat,
			minf(
				threat_from_nation(state, nation_id, other.id),
				threat_from_nation(state, target_id, other.id)
			)
		)
	var balance_affinity := maxf(1.0 - imbalance, 0.0) * 0.55
	return (
		0.35
		+ float(common_enemies) * 1.5
		+ minf(shared_threat * 0.35, 0.80)
		+ border_bonus
		+ balance_affinity
	)


static func war_desire(state: GameState, nation_id: int, target_id: int) -> float:
	if (
		not state.can_declare_war(nation_id, target_id)
		or state.wars_of(nation_id).size() >= MAX_CONCURRENT_WARS
		or _frontier_edges(state, nation_id, target_id) <= 0
		or _has_shared_ally(state, nation_id, target_id)
	):
		return -INF
	var report := resource_report(state, nation_id)
	if not bool(report["ready"]):
		return -INF
	var campaign_troops := _campaign_troop_target(state, nation_id, target_id)
	var food_plan := war_food_report(
		state,
		nation_id,
		campaign_troops,
		FoodPosture.OFFENSIVE_WAR
	)
	if not bool(food_plan["target_sustainable"]):
		return -INF
	var objective := select_war_objective(state, nation_id, target_id)
	if objective.is_empty():
		return -INF
	# 共同防御联盟不参加成员主动发动的战争；进攻方只能计算本国战力。
	var own_power := _national_power(state, nation_id)
	var target_power := _coalition_power(state, target_id)
	var ratio := own_power / maxf(target_power, 1.0)
	var target_distraction := float(state.wars_of(target_id).size()) * 0.25
	var own_overextension := float(state.wars_of(nation_id).size()) * 0.75
	var border_value := minf(float(_frontier_edges(state, nation_id, target_id)) * 0.10, 0.50)
	var reserve_quality := minf(
		float(food_plan["target_runway_years"])
			/ OFFENSIVE_CAMPAIGN_YEARS,
		1.5
	) * 0.20
	var objective_value := minf(float(objective["value"]) * 0.05, 0.50)
	var mobilization_value := float(
		mobilization_capacity(state, nation_id)
	) * 0.15
	return (
		ratio
		+ target_distraction
		+ border_value
		+ reserve_quality
		+ objective_value
		+ mobilization_value
		- own_overextension
	)


static func threat_from_nation(
	state: GameState,
	observer_id: int,
	other_id: int
) -> float:
	if observer_id == other_id or state.is_allied(observer_id, other_id):
		return 0.0
	if state.is_enemy(observer_id, other_id):
		return 3.0
	var border_count := _frontier_edges(state, observer_id, other_id)
	if border_count <= 0:
		return 0.0
	var power_ratio := (
		_coalition_power(state, other_id)
		/ maxf(_coalition_power(state, observer_id), 1.0)
	)
	var report := resource_report(state, other_id)
	var readiness := 0.5 if bool(report["ready"]) else 0.0
	var hostile_intent := war_desire(state, other_id, observer_id)
	var intent_bonus := 0.0
	if hostile_intent > -INF:
		intent_bonus = maxf(hostile_intent - WAR_DECLARE_SCORE + 0.5, 0.0)
	return (
		power_ratio
		+ readiness
		+ minf(float(border_count) * 0.05, 0.25)
		+ intent_bonus
	)


static func resource_report(state: GameState, nation_id: int) -> Dictionary:
	var nation := state.nations[nation_id]
	var troops := _troop_count(state, nation_id)
	var monthly_income := 0
	for city in state.cities_of(nation_id):
		monthly_income += Simulation.city_gold_output(
			state,
			city
		)
	var food_plan := war_food_report(state, nation_id, troops)
	var monthly_food_production := float(food_plan["monthly_food_production"])
	var monthly_war_cost := int(ceil(
		float(troops) / float(GameState.WAR_GOLD_TROOPS_PER_UNIT)
	))
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
	var food_stock := _food_stock(state, nation_id)
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
	return {
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
			nation.unpaid_war_cost <= 0
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


static func mobilization_capacity(
	state: GameState,
	nation_id: int,
	posture: int = FoodPosture.OFFENSIVE_WAR
) -> int:
	var manpower_units := int(floor(
		float(maxi(
			state.nations[nation_id].manpower_pool - MIN_MANPOWER_RESERVE,
			0
		)) / float(MOBILIZATION_ARMY_SIZE)
	))
	var max_units := clampi(manpower_units, 0, MAX_MOBILIZATION_ARMIES)
	var current_troops := _troop_count(state, nation_id)
	var affordable_units := 0
	for units in range(1, max_units + 1):
		var target_troops := current_troops + units * MOBILIZATION_ARMY_SIZE
		var plan := war_food_report(
			state,
			nation_id,
			target_troops,
			posture
		)
		if not bool(plan["target_sustainable"]):
			break
		affordable_units = units
	return affordable_units


static func food_posture(state: GameState, nation_id: int) -> int:
	var wars := state.wars_of(nation_id)
	if not wars.is_empty():
		for enemy_id in wars:
			var objective := state.war_objective(nation_id, enemy_id)
			if (
				not objective.is_empty()
				and int(objective.get("attacker", -1)) == nation_id
			):
				return FoodPosture.OFFENSIVE_WAR
		return FoodPosture.DEFENSIVE_WAR
	if state.nations[nation_id].war_mobilization_target_troops > 0:
		return FoodPosture.GUARDED
	var own_power := _coalition_power(state, nation_id)
	for other in state.nations:
		if (
			other.id == nation_id
			or not other.alive
			or state.is_allied(nation_id, other.id)
			or _frontier_edges(state, nation_id, other.id) <= 0
		):
			continue
		if _coalition_power(state, other.id) >= own_power * 0.75:
			return FoodPosture.GUARDED
	return FoodPosture.PEACE


static func war_food_report(
	state: GameState,
	nation_id: int,
	target_troops: int = -1,
	posture: int = -1
) -> Dictionary:
	var nation := state.nations[nation_id]
	var current_troops := _troop_count(state, nation_id)
	if target_troops < 0:
		target_troops = current_troops
	if posture < 0:
		posture = food_posture(state, nation_id)
	var monthly_production := 0.0
	for city in state.cities_of(nation_id):
		monthly_production += (
			float(Simulation.city_food_output(state, city))
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
	var full_strength_troops := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			full_strength_troops += army.max_size
	var full_strength_monthly_demand := (
		float(full_strength_troops) * food_per_troop
	)
	var annual_production := monthly_production * float(MONTHS_PER_YEAR)
	var current_annual_demand := current_monthly_demand * float(MONTHS_PER_YEAR)
	var target_annual_demand := target_monthly_demand * float(MONTHS_PER_YEAR)
	var full_strength_annual_demand := (
		full_strength_monthly_demand * float(MONTHS_PER_YEAR)
	)
	var stock := float(_food_stock(state, nation_id))
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
	return {
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
	target_id: int
) -> int:
	var current := _troop_count(state, nation_id)
	var enemy := _troop_count(state, target_id)
	var desired := maxi(current, int(ceil(float(enemy) * 1.10)))
	var available := current + maxi(
		state.nations[nation_id].manpower_pool - MIN_MANPOWER_RESERVE,
		0
	)
	return mini(
		desired,
		mini(available, current + MAX_MOBILIZATION_ARMIES * MOBILIZATION_ARMY_SIZE)
	)


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
				and edge.max_throughput > 0
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
			+ _target_cut_ratio(state, city.id, target_id) * 4.0
		)
		var value := gold_value + food_value + manpower_value + strategic_value
		if (
			best.is_empty()
			or value > float(best["value"])
			or (
				is_equal_approx(value, float(best["value"]))
				and city.id < int(best["city_id"])
			)
		):
			best = {
				"city_id": city.id,
				"value": value,
				"reason": (
					"城市%d%s（金%d/月、粮%d/半年、人%d/月、战略值%.2f）"
					% [
						city.id,
						(
							"【粮食核心】" if city.is_food_hub else ""
						) + (
							"【人口核心】" if city.is_manpower_hub else ""
						),
						city.gold_per_month,
						city.food_per_half_year,
						city.manpower_per_month,
						strategic_value,
					]
				),
			}
	return best


static func leave_alliance_desire(state: GameState, nation_id: int, ally_id: int) -> float:
	if not state.is_allied(nation_id, ally_id) or nation_id == ally_id:
		return -INF
	if state.day - state.relation_since(nation_id, ally_id) < MIN_ALLIANCE_DAYS:
		return -INF
	var common_enemies := _common_enemy_count(state, nation_id, ally_id)
	var own_power := _national_power(state, nation_id)
	var ally_power := _national_power(state, ally_id)
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
	return (
		domination_risk
		+ float(conflicting_commitments) * 1.5
		+ float(unilateral_wars) * 0.20
		- float(common_enemies) * 0.75
		- established_trust
	)


static func _collect_peace_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary
) -> void:
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if committed.has(a) or committed.has(b) or not state.is_enemy(a, b):
				continue
			var war_days := state.day - state.relation_since(a, b)
			if war_days < MIN_WAR_DAYS:
				continue
			var score_a := peace_willingness(state, a, b)
			var score_b := peace_willingness(state, b, a)
			if (
				war_days < FORCED_PEACE_DAYS
				and (score_a < PEACE_ACCEPT_SCORE or score_b < PEACE_ACCEPT_SCORE)
			):
				continue
			var reasons_a := peace_reasons(state, a, b)
			var reasons_b := peace_reasons(state, b, a)
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
			actions.append({
				"kind": Action.MAKE_PEACE,
				"a": a,
				"b": b,
				"score": minf(score_a, score_b),
				"reason": "战争持续%d天；国%d：%s；国%d：%s；意愿%.2f/%.2f" % [
					war_days, a, reason_a, b, reason_b, score_a, score_b,
				],
			})
			committed[a] = true
			committed[b] = true


static func _collect_leave_alliance_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary
) -> void:
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if committed.has(a) or committed.has(b) or not state.is_allied(a, b):
				continue
			var score_a := leave_alliance_desire(state, a, b)
			var score_b := leave_alliance_desire(state, b, a)
			var actor := a if score_a >= score_b else b
			var score := maxf(score_a, score_b)
			if score < LEAVE_ALLIANCE_SCORE:
				continue
			actions.append({
				"kind": Action.LEAVE_ALLIANCE,
				"a": actor,
				"b": b if actor == a else a,
				"score": score,
				"reason": "防御条约负担、外交冲突或力量失衡，退盟收益 %.2f" % score,
			})
			committed[a] = true
			committed[b] = true


static func _collect_alliance_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary
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
			var score_a := alliance_willingness(state, a, b)
			var score_b := alliance_willingness(state, b, a)
			if score_a < ALLIANCE_ACCEPT_SCORE or score_b < ALLIANCE_ACCEPT_SCORE:
				continue
			actions.append({
				"kind": Action.FORM_ALLIANCE,
				"a": a,
				"b": b,
				"score": minf(score_a, score_b),
				"reason": "缔结长期共同防御与军事通行条约，双方意愿 %.2f/%.2f"
					% [score_a, score_b],
			})
			committed[a] = true
			committed[b] = true


static func _collect_war_actions(
	state: GameState,
	actions: Array[Dictionary],
	committed: Dictionary
) -> void:
	for nation in state.nations:
		if committed.has(nation.id) or not nation.alive:
			continue
		if nation.war_preparation_target_nation >= 0:
			_collect_existing_war_preparation(state, nation.id, actions, committed)
			continue
		var best_target := -1
		var best_score := -INF
		for target in state.nations:
			if target.id == nation.id or committed.has(target.id) or not target.alive:
				continue
			var score := war_desire(state, nation.id, target.id)
			if score > best_score or (
				is_equal_approx(score, best_score)
				and (best_target == -1 or target.id < best_target)
			):
				best_score = score
				best_target = target.id
		if best_target == -1 or best_score < WAR_DECLARE_SCORE:
			continue
		var objective := select_war_objective(state, nation.id, best_target)
		var report := resource_report(state, nation.id)
		if objective.is_empty() or not bool(report["ready"]):
			continue
		var mobilization_armies := mobilization_capacity(state, nation.id)
		var campaign_troops := (
			int(report["troops"])
			+ mobilization_armies * MOBILIZATION_ARMY_SIZE
		)
		var food_plan := war_food_report(
			state,
			nation.id,
			campaign_troops,
			FoodPosture.OFFENSIVE_WAR
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
					mobilization_armies,
					best_score,
				]
			),
		})
		committed[nation.id] = true
		committed[best_target] = true


static func _collect_existing_war_preparation(
	state: GameState,
	nation_id: int,
	actions: Array[Dictionary],
	committed: Dictionary
) -> void:
	var nation := state.nations[nation_id]
	var target_id := nation.war_preparation_target_nation
	var objective_city := nation.war_preparation_objective_city
	var valid := (
		target_id >= 0
		and target_id < state.nations.size()
		and state.nations[target_id].alive
		and state.can_declare_war(nation_id, target_id)
		and objective_city >= 0
		and objective_city < state.cities.size()
		and state.cities[objective_city].owner_nation == target_id
	)
	var elapsed := state.day - nation.war_preparation_started_day
	if (
		not valid
		or elapsed > WAR_PREPARATION_MAX_DAYS
		or not bool(resource_report(state, nation_id)["ready"])
	):
		actions.append({
			"kind": Action.CANCEL_WAR_PREPARATION,
			"a": nation_id,
			"b": target_id,
			"reason": "战争条件变化或集结超时，取消对国%d的战争准备" % target_id,
		})
		committed[nation_id] = true
		return
	if not war_preparation_ready(state, nation_id):
		committed[nation_id] = true
		return
	var mobilization_armies := maxi(
		int(ceil(
			float(
				nation.war_mobilization_target_troops
				- _troop_count(state, nation_id)
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
	committed[nation_id] = true
	committed[target_id] = true


static func war_preparation_ready(state: GameState, nation_id: int) -> bool:
	var nation := state.nations[nation_id]
	if (
		nation.war_preparation_target_nation < 0
		or nation.war_preparation_objective_city < 0
		or state.day - nation.war_preparation_started_day
			< WAR_PREPARATION_MIN_DAYS
	):
		return false
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
	for neighbor in state.neighbors(objective_city):
		var edge := state.edge_of(neighbor, objective_city)
		if (
			edge != null
			and edge.max_throughput > 0
			and state.has_military_access(
				nation_id, state.cities[neighbor].owner_nation
			)
		):
			result.append(neighbor)
	result.sort()
	return result


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
	var siege_requirement := int(ceil(
		float(maxi(defenders, state.cities[objective_city].defense))
			* Combat.SIEGE_RATIO_MIN
			* UtilityAI.SIEGE_COMMIT_MARGIN
	))
	return maxi(
		siege_requirement,
		int(ceil(float(_troop_count(state, nation_id)) * WAR_PREPARATION_FORCE_SHARE))
	)


static func _national_power(state: GameState, nation_id: int) -> float:
	var power := 0.0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			power += ArmyPower.effective(army)
	return power + float(state.cities_of(nation_id).size()) * 1500.0


static func _troop_count(state: GameState, nation_id: int) -> int:
	var total := 0
	for army in state.armies:
		if army.owner_nation == nation_id and army.size > 0:
			total += army.size
	return total


static func _food_stock(state: GameState, nation_id: int) -> int:
	var total := 0
	for warehouse in state.warehouse_cities_of(nation_id):
		total += warehouse.food_storage
	return total


static func _target_cut_ratio(
	state: GameState,
	target_city: int,
	target_nation: int
) -> float:
	var capital := state.nations[target_nation].capital_city_id
	if capital < 0 or capital == target_city:
		return 0.0
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
				or edge.max_throughput <= 0
				or state.cities[neighbor].owner_nation != target_nation
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
	return float(cut) / float(maxi(total, 1))


static func _coalition_power(state: GameState, nation_id: int) -> float:
	var power := _national_power(state, nation_id)
	for ally_id in state.allies_of(nation_id):
		power += _national_power(state, ally_id) * 0.75
	return power


static func _common_enemy_count(state: GameState, nation_a: int, nation_b: int) -> int:
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
	return count


static func _alliance_has_active_conflict(
	state: GameState,
	nation_a: int,
	nation_b: int
) -> bool:
	for enemy_id in state.wars_of(nation_a):
		if state.is_allied(nation_b, enemy_id):
			return true
	for enemy_id in state.wars_of(nation_b):
		if state.is_allied(nation_a, enemy_id):
			return true
	return false


static func _has_shared_ally(state: GameState, nation_a: int, nation_b: int) -> bool:
	for other in state.nations:
		if (
			other.id != nation_a
			and other.id != nation_b
			and state.is_allied(nation_a, other.id)
			and state.is_allied(nation_b, other.id)
		):
			return true
	return false


static func _frontier_edges(state: GameState, nation_a: int, nation_b: int) -> int:
	var count := 0
	for edge in state.edges:
		if edge.max_throughput <= 0:
			continue
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if (
			(
				state.has_military_access(nation_a, owner_a)
				and owner_b == nation_b
			)
			or (
				state.has_military_access(nation_a, owner_b)
				and owner_a == nation_b
			)
		):
			count += 1
	return count
