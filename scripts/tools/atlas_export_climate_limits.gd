extends SceneTree
const Metrics = preload("res://scripts/tools/atlas_circulation_metrics.gd")
func _initialize() -> void:
	var report := {"seed":1,"city_threshold":1.,"province_area":750.,"observed_climate":false,"regions":{}}
	for pair in [["before","res://.dbg/atlas-earth-circulation-v2.bin"],["after","res://.dbg/atlas-native-generated-earth-1.bin"]]:
		var payload: Dictionary = FileAccess.open(pair[1],FileAccess.READ).get_var(false); var data: Dictionary = payload.data
		report.regions[pair[0]] = Metrics.summarize(data)
		report[pair[0]] = {"params":data.params,"options":data.options,"cells":data.mesh.n,"provinces":data.regions.count,"cities":data.cities.size(),"roads":data.roads.size(),"timing":payload.timing}
	DirAccess.make_dir_recursive_absolute("res://docs/atlas/climate_limits")
	FileAccess.open("res://docs/atlas/climate_limits/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report.regions)); quit()
