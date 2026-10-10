extends "res://scripts/atlas/preview.gd"
const MilitaryMap = preload("res://scripts/atlas/military_map.gd")
const Overlay = preload("res://scripts/atlas/military_overlay.gd")
const WarFronts = preload("res://scripts/atlas/war_fronts.gd")
const Information = preload("res://scripts/atlas/information_model.gd")
const Interface = preload("res://scripts/atlas/military_interface.gd")
const StartupCache = preload("res://scripts/atlas/startup_cache.gd")
const Selection = preload("res://scripts/atlas/map_selection.gd")
const Diplomacy = preload("res://scripts/atlas/diplomacy_view.gd")
var startup_cache_writer: Thread
var startup_cache_key := ""
var startup_cache_directory := StartupCache.DIRECTORY

func load_native(seed_value: int) -> void:
	if generating: return
	if startup_cache_writer!=null and startup_cache_writer.is_started(): startup_cache_writer.wait_to_finish()
	generating=true; generation_index+=1; startup_profile={}
	var options := {"terrain_model":"earth","rainfall_model":rainfall_model} if terrain_model=="earth" else {}
	if terrain_model=="earth" and not settlement_model.is_empty(): options.settlement_model=settlement_model
	var use_cache := true
	for argument in OS.get_cmdline_user_args():
		if argument=="--atlas-no-startup-cache": use_cache=false
		if argument.begins_with("--atlas-startup-dir="): startup_cache_directory=argument.trim_prefix("--atlas-startup-dir=")
	var source: String=source_fingerprint()+load("res://scripts/atlas/military_import.gd").source_fingerprint()
	var cache_options := options.duplicate()
	if terrain_model=="earth" and not cache_options.has("settlement_model"):
		cache_options.settlement_model=Generator.World.SettlementClimate.VERSION if rainfall_model=="seasonal_circulation_v5" else "climate_capacity_v4" if rainfall_model in ["seasonal_circulation_v4","seasonal_circulation_v3"] else "climate_capacity_v2" if rainfall_model=="seasonal_circulation_v2" else "atlas_original"
	startup_cache_key=StartupCache.key_for(seed_value,threshold_control.value,cache_options,source) if use_cache else ""
	begin_log("native_earth" if terrain_model=="earth" else "native",seed_value)
	status.text="准备地图"; await get_tree().process_frame
	var threshold: float=threshold_control.value; var key := startup_cache_key; var directory := startup_cache_directory
	var worker := Thread.new(); generation_worker=worker
	var started := Time.get_ticks_msec()
	var error := worker.start(func():
		var cached := StartupCache.read(directory,key) if not key.is_empty() else {}
		if not cached.is_empty(): return cached
		var base := Generator.generate(seed_value,threshold,func(stage): call_deferred("stage_update",stage),options)
		if base.has("error"): return base
		var payload := MilitaryMap.prepare(base); payload.generation_timing=base.timing
		return {"payload":payload,"display":{}})
	if error!=OK: generating=false; status.text="生成线程无法启动"; return
	while worker.is_alive(): await get_tree().process_frame
	var result = worker.wait_to_finish()
	if not result is Dictionary or not result.get("payload") is Dictionary:
		generating=false; status.text="生成失败，保留原世界"; log_event("failed",{"error":str(result)}); return
	startup_profile.generate_or_load_ms=Time.get_ticks_msec()-started
	startup_profile.cache_hit=not result.display.is_empty()
	var payload: Dictionary=result.payload; initial_display_plan=result.display
	timing=payload.get("generation_timing",payload.timing)
	rainfall_model=payload.data.options.get("rainfall_model","atlas_original"); settlement_model=payload.data.options.get("settlement_model","atlas_original")
	started=Time.get_ticks_msec()
	var prepared := GameState.new(); prepared.generate_from_atlas(payload)
	startup_profile.military_import_ms=Time.get_ticks_msec()-started
	started=Time.get_ticks_msec()
	await present_world(prepared,payload,"atlas_startup_cache" if startup_profile.cache_hit else "atlas_native_zhoufu")
	generating=false; open_log(active_model,Time.get_ticks_msec()-started)
	log_event("startup",{"profile":startup_profile,"cache_key":startup_cache_key})
	if use_cache and not startup_profile.cache_hit:
		# Freeze the generated inputs before handing them to the disk writer.
		# Simulation state is deliberately reconstructed fresh on every launch.
		var cached := {"payload":payload.duplicate(true),"display":startup_display_result.duplicate(true)}
		startup_cache_writer=Thread.new()
		startup_cache_writer.start(func(): return StartupCache.write(directory,key,cached))

