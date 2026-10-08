class_name TerrainMapGenerator
extends RefCounted
const EnvironmentModel = preload("res://scripts/core/settlement_environment.gd")
const CitySampler = preload("res://scripts/core/settlement_sampler.gd")
const Hydrology = preload("res://scripts/core/terrain_hydrology.gd")
const HydroTransport = preload("res://scripts/core/river_transport.gd")
const VectorModel = preload("res://scripts/core/vector_hydrology.gd")
const BankConstraints = preload("res://scripts/core/river_province_constraints.gd")
const DockSampling = preload("res://scripts/core/river_dock_sampling.gd")
const FerrySpacing = preload("res://scripts/core/river_ferry_spacing.gd")
const LandComponents = preload("res://scripts/core/terrain_land_components.gd")
const PixelRoute = preload("res://scripts/core/province_pixel_route.gd")
const ShoreRepair = preload("res://scripts/core/shore_seed_repair.gd")
const RIVER_RESERVATION_VERSION := "local_crossings_v1"
## 从带 Alpha 的灰度高度图确定性生成城市位置和道路图。

const ANALYSIS_WIDTH: int = 256
## Copernicus source covers 73E..135.5E / 18N..54N. Keep that complete
## geographic rectangle as the runtime map instead of cropping to the land
## alpha bounds; the land mask still exclusively controls city placement.
const FULL_MAP_ASPECT_RATIO: float = 62.5 / 36.0  ## Legacy default for old map definitions.
## Packed map source contract: RGB=solid white, Alpha=signed elevation.
## 1..128 is -8000..0m sea; 129..255 is positive land..6200m.
const SEA_LEVEL_ALPHA: float = 128.0 / 255.0
const ALPHA_THRESHOLD: float = SEA_LEVEL_ALPHA
const LUMA_THRESHOLD: float = 0.0  ## Compatibility parameter; RGB never drives geography.
const CANDIDATE_STRIDE: int = 2
const INTERIOR_RADIUS: int = 0
const RELIEF_RADIUS: int = 3
const RELIEF_SPACING_WEIGHT: float = 0.015
const REFERENCE_CITY_COUNT: int = 64
const MIN_CITY_SPACING_AT_REFERENCE: float = 0.075
const LOCAL_SPACING_MIN_FACTOR: float = 0.55
const LOCAL_SPACING_MAX_FACTOR: float = 2.25
const SPACING_RELAXATION_STEP: float = 0.96
const SPACING_RELAXATION_FLOOR: float = 0.72
const RIVER_BANK_MIN_DISTANCE: float = 0.006
const RIVER_BANK_IDEAL_DISTANCE: float = 0.020
const RIVER_BANK_MAX_DISTANCE: float = 0.060
const MAX_LOCAL_EDGE_LENGTH: float = 0.30
const ROAD_SAMPLE_COUNT: int = 48
const ROAD_MINIMUM_LAND_RATIO: float = 0.90
const ROAD_MAXIMUM_HEIGHT_DIFFERENCE: float = 0.20
const RIVER_COUNT: int = 2
const RIVER_DOCK_LOWLAND_ALTITUDE: float = 0.18
const RIVER_CROSSING_ENDPOINT_EPS: float = 0.0001
const RIVER_DOCK_MIN_SPACING: float = 0.012
const RIVER_DOCK_SPACING_REFERENCE_CITY_COUNT: int = 200
const RIVER_DOCK_CITY_MIN_SPACING: float = 0.022
## 省界河流按同一参考岸的沿河省份归组，每省最多选择一个渡口。
## 低海拔、普通城市避让与渡口间距决定具体落点，不按河长、经度或
## 固定数量生成。
const BOUNDARY_RIVER_MIN_LENGTH: float = 0.10
const LANDING_DANGER_MIN: float = 0.90
const EDGE_DISTANCE_UNITS_PER_MAP_HEIGHT: float = 12.0
## 河运速度为同 distance 陆路的 1.2 倍，因此耗时为陆路的 1/1.2。
const RIVER_TRAVEL_TIME_MULTIPLIER: float = 1.0 / 1.2
const RIVER_SUPPLY_LOSS_MULTIPLIER: float = 0.25
const DEFAULT_DENSITY_PEAK_LATITUDE: float = 30.0
const DEFAULT_SOUTH_EDGE_DENSITY: float = 0.50
const DEFAULT_NORTH_EDGE_DENSITY: float = 0.20
## 地理成本在地形分析分辨率求解；边界显示由矢量简化与圆滑消除栅格台阶。
const PROVINCE_RASTER_SCALE: int = 1
## 连续域扭曲把规则 Voronoi 直线变成自然弯曲边界；振幅以地形分析像素计。
const PROVINCE_WARP_PRIMARY_AMPLITUDE: float = 2.6
const PROVINCE_WARP_SECONDARY_AMPLITUDE: float = 1.2
const PROVINCE_MOUNTAIN_ALTITUDE_ONSET: float = 0.42
const PROVINCE_MOUNTAIN_COST: float = 2.8
const PROVINCE_SLOPE_COST: float = 7.0
const PROVINCE_RIVER_CROSSING_COST: float = 7.5
## 邻接道路中只有地形最平缓的这一部分使用 20000 标准容量；其余开放陆路
## 以 10000 为主，避免省份对偶图被宽路淹没。
const ROAD_STANDARD_CAPACITY_SHARE: float = 0.25

static var _cache: Dictionary = {}
static var _crossing_indexes: Dictionary = {}
static var _reservation_cache: Dictionary = {}


static func build(
	source_path: String,
	city_count: int,
	city_mask_path: String = "",
	city_density_settings: Dictionary = {},
	generation_seed: int = 0,
	initial_nation_count: int = 4,
	political_mask_path: String = "",
	source_manifest: String = MapSource.DEFAULT_MANIFEST
) -> Dictionary:
	var source_error := MapSource.validate_manifest(source_manifest)
	if not source_error.is_empty():
		return {"ok": false, "error": source_error}
	var environmental := MapSource.settlement_model(source_manifest) == MapSource.ENVIRONMENT_SETTLEMENT
	var hydrological := MapSource.hydrology_model(source_manifest) == MapSource.TERRAIN_HYDROLOGY
	var environment_only := MapSource.environment_only_rivers(source_manifest)
	var strict_rivers := not environment_only and MapSource.strict_river_transport(source_manifest)
	var full_network := not environment_only and MapSource.full_river_transport(source_manifest)
	var river_settlement := MapSource.river_settlement_model(source_manifest)
	var density_bounds := MapSource.settlement_density_bounds(source_manifest)
	var profile_enabled := (
		OS.get_environment("WORLD_GENERATION_PROFILE") == "1"
	)
	var profile_started := Time.get_ticks_usec() if profile_enabled else 0
	var profile_last := profile_started
	var profile := {}
	var mask_signature := city_mask_signature(city_mask_path)
	var political_mask_signature := city_mask_signature(political_mask_path)
	var density_settings := normalize_city_density_settings(
		city_density_settings, source_manifest
	)
	var cache_key := "settlement-v21-projected-metric-dock-spacing:%s:%d:%s:%s:%s:%d:%d" % [
		source_path, city_count, mask_signature,
		political_mask_signature,
		city_density_signature(density_settings),
		generation_seed,
		initial_nation_count,
	]
	cache_key += ":" + source_manifest + ":" + MapSource.projection_type(source_manifest)
	if MapSource.atlas_roads(source_manifest): cache_key += ":"+str(load("res://scripts/core/atlas_road_network.gd").VERSION)+":coastal_domain_v1"
	cache_key += ":atlas-v1:" + str(environment_only) + ":" + str(MapSource.atlas_roads(source_manifest)) + ":" + str(MapSource.atlas_style(source_manifest))
	cache_key += ":road-path:" + MapSource.road_path_model(source_manifest)
	cache_key += ":ferries:" + str(MapSource.ferry_interval(source_manifest)) + ":" + FerrySpacing.VERSION
	cache_key += ":ferry-cap:" + str(MapSource.ferry_max_per_river(source_manifest))
	if strict_rivers: cache_key += ":" + BankConstraints.VERSION + ":local_transport_v1"
	if full_network: cache_key += ":" + DockSampling.VERSION + ":" + ShoreRepair.VERSION + ":full_pixel_roads_v1"
	cache_key += ":" + river_settlement + ":" + EnvironmentModel.RiverSupport.cache_identity() + ":" + _reservation_identity()
	cache_key += ":" + JSON.stringify(density_bounds)
	if river_settlement == MapSource.VALLEY_RIVER_SETTLEMENT: cache_key += ":" + EnvironmentModel.ValleySupport.cache_identity()
	if hydrological:
		cache_key += ":" + Hydrology.VERSION + ":" + VectorModel.VERSION
		var network_path := MapSource.hydrology_network(source_manifest)
		if not network_path.is_empty(): cache_key += ":" + str(VectorModel.network(network_path).network_id)
		cache_key += ":" + str(MapSource.estimated_boundary_inflow(source_manifest))
	if environmental:
		cache_key += ":" + EnvironmentModel.VERSION + ":" + CitySampler.VERSION + ":" + FileAccess.get_sha256(source_path)
	if _cache.has(cache_key):
		var cached: Dictionary = (_cache[cache_key] as Dictionary).duplicate(true)
		if environmental:
			cached["generation_metadata"]["layout_cache_hit"] = true
		return cached
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	if source == null or source.is_empty():
		return {"ok": false, "error": "无法加载地形高度图：%s" % source_path}
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(float(source.get_height()) * float(ANALYSIS_WIDTH) / float(source.get_width()))),
		1
	)
	# Alpha is numerical elevation, not visual transparency. Never interpolate
	# it across coastlines when building the geography analysis grid.
	analysis.resize(ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_NEAREST)
	var land_geometry := _all_land_geometry(analysis)
	if land_geometry["count"] < city_count * (1 if environmental else 16):
		return {"ok": false, "error": "高度图有效陆地不足，请减少城市数。"}
	var mask: PackedByteArray = land_geometry["mask"]
	var land_bounds: Rect2i = land_geometry["bounds"]
	var city_mask_result := build_city_candidate_mask(
		mask, analysis.get_size(), city_mask_path
	)
	if not bool(city_mask_result.get("ok", false)):
		return city_mask_result
	var city_mask: PackedByteArray = city_mask_result["mask"]
	var city_geometry := _mask_geometry(city_mask, analysis.get_size())
	if int(city_geometry["count"]) < city_count:
		return {"ok": false, "error": "白色蒙版内真实陆地不足，请减少城市数。"}
	var bounds := Rect2i(Vector2i.ZERO, analysis.get_size())
	var political_mask_result := build_city_candidate_mask(
		mask, analysis.get_size(), political_mask_path
	)
	if not bool(political_mask_result.get("ok", false)):
		return political_mask_result
	var political_mask: PackedByteArray = political_mask_result["mask"]
	var map_aspect_ratio := MapSource.aspect_ratio(source_manifest)
	if profile_enabled:
		profile["input"] = Time.get_ticks_usec() - profile_last
		profile_last = Time.get_ticks_usec()
	# Legacy maps choose rivers from province boundaries. Hydrological maps
	# evaluate the existing river network before settlements and province growth.
	var empty_river_paths: Array[Array] = []
	var samples: Dictionary
	var environment_metadata := {}
	var hydro := {}
	var reserved_docks: Array = []
	var atlas_major_scores := PackedFloat32Array()
	if environmental:
		var latitudes := PackedFloat32Array()
		for row in range(analysis.get_height()):
			latitudes.append(latitude_for_map_y((row + 0.5) / analysis.get_height(), density_settings, source_manifest))
		var environment := EnvironmentModel.build(source, analysis, mask, latitudes, map_aspect_ratio, MapSource.projection_type(source_manifest), hydrological, MapSource.hydrology_network(source_manifest), MapSource.estimated_boundary_inflow(source_manifest), river_settlement)
		if full_network:
			environment = environment.duplicate()
			environment["physical_components"] = LandComponents.build(source)
			environment["local_crossings"] = true
		if hydrological: hydro = environment.hydrology
		var reservation_started := Time.get_ticks_usec()
		if not environment_only and (full_network or river_settlement in [MapSource.UNIFORM_RIVER_SETTLEMENT,MapSource.VALLEY_RIVER_SETTLEMENT]):
			reserved_docks = _reserve_hydrology_docks(environment, analysis, map_aspect_ratio, city_count, full_network)
		var reservation_usec := Time.get_ticks_usec() - reservation_started
		samples = CitySampler.sample(source, city_mask, environment, city_count, map_aspect_ratio, generation_seed, reserved_docks, density_bounds)
		for pixel in samples.get("pixels", []):
			atlas_major_scores.append(float(environment.suitability[pixel.y * analysis.get_width() + pixel.x]))
		environment_metadata = samples.get("generation_metadata", {}).duplicate(true)
		environment_metadata.merge({"river_settlement_model": river_settlement, "reservation_version": RIVER_RESERVATION_VERSION, "reservation_usec": reservation_usec, "river_support_usec": environment.get("river_support_usec", 0)})
		environment_metadata.merge({"layout_cache_hit": false, "settlement_model": MapSource.ENVIRONMENT_SETTLEMENT, "environment_version": EnvironmentModel.VERSION, "environment_id": environment["environment_id"], "environment_cache_hit": environment["cache_hit"], "environment_usec": environment["elapsed_usec"]})
		if not bool(samples.get("ok", false)):
			samples["generation_metadata"] = environment_metadata
			return samples
		if hydrological:
			environment_metadata.merge({"hydrology_version": hydro.version, "hydrology_id": hydro.hydrology_id, "hydrology_usec": hydro.elapsed_usec, "basin_count": hydro.basin_count, "external_inflow_count": hydro.get("external_inflow_count", 0), "hydrology_dem_size": hydro.get("dem_size", []), "major_reaches": MapFeatureContract.major_rivers(hydro.features).size(), "minor_reaches": hydro.features.size() - MapFeatureContract.major_rivers(hydro.features).size()})
	else:
		samples = _sample_cities(
			analysis,
			city_mask,
			city_geometry["bounds"],
			bounds,
			city_count,
			empty_river_paths,
			density_settings,
			generation_seed, source_manifest
		)
	if profile_enabled:
		profile["settlements"] = Time.get_ticks_usec() - profile_last
		profile_last = Time.get_ticks_usec()
	environment_metadata.merge({"river_usage": "environment_only" if environment_only else "full", "road_network_model": str(MapSource.load_manifest(source_manifest).get("road_network_model", "legacy")), "map_visual_style": str(MapSource.load_manifest(source_manifest).get("map_visual_style", "legacy"))})
	# Water has already informed settlement suitability. It must not leak into
	# province barriers, docks, movement or the visual feature atlas.
	if environment_only:
		hydro = hydro.duplicate()
		hydro["features"] = []
		hydro["blocked_edges"] = {}
	# Settlement density and spacing are solved in the tight land domain, then
	# projected once into the complete geographic rectangle used by rendering.
	var full_positions: Array[Vector2] = []
	var political_active := PackedByteArray()
	political_active.resize(samples["pixels"].size())
	for city_id in range(samples["pixels"].size()):
		var pixel: Vector2i = samples["pixels"][city_id]
		full_positions.append(samples["positions"][city_id] if environmental else _normalized_map_point(pixel, bounds))
		political_active[city_id] = political_mask[
			pixel.y * analysis.get_width() + pixel.x
		]
	var politically_active_count := _count_mask(political_active)
	samples["positions"] = full_positions
	samples["politically_active"] = political_active
	# 省份是地形/河流上的基础行政分区；道路只能消费省份接壤关系，
	# 不能反过来塑造省界，否则会形成“道路决定省界、省界又决定道路”的循环。
	var constraints := BankConstraints.build(hydro.features, analysis.get_size(), map_aspect_ratio) if strict_rivers else {}
	if full_network: constraints["whole_branch_transfer"] = true
	var province_mask := _atlas_land_domain(source,analysis.get_size()) if MapSource.atlas_roads(source_manifest) else mask
	var provinces := _build_province_raster(
		analysis,
		province_mask,
		bounds,
		samples["pixels"],
		empty_river_paths, projected_pixel_aspect(analysis, source_manifest),
		MapSource.projection_type(source_manifest) == MapSource.WEB_MERCATOR,
		hydro.get("blocked_edges", {}),
		constraints
	)
	if provinces.get("ok", true) == false: return provinces
	if full_network:
		provinces.ids = BankConstraints.complete_conflicts(provinces.ids, mask, analysis.get_size(), samples.pixels, hydro.blocked_edges, constraints)
		var repair := ShoreRepair.repair(samples, provinces, analysis, source, mask, hydro.blocked_edges, constraints, projected_pixel_aspect(analysis, source_manifest))
		provinces = repair.provinces
		environment_metadata["shore_seed_repair"] = {"version": repair.version, "moves": repair.moves, "remaining_gaps": repair.remaining_gaps, "trials": repair.trials}
		if not repair.moves.is_empty(): environment_metadata["spacing_scale"] = minf(float(environment_metadata.get("spacing_scale", 1.0)), 0.8)
		if not repair.remaining_gaps.is_empty():
			_write_hydrology_failure(generation_seed, source_manifest, "provinces", samples, provinces, hydro, environment_metadata)
			return {"ok": false, "error": "主河岸区仍有 %d 个可分配格未覆盖；当前世界已保留。" % repair.remaining_gaps.size(), "generation_metadata": environment_metadata}
		for city_id in range(samples.pixels.size()):
			political_active[city_id] = political_mask[samples.pixels[city_id].y * analysis.get_width() + samples.pixels[city_id].x]
		politically_active_count = _count_mask(political_active)
	provinces["routing_options"] = {"strict": true, "allow_terrain_connector": true, "image": source if full_network else analysis, "aspect": map_aspect_ratio, "river_paths": MapFeatureContract.major_paths(hydro.features)} if strict_rivers else {}
	if full_network:
		provinces["physical_components"] = LandComponents.build(source)
		provinces.routing_options["pixel_fallback"] = true
	if profile_enabled:
		profile["provinces"] = Time.get_ticks_usec() - profile_last
		profile_last = Time.get_ticks_usec()
	var boundary_rivers := _hydrology_transport_input(provinces, hydro.features, strict_rivers, map_aspect_ratio, full_network) if hydrological else _build_boundary_river_network(
		provinces, samples["positions"], map_aspect_ratio
	)
	boundary_rivers["reserved_docks"] = reserved_docks
	boundary_rivers["ferry_interval"] = 0.0 if environment_only else MapSource.ferry_interval(source_manifest)
	boundary_rivers["ferry_max_per_river"] = 0 if environment_only else MapSource.ferry_max_per_river(source_manifest)
	boundary_rivers["navigation_image"] = source if strict_rivers else analysis
	boundary_rivers["local_navigation"] = strict_rivers
	if strict_rivers:
		for river in boundary_rivers.rivers: river["strict_transport"] = true
		environment_metadata["river_transport_model"] = MapSource.FULL_RIVER_TRANSPORT if full_network else MapSource.STRICT_RIVER_TRANSPORT
		environment_metadata["bank_constraint_version"] = BankConstraints.VERSION
	if profile_enabled:
		profile["rivers"] = Time.get_ticks_usec() - profile_last
		profile_last = Time.get_ticks_usec()
	var road_result: Dictionary
	if MapSource.atlas_roads(source_manifest):
		road_result = load("res://scripts/core/atlas_road_network.gd").build(source, analysis, samples, provinces, map_aspect_ratio, atlas_major_scores)
		if not road_result.get("ok", false): return road_result
		environment_metadata.merge(road_result.get("metadata", {}), true)
	else:
		road_result = _build_roads(analysis, mask, samples, map_aspect_ratio, provinces, boundary_rivers["pixel_paths"], hydro.get("blocked_edges", {}))
	if profile_enabled:
		profile["roads"] = Time.get_ticks_usec() - profile_last
		profile_last = Time.get_ticks_usec()
	_attach_province_land_paths(
		road_result["roads"],
		provinces,
		samples["positions"],
		city_count, map_aspect_ratio, hydro.get("blocked_edges", {})
	)
	if profile_enabled:
		profile["road_paths"] = Time.get_ticks_usec() - profile_last
		profile_last = Time.get_ticks_usec()
	var transport := _build_boundary_river_transport(
		analysis,
		samples,
		road_result["roads"],
		provinces,
		boundary_rivers,
		city_count,
		map_aspect_ratio,
		initial_nation_count
	)
	if not transport.get("ok", true): return transport
	if not transport.get("ferry_spacing", {}).is_empty(): environment_metadata["ferry_spacing"] = transport.ferry_spacing
	if hydrological:
		var land_roads: Array[Dictionary] = []
		if strict_rivers:
			environment_metadata["dock_diagnostics"] = transport.get("dock_diagnostics", [])
			environment_metadata["river_navigation_model"] = HydroTransport.Navigation.MODEL
			environment_metadata["river_source_exception_radius"] = BankConstraints.SOURCE_RADIUS
		for road in transport.roads:
			if int(road.get("kind", Edge.Kind.LAND)) != Edge.Kind.RIVER: land_roads.append(road)
		land_roads.append_array(HydroTransport.build(hydro.features, transport.docks, source if strict_rivers else analysis, map_aspect_ratio, strict_rivers))
		transport.roads = land_roads
		if not MapSource.atlas_roads(source_manifest) and MapSource.road_path_model(source_manifest) == MapSource.VISIBILITY_ROAD_PATH:
			environment_metadata["road_path_simplification"] = _simplify_generated_land_roads(transport.roads, provinces, source, hydro.features, map_aspect_ratio)
		var unassigned := 0
		for i in range(mask.size()):
			if mask[i] != 0 and provinces.ids[i] < 0: unassigned += 1
		environment_metadata.unassigned_land_cells = unassigned
		if not _hydrology_transport_valid(transport, samples.positions, analysis, mask, hydro):
			_write_hydrology_failure(generation_seed, source_manifest, "transport", samples, provinces, hydro, environment_metadata, road_result.roads, transport.roads)
			var transport_error := "主河交通无法合法连接城市；请调整城市数量或地图范围。"
			if MapSource.ferry_max_per_river(source_manifest)>0:
				transport_error="每条主河最多%d个渡口的限制下无法合法连接城市；当前世界已保留。" % MapSource.ferry_max_per_river(source_manifest)
			return {"ok": false, "error": transport_error, "generation_metadata": environment_metadata}
	if profile_enabled:
		profile["river_transport"] = Time.get_ticks_usec() - profile_last
		profile_last = Time.get_ticks_usec()
	var result := {
		"positions": samples["positions"],
		"pixels": samples["pixels"],
		"heights": samples["heights"],
		"reliefs": samples["reliefs"],
		"politically_active": samples["politically_active"],
		"politically_active_count": politically_active_count,
		"roads": transport["roads"],
		"docks": transport["docks"],
		"lowland_dock_regions": transport.get(
			"lowland_dock_regions", [] as Array[Dictionary]
		),
		"dock_bank_regions": transport.get(
			"dock_bank_regions", [] as Array[Dictionary]
		),
		"river_paths": transport["river_paths"],
		"river_features": hydro.features if hydrological else MapFeatureContract.from_legacy_river_paths(
			transport["river_paths"]
		),
		"bounds": bounds,
		"land_bounds": land_bounds,
		"image_size": analysis.get_size(),
		"source_region_normalized": Rect2(0.0, 0.0, 1.0, 1.0),
		"map_aspect_ratio": map_aspect_ratio,
		"province_map_size": provinces["size"],
		"province_ids": provinces["ids"],
		"city_mask_path": city_mask_path,
		"city_mask_signature": mask_signature,
		"city_density_settings": density_settings.duplicate(true),
		"generation_seed": generation_seed,
		"political_mask_path": political_mask_path,
	}
	if environmental:
		result["generation_metadata"] = environment_metadata
	_cache[cache_key] = result.duplicate(true)
	if profile_enabled:
		profile["materialize_cache"] = Time.get_ticks_usec() - profile_last
		print("WORLD_GENERATION_PROFILE total=%.2fms stages=%s" % [
			float(Time.get_ticks_usec() - profile_started) / 1000.0,
			str(profile),
		])
	return result

