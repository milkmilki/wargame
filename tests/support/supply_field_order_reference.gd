extends RefCounted
## Original eager full-map rank field from 37da4bb working baseline.

static func _supply_loss_field(
	state: GameState,
	start: int,
	nation_id: int,
	blocked_enemy_edges: Dictionary = {},
	blocked_edges_ready: bool = false,
	extra_zero_origins: Array[int] = [] as Array[int],
	logistics: bool = false
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
		blocked_enemy_edges = Pathfinding._enemy_occupied_edge_keys(
			state,
			nation_id
		)
	var local_crossing_transit_docks := Pathfinding._local_crossing_transit_docks(
		state, nation_id, -1
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
			var edge := state.edge_of(u, v)
			if edge == null or edge.max_manpower <= 0:
				continue
			if not Pathfinding._local_crossing_or_accessible_step(
				state,
				nation_id,
				u,
				v,
				edge,
				local_crossing_transit_docks, logistics
			):
				continue
			if blocked_enemy_edges.has(
				GameState.edge_key(edge.city_a, edge.city_b)
			):
				continue
			var nd: float = dist[u] + Pathfinding._supply_edge_loss(edge)
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

static func _heap_entry_less(
	a: Dictionary,
	b: Dictionary
) -> bool:
	var distance_a := float(a["distance"])
	var distance_b := float(b["distance"])
	if not is_equal_approx(distance_a, distance_b):
		return distance_a < distance_b
	if a.has("order_key"):
		return EquivariantOrder._key_less(a["order_key"], b["order_key"])
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