var interface: Control
var info_panel: PanelContainer
var information_kind := ""
var information_id := -1
var information_road := -1
var information_message := ""
var front_layer: Node2D
var last_front_state_key: Array = []
var state: GameState
var simulation: Simulation
var military_payload: Dictionary = {}
var overlay: Node2D
var run_log := DebugRunLog.new()
var history := PoliticalHistory.new()
var selected_army := -1
var command_target := -1
var diplomatic_observer := -1
var diplomacy_enabled := false
var diplomacy_key: Array=[]
var diplomacy_palette_updates := 0
var player_nation := SpinBox.new()
var military_status := Label.new()
var last_owner_revision := -1
var history_control := SpinBox.new()
var historical_view := false

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--atlas-capture="):
			get_window().content_scale_size = Vector2i(2048,1024)
			get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
			get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	await super._ready()

func load_cached_payload(payload: Dictionary) -> void:
	if payload.get("model")==MilitaryMap.MODEL:
		active_seed = payload.data.seed; timing = payload.timing
		var prepared := GameState.new(); prepared.generate_from_atlas(payload)
		await present_world(prepared,payload,"atlas_development_cache")
	else: await super.load_cached_payload(payload)

func make_ui() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	interface=Interface.new(); add_child(interface); interface.setup(self)
	status.text="滚轮缩放 · 中键平移 · 左键查看辖区 · 右键下令"

func time_controls_available() -> bool:
	return simulation!=null and view_ready and not generating and not historical_view

func set_time_speed(multiplier: float) -> void:
	if time_controls_available(): simulation.set_speed_multiplier(multiplier)

func change_time_speed(factor: float) -> void:
	if time_controls_available(): set_time_speed(simulation.speed_multiplier()*factor)

func toggle_pause() -> void:
	if time_controls_available(): simulation.paused=not simulation.paused

func step_day() -> void:
	if time_controls_available(): await simulation.advance_one_day()

func time_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or not time_controls_available(): return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return false
	if event.keycode==KEY_SPACE and focus!=null: return false
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_EQUAL,KEY_KP_ADD,KEY_BRACKETRIGHT: change_time_speed(2.)
		KEY_MINUS,KEY_KP_SUBTRACT,KEY_BRACKETLEFT: change_time_speed(.5)
		_: return false
	get_viewport().set_input_as_handled(); return true

func information_source() -> GameState:
	return overlay.state if historical_view and is_instance_valid(overlay) else state

func information_document() -> Dictionary:
	var source := information_source()
	if source==null: return {}
	var doc := {}
	match information_kind:
		"city": doc=Information.city(source,information_id)
		"nation": doc=Information.nation(source,information_id)
		"army": doc=Information.army(source,information_id)
		"road": doc=Information.road(source,information_id)
	if doc.is_empty(): return doc
	if information_kind=="city" and information_road>=0 and information_road<source.edges.size():
		doc.sections.append(Information.section("选中道路",[Information.row("查看道路详情","道路 %d"%information_road,"road",information_road)]))
	doc.notice="历史回看 · 政治快照 · 军事操作已禁用" if historical_view else information_message
	for action in doc.actions:
		if action.key in ["order","player","declare","select_army"]:
			action.disabled=action.disabled or historical_view or (simulation!=null and simulation.runtime_day_in_progress())
		if action.key=="declare": action.disabled=action.disabled or action.id==int(player_nation.value) or not source.nations[action.id].alive or source.is_enemy(int(player_nation.value),action.id)
	if historical_view: doc=Information.historical(doc,information_kind)
	return doc

func show_information(kind: String,id: int) -> void:
	information_kind=kind; information_id=id; information_message=""
	var source := information_source()
	if kind=="nation": set_diplomatic_observer(id)
	elif kind=="city" and source!=null and id>=0 and id<source.cities.size(): set_diplomatic_observer(source.cities[id].owner_nation)
	selected_region=id if kind=="city" else -1
	if info_panel!=null: info_panel.show_document(information_document())

func close_information() -> void:
	information_kind=""; information_id=-1; information_road=-1
	selected_region=-1
	command_target=-1
	diplomatic_observer=-1; diplomacy_enabled=false; refresh_diplomacy()

