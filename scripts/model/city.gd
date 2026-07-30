class_name City
extends RefCounted
## 城市（网格）数据模型 —— 纯数据 SSoT，无逻辑。
## id = row * 8 + col（0..63）；坐标可由 id 反算。

var id: int = 0
var coord: Vector2i = Vector2i.ZERO      ## (col, row)
var owner_nation: int = -1                ## 所属国家 id

var defense: int = 0                      ## 城市防御力
var manpower_per_month: int = 0           ## 每月人口产出，立即汇入所属国人口库
var gold_per_month: int = 0               ## 每月金钱产出
var food_per_half_year: int = 0           ## 每半年粮食产出

var is_capital: bool = false               ## 是否为当前所属国家首都
var has_warehouse: bool = false            ## 是否设有粮仓（当前仅首都为 true）

## 本城粮仓库存（仅 has_warehouse=true 时有效，是该粮仓库存 SSoT）。
## 全国产出立即汇入首都粮仓；普通城市不保存粮食。
var food_storage: int = 0

var at_war: bool = false                  ## 是否陷于战争
