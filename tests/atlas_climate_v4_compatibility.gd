extends SceneTree
## Frozen v4 regeneration and snapshot restoration must preserve layout/data.
const World = preload("res://scripts/atlas/world.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const Regions = preload("res://scripts/atlas/regions.gd")
const Snapshot = preload("res://scripts/atlas/snapshot.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		print("CLIMATE_V4_COMPAT_FAIL ", message)

func _initialize() -> void:
	var path := "res://.dbg/atlas-native-generated-earth-rainfall-v4.bin"
	check(FileAccess.file_exists(path), "frozen Earth v4 snapshot required")
	if not FileAccess.file_exists(path): quit(1); return
	var original: Dictionary = FileAccess.open(path, FileAccess.READ).get_var(false)
	var stored: Dictionary = original.data
	check(stored.options.rainfall_model == "seasonal_circulation_v4" and stored.options.settlement_model == "climate_capacity_v4", "reference fixture is not v4")
	var world := World.generate({"terrain_model":"earth", "seed":int(stored.seed), "cells":int(stored.params.cells), "rainfall_model":"seasonal_circulation_v4"})
	check(not world.has("error"), "v4 regeneration failed")
	if world.has("error"): quit(1); return
	check(world.params.rainfall_model == "seasonal_circulation_v4", "explicit rain v4 silently upgraded")
	check(world.params.settlement_model == "climate_capacity_v4", "historical rain v4 default settlement silently upgraded")
	check(world.params.rainfall_transport.version == "seasonal_circulation_v4", "v4 dispatched current rainfall code")
	check(world.params.climate_water_balance.version == "climate_capacity_v4", "v4 dispatched current suitability code")
	for field in ["xyz", "triangles", "x", "y", "adj", "adj_start", "areas", "lengths"]:
		check(world.mesh[field] == stored.mesh[field], "mesh changed: " + field)
	for field in ["water", "elevation", "temperature", "precipitation", "quarter_precipitation", "seasonal_precipitation", "windX", "windY", "biome", "flux", "seaIce", "climate_suitability", "agricultural_potential", "potential_evaporation", "aridity_index", "growing_months"]:
		check(world[field] == stored.environment[field], "environment changed: " + field)
	var habitat := Habitat.build(world.mesh, world)
	for field in ["suitability", "capacity", "climate_suitability", "agricultural_potential"]:
		check(habitat[field] == stored.environment[field], "v4 habitat dispatch changed: " + field)
	world.suitability = habitat.suitability
	world.capacity = habitat.capacity
	var regions := Regions.build(world.mesh, world, int(stored.seed))
	for field in ["of", "seat", "count"]:
		check(regions[field] == stored.regions[field], "v4 province layout changed: " + field)
	var before := Marshalls.variant_to_base64(original)
	var loaded := Snapshot.load_file(path)
	check(not loaded.has("error"), "historical snapshot validation rejected v4")
	if not loaded.has("error"):
		check(Marshalls.variant_to_base64(loaded.payload) == before, "snapshot read mutated or migrated historical data")
		check(loaded.payload.data.options.rainfall_model == "seasonal_circulation_v4" and loaded.payload.data.options.settlement_model == "climate_capacity_v4", "snapshot models were silently upgraded")
	print("ATLAS_CLIMATE_V4_COMPATIBILITY ", JSON.stringify({"pid":OS.get_process_id(), "seed":stored.seed, "rain_model":world.params.rainfall_model, "capacity_model":world.params.settlement_model, "cells":world.mesh.n, "provinces":regions.count, "failures":failures}))
	quit(1 if failures else 0)
