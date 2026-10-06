extends SceneTree
## Off-cycle planning must not pay for unused force-review food capacity.

class ReviewSimulation extends Simulation:
	var food_reports: Array[Vector2i] = []

	func _food_security_report(nation_id: int, armies: Array[Army] = [], cache: Dictionary = {}) -> Dictionary:
		food_reports.append(Vector2i(state.day, nation_id))
		return super._food_security_report(nation_id, armies, cache)


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345, 4, 20)
	var sim := ReviewSimulation.new()
	root.add_child(sim)
	sim.setup(state)
	# Isolate scheduled force reviews from declaration-driven mobilization.
	sim.diplomacy_enabled = false
	for day in range(50):
		sim._advance_day(false)
	var off_cycle := 0
	for report in sim.food_reports:
		if not Simulation._force_structure_review_due(report.y, report.x):
			off_cycle += 1
	var passed := off_cycle == 0 and not sim.food_reports.is_empty()
	print("AI_FORCE_REVIEW_SCHEDULE %s reports=%d off_cycle=%d" % [
		"PASS" if passed else "FAIL", sim.food_reports.size(), off_cycle
	])
	sim.free()
	quit(0 if passed else 1)
