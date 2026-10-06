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
var _relations: VBoxContainer
var _back: Button
var _navigation: Array[int] = []
var _mode: int = 0
var _mode_select: OptionButton
var _history_scroll: ScrollContainer
var _history: VBoxContainer
var _history_font: Font


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
	if not is_open():
		_navigation.clear()
	_nation_id = nation_id
	_title.text = "%s家族树" % WorldNaming.nation_display_name(
		_state, nation_id
	)
	_tree_canvas.set("tree", FamilyTree.tree_for_nation(_state, nation_id))
	_tree_canvas.set("layout_revision", _state.family_revision)
	_tree_canvas.set("current_person_id", _state.nations[nation_id].ruler_person_id)
	_tree_canvas.set("current_nation_alive", _state.nations[nation_id].alive)
	_tree_canvas.call("rebuild_layout")
	_rebuild_relations()
	_rebuild_history()
	_set_mode(_mode)
	var was_open := _overlay.visible
	_overlay.visible = true
	call_deferred("_focus_current_person", nation_id)
	if not was_open:
		panel_opened.emit()
	(_overlay.get_node("Frame/Content/Header/Close") as Button).grab_focus()
	return true


func _focus_current_person(nation_id: int) -> void:
	if not is_open() or _nation_id != nation_id:
		return
	var rects: Dictionary = _tree_canvas.get("_rect_by_person")
	var id := _state.nations[nation_id].ruler_person_id
	if not rects.has(id):
		return
	var scroll := _tree_canvas.get_parent() as ScrollContainer
	var rect: Rect2 = rects[id]
	scroll.scroll_horizontal = maxi(int(rect.get_center().x - scroll.size.x * 0.5), 0)
	scroll.scroll_vertical = maxi(int(rect.get_center().y - scroll.size.y * 0.5), 0)
	_tree_canvas.queue_redraw()


func navigate_to(nation_id: int) -> void:
	if _state == null or not is_open() or nation_id == _nation_id or nation_id < 0 or nation_id >= _state.nations.size():
		return
	_navigation.append(_nation_id)
	open_for_nation(nation_id)


func navigate_back() -> void:
	if not _navigation.is_empty():
		open_for_nation(_navigation.pop_back())


func _rebuild_relations() -> void:
	_back.disabled = _navigation.is_empty()
	for child in _relations.get_children():
		_relations.remove_child(child)
		child.queue_free()
	var reports: Dictionary = _state.get_meta("historical_prince_reports", {})
	var politics: Dictionary = reports.get(_nation_id, {})
	if politics.is_empty():
		politics = PrincePolitics.report(_state, _nation_id, PrincePolitics.military_index(_state).get(_nation_id, {}))
	for line in PrincePolitics.display_lines(politics):
		var label := Label.new()
		label.text = line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 210
		label.add_theme_font_override("font", MapRenderer.create_ui_font())
		label.add_theme_font_size_override("font_size", 14)
		_relations.add_child(label)
	var summary := Label.new()
	summary.text = RoyalTitles.summary(_state, _nation_id)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_override("font", MapRenderer.create_ui_font())
	summary.add_theme_font_size_override("font_size", 14)
	_relations.add_child(summary)
	var census := RoyalTitles.report(_state, _nation_id)
	for rank in [RoyalTitles.PRINCE, RoyalTitles.COMMANDERY, RoyalTitles.DUKE]:
		_add_title_group(rank, census.people[rank])
	var overlord := _state.overlord_of(_nation_id)
	if overlord >= 0:
		_add_relation("宗主", overlord)
	for subject_id in _state.subjects_of(_nation_id):
		var same_tree := _state.nations[subject_id].family_tree_id == _state.nations[_nation_id].family_tree_id
		_add_relation("同宗藩属" if same_tree else "异姓藩属", subject_id)
	var archived := {}
	for nation in _state.nations:
		if nation.absorbed_into_nation_id == _nation_id:
			archived[nation.id] = true
	for event in _state.diplomatic_history:
		if int(event.get("nation_a", -1)) != _nation_id or not event.has("ultimatum"):
			continue
		var report: Dictionary = event.ultimatum
		if int(report.outcome) == UltimatumRules.Outcome.ANNEX:
			for member_id in report.target_members:
				archived[member_id] = true
	var archived_ids := archived.keys()
	archived_ids.sort()
	for member_id in archived_ids:
		_add_relation("已纳土政权", member_id)


