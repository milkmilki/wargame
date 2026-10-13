class_name StateCampaign
extends RefCounted
## One state battle, two side records, one lifecycle. Executors own Army bindings.
enum Lifecycle { PREPARING, ACTIVE, ENDING }
var campaign_id: int = -1
var war_id: int = -1
var pair_id: int = -1
var center_city_id: int = -1
var initiator_nation_id: int = -1
var defender_nation_id: int = -1
var attacker_members: Array[int] = []
var defender_members: Array[int] = []
var offense_front_id: int = -1
var defense_front_id: int = -1
var lifecycle: int = Lifecycle.PREPARING
var started_day: int = -1
var ending_day: int = -1
var end_reason: String = ""
var incidental: bool = false
## Wake the existing component once when a new public target becomes known.
var defense_activation_pending: bool = false
## Former executor cohorts remain references while combat/withdrawal is physical.
var ending_army_ids: Array[int] = []

func visible_to(nation_id: int) -> bool:
	return nation_id == initiator_nation_id if lifecycle == Lifecycle.PREPARING else attacker_members.has(nation_id) or defender_members.has(nation_id)

func mode_for(nation_id: int) -> int:
	return CoalitionCampaignFront.Mode.OFFENSE if attacker_members.has(nation_id) else CoalitionCampaignFront.Mode.DEFENSE
