class_name FamilyTreePanel
extends CanvasLayer
## 国家家族树遮罩页。树本身只读，数据真源位于 GameState.family_trees。

signal panel_opened
signal panel_closed

const CARD_SIZE := Vector2(180.0, 68.0)
const CARD_GAP_X: float = 28.0
const LEVEL_GAP_Y: float = 58.0
const CANVAS_PADDING := Vector2(36.0, 30.0)

var _state: GameState
var _nation_id: int = -1
var _overlay: Control
var _title: Label
var _tree_canvas: Control


func _ready() -> void:
	layer = 30
	_build_ui()
	close_panel()


func bind(state: GameState) -> void:
	_state = state
	if _overlay != null and _overlay.visible:
		close_panel()


func open_for_nation(nation_id: int) -> bool:
	if _state == null or nation_id < 0 or nation_id >= _state.nations.size():
		return false
	FamilyTree.ensure_nation_lineage(_state, nation_id)
	_nation_id = nation_id
	_title.text = "%s家族树" % WorldNaming.nation_display_name(
		_state, nation_id
	)
	_tree_canvas.set("tree", FamilyTree.tree_for_nation(_state, nation_id))
	_tree_canvas.set("current_person_id", _state.nations[nation_id].ruler_person_id)
	_tree_canvas.call("rebuild_layout")
	var was_open := _overlay.visible
	_overlay.visible = true
	if not was_open:
		panel_opened.emit()
	(_overlay.get_node("Frame/Content/Header/Close") as Button).grab_focus()
	return true


func close_panel() -> void:
	_nation_id = -1
	if _overlay != null:
		var was_open := _overlay.visible
		_overlay.visible = false
		if was_open:
			panel_closed.emit()


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func _unhandled_input(event: InputEvent) -> void:
	if (
		is_open()
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
	):
		close_panel()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var font := MapRenderer.create_ui_font()
	_overlay = Control.new()
	_overlay.name = "FamilyTreeOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.color = Color(0.025, 0.02, 0.014, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)

	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.anchor_left = 0.06
	frame.anchor_top = 0.07
	frame.anchor_right = 0.94
	frame.anchor_bottom = 0.93
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.86, 0.76, 0.57, 1.0)
	frame_style.border_color = MapRenderer.INK_COLOR
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", frame_style)
	_overlay.add_child(frame)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 0)
	frame.add_child(content)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size.y = 48.0
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)

	_title = Label.new()
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", font)
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", MapRenderer.PAPER_LIGHT)
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = MapRenderer.COMMAND_GREEN
	title_style.content_margin_left = 18.0
	_title.add_theme_stylebox_override("normal", title_style)
	header.add_child(_title)

	var close := Button.new()
	close.name = "Close"
	close.text = "×"
	close.tooltip_text = "关闭家族树"
	close.custom_minimum_size = Vector2(48.0, 48.0)
	close.add_theme_font_override("font", font)
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(close_panel)
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.name = "TreeScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content.add_child(scroll)

	_tree_canvas = FamilyTreeCanvas.new()
	_tree_canvas.name = "TreeCanvas"
	_tree_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_canvas.set("font", font)
	scroll.add_child(_tree_canvas)


