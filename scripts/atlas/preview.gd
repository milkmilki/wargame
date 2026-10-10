extends Control
## Isolated native 2D atlas, with an optional developer reference-input mode.
## Never creates a GameState or simulation debug run. AGPL-3.0-only port modules.
const Fields = preload("res://scripts/atlas/paint_fields.gd")
const Wash = preload("res://scripts/atlas/wash.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Symbols = preload("res://scripts/atlas/symbols.gd")
const Ink = preload("res://scripts/atlas/preview_ink.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
const Borders = preload("res://scripts/atlas/borders.gd")
const Generator = preload("res://scripts/atlas/generator.gd")
const Names = preload("res://scripts/atlas/names.gd")
const Places = preload("res://scripts/atlas/places.gd")
const LabelPlan = preload("res://scripts/atlas/polity_labels.gd")
const MapText = preload("res://scripts/atlas/map_text.gd")
const CoastInk = preload("res://scripts/atlas/coast_ink.gd")
const IceGeometry = preload("res://scripts/atlas/ice_geometry.gd")
const ZoomGeometry = preload("res://scripts/atlas/zoom_geometry.gd")
const SettlementMask = preload("res://scripts/atlas/settlement_mask.gd")
const MaskControls = preload("res://scripts/atlas/settlement_mask_controls.gd")
const Snapshot = preload("res://scripts/atlas/snapshot.gd")
const RenderScheduler = preload("res://scripts/atlas/render_scheduler.gd")
const SymbolTiles = preload("res://scripts/atlas/symbol_tiles.gd")
const PoliticalDisplay = preload("res://scripts/atlas/political_display.gd")
const StartupDisplay = preload("res://scripts/atlas/startup_display.gd")
var initial_display_plan := {}
var startup_display_result := {}
var startup_profile := {}
@export var high_performance_renderer := true
var render_scheduler := RenderScheduler.new()
var symbol_tiles: Node
var raster_layers: Node
var mode_cache := {}
var prepared_political_texture: ImageTexture
var political_id_texture: ImageTexture
var political_pending := false
var political_revision := 0
var weak_mask := PackedByteArray()
const REFERENCE := "res://.dbg/atlas-native-reference/"
const SYMBOL_PAD := 192
@export_enum("planet","earth") var terrain_model: String = "planet"
@export_enum("seasonal_circulation_v5","seasonal_circulation_v4","seasonal_circulation_v3","seasonal_circulation_v2","legacy_monsoon_global_v1","atlas_original") var rainfall_model: String = "seasonal_circulation_v5"
@export var settlement_mask: Dictionary = {} # Missing policy keeps legacy global generation.
var mask_controls: Control
var settlement_model: String = "" # Empty selects the rainfall model's default.
const RAIN_MODELS := ["seasonal_circulation_v5","seasonal_circulation_v4","seasonal_circulation_v3","seasonal_circulation_v2","legacy_monsoon_global_v1","atlas_original"]
var data: Dictionary = {}
var display: Dictionary = {}
var raster: Dictionary = {}
var labels := PackedInt32Array()
var provinces := PackedInt32Array()
var map_root := Node2D.new()
var copies: Array = []
var symbol_view := SubViewport.new()
var forest_view := SubViewport.new()
var status := Label.new()
var details := Label.new()
var seed_control := SpinBox.new()
var threshold_control := SpinBox.new()
var mode_control := OptionButton.new()
var hud := VBoxContainer.new()
var zoom := 1.0
var dragging := false
var capture_path := ""
var selected_region := -1
var province_labels := PackedInt32Array()
var chains: Dictionary = {}
var province_lines: Array = []
var default_owners := PackedInt32Array()
var owner_control := SpinBox.new()
var log_file: FileAccess
var generating := false
var generation_index := 0
var timing: Dictionary = {}
var symbol_screen := Sprite2D.new()
var symbol_layers: Array = []
var forest_material: ShaderMaterial
var crown_material: ShaderMaterial
var symbol_pending := false
var text_layer := MapText.new()
var coast_ink: Node2D
var capture_labels := false
var capture_zoom := 1.0
var capture_center := Vector2(1024,512)
var political_index: Dictionary = {}
var province_index: Dictionary = {}
var political_segments: Dictionary = {}
var province_segments: Dictionary = {}
var field_textures: Dictionary = {}
var paper_material: ShaderMaterial
var active_seed := 1
var active_model := "native"
var generation_started := 0
var view_ready := false
var snapshot_path := "user://atlas_preview.snapshot"
var habitat_texture: ImageTexture
var political_labels := PackedInt32Array()
var political_edge: ImageTexture
var province_edge: ImageTexture
var show_border_layer := true
var generation_worker: Thread
var rain_control := OptionButton.new()
var symbol_cache_zoom := -1.
var symbol_cache_position := Vector2.ZERO
var symbol_cache_size := Vector2i.ZERO
var symbol_build_count := 0
var navigation_timer := Timer.new()
var navigation_in_progress := false
var text_cache_position := Vector2.ZERO
var text_cache_zoom := 1.
var camera_layout_count := 0
var last_camera_input_usec := 0
const NAVIGATION_SETTLE_SECONDS := .14

func _ready() -> void:
	seed_control.min_value = 0; seed_control.max_value = 4294967295; seed_control.value = 1
	threshold_control.min_value = 0; threshold_control.max_value = 50; threshold_control.step = .1; threshold_control.value = 1
	add_child(map_root)
	add_child(render_scheduler)
	symbol_screen.centered = false; symbol_screen.position = -Vector2.ONE*SYMBOL_PAD; symbol_screen.z_index = 1; add_child(symbol_screen)
	text_layer.z_index = 4; add_child(text_layer)
	make_ui()
	navigation_timer.one_shot = true; navigation_timer.wait_time = NAVIGATION_SETTLE_SECONDS
	navigation_timer.timeout.connect(navigation_timeout); add_child(navigation_timer)
	resized.connect(func():
		if symbol_layers.is_empty() and not high_performance_renderer: return
		forest_view.size = Vector2i(size)+Vector2i.ONE*SYMBOL_PAD*2; symbol_view.size = Vector2i(size) if high_performance_renderer else forest_view.size; limit_pan(); schedule_symbols())
	var actual_seed := 1
	var reference_mode := false
	var cache_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg=="--atlas-legacy-renderer": high_performance_renderer = false
		if arg.begins_with("--atlas-ref="): actual_seed = int(arg.get_slice("=",1)); reference_mode = true
		if arg.begins_with("--atlas-seed="): actual_seed = int(arg.get_slice("=",1))
		if arg=="--atlas-earth": terrain_model = "earth"
		if arg.begins_with("--atlas-rainfall="): rainfall_model = arg.trim_prefix("--atlas-rainfall=")
		if arg.begins_with("--atlas-settlement="): settlement_model = arg.trim_prefix("--atlas-settlement=")
		if arg.begins_with("--atlas-capture="): capture_path = arg.trim_prefix("--atlas-capture=")
		if arg.begins_with("--atlas-cache="): cache_path = arg.trim_prefix("--atlas-cache=")
		if arg=="--atlas-labels": capture_labels = true
		if arg.begins_with("--atlas-zoom="): capture_zoom = float(arg.get_slice("=",1))
		if arg.begins_with("--atlas-center="):
			var xy := arg.get_slice("=",1).split(","); capture_center = Vector2(float(xy[0]),float(xy[1]))
	sync_rain_control()
	if not capture_path.is_empty():
		hud.hide(); get_window().size = Vector2i(2048,1024)
	seed_control.value = actual_seed
	print("ATLAS_PREVIEW_ARGS ",OS.get_cmdline_user_args()," capture=",capture_path)
	await get_tree().process_frame
	if not cache_path.is_empty():
		var payload = FileAccess.open(cache_path,FileAccess.READ).get_var()
		generation_index += 1; begin_log("native_development_cache",int(payload.data.seed))
		var view_start := Time.get_ticks_msec(); await load_cached_payload(payload); open_log("native_development_cache",Time.get_ticks_msec()-view_start)
	elif reference_mode: await load_reference(actual_seed)
	else: await load_native(actual_seed)
	if not capture_path.is_empty() and not data.is_empty():
		zoom = capture_zoom; map_root.scale = Vector2.ONE*zoom; map_root.position = size*.5-capture_center*zoom; limit_pan()
		text_layer.show_names = capture_labels; text_layer.show_cities = capture_labels; refresh_symbols()
		if high_performance_renderer:
			text_layer.rebuild()
			if not await await_render_ready(): printerr("ATLAS_CAPTURE_TIMEOUT"); get_tree().quit(1); return
		print("ATLAS_CAPTURE_PREPARE")
		await get_tree().process_frame
		print("ATLAS_CAPTURE_DRAW")
		RenderingServer.force_draw(true)
		print("ATLAS_CAPTURE_READ")
		get_viewport().get_texture().get_image().save_png(capture_path)
		print("ATLAS_NATIVE_CAPTURE ",capture_path); get_tree().quit()

func load_cached_payload(payload: Dictionary) -> void:
	data = payload.data; raster = payload.raster; display = payload.display; timing = payload.timing
	terrain_model = data.options.get("terrain_model","planet")
	rainfall_model = data.options.get("rainfall_model","atlas_original")
	settlement_model = data.options.get("settlement_model","atlas_original")
	sync_rain_control()
	sync_settlement_mask()
	default_owners = PackedInt32Array(data.ownership); provinces = Generator.pixel_regions(data,raster)
	await build_view()

func make_ui() -> void:
	var panel := PanelContainer.new(); panel.position = Vector2(12,12); panel.add_child(hud); add_child(panel)
	var title := Label.new(); title.text = "civ-atlas · Godot 原生 2D 对照预览"; hud.add_child(title)
	var row := HBoxContainer.new(); hud.add_child(row)
	for text in ["种子","城市阈值 >"]:
		var label := Label.new(); label.text = text; row.add_child(label)
		row.add_child(seed_control if text=="种子" else threshold_control)
	button(row,"重新生成",func(): await load_native(int(seed_control.value)))
	button(row,"真实地球",func(): await load_preset("earth"))
	button(row,"随机星球",func(): await load_preset("planet"))
	button(row,"加载开发对照",func(): await load_reference(int(seed_control.value)))
	button(row,"原生重建城市和道路",rebuild_roads)
	var rain_row := HBoxContainer.new(); hud.add_child(rain_row)
	var rain_label := Label.new(); rain_label.text = "地球降雨"; rain_row.add_child(rain_label)
	rain_control.add_item("环流与内陆水汽 v5",0); rain_control.add_item("旧季节环流 v4（对照）",1); rain_control.add_item("旧季节环流 v3（对照）",2); rain_control.add_item("旧季节环流 v2（对照）",3); rain_control.add_item("旧季风湿润支持（对照）",4); rain_control.add_item("原版气候（对照）",5); rain_row.add_child(rain_control)
	rain_control.item_selected.connect(func(index):
		if generating: sync_rain_control(); return
		rainfall_model = RAIN_MODELS[index]; settlement_model = ""
		if terrain_model=="earth": await load_native(int(seed_control.value)))
	sync_rain_control()
	mask_controls=MaskControls.new(); hud.add_child(mask_controls); mask_controls.setup(self)
	var layers := HBoxContainer.new(); hud.add_child(layers)
	for name_value in ["政治","地形","省份","宜居度"]: mode_control.add_item(name_value)
	layers.add_child(mode_control); mode_control.item_selected.connect(func(_i): update_mode())
	for pair in [["道路","show_roads"],["城市","show_cities"],["边界","show_borders"]]:
		var toggle := CheckButton.new(); toggle.text = pair[0]; toggle.button_pressed = true; layers.add_child(toggle)
		var property: String = pair[1]
		toggle.toggled.connect(func(value):
			if property=="show_cities": text_layer.show_cities = value; text_layer.rebuild()
			elif property=="show_borders":
				show_border_layer = value
				for copy in copies: copy.ink.show_borders = value and mode_control.selected in [0,2]; copy.ink.queue_redraw()
			else:
				for copy in copies: copy.ink.set(property,value); copy.ink.queue_redraw())
	var words := CheckButton.new(); words.text = "文字"; words.button_pressed = true; layers.add_child(words)
	words.toggled.connect(func(value): text_layer.show_names = value; text_layer.rebuild())
	var city_words := CheckButton.new(); city_words.text = "城市名称"; city_words.button_pressed = text_layer.show_city_names; layers.add_child(city_words)
	city_words.toggled.connect(func(value): text_layer.show_city_names = value; text_layer.rebuild())
	button(layers,"全图",fit_map); button(layers,"保存快照",save_snapshot); button(layers,"加载快照",load_snapshot)
	button(layers,"截图",func(): await export_screenshot())
	var ownership_row := HBoxContainer.new(); hud.add_child(ownership_row)
	var ownership_label := Label.new(); ownership_label.text = "选中省份改属国家编号"; ownership_row.add_child(ownership_label)
	owner_control.min_value = 0; owner_control.max_value = 39; ownership_row.add_child(owner_control)
	button(ownership_row,"改归属",change_owner)
	button(ownership_row,"重置归属",func():
		if generating or data.is_empty(): return
		data.ownership = Array(default_owners); refresh_ownership(); log_event("ownership_reset"))
	status.text = "准备参考输入……"; hud.add_child(status); hud.add_child(details)
	details.text = "滚轮缩放 · 中键拖动 · 左键选择（使用曲线修正后的显示归属）"
	var font = load("res://assets/atlas/lxgw-wenkai-gb-500.ttf")
	if font:
		var ui_theme := Theme.new(); ui_theme.default_font = font; hud.theme = ui_theme

func stage_update(stage: String) -> void:
	status.text = "原生生成："+stage
	log_event("stage",{"stage":stage})

func load_preset(model_name: String) -> void:
	if generating: return
	if model_name=="earth" and terrain_model!="earth": rainfall_model = "seasonal_circulation_v5"; settlement_model = ""
	terrain_model = model_name
	await load_native(int(seed_control.value))

func sync_rain_control() -> void:
	var index := RAIN_MODELS.find(rainfall_model); rain_control.select(maxi(0,index))

func native_generation_options() -> Dictionary:
	var options := {"terrain_model":"earth","rainfall_model":rainfall_model} if terrain_model=="earth" else {}
	if terrain_model=="earth" and not settlement_model.is_empty(): options.settlement_model=settlement_model
	if not settlement_mask.is_empty(): options.settlement_mask=SettlementMask.normalize(settlement_mask)
	return options

func sync_settlement_mask() -> void:
	settlement_mask=data.get("options",{}).get("settlement_mask",{}).duplicate()
	if mask_controls!=null: mask_controls.sync()

func load_native(seed_value: int) -> void:
	if generating: return
	var mask_error := SettlementMask.validate(settlement_mask)
	if not mask_error.is_empty(): status.text=mask_error; return
	generating = true; generation_index += 1
	var model_name := "native_earth" if terrain_model=="earth" else "native"
	begin_log(model_name,seed_value)
	status.text = "原生生成：球面网格"; await get_tree().process_frame
	var threshold := threshold_control.value
	var worker := Thread.new(); generation_worker = worker
	var generation_options := native_generation_options()
	var err := worker.start(func(): return Generator.generate(seed_value,threshold,func(stage): call_deferred("stage_update",stage),generation_options))
	if err!=OK: generating = false; status.text = "生成线程无法启动"; log_event("failed",{"error":status.text}); return
	while worker.is_alive(): await get_tree().process_frame
	var payload = worker.wait_to_finish()
	if not payload is Dictionary or not payload.has("data"):
		generating = false; status.text = "生成失败，保留原世界："+str(payload.get("error","未知错误") if payload is Dictionary else "结果无效"); log_event("failed",{"error":status.text}); return
	data = payload.data; raster = payload.raster; display = payload.display; timing = payload.timing
	rainfall_model = data.options.get("rainfall_model","atlas_original"); settlement_model = data.options.get("settlement_model","atlas_original"); sync_rain_control(); sync_settlement_mask()
	default_owners = PackedInt32Array(data.ownership); provinces = Generator.pixel_regions(data,raster)
	var view_started := Time.get_ticks_msec(); await build_view(); generating = false; open_log(model_name,Time.get_ticks_msec()-view_started)
	status.text = "%s · 种子 %d · %d 地块 / %d 省份 / %d 城市 / %d 路段"%["真实地球（生成省份与国家）" if terrain_model=="earth" else "随机星球",seed_value,data.mesh.n,data.regions.count,data.cities.size(),data.roads.size()]

func button(parent: Node,text_value: String,action: Callable) -> void:
	var value := Button.new(); value.text = text_value; parent.add_child(value); value.pressed.connect(action)

func packed_mesh(mesh: Dictionary) -> void:
	for field in ["xyz","x","y","lengths","areas"]: mesh[field] = PackedFloat32Array(mesh[field])
	for field in ["triangles","adj_start","adj"]: mesh[field] = PackedInt32Array(mesh[field])

func read_i16(path: String) -> PackedInt32Array:
	var bytes := FileAccess.get_file_as_bytes(path); var out := PackedInt32Array(); out.resize(bytes.size()/2)
	for i in range(out.size()):
		var value := bytes.decode_u16(2*i); out[i] = value-65536 if value>=32768 else value
	return out

func load_reference(seed_value: int) -> void:
	if generating: return
	var path := REFERENCE+"world-%d.json"%seed_value
	if not FileAccess.file_exists(path): status.text = "尚无种子 %d 的参考输入；开发导出命令见 docs/atlas/README.md。"%seed_value; return
	generation_index += 1; begin_log("reference_input",seed_value)
	status.text = "加载参考网格；Godot 正在计算绘制场……"; await get_tree().process_frame
	var start := Time.get_ticks_msec()
	data = JSON.parse_string(FileAccess.get_file_as_string(path)); packed_mesh(data.mesh)
	for key in ["biome","water"]: data.environment[key] = PackedByteArray(data.environment[key])
	for key in ["elevation","temperature","precipitation","seaIce","suitability","capacity"]: data.environment[key] = PackedFloat32Array(data.environment[key])
	for city in data.cities: city.cell = int(city.cell); city.region = int(city.region)
	display = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE+"display-%d.json"%seed_value))
	var cell := FileAccess.get_file_as_bytes(REFERENCE+"cell-%d.bin"%seed_value).to_int32_array()
	var temp := PackedFloat32Array(); temp.resize(cell.size())
	if FileAccess.file_exists(REFERENCE+"temp-%d.bin"%seed_value): temp = FileAccess.get_file_as_bytes(REFERENCE+"temp-%d.bin"%seed_value).to_float32_array()
	else:
		for k in range(temp.size()): temp[k] = data.environment.temperature[cell[k]]
	raster = {"w":2048,"h":1024,"cell":cell,"temp":temp,
		"water":FileAccess.get_file_as_bytes(REFERENCE+"water-%d.bin"%seed_value),
		"elev":FileAccess.get_file_as_bytes(REFERENCE+"elev-%d.bin"%seed_value).to_float32_array(),
		"biome":FileAccess.get_file_as_bytes(REFERENCE+"biome-%d.bin"%seed_value),
		"ice":FileAccess.get_file_as_bytes(REFERENCE+"ice-%d.bin"%seed_value).to_float32_array()}
	provinces = read_i16(REFERENCE+"provinces-%d.bin"%seed_value)
	display.forest = FileAccess.get_file_as_bytes(REFERENCE+"forest-%d.bin"%seed_value)
	default_owners = PackedInt32Array(data.ownership)
	await build_view()
	open_log("reference_input",Time.get_ticks_msec()-start)
	status.text = "参考输入 %d · %d 地块 / %d 省份 / %d 城市 / %d 路段 · 绘制对照"%[seed_value,data.mesh.n,data.regions.count,data.cities.size(),data.roads.size()]

