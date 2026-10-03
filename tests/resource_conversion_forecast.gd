extends SceneTree
var valid := true
func _init() -> void:
	var policy := {"targets": [20, 1000, 500], "hard_targets": [0, 0, 0], "capacities": [1000000, 10000, 10000]}
	var unchanged := ResourceBalanceRules.plan(100, 2000, 1000, 1000, true, policy)
	_check(unchanged.transferred_value == 0, "no shortfall no exchange")
	policy.hard_targets = [120, 0, 0]
	policy.targets = [120, 1000, 2500]
	var result := ResourceBalanceRules.plan(100, 10000, 0, 40, true, policy)
	_check(result.gold_delta == 10 and result.food_delta == 0, "hard deficit precedes reserve")
	_check(result.gold_delta * 50 + result.manpower_delta + result.food_delta * 2 == 0, "integer value conserved")
	policy.targets = [100, 10000, 0]
	policy.hard_targets = [100, 10000, 0]
	_check(ResourceBalanceRules.plan(100, 10000, 0, 40, true, policy).transferred_value == 0, "no protected resource donations")
	policy.targets = [20, 1000, 1000]
	policy.hard_targets = [0, 0, 1000]
	policy.capacities = [1000000, 10000, 75]
	var capped := ResourceBalanceRules.plan(100, 1000, 24, 1000, true, policy)
	_check(capped.food_delta == 50 and 24 + int(capped.food_delta) <= 75, "receiving capacity includes unchanged fractional bundle remainder")
	_check(capped.gold_delta * 50 + capped.manpower_delta + capped.food_delta * 2 == 0, "capacity-limited allocation still conserves bundles")
	print("resource_conversion_forecast: %s" % ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
func _check(value: bool, label: String) -> void:
	if not value:
		valid = false
		push_error(label)
