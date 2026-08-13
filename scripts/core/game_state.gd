class_name GameState
extends RefCounted
## 单一数据源（SSoT）：持有全部 cities / edges / nations / armies，
## 并负责确定性世界生成。所有可变游戏状态都归此对象所有。

const GRID: int = 8                         ## 8x8 网格
const CITY_COUNT: int = GRID * GRID         ## 64 城兼容网格夹具
const TERRAIN_CITY_COUNT: int = 160         ## 正式高度图基础陆城；动态码头另计
const NATION_COUNT: int = 4
const CITY_MANPOWER_PER_MONTH_MIN: int = 10
const CITY_MANPOWER_PER_MONTH_MAX: int = 30
const INITIAL_MANPOWER_RESERVE_MONTHS: int = 750
const INITIAL_LIGHT_ARMY_SIZE: int = 5000
const INITIAL_HEAVY_ARMY_SIZE: int = 15000
const ARMY_COUNT_LIMIT_PER_CITY: int = 3
const DEFAULT_TRUCE_DAYS: int = 180
const WAR_GOLD_TROOPS_PER_UNIT: int = 1400
const FORMATION_CREATION_UPKEEP_MONTHS: int = 10
const OFFENSIVE_COMMAND_GOLD_PER_ARMY: int = 2
const CITY_FOOD_PER_HALF_YEAR_MIN: int = 400
const CITY_FOOD_PER_HALF_YEAR_MAX: int = 600
const TERRAIN_CITY_GOLD_PER_MONTH_MIN: int = 1
const TERRAIN_CITY_GOLD_PER_MONTH_MAX: int = 5
const TERRAIN_CITY_GOLD_TARGET_AVERAGE: int = 7
const TERRAIN_CITY_GOLD_OUTPUT_MIN: int = 1
const TERRAIN_CITY_GOLD_OUTPUT_MAX: int = 15
const TERRAIN_CITY_FOOD_PER_HALF_YEAR_MIN: int = 145
const TERRAIN_CITY_FOOD_PER_HALF_YEAR_MAX: int = 195
const PLAIN_CITY_SHARE: float = 0.35
const PORT_MARKET_OUTPUT_MULTIPLIER: float = 3.0
const CROSSROADS_GOLD_MULTIPLIER: float = 1.5
const PLAIN_GOLD_MULTIPLIER: float = 1.5
const PLAIN_FOOD_MULTIPLIER: float = 1.5
const DEVELOPMENT_PROPAGATION_RATE: float = 0.5
const TERRAIN_HEIGHT_OUTPUT_MIN_MULTIPLIER: float = 0.2
const TERRAIN_HEIGHT_OUTPUT_SIGMOID_MIDPOINT: float = 0.5
const TERRAIN_HEIGHT_OUTPUT_SIGMOID_STEEPNESS: float = 10.0
const CROSSROADS_MIN_ROADS: int = 6
const INITIAL_CITY_FOOD_STOCK_MIN: int = 500
const INITIAL_CITY_FOOD_STOCK_MAX: int = 600
const FOOD_HUB_MIN_OUTPUT: int = 1600
const MANPOWER_HUB_MIN_OUTPUT: int = 80
const TERRAIN_MAP_PATH := (
	"res://china-map-china-flag-shaded-relief-color-height-map-3d-illustration-png.webp"
)

enum DiplomaticRelation {
	NEUTRAL,
	WAR,
	ALLIED,
}

## 分封默认贡赋率。
const DEFAULT_TRIBUTE_RATE: float = 0.25
const VASSAL_COLOR_HUE_OFFSET_DEGREES: float = 10.0
const VASSAL_COLOR_SATURATION_OFFSET: float = 0.10
const VASSAL_COLOR_VALUE_OFFSET: float = 0.05
const VASSAL_COLOR_SUBJECT_HUE_VARIANCE_DEGREES: float = 4.0


static func army_monthly_upkeep(troops: int) -> int:
	if troops <= 0:
		return 0
	return int(ceil(
		float(troops) / float(WAR_GOLD_TROOPS_PER_UNIT)
	))


static func formation_creation_gold_cost(formation_size: int) -> int:
	return (
		army_monthly_upkeep(formation_size)
		* FORMATION_CREATION_UPKEEP_MONTHS
	)


static func offensive_army_gold_cost(troops: int) -> int:
	if troops <= 0:
		return 0
	return (
		army_monthly_upkeep(troops)
		+ OFFENSIVE_COMMAND_GOLD_PER_ARMY
	)


func nation_monthly_military_upkeep(nation_id: int) -> int:
	var total := 0
	for army in armies:
		if army.owner_nation == nation_id and army.size > 0:
			total += army_monthly_upkeep(army.size)
	return total

var cities: Array[City] = []
var edges: Array[Edge] = []
var nations: Array[Nation] = []
var armies: Array[Army] = []
var battles: Array[Battle] = []            ## 进行中的多回合战斗

## 邻接表：city_id -> Array[int]（相邻 city_id）
var adjacency: Dictionary = {}
## 边查找：规范化无碰撞 int64 key -> Edge
var edge_lookup: Dictionary = {}

var day: int = 0                            ## 时间真源（1 tick = 1 天）
var month: int = 0                          ## 派生显示量：day / DAYS_PER_MONTH（每 tick 由 Simulation 刷新）
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_army_id: int = 0
var _next_battle_id: int = 0
var ownership_revision: int = 0             ## 城市易主版本号，供战略地图缓存失效
var diplomacy_revision: int = 0             ## 外交关系版本号，供 AI 战略缓存失效
var fortification_revision: int = 0         ## 当前城防变化版本号，供 AI 战略缓存失效
## 规范化国家对 key -> DiplomaticRelation / 关系生效日 / 停战截止日。
var diplomatic_relations: Dictionary = {}
var diplomatic_since_day: Dictionary = {}
var truce_until_day: Dictionary = {}
var diplomatic_history: Array[Dictionary] = []
## 规范化国家对 key -> {attacker, defender, city_id, reason, started_day}。
var war_objectives: Dictionary = {}
## 宗藩关系有向真源（SSoT）：subject_id -> {
##     overlord_id, tribute_rate, created_day,
##     last_centralization_day, civil_war
## }。不对称，故不塞进对称的 diplomatic_relations。
## 不变量：一个藩王至多一个宗主；宗主链无环；非内战宗藩对为 ALLIED，
## 削藩内战宗藩对为 WAR。
var suzerainty: Dictionary = {}
var uses_heightmap: bool = false
var map_aspect_ratio: float = 1.0
var map_source_region_normalized: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)
## 每个有效栅格像素保存所属 city_id；-1 表示地图轮廓外。
var province_map_size: Vector2i = Vector2i.ZERO
var province_ids: PackedInt32Array = PackedInt32Array()
## 正式地图河流折线（归一化地图坐标），仅用于渲染；通行真源仍是 Edge。
var river_paths: Array[PackedVector2Array] = []
## 法理归属用于区分“本国底色”和“占领国斜线”；和平协议会确认实际控制区。
var recognized_city_owners: PackedInt32Array = PackedInt32Array()
## 短时战略箭头事件：{start_day,end_day,nation_id,target_city,origin_cities,wave}。
var campaign_visual_events: Array[Dictionary] = []

## 结束态
var winner: int = -1                        ## -1 表示未结束

# ------------------------------------------------------------------ 生成

func generate_world(
	world_seed: int = 12345,
	nation_count: int = NATION_COUNT,
	terrain_city_count: int = TERRAIN_CITY_COUNT
) -> void:
	assert(
		nation_count > 0
			and nation_count <= terrain_city_count,
		"国家数必须在 1..%d 之间" % terrain_city_count
	)
	_reset_world(world_seed)
	uses_heightmap = true
	_generate_nations(
		DiplomaticRelation.NEUTRAL,
		nation_count
	)
	var terrain := TerrainMapGenerator.build(
		TERRAIN_MAP_PATH,
		terrain_city_count
	)
	_generate_terrain_cities(terrain)
	_assign_balanced_nations()
	_generate_terrain_docks(terrain)
	_generate_terrain_edges(terrain)
	_repair_initial_nation_connectivity()
	_initialize_recognized_city_owners()
	_initialize_resource_hubs()
	_initialize_terrain_development()
	_initialize_manpower_pools()
	_initialize_capitals_and_warehouses()
	_generate_armies()

	assert(
		land_cities().size() == terrain_city_count,
		"正式地图陆地城市数应为 %d" % terrain_city_count
	)
	assert(
		cities.size() > terrain_city_count,
		"正式地图应生成河运码头"
	)
	assert(
		edges.size() >= terrain_city_count - 1,
		"道路图必须连通"
	)
	assert(
		_battle_group_structure_valid(),
		"正式地图初始重军必须属于合法的持久战团"
	)


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
	_classify_road_capacity()
	_generate_armies()

	assert(cities.size() == CITY_COUNT, "城市数应为 64")
	assert(edges.size() == 2 * GRID * (GRID - 1), "网格夹具边数应为 112")
	assert(
		armies.size()
			== CITY_COUNT + NATION_COUNT * 3,
		"网格状态机夹具必须保留每城填线军和每国一个满编战团"
	)
	assert(_battle_group_structure_valid(), "网格战团结构必须合法")


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
	fortification_revision = 0
	diplomatic_relations.clear()
	diplomatic_since_day.clear()
	truce_until_day.clear()
	diplomatic_history.clear()
	war_objectives.clear()
	suzerainty.clear()
	province_map_size = Vector2i.ZERO
	province_ids = PackedInt32Array()
	river_paths.clear()
	recognized_city_owners = PackedInt32Array()
	campaign_visual_events.clear()


func _generate_nations(
	initial_relation: int,
	nation_count: int = NATION_COUNT
) -> void:
	var palette := [
		Color(0.85, 0.22, 0.22),   # 红
		Color(0.25, 0.45, 0.85),   # 蓝
		Color(0.30, 0.70, 0.35),   # 绿
		Color(0.90, 0.80, 0.25),   # 黄
	]
	for i in range(nation_count):
		var n := Nation.new()
		n.id = i
		n.color = (
			palette[i]
			if nation_count == NATION_COUNT
			else Color.from_hsv(
				fposmod(
					float(i) * 0.61803398875,
					1.0
				),
				0.65,
				0.85
			)
		)
		n.treasury_gold = 10000
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
			city.fort_strength = rng.randi_range(10, 30)
			city.fort_strength_max = city.fort_strength
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


