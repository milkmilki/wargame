class_name Pathfinding
extends RefCounted
## 图上寻路工具（全静态）。8x8 小图，Dijkstra 足够。
## 边权 = distance + danger 惩罚，保证深入危险地形的路径代价更高。
## 单源 Dijkstra 一次算全场（field），避免对每个候选目标重复搜索。

const DANGER_WEIGHT: float = 2.0           ## danger 对边权的加成系数
const SUPPLY_DISTANCE_LOSS: float = 0.10   ## 每单位边长的基础运输损耗
const SUPPLY_DANGER_MULT: float = 1.0      ## danger 对该边距离损耗的乘性放大系数

## 单源最短路场：返回 { "dist": {id->float}, "prev": {id->int} }。
static func dijkstra_field(
	state: GameState,
	start: int,
	allowed_nation: int = -1,
	block_contested_edges: bool = false,
	use_danger_weight: bool = true,
	allowed_goal: int = -1,
	required_manpower: int = 0,
	blocked_city_ids: Dictionary = {}
) -> Dictionary:
	var dist := {}
	var prev := {}
	var visited := {}
	for city in state.cities:
		dist[city.id] = INF
	dist[start] = 0.0
	var order_nation := (
		allowed_nation
		if allowed_nation >= 0
		else state.cities[start].owner_nation
	)
	var order_rank := EquivariantOrder.city_rank_map(
		state,
		order_nation,
		start
	)
	var blocked_enemy_edges := (
		_enemy_occupied_edge_keys(state, allowed_nation)
		if block_contested_edges
		else {}
	)
	var queue: Array[Dictionary] = [{
		"city": start,
		"distance": 0.0,
		"rank": int(order_rank[start]),
	}]
	while not queue.is_empty():
		var entry := _heap_pop(queue)
		var u := int(entry["city"])
		if (
			visited.has(u)
			or float(entry["distance"]) > float(dist[u]) + 0.000001
		):
			continue
		visited[u] = true
		for v in state.neighbors(u):
			if visited.has(v):
				continue
			if (
				(blocked_city_ids.has(v) and v != allowed_goal)
				or (blocked_city_ids.has(u) and u != start)
			):
				continue
			if allowed_nation != -1:
				# 起点可为刚失守的敌城；之后只经过本国/盟国，攻击时允许最终敌城。
				if (
					v != allowed_goal
					and not state.has_military_access(
						allowed_nation, state.cities[v].owner_nation
					)
				):
					continue
				if (
					u != start
					and not state.has_military_access(
						allowed_nation, state.cities[u].owner_nation
					)
				):
					continue
			var e := state.edge_of(u, v)
			if (
				e == null
				or e.max_manpower <= 0
				or e.max_manpower < required_manpower
			):
				continue
			if (
				block_contested_edges
				and blocked_enemy_edges.has(
					GameState.edge_key(e.city_a, e.city_b)
				)
			):
				continue
			var w := (
				float(e.distance)
				* maxf(e.travel_time_multiplier, 0.05)
			)
			if use_danger_weight:
				w += e.danger * DANGER_WEIGHT
			var nd: float = dist[u] + w
			var improves := nd < float(dist[v])
			var improves_tie := (
				is_equal_approx(nd, float(dist[v]))
				and (
					not prev.has(v)
					or int(order_rank[u])
						< int(order_rank[int(prev[v])])
				)
			)
			if improves or improves_tie:
				dist[v] = nd
				prev[v] = u
				_heap_push(queue, {
					"city": v,
					"distance": nd,
					"rank": int(order_rank[v]),
				})
	return { "dist": dist, "prev": prev }


static func _heap_entry_less(
	a: Dictionary,
	b: Dictionary
) -> bool:
	var distance_a := float(a["distance"])
	var distance_b := float(b["distance"])
	if not is_equal_approx(distance_a, distance_b):
		return distance_a < distance_b
	return int(a["rank"]) < int(b["rank"])


