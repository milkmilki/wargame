extends SceneTree
var scene
var checks := 0
var failures := 0
const DIRECTORY := "res://.dbg/environment-nations"
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("ENVIRONMENT_GPU_FAIL ",message)
func measure_frames(count: int) -> Dictionary:
	var durations: Array[int] = []
	for _i in range(count):
		var started := Time.get_ticks_usec(); await process_frame
		durations.append(Time.get_ticks_usec()-started)
	durations.sort()
	var sum := 0
	for duration in durations: sum+=duration
	return {"average_ms":float(sum)/count/1000.,"p95_ms":durations[floori(count*.95)]/1000.,"peak_ms":durations.back()/1000.}
func run():
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	scene=load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	var deadline := Time.get_ticks_msec()+120000
	while (not scene.view_ready or scene.overlay==null) and Time.get_ticks_msec()<deadline: await process_frame
	check(scene.view_ready,"real military scene starts")
	if not scene.view_ready: quit(1); return
	scene.simulation.paused=true
	check(await scene.await_render_ready(60000),"real political rendering completes")
	var state: GameState=scene.state
	check(state.world_seed==1 and state.nations.size()==40,"seed 1 with 40 countries")
	var nomad := -1; var farm := -1
	for nation in state.nations:
		check(scene.data.nations[nation.id].name==nation.name,"map uses fixed country root")
		if nation.environment_kind=="nomad": nomad=nation.id
		if nation.environment_kind=="farm": farm=nation.id
	check(nomad>=0 and farm>=0,"real map has nomadic and agrarian countries")
	if nomad>=0:
		scene.show_information("nation",nomad)
		check(scene.information_document().title==state.nation_display_name(nomad),"real inspector uses tribal formal title")
	var frames := await measure_frames(120)
	scene.simulation.paused=false
	var running_frames := await measure_frames(240)
	scene.simulation.paused=true
	# Show every environmental vocabulary and its two tiers with the real font.
	var panel := PanelContainer.new(); panel.position=Vector2(590,170); panel.size=Vector2(340,340); panel.z_index=100
	var background := StyleBoxFlat.new(); background.bg_color=Color(0.97,0.97,0.94,0.96)
	background.content_margin_left=16.; background.content_margin_right=16.; background.content_margin_top=12.; background.content_margin_bottom=12.
	panel.add_theme_stylebox_override("panel",background)
	var rows := VBoxContainer.new(); panel.add_child(rows); root.add_child(panel)
	var heading := Label.new(); heading.text="建国环境 · 两级国号"; heading.add_theme_color_override("font_color",Color.BLACK); rows.add_child(heading)
	for kind in NationEnvironment.KINDS:
		var nation := Nation.new(); nation.name=str(RegionalNames.data().pools[kind].preferred).left(1); nation.short_name=nation.name; nation.environment_kind=kind
		var low := WorldNaming.nation_display_name(nation); nation.state_level=1
		var label := Label.new(); label.add_theme_font_override("font",load("res://assets/atlas/lxgw-wenkai-gb-500.ttf")); label.add_theme_font_size_override("font_size",25)
		label.add_theme_color_override("font_color",Color.BLACK)
		label.text="%s　%s → %s"%[NationEnvironment.LABELS[kind],low,WorldNaming.nation_display_name(nation)]; rows.add_child(label)
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(DIRECTORY+"/environment-titles.png")
	FileAccess.open(DIRECTORY+"/gpu.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"frames":frames,"running_frames":running_frames,"renderer":RenderingServer.get_video_adapter_name(),"metadata":state.generation_metadata},"  "))
	print("ENVIRONMENT_GPU checks=",checks," failures=",failures," frames=",frames," running_frames=",running_frames," renderer=",RenderingServer.get_video_adapter_name())
	root.remove_child(scene); scene.queue_free(); panel.queue_free(); await process_frame; quit(1 if failures else 0)
