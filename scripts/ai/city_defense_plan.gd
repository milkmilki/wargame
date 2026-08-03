class_name CityDefensePlan
extends RefCounted
## 国家级城市防御规划：城市是目标，驻城与驻边是可替换的部署手段。

enum Posture {
	NONE,
	CITY,
	EDGE,
}

const RESPONSE_PRESSURE_FLOOR: float = 1000.0
const REQUIRED_PRESSURE_SHARE: float = 0.65
const FRONTIER_SCREEN_POWER: float = 1000.0
const STRATEGIC_CITY_VALUE_FLOOR: float = 3.0
const MUST_HOLD_CITY_VALUE_FLOOR: float = 5.0
const EDGE_DEFENSE_MIN_POWER_RATIO: float = 0.40
const EDGE_SWITCH_PRESSURE_RATIO: float = 1.25
const STRATEGIC_COMMIT_DAYS: int = 30

var view: AiWorldView
var snapshot: StrategicMapSnapshot
var threat: ThreatField
var required_power: Dictionary = {}       ## city_id -> float
var posture_by_city: Dictionary = {}      ## city_id -> Posture
var preferred_edge_by_city: Dictionary = {} ## city_id -> neighbor_id
var directional_pressure: Dictionary = {} ## city_id -> {neighbor_id -> float}
var relief_need: Dictionary = {}          ## city_id -> float
var local_pressure: Dictionary = {}       ## city_id -> float
var must_hold_cities: Dictionary = {}     ## city_id -> true
var frontline_distribution_enabled: bool = false
var primary_frontline_cities: Dictionary = {}
var frontline_cities: Dictionary = {}
var frontline_allocation: Dictionary = {}


static func build(
	world_view: AiWorldView,
	strategic_snapshot: StrategicMapSnapshot,
	threat_field: ThreatField
) -> CityDefensePlan:
	var plan := CityDefensePlan.new()
	plan.view = world_view
	plan.snapshot = strategic_snapshot
	plan.threat = threat_field
	plan._build()
	return plan


func candidate_for(
	army: Army,
	coordinator: ArmyCoordinator
) -> ActionCandidate:
	if army == null or army.size <= 0:
		return null
	var candidate: ActionCandidate = null
	if army.state == Army.State.HOLDING:
		candidate = _holding_candidate(army, coordinator)
	elif army.state == Army.State.IDLE and army.location_city >= 0:
		candidate = _idle_candidate(army, coordinator)
	else:
		return null
	if (
		candidate != null
		and candidate.defensive_deployment
		and view.day < army.defensive_deployment_until_day
		and (
			_is_reverse_to_blocked_edge(
				army,
				candidate
			)
			or not urgent_defense_at(
				_candidate_anchor_city(candidate)
			)
		)
	):
		return null
	return candidate


func requirement_at(city_id: int) -> float:
	return float(required_power.get(city_id, 0.0))


func posture_at(city_id: int) -> int:
	return int(posture_by_city.get(city_id, Posture.NONE))


func preferred_edge_at(city_id: int) -> int:
	return int(preferred_edge_by_city.get(city_id, -1))


func must_hold_city(city_id: int) -> bool:
	return bool(must_hold_cities.get(city_id, false))


func must_keep_at_city(
	army: Army,
	coordinator: ArmyCoordinator
) -> bool:
	if (
		army == null
		or army.state != Army.State.IDLE
		or not must_hold_city(army.location_city)
	):
		return false
	var city_id := army.location_city
	var coverage_without := _city_coverage(
		city_id,
		coordinator,
		army
	)
	if (
		posture_at(city_id) == Posture.EDGE
		and preferred_edge_at(city_id) >= 0
	):
		coverage_without += (
			coordinator.edge_defense_power_reserved(
				city_id,
				preferred_edge_at(city_id)
			)
		)
	return coverage_without < requirement_at(city_id)


