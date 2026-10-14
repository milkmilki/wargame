extends SceneTree
## Render seam-crossing symbols once, then compare the assembled world image
## against independently drawn, overlapping viewport crops at the same detail.
const Tiles = preload("res://scripts/atlas/symbol_tiles.gd")
const State = preload("res://scripts/atlas/symbol_state.gd")
var failures := 0
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("ATLAS_SYMBOL_BAKE_GPU_FAIL ",message)
func _initialize(): call_deferred("run")
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var service := preload("res://scripts/atlas/render_scheduler.gd").new(); root.add_child(service)
	var screen := Sprite2D.new(); screen.centered=false; root.add_child(screen)
	var output := SubViewport.new(); output.size=Vector2i(256,256); root.add_child(output)
	var data := {"seed":1,"mesh":{"spacing":4.,"x":[254.,258.,2047.,1.,1023.],"y":[256.,257.,200.,200.,1023.],"adj_start":[0,0,0,0,0,0],"adj":[]},"environment":{"water":[0,0,0,0,0]}}
	var glyphs: Array=[]
	for point in [Vector2(255,253),Vector2(257,258),Vector2(2047,198),Vector2(1,202),Vector2(1024,1022)]:
		glyphs.append({"x":point.x,"y":point.y,"s":9.,"kind":0,"z":1.,"a":.4,"c":.3,"v":.7})
	var display := {"forest":PackedByteArray([1,2,3,1,2]),"glyphs":glyphs}
	var world := Tiles.new(); world.static_world=true; world.world_screen=screen; root.add_child(world)
	world.setup(data,display,service,output)
	var deadline := Time.get_ticks_msec()+30000
	while not world.is_ready() and Time.get_ticks_msec()<deadline: await process_frame
	check(world.is_ready(),"bounded world bake completes")
	if not world.is_ready(): quit(1); return
	var image: Image=screen.texture.get_image()
	check(image!=null and image.get_size()==Vector2i(8194,4098),"world retains fourfold detail and one-pixel sampling margin")
	var before: int=world.tile_build_count
	# Reference crops straddle both bake-grid seams and the longitude seam.
	for rect in [Rect2(128,128,256,256),Rect2(0,128,256,256),Rect2(1792,128,256,256),Rect2(896,768,256,256)]:
		var reference := Tiles.new(); reference.data=data; reference.display=display; reference.scheduler=service; root.add_child(reference)
		var geometry := State.tile({"data":data,"glyphs":glyphs,"forest":display.forest,"cells":PackedInt32Array([0,1,2,3,4]),"detail":4.,"rect":rect.grow(32.)})
		reference.create_tile("reference",rect,4.,false,geometry,128)
		deadline=Time.get_ticks_msec()+10000
		while not reference.entries.reference.registered and Time.get_ticks_msec()<deadline: await process_frame
		check(reference.entries.reference.registered,"reference viewport finishes")
		var expected: Image=reference.entries.reference.texture.get_image()
		var actual := image.get_region(Rect2i(Vector2i(rect.position*4.),Vector2i(rect.size*4.)+Vector2i.ONE*2))
		var mismatch := 0; var delta := 0.
		if actual.get_data()!=expected.get_data():
			var bounds := Rect2i()
			for y in range(actual.get_height()):
				for x in range(actual.get_width()):
					var a := actual.get_pixel(x,y); var b := expected.get_pixel(x,y)
					if a==b: continue
					mismatch+=1; delta=maxf(delta,maxf(maxf(absf(a.r-b.r),absf(a.g-b.g)),maxf(absf(a.b-b.b),absf(a.a-b.a))))
					bounds=Rect2i(x,y,1,1) if mismatch==1 else bounds.expand(Vector2i(x,y))
			print("SYMBOL_PIXEL_DIFF rect=",rect," pixels=",mismatch," max_delta=",delta," bounds=",bounds," formats=",actual.get_format(),"/",expected.get_format())
		# Different viewport origins introduce isolated RGBA8 rounding changes:
		# one step on RD, two with GL's non-MSAA transparent compositing.
		var quantization := 2. if RenderingServer.get_current_rendering_method()=="gl_compatibility" else 1.
		check(delta<=quantization/255.+.000001 and mismatch<actual.get_width()*actual.get_height()*.001,"assembled symbols match full crop across "+str(rect))
		root.remove_child(reference); reference.free(); await process_frame
	for detail in [1.,2.,4.,8.]: world.set_camera(Vector2(-400,20),detail,Vector2(1280,720))
	check(world.tile_build_count==before,"camera retains the frozen assembled image")
	root.remove_child(world); world.free(); root.remove_child(screen); screen.free(); root.remove_child(output); output.free()
	await process_frame; await process_frame
	check(service.cache_bytes==0,"bake and world texture are released")
	root.remove_child(service); service.free()
	print("ATLAS_SYMBOL_BAKE_GPU checks=",checks," failures=",failures); quit(1 if failures else 0)
