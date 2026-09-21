extends SceneTree


func _army(
	size: int,
	owner: int,
	garrison: bool,
	multiplier: float,
	defense_bonus: float = 3.0
) -> Army:
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
	army.city_garrison_defense_bonus = defense_bonus
	return army


func _run_defender(defender: Army) -> Vector2i:
	var attacker := _army(15000, 0, false, 1.0)
	var battle := Battle.new()
	battle.kind = Battle.Kind.SIEGE
	battle.side_b_defends_city = true
	battle.tactical_key_a = 301
	battle.tactical_key_b = 302
	battle.side_a.append(attacker)
	battle.side_b.append(defender)
	var rng := RandomNumberGenerator.new()
	rng.seed = 94105
	Combat.resolve_round(battle, rng, 0, 94105, 0, Vector2.ONE)
	return Vector2i(attacker.size, defender.size)


func _init() -> void:
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	var full_garrison := _army(15000, 1, true, 1.0, 3.0)
	var full_sizes := _run_defender(full_garrison)
	var full_equivalent := _army(15000, 1, false, 1.0)
	full_equivalent.attack = 5
	full_equivalent.defense = 30
	var full_equivalent_sizes := _run_defender(full_equivalent)
	var encircled_garrison := _army(15000, 1, true, 1.0, 1.0)
	var encircled_sizes := _run_defender(encircled_garrison)
	var encircled_equivalent := _army(15000, 1, false, 1.0)
	encircled_equivalent.attack = 5
	encircled_equivalent.defense = 10
	var encircled_equivalent_sizes := _run_defender(encircled_equivalent)
	Combat.battle_log_enabled = false
	var valid := (
		full_sizes == full_equivalent_sizes
		and encircled_sizes == encircled_equivalent_sizes
		and full_sizes.x == encircled_sizes.x
		and full_sizes.y > encircled_sizes.y
	)
	if valid:
		print("GARRISON_COMBAT_RATIO_OK full=%s encircled=%s" % [
			full_sizes, encircled_sizes,
		])
		quit(0)
		return
	push_error("GARRISON_COMBAT_RATIO_FAILED full=%s/%s encircled=%s/%s" % [
		full_sizes, full_equivalent_sizes,
		encircled_sizes, encircled_equivalent_sizes,
	])
	quit(1)
