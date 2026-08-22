class_name RoadTuningPanel
extends CanvasLayer
## Runtime road-network tuning UI. The panel owns presentation only; Main
## coordinates pause state and commits settings to GameState.

signal panel_opened
signal panel_closed
signal regenerate_requested(settings: Dictionary)
signal province_strength_changed(strength: float)
signal elevation_shadow_strength_changed(strength: float)
signal vertical_terrain_light_strength_changed(strength: float)
signal map_mode_changed(mode: int)

const PROVINCE_STRENGTH_KEY := "province_strength"
const PROVINCE_STRENGTH_DEFAULT: float = (
	MapRenderer.POLITICAL_MAP_DEFAULT_STRENGTH
)
const ELEVATION_SHADOW_STRENGTH_KEY := "elevation_shadow_strength"
const VERTICAL_TERRAIN_LIGHT_STRENGTH_KEY := (
	"vertical_terrain_light_strength"
)
const MAP_MODE_TERRAIN: String = "terrain"
const MAP_MODE_MIXED: String = "mixed"
const MAP_MODE_POLITICAL: String = "political"
const MAP_MODE_LOYALTY: String = "loyalty"
const MAP_MODE_TRADE: String = "trade"

var _overlay: Control
var _status: Label
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _map_mode_buttons: Dictionary = {}
var _map_mode: String = MAP_MODE_POLITICAL


func _ready() -> void:
	layer = 21
	_build_ui()
	set_process_unhandled_input(true)


func _build_ui() -> void:
	var open_button := Button.new()
	open_button.name = "RoadTuningButton"
	open_button.text = "调校"
	open_button.tooltip_text = "调整地图覆色、地形灯光和道路网络"
	open_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	open_button.position = Vector2(116.0, -38.0)
	open_button.size = Vector2(108.0, 30.0)
	open_button.pressed.connect(open_panel)
	add_child(open_button)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.03, 0.02, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-270.0, -280.0)
	panel.size = Vector2(540.0, 560.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.095, 0.085, 0.065, 0.98)
	panel_style.border_color = Color(0.62, 0.46, 0.19, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	var title := Label.new()
	title.text = "地图与路网调校"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)

	var hint := Label.new()
	hint.text = "地图与灯光即时生效；重新计算路网只改变陆路通行性与容量。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.78, 0.73, 0.62)
	content.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)

	var defaults := GameState.default_road_tuning()
	_add_slider(
		grid, "最低陆地率", "minimum_land_ratio",
		0.70, 1.0, 0.01, float(defaults["minimum_land_ratio"]), 2
	)
	_add_slider(
		grid, "最大高差", "maximum_relief",
		0.05, 1.0, 0.01, float(defaults["maximum_relief"]), 2
	)
	_add_slider(
		grid, "封闭支路", "blocked_branch_share",
		0.0, 0.45, 0.01, float(defaults["blocked_branch_share"]), 0, true
	)
	_add_slider(
		grid, "地形容量衰减", "terrain_capacity_penalty",
		0.0, 0.90, 0.01, float(defaults["terrain_capacity_penalty"]), 0, true
	)
	_add_slider(
		grid, "容量倍率", "capacity_multiplier",
		0.25, 3.0, 0.05, float(defaults["capacity_multiplier"]), 2
	)
	_add_slider(
		grid, "国家覆色", PROVINCE_STRENGTH_KEY,
		0.0, 1.0, 0.01, PROVINCE_STRENGTH_DEFAULT, 0, true
	)
	_add_slider(
		grid, "地形顶光", VERTICAL_TERRAIN_LIGHT_STRENGTH_KEY,
		0.0, 1.0, 0.01,
		StrategicMap3D.VERTICAL_TERRAIN_LIGHT_DEFAULT_STRENGTH, 0, true
	)
	_add_slider(
		grid, "地形塑形光", ELEVATION_SHADOW_STRENGTH_KEY,
		0.0, 1.0, 0.01,
		StrategicMap3D.SCULPT_TERRAIN_LIGHT_DEFAULT_STRENGTH, 0, true
	)
	var legend := HBoxContainer.new()
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 10)
	content.add_child(legend)
	var legend_title := Label.new()
	legend_title.text = "道路等级"
	legend.add_child(legend_title)
	for item in [
		["支路 1万", Color(0.30, 0.23, 0.15)],
		["干道 2万", Color(0.60, 0.43, 0.22)],
		["水路 5万", Color(0.20, 0.49, 0.55)],
	]:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(28.0, 6.0)
		swatch.color = item[1]
		legend.add_child(swatch)
		var item_label := Label.new()
		item_label.text = str(item[0])
		legend.add_child(item_label)

	_status = Label.new()
	_status.text = "打开面板后游戏暂停；正在使用的道路保持当前容量。"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 44.0
	_status.modulate = Color(0.78, 0.73, 0.62)
	content.add_child(_status)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(92.0, 36.0)
	close_button.pressed.connect(close_panel)
	_apply_command_button_style(close_button)
	actions.add_child(close_button)
	var rebuild_button := Button.new()
	rebuild_button.text = "重新计算路网"
	rebuild_button.custom_minimum_size = Vector2(148.0, 36.0)
	rebuild_button.pressed.connect(func() -> void:
		regenerate_requested.emit(road_settings())
	)
	_apply_command_button_style(rebuild_button, true)
	actions.add_child(rebuild_button)

	var font := MapRenderer.create_ui_font()
	_apply_font(open_button, font)
	_apply_command_button_style(open_button)
	_apply_font(_overlay, font)
	_build_map_mode_control(font)


