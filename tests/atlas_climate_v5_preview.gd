extends SceneTree
const Earth = preload("res://scripts/atlas/earth_surface.gd")
const Snapshot = preload("res://scripts/atlas/snapshot.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("EARTH_PREVIEW_FAIL ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(2048,1024)
	root.content_scale_size = Vector2i(2048,1024); root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var scene = load("res://atlas_earth_preview.tscn").instantiate(); scene.settlement_model = "climate_capacity_v5"; root.add_child(scene)
	while not scene.view_ready or scene.generating: await process_frame
	var data: Dictionary = scene.data; var surface := Earth.load_surface()
	check(data.options.terrain_model=="earth","scene used random planet")
	check(data.options.rainfall_model=="seasonal_circulation_v5" and data.options.settlement_model=="climate_capacity_v5","scene did not preserve requested historical climate v5")
	check(data.environment.rivers.is_empty(),"visible rivers returned")
	var counts := [0,0,0]
	for cell in range(data.mesh.n):
		var lon: float = data.mesh.x[cell]/2048.*360.-180.; var lat: float = 90.-data.mesh.y[cell]/1024.*180.
		var water := Earth.water_at(surface,lon,lat); counts[water] += 1
		check(data.environment.water[cell]==water,"Earth water changed")
		var expected := Earth.elevation_at(surface,lon,lat)
		if water==1: expected = minf(-1,expected)
		check(absf(data.environment.elevation[cell]-expected)<.002,"real elevation re-eroded")
	for road in data.roads:
		for cell in road.cells:
			check(data.environment.water[cell]==0,"land road crosses water")
			check(data.environment.biome[cell] not in [3,15],"land road crosses blocked ice")
	var payload := {"format":Snapshot.FORMAT,"version":Snapshot.VERSION,"data":data,"raster":scene.raster,"display":scene.display,"provinces":scene.provinces,"default_owners":scene.default_owners,"timing":scene.timing}
	check(Snapshot.validate(payload).is_empty(),"Earth snapshot validation")
	FileAccess.open("res://.dbg/atlas-native-generated-earth-rainfall-v5.bin",FileAccess.WRITE).store_var(payload,false)
	scene.hud.hide(); scene.fit_map()
	var directory := "res://docs/atlas/rainfall_v5/preview"; DirAccess.make_dir_recursive_absolute(directory)
	for mode in [0,1,2,3]:
		scene.mode_control.select(mode); scene.update_mode(); await process_frame; RenderingServer.force_draw(true)
		root.get_texture().get_image().save_png(directory+"/earth-mode-%d.png"%mode)
	for view in [["eurasia",3.,1200.,300.],["china",7.,1660.,345.],["mediterranean",7.,1150.,300.],["caspian",7.,1308.,273.],["congo",7.,1149.,512.]]:
		scene.mode_control.select(0); scene.update_mode(); scene.zoom = view[1]; scene.map_root.scale = Vector2.ONE*view[1]
		scene.map_root.position = Vector2(1024,512)-Vector2(view[2],view[3])*view[1]; scene.limit_pan(); scene.refresh_symbols()
		await process_frame; RenderingServer.force_draw(true); root.get_texture().get_image().save_png(directory+"/earth-%s.png"%view[0])
	print("EARTH_COUNTS ",data.mesh.n,"/",data.regions.count,"/",data.cities.size(),"/",data.roads.size()," land/ocean/lakes=",counts)
	print("ATLAS_NATIVE_EARTH_PREVIEW failures=",failures); quit(1 if failures else 0)
