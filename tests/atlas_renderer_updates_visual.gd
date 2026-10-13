extends SceneTree
var scene
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_RENDER_UPDATE_FAIL ",message)
func wait_ready():
	check(await scene.await_render_ready(30000),"current render revision completes")
	await process_frame
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280,720); scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.overlay==null: await process_frame
	scene.simulation.paused = true; await wait_ready()
	var graph := hash(scene.military_payload.graph); var geography := hash(scene.state.province_ids)
	var roads: Array = []
	for i in range(2,6): roads.append(scene.copies[0].ink.persistent_layers[i].chunks[0].mesh)
	var target := -1; var former_owner := -1; var controller := -1
	# The agreed Eurasia fixture has a different country layout from the old
	# global fixture. Choose adjacent countries with an actual occupiable府.
	for border in scene.display.lines:
		if border.left<0 or border.right<0 or border.left==border.right: continue
		for city in scene.state.land_cities():
			if city.owner_nation==border.left and scene.state.administrative_center_of(city.id)!=city.id:
				target=city.id; former_owner=border.left; controller=border.right; break
		if target>=0: break
	check(target>=0,"fixture contains an independently occupiable府")
	if target<0: quit(1); return
	scene.simulation._set_coalition_war([former_owner] as Array[int],[controller] as Array[int]); await process_frame; await wait_ready()
	check(not scene.front_layer.fronts.is_empty(),"live war uses the persistent front layer")
	scene.history.reset(scene.state)
	var labels := hash(scene.political_labels)
	var old_buffer: int = scene.political_buffer_index
	var uploads: int = scene.political_upload_count
	scene.render_scheduler.frame_budget_usec=1 # Deliberately spread staging uploads.
	var result: Dictionary = scene.state.apply_territory_transaction([{"city_id":target,"controller_id":controller,"legal_owner_id":former_owner,"sponsor_id":controller,"reason":"renderer_visual_occupation"}] as Array[Dictionary])
	check(result.get("ok",false) and result.get("changed",false),"real occupation transaction commits")
	await process_frame
	if scene.political_pending:
		check(hash(scene.political_labels)==labels,"old picking/fill remains until atomic publication")
		check(scene.political_buffer_index==old_buffer,"the visible GPU array remains unchanged while staging")
	var deadline := Time.get_ticks_msec()+30000
	while scene.political_pending and scene.political_upload_count==uploads and Time.get_ticks_msec()<deadline: await process_frame
	check(scene.political_upload_count>uploads and scene.political_pending,"a real occupation uploads a staging tile before publication")
	check(scene.political_buffer_index==old_buffer and hash(scene.political_labels)==labels,"partial uploads preserve both displayed fill and picking")
	# Invalidate after at least one real GPU upload, then repair that same buffer.
	scene.refresh_ownership()
	scene.render_scheduler.frame_budget_usec=4000
	await wait_ready()
	check(scene.render_scheduler.stale_results>0,"a cancelled upload batch cannot publish its stale commit")
	for id in range(128):
		check(scene.political_buffers[scene.political_buffer_index].get_layer_data(id).get_data()==scene.political_cache.tiles[id],"committed GPU tile equals the accepted CPU revision")
	var point: Vector2 = scene.state.cities[target].map_position*Vector2(2048,1024)
	scene.select_at(point)
	check(scene.selected_region==target,"rendered辖区 remains selectable after occupation")
	check(scene.data.ownership[target]==controller,"political data follows the new controller")
	for i in range(2,6): check(scene.copies[0].ink.persistent_layers[i].chunks[0].mesh==roads[i-2],"ownership and diplomacy retain existing road GPU resources")
	scene.history_control.value = 0; scene.show_history(); await wait_ready()
	check(scene.data.ownership[target]==former_owner and not scene.front_layer.fronts.is_empty(),"historical ownership and war are restored together")
	scene.historical_view = false; scene.overlay.state = scene.state; scene.last_owner_revision = -1; await process_frame; await wait_ready()
	check(scene.data.ownership[target]==controller,"returning from history uses current ownership")
	for mode in [1,2,3,0,2,0]:
		scene.mode_control.select(mode); scene.update_mode(); await wait_ready()
	check(hash(scene.military_payload.graph)==graph and hash(scene.state.province_ids)==geography,"view changes preserve simulation geometry")
	check(scene.state.territory_structure_valid(),"real occupation retains territory invariants")
	print("ATLAS_RENDER_UPDATES failures=",failures," pid=",OS.get_process_id()," seed=",scene.state.world_seed)
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
func _initialize(): call_deferred("run")