func _build_map_mode_control(font: Font) -> void:
	var modes := HBoxContainer.new()
	modes.name = "MapModes"
	modes.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	modes.position = Vector2(-402.0, -38.0)
	modes.size = Vector2(390.0, 30.0)
	modes.add_theme_constant_override("separation", 4)
	add_child(modes)
	var group := ButtonGroup.new()
	for mode in [
		[MAP_MODE_TERRAIN, "地形"],
		[MAP_MODE_MIXED, "混合"],
		[MAP_MODE_POLITICAL, "政治"],
		[MAP_MODE_LOYALTY, "忠诚"],
		[MAP_MODE_TRADE, "贸易"],
	]:
		var button := Button.new()
		var mode_id := str(mode[0])
		button.text = str(mode[1])
		button.tooltip_text = "切换%s地图模式" % mode[1]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(74.0, 30.0)
		button.set_meta(&"map_mode", mode_id)
		button.set_meta(&"renderer_map_mode", _renderer_map_mode(mode_id))
		button.pressed.connect(_on_map_mode_pressed.bind(mode_id))
		_apply_command_button_style(button, true)
		modes.add_child(button)
		_map_mode_buttons[mode_id] = button
	_apply_font(modes, font)
	_sync_map_mode_buttons()


func _on_map_mode_pressed(mode: String) -> void:
	set_map_mode(mode)


func set_map_mode(mode: String) -> void:
	if not _map_mode_buttons.has(mode):
		return
	_map_mode = mode
	(_sliders[PROVINCE_STRENGTH_KEY] as HSlider).value = (
		_map_mode_strength(mode)
	)
	_sync_map_mode_buttons()
	map_mode_changed.emit(_renderer_map_mode(mode))


func map_mode() -> String:
	return _map_mode


func renderer_map_mode() -> int:
	return _renderer_map_mode(_map_mode)


static func _map_mode_strength(mode: String) -> float:
	match mode:
		MAP_MODE_TERRAIN:
			return 0.0
		MAP_MODE_MIXED:
			return 0.42
	return PROVINCE_STRENGTH_DEFAULT


static func _renderer_map_mode(mode: String) -> int:
	match mode:
		MAP_MODE_LOYALTY:
			return MapRenderer.MAP_MODE_LOYALTY
		MAP_MODE_TRADE:
			return MapRenderer.MAP_MODE_TRADE
	return MapRenderer.MAP_MODE_POLITICAL


