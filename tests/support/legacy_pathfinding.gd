# Exact cf80691 Dijkstra implementation; compare every distance and predecessor.
extends Pathfinding

static func dijkstra_field(
	state: GameState,
	start: int,
	allowed_nation: int = -1,
	block_contested_edges: bool = false,
	use_danger_weight: bool = true,
	allowed_goal: int = -1,
	required_manpower: int = 0,
	blocked_city_ids: Dictionary = {},
	allowed_exit_city: int = -1
) -> Dictionary:
	var dist := {}
	var prev := {}
	var visited := {}
	var exit_city := allowed_exit_city if allowed_exit_city>=0 else (start if not state.cities[start].is_traffic else -1)
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
	var local_crossing_transit_docks := (
		_local_crossing_transit_docks(
			state, allowed_nation, allowed_goal
		)
		if allowed_nation >= 0
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
			var e := state.edge_of(u, v)
			if e == null or e.max_manpower <= 0:
				continue
			if (
				(blocked_city_ids.has(v) and v != allowed_goal)
				or (blocked_city_ids.has(u) and u != start)
			):
				continue
			if allowed_nation != -1:
				if not state.atlas_layout.is_empty() and not state.atlas_edge_access(e,allowed_nation,allowed_goal,false,exit_city): continue
				var v_is_local_crossing_transit := (
					local_crossing_transit_docks.has(v)
				)
				var u_is_local_crossing_transit := (
					local_crossing_transit_docks.has(u)
				)
				if u_is_local_crossing_transit or v_is_local_crossing_transit:
					var bank_id := v if u_is_local_crossing_transit else u
					if (
						e.kind != Edge.Kind.LANDING
						or state.cities[bank_id].is_dock
						or (
							bank_id != allowed_goal
							and not state.has_military_access(
								allowed_nation,
								state.cities[bank_id].owner_nation
							)
						)
					):
						continue
				# 起点可为刚失守的敌城；之后只经过本国/盟国，攻击时允许最终敌城。
				if state.atlas_layout.is_empty() and (
					v != allowed_goal
					and not v_is_local_crossing_transit
					and not state.has_military_access(
						allowed_nation, state.cities[v].owner_nation
					)
				):
					continue
				if state.atlas_layout.is_empty() and (
					u != start
					and not u_is_local_crossing_transit
					and not state.has_military_access(
						allowed_nation, state.cities[u].owner_nation
					)
				):
					continue
			if (
				block_contested_edges
				and blocked_enemy_edges.has(
					GameState.edge_key(e.city_a, e.city_b)
				)
			):
				continue
			var w := _edge_transport_distance(e, required_manpower)
			if use_danger_weight:
				w += e.danger * DANGER_WEIGHT * (e.distance_units() if e.precise_distance>=0. else 1.)
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


## 同一码头两岸属于政治接壤。共享码头可在两个有通行权的陆岸之间作为
## 本地中继；攻击时还可连接一个作为最终目标的敌岸。遍历码头时只接受
## LANDING 边，因此不会沿 RIVER/SEA 扩展成远程政治通道。
