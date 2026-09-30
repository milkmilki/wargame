class_name CoalitionCampaignFront
extends RefCounted
## 一个战争连通分量共享的州级战线。军队保留国家所有权，但同一支军队只能
## 通过 campaign_front_id 绑定到一条战线。

enum Mode {
	OFFENSE,
	DEFENSE,
}

enum Phase {
	ASSEMBLE,
	BREAK_IN,
	RAID_FU,
	RECALL_CAMP,
	HOLD_CAMP,
	ASSAULT_CENTER,
	CLEANUP,
	HOLD_AND_REINFORCE,
	SORTIE,
}

var front_id: int = -1
var center_city_id: int = -1
var war_id: int = -1
var participant_nation_ids: Array[int] = []
var anchor_nation_id: int = -1
var mode: int = Mode.OFFENSE
var phase: int = Phase.ASSEMBLE
var staging_city_id: int = -1
var camp_city_id: int = -1
var tactical_target_city_ids: Array[int] = []
var army_assignments: Dictionary = {} # army_id -> tactical city_id
var failed_until_day: int = -1
## 强攻阶段连续无法对州治下达任何进攻令的决策日计数；达到阈值即回驻营
## 重整。瞬态字段，不参与快照序列化。
var assault_stalled_days: int = 0
var ownership_revision: int = -1
var administrative_region_revision: int = -1
var garrison_revision: int = -1
var road_network_revision: int = -1
var had_forces: bool = false
## 野战期间的调兵认知快照。真实伤亡始终写入 Army.size，
## 只有战争级分配器在 locked=true 时读取这两个值。
var reported_effective_manpower: int = 0
var reported_requirement: int = 0
var combat_report_locked: bool = false
var combat_report_day: int = -1


func fingerprint_matches(state: GameState) -> bool:
	return (
		ownership_revision == state.ownership_revision
		and administrative_region_revision
			== state.administrative_region_revision
		and garrison_revision == state.garrison_revision
		and road_network_revision == state.road_network_revision
	)


func refresh_fingerprint(state: GameState) -> void:
	ownership_revision = state.ownership_revision
	administrative_region_revision = state.administrative_region_revision
	garrison_revision = state.garrison_revision
	road_network_revision = state.road_network_revision


func reset_combat_report() -> void:
	reported_effective_manpower = 0
	reported_requirement = 0
	combat_report_locked = false
	combat_report_day = -1
