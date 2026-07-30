class_name GameState
extends RefCounted
## 单一数据源（SSoT）：持有全部 cities / edges / nations / armies，
## 并负责确定性世界生成。所有可变游戏状态都归此对象所有。

const GRID: int = 8                         ## 8x8 网格
const CITY_COUNT: int = GRID * GRID         ## 64
const NATION_COUNT: int = 4
const CITY_MANPOWER_PER_MONTH_MIN: int = 10
const CITY_MANPOWER_PER_MONTH_MAX: int = 30
const INITIAL_MANPOWER_RESERVE_MONTHS: int = 150
const INITIAL_ARMY_MANPOWER_MONTHS: int = 50
const DEFAULT_TRUCE_DAYS: int = 180
const WAR_GOLD_TROOPS_PER_UNIT: int = 100
const FOOD_HUB_MIN_OUTPUT: int = 240
const MANPOWER_HUB_MIN_OUTPUT: int = 80
const TERRAIN_MAP_PATH := (
	"res://china-map-china-flag-shaded-relief-color-height-map-3d-illustration-png.webp"
)

enum DiplomaticRelation {
	NEUTRAL,
	WAR,
	ALLIED,
}

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
var diplomacy_revision: int = 0             ## 外交关系版本号，供 AI 战略缓存失效
## 规范化国家对 key -> DiplomaticRelation / 关系生效日 / 停战截止日。
var diplomatic_relations: Dictionary = {}
var diplomatic_since_day: Dictionary = {}
var truce_until_day: Dictionary = {}
var diplomatic_history: Array[Dictionary] = []
## 规范化国家对 key -> {attacker, defender, city_id, reason, started_day}。
var war_objectives: Dictionary = {}
var uses_heightmap: bool = false
var map_aspect_ratio: float = 1.0
var map_source_region_normalized: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
## 每个有效栅格像素保存所属 city_id；-1 表示地图轮廓外。
var province_map_size: Vector2i = Vector2i.ZERO
var province_ids: PackedInt32Array = PackedInt32Array()
## 法理归属用于区分“本国底色”和“占领国斜线”；和平协议会确认实际控制区。
var recognized_city_owners: PackedInt32Array = PackedInt32Array()
## 短时战略箭头事件：{start_day,end_day,nation_id,target_city,origin_cities,wave}。
var campaign_visual_events: Array[Dictionary] = []

## 结束态
var winner: int = -1                        ## -1 表示未结束

# ------------------------------------------------------------------ 生成

func generate_world(world_seed: int = 12345) -> void:
	_reset_world(world_seed)
	uses_heightmap = true
	_generate_nations(DiplomaticRelation.NEUTRAL)
	var terrain := TerrainMapGenerator.build(TERRAIN_MAP_PATH, CITY_COUNT)
	_generate_terrain_cities(terrain)
	_assign_balanced_nations()
	_initialize_recognized_city_owners()
	_generate_terrain_edges(terrain)
	_initialize_resource_hubs()
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
	map_source_region_normalized = Rect2(0.0, 0.0, 1.0, 1.0)
	_generate_nations(DiplomaticRelation.WAR)
	_generate_grid_cities()
	_generate_grid_provinces()
	_initialize_recognized_city_owners()
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
	diplomacy_revision = 0
	diplomatic_relations.clear()
	diplomatic_since_day.clear()
	truce_until_day.clear()
	diplomatic_history.clear()
	war_objectives.clear()
	province_map_size = Vector2i.ZERO
	province_ids = PackedInt32Array()
	recognized_city_owners = PackedInt32Array()
	campaign_visual_events.clear()


func _generate_nations(initial_relation: int) -> void:
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
	for nation_a in range(nations.size()):
		for nation_b in range(nation_a + 1, nations.size()):
			var key := _diplomacy_key(nation_a, nation_b)
			diplomatic_relations[key] = initial_relation
			diplomatic_since_day[key] = day


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
			city.manpower_per_month = rng.randi_range(
				CITY_MANPOWER_PER_MONTH_MIN,
				CITY_MANPOWER_PER_MONTH_MAX
			)
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
	map_source_region_normalized = terrain["source_region_normalized"]
	province_map_size = terrain["province_map_size"]
	province_ids = (terrain["province_ids"] as PackedInt32Array).duplicate()
	for id in range(CITY_COUNT):
		var city := City.new()
		city.id = id
		city.coord = Vector2i(id % GRID, id / GRID)
		city.map_position = positions[id]
		city.terrain_height = heights[id]
		city.terrain_relief = reliefs[id]
		city.defense = rng.randi_range(10, 30)
		city.manpower_per_month = rng.randi_range(
			CITY_MANPOWER_PER_MONTH_MIN,
			CITY_MANPOWER_PER_MONTH_MAX
		)
		city.gold_per_month = rng.randi_range(5, 15)
		city.food_per_half_year = rng.randi_range(20, 60)
		city.food_storage = rng.randi_range(80, 100)
		city.at_war = false
		cities.append(city)
		adjacency[city.id] = [] as Array[int]


