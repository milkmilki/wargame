extends SceneTree
const Metrics = preload("res://scripts/tools/atlas_circulation_metrics.gd")
const World = preload("res://scripts/atlas/world.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("EARTH_CIRCULATION_FAIL ",message)
func _initialize() -> void:
	var before: Dictionary = FileAccess.open("res://.dbg/atlas-earth-monsoon-v1.bin",FileAccess.READ).get_var(false).data
	var data: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-earth-1.bin",FileAccess.READ).get_var(false).data
	var env: Dictionary = data.environment
	# This frozen-data test protects v3; the current v4 generation is validated
	# by atlas_rainfall_seasons and atlas_export_rainfall_v4.
	var repeat := World.generate({"seed":1,"terrain_model":"earth","rainfall_model":"seasonal_circulation_v3","settlement_model":"climate_capacity_v3"})
	check(repeat.precipitation==env.precipitation and repeat.quarter_precipitation==env.quarter_precipitation,"real-Earth precipitation not deterministic")
	check(data.options.rainfall_model=="seasonal_circulation_v3" and data.options.settlement_model=="climate_capacity_v3","frozen v3 reference models")
	check(repeat.params.settlement_model=="climate_capacity_v3","historical regeneration silently upgraded the settlement model")
	for field in ["water","elevation","temperature","biome","flux"]:
		check(repeat[field]==env[field],"settlement scoring changed environmental input "+field)
	check(data.mesh.xyz==before.mesh.xyz and data.mesh.triangles==before.mesh.triangles,"mesh changed")
	for field in ["elevation","water","temperature"]: check(env[field]==before.environment[field],"real input or temperature changed "+field)
	for i in range(data.mesh.n):
		var mean := 0.
		for q in range(4):
			mean += env.quarter_precipitation[q][i]*.25
			check(is_finite(env.seasonal_winds[q].u[i]) and is_finite(env.seasonal_winds[q].v[i]),"invalid wind")
		if not env.water[i]: check(absf(mean-env.precipitation[i])<.01,"season peak masquerades as annual rain")
		check(env.suitability[i]>=0 and is_finite(env.suitability[i]),"invalid habitat")
	var wind_error := 0.
	for i in range(data.mesh.n):
		var north := 0.
		for wind in env.seasonal_winds: north += wind.v[i]*.25
		wind_error = maxf(wind_error,absf(env.windY[i]+north))
	check(wind_error<1e-6,"northward seasonal wind not converted to southward atlas coordinates")
	var rows := Metrics.summarize(data); var old := Metrics.summarize(before)
	check(rows.SouthChina.rain_mm_estimate>rows.NorthChina.rain_mm_estimate,"North China still wetter than South China")
	check(rows.Congo.rain_mm_estimate>1000 and rows.Congo.forest_fraction>.65,"Congo wet forest disappeared")
	check(rows.Sahara.rain_mm_estimate<250 and rows.Sahara.desert_fraction>.65,"Sahara lacks a dry desert core")
	check(rows.Gobi.rain_mm_estimate<150,"Gobi became rainy")
	check(rows.Europe.rain_mm_estimate>500 and rows.Europe.rain_mm_estimate<1700,"European westerly rainfall missing/excessive")
	check(rows.HuSE.cities_per_million_km2>3.*rows.HuNW.cities_per_million_km2,"Hu line lacks density contrast")
	check(rows.HuSE.rain_mm_estimate>rows.HuNW.rain_mm_estimate,"Hu line moisture contrast reversed")
	check(rows.Europe.cities>old.Europe.cities,"wet European lowland city cluster did not increase")
	check(rows.NamibiaWest.rain_mm_estimate<250.,"cold western coastal window still too wet")
	check(rows.NamibiaWest.desert_fraction>.35,"Namib aridity not represented by terrain")
	check(rows.Highveld.rain_mm_estimate<1800.,"subtropical highland uplift generates excessive rain")
	check(rows.SouthernAfrica.cities_per_million_km2<rows.Europe.cities_per_million_km2,"southern Africa climate as dense as temperate Europe")
	check(env.rivers.is_empty(),"visible rivers returned")
	print("CIRCULATION_REGIONAL_METRICS ",JSON.stringify(rows)); print("ATLAS_EARTH_CIRCULATION failures=",failures); quit(1 if failures else 0)
