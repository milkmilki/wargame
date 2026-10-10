extends RefCounted
## Original dependency fields copied from bfd5a4d; independent oracle.

static func _trade_settlement_token(
	state: GameState,
	structure_fingerprint: PackedByteArray,
	wartime_mask: PackedByteArray = PackedByteArray()
) -> PackedByteArray:
	var effective_wartime_mask := (
		wartime_mask
		if wartime_mask.size() == state.nations.size()
		else TradeNetwork.wartime_nation_mask(state)
	)
	var fields: Array = [
		"trade_settlement_v1",
		["family_revision", state.family_revision],
		structure_fingerprint,
		["wartime_nations", effective_wartime_mask],
	]
	for city in state.cities:
		fields.append([
			"city", city.id, city.food_storage,
			city.garrison_manpower, city.garrison_supply_ratio,
			Simulation.city_war_disrupted(state, city),
		])
	var suzerainty_subjects := state.suzerainty.keys()
	suzerainty_subjects.sort()
	for subject_value in suzerainty_subjects:
		var subject_id := int(subject_value)
		var record: Dictionary = state.suzerainty[subject_value]
		fields.append([
			"suzerainty", subject_id,
			int(record.get("overlord_id", -1)),
			float(record.get("tribute_rate", 0.0)),
			bool(record.get("civil_war", false)),
		])
	for nation in state.nations:
		var modifiers := RulerProfile.modifiers(nation)
		fields.append([
			"nation", nation.id, nation.alive,
			state.food_pool_holder(nation.id),
			nation.granary_food, nation.last_food_demand,
			nation.food_demand_ema, nation.treasury_gold,
			nation.manpower_pool,
			nation.ruler_revision, nation.ruler_archetype,
			nation.ruler_traits,
			RulerProfile.court_expense_rate(nation),
			float(modifiers[RulerProfile.KEY_FOOD_CONSUMPTION]),
			int(modifiers[RulerProfile.KEY_RESERVE_MONTHS]),
			float(modifiers[RulerProfile.KEY_UPKEEP]),
		])
	for army in state.armies:
		if army.size <= 0:
			continue
		fields.append([
			"army", army.owner_nation, army.size,
		])
	return var_to_bytes(fields)

static func _trade_summary_settlement_token(
	state: GameState,
	structure_fingerprint: PackedByteArray,
	wartime_mask: PackedByteArray = PackedByteArray()
) -> PackedByteArray:
	var effective_wartime_mask := (
		wartime_mask
		if wartime_mask.size() == state.nations.size()
		else TradeNetwork.wartime_nation_mask(state)
	)
	var fields: Array = [
		"trade_summary_settlement_v1",
		["family_revision", state.family_revision],
		structure_fingerprint,
		["wartime_nations", effective_wartime_mask],
		["diplomacy_revision", state.diplomacy_revision],
	]
	for city in state.cities:
		fields.append([
			"city", city.id, city.garrison_manpower,
			Simulation.city_war_disrupted(state, city),
		])
	var suzerainty_subjects := state.suzerainty.keys()
	suzerainty_subjects.sort()
	for subject_value in suzerainty_subjects:
		var subject_id := int(subject_value)
		var record: Dictionary = state.suzerainty[subject_value]
		fields.append([
			"suzerainty", subject_id,
			int(record.get("overlord_id", -1)),
			float(record.get("tribute_rate", 0.0)),
			bool(record.get("civil_war", false)),
		])
	for nation in state.nations:
		var modifiers := RulerProfile.modifiers(nation)
		fields.append([
			"nation", nation.id, nation.alive,
			nation.ruler_revision, nation.ruler_archetype,
			nation.ruler_traits,
			RulerProfile.court_expense_rate(nation),
			float(modifiers[RulerProfile.KEY_UPKEEP]),
		])
	var field_upkeep_units: Array[int] = []
	field_upkeep_units.resize(state.nations.size())
	field_upkeep_units.fill(0)
	for army in state.armies:
		if (
			army.size <= 0
			or army.owner_nation < 0
			or army.owner_nation >= field_upkeep_units.size()
		):
			continue
		field_upkeep_units[state.financial_nation_of(army.owner_nation)] += (
			GameState.army_monthly_upkeep(army.size)
		)
	fields.append(["field_upkeep_units", field_upkeep_units])
	return var_to_bytes(fields)
