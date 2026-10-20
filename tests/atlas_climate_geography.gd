extends SceneTree
## Fixed NOAA regional observations validate a fresh pure-rule atmosphere.
## The JSON is test-only; no runtime module imports it.
const Model=preload("res://scripts/atlas/seasonal_circulation.gd")
const Adapter=preload("res://scripts/atlas/circulation_rainfall.gd")
const Earth=preload("res://scripts/atlas/earth_surface.gd")
var failures:=0
func check(ok:bool,label:String) -> void:
	if not ok:failures+=1;printerr("CLIMATE_GEOGRAPHY_FAIL ",label)
func _initialize() -> void:
	var surface:=Earth.load_surface();var size:=Adapter.CURRENT_GRID;var n:=size.x*size.y
	var heights:=Model.zeros(n);var raw:=heights.duplicate();var land:=PackedByteArray();land.resize(n);var types:=land.duplicate()
	for y in range(size.y):
		for x in range(size.x):
			var i:=y*size.x+x;var lon:=(x+.5)/size.x*360.-180.;var lat:=90.-(y+.5)/size.y*180.
			raw[i]=Earth.elevation_at(surface,lon,lat);heights[i]=maxf(0.,raw[i]);types[i]=Earth.water_at(surface,lon,lat);land[i]=int(types[i]==0)
	var fields:=Model.build_fields(heights,land,size,{"water_types":types,"lowland_lakes":Adapter.lowland_lake_mask(types,raw,size),"sea_temperature_anomaly":Adapter.marine_anomaly(types,size),"barrier_elevation":Adapter.orographic_barriers(surface,size)})
	var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/atlas_climate_reference.json"))
	var grid:Dictionary=reference.grid_reference
	check(FileAccess.get_sha256(grid.file)==grid.sha256,"offline observed grid checksum")
	var observed_grid:=FileAccess.get_file_as_bytes(grid.file).to_float32_array();var observed_quarters:Array=[]
	for q in range(4):observed_quarters.append(observed_grid.slice(q*144*72,(q+1)*144*72))
	var global_weights:=0.;var global_annual_error:=0.;var global_quarter_error:=0.
	for y in range(size.y):
		var lat:=90.-(y+.5)/size.y*180.
		if absf(lat)>=75.:continue
		var weight:=cos(deg_to_rad(lat))
		for x in range(size.x):
			var i:=y*size.x+x
			if not land[i]:continue
			var lon:=(x+.5)/size.x*360.-180.;var point:=Model.stencil((fposmod(lon,360.)-1.25)/2.5,(88.75-lat)/2.5,Vector2i(144,72))
			var annual_observed:=0.
			for q in range(4):
				var p:=Adapter.sample_any(observed_quarters[q],point);annual_observed+=p
				global_quarter_error+=absf(fields.quarters[q][i]*.25-p)*weight*.25
			global_annual_error+=absf(fields.annual[i]-annual_observed)*weight;global_weights+=weight
	global_annual_error/=global_weights;global_quarter_error/=global_weights
	check(global_annual_error<=reference.revision1_global_annual_mae_mm*1.05,"global annual error cannot regress more than five percent while fixing regions")
	check(global_quarter_error<=reference.revision1_global_quarter_mae_mm*1.05,"global seasonal error cannot regress more than five percent while fixing regions")
	var regions:Dictionary={};var annual_error:=0.;var quarter_error:=0.
	for name_value in reference.regions:
		var observed:Dictionary=reference.regions[name_value];var b:Array=observed.bounds_west_east_south_north
		var weights:=0.;var rain:=PackedFloat64Array([0,0,0,0])
		for y in range(size.y):
			var lat:=90.-(y+.5)/size.y*180.
			if lat<b[2] or lat>=b[3]:continue
			var weight:=cos(deg_to_rad(lat))
			for x in range(size.x):
				var lon:=(x+.5)/size.x*360.-180.;var i:=y*size.x+x
				if not land[i] or lon<b[0] or lon>=b[1]:continue
				if heights[i]>=float(observed.get("max_elevation_m",1e9)):continue
				weights+=weight
				for q in range(4):rain[q]+=fields.quarters[q][i]*.25*weight
		check(weights>0.,"observed region has common land: "+name_value)
		var annual:=0.
		for q in range(4):
			rain[q]/=maxf(weights,1e-9);annual+=rain[q];quarter_error+=absf(rain[q]-observed.quarter_mm[q])
		annual_error+=absf(annual-observed.annual_mm);regions[name_value]={"annual_mm":annual,"quarters_mm":Array(rain)}
	annual_error/=regions.size();quarter_error/=regions.size()*4
	check(annual_error<reference.baseline_region_annual_mae_mm*.8,"fixed regional annual error improves by at least twenty percent over v5")
	check(quarter_error<reference.baseline_region_quarter_mae_mm*.8,"fixed regional quarterly error improves by at least twenty percent over v5")
	check(regions.Mediterranean.quarters_mm[0]>regions.Mediterranean.quarters_mm[2] and regions.PacificNW.quarters_mm[0]>regions.PacificNW.quarters_mm[2],"observed western-shore winter rainfall direction")
	check(regions.India.quarters_mm[2]>regions.India.quarters_mm[0]*3. and regions.SouthChina.quarters_mm[2]>regions.SouthChina.quarters_mm[0]*3.,"South and East Asian summer monsoon survives")
	check(regions.Amazon.annual_mm>reference.regions.Amazon.annual_mm*.5 and regions.Congo.annual_mm>reference.regions.Congo.annual_mm*.5,"major tropical wet cores survive")
	check(regions.Sahara.annual_mm<250. and regions.Gobi.annual_mm<300.,"subtropical and continental dry cores survive")
	for season in [1,3]:check(regions.SouthChina.quarters_mm[season]>=reference.regions.SouthChina.quarter_mm[season]*.65,"South China transition-season rain is not lost: "+str(season))
	check(regions.NorthChina.quarters_mm[2]>=reference.regions.NorthChina.quarter_mm[2]*.7,"summer rain belt reaches North China")
	check(regions.Japan.quarters_mm[2]>=reference.regions.Japan.quarter_mm[2]*.65,"East Asian summer rain belt reaches Japan")
	check(regions.EastAfrica.annual_mm>=500. and regions.EastAfrica.annual_mm<=1200.,"East Africa is neither a tropical rainforest blanket nor a painted desert")
	check(regions.EquatorialEastAfrica.annual_mm<=reference.regions.EquatorialEastAfrica.annual_mm*1.8,"equatorial eastern Africa is not forced into equatorial rainforest rainfall")
	check(regions.HornLowlands.annual_mm<=1000.,"Horn of Africa lowlands are not rainforest-wet")
	print("ATLAS_CLIMATE_GEOGRAPHY ",JSON.stringify({"failures":failures,"global_annual_mae_mm":global_annual_error,"global_quarter_mae_mm":global_quarter_error,"annual_region_mae_mm":annual_error,"quarter_region_mae_mm":quarter_error,"regions":regions}));quit(1 if failures else 0)
