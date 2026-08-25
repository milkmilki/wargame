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

enum StrategicRole {
	LINE,       ## 独立填线军：只执行统一防区规划；正式地图国家级攻势不会临时抽调
	MAIN,       ## 主战军：包含重军与战团轻军，执行完整 Utility AI 与国家级攻势
}

enum LinePosture {
	NONE,
	CITY,
	EDGE,
}

const DEFAULT_MAX_SIZE: int = 15000
## 道路运输的最小编队包。max_size 仍表示战斗编制、补员上限与重军身份，
## 不再兼任“整支编制必须一次塞进道路”的硬准入条件。
const ROAD_PACKET_SIZE: int = 5000
const LIGHT_MAX_MORALE: float = 1.0
const HEAVY_MAX_MORALE: float = 2.0

var id: int = 0
var owner_nation: int = -1

var size: int = 0                          ## 人数
var max_size: int = DEFAULT_MAX_SIZE       ## 满编人数上限
var speed_factor: float = 0.5              ## 速度系数 (0,1)
var attack: int = 10                       ## 攻击力
var defense: int = 10                      ## 防御力
## 当前所属君主的派生军事修正。GameState.refresh_derived() 按 owner 重放；
## 基础 attack/defense/morale 永不被永久改写。
var ruler_defense_multiplier: float = 1.0
var ruler_morale_multiplier: float = 1.0
var strategic_role: int = StrategicRole.LINE
## 所属持久战团；-1 表示独立填线军。战团内最多 2 支轻军和 1 支重军。
var battle_group_id: int = -1
## 填线军的持久防区 Assignment。前线未变化时跨 AI 周期保留，避免每次从零匹配换防。
var line_assignment_city: int = -1
var line_assignment_posture: int = LinePosture.NONE
var line_assignment_edge: int = -1

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

## 瞬态遭遇阻塞兼容标记。只能暂停一次行军推进；遭遇裁决不得依赖它
## 无限等待外部状态破坏对称，也不伪装成 HOLDING 或授予驻防身份。
var encounter_blocked: bool = false

## 派生标记：当日是否缺粮（供渲染标记饥饿）。由 Simulation 每日刷新。
var starving: bool = false

## 持久士气 ∈ [0,max_morale]。战斗中被侵蚀（伤亡/断粮），战斗外每日恢复。
## 真源在此（Battle 层士气为本值的兵力加权派生），使"老兵带疲劳进场"效果自然涌现。
var morale: float = 1.0
## 轻军为 1，重军为 2；高于 1 的部分只增加持续作战储备，不继续放大战斗效率。
var max_morale: float = LIGHT_MAX_MORALE

## 当日补给满足率 ∈[0,1]。驻防适应与每日补给惩罚均读取本值。
var supply_ratio: float = 1.0

## 累积断粮减员债（item 10）：每日按 shortage×size×STARVE_RATE/30 累加的「未满整人」减员，
## 满 1 人即扣减 size 并留下小数余额。持久化字段——存读档不重置，避免利用结算相位套利。
var supply_debt: float = 0.0

## 逐日粮食需求的小数债。月耗先除以 30，再在此累积到整粮后扣库存，
## 从而每日重算竞争与部分短缺，同时避免对每支军队逐日 ceil 导致 30 倍取整膨胀。
var supply_food_debt: float = 0.0

## 在当前边当前位置连续驻防的天数。换边、主动移动或撤退时清零。
var holding_days: int = 0

## 普通行军抵达该进度后转 HOLDING；<0 表示无驻防命令。
var hold_target_progress: float = -1.0

## 进入野战前是否为驻防军。战斗胜利时据此恢复 HOLDING。
var resume_holding_after_battle: bool = false

## 强制撤退命令是否仍有效。RETREATING=true；被动接战转 FIGHTING 时仍保留，
## 若该军获胜则继续原撤退路线，而不是恢复普通 MOVING。
var forced_retreat: bool = false

