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
const SMALL_NATION_SURVIVAL_MAX_CITIES: int = 4
const SMALL_NATION_MOBILE_RESERVE_ARMIES: int = 1
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
const MAP_SOURCE_MANIFEST := MapSource.DEFAULT_MANIFEST
const DEFAULT_CITY_MASK_PATH := (
	"res://assets/terrain/default_china_city_mask.png"
)


static func terrain_map_path() -> String:
	return MapSource.texture_path(MAP_SOURCE_MANIFEST)

enum DiplomaticRelation {
	NEUTRAL,
	WAR,
	ALLIED,
}

## 城市实控变化时，原城内库存的结算策略。所有运行期领土业务都必须显式
## 选择一种去向；事务会在提交前确认对应的最终粮池确实可以入账。
enum TerritoryStockDisposition {
	RETURN_TO_OLD_POOL,
	MOVE_TO_NEW_POOL,
	CAPTURE_SPOILS,
	DESTROY,
}

const TERRITORY_CAPTURE_SPOILS_RATE: float = 0.30

## 分封默认贡赋率。
const DEFAULT_TRIBUTE_RATE: float = 0.25
const VASSAL_COLOR_HUE_OFFSET_DEGREES: float = 10.0
const VASSAL_COLOR_SATURATION_OFFSET: float = 0.10
const VASSAL_COLOR_VALUE_OFFSET: float = 0.05
const VASSAL_COLOR_SUBJECT_HUE_VARIANCE_DEGREES: float = 4.0
const NATION_COLOR_SATURATION_MIN: float = 0.74
const NATION_COLOR_SATURATION_MAX: float = 0.84
const NATION_COLOR_VALUE_MIN: float = 0.34
const NATION_COLOR_VALUE_MAX: float = 0.46
## Hard-coded HSV palette. All procedural colors reuse the same bounded S/V
## bands; only hue changes for additional nations.
const NATION_PALETTE_HUES := [0.000, 0.610, 0.350, 0.140]
const NATION_PALETTE_SATURATIONS := [0.82, 0.78, 0.76, 0.81]
const NATION_PALETTE_VALUES := [0.44, 0.41, 0.37, 0.46]


static func army_monthly_upkeep(troops: int) -> int:
	if troops <= 0:
		return 0
	return int(ceil(
		float(troops) / float(WAR_GOLD_TROOPS_PER_UNIT)
	))


## Shared HSV contract for every faction-owned visual. Hue and alpha survive;
## saturation/value stay inside the requested non-neon palette rectangle.
static func normalize_nation_color(color: Color) -> Color:
	return Color.from_hsv(
		color.h,
		clampf(
			color.s,
			NATION_COLOR_SATURATION_MIN,
			NATION_COLOR_SATURATION_MAX
		),
		clampf(
			color.v,
			NATION_COLOR_VALUE_MIN,
			NATION_COLOR_VALUE_MAX
		),
		color.a
	)


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
var world_seed: int = 12345                 ## 命名/君主等独立确定性域的稳定种子
## 正式世界/地图模板启用确定性君主；兼容网格夹具保持中性，且其运行时
## 新建藩王/叛军沿用同一模式。不能借 uses_heightmap 判断，因为旧测试会单独切换它。
var _random_ruler_profiles_enabled: bool = true
var _next_army_id: int = 0
var _next_battle_id: int = 0
var ownership_revision: int = 0             ## 城市易主版本号，供战略地图缓存失效
var diplomacy_revision: int = 0             ## 外交关系版本号，供 AI 战略缓存失效
var fortification_revision: int = 0         ## 当前城防变化版本号，供 AI 战略缓存失效
var road_network_revision: int = 0          ## 运行时道路通行性/容量重算版本号
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
var city_generation_mask_path: String = ""
var city_density_settings: Dictionary = {}
## 每个有效栅格像素保存所属 city_id；-1 表示地图轮廓外。
var province_map_size: Vector2i = Vector2i.ZERO
var province_ids: PackedInt32Array = PackedInt32Array()
## 正式地图河流折线（归一化地图坐标），仅用于渲染；通行真源仍是 Edge。
var river_paths: Array[PackedVector2Array] = []
## 法理归属用于区分“本国底色”和“占领国斜线”；和平协议会确认实际控制区。
var recognized_city_owners: PackedInt32Array = PackedInt32Array()
## 短时战略箭头事件：{start_day,end_day,nation_id,target_city,origin_cities,wave}。
var campaign_visual_events: Array[Dictionary] = []
## 地方叛乱真源：rebel_nation_id -> {parent_id,started_day,core_city_ids,
## recognized,active,reason}。削藩内战继续使用 suzerainty.civil_war。
var rebellions: Dictionary = {}
## 当月派生贸易路线；静态道路仍由 edges 持有。
var trade_routes: Array[Dictionary] = []
var trade_revision: int = 0
var naming_revision: int = 0

## 结束态
var winner: int = -1                        ## -1 表示未结束

# ------------------------------------------------------------------ 生成

func generate_world(
	world_seed: int = 12345,
	nation_count: int = NATION_COUNT,
	terrain_city_count: int = TERRAIN_CITY_COUNT,
	city_mask_path: String = DEFAULT_CITY_MASK_PATH,
	density_settings: Dictionary = {}
) -> void:
	assert(
		nation_count > 0
			and nation_count <= terrain_city_count,
		"国家数必须在 1..%d 之间" % terrain_city_count
	)
	_reset_world(world_seed)
	uses_heightmap = true
	city_generation_mask_path = city_mask_path.strip_edges()
	city_density_settings = (
		TerrainMapGenerator.normalize_city_density_settings(
			density_settings
		)
	)
	_generate_nations(
		DiplomaticRelation.NEUTRAL,
		nation_count
	)
	var terrain := TerrainMapGenerator.build(
		terrain_map_path(),
		terrain_city_count,
		city_generation_mask_path,
		city_density_settings
	)
	_generate_terrain_cities(terrain)
	_assign_balanced_nations()
	_generate_terrain_docks(terrain)
	_generate_terrain_edges(terrain)
	# 初始归属服从合法省份邻接/水运图；飞地通过归属调整消除，
	# 不得为保留空间配额临时创建跨省陆路。
	_repair_initial_nation_connectivity()
	_rebalance_initial_nation_land_quotas()
	# 正式地图从第一帧起就使用与路网面板相同的默认计算规则；
	# 初始化时保护各国内部连通骨架；这不是运行时变更，revision 最终归零。
	var initial_road_settings := default_road_tuning()
	initial_road_settings["preserve_initial_owner_connectivity"] = true
	var initial_road_result := recalculate_road_network(
		initial_road_settings
	)
	assert(bool(initial_road_result.get("ok", false)))
	road_network_revision = 0
	_initialize_recognized_city_owners()
	_initialize_resource_hubs()
	_initialize_terrain_development()
	_initialize_manpower_pools()
	_initialize_capitals_and_warehouses()
	WorldNaming.assign_initial_names(self, world_seed)
	_initialize_city_loyalty()
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
	# 网格世界是严格镜像与旧状态机测试夹具：未显式设置君主时必须保持
	# 中性参数，避免确定性随机原型改变既有外交、经济和攻势基线。
	_generate_nations(DiplomaticRelation.WAR, NATION_COUNT, false)
	_generate_grid_cities()
	_generate_grid_provinces()
	_initialize_recognized_city_owners()
	_initialize_manpower_pools()
	_initialize_capitals_and_warehouses()
	WorldNaming.assign_initial_names(self, world_seed)
	_initialize_city_loyalty()
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


func generate_from_map_definition(
	definition: Dictionary,
	world_seed: int = 12345
) -> void:
	var validation_error := MapDefinition.validate(definition)
	assert(validation_error.is_empty(), validation_error)
	_reset_world(world_seed)
	uses_heightmap = true
	city_generation_mask_path = str(definition.get(
		"city_generation_mask_path", ""
	))
	city_density_settings = (
		TerrainMapGenerator.normalize_city_density_settings(
			definition.get(
				"city_density_settings", {}
			) as Dictionary
		)
	)
	map_aspect_ratio = float(definition.get(
		"map_aspect_ratio", TerrainMapGenerator.FULL_MAP_ASPECT_RATIO
	))
	var source_region: Array = definition.get(
		"source_region", [0.0, 0.0, 1.0, 1.0]
	)
	map_source_region_normalized = Rect2(
		float(source_region[0]), float(source_region[1]),
		float(source_region[2]), float(source_region[3])
	)
	_generate_nations(
		DiplomaticRelation.NEUTRAL,
		int(definition["nation_count"])
	)
	var city_records: Array = definition["cities"]
	for record_value in city_records:
		var record: Dictionary = record_value
		var city := City.new()
		city.id = int(record["id"])
		city.name = str(record.get("name", ""))
		city.region_symbol = str(record.get("region_symbol", ""))
		var coord: Array = record.get("coord", [0, 0])
		city.coord = Vector2i(int(coord[0]), int(coord[1]))
		var position: Array = record["map_position"]
		city.map_position = Vector2(float(position[0]), float(position[1]))
		city.terrain_height = float(record.get("terrain_height", 0.0))
		city.terrain_relief = float(record.get("terrain_relief", 0.0))
		city.terrain_output_multiplier = float(record.get(
			"terrain_output_multiplier", 1.0
		))
		city.is_dock = bool(record.get("is_dock", false))
		city.owner_nation = int(record["owner_nation"])
		city.fort_strength = int(record.get("fort_strength", 10))
		city.fort_strength_max = int(record.get("fort_strength_max", 10))
		city.manpower_per_month = int(record.get("manpower_per_month", 10))
		city.gold_per_month = int(record.get("gold_per_month", 1))
		city.food_per_half_year = int(record.get("food_per_half_year", 100))
		city.is_food_hub = bool(record.get("is_food_hub", false))
		city.is_manpower_hub = bool(record.get("is_manpower_hub", false))
		city.is_plain_city = bool(record.get("is_plain_city", false))
		city.is_port_market = bool(record.get("is_port_market", false))
		city.is_crossroads = bool(record.get("is_crossroads", false))
		city.development_gold_multiplier = float(record.get(
			"development_gold_multiplier", 1.0
		))
		city.development_food_multiplier = float(record.get(
			"development_food_multiplier", 1.0
		))
		city.loyalty = clampf(float(record.get(
			"loyalty", RebellionSystem.LOYALTY_DEFAULT
		)), RebellionSystem.LOYALTY_MIN, RebellionSystem.LOYALTY_MAX)
		city.loyalty_target_nation = int(record.get(
			"loyalty_target_nation", -1
		))
		city.loyalty_trend = float(record.get("loyalty_trend", 0.0))
		city.unrest = clampf(float(record.get(
			"unrest", 100.0 - city.loyalty
		)), 0.0, 100.0)
		city.rebellion_progress = maxi(int(record.get(
			"rebellion_progress", 0
		)), 0)
		city.rebellion_cooldown_until_day = int(record.get(
			"rebellion_cooldown_until_day", -1
		))
		city.food_storage = int(record.get("food_storage", 0))
		cities.append(city)
		adjacency[city.id] = [] as Array[int]
	var edge_records: Array = definition["edges"]
	for record_value in edge_records:
		var record: Dictionary = record_value
		var edge := Edge.new()
		var raw_a := int(record["city_a"])
		var raw_b := int(record["city_b"])
		edge.city_a = mini(raw_a, raw_b)
		edge.city_b = maxi(raw_a, raw_b)
		edge.kind = int(record.get("kind", Edge.Kind.LAND))
		edge.max_manpower = int(record.get("max_manpower", 0))
		edge.base_max_manpower = int(record.get("base_max_manpower", edge.max_manpower))
		edge.distance = maxi(int(record.get("distance", 1)), 1)
		edge.danger = clampf(float(record.get("danger", 0.0)), 0.0, 1.0)
		edge.travel_time_multiplier = maxf(float(record.get("travel_time_multiplier", 1.0)), 0.01)
		edge.supply_loss_multiplier = maxf(float(record.get("supply_loss_multiplier", 1.0)), 0.0)
		edge.allows_holding = bool(record.get("allows_holding", true))
		edge.max_height_difference = maxf(float(record.get("max_height_difference", 0.0)), 0.0)
		edge.land_ratio = clampf(float(record.get("land_ratio", 1.0)), 0.0, 1.0)
		for point_value in record.get("map_path", []):
			var point: Array = point_value
			edge.map_path.append(Vector2(float(point[0]), float(point[1])))
		if raw_a > raw_b:
			edge.map_path.reverse()
		edge.is_backbone = bool(record.get("is_backbone", false))
		edges.append(edge)
		edge_lookup[_edge_key(edge.city_a, edge.city_b)] = edge
		(adjacency[edge.city_a] as Array[int]).append(edge.city_b)
		(adjacency[edge.city_b] as Array[int]).append(edge.city_a)
	for city_id in adjacency:
		(adjacency[city_id] as Array[int]).sort()
	var province_size: Array = definition.get("province_map_size", [0, 0])
	province_map_size = Vector2i(int(province_size[0]), int(province_size[1]))
	province_ids = PackedInt32Array(definition.get("province_ids", []))
	river_paths.clear()
	for river_value in definition.get("river_paths", []):
		var river := PackedVector2Array()
		for point_value in river_value:
			var point: Array = point_value
			river.append(Vector2(float(point[0]), float(point[1])))
		river_paths.append(river)
	_initialize_recognized_city_owners()
	_initialize_manpower_pools()
	_initialize_capitals_and_warehouses()
	WorldNaming.assign_from_definition(self, definition, world_seed)
	_initialize_city_loyalty(false)
	_generate_armies()
	refresh_derived()


func apply_city_editor_changes(
	city_id: int,
	changes: Dictionary
) -> Dictionary:
	if city_id < 0 or city_id >= cities.size():
		return {"ok": false, "error": "城市不存在。"}
	var city := cities[city_id]
	# 先完成所有可能失败的校验；尤其不能在领土事务被拒绝前移动地图坐标。
	var new_position := Vector2(
		clampf(float(changes.get("map_x", city.map_position.x)), 0.0, 1.0),
		clampf(float(changes.get("map_y", city.map_position.y)), 0.0, 1.0)
	)
	var position_changed := new_position != city.map_position
	if (
		position_changed
		and (city.is_dock or not TerrainMapGenerator.is_land_map_position(
			terrain_map_path(), new_position
		))
	):
		return {"ok": false, "error": "陆地城市不能移动到海洋，码头位置暂不可手动移动。"}
	var previous_owner := city.owner_nation
	var owner := clampi(int(changes.get("owner_nation", previous_owner)), 0, nations.size() - 1)
	var owner_changed := owner != previous_owner
	if (
		owner_changed
		and not city.is_dock
		and land_cities_of(previous_owner).size() <= 1
	):
		return {"ok": false, "error": "不能转移一个国家的最后一座陆地城市。"}
	# 先解析全部字段，避免任一无效值在领土或坐标已提交后才触发转换错误。
	var fort_strength_max := maxi(int(changes.get(
		"fort_strength_max", city.fort_strength_max
	)), 0)
	var fort_strength := clampi(int(changes.get(
		"fort_strength", city.fort_strength
	)), 0, fort_strength_max)
	var manpower_per_month := maxi(int(changes.get(
		"manpower_per_month", city.manpower_per_month
	)), 0)
	var gold_per_month := maxi(int(changes.get(
		"gold_per_month", city.gold_per_month
	)), 0)
	var food_per_half_year := maxi(int(changes.get(
		"food_per_half_year", city.food_per_half_year
	)), 0)
	var food_storage := maxi(int(changes.get(
		"food_storage", city.food_storage
	)), 0)
	var terrain_height := clampf(float(changes.get(
		"terrain_height", city.terrain_height
	)), 0.0, 1.0)
	var terrain_relief := clampf(float(changes.get(
		"terrain_relief", city.terrain_relief
	)), 0.0, 1.0)
	var terrain_output_multiplier := clampf(float(changes.get(
		"terrain_output_multiplier", city.terrain_output_multiplier
	)), 0.0, 4.0)
	var development_gold_multiplier := clampf(float(changes.get(
		"development_gold_multiplier", city.development_gold_multiplier
	)), 0.0, 10.0)
	var development_food_multiplier := clampf(float(changes.get(
		"development_food_multiplier", city.development_food_multiplier
	)), 0.0, 10.0)
	if owner_changed:
		var territory_result := transfer_city_sovereignty(
			city_id, owner, "city_editor_transfer",
			TerritoryStockDisposition.MOVE_TO_NEW_POOL
		)
		if not bool(territory_result.get("ok", false)):
			return {
				"ok": false,
				"error": str(territory_result.get(
					"error", "领土转移失败。"
				)),
			}
	city.map_position = new_position
	city.fort_strength_max = fort_strength_max
	city.fort_strength = fort_strength
	city.manpower_per_month = manpower_per_month
	city.gold_per_month = gold_per_month
	city.food_per_half_year = food_per_half_year
	city.food_storage = food_storage
	city.terrain_height = terrain_height
	city.terrain_relief = terrain_relief
	city.terrain_output_multiplier = terrain_output_multiplier
	city.development_gold_multiplier = development_gold_multiplier
	city.development_food_multiplier = development_food_multiplier
	city.is_food_hub = bool(changes.get("is_food_hub", city.is_food_hub))
	city.is_manpower_hub = bool(changes.get("is_manpower_hub", city.is_manpower_hub))
	city.is_plain_city = bool(changes.get("is_plain_city", city.is_plain_city))
	city.is_port_market = bool(changes.get("is_port_market", city.is_port_market))
	city.is_crossroads = bool(changes.get("is_crossroads", city.is_crossroads))
	if position_changed:
		var land_positions: Array[Vector2] = []
		for land_city in land_cities():
			land_positions.append(land_city.map_position)
		var provinces := TerrainMapGenerator.rebuild_provinces(
			terrain_map_path(), land_positions, edges, river_paths
		)
		province_map_size = provinces["size"]
		province_ids = provinces["ids"]
		_refresh_land_edge_paths_after_province_rebuild()
		ownership_revision += 1
		road_network_revision += 1
	refresh_derived()
	return {"ok": true, "city_id": city_id}