func can_redeploy(
	army: Army,
	coordinator: ArmyCoordinator
) -> bool:
	if (
		army == null
		or army.size <= 0
		or view.day < army.defensive_deployment_until_day
	):
		return false
	if army.state == Army.State.IDLE:
		var city_id := army.location_city
		if not required_power.has(city_id):
			return true
		var coverage_without := _city_coverage(
			city_id,
			coordinator,
			army
		)
		if (
			posture_at(city_id) == Posture.EDGE
			and preferred_edge_at(city_id) >= 0
		):
			coverage_without += (
				coordinator.edge_defense_power_reserved(
					city_id,
					preferred_edge_at(city_id)
				)
			)
		return coverage_without >= requirement_at(city_id)
	if army.state == Army.State.HOLDING:
		var anchor := army.move_from
		if not view.state.has_military_access(
			view.nation_id,
			view.state.cities[anchor].owner_nation
		):
			anchor = army.move_to
		return not required_power.has(anchor)
	return false


func _candidate_anchor_city(
	candidate: ActionCandidate
) -> int:
	if (
		candidate.kind == ActionCandidate.Kind.HOLD
		and candidate.target_edge_a >= 0
	):
		return candidate.target_edge_a
	return candidate.target_city


func _is_reverse_to_blocked_edge(
	army: Army,
	candidate: ActionCandidate
) -> bool:
	if (
		candidate.kind != ActionCandidate.Kind.HOLD
		or candidate.target_edge_a < 0
		or candidate.target_edge_b < 0
		or army.defensive_blocked_edge_a < 0
		or army.defensive_blocked_edge_b < 0
	):
		return false
	return (
		mini(
			candidate.target_edge_a,
			candidate.target_edge_b
		) == army.defensive_blocked_edge_a
		and maxi(
			candidate.target_edge_a,
			candidate.target_edge_b
		) == army.defensive_blocked_edge_b
	)


func urgent_defense_at(city_id: int) -> bool:
	if city_id < 0 or city_id >= view.state.cities.size():
		return false
	if (
		float(local_pressure.get(city_id, 0.0)) > 0.0
		or float(relief_need.get(city_id, 0.0)) > 0.0
	):
		return true
	for enemy in view.enemy_armies:
		if enemy.size <= 0:
			continue
		if (
			not enemy.on_edge
			and enemy.location_city == city_id
		):
			return true
		if (
			enemy.on_edge
			and enemy.move_to != -1
			and (
				enemy.move_from == city_id
				or enemy.move_to == city_id
			)
		):
			return true
		if not enemy.on_edge and enemy.location_city >= 0:
			var approach_edge := view.state.edge_of(
				city_id,
				enemy.location_city
			)
			if (
				approach_edge != null
				and approach_edge.max_manpower
					>= enemy.max_size
			):
				return true
	return false


