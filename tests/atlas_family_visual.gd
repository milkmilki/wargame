extends SceneTree
## Manual real-renderer evidence: run without --headless. Screenshots in .dbg/.
func _initialize(): call_deferred("run")
func capture(path: String):
	for i in range(4): await process_frame
	RenderingServer.force_draw(true); root.get_texture().get_image().save_png(path)
func run():
	if DisplayServer.get_name()=="headless": printerr("FAMILY_VISUAL_REQUIRES_GPU"); quit(1); return
	root.size=Vector2i(1280,720)
	var view=load("res://atlas_military.tscn").instantiate(); root.add_child(view)
	while not view.view_ready or view.generating: await process_frame
	view.simulation.paused=true; view.simulation.set_process(false)
	assert(view.state.world_seed==1)
	assert(view.state.atlas_layout.data.options.settlement_mask.enabled)
	if not await view.await_render_ready(15000): printerr("GPU_NOT_READY"); quit(1); return
	preload("res://tests/ruler_family_fixture.gd").ensure_candidates(view.state,0,3)
	view.show_information("nation",0)
	await capture("res://.dbg/family-country.png")
	view.family_panel.open(0)
	await capture("res://.dbg/family-1280.png")
	var player_before: float=view.player_nation.value
	var target_before: int=view.command_target
	var key:=InputEventKey.new(); key.keycode=KEY_SPACE; key.pressed=true
	view.family_panel.search.grab_focus(); root.push_input(key,true)
	assert(not view.simulation.paused)
	key.pressed=false; root.push_input(key,true); key.pressed=true; root.push_input(key,true)
	assert(view.simulation.paused)
	key.pressed=false; root.push_input(key,true)
	var right:=InputEventMouseButton.new(); right.button_index=MOUSE_BUTTON_RIGHT; right.position=Vector2(450,350); right.pressed=true
	root.push_input(right,true); right.pressed=false; root.push_input(right,true)
	assert(view.player_nation.value==player_before and view.command_target==target_before)
	root.size=Vector2i(900,600)
	await capture("res://.dbg/family-900-person.png")
	view.family_panel.inspector.hide(); view.family_panel.canvas.show()
	view.family_panel.canvas.fit_all()
	await capture("res://.dbg/family-900-tree.png")
	root.size=Vector2i(1280,720); view.family_panel.close()
	var n: Nation=view.state.nations[0]
	var challenger: int=n.prince_person_ids[1]
	PrincePolitics.person(view.state,0,challenger).archetype=RulerProfile.CONQUEROR
	var a: Army=view.state.create_army(0,n.capital_city_id,15000); a.political_person_id=challenger
	var b: Army=view.state.create_army(0,n.capital_city_id,5000); b.political_person_id=n.crown_prince_person_id
	assert(SuccessionRules.begin_preparation(view.state,0,challenger))
	view.history.reset(view.state)
	var conflict: SuccessionConflict=view.state.succession_conflicts[0]
	view.state.day+=1; view.simulation._update_succession_conflicts()
	view.show_information("nation",0)
	for i in range(4): await process_frame
	view.info_panel.scroll.scroll_vertical=400
	await capture("res://.dbg/family-conflict.png")
	view.history_control.value=0; view.show_history(); view.show_information("nation",0)
	view.info_panel.scroll.scroll_vertical=400
	await capture("res://.dbg/family-history-conflict.png")
	assert(preload("res://scripts/atlas/information_model.gd").prince_report(view.information_source(),0).internal_battle.round==0)
	view.return_to_current()
	for day in range(120):
		view.state.day+=1; view.simulation._update_succession_conflicts()
		if not view.state.succession_conflicts.has(0): break
	assert(not view.state.succession_conflicts.has(0))
	assert(a.size==15000 and b.size==5000 and view.state.battles.is_empty())
	view.show_information("nation",0); view.info_panel.scroll.scroll_vertical=500
	await capture("res://.dbg/family-result.png")
	print("FAMILY_GPU_OK seed=",view.state.world_seed," layouts=",view.family_panel.canvas.layout_count)
	root.remove_child(view); view.queue_free(); await process_frame; quit()
