class_name MapEditorPanel
extends CanvasLayer
## Runtime map authoring UI. Selection remains owned by MapRenderer; this panel
## exposes a constrained editor and delegates state changes to Main.

signal panel_opened
signal panel_closed
signal regenerate_requested(city_count: int, city_mask_path: String)
signal save_requested(file_name: String)
signal load_requested(file_name: String)
signal city_changes_requested(city_id: int, changes: Dictionary)
signal edge_changes_requested(city_a: int, city_b: int, changes: Dictionary)

var _overlay: Control
var _dock_panel: PanelContainer
var _status: Label
var _city_count: SpinBox
var _city_mask_path: LineEdit
var _mask_file_dialog: FileDialog
var _file_name: LineEdit
var _selection_title: Label
var _city_form: VBoxContainer
var _edge_form: VBoxContainer
var _city_fields: Dictionary = {}
var _edge_fields: Dictionary = {}
var _state: GameState
var _renderer: MapRenderer
var _last_city_id: int = -2
var _last_edge := Vector2i(-2, -2)


func _ready() -> void:
	layer = 22
	_build_ui()
	set_process(true)


func bind(game_state: GameState, renderer: MapRenderer) -> void:
	_state = game_state
	_renderer = renderer
	_last_city_id = -2
	_last_edge = Vector2i(-2, -2)
	if _city_count != null:
		_city_count.value = game_state.land_cities().size()
	if _city_mask_path != null:
		_city_mask_path.text = game_state.city_generation_mask_path
	_refresh_selection_form()


func _process(_delta: float) -> void:
	if not is_open() or _renderer == null:
		return
	var city_id := _renderer.selected_city_id()
	var edge_pair := _renderer.selected_edge_pair()
	if city_id != _last_city_id or edge_pair != _last_edge:
		_refresh_selection_form()


func _build_ui() -> void:
	var open_button := Button.new()
	open_button.name = "MapEditorButton"
	open_button.text = "地图编辑"
	open_button.tooltip_text = "重新生成、编辑并保存地图定义"
	open_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	open_button.position = Vector2(232.0, -38.0)
	open_button.size = Vector2(116.0, 30.0)
	open_button.pressed.connect(open_panel)
	add_child(open_button)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	add_child(_overlay)

	var panel := PanelContainer.new()
	panel.name = "EditorDock"
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.position = Vector2(-530.0, -325.0)
	panel.size = Vector2(520.0, 650.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.075, 0.068, 0.052, 0.99)
	panel_style.border_color = MapRenderer.ACCENT_GOLD.darkened(0.10)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(panel)
	_dock_panel = panel
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var title := Label.new()
	title.text = "运行时地图编辑器"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)

	var generation := HBoxContainer.new()
	generation.add_theme_constant_override("separation", 10)
	content.add_child(generation)
	generation.add_child(_label("陆地城市数量", 100.0))
	_city_count = SpinBox.new()
	_city_count.min_value = 16
	_city_count.max_value = 500
	_city_count.step = 1
	_city_count.value = GameState.TERRAIN_CITY_COUNT
	_city_count.custom_minimum_size = Vector2(82.0, 32.0)
	generation.add_child(_city_count)
	var regenerate := Button.new()
	regenerate.text = "重新生成城市、省份与路网"
	regenerate.custom_minimum_size = Vector2(210.0, 32.0)
	regenerate.pressed.connect(func() -> void:
		regenerate_requested.emit(
			int(_city_count.value), _city_mask_path.text
		)
	)
	_style_button(regenerate, true)
	generation.add_child(regenerate)
	var generation_hint := Label.new()
	generation_hint.text = "完整矩形高程范围；负海拔为海洋，城市只采样陆地区域。支持16～500城，重新生成会重置当前战局。"
	generation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	generation_hint.modulate = Color(0.78, 0.73, 0.62)
	content.add_child(generation_hint)
	var mask_row := HBoxContainer.new()
	mask_row.add_theme_constant_override("separation", 8)
	content.add_child(mask_row)
	mask_row.add_child(_label("城市蒙版", 82.0))
	_city_mask_path = LineEdit.new()
	_city_mask_path.placeholder_text = "黑白图片路径；白色允许，黑色禁止"
	_city_mask_path.custom_minimum_size = Vector2(250.0, 32.0)
	mask_row.add_child(_city_mask_path)
	var browse_mask := Button.new()
	browse_mask.text = "浏览"
	browse_mask.pressed.connect(func() -> void:
		_mask_file_dialog.popup_centered_ratio(0.72)
	)
	_style_button(browse_mask)
	mask_row.add_child(browse_mask)
	var clear_mask := Button.new()
	clear_mask.text = "清除"
	clear_mask.tooltip_text = "清除后重新生成将允许所有真实陆地"
	clear_mask.pressed.connect(func() -> void:
		_city_mask_path.text = ""
		set_status("已清除城市蒙版配置；点击重新生成后生效。")
	)
	_style_button(clear_mask)
	mask_row.add_child(clear_mask)
	_mask_file_dialog = FileDialog.new()
	_mask_file_dialog.title = "选择黑白城市生成蒙版"
	_mask_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_mask_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_mask_file_dialog.filters = PackedStringArray([
		"*.png,*.jpg,*.jpeg,*.webp ; 图片文件"
	])
	_mask_file_dialog.file_selected.connect(func(path: String) -> void:
		_city_mask_path.text = path
		set_status("已选择蒙版；点击重新生成以应用。")
	)
	add_child(_mask_file_dialog)
	content.add_child(HSeparator.new())

	_selection_title = Label.new()
	_selection_title.text = "选择一座城市或一条道路以编辑属性"
	_selection_title.add_theme_font_size_override("font_size", 17)
	content.add_child(_selection_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 310.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var form_host := VBoxContainer.new()
	form_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form_host)
	_city_form = VBoxContainer.new()
	_city_form.add_theme_constant_override("separation", 7)
	form_host.add_child(_city_form)
	_build_city_form()
	_edge_form = VBoxContainer.new()
	_edge_form.add_theme_constant_override("separation", 7)
	form_host.add_child(_edge_form)
	_build_edge_form()

	content.add_child(HSeparator.new())
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 8)
	content.add_child(file_row)
	_file_name = LineEdit.new()
	_file_name.text = "custom_map.json"
	_file_name.placeholder_text = "地图文件名"
	_file_name.custom_minimum_size = Vector2(190.0, 34.0)
	file_row.add_child(_file_name)
	var save_button := Button.new()
	save_button.text = "保存地图"
	save_button.pressed.connect(func() -> void:
		save_requested.emit(_file_name.text)
	)
	_style_button(save_button)
	file_row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "加载地图"
	load_button.pressed.connect(func() -> void:
		load_requested.emit(_file_name.text)
	)
	_style_button(load_button)
	file_row.add_child(load_button)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(close_panel)
	_style_button(close_button)
	file_row.add_child(close_button)
	_status = Label.new()
	_status.text = "地图文件保存在 user://maps/；不包含进行中的战争和军队状态。"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.74, 0.82, 0.61)
	content.add_child(_status)
	var font := MapRenderer.create_ui_font()
	_apply_font(open_button, font)
	_apply_font(_overlay, font)
	_style_button(open_button)


