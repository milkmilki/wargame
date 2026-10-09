extends SceneTree
## Current native weather on seed1 Earth; preserve the frozen v3 reference.
const World = preload("res://scripts/atlas/world.gd")
const Climate = preload("res://scripts/atlas/climate_settlement_v4.gd")
const Habitat = preload("res://scripts/atlas/habitat.gd")
const Source := "res://.dbg/atlas-native-generated-earth-1.bin"
const Output := "res://.dbg/atlas-rainfall-v4/"
const Points := {"Zhengzhou":[113.65,34.72],"Beijing":[116.4,39.9],"Wuhan":[114.3,30.6],"Nanjing":[118.8,32.1],"Guangzhou":[113.27,23.13],"Yakutsk":[129.72,62.02]}

func sha256(path: String) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path)); return context.finish().hex_encode()

func write_field(name_value: String,values: PackedFloat32Array) -> void:
	FileAccess.open(Output+name_value+".f32",FileAccess.WRITE).store_buffer(values.to_byte_array())

func nearest(mesh: Dictionary,point: Array) -> int:
	var best := 1e30; var found := -1
	for i in range(mesh.n):
		var lon: float = mesh.x[i]/2048.*360.-180.; var lat: float = 90.-mesh.y[i]/1024.*180.
		var dx: float = wrapf(lon-point[0],-180.,180.)*cos(deg_to_rad(point[1])); var dy: float = lat-point[1]
		var distance: float = dx*dx+dy*dy
		if distance<best: best = distance; found = i
	return found

func _initialize() -> void:
	var start := Time.get_ticks_msec(); var failures := 0
	var data: Dictionary = FileAccess.open(Source,FileAccess.READ).get_var(false).data
	var old: Dictionary = data.environment
	var env := World.generate({"seed":1,"terrain_model":"earth","rainfall_model":"seasonal_circulation_v4","settlement_model":"climate_capacity_v4"},func(stage): print("RAIN_V4_STAGE ",stage))
	if env.has("error"): push_error(env.error); quit(1); return
	if env.params.rainfall_model!="seasonal_circulation_v4" or env.params.settlement_model!=Climate.VERSION: failures += 1
	for key in ["xyz","triangles","x","y","adj","areas"]:
		if env.mesh[key]!=data.mesh[key]: failures += 1; push_error("Mesh changed: "+key)
	for key in ["water","elevation","temperature"]:
		if env[key]!=old[key]: failures += 1; push_error("Primitive input changed: "+key)
	if not env.rivers.is_empty(): failures += 1
	var new_habitat := Habitat.build(env.mesh,env)
	var before := old.duplicate(true); before.params.settlement_model = Climate.VERSION
	before.merge(Climate.fields(data.mesh,before),true)
	var before_habitat := Habitat.build(data.mesh,before)
	var maximum_error := 0.
	for i in range(env.mesh.n):
		if env.water[i]!=0: continue
		var annual := 0.
		for quarter in env.quarter_precipitation:
			if not is_finite(quarter[i]) or quarter[i]<0.: failures += 1
			annual += quarter[i]*.25
		maximum_error = maxf(maximum_error,absf(annual-env.precipitation[i]))
		if not is_finite(new_habitat.suitability[i]) or new_habitat.suitability[i]<0.: failures += 1
	if maximum_error>.01: failures += 1
	var cover_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-seasonal-heatmaps/metadata.json"))
	if cover_meta.snapshot_sha256!=sha256(Source): failures += 1; push_error("Frozen reference changed")
	if failures: print("ATLAS_RAIN_V4_EXPORT failures=",failures); quit(1); return
	DirAccess.make_dir_recursive_absolute(Output)
	for q in range(4):
		var a: PackedFloat32Array = old.quarter_precipitation[q].duplicate(); var b: PackedFloat32Array = env.quarter_precipitation[q].duplicate()
		for i in range(a.size()): a[i] *= .25; b[i] *= .25
		write_field("rain-before-%d"%q,a); write_field("rain-after-%d"%q,b)
	write_field("annual-before",old.precipitation); write_field("annual-after",env.precipitation)
	write_field("climate-before",before.climate_suitability); write_field("climate-after",env.climate_suitability)
	write_field("habitat-before",before_habitat.suitability); write_field("habitat-after",new_habitat.suitability)
	FileAccess.open(Output+"environment.bin",FileAccess.WRITE).store_var({"world":env,"habitat":new_habitat},false)
	var points := {}
	for name_value in Points:
		var cell := nearest(env.mesh,Points[name_value]); var row := {"requested_lon_lat":Points[name_value],"nearest_cell":cell,"before_mm":[],"after_mm":[]}
		row.actual_lon_lat = [env.mesh.x[cell]/2048.*360.-180.,90.-env.mesh.y[cell]/1024.*180.]
		for q in range(4): row.before_mm.append(old.quarter_precipitation[q][cell]*.25); row.after_mm.append(env.quarter_precipitation[q][cell]*.25)
		points[name_value] = row
	var revision: Array = []; OS.execute("git",["rev-parse","HEAD"],revision)
	var metadata := {"format":"atlas-rainfall-v4-diagnostics","seed":1,"pid":OS.get_process_id(),"godot":Engine.get_version_info(),"git_base":str(revision[0]).strip_edges() if revision.size() else "unknown","worktree":"uncommitted source hashes below","model":env.params.rainfall_model,"settlement_model":env.params.settlement_model,"parameters":env.params,"source":Source,"source_sha256":sha256(Source),"projection_metadata":cover_meta,"city_policy":"no cities regenerated in this diagnostic export","points_nearest_sphere_node":points,"validation":{"failures":0,"maximum_quarter_sum_error_mm":maximum_error,"primitive_inputs_exact":true,"mesh_exact":true},"sources":{},"export_ms":Time.get_ticks_msec()-start}
	for path in ["scripts/atlas/seasonal_circulation.gd","scripts/atlas/circulation_rainfall.gd","scripts/atlas/world.gd","scripts/atlas/climate_settlement.gd","scripts/atlas/habitat.gd","scripts/tools/atlas_export_rainfall_v4.gd"]: metadata.sources[path] = sha256("res://"+path)
	FileAccess.open(Output+"metadata.json",FileAccess.WRITE).store_string(JSON.stringify(metadata,"\t"))
	print("RAIN_V4_POINTS ",JSON.stringify(points)); print("ATLAS_RAIN_V4_EXPORT failures=0 export_ms=",Time.get_ticks_msec()-start); quit()
