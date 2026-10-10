extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_STATIC_FAIL ",message)
func _initialize(): call_deferred("run")
func wait_ready(layer):
	var deadline := Time.get_ticks_msec()+5000
	while not layer.is_ready() and Time.get_ticks_msec()<deadline: await process_frame
	check(layer.is_ready(),"static layer publication completes")
func run():
	var service := preload("res://scripts/atlas/render_scheduler.gd").new(); root.add_child(service)
	var layer := preload("res://scripts/atlas/map_text.gd").new(); root.add_child(layer)
	layer.high_performance=true; layer.static_world=true; layer.scheduler=service
	var water := PackedByteArray(); water.resize(2048*1024); water.fill(1)
	layer.raster={"water":water}; layer.owners.resize(water.size()); layer.owners.fill(0)
	layer.data={"cities":[{"region":0,"cell":0,"major":false,"name":"甲城"}],"ownership":[0],"nations":[{"seat":0,"color":[100,80,60]}],"mesh":{"x":[100.],"y":[100.]},"places":[{"kind":"sea","rank":1,"name":"海","size":100.,"path":[500.,200.,550.,200.]}]}
	layer.labels=[{"polity":0,"text":"甲国","regions":1,"size":15.,"vertical":false,"path":[100.,100.,300.,100.]}]
	layer.rebuild(); layer.set_camera(Vector2.ZERO,1.,Vector2(1280,720)); await wait_ready(layer)
	check(not layer.static_geography.rows.is_empty() and not layer.static_countries.rows.is_empty(),"natural and country names have independent persistent drawings")
	var geo: int=hash(layer.static_geography.rows); var builds: int=layer.static_build_count
	var marker_hash: int=hash(layer.city_markers.layers[4].mesh.buffer)
	for i in range(50):
		layer.set_camera(Vector2(-i*100,0),[.625,1.,2.,4.,8.][i%5],Vector2(1280,720))
		await process_frame
	check(layer.static_build_count==builds and layer.layout_count==0,"pan, zoom and new regions never prepare fixed names")
	check(hash(layer.city_markers.layers[4].mesh.buffer)==marker_hash,"camera retains all-world marker buffers")
	check(layer.hit_city(Vector2(100,100))==0 and layer.hit_city(Vector2(2148,100))==0,"static markers retain click targets across the seam")
	layer.show_polities=false; layer.rebuild(); await wait_ready(layer)
	check(not layer.static_countries.visible and layer.static_geography.visible and layer.static_build_count==builds,"mode switches only toggle country drawing visibility")
	layer.show_polities=true; layer.labels[0].text="乙国"; layer.rebuild(); await wait_ready(layer)
	check(layer.static_build_count==builds+1 and hash(layer.static_geography.rows)==geo,"country changes do not lay out natural names again")
	layer.show_city_names=true; layer.rebuild(); layer.set_camera(Vector2.ZERO,4.,Vector2(1280,720)); await wait_ready(layer)
	check(layer.text_rows.any(func(row): return row.has("city_id")),"opt-in settlement names retain their dynamic layout")
	layer.show_city_names=false; layer.rebuild(); await wait_ready(layer)
	check(layer.text_rows.is_empty() and layer.label_chunks.is_empty(),"hiding names clears previously accepted settlement text")
	root.remove_child(layer); layer.free(); await process_frame
	var output := SubViewport.new(); output.size=Vector2i(256,256); root.add_child(output)
	var screen := Sprite2D.new(); screen.centered=false; root.add_child(screen)
	var symbols := preload("res://scripts/atlas/symbol_tiles.gd").new(); symbols.static_world=true; symbols.world_screen=screen; root.add_child(symbols)
	symbols.setup({"seed":1,"mesh":{"spacing":1.,"x":[],"y":[],"adj_start":[0],"adj":[]},"environment":{"water":[]}}, {"forest":PackedByteArray(),"glyphs":[]},service,output)
	await wait_ready(symbols)
	var texture: Texture2D=screen.texture
	for i in range(20): symbols.set_camera(Vector2(-i*100,0),[1.,2.,4.,8.][i%4],Vector2(1280,720)); await process_frame
	check(symbols.tile_build_count==1 and symbols.group_update_count==1 and screen.texture==texture,"global symbols reuse one frozen drawing at every camera position")
	check(symbols.world_copies.size()==2 and symbols.groups.is_empty(),"seam copies share the image without viewport compositors")
	# Dummy renderer cannot compile the production shader's TEXTURE helper.
	# Real GPU lifecycle tests exercise wash.gdshader; here verify binding only.
	var material := ShaderMaterial.new(); material.shader=Shader.new()
	material.shader.code="shader_type canvas_item; uniform sampler2D symbols; uniform bool symbols_world=false; uniform float symbol_world_pad=0.; uniform float symbol_world_detail=4.;"
	symbols.bind_world_material(material)
	check(material.get_shader_parameter("symbols_world")==true and material.get_shader_parameter("symbols")==texture,"political mask samples the same fixed symbol image")
	root.remove_child(symbols); symbols.free(); root.remove_child(screen); screen.free(); root.remove_child(output); output.free(); await process_frame
	check(service.cache_bytes==0,"static world resources leave the cache on disposal")
	root.remove_child(service); service.free()
	print("ATLAS_STATIC_LAYERS failures=",failures); quit(1 if failures else 0)
