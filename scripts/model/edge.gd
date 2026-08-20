class_name Edge
extends RefCounted
## 通路（无向边）数据模型。端点规范化为 city_a < city_b。

const MIN_MANPOWER: int = 5000
const STANDARD_MANPOWER: int = 15000
const TERRAIN_LOW_MANPOWER: int = 10000
const TERRAIN_STANDARD_MANPOWER: int = 20000
const WATER_MANPOWER: int = 50000
## 生产地图的最大通行容量就是水路容量。保留 MAX_MANPOWER 名称供旧调用方兼容。
const MAX_MANPOWER: int = WATER_MANPOWER

enum Kind {
	LAND,
	LANDING,
	RIVER,
	SEA,
}

var city_a: int = -1                       ## 端点 A（较小 id）
var city_b: int = -1                       ## 端点 B（较大 id）

var kind: int = Kind.LAND                  ## 陆路 / 码头抢滩连接 / 码头间水路
var max_manpower: int = STANDARD_MANPOWER  ## 每个国家、每个方向允许的满编兵力总和
var distance: int = 1                      ## 距离
var danger: float = 0.0                    ## 地形危险系数 (0,1)
var travel_time_multiplier: float = 1.0    ## 相对同 distance 陆路的行军时间倍率
var supply_loss_multiplier: float = 1.0    ## 相对同 distance 陆路的粮食运输损耗倍率
var allows_holding: bool = true            ## 水路禁止驻边，军队只能航行或交战
var max_height_difference: float = 0.0     ## 两城连线上最高点与最低点之差 [0,1]
var land_ratio: float = 1.0                ## 连线采样中位于陆地的比例 [0,1]
var map_path: PackedVector2Array = PackedVector2Array() ## 归一化地图折线；空=端点直线
var is_backbone: bool = false              ## 最小连通骨架边不可被运行时调参封闭
var base_max_manpower: int = STANDARD_MANPOWER ## 运行时容量倍率的稳定基准
var occupied: bool = false                 ## 是否被占用（passing_count>0 时为真）

var passing_count: int = 0                 ## 全方向/全阵营边上军队总数（仅作占用派生）


func map_points(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	return (
		map_path
		if map_path.size() >= 2
		else PackedVector2Array([from_position, to_position])
	)


func map_position_at(
	progress: float,
	from_position: Vector2,
	to_position: Vector2,
	map_aspect_ratio: float = 1.0
) -> Vector2:
	var points := map_points(from_position, to_position)
	var total := 0.0
	for index in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		delta.x *= map_aspect_ratio
		total += delta.length()
	var target := clampf(progress, 0.0, 1.0) * total
	for index in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		delta.x *= map_aspect_ratio
		var length := delta.length()
		if target <= length or index == points.size() - 2:
			return points[index].lerp(
				points[index + 1], target / maxf(length, 0.000001)
			)
		target -= length
	return points[-1]


## 正式地图陆路容量唯一量化规则：关闭 / 轻通路 / 标准通路。
## 测试夹具仍可直接给 max_manpower 写入任意值以验证容量数学。
static func quantize_land_capacity(raw_capacity: float) -> int:
	if raw_capacity <= 0.0:
		return 0
	return (
		TERRAIN_STANDARD_MANPOWER
		if raw_capacity >= float(
			(TERRAIN_LOW_MANPOWER + TERRAIN_STANDARD_MANPOWER) / 2
		)
		else TERRAIN_LOW_MANPOWER
	)


static func production_capacity_valid(edge_kind: int, capacity: int) -> bool:
	if edge_kind in [Kind.RIVER, Kind.SEA]:
		return capacity == WATER_MANPOWER
	return capacity in [
		0,
		TERRAIN_LOW_MANPOWER,
		TERRAIN_STANDARD_MANPOWER,
	]