static func _heap_push(
	heap: Array[Dictionary],
	entry: Dictionary
) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := int((index - 1) / 2)
		if not _heap_entry_less(heap[index], heap[parent]):
			break
		var swap: Dictionary = heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _heap_pop(
	heap: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = tail
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := left
		if (
			right < heap.size()
			and _heap_entry_less(heap[right], heap[left])
		):
			child = right
		if not _heap_entry_less(heap[child], heap[index]):
			break
		var swap: Dictionary = heap[index]
		heap[index] = heap[child]
		heap[child] = swap
		index = child
	return result


## 由 prev 表回溯 start->goal 的城市序列（含 goal，不含 start）。不可达返回空。
static func reconstruct(prev: Dictionary, start: int, goal: int) -> Array[int]:
	if start == goal:
		return [] as Array[int]
	if not prev.has(goal):
		return [] as Array[int]
	var path: Array[int] = []
	var cur := goal
	while cur != start:
		path.push_front(cur)
		if not prev.has(cur):
			return [] as Array[int]
		cur = prev[cur]
	return path


## 从 start 到 goal 的城市序列（含 goal，不含 start）。不可达 / 相同返回空。
static func dijkstra(state: GameState, start: int, goal: int) -> Array[int]:
	if start == goal:
		return [] as Array[int]
	var field := dijkstra_field(state, start)
	return reconstruct(field["prev"], start, goal)


## 找最近的敌方城市，返回到该城的路径（不含起点）。无敌城 / 不可达返回空。
static func nearest_enemy_city(state: GameState, army: Army) -> Array[int]:
	var start := _origin_of(army)
	var field := dijkstra_field(
		state,
		start,
		-1,
		false,
		true,
		-1,
		army.max_size
	)
	var dist: Dictionary = field["dist"]
	var best_goal := -1
	var best_d := INF
	for city in state.cities:
		if not state.is_enemy(army.owner_nation, city.owner_nation):
			continue
		var d: float = dist[city.id]
		if d < best_d or (
			is_equal_approx(d, best_d)
			and EquivariantOrder.city_id_less(
				state,
				army.owner_nation,
				city.id,
				best_goal,
				start
			)
		):
			best_d = d
			best_goal = city.id
	if best_goal == -1 or best_d == INF:
		return [] as Array[int]
	return reconstruct(field["prev"], start, best_goal)


## 找最近的本国/盟友城市，返回到该城的路径（不含起点）。起点可为敌城，
## 离开起点后的路径及最终恢复城市都必须拥有军事通行权。
## excluded_city_id 用于守城方溃败时排除正在失守的城市。
static func nearest_friendly_city(state: GameState, army: Army, excluded_city_id: int = -1) -> Array[int]:
	return _nearest_retreat_city(
		state,
		army,
		excluded_city_id,
		false
	)


## 战败部队专用：围城城市既不能作为恢复目标，也不能作为撤退中继。
## 目标按“本国且向首都缩短纵深 → 盟友且向首都缩短纵深 → 最近安全本国城
## → 最近安全盟友城”排序。这样每次有首都方向可走时，撤退都会严格减少
## 首都距离，不会在两个同时被围的相邻城市之间往返。
static func strategic_retreat_city(
	state: GameState,
	army: Army,
	excluded_city_id: int = -1
) -> Array[int]:
	var start := _origin_of(army)
	if start < 0 or start >= state.cities.size():
		return [] as Array[int]
	var blocked := state.besieged_city_ids()
	var traversal_blocked := blocked.duplicate()
	traversal_blocked.erase(start)
	var field := dijkstra_field(
		state, start, army.owner_nation, false, true, -1,
		army.max_size, traversal_blocked
	)
	var choice := _strategic_retreat_goal(
		state, army.owner_nation, start, field["dist"],
		excluded_city_id, blocked, army.max_size
	)
	var goal := int(choice.get("goal", -1))
	if goal < 0:
		return [] as Array[int]
	return reconstruct(field["prev"], start, goal)


## 外交遣返专用：可穿越任意国家的正容量道路，但终点只能是本国城市。
static func nearest_home_city_for_repatriation(
	state: GameState,
	army: Army,
	excluded_city_id: int = -1
) -> Array[int]:
	return _nearest_retreat_city(
		state,
		army,
		excluded_city_id,
		true
	)


static func _nearest_retreat_city(
	state: GameState,
	army: Army,
	excluded_city_id: int,
	unrestricted_transit: bool
) -> Array[int]:
	var start := _origin_of(army)
	var field := dijkstra_field(
		state,
		start,
		-1 if unrestricted_transit else army.owner_nation,
		false,
		true,
		-1,
		army.max_size
	)
	var dist: Dictionary = field["dist"]
	var best_goal := (
		_nearest_home_goal(
			state,
			army.owner_nation,
			dist,
			excluded_city_id
		)
		if unrestricted_transit
		else _nearest_friendly_goal(
			state,
			army.owner_nation,
			dist,
			excluded_city_id
		)
	)
	var best_d: float = dist[best_goal] if best_goal != -1 else INF
	if best_goal == -1 or best_d == INF:
		return [] as Array[int]
	return reconstruct(field["prev"], start, best_goal)


## 城市中的军队是否存在通往其他本国/盟友城市的合法撤退路径。
## 当前城本身不算退路；道路容量必须容纳该军满编，敌国城市不能作为中间节点。
static func has_friendly_retreat_route_from_city(
	state: GameState,
	nation_id: int,
	city_id: int,
	required_manpower: int = 0
) -> bool:
	if (
		nation_id < 0
		or nation_id >= state.nations.size()
		or city_id < 0
		or city_id >= state.cities.size()
	):
		return false
	for neighbor in state.neighbors(city_id):
		var edge := state.edge_of(city_id, neighbor)
		if (
			edge != null
			and edge.max_manpower > 0
			and edge.max_manpower >= required_manpower
			and state.has_military_access(
				nation_id,
				state.cities[neighbor].owner_nation
			)
		):
			return true
	return false


## 兼容/非战略调用：军队在边上时，从真实位置分别接入两端，再叠加端点到
## 最近友城的 Dijkstra 距离。战败状态机改用 strategic_retreat_route_from_edge。
## 返回 {endpoint, path, distance}；无友城时返回空 Dictionary。
static func nearest_friendly_route_from_edge(
	state: GameState,
	army: Army,
	excluded_city_id: int = -1
) -> Dictionary:
	return _nearest_retreat_route_from_edge(
		state,
		army,
		excluded_city_id,
		false
	)


## 边上溃败的战略撤退版本。真实战场位置仍分别接入两端，但每个端点
## 后续都使用首都纵深与围城禁行规则，最后按目标层级、总路程和首都深度裁决。
static func strategic_retreat_route_from_edge(
	state: GameState,
	army: Army,
	excluded_city_id: int = -1
) -> Dictionary:
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge == null:
		return {}
	var length := float(maxi(edge.distance, 1))
	var options := [
		{"endpoint": army.move_from, "remaining": clampf(army.move_progress, 0.0, 1.0) * length},
		{"endpoint": army.move_to, "remaining": (1.0 - clampf(army.move_progress, 0.0, 1.0)) * length},
	]
	var blocked := state.besieged_city_ids()
	var best: Dictionary = {}
	for option in options:
		var endpoint := int(option["endpoint"])
		var traversal_blocked := blocked.duplicate()
		traversal_blocked.erase(endpoint)
		var field := dijkstra_field(
			state, endpoint, army.owner_nation, false, true, -1,
			army.max_size, traversal_blocked
		)
		var choice := _strategic_retreat_goal(
			state, army.owner_nation, endpoint, field["dist"],
			excluded_city_id, blocked, army.max_size
		)
		var goal := int(choice.get("goal", -1))
		if goal < 0:
			continue
		var total := (
			float(option["remaining"])
			+ float((field["dist"] as Dictionary)[goal])
		)
		var candidate := {
			"endpoint": endpoint,
			"path": reconstruct(field["prev"], endpoint, goal),
			"distance": total,
			"tier": int(choice["tier"]),
			"capital_distance": float(choice["capital_distance"]),
		}
		if _strategic_edge_route_better(
			state, army.owner_nation, army.move_from, candidate, best
		):
			best = candidate
	return best


static func _strategic_edge_route_better(
	state: GameState,
	nation_id: int,
	anchor_city: int,
	candidate: Dictionary,
	best: Dictionary
) -> bool:
	if best.is_empty():
		return true
	if int(candidate["tier"]) != int(best["tier"]):
		return int(candidate["tier"]) < int(best["tier"])
	if not is_equal_approx(
		float(candidate["distance"]), float(best["distance"])
	):
		return float(candidate["distance"]) < float(best["distance"])
	if not is_equal_approx(
		float(candidate["capital_distance"]),
		float(best["capital_distance"])
	):
		return (
			float(candidate["capital_distance"])
			< float(best["capital_distance"])
		)
	return EquivariantOrder.city_id_less(
		state, nation_id, int(candidate["endpoint"]),
		int(best["endpoint"]), anchor_city
	)


static func _strategic_retreat_goal(
	state: GameState,
	nation_id: int,
	start: int,
	retreat_dist: Dictionary,
	excluded_city_id: int,
	blocked_city_ids: Dictionary,
	required_manpower: int
) -> Dictionary:
	var capital_id := (
		state.nations[nation_id].capital_city_id
		if nation_id >= 0 and nation_id < state.nations.size()
		else -1
	)
	var capital_dist := {}
	if (
		capital_id >= 0
		and capital_id < state.cities.size()
		and not blocked_city_ids.has(capital_id)
		and state.cities[capital_id].owner_nation == nation_id
	):
		var capital_blocked := blocked_city_ids.duplicate()
		capital_blocked.erase(start)
		capital_dist = dijkstra_field(
			state, capital_id, nation_id, false, true, -1,
			required_manpower, capital_blocked
		)["dist"]
	var start_capital_distance := (
		float(capital_dist.get(start, INF))
		if not capital_dist.is_empty() else INF
	)
	var best: Dictionary = {}
	for city in state.cities:
		if (
			city.id == excluded_city_id
			or blocked_city_ids.has(city.id)
			or not state.has_military_access(nation_id, city.owner_nation)
			or float(retreat_dist.get(city.id, INF)) == INF
		):
			continue
		var own_city := city.owner_nation == nation_id
		var depth := float(capital_dist.get(city.id, INF))
		var progresses := (
			start_capital_distance < INF
			and depth < start_capital_distance - 0.000001
		)
		var tier := 0
		if not capital_dist.is_empty():
			tier = (
				0 if own_city and progresses
				else 1 if progresses
				else 2 if own_city
				else 3
			)
		else:
			tier = 0 if own_city else 1
		var candidate := {
			"goal": city.id,
			"tier": tier,
			"distance": float(retreat_dist[city.id]),
			"capital_distance": depth,
		}
		if _strategic_goal_better(
			state, nation_id, start, candidate, best
		):
			best = candidate
	return best


static func _strategic_goal_better(
	state: GameState,
	nation_id: int,
	start: int,
	candidate: Dictionary,
	best: Dictionary
) -> bool:
	if best.is_empty():
		return true
	if int(candidate["tier"]) != int(best["tier"]):
		return int(candidate["tier"]) < int(best["tier"])
	if not is_equal_approx(
		float(candidate["distance"]), float(best["distance"])
	):
		return float(candidate["distance"]) < float(best["distance"])
	if not is_equal_approx(
		float(candidate["capital_distance"]),
		float(best["capital_distance"])
	):
		return (
			float(candidate["capital_distance"])
			< float(best["capital_distance"])
		)
	return EquivariantOrder.city_id_less(
		state, nation_id, int(candidate["goal"]),
		int(best["goal"]), start
	)


## 外交遣返在道路上的对应版本：两端择优，可经第三国，终点仅限本国。
static func nearest_home_route_from_edge_for_repatriation(
	state: GameState,
	army: Army,
	excluded_city_id: int = -1
) -> Dictionary:
	return _nearest_retreat_route_from_edge(
		state,
		army,
		excluded_city_id,
		true
	)


static func _nearest_retreat_route_from_edge(
	state: GameState,
	army: Army,
	excluded_city_id: int,
	unrestricted_transit: bool
) -> Dictionary:
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge == null:
		return {}
	var length := float(maxi(edge.distance, 1))
	var options := [
		{"endpoint": army.move_from, "remaining": clampf(army.move_progress, 0.0, 1.0) * length},
		{"endpoint": army.move_to, "remaining": (1.0 - clampf(army.move_progress, 0.0, 1.0)) * length},
	]
	var best: Dictionary = {}
	for option in options:
		var endpoint: int = option["endpoint"]
		var field := dijkstra_field(
			state,
			endpoint,
			-1 if unrestricted_transit else army.owner_nation,
			false,
			true,
			-1,
			army.max_size
		)
		var dist: Dictionary = field["dist"]
		var goal := (
			_nearest_home_goal(
				state,
				army.owner_nation,
				dist,
				excluded_city_id
			)
			if unrestricted_transit
			else _nearest_friendly_goal(
				state,
				army.owner_nation,
				dist,
				excluded_city_id
			)
		)
		if goal == -1 or dist[goal] == INF:
			continue
		var total: float = float(option["remaining"]) + float(dist[goal])
		if best.is_empty() or total < float(best["distance"]) or (
			is_equal_approx(total, float(best["distance"]))
			and EquivariantOrder.city_id_less(
				state,
				army.owner_nation,
				endpoint,
				int(best["endpoint"]),
				army.move_from
			)
		):
			best = {
				"endpoint": endpoint,
				"path": reconstruct(field["prev"], endpoint, goal),
				"distance": total,
			}
	return best


static func _nearest_home_goal(
	state: GameState,
	nation_id: int,
	dist: Dictionary,
	excluded_city_id: int
) -> int:
	var best_goal := -1
	var best_d := INF
	for city in state.cities:
		if (
			city.id == excluded_city_id
			or city.owner_nation != nation_id
		):
			continue
		var distance := float(dist[city.id])
		if distance < best_d or (
			is_equal_approx(distance, best_d)
			and EquivariantOrder.city_id_less(
				state,
				nation_id,
				city.id,
				best_goal
			)
		):
			best_d = distance
			best_goal = city.id
	return best_goal


static func _nearest_friendly_goal(
	state: GameState,
	nation_id: int,
	dist: Dictionary,
	excluded_city_id: int
) -> int:
	var best_goal := -1
	var best_d := INF
	for city in state.cities:
		if (
			city.id == excluded_city_id
			or not state.has_military_access(
				nation_id,
				city.owner_nation
			)
		):
			continue
		var d: float = dist[city.id]
		if d < best_d or (
			is_equal_approx(d, best_d)
			and EquivariantOrder.city_id_less(
				state,
				nation_id,
				city.id,
				best_goal
			)
		):
			best_d = d
			best_goal = city.id
	return best_goal


## 从可达本国/盟国粮仓中选择运输损耗最低者；返回 [warehouse_city_id, route_loss]。
## 每条边损耗 = SUPPLY_DISTANCE_LOSS × distance × (1 + SUPPLY_DANGER_MULT × danger)，
## 路径损耗按边相加，因此可直接使用 Dijkstra。无可用粮仓返回 [-1, INF]。
static func nearest_supply_city(state: GameState, army: Army) -> Array:
	var sources := supply_sources(state, army)
	if sources.is_empty():
		return [-1, INF]
	return [int(sources[0]["city_id"]), float(sources[0]["loss"])]


## 返回全部可达本国/盟国粮仓，按运输损耗、势力局部物理序排序。
static func supply_sources(state: GameState, army: Army) -> Array[Dictionary]:
	var start := _origin_of(army)
	if start < 0 or start >= state.cities.size():
		return []
	var start_city := state.cities[start]
	# 被围城是补给孤岛：只能使用本城仍有库存且对该军开放的粮仓。
	if (
		not army.on_edge
		and state.city_under_siege(start)
		and state.has_military_access(army.owner_nation, start_city.owner_nation)
	):
		if (
			start_city.has_warehouse and start_city.food_storage > 0
			and state.nations[start_city.owner_nation].warehouse_city_ids.has(start)
		):
			return [{
				"city_id": start,
				"owner_nation": start_city.owner_nation,
				"loss": 0.0,
			}]
		return []
	var source_loss := (
		_supply_sources_from_edge(state, army)
		if army.on_edge and army.move_to != -1
		else _supply_sources_from_city(state, start, army.owner_nation)
	)
	var result: Array[Dictionary] = []
	for city_id_value in source_loss:
		var city_id := int(city_id_value)
		var city := state.cities[city_id]
		result.append({
			"city_id": city_id,
			"owner_nation": city.owner_nation,
			"loss": float(source_loss[city_id]),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a["loss"]), float(b["loss"])):
			return float(a["loss"]) < float(b["loss"])
		return EquivariantOrder.city_id_less(
			state,
			army.owner_nation,
			int(a["city_id"]),
			int(b["city_id"]),
			start
		)
	)
	return result


