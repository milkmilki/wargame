extends SceneTree
## End-to-end contract for rectangular generation, negative-height water, runtime
## city-count regeneration, constrained editing and map-definition round trips.


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("MAP_EDITOR_RUNTIME_FAILED: " + message)
	quit(1)


func _run() -> void:
	var state := GameState.new()
	state.generate_world(24680, 4, 96)
	if state.land_cities().size() != 96:
		_fail("requested city count was not generated exactly")
		return
	if state.city_generation_mask_path != GameState.DEFAULT_CITY_MASK_PATH:
		_fail("default China city mask was not applied")
		return
	var density_defaults := TerrainMapGenerator.default_city_density_settings()
	if (
		not is_equal_approx(float(state.city_density_settings["latitude_min"]), 18.0)
		or not is_equal_approx(float(state.city_density_settings["latitude_max"]), 54.0)
		or not is_equal_approx(float(state.city_density_settings["density_peak_latitude"]), 30.0)
		or state.city_density_settings != density_defaults
	):
		_fail("default city density did not use the source WGS84 latitude bounds")
		return
	var default_mask := (
		load(GameState.DEFAULT_CITY_MASK_PATH) as Texture2D
	).get_image()
	if (
		state.map_source_region_normalized
			!= Rect2(0.0, 0.0, 1.0, 1.0)
		or not is_equal_approx(
			state.map_aspect_ratio,
			TerrainMapGenerator.FULL_MAP_ASPECT_RATIO
		)
	):
		_fail("map must retain the complete geographic rectangle")
		return
	var height_image := (
		load(GameState.terrain_map_path()) as Texture2D
	).get_image()
	var minimum_coast_distance_pixels := INF
	var alpha_image := height_image
	for city in state.land_cities():
		var mask_pixel := default_mask.get_pixel(
			clampi(int(city.map_position.x * default_mask.get_width()), 0, default_mask.get_width() - 1),
			clampi(int(city.map_position.y * default_mask.get_height()), 0, default_mask.get_height() - 1)
		)
		if mask_pixel.get_luminance() < 0.5:
			_fail("default-mask city generated in a black region")
			return
		var pixel := height_image.get_pixel(
			clampi(int(city.map_position.x * height_image.get_width()), 0, height_image.get_width() - 1),
			clampi(int(city.map_position.y * height_image.get_height()), 0, height_image.get_height() - 1)
		)
		if not TerrainMapGenerator.packed_is_land(pixel):
			_fail("generated city landed in negative-height water")
			return
		var px := clampi(int(city.map_position.x * alpha_image.get_width()), 0, alpha_image.get_width() - 1)
		var py := clampi(int(city.map_position.y * alpha_image.get_height()), 0, alpha_image.get_height() - 1)
		for radius in range(1, 65):
			var found_water := false
			for sample in [Vector2i(px - radius, py), Vector2i(px + radius, py), Vector2i(px, py - radius), Vector2i(px, py + radius)]:
				if sample.x < 0 or sample.y < 0 or sample.x >= alpha_image.get_width() or sample.y >= alpha_image.get_height():
					continue
				if not TerrainMapGenerator.packed_is_land(alpha_image.get_pixelv(sample)):
					found_water = true
					break
			if found_water:
				minimum_coast_distance_pixels = minf(minimum_coast_distance_pixels, radius)
				break
	if minimum_coast_distance_pixels > 32.0:
		_fail("all generated cities remain artificially inset from the packed coastline")
		return

	var renderer := StrategicTerrainRenderer.new()
	root.add_child(renderer)
	renderer.configure(Vector2i(96, 56), Vector2(64.0, 36.864), 4.8, 64)
	renderer.generate_from_height_texture(
		load(GameState.terrain_map_path()) as Texture2D,
		Rect2(0.0, 0.0, 1.0, 1.0),
		TerrainMapGenerator.ALPHA_THRESHOLD,
		TerrainMapGenerator.LUMA_THRESHOLD
	)
	var water_samples := 0
	for height in renderer._height_samples:
		if height < StrategicTerrainRenderer.WATER_SURFACE_HEIGHT:
			water_samples += 1
	if water_samples <= 0:
		_fail("rectangular terrain contains no negative-height water samples")
		return

	var city := state.land_cities()[0]
	var original_city_id := city.id
	var original_position := city.map_position
	var moved_position := original_position
	for offset in [
		Vector2(0.002, 0.0),
		Vector2(-0.002, 0.0),
		Vector2(0.0, 0.002),
		Vector2(0.0, -0.002),
	]:
		var candidate: Vector2 = original_position + offset
		if TerrainMapGenerator.is_land_map_position(
			GameState.terrain_map_path(), candidate
		):
			moved_position = candidate
			break
	if moved_position == original_position:
		_fail("could not find nearby editable land position")
		return
	if not _verify_rejected_city_edit_is_atomic(moved_position):
		return
	var city_result := state.apply_city_editor_changes(city.id, {
		"map_x": moved_position.x,
		"map_y": moved_position.y,
		"gold_per_month": 77,
		"fort_strength_max": 42,
		"fort_strength": 31,
		"food_storage": 9876,
		"terrain_output_multiplier": 1.25,
		"development_gold_multiplier": 2.5,
		"is_crossroads": true,
	})
	if not bool(city_result.get("ok", false)):
		_fail("city edit was rejected")
		return
	# Map templates keep initial identity, policy and loyalty, but deliberately
	# omit active rebellion/trade-route snapshots from a running campaign.
	var identity_nation = state.nations[city.owner_nation]
	identity_nation.founding_city_id = city.id
	identity_nation.name = "测"
	identity_nation.short_name = "测"
	identity_nation.name_kind = WorldNaming.KIND_SEPARATIST
	identity_nation.ruler_name = "测试君主"
	identity_nation.ruler_archetype = RulerProfile.MERCHANT
	identity_nation.ruler_traits = [
		RulerProfile.TRAIT_MERCANTILE
	] as Array[String]
	identity_nation.ruler_started_day = 17
	identity_nation.ruler_revision = 3
	identity_nation.trade_policy = RulerProfile.POLICY_GOLD
	city.name = "测试城"
	city.short_name = "测"
	city.loyalty = 61.5
	city.loyalty_target_nation = (city.owner_nation + 1) % state.nations.size()
	var edited_edge: Edge = null
	for edge in state.edges:
		if edge.kind == Edge.Kind.LAND:
			edited_edge = edge
			break
	if edited_edge == null:
		_fail("no editable land edge")
		return
	var edge_a := edited_edge.city_a
	var edge_b := edited_edge.city_b
	var edge_result := state.apply_edge_editor_changes(edge_a, edge_b, {
		"max_manpower": 10000,
		"distance": 9,
		"danger": 0.73,
		"max_height_difference": 0.44,
		"land_ratio": 0.88,
		"is_backbone": true,
	})
	if not bool(edge_result.get("ok", false)):
		_fail("edge edit was rejected")
		return

	var file_name := "map_editor_runtime_roundtrip.json"
	var saved := MapDefinition.save_state(state, file_name)
	if not bool(saved.get("ok", false)):
		_fail(str(saved.get("error", "save failed")))
		return
	var loaded := MapDefinition.load_file(file_name)
	if not bool(loaded.get("ok", false)):
		_fail(str(loaded.get("error", "load failed")))
		return
	var loaded_data := loaded["data"] as Dictionary
	var loaded_city_record := (loaded_data["cities"] as Array)[
		original_city_id
	] as Dictionary
	var loaded_nation_record := (loaded_data["nations"] as Array)[
		identity_nation.id
	] as Dictionary
	if (
		int(loaded_data.get("version", -1)) != MapDefinition.VERSION
		or loaded_data.has("rebellions")
		or loaded_data.has("trade_routes")
		or loaded_city_record.has("rebellion_progress")
		or loaded_city_record.has("rebellion_cooldown_until_day")
		or loaded_city_record.has("loyalty_trend")
		or loaded_city_record.has("trade_route_count")
		or loaded_city_record.has("trade_gold_bonus")
		or loaded_nation_record.has("last_rebellion_day")
		or loaded_nation_record.has("last_trade_route_count")
	):
		_fail("map v3 must omit campaign rebellion and trade-route state")
		return
	var v1_definition := loaded_data.duplicate(true)
	v1_definition["version"] = 1
	if MapDefinition.validate(v1_definition).is_empty():
		_fail("legacy v1 maps must be rejected")
		return
	var v2_definition := loaded_data.duplicate(true)
	v2_definition["version"] = 2
	if MapDefinition.validate(v2_definition).is_empty():
		_fail("legacy v2 maps must be rejected")
		return
	var obsolete_region_field := loaded_data.duplicate(true)
	var obsolete_city := (
		(obsolete_region_field["cities"] as Array)[0] as Dictionary
	)
	obsolete_city["region_symbol"] = obsolete_city["short_name"]
	if MapDefinition.validate(obsolete_region_field).is_empty():
		_fail("v3 maps must reject the deleted region_symbol field")
		return
	var invalid_version := (loaded["data"] as Dictionary).duplicate(true)
	invalid_version["version"] = MapDefinition.VERSION + 1
	if MapDefinition.validate(invalid_version).is_empty():
		_fail("future map versions must be rejected")
		return
	var invalid_v3_no_land := loaded_data.duplicate(true)
	_remove_nation_land(invalid_v3_no_land, 1, 0)
	if MapDefinition.validate(invalid_v3_no_land).is_empty():
		_fail("v3 maps must reject nations without a land city")
		return
	var invalid_nation_name := loaded_data.duplicate(true)
	(invalid_nation_name["nations"] as Array)[0]["name"] = "双字"
	if MapDefinition.validate(invalid_nation_name).is_empty():
		_fail("v3 nation names must be one character")
		return
	var invalid_short_name := loaded_data.duplicate(true)
	(invalid_short_name["nations"] as Array)[0]["short_name"] = ""
	if MapDefinition.validate(invalid_short_name).is_empty():
		_fail("v3 nation short names must be one character")
		return
	var invalid_vassal := loaded_data.duplicate(true)
	(invalid_vassal["nations"] as Array)[0]["name_kind"] = (
		WorldNaming.KIND_VASSAL
	)
	if MapDefinition.validate(invalid_vassal).is_empty():
		_fail("v3 map templates must reject orphan vassal identities")
		return
	var invalid_city_name := loaded_data.duplicate(true)
	(invalid_city_name["cities"] as Array)[0]["name"] = " "
	if MapDefinition.validate(invalid_city_name).is_empty():
		_fail("v3 city names must be non-empty")
		return
	var duplicate_city_name := loaded_data.duplicate(true)
	(duplicate_city_name["cities"] as Array)[1]["name"] = (
		(duplicate_city_name["cities"] as Array)[0]["name"]
	)
	if MapDefinition.validate(duplicate_city_name).is_empty():
		_fail("v3 city names must be unique")
		return
	var invalid_city_short := loaded_data.duplicate(true)
	(invalid_city_short["cities"] as Array)[0]["short_name"] = "双字"
	if MapDefinition.validate(invalid_city_short).is_empty():
		_fail("v3 city short names must be one character")
		return
	var duplicate_city_short := loaded_data.duplicate(true)
	(duplicate_city_short["cities"] as Array)[1]["short_name"] = (
		(duplicate_city_short["cities"] as Array)[0]["short_name"]
	)
	if MapDefinition.validate(duplicate_city_short).is_empty():
		_fail("v3 city short names must be globally unique")
		return
	var invalid_transient_state := loaded_data.duplicate(true)
	(invalid_transient_state["cities"] as Array)[0][
		"rebellion_progress"
	] = 3
	if MapDefinition.validate(invalid_transient_state).is_empty():
		_fail("map templates must reject active rebellion state")
		return
	var invalid_edge := (loaded["data"] as Dictionary).duplicate(true)
	(invalid_edge["edges"] as Array)[0]["city_b"] = 999999
	if MapDefinition.validate(invalid_edge).is_empty():
		_fail("invalid edge endpoint must be rejected")
		return
	var restored := GameState.new()
	restored.generate_from_map_definition(loaded["data"], 24680)
	var restored_edge := restored.edge_of(edge_a, edge_b)
	var restored_identity = restored.nations[identity_nation.id]
	var restored_city = restored.cities[original_city_id]
	var expected_ruler_traits: Array[String] = [
		RulerProfile.TRAIT_MERCANTILE
	]
	var map_paths_roundtrip := restored.edges.size() == state.edges.size()
	if map_paths_roundtrip:
		for edge_index in range(state.edges.size()):
			map_paths_roundtrip = (
				state.edges[edge_index].map_path
					== restored.edges[edge_index].map_path
			)
			if not map_paths_roundtrip:
				break
	var original_sea_count := 0
	var restored_sea_count := 0
	for source_edge in state.edges:
		if source_edge.kind == Edge.Kind.SEA:
			original_sea_count += 1
	for target_edge in restored.edges:
		if target_edge.kind == Edge.Kind.SEA:
			restored_sea_count += 1
	var checks := {
		"city_count": restored.land_cities().size() == 96,
		"gold": restored.cities[original_city_id].gold_per_month == 77,
		"position": restored.cities[original_city_id].map_position.distance_to(moved_position) <= 0.00001,
		"fort": restored.cities[original_city_id].fort_strength_max == 42,
		"food_total": restored.nations[restored.cities[original_city_id].owner_nation].granary_food >= 9876,
		"development": is_equal_approx(restored.cities[original_city_id].development_gold_multiplier, 2.5),
		"crossroads": restored.cities[original_city_id].is_crossroads,
		"edge_exists": restored_edge != null,
		"edge_capacity": restored_edge != null and restored_edge.max_manpower == 10000,
		"edge_distance": restored_edge != null and restored_edge.distance == 9,
		"edge_danger": restored_edge != null and is_equal_approx(restored_edge.danger, 0.73),
		"edge_relief": restored_edge != null and is_equal_approx(restored_edge.max_height_difference, 0.44),
		"edge_land": restored_edge != null and is_equal_approx(restored_edge.land_ratio, 0.88),
		"edge_backbone": restored_edge != null and restored_edge.is_backbone,
		"sea_roundtrip": restored_sea_count == original_sea_count,
		"map_paths_roundtrip": map_paths_roundtrip,
		"density_roundtrip": restored.city_density_settings == state.city_density_settings,
		"nation_name": restored_identity.name == identity_nation.name,
		"nation_short_name": (
			restored_identity.short_name == identity_nation.short_name
		),
		"nation_name_kind": (
			restored_identity.name_kind == identity_nation.name_kind
		),
		"founding_city_id": (
			restored_identity.founding_city_id == identity_nation.founding_city_id
		),
		"ruler_name": restored_identity.ruler_name == "测试君主",
		"ruler_archetype": (
			restored_identity.ruler_archetype == RulerProfile.MERCHANT
		),
		"ruler_traits": (
			restored_identity.ruler_traits
				== expected_ruler_traits
		),
		"ruler_started_day": restored_identity.ruler_started_day == 17,
		"ruler_revision": restored_identity.ruler_revision == 3,
		"trade_policy": (
			restored_identity.trade_policy == RulerProfile.POLICY_GOLD
		),
		"city_name": restored_city.name == "测试城",
		"city_short_name": restored_city.short_name == "测",
		"city_loyalty": is_equal_approx(restored_city.loyalty, 61.5),
		"city_loyalty_target": (
			restored_city.loyalty_target_nation
				== city.loyalty_target_nation
		),
		"armies": not restored.armies.is_empty(),
		"day_zero": restored.day == 0,
	}
	var round_trip_valid := true
	for check_value in checks.values():
		round_trip_valid = round_trip_valid and bool(check_value)
	if not round_trip_valid:
		print("MAP_EDITOR_RUNTIME_DIAGNOSTIC checks=", checks)
		_fail("saved map did not round-trip edited topology and properties")
		return
	if not _verify_annexed_map_roundtrip():
		return
	if not _verify_vassal_export_as_sovereign():
		return
	print(
		"MAP_EDITOR_RUNTIME_OK cities=", restored.land_cities().size(),
		" edges=", restored.edges.size(),
		" water_samples=", water_samples,
		" coast_distance_px=", minimum_coast_distance_pixels,
		" path=", saved["path"]
	)
	renderer.free()
	quit(0)


