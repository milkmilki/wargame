class_name ProvinceVisualLookup
extends RefCounted
## Builds the immutable province-ID raster and the small, mutable per-province
## visual lookup consumed by the 3D terrain shader.

const BASE_ROW: int = 0
const OCCUPATION_ROW: int = 1
const LUT_ROWS: int = 2
const INVALID_PROVINCE_CODE: int = 0
const MAX_PROVINCE_ID: int = 65534


static func build_id_image(
	size: Vector2i,
	province_ids: PackedInt32Array,
	dilation_radius: int = 0,
	visual_scale: int = 1
) -> Image:
	if size.x <= 0 or size.y <= 0 or province_ids.size() != size.x * size.y:
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var expanded_ids := province_ids.duplicate()
	var stripe_phase := PackedByteArray()
	stripe_phase.resize(expanded_ids.size())
	for y in range(size.y):
		for x in range(size.x):
			var index := y * size.x + x
			var province_id := expanded_ids[index]
			if province_id >= 0:
				assert(province_id <= MAX_PROVINCE_ID, "province ID exceeds RG8 encoding")
				stripe_phase[index] = 1 if (x + y) % 9 < 3 else 0
	_dilate_ids(expanded_ids, stripe_phase, size, dilation_radius)

	var pixels := PackedByteArray()
	pixels.resize(expanded_ids.size() * 4)
	for index in range(expanded_ids.size()):
		var code := (
			expanded_ids[index] + 1
			if expanded_ids[index] >= 0
			else INVALID_PROVINCE_CODE
		)
		var offset := index * 4
		pixels[offset] = code & 0xff
		pixels[offset + 1] = (code >> 8) & 0xff
		pixels[offset + 2] = 255 if stripe_phase[index] != 0 else 0
		pixels[offset + 3] = 255
	var image := Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_RGBA8, pixels
	)
	var scale := maxi(visual_scale, 1)
	if scale > 1:
		image.resize(size.x * scale, size.y * scale, Image.INTERPOLATE_NEAREST)
	return image


static func build_visual_lut(
	game_state: GameState,
	view_nation_id: int = -1,
	loyalty_mode: bool = false
) -> Image:
	var city_count := game_state.cities.size() if game_state != null else 0
	var image := Image.create(maxi(city_count, 1), LUT_ROWS, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if game_state == null:
		return image
	for city_id in range(city_count):
		var city := game_state.cities[city_id]
		if not city.politically_active:
			continue
		if loyalty_mode:
			image.set_pixel(
				city_id, BASE_ROW, MapRenderer.loyalty_color(city.loyalty)
			)
			continue
		var current_owner := city.owner_nation
		var recognized_owner := game_state.recognized_owner_of(city_id)
		if recognized_owner < 0:
			recognized_owner = current_owner
		var display_owner := (
			current_owner if view_nation_id >= 0 else recognized_owner
		)
		var base := MapRenderer.political_map_color_for_view(
			game_state, display_owner, view_nation_id
		)
		base.a = 1.0
		image.set_pixel(city_id, BASE_ROW, base)
		if view_nation_id < 0 and current_owner != recognized_owner:
			var occupation := MapRenderer.political_map_color_for_view(
				game_state, current_owner, view_nation_id
			).darkened(0.08)
			occupation.a = 1.0
			image.set_pixel(city_id, OCCUPATION_ROW, occupation)
	return image


static func decode_province_id(encoded: Color) -> int:
	var low := clampi(int(round(encoded.r * 255.0)), 0, 255)
	var high := clampi(int(round(encoded.g * 255.0)), 0, 255)
	var code := low | (high << 8)
	return code - 1 if code != INVALID_PROVINCE_CODE else -1


static func decode_stripe(encoded: Color) -> bool:
	return encoded.b > 0.5


static func build_country_boundary_geometry(
	topology: Dictionary,
	city_owners: PackedInt32Array
) -> Dictionary:
	var province: PackedVector2Array = topology.get(
		"province", PackedVector2Array()
	)
	var province_a: PackedInt32Array = topology.get(
		"province_a", PackedInt32Array()
	)
	var province_b: PackedInt32Array = topology.get(
		"province_b", PackedInt32Array()
	)
	var side_a: PackedVector2Array = topology.get(
		"province_side_a", PackedVector2Array()
	)
	var side_b: PackedVector2Array = topology.get(
		"province_side_b", PackedVector2Array()
	)
	var country := PackedVector2Array()
	var country_owner_a := PackedInt32Array()
	var country_owner_b := PackedInt32Array()
	var country_side_a := PackedVector2Array()
	var country_side_b := PackedVector2Array()
	var edge_count := mini(
		province.size() / 2,
		mini(
			mini(province_a.size(), province_b.size()),
			mini(side_a.size(), side_b.size())
		)
	)
	for edge_index in range(edge_count):
		var city_a := province_a[edge_index]
		var city_b := province_b[edge_index]
		if (
			city_a < 0 or city_a >= city_owners.size()
			or city_b < 0 or city_b >= city_owners.size()
			or city_owners[city_a] == city_owners[city_b]
		):
			continue
		country.append(province[edge_index * 2])
		country.append(province[edge_index * 2 + 1])
		country_owner_a.append(city_owners[city_a])
		country_owner_b.append(city_owners[city_b])
		country_side_a.append(side_a[edge_index])
		country_side_b.append(side_b[edge_index])
	return {
		"province": province,
		"country": country,
		"country_owner_a": country_owner_a,
		"country_owner_b": country_owner_b,
		"country_side_a": country_side_a,
		"country_side_b": country_side_b,
	}


static func _dilate_ids(
	ids: PackedInt32Array,
	stripe_phase: PackedByteArray,
	size: Vector2i,
	radius: int
) -> void:
	for _pass in range(maxi(radius, 0)):
		var previous_ids := ids.duplicate()
		var previous_phase := stripe_phase.duplicate()
		var changed := false
		for y in range(size.y):
			for x in range(size.x):
				var index := y * size.x + x
				if previous_ids[index] >= 0:
					continue
				var source_index := -1
				if x > 0 and previous_ids[index - 1] >= 0:
					source_index = index - 1
				elif x + 1 < size.x and previous_ids[index + 1] >= 0:
					source_index = index + 1
				elif y > 0 and previous_ids[index - size.x] >= 0:
					source_index = index - size.x
				elif y + 1 < size.y and previous_ids[index + size.x] >= 0:
					source_index = index + size.x
				if source_index < 0:
					continue
				ids[index] = previous_ids[source_index]
				stripe_phase[index] = previous_phase[source_index]
				changed = true
		if not changed:
			break
