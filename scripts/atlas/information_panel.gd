extends PanelContainer
## Native equivalent of civ-atlas PanelHead / Acts / Stats / cp-body.
signal navigate(kind: String,id: int)
signal act(key: String,id: int)
signal closed
const Style = preload("res://scripts/atlas/information_theme.gd")
var provider: Callable
var document := {}
var rows: Array = []
var buttons: Array = []
var shape := -1
var refresh_elapsed := 0.
var title := Label.new()
var subtitle := Label.new()
var swatch := Panel.new()
var actions := HBoxContainer.new()
var scroll := ScrollContainer.new()
var body := VBoxContainer.new()
var close_button := Button.new()
var notice := Label.new()
var build_count := 0
var section_cache := {}
var action_shape := -1
func _init():
	theme=Style.create(); custom_minimum_size=Vector2(340,0); mouse_filter=Control.MOUSE_FILTER_STOP; mouse_force_pass_scroll_events=false
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation",12); add_child(content)
	var header := HBoxContainer.new(); header.add_theme_constant_override("separation",10); content.add_child(header)
	swatch.custom_minimum_size=Vector2(12,12); swatch.size_flags_vertical=Control.SIZE_SHRINK_CENTER; header.add_child(swatch)
	var headings := VBoxContainer.new(); headings.size_flags_horizontal=Control.SIZE_EXPAND_FILL; headings.add_theme_constant_override("separation",3); header.add_child(headings)
	title.add_theme_font_size_override("font_size",22); title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; headings.add_child(title)
	subtitle.add_theme_font_size_override("font_size",13); subtitle.add_theme_color_override("font_color",Style.MUTED); subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; headings.add_child(subtitle)
	close_button.text="×"; close_button.tooltip_text="关闭（Esc）"; close_button.custom_minimum_size=Vector2(26,26); close_button.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	close_button.add_theme_stylebox_override("normal",Style.box(Color(.463,.463,.502,.12),13)); header.add_child(close_button)
	close_button.pressed.connect(dismiss); content.add_child(actions)
	notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; notice.add_theme_color_override("font_color",Style.MUTED); notice.add_theme_font_size_override("font_size",12); content.add_child(notice)
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.mouse_force_pass_scroll_events=false; content.add_child(scroll)
	scroll.follow_focus=true
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",18); scroll.add_child(body)
	visible=false
func show_document(value: Dictionary) -> void:
	if value.is_empty(): dismiss(); return
	var same_object: bool = document.get("title","")==value.title
	document=value; visible=true
	title.text=value.title; subtitle.text=value.subtitle; swatch.add_theme_stylebox_override("panel",Style.box(value.color,4))
	notice.text=value.get("notice",""); notice.visible=not notice.text.is_empty()
	var structure: Array = []
	for group in value.sections: structure.append([group.title,group.rows.map(func(r): return [r.label,not r.kind.is_empty() and r.id>=0])])
	var next := hash([structure,value.actions.map(func(a): return [a.key,a.label,a.icon])])
	if next!=shape:
		shape=next; rebuild(value)
	if not same_object: scroll.scroll_vertical=0
	for i in range(buttons.size()):
		buttons[i].action=value.actions[i]; buttons[i].node.disabled=value.actions[i].get("disabled",false)
		buttons[i].node.modulate=Color(1,1,1,.45 if buttons[i].node.disabled else 1.)
	var index := 0
	for group in value.sections:
		for r in group.rows:
			var slot: Dictionary = rows[index]; slot.row=r; slot.node.text=r.value; slot.node.tooltip_text=r.value; index+=1
func rebuild(value: Dictionary) -> void:
	var next_actions := hash(value.actions.map(func(a): return [a.key,a.label,a.icon]))
	if next_actions!=action_shape:
		action_shape=next_actions; rebuild_actions(value)
	rows.clear(); build_count+=1
	var wanted := {}
	for index in range(value.sections.size()):
		var group: Dictionary = value.sections[index]
		var key := "%d:%s"%[index,group.title]; wanted[key]=true
		var signature := hash(group.rows.map(func(r): return [r.label,not r.kind.is_empty() and r.id>=0]))
		if section_cache.has(key) and section_cache[key].signature==signature:
			rows.append_array(section_cache[key].rows); body.move_child(section_cache[key].node,index); continue
		if section_cache.has(key):
			var old: Node = section_cache[key].node; body.remove_child(old); old.queue_free()
		var cached := rebuild_section(group); cached.signature=signature; section_cache[key]=cached
		rows.append_array(cached.rows); body.move_child(cached.node,index)
	for key in section_cache.keys():
		if wanted.has(key): continue
		var old: Node = section_cache[key].node; body.remove_child(old); old.queue_free(); section_cache.erase(key)

