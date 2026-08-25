class_name MapDefinition
extends RefCounted
## Versioned editable map template. This is deliberately not a campaign save:
## armies, battles, diplomacy and the simulation clock are rebuilt on load.

const FORMAT := "world-war-map"
const VERSION := 3
const MIN_SUPPORTED_VERSION := 3
const USER_MAP_DIRECTORY := "user://maps"


static func from_state(state: GameState) -> Dictionary:
	# Nations are append-only during a campaign, but a map template describes a
	# fresh scenario. Drop historical dead entries and compact the remaining ids
	# so the loader never creates a nation without an initial land city.
	var land_city_counts := {}
	for city in state.cities:
		if city.is_dock:
			continue
		var owner_id := int(city.owner_nation)
		land_city_counts[owner_id] = int(land_city_counts.get(owner_id, 0)) + 1
	var exported_nations: Array = []
	for nation in state.nations:
		if nation.alive and int(land_city_counts.get(int(nation.id), 0)) > 0:
			exported_nations.append(nation)
	exported_nations.sort_custom(func(a, b) -> bool:
		return int(a.id) < int(b.id)
	)
	var nation_id_map := {}
	for new_id in range(exported_nations.size()):
		nation_id_map[int(exported_nations[new_id].id)] = new_id
	var nation_records: Array[Dictionary] = []
	for new_id in range(exported_nations.size()):
		var nation = exported_nations[new_id]
		var founding_city_id := _export_founding_city_id(state, nation)
		var exported_name := str(nation.name).strip_edges()
		var exported_short_name := str(nation.short_name).strip_edges()
		var exported_name_kind := str(nation.name_kind)
		if founding_city_id >= 0:
			var founding_symbol := str(
				state.cities[founding_city_id].short_name
			).strip_edges()
			if founding_symbol.length() == 1:
				exported_name = founding_symbol
				exported_short_name = founding_symbol
				exported_name_kind = _sovereign_name_kind(founding_symbol)
		nation_records.append({
			"id": new_id,
			"founding_city_id": founding_city_id,
			"name": exported_name,
			"short_name": exported_short_name,
			"name_kind": exported_name_kind,
			"ruler_name": nation.ruler_name,
			"ruler_archetype": nation.ruler_archetype,
			"ruler_traits": Array(nation.ruler_traits),
			"ruler_started_day": nation.ruler_started_day,
			"ruler_revision": nation.ruler_revision,
			"trade_policy": nation.trade_policy,
		})
	var city_records: Array[Dictionary] = []
	for city in state.cities:
		var owner_nation := _export_city_owner_id(
			state, city, nation_id_map
		)
		var loyalty_target_nation := int(nation_id_map.get(
			int(city.loyalty_target_nation), -1
		))
		if loyalty_target_nation < 0:
			loyalty_target_nation = owner_nation
		city_records.append({
			"id": city.id,
			"name": city.name,
			"short_name": city.short_name,
			"coord": [city.coord.x, city.coord.y],
			"map_position": [city.map_position.x, city.map_position.y],
			"terrain_height": city.terrain_height,
			"terrain_relief": city.terrain_relief,
			"terrain_output_multiplier": city.terrain_output_multiplier,
			"is_dock": city.is_dock,
			"owner_nation": owner_nation,
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
			"loyalty": city.loyalty,
			"loyalty_target_nation": loyalty_target_nation,
			"food_storage": city.food_storage,
		})
	var edge_records: Array[Dictionary] = []
	for edge in state.edges:
		var edge_map_path: Array[Array] = []
		for point in edge.map_path:
			edge_map_path.append([point.x, point.y])
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
			"map_path": edge_map_path,
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
		"nation_count": exported_nations.size(),
		"nations": nation_records,
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


static func _export_founding_city_id(state: GameState, nation) -> int:
	var founding_city_id := int(nation.founding_city_id)
	if (
		founding_city_id >= 0
		and founding_city_id < state.cities.size()
		and not state.cities[founding_city_id].is_dock
	):
		return founding_city_id
	var capital_city_id := int(nation.capital_city_id)
	if (
		capital_city_id >= 0
		and capital_city_id < state.cities.size()
		and not state.cities[capital_city_id].is_dock
		and state.cities[capital_city_id].owner_nation == nation.id
	):
		return capital_city_id
	for city in state.cities:
		if city.owner_nation == nation.id and not city.is_dock:
			return city.id
	return -1


