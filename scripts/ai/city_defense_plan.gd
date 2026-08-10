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
const ROLE_DEPLOYMENT_SCORE: float = 2000.0
const SMALL_NATION_SURVIVAL_MAX_CITIES: int = 4
## 重要城市（内线）部署权重的地理修正：价值随「离边境近」「离首都近」放大。
## 采用拓扑跳数（BFS）度量，加权和合成，跳数越小因子越接近上限。
const STRATEGIC_BORDER_PROXIMITY_WEIGHT: float = 0.60
const STRATEGIC_CAPITAL_PROXIMITY_WEIGHT: float = 0.40
const STRATEGIC_PROXIMITY_DECAY_HOPS: float = 2.0
const STRATEGIC_PROXIMITY_MIN_FACTOR: float = 0.35

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
var defense_assignment_slots: int = 0
var line_city_slots: int = 0
var line_critical_city_slots: int = 0
var line_edge_slots: int = 0
var assigned_city_by_army: Dictionary = {} ## army.id -> city_id
var assigned_armies_by_city: Dictionary = {} ## city_id -> Array[army.id]
var assigned_posture_by_army: Dictionary = {} ## army.id -> Posture
var assigned_edge_by_army: Dictionary = {} ## army.id -> neighbor_id
var _role_city_priority_cache: Dictionary = {}
var _role_path_dist_by_origin: Dictionary = {}
## 内线部署地理修正用的拓扑跳数场（本国领土内 BFS）。惰性构建、随规划复用。
var _border_hop_distance: Dictionary = {}   ## city_id -> 到最近国界城市的跳数
var _capital_hop_distance: Dictionary = {}  ## city_id -> 到首都的跳数
var _proximity_fields_ready: bool = false
var topology: FrontierDefenseTopology = null
var topology_rebuilt: bool = false
var topology_reused: bool = false
var dynamic_plan_reused: bool = false
var input_signature: Array = []
var _topology_prepared: bool = false
var _topology_reconciled: bool = false
var _friendly_line_army_by_id_cache: Dictionary = {}
var _friendly_line_army_index_ready: bool = false



static func build(
	world_view: AiWorldView,
	strategic_snapshot: StrategicMapSnapshot,
	threat_field: ThreatField,
	previous_plan: CityDefensePlan = null
) -> CityDefensePlan:
	var plan := CityDefensePlan.new()
	plan.view = world_view
	plan.snapshot = strategic_snapshot
	plan.threat = threat_field
	plan._prepare_frontier_topology()
	plan.input_signature = plan._input_signature()
	if (
		previous_plan != null
		and previous_plan.topology == plan.topology
		and previous_plan.input_signature
			== plan.input_signature
	):
		plan._reuse_dynamic_plan(previous_plan)
	else:
		plan._build()
	if world_view.state.uses_heightmap:
		plan._assign_role_based_defense()
	return plan


func candidate_for(
	army: Army,
	coordinator: ArmyCoordinator
) -> ActionCandidate:
	if army == null or army.size <= 0:
		return null
	var candidate: ActionCandidate = null
	if not view.state.uses_heightmap:
		if army.state == Army.State.HOLDING:
			candidate = _holding_candidate(
				army,
				coordinator
			)
		elif (
			army.state == Army.State.IDLE
			and army.location_city >= 0
		):
			candidate = _idle_candidate(
				army,
				coordinator
			)
	elif (
		view.state.wars_of(view.nation_id).is_empty()
		and snapshot.potential_frontier_cities.is_empty()
	):
		return null
	else:
		var assigned_city := int(
			assigned_city_by_army.get(army.id, -1)
		)
		if assigned_city < 0:
			return null
		candidate = _assigned_defense_candidate(
			army,
			assigned_city,
			int(
				assigned_posture_by_army.get(
					army.id,
					Posture.CITY
				)
			),
			int(assigned_edge_by_army.get(army.id, -1))
		)
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


func assigned_city_for(army: Army) -> int:
	if army == null:
		return -1
	return int(assigned_city_by_army.get(army.id, -1))


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
	if not view.state.uses_heightmap:
		if (
			army == null
			or army.state != Army.State.IDLE
			or not must_hold_city(army.location_city)
		):
			return false
		return _city_coverage(
			army.location_city,
			coordinator,
			army
		) < requirement_at(army.location_city)
	return (
		army != null
		and army.is_line_role()
		and army.state == Army.State.IDLE
		and int(assigned_city_by_army.get(army.id, -1))
			== army.location_city
	)


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
	if (
		view.state.uses_heightmap
		and army.is_main_battle_role()
	):
		return true
	if view.state.uses_heightmap:
		return false
	if not view.state.uses_heightmap:
		if army.state == Army.State.IDLE:
			if not required_power.has(army.location_city):
				return true
			return _city_coverage(
				army.location_city,
				coordinator,
				army
			) >= requirement_at(army.location_city)
		if army.state == Army.State.HOLDING:
			var anchor := army.move_from
			if not view.state.has_military_access(
				view.nation_id,
				view.state.cities[anchor].owner_nation
			):
				anchor = army.move_to
			return not required_power.has(anchor)
		return false
	return not assigned_city_by_army.has(army.id)