static func _write_hydrology_failure(seed_value: int, source_manifest: String, stage: String, samples: Dictionary, provinces: Dictionary, hydro: Dictionary, metadata: Dictionary, roads_before: Array = [], roads_after: Array = []) -> void:
	if OS.get_environment("HYDROLOGY_DIAGNOSE") != "1": return
	var report := {"seed": seed_value, "source": source_manifest, "stage": stage, "positions": [], "roads_before": roads_before, "roads_after": roads_after, "provinces": Array(provinces.ids), "rivers": MapFeatureContract.serialize_rivers(hydro.features), "metadata": metadata}
	for p in samples.positions: report.positions.append([p.x, p.y])
	var file := FileAccess.open("res://.dbg/hydrology-generation-failure-%d.json" % seed_value, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report))

static func _hydrology_transport_valid(transport: Dictionary, positions: Array[Vector2], image: Image, land: PackedByteArray, hydro: Dictionary) -> bool:
	var major_paths := MapFeatureContract.major_paths(hydro.features)
	var count: int = positions.size() + transport.docks.size()
	var parent: Array[int] = []
	for i in range(count): parent.append(i)
	for road in transport.roads:
		if int(road.get("kind", Edge.Kind.LAND)) in [Edge.Kind.LAND, Edge.Kind.LANDING] and _road_dictionary_crosses_rivers(road, positions, major_paths):
			if OS.get_environment("HYDROLOGY_DIAGNOSE") == "1": print("HYDROLOGY_ILLEGAL_CROSSING ", road)
			return false
		parent[_root(parent, int(road.a))] = _root(parent, int(road.b))
	# Coastal cities may legitimately use the existing sea network. The Eurasia
	# acceptance separately requires the west/central/east route without sea edges.
	var components := Hydrology.components(land, image.get_size(), {})
	var areas := {}
	var mainland := -1
	var largest := 0
	for component in components:
		if component < 0: continue
		areas[component] = int(areas.get(component, 0)) + 1
		if int(areas[component]) > largest:
			largest = int(areas[component])
			mainland = component
	var roots := {}
	for i in range(positions.size()):
		var p := Vector2i(positions[i] * Vector2(image.get_size())).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
		var component := components[p.y * image.get_width() + p.x]
		if component != mainland: continue
		var root := _root(parent, i)
		if roots.has(component) and roots[component] != root:
			print("HYDROLOGY_DISCONNECTED city=%d component=%d root=%d expected=%d position=%s" % [i, component, root, roots[component], positions[i]])
			for road in transport.roads:
				if int(road.a) == i or int(road.b) == i: print("HYDROLOGY_CITY_LINK ", road)
			return false
		roots[component] = root
	return true


static func default_city_density_settings(source_manifest: String = MapSource.DEFAULT_MANIFEST) -> Dictionary:
	var latitude_bounds := MapSource.latitude_bounds(source_manifest)
	var profile := MapSource.city_density_profile(source_manifest)
	return {
		"latitude_min": latitude_bounds.x,
		"latitude_max": latitude_bounds.y,
		"density_peak_latitude": clampf(
			float(profile.get(
				"peak_latitude", DEFAULT_DENSITY_PEAK_LATITUDE
			)),
			latitude_bounds.x,
			latitude_bounds.y
		),
		"south_density": clampf(float(profile.get(
			"south_edge_multiplier", DEFAULT_SOUTH_EDGE_DENSITY
		)), 0.01, 1.0),
		"north_density": clampf(float(profile.get(
			"north_edge_multiplier", DEFAULT_NORTH_EDGE_DENSITY
		)), 0.01, 1.0),
	}


static func normalize_city_density_settings(
	settings: Dictionary,
	source_manifest: String = MapSource.DEFAULT_MANIFEST
) -> Dictionary:
	var defaults := default_city_density_settings(source_manifest)
	var latitude_limit := MapSource.latitude_limit(source_manifest)
	var latitude_min := clampf(
		float(settings.get("latitude_min", defaults["latitude_min"])),
		-latitude_limit, latitude_limit
	)
	var latitude_max := clampf(
		float(settings.get("latitude_max", defaults["latitude_max"])),
		-latitude_limit, latitude_limit
	)
	if latitude_min > latitude_max:
		var swap := latitude_min
		latitude_min = latitude_max
		latitude_max = swap
	if is_equal_approx(latitude_min, latitude_max):
		latitude_max = minf(latitude_min + 0.1, latitude_limit)
		latitude_min = maxf(latitude_max - 0.1, -latitude_limit)
	return {
		"latitude_min": latitude_min,
		"latitude_max": latitude_max,
		"density_peak_latitude": clampf(
			float(settings.get(
				"density_peak_latitude",
				defaults["density_peak_latitude"]
			)),
			latitude_min, latitude_max
		),
		"south_density": clampf(
			float(settings.get(
				"south_density", defaults["south_density"]
			)),
			0.01, 1.0
		),
		"north_density": clampf(
			float(settings.get(
				"north_density", defaults["north_density"]
			)),
			0.01, 1.0
		),
	}


static func city_density_signature(settings: Dictionary) -> String:
	return "%.3f:%.3f:%.3f:%.3f:%.3f" % [
		float(settings["latitude_min"]),
		float(settings["latitude_max"]),
		float(settings["density_peak_latitude"]),
		float(settings["south_density"]),
		float(settings["north_density"]),
	]


static func latitude_for_map_y(
	map_y: float, settings: Dictionary,
	source_manifest: String = MapSource.DEFAULT_MANIFEST
) -> float:
	return MapSource.latitude_at_y(
		clampf(map_y, 0.0, 1.0),
		float(settings["latitude_min"]),
		float(settings["latitude_max"]), source_manifest
	)


static func latitude_density_multiplier(
	latitude: float, settings: Dictionary
) -> float:
	var normalized := normalize_city_density_settings(settings)
	var south := float(normalized["latitude_min"])
	var north := float(normalized["latitude_max"])
	var peak := float(normalized["density_peak_latitude"])
	if latitude <= peak:
		var south_ratio := smoothstep(
			south, maxf(peak, south + 0.0001), latitude
		)
		return lerpf(
			float(normalized["south_density"]),
			1.0, south_ratio
		)
	var north_ratio := smoothstep(
		peak, maxf(north, peak + 0.0001), latitude
	)
	return lerpf(
		1.0, float(normalized["north_density"]), north_ratio
	)


static func city_mask_signature(path: String) -> String:
	var clean := path.strip_edges()
	if clean.is_empty():
		return "none"
	var global_path := (
		ProjectSettings.globalize_path(clean)
		if clean.begins_with("res://") or clean.begins_with("user://")
		else clean
	)
	return "%s:%d" % [clean, FileAccess.get_modified_time(global_path)]


static func load_city_mask_image(path: String) -> Dictionary:
	var clean := path.strip_edges()
	if clean.is_empty():
		return {"ok": true, "image": null, "path": ""}
	var image: Image = null
	if clean.begins_with("res://"):
		var texture := load(clean) as Texture2D
		if texture != null:
			image = texture.get_image()
	else:
		var global_path := (
			ProjectSettings.globalize_path(clean)
			if clean.begins_with("user://")
			else clean
		)
		if FileAccess.file_exists(global_path):
			image = Image.load_from_file(global_path)
	if image == null or image.is_empty():
		return {
			"ok": false,
			"error": "无法读取城市蒙版图片：%s" % clean,
		}
	return {"ok": true, "image": image, "path": clean}


static func build_city_candidate_mask(
	land_mask: PackedByteArray,
	target_size: Vector2i,
	city_mask_path: String
) -> Dictionary:
	var result := load_city_mask_image(city_mask_path)
	if not bool(result.get("ok", false)):
		return result
	var output := land_mask.duplicate()
	var image: Image = result.get("image")
	if image == null:
		return {"ok": true, "mask": output, "white_land_count": _count_mask(output)}
	image = image.duplicate()
	image.resize(target_size.x, target_size.y, Image.INTERPOLATE_NEAREST)
	var allowed_count := 0
	for y in range(target_size.y):
		for x in range(target_size.x):
			var index := y * target_size.x + x
			var color := image.get_pixel(x, y)
			var allowed := (
				land_mask[index] != 0
				and color.get_luminance() >= 0.5
			)
			output[index] = 1 if allowed else 0
			if allowed:
				allowed_count += 1
	return {
		"ok": true,
		"mask": output,
		"white_land_count": allowed_count,
		"path": city_mask_path,
	}


static func validate_city_mask(
	source_path: String,
	city_mask_path: String,
	city_count: int
) -> Dictionary:
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	if source == null or source.is_empty():
		return {"ok": false, "error": "地图源纹理不可用。"}
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(float(source.get_height()) * float(ANALYSIS_WIDTH) / float(source.get_width()))), 1
	)
	analysis.resize(ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_NEAREST)
	var land_geometry := _all_land_geometry(analysis)
	var result := build_city_candidate_mask(
		land_geometry["mask"], analysis.get_size(), city_mask_path
	)
	if not bool(result.get("ok", false)):
		return result
	var available := int(result.get("white_land_count", 0))
	if available < city_count:
		return {
			"ok": false,
			"error": "蒙版白色陆地区域不足：可用%d格，请求%d城。" % [available, city_count],
		}
	return {"ok": true, "white_land_count": available, "path": city_mask_path}


static func validate_political_mask(
	source_path: String,
	political_mask_path: String
) -> Dictionary:
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	if source == null or source.is_empty():
		return {"ok": false, "error": "地图源纹理不可用。"}
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(float(source.get_height()) * float(ANALYSIS_WIDTH) / float(source.get_width()))), 1
	)
	analysis.resize(ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_NEAREST)
	var land_geometry := _all_land_geometry(analysis)
	var result := build_city_candidate_mask(
		land_geometry["mask"], analysis.get_size(), political_mask_path
	)
	if not bool(result.get("ok", false)):
		if str(result.get("error", "")).contains("城市蒙版"):
			result["error"] = str(result["error"]).replace("城市蒙版", "政治蒙版")
		return result
	var available := int(result.get("white_land_count", 0))
	if available <= 0:
		return {"ok": false, "error": "政治蒙版未覆盖任何真实陆地。"}
	return {
		"ok": true,
		"white_land_count": available,
		"path": political_mask_path,
	}


static func _count_mask(mask: PackedByteArray) -> int:
	var count := 0
	for value in mask:
		if value != 0:
			count += 1
	return count


static func _mask_geometry(mask: PackedByteArray, size: Vector2i) -> Dictionary:
	var min_x := size.x
	var min_y := size.y
	var max_x := -1
	var max_y := -1
	var count := 0
	for y in range(size.y):
		for x in range(size.x):
			if mask[y * size.x + x] == 0:
				continue
			count += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return {
		"count": count,
		"bounds": Rect2i(
			min_x if count > 0 else 0,
			min_y if count > 0 else 0,
			maxi(max_x - min_x + 1, 1) if count > 0 else 1,
			maxi(max_y - min_y + 1, 1) if count > 0 else 1
		),
	}


static func is_land_map_position(
	source_path: String,
	map_position: Vector2
) -> bool:
	var texture := load(source_path) as Texture2D
	if texture == null:
		return false
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var x := clampi(
		int(floor(clampf(map_position.x, 0.0, 1.0) * image.get_width())),
		0, image.get_width() - 1
	)
	var y := clampi(
		int(floor(clampf(map_position.y, 0.0, 1.0) * image.get_height())),
		0, image.get_height() - 1
	)
	var pixel := image.get_pixel(x, y)
	return packed_is_land(pixel)


static func packed_is_land(color: Color) -> bool:
	return color.a > SEA_LEVEL_ALPHA + 0.5 / 255.0


static func packed_altitude(color: Color) -> float:
	if not packed_is_land(color):
		return 0.0
	return clampf((color.a * 255.0 - 129.0) / 126.0, 0.0, 1.0)


static func packed_signed_elevation(color: Color) -> float:
	var alpha_byte := color.a * 255.0
	if alpha_byte <= 128.5:
		return lerpf(-1.0, 0.0, clampf((alpha_byte - 1.0) / 127.0, 0.0, 1.0))
	return clampf((alpha_byte - 129.0) / 126.0, 0.0, 1.0)


static func map_segment_profile(
	source_path: String,
	from: Vector2,
	to: Vector2
) -> Dictionary:
	var texture := load(source_path) as Texture2D
	var image := texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		return {"height_difference": 0.0, "land_ratio": 0.0}
	var minimum := 1.0
	var maximum := 0.0
	var land_samples := 0
	for index in range(ROAD_SAMPLE_COUNT + 1):
		var ratio := float(index) / float(ROAD_SAMPLE_COUNT)
		var point := from.lerp(to, ratio)
		var x := clampi(int(floor(point.x * image.get_width())), 0, image.get_width() - 1)
		var y := clampi(int(floor(point.y * image.get_height())), 0, image.get_height() - 1)
		var color := image.get_pixel(x, y)
		var height := packed_altitude(color)
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		if packed_is_land(color):
			land_samples += 1
	return {
		"height_difference": maximum - minimum,
		"land_ratio": float(land_samples) / float(ROAD_SAMPLE_COUNT + 1),
	}


static func rebuild_provinces(
	source_path: String,
	city_positions: Array[Vector2],
	_edges: Array[Edge],
	normalized_rivers: Array[PackedVector2Array],
	source_manifest: String = MapSource.DEFAULT_MANIFEST
) -> Dictionary:
	var texture := load(source_path) as Texture2D
	var source := texture.get_image() if texture != null else null
	assert(source != null and not source.is_empty())
	var analysis := source.duplicate()
	var analysis_height := maxi(
		int(round(
			float(source.get_height()) * float(ANALYSIS_WIDTH)
				/ float(source.get_width())
		)),
		1
	)
	analysis.resize(
		ANALYSIS_WIDTH, analysis_height, Image.INTERPOLATE_NEAREST
	)
	var land_geometry := _all_land_geometry(analysis)
	var mask: PackedByteArray = land_geometry["mask"]
	var bounds := Rect2i(Vector2i.ZERO, analysis.get_size())
	var city_pixels: Array[Vector2i] = []
	for position in city_positions:
		city_pixels.append(Vector2i(
			clampi(
				int(round(position.x * float(analysis.get_width() - 1))),
				0, analysis.get_width() - 1
			),
			clampi(
				int(round(position.y * float(analysis.get_height() - 1))),
				0, analysis.get_height() - 1
			)
		))
	var river_pixels: Array[Array] = []
	for river in normalized_rivers:
		var path: Array[Vector2i] = []
		for point in river:
			path.append(Vector2i(
				clampi(
					int(round(point.x * float(analysis.get_width() - 1))),
					0, analysis.get_width() - 1
				),
				clampi(
					int(round(point.y * float(analysis.get_height() - 1))),
					0, analysis.get_height() - 1
				)
			))
		river_pixels.append(path)
	var projected := MapSource.projection_type(source_manifest) == MapSource.WEB_MERCATOR
	if projected:
		# Rivers are derived from province borders after generation. Feeding them
		# back into growth would redefine the entire map when just one city moves.
		river_pixels.clear()
	return _build_province_raster(
		analysis, mask, bounds, city_pixels, river_pixels,
		projected_pixel_aspect(analysis, source_manifest),
		projected
	)


## Legacy maps retain their original raster metric, including existing layouts.
## Mercator pixels have unequal physical sides because the packed PNG is square.
static func projected_pixel_aspect(image: Image, source_manifest: String) -> float:
	if MapSource.projection_type(source_manifest) != MapSource.WEB_MERCATOR:
		return 1.0
	return MapSource.aspect_ratio(source_manifest) * float(image.get_height()) / float(image.get_width())


static func _build_province_raster(
	image: Image,
	land_mask: PackedByteArray,
	bounds: Rect2i,
	city_pixels: Array[Vector2i],
	river_paths: Array[Array],
	pixel_aspect: float = 1.0,
	precise_costs: bool = false,
	blocked_edges: Dictionary = {},
	bank_constraints: Dictionary = {}
) -> Dictionary:
	var width := bounds.size.x * PROVINCE_RASTER_SCALE
	var height := bounds.size.y * PROVINCE_RASTER_SCALE
	var raster_size := Vector2i(width, height)
	var ids := PackedInt32Array()
	ids.resize(width * height)
	ids.fill(-1)
	var land := PackedByteArray()
	land.resize(width * height)
	var altitude := PackedFloat32Array()
	altitude.resize(width * height)
	var river := PackedByteArray()
	river.resize(width * height)
	var metric_points := PackedVector2Array()
	metric_points.resize(width * height)
	var image_width := image.get_width()
	for local_y in range(height):
		var image_y := bounds.position.y + clampi(
			local_y / PROVINCE_RASTER_SCALE,
			0,
			bounds.size.y - 1
		)
		for local_x in range(width):
			var index := local_y * width + local_x
			metric_points[index] = province_metric_point(
				(Vector2(local_x, local_y)
					+ Vector2(0.5, 0.5))
					/ float(PROVINCE_RASTER_SCALE)
			)
			metric_points[index].x *= pixel_aspect
			var image_x := bounds.position.x + clampi(
				local_x / PROVINCE_RASTER_SCALE,
				0,
				bounds.size.x - 1
			)
			if land_mask[image_y * image_width + image_x] == 0:
				continue
			land[index] = 1
			altitude[index] = packed_altitude(
				image.get_pixel(image_x, image_y)
			)
	_build_province_river_mask(
		river,
		raster_size,
		bounds,
		river_paths
	)
	var distances := PackedFloat64Array()
	distances.resize(width * height)
	distances.fill(INF)
	var heap: Array = []
	var strict := not bank_constraints.is_empty()
	var settled := PackedByteArray()
	settled.resize(width * height)
	var expanded := PackedByteArray()
	expanded.resize(width * height)
	for city_id in range(city_pixels.size()):
		var local := (
			city_pixels[city_id] - bounds.position
		) * PROVINCE_RASTER_SCALE
		var seed := Vector2i(
			clampi(local.x, 0, width - 1),
			clampi(local.y, 0, height - 1)
		)
		var seed_index := seed.y * width + seed.x
		if land[seed_index] == 0:
			continue
		distances[seed_index] = 0.0
		ids[seed_index] = city_id
		if strict: settled[seed_index] = 1
		_province_heap_push(
			heap,
			_province_heap_entry(0.0, seed_index, city_id, precise_costs)
		)
	if strict:
		var error := BankConstraints.validate(ids, bank_constraints)
		if not error.is_empty(): return {"ok": false, "error": error}
	var offsets := [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]
	while not heap.is_empty():
		var entry: Variant = _province_heap_pop(heap)
		var current_index := int(entry[1])
		var owner := int(entry[2])
		var current_cost := float(entry[0])
		if strict and expanded[current_index] != 0: continue
		if strict and ids[current_index] < 0:
			if not BankConstraints.permits(current_index, owner, ids, bank_constraints): continue
			ids[current_index] = owner
			distances[current_index] = current_cost
			settled[current_index] = 1
		if (
			owner != ids[current_index]
			or current_cost
				> distances[current_index] + 0.000001
		):
			continue
		if strict: expanded[current_index] = 1
		var current := Vector2i(
			current_index % width,
			current_index / width
		)
		var current_metric := metric_points[current_index]
		for offset in offsets:
			var next: Vector2i = current + offset
			if (
				next.x < 0
				or next.y < 0
				or next.x >= width
				or next.y >= height
			):
				continue
			var next_index: int = next.y * width + next.x
			if land[next_index] == 0:
				continue
			if blocked_edges.has(Hydrology.edge_key(current_index, next_index, width * height)):
				continue
			if strict and settled[next_index] != 0: continue
			var step_cost := province_geographic_step_cost(
				altitude[current_index],
				altitude[next_index],
				river[current_index] != river[next_index],
				0.0,
				current_metric.distance_to(
					metric_points[next_index]
				)
			)
			var candidate_cost := current_cost + step_cost
			if strict:
				# Claims are permanent. Every queued claim extends a finalized cell
				# of its own province, preserving seed connectivity by construction.
				if BankConstraints.permits(next_index, owner, ids, bank_constraints):
					_province_heap_push(heap, _province_heap_entry(candidate_cost, next_index, owner, true))
				continue
			# 相同成本下堆已按 owner/id 稳定排序，首次到达即为确定胜者。
			# 禁止后到 owner 覆盖，避免旧 owner 已向外传播后留下断开的标签岛。
			if candidate_cost < distances[next_index] - 0.000001:
				distances[next_index] = candidate_cost
				ids[next_index] = owner
				_province_heap_push(
					heap,
					_province_heap_entry(
						candidate_cost,
						next_index,
						owner, precise_costs
					)
				)
	# Land components without a settlement remain unassigned. Assigning them to
	# the nearest seed in screen space creates disconnected provinces across sea.
	if strict:
		for pass_index in range(4):
			var before := ids.count(-1)
			ids = BankConstraints.complete(ids, land, raster_size, city_pixels, blocked_edges, bank_constraints)
			if ids.count(-1) >= before: break
	return {
		"size": raster_size,
		"ids": ids,
	}


