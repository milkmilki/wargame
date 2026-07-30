extends SceneTree
## 真实地图纯和平粮食诊断：隔离外交与战争，只验证裁军后粮食收支收敛。

const DAYS: int = 1080


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.diplomacy_enabled = false
	var half_year_snapshots := {}
	for nation in state.nations:
		half_year_snapshots[nation.id] = [] as Array[int]
	for _day in range(DAYS):
		simulation._advance_day()
		if state.day % Simulation.DAYS_PER_HALF_YEAR != 0:
			continue
		for nation in state.nations:
			half_year_snapshots[nation.id].append(nation.granary_food)
	var failed := false
	for nation in state.nations:
		var snapshots: Array[int] = half_year_snapshots[nation.id]
		var report := simulation._food_security_report(nation.id)
		var army_count := 0
		var troops := 0
		var formations: Array[String] = []
		for army in state.armies:
			if army.owner_nation == nation.id:
				army_count += 1
				troops += army.size
				formations.append("%d:%d@%d" % [
					army.state,
					army.size,
					army.location_city,
				])
		print(
			(
				"nation=%d snapshots=%s armies=%d troops=%d demand=%.1f "
				+ "production=%.1f annual_surplus=%.1f runway=%.1f"
			)
			% [
				nation.id,
				str(snapshots),
				army_count,
				troops,
				report["monthly_demand"],
				report["monthly_production"],
				report["annual_surplus"],
				report["runway_years"],
			]
		)
		print("  formations=%s last_force=%s" % [
			str(formations),
			nation.ai_last_force_reason,
		])
		if (
			snapshots.size() < 6
			or snapshots[-1] < snapshots[-2]
			or float(report["annual_surplus"]) < -0.01
			or nation.granary_food <= 0
		):
			failed = true
	simulation.free()
	quit(1 if failed else 0)
