class_name FamilyTreePanel
extends CanvasLayer
## 国家家族树遮罩页。树本身只读，数据真源位于 GameState.family_trees。

signal panel_opened
signal panel_closed

const CARD_SIZE := Vector2(180.0, 72.0)
const CARD_GAP_X: float = 32.0
const LEVEL_GAP_Y: float = 64.0
const CANVAS_PADDING := Vector2(56.0, 32.0)

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
	var _children_by_person: Dictionary = {}
	var _maximum_depth: int = 0


	func _ready() -> void:
		resized.connect(rebuild_layout)


	func rebuild_layout() -> void:
		_rect_by_person.clear()
		_children_by_person.clear()
		_maximum_depth = 0
		var members: Dictionary = tree.get("members", {})
		if members.is_empty():
			custom_minimum_size = Vector2(520.0, 260.0)
			queue_redraw()
			return
		var root_id := int(tree.get("root_person_id", -1))
		var ordered_ids: Array[int] = []
		for person_value in members.keys():
			ordered_ids.append(int(person_value))
		ordered_ids.sort()
		for person_id in ordered_ids:
			_children_by_person[person_id] = [] as Array[int]
		for person_id in ordered_ids:
			if person_id == root_id:
				continue
			var member: Dictionary = members[person_id]
			var parent_id := int(member.get("parent_id", root_id))
			if _children_by_person.has(parent_id):
				(_children_by_person[parent_id] as Array[int]).append(person_id)
		for child_ids_value in _children_by_person.values():
			(child_ids_value as Array[int]).sort()

		var roots: Array[int] = []
		if members.has(root_id):
			roots.append(root_id)
		for person_id in ordered_ids:
			if person_id == root_id:
				continue
			var parent_id := int(
				(members[person_id] as Dictionary).get("parent_id", root_id)
			)
			if not members.has(parent_id):
				roots.append(person_id)

		var subtree_widths := {}
		var natural_width := 0.0
		for root_person_id in roots:
			natural_width += _measure_subtree_width(
				root_person_id, subtree_widths, {}
			)
		if roots.size() > 1:
			natural_width += (roots.size() - 1) * CARD_GAP_X * 2.0
		var content_width := maxf(
			maxf(520.0, size.x),
			CANVAS_PADDING.x * 2.0 + natural_width
		)
		var cursor_x := (content_width - natural_width) * 0.5
		for root_person_id in roots:
			_place_subtree(root_person_id, 0, cursor_x, subtree_widths, {})
			cursor_x += float(subtree_widths[root_person_id]) + CARD_GAP_X * 2.0
		var content_height := (
			CANVAS_PADDING.y * 2.0
			+ (_maximum_depth + 1) * CARD_SIZE.y
			+ _maximum_depth * LEVEL_GAP_Y
		)
		custom_minimum_size = Vector2(content_width, maxf(content_height, 260.0))
		queue_redraw()


	func _draw() -> void:
		var members: Dictionary = tree.get("members", {})
		if members.is_empty():
			draw_string(
				font, Vector2(30.0, 54.0), "暂无谱系记录",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, MapRenderer.INK_COLOR
			)
			return
		_draw_generation_bands()
		for parent_value in _children_by_person:
			var parent_id := int(parent_value)
			if not _rect_by_person.has(parent_id):
				continue
			var parent_rect: Rect2 = _rect_by_person[parent_id]
			var visible_children: Array[int] = []
			for child_id in _children_by_person[parent_id] as Array[int]:
				if _rect_by_person.has(child_id):
					visible_children.append(child_id)
			if visible_children.is_empty():
				continue
			var start := Vector2(parent_rect.get_center().x, parent_rect.end.y)
			var junction_y := start.y + LEVEL_GAP_Y * 0.5
			var first_child: Rect2 = _rect_by_person[visible_children.front()]
			var last_child: Rect2 = _rect_by_person[visible_children.back()]
			var line_color := Color(MapRenderer.INK_COLOR, 0.58)
			draw_line(start, Vector2(start.x, junction_y), line_color, 2.0)
			draw_line(
				Vector2(first_child.get_center().x, junction_y),
				Vector2(last_child.get_center().x, junction_y),
				line_color, 2.0
			)
			for child_id in visible_children:
				var child_rect: Rect2 = _rect_by_person[child_id]
				draw_line(
					Vector2(child_rect.get_center().x, junction_y),
					Vector2(child_rect.get_center().x, child_rect.position.y),
					line_color, 2.0
				)
		for person_value in _rect_by_person:
			_draw_person(int(person_value), members[int(person_value)])


	func _draw_person(person_id: int, member: Dictionary) -> void:
		var rect: Rect2 = _rect_by_person[person_id]
		var titles: Array = member.get("titles", [])
		var is_sovereign := false
		for title_value in titles:
			if str(title_value).ends_with("帝"):
				is_sovereign = true
				break
		var is_current := person_id == current_person_id
		var fill := (
			Color(0.97, 0.91, 0.76, 1.0)
			if is_sovereign
			else Color(0.95, 0.89, 0.77, 1.0)
		)
		var border := MapRenderer.ACCENT_RED if is_current else MapRenderer.INK_COLOR
		draw_style_box(
			_card_style(Color(0.08, 0.06, 0.04, 0.16), Color.TRANSPARENT),
			Rect2(rect.position + Vector2(2.0, 3.0), rect.size)
		)
		draw_style_box(_card_style(fill, border), rect)
		if is_current:
			draw_rect(
				Rect2(rect.position + Vector2(2.0, 2.0), Vector2(rect.size.x - 4.0, 4.0)),
				MapRenderer.ACCENT_RED
			)
		var name := str(member.get("name", "？"))
		var title_text := "先祖" if titles.is_empty() else " · ".join(titles)
		draw_string(
			font, rect.position + Vector2(10.0, 29.0), name,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0, 16,
			MapRenderer.INK_COLOR
		)
		draw_string(
			font, rect.position + Vector2(10.0, 55.0), title_text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 20.0, 12,
			Color(MapRenderer.INK_COLOR, 0.78)
		)
		if is_current:
			draw_string(
				font, rect.position + Vector2(rect.size.x - 42.0, 17.0), "在位",
				HORIZONTAL_ALIGNMENT_CENTER, 34.0, 10,
				MapRenderer.ACCENT_RED
			)


	func _card_style(fill: Color, border: Color) -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(5)
		return style


	func _measure_subtree_width(
		person_id: int,
		widths: Dictionary,
		visiting: Dictionary
	) -> float:
		if widths.has(person_id):
			return float(widths[person_id])
		if visiting.has(person_id):
			return CARD_SIZE.x
		visiting[person_id] = true
		var children: Array[int] = _children_by_person.get(
			person_id, [] as Array[int]
		)
		var children_width := 0.0
		for child_id in children:
			children_width += _measure_subtree_width(child_id, widths, visiting)
		if children.size() > 1:
			children_width += (children.size() - 1) * CARD_GAP_X
		var result := maxf(CARD_SIZE.x, children_width)
		widths[person_id] = result
		visiting.erase(person_id)
		return result


	func _place_subtree(
		person_id: int,
		depth: int,
		left: float,
		widths: Dictionary,
		visiting: Dictionary
	) -> void:
		if _rect_by_person.has(person_id) or visiting.has(person_id):
			return
		visiting[person_id] = true
		var span := float(widths.get(person_id, CARD_SIZE.x))
		_rect_by_person[person_id] = Rect2(
			Vector2(
				left + (span - CARD_SIZE.x) * 0.5,
				CANVAS_PADDING.y + depth * (CARD_SIZE.y + LEVEL_GAP_Y)
			),
			CARD_SIZE
		)
		_maximum_depth = maxi(_maximum_depth, depth)
		var children: Array[int] = _children_by_person.get(
			person_id, [] as Array[int]
		)
		var children_width := 0.0
		for child_id in children:
			children_width += float(widths.get(child_id, CARD_SIZE.x))
		if children.size() > 1:
			children_width += (children.size() - 1) * CARD_GAP_X
		var child_left := left + (span - children_width) * 0.5
		for child_id in children:
			_place_subtree(child_id, depth + 1, child_left, widths, visiting)
			child_left += float(widths.get(child_id, CARD_SIZE.x)) + CARD_GAP_X
		visiting.erase(person_id)


	func _draw_generation_bands() -> void:
		var canvas_width := maxf(size.x, custom_minimum_size.x)
		for depth in range(_maximum_depth + 1):
			var row_y := CANVAS_PADDING.y + depth * (CARD_SIZE.y + LEVEL_GAP_Y)
			if depth % 2 == 1:
				draw_rect(
					Rect2(0.0, row_y - 14.0, canvas_width, CARD_SIZE.y + 28.0),
					Color(MapRenderer.INK_COLOR, 0.035)
				)
			var generation_label := "始祖" if depth == 0 else "第%d代" % depth
			draw_string(
				font, Vector2(10.0, row_y + CARD_SIZE.y * 0.5 + 4.0),
				generation_label, HORIZONTAL_ALIGNMENT_CENTER, 38.0, 11,
				Color(MapRenderer.INK_COLOR, 0.46)
			)