static func province_geographic_step_cost(
	from_altitude: float,
	to_altitude: float,
	crosses_river: bool,
	_road_strength: float,
	step_length: float
) -> float:
	var average_altitude := (
		from_altitude + to_altitude
	) * 0.5
	var mountain_factor := clampf(
		inverse_lerp(
			PROVINCE_MOUNTAIN_ALTITUDE_ONSET,
			0.88,
			average_altitude
		),
		0.0,
		1.0
	)
	var slope := absf(to_altitude - from_altitude)
	var terrain_cost := maxf(step_length, 0.01) * (
		1.0
		+ mountain_factor * PROVINCE_MOUNTAIN_COST
		+ slope * PROVINCE_SLOPE_COST
	)
	if crosses_river:
		terrain_cost += PROVINCE_RIVER_CROSSING_COST
	return maxf(terrain_cost, 0.01)


static func _build_province_river_mask(
	result: PackedByteArray,
	raster_size: Vector2i,
	bounds: Rect2i,
	river_paths: Array[Array]
) -> void:
	for path in river_paths:
		for point_value in path:
			var point: Vector2i = point_value
			var local := (
				point - bounds.position
			) * PROVINCE_RASTER_SCALE
			_mark_province_disk(
				result,
				raster_size,
				local,
				1,
				1.0
			)


static func _mark_province_disk(
	field: Variant,
	size: Vector2i,
	center: Vector2i,
	radius: int,
	value: float
) -> void:
	for offset_y in range(-radius, radius + 1):
		for offset_x in range(-radius, radius + 1):
			var point := center + Vector2i(
				offset_x,
				offset_y
			)
			if (
				point.x < 0
				or point.y < 0
				or point.x >= size.x
				or point.y >= size.y
			):
				continue
			var distance := Vector2(
				offset_x,
				offset_y
			).length()
			if distance > float(radius) + 0.001:
				continue
			var falloff := (
				1.0
				if radius <= 1
				else 1.0
					- distance / float(radius + 1)
			)
			var index := point.y * size.x + point.x
			if field is PackedByteArray:
				field[index] = 1
			else:
				field[index] = maxf(
					float(field[index]),
					value * falloff
				)


## Larger projected costs cannot be rounded into a float32 Vector3: the stale
## entry check would discard valid frontier nodes and leave holes in land.
## Keep legacy entries unchanged to preserve existing map generation layouts.
static func _province_heap_entry(cost: float, index: int, owner: int, precise: bool) -> Variant:
	return PackedFloat64Array([cost, index, owner]) if precise else Vector3(cost, index, owner)


static func _province_heap_entry_less(
	a: Variant,
	b: Variant
) -> bool:
	var cost_a := float(a[0])
	var cost_b := float(b[0])
	if not is_equal_approx(cost_a, cost_b):
		return cost_a < cost_b
	var owner_a := int(a[2])
	var owner_b := int(b[2])
	if owner_a != owner_b:
		return owner_a < owner_b
	return int(a[1]) < int(b[1])


static func _province_heap_push(
	heap: Array,
	entry: Variant
) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent: int = (index - 1) / 2
		if not _province_heap_entry_less(
			heap[index],
			heap[parent]
		):
			break
		var temporary: Variant = heap[index]
		heap[index] = heap[parent]
		heap[parent] = temporary
		index = parent


static func _province_heap_pop(
	heap: Array
) -> Variant:
	var result: Variant = heap[0]
	var last: Variant = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		var right := left + 1
		var smallest := index
		if (
			left < heap.size()
			and _province_heap_entry_less(
				heap[left],
				heap[smallest]
			)
		):
			smallest = left
		if (
			right < heap.size()
			and _province_heap_entry_less(
				heap[right],
				heap[smallest]
			)
		):
			smallest = right
		if smallest == index:
			break
		var temporary: Variant = heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = temporary
		index = smallest
	return result


## 确定性的低频连续域扭曲。相邻采样点保持相邻，不引入随机飞地；
## 同时两组不同方向波叠加，避免边界呈现统一波纹。
static func province_metric_point(point: Vector2) -> Vector2:
	var primary := Vector2(
		sin(
			point.y * 0.137
				+ sin(point.x * 0.041) * 1.7
		),
		sin(
			point.x * 0.119
				+ cos(point.y * 0.047) * 1.5
		)
	) * PROVINCE_WARP_PRIMARY_AMPLITUDE
	var secondary := Vector2(
		sin((point.x + point.y) * 0.061 + 0.9),
		cos((point.x - point.y) * 0.057 - 0.6)
	) * PROVINCE_WARP_SECONDARY_AMPLITUDE
	return point + primary + secondary


static func _largest_land_component(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var eligible := PackedByteArray()
	eligible.resize(width * height)
	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			if packed_is_land(color):
				eligible[y * width + x] = 1
	var visited := PackedByteArray()
	visited.resize(width * height)
	var best: Array[int] = []
	var offsets := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for index in range(eligible.size()):
		if eligible[index] == 0 or visited[index] != 0:
			continue
		var queue: Array[int] = [index]
		var component: Array[int] = []
		visited[index] = 1
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			component.append(current)
			var point := Vector2i(current % width, current / width)
			for offset in offsets:
				var next: Vector2i = point + offset
				if next.x < 0 or next.y < 0 or next.x >= width or next.y >= height:
					continue
				var next_index: int = next.y * width + next.x
				if eligible[next_index] == 0 or visited[next_index] != 0:
					continue
				visited[next_index] = 1
				queue.append(next_index)
		if component.size() > best.size():
			best = component
	var mask := PackedByteArray()
	mask.resize(width * height)
	var min_x := width
	var min_y := height
	var max_x := 0
	var max_y := 0
	for index in best:
		mask[index] = 1
		var x := index % width
		var y := index / width
		min_x = mini(min_x, x)
		min_y = mini(min_y, y)
		max_x = maxi(max_x, x)
		max_y = maxi(max_y, y)
	return {
		"mask": mask,
		"count": best.size(),
		"bounds": Rect2i(
			min_x,
			min_y,
			maxi(max_x - min_x + 1, 1),
			maxi(max_y - min_y + 1, 1)
		),
	}


static func _all_land_geometry(image: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var mask := PackedByteArray()
	mask.resize(width * height)
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	var count := 0
	for y in range(height):
		for x in range(width):
			if not packed_is_land(image.get_pixel(x, y)):
				continue
			mask[y * width + x] = 1
			count += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	return {
		"mask": mask,
		"count": count,
		"bounds": Rect2i(
			min_x, min_y,
			maxi(max_x - min_x + 1, 1),
			maxi(max_y - min_y + 1, 1)
		),
	}


static func _sample_cities(
	image: Image,
	mask: PackedByteArray,
	bounds: Rect2i,
	full_bounds: Rect2i,
	city_count: int,
	river_paths: Array[Array],
	city_density_settings: Dictionary,
	generation_seed: int = 0,
	source_manifest: String = MapSource.DEFAULT_MANIFEST
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var scale := Vector2(
		maxi(bounds.size.x, 1),
		maxi(bounds.size.y, 1)
	)
	var map_aspect := (
		float(maxi(bounds.size.x, 1))
		/ float(maxi(bounds.size.y, 1))
	)
	map_aspect *= projected_pixel_aspect(image, source_manifest)
	var base_spacing := minimum_city_spacing_for_count(city_count)
	for y in range(bounds.position.y, bounds.end.y, CANDIDATE_STRIDE):
		for x in range(bounds.position.x, bounds.end.x, CANDIDATE_STRIDE):
			if not _is_interior(mask, image.get_width(), image.get_height(), x, y):
				continue
			# 普通城市不能占用河槽；跨河节点只能由后续根据省界与
			# 高程生成的渡口承担。
			if _pixel_in_river_channel(Vector2i(x, y), river_paths):
				continue
			var relief := _local_relief(image, x, y, RELIEF_RADIUS)
			var height := packed_altitude(
				image.get_pixel(x, y)
			)
			var normalized := (
				Vector2(x, y) - Vector2(bounds.position)
			) / scale
			var full_normalized := _normalized_map_point(
				Vector2(x, y), full_bounds
			)
			var latitude := latitude_for_map_y(
				full_normalized.y, city_density_settings, source_manifest
			)
			var latitude_density := latitude_density_multiplier(
				latitude, city_density_settings
			)
			var river_affinity := _river_bank_affinity(
				Vector2i(x, y),
				bounds,
				river_paths
			)
			var density := settlement_density(
				height,
				relief,
				normalized,
				river_affinity,
				latitude_density
			)
			candidates.append({
				"pixel": Vector2i(x, y),
				"metric_position": Vector2(
					normalized.x * map_aspect, normalized.y
				),
				"height": height,
				"relief": relief,
				"density": density,
				# 小幅确定性扰动让不同世界种子产生不同聚落/省界，
				# 同时仍让地理密度和最小间距主导选址质量。
				"seed_weight": (
					lerpf(
						0.90, 1.10,
						_boundary_random_unit(x, y, generation_seed)
					)
					if generation_seed != 0
					else 1.0
				),
				"river_affinity": river_affinity,
				"latitude": latitude,
				"latitude_density": latitude_density,
				"spacing": clampf(
					base_spacing / sqrt(maxf(density, 0.01)),
					base_spacing * LOCAL_SPACING_MIN_FACTOR,
					base_spacing * LOCAL_SPACING_MAX_FACTOR
				),
			})
	assert(candidates.size() >= city_count, "平坦陆地候选点不足")
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var density_a := float(a["density"]) * float(a["seed_weight"])
		var density_b := float(b["density"]) * float(b["seed_weight"])
		if not is_equal_approx(density_a, density_b):
			return density_a > density_b
		var pa: Vector2i = a["pixel"]
		var pb: Vector2i = b["pixel"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	var first_index := 0
	var selected: Array[Dictionary] = [candidates[first_index]]
	var selected_flags := PackedByteArray()
	selected_flags.resize(candidates.size())
	selected_flags.fill(0)
	selected_flags[first_index] = 1
	var minimum_distance_sq := PackedFloat64Array()
	minimum_distance_sq.resize(candidates.size())
	minimum_distance_sq.fill(INF)
	var minimum_clearance_sq := PackedFloat64Array()
	minimum_clearance_sq.resize(candidates.size())
	minimum_clearance_sq.fill(INF)
	_update_city_candidate_distance_cache(
		candidates, first_index, selected_flags,
		minimum_distance_sq, minimum_clearance_sq
	)
	var spacing_scale := 1.0
	while selected.size() < city_count:
		var best_index := -1
		var best_score := -INF
		var required_clearance_sq := spacing_scale * spacing_scale
		for i in range(candidates.size()):
			var candidate := candidates[i]
			if selected_flags[i] != 0:
				continue
			if minimum_clearance_sq[i] < required_clearance_sq:
				continue
			var score := (
				minimum_distance_sq[i] * float(candidate["density"])
					* float(candidate["seed_weight"])
				- float(candidate["relief"]) * RELIEF_SPACING_WEIGHT
			)
			var candidate_pixel: Vector2i = candidate["pixel"]
			var best_pixel: Vector2i = (
				candidates[best_index]["pixel"]
				if best_index >= 0
				else Vector2i(2147483647, 2147483647)
			)
			if (
				score > best_score
				or (
					is_equal_approx(score, best_score)
					and (
						candidate_pixel.y < best_pixel.y
						or (
							candidate_pixel.y == best_pixel.y
							and candidate_pixel.x < best_pixel.x
						)
					)
				)
			):
				best_score = score
				best_index = i
		if best_index == -1:
			spacing_scale *= SPACING_RELAXATION_STEP
			if spacing_scale < SPACING_RELAXATION_FLOOR:
				# User masks may be narrow or fragmented. Once the normal spacing
				# floor is exhausted, keep farthest-point ordering but remove the
				# hard distance gate so an otherwise valid mask can still fill.
				spacing_scale = 0.0
			continue
		selected.append(candidates[best_index])
		selected_flags[best_index] = 1
		_update_city_candidate_distance_cache(
			candidates, best_index, selected_flags,
			minimum_distance_sq, minimum_clearance_sq
		)
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2i = a["pixel"]
		var pb: Vector2i = b["pixel"]
		return pa.y < pb.y or (pa.y == pb.y and pa.x < pb.x)
	)
	var positions: Array[Vector2] = []
	var pixels: Array[Vector2i] = []
	var heights: Array[float] = []
	var reliefs: Array[float] = []
	for selected_city in selected:
		var pixel: Vector2i = selected_city["pixel"]
		positions.append(Vector2(
			float(pixel.x - bounds.position.x) / float(maxi(bounds.size.x - 1, 1)),
			float(pixel.y - bounds.position.y) / float(maxi(bounds.size.y - 1, 1))
		))
		pixels.append(pixel)
		heights.append(float(selected_city["height"]))
		reliefs.append(float(selected_city["relief"]))
	return {
		"positions": positions,
		"pixels": pixels,
		"heights": heights,
		"reliefs": reliefs,
	}


## farthest-point 采样的增量缓存。旧实现每轮都把全部已选点重扫一遍；
## 最近距离与“距离/双方平均间距”都只会随新点单调减小，因此每加入一个点
## 更新一次即可，选点顺序与放宽间距后的结果保持不变。
static func _update_city_candidate_distance_cache(
	candidates: Array[Dictionary],
	chosen_index: int,
	selected_flags: PackedByteArray,
	minimum_distance_sq: PackedFloat64Array,
	minimum_clearance_sq: PackedFloat64Array
) -> void:
	var chosen: Dictionary = candidates[chosen_index]
	var chosen_metric: Vector2 = chosen["metric_position"]
	var chosen_spacing := float(chosen["spacing"])
	for candidate_index in range(candidates.size()):
		if selected_flags[candidate_index] != 0:
			continue
		var candidate: Dictionary = candidates[candidate_index]
		var candidate_metric: Vector2 = candidate["metric_position"]
		var distance_sq := candidate_metric.distance_squared_to(chosen_metric)
		minimum_distance_sq[candidate_index] = minf(
			minimum_distance_sq[candidate_index], distance_sq
		)
		var pair_spacing := (
			float(candidate["spacing"]) + chosen_spacing
		) * 0.5
		var clearance_sq := (
			distance_sq / maxf(pair_spacing * pair_spacing, 0.000000000001)
		)
		minimum_clearance_sq[candidate_index] = minf(
			minimum_clearance_sq[candidate_index], clearance_sq
		)


static func minimum_city_spacing_for_count(city_count: int) -> float:
	return (
		MIN_CITY_SPACING_AT_REFERENCE
		* sqrt(
			float(REFERENCE_CITY_COUNT)
			/ float(maxi(city_count, 1))
		)
	)


## Keep the default map clearance; denser maps shrink it with settlement spacing.
static func minimum_dock_city_spacing_for_count(city_count: int) -> float:
	return RIVER_DOCK_CITY_MIN_SPACING * minf(
		1.0, sqrt(float(RIVER_DOCK_SPACING_REFERENCE_CITY_COUNT) / float(maxi(city_count, 1)))
	)


## Legacy math helper retained for focused combat/terrain tests. Runtime packed
## map sources use packed_altitude() and never infer height from RGB luminance.
static func altitude_from_luminance(luminance: float) -> float:
	return 1.0 - clampf(luminance, 0.0, 1.0)


## 聚落密度的唯一评分源。海拔/起伏越低越适居，中东部与东南获得人口带加权，
## 河岸获得额外加权；返回值也用于反向缩放局部最小间距。
static func settlement_density(
	height: float,
	relief: float,
	normalized_position: Vector2,
	river_affinity: float,
	latitude_multiplier: float = 1.0
) -> float:
	var lowland := pow(
		1.0 - clampf(height, 0.0, 1.0),
		1.6
	)
	var eastness := smoothstep(
		0.10,
		0.95,
		clampf(normalized_position.x, 0.0, 1.0)
	)
	var southness := smoothstep(
		0.20,
		0.95,
		clampf(normalized_position.y, 0.0, 1.0)
	)
	var centrality := 1.0 - clampf(
		absf(normalized_position.x - 0.62) / 0.62,
		0.0,
		1.0
	)
	var geographic_density := clampf(
		0.35
			+ lowland * 1.00
			+ eastness * 0.55
			+ eastness * southness * 0.35
			+ centrality * 0.15
			+ clampf(river_affinity, 0.0, 1.0) * 0.70
			- clampf(relief, 0.0, 1.0) * 1.20,
		0.35,
		3.00
	)
	return clampf(
		geographic_density * clampf(latitude_multiplier, 0.01, 1.0),
		0.03, 3.00
	)


static func _river_bank_affinity(
	pixel: Vector2i,
	bounds: Rect2i,
	river_paths: Array[Array]
) -> float:
	if river_paths.is_empty():
		return 0.0
	var scale := Vector2(
		maxi(bounds.size.x, 1),
		maxi(bounds.size.y, 1)
	)
	var map_aspect := (
		float(maxi(bounds.size.x, 1))
		/ float(maxi(bounds.size.y, 1))
	)
	var normalized := (
		Vector2(pixel) - Vector2(bounds.position)
	) / scale
	var minimum_distance := INF
	for path in river_paths:
		for river_pixel_value in path:
			var river_pixel: Vector2i = river_pixel_value
			var river_normalized := (
				Vector2(river_pixel) - Vector2(bounds.position)
			) / scale
			var delta := normalized - river_normalized
			delta.x *= map_aspect
			minimum_distance = minf(
				minimum_distance,
				delta.length()
			)
	if minimum_distance < RIVER_BANK_MIN_DISTANCE:
		return 0.0
	if minimum_distance <= RIVER_BANK_IDEAL_DISTANCE:
		return inverse_lerp(
			RIVER_BANK_MIN_DISTANCE,
			RIVER_BANK_IDEAL_DISTANCE,
			minimum_distance
		)
	if minimum_distance >= RIVER_BANK_MAX_DISTANCE:
		return 0.0
	return 1.0 - inverse_lerp(
		RIVER_BANK_IDEAL_DISTANCE,
		RIVER_BANK_MAX_DISTANCE,
		minimum_distance
	)


static func _pixel_in_river_channel(
	pixel: Vector2i,
	river_paths: Array[Array]
) -> bool:
	for path in river_paths:
		for river_pixel_value in path:
			if pixel == Vector2i(river_pixel_value):
				return true
	return false


static func _is_interior(
	mask: PackedByteArray,
	width: int,
	height: int,
	x: int,
	y: int
) -> bool:
	for oy in range(-INTERIOR_RADIUS, INTERIOR_RADIUS + 1):
		for ox in range(-INTERIOR_RADIUS, INTERIOR_RADIUS + 1):
			var px := x + ox
			var py := y + oy
			if px < 0 or py < 0 or px >= width or py >= height:
				return false
			if mask[py * width + px] == 0:
				return false
	return true


static func _local_relief(image: Image, x: int, y: int, radius: int) -> float:
	var minimum := 1.0
	var maximum := 0.0
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var px := clampi(x + ox, 0, image.get_width() - 1)
			var py := clampi(y + oy, 0, image.get_height() - 1)
			var height := packed_altitude(image.get_pixel(px, py))
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
	return maximum - minimum


static func _build_roads(
	image: Image,
	mask: PackedByteArray,
	samples: Dictionary,
	map_aspect_ratio: float,
	provinces: Dictionary,
	river_paths: Array[Array],
	blocked_edges: Dictionary = {}
) -> Dictionary:
	var pixels: Array[Vector2i] = samples["pixels"]
	var positions: Array[Vector2] = samples["positions"]
	# The packed source is square pixels but represents a non-square geographic
	# bbox. Use manifest aspect from the first topology decision onward.
	var topology_aspect := map_aspect_ratio
	var metric_positions := PackedVector2Array()
	for position in positions:
		metric_positions.append(Vector2(
			position.x * topology_aspect,
			position.y
		))
	var province_size: Vector2i = provinces["size"]
	var province_ids: PackedInt32Array = provinces["ids"]
	var shared_boundaries := province_shared_boundary_counts(
		province_ids, province_size
	)
	var adjacency_keys := shared_boundaries.keys()
	adjacency_keys.sort()
	var candidates: Array[Dictionary] = []
	for key_value in adjacency_keys:
		var key := int(key_value)
		var a := key / 10000
		var b := key % 10000
		if (
			a < 0 or b < 0
			or a >= pixels.size() or b >= pixels.size()
		):
			continue
		if provinces.has("physical_components") and LandComponents.at(provinces.physical_components, positions[a]) != LandComponents.at(provinces.physical_components, positions[b]): continue
		# 共享边界是道路拓扑的唯一真源。省份受地形成本影响可能为凹形，
		# 同一省 ID 还可能包含无城市的离岸碎片，因此必须确认两个城市种子
		# 在“两省联合域”内四连通；只在远端小岛接触不构成道路接壤。
		var map_path := PackedVector2Array()
		if not blocked_edges.is_empty() or not province_segment_stays_in_pair(
			province_ids, province_size, positions[a], positions[b], a, b
		):
			map_path = province_pair_path(
				province_ids, province_size, positions[a], positions[b], a, b, blocked_edges, provinces.get("routing_options", {})
			)
			if map_path.size() < 2:
				continue
		var profile := _edge_profile(image, mask, pixels[a], pixels[b])
		if not blocked_edges.is_empty() and map_path.size() >= 2:
			profile = _polyline_terrain_profile(image, mask, map_path)
		var length := (
			metric_polyline_length(map_path, map_aspect_ratio)
			if map_path.size() >= 2
			else metric_positions[a].distance_to(metric_positions[b])
		)
		var candidate := {
			"a": a,
			"b": b,
			"length": length,
			"height_difference": profile["height_difference"],
			"land_ratio": profile["land_ratio"],
			"shared_boundary": int(shared_boundaries[key]),
			"cost": (
				length
				+ float(profile["height_difference"]) * 0.8
				+ (1.0 - float(profile["land_ratio"])) * 3.0
			),
		}
		if map_path.size() >= 2:
			candidate["map_path"] = map_path
		candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cost_a := float(a["cost"])
		var cost_b := float(b["cost"])
		if not is_equal_approx(cost_a, cost_b):
			return cost_a < cost_b
		return _pair_key(int(a["a"]), int(a["b"])) < _pair_key(int(b["a"]), int(b["b"]))
	)
	var legal_candidates: Array[Dictionary] = []
	var connector_candidates: Array[Dictionary] = []
	for candidate in candidates:
		if float(candidate["land_ratio"]) < ROAD_MINIMUM_LAND_RATIO:
			continue
		if (
			float(candidate["height_difference"])
				<= ROAD_MAXIMUM_HEIGHT_DIFFERENCE
		):
			legal_candidates.append(candidate)
		else:
			connector_candidates.append(candidate)
	var selected: Array[Dictionary] = []
	var selected_keys := {}
	var parent: Array[int] = []
	parent.resize(pixels.size())
	for city_id in range(parent.size()):
		parent[city_id] = city_id
	# 省份对偶图可能因海岛分成多个陆地区域；每个区域各自生成一棵
	# 最小骨架树，区域之间交给海运/登陆系统，不制造假陆路。
	for candidate in legal_candidates:
		var root_a := _root(parent, int(candidate["a"]))
		var root_b := _root(parent, int(candidate["b"]))
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		candidate["backbone"] = true
		candidate["terrain_connector"] = false
		selected.append(candidate)
		selected_keys[_pair_key(int(candidate["a"]), int(candidate["b"]))] = true

	# Strict terrain filtering can leave a mountain city or a small highland
	# component outside the ordinary road forest. Connect those components with
	# the shortest available land candidates only after every legal edge has
	# been considered, so relief exceptions remain explicit and minimal.
	connector_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var length_a := float(a["length"])
		var length_b := float(b["length"])
		if not is_equal_approx(length_a, length_b):
			return length_a < length_b
		var relief_a := float(a["height_difference"])
		var relief_b := float(b["height_difference"])
		if not is_equal_approx(relief_a, relief_b):
			return relief_a < relief_b
		return _pair_key(int(a["a"]), int(a["b"])) < _pair_key(int(b["a"]), int(b["b"]))
	)
	for candidate in connector_candidates:
		var root_a := _root(parent, int(candidate["a"]))
		var root_b := _root(parent, int(candidate["b"]))
		if root_a == root_b:
			continue
		parent[root_b] = root_a
		candidate["backbone"] = true
		candidate["terrain_connector"] = true
		selected.append(candidate)
		selected_keys[_pair_key(int(candidate["a"]), int(candidate["b"]))] = true

	for candidate in legal_candidates:
		var key := _pair_key(int(candidate["a"]), int(candidate["b"]))
		if selected_keys.has(key):
			continue
		if float(candidate["length"]) > MAX_LOCAL_EDGE_LENGTH:
			continue
		candidate["backbone"] = false
		candidate["terrain_connector"] = false
		selected.append(candidate)
		selected_keys[key] = true
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var diff_a := float(a["height_difference"])
		var diff_b := float(b["height_difference"])
		if not is_equal_approx(diff_a, diff_b):
			return diff_a < diff_b
		return _pair_key(int(a["a"]), int(a["b"])) < _pair_key(int(b["a"]), int(b["b"]))
	)
	var count := selected.size()
	var standard_capacity_count := int(round(
		float(count) * ROAD_STANDARD_CAPACITY_SHARE
	))
	for i in range(count):
		var road := selected[i]
		var percentile := float(i) / float(maxi(count - 1, 1))
		var max_manpower := (
			Edge.TERRAIN_STANDARD_MANPOWER
			if i < standard_capacity_count
			else Edge.TERRAIN_LOW_MANPOWER
		)
		road["max_manpower"] = max_manpower
		if bool(road.get("terrain_connector", false)):
			road["max_manpower"] = Edge.TERRAIN_LOW_MANPOWER
		if bool(road.get("backbone", false)):
			road["max_manpower"] = maxi(
				int(road["max_manpower"]),
				Edge.TERRAIN_LOW_MANPOWER
			)
		road["base_max_manpower"] = maxi(
			int(road["max_manpower"]),
			Edge.MIN_MANPOWER
		)
		road["danger"] = clampf(percentile, 0.0, 1.0)
		road["length"] = metric_length_between(
			positions[int(road["a"])],
			positions[int(road["b"])],
			map_aspect_ratio
		)
		if bool(provinces.get("routing_options", {}).get("strict", false)) and road.has("map_path"):
			road["length"] = metric_polyline_length(road["map_path"], map_aspect_ratio)
		road["distance"] = distance_units_for_metric_length(
			float(road["length"])
		)
	var blocked_target := maxi(int(round(float(count) * 0.10)), 1)
	var blocked_count := 0
	for i in range(count - 1, -1, -1):
		var road := selected[i]
		if bool(road.get("backbone", false)):
			continue
		road["max_manpower"] = 0
		blocked_count += 1
		if blocked_count >= blocked_target:
			break
	var sea_parent := parent.duplicate()
	if not blocked_edges.is_empty():
		# River-separated banks belong to the same physical landmass. They
		# must be connected by legal docks, not by extra "sea" shortcuts.
		var physical := Hydrology.components(mask, image.get_size(), {})
		var first_by_land := {}
		for i in range(pixels.size()):
			var component := physical[pixels[i].y * image.get_width() + pixels[i].x]
			if provinces.has("physical_components"): component = LandComponents.at(provinces.physical_components, positions[i])
			if first_by_land.has(component): sea_parent[_root(sea_parent, i)] = _root(sea_parent, int(first_by_land[component]))
			else: first_by_land[component] = i
	_append_sea_component_backbone(
		selected, sea_parent, image, mask, pixels, positions,
		map_aspect_ratio, river_paths, not blocked_edges.is_empty()
	)
	return {
		"roads": selected,
	}


