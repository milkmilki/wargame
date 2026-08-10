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

## 本 tick 新加入各侧的援军引用（每回合结算增援士气后清空）。
## 语义：把「本 tick 新增的全部有效兵力」作为一个整体统一结算一次士气提振，
## 而非「每支军队 join 一次」。这样把一支援军拆成多支依次加入不会重复获得士气奖励（item 12 拆分套利）。
var reinforce_fresh_a: Array[Army] = []
var reinforce_fresh_b: Array[Army] = []

## 两侧在本场战斗中已经获得的累计援军士气提振。上限由
## Combat.REINFORCE_MORALE_MAX 约束，跨回合分批抵达不能重复刷新额度。
## 必须按侧分别累计；共享单一标量会让先结算的一侧消耗另一侧额度，制造 A/B 偏置。
var reinforcement_morale_gained_a: float = 0.0
var reinforcement_morale_gained_b: float = 0.0

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

## 攻城进度累积（仅 SIEGE 有效）：守军被清空后进入纯围城阶段，每天确定性累加；
## 守城/解围战持续期间每天回退，达 Combat.SIEGE_PROGRESS_REQUIRED 才能破城。
var siege_progress: float = 0.0

## SIEGE 专用：side_b 当前是否为「驻城守军」（享城防加成）。
## 守军溃散后转纯围城置 false；若换成城下援军(挑战者)占 side_b 亦为 false（无城防加成）。
var has_garrison: bool = false

## SIEGE 专用：破城所需兵力（siege_required_manpower，item 6/7：恒为兵力量纲）。
## 由 Combat.siege_required_manpower(city.fort_strength) 推导：= 工事强度换算封锁兵力（不含守军人数）。
## 围城比值分母 = 攻方有效兵力 / 本值。守军是城下决斗阶段的对手、被歼后本值不变
## （item 6 验收：驻军被击败后城防仍来自 fort_strength），使纯围城曲线始终以工事需求为准。
var siege_required: int = 0

# 结束态（由 Combat 解算后置位，Simulation 读取处理善后）
var finished: bool = false
var winner_side: int = 0         ## 1=side_a 胜，2=side_b 胜，0=未决


## 一侧的兵力加权平均有效士气；攻势准备期间读取与攻击加成同源的临时倍率。
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


func prune_dead() -> void:
	side_a = side_a.filter(func(a: Army) -> bool: return a.size > 0)
	side_b = side_b.filter(func(a: Army) -> bool: return a.size > 0)


func has_army(army: Army) -> bool:
	return side_a.has(army) or side_b.has(army)
