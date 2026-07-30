class_name Edge
extends RefCounted
## 通路（无向边）数据模型。端点规范化为 city_a < city_b。

var city_a: int = -1                       ## 端点 A（较小 id）
var city_b: int = -1                       ## 端点 B（较大 id）

var max_throughput: int = 1                ## 每个国家、每个方向允许的最大友军数量
var distance: int = 1                      ## 距离
var danger: float = 0.0                    ## 地形危险系数 (0,1)
var max_height_difference: float = 0.0     ## 两城连线上最高点与最低点之差 [0,1]
var occupied: bool = false                 ## 是否被占用（passing_count>0 时为真）

var passing_count: int = 0                 ## 全方向/全阵营边上军队总数（仅作占用派生）
