class_name Army
extends RefCounted
## 军队数据模型。

enum State {
	IDLE,
	MOVING,
	FIGHTING,
	RETREATING, ## 士气崩溃后向最近友方城市撤退；不受 AI 指令，但可被正常军队接战
	RECOVERING, ## 抵达友城后驻守恢复；士气回满或该城恢复资源耗尽前不得行动
	HOLDING,    ## 固定部署在边上；不移动，持续补给并累计地形适应
}

const DEFAULT_MAX_SIZE: int = 15000

var id: int = 0
var owner_nation: int = -1

var size: int = 0                          ## 人数
var max_size: int = DEFAULT_MAX_SIZE       ## 满编人数上限
var speed_factor: float = 0.5              ## 速度系数 (0,1)
var attack: int = 10                       ## 攻击力
var defense: int = 10                      ## 防御力

var location_city: int = -1                ## 静止时所在城市；行军时为出发城
var state: int = State.IDLE

var path: Array[int] = []                  ## 寻路城市序列（不含当前城）
var move_from: int = -1                    ## 当前正在通过的边端点（起）
var move_to: int = -1                      ## 当前正在通过的边端点（止）
var move_progress: float = 0.0             ## 当前边行进进度 (0,1)

## 当前所属战斗 id（-1=未交战）。FIGHTING 状态时冻结在 move_progress 位置。
var battle_id: int = -1

## 是否正在边上。passing_count 由此维护总占用；方向容量则从全部 on_edge 军队实时派生。
var on_edge: bool = false

## 派生标记：本月是否缺粮（供渲染标记饥饿）。由 Simulation 每月刷新。
var starving: bool = false

## 持久士气 ∈ [0,1]。战斗中被侵蚀（伤亡/断粮），战斗外每月恢复。
## 真源在此（Battle 层士气为本值的兵力加权派生），使"老兵带疲劳进场"效果自然涌现。
var morale: float = 1.0

## 最近一次月度补给满足率 ∈[0,1]。驻防适应每日据此增长/暂停/衰减。
var supply_ratio: float = 1.0

## 在当前边当前位置连续驻防的天数。换边、主动移动或撤退时清零。
var holding_days: int = 0

## 普通行军抵达该进度后转 HOLDING；<0 表示无驻防命令。
var hold_target_progress: float = -1.0

## 进入野战前是否为驻防军。战斗胜利时据此恢复 HOLDING。
var resume_holding_after_battle: bool = false

## 强制撤退命令是否仍有效。RETREATING=true；被动接战转 FIGHTING 时仍保留，
## 若该军获胜则继续原撤退路线，而不是恢复普通 MOVING。
var forced_retreat: bool = false

## AI 命令元数据。只记录决策与滞回，不直接改变状态机语义。
var ai_action: int = 0
var ai_target_city: int = -1
var ai_order_created_day: int = -1
var ai_order_until_day: int = -1
var ai_order_score: float = 0.0
var ai_order_reason: String = ""

## 预定攻势的限时攻击加成。Simulation 负责授予和到期清理，Combat 只读取倍率。
var offensive_attack_multiplier: float = 1.0
var offensive_bonus_until_day: int = -1

## 防御换防锁。非紧急 CityDefensePlan 在截止日前不得再次调离该军。
var defensive_deployment_until_day: int = -1
var defensive_blocked_edge_a: int = -1
var defensive_blocked_edge_b: int = -1

## 跨入敌境时冻结的占领归属国；可为军队所属国或提供出发领土的盟国。
var occupation_claimant_nation: int = -1
