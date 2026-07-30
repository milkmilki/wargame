class_name GameState
extends RefCounted
## 单一数据源（SSoT）：持有全部 cities / edges / nations / armies，
## 并负责确定性世界生成。所有可变游戏状态都归此对象所有。

const GRID: int = 8                         ## 8x8 网格
const CITY_COUNT: int = GRID * GRID         ## 64
const NATION_COUNT: int = 4
const TERRAIN_MAP_PATH := (
	"res://china-map-china-flag-shaded-relief-color-height-map-3d-illustration-png.webp"
)

var cities: Array[City] = []
var edges: Array[Edge] = []
var nations: Array[Nation] = []
var armies: Array[Army] = []
var battles: Array[Battle] = []            ## 进行中的多回合战斗

## 邻接表：city_id -> Array[int]（相邻 city_id）
var adjacency: Dictionary = {}
## 边查找：规范化 key (a*CITY_COUNT+b, a<b) -> Edge
var edge_lookup: Dictionary = {}

var day: int = 0                            ## 时间真源（1 tick = 1 天）
var month: int = 0                          ## 派生显示量：day / DAYS_PER_MONTH（每 tick 由 Simulation 刷新）
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_army_id: int = 0
var _next_battle_id: int = 0
var ownership_revision: int = 0             ## 城市易主版本号，供战略地图缓存失效
var uses_heightmap: bool = false
var map_aspect_ratio: float = 1.0

## 结束态
var winner: int = -1                        ## -1 表示未结束

# ------------------------------------------------------------------ 生成

func generate_world(world_seed: int = 12345) -> void:
	_reset_world(world_seed)
	uses_heightmap = true
	_generate_nations()
	var terrain := TerrainMapGenerator.build(TERRAIN_MAP_PATH, CITY_COUNT)
	_generate_terrain_cities(terrain)
	_generate_terrain_edges(terrain)
	_assign_balanced_nations(terrain)
	_initialize_manpower_pools()
	_initialize_capitals_and_warehouses()
	_generate_armies()

	assert(cities.size() == CITY_COUNT, "城市数应为 64")
	assert(edges.size() >= CITY_COUNT - 1, "道路图必须连通")
	assert(armies.size() == CITY_COUNT, "初始军队数应为 64")


## 严格镜像基准和局部状态机测试使用的兼容网格夹具；正式游戏不调用。
func generate_grid_world(world_seed: int = 12345) -> void:
	_reset_world(world_seed)
	uses_heightmap = false
	map_aspect_ratio = 1.0
	_generate_nations()
	_generate_grid_cities()
	_initialize_manpower_pools()
	_initialize_capitals_and_warehouses()
	_generate_grid_edges()
	_classify_road_throughput()
	_generate_armies()

	assert(cities.size() == CITY_COUNT, "城市数应为 64")
	assert(edges.size() == 2 * GRID * (GRID - 1), "网格夹具边数应为 112")
	assert(armies.size() == CITY_COUNT, "初始军队数应为 64")


func _reset_world(world_seed: int) -> void:
	rng.seed = world_seed
	cities.clear()
	edges.clear()
	nations.clear()
	armies.clear()
	battles.clear()
	adjacency.clear()
	edge_lookup.clear()
	day = 0
	month = 0
	winner = -1
	_next_army_id = 0
	ownership_revision = 0


func _generate_nations() -> void:
	var palette := [
		Color(0.85, 0.22, 0.22),   # 红
		Color(0.25, 0.45, 0.85),   # 蓝
		Color(0.30, 0.70, 0.35),   # 绿
		Color(0.90, 0.80, 0.25),   # 黄
	]
	for i in range(NATION_COUNT):
		var n := Nation.new()
		n.id = i
		n.color = palette[i]
		n.treasury_gold = 200
		n.political_system = 0
		n.alive = true
		nations.append(n)


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
			city.defense = rng.randi_range(10, 30)
			city.manpower_per_month = rng.randi_range(5, 15)
			city.gold_per_month = rng.randi_range(5, 15)
			city.food_per_half_year = rng.randi_range(20, 60)
			# 先生成各城初始储备，随后统一归集到本国首都粮仓。
			city.food_storage = rng.randi_range(80, 100)
			city.at_war = true                                 # 开局全面战争
			cities.append(city)
			adjacency[city.id] = [] as Array[int]


