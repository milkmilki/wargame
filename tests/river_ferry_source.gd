extends SceneTree
const SOURCE := "res://assets/terrain/eurasia_hydrology_map_source.json"
const TEMP := "res://.dbg/ferry-source-validation.json"
func _init() -> void: call_deferred("run")
func run() -> void:
	assert(is_equal_approx(MapSource.ferry_interval(SOURCE),.06))
	assert(MapSource.ferry_interval()==0.0,"legacy China retains existing policy")
	assert(MapSource.ferry_max_per_river(SOURCE)==5 and MapSource.ferry_max_per_river()==0)
	var data := MapSource.load_manifest(SOURCE)
	for invalid in [0,-.01,1.01,"0.06",null]:
		data.ferry_interval=invalid
		FileAccess.open(TEMP,FileAccess.WRITE).store_string(JSON.stringify(data))
		assert(not MapSource.validate_manifest(TEMP).is_empty(),"invalid interval is rejected")
	data.ferry_interval=.06
	FileAccess.open(TEMP,FileAccess.WRITE).store_string(JSON.stringify(data))
	assert(MapSource.validate_manifest(TEMP).is_empty())
	assert(MapSource.ferry_interval(TEMP)==.06)
	for invalid in [0,-1,2.5,"5",null]:
		data.ferry_max_per_river=invalid
		FileAccess.open(TEMP,FileAccess.WRITE).store_string(JSON.stringify(data))
		assert(not MapSource.validate_manifest(TEMP).is_empty(),"invalid cap is rejected")
	data.erase("ferry_max_per_river")
	data.erase("ferry_interval")
	FileAccess.open(TEMP,FileAccess.WRITE).store_string(JSON.stringify(data))
	MapSource._cache.erase(TEMP)
	assert(MapSource.validate_manifest(TEMP).is_empty() and MapSource.ferry_interval(TEMP)==0,"omitted field preserves old generation")
	MapSource._cache.erase(TEMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))
	print("RIVER_FERRY_SOURCE_OK")
	quit(0)