## 合法陆路只形成陆地区域内的生成森林。这里用显式海运边连接不同区域，
## 不允许为了全图连通把跨海线伪装成 LAND。
static func _append_sea_component_backbone(
	roads: Array[Dictionary],
	parent: Array[int],
	image: Image,
	mask: PackedByteArray,
	pixels: Array[Vector2i],
	positions: Array[Vector2],
	map_aspect_ratio: float,
	river_paths: Array[Array],
	allow_disconnected: bool = false
) -> void:
	while true:
		var remaining_roots := {}
		for city_id in range(parent.size()):
			remaining_roots[_root(parent, city_id)] = true
		if remaining_roots.size() <= 1:
			break
		var best_a := -1
		var best_b := -1
		var best_length := INF
		for a in range(pixels.size()):
			for b in range(a + 1, pixels.size()):
				if _root(parent, a) == _root(parent, b):
					continue
				var length := metric_length_between(
					positions[a], positions[b], map_aspect_ratio
				)
				# Distance is cheap and independent of rivers. Reject candidates
				# that cannot win before walking every segment of every river.
				if length > best_length + 0.000001:
					continue
				if _segment_crosses_pixel_river(
					pixels[a], pixels[b], river_paths
				):
					continue
				if (
					length < best_length - 0.000001
					or (
						is_equal_approx(length, best_length)
						and _pair_key(a, b) < _pair_key(best_a, best_b)
					)
				):
					best_a = a
					best_b = b
					best_length = length
		if best_a < 0 and allow_disconnected: return
		assert(best_a >= 0, "海区骨架必须存在不穿河道的SEA连接")
		# Terrain describes the chosen edge; it does not participate in selection.
		var best_profile := _edge_profile(image, mask, pixels[best_a], pixels[best_b])
		var root_a := _root(parent, best_a)
		var root_b := _root(parent, best_b)
		parent[root_b] = root_a
		roads.append({
			"a": best_a,
			"b": best_b,
			"length": best_length,
			"height_difference": best_profile["height_difference"],
			"land_ratio": best_profile["land_ratio"],
			"cost": best_length,
			"backbone": true,
			"max_manpower": Edge.WATER_MANPOWER,
			"base_max_manpower": Edge.WATER_MANPOWER,
			"danger": 0.55,
			"distance": distance_units_for_metric_length(best_length),
			"kind": Edge.Kind.SEA,
			"travel_time_multiplier": RIVER_TRAVEL_TIME_MULTIPLIER,
			"supply_loss_multiplier": RIVER_SUPPLY_LOSS_MULTIPLIER,
			"allows_holding": false,
		})


static func _segment_crosses_pixel_river(
	from: Vector2i, to: Vector2i, river_paths: Array[Array]
) -> bool:
	for path in river_paths:
		for index in range(path.size() - 1):
			var hit = Geometry2D.segment_intersects_segment(
				Vector2(from), Vector2(to),
				Vector2(path[index]), Vector2(path[index + 1])
			)
			if hit == null:
				continue
			var point: Vector2 = hit
			if (
				point.distance_to(Vector2(from)) > 0.5
				and point.distance_to(Vector2(to)) > 0.5
			):
				return true
	return false


## 省份对偶图真源：只统计栅格四邻域共享边界；仅在角点接触不算接壤。
## 返回规范化 pair_key -> 共享栅格边数量。
static func province_shared_boundary_counts(
	province_ids: PackedInt32Array,
	size: Vector2i
) -> Dictionary:
	var result := {}
	if (
		size.x <= 0 or size.y <= 0
		or province_ids.size() != size.x * size.y
	):
		return result
	for y in range(size.y):
		for x in range(size.x):
			var owner := int(province_ids[y * size.x + x])
			if owner < 0:
				continue
			if x + 1 < size.x:
				_accumulate_province_boundary(
					result, owner,
					int(province_ids[y * size.x + x + 1])
				)
			if y + 1 < size.y:
				_accumulate_province_boundary(
					result, owner,
					int(province_ids[(y + 1) * size.x + x])
				)
	return result


static func provinces_share_boundary(shared: Dictionary, owner_a: int, owner_b: int) -> bool:
	return shared.has(_pair_key(owner_a, owner_b))


static func _accumulate_province_boundary(
	counts: Dictionary, owner_a: int, owner_b: int
) -> void:
	if owner_b < 0 or owner_a == owner_b:
		return
	var key := _pair_key(owner_a, owner_b)
	counts[key] = int(counts.get(key, 0)) + 1


## 返回一条轴对齐栅格边两侧的规范化省份 ID；不是公共省界时返回 (-1,-1)。
static func province_boundary_segment_owners(
	province_ids: PackedInt32Array,
	size: Vector2i,
	from: Vector2,
	to: Vector2
) -> Vector2i:
	var raster_from := from * Vector2(size)
	var raster_to := to * Vector2(size)
	var a := -1
	var b := -1
	if is_equal_approx(raster_from.x, raster_to.x):
		var x := int(round(raster_from.x))
		var y := int(floor(minf(raster_from.y, raster_to.y) + 0.000001))
		if x <= 0 or x >= size.x or y < 0 or y >= size.y:
			return Vector2i(-1, -1)
		a = int(province_ids[y * size.x + x - 1])
		b = int(province_ids[y * size.x + x])
	elif is_equal_approx(raster_from.y, raster_to.y):
		var x := int(floor(minf(raster_from.x, raster_to.x) + 0.000001))
		var y := int(round(raster_from.y))
		if y <= 0 or y >= size.y or x < 0 or x >= size.x:
			return Vector2i(-1, -1)
		a = int(province_ids[(y - 1) * size.x + x])
		b = int(province_ids[y * size.x + x])
	if a < 0 or b < 0 or a == b:
		return Vector2i(-1, -1)
	return Vector2i(mini(a, b), maxi(a, b))


## 公共测试/编辑器查询：归一化省界顶点是否同时接触至少两个省份和海域。
static func province_boundary_coast_intersection(
	province_ids: PackedInt32Array,
	size: Vector2i,
	position: Vector2
) -> bool:
	var vertex := Vector2i(
		clampi(int(round(position.x * size.x)), 0, size.x),
		clampi(int(round(position.y * size.y)), 0, size.y)
	)
	return _boundary_node_is_coast_intersection(
		province_ids, size, vertex
	)


## 把省份栅格的每条四邻域公共边转成显式线段。端点位于栅格顶点，
## 每条线段同时保存两岸省份和各自贴边的栅格单元；河道、码头和抢滩
## 路径都消费这一份数据，避免三套几何规则彼此漂移。
static func province_boundary_segment_graph(
	province_ids: PackedInt32Array,
	size: Vector2i,
	valid_cells: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var segments: Array[Dictionary] = []
	var adjacency := {}
	if (
		size.x <= 0 or size.y <= 0
		or province_ids.size() != size.x * size.y
	):
		return {"segments": segments, "adjacency": adjacency}
	var vertex_width := size.x + 1
	for y in range(size.y):
		for x in range(size.x):
			var cell_index := y * size.x + x
			var owner := int(province_ids[cell_index])
			if owner < 0:
				continue
			if x + 1 < size.x:
				var right_index := cell_index + 1
				var right_owner := int(
					province_ids[right_index]
				)
				if (
					right_owner >= 0 and right_owner != owner
					and (
						valid_cells.is_empty()
						or (valid_cells[cell_index] != 0 and valid_cells[right_index] != 0)
					)
				):
					_append_province_boundary_segment(
						segments, adjacency, vertex_width,
						Vector2i(x + 1, y), Vector2i(x + 1, y + 1),
						owner, Vector2i(x, y),
						right_owner, Vector2i(x + 1, y)
					)
			if y + 1 < size.y:
				var lower_index := cell_index + size.x
				var lower_owner := int(
					province_ids[lower_index]
				)
				if (
					lower_owner >= 0 and lower_owner != owner
					and (
						valid_cells.is_empty()
						or (valid_cells[cell_index] != 0 and valid_cells[lower_index] != 0)
					)
				):
					_append_province_boundary_segment(
						segments, adjacency, vertex_width,
						Vector2i(x, y + 1), Vector2i(x + 1, y + 1),
						owner, Vector2i(x, y),
						lower_owner, Vector2i(x, y + 1)
					)
	return {
		"segments": segments,
		"adjacency": adjacency,
		"vertex_width": vertex_width,
		"size": size,
	}


static func _append_province_boundary_segment(
	segments: Array[Dictionary],
	adjacency: Dictionary,
	vertex_width: int,
	from: Vector2i,
	to: Vector2i,
	owner_a: int,
	cell_a: Vector2i,
	owner_b: int,
	cell_b: Vector2i
) -> void:
	var lower_owner := mini(owner_a, owner_b)
	var upper_owner := maxi(owner_a, owner_b)
	var segment_index := segments.size()
	var from_key := from.y * vertex_width + from.x
	var to_key := to.y * vertex_width + to.x
	segments.append({
		"from": from,
		"to": to,
		"from_key": from_key,
		"to_key": to_key,
		"a": lower_owner,
		"b": upper_owner,
		"cell_a": cell_a if owner_a == lower_owner else cell_b,
		"cell_b": cell_b if owner_b == upper_owner else cell_a,
		"pair_key": _pair_key(lower_owner, upper_owner),
	})
	for node_key in [from_key, to_key]:
		if not adjacency.has(node_key):
			adjacency[node_key] = [] as Array[int]
		(adjacency[node_key] as Array[int]).append(segment_index)


## 只保留每个城市种子所在的同 ID 四连通省域。地形求解可能给离岸小岛
## 或狭窄飞地同一个省 ID，但那些碎片不能凭 ID 直接连接到岸边城市。
static func _province_city_seed_components(
	province_ids: PackedInt32Array,
	size: Vector2i,
	city_positions: Array[Vector2]
) -> PackedByteArray:
	var valid := PackedByteArray()
	valid.resize(size.x * size.y)
	var queue: Array[int] = []
	for city_id in range(city_positions.size()):
		var position := city_positions[city_id]
		var cell := Vector2i(
			clampi(int(floor(position.x * size.x)), 0, size.x - 1),
			clampi(int(floor(position.y * size.y)), 0, size.y - 1)
		)
		var index := cell.y * size.x + cell.x
		if int(province_ids[index]) == city_id and valid[index] == 0:
			valid[index] = 1
			queue.append(index)
	var head := 0
	var offsets := [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	]
	while head < queue.size():
		var current_index := queue[head]
		head += 1
		var owner := int(province_ids[current_index])
		var current := Vector2i(
			current_index % size.x, current_index / size.x
		)
		for offset_value in offsets:
			var next: Vector2i = current + offset_value
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var next_index := next.y * size.x + next.x
			if valid[next_index] != 0 or int(province_ids[next_index]) != owner:
				continue
			valid[next_index] = 1
			queue.append(next_index)
	return valid


## 从完整公共边界图中抽取两条西向东走廊。第一条近水平穿过中部，
## 第二条从西部中南侧向东缓慢南偏；全程仍只消费公共省界线段。
static func _build_boundary_river_network(
	provinces: Dictionary,
	city_positions: Array[Vector2],
	map_aspect_ratio: float
) -> Dictionary:
	var size: Vector2i = provinces["size"]
	var ids: PackedInt32Array = provinces["ids"]
	var valid_cells := _province_city_seed_components(
		ids, size, city_positions
	)
	var graph := province_boundary_segment_graph(
		ids, size, valid_cells
	)
	var segments: Array[Dictionary] = graph["segments"]
	var blocked_edges := {}
	var blocked_nodes := {}
	var rivers: Array[Dictionary] = []
	var normalized_paths: Array[PackedVector2Array] = []
	var pixel_paths: Array[Array] = []
	var river_pair_keys := {}
	for river_id in range(RIVER_COUNT):
		var trail := _coastal_boundary_river_trail(
			graph, ids, blocked_edges, blocked_nodes, river_id,
			map_aspect_ratio
		)
		if (
			trail.is_empty()
			or float(trail.get("length", 0.0)) < BOUNDARY_RIVER_MIN_LENGTH
		):
			trail = _coastal_boundary_river_trail(
				graph, ids, blocked_edges, {}, river_id,
				map_aspect_ratio
			)
		if (
			trail.is_empty()
			or float(trail.get("length", 0.0)) < BOUNDARY_RIVER_MIN_LENGTH
		):
			# 第一条横河可能恰好切断省界图；两条目标走廊相距较远，
			# 最后允许第二条重新消费原图，由走廊成本自然保持分离。
			trail = _coastal_boundary_river_trail(
				graph, ids, {}, {}, river_id, map_aspect_ratio
			)
		if (
			trail.is_empty()
			or float(trail.get("length", 0.0)) < BOUNDARY_RIVER_MIN_LENGTH
		):
			# 极小地图可能没有足够长的公共省界。河流只能消费真实省界，
			# 因此宁可少生成，也不能用跨海或屏幕直线补齐固定数量。
			break
		var node_keys: Array = trail["nodes"]
		var edge_indices: Array = trail["edge_indices"]
		var path := PackedVector2Array()
		var pixel_path: Array = []
		for node_value in node_keys:
			var node := _boundary_node_position(
				int(node_value), int(graph["vertex_width"])
			)
			path.append(Vector2(node) / Vector2(size))
			# 城市像素坐标表示像素中心；栅格顶点需减半个像素才能
			# 与道路/海运的分析坐标落在同一几何空间。
			pixel_path.append(Vector2(node) - Vector2(0.5, 0.5))
		for edge_value in edge_indices:
			var edge_index := int(edge_value)
			blocked_edges[edge_index] = true
			river_pair_keys[int(segments[edge_index]["pair_key"])] = true
		for node_value in node_keys:
			blocked_nodes[int(node_value)] = true
		var river := trail.duplicate(true)
		river["river_id"] = river_id
		river["path"] = path
		river["pixel_path"] = pixel_path
		rivers.append(river)
		normalized_paths.append(path)
		pixel_paths.append(pixel_path)
	return {
		"graph": graph,
		"rivers": rivers,
		"paths": normalized_paths,
		"pixel_paths": pixel_paths,
		"river_pair_keys": river_pair_keys,
	}

## Adapt immutable hydrological reaches to the existing two-bank dock selector.
## Reserve isolated crossing sites, never an entire river-bank exclusion corridor.
static func _reservation_identity() -> String:
	return "%s:%s:%s:%s:%s" % [RIVER_RESERVATION_VERSION, RIVER_DOCK_CITY_MIN_SPACING, RIVER_DOCK_SPACING_REFERENCE_CITY_COUNT, RIVER_DOCK_MIN_SPACING, RIVER_DOCK_LOWLAND_ALTITUDE]

static func _reserve_hydrology_docks(environment: Dictionary, image: Image, aspect: float, city_count: int, full_network: bool = false) -> Array:
	var key := str(environment.hydrology.hydrology_id) + _reservation_identity() + str(city_count) + str(full_network) + DockSampling.VERSION
	if _reservation_cache.has(key): return _reservation_cache[key].duplicate(true)
	var ids: PackedInt32Array = environment.components.duplicate()
	var areas := {}
	for id in ids:
		if id >= 0: areas[id] = int(areas.get(id, 0)) + 1
	var minimum_area := PI * pow(minimum_dock_city_spacing_for_count(city_count), 2.0)
	for i in range(ids.size()):
		if ids[i] >= 0 and float(areas[ids[i]]) * aspect / ids.size() < minimum_area: ids[i] = -1
	var input := _hydrology_transport_input({"size": environment.size, "ids": ids}, environment.hydrology.features, full_network, aspect, full_network)
	var candidates: Array[Dictionary] = []
	for river in input.rivers:
		for sample in river.dock_samples:
			var position: Vector2 = river.path[sample.path_index].lerp(river.path[sample.path_index + 1], sample.ratio)
			var pixel := Vector2i(position * Vector2(image.get_size())).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
			var height := packed_altitude(image.get_pixelv(pixel))
			if not full_network and height > RIVER_DOCK_LOWLAND_ALTITUDE: continue
			var banks: Dictionary = input.graph.segments[sample.graph_index]
			candidates.append({"position": position, "river_id": river.river_id, "river_progress": sample.path_index + sample.ratio, "height": height, "relief": _local_relief(image, pixel.x, pixel.y, RELIEF_RADIUS), "cell_a": banks.cell_a, "cell_b": banks.cell_b, "a": banks.a, "b": banks.b})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		for field in ["height", "relief", "river_id", "river_progress"]:
			if a[field] != b[field]: return a[field] < b[field]
		return a.cell_a.y * image.get_width() + a.cell_a.x < b.cell_a.y * image.get_width() + b.cell_a.x
	)
	var parent: Array[int] = []
	var max_id := -1
	for id in areas: max_id = maxi(max_id, id)
	for i in range(max_id + 1): parent.append(i)
	var selected: Array = []
	var positions: Array[Vector2] = []
	for candidate in candidates:
		var a := _root(parent, candidate.a)
		var b := _root(parent, candidate.b)
		if a == b or _minimum_metric_position_distance(candidate.position, positions, aspect) < RIVER_DOCK_MIN_SPACING: continue
		parent[b] = a
		selected.append(candidate)
		positions.append(candidate.position)
	if _reservation_cache.size() >= 8: _reservation_cache.erase(_reservation_cache.keys()[0])
	_reservation_cache[key] = selected.duplicate(true)
	return selected

