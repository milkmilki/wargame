class_name Battle
extends RefCounted
## 一场持续多回合（tick）的战斗。EU4 式：每回合掷骰造成伤亡，累积到一方士气崩溃才结束。
## 支持多路对多路（N v M）：side_a / side_b 为军队数组，围城时新到攻击方可 join。
##
## 数据语义：Battle 是活跃战斗的 SSoT；参战 Army.state=FIGHTING 且 battle_id 指向本战斗。
## 解算与结束处理在 Combat（掷骰/伤亡）与 Simulation（撤退落位/占领）中进行。

enum Kind { FIELD, SIEGE }   ## 野战（边中相遇）/ 攻城（城下）

var id: int = -1
var kind: int = Kind.FIELD

# 参战双方（军队引用数组）。SIEGE 时 side_b 为守军（通常 1 支，在城内）。
var side_a: Array[Army] = []
var side_b: Array[Army] = []

# 战场上下文
var edge: Edge = null            ## FIELD/SIEGE 均记录攻击方经由的边（用于地形惩罚）
var city: City = null            ## SIEGE 时的目标城（守军驻城加成 + 占领目标）
var contact_dist_a: float = 0.0  ## side_a 在边上的绝对距离（地形惩罚用）
var contact_dist_b: float = 0.0  ## side_b 在边上的绝对距离

## FIELD 专用：战斗触发瞬间的驻防侧快照。0=无驻防侧，1/2=side_a/side_b。
## 驻防天数是该侧按兵力加权后的连续驻防天数；战斗中不再从 Army.state 反推。
var holding_side: int = 0
var holding_days: float = 0.0

# 回合计数。士气不在此存储——真源是各 Army.morale，本层士气按兵力加权派生（见 side_morale）。
var round_no: int = 0

## 攻城进度累积（仅 SIEGE 有效）：守军被清空后进入纯围城阶段，每天掷骰累加，
## 达 Combat.SIEGE_PROGRESS_REQUIRED 破城。FIELD 恒为 0。
var siege_progress: float = 0.0

## SIEGE 专用：side_b 当前是否为「驻城守军」（享城防加成）。
## 守军溃散后转纯围城置 false；若换成城下援军(挑战者)占 side_b 亦为 false（无城防加成）。
var has_garrison: bool = false

## SIEGE 专用：围城推进的「守方兵力基准」快照（平衡规格 R2 的 5× 门槛分母）。
## 有守军城 = 围城开始时守军兵力；空城 = city.defense（等效防御规模）。
## 守军被歼后仍保留此快照，使「攻方≥5×守军才推进」在纯围城阶段持续生效。
var garrison_ref: int = 0

# 结束态（由 Combat 解算后置位，Simulation 读取处理善后）
var finished: bool = false
var winner_side: int = 0         ## 1=side_a 胜，2=side_b 胜，0=未决


## 一侧的兵力加权平均士气 ∈ [0,1]（派生自各 Army.morale）。空侧返回 0。
func side_morale(side: Array[Army]) -> float:
	var wsum := 0.0
	var tot := 0
	for a in side:
		if a.size > 0:
			wsum += a.morale * float(a.size)
			tot += a.size
	return wsum / float(tot) if tot > 0 else 0.0


func side_size(side: Array[Army]) -> int:
	var t := 0
	for a in side:
		if a.size > 0:
			t += a.size
	return t


func prune_dead() -> void:
	side_a = side_a.filter(func(a: Army) -> bool: return a.size > 0)
	side_b = side_b.filter(func(a: Army) -> bool: return a.size > 0)


func has_army(army: Army) -> bool:
	return side_a.has(army) or side_b.has(army)
