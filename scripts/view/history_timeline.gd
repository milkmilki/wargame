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


func _ready() -> void:
	layer = 18
	_build_controls()


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
	_slider.custom_minimum_size = Vector2(430.0, 0.0)
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
