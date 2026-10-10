# Exact cf80691 battle-group audit retained as an outcome oracle.
extends GameState

func _battle_group_structure_valid() -> bool:
	for nation in nations:
		for group in nation.battle_groups:
			var army_count := 0
			for army in battle_group_members(nation.id, group.id):
				if army.max_size != INITIAL_HEAVY_ARMY_SIZE:
					return false
				army_count += 1
			if army_count > BattleGroup.MAX_ARMIES:
				return false
	for army in armies:
		if (
			army.size > 0
			and (
				army.max_size != INITIAL_HEAVY_ARMY_SIZE
				or battle_group_by_id(
					army.owner_nation,
					army.battle_group_id
				) == null
			)
		):
			return false
	return true