func _build() -> void:
	var national_power := 0.0
	for army in view.friendly_armies:
		national_power += ArmyPower.effective(army)
	for city_id in snapshot.frontier_cities:
		primary_frontline_cities[city_id] = true
	for city_id in snapshot.potential_frontier_cities:
		primary_frontline_cities[city_id] = true
	frontline_cities = primary_frontline_cities.duplicate()
	var primary_frontline_ids := frontline_cities.keys()
	EquivariantOrder.sort_city_ids(
		primary_frontline_ids,
		view.state,
		view.nation_id
	)
	for city_id_value in primary_frontline_ids:
		var city_id := int(city_id_value)
		for neighbor in view.state.neighbors(city_id):
			if (
				view.state.cities[neighbor].owner_nation
				== view.nation_id
			):
				frontline_cities[neighbor] = true
	frontline_distribution_enabled = (
		not frontline_cities.is_empty()
		and view.friendly_armies.size()
			>= primary_frontline_cities.size()
	)
	for city in view.friendly_cities:
		var pressures := _directional_pressure_at(city.id)
		var direct_pressure := _enemy_power_inside(city.id)
		var relief := UtilityAI._friendly_relief_need(view, city.id)
		var logistics := UtilityAI.required_logistics_garrison(
			view,
			snapshot,
			threat,
			city.id
		)
		var pressure_total := direct_pressure
		var active_directions: Array[int] = []
		var strongest_direction := -1
		var strongest_pressure := 0.0
		var strongest_edge_value := -INF
		var equally_best_directions := 0
		var direction_ids := pressures.keys()
		EquivariantOrder.sort_city_ids(
			direction_ids,
			view.state,
			view.nation_id,
			city.id
		)
		for direction_id in direction_ids:
			var pressure := float(pressures[direction_id])
			var edge_value := snapshot.value_of_edge(
				city.id,
				int(direction_id)
			)
			if pressure > RESPONSE_PRESSURE_FLOOR + 0.001:
				active_directions.append(int(direction_id))
			var better_pressure := pressure > strongest_pressure
			var equal_pressure := is_equal_approx(
				pressure,
				strongest_pressure
			)
			var better_edge := (
				equal_pressure
				and edge_value > strongest_edge_value
			)
			if better_pressure or better_edge:
				strongest_pressure = pressure
				strongest_edge_value = edge_value
				strongest_direction = int(direction_id)
				equally_best_directions = 1
			elif (
				equal_pressure
				and is_equal_approx(
					edge_value,
					strongest_edge_value
				)
			):
				equally_best_directions += 1
				if (
					strongest_direction == -1
					or int(direction_id)
						< strongest_direction
				):
					strongest_direction = int(direction_id)
		if active_directions.is_empty():
			pressure_total += strongest_pressure
		else:
			for direction_id in active_directions:
				pressure_total += float(pressures[direction_id])
		var required := maxf(
			maxf(
				pressure_total * REQUIRED_PRESSURE_SHARE,
				relief
			),
			logistics
		)
		var is_must_hold := (
			pressure_total > 0.0
			and _is_strategic_must_hold_city(city.id)
		)
		if is_must_hold:
			must_hold_cities[city.id] = true
			required = maxf(required, pressure_total)
		if required <= 0.0:
			continue
		required_power[city.id] = required
		directional_pressure[city.id] = pressures
		relief_need[city.id] = relief
		local_pressure[city.id] = direct_pressure
		var edge_defense_understrength := (
			is_must_hold
			and strongest_pressure > 0.0
			and _friendly_local_power(city.id)
				< strongest_pressure
					* EDGE_DEFENSE_MIN_POWER_RATIO
		)
		if (
			direct_pressure > 0.0
			or relief > 0.0
			or edge_defense_understrength
			or active_directions.size() > 1
			or strongest_direction == -1
			or equally_best_directions > 1
		):
			posture_by_city[city.id] = Posture.CITY
		else:
			posture_by_city[city.id] = Posture.EDGE
			preferred_edge_by_city[city.id] = strongest_direction
	_normalize_frontline_requirements(national_power)


