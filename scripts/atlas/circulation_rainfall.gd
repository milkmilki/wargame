extends RefCounted
## Earth adapter for native reduced seasonal circulation. No observed rain input.
const Model = preload("res://scripts/atlas/seasonal_circulation.gd")
const LegacyModel = preload("res://scripts/atlas/seasonal_circulation_v2.gd")
const FrozenModel = preload("res://scripts/atlas/seasonal_circulation_v4.gd")
const PreviousModel = preload("res://scripts/atlas/seasonal_circulation_v3.gd")
const V5Model = preload("res://scripts/atlas/seasonal_circulation_v5.gd")
const Currents = preload("res://scripts/atlas/currents.gd")
const Earth = preload("res://scripts/atlas/earth_surface.gd")
const Sample = preload("res://scripts/atlas/monsoon_rainfall.gd")
const VERSION := Model.VERSION
const GRID := Vector2i(360,180)
const CURRENT_GRID := Vector2i(360,180)

static func orographic_barriers(surface:Dictionary,size:Vector2i=CURRENT_GRID) -> PackedFloat32Array:
	# Preserve sub-grid ridges without raising the ground used for temperature
	# or changing the source water classes. The DEM itself remains authoritative.
	var barriers:=Model.zeros(size.x*size.y)
	for y in range(size.y):
		for x in range(size.x):
			var lon:=(x+.5)/size.x*360.-180.;var lat:=90.-(y+.5)/size.y*180.
			var ground:=maxf(0.,Earth.elevation_at(surface,lon,lat));var peak:=ground
			for dy in [-.33,0.,.33]:
				for dx in [-.33,0.,.33]:peak=maxf(peak,Earth.elevation_at(surface,lon+dx*360./size.x,clampf(lat+dy*180./size.y,-90.,90.)))
			barriers[y*size.x+x]=ground+.6*(peak-ground)
	return barriers

static func marine_anomaly(types:PackedByteArray,size:Vector2i) -> PackedFloat32Array:
	# Complete source cells keep opposite shoreline vertices from cancelling
	# basin width, and do not overweight tiny coastal support cells. Reuse the
	# existing latitude/gyre proxy; this is not observed SST or a region mask.
	var n:=types.size();var west:=Model.zeros(n);var east:=west.duplicate()
	for y in range(size.y):
		var km:=111.*360./size.x*cos(deg_to_rad(90.-(y+.5)/size.y*180.))
		var last:=-1000000000
		for c in range(2*size.x):
			var x:=c%size.x
			if types[y*size.x+x]!=1:last=c
			if c>=size.x:west[y*size.x+x]=maxf(0.,c-last-.5)*km
		last=1000000000
		for c in range(2*size.x-1,-1,-1):
			var x:=c%size.x
			if types[y*size.x+x]!=1:last=c
			if c<size.x:east[y*size.x+x]=maxf(0.,last-c-.5)*km
	var numerator:=Model.zeros(n);var weights:=numerator.duplicate()
	for y in range(size.y):
		var latitude:=absf(90.-(y+.5)/size.y*180.)
		var pw:=Model.Temperature.piecewise(Currents.WEST,latitude);var pe:=Model.Temperature.piecewise(Currents.EAST,latitude)
		for x in range(size.x):
			var i:=y*size.x+x
			if types[i]!=1:continue
			var wide:=smoothstep(1000.,3500.,west[i]+east[i])
			numerator[i]=wide*(pw*Currents.reach(west[i],1500. if pw>0. else 1300.)+pe*Currents.reach(east[i],2200. if pe>0. else 1500.))
			weights[i]=1.
	numerator=Model.blur(numerator,size,1);weights=Model.blur(weights,size,1)
	for i in range(n):numerator[i]=numerator[i]/weights[i] if weights[i]>0. else 0.
	return numerator

