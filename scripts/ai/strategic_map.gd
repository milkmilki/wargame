class_name StrategicMapSnapshot
extends RefCounted
## 国家级战略地图。所有字段均为派生缓存，不写回 GameState。

## 敌对前线边地形据守加成权重：乘在 (terrain_hold_bias(danger,0)-1) 上。取 4.0 使加成幅度
## 与历史线性 danger*2.0 在 danger=0/1 端点对齐（bias-1 在 danger=1 约 0.5，×4≈2.0），
## 差异仅在曲线形状——凸曲线令中段更低、隘口带更陡。是可调的单一权重真源。
const EDGE_TERRAIN_HOLD_GAIN: float = 4.0

## AB 实验开关（默认 true=生产行为）：敌对前线边地形加成是否用 terrain_hold_bias 凸曲线。
## 关闭时退回历史线性 danger*2.0，仅供地形收益 A/B 长跑对照，不影响生产与确定性回归。
static var terrain_hold_bias_enabled: bool = true

var nation_id: int
var ownership_revision: int
var strategic_planning_enabled: bool
var city_value: Dictionary = {}            ## city_id -> float
var edge_value: Dictionary = {}            ## normalized edge key -> float
var bridge_impact: Dictionary = {}         ## edge key -> 被切断友城价值
var articulation_impact: Dictionary = {}   ## city_id -> 被切断友城价值
var corridor_flow: Dictionary = {}         ## edge key -> 粮仓到前线的路径计数
var supply_corridor_importance: Dictionary = {} ## city_id -> 0~1 粮道节点重要度
var critical_supply_cities: Array[int] = []
var frontier_edges: Array[Edge] = []
var frontier_cities: Array[int] = []
var frontier_enemy_cities: Array[int] = []
var potential_frontier_edges: Array[Edge] = []
var potential_frontier_cities: Array[int] = []
var potential_border_threat: Dictionary = {} ## friendly city_id -> float
var potential_edge_threat: Dictionary = {}   ## edge key -> dimensionless threat
var priority_enemy_cities: Array[int] = []
var offensive_value: Dictionary = {}       ## enemy city_id -> 两层占领后战略价值
var campaign_target: int = -1               ## 国家级主战役目标

var _state: GameState
var _view: AiWorldView
var _disc: Dictionary = {}
var _low: Dictionary = {}
var _subtree_value: Dictionary = {}
var _time: int = 0
var _total_friendly_value: float = 0.0



static func build(
	view: AiWorldView,
	diplomacy_cache: Dictionary = {},
	shared_city_values: Dictionary = {},
	shared_edge_values: Dictionary = {},
	build_profile: Dictionary = {}
) -> StrategicMapSnapshot:
	var profile_enabled: bool = bool(
		build_profile.get("enabled", false)
	)
	var build_total_started: int = (
		Time.get_ticks_usec() if profile_enabled else 0
	)
	var snapshot := StrategicMapSnapshot.new()
	var stage_started: int = 0
	var accounted_usec: int = 0
	snapshot.nation_id = view.nation_id
	snapshot.ownership_revision = view.state.ownership_revision
	snapshot.strategic_planning_enabled = view.strategic_planning_enabled
	snapshot._state = view.state
	snapshot._view = view
	if profile_enabled:
		stage_started = Time.get_ticks_usec()
	snapshot._initialize_city_values(shared_city_values)
	if profile_enabled:
		var elapsed_usec := Time.get_ticks_usec() - stage_started
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_initialize",
			elapsed_usec
		)
		accounted_usec += elapsed_usec
		stage_started = Time.get_ticks_usec()
	snapshot._find_frontier(diplomacy_cache, build_profile)
	if profile_enabled:
		var elapsed_usec := Time.get_ticks_usec() - stage_started
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_frontier",
			elapsed_usec
		)
		accounted_usec += elapsed_usec
		stage_started = Time.get_ticks_usec()
	snapshot._compute_connectivity()
	if profile_enabled:
		var elapsed_usec := Time.get_ticks_usec() - stage_started
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_connectivity",
			elapsed_usec
		)
		accounted_usec += elapsed_usec
		stage_started = Time.get_ticks_usec()
	snapshot._compute_supply_corridors(view)
	if profile_enabled:
		var elapsed_usec := Time.get_ticks_usec() - stage_started
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_supply_corridors",
			elapsed_usec
		)
		accounted_usec += elapsed_usec
		stage_started = Time.get_ticks_usec()
	snapshot._finalize_edge_values(shared_edge_values)
	if profile_enabled:
		var elapsed_usec := Time.get_ticks_usec() - stage_started
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_finalize_edges",
			elapsed_usec
		)
		accounted_usec += elapsed_usec
		stage_started = Time.get_ticks_usec()
	snapshot._compute_offensive_values(view, diplomacy_cache)
	if profile_enabled:
		var elapsed_usec := Time.get_ticks_usec() - stage_started
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_offensive",
			elapsed_usec
		)
		accounted_usec += elapsed_usec
		stage_started = Time.get_ticks_usec()
	snapshot._select_priority_targets(view)
	if profile_enabled:
		var elapsed_usec := Time.get_ticks_usec() - stage_started
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_priority",
			elapsed_usec
		)
		accounted_usec += elapsed_usec
		var build_total_usec := (
			Time.get_ticks_usec() - build_total_started
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_build_total",
			build_total_usec
		)
		_accumulate_build_profile(
			build_profile,
			"ai_snapshot_unaccounted",
			maxi(build_total_usec - accounted_usec, 0)
		)
	return snapshot


