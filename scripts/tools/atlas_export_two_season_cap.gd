extends SceneTree
## Isolated scoring comparison: native regeneration, identical v5 weather/DEM.
const World = preload("res://scripts/atlas/world.gd")
const Climate = preload("res://scripts/atlas/climate_settlement.gd")
const Baseline = preload("res://scripts/atlas/climate_settlement_v5.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const Regions = preload("res://scripts/atlas/regions.gd")
const Output := "res://.dbg/atlas-two-season-cap/"
const Source := "res://.dbg/atlas-native-generated-earth-rainfall-v5.bin"
var failures := 0

func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; push_error("TWO_SEASON_EXPORT "+message)

func sha256(path: String) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path)); return context.finish().hex_encode()

func write_field(name_value: String,values: PackedFloat32Array) -> void:
	FileAccess.open(Output+name_value+".f32",FileAccess.WRITE).store_buffer(values.to_byte_array())

func _initialize() -> void:
	var start := Time.get_ticks_msec()
	var data: Dictionary = FileAccess.open(Source,FileAccess.READ).get_var(false).data
	var old: Dictionary = data.environment
	var env := World.generate({"seed":int(data.seed),"terrain_model":"earth"},func(stage): print("CAP_STAGE ",stage))
	if env.has("error"): push_error(env.error); quit(1); return
	check(env.params.rainfall_model=="seasonal_circulation_v5" and env.params.settlement_model==Climate.VERSION,"wrong default models")
	for key in ["xyz","triangles","x","y","adj","adj_start","areas","lengths"]:
		check(env.mesh[key]==data.mesh[key],"mesh changed: "+key)
	for key in ["water","elevation","temperature","precipitation","quarter_precipitation","seasonal_precipitation","seasonal_winds","windX","windY","flux","biome","seaIce"]:
		check(env[key]==old[key],"physical input changed: "+key)
	check(env.rivers.is_empty(),"visible rivers returned")
	var before_habitat := Habitat.build(data.mesh,old)
	check(before_habitat.suitability==old.suitability,"stored v5 habitat changed")
	# Recompute v5 fields through the historical dispatch, without cached scores.
	var historical := env.duplicate(true); historical.params.settlement_model = Baseline.VERSION
	for field in ["agricultural_potential","climate_suitability","potential_evaporation","aridity_index","growing_months"]: historical.erase(field)
	var historical_habitat := Habitat.build(env.mesh,historical)
	check(historical_habitat.suitability==old.suitability,"uncached v5 habitat dispatch changed")
	check(historical_habitat.climate_suitability==old.climate_suitability,"frozen v5 score changed")
	historical.suitability = historical_habitat.suitability; historical.capacity = historical_habitat.capacity
	var historical_regions := Regions.build(env.mesh,historical,int(data.seed))
	for field in ["of","seat","count"]: check(historical_regions[field]==data.regions[field],"v5 province layout changed: "+field)
	var after_habitat := Habitat.build(env.mesh,env)
	var repeated := Climate.fields(env.mesh,env)
	for field in repeated: check(repeated[field]==env[field],"non-deterministic current scoring: "+field)
	for i in range(env.mesh.n):
		check(is_finite(after_habitat.suitability[i]) and after_habitat.suitability[i]>=0.,"invalid final habitat")
		check(env.climate_suitability[i]>=0. and env.climate_suitability[i]<=1.,"climate support outside cap")
		check(after_habitat.suitability[i]+.00001>=before_habitat.suitability[i],"removing penalty unexpectedly decreased support")
	if failures: print("ATLAS_TWO_SEASON_EXPORT failures=",failures); quit(1); return
	DirAccess.make_dir_recursive_absolute(Output)
	write_field("habitat-before",before_habitat.suitability); write_field("habitat-after",after_habitat.suitability)
	write_field("climate-before",old.climate_suitability); write_field("climate-after",env.climate_suitability)
	FileAccess.open(Output+"environment.bin",FileAccess.WRITE).store_var({"world":env,"habitat":after_habitat},false)
	var cover_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-seasonal-heatmaps/metadata.json"))
	var revision: Array = []; OS.execute("git",["rev-parse","HEAD"],revision)
	var metadata := {"format":"atlas-two-season-cap-v1","seed":data.seed,"pid":OS.get_process_id(),"godot":Engine.get_version_info(),"git_base":str(revision[0]).strip_edges(),"parameters":env.params,"before_model":Baseline.VERSION,"after_model":Climate.VERSION,"source":Source,"source_sha256":sha256(Source),"projection_metadata":cover_meta,"validation":{"failures":0,"physical_inputs_exact":true,"mesh_exact":true,"v5_uncached_habitat_exact":true,"v5_provinces_exact":true,"current_scores_repeat_exact":true},"export_ms":Time.get_ticks_msec()-start,"sources":{}}
	for path in ["scripts/atlas/climate_settlement.gd","scripts/atlas/climate_settlement_v5.gd","scripts/atlas/habitat.gd","scripts/atlas/world.gd","scripts/atlas/regions.gd","scripts/atlas/seasonal_circulation.gd","scripts/tools/atlas_export_two_season_cap.gd"]: metadata.sources[path] = sha256("res://"+path)
	FileAccess.open(Output+"metadata.json",FileAccess.WRITE).store_string(JSON.stringify(metadata,"\t"))
	print("ATLAS_TWO_SEASON_EXPORT failures=0 export_ms=",metadata.export_ms); quit()
