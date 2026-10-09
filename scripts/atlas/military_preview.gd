extends "res://scripts/atlas/preview.gd"
const MilitaryMap = preload("res://scripts/atlas/military_map.gd")
const Overlay = preload("res://scripts/atlas/military_overlay.gd")
var state: GameState
var simulation: Simulation
var military_payload: Dictionary = {}
var overlay: Node2D
var run_log := DebugRunLog.new()
var history := PoliticalHistory.new()
var selected_army := -1
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
	var panel := PanelContainer.new(); panel.position = Vector2(12,12); panel.add_child(hud); add_child(panel)
	var title := Label.new(); title.text = "Atlas 州府军事 · 2D 全球地图"; hud.add_child(title)
	var row := HBoxContainer.new(); hud.add_child(row); row.add_child(seed_control)
	button(row,"随机星球",func(): if can_rebuild(): await load_preset("planet"))
	button(row,"真实地球",func(): if can_rebuild(): await load_preset("earth"))
	button(row,"全图",fit_map)
	for name_value in ["政治","地形","府辖区","宜居度"]: mode_control.add_item(name_value)
	row.add_child(mode_control); mode_control.item_selected.connect(func(_i): update_mode())
	var controls := HBoxContainer.new(); hud.add_child(controls)
	button(controls,"暂停/继续",func(): if simulation!=null: simulation.paused = not simulation.paused)
	button(controls,"推进一天",func(): if simulation!=null and not simulation.runtime_day_in_progress(): simulation._advance_day())
	player_nation.min_value = 0; player_nation.max_value = 39; controls.add_child(player_nation)
	button(controls,"选本国军队",select_player_army)
	button(controls,"对选区所属国宣战",declare_selected_war)
	button(controls,"命令前往选区",order_selected)
	var debug_row := HBoxContainer.new(); hud.add_child(debug_row)
	var junctions := CheckButton.new(); junctions.text = "交通节点"; debug_row.add_child(junctions)
	junctions.toggled.connect(func(value): if overlay!=null: overlay.show_traffic = value; overlay.queue_redraw())
	button(debug_row,"截图",func(): await export_screenshot())
	button(debug_row,"保存地图模板",func(): if state!=null: status.text = str(MapDefinition.save_state(state,"atlas-military.json")))
	button(debug_row,"加载地图模板",load_military_template)
	var historical := HBoxContainer.new(); hud.add_child(historical)
	var history_label := Label.new(); history_label.text = "历史快照编号"; historical.add_child(history_label)
	history_control.min_value = 0; history_control.max_value = 0; historical.add_child(history_control)
	button(historical,"查看历史",show_history)
	button(historical,"返回当前",func(): historical_view = false; overlay.state = state; last_owner_revision = -1)
	hud.add_child(status); hud.add_child(military_status); hud.add_child(details)
	details.text = "滚轮缩放 · 中键平移 · 左键选辖区 · 右键下令"
	var font = load("res://assets/atlas/lxgw-wenkai-gb-500.ttf")
	if font: hud.add_theme_font_override("font",font)

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
	state = prepared; military_payload = payload; historical_view = false; selected_army = -1; selected_region = -1
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
	overlay = Overlay.new(); overlay.state = state; overlay.selection = selected_army; overlay.z_index = 6; map_root.add_child(overlay)
	var parent: Dictionary = military_payload.data.regions
	var parent_owners := PackedInt32Array()
	for id in range(parent.count): parent_owners.append(id)
	var parent_chains := Borders.trace(data.mesh,parent.of)
	for line in Borders.build(parent_chains,parent_owners,data.mesh,raster,parent.of): overlay.state_lines.append(Geometry.points(line.pts))
	for line in province_lines: overlay.district_lines.append(Geometry.points(line.pts))
	status.text = "%d 州 · %d 府 · %d 交通点 · %d 条共享道路段"%[state.administrative_region_count,state.land_cities().size()-state.administrative_region_count,state.cities.size()-state.land_cities().size(),state.edges.size()]