func set_diplomatic_observer(id: int) -> void:
	diplomatic_observer=id if Diplomacy.valid(information_source(),id) else -1
	diplomacy_enabled=diplomatic_observer>=0
	refresh_diplomacy()

func restore_country_colors() -> void:
	diplomacy_enabled=false; refresh_diplomacy()

func political_colors() -> Array:
	var source := information_source()
	if source==null: return super.political_colors()
	var colors: Array=[]
	for nation in source.nations: colors.append(Diplomacy.color(source,diplomatic_observer if diplomacy_enabled else -1,nation.id))
	return colors

func refresh_diplomacy() -> void:
	var source := information_source()
	if source==null: diplomacy_key.clear(); return
	if information_kind=="city" and information_id>=0 and information_id<source.cities.size(): diplomatic_observer=source.cities[information_id].owner_nation
	if not Diplomacy.valid(source,diplomatic_observer): diplomatic_observer=-1; diplomacy_enabled=false
	var key := [source.get_instance_id(),source.diplomacy_revision,source.ownership_revision,hash(source.suzerainty),source.nations.map(func(n): return [n.alive,n.color]),diplomatic_observer,diplomacy_enabled]
	if key==diplomacy_key: return
	diplomacy_key=key
	if mode_cache.has(0):
		var colors := political_colors(); var ids := PackedInt32Array()
		for i in range(colors.size()): ids.append(i)
		mode_cache[0].material.set_shader_parameter("palette",Wash.color_texture(ids,maxi(1,ids.size()),1,colors))
		diplomacy_palette_updates+=1
	if interface!=null: interface.refresh_diplomacy()

func information_notify(message: String) -> void:
	details.text=message; information_message=message; status.text=message
	if info_panel!=null and info_panel.visible: info_panel.show_document(information_document())

func information_action(key: String,id: int) -> void:
	match key:
		"city","nation": show_information(key,id)
		"focus":
			var doc := information_document()
			if not doc.is_empty():
				var visible_center := Vector2((info_panel.size.x+28+size.x)*.5,size.y*.5)
				map_root.position=visible_center-doc.point*zoom; limit_pan(); camera_feedback()
		"copy":
			var doc := information_document(); var lines: Array[String]=[doc.get("title",""),doc.get("subtitle","")]
			for section in doc.get("sections",[]):
				lines.append(section.title)
				for row in section.rows: lines.append("%s：%s"%[row.label,row.value])
			DisplayServer.clipboard_set("\n".join(lines)); information_notify("信息已复制")
		"player":
			if not historical_view: player_nation.value=id; information_notify("当前操控国："+Information.nation_name(state,id))
		"select_army":
			if not historical_view:
				var army := simulation._army_by_id(id)
				if army!=null: selected_army=id; player_nation.value=army.owner_nation; information_notify("已选中军队%d，点击目标辖区后右键下令。"%id)
		"order":
			if not historical_view: command_target=id; order_selected()
		"declare":
			if not historical_view and id>=0 and id<state.nations.size():
				declare_war_on(id)

func export_screenshot() -> void:
	var shown := interface.visible if interface!=null else false
	if interface!=null: interface.hide()
	await super.export_screenshot()
	hud.hide()
	if interface!=null: interface.visible=shown

func sync_rain_control() -> void:
	pass # Climate is frozen in this scenario; the preview's climate selector is absent.

func can_rebuild() -> bool:
	if generating: return false
	if state!=null:
		if simulation.runtime_day_in_progress(): status.text = "当天模拟尚未结束，不能重建。"; return false
		for battle in state.battles:
			if not battle.finished: status.text = "战斗期间不能重建。"; return false
		for army in state.armies:
			if army.on_edge or not army.path.is_empty() or army.battle_id>=0 or army.campaign_front_id>=0: status.text = "存在行军、战斗或战线绑定，不能重建。"; return false
	return true

func build_view() -> void:
	if simulation!=null: simulation.paused = true
	var base := {"data":data,"raster":raster,"display":display}
	var payload := MilitaryMap.prepare(base)
	var prepared := GameState.new(); prepared.generate_from_atlas(payload)
	await present_world(prepared,payload)

