extends SceneTree
const Metrics = preload("res://scripts/tools/atlas_circulation_metrics.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const Regions = preload("res://scripts/atlas/regions.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
func _initialize() -> void:
	var report := {"seed":1,"city_threshold":1,"province_area":750,"observed_climate":false,"regions":{}}
	for pair in [["before","res://.dbg/atlas-earth-monsoon-v1.bin"],["after","res://.dbg/atlas-earth-circulation-v2.bin"]]:
		var payload: Dictionary = FileAccess.open(pair[1],FileAccess.READ).get_var(false); var data: Dictionary = payload.data
		report.regions[pair[0]] = Metrics.summarize(data)
		report[pair[0]] = {"params":data.params,"options":data.options,"cells":data.mesh.n,"provinces":data.regions.count,"cities":data.cities.size(),"roads":data.roads.size(),"timing":payload.timing}
		FileAccess.open("res://.dbg/circulation-%s-rain.f32"%pair[0],FileAccess.WRITE).store_buffer(payload.raster.precip.to_byte_array())
		FileAccess.open("res://.dbg/circulation-%s-water.u8"%pair[0],FileAccess.WRITE).store_buffer(payload.raster.water)
		FileAccess.open("res://.dbg/circulation-%s-suit.f32"%pair[0],FileAccess.WRITE).store_buffer(data.environment.suitability.to_byte_array())
		var cells: Array = []; var cities: Array = []; var winds: Array = []
		for i in range(data.mesh.n):
			var p := Metrics.location(data.mesh,i); cells.append([p.x,p.y,data.environment.water[i]])
		for city in data.cities:
			var p := Metrics.location(data.mesh,city.cell); cities.append([p.x,p.y])
		if data.environment.has("seasonal_winds"):
			for quarter in data.environment.seasonal_winds: winds.append({"u":Array(quarter.u),"v":Array(quarter.v)})
		FileAccess.open("res://.dbg/circulation-%s-cells.json"%pair[0],FileAccess.WRITE).store_string(JSON.stringify({"cells":cells,"cities":cities,"winds":winds}))
		if pair[0]=="after":
			var env: Dictionary = data.environment.duplicate(); env.params = env.params.duplicate(); env.params.settlement_model = "atlas_original"
			var hab := Habitat.build(data.mesh,env); env.suitability = hab.suitability; env.capacity = hab.capacity; env.erase("agricultural_potential")
			var regions := Regions.build(data.mesh,env,1); var seats := Roads.seat_cities(data.mesh,env,regions,1.)
			report.regions.climate_only = Metrics.summarize({"mesh":data.mesh,"environment":env,"regions":regions,"cities":seats})
	FileAccess.open("res://docs/atlas/circulation/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report.regions)); quit()