func _normalize_frontline_requirements(
	national_power: float
) -> void:
	if (
		not frontline_distribution_enabled
		or national_power <= 0.0
	):
		return
	var importance_raw := {}
	var danger_raw := {}
	var importance_total := 0.0
	var danger_total := 0.0
	var danger_square_total := 0.0
	var city_ids := frontline_cities.keys()
	EquivariantOrder.sort_city_ids(
		city_ids,
		view.state,
		view.nation_id
	)
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		var importance := maxf(
			snapshot.value_of_city(city_id),
			0.01
		) * (
			1.0 + snapshot.supply_importance_at(city_id)
		)
		var danger := maxf(
			threat.threat_at(city_id),
			snapshot.potential_threat_at(city_id)
		)
		var pressures: Dictionary = directional_pressure.get(
			city_id,
			{}
		)
		for pressure in pressures.values():
			danger += float(pressure)
		# 二线的微小背景威胁不能屏蔽相邻一线的高压信号。始终取本地危险
		# 与按响应时间衰减的一线危险最大值，使预备队自然分布在可及时回援的纵深。
		for neighbor in view.state.neighbors(city_id):
			if not primary_frontline_cities.has(neighbor):
				continue
			var edge := view.state.edge_of(city_id, neighbor)
			if edge == null:
				continue
			var neighbor_danger := maxf(
				threat.threat_at(neighbor),
				snapshot.potential_threat_at(neighbor)
			)
			danger = maxf(
				danger,
				neighbor_danger * exp(
					-_edge_travel_days(edge)
						/ ThreatField.DECAY_DAYS
				)
			)
		if (
			danger <= 0.0
			and primary_frontline_cities.has(city_id)
		):
			danger = FRONTIER_SCREEN_POWER
		importance_raw[city_id] = importance
		danger_raw[city_id] = danger
		importance_total += importance
		danger_total += danger
		danger_square_total += danger * danger
	if importance_total <= 0.0 or danger_total <= 0.0:
		return
	var combined_weights := {}
	var combined_total := 0.0
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		var combined := sqrt(
			float(importance_raw.get(city_id, 0.0))
				/ importance_total
			* float(danger_raw.get(city_id, 0.0))
				/ danger_total
		)
		combined_weights[city_id] = combined
		combined_total += combined
	if combined_total <= 0.0:
		return
	var not_at_war := view.state.wars_of(
		view.nation_id
	).is_empty()
	var aggregate_threat := sqrt(danger_square_total)
	if not_at_war:
		aggregate_threat = minf(
			aggregate_threat,
			national_power
		)
	var defense_budget := (
		national_power * aggregate_threat
		/ maxf(national_power + aggregate_threat, 1.0)
	)
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		var allocation := (
			defense_budget
			* float(combined_weights[city_id])
			/ combined_total
		)
		frontline_allocation[city_id] = allocation
		if not_at_war:
			required_power[city_id] = allocation
		else:
			required_power[city_id] = maxf(
				requirement_at(city_id),
				allocation
			)
		if not posture_by_city.has(city_id):
			posture_by_city[city_id] = Posture.CITY


func _friendly_local_power(city_id: int) -> float:
	var total := UtilityAI.stationed_power_at(
		view,
		city_id
	)
	for army in view.friendly_armies:
		if (
			army.size <= 0
			or army.state != Army.State.HOLDING
			or not army.on_edge
			or army.move_to == -1
			or (
				army.move_from != city_id
				and army.move_to != city_id
			)
		):
			continue
		total += ArmyPower.effective(army)
	return total


func _is_strategic_must_hold_city(city_id: int) -> bool:
	var city := view.state.cities[city_id]
	return (
		city_id == view.capital_city_id
		or city.has_warehouse
		or city.is_food_hub
		or city.is_manpower_hub
		or snapshot.critical_supply_cities.has(city_id)
		or snapshot.value_of_city(city_id)
			>= MUST_HOLD_CITY_VALUE_FLOOR
	)


