extends RefCounted
## Earth adapter for native reduced seasonal circulation. No observed rain input.
const Model = preload("res://scripts/atlas/seasonal_circulation.gd")
const LegacyModel = preload("res://scripts/atlas/seasonal_circulation_v2.gd")
const FrozenModel = preload("res://scripts/atlas/seasonal_circulation_v4.gd")
const PreviousModel = preload("res://scripts/atlas/seasonal_circulation_v3.gd")
const Earth = preload("res://scripts/atlas/earth_surface.gd")
const Sample = preload("res://scripts/atlas/monsoon_rainfall.gd")
const VERSION := Model.VERSION
const GRID := Vector2i(360,180)
const CURRENT_GRID := Vector2i(360,180)

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

static func build(surface: Dictionary,mesh: Dictionary,rain_multiplier: float = 1.,currents: Dictionary = {},water: PackedByteArray = PackedByteArray(),model_version: String = VERSION) -> Dictionary:
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
		if model_version==VERSION: options.lowland_lakes = lowland_lake_mask(water_types,raw_height,size)
		if not currents.is_empty(): options.sea_temperature_anomaly = sea_anomaly_grid(mesh,water,currents.sst,size)
		if model_version==FrozenModel.VERSION: fields = FrozenModel.build_fields(heights,land,size,options)
		elif model_version==PreviousModel.VERSION: fields = PreviousModel.build_fields(heights,land,size,options)
		else: fields = Model.build_fields(heights,land,size,options)
	var annual := Model.zeros(mesh.n); var peak := annual.duplicate(); var u := annual.duplicate(); var v := annual.duplicate()
	var quarters: Array = []; var winds: Array = []
	for q in range(4): quarters.append(Model.zeros(mesh.n)); winds.append({"u":Model.zeros(mesh.n),"v":Model.zeros(mesh.n)})
	for cell in range(mesh.n):
		var position := Vector2(mesh.x[cell]/2048.*size.x-.5,mesh.y[cell]/1024.*size.y-.5)
		var point := Model.stencil(position.x,position.y,size)
		for q in range(4):
			quarters[q][cell] = Sample.sample_land(fields.quarters[q],land,position,size)*rain_multiplier
			annual[cell] += quarters[q][cell]*.25; peak[cell] = maxf(peak[cell],quarters[q][cell])
			winds[q].u[cell] = sample_any(fields.winds[q].u,point); winds[q].v[cell] = sample_any(fields.winds[q].v,point)
			u[cell] += winds[q].u[cell]*.25; v[cell] += winds[q].v[cell]*.25
	var metadata: Dictionary = fields.metadata.duplicate(); metadata.grid = [size.x,size.y]
	# SphereGeometry uses east/south components. Meteorological seasonal v is
	# northward, so invert it at the existing atlas/sea-ice interface only.
	var south := v.duplicate()
	for cell in range(mesh.n): south[cell] = -v[cell]
	metadata.wind_coordinates = {"seasonal_u":"east","seasonal_v":"north","windX":"east","windY":"south"}
	return {"precipitation":annual,"annual_precipitation":annual,"seasonal_precipitation":peak,"quarter_precipitation":quarters,"seasonal_winds":winds,"windX":u,"windY":south,"metadata":metadata}

static func sample_any(values: PackedFloat32Array,point: Array) -> float:
	return lerpf(lerpf(values[point[0]],values[point[1]],point[4]),lerpf(values[point[2]],values[point[3]],point[4]),point[5])
