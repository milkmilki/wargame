extends SceneTree
var scene
var failures := 0
var checks := 0
const DIRECTORY := "res://.dbg/world-naming"
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("ATLAS_NAMING_GPU_FAIL ",message)
func run():
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	var deadline := Time.get_ticks_msec()+60000
	while (not scene.view_ready or scene.overlay == null) and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.view_ready and scene.overlay != null, "real named military scene starts")
	if not scene.view_ready: quit(1); return
	scene.simulation.paused = true
	check(await scene.await_render_ready(30000), "named political rendering completes")
	var state: GameState = scene.state
	var mask: Dictionary = state.atlas_layout.data.options.settlement_mask
	check(state.world_seed == 1 and state.nations.size() == 40 and mask.enabled and mask.south == 20. and mask.north == 55. and mask.west == -15. and mask.east == 145., "GPU fixture is seed 1 / 40 countries / Eurasia mask")
	for id in range(state.nations.size()):
		var nation: Nation = state.nations[id]
		check(scene.data.nations[id].name == state.cities[nation.capital_city_id].short_name, "political map uses the capital-derived country name")
	var target := -1; var distance := INF
	for nation in state.nations:
		var d := state.cities[nation.capital_city_id].map_position.distance_squared_to(Vector2((108.+180.)/360.,(90.-32.)/180.))
		if d < distance: target = nation.capital_city_id; distance = d
	scene.show_information("city",target)
	check(scene.information_document().sections[0].rows.any(func(row): return row.label == "简称" and row.value == state.cities[target].short_name), "live state inspector shows the actual short name")
	scene.zoom = 4.; scene.map_root.scale = Vector2.ONE*4.
	scene.map_root.position = Vector2(920,360)-state.cities[target].map_position*Vector2(2048,1024)*4.
	scene.limit_pan()
	scene.text_layer.show_city_names = true; scene.text_layer.rebuild(); scene.refresh_symbols()
	check(await scene.await_render_ready(30000), "optional named city labels finish")
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	check(scene.text_layer.text_rows.any(func(row): return row.has("city_id")), "city-name switch renders actual city-name rows")
	root.get_texture().get_image().save_png(DIRECTORY+"/named-cities.png")
	FileAccess.open(DIRECTORY+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"capital":state.cities[target].name,"short":state.cities[target].short_name,"country":state.nations[state.cities[target].owner_nation].name,"countries":state.nations.map(func(nation): return {"name":nation.name,"capital":state.cities[nation.capital_city_id].name,"short":state.cities[nation.capital_city_id].short_name}),"renderer":RenderingServer.get_video_adapter_name()},"  "))
	print("ATLAS_WORLD_NAMING_GPU checks=",checks," failures=",failures," capital=",state.cities[target].name," short=",state.cities[target].short_name)
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