func _add_title_group(rank: int, ids: Array) -> void:
	var button := Button.new()
	button.text = "%s %d人  ▸" % [RoyalTitles.NAMES[rank], ids.size()]
	button.add_theme_font_override("font", MapRenderer.create_ui_font())
	_relations.add_child(button)
	var content := VBoxContainer.new()
	content.visible = false
	_relations.add_child(content)
	button.pressed.connect(func():
		content.visible = not content.visible
		if not content.visible or content.get_child_count() > 0:
			return
		_append_title_page(content, ids, 0))


func _append_title_page(content: VBoxContainer, ids: Array, offset: int) -> void:
	var members: Dictionary = FamilyTree.tree_for_nation(_state, _nation_id).get("members", {})
	for index in range(offset, mini(offset + 40, ids.size())):
		var member: Dictionary = members.get(int(ids[index]), {})
		var label := Label.new()
		label.text = "%s · %s%s" % [member.get("name", "？"), RoyalTitles.NAMES[int(member.get("title_rank", 0))], "" if bool(member.get("title_adult", false)) else "（待继承）"]
		label.add_theme_font_override("font", MapRenderer.create_ui_font())
		label.add_theme_font_size_override("font_size", 13)
		content.add_child(label)
	if offset + 40 < ids.size():
		var more := Button.new()
		more.text = "加载更多"
		content.add_child(more)
		more.pressed.connect(func():
			content.remove_child(more)
			more.queue_free()
			_append_title_page(content, ids, offset + 40))


func _rebuild_history() -> void:
	if _history == null or _state == null:
		return
	for child in _history.get_children():
		_history.remove_child(child)
		child.queue_free()
	var events: Array = _state.chronicle_events.duplicate()
	events.reverse()
	for event_value in events:
		var event: Dictionary = event_value
		var ids: Array = []
		ids.assign(event.get("actor_ids", []))
		for id in event.get("target_ids", []):
			if not ids.has(int(id)): ids.append(int(id))
		if _nation_id not in ids:
			continue
		var label := Label.new()
		var views: Dictionary = event.get("views", {})
		label.text = str(views.get(_nation_id, event.get("text", "")))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(300.0, 32.0)
		label.add_theme_font_override("font", _history_font)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color.BLACK)
		_history.add_child(label)


func _set_mode(mode: int) -> void:
	_mode = clampi(mode, 0, 1)
	if _mode_select != null and _mode_select.selected != _mode:
		_mode_select.select(_mode)
	if _tree_canvas != null:
		_tree_canvas.visible = _mode == 0
	if _history_scroll != null:
		_history_scroll.visible = _mode == 1


func _on_mode_selected(index: int) -> void:
	_set_mode(index)
	if _mode == 1:
		_rebuild_history()


func _add_relation(role: String, nation_id: int) -> void:
	var button := Button.new()
	button.text = "%s · %s" % [role, WorldNaming.nation_display_name(_state, nation_id)]
	button.tooltip_text = button.text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 40.0
	button.add_theme_font_override("font", MapRenderer.create_ui_font())
	button.pressed.connect(navigate_to.bind(nation_id))
	_relations.add_child(button)