func build_view() -> void:
	view_ready = false
	var begin := Time.get_ticks_msec()
	var prepared_display := initial_display_plan; initial_display_plan={}
	if high_performance_renderer and prepared_display.is_empty():
		status.text="准备地图绘制数据"; await get_tree().process_frame
		var worker := Thread.new(); generation_worker=worker
		var error := worker.start(func(): return StartupDisplay.prepare(data,raster,provinces,display.glyphs))
		if error!=OK: printerr("ATLAS_DISPLAY_WORKER_FAIL ",error); return
		while worker.is_alive(): await get_tree().process_frame
		prepared_display=worker.wait_to_finish()
	startup_profile.display_prepare_ms=Time.get_ticks_msec()-begin
	startup_display_result=prepared_display
	var upload_begin := Time.get_ticks_msec()
	symbol_cache_zoom = -1.
	navigation_in_progress = false; navigation_timer.stop()
	mode_cache.clear(); prepared_political_texture = null; political_pending = false; render_scheduler.invalidate("political")
	render_scheduler.invalidate("geometry"); render_scheduler.geometry_pending.clear(); render_scheduler.geometry_users.clear()
	for key in render_scheduler.cache.keys():
		if key.begins_with("geometry:"): render_scheduler.forget(key)
	if is_instance_valid(symbol_tiles): symbol_tiles.free(); symbol_tiles = null
	if is_instance_valid(raster_layers): raster_layers.free(); raster_layers=null
	if not data.regions.has("names"): Names.assign(data)
	if not data.has("places"):
		var place_world: Dictionary = data.environment.duplicate(); place_world.mesh = data.mesh; place_world.params = data.params
		data.places = Places.build(place_world)
	owner_control.max_value = maxi(0,data.nations.size()-1)
	for child in map_root.get_children(): child.queue_free()
	coast_ink = CoastInk.new(); coast_ink.scheduler = render_scheduler; coast_ink.high_performance = high_performance_renderer; coast_ink.setup(raster,prepared_display.get("ice",{}),prepared_display.get("coast",{}))
	copies.clear()
	if not prepared_display.is_empty():
		var geo: Dictionary=prepared_display.geometry
		chains=geo.chains; display.lines=geo.lines; province_lines=geo.province_lines
		political_index=geo.political_index; province_index=geo.province_index
		political_segments=Fields.upload_all(geo.political_segments); province_segments=Fields.upload_all(geo.province_segments)
		province_labels=geo.province_labels; political_labels=geo.political_labels; weak_mask=geo.weak
		province_edge=Wash.texture(geo.province_edge); political_edge=Wash.texture(geo.political_edge)
	else:
		chains = Borders.trace(data.mesh,PackedInt32Array(data.regions.of))
		display.lines = Borders.build(chains,PackedInt32Array(data.ownership),data.mesh,raster,PackedInt32Array(data.regions.of))
		var province_owners := PackedInt32Array(); province_owners.resize(data.regions.count)
		for r in range(province_owners.size()): province_owners[r] = r
		province_lines = Borders.build(chains,province_owners,data.mesh,raster,PackedInt32Array(data.regions.of))
		political_index = ZoomGeometry.build(display.lines); political_segments = ZoomGeometry.textures(political_index)
		province_index = ZoomGeometry.build(province_lines); province_segments = ZoomGeometry.textures(province_index)
		province_labels = provinces.duplicate()
		for k in range(province_labels.size()):
			if province_labels[k]<0: province_labels[k] = -2
		var weak := weak_coast()
		weak_mask = weak
		Geometry.band_labels(province_labels,2048,1024,province_lines,weak)
		province_edge = Wash.edge_field(province_labels,2048,1024)
		rebuild_political_labels()
	political_id_texture=Wash.texture(prepared_display.geometry.political_ids if not prepared_display.is_empty() and prepared_display.geometry.has("political_ids") else Wash.id_data(political_labels,2048,1024))
	if symbol_view.get_parent(): remove_child(symbol_view); symbol_view.queue_free()
	else: symbol_view.free()
	if forest_view.get_parent(): remove_child(forest_view); forest_view.queue_free()
	else: forest_view.free()
	forest_view = SubViewport.new(); forest_view.size = Vector2i(size)+Vector2i.ONE*SYMBOL_PAD*2
	forest_view.transparent_bg = true; forest_view.disable_3d = true; forest_view.render_target_update_mode = SubViewport.UPDATE_ONCE; add_child(forest_view)
	var forest_shapes := Symbols.new(); forest_shapes.data = data; forest_shapes.forest = display.forest; forest_shapes.layer = "forest"; forest_view.add_child(forest_shapes)
	symbol_view = SubViewport.new(); symbol_view.size = forest_view.size
	symbol_view.transparent_bg = true; symbol_view.disable_3d = true
	if RenderingServer.get_current_rendering_method() != "gl_compatibility": symbol_view.msaa_2d = Viewport.MSAA_4X
	symbol_view.render_target_update_mode = SubViewport.UPDATE_ONCE; add_child(symbol_view)
	var forest_sprite := Sprite2D.new(); forest_sprite.centered = false; forest_sprite.texture = forest_view.get_texture()
	forest_material = ShaderMaterial.new(); forest_material.shader = load("res://assets/atlas/forest.gdshader")
	forest_material.set_shader_parameter("shade_distance",data.mesh.spacing*.42); forest_sprite.material = forest_material; symbol_view.add_child(forest_sprite)
	var crowns := Symbols.new(); crowns.data = data; crowns.forest = display.forest; crowns.layer = "crowns"
	crown_material = ShaderMaterial.new(); crown_material.shader = load("res://assets/atlas/crown_clip.gdshader"); crown_material.set_shader_parameter("canopy_mask",forest_view.get_texture()); crowns.material = crown_material; symbol_view.add_child(crowns)
	var symbols := Symbols.new(); symbols.data = data; symbols.glyphs = display.glyphs; symbols.layer = "glyphs"; symbol_view.add_child(symbols)
	symbol_layers = [forest_shapes,crowns,symbols]; symbol_screen.texture = symbol_view.get_texture()
	var fields := Fields.upload_all(prepared_display.fields) if not prepared_display.is_empty() else Fields.textures(raster,data,display.glyphs)
	field_textures = fields
	habitat_texture = Fields.upload(prepared_display.habitat) if not prepared_display.is_empty() else Fields.habitat_texture(data,raster)
	var base_material := ShaderMaterial.new(); base_material.shader = load("res://assets/atlas/paper.gdshader")
	paper_material = base_material
	var ice_geometry: Dictionary
	if not prepared_display.is_empty(): ice_geometry={"lines":prepared_display.ice_geometry.lines,"textures":Fields.upload_all(prepared_display.ice_geometry.textures)}
	else: ice_geometry=IceGeometry.build(raster)
	for key in ice_geometry.textures: base_material.set_shader_parameter(key,ice_geometry.textures[key])
	for field in fields: base_material.set_shader_parameter({"paint":"paint_fields","field":"world_fields","distance":"distances","detail":"detail_fields"}[field],fields[field])
	var base := ImageTexture.create_from_image(Image.create(2048,1024,false,Image.FORMAT_RGBA8))
	if high_performance_renderer:
		raster_layers=preload("res://scripts/atlas/raster_layers.gd").new(); add_child(raster_layers)
		raster_layers.setup(base,base_material,render_scheduler)
	var ink := Ink.new(); ink.scheduler = render_scheduler; ink.high_performance = high_performance_renderer; ink.data = data; ink.borders = display.lines; ink.route_lines = Ink.road_lines(data)
	for shift in [-2048.,0.,2048.]:
		var root := Node2D.new(); root.position.x = shift; map_root.add_child(root)
		var background := Sprite2D.new(); background.centered = false; background.texture = base; background.material = base_material; root.add_child(background)
		if high_performance_renderer: raster_layers.bind(background)
		var wash_sprite := Sprite2D.new(); wash_sprite.centered = false; wash_sprite.z_index = 2; root.add_child(wash_sprite)
		copies.append({"wash":wash_sprite,"ink":ink})
	ink.z_index = 3; map_root.add_child(ink)
	coast_ink.z_index = 1; map_root.add_child(coast_ink)
	text_layer.data = data; text_layer.raster = raster
	if not prepared_display.is_empty(): text_layer.labels=prepared_display.geometry.names
	else: refit_names()
	if high_performance_renderer:
		for node in symbol_view.get_children(): node.queue_free()
		forest_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		symbol_layers.clear()
		symbol_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		symbol_view.msaa_2d = Viewport.MSAA_DISABLED # Tiles already contain resolved 4x MSAA.
		symbol_view.size = Vector2i(size)
		symbol_tiles = SymbolTiles.new(); symbol_tiles.static_world=true; symbol_tiles.world_screen=symbol_screen
		add_child(symbol_tiles); symbol_tiles.world_ready.connect(func():
			for copy in copies:
				if copy.wash.material: symbol_tiles.bind_world_material(copy.wash.material))
		symbol_tiles.setup(data,display,render_scheduler,symbol_view)
		text_layer.high_performance = true; text_layer.static_world=true; text_layer.scheduler = render_scheduler
	fit_map(); update_mode(); refresh_symbols()
	await get_tree().process_frame
	if high_performance_renderer and not await await_render_ready(60000): printerr("ATLAS_INITIAL_RENDER_TIMEOUT")
	view_ready = true
	startup_profile.display_upload_ms=Time.get_ticks_msec()-upload_begin