func _generate_terrain_cities(terrain: Dictionary) -> void:
	var positions: Array[Vector2] = terrain["positions"]
	var heights: Array[float] = terrain["heights"]
	var reliefs: Array[float] = terrain["reliefs"]
	map_aspect_ratio = clampf(float(terrain["map_aspect_ratio"]), 0.5, 2.5)
	map_source_region_normalized = terrain["source_region_normalized"]
	province_map_size = terrain["province_map_size"]
	province_ids = (terrain["province_ids"] as PackedInt32Array).duplicate()
	for id in range(positions.size()):
		var city := City.new()
		city.id = id
		city.coord = Vector2i(id % GRID, id / GRID)
		city.map_position = positions[id]
		city.terrain_height = heights[id]
		city.terrain_relief = reliefs[id]
		city.fort_strength = rng.randi_range(10, 30)
		city.fort_strength_max = city.fort_strength
		city.manpower_per_month = rng.randi_range(
			CITY_MANPOWER_PER_MONTH_MIN,
			CITY_MANPOWER_PER_MONTH_MAX
		)
		city.gold_per_month = rng.randi_range(
			TERRAIN_CITY_GOLD_PER_MONTH_MIN,
			TERRAIN_CITY_GOLD_PER_MONTH_MAX
		)
		city.food_per_half_year = rng.randi_range(
			TERRAIN_CITY_FOOD_PER_HALF_YEAR_MIN,
			TERRAIN_CITY_FOOD_PER_HALF_YEAR_MAX
		)
		city.food_storage = rng.randi_range(
			INITIAL_CITY_FOOD_STOCK_MIN,
			INITIAL_CITY_FOOD_STOCK_MAX
		)
		city.at_war = false
		cities.append(city)
		adjacency[city.id] = [] as Array[int]


func _generate_terrain_docks(terrain: Dictionary) -> void:
	river_paths.clear()
	for path_value in terrain.get("river_paths", []):
		var path: PackedVector2Array = path_value
		river_paths.append(path.duplicate())
	var docks: Array[Dictionary] = terrain.get(
		"docks",
		[] as Array[Dictionary]
	)
	for dock_data in docks:
		var city := City.new()
		city.id = cities.size()
		assert(
			city.id == int(dock_data["city_id"]),
			"码头城市 id 必须与河运边端点一致"
		)
		var position: Vector2 = dock_data["position"]
		city.coord = Vector2i(
			int(round(position.x * 1000.0)),
			int(round(position.y * 1000.0))
		)
		city.map_position = position
		city.terrain_height = float(dock_data["height"])
		city.terrain_relief = float(dock_data["relief"])
		city.is_dock = true
		var road_t := float(dock_data["road_t"])
		var owner_city := (
			int(dock_data["road_a"])
			if road_t <= 0.5
			else int(dock_data["road_b"])
		)
		city.owner_nation = cities[owner_city].owner_nation
		city.fort_strength = 10
		city.fort_strength_max = 10
		# 码头是完整可占领城市，但不凭空扩大开局四国经济盘子。
		city.manpower_per_month = 0
		city.gold_per_month = 0
		city.food_per_half_year = 0
		city.food_storage = 0
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
	if nations.size() != NATION_COUNT:
		var partition_cities: Array[City] = cities.duplicate()
		_assign_spatial_nation_partition(
			partition_cities,
			0,
			nations.size()
		)
		return
	var ordered: Array[City] = cities.duplicate()
	ordered.sort_custom(func(a: City, b: City) -> bool:
		if not is_equal_approx(a.map_position.x, b.map_position.x):
			return a.map_position.x < b.map_position.x
		return a.map_position.y < b.map_position.y
	)
	var side_size := ordered.size() / 2
	for side in range(2):
		var side_cities: Array[City] = []
		for index in range(side * side_size, (side + 1) * side_size):
			side_cities.append(ordered[index])
		side_cities.sort_custom(func(a: City, b: City) -> bool:
				if not is_equal_approx(a.map_position.y, b.map_position.y):
					return a.map_position.y < b.map_position.y
				return a.map_position.x < b.map_position.x
		)
		for index in range(side_cities.size()):
			var row_half := 0 if index < side_cities.size() / 2 else 1
			side_cities[index].owner_nation = row_half * 2 + side


func _assign_spatial_nation_partition(
	partition_cities: Array[City],
	first_nation: int,
	partition_nations: int
) -> void:
	assert(
		partition_nations > 0
			and partition_cities.size() >= partition_nations,
		"空间分区必须保证每国至少一座陆城"
	)
	if partition_nations == 1:
		for city in partition_cities:
			city.owner_nation = first_nation
		return
	var min_position := partition_cities[0].map_position
	var max_position := min_position
	for city in partition_cities:
		min_position = min_position.min(city.map_position)
		max_position = max_position.max(city.map_position)
	var split_x := (
		max_position.x - min_position.x
			>= max_position.y - min_position.y
	)
	partition_cities.sort_custom(
		func(a: City, b: City) -> bool:
			var primary_a := (
				a.map_position.x
				if split_x
				else a.map_position.y
			)
			var primary_b := (
				b.map_position.x
				if split_x
				else b.map_position.y
			)
			if not is_equal_approx(primary_a, primary_b):
				return primary_a < primary_b
			var secondary_a := (
				a.map_position.y
				if split_x
				else a.map_position.x
			)
			var secondary_b := (
				b.map_position.y
				if split_x
				else b.map_position.x
			)
			if not is_equal_approx(secondary_a, secondary_b):
				return secondary_a < secondary_b
			return a.id < b.id
	)
	var left_nations := partition_nations / 2
	var right_nations := partition_nations - left_nations
	var split_index := clampi(
		int(round(
			float(partition_cities.size())
				* float(left_nations)
				/ float(partition_nations)
		)),
		left_nations,
		partition_cities.size() - right_nations
	)
	var left_cities: Array[City] = []
	var right_cities: Array[City] = []
	for index in range(partition_cities.size()):
		if index < split_index:
			left_cities.append(partition_cities[index])
		else:
			right_cities.append(partition_cities[index])
	_assign_spatial_nation_partition(
		left_cities,
		first_nation,
		left_nations
	)
	_assign_spatial_nation_partition(
		right_cities,
		first_nation + left_nations,
		right_nations
	)


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
		var owned := land_cities_of(nation.id)
		if owned.is_empty():
			continue
		var food_hub: City = owned[0]
		for city in owned:
			if (
				city.food_per_half_year > food_hub.food_per_half_year
				or (
					city.food_per_half_year == food_hub.food_per_half_year
						and EquivariantOrder.city_less(
							self,
							nation.id,
							city,
							food_hub
						)
				)
			):
				food_hub = city
		food_hub.is_food_hub = true
		food_hub.food_per_half_year = maxi(
			food_hub.food_per_half_year * 4,
				(
					FOOD_HUB_MIN_OUTPUT
					if nations.size() == NATION_COUNT
					else 0
				)
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
						and EquivariantOrder.city_less(
							self,
							nation.id,
							city,
							manpower_hub
						)
				)
			):
				manpower_hub = city
		manpower_hub.is_manpower_hub = true
		manpower_hub.manpower_per_month = maxi(
			manpower_hub.manpower_per_month * 3,
			MANPOWER_HUB_MIN_OUTPUT
		)


## 端点归一化 Logistic 海拔惩罚：低地保持 1.0、最高地保持 0.2，
## 西南高原集中的归一化海拔 0.65~0.75 区间约为 0.34~0.25。
static func terrain_height_output_multiplier(
	normalized_height: float
) -> float:
	var height := clampf(normalized_height, 0.0, 1.0)
	var sigmoid_at_low := 1.0 / (
		1.0 + exp(
			TERRAIN_HEIGHT_OUTPUT_SIGMOID_STEEPNESS
				* (0.0 - TERRAIN_HEIGHT_OUTPUT_SIGMOID_MIDPOINT)
		)
	)
	var sigmoid_at_high := 1.0 / (
		1.0 + exp(
			TERRAIN_HEIGHT_OUTPUT_SIGMOID_STEEPNESS
				* (1.0 - TERRAIN_HEIGHT_OUTPUT_SIGMOID_MIDPOINT)
		)
	)
	var sigmoid_at_height := 1.0 / (
		1.0 + exp(
			TERRAIN_HEIGHT_OUTPUT_SIGMOID_STEEPNESS
				* (
					height
					- TERRAIN_HEIGHT_OUTPUT_SIGMOID_MIDPOINT
				)
		)
	)
	var normalized_sigmoid := (
		(sigmoid_at_height - sigmoid_at_high)
		/ (sigmoid_at_low - sigmoid_at_high)
	)
	return (
		TERRAIN_HEIGHT_OUTPUT_MIN_MULTIPLIER
		+ (
			1.0
			- TERRAIN_HEIGHT_OUTPUT_MIN_MULTIPLIER
		) * normalized_sigmoid
	)