## Missing boundary segments (same province or unowned shore) cannot host docks.
static func _hydrology_transport_input(provinces: Dictionary, features: Array, strict_transport: bool = false, aspect: float = 1.0, full_network: bool = false) -> Dictionary:
	if full_network:
		return _continuous_hydrology_transport_input(provinces, features, aspect)
	var size: Vector2i = provinces.size
	var all_major_paths := MapFeatureContract.major_paths(features)
	var empty_positions: Array[Vector2] = []
	var segments: Array[Dictionary] = []
	var rivers: Array[Dictionary] = []
	var paths: Array[PackedVector2Array] = []
	var pixel_paths: Array[Array] = []
	for feature in MapFeatureContract.major_rivers(features):
		var path: PackedVector2Array = feature.points
		var pixels: Array = []
		var dock_samples: Array[Dictionary] = []
		for p in path: pixels.append(p * Vector2(size) - Vector2(0.5, 0.5))
		for i in range(path.size() - 1):
			var p := path[i] * Vector2(size)
			var q := path[i + 1] * Vector2(size)
			var first := Vector2i((p.min(q) - Vector2.ONE).floor()).max(Vector2i.ZERO)
			var last := Vector2i((p.max(q) + Vector2.ONE).ceil()).min(size - Vector2i.ONE)
			for y in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1):
					var cell := Vector2i(x, y)
					var a := Vector2(cell) + Vector2.ONE * 0.5
					for step in [Vector2i.RIGHT, Vector2i.DOWN]:
						var other: Vector2i = cell + step
						if not Rect2i(Vector2i.ZERO, size).has_point(other): continue
						var hit: Variant = Geometry2D.segment_intersects_segment(p, q, a, a + Vector2(step))
						if hit == null: continue
						var owner_a := int(provinces.ids[y * size.x + x])
						var owner_b := int(provinces.ids[other.y * size.x + other.x])
						if owner_a < 0 or owner_b < 0 or owner_a == owner_b: continue
						var ratio := clampf(((hit as Vector2) - p).dot(q - p) / (q - p).length_squared(), 0.0, 1.0)
						var dock_position := path[i].lerp(path[i + 1], ratio)
						# Several meanders may cross a single coarse province edge.
						# Both banks must reach this exact dock without another crossing.
						var approach_a := {"map_path": PackedVector2Array([a / Vector2(size), dock_position])}
						var approach_b := {"map_path": PackedVector2Array([(a + Vector2(step)) / Vector2(size), dock_position])}
						if _road_dictionary_crosses_rivers(approach_a, empty_positions, all_major_paths) or _road_dictionary_crosses_rivers(approach_b, empty_positions, all_major_paths): continue
						dock_samples.append({"path_index": i, "ratio": ratio, "graph_index": segments.size()})
						segments.append({"a": owner_a, "b": owner_b, "cell_a": cell, "cell_b": other})
		if strict_transport:
			var progress := 0.003
			var traversed := 0.0
			for i in range(path.size() - 1):
				var length := metric_length_between(path[i], path[i + 1], aspect)
				while progress <= traversed + length and length > 0:
					var ratio := clampf((progress - traversed) / length, 0.0, 1.0)
					var position := path[i].lerp(path[i + 1], ratio)
					var banks := _sample_vector_banks(provinces, position, path[i + 1] - path[i], all_major_paths, aspect)
					if not banks.is_empty():
						dock_samples.append({"path_index": i, "ratio": ratio, "graph_index": segments.size()})
						segments.append(banks)
					progress += 0.006
				traversed += length
		dock_samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path_index + a.ratio < b.path_index + b.ratio)
		rivers.append({"river_id": feature.id, "path": path, "pixel_path": pixels, "edge_indices": [], "dock_samples": dock_samples, "hydrological": true, "strict_transport": strict_transport})
		paths.append(path)
		pixel_paths.append(pixels)
	return {"graph": {"segments": segments}, "rivers": rivers, "paths": paths, "pixel_paths": pixel_paths, "river_pair_keys": {}, "features": features, "hydrological": true}

static func _continuous_hydrology_transport_input(provinces: Dictionary, features: Array, aspect: float) -> Dictionary:
	var size: Vector2i = provinces.size
	var paths := MapFeatureContract.major_paths(features)
	var segments: Array[Dictionary] = []
	var rivers: Array[Dictionary] = []
	var pixels: Array[Array] = []
	var by_id := {}
	for feature in MapFeatureContract.major_rivers(features):
		var path: PackedVector2Array = feature.points
		var pixel_path: Array = []
		for p in path: pixel_path.append(p * Vector2(size) - Vector2.ONE * 0.5)
		var river := {"river_id": feature.id, "path": path, "pixel_path": pixel_path, "edge_indices": [], "dock_samples": [], "hydrological": true, "strict_transport": true, "full_network": true, "provinces": provinces, "features": features}
		by_id[int(feature.id)] = river
		rivers.append(river)
		pixels.append(pixel_path)
	var rejected := []
	var all_samples := DockSampling.samples(features, aspect)
	for sample in all_samples:
		var banks := _raster_river_banks(provinces, sample.position, sample.direction, paths, aspect)
		if banks.is_empty():
			rejected.append({"coverage": sample.coverage, "reason": "no_bank_city", "reach_fraction": sample.reach_fraction})
			continue
		var value: Dictionary = sample.duplicate()
		value.merge({"path_index": int(floor(sample.river_progress)), "ratio": fmod(sample.river_progress, 1.0), "graph_index": segments.size()})
		by_id[int(sample.river_id)].dock_samples.append(value)
		segments.append(banks)
	return {"graph": {"segments": segments}, "rivers": rivers, "paths": paths, "pixel_paths": pixels, "river_pair_keys": {}, "features": features, "hydrological": true, "full_network": true, "sample_rejections": rejected, "all_samples": all_samples}

static func _raster_river_banks(provinces: Dictionary, position: Vector2, direction: Vector2, paths: Array[PackedVector2Array], aspect: float) -> Dictionary:
	var size: Vector2i = provinces.size
	var normal := (direction * Vector2(aspect, 1)).orthogonal().normalized() / Vector2(aspect, 1)
	var cell_radius := Vector2(aspect / size.x, 1.0 / size.y).length()
	var no_positions: Array[Vector2] = []
	for scale_value in [0.01, 0.1, 0.25, 0.5, 0.75]:
		var a := position + normal * cell_radius * float(scale_value)
		var b := position - normal * cell_radius * float(scale_value)
		if not Rect2(0, 0, 1, 1).has_point(a) or not Rect2(0, 0, 1, 1).has_point(b): continue
		var ca := Vector2i(a * Vector2(size))
		var cb := Vector2i(b * Vector2(size))
		var oa: int = provinces.ids[ca.y * size.x + ca.x]
		var ob: int = provinces.ids[cb.y * size.x + cb.x]
		if oa < 0 or ob < 0 or oa == ob: continue
		var pa := (Vector2(ca) + Vector2.ONE * 0.5) / Vector2(size)
		var pb := (Vector2(cb) + Vector2.ONE * 0.5) / Vector2(size)
		if _road_dictionary_crosses_rivers({"map_path": PackedVector2Array([pa, position])}, no_positions, paths): continue
		if _road_dictionary_crosses_rivers({"map_path": PackedVector2Array([pb, position])}, no_positions, paths): continue
		return {"a": oa, "b": ob, "cell_a": ca, "cell_b": cb}
	return {}

