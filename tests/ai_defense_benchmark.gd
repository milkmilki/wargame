extends SceneTree
## 正式地图驻防规划隔离基准。手动运行，不纳入快速回归。

const ITERATIONS: int = 100


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var fixtures: Array[Dictionary] = []
	var shared_path_cache := {}
	var shared_threat_cache := {}
	for nation in state.nations:
		var view := AiWorldView.build(
			state,
			nation.id,
			shared_path_cache
		)
		fixtures.append({
			"view": view,
			"snapshot": StrategicMapSnapshot.build(view),
			"threat": ThreatField.build(
				view,
				shared_threat_cache
			),
		})
	for fixture in fixtures:
		CityDefensePlan.build(
			fixture["view"],
			fixture["snapshot"],
			fixture["threat"]
		)
	var started := Time.get_ticks_usec()
	var assignments := 0
	for _iteration in range(ITERATIONS):
		for fixture in fixtures:
			var plan := CityDefensePlan.build(
				fixture["view"],
				fixture["snapshot"],
				fixture["threat"]
			)
			assignments += plan.assigned_city_by_army.size()
	var elapsed_usec := Time.get_ticks_usec() - started
	print(
		"iterations=%d plans=%d assignments=%d elapsed_ms=%.3f us_per_plan=%.3f"
		% [
			ITERATIONS,
			ITERATIONS * fixtures.size(),
			assignments,
			float(elapsed_usec) / 1000.0,
			float(elapsed_usec)
				/ float(ITERATIONS * fixtures.size()),
		]
	)
	quit()
