class_name ResourceForecastRules
extends RefCounted

const HORIZON_DAYS: int = 360
const MONTH_DAYS: int = 30
const HARVEST_DAYS: int = 180
const RECOVERY_MONTHS: int = 36
static var profiling_enabled: bool = false
static var _profile: Dictionary = {}

static func reset_profile() -> void:
	_profile = {"evaluations": 0, "elapsed_usec": 0, "peak_usec": 0, "gold_shortage": 0, "food_shortage": 0, "reserve_growth_denied": 0}

static func profile() -> Dictionary:
	return _profile.duplicate()

## Inputs are a frozen batch aggregate. Negative balances remain visible even
## if a later harvest would conceal a shortage; no future conquest is assumed.
static func evaluate(input: Dictionary, change: Dictionary = {}) -> Dictionary:
	var started := Time.get_ticks_usec() if profiling_enabled else 0
	var day := int(input.get("day", 0))
	var gold := float(input.get("gold", 0)) - float(change.get("gold_cost", 0))
	var food := float(input.get("food", 0))
	var gold_min := gold
	var food_min := food
	var gold_day := day
	var food_day := day
	var upkeep := float(input.get("upkeep", 0)) + float(change.get("upkeep_delta", 0))
	var field_food := maxf(float(input.get("field_food", 0)) + float(change.get("field_food_delta", 0)), 0)
	var garrison := float(input.get("garrison_food", 0))
	var trade := float(input.get("trade_food", 0))
	var capacity := float(input.get("food_capacity", 0))
	var monthly_balance := float(input.get("income", 0)) - float(input.get("court", 0)) - upkeep
	var previous := day
	var pending_days := int(input.get("pending_supply_days", 0))
	var consumed := _field_consumption(input, change, field_food, pending_days)
	food -= consumed
	if food < food_min:
		food_min = food
	var next_month := (day / MONTH_DAYS + 1) * MONTH_DAYS
	while previous < day + HORIZON_DAYS:
		var event_day := mini(next_month, day + HORIZON_DAYS)
		# The day before month settlement is a potential seasonal low point.
		var before_event := maxi(event_day - 1, previous)
		var total_consumed := _field_consumption(input, change, field_food, before_event - day + pending_days)
		food -= total_consumed - consumed
		consumed = total_consumed
		if food < food_min:
			food_min = food
			food_day = before_event
		if event_day == next_month:
			gold += monthly_balance
			if gold < gold_min:
				gold_min = gold
				gold_day = event_day
			# Real month settlement pays garrisons before the half-year harvest.
			food += trade - garrison
			if food < food_min:
				food_min = food
				food_day = event_day
			if event_day % HARVEST_DAYS == 0:
				food = minf(food + float(input.get("harvest", 0)), capacity)
			next_month += MONTH_DAYS
		total_consumed = _field_consumption(input, change, field_food, event_day - day + pending_days)
		food -= total_consumed - consumed
		consumed = total_consumed
		if food < food_min:
			food_min = food
			food_day = event_day
		previous = event_day
	var gold_target := maxf(float(input.get("necessary_gold", 0)) + float(change.get("upkeep_delta", 0)), 0) * int(input.get("gold_months", 0))
	var exports := float(input.get("export_food", maxf(-trade, 0)))
	var food_target := minf((field_food + garrison + exports) * int(input.get("food_months", 0)), capacity)
	var gold_gap := maxf(gold_target - float(input.get("gold", 0)), 0)
	var food_gap := maxf(food_target - float(input.get("food", 0)), 0)
	var reasons: Array[String] = []
	if gold_min < -0.00001:
		reasons.append("gold_shortage")
	if food_min < -0.00001:
		reasons.append("food_shortage")
	var result := {
		"gold_end": int(floor(gold)), "food_end": int(floor(food)),
		"gold_min": int(floor(gold_min)), "food_min": int(floor(food_min)),
		"gold_min_day": gold_day, "food_min_day": food_day,
		"gold_deficit": maxi(int(ceil(-gold_min)), 0), "food_deficit": maxi(int(ceil(-food_min)), 0),
		"gold_target": int(ceil(gold_target)), "food_target": int(ceil(food_target)),
		"gold_gap": int(ceil(gold_gap)), "food_gap": int(ceil(food_gap)),
		"gold_savings": int(ceil(gold_gap / RECOVERY_MONTHS)), "food_savings": food_gap / RECOVERY_MONTHS,
		"monthly_gold_balance": int(floor(monthly_balance)),
		"feasible": reasons.is_empty(), "reasons": reasons,
		"growth_allowed": reasons.is_empty() and gold >= minf(float(input.get("gold", 0)), gold_target) + gold_gap / 3.0 and food >= minf(float(input.get("food", 0)), food_target) + food_gap / 3.0,
	}
	if profiling_enabled:
		if _profile.is_empty():
			reset_profile()
		var elapsed := Time.get_ticks_usec() - started
		_profile.evaluations += 1
		_profile.elapsed_usec += elapsed
		_profile.peak_usec = maxi(int(_profile.peak_usec), elapsed)
		_profile.gold_shortage += int(gold_min < -0.00001)
		_profile.food_shortage += int(food_min < -0.00001)
		_profile.reserve_growth_denied += int(reasons.is_empty() and not result.growth_allowed)
	return result

static func _field_consumption(input: Dictionary, change: Dictionary, monthly: float, days: int) -> float:
	if input.has("consumption") and not change.has("replace_consumers"):
		return float(input.consumption.get(days, floor(monthly * days / MONTH_DAYS))) + ceil(maxf(float(change.get("field_food_delta", 0)), 0) * days / MONTH_DAYS - 0.000001)
	var consumers: Array = input.get("consumers", [])
	if consumers.is_empty() or change.has("replace_consumers"):
		return floor(monthly * days / MONTH_DAYS + float(input.get("food_debt", 0)) + 0.000001)
	var total := 0.0
	for consumer in consumers:
		var demand := float(consumer.rate) * days / MONTH_DAYS + float(consumer.debt)
		total += ceil(demand - 0.000001) if consumer.get("increment", false) else floor(demand + 0.000001)
	# Separate increments must not lose a grain carried by the original army's debt.
	return total + ceil(maxf(float(change.get("field_food_delta", 0)), 0) * days / MONTH_DAYS - 0.000001)