func _verify_rejected_city_edit_is_atomic(moved_position: Vector2) -> bool:
	var state := GameState.new()
	state.generate_world(24683, 4, 4)
	var target: City = null
	for candidate in state.land_cities():
		if state.land_cities_of(candidate.owner_nation).size() == 1:
			target = candidate
			break
	if target == null:
		_fail("could not construct a nation with one last land city")
		return false
	var owner_before := target.owner_nation
	var recipient := (owner_before + 1) % state.nations.size()
	var position_before := target.map_position
	var ownership_revision_before := state.ownership_revision
	var road_revision_before := state.road_network_revision
	var fingerprint_before := _territory_fingerprint(state)
	var requested_position := moved_position
	if not TerrainMapGenerator.is_land_map_position(
		GameState.terrain_map_path(), requested_position
	):
		requested_position = position_before
	for offset in [
		Vector2(0.002, 0.0),
		Vector2(-0.002, 0.0),
		Vector2(0.0, 0.002),
		Vector2(0.0, -0.002),
	]:
		var candidate_position: Vector2 = position_before + offset
		if TerrainMapGenerator.is_land_map_position(
			GameState.terrain_map_path(), candidate_position
		):
			requested_position = candidate_position
			break
	if requested_position == position_before:
		_fail("could not find a nearby land position for atomic edit rejection")
		return false
	var result := state.apply_city_editor_changes(target.id, {
		"map_x": requested_position.x,
		"map_y": requested_position.y,
		"owner_nation": recipient,
	})
	if (
		bool(result.get("ok", true))
		or bool(result.get("changed", false))
		or str(result.get("error", "")).is_empty()
		or target.map_position != position_before
		or state.ownership_revision != ownership_revision_before
		or state.road_network_revision != road_revision_before
		or _territory_fingerprint(state) != fingerprint_before
	):
		_fail(
			"moving and illegally transferring the last land city was not atomic"
		)
		return false
	return true


