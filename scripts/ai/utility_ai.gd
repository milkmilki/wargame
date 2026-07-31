class_name UtilityAI
extends RefCounted
## 无训练 Utility AI：生成可解释候选行动并选择最高分。

const ATTACK_ENTER_RATIO: float = 1.35
const RETREAT_ENTER_RATIO: float = 0.40
const HOLD_DEPLOY_ENTER_RATIO: float = 0.60
const EMERGENCY_RETREAT_RATIO: float = 0.25
const SIEGE_COMMIT_MARGIN: float = 1.50
const SUPPLY_CORRIDOR_MIN_IMPORTANCE: float = 0.50
const SUPPLY_CORRIDOR_THREAT_FLOOR: float = 250.0
const SUPPLY_CORRIDOR_GARRISON_BASE: float = 1000.0
const SUPPLY_CORRIDOR_GARRISON_SCALE: float = 2000.0
const SUPPLY_CORRIDOR_GARRISON_MAX: float = 3000.0
const SUPPLY_CORRIDOR_RESPONSE_MAX_POWER: float = 5000.0
const SUPPLY_CORRIDOR_POWER_RATIO_MIN: float = 0.80
const SUPPLY_CORRIDOR_POWER_RATIO_MAX: float = 1.50
const BREAKOUT_SUPPLY_RATIO: float = 0.25
const BREAKOUT_MIN_POWER_RATIO: float = 0.70
const ASSAULT_PARTICIPANT_MIN_RATIO: float = 0.35
const ASSAULT_SYNC_WINDOW_DAYS: float = 5.0
const STRATEGIC_VALUE_DELTA_LIMIT: float = 1.0
const CAMPAIGN_TARGET_BONUS: float = 1.0
const NORMAL_COMMIT_DAYS: int = 10
const STRATEGIC_COMMIT_DAYS: int = 30


static func choose(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army,
	minimum_participant_ratio: float = ASSAULT_PARTICIPANT_MIN_RATIO,
	defense_plan: CityDefensePlan = null
) -> ActionCandidate:
	var active_defense_plan := defense_plan
	if active_defense_plan == null:
		active_defense_plan = CityDefensePlan.build(
			view,
			snapshot,
			threat
		)
	if army.state == Army.State.HOLDING:
		return _choose_holding(
			view,
			snapshot,
			threat,
			coordinator,
			army,
			minimum_participant_ratio,
			active_defense_plan
		)
	if army.state != Army.State.IDLE or army.location_city < 0:
		return ActionCandidate.make(ActionCandidate.Kind.NONE, 0.0, "状态不可接受新命令")
	var breakout := _breakout_candidate(view, snapshot, army)
	if breakout != null:
		return breakout
	var current := army.location_city
	var power := ArmyPower.effective(army)
	var local_threat := threat.threat_at(current)
	var local_support := maxf(threat.support_at(current), power)
	var local_ratio := local_support / maxf(local_threat, 1.0)
	if view.day < army.ai_order_until_day and local_ratio >= EMERGENCY_RETREAT_RATIO:
		return ActionCandidate.make(ActionCandidate.Kind.NONE, 0.0, "命令承诺期未结束")
	if _must_remain_at_logistics_hub(view, snapshot, threat, army):
		return ActionCandidate.make(
			ActionCandidate.Kind.NONE,
			0.0,
			"首都或粮仓最低守备约束"
		)
	var candidates: Array[ActionCandidate] = []
	candidates.append(ActionCandidate.make(ActionCandidate.Kind.NONE, 0.0, "保持当前驻地"))
	var defense := active_defense_plan.candidate_for(
		army,
		coordinator
	)
	if active_defense_plan.must_keep_at_city(
		army,
		coordinator
	):
		if defense != null:
			return defense
		return ActionCandidate.make(
			ActionCandidate.Kind.NONE,
			100.0,
			"要害城市最低防线：等待其他方向调兵增援",
			current
		)
	if defense != null:
		candidates.append(defense)
	var retreat := _retreat_candidate(view, snapshot, threat, army, local_ratio)
	if retreat != null:
		candidates.append(retreat)
	var attack := _attack_candidate(
		view,
		snapshot,
		threat,
		coordinator,
		army,
		minimum_participant_ratio
	)
	if attack != null:
		candidates.append(attack)
	if view.day >= army.defensive_deployment_until_day:
		var merge := _merge_candidate(
			view,
			snapshot,
			threat,
			coordinator,
			army
		)
		if merge != null:
			candidates.append(merge)
	candidates.sort_custom(func(a: ActionCandidate, b: ActionCandidate) -> bool:
		if not is_equal_approx(a.score, b.score):
			return a.score > b.score
		if a.kind != b.kind:
			return a.kind < b.kind
		return a.target_city < b.target_city
	)
	return candidates[0]


