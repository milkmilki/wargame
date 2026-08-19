extends Node
## 入口：装配 GameState / Simulation / 3D 战略地图 / HUD。

@export var use_grid_world: bool = false
@export var use_3d_map: bool = true
@export_range(1, GameState.TERRAIN_CITY_COUNT, 1) var nation_count: int = (
	GameState.NATION_COUNT
)
@export_range(1, 500, 1) var terrain_city_count: int = (
	GameState.TERRAIN_CITY_COUNT
)
@export var world_seed: int = 12345
@export_range(
	MapRenderer.ARMY_ICON_SCALE_MIN,
	MapRenderer.ARMY_ICON_SCALE_MAX,
	MapRenderer.ARMY_ICON_SCALE_STEP
) var initial_army_icon_scale: float = (
	MapRenderer.ARMY_ICON_SCALE_DEFAULT
)
@export var initial_city_names_visible: bool = true

@onready var simulation: Simulation = $Simulation
@onready var renderer: MapRenderer = $MapRenderer
@onready var map_3d: StrategicMap3D = get_node_or_null(
	"StrategicMap3D"
)
@onready var road_tuning_panel: RoadTuningPanel = get_node_or_null(
	"RoadTuningLayer"
) as RoadTuningPanel
@onready var map_editor_panel: MapEditorPanel = get_node_or_null(
	"MapEditorLayer"
) as MapEditorPanel
@onready var settings_button: Button = $SettingsLayer/SettingsButton
@onready var settings_overlay: Control = $SettingsLayer/SettingsOverlay
@onready var resolution_option: OptionButton = (
	$SettingsLayer/SettingsOverlay/SettingsPanel/Margin/Content/ResolutionOption
)
@onready var resolution_hint: Label = (
	$SettingsLayer/SettingsOverlay/SettingsPanel/Margin/Content/ResolutionHint
)
@onready var settings_close_button: Button = (
	$SettingsLayer/SettingsOverlay/SettingsPanel/Margin/Content/Actions/CloseButton
)
@onready var settings_apply_button: Button = (
	$SettingsLayer/SettingsOverlay/SettingsPanel/Margin/Content/Actions/ApplyButton
)

var state: GameState
var _seed: int = 12345
var _speed_mult: float = 1.0
var _settings_previous_pause: bool = false
var _road_previous_pause: bool = false
var _editor_previous_pause: bool = false
var _city_generation_mask_path: String = GameState.DEFAULT_CITY_MASK_PATH


func _ready() -> void:
	_setup_display_settings()
	if road_tuning_panel != null:
		_setup_road_tuning()
	if map_editor_panel != null:
		_setup_map_editor()
	_seed = world_seed
	_start_new_game(_seed)


func _setup_display_settings() -> void:
	var settings_font := MapRenderer.create_ui_font()
	_apply_settings_font(settings_button, settings_font)
	_apply_settings_font(settings_overlay, settings_font)
	_apply_command_button_style(settings_button)
	_apply_settings_panel_style()
	resolution_option.get_popup().add_theme_font_override(
		"font",
		settings_font
	)
	var saved_resolution := DisplaySettings.load_resolution()
	DisplaySettings.apply_resolution(saved_resolution)
	resolution_option.clear()
	for resolution in DisplaySettings.RESOLUTIONS:
		var index := resolution_option.item_count
		resolution_option.add_item(
			"%d × %d" % [resolution.x, resolution.y]
		)
		resolution_option.set_item_metadata(index, resolution)
		if resolution == saved_resolution:
			resolution_option.select(index)
	settings_button.pressed.connect(_open_settings)
	settings_close_button.pressed.connect(_close_settings)
	settings_apply_button.pressed.connect(_apply_display_settings)


func _apply_command_button_style(button: Button) -> void:
	button.add_theme_color_override(
		"font_color", MapRenderer.PAPER_LIGHT
	)
	button.add_theme_color_override(
		"font_hover_color", Color.WHITE
	)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.075, 0.095, 0.060, 0.97)
	normal.border_color = MapRenderer.ACCENT_GOLD.darkened(0.28)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.16, 0.095, 0.98)
	hover.border_color = MapRenderer.ACCENT_GOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = MapRenderer.ACCENT_GOLD.darkened(0.50)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)


func _apply_settings_panel_style() -> void:
	var panel := (
		$SettingsLayer/SettingsOverlay/SettingsPanel
		as PanelContainer
	)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.075, 0.068, 0.052, 0.985)
	panel_style.border_color = MapRenderer.ACCENT_GOLD.darkened(0.18)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", panel_style)
	_apply_command_button_style(settings_close_button)
	_apply_command_button_style(settings_apply_button)


