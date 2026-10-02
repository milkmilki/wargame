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

# 参战双方（军队引用数组）。SIEGE 时：
# - side_a 为同一战争阵营的围城共同体；
# - side_b 在 side_b_defends_city=true 时为城市防卫共同体（城主及其盟军，可多 nation）；
# - side_b 在 side_b_defends_city=false 时为同一战争阵营的敌对挑战者共同体。
var side_a: Array[Army] = []
var side_b: Array[Army] = []

# 战场上下文
var edge: Edge = null            ## FIELD/SIEGE 均记录攻击方经由的边（用于地形惩罚）
var city: City = null            ## SIEGE 时的目标城（守军驻城加成 + 占领目标）
var siege_attacker_nation: int = -1
var siege_claimant_nation: int = -1
var contact_dist_a: float = 0.0  ## side_a 在边上的绝对距离（地形惩罚用）
var contact_dist_b: float = 0.0  ## side_b 在边上的绝对距离

## FIELD 专用：战斗触发瞬间的驻防侧快照。0=无驻防侧，1/2=side_a/side_b。
## 驻防天数是该侧按兵力加权后的连续驻防天数；战斗中不再从 Army.state 反推。
var holding_side: int = 0
var holding_days: float = 0.0

# 回合计数。士气不在此存储——真源是各 Army.morale，本层士气按兵力加权派生（见 side_morale）。
var round_no: int = 0

## Pending arrivals for logs; morale merges with the whole side next round.
var reinforce_fresh_a: Array[Army] = []
var reinforce_fresh_b: Array[Army] = []

## 本回合因单军士气阈值退出战斗的军队。Combat 负责从 side 中移出，
## Simulation 随后根据真实战场位置启动撤退；下一回合开始前必须已消费并清空。
var routed_a: Array[Army] = []
var routed_b: Array[Army] = []

## 显式前线选择的镜像等变优先级（Army 引用 -> rank）。Simulation 每轮在拥有
## GameState 空间上下文时刷新；Combat 用它裁决完全相同战斗属性军队的先后。
var frontline_priority_a: Dictionary = {}
var frontline_priority_b: Dictionary = {}

## item 8：两侧稳定战术随机键。由首次入场军队的镜像轨道位置/势力中心生成，
## 不含实体 id、兵力、士气或攻防参数；战斗期间参数变化不会“重抽运气”。
## 完全镜像的空间角色可得到相同键，此时独立修正按等变性要求自动退化为同值。
var tactical_key_a: int = 0
var tactical_key_b: int = 0

## SIEGE 专用：side_b 当前是否为城市防卫共同体。该字段只决定野战
## 胜负后的解围/接管归属；真实军队不会因此获得虚拟守军的防御倍率。
var side_b_defends_city: bool = false
# 结束态（由 Combat 解算后置位，Simulation 读取处理善后）
var finished: bool = false
var winner_side: int = 0         ## 1=side_a 胜，2=side_b 胜，0=未决
## Set by Simulation when a FIELD battle resolves through a rout.  Kept on the
## battle object so logs/replays can distinguish pursuit attrition from normal
## round casualties.
var field_rout_attrition_multiplier: float = 1.0


## 一侧的兵力加权平均有效士气。
func side_morale(side: Array[Army]) -> float:
	var wsum := 0.0
	var tot := 0
	for a in side:
		if a.size > 0:
			wsum += a.combat_morale() * float(a.size)
			tot += a.size
	return wsum / float(tot) if tot > 0 else 0.0


func side_size(side: Array[Army]) -> int:
	var t := 0
	for a in side:
		if a.size > 0:
			t += a.size
	return t


## Shared field morale is derived, never a second persistent source of truth.
func shared_morale_summary(side: Array[Army]) -> Dictionary:
	var size := 0
	var capacity := 0.0
	var mass := 0.0
	for army in side:
		if army.size <= 0 or army.is_city_garrison:
			continue
		size += army.size
		capacity += float(army.size) * army.combat_max_morale()
		mass += float(army.size) * army.combat_morale()
	var ratio := clampf(mass / capacity, 0.0, 1.0) if capacity > 0.0 else 0.0
	return {"size": size, "capacity": capacity, "ratio": ratio,
		"effective": ratio * capacity / float(size) if size > 0 else 0.0}


func write_shared_morale(side: Array[Army], ratio: float) -> void:
	for army in side:
		if army.size > 0 and not army.is_city_garrison:
			army.morale = clampf(ratio, 0.0, 1.0) * army.max_morale


func prune_dead() -> void:
	side_a = side_a.filter(func(a: Army) -> bool: return a.size > 0)
	side_b = side_b.filter(func(a: Army) -> bool: return a.size > 0)


func has_army(army: Army) -> bool:
	return side_a.has(army) or side_b.has(army)


## Administrative exit only; combat routs retain their normal attrition ledger.
func remove_army(army: Army) -> void:
	side_a.erase(army)
	side_b.erase(army)
	reinforce_fresh_a.erase(army)
	reinforce_fresh_b.erase(army)
	routed_a.erase(army)
	routed_b.erase(army)
	frontline_priority_a.erase(army)
	frontline_priority_b.erase(army)


## 围城外壳中只要 side_b 存在真实军队，本轮就是城下野战。虚拟守军
## 仅在 side_b 没有真实军队时临时挂载，因此不会与野战军同轮参战。
func uses_field_combat_rules() -> bool:
	if kind == Kind.FIELD:
		return true
	if kind != Kind.SIEGE:
		return false
	for army in side_b:
		if army.size > 0 and not army.is_city_garrison:
			return true
	return false
