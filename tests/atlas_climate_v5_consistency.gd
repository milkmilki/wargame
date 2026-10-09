extends SceneTree
## Compare the real rendered world with an independent native diagnostic run.
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("CLIMATE_V5_CONSISTENCY_FAIL ",message)
func _initialize() -> void:
	var payload: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-earth-rainfall-v5.bin",FileAccess.READ).get_var(false)
	var diagnostic: Dictionary = FileAccess.open("res://.dbg/atlas-rainfall-v5/environment.bin",FileAccess.READ).get_var(false)
	var actual: Dictionary = payload.data.environment
	check(payload.data.options.rainfall_model=="seasonal_circulation_v5" and payload.data.options.settlement_model=="climate_capacity_v5","wrong runtime models")
	for field in ["elevation","water","temperature","precipitation","quarter_precipitation","biome","flux","climate_suitability"]:
		check(var_to_bytes(actual[field])==var_to_bytes(diagnostic.world[field]),"rendered/diagnostic mismatch: "+field)
	check(actual.suitability==diagnostic.habitat.suitability,"heatmap and rendered final suitability differ")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-rainfall-v5/metadata.json"))
	# v5 artifacts are historical after introducing the v6 default. Their
	# scorer was preserved byte-for-byte; current dispatch files may evolve.
	for path in ["scripts/atlas/seasonal_circulation.gd","scripts/atlas/climate_settlement.gd"]:
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
		var current_path: String = "scripts/atlas/climate_settlement_v5.gd" if path=="scripts/atlas/climate_settlement.gd" else path
		digest.update(FileAccess.get_file_as_bytes("res://"+current_path))
		check(digest.finish().hex_encode()==metadata.sources[path],"diagnostics use outdated source: "+path)
	print("ATLAS_CLIMATE_V5_CONSISTENCY failures=",failures); quit(1 if failures else 0)