func _refresh_land_edge_paths_after_province_rebuild() -> void:
	var shared := TerrainMapGenerator.province_shared_boundary_counts(
		province_ids, province_map_size
	)
	for edge in edges:
		if edge.map_path.size() >= 2:
			edge.map_path[0] = cities[edge.city_a].map_position
			edge.map_path[-1] = cities[edge.city_b].map_position
		if (
			edge.kind != Edge.Kind.LAND
			or edge.city_a >= land_cities().size()
			or edge.city_b >= land_cities().size()
		):
			continue
		edge.map_path.clear()
		if not shared.has(_edge_key(edge.city_a, edge.city_b)):
			edge.max_manpower = 0
			edge.base_max_manpower = Edge.TERRAIN_LOW_MANPOWER
			edge.is_backbone = false
			continue
		var from := cities[edge.city_a].map_position
		var to := cities[edge.city_b].map_position
		if not TerrainMapGenerator.province_segment_stays_in_pair(
			province_ids, province_map_size, from, to,
			edge.city_a, edge.city_b
		):
			edge.map_path = TerrainMapGenerator.province_pair_path(
				province_ids, province_map_size, from, to,
				edge.city_a, edge.city_b
			)
		var points := edge.map_points(from, to)
		edge.distance = TerrainMapGenerator.distance_units_for_metric_length(
			TerrainMapGenerator.metric_polyline_length(
				points, map_aspect_ratio
			)
		)
	for edge in edges:
		if edge.kind == Edge.Kind.LAND:
			continue
		var points := edge.map_points(
			cities[edge.city_a].map_position,
			cities[edge.city_b].map_position
		)
		edge.distance = TerrainMapGenerator.distance_units_for_metric_length(
			TerrainMapGenerator.metric_polyline_length(points, map_aspect_ratio)
		)


func apply_edge_editor_changes(
	city_a: int,
	city_b: int,
	changes: Dictionary
) -> Dictionary:
	var edge := edge_of(city_a, city_b)
	if edge == null:
		return {"ok": false, "error": "道路不存在。"}
	edge.kind = clampi(int(changes.get("kind", edge.kind)), Edge.Kind.LAND, Edge.Kind.SEA)
	var requested_capacity := int(changes.get("max_manpower", edge.max_manpower))
	edge.max_manpower = (
		Edge.WATER_MANPOWER
		if edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]
		else Edge.quantize_land_capacity(requested_capacity)
	)
	edge.base_max_manpower = edge.max_manpower
	edge.distance = maxi(int(changes.get("distance", edge.distance)), 1)
	edge.danger = clampf(float(changes.get("danger", edge.danger)), 0.0, 1.0)
	edge.travel_time_multiplier = maxf(float(changes.get("travel_time_multiplier", edge.travel_time_multiplier)), 0.01)
	edge.supply_loss_multiplier = maxf(float(changes.get("supply_loss_multiplier", edge.supply_loss_multiplier)), 0.0)
	edge.allows_holding = bool(changes.get("allows_holding", edge.allows_holding))
	edge.max_height_difference = clampf(float(changes.get("max_height_difference", edge.max_height_difference)), 0.0, 1.0)
	edge.land_ratio = clampf(float(changes.get("land_ratio", edge.land_ratio)), 0.0, 1.0)
	edge.is_backbone = bool(changes.get("is_backbone", edge.is_backbone))
	if edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]:
		edge.allows_holding = false
	road_network_revision += 1
	return {"ok": true, "city_a": edge.city_a, "city_b": edge.city_b}


func _reset_world(world_seed: int) -> void:
	self.world_seed = world_seed
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
	road_network_revision = 0
	diplomatic_relations.clear()
	diplomatic_since_day.clear()
	truce_until_day.clear()
	diplomatic_history.clear()
	war_objectives.clear()
	suzerainty.clear()
	city_generation_mask_path = ""
	city_density_settings = {}
	province_map_size = Vector2i.ZERO
	province_ids = PackedInt32Array()
	river_paths.clear()
	recognized_city_owners = PackedInt32Array()
	campaign_visual_events.clear()
	rebellions.clear()
	trade_routes.clear()
	trade_revision = 0
	naming_revision = 0
	_random_ruler_profiles_enabled = true


func _generate_nations(
	initial_relation: int,
	nation_count: int = NATION_COUNT,
	initialize_rulers: bool = true
) -> void:
	_random_ruler_profiles_enabled = initialize_rulers
	for i in range(nation_count):
		var n := Nation.new()
		n.id = i
		n.color = normalize_nation_color(
			Color.from_hsv(
				float(NATION_PALETTE_HUES[i]),
				float(NATION_PALETTE_SATURATIONS[i]),
				float(NATION_PALETTE_VALUES[i])
			)
			if nation_count == NATION_COUNT
			else Color.from_hsv(
				fposmod(
					float(i) * 0.61803398875,
					1.0
				),
				0.76 + float(i % 3) * 0.03,
				0.36 + float(i % 4) * 0.025
			)
		)
		n.treasury_gold = 10000
		n.political_system = 0
		n.alive = true
		if initialize_rulers:
			RulerProfile.initialize_nation(n, world_seed, i)
		else:
			n.ruler_archetype = RulerProfile.BALANCED
			n.ruler_traits.clear()
			n.trade_policy = RulerProfile.POLICY_BALANCED
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
		var owner_city := int(dock_data.get(
			"owner_city",
			int(dock_data["road_a"])
				if road_t <= 0.5
				else int(dock_data["road_b"])
		))
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
			if edge.kind not in [Edge.Kind.RIVER, Edge.Kind.SEA]:
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


func _initialize_city_loyalty(reset_values: bool = true) -> void:
	for city in cities:
		var recognized := recognized_owner_of(city.id)
		if reset_values or city.loyalty_target_nation < 0:
			city.loyalty_target_nation = (
				recognized if recognized >= 0 else city.owner_nation
			)
		if reset_values:
			city.loyalty = RebellionSystem.LOYALTY_DEFAULT
			city.loyalty_trend = 0.0
			city.unrest = 100.0 - city.loyalty
			city.rebellion_progress = 0
			city.rebellion_cooldown_until_day = -1
			city.last_loyalty_reason = "initial"


## 首都道路跳数的公共真源；忠诚、分封和未来行政范围共用。
func capital_hop_distances(nation_id: int) -> Dictionary:
	return RebellionSystem.capital_hops(self, nation_id)


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
		if edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]:
			edge.max_manpower = Edge.WATER_MANPOWER
		else:
			edge.max_manpower = Edge.quantize_land_capacity(
				edge.max_manpower
			)
		edge.land_ratio = float(road.get("land_ratio", 1.0))
		edge.map_path = (
			road.get("map_path", PackedVector2Array())
			as PackedVector2Array
		).duplicate()
		if a > b:
			edge.map_path.reverse()
		edge.distance = TerrainMapGenerator.distance_units_for_metric_length(
			TerrainMapGenerator.metric_polyline_length(
				edge.map_points(
					cities[edge.city_a].map_position,
					cities[edge.city_b].map_position
				),
				map_aspect_ratio
			)
		)
		edge.is_backbone = bool(road.get("backbone", false))
		edge.base_max_manpower = int(road.get(
			"base_max_manpower",
			maxi(edge.max_manpower, Edge.TERRAIN_LOW_MANPOWER)
		))
		edge.base_max_manpower = (
			Edge.WATER_MANPOWER
			if edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]
			else Edge.quantize_land_capacity(
				maxf(edge.base_max_manpower, Edge.TERRAIN_LOW_MANPOWER)
			)
		)
		edges.append(edge)
		edge_lookup[_edge_key(lo, hi)] = edge
		(adjacency[lo] as Array[int]).append(hi)
		(adjacency[hi] as Array[int]).append(lo)
	for city_id in adjacency.keys():
		(adjacency[city_id] as Array[int]).sort()


static func default_road_tuning() -> Dictionary:
	return {
		"minimum_land_ratio": 0.90,
		"maximum_relief": 0.25,
		"blocked_branch_share": 0.10,
		"terrain_capacity_penalty": 0.35,
		"capacity_multiplier": 1.0,
	}


func road_network_rebuild_block_reason() -> String:
	if edges.is_empty():
		return "当前世界没有可调校的道路。"
	return ""


func recalculate_road_network(settings: Dictionary) -> Dictionary:
	var blocked_reason := road_network_rebuild_block_reason()
	if not blocked_reason.is_empty():
		return {
			"ok": false,
			"error": blocked_reason,
		}
	var defaults := default_road_tuning()
	var minimum_land_ratio := clampf(
		float(settings.get(
			"minimum_land_ratio",
			defaults["minimum_land_ratio"]
		)),
		0.70,
		1.0
	)
	var maximum_relief := clampf(
		float(settings.get(
			"maximum_relief",
			defaults["maximum_relief"]
		)),
		0.05,
		1.0
	)
	var blocked_share := clampf(
		float(settings.get(
			"blocked_branch_share",
			defaults["blocked_branch_share"]
		)),
		0.0,
		0.45
	)
	var terrain_penalty := clampf(
		float(settings.get(
			"terrain_capacity_penalty",
			defaults["terrain_capacity_penalty"]
		)),
		0.0,
		0.90
	)
	var capacity_multiplier := clampf(
		float(settings.get(
			"capacity_multiplier",
			defaults["capacity_multiplier"]
		)),
		0.25,
		3.0
	)
	var protected_keys := {}
	if bool(settings.get(
		"preserve_initial_owner_connectivity", false
	)):
		protected_keys.merge(
			_initial_owner_connectivity_edge_keys(),
			true
		)
	for army in armies:
		if (
			army.size > 0
			and army.on_edge
			and army.move_from >= 0
			and army.move_to >= 0
		):
			protected_keys[_edge_key(
				army.move_from,
				army.move_to
			)] = true
	for battle in battles:
		if not battle.finished and battle.edge != null:
			protected_keys[_edge_key(
				battle.edge.city_a,
				battle.edge.city_b
			)] = true
	var land_edges: Array[Edge] = []
	var blocked_keys := {}
	for edge in edges:
		if edge.kind != Edge.Kind.LAND:
			continue
		land_edges.append(edge)
		if (
			not edge.is_backbone
			and not protected_keys.has(
				_edge_key(edge.city_a, edge.city_b)
			)
			and (
				edge.land_ratio < minimum_land_ratio
				or edge.max_height_difference > maximum_relief
			)
		):
			blocked_keys[_edge_key(edge.city_a, edge.city_b)] = true
	var branch_candidates: Array[Edge] = []
	for edge in land_edges:
		var key := _edge_key(edge.city_a, edge.city_b)
		if (
			edge.is_backbone
			or protected_keys.has(key)
			or blocked_keys.has(key)
		):
			continue
		branch_candidates.append(edge)
	branch_candidates.sort_custom(func(a: Edge, b: Edge) -> bool:
		var difficulty_a := (
			a.danger * 0.55
			+ a.max_height_difference * 0.35
			+ (1.0 - a.land_ratio) * 0.10
		)
		var difficulty_b := (
			b.danger * 0.55
			+ b.max_height_difference * 0.35
			+ (1.0 - b.land_ratio) * 0.10
		)
		if not is_equal_approx(difficulty_a, difficulty_b):
			return difficulty_a > difficulty_b
		return _edge_key(a.city_a, a.city_b) < _edge_key(
			b.city_a,
			b.city_b
		)
	)
	var extra_blocked := mini(
		int(round(float(land_edges.size()) * blocked_share)),
		branch_candidates.size()
	)
	for index in range(extra_blocked):
		var edge := branch_candidates[index]
		blocked_keys[_edge_key(edge.city_a, edge.city_b)] = true
	var open_count := 0
	var blocked_count := 0
	var total_capacity := 0
	for edge in land_edges:
		var key := _edge_key(edge.city_a, edge.city_b)
		if blocked_keys.has(key):
			edge.max_manpower = 0
			blocked_count += 1
			continue
		if protected_keys.has(key):
			edge.max_manpower = Edge.quantize_land_capacity(
				edge.max_manpower
			)
			open_count += 1
			total_capacity += edge.max_manpower
			continue
		var difficulty := clampf(
			edge.danger * 0.60
				+ edge.max_height_difference * 0.40,
			0.0,
			1.0
		)
		var capacity := (
			float(maxi(
				edge.base_max_manpower,
				Edge.MIN_MANPOWER
			))
			* capacity_multiplier
			* (1.0 - terrain_penalty * difficulty)
		)
		edge.max_manpower = Edge.quantize_land_capacity(capacity)
		if edge.is_backbone:
			edge.max_manpower = maxi(
				edge.max_manpower,
				Edge.TERRAIN_LOW_MANPOWER
			)
		open_count += 1
		total_capacity += edge.max_manpower
	for army in armies:
		army.clear_line_assignment()
	for nation in nations:
		nation.frontier_defense_sectors.clear()
		nation.frontier_defense_topology = null
	road_network_revision += 1
	return {
		"ok": true,
		"open_count": open_count,
		"blocked_count": blocked_count,
		"average_capacity": (
			total_capacity / maxi(open_count, 1)
		),
		"protected_count": protected_keys.size(),
		"revision": road_network_revision,
	}

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


func _initial_owner_connectivity_edge_keys() -> Dictionary:
	var result := {}
	for nation in nations:
		var owned := cities_of(nation.id)
		if owned.is_empty():
			continue
		var visited := {owned[0].id: true}
		var queue: Array[int] = [owned[0].id]
		var cursor := 0
		while cursor < queue.size():
			var city_id := queue[cursor]
			cursor += 1
			for neighbor in neighbors(city_id):
				var edge := edge_of(city_id, neighbor)
				if (
					visited.has(neighbor)
					or cities[neighbor].owner_nation != nation.id
					or edge == null
					or edge.max_manpower <= 0
				):
					continue
				visited[neighbor] = true
				queue.append(neighbor)
				result[_edge_key(city_id, neighbor)] = true
		assert(
			visited.size() == owned.size(),
			"初始化路网重算前国%d必须已连通" % nation.id
		)
	return result


