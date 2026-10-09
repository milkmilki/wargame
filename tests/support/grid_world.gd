extends GameState
const GRID := 8
const CITY_COUNT := GRID * GRID
const DEFAULT_CITY_COUNT := 200
## Synthetic graph fixture for shared simulation regressions; never a game scene.

func generate_world(seed_value: int = 12345, nation_count: int = 4, city_count: int = 200) -> bool:
	_reset_world(seed_value)
	uses_heightmap = false
	_generate_nations(DiplomaticRelation.NEUTRAL, nation_count, false)
	var width := ceili(sqrt(float(city_count)))
	var height := ceili(float(city_count) / width)
	for id in range(city_count):
		var city := City.new()
		city.id = id; city.coord = Vector2i(id % width, id / width)
		city.map_position = Vector2((city.coord.x + 0.5) / width, (city.coord.y + 0.5) / height)
		city.owner_nation = mini(nation_count - 1, id * nation_count / city_count)
		city.manpower_per_month = rng.randi_range(500, 1000)
		city.gold_per_month = rng.randi_range(5, 15)
		city.food_per_half_year = rng.randi_range(400, 600)
		city.food_storage = 550
		cities.append(city); adjacency[id] = [] as Array[int]
	province_map_size = Vector2i(width,height); province_ids.resize(width*height); province_ids.fill(-1)
	for id in range(city_count):
		province_ids[id] = id
		if id % width + 1 < width and id + 1 < city_count: _add_edge(id,id+1)
		if id + width < city_count: _add_edge(id,id+width)
	_initialize_recognized_city_owners(); _initialize_manpower_pools()
	_classify_road_capacity(); rebuild_region_analysis(); rebuild_administrative_regions()
	_initialize_city_garrisons_free(); _initialize_capitals_and_warehouses()
	WorldNaming.assign_initial_names(self,seed_value); FamilyTree.ensure_all(self)
	_initialize_city_loyalty(); _generate_armies(); RegionalStrategy.initialize_targets(self)
	EmpireStatus.reconcile(self); reconcile_adjacent_sovereign_colors()
	return true

func generate_grid_world(world_seed: int = 12345) -> void:
	_reset_world(world_seed)
	uses_heightmap = false
	map_aspect_ratio = 1.0
	# 网格世界是严格镜像与旧状态机测试夹具：未显式设置君主时必须保持
	# 中性参数，避免确定性随机原型改变既有外交、经济和攻势基线。
	_generate_nations(DiplomaticRelation.WAR, NATION_COUNT, false)
	_generate_grid_cities()
	_generate_grid_provinces()
	_initialize_recognized_city_owners()
	_initialize_manpower_pools()
	_generate_grid_edges()
	_classify_road_capacity()
	rebuild_region_analysis()
	rebuild_administrative_regions()
	_initialize_city_garrisons_free()
	_initialize_capitals_and_warehouses()
	WorldNaming.assign_initial_names(self, world_seed)
	FamilyTree.ensure_all(self)
	_initialize_city_loyalty()
	_generate_armies()
	RegionalStrategy.initialize_targets(self)
	EmpireStatus.reconcile(self)
	reconcile_adjacent_sovereign_colors()

	assert(cities.size() == CITY_COUNT, "城市数应为 64")
	assert(edges.size() == 2 * GRID * (GRID - 1), "网格夹具边数应为 112")
	assert(
		armies.size() == NATION_COUNT,
		"网格状态机夹具必须只保留每国一个初始指挥单位"
	)
	assert(_battle_group_structure_valid(), "网格战团结构必须合法")


func _generate_grid_cities() -> void:
	for r in range(GRID):
		for c in range(GRID):
			var city := City.new()
			city.id = r * GRID + c
			city.coord = Vector2i(c, r)
			city.map_position = Vector2(
				(float(c) + 0.5) / float(GRID),
				(float(r) + 0.5) / float(GRID)
			)
			city.owner_nation = _quadrant_of(c, r)
			# 保留旧世界种子的后续 RNG 序列。
			var _legacy_world_stream_roll := rng.randi_range(10, 30)
			city.manpower_per_month = rng.randi_range(
				CITY_MANPOWER_PER_MONTH_MIN,
				CITY_MANPOWER_PER_MONTH_MAX
			)
			city.gold_per_month = rng.randi_range(5, 15)
			city.food_per_half_year = rng.randi_range(
				CITY_FOOD_PER_HALF_YEAR_MIN,
				CITY_FOOD_PER_HALF_YEAR_MAX
			)
			# 先生成各城初始储备，随后统一归集到本国首都粮仓。
			city.food_storage = rng.randi_range(
				INITIAL_CITY_FOOD_STOCK_MIN,
				INITIAL_CITY_FOOD_STOCK_MAX
			)
			city.at_war = true                                 # 开局全面战争
			cities.append(city)
			adjacency[city.id] = [] as Array[int]