static func _sample_vector_banks(provinces: Dictionary, position: Vector2, direction: Vector2, paths: Array[PackedVector2Array], aspect: float) -> Dictionary:
	var size: Vector2i = provinces.size
	var center := Vector2i(position * Vector2(size))
	var candidates: Array[Dictionary] = []
	for y in range(maxi(0, center.y - 2), mini(size.y, center.y + 3)):
		for x in range(maxi(0, center.x - 2), mini(size.x, center.x + 3)):
			var owner := int(provinces.ids[y * size.x + x])
			if owner < 0: continue
			var p := (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(size)
			candidates.append({"owner": owner, "cell": Vector2i(x,y), "point": p, "side": signf(direction.cross(p-position)), "distance": metric_length_between(p,position,aspect)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.distance < b.distance)
	var banks := {}
	var no_positions: Array[Vector2] = []
	for candidate in candidates:
		var side := int(candidate.side)
		if side == 0 or banks.has(side): continue
		if _road_dictionary_crosses_rivers({"map_path": PackedVector2Array([candidate.point,position])},no_positions,paths): continue
		banks[side] = candidate
		if banks.size() == 2: break
	if banks.size() < 2 or banks[-1].owner == banks[1].owner: return {}
	return {"a": banks[-1].owner, "b": banks[1].owner, "cell_a": banks[-1].cell, "cell_b": banks[1].cell}


## 固定端点河流：源头取省界网络西侧最贴近目标纬度的节点，河口必须
## 是“两个省份公共边界与海岸线”的交点。固定端点后用省界图最短路
## 连接，纵向距离额外放大，使上河近水平、下河只按端点缓慢南偏。
static func _coastal_boundary_river_trail(
	graph: Dictionary,
	province_ids: PackedInt32Array,
	blocked_edges: Dictionary,
	blocked_nodes: Dictionary,
	river_id: int,
	map_aspect_ratio: float
) -> Dictionary:
	var adjacency: Dictionary = graph["adjacency"]
	var segments: Array[Dictionary] = graph["segments"]
	var size: Vector2i = graph["size"]
	var vertex_width := int(graph["vertex_width"])
	var node_keys := adjacency.keys()
	node_keys.sort()
	var unseen := {}
	for node_value in node_keys:
		var node := int(node_value)
		if not blocked_nodes.has(node):
			unseen[node] = true
	var selected_component: Array[int] = []
	var selected_start := -1
	var selected_goal := -1
	var selected_score := -INF
	var source_target_y := 0.52 if river_id == 0 else 0.62
	var mouth_target_y := 0.52 if river_id == 0 else 0.70
	while not unseen.is_empty():
		var remaining := unseen.keys()
		remaining.sort()
		var component := _boundary_component_nodes(
			int(remaining[0]), adjacency, segments, blocked_edges, blocked_nodes
		)
		var minimum_x := INF
		var maximum_x := -INF
		var coast_nodes: Array[int] = []
		for node in component:
			unseen.erase(node)
			var raster_position := _boundary_node_position(node, vertex_width)
			var position := Vector2(raster_position) / Vector2(size)
			minimum_x = minf(minimum_x, position.x)
			maximum_x = maxf(maximum_x, position.x)
			if _boundary_node_is_coast_intersection(
				province_ids, size, raster_position
			):
				coast_nodes.append(node)
		if component.size() < 2 or coast_nodes.is_empty():
			continue
		var span := maximum_x - minimum_x
		if span < BOUNDARY_RIVER_MIN_LENGTH:
			continue
		var start_candidates: Array[int] = []
		for node in component:
			var x := (
				float(_boundary_node_position(node, vertex_width).x)
					/ float(size.x)
			)
			if x <= minimum_x + span * 0.12:
				start_candidates.append(node)
		for start in start_candidates:
			var start_position := Vector2(
				_boundary_node_position(start, vertex_width)
			) / Vector2(size)
			for goal in coast_nodes:
				var goal_position := Vector2(
					_boundary_node_position(goal, vertex_width)
				) / Vector2(size)
				var horizontal_span := goal_position.x - start_position.x
				if horizontal_span < maxf(span * 0.55, 0.35):
					continue
				var endpoint_error := (
					absf(start_position.y - source_target_y)
					+ absf(goal_position.y - mouth_target_y)
				)
				# 起点/河口纬度是固定形态的主约束；横向跨度只在
				# 同纬度候选之间择优，避免为了多向东一点跑到北部海岸。
				var score := horizontal_span * 12.0 - endpoint_error * 100.0
				if (
					score > selected_score + 0.000001
					or (
						is_equal_approx(score, selected_score)
						and _pair_key(start, goal)
							< _pair_key(selected_start, selected_goal)
					)
				):
					selected_score = score
					selected_component = component
					selected_start = start
					selected_goal = goal
	if selected_start < 0 or selected_goal < 0:
		return {}
	var component_lookup := {}
	for node in selected_component:
		component_lookup[node] = true
	var astar := AStar2D.new()
	for node in selected_component:
		var position := Vector2(
			_boundary_node_position(node, vertex_width)
		) / Vector2(size)
		astar.add_point(node, Vector2(
			position.x * map_aspect_ratio, position.y * 2.8
		))
	for node in selected_component:
		for edge_value in adjacency.get(node, []):
			var edge_index := int(edge_value)
			if blocked_edges.has(edge_index):
				continue
			var segment: Dictionary = segments[edge_index]
			var neighbor := (
				int(segment["to_key"])
				if int(segment["from_key"]) == node
				else int(segment["from_key"])
			)
			if (
				not component_lookup.has(neighbor)
				or astar.are_points_connected(node, neighbor)
			):
				continue
			astar.connect_points(node, neighbor, true)
	var id_path := astar.get_id_path(selected_start, selected_goal)
	if id_path.size() < 2:
		return {}
	var nodes: Array[int] = []
	var edge_indices: Array[int] = []
	for node_value in id_path:
		nodes.append(int(node_value))
	for path_index in range(nodes.size() - 1):
		var found_edge := -1
		for edge_value in adjacency[nodes[path_index]]:
			var edge_index := int(edge_value)
			if blocked_edges.has(edge_index):
				continue
			var segment: Dictionary = segments[edge_index]
			if nodes[path_index + 1] in [
				int(segment["from_key"]), int(segment["to_key"])
			]:
				found_edge = edge_index
				break
		assert(found_edge >= 0, "省界河路径必须能还原每一条公共边界线段")
		edge_indices.append(found_edge)
	return {
		"nodes": nodes,
		"edge_indices": edge_indices,
		"length": _boundary_trail_metric_length(
			nodes, vertex_width, size, map_aspect_ratio
		),
		"source_node": selected_start,
		"mouth_node": selected_goal,
	}


static func _boundary_node_is_coast_intersection(
	province_ids: PackedInt32Array,
	size: Vector2i,
	vertex: Vector2i
) -> bool:
	var owners := {}
	var touches_sea := false
	for offset in [
		Vector2i(-1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(0, 0),
	]:
		var cell: Vector2i = vertex + offset
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			continue
		var owner := int(province_ids[cell.y * size.x + cell.x])
		if owner < 0:
			touches_sea = true
		else:
			owners[owner] = true
	return touches_sea and owners.size() >= 2


static func _boundary_component_nodes(
	start: int,
	adjacency: Dictionary,
	segments: Array[Dictionary],
	blocked_edges: Dictionary,
	blocked_nodes: Dictionary
) -> Array[int]:
	var result: Array[int] = []
	var visited := {start: true}
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var node := queue[head]
		head += 1
		result.append(node)
		for edge_value in adjacency.get(node, []):
			var edge_index := int(edge_value)
			if blocked_edges.has(edge_index):
				continue
			var segment: Dictionary = segments[edge_index]
			var neighbor := (
				int(segment["to_key"])
				if int(segment["from_key"]) == node
				else int(segment["from_key"])
			)
			if blocked_nodes.has(neighbor) or visited.has(neighbor):
				continue
			visited[neighbor] = true
			queue.append(neighbor)
	return result


static func _boundary_trail_metric_length(
	nodes: Array,
	vertex_width: int,
	size: Vector2i,
	map_aspect_ratio: float
) -> float:
	var result := 0.0
	for index in range(nodes.size() - 1):
		var from := Vector2(
			_boundary_node_position(int(nodes[index]), vertex_width)
		) / Vector2(size)
		var to := Vector2(
			_boundary_node_position(int(nodes[index + 1]), vertex_width)
		) / Vector2(size)
		result += metric_length_between(from, to, map_aspect_ratio)
	return result


static func _boundary_node_position(
	node_key: int, vertex_width: int
) -> Vector2i:
	return Vector2i(node_key % vertex_width, node_key / vertex_width)


## 验证任一道路折线段只经过端点两省；按栅格尺度 2 倍超采样覆盖对角穿格。
static func province_segment_stays_in_pair(
	province_ids: PackedInt32Array,
	size: Vector2i,
	from: Vector2,
	to: Vector2,
	province_a: int,
	province_b: int
) -> bool:
	if (
		size.x <= 0 or size.y <= 0
		or province_ids.size() != size.x * size.y
	):
		return false
	var raster_from := Vector2(
		from.x * float(size.x), from.y * float(size.y)
	)
	var raster_to := Vector2(
		to.x * float(size.x), to.y * float(size.y)
	)
	var sample_count := maxi(
		int(ceil(maxf(
			absf(raster_to.x - raster_from.x),
			absf(raster_to.y - raster_from.y)
		) * 2.0)),
		1
	)
	for sample in range(sample_count + 1):
		var ratio := float(sample) / float(sample_count)
		var point := from.lerp(to, ratio)
		var x := clampi(int(floor(point.x * float(size.x))), 0, size.x - 1)
		var y := clampi(int(floor(point.y * float(size.y))), 0, size.y - 1)
		var owner := int(province_ids[y * size.x + x])
		if owner not in [province_a, province_b]:
			return false
	return true


## 为凹形接壤省份生成联合域内的正式道路折线。直线本来就合法时不保存冗余路径。
static func _attach_province_land_paths(
	roads: Array[Dictionary],
	provinces: Dictionary,
	positions: Array[Vector2],
	land_city_count: int,
	map_aspect_ratio: float = FULL_MAP_ASPECT_RATIO,
	blocked_edges: Dictionary = {}
) -> void:
	var size: Vector2i = provinces["size"]
	var ids: PackedInt32Array = provinces["ids"]
	for road in roads:
		if (
			int(road.get("kind", Edge.Kind.LAND)) != Edge.Kind.LAND
			or int(road["a"]) >= land_city_count
			or int(road["b"]) >= land_city_count
		):
			continue
		var a := int(road["a"])
		var b := int(road["b"])
		if not blocked_edges.is_empty() and road.has("map_path"): continue
		if blocked_edges.is_empty() and (road.has("map_path") or province_segment_stays_in_pair(
			ids, size, positions[a], positions[b], a, b
		)):
			continue
		var path := province_pair_path(
			ids, size, positions[a], positions[b], a, b, blocked_edges, provinces.get("routing_options", {})
		)
		if path.size() >= 2:
			road["map_path"] = path
			var metric_length := metric_polyline_length(
				path, map_aspect_ratio
			)
			road["length"] = metric_length
			road["distance"] = distance_units_for_metric_length(metric_length)


static func simplify_saved_road_path(path: PackedVector2Array, provinces: Dictionary, a: int, b: int, options: Dictionary) -> PackedVector2Array:
	if path.size() <= 2: return path.duplicate()
	var result := PackedVector2Array([path[0]])
	var anchor := 0
	while anchor < path.size() - 1:
		# Keep an existing hop if no new shortcut is legal. This stage does not
		# invent roads, alter their adjacency or re-run the candidate selection.
		var next := anchor + 1
		for candidate in range(path.size() - 1, anchor + 1, -1):
			if not _segment_in_pair_exact(provinces.ids, provinces.size, path[anchor], path[candidate], a, b): continue
			if not _safe_road_shortcut(path[anchor], path[candidate], options): continue
			next = candidate
			break
		if not result[-1].is_equal_approx(path[next]): result.append(path[next])
		anchor = next
	return result


static func _simplify_generated_land_roads(roads: Array[Dictionary], provinces: Dictionary, image: Image, features: Array, aspect: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var options := {"image": image, "river_paths": MapFeatureContract.major_paths(features), "aspect": aspect}
	var changed := 0
	var before_points := 0
	var after_points := 0
	for road in roads:
		if int(road.get("kind", Edge.Kind.LAND)) != Edge.Kind.LAND: continue
		var path: PackedVector2Array = road.get("map_path", PackedVector2Array())
		before_points += path.size()
		var simplified := simplify_saved_road_path(path, provinces, int(road.a), int(road.b), options)
		after_points += simplified.size()
		if simplified == path: continue
		changed += 1
		var old_length := float(road.get("length", metric_polyline_length(path, aspect)))
		road.map_path = simplified
		road.length = metric_polyline_length(simplified, aspect)
		road.distance = distance_units_for_metric_length(road.length)
		if road.has("cost"): road.cost = float(road.cost) - old_length + road.length
	return {"model": MapSource.VISIBILITY_ROAD_PATH, "changed_roads": changed,
		"before_points": before_points, "after_points": after_points,
		"elapsed_usec": Time.get_ticks_usec() - started}


static func metric_polyline_length(
	points: PackedVector2Array, map_aspect_ratio: float
) -> float:
	var result := 0.0
	for index in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		delta.x *= map_aspect_ratio
		result += delta.length()
	return result


## 在两个端点省份的联合栅格内做确定性 A*。返回归一化地图折线，首尾钉死城市中心。
static func province_pair_path(province_ids: PackedInt32Array, size: Vector2i, from: Vector2, to: Vector2, province_a: int, province_b: int, blocked_edges: Dictionary = {}, routing_options: Dictionary = {}) -> PackedVector2Array:
	var result := _coarse_province_pair_path(province_ids, size, from, to, province_a, province_b, blocked_edges, routing_options)
	if result.is_empty() and routing_options.get("pixel_fallback", false):
		# A river-separated pair has no legal coarse corridor. Do not explore
		# every terrain pixel merely to rediscover this topological rejection.
		if _coarse_province_pair_path(province_ids, size, from, to, province_a, province_b, blocked_edges, {}).is_empty(): return result
		return PixelRoute.find(province_ids, size, from, to, province_a, province_b, routing_options)
	return result

static func _coarse_province_pair_path(
	province_ids: PackedInt32Array,
	size: Vector2i,
	from: Vector2,
	to: Vector2,
	province_a: int,
	province_b: int,
	blocked_edges: Dictionary = {},
	routing_options: Dictionary = {}
) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if (
		size.x <= 0 or size.y <= 0
		or province_ids.size() != size.x * size.y
	):
		return empty
	if routing_options.get("strict",false) and _safe_road_shortcut(from,to,routing_options) and _segment_in_pair_exact(province_ids,size,from,to,province_a,province_b):
		return PackedVector2Array([from,to])
	var start := Vector2i(
		clampi(int(floor(from.x * size.x)), 0, size.x - 1),
		clampi(int(floor(from.y * size.y)), 0, size.y - 1)
	)
	var goal := Vector2i(
		clampi(int(floor(to.x * size.x)), 0, size.x - 1),
		clampi(int(floor(to.y * size.y)), 0, size.y - 1)
	)
	var start_index := start.y * size.x + start.x
	var goal_index := goal.y * size.x + goal.x
	var route_image: Image = routing_options.get("image")
	var route_heights: PackedFloat32Array = routing_options.get("heights", PackedFloat32Array())
	var representatives: PackedVector2Array = routing_options.get("representatives", PackedVector2Array())
	if route_heights.is_empty() and routing_options.get("strict", false) and route_image != null:
		route_heights.resize(size.x * size.y)
		if routing_options.get("pixel_fallback", false): representatives.resize(size.x * size.y)
		for y in range(size.y):
			for x in range(size.x):
				var pixel := Vector2i((Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(size) * Vector2(route_image.get_size())).clamp(Vector2i.ZERO, route_image.get_size() - Vector2i.ONE)
				# A coastal province cell may contain real land although its
				# center is sea. Keep a legal representative inside that cell;
				# every connecting segment is still checked against the source.
				if not representatives.is_empty() and province_ids[y * size.x + x] >= 0 and not packed_is_land(route_image.get_pixelv(pixel)):
					var first := Vector2i(Vector2(x, y) / Vector2(size) * Vector2(route_image.get_size()))
					var last := Vector2i(Vector2(x + 1, y + 1) / Vector2(size) * Vector2(route_image.get_size()))
					var closest := pixel
					var best := INF
					for py in range(first.y, last.y):
						for px in range(first.x, last.x):
							var p := Vector2i(px, py)
							var d := Vector2(p).distance_squared_to(Vector2(pixel))
							if d < best and packed_is_land(route_image.get_pixelv(p)): closest = p; best = d
					pixel = closest
				var color := route_image.get_pixelv(pixel)
				route_heights[y * size.x + x] = packed_altitude(color) if packed_is_land(color) else -1.0
				if not representatives.is_empty(): representatives[y * size.x + x] = (Vector2(pixel) + Vector2.ONE * 0.5) / Vector2(route_image.get_size())
		routing_options["heights"] = route_heights
		if not representatives.is_empty(): routing_options["representatives"] = representatives
	var distance := PackedFloat64Array()
	distance.resize(size.x * size.y)
	distance.fill(INF)
	var previous := PackedInt32Array()
	previous.resize(size.x * size.y)
	previous.fill(-1)
	var heap: Array[Vector3] = []
	distance[start_index] = 0.0
	_province_heap_push(heap, Vector3(0.0, start_index, 0.0))
	var offsets := [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	]
	while not heap.is_empty():
		var entry: Vector3 = _province_heap_pop(heap)
		var current_index := int(entry.y)
		var current_cost := float(entry.z)
		if current_cost > distance[current_index] + 0.000001:
			continue
		if current_index == goal_index:
			break
		var current := Vector2i(
			current_index % size.x, current_index / size.x
		)
		for offset_value in offsets:
			var offset: Vector2i = offset_value
			var next: Vector2i = current + offset
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var next_index: int = next.y * size.x + next.x
			var owner := int(province_ids[next_index])
			if owner not in [province_a, province_b]:
				continue
			if blocked_edges.has(Hydrology.edge_key(current_index, next_index, size.x * size.y)): continue
			if not route_heights.is_empty() and (route_heights[next_index] < 0 or absf(route_heights[current_index] - route_heights[next_index]) > float(routing_options.get("maximum_height", ROAD_MAXIMUM_HEIGHT_DIFFERENCE))): continue
			var candidate := current_cost + 1.0
			if routing_options.get("pixel_fallback", false):
				var step_length := float(routing_options.get("aspect", 1.0)) * size.y / size.x if offset.x != 0 else 1.0
				var relief_cost := 1.0 + 7.0 * absf(route_heights[current_index] - route_heights[next_index])
				candidate = current_cost + step_length * relief_cost
			if (
				candidate < distance[next_index] - 0.000001
				or (
					is_equal_approx(candidate, distance[next_index])
					and current_index < previous[next_index]
				)
			):
				distance[next_index] = candidate
				previous[next_index] = current_index
				var heuristic := Vector2(next).distance_to(Vector2(goal))
				if routing_options.get("strict",false): heuristic = absf(next.x-goal.x)+absf(next.y-goal.y)
				if routing_options.get("pixel_fallback", false): heuristic = absf(next.x-goal.x) * float(routing_options.get("aspect", 1.0)) * size.y / size.x + absf(next.y-goal.y)
				_province_heap_push(
					heap, Vector3(candidate + heuristic, next_index, candidate)
				)
	if start_index != goal_index and previous[goal_index] < 0:
		if routing_options.get("allow_terrain_connector", false):
			var fallback := routing_options.duplicate()
			fallback.merge({"allow_terrain_connector": false, "terrain_connector_fallback": true, "maximum_height": 1.0}, true)
			return _coarse_province_pair_path(province_ids, size, from, to, province_a, province_b, blocked_edges, fallback)
		return empty
	var raster_points: Array[Vector2i] = []
	var cursor := goal_index
	while cursor >= 0:
		raster_points.append(Vector2i(cursor % size.x, cursor / size.x))
		if cursor == start_index:
			break
		cursor = previous[cursor]
	if raster_points.is_empty() or raster_points[-1] != start:
		return empty
	raster_points.reverse()
	var raw := PackedVector2Array([from])
	for raster_point in raster_points:
		if not representatives.is_empty():
			raw.append(representatives[raster_point.y * size.x + raster_point.x])
			continue
		raw.append(
			(Vector2(raster_point) + Vector2(0.5, 0.5))
				/ Vector2(size)
		)
	raw.append(to)
	if routing_options.get("terrain_connector_fallback", false):
		var low := INF
		var high := -INF
		for cell in raster_points:
			var h := route_heights[cell.y * size.x + cell.x]
			low = minf(low, h)
			high = maxf(high, h)
		routing_options = routing_options.duplicate()
		routing_options["maximum_height"] = maxf(ROAD_MAXIMUM_HEIGHT_DIFFERENCE, high - low + 0.000001)
	if not blocked_edges.is_empty() and not routing_options.get("strict", false): return raw
	var result := PackedVector2Array([raw[0]])
	var anchor := 0
	while anchor < raw.size() - 1:
		var next_anchor := -1 if routing_options.get("strict", false) else anchor + 1
		if routing_options.get("pixel_fallback", false):
			next_anchor = _furthest_checked_shortcut(raw, anchor, province_ids, size, province_a, province_b, routing_options)
		for candidate_index in [] if routing_options.get("pixel_fallback", false) else range(raw.size() - 1, anchor, -1):
			if routing_options.get("strict", false) and not _safe_road_shortcut(raw[anchor], raw[candidate_index], routing_options): continue
			if routing_options.get("strict", false):
				if not _segment_in_pair_exact(province_ids,size,raw[anchor],raw[candidate_index],province_a,province_b): continue
			if province_segment_stays_in_pair(
				province_ids, size, raw[anchor], raw[candidate_index],
				province_a, province_b
			):
				next_anchor = candidate_index
				break
		if next_anchor <= anchor:
			if routing_options.get("pixel_fallback", false):
				# Repair the obstructed short section, preserving the already
				# legal coarse corridor instead of searching both provinces anew.
				for target in range(anchor + 1, mini(raw.size(), anchor + 5)):
					var repaired := PixelRoute.find(province_ids, size, raw[anchor], raw[target], province_a, province_b, routing_options)
					if repaired.size() < 2: continue
					for i in range(1, repaired.size()): result.append(repaired[i])
					next_anchor = target
					break
				if next_anchor > anchor:
					anchor = next_anchor
					continue
			return empty
		result.append(raw[next_anchor])
		anchor = next_anchor
	return result

static func _furthest_checked_shortcut(path: PackedVector2Array, anchor: int, ids: PackedInt32Array, size: Vector2i, a: int, b: int, options: Dictionary) -> int:
	var last := path.size() - 1
	if _segment_in_pair_exact(ids, size, path[anchor], path[last], a, b) and _safe_road_shortcut(path[anchor], path[last], options): return last
	var best := -1
	var step := 1
	while anchor + step < last:
		var next := anchor + step
		if not _segment_in_pair_exact(ids, size, path[anchor], path[next], a, b) or not _safe_road_shortcut(path[anchor], path[next], options): break
		best = next
		step *= 2
	if best < 0: return best
	var low := best + 1
	var high := mini(anchor + step - 1, last - 1)
	while low <= high:
		var middle := (low + high) / 2
		if _segment_in_pair_exact(ids, size, path[anchor], path[middle], a, b) and _safe_road_shortcut(path[anchor], path[middle], options): best = middle; low = middle + 1
		else: high = middle - 1
	return best

static func _segment_in_pair_exact(ids: PackedInt32Array, size: Vector2i, from: Vector2, to: Vector2, a: int, b: int) -> bool:
	for cell in _segment_grid_cells(from,to,size):
		if ids[cell.y*size.x+cell.x] not in [a,b]: return false
	return true

static func _safe_road_shortcut(from: Vector2, to: Vector2, options: Dictionary) -> bool:
	# Routing options are local to one immutable terrain/network build. Fine
	# coastal searches query thousands of edges; do not copy the entire river
	# array for every edge.
	if not options.has("typed_rivers"):
		var typed: Array[PackedVector2Array] = []
		typed.assign(options.get("river_paths", []))
		options["typed_rivers"] = typed
	var rivers: Array[PackedVector2Array] = options.typed_rivers
	if not options.has("river_signature"): options["river_signature"] = hash(rivers)
	var no_positions: Array[Vector2] = []
	if _road_dictionary_crosses_rivers({"map_path": PackedVector2Array([from, to])}, no_positions, rivers, int(options.river_signature)): return false
	var image: Image = options.get("image")
	if image == null: return false
	var low := INF
	var high := -INF
	for p in _segment_grid_cells(from, to, image.get_size()):
		var color := image.get_pixelv(p)
		if not packed_is_land(color): return false
		var h := packed_altitude(color)
		low = minf(low, h)
		high = maxf(high, h)
		if high - low > float(options.get("maximum_height", ROAD_MAXIMUM_HEIGHT_DIFFERENCE)): return false
	return true

static func _segment_grid_cells(from: Vector2, to: Vector2, size: Vector2i) -> Array[Vector2i]:
	var a := from * Vector2(size)
	var b := to * Vector2(size)
	var p := Vector2i(a.floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var end := Vector2i(b.floor()).clamp(Vector2i.ZERO, size - Vector2i.ONE)
	var result: Array[Vector2i] = [p]
	var delta := b - a
	var step := Vector2i(int(signf(delta.x)), int(signf(delta.y)))
	var tx := ((p.x + (1 if step.x > 0 else 0)) - a.x) / delta.x if step.x != 0 else INF
	var ty := ((p.y + (1 if step.y > 0 else 0)) - a.y) / delta.y if step.y != 0 else INF
	var dx := absf(1.0 / delta.x) if step.x != 0 else INF
	var dy := absf(1.0 / delta.y) if step.y != 0 else INF
	while p != end and result.size() <= size.x + size.y + 2:
		if absf(tx-ty) < 1e-9:
			p += step
			tx += dx
			ty += dy
		elif tx < ty:
			p.x += step.x
			tx += dx
		else:
			p.y += step.y
			ty += dy
		if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y: break
		result.append(p)
	return result


## Regular arc targets first; add and prune only connectivity supplements.
static func _build_spaced_ferries(image: Image, provinces: Dictionary, positions: Array[Vector2], base_roads: Array[Dictionary], river_input: Dictionary, candidates: Array, city_count: int, aspect: float, interval: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var maximum := int(river_input.get("ferry_max_per_river",0))
	var selection := FerrySpacing.select(candidates, river_input.features, aspect, interval, RIVER_DOCK_MIN_SPACING, maximum)
	var regular: Array[Dictionary] = []
	for point in selection.selected:
		var dock := _boundary_dock_record(image,int(point.river_id),point,city_count+regular.size())
		dock.merge({"ferry_reason":"interval","ferry_arc":point.ferry_arc,"ferry_slot":point.ferry_slot,"ferry_river":point.ferry_river},true)
		regular.append(dock)
	var roads: Array[Dictionary] = []
	for road in base_roads:
		if int(road.get("kind",Edge.Kind.LAND)) == Edge.Kind.LAND:
			if river_input.river_pair_keys.has(_pair_key(int(road.a),int(road.b))) or _road_dictionary_crosses_rivers(road,positions,river_input.paths): continue
		roads.append(road)
	var required := _mainland_city_ids(image,positions)
	var links := _ferry_city_links(roads,regular,river_input,aspect)
	var eligible: Array[Dictionary] = []
	for point in selection.candidates:
		var too_close := false
		for dock in regular:
			if metric_length_between(point.position,dock.position,aspect)<RIVER_DOCK_MIN_SPACING: too_close=true; break
		if not too_close: eligible.append(point)
	var spacing_check := func(point: Dictionary, chosen: Array) -> bool:
		for other in chosen:
			if metric_length_between(point.position,other.position,aspect)<RIVER_DOCK_MIN_SPACING: return false
		return true
	var extra_points := FerrySpacing.connect_components(eligible,city_count,links,regular,required,spacing_check,maximum)
	var extras: Array[Dictionary] = []
	for point in extra_points:
		var dock := _boundary_dock_record(image,int(point.river_id),point,city_count+regular.size()+extras.size())
		dock["ferry_reason"] = "connectivity"
		dock["ferry_river"] = point.ferry_river
		extras.append(dock)
	var docks: Array[Dictionary] = regular.duplicate()
	docks.append_array(extras)
	# New ports may add river navigation as well as a crossing. Remove any
	# supplement that can now be deleted without breaking mainland traffic.
	var pruned := 0
	if _ferry_mainland_connected(roads,docks,river_input,aspect,city_count,required):
		for i in range(docks.size()-1,regular.size()-1,-1):
			var trial: Array[Dictionary] = docks.duplicate()
			trial.remove_at(i)
			if _ferry_mainland_connected(roads,trial,river_input,aspect,city_count,required): docks=trial; pruned+=1
	for i in range(docks.size()): docks[i]["city_id"] = city_count+i
	var river_counts := {}
	for dock in docks: river_counts[dock.ferry_river]=int(river_counts.get(dock.ferry_river,0))+1
	var diagnostics := {"model":FerrySpacing.VERSION,"interval":interval,"regular":regular.size(),"necessary":docks.size()-regular.size(),"pruned_redundant":pruned,"total":docks.size(),"legal_candidates":candidates.size(),"candidate_intervals":selection.candidate_intervals,"total_intervals":selection.total_intervals,"intervals_without_legal_candidate":selection.intervals_without_legal_candidate,"main_river_length":selection.main_river_length,"spacing_rejections":selection.spacing_rejections,"elapsed_usec":Time.get_ticks_usec()-started}
	diagnostics.merge({"maximum_per_river":maximum,"river_counts":river_counts},true)
	print("FERRY_SPACING ",JSON.stringify(diagnostics))
	return {"docks":docks,"diagnostics":diagnostics}

static func _mainland_city_ids(image: Image, positions: Array[Vector2]) -> Array[int]:
	var components := Hydrology.components(_all_land_geometry(image).mask,image.get_size(),{})
	var areas := {}; var largest := 0; var mainland := -1
	for component in components:
		if component<0: continue
		areas[component] = int(areas.get(component,0))+1
		if areas[component]>largest: largest=areas[component]; mainland=component
	var result: Array[int] = []
	for i in range(positions.size()):
		var p := Vector2i(positions[i]*Vector2(image.get_size())).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)
		if components[p.y*image.get_width()+p.x]==mainland: result.append(i)
	return result

static func _ferry_city_links(roads: Array[Dictionary], docks: Array[Dictionary], river_input: Dictionary, aspect: float) -> Array[Vector2i]:
	var links: Array[Vector2i] = []
	for road in roads: links.append(Vector2i(int(road.a),int(road.b)))
	var banks := {}
	for dock in docks:
		links.append(Vector2i(int(dock.bank_a),int(dock.bank_b)))
		banks[int(dock.city_id)] = int(dock.bank_a)
	for boat in HydroTransport.build(river_input.features,docks,river_input.navigation_image,aspect,bool(river_input.local_navigation)):
		links.append(Vector2i(banks[int(boat.a)],banks[int(boat.b)]))
	return links

static func _ferry_mainland_connected(roads: Array[Dictionary], docks: Array[Dictionary], river_input: Dictionary, aspect: float, city_count: int, required: Array[int]) -> bool:
	var parent: Array[int] = []
	for i in range(city_count): parent.append(i)
	for pair in _ferry_city_links(roads,docks,river_input,aspect): parent[_root(parent,pair.x)] = _root(parent,pair.y)
	var root := -1
	for id in required:
		var current := _root(parent,id)
		if root<0: root=current
		elif root!=current: return false
	return true

## 码头连接两岸城市；河界省份对删除直接 LAND，杜绝绕过抢滩。
static func _build_boundary_river_transport(
	image: Image,
	samples: Dictionary,
	base_roads: Array[Dictionary],
	provinces: Dictionary,
	boundary_rivers: Dictionary,
	city_count: int,
	map_aspect_ratio: float,
	initial_nation_count: int,
	fixed_docks: Array = [],
	preserve_docks: bool = false
) -> Dictionary:
	var positions: Array[Vector2] = samples["positions"]
	var rivers: Array[Dictionary] = boundary_rivers["rivers"]
	var graph: Dictionary = boundary_rivers["graph"]
	var graph_segments: Array[Dictionary] = graph["segments"]
	var occupied_positions: Array[Vector2] = positions.duplicate()
	var ferry_interval := float(boundary_rivers.get("ferry_interval", 0.0))
	var spaced_ferries := ferry_interval > 0.0 and not preserve_docks
	var ferry_diagnostics := {}
	var docks: Array[Dictionary] = []
	var river_groups := {}
	var lowland_dock_regions: Array[Dictionary] = []
	var dock_bank_regions: Array[Dictionary] = []
	var all_dock_candidates: Array[Dictionary] = []
	var dock_diagnostics: Array[Dictionary] = []
	var initial_owners := _initial_nation_owner_by_position(
		positions, initial_nation_count
	)
	if not preserve_docks and not spaced_ferries:
		for reserved in boundary_rivers.get("reserved_docks", []):
			var size: Vector2i = provinces.size
			var a := int(provinces.ids[reserved.cell_a.y * size.x + reserved.cell_a.x])
			var b := int(provinces.ids[reserved.cell_b.y * size.x + reserved.cell_b.x])
			if a < 0 or b < 0 or a == b: continue
			var point: Dictionary = reserved.duplicate(true)
			point.merge({"bank_a": a, "bank_b": b, "reference_bank": a, "lowland": true}, true)
			if boundary_rivers.get("full_network", false):
				point.merge({"coverage": "reserved:%s" % point.position, "reach_fraction": 0.5, "reserved": true, "city_clearance": _minimum_metric_position_distance(point.position, positions, map_aspect_ratio)}, true)
				all_dock_candidates.append(point)
				continue
			var dock := _boundary_dock_record(image, point.river_id, point, city_count + docks.size())
			docks.append(dock)
			occupied_positions.append(dock.position)
	for river in rivers:
		var river_id := int(river["river_id"])
		if boundary_rivers.get("full_network", false) or spaced_ferries: river["collect_only"] = true
		if preserve_docks:
			river_groups[river_id] = []
			for dock in fixed_docks:
				if int(dock.river_id) == river_id: river_groups[river_id].append(dock)
			continue
		var selection := _select_boundary_river_docks(
			image, river, graph_segments, positions, occupied_positions,
			city_count + docks.size(), map_aspect_ratio, initial_owners
		)
		var river_docks: Array = selection["docks"]
		dock_diagnostics.append({"river_id":river_id,"selected":river_docks.size(),"candidates":selection.candidates.size(),"rejected":selection.get("rejected",{})})
		for candidate_value in selection["candidates"]:
			all_dock_candidates.append(
				(candidate_value as Dictionary).duplicate(true)
			)
		for candidate_value in selection["lowland_regions"]:
			lowland_dock_regions.append(
				(candidate_value as Dictionary).duplicate(true)
			)
		for candidate_value in selection["bank_regions"]:
			dock_bank_regions.append(
				(candidate_value as Dictionary).duplicate(true)
			)
		for dock in river_docks:
			dock["city_id"] = city_count + docks.size()
			docks.append(dock)
		river_groups[river_id] = []
		for dock in docks:
			if int(dock.river_id) == river_id: river_groups[river_id].append(dock)

	if spaced_ferries:
		var sparse := _build_spaced_ferries(image, provinces, positions, base_roads, boundary_rivers, all_dock_candidates, city_count, map_aspect_ratio, ferry_interval)
		docks.assign(sparse.docks)
		ferry_diagnostics = sparse.diagnostics
		for dock in docks:
			river_groups[int(dock.river_id)].append(dock)
			dock_bank_regions.append(dock)
			if dock.lowland: lowland_dock_regions.append(dock)
		for entry in dock_diagnostics:
			entry.selected = river_groups[int(entry.river_id)].size()
	elif boundary_rivers.get("full_network", false) and not preserve_docks:
		var selection := _select_full_river_docks(image, {"provinces": provinces, "features": boundary_rivers.features}, all_dock_candidates, occupied_positions, positions, city_count + docks.size(), map_aspect_ratio, {})
		var bands := {"upstream": {"candidates": 0, "docks": 0}, "middle": {"candidates": 0, "docks": 0}, "downstream": {"candidates": 0, "docks": 0}}
		for sample in boundary_rivers.all_samples:
			bands[_dock_reach_band(sample.reach_fraction)].candidates += 1
		for dock in selection.docks:
			docks.append(dock)
			river_groups[int(dock.river_id)].append(dock)
			bands[_dock_reach_band(dock.get("reach_fraction", 0.5))].docks += 1
		dock_diagnostics.append({"model": DockSampling.VERSION, "bands": bands, "coverage": selection.coverage, "rejected": selection.rejected, "sample_rejections": boundary_rivers.get("sample_rejections", [])})
	var river_pair_keys: Dictionary = boundary_rivers["river_pair_keys"]
	var normalized_river_paths: Array[PackedVector2Array] = boundary_rivers["paths"]
	if preserve_docks: docks.assign(fixed_docks)
	elif not spaced_ferries and not boundary_rivers.get("full_network", false): _append_isolated_city_docks(
		image, base_roads, positions, normalized_river_paths,
		river_pair_keys, all_dock_candidates, river_groups, docks,
		occupied_positions, city_count, map_aspect_ratio,
		dock_bank_regions, lowland_dock_regions
	)
	var roads: Array[Dictionary] = []
	for road in base_roads:
		var kind := int(road.get("kind", Edge.Kind.LAND))
		var pair_key := _pair_key(int(road["a"]), int(road["b"]))
		if kind == Edge.Kind.LAND:
			if river_pair_keys.has(pair_key):
				continue
			if _road_dictionary_crosses_rivers(
				road, positions, normalized_river_paths
			):
				continue
		roads.append(road.duplicate(true))

	var city_positions := positions.duplicate()
	var landing_barriers := Hydrology.barriers(boundary_rivers.features, provinces.size) if boundary_rivers.get("hydrological", false) else {}
	for dock in docks:
		city_positions.append(dock["position"])
		var dock_city := int(dock["city_id"])
		for bank_suffix in ["a", "b"]:
			var bank_city := int(dock["bank_" + bank_suffix])
			var bank_cell: Vector2i = dock["cell_" + bank_suffix]
			var map_path: PackedVector2Array = dock["path_" + bank_suffix] if dock.has("path_" + bank_suffix) else _province_to_boundary_dock_path(
				provinces, positions[bank_city], bank_city,
				bank_cell, dock["position"], landing_barriers
			)
			if map_path.size() < 2:
				return {"ok":false,"error":"码头 %d 无法在本省内连接岸侧城市 %d；当前世界已保留。" % [dock_city,bank_city]}
			var metric_length := metric_polyline_length(
				map_path, map_aspect_ratio
			)
			roads.append({
				"a": bank_city,
				"b": dock_city,
				"map_path": map_path,
				"length": metric_length,
				"distance": distance_units_for_metric_length(metric_length),
				"height_difference": absf(
					float(samples["heights"][bank_city])
						- float(dock["height"])
				),
				"land_ratio": 1.0,
				"cost": metric_length,
				"backbone": true,
				"max_manpower": Edge.TERRAIN_LOW_MANPOWER,
				"base_max_manpower": Edge.TERRAIN_LOW_MANPOWER,
				"danger": LANDING_DANGER_MIN,
				"kind": Edge.Kind.LANDING,
				"travel_time_multiplier": 1.0,
				"supply_loss_multiplier": 1.0,
				"allows_holding": true,
			})

	var active_paths: Array[PackedVector2Array] = []
	for river in rivers:
		var river_id := int(river["river_id"])
		var path: PackedVector2Array = river["path"]
		active_paths.append(path.duplicate())
		var group: Array = river_groups[river_id]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["river_progress"]) < float(b["river_progress"])
		)
		for dock_index in range(group.size() - 1):
			var from_dock: Dictionary = group[dock_index]
			var to_dock: Dictionary = group[dock_index + 1]
			var map_path := _river_path_between_docks(
				path, from_dock["position"], to_dock["position"],
				float(from_dock["river_progress"]),
				float(to_dock["river_progress"])
			)
			var metric_length := metric_polyline_length(
				map_path, map_aspect_ratio
			)
			var height_difference := absf(
				float(from_dock["height"]) - float(to_dock["height"])
			)
			if not river_link_is_navigable(height_difference):
				continue
			roads.append({
				"a": int(from_dock["city_id"]),
				"b": int(to_dock["city_id"]),
				"map_path": map_path,
				"length": metric_length,
				"distance": distance_units_for_metric_length(metric_length),
				"height_difference": height_difference,
				"land_ratio": 1.0,
				"cost": metric_length,
				"backbone": true,
				"max_manpower": Edge.WATER_MANPOWER,
				"base_max_manpower": Edge.WATER_MANPOWER,
				"danger": _boundary_river_link_danger(
					map_path, height_difference, river_id, dock_index
				),
				"kind": Edge.Kind.RIVER,
				"travel_time_multiplier": RIVER_TRAVEL_TIME_MULTIPLIER,
				"supply_loss_multiplier": RIVER_SUPPLY_LOSS_MULTIPLIER,
				"allows_holding": false,
			})
	return {
		"roads": roads,
		"docks": docks,
		"river_paths": active_paths,
		"lowland_dock_regions": lowland_dock_regions,
		"dock_bank_regions": dock_bank_regions,
		"dock_diagnostics": dock_diagnostics,
		"ferry_spacing": ferry_diagnostics,
	}

## Transaction preparation only. Existing dock IDs/positions remain stable;
## an edit that invalidates their banks is rejected before touching live state.
static func rebuild_hydrological_map(source_path: String, positions: Array[Vector2], features: Array, old_docks: Array, source_manifest: String, nation_count: int) -> Dictionary:
	if MapSource.environment_only_rivers(source_manifest):
		features = []
		old_docks = []
	var source := (load(source_path) as Texture2D).get_image()
	var image: Image = source.duplicate()
	var strict := not MapSource.environment_only_rivers(source_manifest) and MapSource.strict_river_transport(source_manifest)
	var full_network := not MapSource.environment_only_rivers(source_manifest) and MapSource.full_river_transport(source_manifest)
	image.resize(ANALYSIS_WIDTH, ANALYSIS_WIDTH, Image.INTERPOLATE_NEAREST)
	var size := image.get_size()
	var mask: PackedByteArray = _all_land_geometry(image).mask
	var pixels: Array[Vector2i] = []
	var heights: Array[float] = []
	var reliefs: Array[float] = []
	var occupied := {}
	for position in positions:
		var pixel := Vector2i(position * Vector2(size)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		if occupied.has(pixel) or mask[pixel.y * size.x + pixel.x] == 0:
			return {"ok": false, "error": "城市必须位于独立的陆地种子格。"}
		occupied[pixel] = true
		pixels.append(pixel)
		heights.append(packed_altitude(image.get_pixelv(pixel)))
		reliefs.append(_local_relief(image, pixel.x, pixel.y, RELIEF_RADIUS))
	var blocked := Hydrology.barriers(features, size)
	var empty_paths: Array[Array] = []
	var aspect := MapSource.aspect_ratio(source_manifest)
	var constraints := BankConstraints.build(features, size, aspect) if strict else {}
	if full_network: constraints["whole_branch_transfer"] = true
	var province_mask := _atlas_land_domain(source,size) if MapSource.atlas_roads(source_manifest) else mask
	var provinces := _build_province_raster(image, province_mask, Rect2i(Vector2i.ZERO, size), pixels, empty_paths, projected_pixel_aspect(image, source_manifest), true, blocked, constraints)
	if provinces.get("ok", true) == false: return provinces
	if full_network:
		provinces.ids = BankConstraints.complete_conflicts(provinces.ids, mask, size, pixels, blocked, constraints)
		var missing := ShoreRepair.gaps(provinces.ids, mask, Hydrology.components(mask, size, blocked), pixels, size)
		if not missing.is_empty():
			# Editing a city must not silently relocate other cities to repair
			# its shores. The caller replaces the live world only on success.
			return {"ok": false, "error": "移动后有 %d 个有城市岸区格无法合法分配；当前世界已保留。" % missing.size()}
	provinces["routing_options"] = {"strict":true,"allow_terrain_connector":true,"image":source if full_network else image,"aspect":aspect,"river_paths":MapFeatureContract.major_paths(features)} if strict else {}
	if full_network:
		provinces["physical_components"] = LandComponents.build(source)
		provinces.routing_options["pixel_fallback"] = true
	var river_input := _hydrology_transport_input(provinces, features, strict, aspect, full_network)
	river_input["ferry_interval"] = MapSource.ferry_interval(source_manifest)
	river_input["ferry_max_per_river"] = MapSource.ferry_max_per_river(source_manifest)
	var fixed: Array[Dictionary] = []
	for old in old_docks:
		if _minimum_metric_position_distance(old.position, positions, aspect) < minimum_dock_city_spacing_for_count(positions.size()):
			return {"ok": false, "error": "移动位置离既有码头过近。"}
		var matched := false
		for river in river_input.rivers:
			for sample in river.dock_samples:
				var i := int(sample.path_index)
				if not (river.path[i] as Vector2).lerp(river.path[i + 1], float(sample.ratio)).is_equal_approx(old.position): continue
				var index := int(sample.graph_index)
				if index < 0: return {"ok": false, "error": "移动后既有码头失去合法的双岸省份。"}
				var segment: Dictionary = river_input.graph.segments[index]
				fixed.append(_boundary_dock_record(image, int(river.river_id), {"position": old.position, "river_progress": float(i) + float(sample.ratio), "bank_a": segment.a, "bank_b": segment.b, "cell_a": segment.cell_a, "cell_b": segment.cell_b}, int(old.city_id)))
				matched = true
				break
			if matched: break
		if not matched: return {"ok": false, "error": "既有码头未落在主河段。"}
	var samples := {"positions": positions, "pixels": pixels, "heights": heights, "reliefs": reliefs}
	if MapSource.atlas_roads(source_manifest):
		var latitudes := PackedFloat32Array()
		for row in range(size.y): latitudes.append(MapSource.latitude_at_y((row + 0.5) / size.y, float(MapSource.load_manifest(source_manifest).bbox_wgs84[1]), float(MapSource.load_manifest(source_manifest).bbox_wgs84[3]), source_manifest))
		var environment := EnvironmentModel.build(source, image, mask, latitudes, aspect, MapSource.projection_type(source_manifest), true, MapSource.hydrology_network(source_manifest), MapSource.estimated_boundary_inflow(source_manifest), MapSource.river_settlement_model(source_manifest))
		var scores := PackedFloat32Array()
		for pixel in pixels: scores.append(environment.suitability[pixel.y * size.x + pixel.x])
		var atlas_result: Dictionary = load("res://scripts/core/atlas_road_network.gd").build(source, image, samples, provinces, aspect, scores)
		if not atlas_result.get("ok", false): return atlas_result
		return {"ok": true, "provinces": provinces, "roads": atlas_result.roads}
	var road_result := _build_roads(image, mask, samples, aspect, provinces, river_input.pixel_paths, blocked)
	_attach_province_land_paths(road_result.roads, provinces, positions, positions.size(), aspect, blocked)
	var transport := _build_boundary_river_transport(image, samples, road_result.roads, provinces, river_input, positions.size(), aspect, nation_count, fixed, true)
	if not transport.get("ok",true): return transport
	var roads: Array[Dictionary] = []
	for road in transport.roads:
		if int(road.get("kind", Edge.Kind.LAND)) != Edge.Kind.RIVER: roads.append(road)
	roads.append_array(HydroTransport.build(features, fixed, source if strict else image, aspect, strict))
	transport.roads = roads
	if MapSource.road_path_model(source_manifest) == MapSource.VISIBILITY_ROAD_PATH:
		_simplify_generated_land_roads(roads, provinces, source, features, aspect)
	if not _hydrology_transport_valid(transport, positions, image, mask, {"features": features}):
		return {"ok": false, "error": "移动后主河交通无法合法连接；当前世界已保留。"}
	return {"ok": true, "provinces": provinces, "roads": roads}


## 河流会删除所有未经码头的跨岸 LAND。若某座陆城因此失去全部交通边，
## 在最近的对应河界候选点补一个渡口；不能为了连通性恢复跨河陆路。
static func _append_isolated_city_docks(
	image: Image,
	base_roads: Array[Dictionary],
	land_positions: Array[Vector2],
	river_paths: Array[PackedVector2Array],
	river_pair_keys: Dictionary,
	all_candidates: Array[Dictionary],
	river_groups: Dictionary,
	docks: Array[Dictionary],
	occupied_positions: Array[Vector2],
	city_count: int,
	map_aspect_ratio: float,
	bank_regions: Array[Dictionary],
	lowland_regions: Array[Dictionary]
) -> void:
	var degree := PackedInt32Array()
	degree.resize(city_count)
	for road in base_roads:
		var a := int(road["a"])
		var b := int(road["b"])
		if a < 0 or b < 0 or a >= city_count or b >= city_count:
			continue
		var kind := int(road.get("kind", Edge.Kind.LAND))
		var removed_by_river := (
			kind == Edge.Kind.LAND
			and (
				river_pair_keys.has(_pair_key(a, b))
				or _road_dictionary_crosses_rivers(
					road, land_positions, river_paths
				)
			)
		)
		if not removed_by_river:
			degree[a] += 1
			degree[b] += 1
	for dock in docks:
		for bank_key in ["bank_a", "bank_b"]:
			var bank_id := int(dock[bank_key])
			if bank_id >= 0 and bank_id < city_count:
				degree[bank_id] += 1
	for city_id in range(city_count):
		if degree[city_id] > 0:
			continue
		var best: Dictionary = {}
		var best_distance := INF
		for candidate in all_candidates:
			if city_id not in [
				int(candidate["bank_a"]), int(candidate["bank_b"]),
			]:
				continue
			var distance := metric_length_between(
				land_positions[city_id],
				candidate["position"],
				map_aspect_ratio
			)
			if (
				distance < best_distance - 0.000001
				or (
					is_equal_approx(distance, best_distance)
					and float(candidate["river_progress"])
						< float(best.get("river_progress", INF))
				)
			):
				best = candidate
				best_distance = distance
		if best.is_empty():
			continue
		var river_id := int(best["river_id"])
		var dock := _boundary_dock_record(
			image, river_id, best, city_count + docks.size()
		)
		docks.append(dock)
		if not river_groups.has(river_id):
			river_groups[river_id] = [] as Array[Dictionary]
		(river_groups[river_id] as Array).append(dock)
		occupied_positions.append(dock["position"] as Vector2)
		bank_regions.append(best.duplicate(true))
		if bool(best.get("lowland", false)):
			lowland_regions.append(best.duplicate(true))
		for bank_key in ["bank_a", "bank_b"]:
			var bank_id := int(dock[bank_key])
			if bank_id >= 0 and bank_id < city_count:
				degree[bank_id] += 1


static func _road_dictionary_crosses_rivers(
	road: Dictionary,
	city_positions: Array[Vector2],
	river_paths: Array[PackedVector2Array],
	known_signature: int = -1
) -> bool:
	var signature := hash(river_paths) if known_signature == -1 else known_signature
	if not _crossing_indexes.has(signature):
		var buckets := {}
		for path in river_paths:
			for k in range(path.size() - 1):
				var first := Vector2i((path[k].min(path[k + 1]) * 32.0).floor())
				var last := Vector2i((path[k].max(path[k + 1]) * 32.0).floor())
				var segment := PackedVector2Array([path[k], path[k + 1]])
				for y in range(first.y, last.y + 1):
					for x in range(first.x, last.x + 1):
						var key := Vector2i(x, y)
						if not buckets.has(key): buckets[key] = []
						buckets[key].append(segment)
		if _crossing_indexes.size() >= 4: _crossing_indexes.erase(_crossing_indexes.keys()[0])
		_crossing_indexes[signature] = buckets
	var buckets: Dictionary = _crossing_indexes[signature]
	var road_path: PackedVector2Array = road.get(
		"map_path", PackedVector2Array()
	)
	if road_path.size() < 2:
		if not road.has("a") or not road.has("b") or int(road.a) >= city_positions.size() or int(road.b) >= city_positions.size(): return true
		road_path = PackedVector2Array([
			city_positions[int(road["a"])],
			city_positions[int(road["b"])],
		])
	for road_index in range(road_path.size() - 1):
		var road_from := road_path[road_index]
		var road_to := road_path[road_index + 1]
		var road_delta := road_to - road_from
		var length_squared := road_delta.length_squared()
		if length_squared <= 0.000000000001:
			continue
		var first := Vector2i((road_from.min(road_to) * 32.0).floor())
		var last := Vector2i((road_from.max(road_to) * 32.0).floor())
		var nearby: Array = []
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1): nearby.append_array(buckets.get(Vector2i(x, y), []))
		for river_path in nearby:
			for river_index in range(1):
				var hit = Geometry2D.segment_intersects_segment(
					road_from, road_to,
					river_path[river_index], river_path[river_index + 1]
				)
				if hit == null:
					continue
				var t := (
					(Vector2(hit) - road_from).dot(road_delta)
						/ length_squared
				)
				if t > RIVER_CROSSING_ENDPOINT_EPS and t < 1.0 - RIVER_CROSSING_ENDPOINT_EPS:
					return true
	return false


static func _select_boundary_river_docks(
	image: Image,
	river: Dictionary,
	graph_segments: Array[Dictionary],
	land_positions: Array[Vector2],
	occupied_positions: Array[Vector2],
	first_city_id: int,
	map_aspect_ratio: float,
	initial_owners: Array[int]
) -> Dictionary:
	var path: PackedVector2Array = river["path"]
	var edge_indices: Array = river["edge_indices"]
	var candidates: Array[Dictionary] = []
	var minimum_city_clearance := minimum_dock_city_spacing_for_count(land_positions.size())
	var rejected := {"altitude":0,"city_clearance":0,"dock_spacing":0}
	var dock_samples: Array = river.get("dock_samples", [])
	var cumulative := PackedFloat64Array([0.0])
	for i in range(path.size() - 1): cumulative.append(cumulative[-1] + metric_length_between(path[i], path[i + 1], map_aspect_ratio))
	if not river.has("dock_samples"):
		for i in range(path.size() - 1):
			if int(edge_indices[i]) >= 0: dock_samples.append({"path_index": i, "ratio": 0.5, "graph_index": int(edge_indices[i])})
	for sample in dock_samples:
		var path_index := int(sample.path_index)
		var position := path[path_index].lerp(path[path_index + 1], float(sample.ratio))
		var pixel := Vector2i(
			clampi(
				int(floor(position.x * image.get_width())),
				0, image.get_width() - 1
			),
			clampi(
				int(floor(position.y * image.get_height())),
				0, image.get_height() - 1
			)
		)
		var altitude := packed_altitude(image.get_pixelv(pixel))
		if bool(river.get("hydrological", false)) and not bool(river.get("strict_transport", false)) and altitude > RIVER_DOCK_LOWLAND_ALTITUDE:
			rejected.altitude += 1
			continue
		var city_clearance := _minimum_metric_position_distance(
			position, land_positions, map_aspect_ratio
		)
		if city_clearance < minimum_city_clearance:
			rejected.city_clearance += 1
			continue
		var graph_segment: Dictionary = graph_segments[
			int(sample.graph_index)
		]
		var cell_a_position := Vector2(
			graph_segment["cell_a"] as Vector2i
		) + Vector2(0.5, 0.5)
		cell_a_position /= Vector2(image.get_size())
		var path_direction := path[path_index + 1] - path[path_index]
		var bank_a_is_reference := (
			path_direction.cross(cell_a_position - position) <= 0.0
		)
		var arc := cumulative[path_index] + float(sample.ratio) * (cumulative[path_index + 1] - cumulative[path_index])
		candidates.append({
			"coverage": sample.get("coverage", "%s:%d" % [path[0], int(floor(arc / DockSampling.COVERAGE))]),
			"reach_fraction": sample.get("reach_fraction", 0.5),
			"river_id": int(river["river_id"]),
			"river_progress": float(path_index) + float(sample.ratio),
			"position": position,
			"pixel_position": Vector2(
				position.x * float(image.get_width()) - 0.5,
				position.y * float(image.get_height()) - 0.5
			),
			"height": altitude,
			"relief": _local_relief(
				image, pixel.x, pixel.y, RELIEF_RADIUS
			),
			"bank_a": int(graph_segment["a"]),
			"bank_b": int(graph_segment["b"]),
			"reference_bank": int(
				graph_segment["a"]
				if bank_a_is_reference
				else graph_segment["b"]
			),
			"cell_a": graph_segment["cell_a"],
			"cell_b": graph_segment["cell_b"],
			"city_clearance": city_clearance,
			"lowland": altitude <= RIVER_DOCK_LOWLAND_ALTITUDE,
			"same_initial_nation": (
				int(graph_segment["a"]) < initial_owners.size()
				and int(graph_segment["b"]) < initial_owners.size()
				and initial_owners[int(graph_segment["a"])]
					== initial_owners[int(graph_segment["b"])]
			),
		})
	if river.get("collect_only", false):
		return {"docks": [], "candidates": candidates, "bank_regions": candidates, "lowland_regions": [], "selected_candidates": [], "rejected": rejected}
	if river.get("full_network", false):
		return _select_full_river_docks(image, river, candidates, occupied_positions, land_positions, first_city_id, map_aspect_ratio, rejected)
	var result: Array[Dictionary] = []
	# 按沿河一侧的省份覆盖，不按微小河段逐个落点。先把同一参考岸省份
	# 的全部位置归组，再为每省选择一个与既有渡口保持间距的最低点。
	# 这避免“各省先各选最低点后恰好挤在一起”而无谓丢掉大量省份。
	var candidates_by_bank_province := {}
	for candidate in candidates:
		var bank_province := int(candidate["reference_bank"])
		if not candidates_by_bank_province.has(bank_province):
			candidates_by_bank_province[bank_province] = (
				[] as Array[Dictionary]
			)
		(candidates_by_bank_province[bank_province] as Array[Dictionary]).append(
			candidate
		)
	var bank_provinces := candidates_by_bank_province.keys()
	bank_provinces.sort_custom(func(a: Variant, b: Variant) -> bool:
		var candidates_a: Array = candidates_by_bank_province[a]
		var candidates_b: Array = candidates_by_bank_province[b]
		return (
			float(candidates_a[0]["river_progress"])
				< float(candidates_b[0]["river_progress"])
		)
	)
	var bank_region_candidates: Array[Dictionary] = []
	for bank_value in bank_provinces:
		var group: Array[Dictionary] = candidates_by_bank_province[bank_value]
		var preferred: Dictionary = group[0]
		for candidate in group:
			if (
				(
					bool(candidate["lowland"])
					and not bool(preferred["lowland"])
				)
				or (
					bool(candidate["lowland"]) == bool(preferred["lowland"])
					and bool(candidate["same_initial_nation"])
					and not bool(preferred["same_initial_nation"])
				)
				or (
					bool(candidate["lowland"]) == bool(preferred["lowland"])
					and bool(candidate["same_initial_nation"])
						== bool(preferred["same_initial_nation"])
					and (
						float(candidate["height"]) < float(preferred["height"])
						or (
							is_equal_approx(
								float(candidate["height"]),
								float(preferred["height"])
							)
							and float(candidate["city_clearance"])
								> float(preferred["city_clearance"])
						)
					)
				)
			):
				preferred = candidate
		bank_region_candidates.append(preferred)
	var selected_candidates: Array[Dictionary] = []
	if bool(river.get("strict_transport", false)):
		# Cover the complete reach, including repeated shore provinces. The
		# existing global dock spacing still bounds the number of ferry nodes.
		bank_region_candidates = candidates.duplicate()
		bank_region_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.river_progress < b.river_progress
		)
	for preferred in bank_region_candidates:
		if _minimum_metric_position_distance(
			preferred["position"],
			occupied_positions.slice(land_positions.size()),
			map_aspect_ratio
		) < RIVER_DOCK_MIN_SPACING:
			rejected.dock_spacing += 1
			continue
		var dock := _boundary_dock_record(
			image, int(river["river_id"]), preferred,
			first_city_id + result.size()
		)
		result.append(dock)
		selected_candidates.append(preferred)
		occupied_positions.append(dock["position"] as Vector2)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["river_progress"]) < float(b["river_progress"])
	)
	var selected_lowland: Array[Dictionary] = []
	for selected in selected_candidates:
		if bool(selected["lowland"]):
			selected_lowland.append(selected)
	return {
		"docks": result,
		"candidates": candidates,
		"bank_regions": bank_region_candidates,
		"lowland_regions": selected_lowland,
		"selected_candidates": selected_candidates,
		"rejected": rejected,
	}


static func _select_full_river_docks(image: Image, river: Dictionary, candidates: Array[Dictionary], occupied: Array[Vector2], positions: Array[Vector2], first_id: int, aspect: float, rejected: Dictionary) -> Dictionary:
	var pending := candidates.duplicate()
	var covered: Dictionary = river.get("covered_windows", {})
	var selected: Array[Dictionary] = []
	var docks: Array[Dictionary] = []
	var windows := {}
	var blocked := Hydrology.barriers(river.get("features", []), image.get_size())
	for candidate in pending:
		if not windows.has(candidate.coverage): windows[candidate.coverage] = {"candidates": 0, "docks": 0, "rejected": {}}
		windows[candidate.coverage].candidates += 1
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.get("reserved", false) != b.get("reserved", false): return a.get("reserved", false)
		if a.relief != b.relief: return a.relief < b.relief
		if a.city_clearance != b.city_clearance: return a.city_clearance > b.city_clearance
		if a.river_id != b.river_id: return a.river_id < b.river_id
		return a.river_progress < b.river_progress
	)
	var deferred: Array[Dictionary] = []
	var filling_gaps := true
	while not pending.is_empty() or not deferred.is_empty():
		if pending.is_empty():
			pending = deferred
			deferred = []
			filling_gaps = false
		var candidate: Dictionary = pending.pop_front()
		if filling_gaps and covered.has(candidate.coverage):
			deferred.append(candidate)
			continue
		var reason := ""
		if _minimum_metric_position_distance(candidate.position, occupied.slice(positions.size()), aspect) < RIVER_DOCK_MIN_SPACING:
			reason = "dock_spacing"
		elif candidate.relief > ROAD_MAXIMUM_HEIGHT_DIFFERENCE:
			reason = "local_height"
		elif river.has("provinces"):
			for side in ["a", "b"]:
				var city: int = candidate["bank_" + side]
				var path := _province_to_boundary_dock_path(river.provinces, positions[city], city, candidate["cell_" + side], candidate.position, blocked)
				if path.size() < 2:
					reason = "bank_path"
					break
				candidate["path_" + side] = path
		if not reason.is_empty():
			rejected[reason] = int(rejected.get(reason, 0)) + 1
			var reasons: Dictionary = windows[candidate.coverage].rejected
			reasons[reason] = int(reasons.get(reason, 0)) + 1
			continue
		var dock := _boundary_dock_record(image, int(candidate.river_id), candidate, first_id + docks.size())
		dock["reach_fraction"] = candidate.get("reach_fraction", 0.5)
		for side in ["a", "b"]:
			if candidate.has("path_" + side): dock["path_" + side] = candidate["path_" + side]
		docks.append(dock)
		selected.append(candidate)
		occupied.append(dock.position)
		covered[candidate.coverage] = true
		windows[candidate.coverage].docks += 1
	return {"docks": docks, "candidates": candidates, "bank_regions": candidates, "lowland_regions": [], "selected_candidates": selected, "rejected": rejected, "coverage": windows}

