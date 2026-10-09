extends RefCounted
## Climate-based agricultural potential for the preview; not real population.
## Existing terrain, slope, freshwater and city-threshold rules still apply.
const VERSION := "climate_capacity_v2"

static func farming_potential(temperature: float,annual_mm: float,warm_quarter_mm: float) -> float:
	var thermal := smoothstep(4.,12.,temperature)
	var water := smoothstep(180.,600.,annual_mm)*(.5+.5*smoothstep(80.,220.,warm_quarter_mm))
	var soil_climate := .75+.25*exp(-pow((temperature-18.)/10.,2))
	var excessive_wetness := 1.-.25*smoothstep(2200.,4000.,annual_mm)
	return 110.*thermal*water*soil_climate*excessive_wetness

static func seed_radius(suitability: float) -> float:
	return clampf(pow(13./(suitability+1.),.65),.55,2.3)

static func potentials(mesh: Dictionary,env: Dictionary) -> PackedFloat32Array:
	var result := PackedFloat32Array(); result.resize(mesh.n)
	var quarters: Array = env.get("quarter_precipitation",[])
	for i in range(mesh.n):
		if env.water[i]: continue
		var lat: float = 90.-mesh.y[i]/1024.*180.
		var warm_rain := 0.
		for q in range(quarters.size()):
			var heating: float = [-.85,.4,.85,-.4][q]*signf(lat)
			var t: float = env.temperature[i]+10.*heating*absf(sin(deg_to_rad(lat)))
			if t>=10.: warm_rain = maxf(warm_rain,quarters[q][i]*.25)
		result[i] = farming_potential(env.temperature[i],env.precipitation[i],warm_rain)
	return result
