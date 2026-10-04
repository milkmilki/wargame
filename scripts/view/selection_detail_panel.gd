class_name SelectionDetailPanel
extends PanelContainer
## Receives a frozen display payload; never queries simulation state.

signal action_requested(action: String)
signal visibility_changed_by_fold
const BASE_WIDTH := 620.0

var scroll: ScrollContainer
var expanded := true
var dragging := false
var _title: Label
var _toggle: Button
var _title_panel: PanelContainer
var _title_style := StyleBoxFlat.new()
var _content: VBoxContainer
var _footer: HBoxContainer
var _sections: Dictionary = {}
var _preferences: Dictionary = {}
var _actions: Dictionary = {}
var _payload := {}
var _scale := 1.0
var _drag_offset := Vector2.ZERO
var _placed := false
var _layout_pending := false


func _init() -> void:
	name = "SelectionDetailPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_value := Theme.new()
	theme_value.default_font = MapRenderer.create_ui_font()
	theme_value.default_font_size = 13
	theme = theme_value
	var style := StyleBoxFlat.new()
	style.bg_color = MapRenderer.PAPER_LIGHT
	style.border_color = MapRenderer.INK_COLOR
	style.set_border_width_all(1)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	add_child(column)
	var title_row := HBoxContainer.new()
	_title_panel = PanelContainer.new()
	_title_style.set_content_margin_all(2)
	_title_panel.add_theme_stylebox_override("panel", _title_style)
	_title_panel.add_child(title_row)
	column.add_child(_title_panel)
	_toggle = Button.new()
	_toggle.custom_minimum_size = Vector2(26, 26)
	_toggle.text = "▼"
	_toggle.tooltip_text = "收起信息窗口"
	_toggle.pressed.connect(func() -> void: set_expanded(not expanded))
	title_row.add_child(_toggle)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.gui_input.connect(_on_title_input)
	_title.add_theme_color_override("font_color", MapRenderer.PAPER_LIGHT)
	title_row.add_child(_title)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 7)
	scroll.add_child(_content)
	_content.minimum_size_changed.connect(request_layout)
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_footer)


func present(payload: Dictionary, display_scale: float) -> void:
	visible = not (payload.get("sections", []) as Array).is_empty()
	if not visible:
		return
	if payload == _payload and is_equal_approx(display_scale, _scale):
		return
	var object_changed: bool = payload.get("selection", []) != _payload.get("selection", [])
	_payload = payload.duplicate(true)
	_scale = display_scale
	custom_minimum_size.x = minf(BASE_WIDTH * _scale, get_viewport_rect().size.x - 24 * _scale)
	size.x = custom_minimum_size.x
	theme.default_font_size = maxi(10, int(round(12 * _scale)))
	_title.text = str(payload.get("title", ""))
	_title.tooltip_text = _title.text
	_title_style.bg_color = payload.get("stripe_color", MapRenderer.COMMAND_GREEN)
	var keep := {}
	_actions.clear()
	var section_index := 0
	for data: Dictionary in payload.get("sections", []):
		var id := str(data["id"])
		keep[id] = true
		var group: DisclosureSection = _sections.get(id)
		if group == null:
			group = DisclosureSection.new()
			_sections[id] = group
			_content.add_child(group)
			group.set_expanded(bool(_preferences.get(id, data.get("default_expanded", false))))
			group.expanded_changed.connect(func(value: bool) -> void:
				_preferences[id] = value
				visibility_changed_by_fold.emit()
				request_layout()
			)
		group.set_title(str(data["title"]))
		if group.get_index() != section_index:
			_content.move_child(group, section_index)
		section_index += 1
		_update_rows(group, data)
	for id in _sections.keys():
		if not keep.has(id):
			var old: DisclosureSection = _sections[id]
			_content.remove_child(old)
			old.queue_free()
			_sections.erase(id)
	_update_footer(payload.get("actions", []))
	if object_changed:
		scroll.scroll_vertical = 0
	request_layout()


func _update_rows(group: DisclosureSection, data: Dictionary) -> void:
	var lines: Array = data.get("lines", [])
	var line_actions: Dictionary = data.get("line_actions", {})
	var signature := [lines.size(), line_actions]
	if group.get_meta("rows", []) != signature:
		for child in group.body.get_children():
			group.body.remove_child(child)
			child.queue_free()
		for index in range(lines.size()):
			var row: Control
			if line_actions.has(index):
				var action := str(line_actions[index])
				var button := Button.new()
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				button.pressed.connect(func() -> void: action_requested.emit(action))
				row = button
			else:
				var label := Label.new()
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				label.add_theme_color_override("font_color", MapRenderer.INK_COLOR)
				row = label
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			group.body.add_child(row)
		group.set_meta("rows", signature.duplicate(true))
	for index in range(lines.size()):
		var row := group.body.get_child(index)
		row.text = str(lines[index])
		if line_actions.has(index):
			_actions[str(line_actions[index])] = row


func _update_footer(actions: Array) -> void:
	if _footer.get_meta("actions", []) != actions:
		for child in _footer.get_children():
			_footer.remove_child(child)
			child.queue_free()
		for data: Dictionary in actions:
			var button := Button.new()
			button.text = str(data["title"])
			var action := str(data["id"])
			button.set_meta("action", action)
			button.pressed.connect(func() -> void: action_requested.emit(action))
			_footer.add_child(button)
		_footer.set_meta("actions", actions.duplicate(true))
	for button in _footer.get_children():
		_actions[str(button.get_meta("action"))] = button
	_footer.visible = expanded and not actions.is_empty()


func section(id: String) -> DisclosureSection:
	return _sections.get(id)


func section_expanded(id: String) -> bool:
	var group := section(id)
	return group.expanded if group != null else bool(_preferences.get(id, false))


func action_button(id: String) -> Button:
	return _actions.get(id)


func reset_war_preferences() -> void:
	for id in _preferences.keys():
		if str(id).begins_with("war."):
			_preferences.erase(id)
	_payload.clear()
	for group in _sections.values():
		_content.remove_child(group)
		group.queue_free()
	_sections.clear()
	_actions.clear()


func set_expanded(value: bool) -> void:
	expanded = value
	_toggle.text = "▼" if value else "▶"
	_toggle.tooltip_text = "收起信息窗口" if value else "展开信息窗口"
	scroll.visible = value
	_footer.visible = value and _footer.get_child_count() > 0
	visibility_changed_by_fold.emit()
	request_layout()


func request_layout() -> void:
	if _layout_pending or not is_inside_tree():
		return
	_layout_pending = true
	call_deferred("_layout")


func _layout() -> void:
	_layout_pending = false
	var viewport_size := get_viewport_rect().size
	var margin := 12 * _scale
	var top := 44 * _scale
	var bottom := 62 * _scale
	var available := maxf(60, viewport_size.y - top - bottom)
	var footer_height := _footer.get_combined_minimum_size().y + 5 if _footer.visible else 0.0
	scroll.custom_minimum_size.y = minf(_content.get_combined_minimum_size().y, available - 43 * _scale - footer_height)
	size = get_combined_minimum_size()
	if not _placed:
		position = Vector2(viewport_size.x - size.x - margin, viewport_size.y - size.y - bottom)
		_placed = true
	position = Vector2(clampf(position.x, margin, maxf(margin, viewport_size.x - size.x - margin)),
		clampf(position.y, top, maxf(top, viewport_size.y - size.y - bottom)))


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		_drag_offset = event.global_position - global_position
		_title.accept_event()


func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		position = event.position - _drag_offset
		_layout()
		get_viewport().set_input_as_handled()