static func _accumulate_build_profile(
	build_profile: Dictionary,
	stage: String,
	elapsed_usec: int
) -> void:
	if not bool(build_profile.get("enabled", false)):
		return
	build_profile[stage] = (
		int(build_profile.get(stage, 0))
		+ elapsed_usec
	)


static func build_base_city_values(state: GameState) -> Dictionary:
	var max_gold := 1
	var max_food := 1
	for city in state.cities:
		max_gold = maxi(max_gold, city.gold_per_month)
		max_food = maxi(max_food, city.food_per_half_year)
	var result := {}
	for city in state.cities:
		var value := (
			float(city.gold_per_month) / float(max_gold)
			+ float(city.food_per_half_year) / float(max_food)
			+ float(city.fort_strength) / 30.0 * 0.25
		)
		if city.is_capital:
			value += 5.0
		if city.has_warehouse:
			value += 3.0 + minf(float(city.food_storage) / 1000.0, 2.0)
		if city.is_food_hub:
			value += 4.0
		if city.is_manpower_hub:
			value += 4.0
		result[city.id] = value
	return result


## 道路危险、容量与关隘价值在运行期不随观察国变化。AI tick 内共享这部分，
## 国家快照只叠加本国城市、边境、桥梁和粮道价值。
static func build_base_edge_values(state: GameState) -> Dictionary:
	var result := {}
	for edge in state.edges:
		var capacity_units := (
			float(edge.max_manpower)
				/ float(Edge.STANDARD_MANPOWER)
		)
		var value := (
			edge.danger
			+ 0.75 * maxf(capacity_units - 1.0, 0.0)
		)
		if (
			edge.max_manpower > 0
			and edge.danger
				>= Combat.CHOKEPOINT_DANGER_ONSET
		):
			value += 4.0
		result[_edge_key(edge.city_a, edge.city_b)] = value
	return result


func _initialize_city_values(shared_city_values: Dictionary) -> void:
	city_value = (
		shared_city_values.duplicate()
		if not shared_city_values.is_empty()
		else build_base_city_values(_state)
	)
	for city in _view.friendly_cities:
		var value := float(city_value.get(city.id, 0.0))
		if city.owner_nation == nation_id:
			_total_friendly_value += value