func _generate_grid_provinces() -> void:
	province_map_size = Vector2i(GRID, GRID)
	province_ids.resize(CITY_COUNT)
	for city_id in range(CITY_COUNT):
		province_ids[city_id] = city_id


func _quadrant_of(c: int, r: int) -> int:
	var half := GRID / 2
	var col_half := 0 if c < half else 1
	var row_half := 0 if r < half else 1
	return row_half * 2 + col_half   # 0:左上 1:右上 2:左下 3:右下


func _generate_grid_edges() -> void:
	for r in range(GRID):
		for c in range(GRID):
			var id := r * GRID + c
			# 右邻
			if c + 1 < GRID:
				_add_edge(id, r * GRID + (c + 1))
			# 下邻
			if r + 1 < GRID:
				_add_edge(id, (r + 1) * GRID + c)


func _add_edge(a: int, b: int) -> void:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var e := Edge.new()
	e.city_a = lo
	e.city_b = hi
	e.distance = rng.randi_range(1, 5)
	e.danger = rng.randf_range(0.0, 0.5)
	e.max_manpower = 15000
	e.occupied = false
	edges.append(e)
	edge_lookup[_edge_key(lo, hi)] = e
	(adjacency[lo] as Array[int]).append(hi)
	(adjacency[hi] as Array[int]).append(lo)


func _classify_road_capacity() -> void:
	var flow := {}
	for edge in edges:
		flow[_edge_key(edge.city_a, edge.city_b)] = 0.0
	# 全点对确定性最短路径流量，近似道路介数。
	for source in range(cities.size()):
		var field := _road_dijkstra(source)
		_accumulate_road_flow_tree(
			field["prev"], source, flow
		)
	# 首都到本国城市及初始前线是战略主通路，给予额外权重。
	for nation in nations:
		var capital := nation.capital_city_id
		if capital < 0:
			continue
		var field := _road_dijkstra(capital)
		for city in cities_of(nation.id):
			var weight := 4.0
			for neighbor in neighbors(city.id):
				if cities[neighbor].owner_nation != nation.id:
					weight = 10.0
					break
			_accumulate_road_flow(field["prev"], capital, city.id, flow, weight)

	var backbone := _minimum_spanning_backbone()
	for edge in edges:
		edge.max_manpower = 15000
	var zero_candidates: Array[Edge] = []
	for edge in edges:
		if not backbone.has(_edge_key(edge.city_a, edge.city_b)):
			zero_candidates.append(edge)
	zero_candidates.sort_custom(func(a: Edge, b: Edge) -> bool:
		var score_a := float(flow[_edge_key(a.city_a, a.city_b)])
		var score_b := float(flow[_edge_key(b.city_a, b.city_b)])
		return score_a < score_b or (
			is_equal_approx(score_a, score_b)
			and _edge_key(a.city_a, a.city_b) < _edge_key(b.city_a, b.city_b)
		)
	)
	var zero_count := mini(int(round(float(edges.size()) * 0.15)), zero_candidates.size())
	var zero_keys := {}
	for i in range(zero_count):
		var edge := zero_candidates[i]
		edge.max_manpower = 0
		edge.danger = maxf(edge.danger, 0.75)
		zero_keys[_edge_key(edge.city_a, edge.city_b)] = true

	var roads: Array[Edge] = []
	for edge in edges:
		if not zero_keys.has(_edge_key(edge.city_a, edge.city_b)):
			roads.append(edge)
	roads.sort_custom(func(a: Edge, b: Edge) -> bool:
		var score_a := float(flow[_edge_key(a.city_a, a.city_b)])
		var score_b := float(flow[_edge_key(b.city_a, b.city_b)])
		return score_a > score_b or (
			is_equal_approx(score_a, score_b)
			and _edge_key(a.city_a, a.city_b) < _edge_key(b.city_a, b.city_b)
		)
	)
	var level4_count := int(ceil(float(roads.size()) * 0.05))
	var level3_end := level4_count + int(ceil(float(roads.size()) * 0.10))
	var level2_end := level3_end + int(ceil(float(roads.size()) * 0.35))
	for i in range(roads.size()):
		roads[i].max_manpower = 100000 if i < level4_count else (
			60000 if i < level3_end else (
				30000 if i < level2_end else 15000
			)
		)