func political_colors() -> Array:
	var colors: Array=[]
	for nation in display.nations: colors.append(Color8(nation.color[0],nation.color[1],nation.color[2]))
	return colors

func update_mode() -> void:
	if data.is_empty(): return
	if navigation_in_progress: finish_navigation()
	if high_performance_renderer and mode_cache.has(mode_control.selected):
		apply_cached_mode(); return
	var colors: Array = []; labels.resize(provinces.size())
	var mode := mode_control.selected
	if mode==3:
		for copy in copies:
			copy.wash.texture = habitat_texture; copy.wash.material = null; copy.wash.visible = true; copy.wash.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			copy.ink.show_borders = false; copy.ink.queue_redraw()
		text_layer.show_polities = false; text_layer.rebuild(); return
	colors=political_colors()
	if mode == 2:
		colors.clear()
		for r in range(data.regions.count): colors.append(Color.from_hsv(fmod(r*.61803398875,1),.36,.76))
	labels = political_labels if mode in [0,1] else province_labels
	var color_texture := prepared_political_texture if mode in [0,1] and prepared_political_texture!=null else Wash.color_texture(labels,2048,1024,colors)
	var material := ShaderMaterial.new(); material.shader = load("res://assets/atlas/wash.gdshader")
	material.set_shader_parameter("edge_field",political_edge if mode in [0,1] else province_edge)
	material.set_shader_parameter("symbols",symbol_view.get_texture())
	if is_instance_valid(symbol_tiles) and symbol_tiles.static_world: symbol_tiles.bind_world_material(material)
	var segments: Dictionary = political_segments if mode in [0,1] else province_segments
	for key in segments: material.set_shader_parameter(key,segments[key])
	var palette_values := PackedInt32Array(); palette_values.resize(maxi(1,colors.size()))
	for i in range(palette_values.size()): palette_values[i] = i
	if colors.is_empty(): palette_values.fill(-2)
	material.set_shader_parameter("palette",Wash.color_texture(palette_values,palette_values.size(),1,colors))
	material.set_shader_parameter("owner_ids",political_id_texture)
	material.set_shader_parameter("use_owner_palette",mode==0)
	material.set_shader_parameter("world_fields",field_textures.field)
	material.set_shader_parameter("symbol_origin",symbol_cache_position+Vector2.ONE*SYMBOL_PAD)
	material.set_shader_parameter("symbol_scale",symbol_cache_zoom if symbol_cache_zoom>0 else zoom)
	material.set_shader_parameter("view_zoom",zoom)
	for copy in copies:
		copy.wash.texture = color_texture; copy.wash.material = material; copy.wash.visible = mode!=1; copy.wash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		copy.ink.borders = province_lines if mode==2 else current_political_borders()
		copy.ink.show_borders = show_border_layer and mode in [0,2]; copy.ink.queue_redraw()
	text_layer.show_polities = mode==0
	text_layer.owners = political_labels
	text_layer.rebuild()
	if high_performance_renderer:
		mode_cache[mode] = {"texture":color_texture,"material":material}; refresh_cached_camera()

