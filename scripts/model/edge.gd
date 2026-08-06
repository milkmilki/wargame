class_name Edge
extends RefCounted
## 通路（无向边）数据模型。端点规范化为 city_a < city_b。

const MIN_MANPOWER: int = 5000
const STANDARD_MANPOWER: int = 15000
const TERRAIN_LOW_MANPOWER: int = 10000
const TERRAIN_STANDARD_MANPOWER: int = 20000
const MAX_MANPOWER: int = 100000

enum Kind {
	LAND,
	LANDING,
	RIVER,
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
var occupied: bool = false                 ## 是否被占用（passing_count>0 时为真）

var passing_count: int = 0                 ## 全方向/全阵营边上军队总数（仅作占用派生）