func can_join_offensive(
	army: Army,
	target_city: int
) -> bool:
	if (
		army == null
		or army.size <= 0
		or view.day < army.defensive_deployment_until_day
	):
		return false
	if army.is_main_battle_role():
		return true
	if view.state.uses_heightmap:
		return false
	if not army.is_line_role():
		return false
	if not assigned_city_by_army.has(army.id):
		return true
	if (
		int(assigned_posture_by_army.get(
			army.id,
			Posture.CITY
		)) != Posture.EDGE
	):
		return false
	var anchor := int(assigned_city_by_army[army.id])
	if target_city not in view.state.neighbors(anchor):
		return false
	for assigned_id_value in assigned_armies_by_city.get(
		anchor,
		[] as Array[int]
	):
		var assigned_id := int(assigned_id_value)
		if (
			assigned_id != army.id
			and int(assigned_posture_by_army.get(
				assigned_id,
				Posture.CITY
			)) == Posture.CITY
		):
			return true
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


func _input_signature() -> Array:
	var result: Array = [
		view.nation_id,
		view.state.ownership_revision,
		view.state.diplomacy_revision,
		view.state.fortification_revision,
		view.capital_city_id,
	]
	_append_army_signature(result, view.friendly_armies)
	result.append(-1001)
	_append_army_signature(result, view.enemy_armies)
	result.append(-1002)
	for battle in view.state.battles:
		if (
			battle.finished
			or battle.kind != Battle.Kind.SIEGE
			or battle.city == null
		):
			continue
		result.append_array([
			battle.id,
			battle.city.id,
			battle.city.owner_nation,
			battle.side_a.size(),
			battle.side_b.size(),
		])
	return result


func _append_army_signature(
	result: Array,
	armies: Array[Army]
) -> void:
	result.append(armies.size())
	for army in armies:
		result.append_array([
			army.id,
			army.owner_nation,
			army.size,
			army.max_size,
			army.state,
			army.location_city,
			army.move_from,
			army.move_to,
			army.on_edge,
			army.move_progress,
			army.starving,
			army.supply_ratio,
			army.battle_id,
			ArmyPower.effective(army),
		])


func _reuse_dynamic_plan(
	previous: CityDefensePlan
) -> void:
	required_power = previous.required_power.duplicate(true)
	posture_by_city = (
		previous.posture_by_city.duplicate(true)
	)
	preferred_edge_by_city = (
		previous.preferred_edge_by_city.duplicate(true)
	)
	directional_pressure = (
		previous.directional_pressure.duplicate(true)
	)
	relief_need = previous.relief_need.duplicate(true)
	local_pressure = previous.local_pressure.duplicate(true)
	must_hold_cities = (
		previous.must_hold_cities.duplicate(true)
	)
	frontline_distribution_enabled = (
		previous.frontline_distribution_enabled
	)
	primary_frontline_cities = (
		previous.primary_frontline_cities.duplicate(true)
	)
	frontline_cities = (
		previous.frontline_cities.duplicate(true)
	)
	frontline_allocation = (
		previous.frontline_allocation.duplicate(true)
	)
	defense_assignment_slots = (
		previous.defense_assignment_slots
	)
	_role_city_priority_cache = (
		previous._role_city_priority_cache.duplicate(true)
	)
	dynamic_plan_reused = true


func _prepare_frontier_topology() -> void:
	if _topology_prepared:
		return
	_topology_prepared = true
	if not view.state.uses_heightmap:
		return
	var nation := view.state.nations[view.nation_id]
	var cached: FrontierDefenseTopology = (
		nation.frontier_defense_topology
	)
	if cached != null and cached.matches(view, snapshot):
		topology = cached
		topology_reused = true
		topology_rebuilt = false
		return
	topology = FrontierDefenseTopology.build(
		view,
		snapshot
	)
	nation.frontier_defense_topology = topology
	topology_rebuilt = true
	topology_reused = false


func _defense_evaluation_city_ids() -> Array[int]:
	if not view.state.uses_heightmap or topology == null:
		var all_friendly: Array[int] = []
		for city in view.friendly_cities:
			all_friendly.append(city.id)
		return all_friendly
	var relevant := {}
	for city_id in topology.frontline_city_ids:
		relevant[city_id] = true
	for city_id_value in view.enemy_armies_by_city.keys():
		var city_id := int(city_id_value)
		if (
			view.state.cities[city_id].owner_nation
				== view.nation_id
		):
			relevant[city_id] = true
		for neighbor in view.state.neighbors(city_id):
			if (
				view.state.cities[neighbor].owner_nation
					== view.nation_id
			):
				relevant[neighbor] = true
	for enemy in view.enemy_armies:
		if not enemy.on_edge or enemy.move_to < 0:
			continue
		for endpoint in [enemy.move_from, enemy.move_to]:
			if (
				view.state.cities[endpoint].owner_nation
					== view.nation_id
			):
				relevant[endpoint] = true
	for army in view.friendly_armies:
		if (
			not army.on_edge
			and army.location_city >= 0
			and army.starving
			and army.supply_ratio
				<= UtilityAI.BREAKOUT_SUPPLY_RATIO
		):
			relevant[army.location_city] = true
	for battle in view.state.battles:
		if (
			not battle.finished
			and battle.kind == Battle.Kind.SIEGE
			and battle.city != null
			and battle.city.owner_nation == view.nation_id
		):
			relevant[battle.city.id] = true
	var result: Array[int] = []
	result.assign(relevant.keys())
	EquivariantOrder.sort_city_ids(
		result,
		view.state,
		view.nation_id
	)
	return result