func present_world(prepared: GameState,payload: Dictionary,source: String = "atlas_native_zhoufu") -> void:
	# Swap only after generation succeeds; the old scenario remains intact on failure.
	state = prepared; military_payload = payload; historical_view = false; selected_army = -1; selected_region = -1; command_target=-1
	close_information(); information_message=""
	if info_panel!=null: info_panel.hide()
	if simulation!=null: simulation.queue_free()
	simulation = Simulation.new(); simulation.setup(state); simulation.paused = true; add_child(simulation)
	history.reset(state)
	if run_log.path.is_empty(): run_log.begin("res://atlas_military.tscn")
	var settings := state.generation_metadata.duplicate(true)
	settings["options"] = payload.data.options.duplicate(true)
	settings["params"] = payload.data.params.duplicate(true)
	run_log.world_started(state,settings,source)
	raster = payload.raster; data = visual_data(); provinces = military_payload.district_pixels.duplicate(); display = payload.display.duplicate(true); display.nations = data.nations
	default_owners = data.ownership.duplicate(); last_owner_revision = state.ownership_revision
	await super.build_view()
	text_layer.z_index = 7
	if overlay!=null: overlay.queue_free()
	overlay = Overlay.new(); overlay.scheduler = render_scheduler; overlay.high_performance = high_performance_renderer; overlay.state = state; overlay.selection = selected_army; overlay.z_index = 6; map_root.add_child(overlay)
	front_layer = WarFronts.new(); front_layer.scheduler = render_scheduler; front_layer.high_performance = high_performance_renderer; front_layer.z_index = 8; map_root.add_child(front_layer)
	refresh_fronts(state)
	if startup_display_result.has("geometry") and startup_display_result.geometry.has("state_lines"):
		overlay.state_lines=startup_display_result.geometry.state_lines
	else:
		var parent: Dictionary = military_payload.data.regions
		var parent_owners := PackedInt32Array()
		for id in range(parent.count): parent_owners.append(id)
		var parent_chains := Borders.trace(data.mesh,parent.of)
		for line in Borders.build(parent_chains,parent_owners,data.mesh,raster,parent.of): overlay.state_lines.append(Geometry.points(line.pts))
	for line in province_lines: overlay.district_lines.append(Geometry.points(line.pts))
	status.text = "%d 州 · %d 府 · %d 交通点 · %d 条共享道路段"%[state.administrative_region_count,state.land_cities().size()-state.administrative_region_count,state.cities.size()-state.land_cities().size(),state.edges.size()]

func visual_data() -> Dictionary:
	var result: Dictionary = military_payload.data.duplicate()
	result.parent_regions=military_payload.data.regions
	var h: Dictionary = military_payload.hierarchy
	var seats := PackedInt32Array(); var areas := PackedFloat32Array(); var capacities := PackedFloat32Array(); var names: Array = []
	var cities: Array = h.cities.duplicate(true); var owners := PackedInt32Array()
	for c in range(cities.size()):
		cities[c].region = c; cities[c].name = state.cities[c].name; seats.append(cities[c].cell); areas.append(0.); capacities.append(0.); owners.append(state.cities[c].owner_nation); names.append(state.cities[c].name)
	for cell in range(result.mesh.n):
		var district: int = h.district_of_cell[cell]
		if district>=0: areas[district] += result.mesh.areas[cell]; capacities[district] += result.mesh.areas[cell]*result.environment.suitability[cell]
	result.regions = {"count":cities.size(),"of":h.district_of_cell,"seat":seats,"area":areas,"capacity":capacities,"names":names}
	result.cities = cities; result.ownership = owners; result.nations = []
	for nation in state.nations:
		result.nations.append({"name":nation.name,"seat":nation.capital_city_id,"color":[roundi(nation.color.r*255),roundi(nation.color.g*255),roundi(nation.color.b*255)]})
	result.roads = military_payload.network.routes; result.traffic_graph = military_payload.graph
	return result