func rebuild_actions(value: Dictionary) -> void:
	for child in actions.get_children(): actions.remove_child(child); child.queue_free()
	buttons.clear()
	for i in range(value.actions.size()):
		var entry: Dictionary = value.actions[i]; var button := Button.new(); button.custom_minimum_size=Vector2(0,54); button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal",Style.box(Style.ACCENT if i==0 else Color(.463,.463,.502,.12),10))
		button.add_theme_stylebox_override("hover",Style.box(Color("0066d6") if i==0 else Color(.463,.463,.502,.20),10))
		var contents := VBoxContainer.new(); contents.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(contents); contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		contents.offset_top=6; contents.offset_bottom=-6; contents.add_theme_constant_override("separation",2)
		var icon := TextureRect.new(); icon.mouse_filter=Control.MOUSE_FILTER_IGNORE; icon.custom_minimum_size=Vector2(19,19); icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture=Style.icon(entry.icon); icon.self_modulate=Color.WHITE if i==0 else Style.ACCENT; contents.add_child(icon)
		var caption := Label.new(); caption.mouse_filter=Control.MOUSE_FILTER_IGNORE; caption.text=entry.label; caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; caption.add_theme_font_size_override("font_size",12); caption.add_theme_color_override("font_color",Color.WHITE if i==0 else Style.ACCENT); contents.add_child(caption)
		var slot := {"node":button,"action":entry}; buttons.append(slot)
		button.pressed.connect(func(): act.emit(slot.action.key,slot.action.id)); actions.add_child(button)

func rebuild_section(group: Dictionary) -> Dictionary:
	var group_rows: Array = []
	# Keep the other sections and their text/font commands when a dynamic
	# military roster changes. Replacing the entire card stalls the map frame.
	var section := VBoxContainer.new(); section.add_theme_constant_override("separation",6); body.add_child(section)
	var heading := Label.new(); heading.text=group.title; heading.add_theme_font_size_override("font_size",13); heading.add_theme_color_override("font_color",Style.MUTED); section.add_child(heading)
	var panel := PanelContainer.new(); var group_style := Style.box(Color(.463,.463,.502,.10),10); panel.add_theme_stylebox_override("panel",group_style); section.add_child(panel)
	var list := VBoxContainer.new(); list.add_theme_constant_override("separation",0); panel.add_child(list)
	for r in group.rows:
		if list.get_child_count()>0:
			var separator := ColorRect.new(); separator.color=Style.LINE; separator.custom_minimum_size.y=1; separator.mouse_filter=Control.MOUSE_FILTER_IGNORE; list.add_child(separator)
		var margin := MarginContainer.new(); margin.add_theme_constant_override("margin_left",12); margin.add_theme_constant_override("margin_right",12); margin.add_theme_constant_override("margin_top",9); margin.add_theme_constant_override("margin_bottom",9); list.add_child(margin)
		var line := HBoxContainer.new(); margin.add_child(line)
		var key := Label.new(); key.text=r.label; key.add_theme_color_override("font_color",Style.MUTED); key.add_theme_font_size_override("font_size",13); line.add_child(key)
		var text: Control
		if r.kind.is_empty() or r.id<0:
			var label := Label.new(); label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; text=label
		else:
			var link := Button.new(); link.flat=true; link.alignment=HORIZONTAL_ALIGNMENT_RIGHT; link.add_theme_color_override("font_color",Style.LINK); link.add_theme_color_override("font_hover_color",Style.ACCENT); link.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; text=link
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL; text.custom_minimum_size.x=110; line.add_child(text)
		var slot := {"node":text,"row":r}; group_rows.append(slot)
		if text is Button: text.pressed.connect(func(): navigate.emit(slot.row.kind,slot.row.id))
	return {"node":section,"rows":group_rows}
func _process(delta: float):
	if not visible or not provider.is_valid(): return
	refresh_elapsed+=delta
	if refresh_elapsed<.5: return
	refresh_elapsed=0.; show_document(provider.call())
func _unhandled_key_input(event: InputEvent):
	if visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		dismiss(); get_viewport().set_input_as_handled()
func dismiss():
	visible=false; document={}; closed.emit()