func _build() -> void:
	_prepare_frontier_topology()
	var national_power := 0.0
	for army in view.friendly_armies:
		national_power += ArmyPower.effective(army)
	if topology != null:
		for city_id in topology.primary_city_ids:
			primary_frontline_cities[city_id] = true
		for city_id in topology.frontline_city_ids:
			frontline_cities[city_id] = true
	else:
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
	frontline_distribution_enabled = not frontline_cities.is_empty()
	for city_id in _defense_evaluation_city_ids():
		var city := view.state.cities[city_id]
		var pressures := _directional_pressure_at(city.id)
		var direct_pressure := _enemy_power_inside(city.id)
		var relief := UtilityAI._friendly_relief_need(view, city.id)
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
			pressure_total * REQUIRED_PRESSURE_SHARE,
			relief
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
		var strongest_edge := view.state.edge_of(
			city.id,
			strongest_direction
		)
		if (
			direct_pressure > 0.0
			or relief > 0.0
			or edge_defense_understrength
			or active_directions.size() > 1
			or strongest_direction == -1
			or equally_best_directions > 1
			or strongest_edge == null
			or not strongest_edge.allows_holding
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
	var average_army_power := (
		national_power
		/ float(maxi(view.friendly_armies.size(), 1))
	)
	defense_assignment_slots = clampi(
		int(ceil(
			defense_budget / maxf(average_army_power, 1.0)
		)),
		0,
		view.friendly_armies.size()
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


func _assign_role_based_defense() -> void:
	assigned_city_by_army.clear()
	assigned_armies_by_city.clear()
	assigned_posture_by_army.clear()
	assigned_edge_by_army.clear()
	var line_armies: Array[Army] = []
	for army in view.friendly_armies:
		if (
			army.size <= 0
			or not army.is_line_role()
		):
			continue
		if (
			army.state in [
				Army.State.IDLE,
				Army.State.HOLDING,
				Army.State.RECOVERING,
			] or (
				army.state == Army.State.MOVING
				and army.ai_order_reason.begins_with(
					"填线部署"
				)
			)
		):
			line_armies.append(army)
	line_armies.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(
			view.state,
			view.nation_id,
			a,
			b
		)
	)
	var defense_slots := _build_role_defense_slots()
	line_city_slots = 0
	line_critical_city_slots = 0
	line_edge_slots = 0
	for slot in defense_slots:
		if int(slot["posture"]) == Posture.EDGE:
			line_edge_slots += 1
		else:
			line_city_slots += 1
			if int(slot.get("priority", 0)) == 0:
				line_critical_city_slots += 1
	defense_assignment_slots = mini(
		defense_slots.size(),
		line_armies.size()
	)
	if line_armies.is_empty():
		return
	if defense_slots.is_empty():
		for army in line_armies:
			army.clear_line_assignment()
		return
	var eligible_line_armies := line_armies.duplicate()
	# 只激活当前兵力能覆盖的最高优先级槽位。持久 Assignment 只能在该前缀内
	# 续任，避免城市守军损失后，旧边槽军仍驻边而把更高优先级城市留空。
	var remaining_slots := defense_slots.slice(
		0,
		defense_assignment_slots
	)
	var remaining_armies := line_armies.duplicate()
	# 防区槽是 Assignment 真源。先恢复仍合法的槽-军关系，再处理旧版军队侧索引。
	var sector_slot_index := 0
	while sector_slot_index < remaining_slots.size():
		var slot: Dictionary = remaining_slots[sector_slot_index]
		var sector := _sector_for_slot(slot)
		if sector == null:
			sector_slot_index += 1
			continue
		var slot_index := int(slot["sector_slot"])
		var army_id := sector.assigned_army_at(slot_index)
		if army_id < 0:
			sector_slot_index += 1
			continue
		var army := _friendly_line_army_by_id(army_id)
		if army == null:
			sector.clear_slot(slot_index)
			sector_slot_index += 1
			continue
		if not remaining_armies.has(army):
			if army.state == Army.State.FIGHTING:
				_record_role_assignment(army, slot)
				remaining_slots.remove_at(sector_slot_index)
				continue
			sector.clear_slot(slot_index)
			sector_slot_index += 1
			continue
		if _role_assignment_distance(
			army,
			int(slot["city_id"]),
			int(slot["posture"]),
			int(slot.get("edge_neighbor", -1))
		) == INF:
			sector.clear_slot(slot_index)
			sector_slot_index += 1
			continue
		_record_role_assignment(army, slot)
		remaining_slots.remove_at(sector_slot_index)
		remaining_armies.erase(army)
	# 同一优先级集合内保留有效的持久防区，减少无意义换防。
	for army in line_armies:
		var slot_index := _persistent_role_slot_index(
			remaining_slots,
			army
		)
		if slot_index < 0:
			continue
		var slot: Dictionary = remaining_slots[slot_index]
		if _role_assignment_distance(
			army,
			int(slot["city_id"]),
			int(slot["posture"]),
			int(slot.get("edge_neighbor", -1))
		) == INF:
			continue
		_record_role_assignment(army, slot)
		remaining_slots.remove_at(slot_index)
		remaining_armies.erase(army)
	for slot in remaining_slots:
		if remaining_armies.is_empty():
			break
		var city_id := int(slot["city_id"])
		var posture := int(slot["posture"])
		var edge_neighbor := int(slot.get("edge_neighbor", -1))
		var best_index := -1
		var best_distance := INF
		for army_index in range(remaining_armies.size()):
			var army: Army = remaining_armies[army_index]
			var distance := _role_assignment_distance(
				army,
				city_id,
				posture,
				edge_neighbor
			)
			if (
				distance < best_distance
				or (
					is_equal_approx(distance, best_distance)
					and (
						best_index < 0
						or EquivariantOrder.army_less(
							view.state,
							view.nation_id,
							army,
							remaining_armies[best_index],
							city_id
						)
					)
				)
			):
				best_index = army_index
				best_distance = distance
		if best_index < 0 or best_distance == INF:
			continue
		var army: Army = remaining_armies[best_index]
		remaining_armies.remove_at(best_index)
		_record_role_assignment(army, slot)
	for army in eligible_line_armies:
		if not assigned_city_by_army.has(army.id):
			_clear_army_from_frontier_sector(army)
			army.clear_line_assignment()


func _persistent_role_slot_index(
	slots: Array,
	army: Army
) -> int:
	if (
		army.line_assignment_city < 0
		or army.line_assignment_posture
			== Army.LinePosture.NONE
	):
		return -1
	for index in range(slots.size()):
		var slot: Dictionary = slots[index]
		if (
			int(slot["city_id"])
				== army.line_assignment_city
			and int(slot["posture"])
				== army.line_assignment_posture
			and int(slot.get("edge_neighbor", -1))
				== army.line_assignment_edge
		):
			return index
	return -1


func _record_role_assignment(
	army: Army,
	slot: Dictionary
) -> void:
	var city_id := int(slot["city_id"])
	var posture := int(slot["posture"])
	var edge_neighbor := int(slot.get("edge_neighbor", -1))
	var sector := _sector_for_slot(slot)
	var persistent_assignment := (
		army.line_assignment_city == city_id
		and army.line_assignment_posture == posture
		and army.line_assignment_edge == edge_neighbor
	)
	var sector_slot := int(slot.get("sector_slot", -1))
	var persistent_sector_slot := (
		sector != null
		and sector_slot >= 0
		and sector.assigned_army_at(sector_slot)
			== army.id
	)
	if not (
		persistent_assignment
		and (sector == null or persistent_sector_slot)
	):
		_clear_army_from_frontier_sector(army)
	if sector != null:
		sector.assign(sector_slot, army.id)
	var effective_posture := posture
	var effective_edge := edge_neighbor
	if (
		sector != null
		and sector.state in [
			FrontierDefenseSector.State.RECALLING,
			FrontierDefenseSector.State.DEFENDING,
		]
	):
		effective_posture = Posture.CITY
		effective_edge = -1
	assigned_city_by_army[army.id] = city_id
	assigned_posture_by_army[army.id] = effective_posture
	if effective_edge >= 0:
		assigned_edge_by_army[army.id] = effective_edge
	var assigned: Array[int] = assigned_armies_by_city.get(
		city_id,
		[] as Array[int]
	)
	assigned.append(army.id)
	assigned_armies_by_city[city_id] = assigned
	army.line_assignment_city = city_id
	army.line_assignment_posture = posture
	army.line_assignment_edge = edge_neighbor


func _sector_for_slot(slot: Dictionary) -> FrontierDefenseSector:
	if not slot.has("sector_city") or not slot.has("sector_slot"):
		return null
	return view.state.nations[
		view.nation_id
	].frontier_defense_sectors.get(
		int(slot["sector_city"])
	)


func _clear_army_from_frontier_sector(army: Army) -> void:
	if army == null or army.line_assignment_city < 0:
		return
	var sector: FrontierDefenseSector = view.state.nations[
		view.nation_id
	].frontier_defense_sectors.get(army.line_assignment_city)
	if sector != null:
		sector.clear_army(army.id)


func _reconcile_frontier_defense_sectors() -> void:
	if _topology_reconciled:
		return
	_prepare_frontier_topology()
	if topology == null:
		return
	var nation := view.state.nations[view.nation_id]
	var sectors: Dictionary = nation.frontier_defense_sectors
	var active_city_ids: Array = (
		topology.primary_city_ids.duplicate()
	)
	var full_reconcile := (
		topology_rebuilt
		or not _stored_sector_topology_matches(
			sectors,
			active_city_ids
		)
	)
	if not full_reconcile:
		for city_id_value in active_city_ids:
			var city_id := int(city_id_value)
			_refresh_frontier_sector_runtime(
				sectors[city_id],
				city_id
			)
		_topology_reconciled = true
		return
	var active_set := {}
	for city_id_value in active_city_ids:
		active_set[int(city_id_value)] = true
	for city_id_value in sectors.keys().duplicate():
		var city_id := int(city_id_value)
		if (
			active_set.has(city_id)
			and city_id >= 0
			and city_id < view.state.cities.size()
			and view.state.cities[city_id].owner_nation
				== view.nation_id
		):
			continue
		var removed: FrontierDefenseSector = sectors[city_id]
		for army_id in removed.assigned_army_ids:
			var army := _friendly_line_army_by_id(int(army_id))
			if (
				army != null
				and army.line_assignment_city == city_id
			):
				army.clear_line_assignment()
		sectors.erase(city_id)
	_sort_role_city_ids(active_city_ids)
	topology.edge_neighbors_by_city.clear()
	for city_id_value in active_city_ids:
		var city_id := int(city_id_value)
		if (
			city_id < 0
			or city_id >= view.state.cities.size()
			or view.state.cities[city_id].owner_nation
				!= view.nation_id
		):
			continue
		var edge_neighbors := _frontier_sector_edges(city_id)
		topology.edge_neighbors_by_city[city_id] = (
			edge_neighbors.duplicate()
		)
		var sector: FrontierDefenseSector = sectors.get(city_id)
		if sector == null:
			sector = FrontierDefenseSector.new()
			sector.city_id = city_id
			sector.owner_nation = view.nation_id
			sectors[city_id] = sector
		var topology_changed := (
			sector.edge_neighbors.size() != edge_neighbors.size()
		)
		if not topology_changed:
			for neighbor in edge_neighbors:
				if not sector.edge_neighbors.has(neighbor):
					topology_changed = true
					break
		if topology_changed or sector.assigned_army_ids.is_empty():
			sector.configure(
				edge_neighbors,
				view.state.ownership_revision
			)
		else:
			sector.topology_revision = (
				view.state.ownership_revision
			)
		_refresh_frontier_sector_runtime(
			sector,
			city_id
		)
	nation.frontier_defense_sectors = sectors
	_topology_reconciled = true


func _stored_sector_topology_matches(
	sectors: Dictionary,
	active_city_ids: Array
) -> bool:
	if (
		sectors.size() != active_city_ids.size()
		or topology.edge_neighbors_by_city.size()
			!= active_city_ids.size()
	):
		return false
	for city_id_value in active_city_ids:
		var city_id := int(city_id_value)
		var sector: FrontierDefenseSector = sectors.get(city_id)
		if (
			sector == null
			or sector.owner_nation != view.nation_id
			or not topology.edge_neighbors_by_city.has(
				city_id
			)
			or sector.edge_neighbors
				!= topology.edge_neighbors_by_city[city_id]
		):
			return false
	return true


func _refresh_frontier_sector_runtime(
	sector: FrontierDefenseSector,
	city_id: int
) -> void:
	for slot_index in range(sector.slot_count()):
		var army_id := sector.assigned_army_at(slot_index)
		if (
			army_id >= 0
			and _friendly_line_army_by_id(army_id) == null
		):
			sector.clear_slot(slot_index)
	if view.state.city_under_siege(city_id):
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
	elif sector.state in [
		FrontierDefenseSector.State.RECALLING,
		FrontierDefenseSector.State.DEFENDING,
	]:
		sector.state = FrontierDefenseSector.State.RESTORING


func _frontier_sector_edges(city_id: int) -> Array[int]:
	var result: Array[int] = []
	for neighbor in view.state.neighbors(city_id):
		var edge := view.state.edge_of(city_id, neighbor)
		if (
			edge == null
			or edge.max_manpower <= 0
			or not edge.allows_holding
			or view.state.cities[neighbor].owner_nation
				== view.nation_id
		):
			continue
		var enemy_edge := view.state.is_enemy(
			view.nation_id,
			view.state.cities[neighbor].owner_nation
		)
		var potential_edge := (
			snapshot.potential_frontier_edges.has(edge)
		)
		if enemy_edge or potential_edge:
			result.append(neighbor)
	var preferred := preferred_edge_at(city_id)
	result.sort_custom(func(a: int, b: int) -> bool:
		var score_a := _frontier_edge_rank(
			city_id,
			a,
			preferred
		)
		var score_b := _frontier_edge_rank(
			city_id,
			b,
			preferred
		)
		if not is_equal_approx(score_a, score_b):
			return score_a > score_b
		return EquivariantOrder.city_id_less(
			view.state,
			view.nation_id,
			a,
			b,
			city_id
		)
	)
	return result


func _frontier_edge_rank(
	city_id: int,
	neighbor: int,
	preferred: int
) -> float:
	var edge := view.state.edge_of(city_id, neighbor)
	return (
		(1000.0 if neighbor == preferred else 0.0)
		+ snapshot.value_of_edge(city_id, neighbor)
		+ snapshot.potential_threat_of_edge(city_id, neighbor)
		+ (edge.danger if edge != null else 0.0)
	)


func _friendly_line_army_by_id(army_id: int) -> Army:
	if army_id < 0:
		return null
	if not _friendly_line_army_index_ready:
		for army in view.friendly_armies:
			if army.size > 0 and army.is_line_role():
				_friendly_line_army_by_id_cache[army.id] = army
		_friendly_line_army_index_ready = true
	return _friendly_line_army_by_id_cache.get(army_id)


func _build_role_defense_slots() -> Array[Dictionary]:
	_reconcile_frontier_defense_sectors()
	if _small_nation_survival_mode():
		return _build_small_nation_defense_slots()
	var result: Array[Dictionary] = []
	var screened_cities := {}
	var frontier_ids: Array = (
		topology.primary_city_ids.duplicate()
		if topology != null
		else snapshot.frontier_cities.duplicate()
	)
	if topology == null:
		for city_id_value in snapshot.potential_frontier_cities:
			if not frontier_ids.has(city_id_value):
				frontier_ids.append(city_id_value)
	_sort_role_city_ids(frontier_ids)
	var sectors: Dictionary = (
		view.state.nations[view.nation_id]
			.frontier_defense_sectors
	)
	for city_id_value in frontier_ids:
		var city_id := int(city_id_value)
		var sector: FrontierDefenseSector = sectors.get(city_id)
		if sector == null:
			continue
		required_power[city_id] = maxf(
			requirement_at(city_id),
			FRONTIER_SCREEN_POWER
		)
		result.append({
			"city_id": city_id,
			"posture": Posture.CITY,
			"edge_neighbor": -1,
			"priority": 0,
			"sector_city": city_id,
			"sector_slot": 0,
		})
		screened_cities[city_id] = true
	var max_edge_slots := 0
	for city_id_value in frontier_ids:
		var sector: FrontierDefenseSector = sectors.get(
			int(city_id_value)
		)
		if sector != null:
			max_edge_slots = maxi(
				max_edge_slots,
				sector.edge_neighbors.size()
			)
	for edge_layer in range(max_edge_slots):
		for city_id_value in frontier_ids:
			var city_id := int(city_id_value)
			var sector: FrontierDefenseSector = sectors.get(city_id)
			if (
				sector == null
				or edge_layer >= sector.edge_neighbors.size()
			):
				continue
			result.append({
				"city_id": city_id,
				"posture": Posture.EDGE,
				"edge_neighbor": sector.edge_neighbors[
					edge_layer
				],
				"priority": edge_layer + 1,
				"sector_city": city_id,
				"sector_slot": edge_layer + 1,
			})
	var strategic_ids: Array = []
	for city in view.friendly_cities:
		if (
			screened_cities.has(city.id)
			or not _is_line_strategic_city(city.id)
		):
			continue
		strategic_ids.append(city.id)
	_sort_role_city_ids(strategic_ids)
	for city_id_value in strategic_ids:
		var city_id := int(city_id_value)
		required_power[city_id] = maxf(
			requirement_at(city_id),
			FRONTIER_SCREEN_POWER * 0.5
		)
		result.append({
			"city_id": city_id,
			"posture": Posture.CITY,
			"edge_neighbor": -1,
			"priority": max_edge_slots + 1,
		})
		screened_cities[city_id] = true
	if result.is_empty():
		var fallback_ids := required_power.keys()
		_sort_role_city_ids(fallback_ids)
		for city_id_value in fallback_ids:
			result.append({
				"city_id": int(city_id_value),
				"posture": Posture.CITY,
				"edge_neighbor": -1,
				"priority": 3,
			})
	return result


func _small_nation_survival_mode() -> bool:
	return (
		not view.state.wars_of(view.nation_id).is_empty()
		and view.friendly_cities.size()
			<= SMALL_NATION_SURVIVAL_MAX_CITIES
	)


func _build_small_nation_defense_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var city_ids: Array = []
	for city in view.friendly_cities:
		city_ids.append(city.id)
	_sort_role_city_ids(city_ids)
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		required_power[city_id] = maxf(
			requirement_at(city_id),
			FRONTIER_SCREEN_POWER
		)
		result.append({
			"city_id": city_id,
			"posture": Posture.CITY,
			"edge_neighbor": -1,
			"priority": 0,
		})
	# 平时保留最后一支机动军反攻；只有城市已经被围时才把机动军投入第二守城槽。
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		if not view.state.city_under_siege(city_id):
			continue
		result.append({
			"city_id": city_id,
			"posture": Posture.CITY,
			"edge_neighbor": -1,
			"priority": 0,
		})
		break
	return result


func _append_city_role_slots(
	slots: Array[Dictionary],
	city_ids: Array,
	screened_cities: Dictionary,
	priority: int
) -> void:
	_sort_role_city_ids(city_ids)
	for city_id_value in city_ids:
		var city_id := int(city_id_value)
		if screened_cities.has(city_id):
			continue
		required_power[city_id] = maxf(
			requirement_at(city_id),
			FRONTIER_SCREEN_POWER
		)
		slots.append({
			"city_id": city_id,
			"posture": Posture.CITY,
			"edge_neighbor": -1,
			"priority": priority,
		})
		screened_cities[city_id] = true


func _sort_role_city_ids(city_ids: Array) -> void:
	city_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var city_a := int(a)
		var city_b := int(b)
		var score_a := _line_city_priority(city_a)
		var score_b := _line_city_priority(city_b)
		if not is_equal_approx(score_a, score_b):
			return score_a > score_b
		return EquivariantOrder.city_id_less(
			view.state,
			view.nation_id,
			city_a,
			city_b
		)
	)


