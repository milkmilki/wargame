class_name CombatLog
extends RefCounted
## 结构化战斗日志的 JSONL 持久化与确定性回放器。
##
## 每条记录自带回合开始时的军队快照、战场上下文和实际随机修正，因此可独立回放，
## 不依赖 GameState、自然语言 reason 或此前回合。文件一行一条 JSON，便于流式处理。


static func save_jsonl(
	records: Array[Dictionary],
	path: String
) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": "open_failed",
			"code": FileAccess.get_open_error(),
		}
	for record in records:
		file.store_line(JSON.stringify(record))
	file.close()
	return {
		"ok": true,
		"records": records.size(),
		"path": path,
	}


static func load_jsonl(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": "open_failed",
			"code": FileAccess.get_open_error(),
			"records": [] as Array[Dictionary],
		}
	var records: Array[Dictionary] = []
	var line_number := 0
	while not file.eof_reached():
		var line := file.get_line()
		line_number += 1
		if line.strip_edges().is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			file.close()
			return {
				"ok": false,
				"error": "invalid_json_record",
				"line": line_number,
				"records": records,
			}
		records.append(parsed as Dictionary)
	file.close()
	return {
		"ok": true,
		"records": records,
		"path": path,
	}


static func replay_file(path: String) -> Dictionary:
	var loaded := load_jsonl(path)
	if not bool(loaded.get("ok", false)):
		return loaded
	return replay_records(
		loaded["records"] as Array[Dictionary]
	)


static func replay_records(
	records: Array[Dictionary]
) -> Dictionary:
	var errors: Array[Dictionary] = []
	var previous_logging := Combat.battle_log_enabled
	Combat.battle_log_enabled = false
	for index in range(records.size()):
		var error := _replay_record(records[index])
		if not error.is_empty():
			error["index"] = index
			errors.append(error)
	Combat.battle_log_enabled = previous_logging
	return {
		"ok": errors.is_empty(),
		"replayed": records.size(),
		"errors": errors,
	}