func _initialize_terrain_development() -> void:
	if not uses_heightmap:
		return
	var land := land_cities()
	if land.is_empty():
		return
	var minimum_height := INF
	var maximum_height := -INF
	for city in land:
		minimum_height = minf(
			minimum_height,
			city.terrain_height
		)
		maximum_height = maxf(
			maximum_height,
			city.terrain_height
		)
	var height_span := maxf(
		maximum_height - minimum_height,
		0.000001
	)
	for city in land:
		var normalized_height := (
			(city.terrain_height - minimum_height)
			/ height_span
		)
		city.terrain_output_multiplier = (
			terrain_height_output_multiplier(
				normalized_height
			)
		)
	var relief_order := land.duplicate()
	relief_order.sort_custom(func(a: City, b: City) -> bool:
		if not is_equal_approx(
			a.terrain_relief,
			b.terrain_relief
		):
			return a.terrain_relief < b.terrain_relief
		if not is_equal_approx(
			a.map_position.x,
			b.map_position.x
		):
			return a.map_position.x < b.map_position.x
		return a.map_position.y < b.map_position.y
	)
	var plain_count := clampi(
		int(round(float(land.size()) * PLAIN_CITY_SHARE)),
		1,
		land.size()
	)
	var plain_ids := {}
	for index in range(plain_count):
		plain_ids[relief_order[index].id] = true
	var direct_gold := {}
	var direct_food := {}
	var original_food_total := 0
	for city in land:
		city.is_plain_city = plain_ids.has(city.id)
		city.is_port_market = false
		city.is_crossroads = false
		var road_count := 0
		for neighbor in neighbors(city.id):
			var edge := edge_of(city.id, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			if edge.kind != Edge.Kind.RIVER:
				road_count += 1
			if cities[neighbor].is_dock:
				city.is_port_market = true
		city.is_crossroads = road_count >= CROSSROADS_MIN_ROADS
		var gold_multiplier := 1.0
		if city.is_port_market:
			gold_multiplier = maxf(
				gold_multiplier,
				PORT_MARKET_OUTPUT_MULTIPLIER
			)
		if city.is_crossroads:
			gold_multiplier = maxf(
				gold_multiplier,
				CROSSROADS_GOLD_MULTIPLIER
			)
		if city.is_plain_city:
			gold_multiplier = maxf(
				gold_multiplier,
				PLAIN_GOLD_MULTIPLIER
			)
		var food_multiplier := 1.0
		if city.is_port_market:
			food_multiplier = maxf(
				food_multiplier,
				PORT_MARKET_OUTPUT_MULTIPLIER
			)
		if city.is_plain_city:
			food_multiplier = maxf(
				food_multiplier,
				PLAIN_FOOD_MULTIPLIER
			)
		direct_gold[city.id] = gold_multiplier
		direct_food[city.id] = food_multiplier
		original_food_total += city.food_per_half_year
	var propagated_gold := {}
	var propagated_food := {}
	for source in land:
		var source_gold_bonus := maxf(
			float(direct_gold[source.id]) - 1.0,
			0.0
		)
		var source_food_bonus := maxf(
			float(direct_food[source.id]) - 1.0,
			0.0
		)
		if source_gold_bonus <= 0.0 and source_food_bonus <= 0.0:
			continue
		for neighbor in neighbors(source.id):
			var edge := edge_of(source.id, neighbor)
			var target := cities[neighbor]
			if (
				edge == null
				or edge.max_manpower <= 0
				or target.is_dock
			):
				continue
			propagated_gold[target.id] = maxf(
				float(propagated_gold.get(target.id, 0.0)),
				source_gold_bonus * DEVELOPMENT_PROPAGATION_RATE
			)
			propagated_food[target.id] = maxf(
				float(propagated_food.get(target.id, 0.0)),
				source_food_bonus * DEVELOPMENT_PROPAGATION_RATE
			)
	var gold_weights := {}
	var food_weights := {}
	for city in land:
		city.development_gold_multiplier = maxf(
			float(direct_gold[city.id]),
			1.0 + float(propagated_gold.get(city.id, 0.0))
		)
		city.development_food_multiplier = maxf(
			float(direct_food[city.id]),
			1.0 + float(propagated_food.get(city.id, 0.0))
		)
		gold_weights[city.id] = (
			float(city.gold_per_month)
			* city.development_gold_multiplier
			* city.terrain_output_multiplier
		)
		food_weights[city.id] = (
			float(city.food_per_half_year)
			* city.development_food_multiplier
			* city.terrain_output_multiplier
		)
	_apportion_city_output(
		land,
		land.size() * TERRAIN_CITY_GOLD_TARGET_AVERAGE,
		gold_weights,
		false,
		TERRAIN_CITY_GOLD_OUTPUT_MIN,
		TERRAIN_CITY_GOLD_OUTPUT_MAX
	)
	_apportion_city_output(
		land,
		original_food_total,
		food_weights,
		true
	)


func _apportion_city_output(
	target_cities: Array[City],
	target_total: int,
	weights: Dictionary,
	food_output: bool,
	minimum_output: int = 0,
	maximum_output: int = -1
) -> void:
	var weight_total := 0.0
	for city in target_cities:
		weight_total += maxf(
			float(weights.get(city.id, 0.0)),
			0.0
		)
	if weight_total <= 0.0:
		return
	var values := {}
	var lower_bounds := {}
	var remainders: Array[Dictionary] = []
	var assigned := 0
	for city in target_cities:
		var exact := (
			float(target_total)
			* float(weights.get(city.id, 0.0))
			/ weight_total
		)
		var lower_bound := (
			int(round(
				float(FOOD_HUB_MIN_OUTPUT)
				* city.terrain_output_multiplier
			))
				if (
					food_output
					and city.is_food_hub
					and nations.size() == NATION_COUNT
				)
			else minimum_output
		)
		var value := maxi(int(floor(exact)), lower_bound)
		if maximum_output >= 0:
			value = mini(value, maximum_output)
		values[city.id] = value
		lower_bounds[city.id] = lower_bound
		assigned += value
		remainders.append({
			"city_id": city.id,
			"fraction": exact - floor(exact),
		})
	if assigned < target_total:
		remainders.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				if not is_equal_approx(
					float(a["fraction"]),
					float(b["fraction"])
				):
					return float(a["fraction"]) > float(b["fraction"])
				return int(a["city_id"]) < int(b["city_id"])
		)
		while assigned < target_total:
			var changed := false
			for entry in remainders:
				var city_id := int(entry["city_id"])
				if (
					maximum_output >= 0
					and int(values[city_id]) >= maximum_output
				):
					continue
				values[city_id] = int(values[city_id]) + 1
				assigned += 1
				changed = true
				if assigned >= target_total:
					break
			if not changed:
				break
	elif assigned > target_total:
		remainders.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				if not is_equal_approx(
					float(a["fraction"]),
					float(b["fraction"])
				):
					return float(a["fraction"]) < float(b["fraction"])
				return int(a["city_id"]) > int(b["city_id"])
		)
		while assigned > target_total:
			var changed := false
			for entry in remainders:
				var city_id := int(entry["city_id"])
				if int(values[city_id]) <= int(lower_bounds[city_id]):
					continue
				values[city_id] = int(values[city_id]) - 1
				assigned -= 1
				changed = true
				if assigned <= target_total:
					break
			if not changed:
				break
	assert(
		assigned == target_total,
		"城市产出目标与上下界不兼容：目标%d，实际%d"
			% [target_total, assigned]
	)
	for city in target_cities:
		if food_output:
			city.food_per_half_year = int(values[city.id])
		else:
			city.gold_per_month = int(values[city.id])