func visual_data() -> Dictionary:
	var result: Dictionary = military_payload.data.duplicate()
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
	if state==null or overlay==null: return
	overlay.queue_redraw(); overlay.selection = selected_army
	military_status.text = "第%d天 · 军队%d · 战斗%d · %s"%[state.day,state.armies.size(),state.battles.size(),"暂停" if simulation.paused else "运行军事AI"]
	history_control.max_value = maxi(0,history.snapshot_count()-1)
	if not historical_view and last_owner_revision!=state.ownership_revision:
		for c in range(data.cities.size()): data.ownership[c] = state.cities[c].owner_nation
		sync_nations(state)
		last_owner_revision = state.ownership_revision; refresh_ownership()
	history.maybe_capture(state); run_log.checkpoint(state)

func select_player_army() -> void:
	if state==null: return
	for army in state.armies:
		if army.owner_nation==int(player_nation.value) and army.size>0: selected_army = army.id; details.text = "选中军队%d，%d人。选择辖区后下令。"%[army.id,army.size]; return

func declare_selected_war() -> void:
	if historical_view: details.text = "历史视图不可宣战。"; return
	if state==null or selected_region<0: return
	if simulation.runtime_day_in_progress(): details.text = "等待当天模拟结束后再宣战。"; return
	var target := state.cities[selected_region].owner_nation; var source := int(player_nation.value)
	if target==source or target<0: return
	simulation._set_coalition_war(state.alliance_bloc(source),state.alliance_bloc(target)); details.text = "国家%d向国家%d宣战。"%[source,target]

func order_selected() -> void:
	if historical_view: details.text = "历史视图不可下令。"; return
	if state==null or selected_region<0: return
	if simulation.runtime_day_in_progress(): details.text = "等待当天模拟结束后再下令。"; return
	var army: Army = simulation._army_by_id(selected_army)
	if army==null: select_player_army(); army = simulation._army_by_id(selected_army)
	if army==null: return
	var result := simulation.order_army_to(army,selected_region)
	details.text = str(result.get("error","行军命令已下达。"))

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and overlay!=null and not historical_view:
		var nearest := 10.*10.
		for army in state.armies:
			if army.size<=0: continue
			var p: Vector2 = overlay.army_position(army)
			for shift in [-2048.,0.,2048.]:
				var distance: float = event.position.distance_squared_to(map_root.to_global(p+Vector2(shift,0.)))
				if distance<nearest: nearest = distance; selected_army = army.id; player_nation.value = army.owner_nation
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		select_at(map_root.to_local(event.position)); order_selected()

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
	refresh_ownership(); details.text = "历史：第%d天"%view.day

func sync_nations(source: GameState) -> void:
	data.nations = []
	for nation in source.nations: data.nations.append({"name":nation.name,"seat":nation.capital_city_id,"color":[roundi(nation.color.r*255),roundi(nation.color.g*255),roundi(nation.color.b*255)]})
	display.nations = data.nations; player_nation.max_value = maxi(0,source.nations.size()-1)

func select_at(position_value: Vector2) -> void:
	super.select_at(position_value)
	if state==null or selected_region<0 or selected_region>=state.cities.size(): return
	var source: GameState = overlay.state if historical_view else state
	var city := source.cities[selected_region]
	var center := source.administrative_center_of(city.id)
	details.text += "\n%s · 隶属%s · 月人口%d／金钱%d · 半年粮食%d"%["州治" if center==city.id else "府",source.cities[center].name,city.manpower_per_month,city.gold_per_month,city.food_per_half_year]
	var road := road_at(position_value)
	if road!=null:
		details.text += "\n道路%d—%d · %.1f公里 · 控制辖区：%s"%[road.city_a,road.city_b,road.distance_units()*250.,source.cities[road.control_city_id].name]

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
	# Child districts use the fine overlay lines; the bold dashed pen is reserved
	# for political borders. Their colour boundary is still the shared band map.
	if mode_control.selected==2:
		for copy in copies: copy.ink.show_borders = false; copy.ink.queue_redraw()

func _exit_tree() -> void:
	run_log.close(state)
	super._exit_tree()
