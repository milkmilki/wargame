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
	required_manpower: int = 0
) -> Dictionary:
	var dist := {}
	var prev := {}
	var visited := {}
	for city in state.cities:
		dist[city.id] = INF
	dist[start] = 0.0

	while true:
		var u := -1
		var best := INF
		for cid in dist.keys():
			if visited.has(cid):
				continue
			var d: float = dist[cid]
			if d < best:
				best = d
				u = cid
		if u == -1:
			break
		visited[u] = true
		for v in state.neighbors(u):
			if visited.has(v):
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
			if block_contested_edges and _edge_has_enemy_presence(state, e, allowed_nation):
				continue
			var w := float(e.distance)
			if use_danger_weight:
				w += e.danger * DANGER_WEIGHT
			var nd: float = dist[u] + w
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	return { "dist": dist, "prev": prev }


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
		# tie-break 按 id 升序，保证可复现
		if d < best_d or (d == best_d and city.id < best_goal):
			best_d = d
			best_goal = city.id
	if best_goal == -1 or best_d == INF:
		return [] as Array[int]
	return reconstruct(field["prev"], start, best_goal)


## 找最近的本国/盟友城市，返回到该城的路径（不含起点）。起点可为敌城，
## 离开起点后的路径及最终恢复城市都必须拥有军事通行权。
## excluded_city_id 用于守城方溃败时排除正在失守的城市。
static func nearest_friendly_city(state: GameState, army: Army, excluded_city_id: int = -1) -> Array[int]:
	var start := _origin_of(army)
	var field := dijkstra_field(
		state,
		start,
		army.owner_nation,
		false,
		true,
		-1,
		army.max_size
	)
	var dist: Dictionary = field["dist"]
	var best_goal := _nearest_friendly_goal(state, army.owner_nation, dist, excluded_city_id)
	var best_d: float = dist[best_goal] if best_goal != -1 else INF
	if best_goal == -1 or best_d == INF:
		return [] as Array[int]
	return reconstruct(field["prev"], start, best_goal)


## 军队在边上溃败时，从真实交战位置分别计算到两个端点的剩余距离，再叠加端点到
## 最近友城的 Dijkstra 距离，返回全局最近路线。path 不含 endpoint。
## 返回 {endpoint, path, distance}；无友城时返回空 Dictionary。
static func nearest_friendly_route_from_edge(
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
	var best: Dictionary = {}
	for option in options:
		var endpoint: int = option["endpoint"]
		var field := dijkstra_field(
			state,
			endpoint,
			army.owner_nation,
			false,
			true,
			-1,
			army.max_size
		)
		var dist: Dictionary = field["dist"]
		var goal := _nearest_friendly_goal(state, army.owner_nation, dist, excluded_city_id)
		if goal == -1 or dist[goal] == INF:
			continue
		var total: float = float(option["remaining"]) + float(dist[goal])
		if best.is_empty() or total < float(best["distance"]) or (
			is_equal_approx(total, float(best["distance"])) and endpoint < int(best["endpoint"])
		):
			best = {
				"endpoint": endpoint,
				"path": reconstruct(field["prev"], endpoint, goal),
				"distance": total,
			}
	return best


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
		if d < best_d or (d == best_d and (best_goal == -1 or city.id < best_goal)):
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


## 返回全部可达本国/盟国粮仓，按运输损耗、城市 id 排序。
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
		return (
			float(a["loss"]) < float(b["loss"])
			or (
				is_equal_approx(float(a["loss"]), float(b["loss"]))
				and int(a["city_id"]) < int(b["city_id"])
			)
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
	var dist: Dictionary = field["dist"]
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
		var dist: Dictionary = field["dist"]
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
	dist: Dictionary
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


static func _supply_loss_field(state: GameState, start: int, nation_id: int) -> Dictionary:
	var dist := {}
	var prev := {}
	var visited := {}
	for city in state.cities:
		dist[city.id] = INF
	dist[start] = 0.0
	while true:
		var u := -1
		var best := INF
		for cid in dist.keys():
			if visited.has(cid):
				continue
			var d: float = dist[cid]
			if d < best:
				best = d
				u = cid
		if u == -1:
			break
		visited[u] = true
		for v in state.neighbors(u):
			if visited.has(v):
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
			if _edge_has_enemy_presence(state, edge, nation_id):
				continue
			var nd: float = dist[u] + _supply_edge_loss(edge)
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	return {"dist": dist, "prev": prev}


static func _supply_edge_loss(edge: Edge) -> float:
	if edge == null or edge.max_manpower <= 0:
		return INF
	return (
		SUPPLY_DISTANCE_LOSS
		* float(maxi(edge.distance, 1))
		* (1.0 + SUPPLY_DANGER_MULT * clampf(edge.danger, 0.0, 1.0))
	)


static func _edge_has_enemy_presence(state: GameState, edge: Edge, nation_id: int) -> bool:
	if edge == null:
		return false
	for army in state.armies:
		if army.size <= 0 or not army.on_edge or army.move_to == -1:
			continue
		if not state.is_enemy(army.owner_nation, nation_id):
			continue
		var army_edge := state.edge_of(army.move_from, army.move_to)
		if army_edge == edge:
			return true
	return false


static func _origin_of(army: Army) -> int:
	return army.move_from if army.state in [
		Army.State.MOVING,
		Army.State.RETREATING,
		Army.State.HOLDING,
	] else army.location_city
