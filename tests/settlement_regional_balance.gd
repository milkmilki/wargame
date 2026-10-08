extends SceneTree
## Geographic windows are acceptance diagnostics, never inputs to environment generation.
## Densities use equal-area cells in the projected game plane, not physical Earth area.
const EnvModel = preload("res://scripts/core/settlement_environment.gd")
const Sampler = preload("res://scripts/core/settlement_sampler.gd")
const SOURCE := "res://assets/terrain/eurasia_environment_map_source.json"
const SIZE := 256
const SEEDS := [2342006650, 12345, 23456, 34567, 45678, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
const WINDOWS := [
	{"name": "china_inland", "west": 108.0, "east": 118.0, "south": 29.0, "north": 37.0},
	{"name": "sahara_inland", "west": 0.0, "east": 30.0, "south": 20.0, "north": 29.0},
	{"name": "arabia_inland", "west": 40.0, "east": 50.0, "south": 20.0, "north": 29.0},
]

func _init() -> void:
	call_deferred("_run")

func _region(longitude: float, latitude: float) -> int:
	for index in range(WINDOWS.size()):
		var window: Dictionary = WINDOWS[index]
		if longitude >= window.west and longitude < window.east and latitude >= window.south and latitude < window.north:
			return index
	return -1

func _run() -> void:
	var source := (load(MapSource.texture_path(SOURCE)) as Texture2D).get_image()
	var analysis := source.duplicate()
	analysis.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
	var land: PackedByteArray = TerrainMapGenerator._all_land_geometry(analysis).mask
	var latitudes := PackedFloat32Array()
	for y in range(SIZE):
		latitudes.append(MapSource.latitude_at_y((y + 0.5) / SIZE, 18.0, 57.0, SOURCE))
	var aspect := MapSource.aspect_ratio(SOURCE)
	var environment := EnvModel.build(source, analysis, land, latitudes, aspect, MapSource.projection_type(SOURCE))
	var land_cells := [0, 0, 0]
	var suitability_sum := [0.0, 0.0, 0.0]
	var cities := [0, 0, 0]
	for y in range(SIZE):
		for x in range(SIZE):
			var i := y * SIZE + x
			if land[i] == 0:
				continue
			var lonlat := MapSource.map_to_lonlat((x + 0.5) / SIZE, (y + 0.5) / SIZE, SOURCE)
			var region := _region(lonlat[0], lonlat[1])
			if region < 0:
				continue
			land_cells[region] += 1
			suitability_sum[region] += environment.suitability[i]
	for seed_value in SEEDS:
		var sampled := Sampler.sample(source, land, environment, 500, aspect, seed_value)
		if not sampled.ok:
			printerr("SETTLEMENT_REGIONAL_BALANCE_FAIL: seed=%d sampling failed: %s" % [seed_value, sampled.get("error", "unknown")])
			quit(1)
			return
		for position in sampled.positions:
			var lonlat := MapSource.map_to_lonlat(position.x, position.y, SOURCE)
			var region := _region(lonlat[0], lonlat[1])
			if region >= 0:
				cities[region] += 1
	var densities := [0.0, 0.0, 0.0]
	var failures := 0
	for region in range(WINDOWS.size()):
		if land_cells[region] == 0:
			printerr("SETTLEMENT_REGIONAL_BALANCE_FAIL: empty diagnostic land window ", WINDOWS[region].name)
			failures += 1
			continue
		var projected_area: float = land_cells[region] * aspect / (SIZE * SIZE)
		densities[region] = float(cities[region]) / (SEEDS.size() * land_cells[region])
		print("REGIONAL_BALANCE model=%s region=%s seeds=%d land_cells=%d projected_area=%.6f mean_suitability=%.6f cities=%d cities_per_land_cell_per_seed=%.8f" % [EnvModel.VERSION, WINDOWS[region].name, SEEDS.size(), land_cells[region], projected_area, suitability_sum[region] / land_cells[region], cities[region], densities[region]])
	if densities[0] <= 0.0:
		printerr("SETTLEMENT_REGIONAL_BALANCE_FAIL: inland reference has no cities")
		failures += 1
	else:
		for region in [1, 2]:
			var relative_density: float = densities[region] / densities[0]
			print("REGIONAL_DRY_DENSITY region=%s ratio_to_china_inland=%.6f" % [WINDOWS[region].name, relative_density])
			if relative_density > 0.25:
				printerr("SETTLEMENT_REGIONAL_BALANCE_FAIL: %s dry-window density must be at most 25%% of inland reference; actual %.6f" % [WINDOWS[region].name, relative_density])
				failures += 1
	if failures > 0:
		quit(1)
		return
	print("SETTLEMENT_REGIONAL_BALANCE_OK")
	quit()
