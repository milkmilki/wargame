extends Control
## Floating map controls and the shared inspector; native Godot equivalents.
const Style = preload("res://scripts/atlas/information_theme.gd")
const Inspector = preload("res://scripts/atlas/information_panel.gd")
var host
var tools := PanelContainer.new()
var toolbar := PanelContainer.new()
var footer := PanelContainer.new()
var pause_button: Button
var step_button: Button
func setup(view) -> void:
	host=view; mouse_filter=Control.MOUSE_FILTER_IGNORE; z_index=20; theme=Style.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Preserve the existing HUD owner for scene cleanup and capture helpers.
	add_child(view.hud); view.hud.hide(); view.hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	view.info_panel=Inspector.new(); add_child(view.info_panel)
	view.info_panel.provider=view.information_document
	view.info_panel.navigate.connect(view.show_information); view.info_panel.act.connect(view.information_action)
	view.info_panel.closed.connect(view.close_information)
	add_child(toolbar); var bar := HBoxContainer.new(); toolbar.add_child(bar)
	for name_value in ["政治","地形","府辖区","宜居度"]: view.mode_control.add_item(name_value)
	bar.add_child(view.mode_control); view.mode_control.item_selected.connect(func(_i): view.update_mode())
	pause_button=button(bar,"暂停／继续",func(): if view.simulation!=null and not view.historical_view: view.simulation.paused=not view.simulation.paused)
	button(bar,"全图",view.fit_map)
	button(bar,"地图工具",func(): tools.visible=not tools.visible)
	add_child(tools); tools.visible=false; tools.mouse_force_pass_scroll_events=false; toolbar.mouse_force_pass_scroll_events=false
	var content := VBoxContainer.new(); tools.add_child(content)
	var top := HBoxContainer.new(); content.add_child(top)
	var label := Label.new(); label.text="地图与军事工具"; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; top.add_child(label)
	button(top,"×",func(): tools.hide())
	var scroll := ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.custom_minimum_size.y=300; content.add_child(scroll)
	var body := VBoxContainer.new(); body.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(body)
	var map_row := HBoxContainer.new(); body.add_child(map_row); map_row.add_child(view.seed_control)
	button(map_row,"随机星球",func(): if view.can_rebuild(): await view.load_preset("planet"))
	button(map_row,"真实地球",func(): if view.can_rebuild(): await view.load_preset("earth"))
	var controls := HBoxContainer.new(); body.add_child(controls)
	step_button=button(controls,"推进一天",func(): if view.simulation!=null and not view.historical_view and not view.simulation.runtime_day_in_progress(): view.simulation._advance_day())
	var player := Label.new(); player.text="操控国"; controls.add_child(player)
	view.player_nation.min_value=0; view.player_nation.max_value=39; controls.add_child(view.player_nation)
	var orders := HBoxContainer.new(); body.add_child(orders)
	button(orders,"选本国军队",view.select_player_army); button(orders,"对选区宣战",view.declare_selected_war); button(orders,"前往选区",view.order_selected)
	var debug := HBoxContainer.new(); body.add_child(debug)
	var junctions := CheckButton.new(); junctions.text="交通节点"; debug.add_child(junctions)
	junctions.toggled.connect(func(value): if view.overlay!=null: view.overlay.show_traffic=value; view.overlay.queue_redraw())
	button(debug,"截图",func(): await view.export_screenshot())
	var templates := HBoxContainer.new(); body.add_child(templates)
	button(templates,"保存地图模板",func(): if view.state!=null: view.status.text=str(MapDefinition.save_state(view.state,"atlas-military.json")))
	button(templates,"加载地图模板",view.load_military_template)
	var historic := Label.new(); historic.text="历史快照"; body.add_child(historic)
	var history_row := HBoxContainer.new(); body.add_child(history_row)
	view.history_control.min_value=0; view.history_control.max_value=0; history_row.add_child(view.history_control)
	button(history_row,"查看历史",view.show_history)
	button(history_row,"返回当前",func(): view.historical_view=false; if view.overlay!=null: view.overlay.state=view.state; view.last_owner_revision=-1; view.info_panel.show_document(view.information_document()))
	add_child(footer); footer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var messages := VBoxContainer.new(); footer.add_child(messages); messages.mouse_filter=Control.MOUSE_FILTER_IGNORE
	view.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; view.status.mouse_filter=Control.MOUSE_FILTER_IGNORE; messages.add_child(view.status)
	view.military_status.add_theme_font_size_override("font_size",12); view.military_status.add_theme_color_override("font_color",Style.MUTED); view.military_status.mouse_filter=Control.MOUSE_FILTER_IGNORE; messages.add_child(view.military_status)
	add_child(view.details); view.details.hide()
	resized.connect(place); place()
	footer.resized.connect(func(): footer.position.y=size.y-footer.size.y-14)

func _process(_delta: float) -> void:
	# A wrapped startup message can initially have a large minimum height before
	# its width is assigned. Refit this small status capsule as its text settles.
	footer.size.y=footer.get_combined_minimum_size().y
	footer.position.y=size.y-footer.size.y-14
	if host==null: return
	var blocked: bool=host.historical_view or not host.view_ready or host.simulation==null
	pause_button.disabled=blocked
	step_button.disabled=blocked or host.simulation.runtime_day_in_progress()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_MIDDLE and not event.pressed:
		host.dragging=false # Release remains visible even when the card handles GUI input.
func button(parent: Control,text_value: String,callback: Callable) -> Button:
	var control := Button.new(); control.text=text_value; control.pressed.connect(callback); parent.add_child(control)
	return control
func place() -> void:
	if host==null or host.info_panel==null: return
	var width := 372. if size.x>=1100 else 340.
	host.info_panel.position=Vector2(14,14); host.info_panel.size=Vector2(minf(width,maxf(300,size.x-28)),maxf(240,size.y-28))
	toolbar.position=Vector2(maxf(14,size.x-430),14); toolbar.size=Vector2(416,54)
	tools.position=Vector2(maxf(14,size.x-446),78); tools.size=Vector2(432,minf(380,size.y-100))
	var footer_width := minf(620,maxf(300,size.x-width-42))
	footer.position=Vector2(size.x-footer_width-14,size.y-footer.size.y-14); footer.size.x=footer_width
