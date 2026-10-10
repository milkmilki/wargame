extends SceneTree
## End-to-end native GPU input, palette coverage, version changes and history.
var scene
var failures := 0
var directory := "res://.dbg/interaction-ui"
var captures: Array=[]
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_INTERACTION_GPU_FAIL ",message)
func ready():
	check(await scene.await_render_ready(60000),"current viewport becomes ready")
	await process_frame; await process_frame
func capture(name_value: String):
	await ready(); RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png"); captures.append(name_value)
func camera(center: Vector2,z: float):
	scene.zoom=z; scene.map_root.scale=Vector2.ONE*z; scene.map_root.position=Vector2(830,370)-center*z
	scene.limit_pan(); scene.refresh_symbols(); await ready()
func click(point: Vector2,button: int = MOUSE_BUTTON_LEFT):
	var event := InputEventMouseButton.new(); event.position=scene.map_root.to_global(point); event.button_index=button; event.pressed=true
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await process_frame
func empty_land() -> Vector2:
	for y in range(155,520,12):
		for x in range(450,820,12):
			var p: Vector2=scene.map_root.to_local(Vector2(x,y)); var hit: Dictionary=scene.pick_map(p)
			if hit.kind=="nation": return p
	return Vector2(-1,-1)
func visible_city() -> int:
	for row in scene.text_layer.city_markers.hit_boxes:
		var id: int=row.id; var p: Vector2=scene.state.cities[id].map_position*Vector2(2048,1024)
		var screen: Vector2=scene.map_root.to_global(p)
		if Rect2(420,135,450,400).has_point(screen) and scene.pick_map(p).kind=="city": return id
	return -1
func palette_probe():
	# A transparent native GPU surface proves that interior pixels use the ID
	# lookup, rather than merely checking a uniform or curved-edge code path.
	var wash = preload("res://scripts/atlas/wash.gd")
	var viewport := SubViewport.new(); viewport.size=Vector2i(32,16); viewport.transparent_bg=true; viewport.disable_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var sprite := Sprite2D.new(); sprite.centered=false; sprite.scale=Vector2.ONE*16.; viewport.add_child(sprite)
	sprite.texture=wash.color_texture(PackedInt32Array([0,1]),2,1,[Color.RED,Color.GREEN])
	var material := ShaderMaterial.new(); material.shader=load("res://assets/atlas/wash.gdshader"); sprite.material=material
	material.set_shader_parameter("map_size",Vector2(2,1)); material.set_shader_parameter("use_owner_palette",true)
	material.set_shader_parameter("owner_ids",wash.texture(wash.id_data(PackedInt32Array([0,1]),2,1)))
	material.set_shader_parameter("palette",wash.color_texture(PackedInt32Array([0,1]),2,1,[Color.BLUE,Color.BLACK]))
	var fields := Image.create(1,1,false,Image.FORMAT_RGBAF); fields.fill(Color(1,0,0,0)); material.set_shader_parameter("world_fields",ImageTexture.create_from_image(fields))
	var symbols := Image.create(1,1,false,Image.FORMAT_RGBA8); symbols.fill(Color(1,1,1,0)); material.set_shader_parameter("symbols",ImageTexture.create_from_image(symbols))
	material.set_shader_parameter("edge_field",wash.texture({"w":1,"h":1,"format":Image.FORMAT_RF,"bytes":PackedFloat32Array([100.]).to_byte_array()}))
	var grid := Image.create(2,2,false,Image.FORMAT_RGBAF); grid.fill(Color(0,0,0,0)); material.set_shader_parameter("segment_grid",ImageTexture.create_from_image(grid))
	for z in [1.,4.]:
		material.set_shader_parameter("view_zoom",z); await process_frame; await process_frame; RenderingServer.force_draw(true)
		var image: Image=viewport.get_texture().get_image(); var left := image.get_pixel(8,8); var right := image.get_pixel(24,8)
		# SubViewport readback is premultiplied; compare the unassociated color.
		check(left.a>.05 and left.b/maxf(.001,left.a)>.9 and left.r<.05*left.a and right.a>.05 and maxf(right.r,maxf(right.g,right.b))<.05*right.a,"GPU interior and zoomed band share diplomatic palette at %dx"%z)
		image.save_png(directory+"/palette-probe-%dx.png"%z)
	viewport.queue_free(); await process_frame
