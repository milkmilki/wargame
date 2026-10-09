extends SceneTree
const Snapshot = preload("res://scripts/atlas/snapshot.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("CIRCULATION_SNAPSHOT_FAIL ",message)
func _initialize() -> void:
	var payload: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-earth-1.bin",FileAccess.READ).get_var(false)
	var env: Dictionary = payload.data.environment
	var rain = env.quarter_precipitation[0]; env.quarter_precipitation[0] = PackedFloat32Array([1.])
	check(not Snapshot.validate(payload).is_empty(),"bad season dimensions accepted"); env.quarter_precipitation[0] = rain
	var wind: PackedFloat32Array = env.seasonal_winds[0].v.duplicate(); env.seasonal_winds[0].v[0] = NAN
	check(not Snapshot.validate(payload).is_empty(),"non-finite wind accepted"); env.seasonal_winds[0].v = wind
	check(Snapshot.validate(payload).is_empty(),"valid new climate snapshot rejected")
	if env.has("climate_suitability"):
		var factor: float = env.climate_suitability[0]; env.climate_suitability[0] = 2.
		check(not Snapshot.validate(payload).is_empty(),"impossible climate factor accepted"); env.climate_suitability[0] = factor
		var months: float = env.growing_months[0]; env.growing_months[0] = 13.
		check(not Snapshot.validate(payload).is_empty(),"thirteen-month growing season accepted"); env.growing_months[0] = months
		var pet = env.potential_evaporation; env.erase("potential_evaporation")
		check(not Snapshot.validate(payload).is_empty(),"partial climate fields accepted"); env.potential_evaporation = pet
	check(Snapshot.validate(payload).is_empty(),"restored climate fields rejected")
	print("ATLAS_CIRCULATION_SNAPSHOT failures=",failures); quit(1 if failures else 0)
