extends SceneTree
var scene
var directory := "res://docs/atlas/military_evidence"
func _initialize() -> void: call_deferred("run")
func capture(name_value: String,center: Vector2,zoom_value: float = 8.) -> void:
	scene.zoom = zoom_value; scene.map_root.scale = Vector2.ONE*zoom_value
	scene.map_root.position = Vector2(1024,512)-center*zoom_value
	scene.limit_pan(); scene.refresh_symbols(); scene.overlay.queue_redraw()
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png")
	print("ATLAS_ACTION_CAPTURE ",name_value)
func army(owner: int,location: int) -> Army:
	var result := Army.new(); result.id = scene.state.armies.size()+900000
	result.owner_nation = owner; result.location_city = location; result.move_from = location
	result.size = 15000; result.max_size = 15000; result.morale = result.max_morale
	scene.state.armies.append(result); return result
func run() -> void:
	root.size = Vector2i(2048,1024)
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.overlay==null: await process_frame
	scene.hud.get_parent().hide(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var sea_seats := 0; var seed_clicks_wrong := 0
	for city in scene.data.cities:
		var point := Vector2(scene.data.mesh.x[city.cell],scene.data.mesh.y[city.cell]); var k := clampi(floori(point.y),0,1023)*2048+posmod(floori(point.x),2048)
		if scene.raster.water[k]!=0: sea_seats += 1
		if scene.province_labels[k]!=city.region: seed_clicks_wrong += 1
	print("ATLAS_VISUAL_SEEDS sea=",sea_seats," wrong_district=",seed_clicks_wrong)
	if not OS.get_cmdline_user_args().has("--atlas-action-focus-only"):
		scene.mode_control.select(2); scene.update_mode(); await capture("seed1-china-hierarchy-final",Vector2(1685,338),4.)
		scene.mode_control.select(0); scene.update_mode(); await capture("seed1-dateline-final",Vector2(0,512),4.)
	# A real protected centre-to-prefecture route in East Asia, with an ordinary
	# public movement command. Test actors are added to the generated scenario.
	var start := -1; var goal := -1
	for city in scene.state.land_cities():
		if city.map_position.x<.75 or city.map_position.x>.92 or city.map_position.y<.23 or city.map_position.y>.42: continue
		for neighbor in scene.state.strategic_neighbors(city.id):
			if scene.state.cities[neighbor].owner_nation==city.owner_nation: start = city.id; goal = neighbor; break
		if start>=0: break
	assert(start>=0)
	var mover := army(scene.state.cities[start].owner_nation,start)
	assert(scene.simulation.order_army_to(mover,goal).ok)
	var edge: Edge = scene.state.edge_of(mover.move_from,mover.move_to)
	mover.move_progress = .2; scene.selected_army = mover.id; scene.overlay.selection = mover.id
	var focus: Vector2 = scene.overlay.army_position(mover)
	await capture("seed1-military-marching",focus)
	assert(scene.road_at(focus)==edge,"road picking uses the army's drawn physical curve")
	# Opposing forces contact on that exact shared physical segment.
	var enemy: int = (mover.owner_nation+1)%scene.state.nations.size()
	scene.simulation._set_coalition_war([mover.owner_nation] as Array[int],[enemy] as Array[int])
	var opponent := army(enemy,mover.move_to); opponent.on_edge = true; opponent.state = Army.State.MOVING
	opponent.move_from = mover.move_to; opponent.move_to = mover.move_from
	mover.move_progress = .51; opponent.move_progress = .51
	edge.passing_count += 1; edge.occupied = true
	scene.simulation._detect_encounters()
	assert(mover.battle_id>=0 and opponent.battle_id==mover.battle_id)
	var contact: Vector2 = scene.overlay.army_position(mover)
	await capture("seed1-military-field-battle",contact)
	# Capture through the same siege transaction used by the runtime. The road
	# and fixed administrative references must survive ownership changes.
	var target := edge.control_city_id
	var before: PackedInt32Array = scene.state.administrative_center_by_city.duplicate()
	var paths: PackedVector2Array = edge.map_path.duplicate()
	var conqueror := army(enemy,target); var battle: Battle = scene.state.new_battle(Battle.Kind.SIEGE)
	battle.city = scene.state.cities[target]; battle.siege_attacker_nation = enemy; battle.siege_claimant_nation = enemy
	scene.simulation._enter_battle(battle,conqueror,1)
	scene.simulation._complete_siege_capture(battle)
	assert(scene.state.cities[target].owner_nation==enemy)
	assert(scene.state.administrative_center_by_city==before and edge.map_path==paths)
	await process_frame
	await capture("seed1-military-local-capture",scene.state.cities[target].map_position*Vector2(2048,1024))
	print("ATLAS_MILITARY_ACTION_DONE pid=",OS.get_process_id()," seed=",scene.state.world_seed," start=",start," goal=",goal," captured=",target," failures=",sea_seats+seed_clicks_wrong)
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if sea_seats+seed_clicks_wrong else 0)
