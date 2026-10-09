extends SceneTree
## Rendered native world, diagnostic fields, and preserved v5 source agree.
const Baseline = preload("res://scripts/atlas/climate_settlement_v5.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("TWO_SEASON_CONSISTENCY_FAIL ",message)
func sha256(path: String) -> String:
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
	digest.update(FileAccess.get_file_as_bytes(path)); return digest.finish().hex_encode()
func _initialize() -> void:
	var payload: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-earth-capacity-v6.bin",FileAccess.READ).get_var(false)
	var diagnostic: Dictionary = FileAccess.open("res://.dbg/atlas-two-season-cap/environment.bin",FileAccess.READ).get_var(false)
	var actual: Dictionary = payload.data.environment
	check(payload.data.options.settlement_model=="climate_capacity_v6","wrong rendered model")
	for field in ["elevation","water","temperature","precipitation","quarter_precipitation","biome","flux","climate_suitability","agricultural_potential","growing_months"]:
		check(actual[field]==diagnostic.world[field],"rendered/diagnostic mismatch: "+field)
	check(actual.suitability==diagnostic.habitat.suitability,"plotted/rendered final habitat mismatch")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-two-season-cap/metadata.json"))
	for path in metadata.sources: check(sha256("res://"+path)==metadata.sources[path],"current source changed since export: "+path)
	check(sha256(metadata.source)==metadata.source_sha256,"v5 reference snapshot changed")
	var old_metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-rainfall-v5/metadata.json"))
	check(sha256("res://scripts/atlas/climate_settlement_v5.gd")==old_metadata.sources["scripts/atlas/climate_settlement.gd"],"preserved v5 formula differs from original bytes")
	var original: Dictionary = FileAccess.open(metadata.source,FileAccess.READ).get_var(false)
	check(Baseline.fields(original.data.mesh,original.data.environment).climate_suitability==original.data.environment.climate_suitability,"v5 score restoration changed")
	print("ATLAS_TWO_SEASON_CONSISTENCY failures=",failures); quit(1 if failures else 0)
