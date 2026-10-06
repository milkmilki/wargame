class_name SuccessionConflict
extends RefCounted

enum Outcome { NONE, CROWN_CHANGED, SUPPRESSED, ADMINISTRATIVE }
var nation_id: int = -1
var challenger_person_id: int = -1
var crown_person_id: int = -1
var capital_city_id: int = -1
var camp_city_id: int = -1
var army_ids: Array[int] = []
var crown_army_ids: Array[int] = []
var started_day: int = -1
var war_id: int = -1
var rebel_nation_id: int = -1
var offense_front_id: int = -1
var defense_front_id: int = -1
var pending_outcome: int = Outcome.NONE
var succession_delayed: bool = false
var qualification: Dictionary = {}
var last_progress_day: int = -1
var progress_positions: Dictionary = {}
var progress_battles: Dictionary = {}
var progress_garrison: int = -1
var resolution_reason: String = ""

func launched() -> bool:
	return war_id >= 0

func side_for(army_id: int) -> int:
	if army_ids.has(army_id):
		return 1
	return 2 if crown_army_ids.has(army_id) else 0

func contains_battle(battle: Battle) -> bool:
	if not launched() or battle == null:
		return false
	var a := 0
	var b := 0
	for army in battle.side_a:
		if not army.is_city_garrison:
			a = side_for(army.id)
			if a == 0:
				return false
	for army in battle.side_b:
		if not army.is_city_garrison:
			b = side_for(army.id)
			if b == 0:
				return false
	if a > 0 and b > 0:
		return a != b
	return battle.city != null and battle.city.id in [capital_city_id, camp_city_id] and battle.city.owner_nation in [nation_id, rebel_nation_id] and battle.siege_attacker_nation in [nation_id, rebel_nation_id] and (a > 0 or b > 0)
