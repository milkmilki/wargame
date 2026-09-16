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
	state.nations[0].ruler_archetype = RulerProfile.INEPT
	state.day = Simulation.DAYS_PER_YEAR * 12
	var expected_capital_bonus := 0
	for owned_city in state.land_cities_of(0):
		expected_capital_bonus += owned_city.gold_per_month
	expected_capital_bonus = int(floor(float(expected_capital_bonus) * 0.20))
	var expected_gold_output := int(floor(
		float(city.gold_per_month + expected_capital_bonus)
			* RulerProfile.gold_output_multiplier(state.nations[0])
	))
	var detail := Simulation.city_output_breakdown(state, city)
	var lines := "|".join(MapRenderer.city_detail_lines(state, city.id))
	var valid := (
		int(detail.get("gold_output", -1)) == expected_gold_output
		and int(detail.get("gold_output", -1))
			== Simulation.city_gold_output(state, city)
		and int(detail.get("food_output", -1))
			== Simulation.city_food_output(state, city)
		and int(detail.get("manpower_output", -1))
			== Simulation.city_manpower_output(state, city)
		and int(detail.get("capital_gold_addition", -1))
			== expected_capital_bonus
		and is_equal_approx(
			float(detail.get("terrain_multiplier", 0.0)), 0.75
		)
		and "基础产值" in lines
		and "地形与发展" in lines
		and "首都加成" in lines
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
