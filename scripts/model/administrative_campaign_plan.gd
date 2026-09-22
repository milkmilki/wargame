class_name AdministrativeCampaignPlan
extends RefCounted
## 单个行政州战区的持久状态。一个国家可同时维护多个州计划，但一支军队只能
## 出现在其中一个计划的 army_assignments 中。

enum Mode {
	OFFENSE,
	DEFENSE,
}

enum Phase {
	CAPTURE_FU,
	ENCIRCLE_CENTER,
	ASSAULT_CENTER,
	CLEANUP,
	HOLD_AND_REINFORCE,
	SORTIE,
}

var center_city_id: int = -1
var war_id: int = -1
var mode: int = Mode.OFFENSE
var opponent_nation_id: int = -1
var phase: int = Phase.CAPTURE_FU
var tactical_target_city_ids: Array[int] = []
var army_assignments: Dictionary = {} # army_id -> tactical city_id
var failed_until_day: int = -1
var ownership_revision: int = -1
var administrative_region_revision: int = -1
var garrison_revision: int = -1
var road_network_revision: int = -1
var had_forces: bool = false


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
