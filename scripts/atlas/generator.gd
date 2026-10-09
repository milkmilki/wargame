extends RefCounted
## Independent atlas data pipeline; all computation is native GDScript.
const World = preload("res://scripts/atlas/world.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const Regions = preload("res://scripts/atlas/regions.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
const Ownership = preload("res://scripts/atlas/ownership.gd")
const Raster = preload("res://scripts/atlas/raster.gd")
const Glyphs = preload("res://scripts/atlas/glyph_plan.gd")
const Names = preload("res://scripts/atlas/names.gd")
const Places = preload("res://scripts/atlas/places.gd")

static func generate(seed_value: int = 1,city_threshold: float = 1.0,progress: Callable = Callable(),world_options: Dictionary = {}) -> Dictionary:
	var begin := Time.get_ticks_msec(); var stages := {}
	var options := world_options.duplicate(); options.seed = seed_value
	var world := World.generate(options,progress)
	if world.has("error"): return world
	stages.world_ms = Time.get_ticks_msec()-begin
	var started := Time.get_ticks_msec()
	if progress.is_valid(): progress.call("宜居度与省份")
	var habitat := Habitat.build(world.mesh,world); world.suitability = habitat.suitability; world.capacity = habitat.capacity
	if habitat.has("agricultural_potential"): world.agricultural_potential = habitat.agricultural_potential
	for field in ["climate_suitability","potential_evaporation","aridity_index","growing_months"]:
		if habitat.has(field): world[field] = habitat[field]
	var regions := Regions.build(world.mesh,world,seed_value)
	var cities := Roads.seat_cities(world.mesh,world,regions,city_threshold)
	var ownership := Ownership.build(world.mesh,regions,cities); stages.regions_ms = Time.get_ticks_msec()-started
	started = Time.get_ticks_msec()
	if progress.is_valid(): progress.call("陆上道路")
	var roads := Roads.build(world.mesh,world,cities); stages.roads_ms = Time.get_ticks_msec()-started
	started = Time.get_ticks_msec()
	if progress.is_valid(): progress.call("全球栅格与浮冰")
	var raster := Raster.build(world); stages.raster_ms = Time.get_ticks_msec()-started
	started = Time.get_ticks_msec()
	if progress.is_valid(): progress.call("地形符号规划")
	var display := Glyphs.build(world); stages.glyphs_ms = Time.get_ticks_msec()-started
	var environment := world.duplicate(); environment.erase("mesh"); environment.erase("tect")
	var data := {"format":"atlas-native-map","version":1,"seed":seed_value,"upstream":"103afd3",
		"upstream_commit":"103afd3d998eac6750692a6813bf5aea03521448","params":world.params,"mesh":world.mesh,"environment":environment,
		"regions":regions,"cities":cities,"roads":roads.routes,"connections":roads.connections,"ownership":ownership.ownership,"nations":ownership.nations,
		"options":{"terrain_model":world.params.get("terrain_model","planet"),"rainfall_model":world.params.get("rainfall_model","atlas_original"),"settlement_model":world.params.get("settlement_model","atlas_original"),"river_usage":"environment_only","city_threshold":city_threshold,"road_model":"civ-atlas-103afd3-land-v1","visual_model":"atlas-handdrawn-v1"}}
	Names.assign(data)
	started = Time.get_ticks_msec()
	if progress.is_valid(): progress.call("地理名称与标注路径")
	data.places = Places.build(world); stages.places_ms = Time.get_ticks_msec()-started
	display.nations = ownership.nations; stages.total_ms = Time.get_ticks_msec()-begin
	return {"data":data,"raster":raster,"display":display,"timing":stages}

static func pixel_regions(data: Dictionary,raster: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array(); out.resize(raster.w*raster.h); var mesh: Dictionary = data.mesh
	for k in range(out.size()):
		if raster.water[k]!=0: out[k] = -1; continue
		var c: int = raster.cell[k]; var r: int = data.regions.of[c]
		if r<0:
			for q in range(mesh.adj_start[c],mesh.adj_start[c+1]):
				r = data.regions.of[mesh.adj[q]]
				if r>=0: break
		out[k] = r
	return out
