extends SceneTree
const Model=preload("res://scripts/atlas/seasonal_circulation.gd")
const Adapter=preload("res://scripts/atlas/circulation_rainfall.gd")
const Earth=preload("res://scripts/atlas/earth_surface.gd")
const Baseline=preload("res://scripts/atlas/seasonal_circulation_v5.gd")
const Mask=preload("res://scripts/atlas/settlement_mask.gd")
const OUT="res://.dbg/climate-v6/"
const BASELINE="res://.dbg/atlas-military-eurasia-mask.bin"
func _initialize() -> void:call_deferred("run")
func save_field(key:String,value) -> void:
	FileAccess.open(OUT+key+".bin",FileAccess.WRITE).store_buffer(value if value is PackedByteArray else value.to_byte_array())
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var surface:=Earth.load_surface();var size:=Adapter.CURRENT_GRID;var n:=size.x*size.y
	if surface.is_empty():push_error("verified Earth source missing");quit(1);return
	var heights:=Model.zeros(n);var raw:=heights.duplicate();var land:=PackedByteArray();land.resize(n);var types:=land.duplicate()
	for y in range(size.y):
		for x in range(size.x):
			var lon:=(x+.5)/size.x*360.-180.;var lat:=90.-(y+.5)/size.y*180.;var i:=y*size.x+x
			raw[i]=Earth.elevation_at(surface,lon,lat);heights[i]=maxf(0.,raw[i]);types[i]=Earth.water_at(surface,lon,lat);land[i]=int(types[i]==0)
	if not FileAccess.file_exists(BASELINE):push_error("historical seed1/40/Eurasia coast-v1 baseline required: "+BASELINE);quit(1);return
	var payload:Dictionary=FileAccess.open(BASELINE,FileAccess.READ).get_var(false)
	assert(payload.data.seed==1 and payload.data.options.settlement_mask==Mask.EURASIA and payload.nations.size()==40 and payload.data.mesh.model=="atlas-coastline-mesh-v1")
	var baseline:=OS.get_cmdline_user_args().has("--baseline")
	var anomaly:=Adapter.sea_anomaly_grid(payload.data.mesh,payload.data.environment.water,payload.data.environment.currents.sst,size) if baseline else Adapter.marine_anomaly(types,size)
	var options:={"water_types":types,"lowland_lakes":Adapter.lowland_lake_mask(types,raw,size),"sea_temperature_anomaly":anomaly}
	if not baseline:options.barrier_elevation=Adapter.orographic_barriers(surface,size)
	var label:="before" if baseline else "after"
	for argument in OS.get_cmdline_user_args():
		if argument=="--no-upwelling":options.wind_upwelling=false
		if argument=="--no-terrain":options.terrain_wind=false
		if argument.begins_with("--label="):
			label=argument.trim_prefix("--label=")
			if not label.is_valid_identifier():push_error("invalid output label");quit(1);return
	var started:=Time.get_ticks_msec();var fields:Dictionary=Baseline.build_fields(heights,land,size,options) if baseline else Model.build_fields(heights,land,size,options)
	save_field("land",land);save_field("water",types);save_field("elevation",heights);save_field("sst",anomaly);save_field(label+"-sst",anomaly)
	for key in ["annual","seasonal","mean_u","mean_v"]:save_field(label+"-"+key,fields[key])
	for q in range(4):
		save_field(label+"-rain-%d"%q,fields.quarters[q]);save_field(label+"-u-%d"%q,fields.winds[q].u);save_field(label+"-v-%d"%q,fields.winds[q].v)
		if fields.has("sea_temperature_anomaly"):save_field(label+"-sst-%d"%q,fields.sea_temperature_anomaly[q])
		for key in ["soil_moisture","surface_evaporation","surface_runoff","surface_potential_evaporation","atmospheric_surface_evaporation"]:
			if fields.has(key):save_field(label+"-"+key+"-%d"%q,fields[key][q])
	for key in ["forest_cover","annual_evaporation","annual_runoff","surface_water_error"]:
		if fields.has(key):save_field(label+"-"+key,fields[key])
	FileAccess.open(OUT+label+"-fields.bin",FileAccess.WRITE).store_var(fields,false)
	FileAccess.open(OUT+"inputs.bin",FileAccess.WRITE).store_var({"elevation":heights,"land":land,"size":size,"options":options},false)
	var meta:={"version":Baseline.VERSION if baseline else Model.VERSION,"size":[size.x,size.y],"seed":1,"mask":payload.data.options.settlement_mask,"elapsed_ms":Time.get_ticks_msec()-started,"source":surface.metadata,"rules":fields.metadata}
	meta.model_sources={}
	for path in ["scripts/atlas/seasonal_circulation_v5.gd" if baseline else "scripts/atlas/seasonal_circulation.gd","scripts/atlas/surface_water.gd","scripts/atlas/circulation_rainfall.gd","scripts/atlas/currents.gd","scripts/atlas/climate.gd","scripts/atlas/climate_settlement_v3.gd","scripts/core/rainfall_transport.gd"]:
		meta.model_sources[path]=FileAccess.get_sha256("res://"+path)
	meta.baseline_snapshot_sha256=FileAccess.get_sha256(BASELINE)
	if fields.has("surface_water_metadata"):meta.surface_water=fields.surface_water_metadata
	FileAccess.open(OUT+label+"-metadata.json",FileAccess.WRITE).store_string(JSON.stringify(meta,"  "))
	print("CLIMATE_EXPORT ",JSON.stringify({"label":label,"version":meta.version,"elapsed_ms":meta.elapsed_ms}));quit(0)