func _build_city_form() -> void:
	_city_fields["map_x"] = _spin_field(_city_form, "地图 X", 0, 1, 0.001)
	_city_fields["map_y"] = _spin_field(_city_form, "地图 Y", 0, 1, 0.001)
	_city_fields["owner_nation"] = _spin_field(_city_form, "所属国家", 0, 999, 1)
	_city_fields["fort_strength"] = _spin_field(_city_form, "当前工事", 0, 100, 1)
	_city_fields["fort_strength_max"] = _spin_field(_city_form, "最大工事", 0, 100, 1)
	_city_fields["manpower_per_month"] = _spin_field(_city_form, "每月人力", 0, 10000, 1)
	_city_fields["gold_per_month"] = _spin_field(_city_form, "每月金钱", 0, 10000, 1)
	_city_fields["food_per_half_year"] = _spin_field(_city_form, "半年粮食", 0, 1000000, 1)
	_city_fields["food_storage"] = _spin_field(_city_form, "粮食库存", 0, 100000000, 1)
	_city_fields["terrain_height"] = _spin_field(_city_form, "地形高度", 0, 1, 0.01)
	_city_fields["terrain_relief"] = _spin_field(_city_form, "地形起伏", 0, 1, 0.01)
	_city_fields["terrain_output_multiplier"] = _spin_field(_city_form, "海拔产出倍率", 0, 4, 0.05)
	_city_fields["development_gold_multiplier"] = _spin_field(_city_form, "金钱发展倍率", 0, 10, 0.05)
	_city_fields["development_food_multiplier"] = _spin_field(_city_form, "粮食发展倍率", 0, 10, 0.05)
	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 14)
	_city_form.add_child(flags)
	for key_and_label in [
		["is_food_hub", "粮食核心"],
		["is_manpower_hub", "人口核心"],
		["is_plain_city", "平原"],
		["is_port_market", "港市"],
		["is_crossroads", "枢纽"],
	]:
		var check := CheckBox.new()
		check.text = str(key_and_label[1])
		flags.add_child(check)
		_city_fields[str(key_and_label[0])] = check
	var apply := Button.new()
	apply.text = "应用城市属性"
	apply.pressed.connect(_emit_city_changes)
	_style_button(apply, true)
	_city_form.add_child(apply)