static func _sovereign_name_kind(symbol: String) -> String:
	return (
		WorldNaming.KIND_DYNASTY
		if WorldNaming.DYNASTY_NAMES.has(symbol)
		else WorldNaming.KIND_WARRING_STATE
	)


static func _export_city_owner_id(
	state: GameState,
	city,
	nation_id_map: Dictionary
) -> int:
	var mapped_owner := int(nation_id_map.get(int(city.owner_nation), -1))
	if mapped_owner >= 0:
		return mapped_owner
	var legal_owner := state.recognized_owner_of(int(city.id))
	mapped_owner = int(nation_id_map.get(legal_owner, -1))
	if mapped_owner >= 0:
		return mapped_owner
	var neighbor_ids: Array = state.neighbors(int(city.id)).duplicate()
	neighbor_ids.sort()
	for neighbor_value in neighbor_ids:
		var neighbor_id := int(neighbor_value)
		if neighbor_id < 0 or neighbor_id >= state.cities.size():
			continue
		var neighbor = state.cities[neighbor_id]
		if neighbor.is_dock:
			continue
		mapped_owner = int(nation_id_map.get(
			int(neighbor.owner_nation), -1
		))
		if mapped_owner >= 0:
			return mapped_owner
	# A malformed runtime state can leave an isolated city on an excluded id.
	# Keep export deterministic; validate() will reject the no-nation case.
	return 0 if not nation_id_map.is_empty() else -1


