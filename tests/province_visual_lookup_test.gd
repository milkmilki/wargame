extends SceneTree

const LOOKUP := preload("res://scripts/view/province_visual_lookup.gd")

var _failed: bool = false


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var lookup := LOOKUP.build_id_image(
		state.province_map_size, state.province_ids, 3,
		MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
	)
	_assert(
		lookup.get_size()
			== state.province_map_size * MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE,
		"province ID lookup must use the existing visual resolution"
	)
	var source_pixel := _first_owned_pixel(state)
	var encoded := lookup.get_pixel(
		source_pixel.x * MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE,
		source_pixel.y * MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
	)
	_assert(
		LOOKUP.decode_province_id(encoded)
			== state.province_ids[
				source_pixel.y * state.province_map_size.x + source_pixel.x
			],
		"province ID lookup must round-trip the source province"
	)
	_assert(
		LOOKUP.decode_stripe(encoded)
			== ((source_pixel.x + source_pixel.y) % 9 < 3),
		"lookup must preserve the existing occupation stripe phase"
	)

	var political := LOOKUP.build_visual_lut(state)
	_assert(political.get_height() == 2, "visual LUT must contain base and occupation rows")
	for city_id in range(state.cities.size()):
		var expected := _expected_political_color(state, city_id, -1)
		_assert_color(
			political.get_pixel(city_id, LOOKUP.BASE_ROW),
			expected[0],
			"political base LUT mismatch for city %d" % city_id
		)
		_assert_color(
			political.get_pixel(city_id, LOOKUP.OCCUPATION_ROW),
			expected[1],
			"political occupation LUT mismatch for city %d" % city_id
		)
	var diplomatic := LOOKUP.build_visual_lut(state, 0)
	for city_id in range(state.cities.size()):
		var expected_diplomatic := _expected_political_color(state, city_id, 0)
		_assert_color(
			diplomatic.get_pixel(city_id, LOOKUP.BASE_ROW),
			expected_diplomatic[0],
			"diplomatic LUT mismatch for city %d" % city_id
		)
		_assert(
			diplomatic.get_pixel(city_id, LOOKUP.OCCUPATION_ROW).a < 0.001,
			"diplomatic LUT must classify current control without stripes"
		)
	var legacy_fill := MapRenderer._dilate_political_fill(
		MapRenderer.build_province_overlay_image(state), 3
	)
	legacy_fill.resize(
		lookup.get_width(), lookup.get_height(), Image.INTERPOLATE_NEAREST
	)
	var visual_scale := MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
	for y in range(0, lookup.get_height(), visual_scale):
		for x in range(0, lookup.get_width(), visual_scale):
			var id_pixel := lookup.get_pixel(x, y)
			var province_id := LOOKUP.decode_province_id(id_pixel)
			var lookup_color := Color.TRANSPARENT
			if province_id >= 0 and province_id < political.get_width():
				lookup_color = political.get_pixel(province_id, LOOKUP.BASE_ROW)
				var occupation := political.get_pixel(
					province_id, LOOKUP.OCCUPATION_ROW
				)
				if LOOKUP.decode_stripe(id_pixel) and occupation.a > 0.5:
					lookup_color = occupation
			_assert_color(
				lookup_color,
				legacy_fill.get_pixel(x, y),
				"lookup render differs from the legacy fill at %d,%d" % [x, y]
			)

	var loyalty := LOOKUP.build_visual_lut(state, -1, true)
	for city_id in range(state.cities.size()):
		var expected_loyalty := (
			MapRenderer.loyalty_color(state.cities[city_id].loyalty)
			if state.cities[city_id].politically_active
			else Color.TRANSPARENT
		)
		_assert_color(
			loyalty.get_pixel(city_id, LOOKUP.BASE_ROW),
			expected_loyalty,
			"loyalty LUT mismatch for city %d" % city_id
		)
		_assert(
			loyalty.get_pixel(city_id, LOOKUP.OCCUPATION_ROW).a < 0.001,
			"loyalty LUT must not contain occupation stripes"
		)
	var topology := MapRenderer.build_province_boundary_topology(state)
	var complete_geometry := MapRenderer.classify_province_boundary_topology(
		state, topology
	)
	var city_owners := PackedInt32Array()
	city_owners.resize(state.cities.size())
	for city_id in range(state.cities.size()):
		city_owners[city_id] = state.cities[city_id].owner_nation
	var lookup_geometry := LOOKUP.build_country_boundary_geometry(
		topology, city_owners
	)
	for key in [
		"province", "country", "country_owner_a", "country_owner_b",
		"country_side_a", "country_side_b",
	]:
		_assert(
			lookup_geometry[key] == complete_geometry[key],
			"compact country-boundary classification mismatch: %s" % key
		)

	if _failed:
		quit(1)
	else:
		print("PROVINCE_VISUAL_LOOKUP_TEST PASS")
		quit(0)


func _first_owned_pixel(state: GameState) -> Vector2i:
	for y in range(state.province_map_size.y):
		for x in range(state.province_map_size.x):
			if state.province_ids[y * state.province_map_size.x + x] >= 0:
				return Vector2i(x, y)
	return Vector2i.ZERO


func _expected_political_color(
	state: GameState, city_id: int, view_nation_id: int
) -> Array[Color]:
	var city := state.cities[city_id]
	if not city.politically_active:
		return [Color.TRANSPARENT, Color.TRANSPARENT]
	var current_owner := city.owner_nation
	var recognized_owner := state.recognized_owner_of(city_id)
	if recognized_owner < 0:
		recognized_owner = current_owner
	var display_owner := current_owner if view_nation_id >= 0 else recognized_owner
	var base := MapRenderer.political_map_color_for_view(
		state, display_owner, view_nation_id
	)
	base.a = 1.0
	var occupation := Color.TRANSPARENT
	if view_nation_id < 0 and current_owner != recognized_owner:
		occupation = MapRenderer.political_map_color_for_view(
			state, current_owner, view_nation_id
		).darkened(0.08)
		occupation.a = 1.0
	return [base, occupation]


func _assert_color(actual: Color, expected: Color, message: String) -> void:
	var tolerance := 1.0 / 255.0 + 0.00001
	_assert(
		absf(actual.r - expected.r) <= tolerance
			and absf(actual.g - expected.g) <= tolerance
			and absf(actual.b - expected.b) <= tolerance
			and absf(actual.a - expected.a) <= tolerance,
		"%s: %s != %s" % [message, actual, expected]
	)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
