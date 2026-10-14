extends SceneTree
## Real GPU integration on the agreed seed 1 / 40-country Eurasia map.
## Campaign origins are controlled fixtures at real settlement coordinates.
var scene
var checks := 0
var failures := 0
const DIRECTORY := "res://.dbg/attack-arrows"
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("ATTACK_ARROW_GPU_FAIL ", message)
func capture(name_value: String):
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(DIRECTORY+"/"+name_value+".png")
func samples(visible_value: bool) -> Dictionary:
	scene.attack_arrows.visible = visible_value
	for i in range(25): await process_frame
	var values: Array = []; var before := Time.get_ticks_usec()
	for i in range(120):
		await process_frame
		var now := Time.get_ticks_usec(); values.append((now-before)/1000.); before = now
	values.sort()
	return {"median_ms":values[60],"p95_ms":values[114]}
func run():
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	var deadline := Time.get_ticks_msec()+60000
	while (not scene.view_ready or scene.overlay == null) and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.view_ready and scene.overlay != null, "military scene starts")
	if not scene.view_ready: quit(1); return
	scene.simulation.paused = true
	check(await scene.await_render_ready(30000), "initial real GPU publication completes")
	var state: GameState = scene.state
	var mask: Dictionary = state.atlas_layout.data.options.settlement_mask
	check(state.world_seed == 1 and state.nations.size() == 40 and mask.enabled and mask.south == 20. and mask.north == 55. and mask.west == -15. and mask.east == 145., "real fixture uses agreed seed, countries and Eurasia mask")
	var centers := {}; var focal := Vector2.ZERO
	for coordinates in [Vector2(109,28),Vector2(105,36),Vector2(119,34)]:
		var desired := Vector2((coordinates.x+180.)/360.,(90.-coordinates.y)/180.)
		var target := -1; var distance := INF
		for id in state.administrative_center_city_ids:
			var d := state.cities[id].map_position.distance_squared_to(desired)
			if d < distance and not centers.has(id): target = id; distance = d
		var defender := state.cities[target].owner_nation
		var origin := -1; distance = INF
		for city in state.land_cities():
			if city.owner_nation == defender: continue
			var d := city.map_position.distance_squared_to(state.cities[target].map_position)
			if d < distance: origin = city.id; distance = d
		var attacker := state.cities[origin].owner_nation
		# A real rear settlement in that same country makes a representative
		# mobilization axis, rather than a tiny arrow from the border's closest府.
		var desired_distance := 50.
		distance = INF
		for city in state.land_cities():
			if city.owner_nation != attacker: continue
			var d := absf((city.map_position-state.cities[target].map_position).length()*2048.-desired_distance)
			if d < distance: origin = city.id; distance = d
		state.set_diplomatic_relation(attacker,defender,GameState.DiplomaticRelation.WAR)
		var war := state.set_war_objective(attacker,defender,target,"attack arrow GPU fixture")
		var front := state.create_campaign_front(war,[attacker] as Array[int],attacker,CoalitionCampaignFront.Mode.OFFENSE,target)
		front.staging_city_id = origin
		centers[target] = true; focal += (state.cities[target].map_position+state.cities[origin].map_position)/2.
	var rng_before := state.rng.state
	var started := Time.get_ticks_usec(); scene.refresh_attack_arrows(true)
	var creation_usec := Time.get_ticks_usec()-started
	check(scene.attack_arrows.rows.size() == 3, "all three actual offensive execution plans appear")
	var builds: int = scene.attack_arrows.geometry_build_count
	var publications: int = scene.attack_arrows.publication_count
	scene.zoom = 4.; scene.map_root.scale = Vector2.ONE*4.
	scene.map_root.position = Vector2(root.size)*.5-focal/3.*Vector2(2048,1024)*4.
	scene.limit_pan(); scene.camera_feedback()
	check(await scene.await_render_ready(30000), "political view settles")
	await capture("political4")
	# Suppress preview _process during drawing windows so it cannot restore the
	# hidden layer. Other map layers continue their normal processing.
	scene.set_process(false)
	var with_arrows := await samples(true)
	var without_arrows := await samples(false)
	var repeated_with_arrows := await samples(true)
	scene.set_process(true)
	for i in range(40):
		scene.map_root.position.x += 3.
		scene.zoom = [1.,2.,4.,8.][i % 4]; scene.map_root.scale = Vector2.ONE*scene.zoom
		scene.refresh_attack_arrows(); await process_frame
	check(scene.attack_arrows.geometry_build_count == builds and scene.attack_arrows.publication_count == publications, "camera input reuses both meshes and drawing commands")
	for mode in [1,2,3,4,0]:
		scene.mode_control.select(mode); scene.update_mode()
		check(scene.attack_arrows.visible == (mode == 0), "attack plans only appear in political mode")
	scene.historical_view = true; scene.refresh_attack_arrows()
	check(not scene.attack_arrows.visible, "political history cannot display current future military plans")
	scene.historical_view = false; scene.refresh_attack_arrows()
	check(scene.attack_arrows.visible, "returning to present restores real offensive plans")
	check(state.rng.state == rng_before, "all display changes leave random stream unchanged")
	var old_layer: Node2D = scene.attack_arrows
	await scene.load_cached_payload(scene.military_payload)
	check(not is_instance_valid(old_layer) and scene.attack_arrows.rows.is_empty(), "world replacement frees old arrow meshes and references")
	var result := {"checks":checks,"failures":failures,"creation_usec":creation_usec,"first_with_arrows":with_arrows,"without_arrows":without_arrows,"with_arrows":repeated_with_arrows,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"three controlled offense fronts at real settlement coordinates; seed 1, 40 countries, Eurasia mask"}
	FileAccess.open(DIRECTORY+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("ATLAS_ATTACK_ARROW_GPU ",JSON.stringify(result))
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
