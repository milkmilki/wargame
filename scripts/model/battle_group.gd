class_name BattleGroup
extends RefCounted
## 持久指挥单位。成员关系的真源是 Army.battle_group_id。
## 每国最多六个指挥单位；每个单位只保留一个聚合主战实体，内部军团仅由
## max_size / INITIAL_HEAVY_ARMY_SIZE 派生展示，不再独立移动、补给或参战。

const MAX_COMMAND_UNITS: int = 6
const MAX_LIGHT_ARMIES: int = 0
const MAX_HEAVY_ARMIES: int = 1

var id: int = -1
var owner_nation: int = -1
var created_day: int = -1
## 作为国家机动预备队时的持久驻防城。疆域/编成不变时跨 AI 周期保留，杜绝因
## 目标城列表随即时威胁重排导致战团在城市间轮转横跳。-1 表示尚未分配。
var reserve_target_city: int = -1