func apply_cached_mode() -> void:
	var mode := mode_control.selected; var cached: Dictionary = mode_cache[mode]
	labels = political_labels if mode in [0,1] else province_labels
	for copy in copies:
		copy.wash.texture = cached.texture; copy.wash.material = cached.material; copy.wash.visible = mode!=1
		copy.ink.borders = province_lines if mode==2 else current_political_borders()
		copy.ink.show_borders = show_border_layer and mode in [0,2]; copy.ink.queue_redraw()
	text_layer.show_polities = mode==0; text_layer.owners = political_labels; text_layer.rebuild(); refresh_cached_camera()

func rebuild_political_labels() -> void:
	political_labels.resize(provinces.size())
	for i in range(provinces.size()): political_labels[i] = int(data.ownership[provinces[i]]) if provinces[i]>=0 else -2
	Geometry.band_labels(political_labels,2048,1024,display.lines,weak_coast())
	political_edge = Wash.edge_field(political_labels,2048,1024)

func refit_names() -> void:
	var grid := PackedInt32Array(); grid.resize(512*256)
	for y in range(256):
		for x in range(512): grid[y*512+x] = provinces[(y*4+2)*2048+x*4+2]
	text_layer.labels = LabelPlan.fit_all(data,LabelPlan.field(grid,PackedInt32Array(data.ownership),512,256))