## 几何初分只提供空间先验；最终归属必须服从合法道路/码头图。每轮保留
## 各国陆城最多的主体组件，其余飞地整体交给边界连接最多的邻国，直到稳定。
func _repair_initial_nation_connectivity() -> void:
	var guard := cities.size()
	while guard > 0:
		guard -= 1
		var changed := false
		for nation in nations:
			var components := _initial_owner_components(nation.id)
			if components.size() <= 1:
				continue
			components.sort_custom(
				func(a: Array, b: Array) -> bool:
					var land_a := _initial_component_land_count(a)
					var land_b := _initial_component_land_count(b)
					if land_a != land_b:
						return land_a > land_b
					if a.size() != b.size():
						return a.size() > b.size()
					return int(a[0]) < int(b[0])
			)
			# 每轮只处理该国一个飞地，随后重新计算全部组件；归属或容量
			# 变化会立即影响组件关系，不能继续使用本轮的过期快照。
			var component: Array = components[1]
			if _reopen_initial_component_connector(component, nation.id):
				changed = true
				break
			assert(
				_transfer_initial_component_to_neighbor(component, nation.id),
				"初始飞地必须沿合法交通图连接到邻国"
			)
			changed = true
			break
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


func _reopen_initial_component_connector(
	component: Array, owner_nation: int
) -> bool:
	var component_set := {}
	for city_value in component:
		component_set[int(city_value)] = true
	var best: Edge = null
	for city_value in component:
		for neighbor in neighbors(int(city_value)):
			var edge := edge_of(int(city_value), neighbor)
			if (
				edge == null
				or component_set.has(neighbor)
				or cities[neighbor].owner_nation != owner_nation
			):
				continue
			if best == null or edge.distance < best.distance:
				best = edge
	if best == null:
		return false
	best.max_manpower = (
		Edge.WATER_MANPOWER
		if best.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]
		else Edge.TERRAIN_LOW_MANPOWER
	)
	best.is_backbone = true
	return true


func _transfer_initial_component_to_neighbor(
	component: Array, owner_nation: int
) -> bool:
	var counts := {}
	var edge_by_owner := {}
	for city_value in component:
		for neighbor in neighbors(int(city_value)):
			var edge := edge_of(int(city_value), neighbor)
			var neighbor_owner := cities[neighbor].owner_nation
			if edge == null or neighbor_owner < 0 or neighbor_owner == owner_nation:
				continue
			counts[neighbor_owner] = int(counts.get(neighbor_owner, 0)) + 1
			var previous: Edge = edge_by_owner.get(neighbor_owner)
			if previous == null or edge.distance < previous.distance:
				edge_by_owner[neighbor_owner] = edge
	if counts.is_empty():
		return false
	var owners := counts.keys()
	owners.sort()
	var recipient := int(owners[0])
	for owner_value in owners:
		var owner := int(owner_value)
		var owner_land_count := land_cities_of(owner).size()
		var recipient_land_count := land_cities_of(recipient).size()
		if (
			owner_land_count < recipient_land_count
			or (
				owner_land_count == recipient_land_count
				and int(counts[owner]) > int(counts[recipient])
			)
		):
			recipient = owner
	for city_value in component:
		cities[int(city_value)].owner_nation = recipient
	var connector: Edge = edge_by_owner[recipient]
	connector.max_manpower = (
		Edge.WATER_MANPOWER
		if connector.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]
		else Edge.TERRAIN_LOW_MANPOWER
	)
	connector.is_backbone = true
	return true


## 连通修复可能把少量飞地整体转给同一邻国。只移动连通安全的边界陆城，
## 将初始国陆城数收敛到均值±1；不新增/删除任何道路。
func _rebalance_initial_nation_land_quotas() -> void:
	# 精确四等份是默认四国地图的设计约束。自定义国家数使用递归空间
	# 分区，只要求每国非空且交通连通，不强加全局均值±1。
	if nations.size() != NATION_COUNT:
		return
	var average := float(land_cities().size()) / float(nations.size())
	var target_count := int(round(average))
	var minimum_count := maxi(int(floor(average)) - 1, 1)
	var maximum_count := int(ceil(average)) + 1
	var guard := cities.size() * nations.size()
	while guard > 0:
		guard -= 1
		var counts: Array[int] = []
		counts.resize(nations.size())
		for nation in nations:
			counts[nation.id] = land_cities_of(nation.id).size()
		var changed := false
		for source in nations:
			if counts[source.id] <= maximum_count:
				continue
			var candidates := land_cities_of(source.id)
			candidates.sort_custom(func(a: City, b: City) -> bool:
				return a.id < b.id
			)
			for city in candidates:
				var recipient_ids := {}
				for neighbor in neighbors(city.id):
					var edge := edge_of(city.id, neighbor)
					var owner := cities[neighbor].owner_nation
					if (
						edge != null and edge.max_manpower > 0
						and owner >= 0 and owner != source.id
						and counts[owner] < target_count
					):
						recipient_ids[owner] = true
				var recipients := recipient_ids.keys()
				recipients.sort_custom(func(a: Variant, b: Variant) -> bool:
					var owner_a := int(a)
					var owner_b := int(b)
					return (
						counts[owner_a] < counts[owner_b]
						or (counts[owner_a] == counts[owner_b] and owner_a < owner_b)
					)
				)
				for recipient_value in recipients:
					var recipient := int(recipient_value)
					if _initial_city_transfer_preserves_connectivity(
						city.id, source.id, recipient
					):
						city.owner_nation = recipient
						changed = true
						break
				if changed:
					break
			if changed:
				break
		if not changed:
			break
	for nation in nations:
		var count := land_cities_of(nation.id).size()
		assert(
			count >= minimum_count and count <= maximum_count,
			"初始国%d陆城数必须在均值±1内，实为%d" % [nation.id, count]
		)


func _initial_city_transfer_preserves_connectivity(
	city_id: int, source_id: int, recipient_id: int
) -> bool:
	var city := cities[city_id]
	city.owner_nation = recipient_id
	var source_connected := _initial_owner_components(source_id).size() <= 1
	var recipient_connected := _initial_owner_components(recipient_id).size() <= 1
	city.owner_nation = source_id
	return source_connected and recipient_connected


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
		var owned_land := land_cities_of(nation.id)
		owned_land.sort_custom(func(a: City, b: City) -> bool:
			return EquivariantOrder.city_less(
				self,
				nation.id,
				a,
				b
			)
		)
		# 小型新开局直接采用生存军制：每座陆城一支轻型 LINE，另有
		# 一支单成员轻型 MAIN 作为机动预备队。它不需要先生成完整
		# 二轻一重战团，再等待战争中的运行时逻辑停止补员。
		if (
			not owned_land.is_empty()
			and owned_land.size() <= SMALL_NATION_SURVIVAL_MAX_CITIES
		):
			for city in owned_land:
				var line := create_army(
					nation.id, city.id,
					INITIAL_LIGHT_ARMY_SIZE, INITIAL_LIGHT_ARMY_SIZE
				)
				if line != null:
					_initialize_army_attributes(line)
			for _reserve_index in range(SMALL_NATION_MOBILE_RESERVE_ARMIES):
				if active_army_count(nation.id) >= max_army_count(nation.id):
					break
				var reserve_group := create_battle_group(nation.id)
				var reserve := create_army(
					nation.id, nation.capital_city_id,
					INITIAL_LIGHT_ARMY_SIZE, INITIAL_LIGHT_ARMY_SIZE
				)
				if reserve == null:
					nation.battle_groups.erase(reserve_group)
					break
				_initialize_army_attributes(reserve)
				assign_army_to_battle_group(reserve, reserve_group.id)
			continue
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
		# 每个有城国家随后还要生成二轻一重的完整初始战团。小型自定义
		# 地图必须先为这三支军队预留上限，避免一城国在加载时越界。
		var battle_group_slots := (
			BattleGroup.MAX_LIGHT_ARMIES + BattleGroup.MAX_HEAVY_ARMIES
		)
		var maximum_line_armies := maxi(
			max_army_count(nation.id) - battle_group_slots,
			0
		)
		if line_cities.size() > maximum_line_armies:
			line_cities.resize(maximum_line_armies)
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


func effective_ai_aggression(nation_id: int) -> float:
	if nation_id < 0 or nation_id >= nations.size():
		return 1.0
	var nation := nations[nation_id]
	return clampf(
		nation.ai_aggression
			* RulerProfile.aggression_multiplier(nation),
		0.35, 1.85
	)


func effective_army_defense(army: Army) -> float:
	if army == null:
		return 0.0
	return float(army.defense) * maxf(army.ruler_defense_multiplier, 0.1)


func effective_city_defense(city: City) -> int:
	if city == null:
		return 0
	var owner_id := city.owner_nation
	var multiplier := (
		RulerProfile.city_defense_multiplier(nations[owner_id])
		if owner_id >= 0 and owner_id < nations.size()
		else 1.0
	)
	return maxi(int(round(
		float(Combat.city_defense_modifier(city)) * multiplier
	)), 0)


func nation_display_name(nation_id: int) -> String:
	return WorldNaming.nation_display_name(self, nation_id)


func city_display_name(city_id: int, include_kind: bool = false) -> String:
	return WorldNaming.city_display_name(self, city_id, include_kind)


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


## 当前联盟图中 nation_id 所在的确定性、冲突感知连通分量。按国家 id 顺序扫描
## ALLIED 边；只有两个既有分量之间不存在任何 WAR 对时才合并。这样普通链式联盟
## 仍组成一个集团，但互为敌国的两方不会经共同盟友被传递闭包错误地并入同一集团。
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
	var parent := PackedInt32Array()
	parent.resize(nations.size())
	parent.fill(-1)
	var components: Dictionary = {}
	for candidate_id in range(nations.size()):
		if alive_only and not nations[candidate_id].alive:
			continue
		parent[candidate_id] = candidate_id
		components[candidate_id] = [candidate_id] as Array[int]
	# (a,b) 以字典序遍历，所以在矛盾联盟图上选择保留哪条盟约也不依赖调用者。
	for nation_a in range(nations.size()):
		if parent[nation_a] < 0:
			continue
		for nation_b in range(nation_a + 1, nations.size()):
			if (
				parent[nation_b] < 0
				or relation_between(nation_a, nation_b)
					!= DiplomaticRelation.ALLIED
			):
				continue
			var root_a := nation_a
			while parent[root_a] != root_a:
				root_a = parent[root_a]
			var root_b := nation_b
			while parent[root_b] != root_b:
				root_b = parent[root_b]
			if root_a == root_b:
				continue
			var blocked := false
			for member_a in components[root_a]:
				for member_b in components[root_b]:
					if is_enemy(int(member_a), int(member_b)):
						blocked = true
						break
				if blocked:
					break
			if blocked:
				continue
			var kept_root := mini(root_a, root_b)
			var merged_root := maxi(root_a, root_b)
			var merged: Array[int] = []
			for member in components[kept_root]:
				merged.append(int(member))
			for member in components[merged_root]:
				merged.append(int(member))
			merged.sort()
			parent[merged_root] = kept_root
			components[kept_root] = merged
			components.erase(merged_root)
	var nation_root := nation_id
	while parent[nation_root] != nation_root:
		nation_root = parent[nation_root]
	for member in components[nation_root]:
		result.append(int(member))
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
	if (
		subject_id < 0
		or subject_id >= nations.size()
		or overlord_id < 0
		or overlord_id >= nations.size()
		or not nations[subject_id].alive
		or not nations[overlord_id].alive
		or cities_of(subject_id).is_empty()
		or cities_of(overlord_id).is_empty()
	):
		return false
	# 1. 切分前先量取：反叛方子树（沿非内战边）与整个原粮池的粮食产能，用于按比例分粮。
	var holder_before := food_pool_holder(subject_id)
	var rebel_food_output := _food_pool_food_output(subject_id)
	var pool_food_output := _food_pool_food_output(holder_before)
	var pool_stock := _food_pool_stock(holder_before)
	var rebel_share := _proportional_share(
		pool_stock, rebel_food_output, pool_food_output
	)
	# 2. 把内战边作为完整拟议图随行政/粮池一起提交；失败时 live 政治图
	# 与外交仍保持原状。份额在旧快照上计算，实际切粮只在事务成功后进行。
	var proposed := suzerainty.duplicate(true)
	(proposed[subject_id] as Dictionary)["civil_war"] = true
	(proposed[subject_id] as Dictionary)["last_centralization_day"] = day
	var capital_id := nations[subject_id].capital_city_id
	if capital_id < 0 or capital_id >= cities.size():
		return false
	var territory_result := apply_territory_transaction(
		[] as Array[Dictionary],
		{subject_id: capital_id},
		-1,
		proposed
	)
	if not bool(territory_result.get("ok", false)):
		return false
	if rebel_share > 0:
		var withdrawn_food := _withdraw_food_from_warehouses(
			nations[holder_before], rebel_share
		)
		cities[capital_id].food_storage += withdrawn_food
		refresh_derived()
	# 4. 起兵资本：反叛方首都凭空动员火星兵（满编主战军团）。
	_spawn_civil_war_uprising_armies(subject_id)
	nations[subject_id].last_rebellion_day = day
	nations[overlord_id].last_rebellion_day = day
	return true


## 地方叛乱事务：把同一亲叛政治目标的连续低忠诚城市转成新的反叛国。
## 实控先转给叛军，法理仍留在母国；只有未来和平承认才改变 recognized owner。
## 资源、人力和驻军均从当地/母国守恒划转，不复用削藩的满编“火星兵”。
func start_regional_rebellion(
	parent_id: int,
	city_ids: Array[int]
) -> int:
	if (
		parent_id < 0 or parent_id >= nations.size()
		or not nations[parent_id].alive
		or city_ids.is_empty()
	):
		return -1
	var unique_ids: Array[int] = []
	for city_value in city_ids:
		var city_id := int(city_value)
		if (
			city_id < 0 or city_id >= cities.size()
			or cities[city_id].is_dock
			or cities[city_id].is_capital
			or cities[city_id].owner_nation != parent_id
			or unique_ids.has(city_id)
		):
			return -1
		unique_ids.append(city_id)
	unique_ids.sort()
	if unique_ids.size() >= land_cities_of(parent_id).size():
		return -1
	# Region must be connected through usable roads.
	var allowed := {}
	for city_id in unique_ids:
		allowed[city_id] = true
	var seen := {unique_ids[0]: true}
	var queue: Array[int] = [unique_ids[0]]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor in neighbors(current):
			var edge := edge_of(current, neighbor)
			if (
				not allowed.has(neighbor) or seen.has(neighbor)
				or edge == null or edge.max_manpower <= 0
			):
				continue
			seen[neighbor] = true
			queue.append(neighbor)
	if seen.size() != unique_ids.size():
		return -1

	var parent := nations[parent_id]
	# 地方叛乱可能发生在和平藩王领内；它的库存真源是宗藩根粮池，
	# 不能从零库存的藩王中继首都取数。城市易主前冻结分母与库存。
	var food_holder_before := food_pool_holder(parent_id)
	var food_pool_stock_before := _food_pool_stock(food_holder_before)
	var food_pool_output_before := _food_pool_food_output(food_holder_before)
	var rebel := Nation.new()
	rebel.id = nations.size()
	rebel.color = _derive_vassal_color(parent.color, rebel.id)
	rebel.alive = true
	rebel.political_system = parent.political_system
	rebel.ai_aggression = 1.0
	if _random_ruler_profiles_enabled:
		RulerProfile.initialize_nation(
			rebel, world_seed, rebel.id + day * 97
		)
	else:
		# 兼容网格世界中的运行时新国家也保持中性；专项测试可显式覆写。
		rebel.ruler_archetype = RulerProfile.BALANCED
		rebel.ruler_traits.clear()
		rebel.trade_policy = RulerProfile.POLICY_BALANCED
	rebel.ruler_started_day = day
	rebel.name_kind = WorldNaming.KIND_REBEL
	nations.append(rebel)

	var parent_manpower_output := 0
	var rebel_manpower_output := 0
	var parent_gold_output := 0
	var rebel_gold_output := 0
	var rebel_food_output := 0
	for city in land_cities_of(parent_id):
		parent_manpower_output += city.manpower_per_month
		parent_gold_output += city.gold_per_month
		if allowed.has(city.id):
			rebel_manpower_output += city.manpower_per_month
			rebel_gold_output += city.gold_per_month
			rebel_food_output += city.food_per_half_year
	var transferred_manpower := _proportional_share(
		parent.manpower_pool, rebel_manpower_output, parent_manpower_output
	)
	var transferred_gold := _proportional_share(
		parent.treasury_gold, rebel_gold_output, parent_gold_output
	)
	var region_centroid := Vector2.ZERO
	for city_id in unique_ids:
		region_centroid += cities[city_id].map_position
	region_centroid /= float(unique_ids.size())
	var capital_id := unique_ids[0]
	var capital_distance := INF
	for city_id in unique_ids:
		var distance := cities[city_id].map_position.distance_squared_to(
			region_centroid
		)
		if distance < capital_distance or (
			is_equal_approx(distance, capital_distance) and city_id < capital_id
		):
			capital_distance = distance
			capital_id = city_id
	var territory_operations: Array[Dictionary] = []
	for city_id in unique_ids:
		territory_operations.append({
			"city_id": city_id,
			"controller_id": rebel.id,
			"sponsor_id": rebel.id,
			"stock_policy": TerritoryStockDisposition.RETURN_TO_OLD_POOL,
			"reason": "regional_rebellion",
		})
	var territory_result := apply_territory_transaction(
		territory_operations, {rebel.id: capital_id}
	)
	if not bool(territory_result.get("ok", false)):
		nations.pop_back()
		return -1
	parent.manpower_pool -= transferred_manpower
	parent.treasury_gold -= transferred_gold
	rebel.manpower_pool = transferred_manpower
	rebel.treasury_gold = transferred_gold
	var food_share := _proportional_share(
		food_pool_stock_before, rebel_food_output, food_pool_output_before
	)
	if food_share > 0:
		var withdrawn_food := _withdraw_food_from_warehouses(
			nations[food_holder_before], food_share
		)
		cities[capital_id].food_storage += withdrawn_food
		nations[food_holder_before].granary_food -= withdrawn_food
		rebel.granary_food += withdrawn_food
	WorldNaming.assign_rebel_name(self, rebel.id, parent_id, unique_ids)
	_inherit_rebel_diplomacy(parent_id, rebel.id)
	set_diplomatic_relation(parent_id, rebel.id, DiplomaticRelation.WAR)

	# Local stationed forces defect; if none do, mobilize only from transferred
	# manpower and never conjure a full army without paying the pool.
	var defected := 0
	for army in armies:
		if (
			army.owner_nation == parent_id
			and army.state in [Army.State.IDLE, Army.State.RECOVERING]
			and not army.on_edge and allowed.has(army.location_city)
		):
			army.owner_nation = rebel.id
			army.battle_group_id = -1
			if army.max_size >= INITIAL_HEAVY_ARMY_SIZE:
				var rebel_group := create_battle_group(rebel.id)
				assign_army_to_battle_group(army, rebel_group.id)
			else:
				army.strategic_role = Army.StrategicRole.LINE
			army.clear_line_assignment()
			defected += 1
	if defected == 0 and rebel.manpower_pool >= INITIAL_LIGHT_ARMY_SIZE:
		var uprising := create_army(
			rebel.id, capital_id, INITIAL_LIGHT_ARMY_SIZE, INITIAL_LIGHT_ARMY_SIZE
		)
		if uprising != null:
			rebel.manpower_pool -= INITIAL_LIGHT_ARMY_SIZE
			_initialize_army_attributes(uprising)
	rebellions[rebel.id] = {
		"parent_id": parent_id,
		"started_day": day,
		"core_city_ids": unique_ids.duplicate(),
		"recognized": false,
		"active": true,
		"reason": "连续低忠诚地区起义",
	}
	parent.last_rebellion_day = day
	rebel.last_rebellion_day = day
	return rebel.id


