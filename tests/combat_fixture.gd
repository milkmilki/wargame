class_name CombatFixture
extends RefCounted
## Functional fixtures use explicit neutral dice; statistics initialize real random dice.

static func resolve_round(battle: Battle, day: int = -1) -> void:
	if battle.opening_dice().is_empty():
		if battle.uses_field_combat_rules():
			battle.field_dice = PackedInt32Array([0, 0, 0, 0])
			battle.field_sequence = maxi(battle.field_sequence, 1)
		else:
			battle.assault_dice = PackedInt32Array([0, 0, 0, 0])
			battle.assault_sequence = maxi(battle.assault_sequence, 1)
	Combat.resolve_round(battle, day)
