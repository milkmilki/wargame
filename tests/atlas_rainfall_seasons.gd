extends SceneTree
const Model = preload("res://scripts/atlas/seasonal_circulation.gd")
const Adapter = preload("res://scripts/atlas/circulation_rainfall.gd")
const Earth = preload("res://scripts/atlas/earth_surface.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("RAINFALL_SEASONS_FAIL ",message)

func point(fields: Dictionary,land: PackedByteArray,lon: float,lat: float) -> Array:
	var result: Array = []
	for values in fields.quarters:
		result.append(preload("res://scripts/atlas/monsoon_rainfall.gd").sample_land(values,land,Vector2((lon+180.)/360.*Adapter.CURRENT_GRID.x-.5,(90.-lat)/180.*Adapter.CURRENT_GRID.y-.5),Adapter.CURRENT_GRID)*.25)
	return result

func _initialize() -> void:
	check(Model.VERSION=="seasonal_circulation_v5","model version must invalidate stale climate caches")
	var data: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-earth-1.bin",FileAccess.READ).get_var(false).data
	var surface := Earth.load_surface(); var size := Adapter.CURRENT_GRID
	var elevation := Model.zeros(size.x*size.y); var raw_height := elevation.duplicate(); var land := PackedByteArray(); land.resize(elevation.size()); var types := land.duplicate()
	for y in range(size.y):
		for x in range(size.x):
			var lon := (x+.5)/size.x*360.-180.; var lat := 90.-(y+.5)/size.y*180.; var i := y*size.x+x
			raw_height[i] = Earth.elevation_at(surface,lon,lat); elevation[i] = maxf(0.,raw_height[i]); types[i] = Earth.water_at(surface,lon,lat); land[i] = int(types[i]==0)
	var fields := Model.build_fields(elevation,land,size,{"sea_temperature_anomaly":Adapter.sea_anomaly_grid(data.mesh,data.environment.water,data.environment.currents.sst,size),"water_types":types,"lowland_lakes":Adapter.lowland_lake_mask(types,raw_height,size)})
	var z := point(fields,land,113.65,34.72); var w := point(fields,land,114.3,30.6)
	check(z[0]>=10. and z[0]<100.,"Central Plains winter must have modest precipitation, not zero or a wet summer")
	check(z[3]>=40. and z[3]<300.,"Central Plains autumn must not become a rainless season")
	check(w[0]>=10. and w[3]>=40.,"Yangtze region winter/autumn moisture transport missing")
	check(z[2]>z[0]*2.,"summer monsoon seasonal contrast lost")
	var s := point(fields,land,129.72,62.02)
	check(s[0]<s[2] and s[1]<s[2]*.8,"cold continental Siberia lacks summer rainfall maximum")
	var desert := point(fields,land,105.,42.); var sahara := point(fields,land,15.,25.)
	var gobi_sum := 0.; var sahara_sum := 0.
	for q in range(4): gobi_sum += desert[q]; sahara_sum += sahara[q]
	check(gobi_sum<200. and sahara_sum<250.,"weather disturbance filled real interior deserts with rain")
	for i in range(elevation.size()):
		check(is_finite(fields.annual[i]) and fields.annual[i]>=0.,"nonfinite or negative rainfall")
	print("RAINFALL_SEASONS_POINTS ",JSON.stringify({"Zhengzhou":z,"Wuhan":w,"Yakutsk":s,"Gobi":desert,"Sahara":sahara}))
	print("ATLAS_RAINFALL_SEASONS failures=",failures); quit(1 if failures else 0)
