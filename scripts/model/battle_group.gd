class_name BattleGroup
extends RefCounted
## 持久指挥单位。成员关系的真源是 Army.battle_group_id。
## 每个指挥单位严格对应一支独立的 15000 人主战军。国家可以拥有任意数量
## 的指挥单位；单次攻势仍由 Simulation 自己限制投入数量。

const MAX_CAMPAIGN_COMMAND_UNITS: int = 6
const MAX_ARMIES: int = 1

var id: int = -1
var owner_nation: int = -1
var created_day: int = -1
## 作为国家机动预备队时的持久驻防城。疆域/编成不变时跨 AI 周期保留，杜绝因
## 目标城列表随即时威胁重排导致战团在城市间轮转横跳。-1 表示尚未分配。
var reserve_target_city: int = -1
