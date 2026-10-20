extends RefCounted
## Reduced seasonal circulation, not a numerical weather prediction solver.
## Global rules only: no country masks, Hu-line or prescribed rainfall regions.
## Shared moisture replenishment/high-mountain rules originate in environment_v1.7.
const Transport = preload("res://scripts/core/rainfall_transport.gd")
const Temperature = preload("res://scripts/atlas/climate.gd")
const SurfaceWater = preload("res://scripts/atlas/surface_water.gd")
const VERSION := "seasonal_circulation_v6"
const REVISION := "thermal_monsoon_terrain_v2"
const SEASONS := [-.85,.4,.85,-.4] # Representative DJF / MAM / JJA / SON heating.
const SEA_SEASONS := [-.625,-.225,.625,.225] # Half-quarter thermal lag of the sea.
const STEP_KM := 160.
const RAIN_SCALE := 82000. # Global water-column calibration, not regional rain targets.
const PRECIPITATION_EFFICIENCY := .5 # Finite cloud-to-ground conversion per transport step.
const LAND_MIXING_KM := 1200. # Weak dry-air exchange; ET is water limited separately.
const LAKE_RECHARGE := .10 # Finite inland fetch; same saturation thermodynamics as the sea.

static func zeros(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n); return out

static func continental_land(land:PackedByteArray,size:Vector2i) -> PackedByteArray:
	# Basin-scale gyres and elevated mixed layers require a continental land
	# mass. Small maritime islands must not inherit either continental proxy.
	var large:=PackedByteArray();large.resize(land.size());var seen:=large.duplicate()
	var cell_area:=510100000./(size.x*size.y)*PI/2.
	for first in range(land.size()):
		if not land[first] or seen[first]:continue
		var cells:=PackedInt32Array([first]);seen[first]=1;var head:=0;var area:=0.
		while head<cells.size():
			var i:=cells[head];head+=1;var x:=i%size.x;var y:=floori(float(i)/size.x)
			area+=cell_area*cos(deg_to_rad(90.-(y+.5)/size.y*180.))
			for other in [y*size.x+posmod(x-1,size.x),y*size.x+(x+1)%size.x,maxi(0,y-1)*size.x+x,mini(size.y-1,y+1)*size.x+x]:
				if land[other] and not seen[other]:seen[other]=1;cells.append(other)
		if area>=5000000.:
			for i in cells:large[i]=1
	return large

static func blur(source: PackedFloat32Array,size: Vector2i,radius: int) -> PackedFloat32Array:
	var middle := zeros(source.size()); var result := middle.duplicate(); var inverse := 1./(2*radius+1)
	for y in range(size.y):
		var total := 0.
		for dx in range(-radius,radius+1): total += source[y*size.x+posmod(dx,size.x)]
		for x in range(size.x):
			middle[y*size.x+x] = total*inverse
			total += source[y*size.x+(x+radius+1)%size.x]-source[y*size.x+posmod(x-radius,size.x)]
	for x in range(size.x):
		var total := 0.
		for dy in range(-radius,radius+1): total += middle[clampi(dy,0,size.y-1)*size.x+x]
		for y in range(size.y):
			result[y*size.x+x] = total*inverse
			total += middle[mini(size.y-1,y+radius+1)*size.x+x]-middle[maxi(0,y-radius)*size.x+x]
	return result

static func weather_strength(latitude: float) -> float:
	return smoothstep(12.,25.,absf(latitude))*(1.-smoothstep(55.,70.,absf(latitude)))

static func subsidence(latitude: float,season: float) -> float:
	# Seasonal expansion of the Hadley high suppresses western-shore summer
	# rain; a perennial subtropical core remains dry as the ITCZ migrates.
	# https://www.noaa.gov/jetstream/global/global-atmospheric-circulations
	var summer := season*signf(latitude)
	return maxf(.6*exp(-pow((absf(latitude)-26.)/8.,2)),exp(-pow((absf(latitude)-(28.+9.*summer))/8.,2)))

static func western_exposure(land:PackedByteArray,size:Vector2i) -> PackedFloat32Array:
	var values:=zeros(land.size())
	for y in range(size.y):
		var km_per_pixel:=111.*360./size.x*maxf(.1,cos(deg_to_rad(90.-(y+.5)/size.y*180.)))
		for x in range(size.x):
			if not land[y*size.x+x]:continue
			var west:=0.;var east:=0.
			for k in range(1,7):
				var reach:=maxi(1,roundi(k*200./km_per_pixel))
				west+=1.-land[y*size.x+posmod(x-reach,size.x)]
				east+=1.-land[y*size.x+(x+reach)%size.x]
			values[y*size.x+x]=maxf(0.,west-east)/6.
	return values

static func air_temperature(latitude: float,elevation_m: float,season: float) -> float:
	return Temperature.piecewise(Temperature.TEMP,absf(latitude))-.0065*elevation_m+12.*season*sin(deg_to_rad(latitude))

static func marine_supply(temperature: float,latitude: float) -> Dictionary:
	# Magnus saturation pressure relative to 27 C. No artificial minimum
	# moisture reservoir in cold seas. Freezing is a seasonal proxy, not sea ice
	# observations; warm current anomalies can keep subpolar water open.
	var t := clampf(temperature,-60.,45.)
	var saturation := clampf(exp(17.67*(t/(t+243.5)-27./270.5)),0.,1.)
	var ice := smoothstep(55.,75.,absf(latitude))*(1.-smoothstep(-6.,-1.8,t))
	return {"saturation":saturation,"open_water":1.-ice}

