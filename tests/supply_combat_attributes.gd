extends SceneTree
## Food scales combat attributes, never physical army counts or frontage.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func troop(owner: int, ratio: float) -> Army:
	var army := Army.new()
	army.id = owner
	army.owner_nation = owner
	army.size = 10000
	army.max_size = 15000
	army.attack = 10
	army.defense = 10
	army.morale = army.max_morale
	army.supply_ratio = ratio
	army.starving = ratio < 1.0
	return army

func _init() -> void:
	var army := troop(0, 1.0)
	army.funding_multiplier = 0.75
	army.ruler_attack_multiplier = 1.2
	army.ruler_defense_multiplier = 1.4
	var full_attack := army.combat_attack()
	var full_defense := army.combat_defense()
	var full_power := ArmyPower.effective(army)
	var state := GameState.new()
	for ratio in [0.0, 0.25, 0.5, 0.8, 1.0, 1.5, -0.5]:
		army.supply_ratio = ratio
		var factor := clampf(ratio, 0.0, 1.0)
		check(is_equal_approx(army.combat_attack(), full_attack * factor), "attack scales once by ration %s" % ratio)
		check(is_equal_approx(army.combat_defense(), full_defense * factor), "defense scales once by ration %s" % ratio)
		check(is_equal_approx(ArmyPower.effective(army), full_power * factor), "AI power uses the same attributes without a second ration penalty %s" % ratio)
		check(is_equal_approx(state.effective_army_defense(army), full_defense * factor), "defense query shares live ration multiplier")
		check(army.size == 10000 and army.max_size == 15000 and army.attack == 10 and army.defense == 10
			and army.combat_morale() == army.max_morale, "attribute queries preserve counts, base stats and morale")
	for kind in [Battle.Kind.FIELD, Battle.Kind.SIEGE]:
		var full := combat_round(kind, 1.0)
		var partial := combat_round(kind, 0.5)
		var empty := combat_round(kind, 0.0)
		check(is_equal_approx(partial.effective_attack_a, full.effective_attack_a * 0.5), "real round halves attack for partial food")
		check(is_equal_approx(partial.effective_defense_a, full.effective_defense_a * 0.5), "real round halves defense for partial food")
		check(empty.effective_attack_a == 0.0 and empty.effective_defense_a == 0.0, "real round has zero attributes at zero rations")
		check(partial.frontline_strength_a == full.frontline_strength_a and empty.frontline_strength_a == full.frontline_strength_a,
			"partial/zero rations do not turn people into a smaller frontline")
		check(partial.casualties_b < full.casualties_b and partial.casualties_a > full.casualties_a,
			"scaled attributes change actual inflicted and suffered casualties")
		check(is_equal_approx(partial.supply_modifier_a, 0.5) and is_equal_approx(empty.supply_modifier_a, 0.0), "combat log reports actual ration modifier")
		check(is_equal_approx(float(partial.participants_a[0].get("supply_ratio", -1.0)), 0.5), "participant log preserves ration input")
		check(bool(CombatLog.replay_records([partial]).ok), "partial-food battle log replays exact casualties and morale")
		check(bool(CombatLog.replay_records([empty]).ok), "zero-food battle log replays exact casualties and morale")
		var missing_ratio := partial.duplicate(true)
		missing_ratio.participants_a[0].erase("supply_ratio")
		var rejected := CombatLog.replay_records([missing_ratio])
		check(not rejected.ok and rejected.errors[0].get("field") == "supply_ratio",
			"version 5 replay rejects missing rations rather than assuming a full supply")
	var first := troop(0, 1.0)
	first.size = 6000
	var second := troop(0, 0.5)
	second.id = 2
	second.size = 4000
	var mixed := logged_round(Battle.Kind.FIELD, [first, second], [troop(1, 1.0)])
	check(is_equal_approx(mixed.effective_attack_a, 80000.0) and mixed.frontline_strength_a == 10000,
		"mixed-ration fire is computed per formation while all people remain in frontage")
	check(is_equal_approx(mixed.supply_modifier_a, 0.8), "mixed-ration log is frontline-weighted, not all-side starving penalty")
	print("SUPPLY_COMBAT_ATTRIBUTES checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func combat_round(kind: int, ratio: float) -> Dictionary:
	var defender := troop(1, 1.0)
	defender.is_city_garrison = kind == Battle.Kind.SIEGE
	return logged_round(kind, [troop(0, ratio)], [defender])

func logged_round(kind: int, attackers: Array[Army], defenders: Array[Army]) -> Dictionary:
	var battle := Battle.new()
	battle.kind = kind
	battle.side_a = attackers
	battle.side_b = defenders
	battle.field_dice = [0, 0, 0, 0]
	battle.assault_dice = [0, 0, 0, 0]
	battle.field_sequence = 1
	battle.assault_sequence = 1
	var enabled := Combat.battle_log_enabled
	var old_log := Combat.battle_log.duplicate()
	Combat.battle_log_enabled = true
	Combat.clear_battle_log()
	Combat.resolve_round(battle)
	var row := Combat.battle_log[0].duplicate(true)
	Combat.battle_log.assign(old_log)
	Combat.battle_log_enabled = enabled
	return row