func _add_slider(
	grid: GridContainer,
	label_text: String,
	key: String,
	minimum: float,
	maximum: float,
	step: float,
	initial: float,
	decimals: int,
	as_percent: bool = false
) -> void:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 124.0
	grid.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(270.0, 28.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 66.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value_label)
	_sliders[key] = slider
	_value_labels[key] = value_label
	slider.value_changed.connect(func(value: float) -> void:
		_update_value_label(key, value, decimals, as_percent)
		if key == PROVINCE_STRENGTH_KEY:
			if _map_mode in [
				MAP_MODE_TERRAIN, MAP_MODE_MIXED, MAP_MODE_POLITICAL,
			]:
				_map_mode = _base_map_mode_for_strength(value)
				_sync_map_mode_buttons()
			province_strength_changed.emit(value)
		elif key == ELEVATION_SHADOW_STRENGTH_KEY:
			elevation_shadow_strength_changed.emit(value)
		elif key == VERTICAL_TERRAIN_LIGHT_STRENGTH_KEY:
			vertical_terrain_light_strength_changed.emit(value)
	)
	_update_value_label(key, initial, decimals, as_percent)


func _update_value_label(
	key: String,
	value: float,
	decimals: int,
	as_percent: bool
) -> void:
	var label := _value_labels[key] as Label
	if as_percent:
		label.text = "%d%%" % int(round(value * 100.0))
	else:
		label.text = ("%." + str(decimals) + "f") % value


func _sync_map_mode_buttons() -> void:
	if _map_mode_buttons.is_empty():
		return
	for key in _map_mode_buttons:
		(_map_mode_buttons[key] as Button).set_pressed_no_signal(
			str(key) == _map_mode
		)


static func _base_map_mode_for_strength(strength: float) -> String:
	var best_mode := MAP_MODE_TERRAIN
	var best_distance := INF
	for candidate in [
		[MAP_MODE_TERRAIN, 0.0],
		[MAP_MODE_MIXED, 0.42],
		[MAP_MODE_POLITICAL, PROVINCE_STRENGTH_DEFAULT],
	]:
		var distance := absf(strength - float(candidate[1]))
		if distance < best_distance:
			best_mode = str(candidate[0])
			best_distance = distance
	return best_mode


func _apply_font(control: Control, font: Font) -> void:
	control.add_theme_font_override("font", font)
	for child in control.get_children():
		if child is Control:
			_apply_font(child as Control, font)


func _apply_command_button_style(
	button: Button,
	show_selected: bool = false
) -> void:
	button.add_theme_color_override(
		"font_color", MapRenderer.PAPER_LIGHT
	)
	button.add_theme_color_override(
		"font_hover_color", Color.WHITE
	)
	button.add_theme_color_override(
		"font_pressed_color", MapRenderer.PAPER_LIGHT
	)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.075, 0.095, 0.060, 0.97)
	normal.border_color = MapRenderer.ACCENT_GOLD.darkened(0.42)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.16, 0.095, 0.98)
	hover.border_color = MapRenderer.ACCENT_GOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = (
		MapRenderer.ACCENT_GOLD.darkened(0.55)
		if show_selected
		else Color(0.10, 0.13, 0.075, 0.98)
	)
	pressed.border_color = MapRenderer.PAPER_LIGHT
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)


func road_settings() -> Dictionary:
	return {
		"minimum_land_ratio": _slider_value("minimum_land_ratio"),
		"maximum_relief": _slider_value("maximum_relief"),
		"blocked_branch_share": _slider_value("blocked_branch_share"),
		"terrain_capacity_penalty": _slider_value(
			"terrain_capacity_penalty"
		),
		"capacity_multiplier": _slider_value("capacity_multiplier"),
	}


func province_strength() -> float:
	return _slider_value(PROVINCE_STRENGTH_KEY)


func elevation_shadow_strength() -> float:
	return _slider_value(ELEVATION_SHADOW_STRENGTH_KEY)


func vertical_terrain_light_strength() -> float:
	return _slider_value(VERTICAL_TERRAIN_LIGHT_STRENGTH_KEY)


func _slider_value(key: String) -> float:
	return float((_sliders[key] as HSlider).value)


func open_panel() -> void:
	if _overlay.visible:
		return
	_overlay.visible = true
	panel_opened.emit()


func close_panel() -> void:
	if not _overlay.visible:
		return
	_overlay.visible = false
	panel_closed.emit()


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.modulate = (
		Color(0.92, 0.36, 0.26)
		if is_error
		else Color(0.74, 0.82, 0.61)
	)


func _unhandled_input(event: InputEvent) -> void:
	if (
		_overlay.visible
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		close_panel()
		get_viewport().set_input_as_handled()
