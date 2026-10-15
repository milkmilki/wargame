extends PanelContainer
const Calendar = preload("res://scripts/core/game_calendar.gd")
const Model = preload("res://scripts/atlas/family_model.gd")
const Canvas = preload("res://scripts/atlas/family_canvas.gd")
const Inspector = preload("res://scripts/atlas/information_panel.gd")
const Style = preload("res://scripts/atlas/information_theme.gd")
var host; var nation_id := -1; var model := {}; var revision: Array=[]
var canvas := Canvas.new(); var inspector := Inspector.new()
var selector := OptionButton.new(); var search := LineEdit.new()
var side := VBoxContainer.new(); var layout_row := HBoxContainer.new()
var title := Label.new(); var compact := false; var result_cursor := 0
var viewport_size := Vector2.ZERO
var last_query := ""
func _init() -> void:
	theme=Style.create(); z_index=100; mouse_filter=Control.MOUSE_FILTER_STOP; mouse_force_pass_scroll_events=false
	var panel_style:=Style.panel(); panel_style.bg_color=Color("f8f8fa"); add_theme_stylebox_override("panel",panel_style)
	var body := VBoxContainer.new(); add_child(body)
	var header := HBoxContainer.new(); body.add_child(header)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	button(header,"×",close).tooltip_text="关闭家族树（Esc）"
	var tools := HBoxContainer.new(); body.add_child(tools)
	search.placeholder_text="搜索姓名 / 人物编号"; search.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tools.add_child(search)
	search.text_submitted.connect(func(_text): search_next())
	button(tools,"查找",search_next); button(tools,"全谱",canvas.fit_all)
	button(tools,"当前",func(): canvas.locate(model.get("current",-1)))
	button(tools,"人物",func(): inspector.visible=not inspector.visible; canvas.visible=not inspector.visible if compact else true)
	var legend := Label.new(); legend.text="世代自上而下 · 名字竖排 · 爵号依箭头先后 · 朱色双框「帝」为历任皇帝"
	legend.add_theme_color_override("font_color",Color("726959")); legend.add_theme_font_size_override("font_size",12)
	legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; body.add_child(legend)
	body.add_child(selector); selector.item_selected.connect(func(index): open(selector.get_item_id(index)))
	body.add_child(layout_row); layout_row.size_flags_vertical=Control.SIZE_EXPAND_FILL
	layout_row.add_child(side); side.custom_minimum_size.x=160
	layout_row.add_child(canvas); canvas.clip_contents=true; canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	layout_row.add_child(inspector); inspector.custom_minimum_size=Vector2(300,0)
	inspector.provider=func(): return Model.person_document(model,canvas.focus_id)
	inspector.navigate.connect(func(kind,id):
		if kind=="person":
			canvas.locate(id)
			inspector.show_document(Model.person_document(model,id))
			if compact: canvas.hide()
		elif kind=="nation":
			close()
			host.show_information("nation",id))
	inspector.closed.connect(func(): canvas.show())
	canvas.selected.connect(func(id): inspector.show_document(Model.person_document(model,id)); if compact: canvas.hide())
	visible=false
func button(parent: Node,text_value: String,callback: Callable) -> Button:
	var control:=Button.new(); control.text=text_value; parent.add_child(control); control.pressed.connect(callback); return control
func open(id: int,person_id: int = -1) -> void:
	# z_index controls drawing, not GUI picking. The map toolbar is added
	# later, so raise sibling input order as well before opening this overlay.
	if get_parent()!=null: get_parent().move_child(self,get_parent().get_child_count()-1)
	nation_id=id; revision.clear(); visible=true; refresh_model()
	if model.is_empty(): title.text="等待当日结算完成…"; return
	responsive(); call_deferred("initial_focus",person_id)
func initial_focus(person_id: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not visible or model.is_empty(): return
	canvas.fit_all(); canvas.focus_id=person_id if person_id>=0 else model.last_ruler
	if canvas.scale_value<.65 or person_id>=0: canvas.locate(canvas.focus_id)
	else: canvas.selected.emit(canvas.focus_id)
	# Opening the genealogy starts with the tree on compact windows; explicit
	# person links still open that person's details directly.
	if compact and person_id<0: inspector.hide(); canvas.show()
	canvas.queue_redraw()
func close() -> void:
	hide(); model.clear(); revision.clear(); inspector.hide(); canvas.model.clear(); canvas.layout.clear(); canvas.spatial.clear(); canvas.links.clear(); canvas.signature=-1
func _process(_delta: float) -> void:
	if not visible: return
	responsive(); refresh_model()
func refresh_model() -> void:
	if host==null: return
	if not host.historical_view and host.simulation!=null and host.simulation.runtime_day_in_progress(): return
	var source: GameState=host.information_source()
	if source==null: return
	var key: Array=[source.get_instance_id(),source.day,source.family_revision,nation_id,host.historical_view]
	if key==revision: return
	var next:=Model.capture(source,nation_id)
	if next.is_empty(): close(); return
	revision=key; model=next; canvas.update_model(model)
	title.text="%s氏家谱 · %s · %s%s"%[model.surname,model.name,Calendar.date(model.day)," · 历史只读" if host.historical_view else ""]
	selector.clear()
	for child in side.get_children(): side.remove_child(child); child.queue_free()
	for country in model.countries:
		var label_text: String=country.name+("（已灭亡）" if not country.alive else "")
		selector.add_item(label_text,country.id)
		if country.id==nation_id: selector.select(selector.item_count-1)
		button(side,label_text,func(): open(country.id))
	for family in Model.related_families(source,nation_id):
		var label_text: String="查看"+family.name
		selector.add_item(label_text,family.id)
		button(side,label_text,func(): open(family.id))
	if inspector.visible: inspector.show_document(Model.person_document(model,canvas.focus_id))
	elif canvas.focus_id<0: canvas.fit_all(); canvas.locate(model.current)
func responsive() -> void:
	var viewport := get_viewport_rect().size
	position=Vector2(16,16); size=viewport-Vector2(32,32)
	compact=viewport.x<1100; side.visible=not compact; selector.visible=compact
	if viewport!=viewport_size:
		viewport_size=viewport; canvas.call_deferred("fit_all")
	inspector.custom_minimum_size.x=300 if not compact else maxf(300,viewport.x-64)
	if compact and inspector.visible: canvas.hide()
	elif not compact: canvas.show()
func search_next() -> void:
	if model.is_empty(): return
	var matches: Array=[]; var query:=search.text.strip_edges()
	if query!=last_query: result_cursor=0; last_query=query
	for id in model.members:
		if query.is_empty() or str(model.members[id].get("name","")).contains(query) or str(id)==query: matches.append(id)
	matches.sort()
	if matches.is_empty(): search.tooltip_text="无匹配人物"; return
	canvas.locate(matches[result_cursor%matches.size()]); result_cursor+=1