## 以粮仓为源反向构建国家补给网络。道路为无向图，因此结果与逐军从当前位置
## 搜索粮仓完全等价，但每国每个粮仓只需计算一次距离场。调用方若已在同一冻结
## 世界快照中汇总敌占边，可直接传入以避免重复全军扫描。
static func build_supply_network(
	state: GameState,
	nation_id: int,
	precomputed_blocked_enemy_edges: Variant = null
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var blocked_enemy_edges: Dictionary = (
		precomputed_blocked_enemy_edges
		if precomputed_blocked_enemy_edges is Dictionary
		else _enemy_occupied_edge_keys(
			state,
			nation_id
		)
	)
	var owner_ids: Array = []
	for owner in state.nations:
		if state.has_military_access(nation_id, owner.id):
			owner_ids.append(owner.id)
	owner_ids.sort_custom(func(a, b) -> bool:
		return EquivariantOrder.nation_less(
			state,
			nation_id,
			int(a),
			int(b)
		)
	)
	for owner_id_value in owner_ids:
		var owner_id := int(owner_id_value)
		var warehouses := state.warehouse_cities_of(owner_id)
		if warehouses.is_empty():
			continue
		EquivariantOrder.sort_cities(
			warehouses,
			state,
			nation_id
		)
		# 「共享粮仓」中继节点：owner 是本宗藩体系的粮池持有者（藩王已无独立粮仓，故
		# 只有持有者会走到这里），其和平藩属的首都作为零损耗补给起点注入损耗场——军队
		# 损耗按到「根粮仓或任一藩王首都」的最近距离计算，实现「藩王让偏远军队损耗重新
		# 起算」。独立国无藩属，relay_origins 为空，行为与旧版逐位一致。
		var relay_origins := state.food_pool_relay_capitals(owner_id)
		for warehouse in warehouses:
			if (
				warehouse.food_storage <= 0
				or state.city_under_siege(warehouse.id)
			):
				continue
			result.append({
				"city_id": warehouse.id,
				"owner_nation": owner_id,
				"dist": _supply_loss_field(
					state,
					warehouse.id,
					nation_id,
					blocked_enemy_edges,
					true,
					relay_origins
				)["dist"],
			})
	return result


static func supply_sources_from_network(
	state: GameState,
	army: Army,
	network: Array[Dictionary]
) -> Array[Dictionary]:
	var start := _origin_of(army)
	if start < 0 or start >= state.cities.size():
		return []
	var start_city := state.cities[start]
	if (
		not army.on_edge
		and state.city_under_siege(start)
		and state.has_military_access(
			army.owner_nation,
			start_city.owner_nation
		)
	):
		if (
			start_city.has_warehouse
			and start_city.food_storage > 0
			and state.nations[
				start_city.owner_nation
			].warehouse_city_ids.has(start)
		):
			return [{
				"city_id": start,
				"owner_nation": start_city.owner_nation,
				"loss": 0.0,
			}]
		return []
	var edge: Edge = null
	var edge_loss := 0.0
	var progress := 0.0
	if army.on_edge and army.move_to != -1:
		edge = state.edge_of(army.move_from, army.move_to)
		if edge == null:
			return []
		edge_loss = _supply_edge_loss(edge)
		progress = clampf(army.move_progress, 0.0, 1.0)
	var result: Array[Dictionary] = []
	for source in network:
		var dist: PackedFloat64Array = source["dist"]
		var loss := INF
		if edge == null:
			loss = dist[start]
		else:
			if state.has_military_access(
				army.owner_nation,
				state.cities[army.move_from].owner_nation
			):
				loss = minf(
					loss,
					progress * edge_loss
						+ dist[army.move_from]
				)
			if state.has_military_access(
				army.owner_nation,
				state.cities[army.move_to].owner_nation
			):
				loss = minf(
					loss,
					(1.0 - progress) * edge_loss
						+ dist[army.move_to]
				)
		if loss == INF:
			continue
		result.append({
			"city_id": source["city_id"],
			"owner_nation": source["owner_nation"],
			"loss": loss,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(
			float(a["loss"]),
			float(b["loss"])
		):
			return float(a["loss"]) < float(b["loss"])
		return EquivariantOrder.city_id_less(
			state,
			army.owner_nation,
			int(a["city_id"]),
			int(b["city_id"]),
			start
		)
	)
	return result


## 人口补员通路：与粮食补给共用控制区/争夺边规则，但不要求粮仓当前有粮。
static func can_reach_manpower_hub(state: GameState, army: Army) -> bool:
	if army.owner_nation < 0 or army.owner_nation >= state.nations.size():
		return false
	if army.on_edge and army.move_to != -1:
		var current_edge := state.edge_of(army.move_from, army.move_to)
		if (
			current_edge == null
			or current_edge.max_manpower <= 0
			or _edge_has_enemy_presence(state, current_edge, army.owner_nation)
		):
			return false
		for endpoint in [army.move_from, army.move_to]:
			if not state.has_military_access(
				army.owner_nation, state.cities[endpoint].owner_nation
			):
				continue
			if _field_reaches_warehouse(state, endpoint, army.owner_nation):
				return true
		return false
	var start := _origin_of(army)
	if (
		start < 0 or start >= state.cities.size()
		or not state.has_military_access(
			army.owner_nation, state.cities[start].owner_nation
		)
		or state.city_under_siege(start)
	):
		return false
	return _field_reaches_warehouse(state, start, army.owner_nation)


static func _field_reaches_warehouse(state: GameState, start: int, nation_id: int) -> bool:
	var field := _supply_loss_field(state, start, nation_id)
	var dist: PackedFloat64Array = field["dist"]
	for warehouse in state.warehouse_cities_of(nation_id):
		if not state.city_under_siege(warehouse.id) and float(dist[warehouse.id]) < INF:
			return true
	return false


static func _supply_sources_from_city(
	state: GameState,
	start: int,
	nation_id: int
) -> Dictionary:
	var field := _supply_loss_field(state, start, nation_id)
	return _reachable_supply_losses(state, nation_id, field["dist"])


## 边上军队从真实位置分别接入两个可通行端点，再沿本国/盟国道路寻找粮仓。
static func _supply_sources_from_edge(state: GameState, army: Army) -> Dictionary:
	var edge := state.edge_of(army.move_from, army.move_to)
	if edge == null:
		return {}
	var edge_loss := _supply_edge_loss(edge)
	var progress := clampf(army.move_progress, 0.0, 1.0)
	var options := [
		{"endpoint": army.move_from, "offset": progress * edge_loss},
		{"endpoint": army.move_to, "offset": (1.0 - progress) * edge_loss},
	]
	var result := {}
	for option in options:
		var endpoint: int = option["endpoint"]
		if not state.has_military_access(
			army.owner_nation, state.cities[endpoint].owner_nation
		):
			continue
		var field := _supply_loss_field(state, endpoint, army.owner_nation)
		var dist: PackedFloat64Array = field["dist"]
		var reachable := _reachable_supply_losses(
			state, army.owner_nation, dist
		)
		for city_id in reachable:
			var total := float(option["offset"]) + float(reachable[city_id])
			if total < float(result.get(city_id, INF)):
				result[city_id] = total
	return result


static func _reachable_supply_losses(
	state: GameState,
	nation_id: int,
	dist: PackedFloat64Array
) -> Dictionary:
	var result := {}
	for owner in state.nations:
		if not state.has_military_access(nation_id, owner.id):
			continue
		for city in state.warehouse_cities_of(owner.id):
			if (
				city.food_storage <= 0
				or state.city_under_siege(city.id)
				or float(dist[city.id]) == INF
			):
				continue
			result[city.id] = float(dist[city.id])
	return result


## extra_zero_origins：除主源 start 外的其他「零损耗起点」（如同一宗藩体系的藩王
## 首都中继节点）。距离场从全部起点同时以 dist=0 向外扩散，故军队损耗按到「最近的
## 任一起点」计算——这正是「藩王首都让偏远军队损耗重新起算」的数学表达。确定性打破
## 平局仍以主源 start 锚定 rank，与单源行为在无中继时逐位一致。
static func _supply_loss_field(
	state: GameState,
	start: int,
	nation_id: int,
	blocked_enemy_edges: Dictionary = {},
	blocked_edges_ready: bool = false,
	extra_zero_origins: Array[int] = [] as Array[int]
) -> Dictionary:
	var city_count := state.cities.size()
	var dist := PackedFloat64Array()
	dist.resize(city_count)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(city_count)
	prev.fill(-1)
	var visited := PackedByteArray()
	visited.resize(city_count)
	visited.fill(0)
	dist[start] = 0.0
	var order_rank := EquivariantOrder.city_rank_map(
		state,
		nation_id,
		start
	)
	if not blocked_edges_ready:
		blocked_enemy_edges = _enemy_occupied_edge_keys(
			state,
			nation_id
		)
	var queue: Array[Dictionary] = [{
		"city": start,
		"distance": 0.0,
		"rank": int(order_rank[start]),
	}]
	# 中继起点同样以 dist=0 入堆；沿宗藩体系可达道路自然扩散并竞争最短损耗。
	for origin in extra_zero_origins:
		if (
			origin < 0
			or origin >= state.cities.size()
			or origin == start
			or dist[origin] == 0.0
		):
			continue
		dist[origin] = 0.0
		queue.append({
			"city": origin,
			"distance": 0.0,
			"rank": int(order_rank[origin]),
		})
	while not queue.is_empty():
		var entry := _heap_pop(queue)
		var u := int(entry["city"])
		if (
			visited[u] != 0
			or float(entry["distance"])
				> float(dist[u]) + 0.000001
		):
			continue
		visited[u] = 1
		for v in state.neighbors(u):
			if visited[v] != 0:
				continue
			if (
				not state.has_military_access(
					nation_id, state.cities[u].owner_nation
				)
				or not state.has_military_access(
					nation_id, state.cities[v].owner_nation
				)
			):
				continue
			var edge := state.edge_of(u, v)
			if edge == null or edge.max_manpower <= 0:
				continue
			if blocked_enemy_edges.has(
				GameState.edge_key(edge.city_a, edge.city_b)
			):
				continue
			var nd: float = dist[u] + _supply_edge_loss(edge)
			if nd < float(dist[v]) or (
				is_equal_approx(nd, float(dist[v]))
				and (
					prev[v] < 0
					or int(order_rank[u])
						< int(order_rank[prev[v]])
				)
			):
				dist[v] = nd
				prev[v] = u
				_heap_push(queue, {
					"city": v,
					"distance": nd,
					"rank": int(order_rank[v]),
				})
	return {"dist": dist, "prev": prev}


static func _supply_edge_loss(edge: Edge) -> float:
	if edge == null or edge.max_manpower <= 0:
		return INF
	return (
		SUPPLY_DISTANCE_LOSS
		* float(maxi(edge.distance, 1))
		* maxf(edge.supply_loss_multiplier, 0.0)
		* (1.0 + SUPPLY_DANGER_MULT * clampf(edge.danger, 0.0, 1.0))
	)


static func _edge_has_enemy_presence(state: GameState, edge: Edge, nation_id: int) -> bool:
	if edge == null:
		return false
	return _enemy_occupied_edge_keys(
		state,
		nation_id
	).has(GameState.edge_key(edge.city_a, edge.city_b))


static func _enemy_occupied_edge_keys(
	state: GameState,
	nation_id: int
) -> Dictionary:
	var result := {}
	if nation_id < 0:
		return result
	for army in state.armies:
		if (
			army.size <= 0
			or not army.on_edge
			or army.move_to == -1
			or not state.is_enemy(
				army.owner_nation,
				nation_id
			)
		):
			continue
		result[
			GameState.edge_key(
				army.move_from,
				army.move_to
			)
		] = true
	return result


static func _origin_of(army: Army) -> int:
	return army.move_from if army.state in [
		Army.State.MOVING,
		Army.State.RETREATING,
		Army.State.HOLDING,
	] else army.location_city
