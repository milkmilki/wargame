class_name EconomyRules
extends RefCounted
## Pure monthly fiscal aggregation. Simulation supplies policy callbacks so
## this module does not own campaign, ruler, or cache lifecycle state.


static func monthly_gold_flows_from_trade(
	state: GameState,
	trade: Dictionary,
	effective_upkeep: Callable,
	city_output: Callable,
	tribute_rate: Callable
) -> Array[Dictionary]:
	var upkeep_by_nation := _upkeep_by_nation(state, effective_upkeep)
	var result := _empty_reports(state, trade, upkeep_by_nation)
	_add_city_income(state, result, city_output)
	_add_tribute_flows(state, result, tribute_rate)
	_finalize_balances(result)
	return result


static func _upkeep_by_nation(
	state: GameState,
	effective_upkeep: Callable
) -> Array[int]:
	var result: Array[int] = []
	result.resize(state.nations.size())
	result.fill(0)
	for army in state.armies:
		if (
			army.size <= 0
			or army.owner_nation < 0
			or army.owner_nation >= result.size()
		):
			continue
		result[army.owner_nation] += GameState.army_monthly_upkeep(army.size)
	for nation in state.nations:
		result[nation.id] = int(effective_upkeep.call(
			state, nation.id, result[nation.id]
		))
	return result


static func _empty_reports(
	state: GameState,
	trade: Dictionary,
	upkeep_by_nation: Array[int]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for nation in state.nations:
		var food_trade_income := trade_array_value(
			trade, "nation_food_sale_income", nation.id
		)
		var food_trade_expense := trade_array_value(
			trade, "nation_food_cost", nation.id
		)
		var manpower_trade_expense := trade_array_value(
			trade, "nation_manpower_cost", nation.id
		)
		var trade_gross_income := trade_array_value(
			trade, "nation_trade_gold", nation.id
		)
		var trade_tax_income := maxi(
			trade_gross_income - food_trade_income, 0
		)
		var trade_net_income := (
			trade_tax_income
			+ food_trade_income
			- food_trade_expense
			- manpower_trade_expense
		)
		result.append({
			"nation_id": nation.id,
			"city_income": 0,
			"trade_tax_income": trade_tax_income,
			"food_trade_income": food_trade_income,
			"food_trade_expense": food_trade_expense,
			"manpower_trade_expense": manpower_trade_expense,
			"trade_net_income": trade_net_income,
			"tribute_received": 0,
			"tribute_paid": 0,
			"net_income": 0,
			"military_upkeep": upkeep_by_nation[nation.id],
			"balance": 0,
		})
	return result


static func _add_city_income(
	state: GameState,
	result: Array[Dictionary],
	city_output: Callable
) -> void:
	for city in state.cities:
		if city.owner_nation < 0 or city.owner_nation >= result.size():
			continue
		result[city.owner_nation]["city_income"] = (
			int(result[city.owner_nation]["city_income"])
			+ int(city_output.call(state, city))
		)


static func _add_tribute_flows(
	state: GameState,
	result: Array[Dictionary],
	tribute_rate: Callable
) -> void:
	for subject_value in state.suzerainty:
		var subject_id := int(subject_value)
		var overlord_id := state.overlord_of(subject_id)
		if (
			subject_id < 0
			or subject_id >= result.size()
			or overlord_id < 0
			or overlord_id >= result.size()
		):
			continue
		var tribute := int(floor(
			float(result[subject_id]["city_income"])
			* float(tribute_rate.call(state, subject_id))
		))
		result[subject_id]["tribute_paid"] = (
			int(result[subject_id]["tribute_paid"]) + tribute
		)
		result[overlord_id]["tribute_received"] = (
			int(result[overlord_id]["tribute_received"]) + tribute
		)


static func _finalize_balances(result: Array[Dictionary]) -> void:
	for nation_id in range(result.size()):
		var report: Dictionary = result[nation_id]
		var net_income := (
			int(report["city_income"])
			+ int(report["trade_net_income"])
			+ int(report["tribute_received"])
			- int(report["tribute_paid"])
		)
		report["net_income"] = net_income
		report["balance"] = net_income - int(report["military_upkeep"])


static func trade_array_value(
	trade_snapshot: Dictionary,
	key: String,
	index: int
) -> int:
	var values: Variant = trade_snapshot.get(key, [])
	if not (values is Array) or index < 0 or index >= values.size():
		return 0
	return int(values[index])
