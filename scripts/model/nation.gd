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
var unpaid_military_upkeep: int = 0        ## 最近一月未支付的军队维护费
var military_payment_ratio: float = 1.0    ## 最近一月军费实际支付率 [0,1]
var last_offensive_gold_cost: int = 0      ## 最近一次实际发动攻势的组织费用
var last_offensive_gold_day: int = -1
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
var war_preparation_started_day: int = -1
var war_preparation_reason: String = ""
var war_preparation_unready_since_day: int = -1
## 上次「取消备战」的世界日；用于取消后冷却，杜绝取消→隔一个决策周期立即重开的横跳。
## -1 表示无冷却在途。仅由取消路径盖戳，宣战成功清空备战不盖戳（成功不该被冷却惩罚）。
var war_preparation_cancelled_day: int = -1
## 战争中的进攻波次时钟；到期后重新集结并发动下一轮攻势。
var campaign_last_offensive_day: int = -1
var campaign_next_offensive_day: int = -1
var campaign_offensive_count: int = 0
## 当前国家级攻势准备起点；普通波次可提前发动，僵局波次最多准备 180 天。
var campaign_preparation_started_day: int = -1
## 当前波次并行准备的目标城，以及冻结的一军一目标分配。
## 多个目标共享国家级准备时钟，不能让同一军在多个方向重复计入已集结兵力。
var campaign_preparation_targets: Array[int] = []
## 下一波攻势的战团级唯一真源。旧 preparation_* 字段是兼容/执行投影。
var campaign_preparation_plan: CampaignAllocationPlan = null
var campaign_preparation_assignments: Dictionary = {}
## target_city_id -> representative battle_group_id 的兼容投影。真实的多团归属
## 只保存在 campaign_preparation_plan.target_to_groups，不能从此字段反推预算。
var campaign_preparation_group_assignments: Dictionary = {}
## 正在等待 180 天满准备的目标城集合。
var campaign_full_preparation_targets: Array[int] = []
## 当前波次的具体战役计划：army_id -> target_city_id。
var campaign_attack_assignments: Dictionary = {}
## 持续攻势梯队：army_id -> echelon_index；每个目标从第 0 梯队依次投入。
var campaign_attack_echelons: Dictionary = {}
## target_city_id -> 当前已激活梯队；-1 表示计划已生成但尚未发动。
var campaign_active_echelons: Dictionary = {}
## 已实际收到攻击命令的军队集合。用于区分待命军与因道路容量暂未出发的当前梯队。
var campaign_launched_armies: Dictionary = {}
## target_city_id -> 当前梯队开始日，供持续攻势状态与调试展示使用。
var campaign_echelon_started_days: Dictionary = {}
## 当前准备时钟对应倍率，仅用于评估下一轮是否发动。
var campaign_preparation_multiplier: float = 1.0
## 已发动轮次的倍率和持续天数；后续梯队继承，且从各自实际投入日开始计时。
var campaign_launched_attack_multiplier: float = 1.0
var campaign_launched_bonus_days: int = 0
## 首攻目标城 -> 预先冻结的两步路线。
## {next_city, group_id, heavy_army_id, execution_army_id,
## enemy_nation, created_day, steps}；破城当天消费并立即执行第二步。
var campaign_post_capture_plans: Dictionary = {}
var campaign_plan_targets: Array[int] = []
var campaign_plan_wave: int = -1
var campaign_plan_primary_city: int = -1
## 最近一次实际发动攻势的主战区锚点。只要附近仍有合法敌城，后续波次继续
## 在该战区组织，避免重军因全局评分微调在远距离方向间反复转场。
var campaign_theater_anchor_city: int = -1
var campaign_theater_started_day: int = -1
## 持久战团容器。空战团也保留，后续按“轻、轻、重”顺序补充成员。
var battle_groups: Array[BattleGroup] = []
var next_battle_group_id: int = 0
## 当前控制区派生的持久边境防区。city_id -> FrontierDefenseSector。
var frontier_defense_sectors: Dictionary = {}
## 控制区、外交关系与实际/潜在边境共同派生的防区拓扑缓存。
## 威胁、兵力和 Assignment 不存入此对象，每个 AI tick 仍动态刷新。
var frontier_defense_topology: FrontierDefenseTopology = null
## 首都与粮仓登记。当前每国只有首都一个粮仓；数组结构为未来多粮仓保留扩展位。
var capital_city_id: int = -1
var warehouse_city_ids: Array[int] = []

## 国家粮食总量：派生值 = warehouse_city_ids 对应城市库存之和。
## 库存真源仍在粮仓城市的 City.food_storage，本字段仅供 HUD 展示。
var granary_food: int = 0
var last_food_demand: int = 0              ## 最近月度全部军队计划粮食需求
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
