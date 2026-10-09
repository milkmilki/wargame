extends SceneTree
const Snapshot = preload("res://scripts/atlas/snapshot.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("TWO_SEASON_PREVIEW_FAIL ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(2048,1024)
	root.content_scale_size = Vector2i(2048,1024); root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var scene = load("res://atlas_earth_preview.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.generating: await process_frame
	var data: Dictionary = scene.data
	check(data.options.rainfall_model=="seasonal_circulation_v5" and data.options.settlement_model=="climate_capacity_v6","wrong current defaults")
	var old: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-earth-rainfall-v5.bin",FileAccess.READ).get_var(false).data
	for field in ["water","elevation","temperature","precipitation","quarter_precipitation","biome","flux"]: check(data.environment[field]==old.environment[field],"physical input changed: "+field)
	var payload := {"format":Snapshot.FORMAT,"version":Snapshot.VERSION,"data":data,"raster":scene.raster,"display":scene.display,"provinces":scene.provinces,"default_owners":scene.default_owners,"timing":scene.timing}
	check(Snapshot.validate(payload).is_empty(),"invalid snapshot")
	if failures: print("ATLAS_TWO_SEASON_PREVIEW failures=",failures); quit(1); return
	FileAccess.open("res://.dbg/atlas-native-generated-earth-capacity-v6.bin",FileAccess.WRITE).store_var(payload,false)
	var directory := "res://docs/atlas/two_season_cap/preview"; DirAccess.make_dir_recursive_absolute(directory)
	scene.hud.hide(); scene.fit_map(); scene.mode_control.select(3); scene.update_mode()
	await process_frame; RenderingServer.force_draw(true); root.get_texture().get_image().save_png(directory+"/earth-habitat.png")
	for view in [["china",7.,1660.,345.],["europe",7.,1135.,240.],["africa",5.,1150.,515.]]:
		scene.zoom = view[1]; scene.map_root.scale = Vector2.ONE*view[1]
		scene.map_root.position = Vector2(1024,512)-Vector2(view[2],view[3])*view[1]; scene.limit_pan(); scene.refresh_symbols()
		await process_frame; RenderingServer.force_draw(true); root.get_texture().get_image().save_png(directory+"/%s-habitat.png"%view[0])
	print("ATLAS_TWO_SEASON_PREVIEW ",JSON.stringify({"pid":OS.get_process_id(),"seed":data.seed,"cells":data.mesh.n,"regions":data.regions.count,"cities":data.cities.size(),"roads":data.roads.size(),"failures":failures})); quit()
