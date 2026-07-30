class_name City
extends RefCounted
## 城市数据模型 —— 纯数据 SSoT，无逻辑。

var id: int = 0
var coord: Vector2i = Vector2i.ZERO       ## 兼容测试/镜像基准的逻辑 8x8 索引
var map_position: Vector2 = Vector2.ZERO  ## 地图包围盒内归一化坐标 [0,1]²
var terrain_height: float = 0.0           ## 高度图采样值 [0,1]
var terrain_relief: float = 0.0           ## 城市周边局部最大高度差 [0,1]
var owner_nation: int = -1                ## 所属国家 id

var defense: int = 0                      ## 城市防御力
var manpower_per_month: int = 0           ## 每月人口产出，立即汇入所属国人口库
var gold_per_month: int = 0               ## 每月金钱产出
var food_per_half_year: int = 0           ## 每半年粮食产出
var is_food_hub: bool = false             ## 重点粮食产地
var is_manpower_hub: bool = false         ## 重点人口产地

var is_capital: bool = false               ## 是否为当前所属国家首都
var has_warehouse: bool = false            ## 是否设有粮仓（当前仅首都为 true）

## 本城粮仓库存（仅 has_warehouse=true 时有效，是该粮仓库存 SSoT）。
## 全国产出立即汇入首都粮仓；普通城市不保存粮食。
var food_storage: int = 0

var at_war: bool = false                  ## 是否陷于战争