static func lowland_lake_mask(types: PackedByteArray,raw_height: PackedFloat32Array,size: Vector2i) -> PackedByteArray:
	# A lake with below-sea-level shores cannot have a gravity outlet to the
	# ocean. Infer this closed lowland constraint from DEM/classes, not names.
	var found := PackedByteArray(); found.resize(types.size())
	var seen := found.duplicate()
	for first in range(types.size()):
		if types[first]!=2 or seen[first]: continue
		var queue := PackedInt32Array([first]); seen[first] = 1; var head := 0
		var below_sea := false; var marine_outlet := false
		while head<queue.size():
			var cell := queue[head]; head += 1
			var x := cell%size.x; var y := floori(float(cell)/size.x)
			for other in [y*size.x+posmod(x-1,size.x),y*size.x+(x+1)%size.x,maxi(0,y-1)*size.x+x,mini(size.y-1,y+1)*size.x+x]:
				if types[other]==1: marine_outlet = true
				elif types[other]==0 and raw_height[other]<-2.: below_sea = true
				elif types[other]==2 and not seen[other]: seen[other] = 1; queue.append(other)
		if below_sea and not marine_outlet:
			for cell in queue: found[cell] = 1
	return found

static func sea_anomaly_grid(mesh: Dictionary,water: PackedByteArray,anomaly: PackedFloat32Array,size: Vector2i = GRID) -> PackedFloat32Array:
	var numerator := Model.zeros(size.x*size.y); var weights := numerator.duplicate()
	for cell in range(mesh.n):
		if water[cell]!=1: continue
		var point := Model.stencil(mesh.x[cell]/2048.*size.x-.5,mesh.y[cell]/1024.*size.y-.5,size)
		var contribution := [(1.-point[4])*(1.-point[5]),point[4]*(1.-point[5]),(1.-point[4])*point[5],point[4]*point[5]]
		for k in range(4): numerator[point[k]] += anomaly[cell]*contribution[k]; weights[point[k]] += contribution[k]
	# Smooth numerator and denominator separately: missing ocean samples and
	# intervening land are not zero-temperature measurements. Longitude wraps.
	var radius := maxi(1,roundi(2.*size.x/360.))
	numerator = Model.blur(numerator,size,radius); weights = Model.blur(weights,size,radius)
	for i in range(numerator.size()): numerator[i] = numerator[i]/weights[i] if weights[i]>0. else 0.
	return numerator

