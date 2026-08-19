extends SceneTree
## Optional black/white city mask: white permits, black forbids, and clearing
## the path restores all real positive-elevation land.

func _init() -> void:
	var mask_path := "/private/tmp/world-war-half-city-mask.png"
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	for y in range(64):
		for x in range(32, 64):
			image.set_pixel(x, y, Color.WHITE)
	if image.save_png(mask_path) != OK:
		_fail("could not create temporary mask")
		return
	var validation := TerrainMapGenerator.validate_city_mask(
		GameState.terrain_map_path(), mask_path, 48
	)
	if not bool(validation.get("ok", false)):
		_fail(str(validation.get("error", "mask validation failed")))
		return
	var masked := GameState.new()
	masked.generate_world(13579, 4, 48, mask_path)
	for city in masked.land_cities():
		if city.map_position.x < 0.5:
			_fail("black half generated a city")
			return
	var unrestricted := GameState.new()
	unrestricted.generate_world(13579, 4, 48, "")
	var outside_default := 0
	var default_mask := (
		load(GameState.DEFAULT_CITY_MASK_PATH) as Texture2D
	).get_image()
	for city in unrestricted.land_cities():
		var x := clampi(int(city.map_position.x * default_mask.get_width()), 0, default_mask.get_width() - 1)
		var y := clampi(int(city.map_position.y * default_mask.get_height()), 0, default_mask.get_height() - 1)
		if default_mask.get_pixel(x, y).get_luminance() < 0.5:
			outside_default += 1
	if outside_default <= 0:
		_fail("clearing the mask did not restore non-China real land")
		return
	var bad := TerrainMapGenerator.validate_city_mask(
		GameState.terrain_map_path(), "/private/tmp/does-not-exist-mask.png", 48
	)
	if bool(bad.get("ok", false)):
		_fail("missing mask must be rejected")
		return
	print(
		"CITY_GENERATION_MASK_OK masked=", masked.land_cities().size(),
		" unrestricted=", unrestricted.land_cities().size(),
		" outside_default=", outside_default
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("CITY_GENERATION_MASK_FAILED: " + message)
	quit(1)
