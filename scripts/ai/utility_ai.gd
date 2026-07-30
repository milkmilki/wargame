class_name UtilityAI
extends RefCounted
## 无训练 Utility AI：生成可解释候选行动并选择最高分。

const ATTACK_ENTER_RATIO: float = 1.35
const RETREAT_ENTER_RATIO: float = 0.40
const EMERGENCY_RETREAT_RATIO: float = 0.25
const SIEGE_COMMIT_MARGIN: float = 1.50
const REINFORCE_MIN_DEFICIT_SHARE: float = 0.50
const RELIEF_MIN_DEFICIT_SHARE: float = 0.25
const BREAKOUT_SUPPLY_RATIO: float = 0.25
const BREAKOUT_MIN_POWER_RATIO: float = 0.70
const ASSAULT_SYNC_WINDOW_DAYS: float = 5.0
const NORMAL_COMMIT_DAYS: int = 10
const STRATEGIC_COMMIT_DAYS: int = 30


static func choose(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army
) -> ActionCandidate:
	if army.state == Army.State.HOLDING:
		return _choose_holding(view, snapshot, threat, coordinator, army)
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
	if _must_remain_at_logistics_hub(view, threat, army):
		return ActionCandidate.make(
			ActionCandidate.Kind.NONE,
			0.0,
			"首都或粮仓最低守备约束"
		)

	var candidates: Array[ActionCandidate] = []
	candidates.append(ActionCandidate.make(ActionCandidate.Kind.NONE, 0.0, "保持当前驻地"))
	var retreat := _retreat_candidate(view, snapshot, threat, army, local_ratio)
	if retreat != null:
		candidates.append(retreat)
	var reinforce := _reinforce_candidate(view, snapshot, threat, coordinator, army)
	if reinforce != null:
		candidates.append(reinforce)
	var hold := _hold_candidate(view, snapshot, threat, army)
	if hold != null:
		candidates.append(hold)
	var attack := _attack_candidate(view, snapshot, threat, coordinator, army)
	if attack != null:
		candidates.append(attack)
	var merge := _merge_candidate(view, snapshot, threat, coordinator, army)
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
	var caution := _caution(view.nation_id)
	if local_ratio >= RETREAT_ENTER_RATIO * caution:
		return null
	var start := army.location_city
	var field := Pathfinding.dijkstra_field(view.state, start, view.nation_id, false, true)
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
		10.0 + (RETREAT_ENTER_RATIO - local_ratio) * 10.0 + best_score,
		"局部战力比 %.2f 低于撤退阈值，撤往安全城市 %d" % [local_ratio, best_city],
		best_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	return candidate


static func _reinforce_candidate(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army
) -> ActionCandidate:
	var start := army.location_city
	var field := Pathfinding.dijkstra_field(view.state, start, view.nation_id, false, true)
	var dist: Dictionary = field["dist"]
	var best_city := -1
	var best_score := -INF
	var target_ids: Array[int] = snapshot.frontier_cities.duplicate()
	for warehouse in view.warehouses:
		if not target_ids.has(warehouse.id):
			target_ids.append(warehouse.id)
	for city in view.friendly_cities:
		if _friendly_relief_need(view, city.id) > 0.0 and not target_ids.has(city.id):
			target_ids.append(city.id)
	target_ids.sort()
	var best_is_relief := false
	for city_id in target_ids:
		if city_id == start or dist[city_id] == INF:
			continue
		var enemy := threat.threat_at(city_id)
		# 支援必须是一军一目标的真实预留，不能使用会在多个城市重复计数的支援场。
		var support := coordinator.power_reserved(city_id)
		var frontline_deficit := enemy - support
		var hub_required := required_logistics_garrison(view, threat, city_id)
		var hub_deficit := (
			hub_required
			- stationed_power_at(view, city_id)
			- support
		)
		var relief_need := _friendly_relief_need(view, city_id)
		var relief_deficit := relief_need - support
		var deficit := maxf(maxf(frontline_deficit, hub_deficit), relief_deficit)
		var uncovered := (
			snapshot.frontier_cities.has(city_id)
			and
			not _frontier_has_coverage(view, city_id)
			and coordinator.power_reserved(city_id) <= 0.0
		)
		if deficit <= 0.0 and not uncovered:
			continue
		if (
			deficit > 0.0
			and ArmyPower.effective(army) < deficit * (
				RELIEF_MIN_DEFICIT_SHARE
				if relief_need > 0.0
				else REINFORCE_MIN_DEFICIT_SHARE
			)
		):
			continue
		var score := (
			4.0 * deficit / maxf(maxf(maxf(enemy, hub_required), relief_need), 1.0)
			+ 0.4 * snapshot.value_of_city(city_id)
			- 0.06 * float(dist[city_id])
			+ (10.0 if uncovered else 0.0)
			+ (8.0 if hub_deficit > 0.0 else 0.0)
			+ (15.0 if relief_need > 0.0 else 0.0)
		)
		if score > best_score or (is_equal_approx(score, best_score) and city_id < best_city):
			best_score = score
			best_city = city_id
			best_is_relief = relief_need > 0.0
	if best_city == -1:
		return null
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		best_score,
		(
			"城市 %d 的被围/断粮友军需要紧急解围" % best_city
			if best_is_relief
			else "前线城市 %d 存在兵力缺口" % best_city
		),
		best_city
	)
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	return candidate


