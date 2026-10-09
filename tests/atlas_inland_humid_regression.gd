extends SceneTree
## Behavioral regressions for inland moisture and persistent humid heat.
## Same verified Earth/SST source, at each model's production resolution.
const Model = preload("res://scripts/atlas/seasonal_circulation.gd")
const Legacy = preload("res://scripts/atlas/seasonal_circulation_v4.gd")
const Capacity = preload("res://scripts/atlas/climate_settlement_v5.gd") # Historical humid-heat policy, superseded by v6 cap.
const Adapter = preload("res://scripts/atlas/circulation_rainfall.gd")
const Earth = preload("res://scripts/atlas/earth_surface.gd")
const Sampler = preload("res://scripts/atlas/monsoon_rainfall.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("INLAND_HUMID_FAIL ", message)

func point(fields: Dictionary, land: PackedByteArray, size: Vector2i, lon: float, lat: float) -> Array:
	var values: Array = []
	var position := Vector2((lon + 180.) / 360. * size.x - .5, (90. - lat) / 180. * size.y - .5)
	for quarter in fields.quarters:
		values.append(Sampler.sample_land(quarter, land, position, size) * .25)
	return values

func inputs(surface: Dictionary, data: Dictionary, size: Vector2i) -> Dictionary:
	var elevation := Model.zeros(size.x * size.y); var raw_height := elevation.duplicate()
	var land := PackedByteArray(); land.resize(elevation.size())
	var types := land.duplicate()
	for y in range(size.y):
		for x in range(size.x):
			var lon := (x + .5) / size.x * 360. - 180.
			var lat := 90. - (y + .5) / size.y * 180.; var i := y * size.x + x
			raw_height[i] = Earth.elevation_at(surface, lon, lat)
			elevation[i] = maxf(0., raw_height[i])
			types[i] = Earth.water_at(surface, lon, lat)
			land[i] = int(types[i] == 0)
	var anomaly := Adapter.sea_anomaly_grid(data.mesh, data.environment.water, data.environment.currents.sst, size)
	return {"elevation":elevation, "land":land, "options":{"sea_temperature_anomaly":anomaly, "water_types":types, "lowland_lakes":Adapter.lowland_lake_mask(types,raw_height,size)}}

func total(values: Array) -> float:
	var result := 0.
	for value in values: result += float(value)
	return result

func score(temperatures: Array, rainfall: Array) -> float:
	return float(Capacity.seasonal_suitability(PackedFloat32Array(temperatures), PackedFloat32Array(rainfall), 30.).factor)

func _initialize() -> void:
	var source := "res://.dbg/atlas-native-generated-earth-rainfall-v4.bin"
	check(FileAccess.file_exists(source), "frozen v4 Earth snapshot is required")
	if not FileAccess.file_exists(source): quit(1); return
	var data: Dictionary = FileAccess.open(source, FileAccess.READ).get_var(false).data
	var surface := Earth.load_surface()
	check(not surface.is_empty(), "verified Earth surface unavailable")
	if surface.is_empty(): quit(1); return
	var size := Adapter.CURRENT_GRID; var old_size := Adapter.GRID
	var current_input := inputs(surface, data, size)
	var old_input := inputs(surface, data, old_size)
	var fields := Model.build_fields(current_input.elevation, current_input.land, size, current_input.options)
	var legacy := Legacy.build_fields(old_input.elevation, old_input.land, old_size, old_input.options)
	var coordinates := {"Atyrau":[51.9,47.1], "CaspianEast":[54.,43.], "CaspianSouth":[49.6,37.3], "Zhengzhou":[113.65,34.72], "Berlin":[13.4,52.5], "London":[-.12,51.5], "Chicago":[-87.63,41.88]}
	var current_points: Dictionary = {}; var old_points: Dictionary = {}
	for name in coordinates:
		var coord: Array = coordinates[name]
		current_points[name] = point(fields, current_input.land, size, coord[0], coord[1])
		old_points[name] = point(legacy, old_input.land, old_size, coord[0], coord[1])
	check(total(current_points.Atyrau) > 50. and total(current_points.Atyrau) < 400., "Caspian north shore still behaves like a wet marine coast")
	check(total(current_points.CaspianEast) > 50. and total(current_points.CaspianEast) < 400., "Caspian east shore inland humidity is excessive")
	check(total(current_points.CaspianSouth) > total(current_points.CaspianEast), "Caspian south/east rainfall contrast was erased")
	check(current_points.Zhengzhou[0] >= 10. and current_points.Zhengzhou[3] >= 40., "Central Plains winter/autumn moisture regressed to zero")
	check(current_points.Zhengzhou[2] < 800., "coastal approach uplift filled inland Central Plains with excessive rain")
	for name in ["Berlin", "London"]:
		check(total(current_points[name]) > 400., name + " became an arid inland climate")
		check(total(current_points[name]) < 1400., name + " remains excessively wet")
	check(total(current_points.Chicago) > 350., "dry mixing turned the humid North American interior into desert")
	var cool_winter := score([-2.,15.,15.,8.], [100.,300.,300.,150.])
	var sustained_hot_wet := score([27.,15.,15.,27.], [1500.,300.,300.,1500.])
	var tropical_plateau := score([23.5,23.5,23.5,23.5], [500.,500.,500.,500.])
	var one_hot_season := score([-2.,15.,27.,15.], [100.,300.,600.,300.])
	check(sustained_hot_wet < cool_winter * .8, "best two seasons hide persistent hot/wet burdens")
	check(tropical_plateau < .65, "year-round warm wet climate retains overly broad thermal plateau")
	check(cool_winter >= .75, "cold winter incorrectly penalizes two suitable growing seasons")
	check(one_hot_season >= .65, "one hot wet season collapses a temperate two-season climate")
	print("INLAND_HUMID_POINTS ", JSON.stringify({"current":current_points,"v4":old_points}))
	print("INLAND_HUMID_SCORES ", JSON.stringify({"cool_winter":cool_winter,"sustained_hot_wet":sustained_hot_wet,"tropical_plateau":tropical_plateau,"one_hot_season":one_hot_season}))
	print("ATLAS_INLAND_HUMID_REGRESSION ", JSON.stringify({"pid":OS.get_process_id(), "seed":data.seed, "current_grid":[size.x,size.y], "v4_grid":[old_size.x,old_size.y], "rain_model":Model.VERSION, "capacity_model":Capacity.VERSION, "failures":failures}))
	quit(1 if failures else 0)