static func _dock_reach_band(fraction: float) -> String:
	return "upstream" if fraction < 1.0 / 3.0 else ("downstream" if fraction >= 2.0 / 3.0 else "middle")

static func _boundary_dock_record(
	image: Image,
	river_id: int,
	point: Dictionary,
	city_id: int
) -> Dictionary:
	var position: Vector2 = point["position"]
	var pixel := Vector2i(
		clampi(int(floor(position.x * image.get_width())), 0, image.get_width() - 1),
		clampi(int(floor(position.y * image.get_height())), 0, image.get_height() - 1)
	)
	var owner_a := int(point["bank_a"])
	var owner_b := int(point["bank_b"])
	var owner_pick := _boundary_random_unit(
		river_id, int(floor(float(point["river_progress"]))), 7919
	)
	return {
		"city_id": city_id,
		"river_id": river_id,
		"river_progress": float(point["river_progress"]),
		"position": position,
		"pixel_position": Vector2(
			position.x * float(image.get_width()) - 0.5,
			position.y * float(image.get_height()) - 0.5
		),
		"height": packed_altitude(image.get_pixelv(pixel)),
		"relief": _local_relief(image, pixel.x, pixel.y, RELIEF_RADIUS),
		"bank_a": owner_a,
		"bank_b": owner_b,
		"reference_bank": int(point.get("reference_bank", owner_a)),
		"lowland": bool(point.get("lowland", false)),
		"cell_a": point["cell_a"],
		"cell_b": point["cell_b"],
		"road_a": owner_a,
		"road_b": owner_b,
		"road_t": 0.25 if owner_pick < 0.5 else 0.75,
		"owner_city": owner_a if owner_pick < 0.5 else owner_b,
	}