func weak_coast() -> PackedByteArray:
	var weak := PackedByteArray(); weak.resize(provinces.size())
	for k in range(weak.size()):
		if raster.water[k]==0 and data.regions.of[raster.cell[k]]<0: weak[k] = 1
	return weak

func refresh_ownership() -> void:
	if data.is_empty(): return
	if high_performance_renderer:
		prepare_political(); return
	display.lines = Borders.build(chains,PackedInt32Array(data.ownership),data.mesh,raster,PackedInt32Array(data.regions.of))
	political_index = ZoomGeometry.build(display.lines); political_segments = ZoomGeometry.textures(political_index)
	rebuild_political_labels()
	political_id_texture=Wash.texture(Wash.id_data(political_labels,2048,1024))
	refit_names(); update_mode()

func prepare_political() -> void:
	political_pending = true; political_revision += 1; var revision := political_revision
	render_scheduler.invalidate("political")
	var ownership := PackedInt32Array(data.ownership)
	var front_snapshot := political_front_snapshot()
	var input := {"chains":chains,"ownership":ownership,"mesh":data.mesh,"raster":raster,"region_of":PackedInt32Array(data.regions.of),"provinces":provinces,"weak":weak_mask,"fronts":front_snapshot,"data":{"mesh":data.mesh,"regions":data.regions,"ownership":ownership,"nations":data.nations.duplicate(true)}}
	render_scheduler.submit("political",func(): return PoliticalDisplay.calculate(input),func(result):
		var uploaded := {}
		var geometry := {}; var geometry_bytes := {}
		for kind in result.stroke_plans:
			var name_value: String = kind; geometry[name_value] = []; geometry_bytes[name_value] = 0
			for row in result.stroke_plans[kind]:
				var buffer: Dictionary = row
				geometry_bytes[name_value] += buffer.vertices.size()*96+buffer.indices.size()*8
				render_scheduler.enqueue(func(): geometry[name_value].append({"mesh":Ink.Persistent.resource(buffer),"box":buffer.box}),0,"political")
		for key in result.segments:
			var buffer: Dictionary = result.segments[key]; var name_value: String = key
			render_scheduler.enqueue(func(): uploaded[name_value] = ZoomGeometry.upload(buffer),0,"political")
		render_scheduler.enqueue(func(): uploaded.edge = Wash.texture(result.edge),0,"political")
		render_scheduler.enqueue(func(): uploaded.color = Wash.texture(result.color),0,"political")
		render_scheduler.enqueue(func(): uploaded.ids = Wash.texture(result.ids),0,"political")
		render_scheduler.enqueue(func():
			if revision!=political_revision: return
			if political_front_snapshot().signature!=front_snapshot.signature: prepare_political(); return
			for kind in geometry:
				var key := "geometry:%d:%d"%[render_scheduler.versions.get("geometry",0),result.stroke_keys[kind]]
				render_scheduler.remember(key,geometry[kind],geometry_bytes[kind],true)
			display.lines = result.lines; political_index = result.index; political_labels = result.labels
			political_id_texture=uploaded.ids
			political_segments = uploaded.duplicate(); political_segments.erase("edge"); political_segments.erase("color"); political_segments.erase("ids")
			political_edge = uploaded.edge; prepared_political_texture = uploaded.color; text_layer.labels = result.names
			mode_cache.erase(0); mode_cache.erase(1); political_pending = false
			political_display_ready(); update_mode(),0,"political"),-1)