static func _hold_candidate(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	army: Army
) -> ActionCandidate:
	var current := army.location_city
	var best_edge: Edge = null
	var best_score := -INF
	for neighbor in view.state.neighbors(current):
		if view.state.cities[neighbor].owner_nation == view.nation_id:
			continue
		var edge := view.state.edge_of(current, neighbor)
		if edge == null or edge.max_throughput <= 0:
			continue
		var score := (
			snapshot.value_of_edge(current, neighbor)
			+ 0.5 * threat.threat_at(current) / maxf(ArmyPower.effective(army), 1.0)
			+ edge.danger * 2.0
			+ (10.0 if not _edge_has_holder_or_order(view, current, neighbor) else 0.0)
		)
		if score > best_score or (
			is_equal_approx(score, best_score)
			and (best_edge == null or neighbor < (
				best_edge.city_b if best_edge.city_a == current else best_edge.city_a
			))
		):
			best_score = score
			best_edge = edge
	if best_edge == null:
		return null
	var target := best_edge.city_b if best_edge.city_a == current else best_edge.city_a
	var candidate := ActionCandidate.make(
		ActionCandidate.Kind.HOLD,
		best_score + 2.0,
		"边 %d-%d 战略价值 %.2f" % [current, target, best_score],
		target
	)
	candidate.target_edge_a = current
	candidate.target_edge_b = target
	candidate.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	return candidate


static func _attack_candidate(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army
) -> ActionCandidate:
	if army.morale < 0.5 or Pathfinding.nearest_supply_city(view.state, army)[0] == -1:
		return null
	var start := army.location_city
	var field := Pathfinding.dijkstra_field(view.state, start)
	var dist: Dictionary = field["dist"]
	var power := ArmyPower.effective(army)
	var aggression := _aggression(view.nation_id)
	var best_city := -1
	var best_score := -INF
	var best_directions := 0
	var best_relief := 0.0
	var target_ids: Array[int] = snapshot.priority_enemy_cities.duplicate()
	for city_id in snapshot.frontier_enemy_cities:
		var pool := _adjacent_assault_pool(view, threat, coordinator, city_id)
		var relief := _blockade_relief_value(view, city_id)
		if (
			(int(pool["directions"]) >= 2 or relief > 0.0)
			and not target_ids.has(city_id)
		):
			target_ids.append(city_id)
	target_ids.sort()
	for city_id in target_ids:
		if dist[city_id] == INF:
			continue
		var city := view.state.cities[city_id]
		var garrison_size := 0
		for defender in view.state.armies_at_city(city_id):
			garrison_size += defender.size
		garrison_size = maxi(garrison_size, city.defense)
		var committed_size := coordinator.size_reserved(city_id)
		var required_siege_size := int(ceil(
			float(garrison_size) * Combat.SIEGE_RATIO_MIN * SIEGE_COMMIT_MARGIN
		))
		var pool := _adjacent_assault_pool(view, threat, coordinator, city_id)
		var participants: Dictionary = pool["participants"]
		var is_adjacent_participant := participants.has(army.id)
		if is_adjacent_participant and _wait_for_assault_sync(pool, army):
			continue
		var available_size := army.size + committed_size
		if is_adjacent_participant:
			available_size = maxi(available_size, int(pool["size"]))
		if available_size < required_siege_size:
			continue
		var enemy_power := threat.threat_at(city_id) + ArmyPower.city_defense(city)
		var committed := coordinator.power_reserved(city_id)
		var attack_power := power + committed + 0.35 * threat.support_at(start)
		if is_adjacent_participant:
			attack_power = maxf(attack_power, float(pool["power"]))
		var ratio := attack_power / maxf(enemy_power, 1.0)
		var relief_value := _blockade_relief_value(view, city_id)
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
			- 0.05 * float(dist[city_id])
			- 0.5 * snapshot.value_of_city(start)
			+ 6.0 * float(maxi(directions - 1, 0))
			+ relief_value
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
	var field := Pathfinding.dijkstra_field(view.state, start, view.nation_id, false, true)
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


