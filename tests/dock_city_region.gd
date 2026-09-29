extends SceneTree

const ATLAS := preload("res://scripts/view/map_visual_atlas.gd")
const VORONOI := preload("res://scripts/view/visual_weighted_voronoi.gd")

var _failed := false


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var dock_ids := {}
	var land_count := 0
	for city in state.cities:
		if city.is_dock:
			dock_ids[city.id] = true
		else:
			land_count += 1
	_assert(not dock_ids.is_empty(), "generated world must contain docks")

	var seeds := ATLAS.visual_city_seeds(state)
	_assert(seeds.size() == land_count, "every land city must remain a visual seed")
	for seed in seeds:
		_assert(
			not dock_ids.has(int(seed.get("city_id", -1))),
			"dock must not be a visual city-region seed"
		)

	var height_texture := load(GameState.terrain_map_path()) as Texture2D
	var regions := VORONOI.build_visual_city_ids(
		height_texture.get_image(), seeds,
		Vector2i(256, 256), 32.0, Vector2i(128, 128)
	)
	var ids := regions["city_ids"] as Image
	var land := regions["land_mask"] as Image
	var assigned_pixels := 0
	for y in range(ids.get_height()):
		for x in range(ids.get_width()):
			if land.get_pixel(x, y).r < 0.5:
				continue
			var city_id := int(round(ids.get_pixel(x, y).r))
			if city_id < 0:
				continue
			assigned_pixels += 1
			_assert(not dock_ids.has(city_id), "dock received a visual land region")
	_assert(assigned_pixels > 0, "visual atlas must assign land-city regions")

	for dock_value in dock_ids:
		var dock_id := int(dock_value)
		_assert(
			state.administrative_region_ids[dock_id] < 0,
			"dock must remain outside administrative regions"
		)
		var dock := state.cities[dock_id]
		_assert(
			MapHitTesting.pick_city_at_pixel(
				state, dock.map_position, Vector2.ZERO, Vector2.ONE, 0.001
			) == dock_id,
			"removing the land region must not remove dock icon hit testing"
		)

	if _failed:
		quit(1)
		return
	print("DOCK_CITY_REGION PASS docks=", dock_ids.size())
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("DOCK_CITY_REGION_FAILED: " + message)