func _build_edge_form() -> void:
	var kind_row := HBoxContainer.new()
	kind_row.add_child(_label("道路类型", 120.0))
	var kind := OptionButton.new()
	kind.add_item("陆路", Edge.Kind.LAND)
	kind.add_item("抢滩", Edge.Kind.LANDING)
	kind.add_item("水路", Edge.Kind.RIVER)
	kind.add_item("海路", Edge.Kind.SEA)
	kind.custom_minimum_size = Vector2(180.0, 30.0)
	kind_row.add_child(kind)
	_edge_form.add_child(kind_row)
	_edge_fields["kind"] = kind
	var capacity_row := HBoxContainer.new()
	capacity_row.add_child(_label("容量", 120.0))
	var capacity := OptionButton.new()
	for value in [0, 10000, 20000, 50000]:
		capacity.add_item("%d" % value, value)
	capacity.custom_minimum_size = Vector2(180.0, 30.0)
	capacity_row.add_child(capacity)
	_edge_form.add_child(capacity_row)
	_edge_fields["max_manpower"] = capacity
	_edge_fields["distance"] = _spin_field(_edge_form, "距离", 1, 100, 1)
	_edge_fields["danger"] = _spin_field(_edge_form, "危险度", 0, 1, 0.01)
	_edge_fields["travel_time_multiplier"] = _spin_field(_edge_form, "行军倍率", 0.05, 10, 0.05)
	_edge_fields["supply_loss_multiplier"] = _spin_field(_edge_form, "粮损倍率", 0, 10, 0.05)
	_edge_fields["max_height_difference"] = _spin_field(_edge_form, "沿线最大高差", 0, 1, 0.01)
	_edge_fields["land_ratio"] = _spin_field(_edge_form, "沿线陆地率", 0, 1, 0.01)
	var holding := CheckBox.new()
	holding.text = "允许驻边"
	_edge_form.add_child(holding)
	_edge_fields["allows_holding"] = holding
	var backbone := CheckBox.new()
	backbone.text = "连通骨架"
	_edge_form.add_child(backbone)
	_edge_fields["is_backbone"] = backbone
	var apply := Button.new()
	apply.text = "应用道路属性"
	apply.pressed.connect(_emit_edge_changes)
	_style_button(apply, true)
	_edge_form.add_child(apply)


func _spin_field(
	parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float
) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	row.add_child(_label(label_text, 120.0))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.custom_minimum_size = Vector2(180.0, 30.0)
	row.add_child(spin)
	return spin