static func _frontier_has_coverage(view: AiWorldView, city_id: int) -> bool:
	for army in view.friendly_armies:
		if army.size <= 0:
			continue
		if (
			army.state in [Army.State.IDLE, Army.State.RECOVERING]
			and army.location_city == city_id
		):
			return true
		if (
			army.state == Army.State.HOLDING
			and (army.move_from == city_id or army.move_to == city_id)
		):
			return true
		if army.state == Army.State.MOVING and army.ai_target_city == city_id:
			return true
	return false


static func _edge_has_holder_or_order(
	view: AiWorldView,
	from_city: int,
	to_city: int
) -> bool:
	var lo := mini(from_city, to_city)
	var hi := maxi(from_city, to_city)
	for army in view.friendly_armies:
		if army.size <= 0 or army.move_to == -1:
			continue
		if mini(army.move_from, army.move_to) != lo or maxi(army.move_from, army.move_to) != hi:
			continue
		if army.state == Army.State.HOLDING or army.hold_target_progress >= 0.0:
			return true
	return false


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
			or edge.max_throughput <= 0
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
		if edge == null or edge.max_throughput <= 0:
			continue
		var need := _friendly_relief_need(view, neighbor)
		if need > 0.0:
			value += 4.0 + minf(need / 1000.0 * 2.0, 12.0)
	return value


static func _adjacent_assault_pool(
	view: AiWorldView,
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
		if edge == null or edge.max_throughput <= 0:
			continue
		var has_direction := false
		for army in view.friendly_armies:
			if army.size <= 0 or participants.has(army.id):
				continue
			var eligible := false
			var already_reserved := false
			if army.state == Army.State.IDLE and army.location_city == neighbor:
				eligible = not _must_remain_at_logistics_hub(view, threat, army)
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
				total_power += ArmyPower.effective(army)
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
	threat: ThreatField,
	army: Army
) -> bool:
	var city_id := army.location_city
	var required := required_logistics_garrison(view, threat, city_id)
	if required <= 0.0:
		return false
	return stationed_power_at(view, city_id, army) < required


static func required_logistics_garrison(
	view: AiWorldView,
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
		return maxf(5000.0, future_threat * 1.25)
	if city.has_warehouse:
		return maxf(3000.0, future_threat)
	return 0.0


static func stationed_power_at(
	view: AiWorldView,
	city_id: int,
	excluded: Army = null
) -> float:
	var total := 0.0
	for other in view.friendly_armies:
		if other == excluded or other.size <= 0 or other.on_edge:
			continue
		if (
			other.location_city == city_id
			and other.state in [Army.State.IDLE, Army.State.RECOVERING]
		):
			total += ArmyPower.effective(other)
	return total


static func _choose_holding(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot,
	threat: ThreatField,
	coordinator: ArmyCoordinator,
	army: Army
) -> ActionCandidate:
	var endpoint := army.move_from
	if view.state.cities[endpoint].owner_nation != view.nation_id:
		endpoint = army.move_to
	var enemy_endpoint := army.move_to if endpoint == army.move_from else army.move_from
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
		and target_city.owner_nation != view.nation_id
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
	if enemy > 0.0 and ratio < RETREAT_ENTER_RATIO * _caution(view.nation_id):
		var retreat := ActionCandidate.make(
			ActionCandidate.Kind.RETREAT,
			20.0,
			"驻防边敌军优势，战力比 %.2f，执行撤退" % ratio,
			endpoint
		)
		retreat.minimum_commit_days = STRATEGIC_COMMIT_DAYS
		return retreat
	var hold_score := snapshot.value_of_edge(army.move_from, army.move_to) + 2.0
	if (
		target_city.owner_nation != view.nation_id
		and army.morale >= 0.70
		and army.supply_ratio >= 0.75
	):
		var garrison_size := 0
		for defender in view.state.armies_at_city(enemy_endpoint):
			garrison_size += defender.size
		garrison_size = maxi(garrison_size, target_city.defense)
		var required_size := int(ceil(
			float(garrison_size) * Combat.SIEGE_RATIO_MIN * SIEGE_COMMIT_MARGIN
		))
		var pool := _adjacent_assault_pool(
			view, threat, coordinator, enemy_endpoint
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
		var local_ratio := maxf(ArmyPower.effective(army), float(pool["power"])) / maxf(
			projected_enemy + ArmyPower.city_defense(target_city),
			1.0
		)
		var directions := int(pool["directions"])
		if available_size >= required_size and local_ratio >= ATTACK_ENTER_RATIO:
			var attack := ActionCandidate.make(
				ActionCandidate.Kind.ATTACK,
				hold_score + local_ratio + 6.0 * float(maxi(directions - 1, 0)),
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


static func _aggression(nation_id: int) -> float:
	return 0.85 + float((nation_id * 37 + 11) % 36) / 100.0


static func _caution(nation_id: int) -> float:
	return 0.85 + float((nation_id * 53 + 7) % 36) / 100.0