## 低忠诚地区已有存活政治目标时，不再创造匿名地方叛军，而是恢复/归附该国。
## 实控立即转给 target；法理本就属于 target 时清除占领声明，否则保留原法理并
## 明确标记 target 为占领方。地方资源和静止驻军守恒迁移，既有外交关系不改写。
func restore_regional_loyalty_target(
	parent_id: int,
	target_id: int,
	city_ids: Array[int]
) -> bool:
	if (
		parent_id < 0 or parent_id >= nations.size()
		or target_id < 0 or target_id >= nations.size()
		or parent_id == target_id
		or not nations[parent_id].alive
		or not nations[target_id].alive
		or city_ids.is_empty()
	):
		return false
	var unique_ids: Array[int] = []
	for city_value in city_ids:
		var city_id := int(city_value)
		if (
			city_id < 0 or city_id >= cities.size()
			or cities[city_id].is_dock
			or cities[city_id].is_capital
			or cities[city_id].owner_nation != parent_id
			or cities[city_id].loyalty_target_nation != target_id
			or unique_ids.has(city_id)
		):
			return false
		unique_ids.append(city_id)
	unique_ids.sort()
	if unique_ids.size() >= land_cities_of(parent_id).size():
		return false

	var allowed := {}
	for city_id in unique_ids:
		allowed[city_id] = true
	var seen := {unique_ids[0]: true}
	var queue: Array[int] = [unique_ids[0]]
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for neighbor in neighbors(current):
			var edge := edge_of(current, neighbor)
			if (
				not allowed.has(neighbor) or seen.has(neighbor)
				or edge == null or edge.max_manpower <= 0
			):
				continue
			seen[neighbor] = true
			queue.append(neighbor)
	if seen.size() != unique_ids.size():
		return false
	if is_suzerainty_pair(parent_id, target_id):
		var subject_id := (
			parent_id if overlord_of(parent_id) == target_id else target_id
		)
		if not is_in_civil_war(subject_id):
			return false

	var parent := nations[parent_id]
	var target := nations[target_id]
	var parent_manpower_output := 0
	var moved_manpower_output := 0
	var parent_gold_output := 0
	var moved_gold_output := 0
	var moved_food_output := 0
	var food_holder_before := food_pool_holder(parent_id)
	var food_pool_stock_before := _food_pool_stock(food_holder_before)
	var food_pool_output_before := _food_pool_food_output(food_holder_before)
	for city in land_cities_of(parent_id):
		parent_manpower_output += city.manpower_per_month
		parent_gold_output += city.gold_per_month
		if allowed.has(city.id):
			moved_manpower_output += city.manpower_per_month
			moved_gold_output += city.gold_per_month
			moved_food_output += city.food_per_half_year
	var transferred_manpower := _proportional_share(
		parent.manpower_pool, moved_manpower_output, parent_manpower_output
	)
	var transferred_gold := _proportional_share(
		parent.treasury_gold, moved_gold_output, parent_gold_output
	)
	var transferred_food := _proportional_share(
		food_pool_stock_before, moved_food_output, food_pool_output_before
	)
	var territory_operations: Array[Dictionary] = []
	for city_id in unique_ids:
		territory_operations.append({
			"city_id": city_id,
			"controller_id": target_id,
			"sponsor_id": target_id,
			# 先把随城易主的粮仓库存完整归回旧粮池；下方再以事务前
			# 总库存为基数按产能比例划给目标，避免销毁后重复扣减。
			"stock_policy": TerritoryStockDisposition.RETURN_TO_OLD_POOL,
			"reason": "regional_loyalty_restored",
		})
	var territory_result := apply_territory_transaction(territory_operations)
	if not bool(territory_result.get("ok", false)):
		return false
	if (
		not is_suzerainty_pair(parent_id, target_id)
		and not is_enemy(parent_id, target_id)
	):
		set_diplomatic_relation(
			parent_id, target_id, DiplomaticRelation.WAR
		)
	parent.manpower_pool -= transferred_manpower
	parent.treasury_gold -= transferred_gold
	target.manpower_pool += transferred_manpower
	target.treasury_gold += transferred_gold
	if transferred_food > 0:
		var withdrawn_food := _withdraw_food_from_warehouses(
			nations[food_holder_before], transferred_food
		)
		var target_food_holder := food_pool_holder(target_id)
		if withdrawn_food > 0 and deposit_food(target_id, withdrawn_food):
			nations[food_holder_before].granary_food -= withdrawn_food
			nations[target_food_holder].granary_food += withdrawn_food
	for army in armies:
		if (
			army.owner_nation == parent_id
			and army.state in [Army.State.IDLE, Army.State.RECOVERING]
			and not army.on_edge and allowed.has(army.location_city)
		):
			army.owner_nation = target_id
			army.battle_group_id = -1
			if army.max_size >= INITIAL_HEAVY_ARMY_SIZE:
				var target_group := create_battle_group(target_id)
				assign_army_to_battle_group(army, target_group.id)
			else:
				army.strategic_role = Army.StrategicRole.LINE
			army.clear_line_assignment()
	parent.last_rebellion_day = day
	target.last_rebellion_day = day
	return true


func recognize_regional_rebellion(rebel_id: int) -> bool:
	if not rebellions.has(rebel_id):
		return false
	var record: Dictionary = rebellions[rebel_id]
	if not bool(record.get("active", false)):
		return false
	var operations: Array[Dictionary] = []
	for city_value in record.get("core_city_ids", []):
		var city_id := int(city_value)
		if city_id < 0 or city_id >= cities.size():
			continue
		if cities[city_id].owner_nation == rebel_id:
			operations.append({
				"city_id": city_id,
				"legal_owner_id": rebel_id,
				"reset_political_target": true,
				"stock_policy": TerritoryStockDisposition.RETURN_TO_OLD_POOL,
				"reason": "regional_rebellion_recognized",
			})
	var changed := false
	if not operations.is_empty():
		var territory_result := apply_territory_transaction(operations)
		if not bool(territory_result.get("ok", false)):
			return false
		changed = bool(territory_result.get("changed", false))
	record["recognized"] = true
	record["active"] = false
	rebellions[rebel_id] = record
	return changed


func suppress_regional_rebellion(rebel_id: int) -> bool:
	if not rebellions.has(rebel_id):
		return false
	var record: Dictionary = rebellions[rebel_id]
	if not bool(record.get("active", false)):
		return false
	var parent_id := int(record.get("parent_id", -1))
	if parent_id < 0 or parent_id >= nations.size():
		return false
	if not annex_nation(parent_id, rebel_id):
		return false
	set_diplomatic_relation(
		parent_id, rebel_id, DiplomaticRelation.NEUTRAL, DEFAULT_TRUCE_DAYS
	)
	record["active"] = false
	record["recognized"] = false
	rebellions[rebel_id] = record
	for city_value in record.get("core_city_ids", []):
		var city_id := int(city_value)
		if city_id >= 0 and city_id < cities.size():
			cities[city_id].loyalty_target_nation = parent_id
			cities[city_id].loyalty = 45.0
			cities[city_id].rebellion_progress = 0
			cities[city_id].rebellion_cooldown_until_day = (
				day + RebellionSystem.REBELLION_COOLDOWN_DAYS
			)
	return true


func prune_rebellions() -> bool:
	var changed := false
	for rebel_value in rebellions.keys():
		var rebel_id := int(rebel_value)
		var record: Dictionary = rebellions[rebel_id]
		if not bool(record.get("active", false)):
			continue
		var parent_id := int(record.get("parent_id", -1))
		var rebel_alive := (
			rebel_id >= 0 and rebel_id < nations.size()
			and nations[rebel_id].alive
		)
		var parent_alive := (
			parent_id >= 0 and parent_id < nations.size()
			and nations[parent_id].alive
		)
		if not rebel_alive:
			record["active"] = false
			rebellions[rebel_id] = record
			changed = true
		elif not parent_alive:
			changed = recognize_regional_rebellion(rebel_id) or changed
	return changed


## 地方叛乱战争在双方停战时结算：叛军仍持有任一核心城市即获得承认，
## 否则视为被镇压。削藩内战不进入此表，继续由原首都通吃规则处理。
func resolve_rebellion_peace(nation_a: int, nation_b: int) -> bool:
	var rebel_id := -1
	for candidate in [nation_a, nation_b]:
		if (
			rebellions.has(candidate)
			and bool((rebellions[candidate] as Dictionary).get("active", false))
		):
			rebel_id = candidate
			break
	if rebel_id < 0:
		return false
	var record: Dictionary = rebellions[rebel_id]
	var parent_id := int(record.get("parent_id", -1))
	if parent_id not in [nation_a, nation_b]:
		return false
	var controls_core := false
	for city_value in record.get("core_city_ids", []):
		var city_id := int(city_value)
		if city_id >= 0 and city_id < cities.size() and cities[city_id].owner_nation == rebel_id:
			controls_core = true
			break
	return (
		recognize_regional_rebellion(rebel_id)
		if controls_core
		else suppress_regional_rebellion(rebel_id)
	)


func rebellion_structure_valid() -> bool:
	for rebel_value in rebellions:
		var rebel_id := int(rebel_value)
		var record: Dictionary = rebellions[rebel_id]
		var parent_id := int(record.get("parent_id", -1))
		if (
			rebel_id < 0 or rebel_id >= nations.size()
			or parent_id < 0 or parent_id >= nations.size()
			or rebel_id == parent_id
		):
			return false
		if bool(record.get("active", false)):
			if not nations[rebel_id].alive or not is_enemy(rebel_id, parent_id):
				return false
			for city_value in record.get("core_city_ids", []):
				var city_id := int(city_value)
				if city_id < 0 or city_id >= cities.size():
					return false
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


## 查询一次分封会地方化的宗主 LINE。只认封地城市内的稳定驻军，以及从封地端
## 驻守外部边界的 HOLDING；供 AI 反事实财政评估与实际转移共用，避免预测漂移。
func transferable_vassal_line_armies(
	overlord_id: int,
	fief_city_ids: Array[int]
) -> Array[Army]:
	var result: Array[Army] = []
	if (
		overlord_id < 0
		or overlord_id >= nations.size()
		or fief_city_ids.is_empty()
	):
		return result
	var fief := {}
	for city_id in fief_city_ids:
		if city_id >= 0 and city_id < cities.size():
			fief[city_id] = true
	for army in armies:
		if (
			army.owner_nation != overlord_id
			or army.size <= 0
			or not army.is_line_role()
			or army.battle_group_id >= 0
		):
			continue
		var stationed_in_fief := (
			not army.on_edge
			and army.state in [
				Army.State.IDLE,
				Army.State.RECOVERING,
			]
			and fief.has(army.current_city_node())
		)
		var holding_fief_border := (
			army.on_edge
			and army.state == Army.State.HOLDING
			and fief.has(army.move_from)
		)
		if stationed_in_fief or holding_fief_border:
			result.append(army)
	result.sort_custom(func(a: Army, b: Army) -> bool:
		return a.id < b.id
	)
	return result


## 分封驻军地方化：先把稳定驻扎在封地城市、或从封地端驻守外部边界的宗主 LINE
## 转给藩王，再凭空补足到「封地陆城数」。正在行军/交战/撤退的 LINE 与全部 MAIN
## 仍归宗主，避免政治重组改写进行中的状态机或拆散持久战团。
func _grant_vassal_line_armies(
	subject_id: int,
	overlord_id: int
) -> void:
	if (
		subject_id < 0
		or subject_id >= nations.size()
		or overlord_id < 0
		or overlord_id >= nations.size()
	):
		return
	var owned := land_cities_of(subject_id)
	if owned.is_empty():
		return
	var fief_city_ids: Array[int] = []
	for city in owned:
		fief_city_ids.append(city.id)
	var overlord := nations[overlord_id]
	for army in transferable_vassal_line_armies(
		overlord_id,
		fief_city_ids
	):
		army.owner_nation = subject_id
		army.clear_line_assignment()
		army.ai_action = ActionCandidate.Kind.NONE
		army.ai_target_city = -1
		army.ai_order_created_day = -1
		army.ai_order_until_day = -1
		army.ai_order_score = 0.0
		army.ai_order_reason = ""
		army.defensive_deployment_until_day = -1
		army.defensive_blocked_edge_a = -1
		army.defensive_blocked_edge_b = -1
		army.offensive_attack_multiplier = 1.0
		army.offensive_bonus_until_day = -1
		army.occupation_claimant_nation = -1
		army.diplomatic_repatriation = false
		overlord.campaign_preparation_assignments.erase(
			army.id
		)
		overlord.campaign_attack_assignments.erase(army.id)
		overlord.campaign_attack_echelons.erase(army.id)
		overlord.campaign_launched_armies.erase(army.id)
	var target := owned.size()
	# 只按 LINE 计数；藩王未来已有 MAIN 时也不得挤占地方防务配额。
	var existing := 0
	for army in armies:
		if (
			army.owner_nation == subject_id
			and army.size > 0
			and army.is_line_role()
		):
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
	var proposed := suzerainty.duplicate(true)
	(proposed[subject_id] as Dictionary)["civil_war"] = false
	var operations: Array[Dictionary] = []
	# 预先收集内战临时占领，与粮池合并及政治边在同一次事务提交。
	for city in cities:
		var legal_owner := recognized_owner_of(city.id)
		if (
			city.owner_nation == legal_owner
			or city.owner_nation not in [subject_id, overlord_id]
			or legal_owner not in [subject_id, overlord_id]
			or city.occupation_sponsor_nation != city.owner_nation
		):
			continue
		operations.append({
			"city_id": city.id,
			"controller_id": legal_owner,
			"legal_owner_id": legal_owner,
			"sponsor_id": -1,
			"reset_political_target": true,
			"reason": "civil_war_ended",
			"stock_policy": TerritoryStockDisposition.MOVE_TO_NEW_POOL,
		})
	var result := apply_territory_transaction(
		operations, {}, -1, proposed
	)
	if not bool(result.get("ok", false)):
		return false
	return true


