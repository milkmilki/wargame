class_name Nation
extends RefCounted
## 国家数据模型。

var id: int = 0
var color: Color = Color.WHITE             ## 阵营色（渲染用）

var treasury_gold: int = 0                 ## 国家钱仓
var manpower_pool: int = 0                 ## 全国统一可用人口库（人口 SSoT）
var last_war_upkeep: int = 0               ## 最近一月战争军费（派生记录）
var unpaid_war_cost: int = 0               ## 最近一月无力支付的战争军费
var war_mobilization_target_troops: int = 0 ## 宣战粮食预算对应的目标总兵力
var war_mobilization_until_day: int = -1
var war_mobilization_reason: String = ""
## 主动战争必须先集结再宣战；这些字段是准备阶段的国家级 SSoT。
var war_preparation_target_nation: int = -1
var war_preparation_objective_city: int = -1
var war_preparation_started_day: int = -1
var war_preparation_reason: String = ""
## 战争中的进攻波次时钟；到期后重新集结并发动下一轮攻势。
var campaign_last_offensive_day: int = -1
var campaign_next_offensive_day: int = -1
var campaign_offensive_count: int = 0
## 首都与粮仓登记。当前每国只有首都一个粮仓；数组结构为未来多粮仓保留扩展位。
var capital_city_id: int = -1
var warehouse_city_ids: Array[int] = []

## 国家粮食总量：派生值 = warehouse_city_ids 对应城市库存之和。
## 库存真源仍在粮仓城市的 City.food_storage，本字段仅供 HUD 展示。
var granary_food: int = 0
var last_food_demand: int = 0              ## 最近月度全部军队计划粮食需求
var food_demand_ema: float = 0.0           ## 历史真实需求平滑值，供裁军规划
var political_system: int = 0              ## 政治制度（预留，暂未使用）

## 最近一次 AI 建军/解散命令，供调试和可解释性展示。
var ai_last_force_action: int = 0
var ai_last_force_day: int = -1
var ai_last_force_reason: String = ""

## 最近一次外交动作仅用于解释和展示；双边关系真源位于 GameState。
var ai_last_diplomatic_action: int = 0
var ai_last_diplomatic_target: int = -1
var ai_last_diplomatic_day: int = -1
var ai_last_diplomatic_reason: String = ""

var alive: bool = true                     ## 是否仍拥有城市（派生）
