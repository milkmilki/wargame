extends RefCounted
## Reduced seasonal circulation, not a numerical weather prediction solver.
## Global rules only: no country masks, Hu-line or prescribed rainfall regions.
## Shared moisture replenishment/high-mountain rules originate in environment_v1.7.
const Transport = preload("res://scripts/core/rainfall_transport.gd")
const VERSION := "seasonal_circulation_v3"
const SEASONS := [-.85,.4,.85,-.4] # Representative DJF / MAM / JJA / SON heating.
const STEP_KM := 160.
const RAIN_SCALE := 70000. # Estimated annualized mm per per-step condensed moisture.
const RECYCLING := .25

static func zeros(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(n); return out

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

static func wind_fields(continent: PackedFloat32Array,size: Vector2i,season: float) -> Dictionary:
	var n := continent.size(); var u := zeros(n); var v := u.duplicate(); var heat := u.duplicate(); var itcz := u.duplicate(); var summer := u.duplicate()
	var dx := 360./size.x; var dy := 180./size.y
	for y in range(size.y):
		var lat := 90.-(y+.5)*dy; var cosine := cos(deg_to_rad(lat))
		for x in range(size.x):
			var i := y*size.x+x; summer[i] = season*signf(lat); itcz[i] = season*(3.+9.*continent[i])
			var d := lat-itcz[i]; var west := smoothstep(25,38,absf(d))*(1.-smoothstep(60,70,absf(d)))
			u[i] = -1.*(1.-west)+1.1*west; v[i] = signf(d)*(-.45*(1.-west)+.35*west)
			heat[i] = 16.*summer[i]*cosine*continent[i]
	for y in range(size.y):
		var lat := 90.-(y+.5)*dy; var cosine := maxf(.2,cos(deg_to_rad(lat))); var rotation := tanh(lat/20.)*.6
		var gain := 2.*exp(-pow((absf(lat)-24.)/20.,2))
		for x in range(size.x):
			var i := y*size.x+x
			var fu := (heat[y*size.x+(x+1)%size.x]-heat[y*size.x+posmod(x-1,size.x)])/(2.*dx*cosine)
			var fv := (heat[maxi(y-1,0)*size.x+x]-heat[mini(y+1,size.y-1)*size.x+x])/(2.*dy)
			u[i] += gain*(fu+rotation*fv); v[i] += gain*(fv-rotation*fu)
			var speed := maxf(1.,Vector2(u[i],v[i]).length()/2.5); u[i] /= speed; v[i] /= speed
	var convergence := zeros(n)
	for y in range(size.y):
		var cosine := maxf(.2,cos(deg_to_rad(90.-(y+.5)*dy)))
		for x in range(size.x):
			var i := y*size.x+x
			var divergence := (u[y*size.x+(x+1)%size.x]-u[y*size.x+posmod(x-1,size.x)])/(2.*dx*cosine)
			divergence += (v[maxi(y-1,0)*size.x+x]-v[mini(y+1,size.y-1)*size.x+x])/(2.*dy)
			convergence[i] = clampf(-divergence*8.,0,1)
	return {"u":u,"v":v,"itcz":itcz,"summer":summer,"convergence":convergence}

static func stencil(x: float,y: float,size: Vector2i) -> Array:
	x = fposmod(x,size.x); y = clampf(y,0,size.y-1)
	var xx := floori(x); var yy := floori(y); var tx := x-xx; var ty := y-yy
	return [yy*size.x+xx,yy*size.x+(xx+1)%size.x,mini(yy+1,size.y-1)*size.x+xx,mini(yy+1,size.y-1)*size.x+(xx+1)%size.x,tx,ty]

static func interpolated(source: PackedFloat32Array,indices: PackedInt32Array,tx: PackedFloat32Array,ty: PackedFloat32Array,i: int) -> float:
	return lerpf(lerpf(source[indices[4*i]],source[indices[4*i+1]],tx[i]),lerpf(source[indices[4*i+2]],source[indices[4*i+3]],tx[i]),ty[i])

static func marine_cooling(sea_anomaly: PackedFloat32Array,land: PackedByteArray,indices: PackedInt32Array,tx: PackedFloat32Array,ty: PackedFloat32Array,elevation: PackedFloat32Array) -> PackedFloat32Array:
	# Cold marine boundary layers inhibit rain (fog is not rainfall). Carry the
	# anomaly with the wind; mix it away inland. A modest coastal rise must not
	# instantly erase the inversion and turn fog into heavy orographic rainfall.
	var cooling := zeros(land.size()); var next := cooling.duplicate()
	for i in range(land.size()):
		if not land[i]: cooling[i] = minf(0.,sea_anomaly[i])
	for iteration in range(32):
		for i in range(land.size()):
			if not land[i]: next[i] = minf(0.,sea_anomaly[i]); continue
			var above_layer := maxf(0.,elevation[i]-1800.)
			next[i] = interpolated(cooling,indices,tx,ty,i)*exp(-STEP_KM/900.-above_layer/2000.)
		var swap := cooling; cooling = next; next = swap
	return cooling

static func build_fields(elevation_m: PackedFloat32Array,land: PackedByteArray,size: Vector2i,options: Dictionary = {}) -> Dictionary:
	var n := land.size(); var continent := zeros(n)
	var sea_anomaly := PackedFloat32Array(options.get("sea_temperature_anomaly",zeros(n)))
	for i in range(n): continent[i] = land[i]
	var radius := maxi(1,roundi(6.*size.x/360.)); continent = blur(blur(continent,size,radius),size,radius)
	var latitudes := zeros(size.y); var water_width := PackedByteArray(); water_width.resize(n*3)
	for y in range(size.y):
		latitudes[y] = 90.-(y+.5)/size.y*180.
		for x in range(size.x*3): water_width[y*size.x*3+x] = 1-land[y*size.x+x%size.x]
	var offshore := Transport._sea_distance(water_width,Vector2i(size.x*3,size.y),6.,latitudes,true)
	var quarters: Array = []; var winds: Array = []; var annual := zeros(n); var peak := annual.duplicate(); var mean_u := annual.duplicate(); var mean_v := annual.duplicate()
	for season in SEASONS:
		var wind := wind_fields(continent,size,season); winds.append(wind)
		var indices := PackedInt32Array(); indices.resize(4*n); var tx := zeros(n); var ty := tx.duplicate()
		var capacity := tx.duplicate(); var fraction := tx.duplicate(); var monsoon := tx.duplicate(); var retention := tx.duplicate(); var sat := tx.duplicate(); var recharge := tx.duplicate()
		for y in range(size.y):
			var lat := latitudes[y]; var cosine := maxf(.05,cos(deg_to_rad(lat)))
			for x in range(size.x):
				var i := y*size.x+x
				var point := stencil(x-wind.u[i]*STEP_KM/(111.*360./size.x*cosine),y+wind.v[i]*STEP_KM/(111.*180./size.y),size)
				for j in range(4): indices[4*i+j] = point[j]
				tx[i] = point[4]; ty[i] = point[5]
				var up_elevation := interpolated(elevation_m,indices,tx,ty,i); var rise := maxf(0,elevation_m[i]-up_elevation)
				var barrier := smoothstep(Transport.RAIN_BARRIER_START_KM*1000.,Transport.RAIN_BARRIER_FULL_KM*1000.,elevation_m[i])
				capacity[i] = exp(-elevation_m[i]/1000.*barrier*.8)
				var descending := exp(-pow((absf(lat)-(27.+2.*wind.summer[i]))/7.,2))
				var convective := exp(-pow((lat-wind.itcz[i])/9.,2))
				var fronts := exp(-pow((absf(lat)-(48.-5.*wind.summer[i]))/13.,2))
				# Rain-producing uplift also requires unstable air. Previously the
				# raw mountain term bypassed subtropical subsidence altogether.
				# Summer land-sea convergence can break subsidence (wet monsoon
				# coasts). Cold marine stability is applied independently below.
				var monsoon_lift := clampf(1.5*maxf(0.,wind.summer[i])*sqrt(continent[i])*smoothstep(.45,.9,wind.convergence[i]),0.,1.)
				fraction[i] = (.008+.12*convective+.035*fronts)*(1.-.98*descending)+rise/1200.*.16*(1.-.8*descending*(1.-monsoon_lift))
				monsoon[i] = .085*maxf(0,wind.summer[i])*exp(-pow((absf(lat)-24.)/12.,2))*continent[i]*wind.convergence[i]
				retention[i] = exp(-.005-.20*descending)
				var sea_temperature: float = 27.-.55*absf(lat)+5.*season*sin(deg_to_rad(lat))
				sat[i] = clampf((sea_temperature+12.)/38.*exp(.065*sea_anomaly[i]),.06,1.)
				# A ~100 km marine cell is an evaporation source; the legacy 320 km
				# width cutoff starved ocean channels and tropical coastal inflow.
				recharge[i] = (1.-exp(-STEP_KM/320.))*smoothstep(0,120.,offshore[y*size.x*3+size.x+x]*20000.)
		var cooling := marine_cooling(sea_anomaly,land,indices,tx,ty,elevation_m)
		for i in range(n):
			var stability := exp(.9*cooling[i])
			fraction[i] *= stability; monsoon[i] *= stability
		var humidity := zeros(n); var next := humidity.duplicate(); var rain := humidity.duplicate()
		for i in range(n): humidity[i] = sat[i] if not land[i] else 0.
		for iteration in range(int(options.get("spinup_steps",100))):
			for i in range(n):
				var incoming := interpolated(humidity,indices,tx,ty,i)*.96+humidity[i]*.04
				if not land[i]: next[i] = incoming+(sat[i]-incoming)*recharge[i]; continue
				var condensation := maxf(0,incoming-capacity[i])
				var precip_fraction := clampf(fraction[i]+monsoon[i]*smoothstep(.20,.55,incoming),0,.65)
				rain[i] = condensation+(incoming-condensation)*precip_fraction
				next[i] = (incoming-rain[i]+rain[i]*RECYCLING)*retention[i]
			var swap := humidity; humidity = next; next = swap
		for i in range(n):
			rain[i] *= RAIN_SCALE; annual[i] += rain[i]*.25; peak[i] = maxf(peak[i],rain[i]); mean_u[i] += wind.u[i]*.25; mean_v[i] += wind.v[i]*.25
		quarters.append(rain)
	return {"annual":annual,"seasonal":peak,"quarters":quarters,"winds":winds,"mean_u":mean_u,"mean_v":mean_v,
			"metadata":{"version":VERSION,"seasons":["DJF","MAM","JJA","SON"],"season_heating":SEASONS,"spinup_steps":int(options.get("spinup_steps",100)),"transport_step_km":STEP_KM,"water_width_km":120.,"rain_scale":RAIN_SCALE,"rainfall_units":"estimated annual mm; quarterly fields are annualized rates","recycling_fraction":RECYCLING,"observed_climate":false,"annual_combine":"arithmetic mean of four seasonal rates","cold_layer_inland_scale_km":900.,"cold_layer_height_m":1800.,"orographic_gain":.16,"rules":"seasonal ITCZ, subtropical dry-air exchange, westerlies, land-sea heating gradient, Coriolis deflection, stability/monsoon-limited mountain uplift, high-mountain rain shadow, SST moisture supply and advected cold marine inversion"}}



