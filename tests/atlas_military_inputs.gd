extends RefCounted
## Test inputs are reproducible native outputs; ignored developer caches are optional.
const Generator = preload("res://scripts/atlas/generator.gd")
const MilitaryMap = preload("res://scripts/atlas/military_map.gd")
static func base(seed_value: int = 1,earth: bool = true) -> Dictionary:
	var path := "res://.dbg/atlas-native-generated-earth-capacity-v6.bin" if earth else "res://.dbg/atlas-native-generated-%d.bin"%seed_value
	if FileAccess.file_exists(path): return FileAccess.open(path,FileAccess.READ).get_var(false)
	var options := {"terrain_model":"earth","rainfall_model":"seasonal_circulation_v5","settlement_model":"climate_capacity_v6"} if earth else {"terrain_model":"planet","rainfall_model":"atlas_original","settlement_model":"atlas_original"}
	var result := Generator.generate(seed_value,1.,Callable(),options)
	assert(not result.has("error"),str(result.get("error","")))
	DirAccess.make_dir_recursive_absolute("res://.dbg")
	FileAccess.open(path,FileAccess.WRITE).store_var(result,false)
	return result
static func military() -> Dictionary:
	var path := "res://.dbg/atlas-military-earth.bin"
	if FileAccess.file_exists(path): return FileAccess.open(path,FileAccess.READ).get_var(false)
	var result := MilitaryMap.prepare(base()); FileAccess.open(path,FileAccess.WRITE).store_var(result,false); return result
