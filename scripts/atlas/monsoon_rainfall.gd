extends RefCounted
## Adapt the game's shared environment_v1.7 rainfall transport to the globe.
## The old rainfall is dimensionless effective moisture, not observed annual mm.
## MM_PER_UNIT is an explicit global conversion for civ-atlas biome thresholds.
const Transport = preload("res://scripts/core/rainfall_transport.gd")
const Earth = preload("res://scripts/atlas/earth_surface.gd")
const VERSION := "legacy_monsoon_global_v1"
const GRID := Vector2i(720,360)
const REFERENCE_KM := 4000.
const MM_PER_UNIT := 2000.

static func build(surface: Dictionary,mesh: Dictionary,rain_multiplier: float = 1.) -> Dictionary:
	var count := GRID.x*GRID.y; var land := PackedByteArray(); land.resize(count)
	var heights := PackedFloat32Array(); heights.resize(count); var latitudes := PackedFloat32Array(); latitudes.resize(GRID.y)
	for y in range(GRID.y):
		var lat := 90.-(y+.5)/GRID.y*180.; latitudes[y] = lat
		for x in range(GRID.x):
			var cell := y*GRID.x+x; var lon := (x+.5)/GRID.x*360.-180.
			land[cell] = 1 if Earth.water_at(surface,lon,lat)==0 else 0
			heights[cell] = maxf(0,Earth.elevation_at(surface,lon,lat))/(Transport.ELEVATION_KM*1000.)
	var fields := Transport.build_fields(heights,land,GRID,latitudes,2.,{"wrap_x":true,"latitude_distance":true,"distance_scale":20000./REFERENCE_KM})
	var rainfall := PackedFloat32Array(); rainfall.resize(mesh.n); var annual := rainfall.duplicate(); var seasonal := rainfall.duplicate()
	for cell in range(mesh.n):
		var position := Vector2(mesh.x[cell]/2048.*GRID.x-.5,mesh.y[cell]/1024.*GRID.y-.5)
		annual[cell] = sample_land(fields.annual,land,position)*MM_PER_UNIT*rain_multiplier
		seasonal[cell] = sample_land(fields.seasonal,land,position)*MM_PER_UNIT*rain_multiplier
		# Combine after interpolation so diagnostic components explain precisely
		# the moisture used by biomes and habitat at this sphere cell.
		rainfall[cell] = maxf(annual[cell],seasonal[cell])
	return {"precipitation":rainfall,"annual_precipitation":annual,"seasonal_precipitation":seasonal,
		"metadata":{"version":VERSION,"source":"SettlementEnvironment environment_v1.7","grid":[GRID.x,GRID.y],"distance_reference_km":REFERENCE_KM,"mm_per_effective_unit":MM_PER_UNIT,"wrap_x":true,"horizontal_spinup_cycles":3,"seasonal_combine":"max(annual,seasonal)","observed_climate":false}}

static func sample_land(values: PackedFloat32Array,land: PackedByteArray,position: Vector2,size: Vector2i = GRID) -> float:
	var x := floori(position.x); var fy := clampf(position.y,0,size.y-1); var y := floori(fy)
	var tx := position.x-x; var ty := fy-y; var numerator := 0.; var denominator := 0.
	for dy in range(2):
		for dx in range(2):
			var cell := mini(y+dy,size.y-1)*size.x+posmod(x+dx,size.x)
			if not land[cell]: continue
			var weight := (tx if dx else 1-tx)*(ty if dy else 1-ty)
			numerator += values[cell]*weight; denominator += weight
	if denominator>1e-8: return numerator/denominator
	# Small islands can disappear in the coarse climate grid. Query nearby land
	# rather than blend its rainfall with the ocean's zero display samples.
	var distance := INF; var value := 0.
	for dy in range(-3,4):
		for dx in range(-3,4):
			var yy := y+dy
			if yy<0 or yy>=size.y: continue
			var cell := yy*size.x+posmod(x+dx,size.x); var d := Vector2(dx-tx,dy-ty).length_squared()
			if land[cell] and d<distance: distance = d; value = values[cell]
	return value
