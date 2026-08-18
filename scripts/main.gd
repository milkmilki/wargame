extends Node
## 入口：装配 GameState / Simulation / Gaea 3D 地图 / HUD。

@export var use_grid_world: bool = false
@export var use_3d_map: bool = true
@export_range(1, GameState.TERRAIN_CITY_COUNT, 1) var nation_count: int = (
	GameState.NATION_COUNT
)
@export_range(1, 1000, 1) var terrain_city_count: int = (
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


func _ready() -> void:
	_setup_display_settings()
	if road_tuning_panel != null:
		_setup_road_tuning()
	_seed = world_seed
	_start_new_game(_seed)


func _setup_display_settings() -> void:
	var settings_font := MapRenderer.create_ui_font()
	_apply_settings_font(settings_button, settings_font)
	_apply_settings_font(settings_overlay, settings_font)
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
	if map_3d != null:
		map_3d.set_province_strength(strength)


func _start_new_game(world_seed: int) -> void:
	state = GameState.new()
	if use_grid_world:
		state.generate_grid_world(world_seed)
	else:
		state.generate_world(
			world_seed,
			nation_count,
			terrain_city_count
		)
	simulation.setup(state)
	simulation.diplomacy_enabled = not use_grid_world
	simulation.set_speed_multiplier(_speed_mult)
	renderer.set_army_icon_scale(initial_army_icon_scale)
	renderer.set_city_names_visible(initial_city_names_visible)
	renderer.setup(state, simulation)
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
