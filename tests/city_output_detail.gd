extends SceneTree
## City details expose every factor used by the actual output settlement.


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(92032)
	var city := state.cities[state.nations[0].capital_city_id]
	city.gold_per_month = 20
	city.food_per_half_year = 120
	city.manpower_per_month = 8
	city.terrain_output_multiplier = 0.75
	city.development_gold_multiplier = 1.25
	city.development_food_multiplier = 1.40
	city.capital_since_day = 0
	state.day = Simulation.DAYS_PER_YEAR * 12
	var detail := Simulation.city_output_breakdown(state, city)
	var lines := "|".join(MapRenderer.city_detail_lines(state, city.id))
	var valid := (
		int(detail.get("gold_output", -1))
			== Simulation.city_gold_output(state, city)
		and int(detail.get("food_output", -1))
			== Simulation.city_food_output(state, city)
		and int(detail.get("manpower_output", -1))
			== Simulation.city_manpower_output(state, city)
		and int(detail.get("capital_gold_bonus", -1)) == 12
		and is_equal_approx(
			float(detail.get("terrain_multiplier", 0.0)), 0.75
		)
		and "基础产值" in lines
		and "地形与发展" in lines
		and "首都发展" in lines
		and "治理与君主" in lines
		and "战乱与驻军" in lines
		and "贸易" in lines
	)
	if valid:
		print("CITY_OUTPUT_DETAIL_OK %s" % str(detail))
		quit(0)
		return
	push_error("CITY_OUTPUT_DETAIL_FAILED detail=%s lines=%s" % [
		str(detail), lines,
	])
	quit(1)