func _directional_pressure_at(city_id: int) -> Dictionary:
	var result := {}
	var potential_neighbors: Array[int] = []
	for neighbor in view.state.neighbors(city_id):
		var edge := view.state.edge_of(city_id, neighbor)
		if (
			edge != null
			and edge.max_manpower > 0
			and snapshot.potential_threat_of_edge(
				city_id,
				neighbor
			) > 0.0
		):
			potential_neighbors.append(neighbor)
	var potential_share := (
		snapshot.potential_threat_at(city_id)
		/ float(maxi(potential_neighbors.size(), 1))
	)
	for neighbor in view.state.neighbors(city_id):
		var edge := view.state.edge_of(city_id, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		var owner := view.state.cities[neighbor].owner_nation
		var pressure := 0.0
		if (
			view.state.is_enemy(view.nation_id, owner)
			and _requires_frontier_screen(city_id)
		):
			pressure = FRONTIER_SCREEN_POWER
		elif potential_neighbors.has(neighbor):
			pressure = potential_share
		for enemy in view.enemy_armies:
			var power := ArmyPower.effective(enemy)
			if power <= 0.0:
				continue
			if enemy.on_edge and enemy.move_to != -1:
				if (
					mini(enemy.move_from, enemy.move_to)
						!= mini(city_id, neighbor)
					or maxi(enemy.move_from, enemy.move_to)
						!= maxi(city_id, neighbor)
				):
					continue
				if enemy.state == Army.State.HOLDING:
					pressure += power
				elif enemy.move_to == city_id:
					var remaining_days := (
						1.0
						- clampf(
							enemy.move_progress,
							0.0,
							1.0
						)
					) * _edge_travel_days(edge)
					pressure += power * exp(
						-remaining_days
							/ ThreatField.DECAY_DAYS
					)
				continue
			if enemy.location_city != neighbor:
				continue
			if edge.max_manpower < enemy.max_size:
				continue
			pressure += power * exp(
				-_edge_travel_days(edge)
					/ ThreatField.DECAY_DAYS
			)
		if pressure > 0.0:
			result[neighbor] = pressure
	return result


func _requires_frontier_screen(city_id: int) -> bool:
	if frontline_distribution_enabled:
		return snapshot.frontier_cities.has(city_id)
	var city := view.state.cities[city_id]
	return (
		city_id == view.capital_city_id
		or city.has_warehouse
		or city.is_food_hub
		or city.is_manpower_hub
		or snapshot.critical_supply_cities.has(city_id)
		or snapshot.value_of_city(city_id)
			>= STRATEGIC_CITY_VALUE_FLOOR
	)


func _enemy_power_inside(city_id: int) -> float:
	var result := 0.0
	for enemy in view.enemy_armies:
		if (
			not enemy.on_edge
			and enemy.location_city == city_id
		):
			result += ArmyPower.effective(enemy)
	return result


func _holding_candidate(
	army: Army,
	coordinator: ArmyCoordinator
) -> ActionCandidate:
	var friendly_city := army.move_from
	if (
		friendly_city < 0
		or friendly_city >= view.state.cities.size()
		or view.state.cities[friendly_city].owner_nation
			!= view.nation_id
	):
		friendly_city = army.move_to
	if not required_power.has(friendly_city):
		return null
	var other_endpoint := (
		army.move_to
		if friendly_city == army.move_from
		else army.move_from
	)
	var posture := posture_at(friendly_city)
	var preferred_edge := preferred_edge_at(friendly_city)
	if posture == Posture.EDGE:
		var pressures: Dictionary = directional_pressure.get(
			friendly_city,
			{}
		)
		var current_pressure := float(
			pressures.get(other_endpoint, 0.0)
		)
		var preferred_pressure := float(
			pressures.get(preferred_edge, 0.0)
		)
		if (
			preferred_edge == other_endpoint
				or current_pressure
					* EDGE_SWITCH_PRESSURE_RATIO
					>= preferred_pressure
		):
			return null
	var coverage := _city_coverage(
		friendly_city,
		coordinator
	)
	if posture == Posture.EDGE and preferred_edge >= 0:
		coverage += coordinator.edge_defense_power_reserved(
			friendly_city,
			preferred_edge
		)
	var deficit := requirement_at(friendly_city) - coverage
	if deficit <= 0.0:
		return null
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.RETREAT,
		_defense_score(friendly_city, deficit),
		(
			"城市 %d 面临集中进攻，驻边军回城填补 %.0f 战力缺口"
			% [friendly_city, deficit]
		),
		friendly_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	candidate.defensive_deployment = true
	candidate.target_edge_a = friendly_city
	candidate.target_edge_b = other_endpoint
	return candidate


func _idle_candidate(
	army: Army,
	coordinator: ArmyCoordinator
) -> ActionCandidate:
	var start := army.location_city
	var own_power := ArmyPower.effective(army)
	if required_power.has(start):
		var coverage_without_army := (
			_city_coverage(start, coordinator, army)
		)
		var posture := posture_at(start)
		var preferred_edge := preferred_edge_at(start)
		if posture == Posture.EDGE and preferred_edge >= 0:
			coverage_without_army += (
				coordinator.edge_defense_power_reserved(
					start,
					preferred_edge
				)
			)
			if (
				requirement_at(start) > coverage_without_army
				and coordinator.edge_defense_power_reserved(
					start,
					preferred_edge
				) < requirement_at(start)
			):
				return _edge_hold_candidate(
					army,
					start,
					preferred_edge
				)
		elif requirement_at(start) > coverage_without_army:
			return ActionCandidate.make(
				ActionCandidate.Kind.NONE,
				_defense_score(
					start,
					requirement_at(start)
						- coverage_without_army
				),
				"城市 %d 面临多方向威胁，保留驻城预备队"
					% start,
				start
			)

	var field := view.path_field(
		start,
		view.nation_id,
		false,
		true,
		-1,
		army.max_size
	)
	var dist: Dictionary = field["dist"]
	var best_city := -1
	var best_deficit := 0.0
	var best_score := -INF
	var city_ids := required_power.keys()
	EquivariantOrder.sort_city_ids(
		city_ids,
		view.state,
		view.nation_id,
		start
	)
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		if float(dist.get(city_id, INF)) == INF:
			continue
		var deficit := (
			requirement_at(city_id)
			- _effective_coverage(city_id, coordinator)
		)
		if deficit <= 0.0:
			continue
		if (
			snapshot.supply_importance_at(city_id)
				>= UtilityAI.SUPPLY_CORRIDOR_MIN_IMPORTANCE
			and own_power
				> UtilityAI.SUPPLY_CORRIDOR_RESPONSE_MAX_POWER
			and not snapshot.frontier_cities.has(city_id)
		):
			continue
		var score := (
			_defense_score(city_id, deficit)
			- 0.06 * float(dist[city_id])
		)
		if (
			score > best_score
			or (
				is_equal_approx(score, best_score)
				and EquivariantOrder.city_id_less(
					view.state,
					view.nation_id,
					city_id,
					best_city,
					start
				)
			)
		):
			best_score = score
			best_city = city_id
			best_deficit = deficit
	if best_city == -1:
		return _frontline_balance_candidate(
			army,
			coordinator,
			dist
		)
	if best_city == start:
		if (
			posture_at(best_city) == Posture.EDGE
			and preferred_edge_at(best_city) >= 0
		):
			return _edge_hold_candidate(
				army,
				best_city,
				preferred_edge_at(best_city)
			)
		return ActionCandidate.make(
			ActionCandidate.Kind.NONE,
			best_score,
			"留守重点城市 %d，守备缺口 %.0f"
				% [best_city, best_deficit],
			best_city
		)
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		best_score,
		_defense_reason(best_city, best_deficit),
		best_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	candidate.defensive_deployment = true
	return candidate


func _frontline_balance_candidate(
	army: Army,
	coordinator: ArmyCoordinator,
	dist: Dictionary
) -> ActionCandidate:
	if (
		not frontline_distribution_enabled
		or not view.state.wars_of(view.nation_id).is_empty()
		or view.state.nations[
			view.nation_id
		].war_preparation_target_nation >= 0
	):
		return null
	var source_target := float(
		frontline_allocation.get(
			army.location_city,
			0.0
		)
	)
	var source_after_move := 0.0
	var source_ratio_before := 0.0
	if frontline_cities.has(army.location_city):
		var source_coverage := _effective_coverage(
			army.location_city,
			coordinator
		)
		source_after_move = (
			source_coverage - ArmyPower.effective(army)
		)
		if (
			source_after_move
			< source_target * 1.10
		):
			return null
		source_ratio_before = (
			source_coverage / maxf(source_target, 1.0)
		)
	var best_city := -1
	var best_score := -INF
	var city_ids := frontline_cities.keys()
	EquivariantOrder.sort_city_ids(
		city_ids,
		view.state,
		view.nation_id,
		army.location_city
	)
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		if (
			city_id == army.location_city
			or float(dist.get(city_id, INF)) == INF
		):
			continue
		var coverage := _effective_coverage(
			city_id,
			coordinator
		)
		var target_power := float(
			frontline_allocation.get(city_id, 0.0)
		)
		if target_power <= 0.0:
			continue
		var target_ratio := coverage / target_power
		var below_target_band := target_ratio < 0.75
		var saturation_gap := source_ratio_before - target_ratio
		if (
			not below_target_band
			and (
				source_target <= 0.0
				or source_ratio_before
					< target_ratio * EDGE_SWITCH_PRESSURE_RATIO
			)
		):
			continue
		var normalized_need := maxf(
			1.0 - target_ratio,
			saturation_gap
		)
		if normalized_need <= 0.0:
			continue
		var score := (
			20.0
			+ 5.0 * normalized_need
			- 0.05 * float(dist[city_id])
		)
		if (
			score > best_score
			or (
				is_equal_approx(score, best_score)
				and (
					EquivariantOrder.city_id_less(
						view.state,
						view.nation_id,
						city_id,
						best_city,
						army.location_city
					)
				)
			)
		):
			best_score = score
			best_city = city_id
	if best_city < 0:
		return null
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		best_score,
		"前线防区机动预备队向低覆盖城市 %d 展开"
			% best_city,
		best_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	candidate.defensive_deployment = true
	return candidate


func _edge_hold_candidate(
	army: Army,
	city_id: int,
	neighbor: int
) -> ActionCandidate:
	var saved_food := Simulation.city_garrison_food_loss(
		view.state,
		view.state.cities[city_id],
		army.size
	)
	var score := (
		_defense_score(
			city_id,
			requirement_at(city_id)
		)
		+ snapshot.value_of_edge(city_id, neighbor)
		+ float(saved_food) * 0.05
	)
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.HOLD,
		score,
		(
			"城市 %d 仅受 %d 方向威胁，驻边拦截并避免 %d 粮食减产"
			% [city_id, neighbor, saved_food]
		),
		neighbor
	)
	candidate.target_edge_a = city_id
	candidate.target_edge_b = neighbor
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	candidate.defensive_deployment = true
	return candidate