func _territory_fingerprint(state: GameState) -> Dictionary:
	var cities: Array[Dictionary] = []
	for city in state.cities:
		cities.append({
			"id": city.id,
			"owner": city.owner_nation,
			"legal": state.recognized_owner_of(city.id),
			"sponsor": city.occupation_sponsor_nation,
			"position": city.map_position,
			"capital": city.is_capital,
			"warehouse": city.has_warehouse,
			"food": city.food_storage,
		})
	var nations: Array[Dictionary] = []
	for nation in state.nations:
		nations.append({
			"id": nation.id,
			"alive": nation.alive,
			"capital_city_id": nation.capital_city_id,
			"warehouse_city_ids": nation.warehouse_city_ids.duplicate(),
			"granary_food": nation.granary_food,
		})
	return {
		"cities": cities,
		"nations": nations,
		"ownership_revision": state.ownership_revision,
		"road_network_revision": state.road_network_revision,
	}


func _remove_nation_land(
	definition: Dictionary,
	removed_nation: int,
	recipient_nation: int
) -> void:
	for city_value in definition["cities"]:
		var record := city_value as Dictionary
		if int(record.get("owner_nation", -1)) == removed_nation:
			record["owner_nation"] = recipient_nation
		if int(record.get("loyalty_target_nation", -1)) == removed_nation:
			record["loyalty_target_nation"] = recipient_nation


