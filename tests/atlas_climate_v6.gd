extends SceneTree
## General mechanisms; geographic observations are a separate validation fixture.
const Model=preload("res://scripts/atlas/seasonal_circulation.gd")
var failures:=0
func check(ok:bool,label:String) -> void:
	if not ok:failures+=1;printerr("CLIMATE_V6_FAIL ",label)
func _initialize() -> void:
	var model=Model.new()
	var island_size:=Vector2i(72,36);var islands:=PackedByteArray();islands.resize(island_size.x*island_size.y)
	islands[18*72+5]=1
	for y in range(10,26):
		for x in range(25,45):islands[y*72+x]=1
	var continents:=Model.continental_land(islands,island_size)
	check(continents[18*72+5]==0 and continents[18*72+35]==1,"maritime island is not assigned the large continent's thermal cap and ocean gyre response")
	check(model.has_method("upwelling_anomaly"),"alongshore winds drive coastal cooling with the hemisphere's Ekman direction")
	check(model.has_method("marine_boundary"),"onshore Ekman transport can replace a static cold-coast assumption with warm surface water")
	check(model.has_method("cloud_to_ground"),"finite cloud conversion leaves excess moisture available for downwind rainfall")
	if model.has_method("cloud_to_ground"):
		var limited:float=model.cloud_to_ground(.5,85000.)
		check(limited>0. and limited<.5,"extreme condensed columns are not dumped into one coarse cell")
		check(model.cloud_to_ground(0.,85000.)==0. and model.cloud_to_ground(.001,85000.)==.001,"ordinary clouds and empty columns preserve their flux")
	if model.has_method("upwelling_anomaly"):
		var sea_size:=Vector2i(72,36);var coast:=PackedByteArray();coast.resize(sea_size.x*sea_size.y)
		for y in range(sea_size.y):
			for x in range(36,sea_size.x):coast[y*sea_size.x+x]=1
		var flow:={"u":Model.zeros(coast.size()),"v":Model.zeros(coast.size())};flow.v.fill(-1.)
		var southward:PackedFloat32Array=model.upwelling_anomaly(coast,sea_size,flow)
		flow.v.fill(1.)
		var northward:PackedFloat32Array=model.upwelling_anomaly(coast,sea_size,flow)
		check(southward[13*sea_size.x+35]<-1. and northward[13*sea_size.x+35]==0.,"Northern Hemisphere offshore Ekman transport cools; onshore transport does not")
		check(northward[22*sea_size.x+35]<-1. and southward[22*sea_size.x+35]==0.,"Southern Hemisphere reverses the upwelling-favourable wind")
		if model.has_method("marine_boundary"):
			var cold:=Model.zeros(coast.size());cold.fill(-6.)
			var warmed:PackedFloat32Array=model.marine_boundary(cold,coast,sea_size,flow)
			check(warmed[13*sea_size.x+35]>-3. and warmed[13*sea_size.x+35]<=0.,"downwelling relaxes coastal cold anomaly without inventing a warm ocean beyond its background")
	check(model.has_method("steer_terrain"),"low-level winds respond to terrain before moisture transport")
	if model.has_method("steer_terrain"):
		var ridge_size:=Vector2i(144,72);var ridge:=Model.zeros(ridge_size.x*ridge_size.y)
		var flow:={"u":ridge.duplicate(),"v":ridge.duplicate()};flow.u.fill(1.);flow.v.fill(.3)
		var flat:Dictionary=model.steer_terrain(flow,ridge,ridge_size)
		check(flat.u==flow.u and flat.v==flow.v,"flat terrain does not invent a wind correction")
		for y in range(ridge_size.y):ridge[y*ridge_size.x+72]=6000.
		var guided:Dictionary=model.steer_terrain(flow,ridge,ridge_size)
		var cell:=20*ridge_size.x+70
		check(guided.u[cell]<flow.u[cell] and guided.v[cell]>flow.v[cell],"windward barrier reduces cross-ridge flow and strengthens the existing along-ridge flow")
	check(Model.VERSION=="seasonal_circulation_v6","new model must invalidate stale climate caches")
	check(model.has_method("subsidence"),"seasonal subtropical subsidence is explicit and testable")
	if model.has_method("subsidence"):
		check(model.subsidence(37.,.85)>model.subsidence(37.,-.85)*3.,"subtropical western shores need stronger summer subsidence")
		check(absf(model.subsidence(-37.,-.85)-model.subsidence(37.,.85))<1e-6,"southern-hemisphere seasonal symmetry")
		check(model.subsidence(0.,0.)<.05,"equatorial convection must not become a desert belt")
	var adapter=preload("res://scripts/atlas/circulation_rainfall.gd").new()
	var relief:=PackedByteArray();relief.resize(72*36*2)
	for y in range(36):relief.encode_s16((y*72+36)*2,4000)
	var surface:={"width":72,"height":36,"heights":relief,"metadata":{"elevation_scale_m":1.}}
	var barriers:PackedFloat32Array=adapter.orographic_barriers(surface,Vector2i(24,12))
	var ground:=preload("res://scripts/atlas/earth_surface.gd").elevation_at(surface,7.5,-7.5)
	check(barriers[6*24+12]>ground and surface.heights==relief,"sub-grid ridge raises only the transport barrier, preserving source ground data")
	check(adapter.has_method("marine_anomaly"),"coastal SST has a complete source-grid basis")
	if adapter.has_method("marine_anomaly"):
		var size:=Vector2i(72,36);var water:=PackedByteArray();water.resize(size.x*size.y);water.fill(1)
		for y in range(size.y):
			for x in range(24,48):water[y*size.x+x]=0
		var anomaly:PackedFloat32Array=adapter.marine_anomaly(water,size)
		check(anomaly[11*size.x+23]<-1.,"cold west-continental coast survives adjacent land in the same coarse region")
		check(anomaly[11*size.x+48]>1.,"warm east-continental coast remains distinct")
		var shifted:=water.duplicate()
		for y in range(size.y):
			for x in range(size.x):shifted[y*size.x+(x+13)%size.x]=water[y*size.x+x]
		var moved:PackedFloat32Array=adapter.marine_anomaly(shifted,size)
		var error:=0.
		for y in range(size.y):
			for x in range(size.x):error=maxf(error,absf(anomaly[y*size.x+x]-moved[y*size.x+(x+13)%size.x]))
		check(error<1e-6,"marine basin proxy is invariant under longitude rotation")
	var size:=Vector2i(48,24);var n:=size.x*size.y;var height:=Model.zeros(n);var land:=PackedByteArray();land.resize(n);land.fill(1)
	for y in range(size.y):
		for x in range(16):land[y*size.x+x]=0
	var weather:=Model.build_fields(height,land,size,{"spinup_steps":60,"surface_water":false})
	check(weather.sea_temperature_anomaly.size()==4,"seasonal marine boundaries remain available for consistent native SST diagnostics")
	var transient:=Model.steady_fields(height,land,size,{"spinup_steps":2,"weather_regime":1.})
	check(transient.sea_temperature_anomaly==weather.sea_temperature_anomaly,"a passing front does not instantly reset seasonal ocean heat")
	var winter:=0.;var summer:=0.
	for y in range(5,6):
		for x in range(16,18):winter+=weather.quarters[0][y*size.x+x];summer+=weather.quarters[2][y*size.x+x]
	check(winter>summer,"synthetic midlatitude western shore has winter storm maximum rather than summer wet maximum")
	var dry:=Model.build_fields(height,land,size,{"spinup_steps":12,"weather_ensemble":false,"rain_multiplier":0.})
	check(Array(dry.annual).max()==0. and Array(dry.annual_evaporation).max()==0. and Array(dry.annual_runoff).max()==0.,"zero rainfall control reaches atmosphere and finite-water feedback without a seeded reservoir")
	print("ATLAS_CLIMATE_V6 failures=",failures);quit(1 if failures else 0)