func political_front_snapshot() -> Dictionary:
	return {"roles":{},"signature":0}

func current_political_borders() -> Array:
	return display.lines

func political_display_ready() -> void:
	pass

func change_owner() -> void:
	if generating or selected_region<0: return
	data.ownership[selected_region] = int(owner_control.value); refresh_ownership()
	log_event("ownership",{"region":selected_region,"owner":int(owner_control.value)})
	status.text = "省份归属已更新；网格、省份与道路未重新生成"

func rebuild_roads() -> void:
	if generating or data.is_empty(): return
	status.text = "原生道路重建中……"; await get_tree().process_frame
	var start := Time.get_ticks_msec()
	data.cities = Roads.seat_cities(data.mesh,data.environment,data.regions,threshold_control.value)
	var roads := Roads.build(data.mesh,data.environment,data.cities); data.roads = roads.routes; data.connections = roads.connections
	Names.assign(data); text_layer.data = data; text_layer.rebuild()
	data.options.city_threshold = threshold_control.value; log_event("city_threshold",{"value":threshold_control.value,"cities":data.cities.size(),"roads":data.roads.size()})
	for copy in copies: copy.ink.data = data; copy.ink.route_lines = Ink.road_lines(data); copy.ink.queue_redraw()
	status.text = "原生城市/道路 · %d 城市 · %d 路段 · %d ms"%[data.cities.size(),data.roads.size(),Time.get_ticks_msec()-start]

func fit_map() -> void:
	navigation_in_progress = false; navigation_timer.stop()
	zoom = minf(size.x/2048.0,size.y/1024.0); map_root.scale = Vector2.ONE*zoom
	map_root.position = (size-Vector2(2048,1024)*zoom)/2
	schedule_symbols()

func schedule_symbols() -> void:
	if symbol_pending or (symbol_layers.is_empty() and not high_performance_renderer): return
	symbol_pending = true; call_deferred("refresh_symbols")

func refresh_symbols() -> void:
	symbol_pending = false
	if high_performance_renderer and is_instance_valid(symbol_tiles):
		refresh_cached_camera(); return
	if symbol_layers.is_empty(): return
	if navigation_in_progress:
		camera_feedback(); return
	var delta := map_root.position-symbol_cache_position
	delta.x -= roundf(delta.x/(2048.*zoom))*2048.*zoom
	var reuse := is_equal_approx(symbol_cache_zoom,zoom) and symbol_cache_size==symbol_view.size and absf(delta.x)<=SYMBOL_PAD-32 and absf(delta.y)<=SYMBOL_PAD-32
	if not reuse:
		symbol_cache_position = map_root.position; symbol_cache_zoom = zoom; symbol_cache_size = symbol_view.size
		delta = Vector2.ZERO; symbol_build_count += 1
	var origin := symbol_cache_position+Vector2.ONE*SYMBOL_PAD
	symbol_screen.position = delta-Vector2.ONE*SYMBOL_PAD; symbol_screen.scale = Vector2.ONE
	var k := maxf(1.,zoom); var gs := 1.0 if k<=1.35 else pow(k/1.35,-.22)
	paper_material.set_shader_parameter("view_zoom",zoom); paper_material.set_shader_parameter("glyph_scale",gs)
	coast_ink.zoom = zoom; coast_ink.visible_world = Rect2(-map_root.position/zoom,size/zoom); coast_ink.rebuild()
	if not reuse:
		var rect := Rect2(-origin/zoom,Vector2(symbol_view.size)/zoom)
		for layer in symbol_layers:
			layer.detail_zoom = k; layer.visible_world = rect; layer.scale = Vector2.ONE*zoom; layer.position = origin; layer.queue_redraw()
		forest_material.set_shader_parameter("shade_distance",data.mesh.spacing*.42*gs*zoom)
		forest_material.set_shader_parameter("glyph_scale",gs); forest_material.set_shader_parameter("view_scale",zoom); forest_material.set_shader_parameter("view_origin",origin)
		crown_material.set_shader_parameter("view_origin",origin); crown_material.set_shader_parameter("view_scale",zoom)
		forest_view.render_target_update_mode = SubViewport.UPDATE_ONCE; symbol_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	for copy in copies:
		if copy.wash.material:
			copy.wash.material.set_shader_parameter("symbol_origin",origin); copy.wash.material.set_shader_parameter("symbol_scale",zoom)
			copy.wash.material.set_shader_parameter("view_zoom",zoom)
		copy.ink.pen = gs; copy.ink.view_zoom = zoom
		copy.ink.visible_world = Rect2(-map_root.position/zoom,size/zoom); copy.ink.queue_redraw()
	text_layer.position = Vector2.ZERO; text_layer.scale = Vector2.ONE
	text_layer.origin = map_root.position; text_layer.zoom = zoom; text_layer.canvas_size = size; text_layer.rebuild()
	text_cache_position = map_root.position; text_cache_zoom = zoom; camera_layout_count += 1

