extends SceneTree
## Run with a real rendering backend. Pixel oracle for array sampling and marker zoom.
const Native = preload("res://scripts/atlas/native_display.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
const Overlay = preload("res://scripts/atlas/military_overlay.gd")
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("ATLAS_GPU_TILES_FAIL ",message)
func settle():
	for i in range(4): await process_frame
	RenderingServer.force_draw(true)
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	check(RenderingServer.get_current_rendering_method()!="dummy","real GPU backend")
	var labels := PackedInt32Array(); labels.resize(2048*1024)
	for y in range(1024):
		for x in range(2048): labels[y*2048+x]=(x/128+y/128)%4 if (x+y)%23 else -2
	var texture_array := Texture2DArray.new()
	var images: Array[Image] = []
	for row in Native.label_tiles(labels,2048,1024,128,Native.all_tiles(2048,1024,128)):
		images.append(Image.create_from_data(128,128,false,Image.FORMAT_RF,row.bytes))
	check(texture_array.create_from_images(images)==OK,"RF array upload succeeds")
	var ids := Wash.texture(Wash.id_data(labels,2048,1024))
	var palette := Wash.color_texture(PackedInt32Array([0,1,2,3]),4,1,[Color.RED,Color.GREEN,Color.BLUE,Color.YELLOW])
	var blank := Image.create(2048,1024,false,Image.FORMAT_RGBA8); blank.fill(Color.WHITE)
	var base := ImageTexture.create_from_image(blank)
	var edge_values := PackedFloat32Array([100.]); var edge := ImageTexture.create_from_image(Image.create_from_data(1,1,false,Image.FORMAT_RF,edge_values.to_byte_array()))
	var symbols := ImageTexture.create_from_image(Image.create(16,16,false,Image.FORMAT_RGBA8))
	var views: Array = []
	for tiled in [false,true]:
		var view := SubViewport.new(); view.size=Vector2i(2048,1024); view.disable_3d=true; view.transparent_bg=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); views.append(view)
		var sprite := Sprite2D.new(); sprite.centered=false; sprite.texture=base
		var material := ShaderMaterial.new(); material.shader=preload("res://assets/atlas/wash.gdshader")
		material.set_shader_parameter("use_owner_palette",true)
		material.set_shader_parameter("use_owner_tiles",tiled)
		material.set_shader_parameter("owner_tiles",texture_array)
		material.set_shader_parameter("owner_ids",ids)
		material.set_shader_parameter("palette",palette)
		material.set_shader_parameter("view_zoom",1.)
		material.set_shader_parameter("edge_field",edge)
		material.set_shader_parameter("symbols",symbols)
		sprite.material=material; view.add_child(sprite)
	await settle()
	var a: PackedByteArray=views[0].get_texture().get_image().get_data()
	var b: PackedByteArray=views[1].get_texture().get_image().get_data()
	check(a==b,"all 2,097,152 GPU pixels match the original owner texture, including tile and longitude seams")
	# The original owner sampler repeats on both axes, including neighbor
	# probes just outside the world. Keep exactly that behavior in array mode.
	for shift in [".03125","-.03125"]:
		var shader := Shader.new()
		shader.code=preload("res://assets/atlas/wash.gdshader").code.replace("vec4 color=territory_color(TEXTURE,UV);","vec4 color=territory_color(TEXTURE,UV+vec2("+shift+"));")
		for view in views: view.get_child(0).material.shader=shader
		await settle()
		check(views[0].get_texture().get_image().get_data()==views[1].get_texture().get_image().get_data(),"periodic GPU pixels match beyond north/south/east/west seams "+shift)
	for id in [0,15,16,127]:
		check(texture_array.get_layer_data(id).get_data()==images[id].get_data(),"GPU RF layer retains exact bytes "+str(id))
	for view in views: view.queue_free()
	await settle()
	var state := GameState.new()
	var nation := Nation.new(); nation.id=0; nation.color=Color.RED; state.nations.append(nation)
	var city := City.new(); city.id=0; city.owner_nation=0; city.map_position=Vector2(64./2048,64./1024); state.cities.append(city)
	var army := Army.new(); army.id=9; army.owner_nation=0; army.location_city=0; army.size=10000; state.armies.append(army)
	var viewport := SubViewport.new(); viewport.size=Vector2i(256,256); viewport.transparent_bg=true; viewport.disable_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var overlay := Overlay.new(); overlay.state=state; viewport.add_child(overlay)
	for zoom in [1.,2.,4.]:
		overlay.scale=Vector2.ONE*zoom; overlay.position=Vector2(128,128)-Vector2(64,64)*zoom
		overlay.set_view(zoom,Rect2(-overlay.position/zoom,Vector2(256,256)/zoom))
		await settle()
		var image: Image=viewport.get_texture().get_image()
		check(image.get_pixel(128,128).r>.9 and image.get_pixel(128,128).a>.9,"instance center stays at the camera transformed position "+str(zoom))
		check(image.get_pixel(132,128).a>.9 and image.get_pixel(132,128).r<.25,"army outer ring remains visible "+str(zoom))
		check(image.get_pixel(135,128).a<.05,"army radius remains fixed in screen pixels "+str(zoom))
	var builds: int=overlay.army_build_count
	overlay.selection=9; await settle()
	check(overlay.army_build_count==builds,"GPU selection does not re-upload army instances")
	check(viewport.get_texture().get_image().get_pixel(136,128).a>.1,"selected inspection ring is actually rendered")
	overlay.selection=-1; await settle()
	check(viewport.get_texture().get_image().get_pixel(136,128).a<.05,"closing inspection removes only its ring")
	viewport.queue_free(); await settle()
	print("ATLAS_GPU_TILES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