class FamilyTreeCanvas extends Control:
	var tree: Dictionary = {}
	var current_person_id: int = -1
	var font: Font
	var _rect_by_person: Dictionary = {}


	func _ready() -> void:
		resized.connect(rebuild_layout)


	func rebuild_layout() -> void:
		_rect_by_person.clear()
		var members: Dictionary = tree.get("members", {})
		if members.is_empty():
			custom_minimum_size = Vector2(520.0, 260.0)
			queue_redraw()
			return
		var root_id := int(tree.get("root_person_id", -1))
		var levels: Dictionary = {}
		var maximum_depth := 0
		for person_value in members.keys():
			var person_id := int(person_value)
			var depth := _depth_of(person_id, root_id, members)
			maximum_depth = maxi(maximum_depth, depth)
			if not levels.has(depth):
				levels[depth] = [] as Array[int]
			(levels[depth] as Array[int]).append(person_id)
		var maximum_count := 1
		for depth_value in levels:
			var ids: Array[int] = levels[depth_value]
			ids.sort()
			maximum_count = maxi(maximum_count, ids.size())
		var content_width := maxf(
			maxf(520.0, size.x),
			CANVAS_PADDING.x * 2.0
				+ maximum_count * CARD_SIZE.x
				+ maxi(maximum_count - 1, 0) * CARD_GAP_X
		)
		var content_height := (
			CANVAS_PADDING.y * 2.0
			+ (maximum_depth + 1) * CARD_SIZE.y
			+ maximum_depth * LEVEL_GAP_Y
		)
		custom_minimum_size = Vector2(content_width, maxf(content_height, 260.0))
		for depth in range(maximum_depth + 1):
			var ids: Array[int] = levels.get(depth, [] as Array[int])
			var row_width := (
				ids.size() * CARD_SIZE.x
				+ maxi(ids.size() - 1, 0) * CARD_GAP_X
			)
			var start_x := (content_width - row_width) * 0.5
			for index in range(ids.size()):
				_rect_by_person[ids[index]] = Rect2(
					Vector2(
						start_x + index * (CARD_SIZE.x + CARD_GAP_X),
						CANVAS_PADDING.y + depth * (CARD_SIZE.y + LEVEL_GAP_Y)
					),
					CARD_SIZE
				)
		queue_redraw()


	func _draw() -> void:
		var members: Dictionary = tree.get("members", {})
		if members.is_empty():
			draw_string(
				font, Vector2(30.0, 54.0), "暂无谱系记录",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, MapRenderer.INK_COLOR
			)
			return
		for person_value in _rect_by_person:
			var person_id := int(person_value)
			var member: Dictionary = members[person_id]
			var parent_id := int(member.get("parent_id", -1))
			if not _rect_by_person.has(parent_id):
				continue
			var parent_rect: Rect2 = _rect_by_person[parent_id]
			var child_rect: Rect2 = _rect_by_person[person_id]
			var start := Vector2(parent_rect.get_center().x, parent_rect.end.y)
			var finish := Vector2(child_rect.get_center().x, child_rect.position.y)
			var middle_y := (start.y + finish.y) * 0.5
			draw_polyline(
				PackedVector2Array([
					start, Vector2(start.x, middle_y),
					Vector2(finish.x, middle_y), finish,
				]),
				Color(MapRenderer.INK_COLOR, 0.62), 2.0
			)
		for person_value in _rect_by_person:
			_draw_person(int(person_value), members[int(person_value)])


	func _draw_person(person_id: int, member: Dictionary) -> void:
		var rect: Rect2 = _rect_by_person[person_id]
		var fill := Color(0.96, 0.90, 0.76, 1.0)
		var border := MapRenderer.ACCENT_RED if person_id == current_person_id else MapRenderer.INK_COLOR
		draw_style_box(_card_style(fill, border), rect)
		var name := str(member.get("name", "？"))
		var titles: Array = member.get("titles", [])
		var title_text := "先祖" if titles.is_empty() else " · ".join(titles)
		draw_string(
			font, rect.position + Vector2(10.0, 27.0), name,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0, 16,
			MapRenderer.INK_COLOR
		)
		draw_string(
			font, rect.position + Vector2(10.0, 51.0), title_text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0, 12,
			Color(MapRenderer.INK_COLOR, 0.78)
		)


	func _card_style(fill: Color, border: Color) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(5)
		return style


	func _depth_of(person_id: int, root_id: int, members: Dictionary) -> int:
		var depth := 0
		var cursor := person_id
		var visited := {}
		while cursor != root_id and members.has(cursor) and not visited.has(cursor):
			visited[cursor] = true
			cursor = int((members[cursor] as Dictionary).get("parent_id", root_id))
			depth += 1
		return depth