static func validate(data: Dictionary) -> String:
	if str(data.get("format", "")) != FORMAT:
		return "不是 WorldWar 地图文件。"
	var version_value: Variant = data.get("version")
	if not _is_integer_value(version_value):
		return "地图版本不支持：%s" % str(version_value)
	var version := int(version_value)
	if version < MIN_SUPPORTED_VERSION or version > VERSION:
		return "地图版本不支持：%s" % str(data.get("version", -1))
	if data.has("rebellions") or data.has("trade_routes"):
		return "地图模板不能包含活动叛乱或贸易路径。"
	var cities_value: Variant = data.get("cities")
	var edges_value: Variant = data.get("edges")
	var nation_count_value: Variant = data.get("nation_count")
	if (
		not cities_value is Array
		or not edges_value is Array
		or not _is_integer_value(nation_count_value)
	):
		return "地图城市、道路或国家数量格式无效。"
	var cities: Array = cities_value
	var edges: Array = edges_value
	var nation_count := int(nation_count_value)
	if cities.is_empty() or nation_count <= 0:
		return "地图必须包含城市和国家。"
	var nation_error := _validate_nations(data, nation_count)
	if not nation_error.is_empty():
		return nation_error
	var city_names := {}
	var city_short_names := {}
	var land_city_counts: Array[int] = []
	land_city_counts.resize(nation_count)
	land_city_counts.fill(0)
	for index in range(cities.size()):
		var record_value: Variant = cities[index]
		if not record_value is Dictionary:
			return "城市 %d 的资料格式无效。" % index
		var record := record_value as Dictionary
		if record.has("region_symbol"):
			return "城市 %d 仍含已删除的地域字字段。" % index
		var id_value: Variant = record.get("id")
		if not _is_integer_value(id_value) or int(id_value) != index:
			return "城市 ID 必须从 0 连续排列。"
		var owner_value: Variant = record.get("owner_nation")
		if not _is_integer_value(owner_value):
			return "城市 %d 的国家归属无效。" % index
		var owner := int(owner_value)
		if owner < 0 or owner >= nation_count:
			return "城市 %d 的国家归属无效。" % index
		if not bool(record.get("is_dock", false)):
			land_city_counts[owner] += 1
		var name_value: Variant = record.get("name")
		if not name_value is String or str(name_value).strip_edges().is_empty():
			return "城市 %d 的名称不能为空。" % index
		var city_name := str(name_value).strip_edges()
		if city_names.has(city_name):
			return "城市名称不能重复：%s" % city_name
		city_names[city_name] = true
		var short_value: Variant = record.get("short_name")
		if not short_value is String or str(short_value).strip_edges().length() != 1:
			return "城市 %d 的简称必须是单字。" % index
		var city_short_name := str(short_value).strip_edges()
		if city_short_names.has(city_short_name):
			return "城市简称不能重复：%s" % city_short_name
		city_short_names[city_short_name] = true
		var loyalty_value: Variant = record.get("loyalty")
		if not loyalty_value is float and not loyalty_value is int:
			return "城市 %d 的忠诚度格式无效。" % index
		var loyalty := float(loyalty_value)
		if not is_finite(loyalty) or loyalty < 0.0 or loyalty > 100.0:
			return "城市 %d 的忠诚度无效。" % index
		var loyalty_target_value: Variant = record.get(
			"loyalty_target_nation"
		)
		if not _is_integer_value(loyalty_target_value):
			return "城市 %d 的忠诚目标无效。" % index
		var loyalty_target := int(loyalty_target_value)
		if loyalty_target < 0 or loyalty_target >= nation_count:
			return "城市 %d 的忠诚目标无效。" % index
		for transient_key in [
			"loyalty_trend", "unrest", "rebellion_progress",
			"rebellion_cooldown_until_day", "last_loyalty_reason",
			"trade_gold_bonus", "trade_route_count",
			"trade_food_balance",
		]:
			if record.has(transient_key):
				return "地图城市不能包含活动叛乱或贸易状态。"
	for nation_id in range(nation_count):
		if land_city_counts[nation_id] <= 0:
			return "国家 %d 必须至少拥有一座陆地城市。" % nation_id
	for edge_record in edges:
		var record: Dictionary = edge_record
		var a := int(record.get("city_a", -1))
		var b := int(record.get("city_b", -1))
		if a < 0 or b < 0 or a >= cities.size() or b >= cities.size() or a == b:
			return "道路端点无效。"
		var map_path: Array = record.get("map_path", [])
		for point_value in map_path:
			if point_value is not Array:
				return "道路折线路径格式无效。"
			var point: Array = point_value
			if point.size() != 2:
				return "道路折线路径点必须包含两个坐标。"
			var x := float(point[0])
			var y := float(point[1])
			if (
				not is_finite(x) or not is_finite(y)
				or x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0
			):
				return "道路折线路径坐标无效。"
		if not map_path.is_empty() and map_path.size() < 2:
			return "道路折线路径至少需要两个点。"
		if not map_path.is_empty():
			var city_a_position: Array = (cities[a] as Dictionary)["map_position"]
			var city_b_position: Array = (cities[b] as Dictionary)["map_position"]
			var first: Array = map_path[0]
			var last: Array = map_path[-1]
			if (
				absf(float(first[0]) - float(city_a_position[0])) > 0.0001
				or absf(float(first[1]) - float(city_a_position[1])) > 0.0001
				or absf(float(last[0]) - float(city_b_position[0])) > 0.0001
				or absf(float(last[1]) - float(city_b_position[1])) > 0.0001
			):
				return "道路折线路径首尾必须匹配端点城市。"
	return ""