func _road_dijkstra(start: int) -> Dictionary:
	var dist := {}
	var prev := {}
	var visited := {}
	for city in cities:
		dist[city.id] = INF
	dist[start] = 0.0
	var queue: Array[Dictionary] = [{
		"city": start, "distance": 0.0, "rank": start,
	}]
	while not queue.is_empty():
		var entry := Pathfinding._heap_pop(queue)
		var current := int(entry["city"])
		if (
			visited.has(current)
			or float(entry["distance"])
				> float(dist[current]) + 0.000001
		):
			continue
		visited[current] = true
		for neighbor in neighbors(current):
			if visited.has(neighbor):
				continue
			var edge := edge_of(current, neighbor)
			var next_dist: float = (
				float(dist[current])
				+ float(edge.distance)
				+ edge.danger * 2.0
			)
			if next_dist < float(dist[neighbor]) or (
				is_equal_approx(next_dist, float(dist[neighbor]))
				and current < int(prev.get(neighbor, CITY_COUNT))
			):
				dist[neighbor] = next_dist
				prev[neighbor] = current
				Pathfinding._heap_push(queue, {
					"city": neighbor,
					"distance": next_dist,
					"rank": neighbor,
				})
	return {"dist": dist, "prev": prev}


## 对固定 source，旧实现逐 goal 回溯 prev 树；同一树干会被重复遍历 O(V²)。
## 这里给 goal>source 的节点各放一个单位，自叶到根汇总子树权重，每条父边一次
## 得到完全相同的累计流量，单个源点降为 O(V)。
func _accumulate_road_flow_tree(
	prev: Dictionary,
	source: int,
	flow: Dictionary
) -> void:
	var child_counts := PackedInt32Array()
	child_counts.resize(cities.size())
	child_counts.fill(0)
	var contributions := PackedFloat64Array()
	contributions.resize(cities.size())
	contributions.fill(0.0)
	for child_value in prev:
		var child := int(child_value)
		var parent := int(prev[child_value])
		if parent >= 0 and parent < child_counts.size():
			child_counts[parent] += 1
		if child > source:
			contributions[child] = 1.0
	var leaves: Array[int] = []
	for city_id in range(cities.size()):
		if city_id != source and prev.has(city_id) and child_counts[city_id] == 0:
			leaves.append(city_id)
	var cursor := 0
	while cursor < leaves.size():
		var child := leaves[cursor]
		cursor += 1
		var parent := int(prev[child])
		var weight := contributions[child]
		if weight > 0.0:
			var key := _edge_key(parent, child)
			flow[key] = float(flow[key]) + weight
			contributions[parent] += weight
		child_counts[parent] -= 1
		if parent != source and child_counts[parent] == 0:
			leaves.append(parent)


func _accumulate_road_flow(
	prev: Dictionary,
	source: int,
	goal: int,
	flow: Dictionary,
	weight: float
) -> void:
	if source == goal:
		return
	var current := goal
	var guard := 0
	while current != source and prev.has(current) and guard <= cities.size():
		var parent: int = prev[current]
		var key := _edge_key(parent, current)
		flow[key] = float(flow[key]) + weight
		current = parent
		guard += 1


func _minimum_spanning_backbone() -> Dictionary:
	var sorted_edges: Array[Edge] = edges.duplicate()
	sorted_edges.sort_custom(func(a: Edge, b: Edge) -> bool:
		var weight_a := float(a.distance) + a.danger * 2.0
		var weight_b := float(b.distance) + b.danger * 2.0
		return weight_a < weight_b or (
			is_equal_approx(weight_a, weight_b)
			and _edge_key(a.city_a, a.city_b) < _edge_key(b.city_a, b.city_b)
		)
	)
	var parent: Array[int] = []
	parent.resize(cities.size())
	for i in range(parent.size()):
		parent[i] = i
	var backbone := {}
	for edge in sorted_edges:
		var root_a := _union_find_root(parent, edge.city_a)
		var root_b := _union_find_root(parent, edge.city_b)
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		backbone[_edge_key(edge.city_a, edge.city_b)] = true
	return backbone


func _union_find_root(parent: Array[int], node: int) -> int:
	var current := node
	while parent[current] != current:
		parent[current] = parent[parent[current]]
		current = parent[current]
	return current