## 沿宗主链上溯到的最终宗主（自身不是藩王时返回自身）。含环保护。
func suzerainty_root(nation_id: int) -> int:
	var current := nation_id
	var guard := 0
	while suzerainty.has(current) and guard <= nations.size():
		current = int(suzerainty[current]["overlord_id"])
		guard += 1
	return current


## 对外战争中新取得领土的主权接收者。和平宗藩没有独立议和权，故沿非内战
## 宗藩链上溯到当前主权方；削藩内战边在政治上已经断开，反叛方及其和平子树
## 以反叛方为接收者。死亡或非法宗主不会获得新领土，避免悬空记录复活死国。
func external_territory_recipient(nation_id: int) -> int:
	if nation_id < 0 or nation_id >= nations.size():
		return -1
	var current := nation_id
	var guard := 0
	while (
		suzerainty.has(current)
		and not is_in_civil_war(current)
		and guard <= nations.size()
	):
		var overlord_id := overlord_of(current)
		if (
			overlord_id < 0
			or overlord_id >= nations.size()
			or cities_of(overlord_id).is_empty()
		):
			break
		current = overlord_id
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
	# 运行时缺失法理数组属于损坏状态，不能把当前实控静默洗成法理。
	if recognized_city_owners.size() != cities.size():
		push_error("清理死亡宗藩失败：法理领土索引与城市数量不一致。")
		return false
	var final_city_counts: Array[int] = []
	final_city_counts.resize(nations.size())
	final_city_counts.fill(0)
	for city in cities:
		if (
			city.owner_nation >= 0
			and city.owner_nation < nations.size()
			and nations[city.owner_nation].alive
		):
			final_city_counts[city.owner_nation] += 1
	var proposed := _normalized_suzerainty_for_city_counts(
		suzerainty, final_city_counts
	)
	if proposed == suzerainty:
		return false
	var operations: Array[Dictionary] = []
	var promoted: Array[int] = []
	for subject_value in suzerainty:
		var subject_id := int(subject_value)
		if final_city_counts[subject_id] <= 0:
			continue
		if not proposed.has(subject_id):
			promoted.append(subject_id)
			continue
	# 灭亡藩王的法理在同一事务交给最近的存活祖先；sponsor 若指向
	# 死亡节点也同步转移，避免 phase 2 留下无效战争责任方。
	for city in cities:
		var former_id := recognized_owner_of(city.id)
		if (
			former_id < 0 or former_id >= nations.size()
			or final_city_counts[former_id] > 0
			or not suzerainty.has(former_id)
		):
			continue
		var successor := int(
			(suzerainty[former_id] as Dictionary)["overlord_id"]
		)
		var guard := 0
		while (
			successor >= 0
			and successor < nations.size()
			and final_city_counts[successor] <= 0
			and suzerainty.has(successor)
			and guard <= nations.size()
		):
			successor = int(
				(suzerainty[successor] as Dictionary)["overlord_id"]
			)
			guard += 1
		if successor < 0 or successor >= nations.size():
			continue
		var sponsor := city.occupation_sponsor_nation
		if sponsor == former_id:
			sponsor = successor
		if city.owner_nation == successor:
			sponsor = -1
		operations.append({
			"city_id": city.id,
			"legal_owner_id": successor,
			"sponsor_id": sponsor,
			"reset_political_target": true,
			"stock_policy": TerritoryStockDisposition.RETURN_TO_OLD_POOL,
			"reason": "recognized_territory_inherited",
		})
	var result := apply_territory_transaction(
		operations, {}, -1, proposed
	)
	if not bool(result.get("ok", false)):
		return false
	for nation_id in promoted:
		WorldNaming.promote_vassal_to_sovereign(self, nation_id)
	return true


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
	# 藩王首都只作零库存补给中继节点，由领土事务统一建立，不切分库存。

	# 2. 建新藩王 Nation（完整实体，色调随宗主派生以体现同一政治共同体）。
	var subject := Nation.new()
	subject.id = nations.size()
	subject.color = _derive_vassal_color(overlord.color, subject.id)
	subject.alive = true
	subject.political_system = overlord.political_system
	subject.ai_aggression = 1.0
	if _random_ruler_profiles_enabled:
		RulerProfile.initialize_nation(
			subject, world_seed, subject.id + day * 31
		)
	else:
		# 网格世界是旧状态机/镜像夹具；未显式指定时新藩王同样保持中性。
		subject.ruler_archetype = RulerProfile.BALANCED
		subject.ruler_traits.clear()
		subject.trade_policy = RulerProfile.POLICY_BALANCED
	subject.ruler_started_day = day
	nations.append(subject)

	# 3. 不预写 live 图；完整拟议图与封地迁移由同一事务提交。
	var proposed_suzerainty := suzerainty.duplicate(true)
	proposed_suzerainty[subject.id] = {
		"overlord_id": overlord_id,
		"tribute_rate": clampf(tribute_rate, 0.0, 1.0),
		"created_day": day,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	var region_centroid := Vector2.ZERO
	for city_id in city_ids:
		region_centroid += cities[city_id].map_position
	region_centroid /= float(city_ids.size())
	var capital_id := city_ids[0]
	var capital_distance := INF
	for city_id in city_ids:
		var distance := cities[city_id].map_position.distance_squared_to(
			region_centroid
		)
		if distance < capital_distance or (
			is_equal_approx(distance, capital_distance)
			and EquivariantOrder.city_id_less(
				self, subject.id, city_id, capital_id
			)
		):
			capital_distance = distance
			capital_id = city_id
	var territory_operations: Array[Dictionary] = []
	for city_id in city_ids:
		territory_operations.append({
			"city_id": city_id,
			"controller_id": subject.id,
			"legal_owner_id": subject.id,
			"sponsor_id": -1,
			"reset_political_target": true,
			"stock_policy": TerritoryStockDisposition.RETURN_TO_OLD_POOL,
			"reason": "enfeoffment",
		})
	var territory_result := apply_territory_transaction(
		territory_operations, {subject.id: capital_id}, -1,
		proposed_suzerainty
	)
	if not bool(territory_result.get("ok", false)):
		nations.pop_back()
		return -1

	# 3.5 军队归属在第 5.5 步统一处理：封地内稳定驻防的 LINE 地方化并补齐，
	#     MAIN 战团与在途 LINE 继续归中央。

	# 4. 划转人力与金钱（守恒：从宗主池扣除、注入藩王池）。
	overlord.manpower_pool -= granted_manpower
	subject.manpower_pool = granted_manpower
	overlord.treasury_gold -= granted_gold
	subject.treasury_gold = granted_gold

	# 5. 首都、零库存中继与封地存粮回流已由领土事务统一完成。
	WorldNaming.assign_vassal_name(self, subject.id, city_ids)

	# 5.5 地方化驻军并补齐：先转移封地内稳定驻防的宗主 LINE，再把缺口凭空补到
	#     「陆城数」；MAIN 不转移、不凭空赐予，由藩王后续按经济能力自行组建。
	_grant_vassal_line_armies(subject.id, overlord_id)

	# 6. 外交：藩王继承宗主对每个第三方的关系，并与宗主结盟。
	#    这样 alliance_bloc 天然把宗藩聚为一体，对外 is_enemy 自动正确，
	#    且不会因缺省 key 让新藩王与未建交国凭空开战（relation_between 缺省=WAR）。
	_inherit_overlord_diplomacy(overlord_id, subject.id)

	# 7. 宗藩关系已在领土事务前写入，以参与最终粮池规划。
	for city_id in city_ids:
		var granted_city := cities[city_id]
		granted_city.loyalty_target_nation = subject.id
		granted_city.loyalty = maxf(granted_city.loyalty, 68.0)
		granted_city.loyalty_trend = 0.0
		granted_city.unrest = 100.0 - granted_city.loyalty
		granted_city.rebellion_progress = 0

	assert(
		suzerainty_structure_valid(),
		"分封后宗藩结构不变量必须成立"
	)
	assert(
		_battle_group_structure_valid(),
		"分封迁移军队后战团结构不变量必须成立"
	)
	return subject.id


## 把一次兼并追加到现有虚拟领土计划。draft 的五个字段均是完整快照：
## owners / legal / sponsors 为逐城最终值，operation_by_city 以 city_id 去重，
## proposed_suzerainty 为完整拟议宗藩图。函数只在全部校验与合成成功后替换
## draft 字段，因此失败不会留下半份兼并计划。
func append_annexation_to_territory_plan(
	draft: Dictionary,
	absorber: int,
	absorbed: int,
	stock_policy_overrides: Dictionary = {}
) -> bool:
	if (
		absorber < 0 or absorber >= nations.size()
		or absorbed < 0 or absorbed >= nations.size()
		or absorber == absorbed
		or not draft.has("owners")
		or not draft.has("legal")
		or not draft.has("sponsors")
		or not draft.has("operation_by_city")
		or not draft.has("proposed_suzerainty")
		or typeof(draft["owners"]) != TYPE_ARRAY
		or typeof(draft["legal"]) != TYPE_ARRAY
		or typeof(draft["sponsors"]) != TYPE_ARRAY
		or typeof(draft["operation_by_city"]) != TYPE_DICTIONARY
		or typeof(draft["proposed_suzerainty"]) != TYPE_DICTIONARY
	):
		return false
	var owner_values: Array = draft["owners"]
	var legal_values: Array = draft["legal"]
	var sponsor_values: Array = draft["sponsors"]
	if (
		owner_values.size() != cities.size()
		or legal_values.size() != cities.size()
		or sponsor_values.size() != cities.size()
	):
		return false
	for city_id in range(cities.size()):
		if (
			typeof(owner_values[city_id]) != TYPE_INT
			or typeof(legal_values[city_id]) != TYPE_INT
			or typeof(sponsor_values[city_id]) != TYPE_INT
		):
			return false
	var planned_owners: Array[int] = []
	var planned_legal: Array[int] = []
	var planned_sponsors: Array[int] = []
	planned_owners.assign(owner_values)
	planned_legal.assign(legal_values)
	planned_sponsors.assign(sponsor_values)
	var operation_by_city: Dictionary = (
		(draft["operation_by_city"] as Dictionary).duplicate(true)
	)
	var suzerainty_validation := _validated_suzerainty_snapshot(
		draft["proposed_suzerainty"] as Dictionary
	)
	if not bool(suzerainty_validation.get("ok", false)):
		return false
	var proposed_suzerainty: Dictionary = (
		suzerainty_validation["snapshot"] as Dictionary
	)

	# override 只对虚拟快照中仍由 absorbed 实控的城市有意义。
	for city_value in stock_policy_overrides:
		if typeof(city_value) != TYPE_INT:
			return false
		var city_id := int(city_value)
		var policy_value: Variant = stock_policy_overrides[city_value]
		if (
			city_id < 0
			or city_id >= cities.size()
			or cities[city_id].owner_nation != absorbed
			or typeof(policy_value) != TYPE_INT
			or int(policy_value) not in [
				TerritoryStockDisposition.RETURN_TO_OLD_POOL,
				TerritoryStockDisposition.MOVE_TO_NEW_POOL,
				TerritoryStockDisposition.CAPTURE_SPOILS,
				TerritoryStockDisposition.DESTROY,
			]
		):
			return false

	# 若胜者原是败方藩属，先解除该边；败方的其他直接藩属改挂胜者。
	if (
		proposed_suzerainty.has(absorber)
		and int((proposed_suzerainty[absorber] as Dictionary).get(
			"overlord_id", -1
		)) == absorbed
	):
		proposed_suzerainty.erase(absorber)
	var absorbed_children: Array[int] = []
	for subject_value in proposed_suzerainty:
		var subject_id := int(subject_value)
		if (
			subject_id != absorber
			and int((proposed_suzerainty[subject_id] as Dictionary).get(
				"overlord_id", -1
			)) == absorbed
		):
			absorbed_children.append(subject_id)
	for child_id in absorbed_children:
		(proposed_suzerainty[child_id] as Dictionary)["overlord_id"] = absorber
		(proposed_suzerainty[child_id] as Dictionary)["civil_war"] = false
	proposed_suzerainty.erase(absorbed)
	if not bool(_validated_suzerainty_snapshot(
		proposed_suzerainty
	).get("ok", false)):
		return false

	# 所有判断都读取 draft 的虚拟快照；同一城市只覆盖一条最终 operation。
	for city_id in range(cities.size()):
		var controlled_by_absorbed := planned_owners[city_id] == absorbed
		var legally_absorbed := planned_legal[city_id] == absorbed
		var sponsored_by_absorbed := planned_sponsors[city_id] == absorbed
		if not (
			controlled_by_absorbed
			or legally_absorbed
			or sponsored_by_absorbed
			or stock_policy_overrides.has(city_id)
		):
			continue
		var controller := absorber if controlled_by_absorbed else planned_owners[city_id]
		var legal_owner := absorber if legally_absorbed else planned_legal[city_id]
		var sponsor := absorber if sponsored_by_absorbed else planned_sponsors[city_id]
		if controller == legal_owner:
			sponsor = -1
		var operation: Dictionary = {}
		if operation_by_city.has(city_id):
			if typeof(operation_by_city[city_id]) != TYPE_DICTIONARY:
				return false
			operation = (operation_by_city[city_id] as Dictionary).duplicate(true)
		operation["city_id"] = city_id
		operation["controller_id"] = controller
		operation["legal_owner_id"] = legal_owner
		operation["sponsor_id"] = sponsor
		operation["reset_political_target"] = (
			bool(operation.get("reset_political_target", false))
			or legally_absorbed
		)
		operation["reason"] = "annexation"
		if stock_policy_overrides.has(city_id):
			# override 针对事务开始时由 absorbed 实控的库存；即使前序
			# draft 已先规划攻占该城，也必须覆盖已有 capture policy。
			operation["stock_policy"] = int(
				stock_policy_overrides[city_id]
			)
		elif not operation.has("stock_policy"):
			operation["stock_policy"] = (
				TerritoryStockDisposition.MOVE_TO_NEW_POOL
			)
		operation_by_city[city_id] = operation
		planned_owners[city_id] = controller
		planned_legal[city_id] = legal_owner
		planned_sponsors[city_id] = sponsor

	var absorber_has_city := false
	for owner_id in planned_owners:
		if owner_id == absorber:
			absorber_has_city = true
			break
	if not absorber_has_city:
		return false
	draft["owners"] = planned_owners
	draft["legal"] = planned_legal
	draft["sponsors"] = planned_sponsors
	draft["operation_by_city"] = operation_by_city
	draft["proposed_suzerainty"] = proposed_suzerainty
	return true


## 领土提交成功后的兼并收尾。这里只迁移无独立失败条件的军队、战团与资源；
## 城市、宗藩、首都、粮仓和库存已由 apply_territory_transaction 一次提交。
func finalize_annexation_after_territory_commit(
	absorber: int,
	absorbed: int
) -> void:
	if (
		absorber < 0 or absorber >= nations.size()
		or absorbed < 0 or absorbed >= nations.size()
		or absorber == absorbed
	):
		return
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
		if army.occupation_claimant_nation == absorbed:
			army.occupation_claimant_nation = absorber
		if army.owner_nation == absorber:
			army.ruler_defense_multiplier = (
				RulerProfile.defense_multiplier(nations[absorber])
			)
			army.ruler_morale_multiplier = (
				RulerProfile.morale_multiplier(nations[absorber])
			)
	_reconcile_battles_after_annexation()
	nations[absorber].manpower_pool += nations[absorbed].manpower_pool
	nations[absorbed].manpower_pool = 0
	nations[absorber].treasury_gold += nations[absorbed].treasury_gold
	nations[absorbed].treasury_gold = 0


## 把 absorbed 国的全部领土、军队、战团、资源并入 absorber 国。普通兼并与
## 集团和平中的叛乱镇压共用同一 planner/finalizer，避免两套语义漂移。
func annex_nation(
	absorber: int,
	absorbed: int,
	expected_ownership_revision: int = -1,
	stock_policy_overrides: Dictionary = {}
) -> bool:
	var owners: Array[int] = []
	var legal: Array[int] = []
	var sponsors: Array[int] = []
	owners.resize(cities.size())
	legal.resize(cities.size())
	sponsors.resize(cities.size())
	for city in cities:
		owners[city.id] = city.owner_nation
		legal[city.id] = recognized_owner_of(city.id)
		sponsors[city.id] = city.occupation_sponsor_nation
	var draft := {
		"owners": owners,
		"legal": legal,
		"sponsors": sponsors,
		"operation_by_city": {},
		"proposed_suzerainty": suzerainty.duplicate(true),
	}
	if not append_annexation_to_territory_plan(
		draft, absorber, absorbed, stock_policy_overrides
	):
		return false
	var operation_ids: Array[int] = []
	for city_value in (draft["operation_by_city"] as Dictionary):
		operation_ids.append(int(city_value))
	operation_ids.sort()
	var operations: Array[Dictionary] = []
	for city_id in operation_ids:
		operations.append(
			(draft["operation_by_city"] as Dictionary)[city_id]
		)
	var territory_result := apply_territory_transaction(
		operations, {}, expected_ownership_revision,
		draft["proposed_suzerainty"]
	)
	if not bool(territory_result.get("ok", false)):
		return false
	finalize_annexation_after_territory_commit(absorber, absorbed)
	return true


## 兼并可能让原战斗双方变成同国或不再敌对。Battle 持有 Army 引用，因此必须在
## owner 迁移的同一事务中解除这类战斗，不能留到下一回合继续互相造成伤亡。
func _reconcile_battles_after_annexation() -> void:
	for battle in battles:
		if battle.finished:
			continue
		battle.prune_dead()
		if battle.kind == Battle.Kind.SIEGE and not battle.side_a.is_empty():
			var besieger_nation := battle.side_a[0].owner_nation
			var merged: Array[Army] = []
			for army in battle.side_b:
				if army.owner_nation == besieger_nation:
					if not battle.side_a.has(army):
						battle.side_a.append(army)
					merged.append(army)
			for army in merged:
				battle.side_b.erase(army)
				battle.reinforce_fresh_b.erase(army)
				battle.routed_b.erase(army)
				battle.frontline_priority_b.erase(army)
			if battle.side_b.is_empty():
				battle.has_garrison = false
				battle.reinforce_fresh_b.clear()
				battle.routed_b.clear()
				battle.frontline_priority_b.clear()
				battle.reinforcement_morale_gained_b = 0.0
				battle.tactical_key_b = 0
		if _battle_has_hostile_sides(battle):
			continue
		for army in battle.side_a + battle.side_b:
			army.battle_id = -1
			if army.state != Army.State.FIGHTING:
				continue
			army.state = (
				Army.State.MOVING
				if army.on_edge and army.move_to != -1
				else Army.State.IDLE
			)
		battle.finished = true
		battle.winner_side = 0


func _battle_has_hostile_sides(battle: Battle) -> bool:
	for army_a in battle.side_a:
		if army_a.size <= 0:
			continue
		for army_b in battle.side_b:
			if (
				army_b.size > 0
				and is_enemy(
					army_a.owner_nation,
					army_b.owner_nation
				)
			):
				return true
	if battle.kind == Battle.Kind.SIEGE and battle.city != null:
		for besieger in battle.side_a:
			if (
				besieger.size > 0
				and is_enemy(
					besieger.owner_nation,
					battle.city.owner_nation
				)
			):
				return true
	return false


## 和平撤藩：宗主直接吸收藩王全境，宗藩记录移除。返回是否成功。
## 用于藩王面对削藩选择不反抗（军力悬殊）时的和平收场。
func revoke_vassal(subject_id: int) -> bool:
	if not suzerainty.has(subject_id):
		return false
	var overlord_id := int(suzerainty[subject_id]["overlord_id"])
	if overlord_id < 0 or overlord_id >= nations.size():
		return false
	# 兼并原语会原子移除 subject 并把其直接藩王改投宗主。
	if not annex_nation(overlord_id, subject_id):
		return false
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


## 分封合法性：宗主有效存活、区域非空且全部属于宗主实控与法理、不含宗主首都、
## 不得清空宗主陆地领土；传入区域必须已经包含其造成的全部直辖飞地。临时占领地
## 不能通过分封直接洗成新藩王法理，必须先由议和确认归宗主。
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
			or recognized_owner_of(city_id) != overlord_id
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


## 按确定性粮仓顺序扣除最多 amount 单位粮食，并返回实际扣除量。
## requested 不超过总库存时必须精确扣足；超出时扣尽现有库存。
func _withdraw_food_from_warehouses(overlord: Nation, amount: int) -> int:
	if overlord == null or amount <= 0:
		return 0
	var warehouses := warehouse_cities_of(overlord.id)
	var total := 0
	for warehouse in warehouses:
		total += warehouse.food_storage
	if total <= 0:
		return 0
	var remaining := mini(amount, total)
	var requested := remaining
	for warehouse in warehouses:
		if remaining <= 0:
			break
		var take := mini(remaining, warehouse.food_storage)
		warehouse.food_storage -= take
		remaining -= take
	# granary_food 是派生量，由 refresh_derived 统一重算，此处不手改。
	return requested - remaining


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
	return Color.from_hsv(
		h,
		clampf(s + 0.10, NATION_COLOR_SATURATION_MIN, NATION_COLOR_SATURATION_MAX),
		clampf(v * 0.85, 0.28, NATION_COLOR_VALUE_MAX)
	)


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


## 地方叛军只继承母国已有的战争与中立关系，不继承母国盟约。母国盟友对新叛军
## 默认为中立，避免叛军一出生便借第三方盟友重新落入母国的联盟集团。
func _inherit_rebel_diplomacy(parent_id: int, rebel_id: int) -> void:
	for third in nations:
		if third.id == rebel_id or third.id == parent_id:
			continue
		var inherited := relation_between(parent_id, third.id)
		if inherited == DiplomaticRelation.ALLIED:
			inherited = DiplomaticRelation.NEUTRAL
		set_diplomatic_relation(rebel_id, third.id, inherited)


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


## 按事务最终实控图选择确定性首都。已有首都仍合法时保持不动；需要修复时，
## 复用迁都规则：优先最大陆地连通分量，再取工事最强城市。
func _planned_territory_capital(
	nation_id: int,
	planned_owners: Array[int],
	preferred_city_id: int = -1
) -> int:
	if (
		nation_id < 0
		or nation_id >= nations.size()
		or planned_owners.size() != cities.size()
	):
		return -1
	if (
		preferred_city_id >= 0
		and preferred_city_id < cities.size()
		and planned_owners[preferred_city_id] == nation_id
	):
		return preferred_city_id
	var current := nations[nation_id].capital_city_id
	if (
		current >= 0
		and current < cities.size()
		and planned_owners[current] == nation_id
	):
		return current
	var candidates: Array[int] = []
	for city in cities:
		if planned_owners[city.id] == nation_id and not city.is_dock:
			candidates.append(city.id)
	if candidates.is_empty():
		for city in cities:
			if planned_owners[city.id] == nation_id:
				candidates.append(city.id)
	if candidates.is_empty():
		return -1
	var candidate_set := {}
	for city_id in candidates:
		candidate_set[city_id] = true
	var visited := {}
	var best_component: Array[int] = []
	var best_rep := -1
	for city_id in candidates:
		if visited.has(city_id):
			continue
		var component: Array[int] = []
		var queue: Array[int] = [city_id]
		var cursor := 0
		var representative := city_id
		visited[city_id] = true
		while cursor < queue.size():
			var current_id := queue[cursor]
			cursor += 1
			component.append(current_id)
			representative = mini(representative, current_id)
			for neighbor in neighbors(current_id):
				if visited.has(neighbor) or not candidate_set.has(neighbor):
					continue
				var edge := edge_of(current_id, neighbor)
				if edge == null or edge.max_manpower <= 0:
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		if (
			component.size() > best_component.size()
			or (
				component.size() == best_component.size()
				and (best_rep < 0 or representative < best_rep)
			)
		):
			best_component = component
			best_rep = representative
	var best := best_component[0]
	for city_id in best_component:
		if (
			cities[city_id].fort_strength > cities[best].fort_strength
			or (
				cities[city_id].fort_strength == cities[best].fort_strength
				and EquivariantOrder.city_id_less(
					self, nation_id, city_id, best
				)
			)
		):
			best = city_id
	return best


## 规范化一份任意宗藩快照。事务只能接收完整最终图，不能让调用方通过提前
## 修改 live suzerainty 来影响规划。这里同时把 key 统一为 int 并拒绝环。
## validate_relations 只用于对 live 快照作一致性检查；拟议图的对应外交变化由
## 生命周期调用方在事务成功后无失败地落盘，不能用旧外交关系拒绝合法改图。
func _validated_suzerainty_snapshot(
	snapshot: Dictionary,
	validate_relations: bool = false
) -> Dictionary:
	var normalized := {}
	for subject_value in snapshot:
		if typeof(subject_value) != TYPE_INT:
			return {"ok": false, "error": "宗藩图包含非整数国家 id。"}
		var subject_id := int(subject_value)
		var record_value: Variant = snapshot[subject_value]
		if (
			subject_id < 0
			or subject_id >= nations.size()
			or typeof(record_value) != TYPE_DICTIONARY
		):
			return {"ok": false, "error": "宗藩图包含无效藩属记录。"}
		var record: Dictionary = record_value
		if not record.has("overlord_id"):
			return {"ok": false, "error": "宗藩记录缺少宗主 id。"}
		var overlord_id := int(record["overlord_id"])
		if (
			overlord_id < 0
			or overlord_id >= nations.size()
			or overlord_id == subject_id
		):
			return {"ok": false, "error": "宗藩图包含无效宗主。"}
		normalized[subject_id] = record.duplicate(true)
		if validate_relations:
			var expected_relation := (
				DiplomaticRelation.WAR
				if bool(record.get("civil_war", false))
				else DiplomaticRelation.ALLIED
			)
			if relation_between(subject_id, overlord_id) != expected_relation:
				return {
					"ok": false,
					"error": "现有宗藩图与外交关系不一致。",
				}
	for subject_value in normalized:
		var subject_id := int(subject_value)
		var walker := subject_id
		var seen := {}
		while normalized.has(walker):
			if seen.has(walker):
				return {"ok": false, "error": "宗藩图不能包含环。"}
			seen[walker] = true
			walker = int((normalized[walker] as Dictionary)["overlord_id"])
	return {"ok": true, "error": "", "snapshot": normalized}


## 根据最终有城国家集合一次性跳过死亡宗主、删除死亡藩属。跨过死亡节点的
## 新边不继承旧内战；它是死亡清理后与存活祖先建立的新和平宗藩边。
func _normalized_suzerainty_for_city_counts(
	snapshot: Dictionary,
	final_city_counts: Array[int]
) -> Dictionary:
	var result := {}
	for subject_value in snapshot:
		var subject_id := int(subject_value)
		if final_city_counts[subject_id] <= 0:
			continue
		var record: Dictionary = snapshot[subject_id]
		var overlord_id := int(record["overlord_id"])
		var skipped_dead := false
		var guard := 0
		while (
			overlord_id >= 0
			and overlord_id < nations.size()
			and final_city_counts[overlord_id] <= 0
			and snapshot.has(overlord_id)
			and guard <= nations.size()
		):
			overlord_id = int(
				(snapshot[overlord_id] as Dictionary)["overlord_id"]
			)
			skipped_dead = true
			guard += 1
		if (
			overlord_id < 0
			or overlord_id >= nations.size()
			or final_city_counts[overlord_id] <= 0
			or overlord_id == subject_id
		):
			continue
		var final_record := record.duplicate(true)
		final_record["overlord_id"] = overlord_id
		if skipped_dead:
			final_record["civil_war"] = false
		result[subject_id] = final_record
	return result


## 按最终有城国家集合及任意宗藩快照解析粮池持有者。若宗主在本批失去
## 最后一城，跳过死亡宗主并接到仍存活的祖先；没有祖先时返回自身（自身
## 也死亡时返回 -1）。活节点上的内战边仍会截断共享关系。
func _planned_territory_food_pool_holder(
	nation_id: int,
	final_city_counts: Array[int],
	suzerainty_snapshot: Dictionary
) -> int:
	if (
		nation_id < 0
		or nation_id >= nations.size()
		or final_city_counts.size() != nations.size()
	):
		return -1
	var current := nation_id
	var holder := nation_id if final_city_counts[nation_id] > 0 else -1
	var guard := 0
	while suzerainty_snapshot.has(current) and guard <= nations.size():
		var record: Dictionary = suzerainty_snapshot[current]
		# 只有仍存活的子节点可以维持一条内战边；死亡中间节点会被 prune 掉。
		if (
			final_city_counts[current] > 0
			and bool(record.get("civil_war", false))
		):
			break
		var overlord_id := int(record.get("overlord_id", -1))
		if overlord_id < 0 or overlord_id >= nations.size():
			break
		if final_city_counts[overlord_id] > 0:
			holder = overlord_id
		current = overlord_id
		guard += 1
	return holder


## 运行期领土状态的唯一写入口。phase 1 只读旧快照并完整规划所有城市、政治
## 目标、首都、粮仓双向索引和库存账本；任一错误直接返回且没有副作用。phase 2
## 才一次提交整批结果，ownership_revision 与 refresh_derived 都只发生一次。
## operation 必须含 city_id；可含 controller_id、legal_owner_id、sponsor_id、
## reset_political_target、reason、stock_policy。另接受三个旧字段名别名。
## diplomatic_operations 每项必须含 nation_a、nation_b、relation，可选
## truce_days；显式外交边会和最终宗藩图要求的 WAR/ALLIED 边合并规划。
func apply_territory_transaction(
	operations: Array[Dictionary],
	preferred_capitals: Dictionary = {},
	expected_ownership_revision: int = -1,
	proposed_suzerainty: Variant = null,
	diplomatic_operations: Array[Dictionary] = [],
	expected_diplomacy_revision: int = -1
) -> Dictionary:
	# 乐观锁必须是入口第一项检查，冲突时连规划快照都不建立。
	if (
		expected_ownership_revision != -1
		and expected_ownership_revision != ownership_revision
	):
		return {
			"ok": false, "changed": false,
			"territory_changed": false,
			"political_changed": false,
			"diplomacy_changed": false,
			"error": "领土版本已变化，请重试。",
			"changed_city_ids": [] as Array[int],
		}
	if (
		expected_diplomacy_revision != -1
		and expected_diplomacy_revision != diplomacy_revision
	):
		return {
			"ok": false, "changed": false,
			"territory_changed": false,
			"political_changed": false,
			"diplomacy_changed": false,
			"error": "外交版本已变化，请重试。",
			"changed_city_ids": [] as Array[int],
		}
	if recognized_city_owners.size() != cities.size():
		return {
			"ok": false, "changed": false,
			"territory_changed": false,
			"political_changed": false,
			"diplomacy_changed": false,
			"error": "法理领土索引与城市数量不一致。",
			"changed_city_ids": [] as Array[int],
		}
	if (
		proposed_suzerainty != null
		and typeof(proposed_suzerainty) != TYPE_DICTIONARY
	):
		return {
			"ok": false, "changed": false,
			"territory_changed": false,
			"political_changed": false,
			"diplomacy_changed": false,
			"error": "proposed_suzerainty 必须是完整宗藩图。",
			"changed_city_ids": [] as Array[int],
		}

	# ------------------------------ phase 1a: 规范化并校验 operation。
	var planned_owners: Array[int] = []
	var planned_legal_owners: Array[int] = []
	var planned_sponsors: Array[int] = []
	planned_owners.resize(cities.size())
	planned_legal_owners.resize(cities.size())
	planned_sponsors.resize(cities.size())
	for city in cities:
		if (
			city.id < 0
			or city.id >= cities.size()
			or city.owner_nation < 0
			or city.owner_nation >= nations.size()
			or recognized_owner_of(city.id) < 0
			or recognized_owner_of(city.id) >= nations.size()
			or city.occupation_sponsor_nation < -1
			or city.occupation_sponsor_nation >= nations.size()
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "现有领土三元组包含无效国家。",
				"changed_city_ids": [] as Array[int],
			}
		planned_owners[city.id] = city.owner_nation
		planned_legal_owners[city.id] = recognized_owner_of(city.id)
		planned_sponsors[city.id] = city.occupation_sponsor_nation
	var normalized_operations: Array[Dictionary] = []
	var operation_by_city := {}
	var changed_city_ids: Array[int] = []
	for operation in operations:
		if not operation.has("city_id"):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "领土操作缺少 city_id。",
				"changed_city_ids": [] as Array[int],
			}
		var city_id := int(operation["city_id"])
		if (
			city_id < 0
			or city_id >= cities.size()
			or operation_by_city.has(city_id)
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "领土操作包含无效或重复城市。",
				"changed_city_ids": [] as Array[int],
			}
		var city := cities[city_id]
		var controller_id := city.owner_nation
		if operation.has("controller_id"):
			controller_id = int(operation["controller_id"])
		elif operation.has("owner_nation"):
			controller_id = int(operation["owner_nation"])
		var legal_owner_id := recognized_owner_of(city_id)
		if operation.has("legal_owner_id"):
			legal_owner_id = int(operation["legal_owner_id"])
		elif operation.has("legal_owner_nation"):
			legal_owner_id = int(operation["legal_owner_nation"])
		var sponsor_id := city.occupation_sponsor_nation
		if operation.has("sponsor_id"):
			sponsor_id = int(operation["sponsor_id"])
		elif operation.has("occupation_sponsor_nation"):
			sponsor_id = int(operation["occupation_sponsor_nation"])
		if (
			controller_id < 0
			or controller_id >= nations.size()
			or legal_owner_id < 0
			or legal_owner_id >= nations.size()
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "领土操作包含无效国家。",
				"changed_city_ids": [] as Array[int],
			}
		if controller_id == legal_owner_id:
			sponsor_id = -1
		elif sponsor_id < 0 or sponsor_id >= nations.size():
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "临时占领必须指定有效的战争结算责任方。",
				"changed_city_ids": [] as Array[int],
			}
		var stock_policy := int(operation.get(
			"stock_policy", TerritoryStockDisposition.RETURN_TO_OLD_POOL
		))
		if stock_policy not in [
			TerritoryStockDisposition.RETURN_TO_OLD_POOL,
			TerritoryStockDisposition.MOVE_TO_NEW_POOL,
			TerritoryStockDisposition.CAPTURE_SPOILS,
			TerritoryStockDisposition.DESTROY,
		]:
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "未知的领土库存结算策略。",
				"changed_city_ids": [] as Array[int],
			}
		var reset_target := bool(operation.get(
			"reset_political_target", false
		))
		var reason := str(operation.get("reason", "territory_transfer"))
		var cooldown_until := city.rebellion_cooldown_until_day
		if reset_target:
			cooldown_until = maxi(
				cooldown_until,
				day + RebellionSystem.REBELLION_COOLDOWN_DAYS
			)
		var operation_changed := (
			city.owner_nation != controller_id
			or recognized_owner_of(city_id) != legal_owner_id
			or city.occupation_sponsor_nation != sponsor_id
			or (
				reset_target
				and (
					city.loyalty_target_nation != legal_owner_id
					or not is_zero_approx(city.loyalty_trend)
					or city.unrest != 100.0 - city.loyalty
					or city.rebellion_progress != 0
					or city.rebellion_cooldown_until_day != cooldown_until
					or city.last_loyalty_reason != reason
				)
			)
		)
		var normalized := {
			"city_id": city_id,
			"controller_id": controller_id,
			"legal_owner_id": legal_owner_id,
			"sponsor_id": sponsor_id,
			"reset_political_target": reset_target,
			"cooldown_until": cooldown_until,
			"reason": reason,
			"stock_policy": stock_policy,
		}
		normalized_operations.append(normalized)
		operation_by_city[city_id] = normalized
		planned_owners[city_id] = controller_id
		planned_legal_owners[city_id] = legal_owner_id
		planned_sponsors[city_id] = sponsor_id
		if operation_changed:
			changed_city_ids.append(city_id)
	# operation 合成完后全量校验最终三元组；未触及城市也不得把历史脏值
	# 带进 phase 2，尤其不能在 refresh_derived 时才因非法 owner 崩溃。
	for city_id in range(cities.size()):
		var owner_id := planned_owners[city_id]
		var legal_id := planned_legal_owners[city_id]
		var sponsor_id := planned_sponsors[city_id]
		if (
			owner_id < 0 or owner_id >= nations.size()
			or legal_id < 0 or legal_id >= nations.size()
			or (owner_id == legal_id and sponsor_id != -1)
			or (
				owner_id != legal_id
				and (sponsor_id < 0 or sponsor_id >= nations.size())
			)
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "最终领土三元组无效。",
				"changed_city_ids": [] as Array[int],
			}
	# ------------------------------ phase 1b: 最终三元组、首都、粮池。
	var final_city_counts: Array[int] = []
	final_city_counts.resize(nations.size())
	final_city_counts.fill(0)
	for city_id in range(cities.size()):
		var owner := planned_owners[city_id]
		# 旧测试夹具及存档可能含与本批无关的历史脏 sponsor；原子事务只
		# 拒绝本批 operation 的非法最终值，不能让无关城市阻断合法占领。
		if owner >= 0 and owner < nations.size():
			final_city_counts[owner] += 1
	var requested_suzerainty := (
		(proposed_suzerainty as Dictionary).duplicate(true)
		if proposed_suzerainty != null
		else suzerainty.duplicate(true)
	)
	var suzerainty_validation := _validated_suzerainty_snapshot(
		requested_suzerainty
	)
	if not bool(suzerainty_validation.get("ok", false)):
		return {
			"ok": false, "changed": false,
			"territory_changed": false,
			"political_changed": false,
			"diplomacy_changed": false,
			"error": str(suzerainty_validation.get("error", "宗藩图无效。")),
			"changed_city_ids": [] as Array[int],
		}
	var validated_requested_suzerainty: Dictionary = (
		suzerainty_validation["snapshot"] as Dictionary
	)
	# 默认政治图中死亡藩属的法理随同一次事务归入最近的存活祖先。显式
	# overlay（如兼并）通常已由调用方给出更精确的法理 operation；这里只
	# 补齐仍指向死亡藩属的城市，避免图已清理而法理继承永远丢失。
	for former_value in validated_requested_suzerainty:
		var former_id := int(former_value)
		if final_city_counts[former_id] > 0:
			continue
		var successor := int(
			(validated_requested_suzerainty[former_id] as Dictionary).get(
				"overlord_id", -1
			)
		)
		var guard := 0
		while (
			successor >= 0
			and successor < nations.size()
			and final_city_counts[successor] <= 0
			and validated_requested_suzerainty.has(successor)
			and guard <= nations.size()
		):
			successor = int(
				(validated_requested_suzerainty[successor] as Dictionary).get(
					"overlord_id", -1
				)
			)
			guard += 1
		if (
			successor < 0
			or successor >= nations.size()
			or final_city_counts[successor] <= 0
		):
			continue
		for city_id in range(cities.size()):
			if planned_legal_owners[city_id] != former_id:
				continue
			planned_legal_owners[city_id] = successor
			if planned_sponsors[city_id] == former_id:
				planned_sponsors[city_id] = successor
			if planned_owners[city_id] == successor:
				planned_sponsors[city_id] = -1
			if not changed_city_ids.has(city_id):
				changed_city_ids.append(city_id)
	var planned_suzerainty := _normalized_suzerainty_for_city_counts(
		validated_requested_suzerainty,
		final_city_counts
	)
	var normalized_suzerainty_validation := _validated_suzerainty_snapshot(
		planned_suzerainty
	)
	if not bool(normalized_suzerainty_validation.get("ok", false)):
		return {
			"ok": false, "changed": false,
			"territory_changed": false,
			"political_changed": false,
			"diplomacy_changed": false,
			"error": str(normalized_suzerainty_validation.get(
				"error", "最终宗藩图无效。"
			)),
			"changed_city_ids": [] as Array[int],
		}
	var political_changed := planned_suzerainty != suzerainty
	# 宗藩边的外交态属于同一政治事务：拟议图中每条边按 civil_war
	# 归一为 WAR/ALLIED，phase 2 与 suzerainty 同批写入。非宗藩边不动。
	var planned_diplomatic_relations := diplomatic_relations.duplicate(true)
	var planned_diplomatic_since := diplomatic_since_day.duplicate(true)
	var planned_truce_until := truce_until_day.duplicate(true)
	var explicit_relations := {}
	for operation in diplomatic_operations:
		if (
			not operation.has("nation_a")
			or not operation.has("nation_b")
			or not operation.has("relation")
			or typeof(operation.get("nation_a")) != TYPE_INT
			or typeof(operation.get("nation_b")) != TYPE_INT
			or typeof(operation.get("relation")) != TYPE_INT
			or (
				operation.has("truce_days")
				and typeof(operation.get("truce_days")) != TYPE_INT
			)
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "外交操作缺少国家或关系字段。",
				"changed_city_ids": [] as Array[int],
			}
		var nation_a := int(operation["nation_a"])
		var nation_b := int(operation["nation_b"])
		var relation := int(operation["relation"])
		var truce_days := int(operation.get("truce_days", 0))
		if (
			nation_a < 0 or nation_a >= nations.size()
			or nation_b < 0 or nation_b >= nations.size()
			or nation_a == nation_b
			or relation not in [
				DiplomaticRelation.NEUTRAL,
				DiplomaticRelation.WAR,
				DiplomaticRelation.ALLIED,
			]
			or truce_days < 0
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "外交操作包含无效国家、关系或停战期。",
				"changed_city_ids": [] as Array[int],
			}
		var key := _diplomacy_key(nation_a, nation_b)
		if explicit_relations.has(key):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "外交操作包含重复国家对。",
				"changed_city_ids": [] as Array[int],
			}
		explicit_relations[key] = {
			"relation": relation, "truce_days": truce_days,
		}
	for subject_value in planned_suzerainty:
		var subject_id := int(subject_value)
		var record: Dictionary = planned_suzerainty[subject_id]
		var overlord_id := int(record["overlord_id"])
		var key := _diplomacy_key(subject_id, overlord_id)
		var expected_relation := (
			DiplomaticRelation.WAR
			if bool(record.get("civil_war", false))
			else DiplomaticRelation.ALLIED
		)
		if (
			explicit_relations.has(key)
			and int((explicit_relations[key] as Dictionary)["relation"])
				!= expected_relation
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "显式外交操作与最终宗藩关系冲突。",
				"changed_city_ids": [] as Array[int],
			}
	# 先把显式操作应用到旧快照；同一宗藩边若显式给出相同关系，
	# 其 truce_days 由这里保留。随后只补没有显式指定的宗藩必需边。
	for key_value in explicit_relations:
		var key := str(key_value)
		var operation: Dictionary = explicit_relations[key_value]
		var relation := int(operation["relation"])
		var previous_relation := int(diplomatic_relations.get(
			key, DiplomaticRelation.WAR
		))
		if previous_relation != relation:
			planned_diplomatic_relations[key] = relation
			planned_diplomatic_since[key] = day
			if (
				previous_relation == DiplomaticRelation.WAR
				and relation != DiplomaticRelation.WAR
			):
				planned_truce_until[key] = maxi(
					int(planned_truce_until.get(key, 0)),
					day + int(operation["truce_days"])
				)
	for subject_value in planned_suzerainty:
		var subject_id := int(subject_value)
		var record: Dictionary = planned_suzerainty[subject_id]
		var overlord_id := int(record["overlord_id"])
		var key := _diplomacy_key(subject_id, overlord_id)
		if explicit_relations.has(key):
			continue
		var relation := (
			DiplomaticRelation.WAR
			if bool(record.get("civil_war", false))
			else DiplomaticRelation.ALLIED
		)
		var previous_relation := int(diplomatic_relations.get(
			key, DiplomaticRelation.WAR
		))
		if previous_relation == relation:
			continue
		planned_diplomatic_relations[key] = relation
		planned_diplomatic_since[key] = day
		if (
			previous_relation == DiplomaticRelation.WAR
			and relation != DiplomaticRelation.WAR
		):
			planned_truce_until[key] = maxi(
				int(planned_truce_until.get(key, 0)), day
			)
	var diplomacy_changed := (
		planned_diplomatic_relations != diplomatic_relations
		or planned_diplomatic_since != diplomatic_since_day
		or planned_truce_until != truce_until_day
	)
	var normalized_preferred := {}
	for nation_value in preferred_capitals:
		var nation_id := int(nation_value)
		var preferred_id := int(preferred_capitals[nation_value])
		if (
			nation_id < 0 or nation_id >= nations.size()
			or preferred_id < 0 or preferred_id >= cities.size()
			or planned_owners[preferred_id] != nation_id
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "preferred_capitals 包含无效首都。",
				"changed_city_ids": [] as Array[int],
			}
		normalized_preferred[nation_id] = preferred_id
	var planned_capitals: Array[int] = []
	planned_capitals.resize(nations.size())
	planned_capitals.fill(-1)
	for nation in nations:
		if final_city_counts[nation.id] <= 0:
			continue
		planned_capitals[nation.id] = _planned_territory_capital(
			nation.id, planned_owners,
			int(normalized_preferred.get(nation.id, -1))
		)
		if planned_capitals[nation.id] < 0:
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "无法为有城国家规划首都。",
				"changed_city_ids": [] as Array[int],
			}
	var final_pool_holders: Array[int] = []
	final_pool_holders.resize(nations.size())
	final_pool_holders.fill(-1)
	for nation in nations:
		if final_city_counts[nation.id] <= 0:
			continue
		var holder_id := _planned_territory_food_pool_holder(
			nation.id, final_city_counts, planned_suzerainty
		)
		if (
			holder_id < 0
			or holder_id >= nations.size()
			or final_city_counts[holder_id] <= 0
			or planned_capitals[holder_id] < 0
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "领土操作后的粮池持有者没有可用首都。",
				"changed_city_ids": [] as Array[int],
			}
		final_pool_holders[nation.id] = holder_id

	var planned_warehouse_flags: Array[bool] = []
	planned_warehouse_flags.resize(cities.size())
	planned_warehouse_flags.fill(false)
	for city in cities:
		var final_owner := planned_owners[city.id]
		planned_warehouse_flags[city.id] = (
			city.has_warehouse
			and city.owner_nation == final_owner
			and final_pool_holders[final_owner] == final_owner
		)
	for nation in nations:
		if (
			final_city_counts[nation.id] > 0
			and final_pool_holders[nation.id] == nation.id
		):
			planned_warehouse_flags[planned_capitals[nation.id]] = true

	# ------------------------------ phase 1c: 以旧快照计算库存账本。
	var planned_food: Array[int] = []
	planned_food.resize(cities.size())
	for city in cities:
		planned_food[city.id] = city.food_storage
	var stock_credits := {}
	for normalized in normalized_operations:
		var city_id := int(normalized["city_id"])
		var city := cities[city_id]
		if city.owner_nation == int(normalized["controller_id"]):
			continue
		var stock := city.food_storage
		planned_food[city_id] = 0
		if stock <= 0:
			continue
		var policy := int(normalized["stock_policy"])
		var recipient := -1
		var credited := stock
		match policy:
			TerritoryStockDisposition.RETURN_TO_OLD_POOL:
				recipient = _planned_territory_food_pool_holder(
					city.owner_nation, final_city_counts,
					validated_requested_suzerainty
				)
			TerritoryStockDisposition.MOVE_TO_NEW_POOL:
				recipient = final_pool_holders[int(normalized["controller_id"])]
			TerritoryStockDisposition.CAPTURE_SPOILS:
				recipient = final_pool_holders[int(normalized["controller_id"])]
				credited = int(floor(
					float(stock) * TERRITORY_CAPTURE_SPOILS_RATE
				))
			TerritoryStockDisposition.DESTROY:
				credited = 0
		if credited <= 0:
			continue
		if (
			recipient < 0
			or recipient >= nations.size()
			or final_city_counts[recipient] <= 0
			or planned_capitals[recipient] < 0
			or not planned_warehouse_flags[planned_capitals[recipient]]
		):
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "库存策略在最终版图中没有可入账粮池。",
				"changed_city_ids": [] as Array[int],
			}
		stock_credits[recipient] = (
			int(stock_credits.get(recipient, 0)) + credited
		)
	# 宗藩关系刚改变时，旧的非持有者粮仓也在本批摘除并全额归入最终共享池。
	for city in cities:
		if (
			city.owner_nation != planned_owners[city.id]
			or not city.has_warehouse
			or planned_warehouse_flags[city.id]
		):
			continue
		var stock := planned_food[city.id]
		planned_food[city.id] = 0
		if stock <= 0:
			continue
		var recipient := final_pool_holders[planned_owners[city.id]]
		if recipient < 0 or planned_capitals[recipient] < 0:
			return {
				"ok": false, "changed": false,
				"territory_changed": false,
				"political_changed": false,
				"diplomacy_changed": false,
				"error": "被摘除粮仓的库存没有可入账粮池。",
				"changed_city_ids": [] as Array[int],
			}
		stock_credits[recipient] = (
			int(stock_credits.get(recipient, 0)) + stock
		)
	# 和平藩属的首都必须是零库存中继；关系变化前遗留的库存同样回池。
	for nation in nations:
		if (
			final_city_counts[nation.id] <= 0
			or final_pool_holders[nation.id] == nation.id
		):
			continue
		var capital_id := planned_capitals[nation.id]
		var stock := planned_food[capital_id]
		planned_food[capital_id] = 0
		if stock > 0:
			var recipient := final_pool_holders[nation.id]
			stock_credits[recipient] = (
				int(stock_credits.get(recipient, 0)) + stock
			)
	for recipient_value in stock_credits:
		var recipient := int(recipient_value)
		planned_food[planned_capitals[recipient]] += int(
			stock_credits[recipient_value]
		)

	var planned_warehouse_ids: Array = []
	for _nation in nations:
		planned_warehouse_ids.append([] as Array[int])
	for city_id in range(cities.size()):
		if planned_warehouse_flags[city_id]:
			(planned_warehouse_ids[planned_owners[city_id]] as Array[int]).append(
				city_id
			)
	var territory_changed := not changed_city_ids.is_empty()
	for nation in nations:
		if (
			nation.capital_city_id != planned_capitals[nation.id]
			or nation.warehouse_city_ids != (
				planned_warehouse_ids[nation.id] as Array[int]
			)
		):
			territory_changed = true
			break
	if not territory_changed:
		for city_id in range(cities.size()):
			var city := cities[city_id]
			if (
				city.is_capital != (planned_capitals[city.owner_nation] == city_id)
				or city.has_warehouse != planned_warehouse_flags[city_id]
				or city.food_storage != planned_food[city_id]
			):
				territory_changed = true
				break
	if not territory_changed and not political_changed and not diplomacy_changed:
		return {
			"ok": true, "changed": false,
			"territory_changed": false,
			"political_changed": false,
			"diplomacy_changed": false, "error": "",
			"changed_city_ids": [] as Array[int],
		}

	# ------------------------------ phase 2: 一次提交，不再包含可失败分支。
	for city_id in range(cities.size()):
		var city := cities[city_id]
		city.owner_nation = planned_owners[city_id]
		recognized_city_owners[city_id] = planned_legal_owners[city_id]
		city.occupation_sponsor_nation = planned_sponsors[city_id]
		city.is_capital = false
		city.has_warehouse = planned_warehouse_flags[city_id]
		city.food_storage = planned_food[city_id]
	for normalized in normalized_operations:
		if not bool(normalized["reset_political_target"]):
			continue
		var city := cities[int(normalized["city_id"])]
		city.loyalty_target_nation = int(normalized["legal_owner_id"])
		city.loyalty_trend = 0.0
		city.unrest = 100.0 - city.loyalty
		city.rebellion_progress = 0
		city.rebellion_cooldown_until_day = int(normalized["cooldown_until"])
		city.last_loyalty_reason = str(normalized["reason"])
	for nation in nations:
		nation.capital_city_id = planned_capitals[nation.id]
		nation.warehouse_city_ids = (
			planned_warehouse_ids[nation.id] as Array[int]
		).duplicate()
		if nation.capital_city_id >= 0:
			cities[nation.capital_city_id].is_capital = true
	suzerainty = planned_suzerainty.duplicate(true)
	diplomatic_relations = planned_diplomatic_relations
	diplomatic_since_day = planned_diplomatic_since
	truce_until_day = planned_truce_until
	if territory_changed or political_changed:
		ownership_revision += 1
	if diplomacy_changed:
		diplomacy_revision += 1
	refresh_derived()
	changed_city_ids.sort()
	return {
		"ok": true, "changed": true,
		"territory_changed": territory_changed,
		"political_changed": political_changed,
		"diplomacy_changed": diplomacy_changed, "error": "",
		"changed_city_ids": changed_city_ids,
	}


