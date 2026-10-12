class_name SuccessionConflict
extends RefCounted
## Private political combat. Provenance IDs never reserve map troops.
enum Outcome { NONE, CROWN_CHANGED, SUPPRESSED, ADMINISTRATIVE }
var nation_id: int = -1
var challenger_person_id: int = -1
var crown_person_id: int = -1
var ruler_person_id: int = -1
var ruler_revision: int = -1
var started_day: int = -1
var last_advanced_day: int = -1
var last_progress_day: int = -1
var pending_outcome: int = Outcome.NONE
var succession_delayed: bool = false
var qualification: Dictionary = {}
var resolution_reason: String = ""
var battle: Battle
var round_logs: Array[Dictionary] = []
var army_ids: Array[int] = []
var crown_army_ids: Array[int] = []
# Inert compatibility fields for legacy map queries; no private map identities.
var capital_city_id: int = -1
var camp_city_id: int = -1
var war_id: int = -1
var rebel_nation_id: int = -1
var offense_front_id: int = -1
var defense_front_id: int = -1

func launched() -> bool: return battle != null
func side_for(_army_id: int) -> int: return 0
func contains_battle(_battle: Battle) -> bool: return false

func display_report() -> Dictionary:
	if battle == null: return {}
	return {"context": "internal_succession", "battle_id": battle.id,
		"challenger_person_id": challenger_person_id, "crown_person_id": crown_person_id,
		"troops_a": battle.side_size(battle.side_a), "troops_b": battle.side_size(battle.side_b),
		"morale_a": battle.side_morale(battle.side_a), "morale_b": battle.side_morale(battle.side_b),
		"round": battle.round_no, "delayed": succession_delayed, "started_day": started_day}

func snapshot() -> Dictionary:
	var result := {}
	for property in get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or property.name == "battle": continue
		var value: Variant = get(property.name)
		result[property.name] = value.duplicate(true) if value is Array or value is Dictionary else value
	var combat := {}
	if battle != null:
		for property in battle.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
			var value: Variant = battle.get(property.name)
			if value is Array or value is Dictionary or value is Object: continue
			combat[property.name] = value
		combat["side_a"] = CombatLog._side_snapshot(battle.side_a)
		combat["side_b"] = CombatLog._side_snapshot(battle.side_b)
	result["battle"] = combat
	return result

static func from_snapshot(data: Dictionary) -> SuccessionConflict:
	var result := SuccessionConflict.new()
	for key in data:
		if key != "battle": result.set(key, data[key])
	result.battle = Battle.new()
	for key in data.battle:
		if key in ["side_a", "side_b"]:
			for army in data.battle[key]: result.battle.get(key).append(CombatLog._army_from_snapshot(army))
		else: result.battle.set(key, data.battle[key])
	return result