static func _replay_record(record: Dictionary) -> Dictionary:
	if int(record.get("combat_rules_version", -1)) != Combat.COMBAT_RULES_VERSION:
		return {"error": "incompatible_combat_rules"}
	var required := [
		"battle_id",
		"day",
		"round_no",
		"kind",
		"participants_a",
		"participants_b",
		"participants_after_a",
		"participants_after_b",
		"routed_a",
		"routed_b",
		"battle_context",
		"opening_dice",
		"performance_modifier_a",
		"performance_modifier_b",
		"expansion_modifier_a",
		"expansion_modifier_b",
		"base_frontage",
		"frontage_a",
		"frontage_b",
		"winner_or_draw",
		"finished",
	]
	for key in required:
		if not record.has(key):
			return {
				"error": "missing_field",
				"field": key,
			}
	if not record["battle_context"] is Dictionary:
		return {"error": "invalid_battle_context"}
	var context: Dictionary = record["battle_context"]
	for key in ["field_dice", "assault_dice", "field_sequence", "assault_sequence"]:
		if not context.has(key):
			return {"error": "missing_field", "field": key}
	for kind in ["field", "assault"]:
		var sequence = context[kind + "_sequence"]
		if not (sequence is int or sequence is float) or not is_finite(float(sequence)) or float(sequence) != floorf(float(sequence)) or float(sequence) < 0:
			return {"error": "invalid_engagement_sequence"}
		if context[kind + "_dice"] is Array and not context[kind + "_dice"].is_empty() and sequence == 0:
			return {"error": "invalid_engagement_sequence"}
	for raw in [record["opening_dice"], context.field_dice, context.assault_dice]:
		if not raw is Array or (not raw.is_empty() and raw.size() != 4):
			return {"error": "invalid_opening_dice"}
		for die in raw:
			if not (die is int or die is float) or float(die) != floorf(float(die)) or float(die) < 0 or float(die) > 10:
				return {"error": "invalid_opening_dice"}
	for side_key in ["participants_a", "participants_b"]:
		for data in record[side_key]:
			if not data.has("funding_multiplier"):
				return {"error": "missing_field", "field": "funding_multiplier"}
	var battle := _battle_from_record(record)
	var dice := battle.opening_dice()
	if not Battle.valid_dice(dice) or dice != PackedInt32Array(record["opening_dice"]):
		return {"error": "invalid_opening_dice"}
	if (
		not is_equal_approx(Battle.dice_multiplier(dice[0]), float(record["performance_modifier_a"]))
		or not is_equal_approx(Battle.dice_multiplier(dice[1]), float(record["performance_modifier_b"]))
		or not is_equal_approx(Battle.dice_multiplier(dice[2]), float(record["expansion_modifier_a"]))
		or not is_equal_approx(Battle.dice_multiplier(dice[3]), float(record["expansion_modifier_b"]))
		or Combat.combat_frontage(battle) != int(record["base_frontage"])
		or Combat.side_combat_frontage(battle, 1) != int(record["frontage_a"])
		or Combat.side_combat_frontage(battle, 2) != int(record["frontage_b"])
	):
		return {"error": "opening_modifier_mismatch"}
	Combat.resolve_round(battle, int(record["day"]))
	if battle.winner_side != int(record["winner_or_draw"]):
		return {
			"error": "winner_mismatch",
			"expected": int(record["winner_or_draw"]),
			"actual": battle.winner_side,
		}
	if battle.finished != bool(record["finished"]):
		return {
			"error": "finished_mismatch",
			"expected": bool(record["finished"]),
			"actual": battle.finished,
		}
	var after_a := _side_snapshot(battle.side_a)
	var after_b := _side_snapshot(battle.side_b)
	if not _snapshots_equal(
		after_a,
		record["participants_after_a"] as Array
	):
		return {
			"error": "side_a_state_mismatch",
			"expected": record["participants_after_a"],
			"actual": after_a,
		}
	if not _snapshots_equal(
		after_b,
		record["participants_after_b"] as Array
	):
		return {
			"error": "side_b_state_mismatch",
			"expected": record["participants_after_b"],
			"actual": after_b,
		}
	if not _snapshots_equal(
		_side_snapshot(battle.routed_a),
		record["routed_a"] as Array
	):
		return {
			"error": "side_a_routed_mismatch",
			"expected": record["routed_a"],
			"actual": _side_snapshot(battle.routed_a),
		}
	if not _snapshots_equal(
		_side_snapshot(battle.routed_b),
		record["routed_b"] as Array
	):
		return {
			"error": "side_b_routed_mismatch",
			"expected": record["routed_b"],
			"actual": _side_snapshot(battle.routed_b),
		}
	return {}


static func _battle_from_record(record: Dictionary) -> Battle:
	var battle := Battle.new()
	battle.id = int(record["battle_id"])
	battle.kind = int(record["kind"])
	battle.round_no = int(record["round_no"]) - 1
	var context: Dictionary = record["battle_context"]
	battle.holding_side = int(context.get("holding_side", 0))
	battle.holding_days = float(context.get("holding_days", 0.0))
	battle.side_b_defends_city = bool(context.get(
		"side_b_defends_city", false
	))
	battle.contact_dist_a = float(context.get("contact_dist_a", 0.0))
	battle.contact_dist_b = float(context.get("contact_dist_b", 0.0))
	battle.field_dice = PackedInt32Array(context.get("field_dice", []))
	battle.assault_dice = PackedInt32Array(context.get("assault_dice", []))
	battle.field_sequence = int(context.get("field_sequence", 0))
	battle.assault_sequence = int(context.get("assault_sequence", 0))
	var edge_data: Dictionary = context.get("edge", {})
	if not edge_data.is_empty():
		var edge := Edge.new()
		edge.distance = int(edge_data.get("distance", 1))
		edge.danger = float(edge_data.get("danger", 0.0))
		edge.max_manpower = int(edge_data.get(
			"max_manpower",
			Combat.FRONTAGE_FALLBACK
		))
		edge.kind = int(edge_data.get("kind", Edge.Kind.LAND))
		edge.travel_time_multiplier = float(
			edge_data.get("travel_time_multiplier", 1.0)
		)
		edge.supply_loss_multiplier = float(
			edge_data.get("supply_loss_multiplier", 1.0)
		)
		edge.allows_holding = bool(
			edge_data.get("allows_holding", true)
		)
		battle.edge = edge
	var city_data: Dictionary = context.get("city", {})
	if not city_data.is_empty():
		var city := City.new()
		city.food_storage = int(city_data.get("food_storage", 0))
		city.garrison_manpower = int(city_data.get("garrison_manpower", 0))
		battle.city = city
	for army_data in record["participants_a"]:
		battle.side_a.append(_army_from_snapshot(army_data))
	for army_data in record["participants_b"]:
		battle.side_b.append(_army_from_snapshot(army_data))
	_restore_frontline_priority(
		battle.side_a,
		battle.frontline_priority_a,
		context.get("frontline_priority_a", {})
	)
	_restore_frontline_priority(
		battle.side_b,
		battle.frontline_priority_b,
		context.get("frontline_priority_b", {})
	)
	return battle


