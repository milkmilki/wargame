extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _army(army_id: int, attack: int, defense: int) -> Army:
	var army := Army.new()
	army.id = army_id
	army.owner_nation = army_id
	army.size = 15000
	army.max_size = 15000
	army.attack = attack
	army.defense = defense
	army.morale = 1.0
	army.max_morale = 1.0
	return army


func _run() -> void:
	var attacker := _army(1, 15, 8)
	var defender := _army(2, 8, 15)
	var battle := Battle.new()
	battle.side_a = [attacker] as Array[Army]
	battle.side_b = [defender] as Array[Army]
	var rng := RandomNumberGenerator.new()
	rng.seed = 91827
	var rounds := 0
	while not battle.finished and rounds < 500:
		Combat.resolve_round(battle, rng, 4, 77123 + rounds)
		rounds += 1
	var valid := (
		battle.finished
		and rounds < 500
		and attacker.size >= 7500
		and defender.size >= 7500
		and (
			attacker.combat_morale() <= Combat.SIDE_ROUT_THRESHOLD
			or defender.combat_morale() <= Combat.SIDE_ROUT_THRESHOLD
		)
	)
	if not valid:
		push_error(
			"COMBAT_CASUALTY_CAP_FAILED rounds=%d sizes=%d/%d morale=%.3f/%.3f"
			% [rounds, attacker.size, defender.size, attacker.morale, defender.morale]
		)
		quit(1)
		return
	print(
		"COMBAT_CASUALTY_CAP_OK rounds=%d sizes=%d/%d morale=%.3f/%.3f"
		% [rounds, attacker.size, defender.size, attacker.morale, defender.morale]
	)
	quit(0)
