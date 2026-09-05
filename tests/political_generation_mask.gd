extends SceneTree
## Political masks are applied after natural topology generation. Settlements
## outside the mask remain geographic nodes but start inactive and uncolored.


func _init() -> void:
	var mask_path := "user://political-generation-mask.png"
	var fixture := TerrainMapGenerator.build(
		GameState.terrain_map_path(), 48, "", {}, 0, 4
	)
	var mask_size: Vector2i = fixture["image_size"]
	var mask := Image.create(
		mask_size.x, mask_size.y, false, Image.FORMAT_RGB8
	)
	mask.fill(Color.BLACK)
	for y in range(mask_size.y):
		for x in range(int(mask_size.x * 0.90)):
			mask.set_pixel(x, y, Color.WHITE)
	if mask.save_png(mask_path) != OK:
		_fail("could not write political mask")
		return
	var state := GameState.new()
	state.generate_world(13579, 4, 48, "", {}, 0, mask_path)
	var active := 0
	var inactive := 0
	for city in state.land_cities():
		if city.politically_active:
			active += 1
			if city.owner_nation < 0:
				_fail("active city has no owner")
				return
		else:
			inactive += 1
			if city.owner_nation != -1:
				_fail("inactive city received a nation")
				return
	var overlay := MapRenderer.build_province_overlay_image(state)
	var inactive_pixels := 0
	for y in range(state.province_map_size.y):
		for x in range(state.province_map_size.x):
			var index := y * state.province_map_size.x + x
			var province_id := state.province_ids[index]
			if (
				province_id >= 0
				and not state.cities[province_id].politically_active
			):
				inactive_pixels += 1
				if overlay.get_pixel(x, y).a > 0.001:
					_fail("inactive province received political color")
					return
	if active < state.nations.size() or inactive <= 0 or inactive_pixels <= 0:
		_fail("mask did not produce both active and inactive geography")
		return
	var packed_height := (
		load(GameState.terrain_map_path()) as Texture2D
	).get_image()
	var base_images := MapRenderer.build_political_base_images(
		state.province_map_size * MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE,
		packed_height
	)
	var visual_pixel := Vector2i(-1, -1)
	var ocean_image := base_images["ocean"] as Image
	for province_y in range(state.province_map_size.y):
		for province_x in range(state.province_map_size.x):
			var province_id := state.province_ids[
				province_y * state.province_map_size.x + province_x
			]
			if (
				province_id < 0
				or state.cities[province_id].politically_active
			):
				continue
			var candidate := Vector2i(province_x, province_y)
			candidate *= MapRenderer.PROVINCE_VISUAL_SUPERSAMPLE
			candidate += Vector2i.ONE * 2
			if ocean_image.get_pixelv(candidate).a <= 0.001:
				visual_pixel = candidate
				break
		if visual_pixel.x >= 0:
			break
	if visual_pixel.x < 0:
		_fail("could not find an inactive land visual pixel")
		return
	var white_base := (base_images["land"] as Image).get_pixelv(visual_pixel)
	var ocean_overlay := ocean_image.get_pixelv(visual_pixel)
	var expected_white := MapRenderer.POLITICAL_LAND_BASE_COLOR
	if (
		maxf(
			absf(white_base.r - expected_white.r),
			maxf(
				absf(white_base.g - expected_white.g),
				absf(white_base.b - expected_white.b)
			)
		) > 0.01
		or ocean_overlay.a > 0.001
	):
		_fail("inactive land did not retain the white terrain base")
		return
	for army in state.armies:
		if army.owner_nation < 0:
			_fail("inactive geography generated an army")
			return
	var definition := MapDefinition.from_state(state)
	var validation_error := MapDefinition.validate(definition)
	if not validation_error.is_empty():
		_fail("political map definition was invalid: " + validation_error)
		return
	var restored := GameState.new()
	restored.generate_from_map_definition(definition, 13579)
	if restored.political_mask_path != mask_path:
		_fail("political mask path was not restored")
		return
	for city_id in range(state.cities.size()):
		if (
			restored.cities[city_id].politically_active
			!= state.cities[city_id].politically_active
			or restored.cities[city_id].owner_nation
			!= state.cities[city_id].owner_nation
		):
			_fail("political city state changed during map round trip")
			return
	var simulation := Simulation.new()
	simulation.setup(restored)
	for _day in range(30):
		simulation._advance_day()
	for city in restored.cities:
		if not city.politically_active and city.owner_nation != -1:
			_fail("inactive city entered politics during simulation")
			simulation.free()
			return
	simulation.free()
	print("POLITICAL_GENERATION_MASK_OK active=%d inactive=%d" % [
		active, inactive,
	])
	quit(0)


func _fail(message: String) -> void:
	push_error("POLITICAL_GENERATION_MASK_FAILED: " + message)
	quit(1)
