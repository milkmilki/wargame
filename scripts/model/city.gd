class_name City
extends RefCounted
## 城市数据模型 —— 纯数据 SSoT，无逻辑。

var id: int = 0
var coord: Vector2i = Vector2i.ZERO       ## 兼容测试/镜像基准的逻辑 8x8 索引
var map_position: Vector2 = Vector2.ZERO  ## 地图包围盒内归一化坐标 [0,1]²
var terrain_height: float = 0.0           ## 高度图采样值 [0,1]
var terrain_relief: float = 0.0           ## 城市周边局部最大高度差 [0,1]
var owner_nation: int = -1                ## 所属国家 id
## 当前占领由哪个直接交战国的军队取得；和平确认后清空。
var occupation_sponsor_nation: int = -1

## 城墙/工事/要塞的结构强度（量纲：城防点数，值域约 10~30；非兵力）。
## 战斗中作为守军的防御加成（city_defense_modifier 语义）；空城时经
## Combat.siege_required_manpower() 显式换算为「破城所需兵力」（兵力量纲），
## 不得与驻军人数直接相加或比较（item 6：禁止量纲混用）。
var fort_strength: int = 0
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
var war_disruption_until_day: int = 0     ## 城市战斗结束后粮食/金钱减产截止日