## 只转移城市实控及其战争结算责任方。
func transfer_city_control(
	city_id: int,
	controller_id: int,
	sponsor_id: int = -1,
	stock_policy: int = TerritoryStockDisposition.RETURN_TO_OLD_POOL,
	reason: String = "control_transfer"
) -> Dictionary:
	var normalized_sponsor := sponsor_id
	if (
		city_id >= 0
		and city_id < cities.size()
		and controller_id != recognized_owner_of(city_id)
		and normalized_sponsor == -1
	):
		normalized_sponsor = controller_id
	return apply_territory_transaction([{
		"city_id": city_id,
		"controller_id": controller_id,
		"sponsor_id": normalized_sponsor,
		"stock_policy": stock_policy,
		"reason": reason,
	}] as Array[Dictionary])


## 只迁移城市法理；可一并重置政治目标与叛乱进度。
func transfer_city_legal_title(
	city_id: int,
	legal_owner_id: int,
	reset_political_target: bool = true,
	stock_policy: int = TerritoryStockDisposition.RETURN_TO_OLD_POOL,
	reason: String = "legal_title_transfer"
) -> Dictionary:
	return apply_territory_transaction([{
		"city_id": city_id,
		"legal_owner_id": legal_owner_id,
		"reset_political_target": reset_political_target,
		"stock_policy": stock_policy,
		"reason": reason,
	}] as Array[Dictionary])


