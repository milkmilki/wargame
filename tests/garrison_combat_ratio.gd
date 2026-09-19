extends SceneTree


func _army(size: int, owner: int, garrison: bool, multiplier: float) -> Army:
	var army := Army.new()
	army.id = -1 if garrison else owner + 1
	army.owner_nation = owner
	army.size = size
	army.max_size = size
	army.attack = 10
	army.defense = 10
	army.morale = 2.0 if not garrison else 1.0
	army.max_morale = army.morale
	army.is_city_garrison = garrison
	army.city_garrison_combat_multiplier = multiplier
	return army


func _run_ratio(multiplier: float) -> Vector3:
	var attacker := _army(int(15000.0 * multiplier), 0, false, 1.0)
	var garrison := _army(15000, 1, true, multiplier)
	var battle := Battle.new()
	battle.kind = Battle.Kind.SIEGE
	battle.side_b_defends_city = true
	battle.tactical_key_a = 101
	battle.tactical_key_b = 202
	battle.side_a.append(attacker)
	battle.side_b.append(garrison)
	var rng := RandomNumberGenerator.new()
	rng.seed = 94104
	Combat.resolve_round(
		battle, rng, 4, 94104, 0
	)
	var attacker_losses := int(15000.0 * multiplier) - attacker.size
	var garrison_losses := 15000 - garrison.size
	return Vector3(attacker.size, garrison.size, (
		float(attacker_losses) / float(maxi(garrison_losses, 1))
	))


func _init() -> void:
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	var d3 := _run_ratio(3.0)
	var d4 := _run_ratio(4.0)
	var d5 := _run_ratio(5.0)
	var replay := CombatLog.replay_records(Combat.battle_log)
	Combat.battle_log_enabled = false
	var valid := (
		absf(d3.z - 3.0) <= 0.30
		and absf(d4.z - 4.0) <= 0.40
		and absf(d5.z - 5.0) <= 0.50
		and bool(replay.get("ok", false))
	)
	if valid:
		print("GARRISON_COMBAT_RATIO_OK d3=%s d4=%s d5=%s" % [d3, d4, d5])
		quit(0)
		return
	push_error("GARRISON_COMBAT_RATIO_FAILED d3=%s d4=%s d5=%s replay=%s" % [d3, d4, d5, replay])
	quit(1)