func _find_frontier(
	diplomacy_cache: Dictionary = {},
	build_profile: Dictionary = {}
) -> void:
	var profile_enabled := bool(build_profile.get("enabled", false))
	var stage_started := Time.get_ticks_usec() if profile_enabled else 0
	var frontier_seen := {}
	var enemy_seen := {}
	var neutral_cities_by_nation := {}
	var neutral_edges_by_nation := {}
	for friendly_city in _view.friendly_cities:
		var friendly_id := friendly_city.id
		for other_id in _state.neighbors(friendly_id):
			var other_nation := _state.cities[other_id].owner_nation
			if other_nation == nation_id:
				continue
			var edge := _state.edge_of(friendly_id, other_id)
			if edge == null or edge.max_manpower <= 0:
				continue
			if _state.is_enemy(nation_id, other_nation):
				frontier_edges.append(edge)
				if not frontier_seen.has(friendly_id):
					frontier_seen[friendly_id] = true
					frontier_cities.append(friendly_id)
				if not enemy_seen.has(other_id):
					enemy_seen[other_id] = true
					frontier_enemy_cities.append(other_id)
			elif (
				_state.relation_between(
					nation_id,
					other_nation
				) == GameState.DiplomaticRelation.NEUTRAL
			):
				if not neutral_cities_by_nation.has(other_nation):
					neutral_cities_by_nation[other_nation] = {}
					neutral_edges_by_nation[other_nation] = []
				neutral_cities_by_nation[other_nation][
					friendly_id
				] = true
				neutral_edges_by_nation[other_nation].append(
					edge
				)
	if profile_enabled:
		_accumulate_build_profile(
			build_profile, "ai_snapshot_frontier_scan",
			Time.get_ticks_usec() - stage_started
		)
		stage_started = Time.get_ticks_usec()
	var neutral_nations := neutral_cities_by_nation.keys()
	neutral_nations.sort_custom(func(a, b) -> bool:
		return EquivariantOrder.nation_less(
			_state,
			nation_id,
			int(a),
			int(b)
		)
	)
	var potential_seen := {}
	# 复用跨国共享的外交评估缓存：resource_report / _national_power / _troop_count
	# 等按 nation_id 记忆的全局事实在同一 AI tick 内只算一次，避免每国重复扫全军。
	var diplomacy_evaluation_cache := diplomacy_cache
	for other_nation_value in neutral_nations:
		var other_nation := int(other_nation_value)
		var threat_cached := false
		if profile_enabled:
			var threat_cache_key := "threat:%d:%d" % [
				nation_id, other_nation
			]
			threat_cached = diplomacy_evaluation_cache.has(
				threat_cache_key
			)
		var threat_started := Time.get_ticks_usec() if profile_enabled else 0
		var threat_score := DiplomacyAI.threat_from_nation(
			_state,
			nation_id,
			other_nation,
			diplomacy_evaluation_cache
		)
		if profile_enabled:
			var threat_elapsed := Time.get_ticks_usec() - threat_started
			_accumulate_build_profile(
				build_profile, "ai_snapshot_frontier_threat_score",
				threat_elapsed
			)
			_accumulate_build_profile(
				build_profile,
				("ai_snapshot_frontier_threat_hit_time"
					if threat_cached
					else "ai_snapshot_frontier_threat_miss_time"),
				threat_elapsed
			)
			build_profile["ai_snapshot_frontier_threat_queries"] = (
				int(build_profile.get(
					"ai_snapshot_frontier_threat_queries", 0
				)) + 1
			)
			var result_count_key := (
				"ai_snapshot_frontier_threat_hits"
				if threat_cached
				else "ai_snapshot_frontier_threat_misses"
			)
			build_profile[result_count_key] = int(
				build_profile.get(result_count_key, 0)
			) + 1
		if threat_score < 1.0:
			continue
		var concentration_started := (
			Time.get_ticks_usec() if profile_enabled else 0
		)
		var border_city_ids: Array = neutral_cities_by_nation[other_nation].keys()
		EquivariantOrder.sort_city_ids(
			border_city_ids,
			_state,
			nation_id
		)
		var deployable_power := _army_power_of(other_nation)
		var per_city_power := (
			deployable_power
			/ float(maxi(border_city_ids.size(), 1))
			* clampf(threat_score / 2.0, 0.25, 1.0)
		)
		for city_id_value in border_city_ids:
			var city_id := int(city_id_value)
			var local_concentration := _neutral_border_concentration(
				other_nation,
				city_id
			)
			potential_border_threat[city_id] = (
				float(potential_border_threat.get(city_id, 0.0))
				+ maxf(per_city_power, local_concentration)
			)
			if not potential_seen.has(city_id):
				potential_seen[city_id] = true
				potential_frontier_cities.append(city_id)
		for edge in neutral_edges_by_nation[other_nation]:
			if not potential_frontier_edges.has(edge):
				potential_frontier_edges.append(edge)
			potential_edge_threat[_edge_key(edge.city_a, edge.city_b)] = threat_score
		if profile_enabled:
			_accumulate_build_profile(
				build_profile, "ai_snapshot_frontier_concentration",
				Time.get_ticks_usec() - concentration_started
			)
	if profile_enabled:
		_accumulate_build_profile(
			build_profile, "ai_snapshot_frontier_threat",
			Time.get_ticks_usec() - stage_started
		)
		stage_started = Time.get_ticks_usec()
	EquivariantOrder.sort_edges(
		frontier_edges,
		_state,
		nation_id
	)
	EquivariantOrder.sort_edges(
		potential_frontier_edges,
		_state,
		nation_id
	)
	EquivariantOrder.sort_city_ids(frontier_cities, _state, nation_id)
	EquivariantOrder.sort_city_ids(
		frontier_enemy_cities,
		_state,
		nation_id
	)
	EquivariantOrder.sort_city_ids(
		potential_frontier_cities,
		_state,
		nation_id
	)
	if profile_enabled:
		_accumulate_build_profile(
			build_profile, "ai_snapshot_frontier_sort",
			Time.get_ticks_usec() - stage_started
		)