func _generate_terrain_cities(terrain: Dictionary) -> void:
	var positions: Array[Vector2] = terrain["positions"]
	var heights: Array[float] = terrain["heights"]
	var reliefs: Array[float] = terrain["reliefs"]
	map_aspect_ratio = clampf(float(terrain["map_aspect_ratio"]), 0.5, 2.5)
	for id in range(CITY_COUNT):
		var city := City.new()
		city.id = id
		city.coord = Vector2i(id % GRID, id / GRID)
		city.map_position = positions[id]
		city.terrain_height = heights[id]
		city.terrain_relief = reliefs[id]
		city.defense = rng.randi_range(10, 30)
		city.manpower_per_month = rng.randi_range(5, 15)
		city.gold_per_month = rng.randi_range(5, 15)
		city.food_per_half_year = rng.randi_range(20, 60)
		city.food_storage = rng.randi_range(80, 100)
		city.at_war = true
		cities.append(city)
		adjacency[city.id] = [] as Array[int]


func _assign_balanced_nations(terrain: Dictionary) -> void:
	var nation_order: Array[int] = terrain["nation_order"]
	assert(nation_order.size() == CITY_COUNT, "国家分区骨架必须覆盖全部城市")
	var quota := CITY_COUNT / NATION_COUNT
	for index in range(nation_order.size()):
		cities[nation_order[index]].owner_nation = index / quota


func _initialize_manpower_pools() -> void:
	for nation in nations:
		nation.manpower_pool = 0
	for city in cities:
		# 初始人口库按 100 个月的单城产出标定，约等于旧版 500~1500 城市储备。
		nations[city.owner_nation].manpower_pool += city.manpower_per_month * 100


func _initialize_capitals_and_warehouses() -> void:
	var initial_food: Array[int] = []
	initial_food.resize(NATION_COUNT)
	initial_food.fill(0)
	for city in cities:
		initial_food[city.owner_nation] += city.food_storage
		city.food_storage = 0
		city.is_capital = false
		city.has_warehouse = false
	for nation in nations:
		var owned := cities_of(nation.id)
		var centroid := Vector2.ZERO
		for city in owned:
			centroid += city.map_position
		centroid /= float(maxi(owned.size(), 1))
		var capital_id := owned[0].id
		var best_distance := INF
		for city in owned:
			var distance := city.map_position.distance_squared_to(centroid)
			if distance < best_distance or (
				is_equal_approx(distance, best_distance) and city.id < capital_id
			):
				best_distance = distance
				capital_id = city.id
		nation.capital_city_id = capital_id
		nation.warehouse_city_ids = [capital_id] as Array[int]
		var capital := cities[capital_id]
		capital.is_capital = true
		capital.has_warehouse = true
		capital.food_storage = initial_food[nation.id]


## 四象限等分：每国 4x4=16 城
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


func _generate_terrain_edges(terrain: Dictionary) -> void:
	var roads: Array[Dictionary] = terrain["roads"]
	for road in roads:
		var a := int(road["a"])
		var b := int(road["b"])
		var lo := mini(a, b)
		var hi := maxi(a, b)
		var edge := Edge.new()
		edge.city_a = lo
		edge.city_b = hi
		edge.distance = int(road["distance"])
		edge.danger = float(road["danger"])
		edge.max_height_difference = float(road["height_difference"])
		edge.max_throughput = int(road["max_throughput"])
		edges.append(edge)
		edge_lookup[_edge_key(lo, hi)] = edge
		(adjacency[lo] as Array[int]).append(hi)
		(adjacency[hi] as Array[int]).append(lo)
	for city_id in adjacency.keys():
		(adjacency[city_id] as Array[int]).sort()