func _line_city_priority(city_id: int) -> float:
	if _role_city_priority_cache.has(city_id):
		return float(
			_role_city_priority_cache[city_id]
		)
	# 基础重要性（城市价值 + 补给枢纽价值）按地理区位放大：优先部署在
	# 离国境、离首都都近的重要城市。威胁项是对敌情的即时反应，不参与地理修正。
	var base_importance := (
		snapshot.value_of_city(city_id) * 100.0
		+ snapshot.supply_importance_at(city_id) * 100.0
	)
	var priority := (
		maxf(threat.threat_at(city_id), 0.0)
		+ maxf(
			snapshot.potential_threat_at(city_id),
			0.0
		)
		+ base_importance * _strategic_proximity_factor(city_id)
	)
	_role_city_priority_cache[city_id] = priority
	return priority


## 地理区位修正因子 ∈ [MIN_FACTOR, 1]：离国境越近、离首都越近，因子越大。
## 两个方向以加权和合成，任一方向靠近都能提升，但同时靠近收益最高。
func _strategic_proximity_factor(city_id: int) -> float:
	_ensure_proximity_fields()
	var border_factor := _hop_decay(
		_border_hop_distance.get(city_id, INF)
	)
	var capital_factor := _hop_decay(
		_capital_hop_distance.get(city_id, INF)
	)
	var factor := (
		STRATEGIC_BORDER_PROXIMITY_WEIGHT * border_factor
		+ STRATEGIC_CAPITAL_PROXIMITY_WEIGHT * capital_factor
	)
	return clampf(factor, STRATEGIC_PROXIMITY_MIN_FACTOR, 1.0)