func _army_power_of(owner_nation: int) -> float:
	return float(
		_view.army_power_by_nation.get(owner_nation, 0.0)
	)


func _neutral_border_concentration(
	other_nation: int,
	friendly_city: int
) -> float:
	var total := 0.0
	for neighbor in _state.neighbors(friendly_city):
		var edge := _state.edge_of(friendly_city, neighbor)
		if (
			edge == null
			or edge.max_manpower <= 0
			or _state.cities[neighbor].owner_nation != other_nation
		):
			continue
		for army in _view.armies_at_or_on_city(neighbor):
			if army.owner_nation != other_nation:
				continue
			if (
				army.state in [
					Army.State.IDLE,
					Army.State.RECOVERING,
				]
				and army.location_city == neighbor
			) or (
				army.state == Army.State.HOLDING
				and (
					(army.move_from == neighbor and army.move_to == friendly_city)
					or (
						army.move_to == neighbor
						and army.move_from == friendly_city
					)
				)
			):
				total += ArmyPower.effective(army)
	return total


func _compute_connectivity() -> void:
	_disc.clear()
	_low.clear()
	_subtree_value.clear()
	_time = 0
	var roots: Array[int] = []
	var capital := _state.nations[nation_id].capital_city_id
	if capital >= 0 and _state.cities[capital].owner_nation == nation_id:
		roots.append(capital)
	for city in _state.cities:
		if city.owner_nation == nation_id and city.id != capital:
			roots.append(city.id)
	EquivariantOrder.sort_city_ids(roots, _state, nation_id, capital)
	for root in roots:
		if _disc.has(root):
			continue
		_dfs_connectivity_iterative(root)
	var articulation_ids := articulation_impact.keys()
	EquivariantOrder.sort_city_ids(
		articulation_ids,
		_state,
		nation_id,
		capital
	)
	for city_id in articulation_ids:
		city_value[city_id] = (
			float(city_value[city_id])
			+ 2.0 * float(articulation_impact[city_id]) / maxf(_total_friendly_value, 0.001)
		)


func _dfs_connectivity_iterative(root: int) -> void:
	var parent := {root: -1}
	var child_count := {root: 0}
	_discover_connectivity_node(root)
	var stack: Array[Dictionary] = [{
		"city": root,
		"index": 0,
		"neighbors": _friendly_neighbors(root),
	}]
	while not stack.is_empty():
		var frame: Dictionary = stack[stack.size() - 1]
		var city_id: int = frame["city"]
		var neighbors: Array[int] = frame["neighbors"]
		var index: int = frame["index"]
		if index < neighbors.size():
			var neighbor := neighbors[index]
			frame["index"] = index + 1
			if neighbor == int(parent[city_id]):
				continue
			if not _disc.has(neighbor):
				parent[neighbor] = city_id
				child_count[city_id] = int(child_count.get(city_id, 0)) + 1
				child_count[neighbor] = 0
				_discover_connectivity_node(neighbor)
				stack.append({
					"city": neighbor,
					"index": 0,
					"neighbors": _friendly_neighbors(neighbor),
				})
			else:
				_low[city_id] = mini(int(_low[city_id]), int(_disc[neighbor]))
			continue

		stack.pop_back()
		var parent_id: int = parent[city_id]
		if parent_id == -1:
			if int(child_count[city_id]) > 1:
				articulation_impact[city_id] = (
					float(_subtree_value[city_id])
					- float(city_value.get(city_id, 0.0))
				)
			continue
		_subtree_value[parent_id] = (
			float(_subtree_value[parent_id]) + float(_subtree_value[city_id])
		)
		_low[parent_id] = mini(int(_low[parent_id]), int(_low[city_id]))
		if int(_low[city_id]) > int(_disc[parent_id]):
			bridge_impact[_edge_key(parent_id, city_id)] = float(_subtree_value[city_id])
		if int(parent[parent_id]) != -1 and int(_low[city_id]) >= int(_disc[parent_id]):
			articulation_impact[parent_id] = (
				float(articulation_impact.get(parent_id, 0.0))
				+ float(_subtree_value[city_id])
			)


