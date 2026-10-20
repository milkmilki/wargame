extends RefCounted
## Test inputs are reproducible native outputs; ignored developer caches are optional.
const Generator = preload("res://scripts/atlas/generator.gd")
const MilitaryMap = preload("res://scripts/atlas/military_map.gd")
static func base(seed_value: int = 1,earth: bool = true) -> Dictionary:
	var path := "res://.dbg/atlas-native-generated-earth-coast-v1-capacity-v6.bin" if earth else "res://.dbg/atlas-native-generated-%d.bin"%seed_value
	if FileAccess.file_exists(path): return FileAccess.open(path,FileAccess.READ).get_var(false)
	var options := {"terrain_model":"earth","rainfall_model":"seasonal_circulation_v5","settlement_model":"climate_capacity_v6"} if earth else {"terrain_model":"planet","rainfall_model":"atlas_original","settlement_model":"atlas_original"}
	var result := Generator.generate(seed_value,1.,Callable(),options)
	assert(not result.has("error"),str(result.get("error","")))
	DirAccess.make_dir_recursive_absolute("res://.dbg")
	FileAccess.open(path,FileAccess.WRITE).store_var(result,false)
	return result
static func military() -> Dictionary:
	var path := "res://.dbg/atlas-military-earth-coast-v1.bin"
	if FileAccess.file_exists(path): return FileAccess.open(path,FileAccess.READ).get_var(false)
	var result := MilitaryMap.prepare(base())
	result.simulation_options={"trade_enabled":false,"rulers_enabled":false}
	FileAccess.open(path,FileAccess.WRITE).store_var(result,false); return result

## Performance/default audit world. Global fixtures above remain compatibility inputs.
static func climate_source_fingerprint() -> String:
	var sources:=PackedStringArray()
	for path in ["seasonal_circulation.gd","surface_water.gd","circulation_rainfall.gd","world.gd","climate.gd"]:
		sources.append(FileAccess.get_sha256("res://scripts/atlas/"+path))
	return "".join(sources).sha256_text()

static func eurasia_military(seed_value: int = 1) -> Dictionary:
	var path := "res://.dbg/atlas-military-eurasia-climate-v6.bin" if seed_value==1 else "res://.dbg/atlas-military-eurasia-climate-v6-%d.bin"%seed_value
	var mask: Dictionary = preload("res://scripts/atlas/settlement_mask.gd").EURASIA
	if FileAccess.file_exists(path):
		var cached: Dictionary = FileAccess.open(path,FileAccess.READ).get_var(false)
		if cached.get("test_climate_source","")==climate_source_fingerprint() and cached.get("data",{}).get("seed",-1)==seed_value and cached.get("data",{}).get("options",{}).get("settlement_mask",{})==mask and cached.data.options.get("rainfall_model","")=="seasonal_circulation_v6" and cached.get("data",{}).get("mesh",{}).get("model","")==preload("res://scripts/atlas/coastline_mesh.gd").MODEL:
			cached.simulation_options={"trade_enabled":true,"rulers_enabled":true}
			return cached
	var result := MilitaryMap.prepare(Generator.generate(seed_value,1.,Callable(),{"terrain_model":"earth","rainfall_model":"seasonal_circulation_v6","settlement_model":"climate_capacity_v6","settlement_mask":mask}))
	assert(not result.has("error"),str(result.get("error","")))
	result.simulation_options={"trade_enabled":true,"rulers_enabled":true}
	result.test_climate_source=climate_source_fingerprint()
	DirAccess.make_dir_recursive_absolute("res://.dbg")
	FileAccess.open(path,FileAccess.WRITE).store_var(result,false)
	return result