static func _hop_decay(hops: float) -> float:
	if hops == INF:
		return 0.0
	return exp(-maxf(hops, 0.0) / STRATEGIC_PROXIMITY_DECAY_HOPS)


## 在本国领土内做两次 BFS 跳数场：到最近国界城市、到首都。只按本国可通行边
## 扩散，与填线军实际可达范围一致。territory 不变时随规划缓存复用。
func _ensure_proximity_fields() -> void:
	if _proximity_fields_ready:
		return
	_proximity_fields_ready = true
	var border_sources: Array[int] = []
	for city_id in snapshot.frontier_cities:
		border_sources.append(int(city_id))
	for city_id in snapshot.potential_frontier_cities:
		if not border_sources.has(int(city_id)):
			border_sources.append(int(city_id))
	_border_hop_distance = _friendly_hop_field(border_sources)
	var capital := view.capital_city_id
	var capital_sources: Array[int] = []
	if (
		capital >= 0
		and capital < view.state.cities.size()
		and view.state.cities[capital].owner_nation
			== view.nation_id
	):
		capital_sources.append(capital)
	_capital_hop_distance = _friendly_hop_field(capital_sources)


## 多源 BFS 跳数场，仅在本国领土、沿可驻守（正容量）边扩散。源点顺序不影响
## 最短跳数结果，因而无需等变排序即保持确定性。
func _friendly_hop_field(sources: Array[int]) -> Dictionary:
	var dist := {}
	var frontier: Array[int] = []
	for source in sources:
		if (
			source >= 0
			and source < view.state.cities.size()
			and view.state.cities[source].owner_nation
				== view.nation_id
			and not dist.has(source)
		):
			dist[source] = 0
			frontier.append(source)
	var head := 0
	while head < frontier.size():
		var city_id := frontier[head]
		head += 1
		var next_hops := int(dist[city_id]) + 1
		for neighbor in view.state.neighbors(city_id):
			if dist.has(neighbor):
				continue
			if view.state.cities[neighbor].owner_nation != view.nation_id:
				continue
			var edge := view.state.edge_of(city_id, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			dist[neighbor] = next_hops
			frontier.append(neighbor)
	return dist


func _line_edge_for_city(city_id: int) -> int:
	var preferred := preferred_edge_at(city_id)
	var preferred_edge := view.state.edge_of(city_id, preferred)
	if (
		preferred >= 0
		and preferred_edge != null
		and preferred_edge.allows_holding
		and view.state.cities[preferred].owner_nation
			!= view.nation_id
	):
		return preferred
	var best_neighbor := -1
	var best_score := -INF
	var neighbors := view.state.neighbors(city_id).duplicate()
	EquivariantOrder.sort_city_ids(
		neighbors,
		view.state,
		view.nation_id,
		city_id
	)
	for neighbor_value in neighbors:
		var neighbor := int(neighbor_value)
		var edge := view.state.edge_of(city_id, neighbor)
		if (
			edge == null
			or not edge.allows_holding
			or view.state.cities[neighbor].owner_nation
				== view.nation_id
		):
			continue
		var score := (
			snapshot.value_of_edge(city_id, neighbor)
			+ snapshot.potential_threat_of_edge(
				city_id,
				neighbor
			)
			+ edge.danger
		)
		if score > best_score:
			best_score = score
			best_neighbor = neighbor
	return best_neighbor


func _is_line_strategic_city(city_id: int) -> bool:
	var city := view.state.cities[city_id]
	return (
		city.is_dock
		or city.fort_strength_max >= 24
		or _is_strategic_must_hold_city(city_id)
	)


func _role_assignment_distance(
	army: Army,
	city_id: int,
	posture: int,
	edge_neighbor: int
) -> float:
	if army.state == Army.State.MOVING:
		if (
			posture == Posture.EDGE
			and army.ai_action == ActionCandidate.Kind.HOLD
			and city_id in [army.move_from, army.move_to]
			and edge_neighbor in [army.move_from, army.move_to]
		):
			return -3.0
		if army.ai_target_city != city_id:
			return INF
		var moving_to_edge := army.ai_order_reason.contains(
			"国界边锚点"
		)
		if (
			(posture == Posture.EDGE) != moving_to_edge
			and army.ai_action
				!= ActionCandidate.Kind.RETREAT
		):
			return INF
		return -2.5
	var origin := army.location_city
	if army.state == Army.State.HOLDING:
		origin = army.move_from
		if not view.state.has_military_access(
			view.nation_id,
			view.state.cities[origin].owner_nation
		):
			origin = army.move_to
		if (
			posture == Posture.EDGE
			and city_id in [army.move_from, army.move_to]
			and edge_neighbor in [army.move_from, army.move_to]
		):
			return -2.0
	if origin < 0:
		return INF
	if army.state == Army.State.RECOVERING:
		if origin != city_id:
			return INF
		return -1.5 if posture == Posture.EDGE else -0.5
	if posture == Posture.CITY and origin == city_id:
		return -1.0
	if not _role_path_dist_by_origin.has(origin):
		var field := view.path_field(
			origin,
			view.nation_id,
			false,
			true,
			-1,
			army.max_size
		)
		_role_path_dist_by_origin[origin] = (
			field["dist"] as Dictionary
		)
	var distances: Dictionary = (
		_role_path_dist_by_origin[origin]
	)
	return float(
		distances.get(city_id, INF)
	)


func _assigned_defense_candidate(
	army: Army,
	city_id: int,
	assigned_posture: int,
	assigned_edge: int
) -> ActionCandidate:
	var origin := army.location_city
	if army.state == Army.State.HOLDING:
		origin = army.move_from
		if not view.state.has_military_access(
			view.nation_id,
			view.state.cities[origin].owner_nation
		):
			origin = army.move_to
		if (
			origin == city_id
			and assigned_posture == Posture.EDGE
			and assigned_edge in [
				army.move_from,
				army.move_to,
			]
		):
			return null
		var retreat := ActionCandidate.make(
			ActionCandidate.Kind.RETREAT,
			ROLE_DEPLOYMENT_SCORE,
			"填线部署：回到国界城市%d" % city_id,
			city_id
		)
		retreat.minimum_commit_days = STRATEGIC_COMMIT_DAYS
		retreat.defensive_deployment = true
		return retreat
	if army.state != Army.State.IDLE or origin < 0:
		return null
	if origin == city_id:
		if (
			assigned_posture == Posture.EDGE
			and assigned_edge >= 0
		):
			var edge_candidate := _edge_hold_candidate(
				army,
				city_id,
				assigned_edge
			)
			if edge_candidate != null:
				edge_candidate.score = ROLE_DEPLOYMENT_SCORE
				edge_candidate.reason = (
					"填线部署：驻守国界城市%d至城市%d的道路"
					% [city_id, assigned_edge]
				)
			return edge_candidate
		return ActionCandidate.make(
			ActionCandidate.Kind.NONE,
			ROLE_DEPLOYMENT_SCORE,
			"填线部署：留守城市%d" % city_id,
			city_id
		)
	var reinforce := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		ROLE_DEPLOYMENT_SCORE,
		(
			"填线部署：5000编制军调往国界边锚点城市%d"
			if assigned_posture == Posture.EDGE
			else "填线部署：5000编制军调往城市%d"
		) % city_id,
		city_id
	)
	reinforce.minimum_commit_days = STRATEGIC_COMMIT_DAYS
	reinforce.defensive_deployment = true
	return reinforce


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
		if view.enemy_armies.is_empty():
			if pressure > 0.0:
				result[neighbor] = pressure
			continue
		for enemy in view.enemy_armies_on_edge(
			city_id,
			neighbor
		):
			var power := ArmyPower.effective(enemy)
			if power <= 0.0:
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
		for enemy in view.enemy_armies_at_city(neighbor):
			if edge.max_manpower < enemy.max_size:
				continue
			var power := ArmyPower.effective(enemy)
			if power <= 0.0:
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
	if view.enemy_armies.is_empty():
		return 0.0
	var result := 0.0
	for enemy in view.enemy_armies_at_city(city_id):
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
	var edge := view.state.edge_of(city_id, neighbor)
	if edge == null or not edge.allows_holding:
		return null
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
		snapshot.supply_importance_at(city_id) > 0.0
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
	return Simulation.edge_travel_days(edge)
