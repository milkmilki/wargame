extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	state.refresh_derived()
	var mismatches := 0
	for city in state.cities:
		var expected := RulerProfile.city_defense_multiplier(
			state.nations[city.owner_nation]
		)
		if not is_equal_approx(city.ruler_city_defense_multiplier, expected):
			if mismatches < 5:
				print("CITY id=%d owner=%d actual=%.9f expected=%.9f" % [
					city.id, city.owner_nation,
					city.ruler_city_defense_multiplier, expected,
				])
			mismatches += 1
	for army in state.armies:
		var ruler := state.nations[army.owner_nation]
		var expected_defense := RulerProfile.defense_multiplier(ruler)
		var expected_morale := RulerProfile.morale_multiplier(ruler)
		if (
			not is_equal_approx(army.ruler_defense_multiplier, expected_defense)
			or not is_equal_approx(army.ruler_morale_multiplier, expected_morale)
		):
			if mismatches < 5:
				print(
					"ARMY id=%d owner=%d defense=%.9f/%.9f morale=%.9f/%.9f"
					% [
						army.id, army.owner_nation,
						army.ruler_defense_multiplier, expected_defense,
						army.ruler_morale_multiplier, expected_morale,
					]
				)
			mismatches += 1
	print("REFRESH_DERIVED_MODIFIER_%s mismatches=%d" % [
		"OK" if mismatches == 0 else "FAILED", mismatches,
	])
	quit(0 if mismatches == 0 else 1)