func _initialize_capitals_and_warehouses() -> void:
	var initial_food: Array[int] = []
	initial_food.resize(nations.size())
	initial_food.fill(0)
	for city in cities:
		initial_food[city.owner_nation] += city.food_storage
		city.food_storage = 0
		city.is_capital = false
		city.has_warehouse = false
	for nation in nations:
		var owned := land_cities_of(nation.id)
		var centroid := Vector2.ZERO
		for city in owned:
			centroid += city.map_position
		centroid /= float(maxi(owned.size(), 1))
		var capital_id := owned[0].id
		var best_distance := INF
		for city in owned:
			var distance := city.map_position.distance_squared_to(centroid)
			if distance < best_distance or (
					is_equal_approx(distance, best_distance)
					and EquivariantOrder.city_id_less(
						self,
						nation.id,
						city.id,
						capital_id
					)
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
		edge.kind = int(road.get("kind", Edge.Kind.LAND))
		edge.travel_time_multiplier = float(
			road.get("travel_time_multiplier", 1.0)
		)
		edge.supply_loss_multiplier = float(
			road.get("supply_loss_multiplier", 1.0)
		)
		edge.allows_holding = bool(
			road.get("allows_holding", true)
		)
		edge.max_height_difference = float(road["height_difference"])
		edge.max_manpower = int(road["max_manpower"])
		edges.append(edge)
		edge_lookup[_edge_key(lo, hi)] = edge
		(adjacency[lo] as Array[int]).append(hi)
		(adjacency[hi] as Array[int]).append(lo)
	for city_id in adjacency.keys():
		(adjacency[city_id] as Array[int]).sort()

func _initial_owner_components(
	nation_id: int
) -> Array[Array]:
	var result: Array[Array] = []
	var unseen := {}
	for city in cities:
		if city.owner_nation == nation_id:
			unseen[city.id] = true
	while not unseen.is_empty():
		var starts := unseen.keys()
		starts.sort()
		var start := int(starts[0])
		var component: Array[int] = []
		var queue: Array[int] = [start]
		unseen.erase(start)
		var head := 0
		while head < queue.size():
			var city_id := queue[head]
			head += 1
			component.append(city_id)
			for neighbor in neighbors(city_id):
				if not unseen.has(neighbor):
					continue
				var edge := edge_of(city_id, neighbor)
				if (
					edge == null
					or edge.max_manpower <= 0
					or cities[neighbor].owner_nation
						!= nation_id
				):
					continue
				unseen.erase(neighbor)
				queue.append(neighbor)
		component.sort()
		result.append(component)
	return result


func _initial_component_land_count(component: Array) -> int:
	var result := 0
	for city_value in component:
		if not cities[int(city_value)].is_dock:
			result += 1
	return result


## 几何初分只提供空间先验；最终归属必须服从合法道路/码头图。每轮保留
## 各国陆城最多的主体组件，其余飞地整体交给边界连接最多的邻国，直到稳定。
func _repair_initial_nation_connectivity() -> void:
	var guard := cities.size()
	while guard > 0:
		guard -= 1
		var changed := false
		for nation in nations:
			var components := _initial_owner_components(
				nation.id
			)
			if components.size() <= 1:
				continue
			components.sort_custom(
				func(a: Array, b: Array) -> bool:
					var land_a := (
						_initial_component_land_count(a)
					)
					var land_b := (
						_initial_component_land_count(b)
					)
					if land_a != land_b:
						return land_a > land_b
					if a.size() != b.size():
						return a.size() > b.size()
					return int(a[0]) < int(b[0])
			)
			for component_index in range(
				1,
				components.size()
			):
				var component: Array = components[
					component_index
				]
				var boundary_counts := {}
				for city_value in component:
					var city_id := int(city_value)
					for neighbor in neighbors(city_id):
						var edge := edge_of(
							city_id,
							neighbor
						)
						var neighbor_owner := (
							cities[
								neighbor
							].owner_nation
						)
						if (
							edge == null
							or edge.max_manpower <= 0
							or neighbor_owner < 0
							or neighbor_owner
								== nation.id
						):
							continue
						boundary_counts[
							neighbor_owner
						] = (
							int(boundary_counts.get(
								neighbor_owner,
								0
							))
							+ 1
						)
				assert(
					not boundary_counts.is_empty(),
					"初始飞地必须沿合法交通图连接到邻国"
				)
				var recipient := -1
				var best_count := -1
				var owner_ids := boundary_counts.keys()
				owner_ids.sort()
				for owner_value in owner_ids:
					var owner := int(owner_value)
					var count := int(
						boundary_counts[owner]
					)
					if count > best_count:
						best_count = count
						recipient = owner
				for city_value in component:
					cities[
						int(city_value)
					].owner_nation = recipient
				changed = true
		if not changed:
			break
	assert(guard > 0, "初始国家飞地修复必须收敛")
	for nation in nations:
		assert(
			_initial_owner_components(nation.id).size()
				== 1,
			"初始国%d领土必须经合法交通图连通"
				% nation.id
		)


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
	for nation in nations:
		var owned := cities_of(nation.id)
		owned.sort_custom(func(a: City, b: City) -> bool:
			return EquivariantOrder.city_less(
				self,
				nation.id,
				a,
				b
			)
		)
		var line_cities: Array[City] = []
		for city in owned:
			for neighbor in neighbors(city.id):
				if cities[neighbor].owner_nation == nation.id:
					continue
				line_cities.append(city)
				break
		# 网格世界是镜像测试夹具，保留每城一支填线军；正式地图按实际国界城市起步。
		if not uses_heightmap:
			line_cities = owned
		for city in line_cities:
			_initialize_army_attributes(create_army(
				nation.id,
				city.id,
				INITIAL_LIGHT_ARMY_SIZE,
				INITIAL_LIGHT_ARMY_SIZE
			))
		if owned.is_empty():
			continue
		var group := create_battle_group(nation.id)
		var group_city := nation.capital_city_id
		for _index in range(BattleGroup.MAX_LIGHT_ARMIES):
			var light := create_army(
				nation.id,
				group_city,
				INITIAL_LIGHT_ARMY_SIZE,
				INITIAL_LIGHT_ARMY_SIZE
			)
			_initialize_army_attributes(light)
			assign_army_to_battle_group(light, group.id)
		var heavy := create_army(
			nation.id,
			group_city,
			INITIAL_HEAVY_ARMY_SIZE,
			INITIAL_HEAVY_ARMY_SIZE
		)
		_initialize_army_attributes(heavy)
		assign_army_to_battle_group(heavy, group.id)


func _battle_group_structure_valid() -> bool:
	for nation in nations:
		for group in nation.battle_groups:
			var light_count := 0
			var heavy_count := 0
			for army in battle_group_members(nation.id, group.id):
				if army.max_size == INITIAL_LIGHT_ARMY_SIZE:
					light_count += 1
				elif army.max_size >= INITIAL_HEAVY_ARMY_SIZE:
					heavy_count += 1
			if (
				light_count > BattleGroup.MAX_LIGHT_ARMIES
				or heavy_count > BattleGroup.MAX_HEAVY_ARMIES
			):
				return false
	for army in armies:
		if (
			army.size > 0
			and army.max_size >= INITIAL_HEAVY_ARMY_SIZE
			and battle_group_by_id(
				army.owner_nation,
				army.battle_group_id
			) == null
		):
			return false
	return true


func _initialize_army_attributes(army: Army) -> void:
	assert(army != null, "初始军队生成不得突破国家军队上限")
	army.speed_factor = rng.randf_range(0.3, 0.9)
	army.attack = rng.randi_range(8, 15)
	army.defense = rng.randi_range(8, 15)


func create_battle_group(nation_id: int) -> BattleGroup:
	if nation_id < 0 or nation_id >= nations.size():
		return null
	var nation := nations[nation_id]
	var group := BattleGroup.new()
	group.id = nation.next_battle_group_id
	nation.next_battle_group_id += 1
	group.owner_nation = nation_id
	group.created_day = day
	nation.battle_groups.append(group)
	return group


func battle_group_by_id(
	nation_id: int,
	group_id: int
) -> BattleGroup:
	if nation_id < 0 or nation_id >= nations.size() or group_id < 0:
		return null
	for group in nations[nation_id].battle_groups:
		if group.id == group_id:
			return group
	return null


func battle_group_members(
	nation_id: int,
	group_id: int,
	alive_only: bool = true
) -> Array[Army]:
	var result: Array[Army] = []
	if battle_group_by_id(nation_id, group_id) == null:
		return result
	for army in armies:
		if (
			army.owner_nation == nation_id
			and army.battle_group_id == group_id
			and (not alive_only or army.size > 0)
		):
			result.append(army)
	return result


func assign_army_to_battle_group(
	army: Army,
	group_id: int
) -> bool:
	if (
		army == null
		or army.size <= 0
		or battle_group_by_id(
			army.owner_nation,
			group_id
		) == null
	):
		return false
	var light_count := 0
	var heavy_count := 0
	for member in battle_group_members(army.owner_nation, group_id):
		if member == army:
			continue
		if member.max_size == INITIAL_LIGHT_ARMY_SIZE:
			light_count += 1
		elif member.max_size >= INITIAL_HEAVY_ARMY_SIZE:
			heavy_count += 1
	if (
		army.max_size == INITIAL_LIGHT_ARMY_SIZE
		and light_count >= BattleGroup.MAX_LIGHT_ARMIES
	) or (
		army.max_size >= INITIAL_HEAVY_ARMY_SIZE
		and heavy_count >= BattleGroup.MAX_HEAVY_ARMIES
	):
		return false
	army.battle_group_id = group_id
	army.strategic_role = Army.StrategicRole.MAIN
	army.clear_line_assignment()
	return true


func create_army(
	nation_id: int,
	city_id: int,
	size: int,
	max_size: int = Army.DEFAULT_MAX_SIZE
) -> Army:
	if (
		nation_id < 0 or nation_id >= nations.size()
		or city_id < 0 or city_id >= cities.size()
		or cities[city_id].owner_nation != nation_id
		or size <= 0
		or max_size <= 0
		or active_army_count(nation_id)
			>= max_army_count(nation_id)
	):
		return null
	var army := Army.new()
	army.id = _next_army_id
	_next_army_id += 1
	army.owner_nation = nation_id
	army.max_size = max_size
	army.size = mini(size, max_size)
	army.max_morale = Army.max_morale_for_formation(max_size)
	army.morale = army.max_morale
	army.strategic_role = (
		Army.StrategicRole.MAIN
		if max_size >= INITIAL_HEAVY_ARMY_SIZE
		else Army.StrategicRole.LINE
	)
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	armies.append(army)
	return army


func active_army_count(nation_id: int) -> int:
	var count := 0
	for army in armies:
		if army.owner_nation == nation_id and army.size > 0:
			count += 1
	return count


func max_army_count(nation_id: int) -> int:
	return maxi(
		cities_of(nation_id).size()
			* ARMY_COUNT_LIMIT_PER_CITY,
		ARMY_COUNT_LIMIT_PER_CITY
	)


## 将一支静止军队按满编容量等分，兵力和满编总额严格守恒。
func split_army(
	army: Army,
	part_max_size: int
) -> Array[Army]:
	var result: Array[Army] = []
	if (
		army == null
		or not armies.has(army)
		or army.size <= 0
		or army.state != Army.State.IDLE
		or army.on_edge
		or part_max_size < Edge.MIN_MANPOWER
		or part_max_size >= army.max_size
		or army.max_size % part_max_size != 0
		or army.location_city < 0
		or army.location_city >= cities.size()
		or not has_military_access(
			army.owner_nation,
			cities[army.location_city].owner_nation
		)
	):
		return result
	var part_count := army.max_size / part_max_size
	if (
		army.size < part_count
		or active_army_count(army.owner_nation)
			+ part_count - 1
			> max_army_count(army.owner_nation)
	):
		return result
	var original_size := army.size
	var original_battle_group_id := army.battle_group_id
	var original_line_assignment_city := (
		army.line_assignment_city
	)
	var original_line_assignment_posture := (
		army.line_assignment_posture
	)
	var original_line_assignment_edge := (
		army.line_assignment_edge
	)
	var original_supply_debt := army.supply_debt
	var original_food_debt := army.supply_food_debt
	var original_morale_ratio := army.morale_ratio()
	var part_max_morale := Army.max_morale_for_formation(
		part_max_size
	)
	var base_size := original_size / part_count
	var remainder := original_size % part_count
	var available_group_light_slots := 0
	if original_battle_group_id >= 0:
		var existing_group_lights := 0
		for member in battle_group_members(
			army.owner_nation,
			original_battle_group_id
		):
			if (
				member != army
				and member.max_size == INITIAL_LIGHT_ARMY_SIZE
			):
				existing_group_lights += 1
		available_group_light_slots = maxi(
			BattleGroup.MAX_LIGHT_ARMIES
				- existing_group_lights,
			0
		)
	army.max_size = part_max_size
	army.max_morale = part_max_morale
	army.morale = original_morale_ratio * part_max_morale
	army.battle_group_id = (
		original_battle_group_id
		if available_group_light_slots > 0
		else -1
	)
	army.strategic_role = (
		Army.StrategicRole.MAIN
		if army.battle_group_id >= 0
		else Army.StrategicRole.LINE
	)
	army.size = base_size + (1 if remainder > 0 else 0)
	army.supply_debt = (
		original_supply_debt
		* float(army.size)
		/ float(original_size)
	)
	army.supply_food_debt = (
		original_food_debt
		* float(army.size)
		/ float(original_size)
	)
	result.append(army)
	for part_index in range(1, part_count):
		var child := Army.new()
		child.id = _next_army_id
		_next_army_id += 1
		child.owner_nation = army.owner_nation
		child.max_size = part_max_size
		child.max_morale = part_max_morale
		child.battle_group_id = (
			original_battle_group_id
			if part_index < available_group_light_slots
			else -1
		)
		child.strategic_role = (
			Army.StrategicRole.MAIN
			if child.battle_group_id >= 0
			else Army.StrategicRole.LINE
		)
		child.line_assignment_city = (
			original_line_assignment_city
		)
		child.line_assignment_posture = (
			original_line_assignment_posture
		)
		child.line_assignment_edge = (
			original_line_assignment_edge
		)
		child.size = (
			base_size
			+ (1 if part_index < remainder else 0)
		)
		child.speed_factor = army.speed_factor
		child.attack = army.attack
		child.defense = army.defense
		child.morale = original_morale_ratio * part_max_morale
		child.supply_ratio = army.supply_ratio
		child.starving = army.starving
		child.supply_debt = (
			original_supply_debt
			* float(child.size)
			/ float(original_size)
		)
		child.supply_food_debt = (
			original_food_debt
			* float(child.size)
			/ float(original_size)
		)
		child.location_city = army.location_city
		child.move_from = army.location_city
		child.state = Army.State.IDLE
		child.offensive_attack_multiplier = (
			army.offensive_attack_multiplier
		)
		child.offensive_bonus_until_day = (
			army.offensive_bonus_until_day
		)
		child.defensive_deployment_until_day = (
			army.defensive_deployment_until_day
		)
		child.defensive_blocked_edge_a = (
			army.defensive_blocked_edge_a
		)
		child.defensive_blocked_edge_b = (
			army.defensive_blocked_edge_b
		)
		armies.append(child)
		result.append(child)
	return result

# ------------------------------------------------------------------ 查询辅助

static func edge_key(a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return (lo << 32) | hi


func _edge_key(a: int, b: int) -> int:
	return edge_key(a, b)


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


## 共同防御联盟同时授予双向军事通行权；中立国不开放领土。
func has_military_access(traveler_nation: int, territory_owner: int) -> bool:
	return (
		traveler_nation == territory_owner
		or (
			traveler_nation >= 0
			and territory_owner >= 0
			and traveler_nation < nations.size()
			and territory_owner < nations.size()
			and is_allied(traveler_nation, territory_owner)
		)
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


func can_alliance_declare_war(
	nation_a: int,
	nation_b: int
) -> bool:
	if not can_declare_war(nation_a, nation_b):
		return false
	var attackers := alliance_bloc(nation_a)
	var defenders := alliance_bloc(nation_b)
	if attackers.is_empty() or defenders.is_empty():
		return false
	for attacker in attackers:
		for defender in defenders:
			if (
				attacker == defender
				or is_allied(attacker, defender)
				or (
					not is_enemy(attacker, defender)
					and (
						relation_between(attacker, defender)
							!= DiplomaticRelation.NEUTRAL
						or day < truce_until(attacker, defender)
					)
				)
			):
				return false
	return true


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


## 当前联盟图中 nation_id 所在的完整连通分量。联盟上限虽通常使其退化为二元组，
## 但按连通分量派生可避免外交层再维护一份易漂移的“战争集团成员”状态。
func alliance_bloc(
	nation_id: int,
	alive_only: bool = true
) -> Array[int]:
	var result: Array[int] = []
	if (
		nation_id < 0
		or nation_id >= nations.size()
		or (alive_only and not nations[nation_id].alive)
	):
		return result
	var seen := {nation_id: true}
	var queue: Array[int] = [nation_id]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		result.append(current)
		for other in nations:
			if (
				other.id == current
				or seen.has(other.id)
				or (alive_only and not other.alive)
				or not is_allied(current, other.id)
			):
				continue
			seen[other.id] = true
			queue.append(other.id)
	result.sort()
	return result


# ------------------------------------------------------------------ 宗藩关系
# 宗藩是一层挂在对外「联盟共同体」之上的有向元数据：宗主与藩王对外恒为 ALLIED，
# 故对外战争、威胁、防区等逻辑仍只依赖 is_enemy()/alliance_bloc()，无需理解藩王。
# 本区只维护「谁是谁的宗主」这一有向真源及其不变量，不涉及削藩/内战机制。

## 藩王的宗主 id；不是藩王返回 -1。
func overlord_of(nation_id: int) -> int:
	var record: Dictionary = suzerainty.get(nation_id, {})
	return int(record.get("overlord_id", -1)) if not record.is_empty() else -1


## 直接藩王 id 列表（不含更下级），按 id 升序，确定性。
func subjects_of(overlord_id: int) -> Array[int]:
	var result: Array[int] = []
	for subject_id in suzerainty:
		if int(suzerainty[subject_id].get("overlord_id", -1)) == overlord_id:
			result.append(int(subject_id))
	result.sort()
	return result


## 藩王关系记录副本；不是藩王返回空字典。
func suzerainty_record(subject_id: int) -> Dictionary:
	return (suzerainty.get(subject_id, {}) as Dictionary).duplicate()


func is_vassal(nation_id: int) -> bool:
	return suzerainty.has(nation_id)


func is_overlord(nation_id: int) -> bool:
	return not subjects_of(nation_id).is_empty()


## a 与 b 是否互为直接宗主-藩属。宗藩的 ALLIED 纽带是政治义务、非普通盟约，
## 不得被普通外交（退盟/结盟/宣战/议和）随意改动；各外交收集器据此跳过这类对。
func is_suzerainty_pair(nation_a: int, nation_b: int) -> bool:
	return overlord_of(nation_a) == nation_b or overlord_of(nation_b) == nation_a


## 藩王领土是否与本宗藩体系的任一敌国接壤（存在一条正容量边通往体系敌国的城）。
## 用于分封战争加成：接壤敌国的藩王须以自有军团守卫封地，
## 非接壤藩王只提高贡赋、不承担前线。判据只看实控归属与道路容量，确定性。
func vassal_borders_system_enemy(subject_id: int) -> bool:
	if not is_vassal(subject_id):
		return false
	for city in cities:
		if city.owner_nation != subject_id:
			continue
		for neighbor in neighbors(city.id):
			var edge := edge_of(city.id, neighbor)
			if edge == null or edge.max_manpower <= 0:
				continue
			var neighbor_owner := cities[neighbor].owner_nation
			if neighbor_owner >= 0 and is_enemy(subject_id, neighbor_owner):
				return true
	return false


## 藩王是否正处于与其宗主的削藩内战中。内战期间宗主↔藩王为 WAR（而非 ALLIED），
## 对外共同体因此自然解散（alliance_bloc 会把两者拆开）——攘外必先安内。
func is_in_civil_war(subject_id: int) -> bool:
	var record: Dictionary = suzerainty.get(subject_id, {})
	return not record.is_empty() and bool(record.get("civil_war", false))


## 发起削藩内战：把宗主↔藩王从 ALLIED 改为 WAR，并在记录上打内战标记。
## 反叛藩王随即退出共享粮仓、按其（含下级和平藩属）领土粮食产能占原粮池的比例
## 切分库存到自己新建的首都粮仓（自成一池），并在首都凭空动员一批「火星兵」满编
## 主战军团（数量 = ceil(0.1 × 反叛方陆城数)）作为起兵资本。
## 返回是否成功（须是既有宗藩对且当前非内战）。
func start_civil_war(subject_id: int) -> bool:
	if not suzerainty.has(subject_id) or is_in_civil_war(subject_id):
		return false
	var overlord_id := int(suzerainty[subject_id]["overlord_id"])
	# 1. 切分前先量取：反叛方子树（沿非内战边）与整个原粮池的粮食产能，用于按比例分粮。
	var holder_before := food_pool_holder(subject_id)
	var rebel_food_output := _food_pool_food_output(subject_id)
	var pool_food_output := _food_pool_food_output(holder_before)
	var pool_stock := _food_pool_stock(holder_before)
	# 2. 断开内战边（关系转 WAR、打标记）。此后 food_pool_holder(subject) 收敛到 subject 自身。
	suzerainty[subject_id]["civil_war"] = true
	suzerainty[subject_id]["last_centralization_day"] = day
	set_diplomatic_relation(subject_id, overlord_id, DiplomaticRelation.WAR)
	# 3. 反叛方自成一池：在其首都建独立粮仓，从原持有者粮仓按产能占比划入切分份额（守恒）。
	var rebel_share := _proportional_share(
		pool_stock, rebel_food_output, pool_food_output
	)
	_establish_rebel_food_pool(subject_id, holder_before, rebel_share)
	# 4. 起兵资本：反叛方首都凭空动员火星兵（满编主战军团）。
	_spawn_civil_war_uprising_armies(subject_id)
	return true


## 一个粮池（沿非内战宗藩边可达的成员集）领土陆城的半年粮食产能之和。
## 用作内战切分共享库存的守恒比例基数。
func _food_pool_food_output(holder_id: int) -> int:
	var total := 0
	for member_id in food_pool_members(holder_id):
		for city in land_cities_of(member_id):
			total += city.food_per_half_year
	return total


## 一个粮池的当前库存总量（持有者名下全部粮仓存量之和；藩属首都零库存不计）。
func _food_pool_stock(holder_id: int) -> int:
	var total := 0
	for warehouse in warehouse_cities_of(holder_id):
		total += warehouse.food_storage
	return total


## 反叛方脱离共享粮仓、自成一池：在其首都建独立粮仓，从原持有者粮仓扣除 share 并注入。
## 守恒：先从原持有者粮仓（按占比）扣，再存入反叛方首都，粮食总量不变。
func _establish_rebel_food_pool(
	rebel_id: int,
	former_holder_id: int,
	share: int
) -> void:
	if rebel_id < 0 or rebel_id >= nations.size():
		return
	var rebel := nations[rebel_id]
	var capital_id := rebel.capital_city_id
	if capital_id < 0 or capital_id >= cities.size():
		return
	# 反叛方首都升为独立粮仓（内战期它是自己粮池的持有者）。
	var capital := cities[capital_id]
	capital.has_warehouse = true
	if not rebel.warehouse_city_ids.has(capital_id):
		rebel.warehouse_city_ids = [capital_id] as Array[int]
	# 从原持有者共享粮仓按占比扣除，等额注入反叛方首都（守恒转移）。
	if share > 0 and former_holder_id >= 0 and former_holder_id < nations.size():
		_withdraw_food_from_warehouses(nations[former_holder_id], share)
		capital.food_storage += share
	refresh_derived()


## 削藩内战起兵：反叛方首都凭空动员 ceil(0.1 × 反叛方陆城数) 个满编主战军团（火星兵）。
## 每个军团为一支满编重军（INITIAL_HEAVY_ARMY_SIZE、MAIN 角色），独立成团。起兵是离散
## 政治事件，属性沿用 _initialize_army_attributes 的世界生成随机口径（确定性由 rng 序保证）。
func _spawn_civil_war_uprising_armies(rebel_id: int) -> void:
	if rebel_id < 0 or rebel_id >= nations.size():
		return
	var capital_id := nations[rebel_id].capital_city_id
	if capital_id < 0 or capital_id >= cities.size():
		return
	var land_count := land_cities_of(rebel_id).size()
	if land_count <= 0:
		return
	var uprising_count := int(ceil(0.1 * float(land_count)))
	for _index in range(uprising_count):
		var group := create_battle_group(rebel_id)
		if group == null:
			return
		var heavy := _spawn_uprising_army(rebel_id, capital_id)
		if heavy == null:
			# 军队数上限已满：撤掉空战团，停止动员（不留悬空战团破坏结构不变量）。
			nations[rebel_id].battle_groups.erase(group)
			return
		assign_army_to_battle_group(heavy, group.id)


## 凭空动员一支满编重军（绕过 create_army 的城市归属校验：火星兵可在被围/新夺首都起兵）。
## 突破 create_army 的国家军队数上限硬约束——起兵是剧情动员，不受常备军配额限制。
func _spawn_uprising_army(nation_id: int, city_id: int) -> Army:
	return _spawn_conjured_army(
		nation_id,
		city_id,
		INITIAL_HEAVY_ARMY_SIZE,
		Army.StrategicRole.MAIN
	)


## 凭空动员一支指定编制/角色的满编军队（不扣人力/金钱、不受军队数上限约束）。
## 用于分封赐军（LINE）与削藩起兵火星兵（MAIN）等离散政治动员事件的单一真源。
func _spawn_conjured_army(
	nation_id: int,
	city_id: int,
	formation_size: int,
	role: int
) -> Army:
	var army := Army.new()
	army.id = _next_army_id
	_next_army_id += 1
	army.owner_nation = nation_id
	army.max_size = formation_size
	army.size = formation_size
	army.max_morale = Army.max_morale_for_formation(formation_size)
	army.morale = army.max_morale
	army.strategic_role = role
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	army.speed_factor = rng.randf_range(0.3, 0.9)
	army.attack = rng.randi_range(8, 15)
	army.defense = rng.randi_range(8, 15)
	armies.append(army)
	return army


## 分封赐军：确保新藩王拥有至少「陆城数」支 LINE 填线军（不足则凭空补足）。
## 新模型下分封不迁移宗主驻军，故一般 existing=0、按城数全额赐军；仍做「计现有、补缺口」
## 以对任何既有藩王军队（如反复分封的边界情形）保持幂等、不超编。凭空补（不扣人力池）。
## 分封时只赐 LINE 守土军；藩王后续可用自身资源组建 MAIN 内线军团。
func _grant_vassal_line_armies(subject_id: int) -> void:
	if subject_id < 0 or subject_id >= nations.size():
		return
	var owned := land_cities_of(subject_id)
	if owned.is_empty():
		return
	var target := owned.size()
	# 统计藩王当前存活军队数（迁入驻军已归属藩王）；只补足到城市数，不叠加超编。
	var existing := 0
	for army in armies:
		if army.owner_nation == subject_id and army.size > 0:
			existing += 1
	var deficit := target - existing
	if deficit <= 0:
		return
	# 缺口按城序补：优先补到当前无本国驻军的城，让填线军铺开而非堆在首都（确定性城序）。
	var garrisoned := {}
	for army in armies:
		if (
			army.owner_nation == subject_id
			and army.size > 0
			and not army.on_edge
			and army.location_city >= 0
		):
			garrisoned[army.location_city] = true
	var granted := 0
	for city in owned:
		if granted >= deficit:
			break
		if garrisoned.has(city.id):
			continue
		_spawn_conjured_army(
			subject_id,
			city.id,
			INITIAL_LIGHT_ARMY_SIZE,
			Army.StrategicRole.LINE
		)
		granted += 1
	# 若无驻军空城已补完仍有缺口（城少军多的极端情形），余量补在首都。
	var capital_id := nations[subject_id].capital_city_id
	while granted < deficit and capital_id >= 0 and capital_id < cities.size():
		_spawn_conjured_army(
			subject_id,
			capital_id,
			INITIAL_LIGHT_ARMY_SIZE,
			Army.StrategicRole.LINE
		)
		granted += 1


## 结束削藩内战（不改变领土归属，仅复位关系）：宗主↔藩王恢复 ALLIED，清内战标记。
## 供藩王战败保留宗藩、或和平收场时调用；通吃吞并另由领土结算处理。
func end_civil_war(subject_id: int) -> bool:
	if not suzerainty.has(subject_id) or not is_in_civil_war(subject_id):
		return false
	var overlord_id := int(suzerainty[subject_id]["overlord_id"])
	suzerainty[subject_id]["civil_war"] = false
	set_diplomatic_relation(subject_id, overlord_id, DiplomaticRelation.ALLIED)
	# 内战结束（藩王战败保留宗藩）：反叛方重新并入共享粮仓——撤销其独立粮仓，
	# 剩余库存回流原持有者共享池，藩王首都复位为零库存中继节点。
	_merge_rebel_food_pool_back(subject_id)
	return true


## 内战和平收场时把反叛方独立粮仓并回共享池：库存回流新的粮池持有者，首都复位零库存中继。
func _merge_rebel_food_pool_back(subject_id: int) -> void:
	if subject_id < 0 or subject_id >= nations.size():
		return
	var subject := nations[subject_id]
	var capital_id := subject.capital_city_id
	if capital_id < 0 or capital_id >= cities.size():
		return
	var leftover := 0
	for warehouse in warehouse_cities_of(subject_id):
		leftover += warehouse.food_storage
		warehouse.food_storage = 0
		warehouse.has_warehouse = false
	subject.warehouse_city_ids = [] as Array[int]
	cities[capital_id].has_warehouse = false
	cities[capital_id].food_storage = 0
	# 复位后 food_pool_holder(subject) 收敛到宗主根；库存回流共享池（守恒）。
	if leftover > 0:
		deposit_food(subject_id, leftover)
	refresh_derived()


## 沿宗主链上溯到的最终宗主（自身不是藩王时返回自身）。含环保护。
func suzerainty_root(nation_id: int) -> int:
	var current := nation_id
	var guard := 0
	while suzerainty.has(current) and guard <= nations.size():
		current = int(suzerainty[current]["overlord_id"])
		guard += 1
	return current


## nation_id 所属宗藩体系的全部成员（含宗主与各级藩王），按 id 升序。
## 与 alliance_bloc 的区别：bloc 是对外军事共同体（对称 ALLIED 连通分量），
## 可能包含平等盟友；本方法只沿有向宗藩链聚合同一个宗主根下的成员。
func suzerainty_members(nation_id: int) -> Array[int]:
	var root := suzerainty_root(nation_id)
	var result: Array[int] = [root]
	var seen := {root: true}
	var cursor := 0
	while cursor < result.size():
		for subject_id in subjects_of(result[cursor]):
			if not seen.has(subject_id):
				seen[subject_id] = true
				result.append(subject_id)
		cursor += 1
	result.sort()
	return result


## 粮食共享池的持有者：沿「非内战」宗藩边上溯到的最顶端节点（遇到内战边即停，不跨越）。
## 语义：同一宗藩体系里所有和平成员共享持有者首都的唯一粮仓这一「共享粮仓」，藩王首都
## 只是零库存补给中继节点；削藩内战的反叛者与其宗主断开、自成一池（见 start_civil_war）。
## 独立国返回自身。含环保护。这是「共享粮仓」库存归属的单一真源。
func food_pool_holder(nation_id: int) -> int:
	var current := nation_id
	var guard := 0
	while (
		suzerainty.has(current)
		and not is_in_civil_war(current)
		and guard <= nations.size()
	):
		current = int(suzerainty[current]["overlord_id"])
		guard += 1
	return current


## holder 共享粮池的全部和平成员（holder + 其下沿非内战边可达的各级藩王），按 id 升序。
## 用于补给网络把成员首都注入为零损耗中继起点，以及内战切分时界定「反叛方 / 留守方」。
func food_pool_members(holder_id: int) -> Array[int]:
	var result: Array[int] = [holder_id]
	var seen := {holder_id: true}
	var cursor := 0
	while cursor < result.size():
		for subject_id in subjects_of(result[cursor]):
			# 内战边被切断：反叛藩王及其子树不属于宗主的共享池。
			if not seen.has(subject_id) and not is_in_civil_war(subject_id):
				seen[subject_id] = true
				result.append(subject_id)
		cursor += 1
	result.sort()
	return result


## holder 粮池里可作补给中继起点的藩王首都（不含 holder 自己首都，那是主源；不含被围首都）。
## 补给损耗场与网络缓存指纹共用此单一真源，保证「降损耗中继」与「缓存失效」判据一致。
func food_pool_relay_capitals(holder_id: int) -> Array[int]:
	var origins: Array[int] = []
	for member_id in food_pool_members(holder_id):
		if member_id == holder_id:
			continue
		var capital_id := nations[member_id].capital_city_id
		if (
			capital_id < 0
			or capital_id >= cities.size()
			or cities[capital_id].owner_nation != member_id
			or city_under_siege(capital_id)
		):
			continue
		origins.append(capital_id)
	origins.sort()
	return origins


## 宗藩结构不变量校验。任一破坏都表明分封/削藩逻辑有 bug，应在测试中断言。
func suzerainty_structure_valid() -> bool:
	for subject_value in suzerainty:
		var subject_id := int(subject_value)
		var record: Dictionary = suzerainty[subject_id]
		var overlord_id := int(record.get("overlord_id", -1))
		# 1. id 合法且宗主藩属互异。
		if (
			subject_id < 0
			or subject_id >= nations.size()
			or overlord_id < 0
			or overlord_id >= nations.size()
			or subject_id == overlord_id
		):
			return false
		# 2. 关系随内战态：内战中宗主↔藩王须为 WAR（共同体解散、攘外必先安内），
		#    非内战的宗藩对须恒为 ALLIED（对外共同体化的前提）。
		var expected := (
			DiplomaticRelation.WAR
			if bool(record.get("civil_war", false))
			else DiplomaticRelation.ALLIED
		)
		if relation_between(subject_id, overlord_id) != expected:
			return false
		# 3. 沿宗主链上溯必须在有限步内终止（无环、单一宗主）。
		var walker := overlord_id
		var guard := 0
		while suzerainty.has(walker):
			if walker == subject_id or guard > nations.size():
				return false
			walker = int(suzerainty[walker]["overlord_id"])
			guard += 1
	return true


## 清理死亡国家（无城）造成的悬空宗藩记录，保持不变量。每 tick 领土结算后调用。
## - 死亡藩王：直接移除其记录（它已不存在）。
## - 死亡宗主：其直接藩王上移一级（挂到宗主自己的宗主，无则升为独立主权），
##   宗藩链因此保持连续、无悬空、无环。
## 返回是否发生了任何清理（供调用方决定是否刷新缓存）。
func prune_dead_suzerainty() -> bool:
	var changed := false
	# 先处理死亡宗主：把它的直接藩王提升到它自己的上级。
	# 反复扫描直到稳定，兼容一次结算中多级宗主同时消亡。
	var progressing := true
	while progressing:
		progressing = false
		for subject_value in suzerainty.keys():
			var subject_id := int(subject_value)
			var overlord_id := int(suzerainty[subject_id]["overlord_id"])
			var overlord_dead := (
				overlord_id < 0
				or overlord_id >= nations.size()
				or not nations[overlord_id].alive
			)
			if not overlord_dead:
				continue
			# 宗主已死：藩王上移到宗主的宗主（祖父），无则脱离宗藩成为独立主权。
			var grand := overlord_of(overlord_id)
			if grand >= 0 and grand != subject_id and nations[grand].alive:
				suzerainty[subject_id]["overlord_id"] = grand
				# 宗主死于内战则内战随之终结；继承为新宗主的藩属须对外 ALLIED。
				suzerainty[subject_id]["civil_war"] = false
				set_diplomatic_relation(subject_id, grand, DiplomaticRelation.ALLIED)
			else:
				suzerainty.erase(subject_id)
			changed = true
			progressing = true
	# 再移除死亡藩王自身的记录。
	for subject_value in suzerainty.keys():
		var subject_id := int(subject_value)
		if (
			subject_id < 0
			or subject_id >= nations.size()
			or not nations[subject_id].alive
		):
			suzerainty.erase(subject_id)
			changed = true
	return changed


## 分封：宗主 overlord_id 将 city_ids 划出，新建一个完整藩王 Nation。
## 长期主义切分：增量 A 只转移「领土 + 对外关系 + 派生资源」，军队不迁移
## （藩王首版无常备军，军队迁移涉及战团结构不变量，留待增量 B 专门处理）。
## 资源按迁出区在宗主总产能中的动态占比划转，全局守恒、无硬编码常量。
## 返回新藩王 id；输入非法（空区、含宗主首都、跨国、道路不连续保留给增量 B）
## 时返回 -1，不产生任何副作用。
func enfeoff(
	overlord_id: int,
	city_ids: Array[int],
	tribute_rate: float = DEFAULT_TRIBUTE_RATE
) -> int:
	city_ids = enfeoff_region_closure(
		overlord_id,
		city_ids
	)
	if not _can_enfeoff(overlord_id, city_ids):
		return -1
	var overlord := nations[overlord_id]

	# 1. 按产能占比确定划转份额（迁出区 / 宗主全域），保证资源守恒。
	#    人力、金钱按各自产能占比划转；粮食不划转（归共享粮仓，见下）。
	var overlord_manpower_output := 0
	var overlord_gold_output := 0
	for city in land_cities_of(overlord_id):
		overlord_manpower_output += city.manpower_per_month
		overlord_gold_output += city.gold_per_month
	var moved_manpower_output := 0
	var moved_gold_output := 0
	for city_id in city_ids:
		moved_manpower_output += cities[city_id].manpower_per_month
		moved_gold_output += cities[city_id].gold_per_month
	var granted_manpower := _proportional_share(
		overlord.manpower_pool, moved_manpower_output, overlord_manpower_output
	)
	var granted_gold := _proportional_share(
		overlord.treasury_gold, moved_gold_output, overlord_gold_output
	)
	# 粮食归「共享粮仓」：分封不划走粮食库存，全体系粮食继续留在宗主根粮仓。
	# 藩王首都只作零库存补给中继节点（见 _establish_vassal_capital），不切分库存。

	# 2. 建新藩王 Nation（完整实体，色调随宗主派生以体现同一政治共同体）。
	var subject := Nation.new()
	subject.id = nations.size()
	subject.color = _derive_vassal_color(overlord.color, subject.id)
	subject.alive = true
	subject.political_system = overlord.political_system
	subject.ai_aggression = overlord.ai_aggression
	nations.append(subject)

	# 3. 迁移城市实控与法理归属；宗主与藩王间同色系，法理即刻归藩王。
	for city_id in city_ids:
		var city := cities[city_id]
		city.owner_nation = subject.id
		recognized_city_owners[city_id] = subject.id
	ownership_revision += 1

	# 3.5 分封不把宗主驻军（尤其 MAIN 战团）转隶藩王：新藩王先获得第 5.5 步赐予的
	#     LINE 守土军，后续再用自身资源组建受封地防区约束的 MAIN 内线军团；
	#     留在封地内的宗主军队因宗藩 ALLIED 通行权不会被困，交宗主 AI 下个 tick 自然调度。

	# 4. 划转人力与金钱（守恒：从宗主池扣除、注入藩王池）。
	overlord.manpower_pool -= granted_manpower
	subject.manpower_pool = granted_manpower
	overlord.treasury_gold -= granted_gold
	subject.treasury_gold = granted_gold

	# 5. 选藩王首都作为「共享粮仓」的补给中继节点（零库存）；封地城市自带的存粮
	#    回流宗主根粮仓（共享池守恒，不凭空蒸发）。
	_establish_vassal_capital(subject, overlord_id)

	# 5.5 赐军：确保藩王至少拥有「陆城数」支 LINE 填线军（含迁入驻军，缺口凭空补足），
	#     解决「分封藩王常无军队」；MAIN 不凭空赐予，由藩王后续按经济能力自行组建。
	_grant_vassal_line_armies(subject.id)

	# 6. 外交：藩王继承宗主对每个第三方的关系，并与宗主结盟。
	#    这样 alliance_bloc 天然把宗藩聚为一体，对外 is_enemy 自动正确，
	#    且不会因缺省 key 让新藩王与未建交国凭空开战（relation_between 缺省=WAR）。
	_inherit_overlord_diplomacy(overlord_id, subject.id)

	# 7. 写宗藩关系 SSoT。
	suzerainty[subject.id] = {
		"overlord_id": overlord_id,
		"tribute_rate": clampf(tribute_rate, 0.0, 1.0),
		"created_day": day,
		"last_centralization_day": -1,
		"civil_war": false,
	}

	refresh_derived()
	assert(
		suzerainty_structure_valid(),
		"分封后宗藩结构不变量必须成立"
	)
	assert(
		_battle_group_structure_valid(),
		"分封迁移军队后战团结构不变量必须成立"
	)
	return subject.id


## 把 absorbed 国的全部领土、军队、战团、资源并入 absorber 国。通用兼并原语，
## 同时服务于「和平撤藩」（宗主吸收藩王）与「削藩内战通吃」（胜者吸收败者）。
## absorbed 随后成为无城的死国（alive=false）。不处理宗藩记录，调用方负责。
func annex_nation(absorber: int, absorbed: int) -> void:
	if (
		absorber < 0 or absorber >= nations.size()
		or absorbed < 0 or absorbed >= nations.size()
		or absorber == absorbed
	):
		return
	# 1. 领土：城市实控与法理归属全部转给 absorber，清 absorbed 的首都/粮仓标记。
	#    粮仓存粮先累加，稍后并入 absorber 首都粮仓（守恒）。
	var absorbed_food := 0
	for city in cities:
		if city.owner_nation != absorbed:
			continue
		if city.has_warehouse:
			absorbed_food += city.food_storage
		city.food_storage = 0
		city.is_capital = false
		city.has_warehouse = false
		city.owner_nation = absorber
		recognized_city_owners[city.id] = absorber
	ownership_revision += 1
	# 2. 军队与战团：整体改属 absorber。战团 id 重新分配到 absorber 的 id 空间。
	for group in nations[absorbed].battle_groups:
		var members := battle_group_members(absorbed, group.id)
		var new_group_id := nations[absorber].next_battle_group_id
		nations[absorber].next_battle_group_id += 1
		group.id = new_group_id
		group.owner_nation = absorber
		nations[absorber].battle_groups.append(group)
		for member in members:
			member.owner_nation = absorber
			member.battle_group_id = new_group_id
	nations[absorbed].battle_groups.clear()
	for army in armies:
		if army.owner_nation == absorbed and army.size > 0:
			army.owner_nation = absorber
			if army.battle_group_id < 0:
				army.clear_line_assignment()
	# 3. 资源：人力/金钱并入；粮食并入 absorber 首都粮仓。
	nations[absorber].manpower_pool += nations[absorbed].manpower_pool
	nations[absorbed].manpower_pool = 0
	nations[absorber].treasury_gold += nations[absorbed].treasury_gold
	nations[absorbed].treasury_gold = 0
	var absorber_capital := nations[absorber].capital_city_id
	if absorbed_food > 0 and absorber_capital >= 0 and absorber_capital < cities.size():
		cities[absorber_capital].food_storage += absorbed_food
	# 4. absorbed 成为无城死国。其宗藩记录由调用方按语义处理。
	nations[absorbed].capital_city_id = -1
	nations[absorbed].warehouse_city_ids = [] as Array[int]
	nations[absorbed].alive = false
	refresh_derived()


## 和平撤藩：宗主直接吸收藩王全境，宗藩记录移除。返回是否成功。
## 用于藩王面对削藩选择不反抗（军力悬殊）时的和平收场。
func revoke_vassal(subject_id: int) -> bool:
	if not suzerainty.has(subject_id):
		return false
	var overlord_id := int(suzerainty[subject_id]["overlord_id"])
	if overlord_id < 0 or overlord_id >= nations.size():
		return false
	# 先解除内战态关系（若在内战中），避免吸收后残留 WAR 关系。
	suzerainty.erase(subject_id)
	set_diplomatic_relation(subject_id, overlord_id, DiplomaticRelation.ALLIED)
	annex_nation(overlord_id, subject_id)
	# 被撤藩者若有下级藩王，其记录此刻悬空（指向已死国），立即修复上移。
	prune_dead_suzerainty()
	assert(
		suzerainty_structure_valid(),
		"撤藩后宗藩结构不变量必须成立"
	)
	assert(
		_battle_group_structure_valid(),
		"撤藩合并军队后战团结构不变量必须成立"
	)
	return true


## 分封区域闭包：拟分封区域从宗主直辖领土移除后，所有无法再沿正容量道路连回
## 宗主首都的直辖飞地一并纳入封地。闭包不改变合法输入的城市，只补齐被切断部分。
func enfeoff_region_closure(
	overlord_id: int,
	city_ids: Array[int]
) -> Array[int]:
	if (
		overlord_id < 0
		or overlord_id >= nations.size()
		or not nations[overlord_id].alive
		or city_ids.is_empty()
	):
		return [] as Array[int]
	var capital_id := nations[overlord_id].capital_city_id
	if (
		capital_id < 0
		or capital_id >= cities.size()
		or cities[capital_id].owner_nation != overlord_id
	):
		return [] as Array[int]
	var region := {}
	for city_id in city_ids:
		if (
			city_id < 0
			or city_id >= cities.size()
			or region.has(city_id)
			or city_id == capital_id
			or cities[city_id].owner_nation != overlord_id
		):
			return [] as Array[int]
		region[city_id] = true
	var reachable := {capital_id: true}
	var queue: Array[int] = [capital_id]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor in neighbors(current):
			var edge := edge_of(current, neighbor)
			if (
				reachable.has(neighbor)
				or region.has(neighbor)
				or cities[neighbor].owner_nation
					!= overlord_id
				or edge == null
				or edge.max_manpower <= 0
			):
				continue
			reachable[neighbor] = true
			queue.append(neighbor)
	for city in cities:
		if (
			city.owner_nation == overlord_id
			and not reachable.has(city.id)
		):
			region[city.id] = true
	var result: Array[int] = []
	for city_id_value in region:
		result.append(int(city_id_value))
	result.sort()
	return result


## 分封合法性：宗主有效存活、区域非空且全部属于宗主、不含宗主首都、
## 不得清空宗主陆地领土；传入区域必须已经包含其造成的全部直辖飞地。
func _can_enfeoff(overlord_id: int, city_ids: Array[int]) -> bool:
	if (
		overlord_id < 0
		or overlord_id >= nations.size()
		or not nations[overlord_id].alive
		or city_ids.is_empty()
	):
		return false
	var seen := {}
	for city_id in city_ids:
		if (
			city_id < 0
			or city_id >= cities.size()
			or seen.has(city_id)
			or cities[city_id].owner_nation != overlord_id
			or cities[city_id].is_capital
		):
			return false
		seen[city_id] = true
	var remaining_land := 0
	for city in land_cities_of(overlord_id):
		if not seen.has(city.id):
			remaining_land += 1
	if remaining_land <= 0:
		return false
	var closure := enfeoff_region_closure(
		overlord_id,
		city_ids
	)
	if closure.size() != seen.size():
		return false
	return true


## 按产能占比从一个整数资源池中切出应划转的整数份额（floor，保证不超发）。
## share 分母为 0 时返回 0。三种同质资源（人力/金钱/粮食）共用此逻辑。
func _proportional_share(pool: int, moved_output: int, total_output: int) -> int:
	if total_output <= 0 or pool <= 0 or moved_output <= 0:
		return 0
	var ratio := float(moved_output) / float(total_output)
	return mini(pool, int(floor(float(pool) * ratio)))


## 从宗主全部粮仓按库存占比扣除 amount 单位粮食（守恒地把粮食划给藩王）。
## 当前每国仅首都一个粮仓；按占比分摊为未来多粮仓保留正确性。
func _withdraw_food_from_warehouses(overlord: Nation, amount: int) -> void:
	if amount <= 0:
		return
	var warehouses := warehouse_cities_of(overlord.id)
	var total := 0
	for warehouse in warehouses:
		total += warehouse.food_storage
	if total <= 0:
		return
	var remaining := mini(amount, total)
	for i in range(warehouses.size()):
		if remaining <= 0:
			break
		var warehouse := warehouses[i]
		var take := (
			remaining
			if i == warehouses.size() - 1
			else mini(
				warehouse.food_storage,
				int(floor(float(amount) * float(warehouse.food_storage) / float(total)))
			)
		)
		take = mini(take, warehouse.food_storage)
		warehouse.food_storage -= take
		remaining -= take
	# granary_food 是派生量，由 refresh_derived 统一重算，此处不手改。


## 藩王色调从宗主派生：色相小幅偏移、降低明度/饱和度，体现「同一政治共同体、
## 内部多个实体」。id 仅参与小幅确定性微调，避免多个藩王完全同色。
func _derive_vassal_color(overlord_color: Color, subject_id: int) -> Color:
	var subject_hue_variance := fposmod(
		float(subject_id) * 1.61803398875,
		VASSAL_COLOR_SUBJECT_HUE_VARIANCE_DEGREES
	)
	var h := fposmod(
		overlord_color.h
			+ (VASSAL_COLOR_HUE_OFFSET_DEGREES + subject_hue_variance) / 360.0,
		1.0
	)
	var s := clampf(
		overlord_color.s - VASSAL_COLOR_SATURATION_OFFSET,
		0.0,
		1.0
	)
	var v := clampf(
		overlord_color.v - VASSAL_COLOR_VALUE_OFFSET,
		0.0,
		1.0
	)
	return Color.from_hsv(h, s, v)


## 为藩王选定首都作为「共享粮仓」的补给中继节点：首都本身零库存、不建独立粮仓，
## 封地城市自带的存粮全部回流宗主根粮仓（共享池守恒）。复用宗主首都选取的
## 「领土重心 + EquivariantOrder 决定性打破平局」规则。overlord_id 是回流粮食的接收方。
func _establish_vassal_capital(subject: Nation, overlord_id: int) -> void:
	var owned := land_cities_of(subject.id)
	if owned.is_empty():
		return
	var reclaimed_food := 0
	for city in owned:
		reclaimed_food += city.food_storage
		city.food_storage = 0
		city.is_capital = false
		city.has_warehouse = false
	var centroid := Vector2.ZERO
	for city in owned:
		centroid += city.map_position
	centroid /= float(owned.size())
	var capital_id := owned[0].id
	var best_distance := INF
	for city in owned:
		var distance := city.map_position.distance_squared_to(centroid)
		if distance < best_distance or (
			is_equal_approx(distance, best_distance)
			and EquivariantOrder.city_id_less(self, subject.id, city.id, capital_id)
		):
			best_distance = distance
			capital_id = city.id
	subject.capital_city_id = capital_id
	# 藩王首都是补给中继节点，不是独立粮仓：warehouse_city_ids 保持空、has_warehouse=false。
	subject.warehouse_city_ids = [] as Array[int]
	var capital := cities[capital_id]
	capital.is_capital = true
	capital.has_warehouse = false
	capital.food_storage = 0
	# 封地存粮回流宗主共享池（deposit_food 会重定向到 food_pool_holder 首都）。
	if reclaimed_food > 0 and overlord_id >= 0 and overlord_id < nations.size():
		deposit_food(overlord_id, reclaimed_food)


## 军队是否静止驻扎在 nation_id 的领土内（可安全整体转隶）。
## 只认已停在城节点且处于静止态的军队；行军/战斗/边上驻防/撤退一律不迁移，
## 以免破坏 battle、边通行占用与撤退路线的连续性。
func _army_stationed_in_nation(army: Army, nation_id: int) -> bool:
	if army.on_edge or army.state not in [Army.State.IDLE, Army.State.RECOVERING]:
		return false
	var node := army.current_city_node()
	return (
		node >= 0
		and node < cities.size()
		and cities[node].owner_nation == nation_id
	)


## 让藩王继承宗主对每一个第三方国家的对外关系，并与宗主结盟。
func _inherit_overlord_diplomacy(overlord_id: int, subject_id: int) -> void:
	for third in nations:
		if third.id == subject_id or third.id == overlord_id:
			continue
		var inherited := relation_between(overlord_id, third.id)
		set_diplomatic_relation(subject_id, third.id, inherited)
	set_diplomatic_relation(
		subject_id,
		overlord_id,
		DiplomaticRelation.ALLIED
	)


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
	result.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(
			self,
			city_owner,
			a,
			b,
			city_id
		)
	)
	return result


func armies_available_to_defend_city(
	city_id: int
) -> Array[Army]:
	## 返回物理停留在城节点、可被攻城入口征召的本国军队。
	## 容量等待中的 MOVING/RETREATING 尚未上边，不能因任务状态而从战场消失。
	var result: Array[Army] = []
	var city_owner := cities[city_id].owner_nation
	for army in armies:
		if (
			army.size <= 0
			or army.owner_nation != city_owner
			or not army.is_at_city_node(city_id)
		):
			continue
		if army.state == Army.State.FIGHTING:
			var active_battle := battle_by_id(
				army.battle_id
			)
			if (
				active_battle != null
				and not active_battle.finished
				and active_battle.kind == Battle.Kind.SIEGE
				and active_battle.city != null
				and active_battle.city.id == city_id
				and active_battle.has_army(army)
			):
				continue
		result.append(army)
	result.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(
			self,
			city_owner,
			a,
			b,
			city_id
		)
	)
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


## 一次遍历 battles（O(B)）收集全部被围城 id 集合。供每 tick 对多城/多粮仓
## 反复判被围的结算路径共享，替代逐次 city_under_siege 的 O(城×B) 退化。
func besieged_city_ids() -> Dictionary:
	var result := {}
	for b in battles:
		if not b.finished and b.kind == Battle.Kind.SIEGE and b.city != null:
			result[b.city.id] = true
	return result


func recognized_owner_of(city_id: int) -> int:
	if city_id < 0 or city_id >= recognized_city_owners.size():
		return -1
	return recognized_city_owners[city_id]


## 双边和平确认交战双方及其占领归属盟友取得的实际控制区。
func recognize_occupied_territory(
	nation_a: int,
	nation_b: int
) -> Array[int]:
	var transferred: Array[int] = []
	for city in cities:
		var recognized_owner := recognized_owner_of(city.id)
		if city.owner_nation == recognized_owner:
			continue
		var occupying_side := -1
		if city.occupation_sponsor_nation in [
			nation_a,
			nation_b,
		]:
			occupying_side = city.occupation_sponsor_nation
		elif (
			city.owner_nation == nation_a
			or is_allied(city.owner_nation, nation_a)
		):
			occupying_side = nation_a
		elif (
			city.owner_nation == nation_b
			or is_allied(city.owner_nation, nation_b)
		):
			occupying_side = nation_b
		var recognized_side := -1
		if recognized_owner == nation_a:
			recognized_side = nation_a
		elif recognized_owner == nation_b:
			recognized_side = nation_b
		if (
			occupying_side < 0
			or recognized_side < 0
			or occupying_side == recognized_side
		):
			continue
		recognized_city_owners[city.id] = city.owner_nation
		city.occupation_sponsor_nation = -1
		transferred.append(city.id)
	if not transferred.is_empty():
		ownership_revision += 1
	return transferred


## 联盟整体议和确认两个集团之间的全部实际占领。实际控制者保留自己的占领成果，
## 不把盟军占领地错误归给发起议和的代表国。
func recognize_coalition_occupied_territory(
	bloc_a: Array[int],
	bloc_b: Array[int]
) -> Array[int]:
	var side_a := {}
	var side_b := {}
	for nation_id in bloc_a:
		side_a[nation_id] = true
	for nation_id in bloc_b:
		side_b[nation_id] = true
	var transferred: Array[int] = []
	for city in cities:
		var recognized_owner := recognized_owner_of(city.id)
		if city.owner_nation == recognized_owner:
			continue
		var opposing_sides := (
			(side_a.has(city.owner_nation) and side_b.has(recognized_owner))
			or (side_b.has(city.owner_nation) and side_a.has(recognized_owner))
		)
		if not opposing_sides:
			continue
		recognized_city_owners[city.id] = city.owner_nation
		city.occupation_sponsor_nation = -1
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


func land_cities() -> Array[City]:
	var result: Array[City] = []
	for city in cities:
		if not city.is_dock:
			result.append(city)
	return result


func land_cities_of(nation_id: int) -> Array[City]:
	var result: Array[City] = []
	for city in cities:
		if city.owner_nation == nation_id and not city.is_dock:
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
	result.sort_custom(func(a: City, b: City) -> bool:
		return EquivariantOrder.city_less(
			self,
			nation_id,
			a,
			b
		)
	)
	return result


## 将粮食汇入「共享粮仓」：藩王的粮食产出重定向到其宗藩体系的粮池持有者
## （food_pool_holder）首都粮仓，藩王首都不再持有独立库存（它只是补给中继节点）。
## 独立国 / 内战反叛方 holder 即自身，行为与旧版一致。若持有者首都暂不可用，回退到其
## 第一个有效粮仓。这是「一个宗主国内所有藩属共享粮仓」在库存写入侧的单一真源。
func deposit_food(nation_id: int, amount: int) -> bool:
	if amount <= 0 or nation_id < 0 or nation_id >= nations.size():
		return false
	var holder_id := food_pool_holder(nation_id)
	var nation := nations[holder_id]
	var target: City = null
	if nation.capital_city_id >= 0 and nation.capital_city_id < cities.size():
		var capital := cities[nation.capital_city_id]
		if capital.owner_nation == holder_id and capital.has_warehouse:
			target = capital
	if target == null:
		var warehouses := warehouse_cities_of(holder_id)
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


## 首都失守后迁都：优先落在本国「最大连通领土分量」内，分量内再取工事最强者
## （同工事按势力局部物理序）。选最大分量而非全局最强单城，可避免把主体国土误
## 判为飞地——投降割地后国土可能碎成多块，迁都到最大块才能让其余飞地被正确放弃。
func relocate_capital(nation_id: int) -> int:
	if nation_id < 0 or nation_id >= nations.size():
		return -1
	var candidates := cities_of(nation_id)
	if candidates.is_empty():
		nations[nation_id].capital_city_id = -1
		return -1
	var best_component := _largest_owned_component(nation_id, candidates)
	best_component.sort_custom(func(a: City, b: City) -> bool:
		if a.fort_strength != b.fort_strength:
			return a.fort_strength > b.fort_strength
		return EquivariantOrder.city_less(
			self,
			nation_id,
			a,
			b
		)
	)
	var capital := best_component[0]
	var nation := nations[nation_id]
	nation.capital_city_id = capital.id
	if not nation.warehouse_city_ids.has(capital.id):
		nation.warehouse_city_ids.append(capital.id)
	capital.is_capital = true
	capital.has_warehouse = true
	return capital.id


## 返回本国按道路连通划分后的「最大连通分量」（城市列表）。同大小时按分量代表城
## 的势力局部物理序取更小者，保证确定性。仅用本国实控城 + 可通行边构成子图。
func _largest_owned_component(
	nation_id: int,
	owned_cities: Array[City]
) -> Array[City]:
	var owned := {}
	for city in owned_cities:
		owned[city.id] = true
	var visited := {}
	var best: Array[City] = []
	var best_rep := -1
	for city in owned_cities:
		if visited.has(city.id):
			continue
		var component: Array[City] = []
		var rep := city.id
		var queue: Array[int] = [city.id]
		visited[city.id] = true
		var cursor := 0
		while cursor < queue.size():
			var cid := queue[cursor]
			cursor += 1
			component.append(cities[cid])
			rep = mini(rep, cid)
			for neighbor in neighbors(cid):
				if visited.has(neighbor) or not owned.has(neighbor):
					continue
				var edge := edge_of(cid, neighbor)
				if edge == null or edge.max_manpower <= 0:
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		if (
			component.size() > best.size()
			or (component.size() == best.size() and (best_rep < 0 or rep < best_rep))
		):
			best = component
			best_rep = rep
	return best


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