func _add_edge(a: int, b: int) -> void:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var e := Edge.new()
	e.city_a = lo
	e.city_b = hi
	e.distance = rng.randi_range(1, 5)
	e.danger = rng.randf_range(0.0, 0.5)
	e.max_throughput = 1
	e.occupied = false
	edges.append(e)
	edge_lookup[_edge_key(lo, hi)] = e
	(adjacency[lo] as Array[int]).append(hi)
	(adjacency[hi] as Array[int]).append(lo)


func _classify_road_throughput() -> void:
	var flow := {}
	for edge in edges:
		flow[_edge_key(edge.city_a, edge.city_b)] = 0.0
	# 全点对确定性最短路径流量，近似道路介数。
	for source in range(cities.size()):
		var field := _road_dijkstra(source)
		for goal in range(source + 1, cities.size()):
			_accumulate_road_flow(field["prev"], source, goal, flow, 1.0)
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
		edge.max_throughput = 1
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
		edge.max_throughput = 0
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
	var level4_count := int(ceil(float(roads.size()) * 0.08))
	var level3_end := level4_count + int(ceil(float(roads.size()) * 0.10))
	var level2_end := level3_end + int(ceil(float(roads.size()) * 0.20))
	for i in range(roads.size()):
		roads[i].max_throughput = 4 if i < level4_count else (
			3 if i < level3_end else (2 if i < level2_end else 1)
		)


func _road_dijkstra(start: int) -> Dictionary:
	var dist := {}
	var prev := {}
	var visited := {}
	for city in cities:
		dist[city.id] = INF
	dist[start] = 0.0
	while true:
		var current := -1
		var best := INF
		for city_id in dist.keys():
			if visited.has(city_id):
				continue
			var value: float = dist[city_id]
			if value < best:
				best = value
				current = city_id
		if current == -1:
			break
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
	return {"dist": dist, "prev": prev}


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


func _generate_armies() -> void:
	for city in cities:
		var army := create_army(city.owner_nation, city.id, city.manpower_per_month * 100)
		army.speed_factor = rng.randf_range(0.3, 0.9)
		army.attack = rng.randi_range(8, 15)
		army.defense = rng.randi_range(8, 15)


func create_army(nation_id: int, city_id: int, size: int) -> Army:
	if (
		nation_id < 0 or nation_id >= nations.size()
		or city_id < 0 or city_id >= cities.size()
		or cities[city_id].owner_nation != nation_id
		or size <= 0
	):
		return null
	var army := Army.new()
	army.id = _next_army_id
	_next_army_id += 1
	army.owner_nation = nation_id
	army.size = mini(size, army.max_size)
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	armies.append(army)
	return army

# ------------------------------------------------------------------ 查询辅助

