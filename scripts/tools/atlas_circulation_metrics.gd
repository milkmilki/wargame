extends RefCounted
## Validation geography only. No runtime generator imports this module/mask.
const MASK := "res://tests/fixtures/atlas_china_study_mask.u8"
const ZONES := [["ChinaEast",105.,122.,22.,42.],["NorthChina",110.,122.,34.,42.],["SouthChina",105.,122.,22.,34.],["Europe",-10.,30.,36.,60.],["Congo",15.,30.,-5.,5.],["Sahara",-10.,30.,20.,30.],["Gobi",95.,110.,38.,47.],["India",70.,90.,10.,30.],["SouthernAfrica",10.,40.,-35.,-15.],["NamibiaWest",12.,20.,-30.,-17.],["Kalahari",20.,28.,-28.,-18.],["SoutheastAfrica",28.,40.,-25.,-10.],["Highveld",25.,31.,-30.,-24.]]

static func location(mesh: Dictionary,i: int) -> Vector2:
	return Vector2(mesh.x[i]/2048.*360.-180.,90.-mesh.y[i]/1024.*180.)

static func inside(p: Vector2,zone: Array) -> bool:
	return p.x>=zone[1] and p.x<zone[2] and p.y>=zone[3] and p.y<zone[4]

static func hu_side(p: Vector2,mask: PackedByteArray) -> String:
	var x := clampi(floori(p.x+180.),0,359); var y := clampi(floori(90.-p.y),0,179)
	if not mask[y*360+x]: return ""
	# Heihe / Tengchong comparison line, not a prescribed climate boundary.
	return "HuSE" if (p.x-98.5)/(127.49-98.5)>(p.y-25.02)/(50.25-25.02) else "HuNW"

static func summarize(data: Dictionary) -> Dictionary:
	var mesh: Dictionary = data.mesh; var env: Dictionary = data.environment; var mask := FileAccess.get_file_as_bytes(MASK)
	var output := {}
	var zones := ZONES.duplicate(); zones.append(["HuSE"]); zones.append(["HuNW"])
	for zone in zones:
		var name_value: String = zone[0]; var area := 0.; var rain := 0.; var suitability := 0.; var desert := 0.; var forest := 0.; var farmland := 0.; var cities := 0; var provinces := 0
		var pet := 0.; var growing := 0.; var thermal := 0.
		for i in range(mesh.n):
			if env.water[i]: continue
			var p := location(mesh,i); var match_zone: bool = hu_side(p,mask)==name_value if zone.size()==1 else inside(p,zone)
			if not match_zone: continue
			var a: float = mesh.areas[i]; area += a; rain += env.precipitation[i]*a; suitability += env.suitability[i]*a
			if env.biome[i] in [6,11]: desert += a
			if env.biome[i] in [5,9,10,13,14]: forest += a
			if env.has("agricultural_potential"): farmland += env.agricultural_potential[i]*a
			thermal += env.temperature[i]*a
			if env.has("potential_evaporation"): pet += env.potential_evaporation[i]*a; growing += env.growing_months[i]*a
		for city in data.cities:
			var p := location(mesh,city.cell)
			if (hu_side(p,mask)==name_value if zone.size()==1 else inside(p,zone)): cities += 1
		for seat in data.regions.seat:
			var p := location(mesh,seat)
			if (hu_side(p,mask)==name_value if zone.size()==1 else inside(p,zone)): provinces += 1
		var km2 := area*pow(40000./2048.,2)
		output[name_value] = {"area_km2":km2,"cities":cities,"provinces":provinces,"cities_per_million_km2":cities/km2*1e6,"rain_mm_estimate":rain/area,"suitability":suitability/area,"desert_fraction":desert/area,"forest_fraction":forest/area,"farming_potential":farmland/area}
		output[name_value].temperature_C = thermal/area
		if env.has("potential_evaporation"): output[name_value].potential_evaporation_mm = pet/area; output[name_value].growing_months = growing/area
	return output
