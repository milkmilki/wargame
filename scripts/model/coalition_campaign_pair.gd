class_name CoalitionCampaignPair
extends RefCounted
## Two opposing territorial components share up to two geographic battlefields.
## Execution, troops and combat reports remain on CoalitionCampaignFront.

const MAX_BATTLEFIELDS: int = 2

var pair_id: int = -1
var war_id: int = -1
var side_a_nation_ids: Array[int] = []
var side_b_nation_ids: Array[int] = []
var battlefields: Array[Dictionary] = []
var cooldown_until_by_nation: Dictionary = {}


func members_for(nation_id: int) -> Array[int]:
	return side_a_nation_ids if side_a_nation_ids.has(nation_id) else side_b_nation_ids


func opponents_for(nation_id: int) -> Array[int]:
	return side_b_nation_ids if side_a_nation_ids.has(nation_id) else side_a_nation_ids


func includes(nation_id: int) -> bool:
	return side_a_nation_ids.has(nation_id) or side_b_nation_ids.has(nation_id)


func cooldown_until(members: Array[int]) -> int:
	var result := -1
	for nation_id in members:
		result = maxi(result, int(cooldown_until_by_nation.get(nation_id, -1)))
	return result


static func make_battlefield(center_id: int, front_id: int, preferred_id: int = -1, counterattack: bool = false) -> Dictionary:
	return {"center_city_id": center_id, "offense_front_id": front_id,
		"preferred_nation_id": preferred_id, "counterattack": counterattack, "awaiting_mobilization": false}