func start_navigation() -> void:
	if high_performance_renderer: return
	navigation_in_progress = true
	last_camera_input_usec = Time.get_ticks_usec()
	if navigation_timer.is_inside_tree(): navigation_timer.start(NAVIGATION_SETTLE_SECONDS)

func navigation_timeout() -> void:
	if not navigation_in_progress: return
	# A heavy preceding frame can advance a Timer past its duration immediately
	# after fresh input. Debounce against real elapsed time, not that frame's delta.
	var remaining := NAVIGATION_SETTLE_SECONDS-(Time.get_ticks_usec()-last_camera_input_usec)/1000000.
	if remaining>0: navigation_timer.start(remaining)
	else: finish_navigation()

func finish_navigation() -> void:
	navigation_in_progress = false; navigation_timer.stop(); refresh_symbols()

func camera_feedback() -> void:
	if high_performance_renderer and is_instance_valid(symbol_tiles): refresh_cached_camera(); return
	# Reproject existing screen-space ink immediately; settle to exact label/glyph
	# sizes after the input burst, instead of rebuilding on every mouse event.
	if symbol_cache_zoom<=0: return
	var ratio := zoom/symbol_cache_zoom
	var delta := map_root.position-symbol_cache_position*ratio
	delta.x -= roundf(delta.x/(2048.*zoom))*2048.*zoom
	symbol_screen.scale = Vector2.ONE*ratio
	symbol_screen.position = delta-Vector2.ONE*SYMBOL_PAD*ratio
	var text_ratio := zoom/text_cache_zoom
	var text_delta := map_root.position-text_cache_position*text_ratio
	text_delta.x -= roundf(text_delta.x/(2048.*zoom))*2048.*zoom
	text_layer.scale = Vector2.ONE*text_ratio; text_layer.position = text_delta
	paper_material.set_shader_parameter("view_zoom",zoom)
	for copy in copies:
		if copy.wash.material: copy.wash.material.set_shader_parameter("view_zoom",zoom)

func refresh_cached_camera() -> void:
	var origin := map_root.position
	if is_instance_valid(raster_layers): raster_layers.set_zoom(zoom)
	symbol_tiles.set_camera(origin,zoom,Vector2(symbol_view.size))
	if not symbol_tiles.static_world: symbol_screen.position = Vector2.ZERO; symbol_screen.scale = Vector2.ONE
	symbol_cache_position = map_root.position; symbol_cache_zoom = zoom
	var rect := Rect2(-map_root.position/zoom,size/zoom)
	var gs := pow(maxf(1.,zoom/1.35),-.22)
	paper_material.set_shader_parameter("view_zoom",zoom); paper_material.set_shader_parameter("glyph_scale",gs)
	coast_ink.zoom = zoom; coast_ink.visible_world = rect; coast_ink.rebuild()
	for copy in copies:
		if copy.wash.material:
			if not symbol_tiles.static_world:
				copy.wash.material.set_shader_parameter("symbol_origin",origin); copy.wash.material.set_shader_parameter("symbol_scale",zoom)
			copy.wash.material.set_shader_parameter("view_zoom",zoom)
	if not copies.is_empty():
		var ink: Node2D = copies[0].ink; ink.view_zoom = zoom; ink.visible_world = rect
		if ink.persistent_layers.is_empty(): ink.update_persistent()
		else:
			for layer in ink.persistent_layers: layer.set_zoom(zoom); layer.set_view(rect)
	text_layer.set_camera(map_root.position,zoom,size)

func render_is_ready() -> bool:
	if not high_performance_renderer: return true
	if political_pending or not is_instance_valid(symbol_tiles) or not symbol_tiles.is_ready() or not text_layer.is_ready(): return false
	for node in map_root.get_children():
		if "persistent_layers" in node:
			for layer in node.persistent_layers:
				if layer.preparing: return false
	return true

func await_render_ready(timeout_ms: int = 10000) -> bool:
	var deadline := Time.get_ticks_msec()+timeout_ms
	while not render_is_ready() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	return render_is_ready()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE: dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			start_navigation()
			var before := map_root.to_local(event.position)
			zoom = clampf(zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.2),minf(size.x/2048.,size.y/1024.),8.)
			map_root.scale = Vector2.ONE*zoom; map_root.position = event.position-before*zoom; limit_pan()
			schedule_symbols()
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT: select_at(map_root.to_local(event.position))
	elif event is InputEventMouseMotion and dragging:
		start_navigation(); map_root.position += event.relative; limit_pan(); schedule_symbols()

func limit_pan() -> void:
	map_root.position.x = fposmod(map_root.position.x+2048*zoom,2048*zoom)-2048*zoom
	map_root.position.y = clampf(map_root.position.y,minf(0,size.y-1024*zoom),maxf(0,size.y-1024*zoom))

func select_at(position_value: Vector2) -> void:
	if data.is_empty() or position_value.y<0 or position_value.y>=1024: return
	var x := int(floor(fposmod(position_value.x,2048))); var y := int(floor(position_value.y)); var k := y*2048+x
	selected_region = province_labels[k]
	if zoom>1.35:
		var region_hit := ZoomGeometry.nearest(province_index,fposmod(position_value.x,2048),position_value.y)
		if region_hit.side!=ZoomGeometry.KEEP: selected_region = region_hit.side
	if selected_region<0: details.text = "海洋／湖泊"; return
	var owner := labels[k] if mode_control.selected==0 else int(data.ownership[selected_region])
	if zoom>1.35 and mode_control.selected==0:
		var owner_hit := ZoomGeometry.nearest(political_index,fposmod(position_value.x,2048),position_value.y)
		if owner_hit.side!=ZoomGeometry.KEEP: owner = owner_hit.side
	if owner>=0 and mode_control.selected==0 and int(data.ownership[selected_region])!=owner:
		var nearest := INF; var found := -1
		for dy in range(-8,9):
			for dx in range(-8,9):
				var yy := y+dy
				if yy<0 or yy>=1024: continue
				var r: int = provinces[yy*2048+posmod(x+dx,2048)]
				if r<0 or int(data.ownership[r])!=owner: continue
				var distance := float(dx*dx+dy*dy)
				if distance<nearest: nearest = distance; found = r
		if found>=0: selected_region = found
	owner_control.value = maxi(0,owner)
	var seat := int(data.regions.seat[selected_region])
	details.text = "省 %d（%s）· 可见国家 %d · 治所宜居度 %.3f · 高程 %.0f m"%[selected_region,data.regions.names[selected_region],owner,data.environment.suitability[seat],raster.elev[k]]
	var climate_cell := int(raster.cell[k])
	if data.environment.has("quarter_precipitation"):
		var totals: Array = []
		for quarter in data.environment.quarter_precipitation: totals.append(roundi(quarter[climate_cell]*.25))
		details.text += "\n模型年降水 ≈%.0f mm · 冬/春/夏/秋 ≈%s mm（估计）"%[data.environment.precipitation[climate_cell],str(totals)]
	if data.environment.has("aridity_index"):
		var season_label := "适宜季节折算" if data.options.get("settlement_model","") in ["climate_capacity_v6","climate_capacity_v5","climate_capacity_v4"] else "适温适水生长季"
		details.text += "\n年潜在蒸散 ≈%.0f mm · 水分比 %.2f · %s ≈%.1f 月"%[data.environment.potential_evaporation[climate_cell],data.environment.aridity_index[climate_cell],season_label,data.environment.growing_months[climate_cell]]

