extends RefCounted
## Categorical display of the generated province grid. Never assigns territory.
const Masks := preload("res://scripts/view/visual_region_geometry.gd")
const Borders := preload("res://scripts/view/river_province_geometry.gd")

static func build(state: GameState, height_image: Image, size: Vector2i) -> Dictionary:
	var labels := PackedFloat32Array(Array(state.province_ids))
	var ids := Image.create_from_data(state.province_map_size.x, state.province_map_size.y, false, Image.FORMAT_RF, labels.to_byte_array())
	ids.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var land := Masks._build_land_mask(height_image, size)
	var coverage := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	var values := PackedByteArray()
	values.resize(size.x * size.y)
	labels = ids.get_data().to_float32_array()
	for index in range(labels.size()):
		values[index] = 255 if labels[index] >= 0.0 else 0
	coverage.set_data(size.x, size.y, false, Image.FORMAT_L8, values)
	var edge := Image.create(size.x, size.y, false, Image.FORMAT_RF)
	Masks._fill_region_edges(ids, edge)
	return {
		"city_id": ids, "land_mask": land, "region_coverage": coverage,
		"region_edge": edge, "region_distance": Masks._build_distance_channel(ids, land, edge),
		"regions": [],
	}

static func topology(state: GameState) -> Dictionary:
	# Only trace label transitions; no bank recoloring, new seeds or smoothing.
	return Borders.topology_from_labels(PackedFloat32Array(Array(state.province_ids)), state.province_map_size)
