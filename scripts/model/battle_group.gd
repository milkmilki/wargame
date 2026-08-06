class_name BattleGroup
extends RefCounted
## 持久战团。成员关系的真源是 Army.battle_group_id。

const MAX_LIGHT_ARMIES: int = 2
const MAX_HEAVY_ARMIES: int = 1

var id: int = -1
var owner_nation: int = -1
var created_day: int = -1