func _verify_annexed_map_roundtrip() -> bool:
	var annexed := GameState.new()
	annexed.generate_grid_world(24681)
	var survivor_old_ids: Array[int] = [0, 2, 3]
	var absorbed_ruler := annexed.nations[1].ruler_name
	var stale_target_city := annexed.land_cities_of(1)[0].id
	annexed.annex_nation(0, 1)
	annexed.cities[stale_target_city].loyalty_target_nation = 1
	if (
		annexed.nations[1].alive
		or not annexed.cities_of(1).is_empty()
	):
		_fail("annex fixture did not produce a historical dead nation")
		return false
	var definition := MapDefinition.from_state(annexed)
	var validation_error := MapDefinition.validate(definition)
	if not validation_error.is_empty():
		_fail("annexed map export was invalid: " + validation_error)
		return false
	var records := definition["nations"] as Array
	if int(definition["nation_count"]) != 3 or records.size() != 3:
		_fail("annexed map did not compact historical dead nations")
		return false
	for new_id in range(survivor_old_ids.size()):
		var old_id := survivor_old_ids[new_id]
		var record := records[new_id] as Dictionary
		if (
			int(record["id"]) != new_id
			or str(record["ruler_name"])
				!= annexed.nations[old_id].ruler_name
			or int(record["founding_city_id"])
				!= annexed.nations[old_id].founding_city_id
		):
			_fail("surviving nation identity was not remapped deterministically")
			return false
	if str(records[0]["ruler_name"]) == absorbed_ruler:
		_fail("historical dead nation identity leaked into map template")
		return false
	var city_records := definition["cities"] as Array
	for city_value in city_records:
		var record := city_value as Dictionary
		var owner := int(record["owner_nation"])
		var target := int(record["loyalty_target_nation"])
		if owner < 0 or owner >= 3 or target < 0 or target >= 3:
			_fail("annexed map retained an invalid nation reference")
			return false
	if int((city_records[stale_target_city] as Dictionary)[
		"loyalty_target_nation"
	]) != 0:
		_fail("dead loyalty target did not fall back to the remapped owner")
		return false
	var restored := GameState.new()
	restored.generate_from_map_definition(definition, 24681)
	if restored.nations.size() != 3 or not restored.territory_structure_valid():
		_fail("annexed map did not load as a valid compact scenario")
		return false
	for nation in restored.nations:
		if not nation.alive or restored.land_cities_of(nation.id).is_empty():
			_fail("restored compact scenario retained a landless nation")
			return false
	return true