## 原子统一城市实控、法理与政治目标；调用方不得预先拆首都或粮仓。
func transfer_city_sovereignty(
	city_id: int,
	sovereign_id: int,
	reason: String = "sovereignty_transfer",
	stock_policy: int = TerritoryStockDisposition.RETURN_TO_OLD_POOL
) -> Dictionary:
	return apply_territory_transaction([{
		"city_id": city_id,
		"controller_id": sovereign_id,
		"legal_owner_id": sovereign_id,
		"sponsor_id": -1,
		"reset_political_target": true,
		"stock_policy": stock_policy,
		"reason": reason,
	}] as Array[Dictionary])


## 和平事务尾部兜底：只依据“战争结算责任方 sponsor ↔ 法理方”判断。
## controller 正在参与的另一场战争与本城占领无关，不能阻止该城恢复法理。
func normalize_peaceful_occupations(
	excluded_war_pairs: Dictionary = {}
) -> Array[int]:
	var operations: Array[Dictionary] = []
	for city in cities:
		var legal_owner := recognized_owner_of(city.id)
		if city.owner_nation == legal_owner:
			continue
		var sponsor := city.occupation_sponsor_nation
		if (
			sponsor >= 0
			and sponsor < nations.size()
			and excluded_war_pairs.has(edge_key(sponsor, legal_owner))
		):
			continue
		var sponsor_at_war := (
			sponsor >= 0
			and sponsor < nations.size()
			and nations[sponsor].alive
			and is_enemy(sponsor, legal_owner)
		)
		if sponsor_at_war:
			continue
		operations.append({
			"city_id": city.id,
			"controller_id": legal_owner,
			"legal_owner_id": legal_owner,
			"sponsor_id": -1,
			"reset_political_target": true,
			"reason": "peaceful_occupation_normalized",
			"stock_policy": TerritoryStockDisposition.MOVE_TO_NEW_POOL,
		})
	if operations.is_empty():
		return [] as Array[int]
	var result := apply_territory_transaction(operations)
	if not bool(result.get("ok", false)):
		return [] as Array[int]
	return result.get("changed_city_ids", []) as Array[int]