static func _retreat_candidate(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	army: Army,
	local_ratio: float
) -> ActionCandidate:
	var caution := _caution(view)
	if local_ratio >= RETREAT_ENTER_RATIO * caution:
		return null
	var start := army.location_city
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
	var best_score := -INF
	for city in view.friendly_cities:
		if city.id == start or dist[city.id] == INF:
			continue
		var safety := threat.support_at(city.id) - threat.threat_at(city.id)
		var score := (
			safety / maxf(ArmyPower.effective(army), 1.0)
			+ 0.2 * snapshot.value_of_city(city.id)
			- 0.08 * float(dist[city.id])
		)
		if score > best_score or (is_equal_approx(score, best_score) and city.id < best_city):
			best_score = score
			best_city = city.id
	if best_city == -1:
		return null
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.RETREAT,
		100.0 + (RETREAT_ENTER_RATIO - local_ratio) * 10.0 + best_score,
		"局部战力比 %.2f 低于撤退阈值，撤往安全城市 %d" % [local_ratio, best_city],
		best_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	return candidate


static func _frontier_deployment_safe(
	view: AiWorldView,
	threat: ThreatField,
	army: Army
) -> bool:
	var threat_power := threat.threat_at(army.location_city)
	var support_power := maxf(
		threat.support_at(army.location_city),
		ArmyPower.effective(army)
	)
	return (
		support_power / maxf(threat_power, 1.0)
		>= HOLD_DEPLOY_ENTER_RATIO * _caution(view)
	)


