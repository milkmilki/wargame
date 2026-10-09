extends SceneTree
## Re-score frozen Earth climate in native Godot; do not move cities or terrain.
const Climate = preload("res://scripts/atlas/climate_settlement_v4.gd")
const Previous = preload("res://scripts/atlas/climate_settlement_v3.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const SOURCE := "res://.dbg/atlas-native-generated-earth-1.bin"
const OUTPUT := "res://.dbg/atlas-seasonal-capacity/"

func sha256(path: String) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path)); return context.finish().hex_encode()

func write_field(name_value: String,values: PackedFloat32Array) -> void:
	FileAccess.open(OUTPUT+name_value+".f32",FileAccess.WRITE).store_buffer(values.to_byte_array())

func _initialize() -> void:
	var begin := Time.get_ticks_msec()
	var data: Dictionary = FileAccess.open(SOURCE,FileAccess.READ).get_var(false).data
	var mesh: Dictionary = data.mesh; var original: Dictionary = data.environment
	var old_fields := Previous.fields(mesh,original)
	var old_habitat := Habitat.build(mesh,original)
	var failures := 0; var legacy_error := 0.
	for key in ["suitability","capacity","agricultural_potential"]:
		if old_habitat[key]!=original[key]: failures += 1; push_error("Historical habitat changed: "+key)
	for i in range(mesh.n): legacy_error = maxf(legacy_error,absf(old_fields.climate_suitability[i]-original.climate_suitability[i]))
	if legacy_error>1e-6: failures += 1
	var env := original.duplicate(true); env.params.settlement_model = Climate.VERSION
	env.params.climate_water_balance = Climate.METADATA.duplicate(true)
	var fields := Climate.fields(mesh,env); var repeated := Climate.fields(mesh,env)
	for key in fields:
		if fields[key]!=repeated[key]: failures += 1; push_error("Nondeterministic field: "+key)
	env.merge(fields,true)
	var habitat := Habitat.build(mesh,env)
	for key in ["elevation","water","temperature","precipitation","quarter_precipitation","biome","flux"]:
		if var_to_bytes(env[key])!=var_to_bytes(original[key]): failures += 1; push_error("Climate input changed: "+key)
	var quarters: Array = []
	for q in range(4):
		var values := PackedFloat32Array(); values.resize(mesh.n); quarters.append(values)
	for i in range(mesh.n):
		if env.water[i]: continue
		var lat: float = 90.-mesh.y[i]/1024.*180.
		var t := PackedFloat32Array(); var p := PackedFloat32Array()
		for q in range(4):
			t.append(env.temperature[i]+12.*[-.85,.4,.85,-.4][q]*signf(lat)*absf(sin(deg_to_rad(lat))))
			p.append(env.quarter_precipitation[q][i]*.25)
		var result := Climate.seasonal_suitability(t,p,lat)
		for q in range(4): quarters[q][i] = result.quarter_scores[q]
		if absf(result.factor-fields.climate_suitability[i])>1e-6: failures += 1
		if not is_finite(habitat.suitability[i]) or habitat.suitability[i]<0.: failures += 1
	if failures: print("ATLAS_CAPACITY_EXPORT failures=",failures); quit(1); return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	write_field("climate-before",original.climate_suitability); write_field("climate-after",fields.climate_suitability)
	write_field("habitat-before",original.suitability); write_field("habitat-after",habitat.suitability)
	for q in range(4): write_field("quarter-%d"%q,quarters[q])
	var cover_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-seasonal-heatmaps/metadata.json"))
	if cover_meta.snapshot_sha256!=sha256(SOURCE): push_error("Projection belongs to different world"); quit(1); return
	var metadata := {"format":"atlas-seasonal-capacity-v1","seed":data.seed,"source":SOURCE,"source_sha256":sha256(SOURCE),"rainfall_model":data.options.rainfall_model,"previous_settlement_model":Previous.VERSION,"settlement_model":Climate.VERSION,"parameters":Climate.METADATA,"godot":Engine.get_version_info(),"pid":OS.get_process_id(),"formula_sha256":sha256("res://scripts/atlas/climate_settlement_v4.gd"),"previous_formula_sha256":sha256("res://scripts/atlas/climate_settlement_v3.gd"),"habitat_formula_sha256":sha256("res://scripts/atlas/habitat.gd"),"exporter_sha256":sha256("res://scripts/tools/atlas_export_seasonal_capacity.gd"),"projection_metadata":cover_meta,"validation":{"legacy_climate_error":legacy_error,"legacy_habitat_exact":true,"climate_inputs_exact":true,"deterministic":true},"export_ms":Time.get_ticks_msec()-begin,"city_policy":"unchanged frozen layout; only suitability rescored"}
	FileAccess.open(OUTPUT+"metadata.json",FileAccess.WRITE).store_string(JSON.stringify(metadata,"\t"))
	print("ATLAS_CAPACITY_EXPORT failures=0 seed=",data.seed," model=",Climate.VERSION," export_ms=",Time.get_ticks_msec()-begin); quit()
