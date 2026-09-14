class_name BattleGroup
extends RefCounted
## 持久主战军团。成员关系的真源是 Army.battle_group_id，战略命令的真源在此。

const MAX_MANPOWER: int = 15000
const CAPITAL_GUARD_MANPOWER: int = 50000
## 旧军制代码仍会读取这两个常量来估算一次征募的编成；它们不再构成战团合法性约束。
const MAX_LIGHT_ARMIES: int = 2
const MAX_HEAVY_ARMIES: int = 1

enum Role {
	FIELD,
	CAPITAL_GUARD,
}

enum Posture {
	PEACE,
	ATTACK,
	DEFEND,
	RECOVER,
}

var id: int = -1
var owner_nation: int = -1
var created_day: int = -1
var role: int = Role.FIELD
var posture: int = Posture.PEACE
var target_nation: int = -1
var target_city: int = -1
## 兼容旧走廊编号；当前简化军制以交战国首都对为一条公共走廊，多个
## 1.5万人主战军团根据威胁权重共同分配到该走廊。
var corridor_lane: int = -1
## 防守军团选择走廊据点后，可进一步驻扎在据点朝敌方方向的有利道路。
## -1 表示守城节点，不进入道路驻防。
var defense_edge_to: int = -1
## 战时保存交战双方首都之间的完整公共走廊；和平/备战时保存当前调动路线。
## Army 若不在战时走廊上，就近汇入可达节点，再执行该节点之后的后缀。
var route: Array[int] = []
var route_revision: int = -1
var merge_group_owner: int = -1
var merge_group_id: int = -1
## 作为国家机动预备队时的持久驻防城。疆域/编成不变时跨 AI 周期保留，杜绝因
## 目标城列表随即时威胁重排导致战团在城市间轮转横跳。-1 表示尚未分配。
var reserve_target_city: int = -1


func manpower_limit() -> int:
	return (
		CAPITAL_GUARD_MANPOWER
		if role == Role.CAPITAL_GUARD
		else MAX_MANPOWER
	)


func clear_order() -> void:
	posture = Posture.PEACE
	target_nation = -1
	target_city = -1
	corridor_lane = -1
	defense_edge_to = -1
	route.clear()
	route_revision = -1
	merge_group_owner = -1
	merge_group_id = -1