func _process(_delta: float) -> void:
	if state==null or not view_ready or not is_instance_valid(overlay): return
	if not navigation_in_progress: overlay.set_view(zoom,Rect2(-map_root.position/zoom,size/zoom))
	overlay.selection = selected_army
	military_status.text = "历史：第%d天 · 只读政治快照"%overlay.state.day if historical_view else "第%d天 · 军队%d · 战斗%d · %s"%[state.day,state.armies.size(),state.battles.size(),"暂停" if simulation.paused else "运行军事AI"]
	history_control.max_value = maxi(0,history.snapshot_count()-1)
	if not historical_view and last_owner_revision!=state.ownership_revision:
		for c in range(data.cities.size()): data.ownership[c] = state.cities[c].owner_nation
		sync_nations(state)
		last_owner_revision = state.ownership_revision; refresh_ownership()
	if not political_pending and not historical_view and WarFronts.state_key(state)!=last_front_state_key:
		refresh_fronts(state)
	if is_instance_valid(front_layer): front_layer.set_view_zoom(zoom)
	refresh_diplomacy()
	history.maybe_capture(state); run_log.checkpoint(state)

func refresh_fronts(source: GameState) -> void:
	if political_pending: return
	if not is_instance_valid(front_layer) or front_layer.is_queued_for_deletion(): return
	front_layer.configure(display.lines,source)
	front_layer.set_view_zoom(zoom)
	front_layer.visible = mode_control.selected==0 and show_border_layer
	last_front_state_key = WarFronts.state_key(source)
	if mode_control.selected==0:
		for copy in copies:
			copy.ink.borders = front_layer.normal_borders; copy.ink.queue_redraw()

func political_display_ready() -> void:
	if overlay!=null: refresh_fronts(overlay.state if historical_view else state)

func current_political_borders() -> Array:
	return front_layer.normal_borders if is_instance_valid(front_layer) and not front_layer.is_queued_for_deletion() else display.lines

func political_front_snapshot() -> Dictionary:
	var source: GameState = overlay.state if historical_view and overlay!=null else state
	var roles := {}
	if source==null: return {"roles":roles,"signature":0}
	for left in range(source.nations.size()):
		for right in range(left+1,source.nations.size()):
			if source.nations[left].alive and source.nations[right].alive and source.is_enemy(left,right): roles["%d:%d"%[left,right]] = WarFronts.defender_of(source,left,right)
	return {"roles":roles,"signature":hash([source.get_instance_id(),roles])}

func select_player_army() -> void:
	if state==null: return
	for army in state.armies:
		if army.owner_nation==int(player_nation.value) and army.size>0:
			selected_army = army.id; show_information("army",army.id)
			information_notify("选中军队%d，%d人。选择辖区后下令。"%[army.id,army.size]); return

func declare_selected_war() -> void:
	if information_kind=="nation": declare_war_on(information_id)
	elif information_kind=="city" and state!=null and information_id>=0 and information_id<state.cities.size(): declare_war_on(state.cities[information_id].owner_nation)

func declare_war_on(target: int) -> void:
	if historical_view: information_notify("历史视图不可宣战。"); return
	if state==null or simulation==null or generating or target<0 or target>=state.nations.size() or not state.nations[target].alive: return
	if simulation.runtime_day_in_progress(): information_notify("等待当天模拟结束后再宣战。"); return
	var source := int(player_nation.value)
	if target==source or source<0 or source>=state.nations.size() or not state.nations[source].alive or state.is_enemy(source,target): return
	simulation._set_coalition_war(state.alliance_bloc(source),state.alliance_bloc(target)); information_notify("%s向%s宣战。"%[state.nations[source].name,state.nations[target].name])

func order_selected() -> void:
	if historical_view: information_notify("历史视图不可下令。"); return
	if state==null or command_target<0 or command_target>=state.cities.size(): return
	if simulation.runtime_day_in_progress(): information_notify("等待当天模拟结束后再下令。"); return
	var army: Army = simulation._army_by_id(selected_army)
	if army==null: select_player_army(); army = simulation._army_by_id(selected_army)
	if army==null: return
	if army.owner_nation!=int(player_nation.value): information_notify("请先选择本国军队。"); return
	var result := simulation.order_army_to(army,command_target)
	information_notify(str(result.get("error","行军命令已下达。")))

func order_to_inspected() -> void:
	command_target=selected_region; order_selected()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and time_key(event): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		if historical_view or generating or not view_ready or political_pending: return
		var target := pick_map(map_root.to_local(event.position),false)
		command_target=target.district_id; order_selected(); return
	super._unhandled_input(event)

func load_military_template() -> void:
	if not can_rebuild(): return
	var loaded := MapDefinition.load_file("atlas-military.json")
	if not loaded.ok: status.text = loaded.error; return
	if loaded.data.get("map_kind")!="atlas_military": status.text = "此入口只读取 Atlas 军事模板。"; return
	var prepared := GameState.new(); prepared.generate_from_map_definition(loaded.data)
	await present_world(prepared,prepared.atlas_layout,"atlas_template:"+str(loaded.path))