func run():
	root.size=Vector2i(1280,720); DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await palette_probe()
	var started := Time.get_ticks_msec()
	scene=load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.overlay==null or scene.generating: await process_frame
	scene.simulation.paused=true; await ready()
	var startup_ms := Time.get_ticks_msec()-started
	var graph := hash(scene.military_payload.graph); var administrative := hash(scene.state.province_ids)
	await capture("global-ordinary")
	for z in [1.,2.,4.,8.]:
		await camera(Vector2(1685,338),z); await capture("china-%dx"%z)
	await camera(Vector2(1685,338),4.)
	var p := empty_land(); check(p.y>=0,"visible territory without a symbol exists")
	var hit: Dictionary=scene.pick_map(p,false); var owner: int=hit.owner_id
	var controlled: float=scene.player_nation.value
	await click(p)
	check(scene.information_kind=="nation" and scene.information_id==owner and scene.diplomatic_observer==owner,"real territory click opens country and its diplomacy view")
	check(scene.player_nation.value==controlled,"inspecting another country preserves controlled nation")
	check(scene.mode_cache[0].material.get_shader_parameter("use_owner_palette"),"the interior uses the same owner palette as the curve band")
	var revision: int=scene.political_revision; var ids=scene.political_id_texture; var borders=scene.political_index
	var updates: int=scene.diplomacy_palette_updates
	for i in range(6): scene.show_information("nation",(owner+i)%scene.state.nations.size())
	check(scene.political_revision==revision and scene.political_id_texture==ids and scene.political_index==borders,"selection only changes a small palette, never political geometry")
	check(scene.diplomacy_palette_updates>updates,"new observer publishes a new palette")
	scene.show_information("nation",owner); await capture("nation-diplomacy")
	var city := visible_city(); check(city>=0,"a visible city can be picked")
	if city>=0:
		await click(scene.state.cities[city].map_position*Vector2(2048,1024))
		check(scene.information_kind=="city" and scene.information_id==city,"real city marker opens its administrative card")
		await capture("city")
	var army := -1
	for unit in scene.state.armies:
		if unit.owner_nation==int(scene.player_nation.value) and unit.size>0: army=unit.id; break
	if army>=0:
		scene.selected_army=army
		var kind: String=scene.information_kind; var id: int=scene.information_id
		await click(p,MOUSE_BUTTON_RIGHT)
		check(scene.command_target==hit.district_id and scene.information_kind==kind and scene.information_id==id,"right click picks its own destination without replacing the inspector")
	scene.mode_control.select(2); scene.update_mode(); await ready()
	scene.select_at(p); check(scene.information_kind=="city","district empty ground opens district information")
	await capture("district")
	for mode in [1,3,0]:
		scene.mode_control.select(mode); scene.update_mode(); await ready(); await capture("mode-%d"%mode)
	scene.interface.countries.open(); await capture("countries")
	var rows: Array=scene.Diplomacy.rows(scene.state,scene.diplomatic_observer)
	if not rows.is_empty():
		scene.interface.countries.search.text=rows[0].name; scene.interface.countries.refresh()
		check(scene.interface.countries.entries.values().filter(func(b): return b.visible).size()==1,"country name search updates visible entries")
	scene.interface.countries.hide()
	# Exercise real diplomacy lifecycle without changing military rules.
	scene.simulation._set_coalition_war([1] as Array[int],[36] as Array[int]); await process_frame; await ready()
	scene.show_information("nation",1)
	check(scene.Diplomacy.kind(scene.state,1,36)=="enemy" and not scene.front_layer.fronts.is_empty(),"real war updates relations and keeps the hand-drawn front")
	await camera(Vector2(1060,225),2.); await capture("europe-front")
	if not scene.front_layer.fronts.is_empty():
		var path: PackedVector2Array=scene.front_layer.fronts[0].path
		await camera(path[path.size()/2],4.); await capture("front-closeup")
	scene.history.reset(scene.state)
	var target := -1
	for c in scene.state.land_cities():
		if c.owner_nation==1 and scene.state.administrative_center_of(c.id)!=c.id: target=c.id; break
	if target>=0:
		var change: Dictionary=scene.state.apply_territory_transaction([{"city_id":target,"controller_id":36,"legal_owner_id":1,"sponsor_id":36,"reason":"interaction_visual"}] as Array[Dictionary])
		check(change.get("ok",false),"real occupation commits")
		await process_frame; await ready()
		var pick: Dictionary=scene.pick_map(scene.state.cities[target].map_position*Vector2(2048,1024),false)
		check(pick.owner_id==36,"occupation changes the picked controller")
		scene.show_information("city",target); check(scene.diplomatic_observer==36,"occupied district observes its actual controller")
	scene.set_time_speed(4.); scene.history_control.value=0; scene.show_history(); await ready()
	check(scene.information_source()!=scene.state and scene.simulation.paused,"historical inspection reads a separate political snapshot")
	if target>=0: check(scene.diplomatic_observer==1,"historical district inspection observes historical controller")
	if target>=0: check(scene.information_source().cities[target].owner_nation==1,"historical ownership does not read current occupation")
	check(scene.interface.speed_buttons.all(func(b): return b.node.disabled),"historical speed controls disabled")
	await capture("history")
	scene.return_to_current(); await process_frame; await ready()
	check(scene.simulation.paused and scene.simulation.speed_multiplier()==4.,"return preserves pause and chosen multiplier")
	if target>=0: check(scene.diplomatic_observer==36,"returning current district uses current controller")
	var day: int=scene.state.day
	scene.step_day(); scene.step_day()
	while scene.simulation.runtime_day_in_progress(): await process_frame
	check(scene.state.day==day+1,"real daily simulation commits exactly once")
	await ready()
	var seam_y := 450.; var nearest_seam := INF
	for c in scene.state.land_cities():
		var seam_point: Vector2=c.map_position*Vector2(2048,1024); var distance := minf(seam_point.x,2048-seam_point.x)
		if distance<nearest_seam: nearest_seam=distance; seam_y=seam_point.y
	await camera(Vector2(2045,seam_y),4.); await capture("longitude")
	scene.close_information(); scene.info_panel.hide()
	await camera(Vector2(1685,338),4.)
	root.size=Vector2i(900,600); await process_frame; await ready()
	scene.interface.countries.open(); await capture("compact-countries")
	check(scene.interface.toolbar.get_global_rect().end.x<=900 and scene.interface.toolbar.get_global_rect().end.y<130,"two-row toolbar fits compact viewport")
	check(scene.interface.countries.get_global_rect().end.x<=900 and scene.interface.countries.get_global_rect().end.y<=600,"country browser fits compact viewport")
	check(scene.interface.countries.get_global_rect().end.y<=scene.interface.footer.get_global_rect().position.y,"footer does not cover country rows")
	scene.interface.countries.hide(); scene.interface.tools.show(); await capture("compact-tools")
	check(hash(scene.military_payload.graph)==graph and hash(scene.state.province_ids)==administrative,"all interactions preserve geography and traffic graph")
	var result := {"pid":OS.get_process_id(),"scene":scene.scene_file_path,"seed":scene.state.world_seed,"godot":Engine.get_version_info().string,"failures":failures,"captures":captures,"palette_updates":scene.diplomacy_palette_updates,"startup_ms":startup_ms,"startup_profile":scene.startup_profile,"parameters":scene.state.generation_metadata}
	FileAccess.open(directory+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t")); print("ATLAS_INTERACTION_GPU ",JSON.stringify(result))
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