static func _restore_frontline_priority(
	side: Array[Army],
	priority: Dictionary,
	serialized: Dictionary
) -> void:
	for army in side:
		var key := str(army.id)
		if serialized.has(key):
			priority[army] = int(serialized[key])


static func _army_from_snapshot(data: Dictionary) -> Army:
	var army := Army.new()
	army.id = int(data.get("id", 0))
	army.owner_nation = int(data.get("owner_nation", -1))
	army.campaign_war_id = int(data.get("campaign_war_id", -1))
	army.campaign_front_id = int(data.get("campaign_front_id", -1))
	army.size = int(data.get("size", 0))
	army.max_size = int(data.get("max_size", Army.DEFAULT_MAX_SIZE))
	army.max_morale = float(data.get(
		"max_morale",
		Army.DEFAULT_MAX_MORALE
	))
	army.attack = int(data.get("attack", 10))
	army.ruler_attack_multiplier = float(data.get(
		"ruler_attack_multiplier", 1.0
	))
	army.ruler_defense_multiplier = float(data.get("ruler_defense_multiplier", 1.0))
	army.ruler_morale_multiplier = float(data.get("ruler_morale_multiplier", 1.0))
	army.funding_multiplier = float(data["funding_multiplier"])
	army.defense = int(data.get("defense", 10))
	army.morale = float(data.get("morale", 1.0))
	army.starving = bool(data.get("starving", false))
	army.is_city_garrison = bool(data.get("is_city_garrison", false))
	army.city_garrison_combat_multiplier = float(data.get(
		"city_garrison_combat_multiplier", 1.0
	))
	army.city_garrison_defense_bonus = float(data.get(
		"city_garrison_defense_bonus", 3.0
	))
	return army


static func _side_snapshot(side: Array[Army]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for army in side:
		result.append({
			"id": army.id,
			"owner_nation": army.owner_nation,
			"campaign_war_id": army.campaign_war_id,
			"campaign_front_id": army.campaign_front_id,
			"size": army.size,
			"max_size": army.max_size,
			"max_morale": army.max_morale,
			"attack": army.attack,
			"ruler_attack_multiplier": army.ruler_attack_multiplier,
			"ruler_defense_multiplier": army.ruler_defense_multiplier,
			"ruler_morale_multiplier": army.ruler_morale_multiplier,
			"funding_multiplier": army.funding_multiplier,
			"defense": army.defense,
			"morale": army.morale,
			"starving": army.starving,
			"is_city_garrison": army.is_city_garrison,
			"city_garrison_combat_multiplier":
				army.city_garrison_combat_multiplier,
			"city_garrison_defense_bonus":
				army.city_garrison_defense_bonus,
		})
	return result


static func _snapshots_equal(
	actual: Array,
	expected: Array
) -> bool:
	if actual.size() != expected.size():
		return false
	for index in range(actual.size()):
		var a: Dictionary = actual[index]
		var e: Dictionary = expected[index]
		for key in [
			"id",
			"owner_nation",
			"size",
			"max_size",
			"attack",
			"defense",
			"starving",
			"is_city_garrison",
		]:
			if a.get(key) != e.get(key):
				return false
		for key in [
			"morale",
			"ruler_attack_multiplier",
			"ruler_defense_multiplier",
			"ruler_morale_multiplier",
			"funding_multiplier",
			"max_morale",
			"city_garrison_combat_multiplier",
			"city_garrison_defense_bonus",
		]:
			if not is_equal_approx(
				float(a.get(key, 0.0)),
				float(e.get(key, 0.0))
			):
				return false
	return true