## 外交关系变化后的遣返状态。仅允许沿正容量道路穿越第三国返回本国，
## 不授予驻扎、补给、攻击或占领权；抵达本国城市后立即清除。
var diplomatic_repatriation: bool = false

## AI 命令元数据。只记录决策与滞回，不直接改变状态机语义。
var ai_action: int = 0
var ai_target_city: int = -1
var ai_order_created_day: int = -1
var ai_order_until_day: int = -1
var ai_order_score: float = 0.0
var ai_order_reason: String = ""

## 预定攻势的限时攻击/有效士气加成。Simulation 负责授予和到期清理；
## 持久 morale 不直接改写，战斗层通过 combat_morale() 读取同一倍率。
var offensive_attack_multiplier: float = 1.0
var offensive_bonus_until_day: int = -1

## 防御换防锁。非紧急 CityDefensePlan 在截止日前不得再次调离该军。
var defensive_deployment_until_day: int = -1
var defensive_blocked_edge_a: int = -1
var defensive_blocked_edge_b: int = -1

## 跨入敌境时冻结的占领归属国；可为军队所属国或提供出发领土的盟国。
var occupation_claimant_nation: int = -1


static func max_morale_for_formation(formation_size: int) -> float:
	return (
		HEAVY_MAX_MORALE
		if formation_size >= DEFAULT_MAX_SIZE
		else LIGHT_MAX_MORALE
	)


static func road_footprint_for_formation(formation_size: int) -> int:
	if formation_size <= 0:
		return 0
	return mini(formation_size, ROAD_PACKET_SIZE)


func road_footprint() -> int:
	return road_footprint_for_formation(max_size)


## 一支军队在某条道路上同时占用的吞吐容量。窄路允许重军分批通过，
## 但会占满可用方向容量；宽路则按完整编制占用。
func road_capacity_load(edge_capacity: int) -> int:
	if edge_capacity < road_footprint():
		return 0
	return mini(max_size, edge_capacity)


static func road_transport_batches_for_formation(
	formation_size: int,
	edge_capacity: int
) -> int:
	if formation_size <= 0 or edge_capacity <= 0:
		return 1
	return maxi(int(ceil(float(formation_size) / float(edge_capacity))), 1)


func road_transport_batches(edge_capacity: int) -> int:
	return road_transport_batches_for_formation(max_size, edge_capacity)


func morale_ratio() -> float:
	return clampf(
		morale / maxf(max_morale, LIGHT_MAX_MORALE),
		0.0,
		1.0
	)


func offensive_multiplier() -> float:
	return maxf(offensive_attack_multiplier, 1.0)


func combat_morale() -> float:
	return morale * offensive_multiplier() * maxf(ruler_morale_multiplier, 0.1)


func combat_max_morale() -> float:
	return max_morale * offensive_multiplier() * maxf(ruler_morale_multiplier, 0.1)


func combat_morale_ratio() -> float:
	return clampf(
		combat_morale() / maxf(max_morale, LIGHT_MAX_MORALE),
		0.0,
		1.0
	)


func is_main_battle_role() -> bool:
	return (
		max_size >= DEFAULT_MAX_SIZE
		or strategic_role == StrategicRole.MAIN
	)


func is_line_role() -> bool:
	return (
		max_size < DEFAULT_MAX_SIZE
		and strategic_role == StrategicRole.LINE
	)


func clear_line_assignment() -> void:
	line_assignment_city = -1
	line_assignment_posture = LinePosture.NONE
	line_assignment_edge = -1


## 是否已经物理停留在城市节点。
## 围城军抵达后会保留 move_from/move_to 作为补给与地形锚点，但已释放道路占用；
## 容量等待军则以 location_city 锚定节点。两种状态必须由同一谓词识别。
func is_at_city_node(city_id: int) -> bool:
	return current_city_node() == city_id


func current_city_node() -> int:
	if on_edge:
		return -1
	if move_to >= 0 and move_progress >= 1.0:
		return move_to
	if move_to == -1:
		return location_city
	return -1
