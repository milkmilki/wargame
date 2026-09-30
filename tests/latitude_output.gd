extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var total_gold := 0
	var total_food := 0
	var valid := true
	for city in state.land_cities():
		total_gold += city.gold_per_month
		total_food += city.food_per_half_year
		var expected := RegionalStrategy.latitude_output_multiplier(RegionalStrategy.city_latitude(state, city))
		var actual = city.get("latitude_output_multiplier")
		valid = valid and actual != null and is_equal_approx(float(actual), expected)
	var definition := MapDefinition.from_state(state)
	var restored := GameState.new()
	restored.generate_from_map_definition(definition)
	for city in state.cities:
		valid = valid and restored.cities[city.id].gold_per_month == city.gold_per_month
		valid = valid and restored.cities[city.id].food_per_half_year == city.food_per_half_year
		valid = valid and restored.cities[city.id].get("latitude_output_multiplier") == city.get("latitude_output_multiplier")
	valid = valid and total_gold == state.land_cities().size() * GameState.TERRAIN_CITY_GOLD_TARGET_AVERAGE
	var legacy := definition.duplicate(true)
	for record in legacy["cities"]:
		record.erase("latitude_output_multiplier")
	var legacy_state := GameState.new()
	legacy_state.generate_from_map_definition(legacy)
	for city in legacy_state.cities:
		valid = valid and city.get("latitude_output_multiplier") == 1.0
	var fixture := GameState.new()
	fixture.uses_heightmap = true
	fixture.city_density_settings = {"latitude_min": 0.0, "latitude_max": 90.0}
	var original_food := 0
	for id in range(6):
		var city := City.new()
		city.id = id
		city.map_position = Vector2(0.5, float(id) / 5.0)
		city.terrain_height = 0.1
		city.gold_per_month = 3
		city.food_per_half_year = 170 + id
		fixture.cities.append(city)
		original_food += city.food_per_half_year
	fixture._initialize_terrain_development()
	var apportioned_food := 0
	var apportioned_gold := 0
	for city in fixture.cities:
		apportioned_food += city.food_per_half_year
		apportioned_gold += city.gold_per_month
		valid = valid and city.gold_per_month >= GameState.TERRAIN_CITY_GOLD_OUTPUT_MIN
		valid = valid and city.gold_per_month <= GameState.TERRAIN_CITY_GOLD_OUTPUT_MAX
	valid = valid and apportioned_food == original_food
	valid = valid and apportioned_gold == fixture.cities.size() * GameState.TERRAIN_CITY_GOLD_TARGET_AVERAGE
	valid = valid and fixture.cities[2].food_per_half_year > fixture.cities[5].food_per_half_year
	var grid := GameState.new()
	grid.generate_grid_world(12345)
	for city in grid.cities:
		valid = valid and city.latitude_output_multiplier == 1.0
	print("LATITUDE_OUTPUT_RESULT valid=%s gold=%d food=%d" % [valid, total_gold, total_food])
	quit(0 if valid else 1)
