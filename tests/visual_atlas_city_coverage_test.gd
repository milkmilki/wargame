extends SceneTree

const ATLAS := preload("res://scripts/view/map_visual_atlas.gd")


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var regions := MapRenderer.build_boundary_regions(state)
	var masks := MapRenderer.rasterize_boundary_regions(
		regions, ATLAS.SIZE, state
	)
	var height_texture := load(GameState.terrain_map_path()) as Texture2D
	var atlas := ATLAS.build_visual_atlas(
		state,
		height_texture.get_image(),
		ATLAS.SIZE,
		masks["province_id"],
		{"edge_mask": masks["edge_mask"]}
	)
	var failures: Array[String] = []
	var southern_samples: Array[Dictionary] = []
	var logical_city_ids := {}
	for city_id in state.province_ids:
		if city_id >= 0:
			logical_city_ids[city_id] = true
	for city in state.cities:
		if not city.politically_active or not logical_city_ids.has(city.id):
			continue
		var sampled_id := ATLAS.sample_city_id_uv(atlas, city.map_position)
		if sampled_id != city.id:
			failures.append(
				"city=%d y=%.4f sampled=%d" % [
					city.id, city.map_position.y, sampled_id,
				]
			)
		if city.map_position.y > 0.78:
			southern_samples.append({
				"city": city.id,
				"position": city.map_position,
				"sampled": sampled_id,
			})
			for offset_y in [-4, 0, 4]:
				for offset_x in [-4, 0, 4]:
					var pixel := Vector2i(
						clampi(
							int(floor(city.map_position.x * ATLAS.SIZE.x))
								+ offset_x,
							0, ATLAS.SIZE.x - 1
						),
						clampi(
							int(floor(city.map_position.y * ATLAS.SIZE.y))
								+ offset_y,
							0, ATLAS.SIZE.y - 1
						)
					)
					if (atlas["land_mask"] as Image).get_pixelv(pixel).r < 0.5:
						continue
					if int(round((atlas["city_id"] as Image).get_pixelv(pixel).r)) < 0:
						failures.append(
							"southern city=%d has unpainted land at %s" % [
								city.id, pixel,
							]
						)
	if not failures.is_empty():
		print("VISUAL_ATLAS_SOUTHERN_SAMPLES=", southern_samples)
		push_error(
			"VISUAL_ATLAS_CITY_COVERAGE_FAILED count=%d first=%s" % [
				failures.size(), failures.slice(0, mini(failures.size(), 12)),
			]
		)
		quit(1)
		return
	print("VISUAL_ATLAS_CITY_COVERAGE_OK southern=", southern_samples.size())
	quit(0)
