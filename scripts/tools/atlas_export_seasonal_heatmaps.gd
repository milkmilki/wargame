extends SceneTree
## Read-only diagnostics of the frozen native Earth; never regenerates a world.
const Cover = preload("res://scripts/atlas/raster_cover.gd")
const Climate = preload("res://scripts/atlas/climate_settlement_v3.gd")
const Circulation = preload("res://scripts/atlas/seasonal_circulation_v3.gd")
const SOURCE := "res://.dbg/atlas-native-generated-earth-1.bin"
const OUTPUT := "res://.dbg/atlas-seasonal-heatmaps/"
const WIDTH := 4096
const HEIGHT := 2048

func write_array(name_value: String,values: Variant) -> void:
	FileAccess.open(OUTPUT+name_value,FileAccess.WRITE).store_buffer(values.to_byte_array() if not values is PackedByteArray else values)

func sha256(path: String) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()

func _initialize() -> void:
	var begin := Time.get_ticks_msec(); var payload: Dictionary = FileAccess.open(SOURCE,FileAccess.READ).get_var(false)
	var data: Dictionary = payload.data; var mesh: Dictionary = data.mesh; var env: Dictionary = data.environment
	if data.options.rainfall_model!=Circulation.VERSION or data.options.settlement_model!=Climate.VERSION:
		push_error("Heatmap source must be current v3 Earth, not a historical model"); quit(1); return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var temperatures: Array = []; var rainfall: Array = []; var failures := 0
	var max_rain_error := 0.; var max_temperature_error := 0.; var max_climate_error := 0.
	var amplitude: float = env.params.climate_water_balance.seasonal_temperature_amplitude_C
	for q in range(4):
		var t := PackedFloat32Array(); t.resize(mesh.n); var p := t.duplicate()
		for i in range(mesh.n):
			var lat: float = 90.-mesh.y[i]/1024.*180.
			# Exactly the seasonal temperature formula used by Climate.fields.
			t[i] = env.temperature[i]+amplitude*Circulation.SEASONS[q]*signf(lat)*absf(sin(deg_to_rad(lat)))
			p[i] = env.quarter_precipitation[q][i]*.25
			if not is_finite(t[i]) or not is_finite(p[i]) or p[i]<0.: failures += 1
		temperatures.append(t); rainfall.append(p)
		write_array("temperature-%d.f32"%q,t); write_array("precipitation-%d.f32"%q,p)
	for i in range(mesh.n):
		if env.water[i]!=0: continue
		var t := PackedFloat32Array(); var p := t.duplicate(); var sum_t := 0.; var sum_p := 0.
		for q in range(4): t.append(temperatures[q][i]); p.append(rainfall[q][i]); sum_t += t[q]*.25; sum_p += p[q]
		max_temperature_error = maxf(max_temperature_error,absf(sum_t-env.temperature[i]))
		max_rain_error = maxf(max_rain_error,absf(sum_p-env.precipitation[i]))
		var climate := Climate.seasonal_suitability(t,p,90.-mesh.y[i]/1024.*180.)
		max_climate_error = maxf(max_climate_error,absf(climate.factor-env.climate_suitability[i]))
	if max_temperature_error>1e-4 or max_rain_error>.01 or max_climate_error>1e-5: failures += 1
	print("SEASONAL_NODE_CHECK rain_error=",max_rain_error," temperature_error=",max_temperature_error," climate_error=",max_climate_error," failures=",failures)
	if failures: quit(1); return
	print("SEASONAL_COVER start ",WIDTH,"x",HEIGHT)
	var cover := Cover.build(mesh,WIDTH,HEIGHT)
	if cover.holes>0 or cover.tri.count(0)>0:
		push_error("Unexplained spherical projection holes"); quit(1); return
	write_array("tri.i32",cover.tri); write_array("wa.f32",cover.wa); write_array("wb.f32",cover.wb)
	write_array("triangles.i32",mesh.triangles); write_array("node-water.u8",env.water)
	write_array("annual-temperature.f32",env.temperature); write_array("annual-precipitation.f32",env.precipitation)
	var metadata := {"format":"atlas-seasonal-heatmaps-v1","seed":data.seed,"terrain_model":data.options.terrain_model,"rainfall_model":data.options.rainfall_model,"settlement_model":data.options.settlement_model,"params":data.params,"mesh_cells":mesh.n,"width":WIDTH,"height":HEIGHT,"bounds":[-180,-90,180,90],"row_order":"north_to_south","projection":"equirectangular","seasons":["DJF","MAM","JJA","SON"],"months":[[12,1,2],[3,4,5],[6,7,8],[9,10,11]],"temperature_units":"C","rainfall_units":"estimated mm per quarter; source annualized rates divided by four","temperature_source":"annual node temperature plus latitude-scaled seasonal amplitude; not an independent seasonal atmosphere solve","ocean_policy":"masked; no simulated ocean rainfall output","rain_solver_grid":env.params.rainfall_transport.grid,"source_snapshot":SOURCE,"snapshot_sha256":sha256(SOURCE),"temperature_formula_sha256":sha256("res://scripts/atlas/climate_settlement_v3.gd"),"exporter_sha256":sha256("res://scripts/tools/atlas_export_seasonal_heatmaps.gd"),"godot":Engine.get_version_info(),"pid":OS.get_process_id(),"validation":{"max_temperature_mean_error":max_temperature_error,"max_precipitation_sum_error":max_rain_error,"max_climate_factor_error":max_climate_error,"projection_holes":cover.holes},"export_ms":Time.get_ticks_msec()-begin}
	FileAccess.open(OUTPUT+"metadata.json",FileAccess.WRITE).store_string(JSON.stringify(metadata,"\t"))
	print("ATLAS_SEASONAL_EXPORT failures=0 seed=",data.seed," export_ms=",Time.get_ticks_msec()-begin); quit()
