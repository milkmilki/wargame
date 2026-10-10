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
	scene.simulation._set_coalition_war([1] as Array[int],[36] as Array[int]); await process_frame; await wait_ready()
	check(not scene.front_layer.fronts.is_empty(),"live war uses the persistent front layer")
	scene.history.reset(scene.state)
	var target := -1
	for city in scene.state.land_cities():
		if city.owner_nation==1 and scene.state.administrative_center_of(city.id)!=city.id: target = city.id; break
	check(target>=0,"fixture contains an independently occupiable府")
	if target<0: quit(1); return
	var labels := hash(scene.political_labels)
	var result: Dictionary = scene.state.apply_territory_transaction([{"city_id":target,"controller_id":36,"legal_owner_id":1,"sponsor_id":36,"reason":"renderer_visual_occupation"}] as Array[Dictionary])
	check(result.get("ok",false) and result.get("changed",false),"real occupation transaction commits")
	await process_frame
	if scene.political_pending: check(hash(scene.political_labels)==labels,"old picking/fill remains until atomic publication")
	await wait_ready()
	var point: Vector2 = scene.state.cities[target].map_position*Vector2(2048,1024)
	scene.select_at(point)
	check(scene.selected_region==target,"rendered辖区 remains selectable after occupation")
	check(scene.data.ownership[target]==36,"political data follows the new controller")
	for i in range(2,6): check(scene.copies[0].ink.persistent_layers[i].chunks[0].mesh==roads[i-2],"ownership and diplomacy retain existing road GPU resources")
	scene.history_control.value = 0; scene.show_history(); await wait_ready()
	check(scene.data.ownership[target]==1 and not scene.front_layer.fronts.is_empty(),"historical ownership and war are restored together")
	scene.historical_view = false; scene.overlay.state = scene.state; scene.last_owner_revision = -1; await process_frame; await wait_ready()
	check(scene.data.ownership[target]==36,"returning from history uses current ownership")
	for mode in [1,2,3,0,2,0]:
		scene.mode_control.select(mode); scene.update_mode(); await wait_ready()
	check(hash(scene.military_payload.graph)==graph and hash(scene.state.province_ids)==geography,"view changes preserve simulation geometry")
	check(scene.state.territory_structure_valid(),"real occupation retains territory invariants")
	print("ATLAS_RENDER_UPDATES failures=",failures," pid=",OS.get_process_id()," seed=",scene.state.world_seed)
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
func _initialize(): call_deferred("run")