func _edge_key(a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return lo * CITY_COUNT + hi


## 取两城之间的边（不存在返回 null）
func edge_of(a: int, b: int) -> Edge:
	return edge_lookup.get(_edge_key(a, b), null)


func neighbors(city_id: int) -> Array[int]:
	return adjacency.get(city_id, [] as Array[int])


func is_enemy(nation_a: int, nation_b: int) -> bool:
	return nation_a != nation_b


func army_at_city(city_id: int) -> Army:
	## 返回驻扎在该城的第一支军队。恢复中的撤退军仍是守军，不能被视为空城。
	var found := armies_at_city(city_id)
	return found[0] if not found.is_empty() else null


func armies_at_city(city_id: int) -> Array[Army]:
	## 返回该城全部本国驻军；恢复中的撤退军同样必须参加守城。
	var result: Array[Army] = []
	var city_owner := cities[city_id].owner_nation
	for army in armies:
		if army.size <= 0 or army.owner_nation != city_owner:
			continue
		if army.location_city == city_id and army.state in [Army.State.IDLE, Army.State.RECOVERING]:
			result.append(army)
	result.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
	return result


## 新建一场战斗并登记，返回该 Battle（id 已分配）。
func new_battle(kind: int) -> Battle:
	var b := Battle.new()
	b.id = _next_battle_id
	_next_battle_id += 1
	b.kind = kind
	battles.append(b)
	return b


func battle_by_id(bid: int) -> Battle:
	if bid < 0:
		return null
	for b in battles:
		if b.id == bid:
			return b
	return null


## 该城是否正被围攻（存在以其为目标的进行中 SIEGE）。规格 R3：被围城=补给孤岛。
func city_under_siege(city_id: int) -> bool:
	for b in battles:
		if not b.finished and b.kind == Battle.Kind.SIEGE and b.city != null and b.city.id == city_id:
			return true
	return false


func cities_of(nation_id: int) -> Array[City]:
	var result: Array[City] = []
	for city in cities:
		if city.owner_nation == nation_id:
			result.append(city)
	return result


func warehouse_cities_of(nation_id: int) -> Array[City]:
	var result: Array[City] = []
	if nation_id < 0 or nation_id >= nations.size():
		return result
	for city_id in nations[nation_id].warehouse_city_ids:
		if city_id < 0 or city_id >= cities.size():
			continue
		var city := cities[city_id]
		if city.owner_nation == nation_id and city.has_warehouse:
			result.append(city)
	result.sort_custom(func(a: City, b: City) -> bool: return a.id < b.id)
	return result


## 将粮食汇入首都粮仓；若首都暂不可用，则回退到第一个有效粮仓。
func deposit_food(nation_id: int, amount: int) -> bool:
	if amount <= 0 or nation_id < 0 or nation_id >= nations.size():
		return false
	var nation := nations[nation_id]
	var target: City = null
	if nation.capital_city_id >= 0 and nation.capital_city_id < cities.size():
		var capital := cities[nation.capital_city_id]
		if capital.owner_nation == nation_id and capital.has_warehouse:
			target = capital
	if target == null:
		var warehouses := warehouse_cities_of(nation_id)
		if not warehouses.is_empty():
			target = warehouses[0]
	if target == null:
		return false
	target.food_storage += amount
	return true


func remove_warehouse(nation_id: int, city_id: int) -> void:
	if nation_id < 0 or nation_id >= nations.size():
		return
	var nation := nations[nation_id]
	nation.warehouse_city_ids.erase(city_id)
	if nation.capital_city_id == city_id:
		nation.capital_city_id = -1
	if city_id >= 0 and city_id < cities.size():
		cities[city_id].is_capital = false
		cities[city_id].has_warehouse = false


## 首都失守后，从剩余城市中选择防御最高者迁都（同防御按 id 升序）。
func relocate_capital(nation_id: int) -> int:
	if nation_id < 0 or nation_id >= nations.size():
		return -1
	var candidates := cities_of(nation_id)
	if candidates.is_empty():
		nations[nation_id].capital_city_id = -1
		return -1
	candidates.sort_custom(func(a: City, b: City) -> bool:
		return a.defense > b.defense or (a.defense == b.defense and a.id < b.id)
	)
	var capital := candidates[0]
	var nation := nations[nation_id]
	nation.capital_city_id = capital.id
	if not nation.warehouse_city_ids.has(capital.id):
		nation.warehouse_city_ids.append(capital.id)
	capital.is_capital = true
	capital.has_warehouse = true
	return capital.id


## 刷新派生量：国家 granary_food（粮仓求和）与 alive（是否还有城市）
func refresh_derived() -> void:
	for n in nations:
		n.granary_food = 0
		n.alive = false
	for city in cities:
		var owner := nations[city.owner_nation]
		owner.alive = true
	for n in nations:
		for warehouse in warehouse_cities_of(n.id):
			n.granary_food += warehouse.food_storage
