extends RefCounted
## Four seasonal joint temperature/rainfall scores; a game suitability proxy.
## Hargreaves evaporation is retained for biome/diagnostic use, not city scoring.
const VERSION := "climate_capacity_v6"
const TWO_SEASON_CAP := 1.6
const DAYS := [15.,105.,196.,288.]
const METADATA := {"version":VERSION,"evaporation":"FAO-56 Hargreaves; biome diagnostics only","seasonal_temperature_amplitude_C":12.,"temperature_plateau_C":[10.,20.],"temperature_low_cutoff_C":0.,"temperature_hot_cutoff_C":28.,"quarter_rain_plateau_mm":[200.,800.],"quarter_rain_cutoffs_mm":[50.,1400.],"aggregation":"min(1, sum of best two joint seasonal scores / 1.6)","two_season_full_support_score":TWO_SEASON_CAP,"annual_penalty":false,"growing_months":"sum of four joint seasonal scores times three; equivalent suitable months, not capped food support","observed_soils":false,"observed_temperature_range":false}

static func thermal_factor(temperature: float) -> float:
	var cold := smoothstep(0.,10.,temperature)
	var hot := 1.-smoothstep(20.,28.,temperature)
	return cold*hot

static func rainfall_factor(quarter_mm: float) -> float:
	return smoothstep(50.,200.,quarter_mm)*(1.-smoothstep(800.,1400.,quarter_mm))

static func potential_evaporation(temperature: float,latitude: float,quarter: int,diurnal_range: float = 10.) -> float:
	# Extraterrestrial radiation in MJ/m2/day, then 0.408 converts to mm/day.
	var day: float = DAYS[quarter]; var phi := deg_to_rad(clampf(latitude,-89.9,89.9))
	var inverse_distance := 1.+.033*cos(TAU*day/365.)
	var declination := .409*sin(TAU*day/365.-1.39)
	var sunset := acos(clampf(-tan(phi)*tan(declination),-1.,1.))
	var radiation := maxf(0.,24.*60./PI*.082*inverse_distance*(sunset*sin(phi)*sin(declination)+cos(phi)*cos(declination)*sin(sunset)))
	return .0023*maxf(0.,temperature+17.8)*sqrt(maxf(0.,diurnal_range))*.408*radiation*365.25/4.

static func seasonal_suitability(temperatures: PackedFloat32Array,quarter_mm: PackedFloat32Array,latitude: float) -> Dictionary:
	var scores := PackedFloat32Array(); scores.resize(4)
	var annual := 0.; var annual_pet := 0.; var supported_months := 0.
	for q in range(4):
		var rain := maxf(0.,quarter_mm[q]); annual += rain
		annual_pet += potential_evaporation(temperatures[q],latitude,q,14.-6.*smoothstep(40.,300.,rain))
		scores[q] = thermal_factor(temperatures[q])*rainfall_factor(rain)
		supported_months += 3.*scores[q]
	var ranked := scores.duplicate(); ranked.sort()
	# Two productive quarters suffice for capped climate-based food support.
	# Other quarters neither add support nor subtract it. Their own extreme
	# heat/rainfall still reduces their joint scores through the curves above.
	var factor := minf(1.,(ranked[2]+ranked[3])/TWO_SEASON_CAP)
	var aridity := annual/maxf(1.,annual_pet)
	return {"factor":clampf(factor,0.,1.),"quarter_scores":scores,"annual_penalty":1.,"annual_pet":annual_pet,"aridity":aridity,"growing_months":supported_months}

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