func _city_coverage(
	city_id: int,
	coordinator: ArmyCoordinator,
	excluded: Army = null
) -> float:
	return (
		UtilityAI.stationed_power_at(
			view,
			city_id,
			excluded
		)
		+ coordinator.city_defense_power_reserved(city_id)
		+ ArmyPower.city_defense(
			view.state.cities[city_id]
		)
	)


func _effective_coverage(
	city_id: int,
	coordinator: ArmyCoordinator
) -> float:
	var result := _city_coverage(city_id, coordinator)
	if posture_at(city_id) == Posture.EDGE:
		var preferred_edge := preferred_edge_at(city_id)
		if preferred_edge >= 0:
			result += coordinator.edge_defense_power_reserved(
				city_id,
				preferred_edge
			)
	return result


func _defense_score(city_id: int, deficit: float) -> float:
	var required := requirement_at(city_id)
	var score := (
		30.0
		+ 12.0 * deficit / maxf(required, 1.0)
		+ 2.0 * snapshot.value_of_city(city_id)
	)
	if float(relief_need.get(city_id, 0.0)) > 0.0:
		score += 100.0
	var city := view.state.cities[city_id]
	if city_id == view.capital_city_id:
		score += 50.0
	elif city.has_warehouse:
		score += 40.0
	if (
		snapshot.supply_importance_at(city_id)
			>= UtilityAI.SUPPLY_CORRIDOR_MIN_IMPORTANCE
		and not snapshot.frontier_cities.has(city_id)
	):
		score += 20.0
	return score


func _defense_reason(
	city_id: int,
	deficit: float
) -> String:
	if float(relief_need.get(city_id, 0.0)) > 0.0:
		return "紧急解围城市 %d，守备缺口 %.0f" % [
			city_id,
			deficit,
		]
	if (
		snapshot.supply_importance_at(city_id)
			>= UtilityAI.SUPPLY_CORRIDOR_MIN_IMPORTANCE
		and not snapshot.frontier_cities.has(city_id)
	):
		return "唯一粮道节点 %d 面临截断风险，增援保护补给线" % city_id
	if snapshot.potential_frontier_cities.has(city_id):
		return "高威胁中立国边境城市 %d 存在守备缺口" % city_id
	return "重点城市 %d 存在守备缺口 %.0f" % [
		city_id,
		deficit,
	]


static func _edge_travel_days(edge: Edge) -> float:
	return clampf(
		10.0 + float(maxi(edge.distance, 1) - 1) * 5.0,
		10.0,
		30.0
	)