func _apply_settings_font(control: Control, font: Font) -> void:
	control.add_theme_font_override("font", font)
	for child in control.get_children():
		if child is Control:
			_apply_settings_font(child as Control, font)


func _open_settings() -> void:
	if settings_overlay.visible:
		return
	if (
		road_tuning_panel != null
		and road_tuning_panel.is_open()
	):
		road_tuning_panel.close_panel()
	if map_editor_panel != null and map_editor_panel.is_open():
		map_editor_panel.close_panel()
	_settings_previous_pause = simulation.paused
	simulation.paused = true
	settings_overlay.visible = true


func _close_settings() -> void:
	if not settings_overlay.visible:
		return
	settings_overlay.visible = false
	simulation.paused = _settings_previous_pause


func _apply_display_settings() -> void:
	var resolution: Vector2i = (
		resolution_option.get_selected_metadata()
	)
	var save_error := DisplaySettings.save_resolution(resolution)
	if save_error != OK:
		resolution_hint.text = (
			"设置保存失败（错误码 %d），请检查用户目录权限。"
			% save_error
		)
		return
	DisplaySettings.apply_resolution(resolution)
	resolution_hint.text = "应用后窗口将按所选分辨率固定并自动居中。"
	_close_settings()


func _setup_road_tuning() -> void:
	road_tuning_panel.panel_opened.connect(_on_road_panel_opened)
	road_tuning_panel.panel_closed.connect(_on_road_panel_closed)
	road_tuning_panel.regenerate_requested.connect(
		_on_road_regenerate_requested
	)
	road_tuning_panel.province_strength_changed.connect(
		_on_province_strength_changed
	)


func _on_road_panel_opened() -> void:
	if settings_overlay.visible:
		_close_settings()
	if map_editor_panel != null and map_editor_panel.is_open():
		map_editor_panel.close_panel()
	_road_previous_pause = simulation.paused
	simulation.paused = true


func _on_road_panel_closed() -> void:
	simulation.paused = _road_previous_pause


func _on_road_regenerate_requested(settings: Dictionary) -> void:
	if state == null or use_grid_world:
		road_tuning_panel.set_status(
			"网格测试地图不支持运行时路网调校。",
			true
		)
		return
	var result := state.recalculate_road_network(settings)
	if not bool(result.get("ok", false)):
		road_tuning_panel.set_status(
			str(result.get("error", "路网重算失败。")),
			true
		)
		return
	simulation.on_road_network_rebuilt()
	renderer.refresh_road_network()
	var protected_count := int(result.get("protected_count", 0))
	var protected_text := (
		"，%d 条在用道路保持原容量" % protected_count
		if protected_count > 0
		else ""
	)
	road_tuning_panel.set_status(
		"已生成：%d 条通路，%d 条封闭，平均容量 %d%s。"
		% [
			int(result["open_count"]),
			int(result["blocked_count"]),
			int(result["average_capacity"]),
			protected_text,
		]
	)


func _on_province_strength_changed(strength: float) -> void:
	if renderer != null:
		renderer.set_province_strength(strength)
	if map_3d != null:
		map_3d.set_province_strength(strength)


func _setup_map_editor() -> void:
	map_editor_panel.panel_opened.connect(_on_map_editor_opened)
	map_editor_panel.panel_closed.connect(_on_map_editor_closed)
	map_editor_panel.regenerate_requested.connect(
		_on_map_regenerate_requested
	)
	map_editor_panel.save_requested.connect(_on_map_save_requested)
	map_editor_panel.load_requested.connect(_on_map_load_requested)
	map_editor_panel.city_changes_requested.connect(
		_on_city_changes_requested
	)
	map_editor_panel.edge_changes_requested.connect(
		_on_edge_changes_requested
	)


func _on_map_editor_opened() -> void:
	if settings_overlay.visible:
		_close_settings()
	if road_tuning_panel != null and road_tuning_panel.is_open():
		road_tuning_panel.close_panel()
	_editor_previous_pause = simulation.paused
	simulation.paused = true


func _on_map_editor_closed() -> void:
	simulation.paused = _editor_previous_pause


