class_name AdministrativeCampaignPlan
extends RefCounted
## 州级战役的最小持久状态。战术目标最多两个，兵力需求每轮从州状态重算。

enum Phase {
	CAPTURE_FU,
	ENCIRCLE_CENTER,
	ASSAULT_CENTER,
	CLEANUP,
}

var center_city_id: int = -1
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