static func _validate_nations(
	data: Dictionary,
	nation_count: int
) -> String:
	var cities: Array = data.get("cities", [])
	var nation_value: Variant = data.get("nations")
	if not nation_value is Array:
		return "地图国家资料缺失。"
	var nations: Array = nation_value
	if nations.size() != nation_count:
		return "地图国家资料数量与国家数不一致。"
	for index in range(nations.size()):
		var record_value: Variant = nations[index]
		if not record_value is Dictionary:
			return "国家 %d 的资料格式无效。" % index
		var record := record_value as Dictionary
		var id_value: Variant = record.get("id")
		if not _is_integer_value(id_value) or int(id_value) != index:
			return "国家 ID 必须从 0 连续排列。"
		if not record.has("founding_city_id"):
			return "国家 %d 缺少建国城市。" % index
		var founding_value: Variant = record["founding_city_id"]
		if not _is_integer_value(founding_value):
			return "国家 %d 的建国城市格式无效。" % index
		var founding_city_id := int(founding_value)
		if founding_city_id < 0 or founding_city_id >= cities.size():
			return "国家 %d 的建国城市无效。" % index
		if not cities[founding_city_id] is Dictionary:
			return "国家 %d 的建国城市资料无效。" % index
		var founding_record := cities[founding_city_id] as Dictionary
		if bool(founding_record.get("is_dock", false)):
			return "国家 %d 的建国城市不能是码头。" % index
		var name_kind_value: Variant = record.get("name_kind")
		if (
			not name_kind_value is String
			or not ["dynasty", "state", "vassal", "rebel"].has(
				str(name_kind_value)
			)
		):
			return "国家 %d 的国号类型无效。" % index
		var name_kind := str(name_kind_value)
		if name_kind == "vassal":
			return (
				"地图模板不持久化宗藩关系；国家 %d 必须导出为主权身份。"
				% index
			)
		var resolved_names: Array[String] = []
		for key in ["name", "short_name"]:
			var name_value: Variant = record.get(key)
			if not name_value is String or str(name_value).strip_edges().is_empty():
				return "国家 %d 的名称不能为空。" % index
			resolved_names.append(str(name_value).strip_edges())
		if name_kind in ["dynasty", "state"]:
			if (
				resolved_names[0].length() != 1
				or resolved_names[1].length() != 1
				or resolved_names[0] != resolved_names[1]
			):
				return "国家 %d 的国号和简称必须是同一单字主权名。" % index
			if (
				founding_city_id >= 0
				and resolved_names[0]
					!= str(founding_record.get("short_name", "")).strip_edges()
			):
				return "国家 %d 的主权名必须对应建国城市简称。" % index
		var ruler_name_value: Variant = record.get("ruler_name")
		if (
			not ruler_name_value is String
			or str(ruler_name_value).strip_edges().is_empty()
		):
			return "国家 %d 的君主姓名不能为空。" % index
		var archetype_value: Variant = record.get("ruler_archetype")
		if not _is_integer_value(archetype_value):
			return "国家 %d 的君主原型格式无效。" % index
		var archetype := int(archetype_value)
		if not RulerProfile.is_valid_archetype(archetype):
			return "国家 %d 的君主原型无效。" % index
		var traits_value: Variant = record.get("ruler_traits")
		if not traits_value is Array:
			return "国家 %d 的君主特质格式无效。" % index
		var traits: Array = traits_value
		if traits.size() > RulerProfile.MAX_TRAITS:
			return "国家 %d 的君主特质过多。" % index
		var seen_traits := {}
		for trait_value in traits:
			if (
				not trait_value is String
				or not RulerProfile.is_valid_trait(str(trait_value))
				or seen_traits.has(str(trait_value))
			):
				return "国家 %d 的君主特质无效。" % index
			seen_traits[str(trait_value)] = true
		for key in ["ruler_started_day", "ruler_revision"]:
			var counter_value: Variant = record.get(key)
			if not _is_integer_value(counter_value) or int(counter_value) < 0:
				return "国家 %d 的君主身份版本无效。" % index
		var trade_policy_value: Variant = record.get("trade_policy")
		if not _is_integer_value(trade_policy_value):
			return "国家 %d 的贸易政策格式无效。" % index
		var trade_policy := int(trade_policy_value)
		if (
			trade_policy < RulerProfile.POLICY_BALANCED
			or trade_policy > RulerProfile.POLICY_ISOLATION
		):
			return "国家 %d 的贸易政策无效。" % index
		for transient_key in [
			"last_rebellion_day", "average_loyalty",
			"last_trade_gold", "last_trade_food_import",
			"last_trade_food_export", "last_trade_route_count",
		]:
			if record.has(transient_key):
				return "地图国家不能包含活动叛乱或贸易状态。"
	return ""


static func _is_integer_value(value: Variant) -> bool:
	if value is int:
		return true
	if not value is float:
		return false
	var number := float(value)
	return is_finite(number) and number == floorf(number)


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