static func _attack_candidate(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army,
	minimum_participant_ratio: float
) -> ActionCandidate:
	if army.morale < 0.5 or view.nearest_supply_city(army)[0] == -1:
		return null
	var start := army.location_city
	var field := view.path_field(
		start,
		-1,
		false,
		true,
		-1,
		army.max_size
	)
	var dist: Dictionary = field["dist"]
	var access_dist: Dictionary = {}
	if view.executable_attack_paths_enabled:
		access_dist = view.path_field(
			start,
			view.nation_id,
			false,
			true,
			-1,
			army.max_size
		)["dist"]
	var power := ArmyPower.effective(army)
	var aggression := _aggression(view)
	var best_city := -1
	var best_score := -INF
	var best_directions := 0
	var best_relief := 0.0
	var target_ids: Array[int] = snapshot.priority_enemy_cities.duplicate()
	for city_id in snapshot.frontier_enemy_cities:
		var legal_reclamation := (
			view.state.recognized_owner_of(city_id)
				== view.nation_id
		)
		var pool := _adjacent_assault_pool(
			view, snapshot, threat, coordinator, city_id
		)
		var relief := _blockade_relief_value(view, city_id)
		if (
			(
				int(pool["directions"]) >= 2
				or relief > 0.0
				or legal_reclamation
			)
			and not target_ids.has(city_id)
		):
			target_ids.append(city_id)
	target_ids.sort()
	for city_id in target_ids:
		var target_distance := float(dist[city_id])
		if view.executable_attack_paths_enabled:
			target_distance = _attack_approach_distance(
				view, access_dist, city_id
			)
		if target_distance == INF:
			continue
		var city := view.state.cities[city_id]
		var legal_reclamation := (
			view.state.recognized_owner_of(city_id)
				== view.nation_id
		)
		var garrison_size := 0
		for defender in view.armies_at_city(city_id):
			garrison_size += defender.size
		if not legal_reclamation:
			garrison_size = maxi(
				garrison_size,
				city.defense
			)
		var committed_size := coordinator.size_reserved(city_id)
		var required_siege_size := (
			0
			if legal_reclamation
			else int(ceil(
				float(garrison_size)
					* Combat.SIEGE_RATIO_MIN
					* SIEGE_COMMIT_MARGIN
			))
		)
		var pool := _adjacent_assault_pool(
			view, snapshot, threat, coordinator, city_id
		)
		var participants: Dictionary = pool["participants"]
		var is_adjacent_participant := participants.has(army.id)
		if is_adjacent_participant and _wait_for_assault_sync(pool, army):
			continue
		var available_size := army.size + committed_size
		if is_adjacent_participant:
			available_size = maxi(available_size, int(pool["size"]))
		if available_size < required_siege_size:
			continue
		var enemy_power := threat.threat_at(city_id)
		if not legal_reclamation:
			enemy_power += ArmyPower.city_defense(city)
		var committed := coordinator.power_reserved(city_id)
		var relief_value := _blockade_relief_value(view, city_id)
		var participant_power := power
		if (
			is_adjacent_participant
			and _enemy_power_on_edge(
				view,
				start,
				city_id
			) > 0.0
		):
			var approach_edge := view.state.edge_of(
				start,
				city_id
			)
			if approach_edge != null:
				participant_power *= Combat.attack_multiplier(
					approach_edge.danger
				)
		var attack_power := (
			participant_power
			+ committed
			+ 0.35 * threat.support_at(start)
		)
		if is_adjacent_participant:
			attack_power = maxf(attack_power, float(pool["power"]))
		var ratio := attack_power / maxf(enemy_power, 1.0)
		var participant_ratio := participant_power / maxf(
			enemy_power,
			1.0
		)
		if participant_ratio < minimum_participant_ratio:
			continue
		if (
			ratio < ATTACK_ENTER_RATIO / aggression
			and (relief_value <= 0.0 or ratio < 1.0)
		):
			continue
		var expected_win := clampf(ratio / (ratio + 1.0), 0.0, 1.0)
		var directions := int(pool["directions"]) if is_adjacent_participant else 1
		var score := (
			snapshot.value_of_city(city_id) * expected_win
			+ minf(ratio - 1.0, 2.0) * 2.0
			- 0.05 * target_distance
			- 0.5 * snapshot.value_of_city(start)
			+ 6.0 * float(maxi(directions - 1, 0))
			+ relief_value
			+ (12.0 if legal_reclamation else 0.0)
			+ _strategic_attack_adjustment(
				view, snapshot, city_id, directions
			)
		)
		if score > best_score or (is_equal_approx(score, best_score) and city_id < best_city):
			best_score = score
			best_city = city_id
			best_directions = directions
			best_relief = relief_value
	if best_city == -1:
		return null
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.ATTACK,
		best_score,
		(
			"从 %d 个方向协同进攻城市 %d%s，收益 %.2f"
			% [
				best_directions,
				best_city,
				"并打破解围通道" if best_relief > 0.0 else "",
				best_score,
			]
		),
		best_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	return candidate


static func _attack_approach_distance(
	view: AiWorldView,
	access_dist: Dictionary,
	target_city: int
) -> float:
	var best := INF
	for neighbor in view.state.neighbors(target_city):
		var edge := view.state.edge_of(target_city, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		var neighbor_dist := float(access_dist.get(neighbor, INF))
		if neighbor_dist == INF:
			continue
		best = minf(
			best,
			neighbor_dist
				+ float(maxi(edge.distance, 1))
				+ edge.danger * Pathfinding.DANGER_WEIGHT
		)
	return best


static func _merge_candidate(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army
) -> ActionCandidate:
	var start := army.location_city
	if snapshot.frontier_cities.has(start):
		return null
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
	var best_score := -INF
	var own_power := ArmyPower.effective(army)
	for other in view.friendly_armies:
		if other == army or other.state != Army.State.IDLE or other.location_city == start:
			continue
		if snapshot.frontier_cities.has(other.location_city):
			continue
		if dist[other.location_city] == INF:
			continue
		var other_power := ArmyPower.effective(other)
		if other_power < own_power:
			continue
		# 跨城合并必须形成严格单向偏序，否则两个等战力军会互相追逐
		# 对方的上一周期位置。低 ID 为稳定接收端，目标链不可能成环。
		if other.id >= army.id:
			continue
		if other.max_size - other.size < army.size:
			continue
		var local_enemy := threat.threat_at(other.location_city)
		var threshold_gain := 1.0 if (
			other_power < local_enemy * ATTACK_ENTER_RATIO
			and other_power + own_power >= local_enemy * ATTACK_ENTER_RATIO
		) else 0.0
		var score := (
			1.0 + threshold_gain * 3.0
			- 0.08 * float(dist[other.location_city])
			- 0.5 * coordinator.power_reserved(other.location_city) / maxf(other_power, 1.0)
		)
		if score > best_score or (
			is_equal_approx(score, best_score) and other.location_city < best_city
		):
			best_score = score
			best_city = other.location_city
	if best_city == -1:
		return null
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.MERGE,
		best_score,
		"向城市 %d 集结以形成更大军团" % best_city,
		best_city
	)
	candidate.minimum_commit_days = NORMAL_COMMIT_DAYS
	return candidate


