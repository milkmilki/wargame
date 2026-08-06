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
		"shared_random_roll",
		"tactical_entropy",
		"side_random_modifier_a",
		"side_random_modifier_b",
		"winner_or_draw",
		"finished",
	]
	for key in required:
		if not record.has(key):
			return {
				"error": "missing_field",
				"field": key,
			}
	var battle := _battle_from_record(record)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	if battle.tactical_key_a <= 0 or battle.tactical_key_b <= 0:
		return {
			"error": "missing_stable_tactical_key",
		}
	var derived_modifiers := Combat.side_tactical_modifiers(
		int(record["tactical_entropy"]),
		Combat._battle_context_signature(battle),
		battle.tactical_key_a,
		battle.tactical_key_b
	)
	if (
		not is_equal_approx(
			derived_modifiers.x,
			float(record["side_random_modifier_a"])
		)
		or not is_equal_approx(
			derived_modifiers.y,
			float(record["side_random_modifier_b"])
		)
	):
		return {
			"error": "side_random_modifier_mismatch",
			"expected": [
				float(record["side_random_modifier_a"]),
				float(record["side_random_modifier_b"]),
			],
			"actual": [
				derived_modifiers.x,
				derived_modifiers.y,
			],
		}
	Combat.resolve_round(
		battle,
		rng,
		int(record["shared_random_roll"]),
		int(record["tactical_entropy"]),
		int(record["day"]),
		derived_modifiers
	)
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
	battle.has_garrison = bool(context.get("has_garrison", false))
	battle.contact_dist_a = float(context.get("contact_dist_a", 0.0))
	battle.contact_dist_b = float(context.get("contact_dist_b", 0.0))
	battle.tactical_key_a = int(context.get("tactical_key_a", 0))
	battle.tactical_key_b = int(context.get("tactical_key_b", 0))
	battle.reinforcement_morale_gained_a = float(context.get(
		"reinforcement_morale_gained_a",
		0.0
	))
	battle.reinforcement_morale_gained_b = float(context.get(
		"reinforcement_morale_gained_b",
		0.0
	))
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
		city.fort_strength = int(city_data.get("fort_strength", 0))
		city.food_storage = int(city_data.get("food_storage", 0))
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
	army.size = int(data.get("size", 0))
	army.max_size = int(data.get("max_size", Army.DEFAULT_MAX_SIZE))
	army.max_morale = float(data.get(
		"max_morale",
		Army.max_morale_for_formation(army.max_size)
	))
	army.attack = int(data.get("attack", 10))
	army.defense = int(data.get("defense", 10))
	army.morale = float(data.get("morale", 1.0))
	army.starving = bool(data.get("starving", false))
	army.offensive_attack_multiplier = float(data.get(
		"offensive_attack_multiplier",
		1.0
	))
	return army


static func _side_snapshot(side: Array[Army]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for army in side:
		result.append({
			"id": army.id,
			"owner_nation": army.owner_nation,
			"size": army.size,
			"max_size": army.max_size,
			"max_morale": army.max_morale,
			"attack": army.attack,
			"defense": army.defense,
			"morale": army.morale,
			"starving": army.starving,
			"offensive_attack_multiplier":
				army.offensive_attack_multiplier,
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
		]:
			if a.get(key) != e.get(key):
				return false
		for key in [
			"morale",
			"offensive_attack_multiplier",
		]:
			if not is_equal_approx(
				float(a.get(key, 0.0)),
				float(e.get(key, 0.0))
			):
				return false
	return true
