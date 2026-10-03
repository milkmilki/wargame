extends SceneTree
var valid := true
func _init() -> void:
	var input := {"day": 30, "gold": 100, "income": 10, "upkeep": 15, "court": 3, "food": 50, "harvest": 600, "food_capacity": 1000, "field_food": 30.0, "garrison_food": 0, "trade_food": 0, "necessary_gold": 18, "gold_months": 6, "food_months": 6}
	var report := ResourceForecastRules.evaluate(input)
	_check(report.gold_min == 4 and report.gold_end == 4, "12 real monthly payments")
	_check(report.food_min < 0 and report.food_min_day < 180, "pre-harvest deficit despite annual surplus")
	_check(not report.feasible and report.food_deficit > 0, "deficit prevents new commitments")
	input.food = 300
	report = ResourceForecastRules.evaluate(input)
	_check(report.feasible, "stock can fund a deficit year")
	_check(not ResourceForecastRules.evaluate(input, {"gold_cost": 5}).feasible, "creation cost included")
	input.food_capacity = 200
	report = ResourceForecastRules.evaluate(input)
	_check(report.food_end <= 200 and report.food_target <= 200, "capacity clips harvest and target")
	input.day = 179
	input.food = 0
	input.food_capacity = 1000
	input.garrison_food = 5
	report = ResourceForecastRules.evaluate(input)
	_check(report.food_min == -5 and report.food_min_day == 180, "garrison consumption precedes harvest")
	var fractional := {"day": 1, "food": 100, "food_capacity": 1000, "field_food": 2.0, "consumers": [{"rate": 1.0, "debt": 0.9}, {"rate": 1.0, "debt": 0.1}]}
	_check(ResourceForecastRules.evaluate(fractional).food_end == 76, "per-army fractional debts survive event intervals")
	var rounded := {"consumers": [{"rate": 20.0, "debt": 0.3}]}
	_check(ResourceForecastRules._field_consumption(rounded, {"field_food_delta": 5.0}, 25.0, 1) == 1, "candidate increment cannot lose the grain carried by existing debt")
	rounded.consumers.append({"rate": 5.0, "debt": 0.0, "increment": true})
	_check(ResourceForecastRules._field_consumption(rounded, {}, 25.0, 1) == 1, "accepted increment keeps the same conservative rounding")
	fractional.day = 179
	fractional.food = 0
	fractional.harvest = 50
	fractional.garrison_food = 0
	fractional.field_food = 30.0
	fractional.consumers = []
	report = ResourceForecastRules.evaluate(fractional)
	_check(report.food_min_day >= 180, "harvest on same day precedes daily field supply")
	_check(ResourceForecastRules.evaluate({"gold": 100, "income": 5, "upkeep": 10}).feasible, "cash deficit with sufficient inventory remains legal")
	_check(not ResourceForecastRules.evaluate({"gold": 10, "income": 5, "upkeep": 10}).feasible, "future arrears blocks new commitments")
	_check(ResourceForecastRules.evaluate({"food": 100, "food_capacity": 1000, "trade_food": 20, "export_food": 5, "food_months": 6}).food_target == 30, "imports do not cancel the export reserve preference")
	print("resource_forecast: %s" % ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
func _check(value: bool, label: String) -> void:
	if not value:
		valid = false
		push_error(label)