func _generate_grid_provinces() -> void:
	province_map_size = Vector2i(GRID, GRID)
	province_ids.resize(CITY_COUNT)
	for city_id in range(CITY_COUNT):
		province_ids[city_id] = city_id


func _initialize_recognized_city_owners() -> void:
	recognized_city_owners.resize(cities.size())
	for city in cities:
		recognized_city_owners[city.id] = city.owner_nation


func _assign_balanced_nations() -> void:
	var ordered: Array[City] = cities.duplicate()
	ordered.sort_custom(func(a: City, b: City) -> bool:
		return (
			a.map_position.x < b.map_position.x
			or (
				is_equal_approx(a.map_position.x, b.map_position.x)
				and a.id < b.id
			)
		)
	)
	var side_size := CITY_COUNT / 2
	for side in range(2):
		var side_cities: Array[City] = []
		for index in range(side * side_size, (side + 1) * side_size):
			side_cities.append(ordered[index])
		side_cities.sort_custom(func(a: City, b: City) -> bool:
			return (
				a.map_position.y < b.map_position.y
				or (
					is_equal_approx(a.map_position.y, b.map_position.y)
					and a.id < b.id
				)
			)
		)
		for index in range(side_cities.size()):
			var row_half := 0 if index < side_cities.size() / 2 else 1
			side_cities[index].owner_nation = row_half * 2 + side


func _initialize_manpower_pools() -> void:
	for nation in nations:
		nation.manpower_pool = 0
	for city in cities:
		nations[city.owner_nation].manpower_pool += (
			city.manpower_per_month * INITIAL_MANPOWER_RESERVE_MONTHS
		)


func _initialize_resource_hubs() -> void:
	for city in cities:
		city.is_food_hub = false
		city.is_manpower_hub = false
	for nation in nations:
		var owned := cities_of(nation.id)
		if owned.is_empty():
			continue
		var food_hub: City = owned[0]
		for city in owned:
			if (
				city.food_per_half_year > food_hub.food_per_half_year
				or (
					city.food_per_half_year == food_hub.food_per_half_year
					and city.id < food_hub.id
				)
			):
				food_hub = city
		food_hub.is_food_hub = true
		food_hub.food_per_half_year = maxi(
			food_hub.food_per_half_year * 4,
			FOOD_HUB_MIN_OUTPUT
		)
		var manpower_hub: City = food_hub
		for city in owned:
			if city == food_hub and owned.size() > 1:
				continue
			if (
				manpower_hub == food_hub
				or city.manpower_per_month > manpower_hub.manpower_per_month
				or (
					city.manpower_per_month == manpower_hub.manpower_per_month
					and city.id < manpower_hub.id
				)
			):
				manpower_hub = city
		manpower_hub.is_manpower_hub = true
		manpower_hub.manpower_per_month = maxi(
			manpower_hub.manpower_per_month * 3,
			MANPOWER_HUB_MIN_OUTPUT
		)


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
		var army := create_army(
			city.owner_nation,
			city.id,
			clampi(
				city.manpower_per_month,
				CITY_MANPOWER_PER_MONTH_MIN,
				CITY_MANPOWER_PER_MONTH_MAX
			) * INITIAL_ARMY_MANPOWER_MONTHS
		)
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
	return relation_between(nation_a, nation_b) == DiplomaticRelation.WAR


func is_allied(nation_a: int, nation_b: int) -> bool:
	return (
		nation_a == nation_b
		or relation_between(nation_a, nation_b) == DiplomaticRelation.ALLIED
	)


func relation_between(nation_a: int, nation_b: int) -> int:
	if nation_a == nation_b:
		return DiplomaticRelation.ALLIED
	if (
		nation_a < 0
		or nation_b < 0
		or nation_a >= nations.size()
		or nation_b >= nations.size()
	):
		# 非法/测试占位国家不得被视为可安全借道的中立方。
		return DiplomaticRelation.WAR
	return int(diplomatic_relations.get(
		_diplomacy_key(nation_a, nation_b),
		DiplomaticRelation.WAR
	))


