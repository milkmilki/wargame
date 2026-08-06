class_name City
extends RefCounted
## 城市数据模型 —— 纯数据 SSoT，无逻辑。

var id: int = 0
var coord: Vector2i = Vector2i.ZERO       ## 兼容测试/镜像基准的逻辑 8x8 索引
var map_position: Vector2 = Vector2.ZERO  ## 地图包围盒内归一化坐标 [0,1]²
var terrain_height: float = 0.0           ## 高度图采样值 [0,1]
var terrain_relief: float = 0.0           ## 城市周边局部最大高度差 [0,1]
var is_dock: bool = false                 ## 河运码头；仍复用完整城市占领/补给/经济状态
var owner_nation: int = -1                ## 所属国家 id
## 当前占领由哪个直接交战国的军队取得；和平确认后清空。
var occupation_sponsor_nation: int = -1

## 当前有效城墙/工事强度（量纲：城防点数，值域通常 0~30；非兵力）。
## 战斗中作为守军的防御加成（city_defense_modifier 语义）；空城时经
## Combat.siege_required_manpower() 显式换算为「破城所需兵力」（兵力量纲），
## 不得与驻军人数直接相加或比较（item 6：禁止量纲混用）。
var fort_strength: int = 0
## 完整工事强度。城市易手后 fort_strength 降到本值的 50%，一年内线性恢复。
var fort_strength_max: int = 0
## 最近一次实际易手的世界日；-1 表示从未被攻破。再次易手直接刷新。
var fort_last_capture_day: int = -1
var manpower_per_month: int = 0           ## 每月人口产出，立即汇入所属国人口库
var gold_per_month: int = 0               ## 每月金钱产出
var food_per_half_year: int = 0           ## 每半年粮食产出
var is_food_hub: bool = false             ## 重点粮食产地
var is_manpower_hub: bool = false         ## 重点人口产地
var is_plain_city: bool = false            ## 正式地图局部起伏最低的平原城市
var is_port_market: bool = false           ## 与码头直接相连的陆城
var is_crossroads: bool = false            ## 至少连接六条正容量道路的高连接交通枢纽
## 地理开发直接加成与一跳传播后的相对权重；最终整数产出已全图归一化写回。
var development_gold_multiplier: float = 1.0
var development_food_multiplier: float = 1.0

var is_capital: bool = false               ## 是否为当前所属国家首都
var has_warehouse: bool = false            ## 是否设有粮仓（当前仅首都为 true）

## 本城粮仓库存（仅 has_warehouse=true 时有效，是该粮仓库存 SSoT）。
## 全国产出立即汇入首都粮仓；普通城市不保存粮食。
var food_storage: int = 0

var at_war: bool = false                  ## 是否陷于战争
var war_disruption_until_day: int = 0     ## 城市战斗结束后粮食/金钱减产截止日
