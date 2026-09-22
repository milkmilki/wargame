class_name Nation
extends RefCounted
## 国家数据模型。

var id: int = 0
var color: Color = Color.WHITE             ## 阵营色（渲染用）
var name: String = ""                    ## 稳定国号；UI 不再直接展示裸 id
var short_name: String = ""              ## 战略地图大字使用的 1～4 字简称
var name_kind: String = "state"          ## dynasty/state/vassal/rebel
## 藩王封号单向棘轮：一旦陆城数达到过 5 座即永久升为「单字王」。之后即使
## 失地也只保持单字王，绝不降回双字王。仅对 name_kind==vassal 有意义。
var vassal_single_char: bool = false
## 建国/受封时的地域锚点。首次命名后不随迁都、失地或兼并改变；旧档缺失时
## WorldNaming 仅以当时有效首都（再回退到首座直属陆城）确定性补一次。
var founding_city_id: int = -1

## 君主只保存身份与特质；所有效果由 RulerProfile 纯函数派生，禁止把加成
## 永久烧入经济或军队基础属性，确保分封、兼并与未来继位不会叠层漂移。
var ruler_name: String = ""
var ruler_archetype: int = 0
var ruler_traits: Array[String] = []
var ruler_started_day: int = 0
var ruler_revision: int = 0
var trade_policy: int = 0
## 王族谱由 GameState 统一持有；多个独立国家可继续引用同一棵谱。
var family_tree_id: int = -1
var ruler_person_id: int = -1

## 最近一次月度内部政治与贸易快照，仅用于 UI/解释；真源分别是 City
## 忠诚字段及 GameState.trade_routes。
var average_loyalty: float = 70.0
var last_trade_gold: int = 0
var last_trade_food_import: int = 0
var last_trade_food_export: int = 0
var last_trade_manpower_import: int = 0
var last_trade_route_count: int = 0
var last_rebellion_day: int = -1

var treasury_gold: int = 0                 ## 国家钱仓
var manpower_pool: int = 0                 ## 全国统一可用人口库（人口 SSoT）
var last_military_upkeep: int = 0          ## 最近一月全军维护费
var last_field_army_upkeep: int = 0        ## 最近一月野战军维护费
var last_garrison_upkeep: int = 0          ## 最近一月州治虚拟守军维护费
var unpaid_military_upkeep: int = 0        ## 最近一月未支付的军队维护费
var military_payment_ratio: float = 1.0    ## 最近一月军费实际支付率 [0,1]
## 首次进入当前连续战争时冻结的战前月收入（城市+贡赋净收入，不扣军费）。
## 战争期国库目标始终基于此值，领土易手和贡赋变化不得触发军队快速裁撤。
## -1 表示当前和平；初始战争/外部脚本改关系由 Simulation.setup/日同步补快照。
var war_gold_income_snapshot: int = -1
var war_gold_income_snapshot_day: int = -1
## 实际欠饷触发的财政缩编每月最多一次，防止 10 日 AI 周期读取同一月
## unpaid 记录而连续缩编；值为世界月份（day / 30）。
var last_gold_demobilization_month: int = -1
var war_mobilization_target_troops: int = 0 ## 宣战粮食预算对应的目标总兵力
var war_mobilization_until_day: int = -1
var war_mobilization_reason: String = ""
## 主动战争必须先集结再宣战；这些字段是准备阶段的国家级 SSoT。
var war_preparation_target_nation: int = -1
var war_preparation_objective_city: int = -1
var war_preparation_objective_center_city: int = -1
var war_preparation_started_day: int = -1
var war_preparation_reason: String = ""
## 0=普通联盟战争，1=低凝聚力宗藩私人战争。使用整数以保持模型不反向依赖 GameState。
var war_preparation_unready_since_day: int = -1
## 上次「取消备战」的世界日；用于取消后冷却，杜绝取消→隔一个决策周期立即重开的横跳。
## -1 表示无冷却在途。仅由取消路径盖戳，宣战成功清空备战不盖戳（成功不该被冷却惩罚）。
var war_preparation_cancelled_day: int = -1
## 当前州级战争目标。
var campaign_objective_center_city: int = -1
## center_city_id -> AdministrativeCampaignPlan。运行期派生，不进入地图模板。
var administrative_campaign_plans: Dictionary = {}
## 持久战团容器。空战团也保留，每个战团至多编入一支标准主战军。
var battle_groups: Array[BattleGroup] = []
var next_battle_group_id: int = 0
## 首都与粮仓登记。当前每国只有首都一个粮仓；数组结构为未来多粮仓保留扩展位。
var capital_city_id: int = -1
var warehouse_city_ids: Array[int] = []

## 国家粮食总量：派生值 = warehouse_city_ids 对应城市库存之和。
## 库存真源仍在粮仓城市的 City.food_storage，本字段仅供 HUD 展示。
var granary_food: int = 0
var last_food_demand: int = 0              ## 最近月度全部军队计划粮食需求
var last_garrison_food_demand: int = 0     ## 最近月度州治虚拟守军粮食需求
var food_demand_ema: float = 0.0           ## 历史真实需求平滑值，供裁军规划
## 最近一次月结发布给 UI 的粮食快照。为避免把每日真实扣粮伪称为月累计实际，
## 这里显式记录“预计月产/月需/月结余”；旧档缺失时默认 0，保持向后兼容。
var last_food_estimated_production: int = 0
var last_food_estimated_consumption: int = 0 ## 语义为预计月需，来源是 last_food_demand
var last_food_estimated_balance: int = 0
var political_system: int = 0              ## 政治制度（预留，暂未使用）
## 国家级 AI 风险偏好。1.0 为中性；更高时更愿意宣战、持续进攻并承担战术风险。
## 默认对所有国家一致，避免把 nation id 重新引入镜像公平性。
var ai_aggression: float = 1.0

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