func relation_since(nation_a: int, nation_b: int) -> int:
	return int(diplomatic_since_day.get(_diplomacy_key(nation_a, nation_b), 0))


func truce_until(nation_a: int, nation_b: int) -> int:
	return int(truce_until_day.get(_diplomacy_key(nation_a, nation_b), 0))


func war_objective(nation_a: int, nation_b: int) -> Dictionary:
	return war_objectives.get(_diplomacy_key(nation_a, nation_b), {})


func set_war_objective(
	attacker: int,
	defender: int,
	city_id: int,
	reason: String
) -> void:
	war_objectives[_diplomacy_key(attacker, defender)] = {
		"attacker": attacker,
		"defender": defender,
		"city_id": city_id,
		"reason": reason,
		"started_day": day,
	}


func clear_war_objective(nation_a: int, nation_b: int) -> void:
	war_objectives.erase(_diplomacy_key(nation_a, nation_b))


func can_declare_war(nation_a: int, nation_b: int) -> bool:
	return (
		nation_a != nation_b
		and nation_a >= 0
		and nation_b >= 0
		and nation_a < nations.size()
		and nation_b < nations.size()
		and nations[nation_a].alive
		and nations[nation_b].alive
		and relation_between(nation_a, nation_b) == DiplomaticRelation.NEUTRAL
		and day >= truce_until(nation_a, nation_b)
	)


func set_diplomatic_relation(
	nation_a: int,
	nation_b: int,
	relation: int,
	truce_days: int = 0
) -> bool:
	if (
		nation_a == nation_b
		or nation_a < 0
		or nation_b < 0
		or nation_a >= nations.size()
		or nation_b >= nations.size()
		or relation not in [
			DiplomaticRelation.NEUTRAL,
			DiplomaticRelation.WAR,
			DiplomaticRelation.ALLIED,
		]
	):
		return false
	var key := _diplomacy_key(nation_a, nation_b)
	var previous := relation_between(nation_a, nation_b)
	if previous == relation:
		return false
	diplomatic_relations[key] = relation
	diplomatic_since_day[key] = day
	if previous == DiplomaticRelation.WAR and relation != DiplomaticRelation.WAR:
		truce_until_day[key] = maxi(
			int(truce_until_day.get(key, 0)),
			day + maxi(truce_days, 0)
		)
	diplomacy_revision += 1
	return true


func wars_of(nation_id: int) -> Array[int]:
	var result: Array[int] = []
	for other in nations:
		if other.id != nation_id and other.alive and is_enemy(nation_id, other.id):
			result.append(other.id)
	return result


func allies_of(nation_id: int) -> Array[int]:
	var result: Array[int] = []
	for other in nations:
		if other.id != nation_id and other.alive and is_allied(nation_id, other.id):
			result.append(other.id)
	return result


func _diplomacy_key(nation_a: int, nation_b: int) -> String:
	var lo := mini(nation_a, nation_b)
	var hi := maxi(nation_a, nation_b)
	return "%d:%d" % [lo, hi]


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


func recognized_owner_of(city_id: int) -> int:
	if city_id < 0 or city_id >= recognized_city_owners.size():
		return -1
	return recognized_city_owners[city_id]


## 双边和平只确认交战双方之间的实际控制区，不误处理第三国领土。
func recognize_occupied_territory(
	nation_a: int,
	nation_b: int
) -> Array[int]:
	var transferred: Array[int] = []
	for city in cities:
		var recognized_owner := recognized_owner_of(city.id)
		if (
			city.owner_nation == recognized_owner
			or city.owner_nation not in [nation_a, nation_b]
			or recognized_owner not in [nation_a, nation_b]
		):
			continue
		recognized_city_owners[city.id] = city.owner_nation
		transferred.append(city.id)
	if not transferred.is_empty():
		ownership_revision += 1
	return transferred


func add_campaign_visual_event(
	nation_id: int,
	target_city: int,
	origin_cities: Array[int],
	wave: int,
	duration_days: int
) -> void:
	campaign_visual_events.append({
		"start_day": day,
		"end_day": day + maxi(duration_days, 1),
		"nation_id": nation_id,
		"target_city": target_city,
		"origin_cities": origin_cities.duplicate(),
		"wave": wave,
	})


func prune_campaign_visual_events() -> void:
	campaign_visual_events = campaign_visual_events.filter(
		func(event: Dictionary) -> bool:
			return day <= int(event["end_day"])
	)


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
