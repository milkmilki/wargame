extends RefCounted
## Rainfed settlement potential; estimated seasons, not observed population.
## FAO-56 Hargreaves radiation/temperature ETo with assumed diurnal range,
## a cyclic 150 mm soil bucket and joint thermal/moisture growing seasons.
const VERSION := "climate_capacity_v3"
const DAYS := [15.,105.,196.,288.]
const SOIL_STORAGE_MM := 150.
const METADATA := {"version":VERSION,"evaporation":"FAO-56 Hargreaves; estimated 8-14 C diurnal range","soil_storage_mm":SOIL_STORAGE_MM,"seasonal_temperature_amplitude_C":12.,"rain_distribution":"uniform monthly within each quarter","soil_spinup_years":2,"rainfed_only":true,"observed_temperature_range":false,"observed_soils":false}

static func thermal_factor(temperature: float) -> float:
	return smoothstep(4.,12.,temperature)*(1.-.9*smoothstep(26.,36.,temperature))*(1.-smoothstep(38.,42.,temperature))

static func potential_evaporation(temperature: float,latitude: float,quarter: int,diurnal_range: float = 10.) -> float:
	# Extraterrestrial radiation in MJ/m2/day, then 0.408 converts to mm/day.
	var day: float = DAYS[quarter]; var phi := deg_to_rad(clampf(latitude,-89.9,89.9))
	var inverse_distance := 1.+.033*cos(TAU*day/365.)
	var declination := .409*sin(TAU*day/365.-1.39)
	var sunset := acos(clampf(-tan(phi)*tan(declination),-1.,1.))
	var radiation := maxf(0.,24.*60./PI*.082*inverse_distance*(sunset*sin(phi)*sin(declination)+cos(phi)*cos(declination)*sin(sunset)))
	return .0023*maxf(0.,temperature+17.8)*sqrt(maxf(0.,diurnal_range))*.408*radiation*365.25/4.

static func seasonal_suitability(temperatures: PackedFloat32Array,quarter_mm: PackedFloat32Array,latitude: float) -> Dictionary:
	var pet := PackedFloat32Array(); pet.resize(4); var thermal := pet.duplicate()
	var annual := 0.; var annual_pet := 0.; var growing_pet := 0.; var growing_rain := 0.
	for q in range(4):
		var rain := maxf(0.,quarter_mm[q]); annual += rain
		# Cloudy wet seasons have smaller daily temperature swings. This is a
		# proxy, not measured Tmin/Tmax or a calibrated Penman-Monteith model.
		pet[q] = potential_evaporation(temperatures[q],latitude,q,14.-6.*smoothstep(40.,300.,rain))
		thermal[q] = thermal_factor(temperatures[q]); annual_pet += pet[q]
		growing_pet += pet[q]*thermal[q]; growing_rain += rain*thermal[q]
	var storage := 0.; var supported := 0.; var longest := 0; var run := 0
	# Two spin-up years remove arbitrary initial soil moisture. Monthly steps
	# spread each quarter's total uniformly; overflow drains, not stored forever.
	for month in range(48):
		var q := (month%12)/3; var rain := maxf(0.,quarter_mm[q])/3.; var demand := pet[q]/3.
		var available := storage+rain
		var water_factor := clampf(available/maxf(1.,demand),0.,1.)
		storage = clampf(available-demand,0.,SOIL_STORAGE_MM)
		if month>=24:
			var growth := thermal[q]*water_factor
			run = run+1 if growth>=.45 else 0; longest = maxi(longest,mini(12,run))
			if month>=36: supported += growth
	var aridity := annual/maxf(1.,annual_pet)
	var dry_limit := smoothstep(.12,.65,aridity)
	var wet_ratio := growing_rain/maxf(1.,growing_pet)
	var wet_limit := 1.-.7*smoothstep(1.4,3.5,wet_ratio)
	var season_length := smoothstep(1.5,5.,float(longest))
	var growing_support := clampf(supported/6.,0.,1.)
	var factor := clampf(dry_limit*wet_limit*season_length*growing_support,0.,1.)
	return {"factor":factor,"annual_pet":annual_pet,"aridity":aridity,"growing_months":longest,"wetness_factor":wet_limit}

static func farming_potential(temperature: float,annual_mm: float,warm_quarter_mm: float) -> float:
	# Scalar diagnostic helper; the runtime uses all four seasonal totals below.
	var rain := PackedFloat32Array(); rain.resize(4); rain.fill(maxf(0.,annual_mm)/4.)
	if warm_quarter_mm>annual_mm*.25:
		rain[0] = minf(maxf(0.,annual_mm),warm_quarter_mm)
		for q in range(1,4): rain[q] = maxf(0.,annual_mm-rain[0])/3.
	var temperatures := PackedFloat32Array(); temperatures.resize(4); temperatures.fill(temperature)
	return 110.*seasonal_suitability(temperatures,rain,25.).factor

static func seed_radius(suitability: float) -> float:
	return clampf(pow(13./(suitability+1.),.65),.55,2.3)

static func fields(mesh: Dictionary,env: Dictionary) -> Dictionary:
	var result := PackedFloat32Array(); result.resize(mesh.n)
	var factor := result.duplicate(); var pet := result.duplicate(); var aridity := result.duplicate(); var months := result.duplicate()
	var quarters: Array = env.get("quarter_precipitation",[])
	for i in range(mesh.n):
		if env.water[i]: continue
		var lat: float = 90.-mesh.y[i]/1024.*180.
		var temperatures := PackedFloat32Array(); temperatures.resize(4); var rain := temperatures.duplicate()
		for q in range(4):
			var heating: float = [-.85,.4,.85,-.4][q]*signf(lat)
			temperatures[q] = env.temperature[i]+12.*heating*absf(sin(deg_to_rad(lat)))
			rain[q] = quarters[q][i]*.25 if quarters.size()==4 else env.precipitation[i]*.25
		var climate := seasonal_suitability(temperatures,rain,lat)
		factor[i] = climate.factor; result[i] = 110.*factor[i]; pet[i] = climate.annual_pet; aridity[i] = climate.aridity; months[i] = climate.growing_months
	return {"agricultural_potential":result,"climate_suitability":factor,"potential_evaporation":pet,"aridity_index":aridity,"growing_months":months}

static func potentials(mesh: Dictionary,env: Dictionary) -> PackedFloat32Array:
	return fields(mesh,env).agricultural_potential