func _discover_connectivity_node(city_id: int) -> void:
	_time += 1
	_disc[city_id] = _time
	_low[city_id] = _time
	_subtree_value[city_id] = float(city_value.get(city_id, 0.0))


func _friendly_neighbors(city_id: int) -> Array[int]:
	var result: Array[int] = []
	for neighbor in _state.neighbors(city_id):
		if _state.cities[neighbor].owner_nation != nation_id:
			continue
		var edge := _state.edge_of(city_id, neighbor)
		if edge == null or edge.max_manpower <= 0:
			continue
		result.append(neighbor)
	EquivariantOrder.sort_city_subset(
		result,
		_state,
		nation_id,
		city_id
	)
	return result


func _compute_supply_corridors(view: AiWorldView) -> void:
	var defended_cities: Array[int] = frontier_cities.duplicate()
	for city_id in potential_frontier_cities:
		if not defended_cities.has(city_id):
			defended_cities.append(city_id)
	EquivariantOrder.sort_city_ids(
		defended_cities,
		_state,
		nation_id
	)
	if defended_cities.is_empty():
		return
	for warehouse in view.warehouses:
		var field := view.path_field(
			warehouse.id,
			nation_id,
			false,
			true
		)
		var prev: Dictionary = field["prev"]
		for frontier_id in defended_cities:
			var path := Pathfinding.reconstruct(prev, warehouse.id, frontier_id)
			var from_id := warehouse.id
			for to_id in path:
				var key := _edge_key(from_id, to_id)
				corridor_flow[key] = float(corridor_flow.get(key, 0.0)) + 1.0
				from_id = to_id


func _finalize_edge_values(shared_edge_values: Dictionary = {}) -> void:
	edge_value = (
		shared_edge_values.duplicate()
		if not shared_edge_values.is_empty()
		else build_base_edge_values(_state)
	)
	var max_flow := 1.0
	for value in corridor_flow.values():
		max_flow = maxf(max_flow, float(value))
	var max_bridge_impact := 0.001
	for value in bridge_impact.values():
		max_bridge_impact = maxf(max_bridge_impact, float(value))
	var relevant_edges: Array[Edge] = []
	var relevant_edge_keys := {}
	for city in _view.friendly_cities:
		for neighbor in _state.neighbors(city.id):
			var edge := _state.edge_of(city.id, neighbor)
			if edge == null:
				continue
			var edge_key := _edge_key(edge.city_a, edge.city_b)
			if relevant_edge_keys.has(edge_key):
				continue
			relevant_edge_keys[edge_key] = true
			relevant_edges.append(edge)
	for edge in relevant_edges:
		var key := _edge_key(edge.city_a, edge.city_b)
		var owner_a := _state.cities[edge.city_a].owner_nation
		var owner_b := _state.cities[edge.city_b].owner_nation
		var value := float(edge_value.get(key, 0.0))
		if owner_a == nation_id:
			value += 0.15 * float(city_value.get(edge.city_a, 0.0))
		if owner_b == nation_id:
			value += 0.15 * float(city_value.get(edge.city_b, 0.0))
		value += 3.0 * float(bridge_impact.get(key, 0.0)) / maxf(_total_friendly_value, 0.001)
		value += 2.0 * float(corridor_flow.get(key, 0.0)) / max_flow
		if (
			_state.is_enemy(owner_a, owner_b)
			and (owner_a == nation_id or owner_b == nation_id)
		):
			# 敌对前线边据守价值：基线 1.0（是条敌对前线边）+ 地形据守加成。
			# 加成改用 Combat.terrain_hold_bias 凸曲线（刚进驻 holding_days=0）而非历史线性
			# danger*2.0：两者在 danger=0/1 端点对齐（幅度均 [0,2]），但凸曲线令中等地形加权
			# 更低、真正的隘口带(danger≥0.85)加权更陡，与实战「唯隘口显著利守」的物理一致。
			# AB 关闭时退回历史线性项，用于隔离曲线形状的净收益。
			var terrain_gain := (
				(Combat.terrain_hold_bias(edge.danger, 0.0) - 1.0) * EDGE_TERRAIN_HOLD_GAIN
				if terrain_hold_bias_enabled
				else edge.danger * 2.0
			)
			value += 1.0 + terrain_gain
		value += 2.0 * float(potential_edge_threat.get(key, 0.0))
		edge_value[key] = value
		var normalized_flow := (
			float(corridor_flow.get(key, 0.0)) / max_flow
		)
		if normalized_flow <= 0.0:
			continue
		var bridge_share := clampf(
			float(bridge_impact.get(key, 0.0)) / max_bridge_impact,
			0.0,
			1.0
		)
		# 只有粮流与桥梁属性同时成立才形成硬守备需求。
		# 非桥梁高流量道路仍保留 edge_value 加分，但不钉死常驻军。
		var importance := clampf(
			normalized_flow * bridge_share,
			0.0,
			1.0
		)
		for city_id in [edge.city_a, edge.city_b]:
			if _state.cities[city_id].owner_nation != nation_id:
				continue
			supply_corridor_importance[city_id] = maxf(
				float(supply_corridor_importance.get(city_id, 0.0)),
				importance
			)
	for city_id_value in supply_corridor_importance:
		var city_id := int(city_id_value)
		if float(supply_corridor_importance[city_id]) >= 0.50:
			critical_supply_cities.append(city_id)
	EquivariantOrder.sort_city_ids(
		critical_supply_cities,
		_state,
		nation_id
	)