static func steer_terrain(wind:Dictionary,elevation:PackedFloat32Array,size:Vector2i) -> Dictionary:
	# Project blocked upslope low-level flow onto the terrain contour. Keep
	# the existing along-barrier direction; do not invent a regional jet.
	var height:=blur(elevation,size,1);var u:PackedFloat32Array=wind.u.duplicate();var v:PackedFloat32Array=wind.v.duplicate()
	var ky:=111.*180./size.y
	for y in range(size.y):
		var kx:=111.*360./size.x*maxf(.1,cos(deg_to_rad(90.-(y+.5)/size.y*180.)))
		for x in range(size.x):
			var i:=y*size.x+x
			var gradient:=Vector2((height[y*size.x+(x+1)%size.x]-height[y*size.x+posmod(x-1,size.x)])/(2.*kx),(height[maxi(0,y-1)*size.x+x]-height[mini(size.y-1,y+1)*size.x+x])/(2.*ky))
			var normal:=gradient.normalized();var velocity:=Vector2(u[i],v[i]);var upslope:=maxf(0.,velocity.dot(normal))
			var blocked:=upslope*.4*smoothstep(250.,1500.,upslope*gradient.length()*STEP_KM)
			var tangent:=Vector2(-normal.y,normal.x);var along:=velocity.dot(tangent)
			velocity-=normal*blocked;velocity+=tangent*signf(along)*blocked*.6
			velocity=velocity.limit_length(2.5);u[i]=velocity.x;v[i]=velocity.y
	return {"u":u,"v":v}

static func coastal_transport(land:PackedByteArray,size:Vector2i,wind:Dictionary,water_types:PackedByteArray=PackedByteArray(),reach_degrees:float=2.) -> PackedFloat32Array:
	# Offshore Ekman transport is 90 degrees right of the wind in the north,
	# left in the south. A coastline normal comes only from source geometry.
	# This bounded mixed-layer proxy is not an ocean circulation solver.
	var coast:=zeros(land.size())
	for i in range(land.size()):coast[i]=land[i]
	coast=blur(coast,size,maxi(1,roundi(reach_degrees*size.x/360.)))
	var transport:=zeros(land.size())
	for y in range(size.y):
		var latitude:=90.-(y+.5)/size.y*180.;var cosine:=maxf(.1,cos(deg_to_rad(latitude)));var rotation:=.35*tanh(latitude/1.5)/maxf(.08,absf(sin(deg_to_rad(latitude))))
		for x in range(size.x):
			var i:=y*size.x+x
			if land[i] or (not water_types.is_empty() and water_types[i]!=1):continue
			var gradient:=Vector2((coast[y*size.x+(x+1)%size.x]-coast[y*size.x+posmod(x-1,size.x)])/cosine,2.*size.y/size.x*(coast[maxi(0,y-1)*size.x+x]-coast[mini(size.y-1,y+1)*size.x+x]))
			var offshore:=Vector2(wind.v[i],-wind.u[i])*rotation
			var export:=offshore.dot(-gradient.normalized())
			transport[i]=signf(export)*smoothstep(.2,1.2,absf(export))*smoothstep(0.,.4,coast[i])
	return transport

static func upwelling_anomaly(land:PackedByteArray,size:Vector2i,wind:Dictionary,water_types:PackedByteArray=PackedByteArray()) -> PackedFloat32Array:
	var transport:=coastal_transport(land,size,wind,water_types);var cooling:=zeros(land.size())
	for y in range(size.y):
		var latitude:=90.-(y+.5)/size.y*180.
		var thermal_response:=minf(8.,3.*sqrt(.35/maxf(.08,absf(sin(deg_to_rad(latitude))))))
		for x in range(size.x):
			var i:=y*size.x+x;cooling[i]=-thermal_response*maxf(0.,transport[i])
	return cooling

static func marine_boundary(base:PackedFloat32Array,land:PackedByteArray,size:Vector2i,wind:Dictionary,water_types:PackedByteArray=PackedByteArray(),continents:PackedByteArray=PackedByteArray()) -> PackedFloat32Array:
	var coast:=land if continents.is_empty() else continents
	var transport:=coastal_transport(coast,size,wind,water_types);var anomaly:=base.duplicate()
	var warm_transport:=coastal_transport(coast,size,wind,water_types,8.)
	for y in range(size.y):
		var latitude:=90.-(y+.5)/size.y*180.;var cooling:=minf(8.,3.*sqrt(.35/maxf(.08,absf(sin(deg_to_rad(latitude))))))
		for x in range(size.x):
			var i:=y*size.x+x
			if transport[i]>0.:anomaly[i]=minf(base[i],maxf(-6.,base[i]-cooling*transport[i]))
			if warm_transport[i]<0. and base[i]<0.:anomaly[i]=maxf(anomaly[i],base[i]*(1.+.85*warm_transport[i]))
			# The inherited cold eastern-basin gyre curve assumes equatorward
			# coastal winds. A poleward monsoon reverses that zonal Ekman
			# transport and imports warm surface water across the whole fetch.
			if base[i]<0.:
				var recharge:=.9*smoothstep(.1,.8,wind.v[i]*signf(latitude))*(1.-smoothstep(35.,45.,absf(latitude)))
				recharge=maxf(recharge,.9*smoothstep(.2,1.2,wind.u[i])*smoothstep(0.,.35,wind.v[i]*signf(latitude))*(1.-smoothstep(25.,40.,absf(latitude))))
				anomaly[i]=maxf(anomaly[i],base[i]*(1.-recharge))
	return anomaly

static func cloud_to_ground(flux:float,rain_scale:float) -> float:
	# Finite climatological cloud conversion: leave unprecipitated moisture
	# in the transported column, rather than clip the exported rainfall map.
	if rain_scale<=0. or flux*rain_scale<=8000.:return flux
	var excess:=flux*rain_scale-8000.
	return (8000.+excess/(1.+excess/8000.))/rain_scale