func _on_map_regenerate_requested(
	city_count: int,
	city_mask_path: String
) -> void:
	var requested_count := clampi(city_count, nation_count, 500)
	var requested_mask := city_mask_path.strip_edges()
	var validation := TerrainMapGenerator.validate_city_mask(
		GameState.terrain_map_path(), requested_mask, requested_count
	)
	if not bool(validation.get("ok", false)):
		map_editor_panel.set_status(
			str(validation.get("error", "城市蒙版无效。")), true
		)
		return
	terrain_city_count = requested_count
	_city_generation_mask_path = requested_mask
	_start_new_game(_seed)
	map_editor_panel.set_status(
		"已按 %d 座城市重新生成；%s。" % [
			terrain_city_count,
			"仅白色蒙版内真实陆地可生成"
				if not _city_generation_mask_path.is_empty()
				else "未启用城市蒙版，所有真实陆地可生成",
		]
	)


func _on_map_save_requested(file_name: String) -> void:
	var result := MapDefinition.save_state(state, file_name)
	map_editor_panel.set_status(
		str(result.get("path", result.get("error", "保存失败。"))),
		not bool(result.get("ok", false))
	)


func _on_map_load_requested(file_name: String) -> void:
	var result := MapDefinition.load_file(file_name)
	if not bool(result.get("ok", false)):
		map_editor_panel.set_status(str(result.get("error", "加载失败。")), true)
		return
	_start_from_map_definition(result["data"] as Dictionary)
	map_editor_panel.set_status(
		"已加载 %s；战局已按地图定义重置。" % str(result["path"])
	)


func _on_city_changes_requested(
	city_id: int,
	changes: Dictionary
) -> void:
	var result := state.apply_city_editor_changes(city_id, changes)
	if not bool(result.get("ok", false)):
		map_editor_panel.set_status(str(result.get("error", "编辑失败。")), true)
		return
	_rebuild_scenario_from_edited_map("城市 %d 属性已应用" % city_id)


func _on_edge_changes_requested(
	city_a: int,
	city_b: int,
	changes: Dictionary
) -> void:
	var result := state.apply_edge_editor_changes(city_a, city_b, changes)
	if not bool(result.get("ok", false)):
		map_editor_panel.set_status(str(result.get("error", "编辑失败。")), true)
		return
	_rebuild_scenario_from_edited_map(
		"道路 %d ↔ %d 属性已应用" % [city_a, city_b]
	)


func _rebuild_scenario_from_edited_map(message: String) -> void:
	var definition := MapDefinition.from_state(state)
	_start_from_map_definition(definition)
	map_editor_panel.set_status(message + "；战局已安全重置。")


func _start_new_game(world_seed: int) -> void:
	var next_state := GameState.new()
	if use_grid_world:
		next_state.generate_grid_world(world_seed)
	else:
		next_state.generate_world(
			world_seed,
			nation_count,
			terrain_city_count,
			_city_generation_mask_path
		)
	_activate_state(next_state)


func _start_from_map_definition(definition: Dictionary) -> void:
	var next_state := GameState.new()
	next_state.generate_from_map_definition(definition, _seed)
	nation_count = next_state.nations.size()
	terrain_city_count = next_state.land_cities().size()
	_city_generation_mask_path = next_state.city_generation_mask_path
	_activate_state(next_state)


func _activate_state(next_state: GameState) -> void:
	state = next_state
	simulation.setup(state)
	simulation.diplomacy_enabled = not use_grid_world
	simulation.set_speed_multiplier(_speed_mult)
	renderer.set_army_icon_scale(initial_army_icon_scale)
	renderer.set_city_names_visible(initial_city_names_visible)
	renderer.setup(state, simulation)
	if road_tuning_panel != null:
		renderer.set_province_strength(
			road_tuning_panel.province_strength()
		)
	var enable_3d := (
		use_3d_map
		and not use_grid_world
		and map_3d != null
	)
	renderer.set_world_layer_visible(not enable_3d)
	if enable_3d:
		map_3d.visible = true
		map_3d.setup(state, simulation, renderer)
		if road_tuning_panel != null:
			map_3d.set_province_strength(
				road_tuning_panel.province_strength()
			)
	elif map_3d != null:
		map_3d.visible = false
	if map_editor_panel != null:
		map_editor_panel.bind(state, renderer)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE and settings_overlay.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE:
			simulation.paused = not simulation.paused
		KEY_EQUAL, KEY_KP_ADD, KEY_BRACKETRIGHT:
			_speed_mult = clampf(_speed_mult * 2.0, Simulation.SPEED_MIN, Simulation.SPEED_MAX)
			simulation.set_speed_multiplier(_speed_mult)
		KEY_MINUS, KEY_KP_SUBTRACT, KEY_BRACKETLEFT:
			_speed_mult = clampf(_speed_mult * 0.5, Simulation.SPEED_MIN, Simulation.SPEED_MAX)
			simulation.set_speed_multiplier(_speed_mult)
		KEY_R:
			_seed = randi()
			_start_new_game(_seed)