func save_snapshot() -> void:
	if generating or data.is_empty(): return
	var error := Snapshot.save_file(snapshot_path,{"format":Snapshot.FORMAT,"version":Snapshot.VERSION,"data":data,"display":display,"raster":raster,"provinces":provinces,"default_owners":default_owners,"timing":timing})
	status.text = "快照已保存："+ProjectSettings.globalize_path(snapshot_path) if error.is_empty() else "快照保存失败："+error
	log_event("snapshot_save",{"error":error})

func load_snapshot() -> void:
	if generating: return
	if not FileAccess.file_exists(snapshot_path): status.text = "尚无预览快照"; return
	var result := Snapshot.load_file(snapshot_path)
	if result.has("error"): status.text = "快照加载失败，保留原世界："+result.error; return
	var payload: Dictionary = result.payload
	data = payload.data; display = payload.display; raster = payload.raster; provinces = payload.provinces
	default_owners = PackedInt32Array(payload.get("default_owners",data.ownership)); timing = payload.get("timing",{})
	seed_control.value = data.seed; threshold_control.value = data.options.city_threshold
	terrain_model = data.options.get("terrain_model","planet")
	rainfall_model = data.options.get("rainfall_model","atlas_original")
	settlement_model = data.options.get("settlement_model","atlas_original")
	sync_rain_control()
	sync_settlement_mask()
	generation_index += 1; begin_log("snapshot",int(data.seed)); var start := Time.get_ticks_msec()
	await build_view(); status.text = "预览快照已恢复"; open_log("snapshot",Time.get_ticks_msec()-start)

func export_screenshot() -> void:
	if data.is_empty(): return
	if navigation_in_progress: finish_navigation()
	if not await await_render_ready(): status.text = "截图失败：地图细节准备超时"; return
	hud.hide(); await get_tree().process_frame; RenderingServer.force_draw(true)
	var path := "user://atlas-%s-%d.png"%[data.options.get("terrain_model","planet"),int(data.get("seed",0))]
	get_viewport().get_texture().get_image().save_png(path); hud.show(); status.text = "截图："+ProjectSettings.globalize_path(path); log_event("screenshot",{"path":ProjectSettings.globalize_path(path)})

func begin_log(model: String,seed_value: int) -> void:
	if log_file: log_file.close()
	var directory := "user://debug_runs/atlas_preview"; DirAccess.make_dir_recursive_absolute(directory)
	var path := directory+"/atlas-%d-%d-%d.jsonl"%[OS.get_process_id(),Time.get_unix_time_from_system(),generation_index]
	log_file = FileAccess.open(path,FileAccess.WRITE); active_seed = seed_value; active_model = model; generation_started = Time.get_ticks_msec()
	log_event("start",{"upstream":"103afd3d998eac6750692a6813bf5aea03521448","godot":Engine.get_version_info(),"base_commit":"9d26b1b1ddbe7736ef62d781c1f01c4c77f8a464","code_commit":current_commit(),"source_fingerprint":source_fingerprint(),"code_version":"atlas-native-port-v1","city_threshold":threshold_control.value})
	print("ATLAS_PREVIEW_LOG ",ProjectSettings.globalize_path(path))

static func current_commit() -> String:
	# Local development metadata only; no shell, network, or simulation dependency.
	var path := "res://.git/HEAD"
	if not FileAccess.file_exists(path): return "unavailable-in-export"
	var head := FileAccess.get_file_as_string(path).strip_edges()
	if not head.begins_with("ref: "): return head
	var ref := head.substr(5); var loose := "res://.git/"+ref
	if FileAccess.file_exists(loose): return FileAccess.get_file_as_string(loose).strip_edges()
	if FileAccess.file_exists("res://.git/packed-refs"):
		for line in FileAccess.get_file_as_string("res://.git/packed-refs").split("\n"):
			if line.ends_with(" "+ref): return line.get_slice(" ",0)
	return "unavailable"

static func source_fingerprint() -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256)
	var files: Array = ["res://atlas_preview.tscn","res://atlas_earth_preview.tscn","res://scripts/core/rainfall_transport.gd"]
	for directory in ["res://scripts/atlas/","res://assets/atlas/"]:
		var folder := DirAccess.open(directory)
		if not folder: continue
		for name_value in folder.get_files():
			if name_value.get_extension() in ["gd","gdshader","json","ttf"]: files.append(directory+name_value)
	files.sort()
	for path in files:
		context.update(path.to_utf8_buffer()); context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()

func _exit_tree() -> void:
	if generation_worker!=null and generation_worker.is_started(): generation_worker.wait_to_finish()
	if log_file: log_file.close()

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	# Node-valued script members are not automatically owned by the scene tree.
	# The military UI omits some preview controls; free those unused members too.
	for property in get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var value = get(property.name)
		if is_instance_valid(value) and value is Node and value.get_parent() == null and not value.is_queued_for_deletion():
			value.free()

func log_event(event: String,extra: Dictionary = {}) -> void:
	if not log_file: return
	var record := {"event":event,"pid":OS.get_process_id(),"seed":active_seed,"model":active_model,"world_index":generation_index,"scene":scene_file_path if not scene_file_path.is_empty() else "res://atlas_preview.tscn","elapsed_ms":Time.get_ticks_msec()-generation_started}
	record.merge(extra,true); log_file.store_line(JSON.stringify(record)); log_file.flush()

func open_log(model: String,elapsed: int) -> void:
	if not log_file: begin_log(model,int(data.seed))
	log_event("ready",{"params":data.params,"options":data.options,"timing":timing,"cells":data.mesh.n,"regions":data.regions.count,"cities":data.cities.size(),"roads":data.roads.size(),"view_ms":elapsed})