func _label(text_value: String, width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text_value
	if width > 0.0:
		label.custom_minimum_size.x = width
	return label


func _refresh_selection_form() -> void:
	if _state == null or _renderer == null:
		return
	_last_city_id = _renderer.selected_city_id()
	_last_edge = _renderer.selected_edge_pair()
	_city_form.visible = false
	_edge_form.visible = false
	if _last_city_id >= 0 and _last_city_id < _state.cities.size():
		var city := _state.cities[_last_city_id]
		_selection_title.text = "编辑城市 %d%s" % [city.id, "（码头）" if city.is_dock else ""]
		(_city_fields["owner_nation"] as SpinBox).max_value = _state.nations.size() - 1
		_set_spin(_city_fields, "map_x", city.map_position.x)
		_set_spin(_city_fields, "map_y", city.map_position.y)
		_set_spin(_city_fields, "owner_nation", city.owner_nation)
		_set_spin(_city_fields, "fort_strength", city.fort_strength)
		_set_spin(_city_fields, "fort_strength_max", city.fort_strength_max)
		_set_spin(_city_fields, "manpower_per_month", city.manpower_per_month)
		_set_spin(_city_fields, "gold_per_month", city.gold_per_month)
		_set_spin(_city_fields, "food_per_half_year", city.food_per_half_year)
		_set_spin(_city_fields, "food_storage", city.food_storage)
		_set_spin(_city_fields, "terrain_height", city.terrain_height)
		_set_spin(_city_fields, "terrain_relief", city.terrain_relief)
		_set_spin(_city_fields, "terrain_output_multiplier", city.terrain_output_multiplier)
		_set_spin(_city_fields, "development_gold_multiplier", city.development_gold_multiplier)
		_set_spin(_city_fields, "development_food_multiplier", city.development_food_multiplier)
		for key in ["is_food_hub", "is_manpower_hub", "is_plain_city", "is_port_market", "is_crossroads"]:
			(_city_fields[key] as CheckBox).button_pressed = bool(city.get(key))
		_city_form.visible = true
		return
	if _last_edge.x >= 0 and _last_edge.y >= 0:
		var edge := _state.edge_of(_last_edge.x, _last_edge.y)
		if edge != null:
			_selection_title.text = "编辑道路 %d ↔ %d" % [edge.city_a, edge.city_b]
			(_edge_fields["kind"] as OptionButton).select(edge.kind)
			_select_metadata(_edge_fields["max_manpower"] as OptionButton, edge.max_manpower)
			_set_spin(_edge_fields, "distance", edge.distance)
			_set_spin(_edge_fields, "danger", edge.danger)
			_set_spin(_edge_fields, "travel_time_multiplier", edge.travel_time_multiplier)
			_set_spin(_edge_fields, "supply_loss_multiplier", edge.supply_loss_multiplier)
			_set_spin(_edge_fields, "max_height_difference", edge.max_height_difference)
			_set_spin(_edge_fields, "land_ratio", edge.land_ratio)
			(_edge_fields["allows_holding"] as CheckBox).button_pressed = edge.allows_holding
			(_edge_fields["is_backbone"] as CheckBox).button_pressed = edge.is_backbone
			_edge_form.visible = true
			return
	_selection_title.text = "选择一座城市或一条道路以编辑属性"


func _set_spin(fields: Dictionary, key: String, value: float) -> void:
	(fields[key] as SpinBox).value = value


func _select_metadata(option: OptionButton, value: int) -> void:
	for index in range(option.item_count):
		if int(option.get_item_id(index)) == value:
			option.select(index)
			return


func _emit_city_changes() -> void:
	if _last_city_id < 0:
		return
	var changes := {}
	for key in ["owner_nation", "fort_strength", "fort_strength_max", "manpower_per_month", "gold_per_month", "food_per_half_year", "food_storage"]:
		changes[key] = int((_city_fields[key] as SpinBox).value)
	for key in ["map_x", "map_y", "terrain_height", "terrain_relief", "terrain_output_multiplier", "development_gold_multiplier", "development_food_multiplier"]:
		changes[key] = (_city_fields[key] as SpinBox).value
	for key in ["is_food_hub", "is_manpower_hub", "is_plain_city", "is_port_market", "is_crossroads"]:
		changes[key] = (_city_fields[key] as CheckBox).button_pressed
	city_changes_requested.emit(_last_city_id, changes)


func _emit_edge_changes() -> void:
	if _last_edge.x < 0 or _last_edge.y < 0:
		return
	var kind := _edge_fields["kind"] as OptionButton
	var capacity := _edge_fields["max_manpower"] as OptionButton
	edge_changes_requested.emit(_last_edge.x, _last_edge.y, {
		"kind": kind.get_selected_id(),
		"max_manpower": capacity.get_selected_id(),
		"distance": int((_edge_fields["distance"] as SpinBox).value),
		"danger": (_edge_fields["danger"] as SpinBox).value,
		"travel_time_multiplier": (_edge_fields["travel_time_multiplier"] as SpinBox).value,
		"supply_loss_multiplier": (_edge_fields["supply_loss_multiplier"] as SpinBox).value,
		"max_height_difference": (_edge_fields["max_height_difference"] as SpinBox).value,
		"land_ratio": (_edge_fields["land_ratio"] as SpinBox).value,
		"allows_holding": (_edge_fields["allows_holding"] as CheckBox).button_pressed,
		"is_backbone": (_edge_fields["is_backbone"] as CheckBox).button_pressed,
	})


func open_panel() -> void:
	if is_open():
		return
	_overlay.visible = true
	_refresh_selection_form()
	panel_opened.emit()


func close_panel() -> void:
	if not is_open():
		return
	_overlay.visible = false
	panel_closed.emit()


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func set_status(text: String, is_error: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(0.92, 0.36, 0.26) if is_error else Color(0.74, 0.82, 0.61)


func _apply_font(control: Control, font: Font) -> void:
	control.add_theme_font_override("font", font)
	for child in control.get_children():
		if child is Control:
			_apply_font(child as Control, font)


func _style_button(button: Button, selected: bool = false) -> void:
	button.add_theme_color_override("font_color", MapRenderer.PAPER_LIGHT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.075, 0.095, 0.060, 0.97)
	normal.border_color = MapRenderer.ACCENT_GOLD.darkened(0.38)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.16, 0.095, 0.98)
	hover.border_color = MapRenderer.ACCENT_GOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = MapRenderer.ACCENT_GOLD.darkened(0.55) if selected else normal.bg_color
	pressed.border_color = MapRenderer.PAPER_LIGHT
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