func show_history() -> void:
	if state==null or simulation.runtime_day_in_progress(): return
	simulation.paused = true
	var view := history.build_view_state(state,int(history_control.value))
	if view==null: return
	historical_view = true; overlay.state = view
	for c in range(data.cities.size()): data.ownership[c] = view.cities[c].owner_nation
	sync_nations(view)
	refresh_ownership(); refresh_diplomacy(); details.text = "历史：第%d天"%view.day
	if info_panel!=null and info_panel.visible: info_panel.show_document(information_document())

func return_to_current() -> void:
	if state==null or simulation.runtime_day_in_progress(): return
	historical_view=false; simulation.paused=true
	if overlay!=null: overlay.state=state
	last_owner_revision=-1; refresh_diplomacy()
	if info_panel!=null and info_panel.visible: info_panel.show_document(information_document())

func sync_nations(source: GameState) -> void:
	data.nations = []
	for nation in source.nations: data.nations.append({"name":nation.name,"seat":nation.capital_city_id,"color":[roundi(nation.color.r*255),roundi(nation.color.g*255),roundi(nation.color.b*255)]})
	display.nations = data.nations
	if not historical_view: player_nation.max_value = maxi(0,source.nations.size()-1)

func select_at(position_value: Vector2) -> void:
	if state==null or generating or not view_ready or political_pending: return
	var picked := pick_map(position_value)
	if picked.kind.is_empty():
		close_information()
		if info_panel!=null: info_panel.hide()
		return
	if picked.kind=="army": selected_army=picked.id
	information_road=-1
	if picked.kind=="city":
		var road := road_at(position_value)
		information_road=information_source().edges.find(road) if road!=null else -1
	show_information(picked.kind,picked.id)
	selected_region=picked.district_id

func pick_map(point: Vector2,objects: bool = true) -> Dictionary:
	var result := Selection.territory(self,point)
	if not objects or point.y<0 or point.y>=1024: return result
	var source := information_source()
	if source==null: return result
	if not historical_view and is_instance_valid(overlay):
		var best := pow(10./maxf(.1,zoom),2); var selected := -1
		for army in source.armies:
			if army.size<=0 or (not army.on_edge and (army.location_city<0 or not source.cities[army.location_city].is_traffic)): continue
			var p: Vector2=overlay.army_position(army); p.x+=roundf((point.x-p.x)/2048.)*2048.
			var d := point.distance_squared_to(p)
			if d<best: best=d; selected=army.id
		if selected>=0: result.kind="army"; result.id=selected; return result
	if is_instance_valid(text_layer):
		var city: int=text_layer.hit_city(point)
		if city>=0 and city<source.cities.size() and source.cities[city].is_settlement():
			result={"kind":"city","id":city,"district_id":city,"owner_id":source.cities[city].owner_nation}
	return result

func road_at(position_value: Vector2) -> Edge:
	if overlay==null: return null
	var closest := pow(5./maxf(zoom,.1),2); var found: Edge
	for edge in overlay.state.edges:
		for i in range(1,edge.map_path.size()):
			var a: Vector2 = edge.map_path[i-1]*Vector2(2048,1024); var b: Vector2 = edge.map_path[i]*Vector2(2048,1024)
			var shift := roundf((position_value.x-a.x)/2048.)*2048.; a.x += shift; b.x += shift
			var distance := position_value.distance_squared_to(Geometry2D.get_closest_point_to_segment(position_value,a,b))
			if distance<closest: closest = distance; found = edge
	return found

func update_mode() -> void:
	super.update_mode()
	refresh_diplomacy()
	if interface!=null: interface.refresh_diplomacy()
	if overlay!=null: refresh_fronts(overlay.state if historical_view else state)
	# Child districts use the fine overlay lines; the bold dashed pen is reserved
	# for political borders. Their colour boundary is still the shared band map.
	if mode_control.selected==2:
		for copy in copies: copy.ink.show_borders = false; copy.ink.queue_redraw()

func _exit_tree() -> void:
	if startup_cache_writer!=null and startup_cache_writer.is_started(): startup_cache_writer.wait_to_finish()
	run_log.close(state)
	super._exit_tree()