func _verify_vassal_export_as_sovereign() -> bool:
	var vassal_state := GameState.new()
	vassal_state.generate_grid_world(24682)
	var granted_region: Array[int] = []
	for candidate in vassal_state.land_cities_of(0):
		if not candidate.is_capital:
			granted_region.append(candidate.id)
			break
	if granted_region.size() != 1:
		_fail("could not construct vassal export fixture")
		return false
	var subject_id := vassal_state.enfeoff(0, granted_region)
	if subject_id < 0 or not vassal_state.is_vassal(subject_id):
		_fail("enfeoff fixture did not create a vassal")
		return false
	var definition := MapDefinition.from_state(vassal_state)
	var validation_error := MapDefinition.validate(definition)
	if not validation_error.is_empty():
		_fail("vassal map export was invalid: " + validation_error)
		return false
	var subject_record := (definition["nations"] as Array)[
		subject_id
	] as Dictionary
	var founding_city_id := int(subject_record["founding_city_id"])
	var founding_symbol := str(
		(definition["cities"] as Array)[founding_city_id]["short_name"]
	)
	if (
		str(subject_record["name_kind"]) == WorldNaming.KIND_VASSAL
		or str(subject_record["name"]) != founding_symbol
		or str(subject_record["short_name"]) != founding_symbol
		or str(subject_record["name"]).contains("王")
	):
		_fail("vassal was not normalized to a sovereign map identity")
		return false
	var restored := GameState.new()
	restored.generate_from_map_definition(definition, 24682)
	var restored_line_armies := 0
	var restored_main_light_armies := 0
	var restored_main_heavy_armies := 0
	for army in restored.armies:
		if army.owner_nation != subject_id or army.size <= 0:
			continue
		if army.is_line_role():
			restored_line_armies += 1
		elif army.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
			restored_main_heavy_armies += 1
		else:
			restored_main_light_armies += 1
	if (
		restored.is_vassal(subject_id)
		or restored.nation_display_name(subject_id).contains("王")
		or restored.nations[subject_id].name != founding_symbol
		or restored_line_armies != 1
		or restored_main_light_armies
			!= GameState.SMALL_NATION_MOBILE_RESERVE_ARMIES
		or restored_main_heavy_armies != 0
	):
		_fail(
			"loaded map retained orphan vassal identity or invalid small-nation force: "
			+ "vassal=%s display=%s name=%s symbol=%s line=%d main_light=%d main_heavy=%d"
			% [
				str(restored.is_vassal(subject_id)),
				restored.nation_display_name(subject_id),
				restored.nations[subject_id].name,
				founding_symbol,
				restored_line_armies,
				restored_main_light_armies,
				restored_main_heavy_armies,
			]
		)
		return false
	return true
