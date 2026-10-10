extends SceneTree
## GPU-only integration evidence: actual native Earth + real declaration path.
const Front = preload("res://scripts/atlas/war_fronts.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
var scene
var failures := 0
var checks := 0
var directory := "res://docs/atlas/fronts_evidence"

func _initialize() -> void: call_deferred("run")

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("ATLAS_FRONT_VISUAL_FAIL ",message)

func capture(name_value: String,center: Vector2,zoom_value: float) -> void:
	scene.zoom = zoom_value; scene.map_root.scale = Vector2.ONE*zoom_value
	scene.map_root.position = Vector2(root.size)*.5-center*zoom_value
	scene.limit_pan(); scene.refresh_symbols()
	check(await scene.await_render_ready(15000),"capture prepares visible cached detail")
	await process_frame; await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png")
	print("ATLAS_FRONT_CAPTURE ",name_value)

func run() -> void:
	root.size = Vector2i(2048,1024)
	scene = load("res://atlas_military.tscn").instantiate(); root.add_child(scene)
	while not scene.view_ready or scene.front_layer==null: await process_frame
	scene.hud.get_parent().hide(); DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	# Longest shared border near China, taken directly from the actual map.
	var chosen := {}; var longest := 0.; var focus := Vector2.ZERO
	for border in scene.display.lines:
		if border.left<0 or border.right<0: continue
		var path := Geometry.points(border.pts); var center := path[path.size()/2]
		if center.x<1550 or center.x>1850 or center.y<230 or center.y>460: continue
		var length := 0.
		for i in range(1,path.size()): length += path[i].distance_to(path[i-1])
		if length>longest: longest = length; chosen = border; focus = center
	check(not chosen.is_empty(),"native Earth contains an East Asian shared border")
	if chosen.is_empty(): scene.queue_free(); await process_frame; quit(1); return
	var left := int(chosen.left); var right := int(chosen.right)
	var geometry_hash := hash(scene.display.lines); var roads_hash := hash(scene.military_payload.graph)
	var ownership: int = scene.state.ownership_revision
	check(scene.front_layer.fronts.is_empty(),"neutral world starts with ordinary borders")
	await capture("seed1-peace-china-4x",focus,4.)
	# UI declaration enters the same coalition war transaction as normal play.
	scene.player_nation.value = left
	for city in scene.state.land_cities():
		if city.owner_nation==right: scene.selected_region = city.id; break
	scene.declare_selected_war(); await process_frame; await process_frame
	check(scene.state.is_enemy(left,right) and not scene.front_layer.fronts.is_empty(),"declaration automatically refreshes fronts")
	check(scene.state.ownership_revision==ownership and hash(scene.display.lines)==geometry_hash,"diplomacy refresh preserves border geometry and territory")
	for front in scene.front_layer.fronts: check(front.defender==right,"teeth point toward original defender")
	var ordinary_count: int = scene.front_layer.normal_borders.size()
	for copy in scene.copies: check(copy.ink.borders.size()==ordinary_count,"hostile border is replaced in ordinary ink")
	await capture("seed1-war-global-1x",Vector2(1024,512),1.)
	await capture("seed1-war-china-2x",focus,2.)
	await capture("seed1-war-china-4x",focus,4.)
	await capture("seed1-war-china-8x",focus,8.)
	var classified: int = scene.front_layer.classification_count
	await process_frame; check(scene.front_layer.classification_count==classified,"pan and zoom do not reclassify political geometry")
	for mode in [1,2,3]:
		scene.mode_control.select(mode); scene.update_mode()
		check(not scene.front_layer.visible,"fronts hide outside political mode")
	scene.mode_control.select(0); scene.update_mode()
	check(scene.front_layer.visible,"political mode restores fronts")
	scene.history.reset(scene.state)
	scene.state.set_diplomatic_relation(left,right,GameState.DiplomaticRelation.NEUTRAL)
	await process_frame; await process_frame
	check(scene.front_layer.fronts.is_empty() and scene.front_layer.normal_borders.size()==scene.display.lines.size(),"peace automatically restores ordinary borders")
	await capture("seed1-peace-restored-china-4x",focus,4.)
	scene.history_control.value = 0; scene.show_history(); await process_frame
	check(await scene.await_render_ready(15000),"historical display commits its own revision")
	check(not scene.front_layer.fronts.is_empty(),"historical war remains visible after current peace")
	await capture("seed1-history-war-china-4x",focus,4.)
	scene.historical_view = false; scene.overlay.state = scene.state; scene.last_owner_revision = -1
	await process_frame; await process_frame
	check(await scene.await_render_ready(15000),"current display commits after leaving history")
	check(scene.front_layer.fronts.is_empty(),"return to current view uses current diplomacy")
	check(hash(scene.military_payload.graph)==roads_hash,"rendering never mutates traffic graph")
	var result := {"pid":OS.get_process_id(),"seed":scene.state.world_seed,"scene":"res://atlas_military.tscn","source":"atlas_development_cache" if Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--atlas-cache=")) else "atlas_native_zhoufu","godot":Engine.get_version_info().string,"parameters":scene.state.generation_metadata,"left":left,"right":right,"focus":[focus.x,focus.y],"border_length":longest,"checks":checks,"failures":failures}
	var file := FileAccess.open(directory+"/manifest.json",FileAccess.WRITE); file.store_string(JSON.stringify(result,"\t")); file.close()
	print("ATLAS_FRONT_VISUAL ",JSON.stringify(result))
	root.remove_child(scene); scene.queue_free(); await process_frame; quit(1 if failures else 0)
