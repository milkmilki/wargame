extends SceneTree
const World = preload("res://scripts/atlas/world.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const Regions = preload("res://scripts/atlas/regions.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("CLIMATE_V2_COMPAT_FAIL ",message)
func _initialize() -> void:
	var before: Dictionary = FileAccess.open("res://.dbg/atlas-earth-circulation-v2.bin",FileAccess.READ).get_var(false).data
	var env := World.generate({"seed":1,"terrain_model":"earth","rainfall_model":"seasonal_circulation_v2"})
	check(env.params.settlement_model=="climate_capacity_v2","v2 regeneration silently changed settlement model")
	for field in ["water","elevation","temperature","precipitation","quarter_precipitation","seasonal_winds","seaIce","biome","flux"]:
		check(var_to_bytes(env[field])==var_to_bytes(before.environment[field]),"v2 environment changed "+field)
	var habitat := Habitat.build(env.mesh,env)
	for field in ["suitability","capacity","agricultural_potential"]:
		check(habitat[field]==before.environment[field],"v2 habitat changed "+field)
	env.suitability = habitat.suitability; env.capacity = habitat.capacity
	var regions := Regions.build(env.mesh,env,1)
	for field in ["of","seat","area","capacity","landmass","adj","adjStart"]:
		check(regions[field]==before.regions[field],"v2 provinces changed "+field)
	print("ATLAS_CLIMATE_V2_COMPATIBILITY failures=",failures); quit(1 if failures else 0)