static func _breakout_candidate(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	army: Army
) -> ActionCandidate:
	if not _is_encircled_low_supply(view, army):
		return null
	var start := army.location_city
	var own_power := maxf(ArmyPower.effective(army), 1.0)
	var best_city := -1
	var best_score := -INF
	var best_enemy_power := 0.0
	for neighbor in view.state.neighbors(start):
		var edge := view.state.edge_of(start, neighbor)
		if (
			edge == null
			or edge.max_manpower <= 0
			or not view.state.is_enemy(view.nation_id, view.state.cities[neighbor].owner_nation)
		):
			continue
		var enemy_power := _breakout_target_power(view, neighbor)
		var score := (
			100.0
			+ snapshot.value_of_city(neighbor)
			- 5.0 * enemy_power / own_power
			- 0.25 * float(edge.distance)
		)
		if score > best_score or (
			is_equal_approx(score, best_score) and neighbor < best_city
		):
			best_score = score
			best_city = neighbor
			best_enemy_power = enemy_power
	if best_city == -1:
		return null
	if own_power / maxf(best_enemy_power, 1.0) < BREAKOUT_MIN_POWER_RATIO:
		return null
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.ATTACK,
		best_score,
		"补给率 %.0f%%，断粮军向城市 %d 背水突围"
			% [army.supply_ratio * 100.0, best_city],
		best_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	return candidate


static func _is_encircled_low_supply(view: AiWorldView, army: Army) -> bool:
	return (
		army.starving
		and army.supply_ratio <= BREAKOUT_SUPPLY_RATIO
		and not Pathfinding.can_reach_manpower_hub(view.state, army)
	)


static func _breakout_target_power(view: AiWorldView, city_id: int) -> float:
	var power := ArmyPower.city_defense(view.state.cities[city_id])
	for defender in view.state.armies_at_city(city_id):
		if view.state.is_enemy(view.nation_id, defender.owner_nation):
			power += ArmyPower.effective(defender)
	return power


static func _friendly_relief_need(view: AiWorldView, city_id: int) -> float:
	if (
		city_id < 0
		or city_id >= view.state.cities.size()
		or view.state.cities[city_id].owner_nation != view.nation_id
	):
		return 0.0
	var need := 0.0
	for army in view.friendly_armies:
		if (
			not army.on_edge
			and army.location_city == city_id
			and _is_encircled_low_supply(view, army)
		):
			need += float(army.size) * 1.25
	for battle in view.state.battles:
		if (
			battle.finished
			or battle.kind != Battle.Kind.SIEGE
			or battle.city == null
			or battle.city.id != city_id
		):
			continue
		var defender_size := 0
		for defender in battle.side_b:
			if defender.owner_nation == view.nation_id and defender.size > 0:
				defender_size += defender.size
		need = maxf(need, float(maxi(defender_size, battle.city.defense)) * 1.25)
	return need


