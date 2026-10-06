extends SceneTree
## Compare every report field with the frozen pre-optimization event loop.
## Optional same-process timing: RESOURCE_FORECAST_BENCH=1.

const REFERENCE = preload("res://tests/fixtures/resource_forecast_reference.gd")

func _init() -> void:
	var legacy := REFERENCE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261006
	var checks := 0
	for sample in range(1200):
		var consumers: Array = []
		var monthly := 0.0
		for i in range(rng.randi_range(0, 12)):
			var rate := rng.randf_range(0, 300)
			monthly += rate
			consumers.append({"rate": rate, "debt": rng.randf(), "increment": i % 3 == 0})
		var input := {
			"day": rng.randi_range(0, 1095),
			"gold": rng.randi_range(-5, 1000),
			"food": rng.randi_range(-5, 10000),
			"income": rng.randi_range(0, 100),
			"court": rng.randi_range(0, 50),
			"upkeep": rng.randi_range(0, 100),
			"field_food": monthly, "consumers": consumers,
			"food_debt": rng.randf(), "pending_supply_days": sample % 2,
			"garrison_food": rng.randi_range(0, 100),
			"harvest": rng.randi_range(0, 10000),
			"food_capacity": rng.randi_range(0, 10000),
			"trade_food": rng.randi_range(-100, 100),
			"food_months": sample % 27, "gold_months": sample % 45,
			"necessary_gold": rng.randi_range(0, 100),
		}
		if sample % 3 == 0:
			var table := {}
			for elapsed in range(362):
				if elapsed % 4 != 0:
					table[elapsed] = legacy._field_consumption(input, {}, monthly, elapsed)
			input.consumption = table
		var change := {"field_food_delta": rng.randf_range(-monthly, 500), "upkeep_delta": rng.randi_range(-100, 100)}
		if sample % 5 == 0:
			change.replace_consumers = false # presence, not truthiness, is the existing rule.
		var expected: Dictionary = legacy.evaluate(input, change)
		var actual := ResourceForecastRules.evaluate(input, change)
		if expected != actual:
			push_error("forecast mismatch sample=%d expected=%s actual=%s" % [sample, expected, actual])
			quit(1)
			return
		checks += actual.size()
	print("FORECAST_EQUIVALENCE PASS samples=1200 fields=%d" % checks)
	if OS.get_environment("RESOURCE_FORECAST_BENCH") == "1":
		_benchmark()
	quit()


func _benchmark() -> void:
	var legacy := REFERENCE
	var fixture := {"day": 123, "food": 3000, "food_capacity": 10000, "harvest": 1000, "field_food": 201.0, "consumption": {0: 0, 6: 40, 7: 46}, "consumers": [{"rate": 201.0, "debt": 0.8}]}
	var legacy_usec := 0
	var candidate_usec := 0
	for round in range(8):
		for mode in range(2):
			var old := (round + mode) % 2 == 0
			var started := Time.get_ticks_usec()
			for i in range(2500):
				var delta := {"field_food_delta": float(i % 100)}
				if i % 2 == 0:
					delta.replace_consumers = true
				if old:
					legacy.evaluate(fixture, delta)
				else:
					ResourceForecastRules.evaluate(fixture, delta)
			var elapsed := Time.get_ticks_usec() - started
			if old:
				legacy_usec += elapsed
			else:
				candidate_usec += elapsed
	print("FORECAST_BENCH legacy_ms=%.3f candidate_ms=%.3f" % [legacy_usec / 1000.0, candidate_usec / 1000.0])
