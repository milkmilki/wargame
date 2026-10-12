extends SceneTree
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
var scene
var failures := 0
var checks := 0
var directory := "res://docs/atlas/evidence/vassal_borders"
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func capture(name_value: String,focus: Vector2,value: float) -> void:
	scene.zoom=value;scene.map_root.scale=Vector2.ONE*value
	scene.map_root.position=Vector2(root.size)*.5-focus*value
	scene.limit_pan();scene.refresh_symbols()
	check(await scene.await_render_ready(20000),"visible resources ready for "+name_value)
	await process_frame;await process_frame;RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(directory+"/"+name_value+".png")
func run() -> void:
	root.size=Vector2i(1280,720)
	scene=load("res://atlas_military.tscn").instantiate();root.add_child(scene)
	while not scene.view_ready or scene.front_layer==null:await process_frame
	scene.simulation.paused=true
	scene.hud.get_parent().hide()
	var original_graph:=hash(scene.military_payload.graph)
	var state: GameState=scene.state
	var owner:=-1;var region:Array[int]=[]
	for nation in state.nations:
		if PrincePolitics.enfeoff_candidate(state,nation.id,false)<0:continue
		for center in state.administrative_center_city_ids:
			var candidate:=state.normalize_enfeoff_region(nation.id,[center] as Array[int])
			if not candidate.is_empty() and state._can_enfeoff(nation.id,candidate):owner=nation.id;region=candidate;break
		if owner>=0:break
	check(owner>=0,"actual native world has a legal grant")
	if owner<0:quit(1);return
	var action:={"kind":DiplomacyAI.Action.ENFEOFF,"a":owner,"b":owner,"region_cities":region,"reason":"GPU vassal border test"}
	check(scene.simulation._execute_diplomatic_action(action),"real enfeoffment in running scene")
	var subject:int=action.get("subject_nation",-1)
	await process_frame;await process_frame
	check(await scene.await_render_ready(20000),"ownership display commits")
	scene.refresh_fronts(state)
	check(not scene.front_layer.vassal_borders.is_empty(),"short borders appear after real grant")
	var focus:=Vector2.ZERO;var longest:=0.
	for border in scene.front_layer.vassal_borders:
		var path:=Geometry.points(border.pts);var length:=0.
		for i in range(1,path.size()):length+=path[i].distance_to(path[i-1])
		if length>longest:longest=length;focus=path[path.size()/2]
	await capture("vassal-global-1x",Vector2(1024,512),1.)
	await capture("vassal-local-4x",focus,4.)
	await capture("vassal-local-8x",focus,8.)
	var classified:int=scene.front_layer.classification_count
	await capture("vassal-local-2x",focus,2.)
	check(scene.front_layer.classification_count==classified,"zoom does not reclassify boundaries")
	var geometry_hash:=hash(scene.display.lines)
	var bond:Dictionary=state.suzerainty[subject].duplicate(true)
	state.suzerainty.erase(subject);scene.refresh_fronts(state)
	await capture("ordinary-comparison-4x",focus,4.)
	check(hash(scene.display.lines)==geometry_hash,"relation-only styling keeps geometry")
	state.suzerainty[subject]=bond;scene.refresh_fronts(state)
	scene.history.reset(state)
	# Render fixture only: a geographically isolated subject can legitimately
	# choose peaceful independence in start_civil_war(), which is outside this test.
	state.set_diplomatic_relation(owner,subject,GameState.DiplomaticRelation.WAR)
	check(state.is_enemy(owner,subject),"hostile bond fixture sets real relationship field")
	await process_frame;await process_frame;scene.refresh_fronts(state)
	await capture("hostile-bond-local-4x",focus,4.)
	check(not scene.front_layer.fronts.is_empty(),"civil war replaces internal dashes with front")
	scene.history_control.value=0;scene.show_history();await process_frame
	check(await scene.await_render_ready(20000),"history commits frozen ownership/diplomacy")
	scene.refresh_fronts(scene.overlay.state)
	check(not scene.front_layer.vassal_borders.is_empty() and scene.front_layer.fronts.is_empty(),"historical peaceful bond uses short dashes")
	await capture("history-peaceful-4x",focus,4.)
	check(hash(scene.military_payload.graph)==original_graph,"all styling leaves traffic graph unchanged")
	var result:={"pid":OS.get_process_id(),"godot":Engine.get_version_info().string,"seed":state.world_seed,"parameters":state.generation_metadata,"renderer":RenderingServer.get_video_adapter_name(),"owner":owner,"subject":subject,"hostile_relation_fixture":true,"focus":[focus.x,focus.y],"checks":checks,"failures":failures}
	FileAccess.open(directory+"/gpu-manifest.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("VASSAL_BORDER_GPU ",JSON.stringify(result))
	root.remove_child(scene);scene.queue_free();await process_frame;quit(0 if failures==0 else 1)