static func _blockade_relief_value(view: AiWorldView, enemy_city_id: int) -> float:
	if (
		enemy_city_id < 0
		or enemy_city_id >= view.state.cities.size()
		or not view.state.is_enemy(
			view.nation_id, view.state.cities[enemy_city_id].owner_nation
		)
	):
		return 0.0
	var value := 0.0
	for neighbor in view.state.neighbors(enemy_city_id):
		var edge := view.state.edge_of(enemy_city_id, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		var need := _friendly_relief_need(view, neighbor)
		if need > 0.0:
			value += 4.0 + minf(need / 1000.0 * 2.0, 12.0)
	return value


static func _adjacent_assault_pool(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	target_city: int
) -> Dictionary:
	var total_size := coordinator.size_reserved(target_city)
	var total_power := coordinator.power_reserved(target_city)
	var directions := {}
	var participants := {}
	var arrival_by_army := {}
	var max_arrival_days := 0.0
	for neighbor in view.state.neighbors(target_city):
		var edge := view.state.edge_of(target_city, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		var edge_attack_multiplier := 1.0
		if _enemy_power_on_edge(
			view,
			target_city,
			neighbor
		) > 0.0:
			edge_attack_multiplier = Combat.attack_multiplier(
				edge.danger
			)
		var has_direction := false
		for army in view.friendly_armies:
			if army.size <= 0 or participants.has(army.id):
				continue
			var eligible := false
			var already_reserved := false
			if army.state == Army.State.IDLE and army.location_city == neighbor:
				eligible = not _must_remain_at_logistics_hub(
					view, snapshot, threat, army
				)
			elif (
				army.state == Army.State.HOLDING
				and (
					(army.move_from == neighbor and army.move_to == target_city)
					or (army.move_to == neighbor and army.move_from == target_city)
				)
			):
				eligible = true
			elif (
				army.state == Army.State.MOVING
				and army.ai_target_city == target_city
				and army.move_from == neighbor
				and army.move_to == target_city
			):
				eligible = true
				already_reserved = true
			if (
				not eligible
				or army.starving
				or army.supply_ratio < 0.75
				or army.morale < 0.5
			):
				continue
			var march_days := Simulation.march_days(edge.distance)
			var arrival_days := march_days
			if army.state in [Army.State.HOLDING, Army.State.MOVING]:
				var remaining := (
					army.move_progress
					if army.move_from == target_city
					else 1.0 - army.move_progress
				)
				arrival_days = clampf(remaining, 0.0, 1.0) * march_days
			participants[army.id] = true
			arrival_by_army[army.id] = arrival_days
			max_arrival_days = maxf(max_arrival_days, arrival_days)
			has_direction = true
			if not already_reserved:
				total_size += army.size
				total_power += (
					ArmyPower.effective(army)
					* edge_attack_multiplier
				)
		if has_direction:
			directions[neighbor] = true
	return {
		"size": total_size,
		"power": total_power,
		"directions": directions.size(),
		"participants": participants,
		"arrival_by_army": arrival_by_army,
		"max_arrival_days": max_arrival_days,
	}


static func _wait_for_assault_sync(pool: Dictionary, army: Army) -> bool:
	var arrival_by_army: Dictionary = pool["arrival_by_army"]
	if not arrival_by_army.has(army.id):
		return false
	return (
		float(arrival_by_army[army.id]) + ASSAULT_SYNC_WINDOW_DAYS + 0.001
		< float(pool["max_arrival_days"])
	)


static func _must_remain_at_logistics_hub(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	army: Army
) -> bool:
	var city_id := army.location_city
	if city_id < 0 or city_id >= view.state.cities.size():
		return false
	var city := view.state.cities[city_id]
	# 内部粮道使用高优先级增援和命令承诺期，不硬锁整支不可拆分军队。
	if city_id != view.capital_city_id and not city.has_warehouse:
		return false
	var required := required_logistics_garrison(
		view, snapshot, threat, city_id
	)
	if required <= 0.0:
		return false
	return stationed_power_at(view, city_id, army) < required


static func required_logistics_garrison(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	city_id: int
) -> float:
	if city_id < 0 or city_id >= view.state.cities.size():
		return 0.0
	var city := view.state.cities[city_id]
	if city.owner_nation != view.nation_id:
		return 0.0
	var future_threat := threat.threat_at(city_id)
	if city_id == view.capital_city_id:
		if view.adaptive_garrison_enabled:
			return 5000.0
		return maxf(5000.0, future_threat * 1.25)
	if city.has_warehouse:
		if view.adaptive_garrison_enabled:
			return 3000.0
		return maxf(3000.0, future_threat)
	var importance := snapshot.supply_importance_at(city_id)
	if (
		not view.supply_corridor_defense_enabled
		or not _corridor_response_strategically_affordable(view)
		or importance < SUPPLY_CORRIDOR_MIN_IMPORTANCE
	):
		return 0.0
	var corridor_threat := maxf(
		future_threat,
		snapshot.potential_threat_at(city_id)
	)
	if corridor_threat < SUPPLY_CORRIDOR_THREAT_FLOOR:
		return 0.0
	return minf(
		maxf(
			SUPPLY_CORRIDOR_GARRISON_BASE
				+ SUPPLY_CORRIDOR_GARRISON_SCALE * importance,
			corridor_threat * (0.75 + importance * 0.50)
		),
		SUPPLY_CORRIDOR_GARRISON_MAX
	)


static func _corridor_response_strategically_affordable(
	view: AiWorldView
) -> bool:
	var friendly_power := 0.0
	for army in view.friendly_armies:
		friendly_power += ArmyPower.effective(army)
	var enemy_power := 0.0
	for army in view.enemy_armies:
		enemy_power += ArmyPower.effective(army)
	if enemy_power <= 0.0:
		return false
	var ratio := friendly_power / enemy_power
	return (
		ratio >= SUPPLY_CORRIDOR_POWER_RATIO_MIN
		and ratio <= SUPPLY_CORRIDOR_POWER_RATIO_MAX
	)


static func stationed_power_at(
	view: AiWorldView,
	city_id: int,
	excluded: Army = null
) -> float:
	return view.stationed_power_at(city_id, excluded)


static func _choose_holding(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army,
	minimum_participant_ratio: float,
	defense_plan: CityDefensePlan
) -> ActionCandidate:
	var endpoint := army.move_from
	if view.state.cities[endpoint].owner_nation != view.nation_id:
		endpoint = army.move_to
	var enemy_endpoint := army.move_to if endpoint == army.move_from else army.move_from
	var defense := defense_plan.candidate_for(
		army,
		coordinator
	)
	if defense != null:
		return defense
	var enemy := maxf(threat.threat_at(army.move_from), threat.threat_at(army.move_to))
	var support := maxf(
		maxf(
			threat.support_at(army.move_from),
			threat.support_at(army.move_to)
		),
		ArmyPower.effective(army)
	)
	var ratio := support / maxf(enemy, 1.0)
	var target_city := view.state.cities[enemy_endpoint]
	if (
		_is_encircled_low_supply(view, army)
		and view.state.is_enemy(view.nation_id, target_city.owner_nation)
	):
		var breakout_target_power := _breakout_target_power(view, enemy_endpoint)
		var breakout_ratio := (
			ArmyPower.effective(army) / maxf(breakout_target_power, 1.0)
		)
		if breakout_ratio >= BREAKOUT_MIN_POWER_RATIO:
			var breakout := ActionCandidate.make(
				ActionCandidate.Kind.ATTACK,
				100.0,
				"边上驻军断粮，向敌方端点 %d 背水突围" % enemy_endpoint,
				enemy_endpoint
			)
			breakout.minimum_commit_days = STRATEGIC_COMMIT_DAYS
			return breakout
	if enemy > 0.0 and ratio < RETREAT_ENTER_RATIO * _caution(view):
		var retreat := ActionCandidate.make(
			ActionCandidate.Kind.RETREAT,
			20.0,
			"驻防边敌军优势，战力比 %.2f，执行撤退" % ratio,
			endpoint
		)
		retreat.minimum_commit_days = STRATEGIC_COMMIT_DAYS
		retreat.defensive_deployment = true
		retreat.target_edge_a = army.move_from
		retreat.target_edge_b = army.move_to
		return retreat
	if defense_plan.must_hold_city(endpoint):
		return ActionCandidate.make(
			ActionCandidate.Kind.HOLD,
			100.0,
			"继续扼守要害城市 %d 的首要防线" % endpoint,
			enemy_endpoint
		)
	var hold_score := snapshot.value_of_edge(army.move_from, army.move_to) + 2.0
	if (
		view.state.is_enemy(view.nation_id, target_city.owner_nation)
		and army.morale >= 0.70
		and army.supply_ratio >= 0.75
	):
		var garrison_size := 0
		for defender in view.armies_at_city(enemy_endpoint):
			garrison_size += defender.size
		garrison_size = maxi(garrison_size, target_city.defense)
		var required_size := int(ceil(
			float(garrison_size) * Combat.SIEGE_RATIO_MIN * SIEGE_COMMIT_MARGIN
		))
		var pool := _adjacent_assault_pool(
			view, snapshot, threat, coordinator, enemy_endpoint
		)
		if _wait_for_assault_sync(pool, army):
			return ActionCandidate.make(
				ActionCandidate.Kind.HOLD,
				hold_score + 8.0,
				"等待较慢方向接近，确保多路军队在 5 天内抵达",
				army.move_to
			)
		var available_size := maxi(army.size, int(pool["size"]))
		var direct_edge_enemy := _enemy_power_on_edge(
			view, army.move_from, army.move_to
		)
		var projected_enemy := maxf(
			threat.threat_at(enemy_endpoint) * 0.35,
			direct_edge_enemy
		)
		var held_edge := view.state.edge_of(
			army.move_from,
			army.move_to
		)
		var own_attack_power := ArmyPower.effective(army)
		if held_edge != null and direct_edge_enemy > 0.0:
			own_attack_power *= Combat.attack_multiplier(
				held_edge.danger
			)
		var local_ratio := maxf(own_attack_power, float(pool["power"])) / maxf(
			projected_enemy + ArmyPower.city_defense(target_city),
			1.0
		)
		var participant_ratio := own_attack_power / maxf(
			projected_enemy + ArmyPower.city_defense(target_city),
			1.0
		)
		var directions := int(pool["directions"])
		if (
			available_size >= required_size
			and local_ratio >= ATTACK_ENTER_RATIO
			and participant_ratio >= minimum_participant_ratio
		):
			var attack := ActionCandidate.make(
				ActionCandidate.Kind.ATTACK,
				(
					hold_score
					+ local_ratio
					+ 6.0 * float(maxi(directions - 1, 0))
					+ _strategic_attack_adjustment(
						view, snapshot, enemy_endpoint, directions
					)
				),
				"%d 个方向形成协同优势 %.2f，向敌方端点 %d 同步推进"
					% [directions, local_ratio, enemy_endpoint],
				enemy_endpoint
			)
			attack.minimum_commit_days = STRATEGIC_COMMIT_DAYS
			return attack
	return ActionCandidate.make(
		ActionCandidate.Kind.HOLD,
		hold_score,
		"继续控制战略边，价值 %.2f" % hold_score,
		army.move_to
	)


static func _strategic_attack_adjustment(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	city_id: int,
	directions: int
) -> float:
	if not view.strategic_planning_enabled:
		return 0.0
	var value_delta := clampf(
		snapshot.value_of_offense(city_id) - snapshot.value_of_city(city_id),
		-STRATEGIC_VALUE_DELTA_LIMIT,
		STRATEGIC_VALUE_DELTA_LIMIT
	)
	var campaign_bonus := 0.0
	if (
		city_id == snapshot.campaign_target
		and (directions >= 2 or _post_capture_exposure(view, city_id) <= 0)
	):
		campaign_bonus = CAMPAIGN_TARGET_BONUS
	return value_delta * 0.5 + campaign_bonus


static func _post_capture_exposure(view: AiWorldView, city_id: int) -> int:
	var friendly_links := 0
	var hostile_links := 0
	var target_owner := view.state.cities[city_id].owner_nation
	for neighbor in view.state.neighbors(city_id):
		var edge := view.state.edge_of(city_id, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		var owner := view.state.cities[neighbor].owner_nation
		if owner == view.nation_id:
			friendly_links += 1
		elif owner == target_owner:
			hostile_links += 1
	return hostile_links - friendly_links


## 同一条边上的敌军是即将直接接战的对象，不能套用威胁场的时间衰减或远方折扣。
static func _enemy_power_on_edge(
	view: AiWorldView,
	city_a: int,
	city_b: int
) -> float:
	var lo := mini(city_a, city_b)
	var hi := maxi(city_a, city_b)
	var total := 0.0
	for enemy in view.enemy_armies:
		if enemy.size <= 0 or not enemy.on_edge or enemy.move_to == -1:
			continue
		if (
			mini(enemy.move_from, enemy.move_to) == lo
			and maxi(enemy.move_from, enemy.move_to) == hi
		):
			total += ArmyPower.effective(enemy)
	return total


static func _aggression(view: AiWorldView) -> float:
	if not view.legacy_id_personality_enabled:
		return clampf(
			view.state.nations[view.nation_id].ai_aggression,
			0.5,
			1.5
		)
	return 0.85 + float((view.nation_id * 37 + 11) % 36) / 100.0


static func _caution(view: AiWorldView) -> float:
	if not view.legacy_id_personality_enabled:
		return 1.0 / _aggression(view)
	return 0.85 + float((view.nation_id * 53 + 7) % 36) / 100.0