static func _boundary_river_point_at_distance(
	path: PackedVector2Array,
	edge_indices: Array,
	cumulative: PackedFloat32Array,
	target_distance: float,
	graph_segments: Array[Dictionary],
	map_aspect_ratio: float
) -> Dictionary:
	var path_index := 0
	while (
		path_index + 1 < cumulative.size() - 1
		and float(cumulative[path_index + 1]) < target_distance
	):
		path_index += 1
	var segment_length := metric_length_between(
		path[path_index], path[path_index + 1], map_aspect_ratio
	)
	var ratio := clampf(
		(target_distance - float(cumulative[path_index]))
			/ maxf(segment_length, 0.000001),
		0.001, 0.999
	)
	var graph_segment: Dictionary = graph_segments[int(edge_indices[path_index])]
	return {
		"position": path[path_index].lerp(path[path_index + 1], ratio),
		"river_progress": float(path_index) + ratio,
		"bank_a": int(graph_segment["a"]),
		"bank_b": int(graph_segment["b"]),
		"cell_a": graph_segment["cell_a"],
		"cell_b": graph_segment["cell_b"],
	}


static func _province_to_boundary_dock_path(
	provinces: Dictionary,
	city_position: Vector2,
	city_id: int,
	bank_cell: Vector2i,
	dock_position: Vector2,
	blocked_edges: Dictionary = {}
) -> PackedVector2Array:
	var size: Vector2i = provinces["size"]
	var ids: PackedInt32Array = provinces["ids"]
	if not blocked_edges.is_empty():
		var bank_center := (Vector2(bank_cell) + Vector2.ONE * 0.5) / Vector2(size)
		var options: Dictionary = provinces.get("routing_options", {})
		if options.get("strict", false) and not _safe_road_shortcut(bank_center, dock_position, options): return PackedVector2Array()
		if provinces.has("physical_components") and LandComponents.at(provinces.physical_components, city_position) != LandComponents.at(provinces.physical_components, bank_center): return PackedVector2Array()
		var path: PackedVector2Array
		if options.get("pixel_fallback", false):
			# Many samples share a shore cell. Its city approach is identical,
			# including failure, while only the short final dock segment varies.
			if not provinces.has("dock_approach_cache"): provinces["dock_approach_cache"] = {}
			var cache: Dictionary = provinces.dock_approach_cache
			var key := Vector3i(city_id, bank_cell.x, bank_cell.y)
			if not cache.has(key): cache[key] = province_pair_path(ids, size, city_position, bank_center, city_id, city_id, blocked_edges, options)
			path = (cache[key] as PackedVector2Array).duplicate()
		else:
			path = province_pair_path(ids, size, city_position, bank_center, city_id, city_id, blocked_edges, options)
		if not path.is_empty(): path.append(dock_position)
		return path
	var start := Vector2i(
		clampi(int(floor(city_position.x * size.x)), 0, size.x - 1),
		clampi(int(floor(city_position.y * size.y)), 0, size.y - 1)
	)
	var raw_cells := _province_owner_cell_path(
		ids, size, start, bank_cell, city_id
	)
	assert(not raw_cells.is_empty(), "岸边城市必须能在本省内连接到省界码头")
	var result := PackedVector2Array([city_position])
	for cell_index in range(1, raw_cells.size() - 1):
		var incoming: Vector2i = raw_cells[cell_index] - raw_cells[cell_index - 1]
		var outgoing: Vector2i = raw_cells[cell_index + 1] - raw_cells[cell_index]
		if incoming != outgoing:
			result.append(
				(Vector2(raw_cells[cell_index]) + Vector2(0.5, 0.5))
					/ Vector2(size)
			)
	var bank_center := (Vector2(bank_cell) + Vector2(0.5, 0.5)) / Vector2(size)
	if result[-1].distance_squared_to(bank_center) > 0.000000000001:
		result.append(bank_center)
	if result[-1].distance_squared_to(dock_position) > 0.000000000001:
		result.append(dock_position)
	else:
		result[-1] = dock_position
	return result


static func _province_owner_cell_path(
	province_ids: PackedInt32Array,
	size: Vector2i,
	start: Vector2i,
	goal: Vector2i,
	owner: int
) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	var start_index := start.y * size.x + start.x
	var goal_index := goal.y * size.x + goal.x
	if (
		int(province_ids[start_index]) != owner
		or int(province_ids[goal_index]) != owner
	):
		return empty
	var previous := PackedInt32Array()
	previous.resize(size.x * size.y)
	previous.fill(-2)
	previous[start_index] = -1
	var queue: Array[int] = [start_index]
	var head := 0
	var offsets := [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	]
	while head < queue.size() and previous[goal_index] == -2:
		var current_index := queue[head]
		head += 1
		var current := Vector2i(
			current_index % size.x, current_index / size.x
		)
		for offset_value in offsets:
			var next: Vector2i = current + offset_value
			if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y:
				continue
			var next_index := next.y * size.x + next.x
			if previous[next_index] != -2 or int(province_ids[next_index]) != owner:
				continue
			previous[next_index] = current_index
			queue.append(next_index)
	if previous[goal_index] == -2:
		return empty
	var result: Array[Vector2i] = []
	var cursor := goal_index
	while cursor >= 0:
		result.append(Vector2i(cursor % size.x, cursor / size.x))
		cursor = previous[cursor]
	result.reverse()
	return result


static func _minimum_metric_position_distance(
	position: Vector2, others: Array, map_aspect_ratio: float
) -> float:
	if others.is_empty():
		return INF
	var result := INF
	for other_value in others:
		result = minf(
			result, metric_length_between(
				position, Vector2(other_value), map_aspect_ratio
			)
		)
	return result


static func _boundary_random_unit(a: int, b: int, c: int) -> float:
	var value := posmod(
		a * 73856093 + b * 19349663 + c * 83492791 + 104729,
		2147483647
	)
	value = posmod(value * 48271 + 31, 2147483647)
	return float(value) / 2147483647.0


static func river_link_is_navigable(height_difference: float) -> bool:
	return height_difference <= ROAD_MAXIMUM_HEIGHT_DIFFERENCE


static func _boundary_river_link_danger(
	path: PackedVector2Array,
	height_difference: float,
	river_id: int,
	link_index: int
) -> float:
	var turn_total := 0.0
	for point_index in range(path.size()):
		if point_index > 0 and point_index + 1 < path.size():
			var incoming := (path[point_index] - path[point_index - 1]).normalized()
			var outgoing := (path[point_index + 1] - path[point_index]).normalized()
			turn_total += 1.0 - clampf(incoming.dot(outgoing), -1.0, 1.0)
	return clampf(
		0.12 + height_difference * 2.5
			+ turn_total / float(maxi(path.size() - 2, 1)) * 0.10
			+ _boundary_random_unit(river_id, link_index, 3571) * 0.08,
		0.12, 0.60
	)


## 按原始河程截取相邻码头间的正式折线。码头可能来自道路与河道的
## 亚像素交点，所以首尾使用码头精确位置，中间使用河道采样点。
static func _river_path_between_docks(
	river: PackedVector2Array,
	from_position: Vector2,
	to_position: Vector2,
	from_progress: float,
	to_progress: float
) -> PackedVector2Array:
	assert(river.size() >= 2, "河运边必须依附有效河道")
	assert(
		to_progress > from_progress,
		"相邻码头必须按递增河程连接"
	)
	var result := PackedVector2Array([from_position])
	for river_index in range(1, river.size() - 1):
		if (
			float(river_index) <= from_progress + 0.000001
			or float(river_index) >= to_progress - 0.000001
		):
			continue
		var point := river[river_index]
		if result[-1].distance_squared_to(point) > 0.000000000001:
			result.append(point)
	if result[-1].distance_squared_to(to_position) > 0.000000000001:
		result.append(to_position)
	else:
		result[-1] = to_position
	assert(result.size() >= 2, "相邻码头河道切片不能为空")
	return result


static func _initial_nation_owner_by_position(
	city_positions: Array[Vector2],
	nation_count: int = 4
) -> Array[int]:
	var owner: Array[int] = []
	owner.resize(city_positions.size())
	owner.fill(-1)
	var ordered: Array[int] = []
	for city_id in range(city_positions.size()):
		ordered.append(city_id)
	if nation_count != 4:
		_assign_initial_owner_partition(
			ordered, city_positions, 0, nation_count, owner
		)
		return owner
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var pa := city_positions[a]
		var pb := city_positions[b]
		if not is_equal_approx(pa.x, pb.x):
			return pa.x < pb.x
		return pa.y < pb.y
	)
	var side_size := city_positions.size() / 2
	for side in range(2):
		var side_cities: Array[int] = []
		for index in range(
			side * side_size,
			(side + 1) * side_size
		):
			side_cities.append(ordered[index])
		side_cities.sort_custom(func(a: int, b: int) -> bool:
			var pa := city_positions[a]
			var pb := city_positions[b]
			if not is_equal_approx(pa.y, pb.y):
				return pa.y < pb.y
			return pa.x < pb.x
		)
		for index in range(side_cities.size()):
			var row_half := (
				0
				if index < side_cities.size() / 2
				else 1
			)
			owner[side_cities[index]] = row_half * 2 + side
	return owner


static func _assign_initial_owner_partition(
	city_ids: Array[int],
	city_positions: Array[Vector2],
	first_nation: int,
	nation_count: int,
	owner: Array[int]
) -> void:
	if nation_count <= 1:
		for city_id in city_ids:
			owner[city_id] = first_nation
		return
	var minimum := city_positions[city_ids[0]]
	var maximum := minimum
	for city_id in city_ids:
		minimum = minimum.min(city_positions[city_id])
		maximum = maximum.max(city_positions[city_id])
	var split_x := maximum.x - minimum.x >= maximum.y - minimum.y
	city_ids.sort_custom(func(a: int, b: int) -> bool:
		var pa := city_positions[a]
		var pb := city_positions[b]
		var primary_a := pa.x if split_x else pa.y
		var primary_b := pb.x if split_x else pb.y
		if not is_equal_approx(primary_a, primary_b):
			return primary_a < primary_b
		var secondary_a := pa.y if split_x else pa.x
		var secondary_b := pb.y if split_x else pb.x
		return secondary_a < secondary_b if not is_equal_approx(
			secondary_a, secondary_b
		) else a < b
	)
	var left_nations := nation_count / 2
	var right_nations := nation_count - left_nations
	var split_index := clampi(
		int(round(
			float(city_ids.size()) * float(left_nations) / float(nation_count)
		)),
		left_nations, city_ids.size() - right_nations
	)
	var left_ids: Array[int] = []
	var right_ids: Array[int] = []
	for index in range(city_ids.size()):
		(left_ids if index < split_index else right_ids).append(city_ids[index])
	_assign_initial_owner_partition(
		left_ids, city_positions, first_nation, left_nations, owner
	)
	_assign_initial_owner_partition(
		right_ids, city_positions, first_nation + left_nations,
		right_nations, owner
	)


static func distance_units_for_metric_length(metric_length: float) -> int:
	return maxi(
		int(round(
			maxf(metric_length, 0.0)
				* EDGE_DISTANCE_UNITS_PER_MAP_HEIGHT
		)),
		1
	)


static func metric_length_between(
	from_position: Vector2,
	to_position: Vector2,
	map_aspect_ratio: float
) -> float:
	var delta := to_position - from_position
	delta.x *= map_aspect_ratio
	return delta.length()


static func river_crossing_positions(
	from_position: Vector2,
	to_position: Vector2,
	paths: Array[PackedVector2Array]
) -> PackedVector2Array:
	var road_delta := to_position - from_position
	var road_length_sq := road_delta.length_squared()
	var crossings: Array[Dictionary] = []
	if road_length_sq <= 0.000001:
		return PackedVector2Array()
	for path in paths:
		for path_index in range(path.size() - 1):
			var hit = Geometry2D.segment_intersects_segment(
				from_position, to_position,
				path[path_index], path[path_index + 1]
			)
			if hit == null:
				continue
			var road_t := (
				(Vector2(hit) - from_position).dot(road_delta)
					/ road_length_sq
			)
			if (
				road_t > RIVER_CROSSING_ENDPOINT_EPS
				and road_t < 1.0 - RIVER_CROSSING_ENDPOINT_EPS
			):
				var duplicate := false
				for existing in crossings:
					if (
						absf(float(existing["t"]) - road_t)
							<= RIVER_CROSSING_ENDPOINT_EPS
					):
						duplicate = true
						break
				if not duplicate:
					crossings.append({"t": road_t, "position": Vector2(hit)})
	crossings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["t"]) < float(b["t"])
	)
	var result := PackedVector2Array()
	for crossing in crossings:
		result.append(crossing["position"])
	return result


static func altitude_at_map_position(
	source_path: String, map_position: Vector2
) -> float:
	var texture := load(source_path) as Texture2D
	if texture == null:
		return 0.0
	var image := texture.get_image()
	if image == null or image.is_empty():
		return 0.0
	var x := clampi(
		int(floor(clampf(map_position.x, 0.0, 1.0) * image.get_width())),
		0, image.get_width() - 1
	)
	var y := clampi(
		int(floor(clampf(map_position.y, 0.0, 1.0) * image.get_height())),
		0, image.get_height() - 1
	)
	return packed_altitude(image.get_pixel(x, y))


static func _normalized_map_point(
	point: Vector2,
	bounds: Rect2i
) -> Vector2:
	return Vector2(
		(point.x - float(bounds.position.x) + 0.5)
			/ float(maxi(bounds.size.x, 1)),
		(point.y - float(bounds.position.y) + 0.5)
			/ float(maxi(bounds.size.y, 1))
	)


static func _pixel_relief(
	image: Image,
	x: int,
	y: int
) -> float:
	var center := packed_altitude(image.get_pixel(x, y))
	var result := 0.0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var px := clampi(x + ox, 0, image.get_width() - 1)
			var py := clampi(y + oy, 0, image.get_height() - 1)
			result = maxf(
				result,
				absf(
					center
					- packed_altitude(image.get_pixel(px, py))
				)
			)
	return result


static func _edge_profile(
	image: Image,
	mask: PackedByteArray,
	from: Vector2i,
	to: Vector2i
) -> Dictionary:
	var minimum := 1.0
	var maximum := 0.0
	var land_samples := 0
	for i in range(ROAD_SAMPLE_COUNT + 1):
		var t := float(i) / float(ROAD_SAMPLE_COUNT)
		var point := Vector2(from).lerp(Vector2(to), t)
		var x := clampi(int(round(point.x)), 0, image.get_width() - 1)
		var y := clampi(int(round(point.y)), 0, image.get_height() - 1)
		var height := packed_altitude(image.get_pixel(x, y))
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		if mask[y * image.get_width() + x] != 0:
			land_samples += 1
	return {
		"height_difference": maximum - minimum,
		"land_ratio": float(land_samples) / float(ROAD_SAMPLE_COUNT + 1),
	}

## Grade the actual routed line, not a straight chord across a bay or mountain.
static func _polyline_terrain_profile(image: Image, mask: PackedByteArray, path: PackedVector2Array) -> Dictionary:
	var low := 1.0
	var high := 0.0
	var land_samples := 0
	var count := 0
	for i in range(path.size() - 1):
		var a := path[i] * Vector2(image.get_size())
		var b := path[i + 1] * Vector2(image.get_size())
		var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
		for step in range(steps + 1):
			var p := Vector2i(a.lerp(b, float(step) / steps)).clamp(Vector2i.ZERO, image.get_size() - Vector2i.ONE)
			var height := packed_altitude(image.get_pixelv(p))
			low = minf(low, height)
			high = maxf(high, height)
			land_samples += int(mask[p.y * image.get_width() + p.x] != 0)
			count += 1
	return {"height_difference": high - low, "land_ratio": float(land_samples) / maxi(count, 1)}


static func _pair_key(a: int, b: int) -> int:
	return mini(a, b) * 10000 + maxi(a, b)


static func _root(parent: Array[int], node: int) -> int:
	var current := node
	while parent[current] != current:
		parent[current] = parent[parent[current]]
		current = parent[current]
	return current

static func _atlas_land_domain(source: Image,grid: Vector2i) -> PackedByteArray:
	# Assign provinces once on conservative fine-land occupancy. The same
	# immutable DEM components are reused by road connectivity validation.
	var physical:=LandComponents.build(source);var size: Vector2i=physical.size
	var mask:=PackedByteArray();mask.resize(grid.x*grid.y)
	for y in range(size.y):
		var row:=mini(grid.y-1,y*grid.y/size.y)*grid.x
		for run in physical.rows[y]:
			var low:=int(run.x)*grid.x/size.x;var high:=(int(run.y)-1)*grid.x/size.x
			for x in range(low,high+1): mask[row+x]=1
	return mask