func close_panel() -> void:
	_nation_id = -1
	_navigation.clear()
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
	_history_font = MapRenderer.create_map_label_font()
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
	_mode_select = OptionButton.new()
	_mode_select.name = "Mode"
	_mode_select.add_item("家族树")
	_mode_select.add_item("历史记录")
	_mode_select.custom_minimum_size = Vector2(120.0, 42.0)
	_mode_select.item_selected.connect(_on_mode_selected)
	header.add_child(_mode_select)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "←"
	_back.tooltip_text = "返回上一家族"
	_back.custom_minimum_size = Vector2(48.0, 48.0)
	_back.pressed.connect(navigate_back)
	header.add_child(_back)

	var close := Button.new()
	close.name = "Close"
	close.text = "×"
	close.tooltip_text = "关闭家族树"
	close.custom_minimum_size = Vector2(48.0, 48.0)
	close.add_theme_font_override("font", font)
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(close_panel)
	header.add_child(close)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var relation_scroll := ScrollContainer.new()
	relation_scroll.name = "Relations"
	relation_scroll.custom_minimum_size.x = 220.0
	relation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(relation_scroll)
	_relations = VBoxContainer.new()
	_relations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	relation_scroll.add_child(_relations)
	var scroll := ScrollContainer.new()
	scroll.name = "TreeScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(scroll)
	_history_scroll = ScrollContainer.new()
	_history_scroll.name = "HistoryScroll"
	_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_scroll.visible = false
	body.add_child(_history_scroll)
	_history = VBoxContainer.new()
	_history.name = "History"
	_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history.add_theme_constant_override("separation", 8)
	_history_scroll.add_child(_history)

	_tree_canvas = FamilyTreeCanvas.new()
	_tree_canvas.name = "TreeCanvas"
	_tree_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_canvas.set("font", font)
	scroll.add_child(_tree_canvas)


class FamilyTreeCanvas extends Control:
	var tree: Dictionary = {}
	var current_person_id: int = -1
	var current_nation_alive: bool = true
	var font: Font
	var _rect_by_person: Dictionary = {}
	var _children_by_person: Dictionary = {}
	var _maximum_depth: int = 0
	var layout_revision: int = -1
	var _layout_key: Array = []


	func _ready() -> void:
		resized.connect(rebuild_layout)


	func rebuild_layout() -> void:
		var key := [tree.get("id", -1), layout_revision, tree.get("root_person_id", -1), tree.get("members", {}).size(), get_parent().size.x if get_parent() is Control else size.x]
		if key == _layout_key:
			queue_redraw()
			return
		_layout_key = key
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
			maxf(520.0, get_parent().size.x - 16.0 if get_parent() is ScrollContainer else size.x),
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
		var visible_rect := Rect2(Vector2.ZERO, size)
		if get_parent() is ScrollContainer:
			visible_rect = Rect2(get_parent().get_global_rect().position - global_position, get_parent().size).grow(80.0)
		for person_value in _rect_by_person:
			if not visible_rect.intersects(_rect_by_person[person_value]):
				continue
			_draw_person(int(person_value), members[int(person_value)])


	func _draw_person(person_id: int, member: Dictionary) -> void:
		var rect: Rect2 = _rect_by_person[person_id]
		var is_sovereign := str(member.get("current_title", "")).ends_with("帝")
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
		var title_text := FamilyTree.display_title(
			member, person_id, int(tree.get("root_person_id", -1))
		)
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
		var badges: Array[String] = []
		if bool(member.get("taizu", false)): badges.append("太祖")
		if str(member.get("accession_source", "")) == "remote": badges.append("远支入继")
		elif bool(member.get("synthetic_ancestor", false)): badges.append("补录")
		if bool(member.get("crown", false)) and bool(member.get("alive", true)): badges.append("储君")
		if not bool(member.get("alive", true)): badges.append("已故")
		elif is_current: badges.append("在位" if current_nation_alive else "末任")
		if not badges.is_empty():
			draw_string(
				font, rect.position + Vector2(10.0, 15.0), " · ".join(badges),
				HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 20.0, 10,
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
