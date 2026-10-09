extends SceneTree
## Development-only export of numeric fields; does not modify screenshot pixels.
func _initialize() -> void:
	var report := {"seed":1,"city_threshold":1,"province_area":750,"regions":{}}
	for pair in [["before","res://.dbg/atlas-earth-before-monsoon.bin"],["after","res://.dbg/atlas-earth-monsoon-v1.bin"]]:
		var payload: Dictionary = FileAccess.open(pair[1],FileAccess.READ).get_var(false)
		var data: Dictionary = payload.data; var mesh: Dictionary = data.mesh; var env: Dictionary = data.environment
		FileAccess.open("res://.dbg/atlas-rain-%s.f32"%pair[0],FileAccess.WRITE).store_buffer(payload.raster.precip.to_byte_array())
		FileAccess.open("res://.dbg/atlas-rain-%s.u8"%pair[0],FileAccess.WRITE).store_buffer(payload.raster.water)
		var cities: Array = []
		for city in data.cities: cities.append([mesh.x[city.cell]/2048.*360.-180.,90.-mesh.y[city.cell]/1024.*180.])
		FileAccess.open("res://.dbg/atlas-rain-%s-cities.json"%pair[0],FileAccess.WRITE).store_string(JSON.stringify(cities))
		var rows: Array = []
		for zone in [["ChinaEast",105.,122.,22.,42.],["Europe",-10.,30.,36.,60.],["EastAsia",100.,145.,18.,50.],["NorthChina",110.,122.,34.,42.],["SouthChina",105.,122.,22.,34.],["Sahara",-10.,30.,20.,30.],["Arabia",40.,55.,18.,30.],["India",70.,90.,10.,30.]]:
			var area := 0.; var rain := 0.; var suit := 0.; var seasonal := 0.; var provinces := 0; var city_count := 0
			for cell in range(mesh.n):
				if env.water[cell] or not inside(mesh,cell,zone): continue
				var a: float = mesh.areas[cell]; area += a; rain += env.precipitation[cell]*a; suit += env.suitability[cell]*a
				if env.has("seasonal_precipitation"): seasonal += env.seasonal_precipitation[cell]*a
			for seat in data.regions.seat:
				if inside(mesh,seat,zone): provinces += 1
			for city in data.cities:
				if inside(mesh,city.cell,zone): city_count += 1
			rows.append({"name":zone[0],"bounds":zone.slice(1),"provinces":provinces,"cities":city_count,"effective_moisture":rain/area,"suitability":suit/area,"seasonal_moisture":seasonal/area})
		report.regions[pair[0]] = rows
		report[pair[0]] = {"params":data.params,"options":data.options,"cells":mesh.n,"provinces":data.regions.count,"cities":data.cities.size(),"roads":data.roads.size(),"timing":payload.timing}
	FileAccess.open("res://docs/atlas/monsoon/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report.regions)); quit()
func inside(mesh: Dictionary,cell: int,zone: Array) -> bool:
	var lon: float = mesh.x[cell]/2048.*360.-180.; var lat: float = 90.-mesh.y[cell]/1024.*180.
	return lon>=zone[1] and lon<zone[2] and lat>=zone[3] and lat<zone[4]