static func regional_plateau(elevation:PackedFloat32Array,land:PackedByteArray,size:Vector2i) -> PackedFloat32Array:
	var heights:=elevation.duplicate();var weights:=zeros(land.size());var radius:=maxi(1,roundi(6.*size.x/360.))
	for i in range(land.size()):heights[i]*=land[i];weights[i]=land[i]
	heights=blur(blur(heights,size,radius),size,radius);weights=blur(blur(weights,size,radius),size,radius)
	for i in range(land.size()):heights[i]=heights[i]/weights[i] if weights[i]>0. else 0.
	return heights

static func wind_fields(continent: PackedFloat32Array,size: Vector2i,season: float,weather_regime: float = 0.,meridional_sector: float = 1.,zonal_sector: float = 1.,elevation:PackedFloat32Array=PackedFloat32Array(),barrier_height:PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	var n := continent.size(); var u := zeros(n); var v := u.duplicate(); var heat := u.duplicate(); var itcz := u.duplicate(); var summer := u.duplicate()
	var dx := 360./size.x; var dy := 180./size.y
	for y in range(size.y):
		var lat := 90.-(y+.5)*dy; var cosine := cos(deg_to_rad(lat))
		for x in range(size.x):
			var i := y*size.x+x; summer[i] = season*signf(lat); itcz[i] = season*(3.+9.*continent[i])
			var d := lat-itcz[i]; var west := smoothstep(25,38,absf(d))*(1.-smoothstep(60,70,absf(d)))
			u[i] = -1.*(1.-west)+1.1*west; v[i] = signf(d)*(-.45*(1.-west)+.35*west)
			# A sign(latitude) heat jump made the equator a permanent artificial
			# pressure wall. Seasonal thermal forcing must cross it continuously.
			var plateau:=smoothstep(1000.,4000.,elevation[i]) if not elevation.is_empty() else 0.
			heat[i] = (2.*exp(-pow(lat/18.,2))+16.*season*tanh(lat/18.))*cosine*continent[i]*(1.+.7*plateau)
	# A regional pressure response must reach beyond the immediate shoreline:
	# nearby ocean air responds to the heated continental interior. Damped
	# geostrophic turning plus cross-isobar flow yields monsoon inflow without
	# prescribing an Asian/African rectangle or an observed pressure field.
	var pressure:=blur(blur(heat,size,maxi(1,roundi(10.*size.x/360.))),size,maxi(1,roundi(10.*size.x/360.)))
	for y in range(size.y):
		var lat := 90.-(y+.5)*dy; var cosine := maxf(.2,cos(deg_to_rad(lat))); var rotation := tanh(lat/20.)*.6
		var gain := 2.*exp(-pow((absf(lat)-24.)/20.,2))
		for x in range(size.x):
			var i := y*size.x+x
			var fu := (heat[y*size.x+(x+1)%size.x]-heat[y*size.x+posmod(x-1,size.x)])/(2.*dx*cosine)
			var fv := (heat[maxi(y-1,0)*size.x+x]-heat[mini(y+1,size.y-1)*size.x+x])/(2.*dy)
			u[i] += gain*(fu+rotation*fv); v[i] += gain*(fv-rotation*fu)
			var pu:float=(pressure[y*size.x+(x+1)%size.x]-pressure[y*size.x+posmod(x-1,size.x)])/(2.*dx*cosine)
			var pv:float=(pressure[maxi(y-1,0)*size.x+x]-pressure[mini(y+1,size.y-1)*size.x+x])/(2.*dy)
			var turning:=2.*tanh(lat/15.);var thermal_response:=3.*(1.-smoothstep(45.,65.,absf(lat)))*(1.-.9*continent[i])
			u[i]+=thermal_response*(.25*pu+turning*pv);v[i]+=thermal_response*(.25*pv-turning*pu)
			# Two moist frontal sectors sample departures from the seasonal mean.
			# Warm sectors move poleward; cold sectors move equatorward. This
			# permits lake/sea moisture to reach a mountain's north-facing coast.
			var storm := weather_strength(lat)*absf(weather_regime)*(1.-.6*season*signf(lat))
			u[i] += 3.*weather_regime*storm*zonal_sector; v[i] += 1.5*signf(lat)*storm*meridional_sector
			var speed := maxf(1.,Vector2(u[i],v[i]).length()/2.5); u[i] /= speed; v[i] /= speed
	if not elevation.is_empty():
		var steered:=steer_terrain({"u":u,"v":v},elevation if barrier_height.is_empty() else barrier_height,size);u=steered.u;v=steered.v
	var convergence := zeros(n);var ventilation:=zeros(n)
	for y in range(size.y):
		var cosine := maxf(.2,cos(deg_to_rad(90.-(y+.5)*dy)))
		for x in range(size.x):
			var i := y*size.x+x
			var divergence := (u[y*size.x+(x+1)%size.x]-u[y*size.x+posmod(x-1,size.x)])/(2.*dx*cosine)
			divergence += (v[maxi(y-1,0)*size.x+x]-v[mini(y+1,size.y-1)*size.x+x])/(2.*dy)
			convergence[i] = clampf(-divergence*8.,0,1)
			ventilation[i]=clampf(divergence*8.,0.,1.)
	return {"u":u,"v":v,"itcz":itcz,"summer":summer,"convergence":convergence,"ventilation":ventilation}

static func stencil(x: float,y: float,size: Vector2i) -> Array:
	x = fposmod(x,size.x); y = clampf(y,0,size.y-1)
	var xx := floori(x); var yy := floori(y); var tx := x-xx; var ty := y-yy
	return [yy*size.x+xx,yy*size.x+(xx+1)%size.x,mini(yy+1,size.y-1)*size.x+xx,mini(yy+1,size.y-1)*size.x+(xx+1)%size.x,tx,ty]

static func interpolated(source: PackedFloat32Array,indices: PackedInt32Array,tx: PackedFloat32Array,ty: PackedFloat32Array,i: int) -> float:
	return lerpf(lerpf(source[indices[4*i]],source[indices[4*i+1]],tx[i]),lerpf(source[indices[4*i+2]],source[indices[4*i+3]],tx[i]),ty[i])

static func marine_air_anomaly(sea_anomaly: PackedFloat32Array,land: PackedByteArray,indices: PackedInt32Array,tx: PackedFloat32Array,ty: PackedFloat32Array,elevation: PackedFloat32Array) -> PackedFloat32Array:
	# Cold marine boundary layers inhibit rain (fog is not rainfall). Carry the
	# anomaly with the wind; mix it away inland. A modest coastal rise must not
	# instantly erase the inversion and turn fog into heavy orographic rainfall.
	var cooling := zeros(land.size()); var next := cooling.duplicate()
	for i in range(land.size()):
		if not land[i]: cooling[i] = sea_anomaly[i]
	for iteration in range(32):
		for i in range(land.size()):
			if not land[i]: next[i] = sea_anomaly[i]; continue
			var above_layer := maxf(0.,elevation[i]-1800.)
			next[i] = interpolated(cooling,indices,tx,ty,i)*exp(-STEP_KM/900.-above_layer/2000.)
		var swap := cooling; cooling = next; next = swap
	return cooling

static func steady_fields(elevation_m: PackedFloat32Array,land: PackedByteArray,size: Vector2i,options: Dictionary = {}) -> Dictionary:
	var n := land.size(); var continent := zeros(n)
	# Explicit source classes avoid mistaking coarse, disconnected sea straits
	# for lakes. Without classes, legacy synthetic inputs treat water as ocean.
	var water_types := PackedByteArray(options.get("water_types",[]))
	assert(water_types.is_empty() or water_types.size()==n)
	var lowland_lakes := PackedByteArray(options.get("lowland_lakes",[]))
	assert(lowland_lakes.is_empty() or lowland_lakes.size()==n)
	var sea_anomaly := PackedFloat32Array(options.get("sea_temperature_anomaly",zeros(n)))
	for i in range(n): continent[i] = land[i]
	var radius := maxi(1,roundi(6.*size.x/360.)); continent = blur(blur(continent,size,radius),size,radius)
	var latitudes := zeros(size.y); var water_width := PackedByteArray(); water_width.resize(n*3)
	var ocean_mask := water_width.duplicate()
	var lowland_mask := water_width.duplicate()
	for y in range(size.y):
		latitudes[y] = 90.-(y+.5)/size.y*180.
		for x in range(size.x*3):
			var original := y*size.x+x%size.x
			water_width[y*size.x*3+x] = 1-land[original]
			ocean_mask[y*size.x*3+x] = 0 if not land[original] and (water_types.is_empty() or water_types[original]==1) else 1
			lowland_mask[y*size.x*3+x] = 0 if not lowland_lakes.is_empty() and lowland_lakes[original] else 1
	var offshore := Transport._sea_distance(water_width,Vector2i(size.x*3,size.y),6.,latitudes,true)
	var inland := Transport._sea_distance(ocean_mask,Vector2i(size.x*3,size.y),6.,latitudes,true)
	var basin_distance := Transport._sea_distance(lowland_mask,Vector2i(size.x*3,size.y),6.,latitudes,true)
	var humidities: Array = []; var quarters: Array = []; var winds: Array = []; var marine: Array = []; var annual := zeros(n); var peak := annual.duplicate(); var mean_u := annual.duplicate(); var mean_v := annual.duplicate()
	var context := {"water_types":water_types,"sea_anomaly":sea_anomaly,"continent":continent,"latitudes":latitudes,"offshore":offshore,"inland":inland,"basin_distance":basin_distance,"west_exposure":western_exposure(land,size),"regional_plateau":regional_plateau(elevation_m,land,size),"continental_land":continental_land(land,size),"barrier_height":PackedFloat32Array(options.get("barrier_elevation",elevation_m))}
	var results: Array = [null,null,null,null]
	if options.get("parallel",n>=4096):
		# Each task owns its output arrays; shared inputs are read-only. Join before
		# combining in the original quarter order to preserve float rounding.
		var mutex := Mutex.new()
		var task := WorkerThreadPool.add_group_task(func(q):
			var result := steady_quarter(q,elevation_m,land,size,options,context)
			mutex.lock(); results[q]=result; mutex.unlock(),4,mini(4,maxi(1,OS.get_processor_count()-1)),false,"Atlas seasonal climate")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for q in range(4): results[q]=steady_quarter(q,elevation_m,land,size,options,context)
	for q in range(4):
		var result: Dictionary=results[q]; var rain: PackedFloat32Array=result.rain; var wind: Dictionary=result.wind
		humidities.append(result.humidity); quarters.append(rain); winds.append(wind); marine.append(result.sea_temperature_anomaly)
		for i in range(n):
			annual[i] += rain[i]*.25; peak[i] = maxf(peak[i],rain[i]); mean_u[i] += wind.u[i]*.25; mean_v[i] += wind.v[i]*.25
	return {"continentality":continent,"humidity":humidities,"annual":annual,"seasonal":peak,"quarters":quarters,"winds":winds,"mean_u":mean_u,"mean_v":mean_v,"sea_temperature_anomaly":marine,
			"metadata":{"version":VERSION,"seasons":["DJF","MAM","JJA","SON"],"season_heating":SEASONS,"spinup_steps":int(options.get("spinup_steps",100)),"transport_step_km":STEP_KM,"water_width_km":120.,"rain_scale":RAIN_SCALE,"rain_multiplier":maxf(0.,float(options.get("rain_multiplier",1.))),"temperature_offset":float(options.get("temperature_offset",0.)),"rainfall_units":"estimated annual mm; quarterly fields are annualized rates","recycling_fraction":0.,"precipitation_efficiency":PRECIPITATION_EFFICIENCY,"observed_climate":false,"annual_combine":"arithmetic mean of four seasonal rates","cold_layer_inland_scale_km":900.,"cold_layer_height_m":1800.,"orographic_gain":.08,"rules":"seasonal ITCZ, geometry-dependent western-shore summer subsidence, winter frontal occupancy, continuous equatorial land heating, monsoon convergence, stability-limited uplift and advected signed marine temperature anomaly"}}

static func steady_quarter(q: int,elevation_m: PackedFloat32Array,land: PackedByteArray,size: Vector2i,options: Dictionary,context: Dictionary) -> Dictionary:
	var n := land.size()
	var water_types: PackedByteArray=context.water_types
	var sea_anomaly: PackedFloat32Array=context.sea_anomaly.duplicate()
	var continent: PackedFloat32Array=context.continent
	var latitudes: PackedFloat32Array=context.latitudes
	var offshore: PackedFloat32Array=context.offshore
	var inland: PackedFloat32Array=context.inland
	var basin_distance: PackedFloat32Array=context.basin_distance
	var west_exposure:PackedFloat32Array=context.west_exposure
	var plateau:PackedFloat32Array=context.regional_plateau
	var continents:PackedByteArray=context.continental_land
	var barrier_height:PackedFloat32Array=context.barrier_height
	var season: float = SEASONS[q]
	var rain_scale:=RAIN_SCALE*maxf(0.,float(options.get("rain_multiplier",1.)))
	var temperature_offset:=float(options.get("temperature_offset",0.))
	var regime: float = options.get("weather_regime",0.)
	var wind := wind_fields(continent,size,season,regime,float(options.get("meridional_sector",1.)),float(options.get("zonal_sector",1.)),elevation_m if options.get("terrain_wind",true) else PackedFloat32Array(),barrier_height)
	if options.get("wind_upwelling",true):
		# A transient frontal wind does not instantaneously reset seasonal SST.
		var ocean_wind:=wind if regime==0. else wind_fields(continent,size,season,0.,1.,1.,elevation_m if options.get("terrain_wind",true) else PackedFloat32Array(),barrier_height)
		sea_anomaly=marine_boundary(sea_anomaly,land,size,ocean_wind,water_types,continents)
	var indices := PackedInt32Array(); indices.resize(4*n); var tx := zeros(n); var ty := tx.duplicate()
	var capacity := tx.duplicate(); var fraction := tx.duplicate(); var monsoon := tx.duplicate(); var retention := tx.duplicate(); var sat := tx.duplicate(); var recharge := tx.duplicate(); var open_water := tx.duplicate(); var dry_mixing := tx.duplicate();var ascent_relief:=tx.duplicate();var frontal_rain:=tx.duplicate();var foehn:=tx.duplicate();var coastal_front_gain:=tx.duplicate()
	for y in range(size.y):
		var lat := latitudes[y]; var cosine := maxf(.05,cos(deg_to_rad(lat)))
		for x in range(size.x):
			var i := y*size.x+x
			var point := stencil(x-wind.u[i]*STEP_KM/(111.*360./size.x*cosine),y+wind.v[i]*STEP_KM/(111.*180./size.y),size)
			for j in range(4): indices[4*i+j] = point[j]
			tx[i] = point[4]; ty[i] = point[5]
			var up_elevation := interpolated(elevation_m,indices,tx,ty,i); var rise := maxf(0,elevation_m[i]-up_elevation)
			var up_barrier:=interpolated(barrier_height,indices,tx,ty,i)
			rise=maxf(rise,barrier_height[i]-up_barrier)
			foehn[i]=exp(-maxf(0.,up_barrier-barrier_height[i]-300.)/1000.)
			# Orographic ascent begins on the windward approach, not only in
			# the summit cell. Otherwise a narrow coastal plain receives no
			# mountain rain while the adjacent high cell receives all of it.
			var downwind := stencil(x+wind.u[i]*STEP_KM/(111.*360./size.x*cosine),y-wind.v[i]*STEP_KM/(111.*180./size.y),size)
			var ahead: float = lerpf(lerpf(elevation_m[downwind[0]],elevation_m[downwind[1]],downwind[4]),lerpf(elevation_m[downwind[2]],elevation_m[downwind[3]],downwind[4]),downwind[5])
			var lakes: Array = [0.,0.,0.,0.]
			if not water_types.is_empty():
				for j in range(4): lakes[j] = float(water_types[indices[4*i+j]]==2)
			var up_water: float = lerpf(lerpf(lakes[0],lakes[1],tx[i]),lerpf(lakes[2],lakes[3],tx[i]),ty[i])
			# Only directly marine/lake-fed approaches receive this coastal
			# lifting term; inland hills must not double monsoon rainfall.
			rise = maxf(rise,.75*up_water*maxf(0.,ahead-elevation_m[i]))
			var barrier := smoothstep(Transport.RAIN_BARRIER_START_KM*1000.,Transport.RAIN_BARRIER_FULL_KM*1000.,elevation_m[i])
			capacity[i] = exp(-elevation_m[i]/1000.*barrier*.8)
			var descending := exp(-pow((absf(lat)-(27.+2.*wind.summer[i]))/7.,2))
			descending=maxf(descending,.7*exp(-pow((absf(lat)-26.)/9.,2)))
			descending=maxf(descending,west_exposure[i]*subsidence(lat,season))
			var convective := exp(-pow((lat-wind.itcz[i])/12.,2))
			convective*=smoothstep(14.,26.,air_temperature(lat,elevation_m[i],season)+temperature_offset)
			# Midlatitude storm tracks migrate poleward in local summer,
			# alongside the westerly circulation, rather than equatorward.
			var fronts := exp(-pow((absf(lat)-(48.+7.*wind.summer[i]))/13.,2))
			# Rain-producing uplift also requires unstable air. Previously the
			# raw mountain term bypassed subtropical subsidence altogether.
			# Summer land-sea convergence can break subsidence (wet monsoon
			# coasts). Cold marine stability is applied independently below.
			var poleward := smoothstep(0.,.7,wind.v[i]*signf(lat))
			var front_latitude:=24.+16.*pow(maxf(0.,wind.summer[i]),2)*continent[i]
			var monsoon_band:=maxf(exp(-pow((absf(lat)-front_latitude)/12.,2)),exp(-pow((absf(lat)-20.)/10.,2)))
			var orographic_band:=maxf(monsoon_band,smoothstep(12.,20.,absf(lat))*(1.-smoothstep(30.,40.,absf(lat))))
			var resolved_ascent:=maxf(smoothstep(.45,.9,wind.convergence[i])*poleward*monsoon_band,smoothstep(250.,1000.,rise)*orographic_band)
			var monsoon_lift := clampf(1.5*maxf(0.,wind.summer[i])*sqrt(continent[i])*resolved_ascent,0.,1.)
			# Autumn's warm sea outlasts continental summer heating. Retain a
			# narrower eastern-shore rain front during monsoon withdrawal.
			var retreat:=smoothstep(0.,.225,SEA_SEASONS[q]*signf(lat))*smoothstep(0.,.4,-wind.summer[i])*(1.-west_exposure[i])
			coastal_front_gain[i]=2.75+1.75*retreat
			var frontal_band:=lerpf(exp(-pow((absf(lat)-front_latitude)/(16.-6.*retreat),2)),1.,west_exposure[i])
			var frontal_lift:=weather_strength(lat)*absf(regime)*smoothstep(.1,1.,wind.v[i]*signf(lat))*frontal_band*(1.+.35*retreat)
			ascent_relief[i]=clampf(maxf(monsoon_lift,frontal_lift),0.,1.)
			descending *= 1.-.9*ascent_relief[i]
			fraction[i] = (.02+.08*convective+.035*fronts*(1.-.5*wind.summer[i]))*(1.-.98*descending)+rise/1200.*.08*(1.-.8*descending*(1.-monsoon_lift))
			# A passing front replaces locally stable air. This lift still needs
			# advected humidity and is cooled by marine stability below.
			fraction[i] += .04*weather_strength(lat)*absf(regime)*(1.-.6*wind.summer[i]);frontal_rain[i]=.08*frontal_lift
			monsoon[i] = .18*pow(maxf(0,wind.summer[i]),2)*monsoon_band*continent[i]*wind.convergence[i]*poleward
			var ocean_km: float = inland[y*size.x*3+size.x+x]*20000.
			var basin_km: float = basin_distance[y*size.x*3+size.x+x]*20000.
			var basin_weight := (1.-smoothstep(600.,1000.,basin_km))*smoothstep(0.,500.,ocean_km-basin_km)
			# Temperate continental dry-air mixing does not suppress tropical
			# convection or the subtropical monsoon. Rising moist air condenses
			# before this mixing, preserving windward lake/sea mountain coasts.
			var temperate := smoothstep(30.,40.,absf(lat))*(1.-smoothstep(50.,55.,absf(lat)))
			var inland_mixing := basin_weight*smoothstep(200.,1000.,ocean_km)*temperate*(1.-smoothstep(200.,1000.,rise))*STEP_KM/float(options.get("land_mixing_km",LAND_MIXING_KM))
			dry_mixing[i] = exp(-inland_mixing)
			retention[i] = exp(-.005-.20*descending)
			# The old 27-.55*latitude proxy froze temperate open seas and was
			# inconsistent with the atlas's own ocean temperature baseline.
			var lake := not water_types.is_empty() and water_types[i]==2
			var thermal_amplitude := 24. if lake else 5.
			var sea_temperature: float = Temperature.piecewise(Temperature.TEMP,absf(lat))+thermal_amplitude*SEA_SEASONS[q]*sin(deg_to_rad(lat))+sea_anomaly[i]+temperature_offset
			var supply := marine_supply(sea_temperature,lat)
			sat[i] = supply.saturation; open_water[i] = supply.open_water
			if lake: open_water[i] *= smoothstep(-2.,1.,sea_temperature)
			# A ~100 km marine cell is an evaporation source; the legacy 320 km
			# width cutoff starved ocean channels and tropical coastal inflow.
			recharge[i] = (1.-exp(-STEP_KM/320.))*smoothstep(0,120.,offshore[y*size.x*3+size.x+x]*20000.)
			if not water_types.is_empty() and water_types[i]==2:
				recharge[i] *= LAKE_RECHARGE
	var cooling := marine_air_anomaly(sea_anomaly,land,indices,tx,ty,elevation_m)
	var lift_stability:=zeros(n)
	for i in range(n):
		var summer: float = SEASONS[q]*signf(latitudes[floori(float(i)/size.x)])
		lift_stability[i] = exp(.9*minf(0.,cooling[i])*(1.+1.25*maxf(0.,summer))*(1.-.85*ascent_relief[i]))
		# Divergence suppresses local ascent; it must not delete a parcel's
		# humidity before it can feed a downstream rainforest or convergence zone.
		lift_stability[i]*=exp(-3.*wind.ventilation[i]*(1.-smoothstep(20.,35.,absf(latitudes[floori(float(i)/size.x)]))))
		var ocean_km:float=inland[floori(float(i)/size.x)*size.x*3+size.x+i%size.x]*20000.
		# A shallow regional hill is not an elevated dry-air inversion. Require
		# a regional plateau, retaining its height difference above the lowland.
		var elevated_cap:=maxf(0.,plateau[i]-elevation_m[i])/1000.*smoothstep(300.,750.,plateau[i])*(1.-smoothstep(300.,1200.,ocean_km))*continents[i]
		lift_stability[i]*=exp(-4.3*elevated_cap*(1.-.9*ascent_relief[i]))
		lift_stability[i]*=foehn[i]
		var coastal_high:=west_exposure[i]*maxf(0.,summer)*exp(-pow((absf(latitudes[floori(float(i)/size.x)])-35.)/14.,2))
		lift_stability[i]*=exp(-3.*coastal_high*(1.-.9*ascent_relief[i]))
		# A warm maritime source can destabilize the summer continental high;
		# this follows advected SST rather than a prescribed monsoon region.
		fraction[i] += .05*maxf(0.,summer)*sqrt(continent[i])*smoothstep(.2,2.,cooling[i])
		frontal_rain[i]*=1.+coastal_front_gain[i]*smoothstep(.1,1.,cooling[i])
	var humidity := zeros(n); var next := humidity.duplicate(); var rain := humidity.duplicate()
	var land_evaporation := PackedFloat32Array(options.get("land_evaporation",[])[q]) if options.has("land_evaporation") else zeros(n)
	if options.has("initial_humidity"): humidity = options.initial_humidity[q].duplicate()
	else:
		for i in range(n):
			var ocean := not land[i] and (water_types.is_empty() or water_types[i]==1)
			humidity[i] = sat[i]*open_water[i] if ocean else 0.
	var steps: int = options.get("spinup_steps",100)
	var sample_steps := clampi(int(options.get("sample_steps",1)),1,steps)
	var sampled := zeros(n)
	for iteration in range(steps):
		for i in range(n):
			var incoming := interpolated(humidity,indices,tx,ty,i)*.96+humidity[i]*.04
			if not land[i]: next[i] = incoming+(sat[i]-incoming)*recharge[i]*open_water[i]; continue
			incoming += land_evaporation[i]*4./maxf(1.,rain_scale)
			# Moist maritime air entrains less dry continental air than an
			# already depleted parcel. Do not turn warm-ocean-fed plains into
			# deserts merely because their nearest coast is far away.
			incoming *= pow(dry_mixing[i],1.-.9*smoothstep(.15,.4,incoming))
			var condensation := maxf(0,incoming-capacity[i])
			var precip_fraction := clampf(fraction[i]+frontal_rain[i]*smoothstep(.1,.3,incoming)+monsoon[i]*smoothstep(.20,.55,incoming),0,.65)
			# Apply stability to all uplift, including high-terrain condensation.
			# Previously that term bypassed the marine inversion entirely.
			rain[i] = (condensation+(incoming-condensation)*precip_fraction)*PRECIPITATION_EFFICIENCY*lift_stability[i]
			if rain[i]*rain_scale>8000.:rain[i]=cloud_to_ground(rain[i],rain_scale)
			if iteration>=steps-sample_steps: sampled[i] += rain[i]/sample_steps
			next[i] = (incoming-rain[i])*retention[i]
		var swap := humidity; humidity = next; next = swap
	rain = sampled
	for i in range(n): rain[i] *= rain_scale
	return {"rain":rain,"wind":wind,"humidity":humidity,"sea_temperature_anomaly":sea_anomaly}

static func circulation_fields(elevation_m: PackedFloat32Array,land: PackedByteArray,size: Vector2i,options: Dictionary = {}) -> Dictionary:
	# Average the precipitation produced by different weather states, rather
	# than precipitating one averaged wind. These operations are nonlinear.
	var mean_options := options.duplicate(); mean_options.weather_regime = 0.
	var mean := steady_fields(elevation_m,land,size,mean_options)
	if options.get("weather_ensemble",true)==false: mean.erase("humidity"); mean.erase("continentality"); return mean
	var west_options := options.duplicate(); west_options.weather_regime = -1.
	var east_options := options.duplicate(); east_options.weather_regime = 1.
	var cold_options := options.duplicate(); cold_options.weather_regime = 1.
	# Equatorward cold-front passages have a stronger meridional component
	# than the warm sector. Both remain short-lived and speed-limited.
	cold_options.meridional_sector = -3.
	cold_options.zonal_sector = -.3
	# A frontal sector lasts days, not the entire season. Start from that
	# season's background humidity, sample its later part, then reset. A
	# permanently reversed wind falsely irrigated distant interior deserts.
	for state in [west_options,east_options,cold_options]:
		state.initial_humidity = mean.humidity
		state.spinup_steps = 12; state.sample_steps = 6
	var west := steady_fields(elevation_m,land,size,west_options)
	var east := steady_fields(elevation_m,land,size,east_options)
	var cold := steady_fields(elevation_m,land,size,cold_options)
	var n := land.size(); var annual := zeros(n); var peak := annual.duplicate()
	var mean_u := annual.duplicate(); var mean_v := annual.duplicate(); var weights: Array = []
	for q in range(4):
		# Transition seasons contain both withdrawing/advancing monsoon and
		# frontal regimes. Solstices retain a stronger dominant circulation.
		var share := .10+.06*(1.-smoothstep(.4,.85,absf(SEASONS[q])))
		weights.append([1.-2.8*share,share,share,.8*share])
		for i in range(n):
			var latitude := 90.-(floori(float(i)/size.x)+.5)/size.y*180.
			# Cold continental anticyclones reduce the occurrence of moist
			# frontal sectors; this is not a mask prescribing regional rainfall.
			var cold_continent: float = mean.continentality[i]*(1.-smoothstep(0.,12.,air_temperature(latitude,elevation_m[i],SEASONS[q])+float(options.get("temperature_offset",0.))))
			var local_share: float = share*(1.-.7*cold_continent)*(1.-.45*SEASONS[q]*signf(latitude))
			var cold_share := .8*local_share
			mean.quarters[q][i] = mean.quarters[q][i]*(1.-2.*local_share-cold_share)+(west.quarters[q][i]+east.quarters[q][i])*local_share+cold.quarters[q][i]*cold_share
			for component in ["u","v"]:
				mean.winds[q][component][i] = mean.winds[q][component][i]*(1.-2.*local_share-cold_share)+(west.winds[q][component][i]+east.winds[q][component][i])*local_share+cold.winds[q][component][i]*cold_share
			annual[i] += mean.quarters[q][i]*.25; peak[i] = maxf(peak[i],mean.quarters[q][i])
			mean_u[i] += mean.winds[q].u[i]*.25; mean_v[i] += mean.winds[q].v[i]*.25
	mean.annual = annual; mean.seasonal = peak; mean.mean_u = mean_u; mean.mean_v = mean_v
	mean.metadata.weather_regimes = ["seasonal_mean","westward_poleward_warm_sector","eastward_poleward_warm_sector","equatorward_cold_sector"]
	mean.metadata.base_weather_weights = weights; mean.metadata.frontal_extra_lift = .04
	mean.metadata.cold_sector_meridional_multiplier = -3.
	mean.metadata.cold_sector_zonal_multiplier = -.3
	mean.metadata.cold_continent_weather_occupancy = "up to 70 percent fewer moist frontal sectors; local weights normalized"
	mean.metadata.marine_supply = "Magnus saturation relative to 27 C, without a humidity floor"
	mean.metadata.sea_ice = "temperature/latitude seasonal open-water proxy; no observed sea ice"
	mean.metadata.sea_temperature_heating = SEA_SEASONS; mean.metadata.frontal_transport_steps = 12; mean.metadata.frontal_sample_steps = 6
	mean.metadata.seasonal_weather_occupancy = "winter frontal occupancy enhanced; summer reduced, all local weights normalized"
	mean.metadata.inland_water_recharge_multiplier = LAKE_RECHARGE
	mean.metadata.lake_temperature_seasonal_amplitude = 24.
	mean.metadata.lake_freezing_proxy_C = [-2.,1.]
	mean.metadata.land_dry_air_mixing_km = float(options.get("land_mixing_km",LAND_MIXING_KM))
	mean.metadata.moist_parcel_mixing_relief = {"humidity_range":[.15,.4],"maximum_relief":.9}
	mean.metadata.inland_mixing_transition_km = [200.,1000.]
	mean.metadata.inland_mixing_latitude_band = [30.,40.,50.,55.]
	mean.metadata.lowland_basin_mixing = "DEM-inferred closed below-sea-level lake basin; 600-1000 km taper, only where nearer than the ocean"
	mean.metadata.windward_mixing_relief_m = [200.,1000.]
	mean.metadata.windward_approach_lift = {"distance_km":STEP_KM,"fraction_of_downwind_rise":.75,"source":"upwind inland-lake fraction only"}
	mean.metadata.water_classes = "explicit 0 land / 1 ocean / 2 inland lake; no region masks"
	mean.erase("humidity"); mean.erase("continentality")
	return mean

static func build_fields(elevation_m: PackedFloat32Array,land: PackedByteArray,size:Vector2i,options:Dictionary={}) -> Dictionary:
	var result:=circulation_fields(elevation_m,land,size,options)
	if not options.get("surface_water",true):return result
	var passes:=clampi(int(options.get("land_coupling_passes",1)),1,3)
	for pass_index in range(passes):
		var antecedent:=SurfaceWater.fields(elevation_m,land,size,result.quarters,float(options.get("temperature_offset",0.)))
		var coupled_options:=options.duplicate();coupled_options.land_evaporation=antecedent.surface_evaporation
		result=circulation_fields(elevation_m,land,size,coupled_options)
		result.atmospheric_surface_evaporation=antecedent.surface_evaporation
	result.merge(SurfaceWater.fields(elevation_m,land,size,result.quarters,float(options.get("temperature_offset",0.))),true)
	result.metadata.land_surface=SurfaceWater.VERSION
	result.metadata.revision=REVISION
	result.metadata.thermal_low={"regional_blur_degrees":10.,"plateau_heating_gain":.7,"ocean_response":3.,"continental_friction":.9}
	result.metadata.coastal_ocean="seasonal background winds drive bounded Ekman upwelling/downwelling; static cold gyres relax under poleward monsoon flow; no observed SST"
	result.metadata.continental_area_min_km2=5000000.
	result.metadata.terrain_wind="upslope normal damping and along-contour steering; optional sub-grid DEM barrier envelope"
	result.metadata.terrain_wind_enabled=options.get("terrain_wind",true)
	result.metadata.wind_upwelling_enabled=options.get("wind_upwelling",true)
	result.metadata.lowland_stability="cool air below regional plateau, coastal inversion, divergence and leeward descent inhibit uplift without deleting column humidity"
	result.metadata.monsoon_front="tropical band plus land-heating-driven poleward subtropical front; warm-sea withdrawal front contracts in autumn"
	result.metadata.cloud_conversion={"soft_limit_start_annualized_mm":8000.,"asymptote_annualized_mm":16000.,"unconverted_moisture":"retained for transport before output"}
	result.metadata.recycling_fraction=0.
	result.metadata.land_coupling_passes=passes
	result.metadata.recycling="finite-water predictor/corrector; prescribed quarterly ET from preceding climatology, not instantaneous rainfall multiplication"
	return result