func _compute_offensive_values(
	view: AiWorldView, diplomacy_cache: Dictionary = {}
) -> void:
	for city_id in frontier_enemy_cities:
		var base := value_of_city(city_id)
		if not view.strategic_planning_enabled:
			offensive_value[city_id] = base
			continue
		var target_owner := _state.cities[city_id].owner_nation
		var friendly_links := 0
		var hostile_links := 0
		var gateway_value := 0.0
		for neighbor in _state.neighbors(city_id):
			var edge := _state.edge_of(city_id, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			var neighbor_owner := _state.cities[neighbor].owner_nation
			if neighbor_owner == nation_id:
				friendly_links += 1
			elif neighbor_owner == target_owner:
				hostile_links += 1
				if not frontier_enemy_cities.has(neighbor):
					gateway_value = maxf(gateway_value, value_of_city(neighbor))
		var defensive_gain := float(friendly_links - hostile_links)
		var exposure := maxi(hostile_links - friendly_links, 0)
		var gateway_bonus := 0.0
		if exposure <= 1:
			gateway_bonus = minf(gateway_value * 0.30, 1.5)
		var encirclement_value := DiplomacyAI.encirclement_value(
			_state,
			city_id,
			target_owner,
			diplomacy_cache
		)
		offensive_value[city_id] = (
			base
			+ maxf(defensive_gain, 0.0) * 1.5
			- float(exposure) * 1.5
			+ gateway_bonus
			+ encirclement_value
		)


func _select_priority_targets(view: AiWorldView) -> void:
	var scored: Array = []
	var diplomatic_targets := {}
	for enemy_id in _state.wars_of(nation_id):
		var objective := _state.war_objective(nation_id, enemy_id)
		if (
			not objective.is_empty()
			and int(objective.get("attacker", -1)) == nation_id
		):
			diplomatic_targets[int(objective["city_id"])] = true
	for city_id in frontier_enemy_cities:
		scored.append([
			value_of_offense(city_id)
				+ 2.0
				+ (4.0 if diplomatic_targets.has(city_id) else 0.0),
			city_id,
		])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		if not is_equal_approx(float(a[0]), float(b[0])):
			return float(a[0]) > float(b[0])
		return EquivariantOrder.city_id_less(
			_state,
			nation_id,
			int(a[1]),
			int(b[1])
		)
	)
	for i in range(scored.size()):
		priority_enemy_cities.append(int(scored[i][1]))
	if view.strategic_planning_enabled and not scored.is_empty():
		campaign_target = int(scored[0][1])


func value_of_city(city_id: int) -> float:
	return float(city_value.get(city_id, 0.0))


func value_of_offense(city_id: int) -> float:
	return float(offensive_value.get(city_id, value_of_city(city_id)))


func value_of_edge(a: int, b: int) -> float:
	return float(edge_value.get(_edge_key(a, b), 0.0))


func potential_threat_at(city_id: int) -> float:
	return float(potential_border_threat.get(city_id, 0.0))


func potential_threat_of_edge(a: int, b: int) -> float:
	return float(potential_edge_threat.get(_edge_key(a, b), 0.0))


func supply_importance_at(city_id: int) -> float:
	return float(supply_corridor_importance.get(city_id, 0.0))


static func _edge_key(a: int, b: int) -> int:
	return GameState.edge_key(a, b)