static func build(surface: Dictionary,mesh: Dictionary,rain_multiplier: float = 1.,currents: Dictionary = {},water: PackedByteArray = PackedByteArray(),model_version: String = VERSION,temperature_offset:float=0.) -> Dictionary:
	var size := CURRENT_GRID if model_version==VERSION else GRID
	var heights := Model.zeros(size.x*size.y); var raw_height := heights.duplicate(); var land := PackedByteArray(); land.resize(heights.size()); var water_types := land.duplicate()
	for y in range(size.y):
		for x in range(size.x):
			var lon := (x+.5)/size.x*360.-180.; var lat := 90.-(y+.5)/size.y*180.; var i := y*size.x+x
			raw_height[i] = Earth.elevation_at(surface,lon,lat); heights[i] = maxf(0,raw_height[i]); water_types[i] = Earth.water_at(surface,lon,lat); land[i] = int(water_types[i]==0)
	var fields: Dictionary
	if model_version==LegacyModel.VERSION: fields = LegacyModel.build_fields(heights,land,size)
	else:
		var options := {"water_types":water_types}
		if model_version in [VERSION,V5Model.VERSION]: options.lowland_lakes = lowland_lake_mask(water_types,raw_height,size)
		if model_version==VERSION:
			options.sea_temperature_anomaly=marine_anomaly(water_types,size)
			options.barrier_elevation=orographic_barriers(surface,size)
			options.rain_multiplier=rain_multiplier;options.temperature_offset=temperature_offset
		elif not currents.is_empty(): options.sea_temperature_anomaly = sea_anomaly_grid(mesh,water,currents.sst,size)
		if model_version==FrozenModel.VERSION: fields = FrozenModel.build_fields(heights,land,size,options)
		elif model_version==PreviousModel.VERSION: fields = PreviousModel.build_fields(heights,land,size,options)
		elif model_version==V5Model.VERSION: fields = V5Model.build_fields(heights,land,size,options)
		else: fields = Model.build_fields(heights,land,size,options)
	var annual := Model.zeros(mesh.n); var peak := annual.duplicate(); var u := annual.duplicate(); var v := annual.duplicate()
	var quarters: Array = []; var winds: Array = []
	for q in range(4): quarters.append(Model.zeros(mesh.n)); winds.append({"u":Model.zeros(mesh.n),"v":Model.zeros(mesh.n)})
	var surface_fields:Dictionary={}
	for key in ["forest_cover","annual_evaporation","annual_runoff","surface_water_error"]:
		if fields.has(key):surface_fields[key]=Model.zeros(mesh.n)
	for key in ["soil_moisture","surface_evaporation","surface_runoff","surface_potential_evaporation"]:
		if fields.has(key):
			surface_fields[key]=[]
			for q in range(4):surface_fields[key].append(Model.zeros(mesh.n))
	var sample_multiplier:=1. if model_version==VERSION else rain_multiplier
	var mean_sea:=Model.zeros(size.x*size.y)
	if fields.has("sea_temperature_anomaly"):
		for q in range(4):
			for i in range(mean_sea.size()):mean_sea[i]+=.25*fields.sea_temperature_anomaly[q][i]
	var marine:=Model.zeros(mesh.n)
	for cell in range(mesh.n):
		var position := Vector2(mesh.x[cell]/2048.*size.x-.5,mesh.y[cell]/1024.*size.y-.5)
		var point := Model.stencil(position.x,position.y,size)
		if fields.has("sea_temperature_anomaly"):marine[cell]=sample_any(mean_sea,point)
		for q in range(4):
			quarters[q][cell] = Sample.sample_land(fields.quarters[q],land,position,size)*sample_multiplier
			annual[cell] += quarters[q][cell]*.25; peak[cell] = maxf(peak[cell],quarters[q][cell])
			winds[q].u[cell] = sample_any(fields.winds[q].u,point); winds[q].v[cell] = sample_any(fields.winds[q].v,point)
			u[cell] += winds[q].u[cell]*.25; v[cell] += winds[q].v[cell]*.25
		if not water.is_empty() and water[cell]!=0:continue
		for key in surface_fields:
			if surface_fields[key] is Array:
				for q in range(4):surface_fields[key][q][cell]=Sample.sample_land(fields[key][q],land,position,size)
			else:surface_fields[key][cell]=Sample.sample_land(fields[key],land,position,size)
	var metadata: Dictionary = fields.metadata.duplicate(); metadata.grid = [size.x,size.y]
	# SphereGeometry uses east/south components. Meteorological seasonal v is
	# northward, so invert it at the existing atlas/sea-ice interface only.
	var south := v.duplicate()
	for cell in range(mesh.n): south[cell] = -v[cell]
	metadata.wind_coordinates = {"seasonal_u":"east","seasonal_v":"north","windX":"east","windY":"south"}
	var result:={"precipitation":annual,"annual_precipitation":annual,"seasonal_precipitation":peak,"quarter_precipitation":quarters,"seasonal_winds":winds,"windX":u,"windY":south,"metadata":metadata}
	result.merge(surface_fields,true)
	if fields.has("sea_temperature_anomaly"):result.marine_temperature_anomaly=marine
	if fields.has("surface_water_metadata"):result.surface_water_metadata=fields.surface_water_metadata
	if model_version==VERSION:
		metadata.marine_boundary="complete source-grid basin/latitude proxy plus seasonal wind-driven Ekman response; displayed annual SST averages the same four atmospheric boundaries"
		metadata.orographic_barrier={"source":"3x3 DEM samples within each climate cell","offset_cell_fraction":.33,"peak_relief_fraction":.6,"changes_ground_height":false}
		metadata.rain_multiplier=rain_multiplier
	return result

static func sample_any(values: PackedFloat32Array,point: Array) -> float:
	return lerpf(lerpf(values[point[0]],values[point[1]],point[4]),lerpf(values[point[2]],values[point[3]],point[4]),point[5])
