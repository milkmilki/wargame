extends SceneTree
## GPU rendering with a controlled blockade in the real masked Earth layout.
var scene
var failures:=0
const Rules=preload("res://scripts/simulation/rules/simple_campaign.gd")
const DIRECTORY="res://docs/atlas/evidence/simple_campaign/gpu"
func _initialize():call_deferred("run")
func capture(name_value: String):
	if not await scene.await_render_ready(30000):failures+=1;printerr("CAMPAIGN_GPU_TIMEOUT")
	await process_frame;await process_frame
	scene.info_panel.scroll.scroll_vertical=10000
	await process_frame
	for control in scene.info_panel.find_children("*","Label",true,false):
		if control.text=="州战役":
			scene.info_panel.scroll.scroll_vertical=int(scene.info_panel.scroll.scroll_vertical+control.global_position.y-scene.info_panel.scroll.global_position.y-8)
			break
	await process_frame;await process_frame;RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png(DIRECTORY+"/"+name_value+".png")
func run():
	root.size=Vector2i(1280,720);DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	scene=load("res://atlas_military.tscn").instantiate();root.add_child(scene)
	while not scene.view_ready or scene.overlay==null:await process_frame
	scene.simulation.paused=true
	var state:GameState=scene.state
	var center:=-1;var distance:=INF
	for id in state.administrative_center_city_ids:
		if state.administrative_members(id).size()<3:continue
		var current:=state.cities[id].map_position.distance_squared_to(Vector2((105.+180.)/360.,(90.-30.)/180.))
		if current<distance:distance=current;center=id
	var defender:=state.cities[center].owner_nation;var attacker:=(defender+1)%state.nations.size()
	state.set_diplomatic_relation(attacker,defender,GameState.DiplomaticRelation.WAR)
	var war:=state.set_war_objective(attacker,defender,center,"GPU campaign fixture")
	var front:=state.create_campaign_front(war,[attacker] as Array[int],attacker,CoalitionCampaignFront.Mode.OFFENSE,center)
	var battle:=state.new_battle(Battle.Kind.SIEGE);battle.city=state.cities[center];battle.siege_attacker_nation=attacker
	state.cities[center].garrison_manpower=60000
	for index in range(3):
		var army:=Army.new();army.id=1000000+index;army.owner_nation=attacker;army.location_city=center;army.move_from=center;army.size=10000+index*1000;army.max_size=15000
		army.state=Army.State.FIGHTING;army.battle_id=battle.id;army.campaign_front_id=front.front_id;army.campaign_war_id=war
		front.army_assignments[army.id]=center;state.armies.append(army);battle.side_a.append(army)
	Rules.poll(scene.simulation)
	scene.zoom=4.;scene.map_root.scale=Vector2.ONE*4.;scene.map_root.position=Vector2(785,360)-state.cities[center].map_position*Vector2(2048,1024)*4.
	scene.limit_pan();scene.refresh_symbols();scene.overlay.queue_redraw()
	scene.show_information("nation",attacker);scene.info_panel.scroll.scroll_vertical=10000
	await capture("blockade-raids")
	if front.detachments.is_empty():failures+=1;printerr("CAMPAIGN_GPU_NO_DETACHMENT")
	else:
		var id:=int(front.detachments.keys()[0]);var task:Dictionary=front.detachments[id]
		var unit:Army=scene.simulation._army_by_id(id)
		scene.simulation._release_edge(unit);unit.state=Army.State.IDLE;unit.location_city=int(task.target);unit.move_from=unit.location_city;unit.move_to=-1;unit.path.clear()
		scene.simulation._capture_city(unit,state.cities[unit.location_city])
		Rules.poll(scene.simulation)
		if int(task.status)!=CoalitionCampaignFront.DetachmentStatus.RETURNING or unit.ai_target_city!=center:failures+=1;printerr("CAMPAIGN_GPU_NO_RETURN")
		scene.show_information("nation",attacker);scene.overlay.queue_redraw()
		await capture("fu-return")
	var defense:=state.create_campaign_front(war,[defender] as Array[int],defender,CoalitionCampaignFront.Mode.DEFENSE,center)
	Rules.ensure_rally(scene.simulation,defense);defense.phase=CoalitionCampaignFront.Phase.DEFENSE_REGROUP
	scene.show_information("nation",defender);scene.info_panel.scroll.scroll_vertical=10000
	await capture("rear-regroup")
	if defense.camp_city_id<0:failures+=1;printerr("CAMPAIGN_GPU_NO_REAR")
	else:
		for index in range(3):
			var army:=Army.new();army.id=1000010+index;army.owner_nation=defender;army.size=15000;army.max_size=15000;army.location_city=defense.camp_city_id;army.move_from=army.location_city;army.campaign_front_id=defense.front_id;army.campaign_war_id=war
			defense.army_assignments[army.id]=defense.camp_city_id;state.armies.append(army)
		Rules.defense(scene.simulation,defense)
		if defense.phase!=CoalitionCampaignFront.Phase.RELIEVE_CENTER:failures+=1;printerr("CAMPAIGN_GPU_NO_RELIEF")
		scene.show_information("nation",defender);scene.overlay.queue_redraw()
		await capture("concentrated-relief")
	var source_hashes:={}
	for path in ["scripts/core/combat.gd","scripts/core/pathfinding.gd","scripts/simulation/simulation.gd","scripts/simulation/rules/simple_campaign.gd","scripts/atlas/information_model.gd","tests/campaign_simple_visual.gd"]:source_hashes[path]=FileAccess.get_sha256("res://"+path)
	FileAccess.open(DIRECTORY+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify({"pid":OS.get_process_id(),"seed":state.world_seed,"center":center,"attacker":attacker,"defender":defender,"front":front.front_id,"tasks":front.detachments,"renderer":RenderingServer.get_video_adapter_name(),"mask":state.atlas_layout.data.options.settlement_mask,"fixture":"controlled blockade, territory capture/return and relief on real Earth; manually positioned troops","source_hashes":source_hashes},"  "))
	print("CAMPAIGN_GPU_DONE failures=",failures," center=",center," phases=",[front.phase,defense.phase]," renderer=",RenderingServer.get_video_adapter_name())
	scene.queue_free();await process_frame;quit(1 if failures else 0)
