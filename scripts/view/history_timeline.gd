class_name HistoryTimeline
extends CanvasLayer
## 底部政治史时间轴。最后一格恒为实时状态。

signal position_requested(index: int)
signal preview_requested(index: int)

var _days := PackedInt32Array()
var _live_day: int = 0
var _selected_index: int = 0
var _updating: bool = false
var _panel: PanelContainer
var _date_label: Label
var _slider: HSlider
var _live_label: Label
var _debounce: Timer
var _settle: Timer
var _toggle: Button
var expanded := true


func _ready() -> void:
	layer = 18
	_build_controls()
	get_viewport().size_changed.connect(_layout_panel)


func set_history_points(days: PackedInt32Array, live_day: int) -> void:
	var was_live := _selected_index >= _days.size()
	_days = days.duplicate()
	_live_day = live_day
	_updating = true
	_slider.max_value = _days.size()
	if was_live or _days.is_empty():
		_selected_index = _days.size()
	else:
		_selected_index = clampi(_selected_index, 0, _days.size() - 1)
	_slider.value = _selected_index
	_updating = false
	_update_labels()


func select_live_without_signal() -> void:
	_selected_index = _days.size()
	_updating = true
	_slider.value = _selected_index
	_updating = false
	_update_labels()


func selected_index() -> int:
	return _selected_index


func _build_controls() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PoliticalHistoryTimeline"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.position = Vector2(-360.0, -48.0)
	_panel.size = Vector2(720.0, 38.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.095, 0.060, 0.97)
	style.border_color = MapRenderer.ACCENT_GOLD.darkened(0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)
	var font := MapRenderer.create_ui_font()
	_toggle = Button.new()
	_toggle.text = "▼"
	_toggle.tooltip_text = "收起历史时间轴"
	_toggle.add_theme_font_override("font", font)
	_toggle.pressed.connect(func() -> void: set_expanded(not expanded))
	row.add_child(_toggle)

	_date_label = Label.new()
	_date_label.custom_minimum_size = Vector2(122.0, 0.0)
	_date_label.add_theme_font_override("font", font)
	_date_label.add_theme_font_size_override("font_size", 11)
	_date_label.add_theme_color_override("font_color", MapRenderer.PAPER_LIGHT)
	row.add_child(_date_label)

	_slider = HSlider.new()
	_slider.name = "HistorySlider"
	_slider.min_value = 0.0
	_slider.max_value = 0.0
	_slider.step = 1.0
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.custom_minimum_size = Vector2(80.0, 0.0)
	_slider.tooltip_text = "查看历史政治版图；最右端返回当前时间"
	_slider.value_changed.connect(_on_value_changed)
	_slider.drag_ended.connect(_on_drag_ended)
	row.add_child(_slider)

	_live_label = Label.new()
	_live_label.custom_minimum_size = Vector2(92.0, 0.0)
	_live_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_live_label.add_theme_font_override("font", font)
	_live_label.add_theme_font_size_override("font_size", 11)
	_live_label.add_theme_color_override("font_color", MapRenderer.ACCENT_GOLD)
	row.add_child(_live_label)

	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.08
	_debounce.timeout.connect(_emit_preview_position)
	add_child(_debounce)
	_settle = Timer.new()
	_settle.one_shot = true
	_settle.wait_time = 0.30
	_settle.timeout.connect(_emit_final_position)
	add_child(_settle)
	_update_labels()
	_layout_panel()


func set_expanded(value: bool) -> void:
	if expanded == value:
		return
	if not value and (_debounce.time_left > 0.0 or _settle.time_left > 0.0):
		_emit_final_position()
	expanded = value
	_slider.visible = value
	_toggle.text = "▼" if value else "▶"
	_toggle.tooltip_text = "收起历史时间轴" if value else "展开历史时间轴"
	_layout_panel()


func _layout_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var available := maxf(260.0, viewport_size.x - 352.0 - 152.0)
	var width := minf(720.0 if expanded else 280.0, available)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(352.0 + (available - width) * 0.5, viewport_size.y - 48.0)
	_panel.size = Vector2(width, 38.0)


func _on_value_changed(value: float) -> void:
	_selected_index = clampi(int(round(value)), 0, _days.size())
	_update_labels()
	if _updating:
		return
	_debounce.start()
	_settle.start()


func _on_drag_ended(_value_changed: bool) -> void:
	if _debounce.time_left > 0.0:
		_debounce.stop()
	if _settle.time_left > 0.0:
		_settle.stop()
	_emit_final_position()


func _emit_preview_position() -> void:
	preview_requested.emit(_selected_index)


func _emit_final_position() -> void:
	if _debounce.time_left > 0.0:
		_debounce.stop()
	if _settle.time_left > 0.0:
		_settle.stop()
	position_requested.emit(_selected_index)


func _update_labels() -> void:
	var live := _selected_index >= _days.size()
	var day := _live_day if live else int(_days[_selected_index])
	_date_label.text = "当前时间" if live else "历史  第 %d 月" % (day / Simulation.DAYS_PER_MONTH)
	_live_label.text = "第 %d 日" % day
