class_name Nation
extends RefCounted
## 国家数据模型。

var id: int = 0
var color: Color = Color.WHITE             ## 阵营色（渲染用）

var treasury_gold: int = 0                 ## 国家钱仓
var manpower_pool: int = 0                 ## 全国统一可用人口库（人口 SSoT）
var last_military_upkeep: int = 0          ## 最近一月全军维护费
var unpaid_military_upkeep: int = 0        ## 最近一月未支付的军队维护费
var military_payment_ratio: float = 1.0    ## 最近一月军费实际支付率 [0,1]
var last_offensive_gold_cost: int = 0      ## 最近一次实际发动攻势的组织费用
var last_offensive_gold_day: int = -1
var war_mobilization_target_troops: int = 0 ## 宣战粮食预算对应的目标总兵力
var war_mobilization_until_day: int = -1
var war_mobilization_reason: String = ""
## 主动战争必须先集结再宣战；这些字段是准备阶段的国家级 SSoT。
var war_preparation_target_nation: int = -1
var war_preparation_objective_city: int = -1
var war_preparation_started_day: int = -1
var war_preparation_reason: String = ""
var war_preparation_unready_since_day: int = -1
## 战争中的进攻波次时钟；到期后重新集结并发动下一轮攻势。
var campaign_last_offensive_day: int = -1
var campaign_next_offensive_day: int = -1
var campaign_offensive_count: int = 0
## 当前国家级攻势准备起点；普通波次可提前发动，僵局波次最多准备 180 天。
var campaign_preparation_started_day: int = -1
## 当前波次并行准备的目标城，以及冻结的一军一目标分配。
## 多个目标共享国家级准备时钟，不能让同一军在多个方向重复计入已集结兵力。
var campaign_preparation_targets: Array[int] = []
var campaign_preparation_assignments: Dictionary = {}
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
## 满准备目标城 -> {preparation_days, expires_day}。
## 破城当天消费并生成驻城/驻边/扩张的第二阶段命令。
var campaign_post_capture_plans: Dictionary = {}
var campaign_plan_targets: Array[int] = []
var campaign_plan_wave: int = -1
var campaign_plan_primary_city: int = -1
## 首都与粮仓登记。当前每国只有首都一个粮仓；数组结构为未来多粮仓保留扩展位。
var capital_city_id: int = -1
var warehouse_city_ids: Array[int] = []

## 国家粮食总量：派生值 = warehouse_city_ids 对应城市库存之和。
## 库存真源仍在粮仓城市的 City.food_storage，本字段仅供 HUD 展示。
var granary_food: int = 0
var last_food_demand: int = 0              ## 最近月度全部军队计划粮食需求
var food_demand_ema: float = 0.0           ## 历史真实需求平滑值，供裁军规划
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