## 联盟整体议和确认两个集团之间的全部实际占领。实际控制者保留自己的占领成果，
## 不把盟军占领地错误归给发起议和的代表国。
func recognize_coalition_occupied_territory(
	bloc_a: Array[int],
	bloc_b: Array[int],
	settled_war_pairs: Dictionary = {}
) -> Array[int]:
	var side_a := {}
	var side_b := {}
	for nation_id in bloc_a:
		side_a[nation_id] = true
	for nation_id in bloc_b:
		side_b[nation_id] = true
	var operations: Array[Dictionary] = []
	for city in cities:
		var recognized_owner := recognized_owner_of(city.id)
		if city.owner_nation == recognized_owner:
			continue
		var occupying_side := -1
		var sponsor := city.occupation_sponsor_nation
		if (
			not settled_war_pairs.is_empty()
			and sponsor >= 0
			and sponsor < nations.size()
			and not settled_war_pairs.has(
				edge_key(sponsor, recognized_owner)
			)
		):
			continue
		if side_a.has(sponsor):
			occupying_side = 0
		elif side_b.has(sponsor):
			occupying_side = 1
		elif side_a.has(city.owner_nation):
			occupying_side = 0
		elif side_b.has(city.owner_nation):
			occupying_side = 1
		var recognized_side := -1
		if side_a.has(recognized_owner):
			recognized_side = 0
		elif side_b.has(recognized_owner):
			recognized_side = 1
		if (
			occupying_side < 0
			or recognized_side < 0
			or occupying_side == recognized_side
		):
			continue
		var recipient := external_territory_recipient(
			city.owner_nation
		)
		if recipient < 0:
			continue
		operations.append({
			"city_id": city.id,
			"controller_id": recipient,
			"legal_owner_id": recipient,
			"sponsor_id": -1,
			"reset_political_target": true,
			"reason": "coalition_territory_recognized",
			"stock_policy": TerritoryStockDisposition.MOVE_TO_NEW_POOL,
		})
	if operations.is_empty():
		return [] as Array[int]
	var result := apply_territory_transaction(operations)
	if not bool(result.get("ok", false)):
		return [] as Array[int]
	if bool(result.get("changed", false)):
		prune_dead_suzerainty()
	return result.get("changed_city_ids", []) as Array[int]


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


## Applies an inventory delta to one city and keeps the owning nation's derived
## granary total synchronized without rescanning every city. Returns actual delta.
func change_city_food_storage(city_id: int, delta: int) -> int:
	if city_id < 0 or city_id >= cities.size() or delta == 0:
		return 0
	var city := cities[city_id]
	var raw_old := city.food_storage
	var new_storage := maxi(raw_old + delta, 0)
	var actual_delta := new_storage - raw_old
	city.food_storage = new_storage
	if (
		actual_delta != 0
		and city.has_warehouse
		and city.owner_nation >= 0
		and city.owner_nation < nations.size()
	):
		var owner := nations[city.owner_nation]
		owner.granary_food = maxi(owner.granary_food + actual_delta, 0)
	return actual_delta


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
## 只有当前粮池持有者建立粮仓；和平藩王的新首都仍是零库存补给中继，不能因迁都
## 意外获得独立粮仓。削藩内战反叛方是自己的粮池持有者，仍会正常建立粮仓。
func relocate_capital(nation_id: int) -> int:
	if nation_id < 0 or nation_id >= nations.size():
		return -1
	var candidates: Array[City] = land_cities_of(nation_id)
	if candidates.is_empty():
		candidates = cities_of(nation_id)
	if candidates.is_empty():
		nations[nation_id].capital_city_id = -1
		nations[nation_id].warehouse_city_ids.clear()
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
	capital.is_capital = true
	var owns_food_pool := food_pool_holder(nation_id) == nation_id
	if owns_food_pool:
		if not nation.warehouse_city_ids.has(capital.id):
			nation.warehouse_city_ids.append(capital.id)
		capital.has_warehouse = true
	else:
		nation.warehouse_city_ids.clear()
		capital.has_warehouse = false
		capital.food_storage = 0
	return capital.id


## 领土转移后的首都修复。国家仍有城市但首都已不归本国时立即迁都；无城则清空
## 首都与粮仓索引。调用者不需要依赖下一日的寻路或 AI 查询来被动修复悬空首都。
func ensure_valid_capital(nation_id: int) -> int:
	if nation_id < 0 or nation_id >= nations.size():
		return -1
	var nation := nations[nation_id]
	var capital_id := nation.capital_city_id
	if (
		capital_id >= 0
		and capital_id < cities.size()
		and cities[capital_id].owner_nation == nation_id
		and cities[capital_id].is_capital
	):
		return capital_id
	return relocate_capital(nation_id)


## 运行期领土事务不变量。覆盖实控/法理 ID、占领声明、国家存亡、首都与粮仓
## 的双向索引，以及和平宗藩共享粮仓约束。世界生成中间态可以暂不满足；每个完整
## 领土事务和每日 tick 结束后必须成立。
func territory_structure_valid() -> bool:
	if recognized_city_owners.size() != cities.size():
		return false
	var capital_count_by_nation := {}
	for city in cities:
		var owner := city.owner_nation
		var legal_owner := recognized_owner_of(city.id)
		if (
			owner < 0
			or owner >= nations.size()
			or legal_owner < 0
			or legal_owner >= nations.size()
			or city.occupation_sponsor_nation < -1
			or city.occupation_sponsor_nation >= nations.size()
		):
			return false
		if owner == legal_owner and city.occupation_sponsor_nation != -1:
			return false
		if (
			owner != legal_owner
			and (
				city.occupation_sponsor_nation < 0
				or city.occupation_sponsor_nation >= nations.size()
			)
		):
			return false
		if (
			city.loyalty_target_nation < 0
			or city.loyalty_target_nation >= nations.size()
			or city.rebellion_progress < 0
		):
			return false
		if city.is_capital:
			if nations[owner].capital_city_id != city.id:
				return false
			capital_count_by_nation[owner] = (
				int(capital_count_by_nation.get(owner, 0)) + 1
			)
		if (
			city.has_warehouse
			and not nations[owner].warehouse_city_ids.has(city.id)
		):
			return false
	for nation in nations:
		var has_city := not cities_of(nation.id).is_empty()
		if nation.alive != has_city:
			return false
		if not has_city:
			if (
				nation.capital_city_id != -1
				or not nation.warehouse_city_ids.is_empty()
			):
				return false
			continue
		var capital_id := nation.capital_city_id
		if (
			capital_id < 0
			or capital_id >= cities.size()
			or cities[capital_id].owner_nation != nation.id
			or not cities[capital_id].is_capital
			or int(capital_count_by_nation.get(nation.id, 0)) != 1
		):
			return false
		var warehouse_seen := {}
		for warehouse_id in nation.warehouse_city_ids:
			if (
				warehouse_seen.has(warehouse_id)
				or warehouse_id < 0
				or warehouse_id >= cities.size()
				or cities[warehouse_id].owner_nation != nation.id
				or not cities[warehouse_id].has_warehouse
			):
				return false
			warehouse_seen[warehouse_id] = true
		if food_pool_holder(nation.id) != nation.id:
			if (
				not nation.warehouse_city_ids.is_empty()
				or cities[capital_id].has_warehouse
				or cities[capital_id].food_storage != 0
			):
				return false
		elif (
			not cities[capital_id].has_warehouse
			or not nation.warehouse_city_ids.has(capital_id)
		):
			return false
	return true


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
		city.ruler_city_defense_multiplier = (
			RulerProfile.city_defense_multiplier(owner)
		)
	for army in armies:
		if army.owner_nation < 0 or army.owner_nation >= nations.size():
			continue
		var ruler := nations[army.owner_nation]
		army.ruler_defense_multiplier = (
			RulerProfile.defense_multiplier(ruler)
		)
		army.ruler_morale_multiplier = (
			RulerProfile.morale_multiplier(ruler)
		)
	for n in nations:
		for warehouse in warehouse_cities_of(n.id):
			n.granary_food += warehouse.food_storage
