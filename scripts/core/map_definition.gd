class_name MapDefinition
extends RefCounted
## Versioned editable map template. This is deliberately not a campaign save:
## armies, battles, diplomacy and the simulation clock are rebuilt on load.

const FORMAT := "world-war-map"
const VERSION := 1
const USER_MAP_DIRECTORY := "user://maps"


static func from_state(state: GameState) -> Dictionary:
	var city_records: Array[Dictionary] = []
	for city in state.cities:
		city_records.append({
			"id": city.id,
			"coord": [city.coord.x, city.coord.y],
			"map_position": [city.map_position.x, city.map_position.y],
			"terrain_height": city.terrain_height,
			"terrain_relief": city.terrain_relief,
			"terrain_output_multiplier": city.terrain_output_multiplier,
			"is_dock": city.is_dock,
			"owner_nation": city.owner_nation,
			"fort_strength": city.fort_strength,
			"fort_strength_max": city.fort_strength_max,
			"manpower_per_month": city.manpower_per_month,
			"gold_per_month": city.gold_per_month,
			"food_per_half_year": city.food_per_half_year,
			"is_food_hub": city.is_food_hub,
			"is_manpower_hub": city.is_manpower_hub,
			"is_plain_city": city.is_plain_city,
			"is_port_market": city.is_port_market,
			"is_crossroads": city.is_crossroads,
			"development_gold_multiplier": city.development_gold_multiplier,
			"development_food_multiplier": city.development_food_multiplier,
			"food_storage": city.food_storage,
		})
	var edge_records: Array[Dictionary] = []
	for edge in state.edges:
		edge_records.append({
			"city_a": edge.city_a,
			"city_b": edge.city_b,
			"kind": edge.kind,
			"max_manpower": edge.max_manpower,
			"base_max_manpower": edge.base_max_manpower,
			"distance": edge.distance,
			"danger": edge.danger,
			"travel_time_multiplier": edge.travel_time_multiplier,
			"supply_loss_multiplier": edge.supply_loss_multiplier,
			"allows_holding": edge.allows_holding,
			"max_height_difference": edge.max_height_difference,
			"land_ratio": edge.land_ratio,
			"is_backbone": edge.is_backbone,
		})
	var river_records: Array[Array] = []
	for river in state.river_paths:
		var points: Array[Array] = []
		for point in river:
			points.append([point.x, point.y])
		river_records.append(points)
	return {
		"format": FORMAT,
		"version": VERSION,
		"map_source_manifest": GameState.MAP_SOURCE_MANIFEST,
		"city_generation_mask_path": state.city_generation_mask_path,
		"city_density_settings": state.city_density_settings.duplicate(true),
		"nation_count": state.nations.size(),
		"map_aspect_ratio": state.map_aspect_ratio,
		"source_region": [
			state.map_source_region_normalized.position.x,
			state.map_source_region_normalized.position.y,
			state.map_source_region_normalized.size.x,
			state.map_source_region_normalized.size.y,
		],
		"province_map_size": [
			state.province_map_size.x, state.province_map_size.y
		],
		"province_ids": Array(state.province_ids),
		"river_paths": river_records,
		"cities": city_records,
		"edges": edge_records,
	}


static func validate(data: Dictionary) -> String:
	if str(data.get("format", "")) != FORMAT:
		return "不是 WorldWar 地图文件。"
	if int(data.get("version", -1)) != VERSION:
		return "地图版本不支持：%s" % str(data.get("version", -1))
	var cities: Array = data.get("cities", [])
	var edges: Array = data.get("edges", [])
	var nation_count := int(data.get("nation_count", 0))
	if cities.is_empty() or nation_count <= 0:
		return "地图必须包含城市和国家。"
	for index in range(cities.size()):
		var record: Dictionary = cities[index]
		if int(record.get("id", -1)) != index:
			return "城市 ID 必须从 0 连续排列。"
		var owner := int(record.get("owner_nation", -1))
		if owner < 0 or owner >= nation_count:
			return "城市 %d 的国家归属无效。" % index
	for edge_record in edges:
		var record: Dictionary = edge_record
		var a := int(record.get("city_a", -1))
		var b := int(record.get("city_b", -1))
		if a < 0 or b < 0 or a >= cities.size() or b >= cities.size() or a == b:
			return "道路端点无效。"
	return ""


static func safe_user_path(file_name: String) -> String:
	var clean := file_name.strip_edges().get_file()
	if clean.is_empty():
		clean = "custom_map.json"
	if not clean.to_lower().ends_with(".json"):
		clean += ".json"
	return USER_MAP_DIRECTORY.path_join(clean)


static func save_state(state: GameState, file_name: String) -> Dictionary:
	var path := safe_user_path(file_name)
	var absolute_directory := ProjectSettings.globalize_path(
		USER_MAP_DIRECTORY
	)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		absolute_directory
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "无法创建地图目录。"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": "无法写入地图文件（错误码 %d）。"
				% FileAccess.get_open_error(),
		}
	file.store_string(JSON.stringify(from_state(state), "  "))
	file.close()
	return {"ok": true, "path": path}


static func load_file(file_name: String) -> Dictionary:
	var path := safe_user_path(file_name)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "地图文件不存在：%s" % path}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "error": "地图 JSON 格式错误。"}
	var data := parsed as Dictionary
	var validation_error := validate(data)
	if not validation_error.is_empty():
		return {"ok": false, "error": validation_error}
	return {"ok": true, "path": path, "data": data}
