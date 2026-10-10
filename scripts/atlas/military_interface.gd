extends Control
## Floating map controls and the shared inspector; native Godot equivalents.
const Style = preload("res://scripts/atlas/information_theme.gd")
const Inspector = preload("res://scripts/atlas/information_panel.gd")
const Countries = preload("res://scripts/atlas/nation_list.gd")
var host
var tools := PanelContainer.new()
var toolbar := PanelContainer.new()
var footer := PanelContainer.new()
var pause_button: Button
var step_button: Button
var speed_label := Label.new()
var speed_buttons: Array = []
var slower_button: Button
var faster_button: Button
var countries := Countries.new()
var diplomacy_row := HBoxContainer.new()
var observer_label := Label.new()
var relation_legend := Label.new()
func setup(view) -> void:
	host=view; mouse_filter=Control.MOUSE_FILTER_IGNORE; z_index=20; theme=Style.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Preserve the existing HUD owner for scene cleanup and capture helpers.
	add_child(view.hud); view.hud.hide(); view.hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	view.info_panel=Inspector.new(); add_child(view.info_panel)
	view.info_panel.provider=view.information_document
	view.info_panel.navigate.connect(view.show_information); view.info_panel.act.connect(view.information_action)
	view.info_panel.closed.connect(view.close_information)
	add_child(toolbar); var bars := VBoxContainer.new(); toolbar.add_child(bars)
	var bar := HBoxContainer.new(); bars.add_child(bar)
	for name_value in ["政治","地形","府辖区","宜居度"]: view.mode_control.add_item(name_value)
	bar.add_child(view.mode_control); view.mode_control.item_selected.connect(func(_i): view.update_mode())
	pause_button=button(bar,"继续",view.toggle_pause)
	button(bar,"全图",view.fit_map)
	button(bar,"国家",func(): tools.hide(); countries.hide() if countries.visible else countries.open())
	button(bar,"工具",func(): countries.hide(); tools.visible=not tools.visible)
	var timeline := HBoxContainer.new(); bars.add_child(timeline)
	step_button=button(timeline,"推进一天",view.step_day)
	slower_button=button(timeline,"−",func(): view.change_time_speed(.5))
	speed_label.custom_minimum_size.x=44; speed_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; timeline.add_child(speed_label)
	faster_button=button(timeline,"+",func(): view.change_time_speed(2.))
	for multiplier in [1.,2.,4.,8.]:
		var control := button(timeline,"%d×"%multiplier,func(): view.set_time_speed(multiplier))
		control.toggle_mode=true; speed_buttons.append({"node":control,"multiplier":multiplier})
	add_child(countries); countries.source_provider=view.information_source
	countries.observer_provider=func(): return view.diplomatic_observer
	countries.selected.connect(func(id): view.show_information("nation",id))
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
	view.mask_controls=view.MaskControls.new(); body.add_child(view.mask_controls); view.mask_controls.setup(view)
	var controls := HBoxContainer.new(); body.add_child(controls)
	var player := Label.new(); player.text="操控国"; controls.add_child(player)
	view.player_nation.min_value=0; view.player_nation.max_value=39; controls.add_child(view.player_nation)
	var orders := HBoxContainer.new(); body.add_child(orders)
	button(orders,"选本国军队",view.select_player_army); button(orders,"对选区宣战",view.declare_selected_war); button(orders,"前往选区",view.order_to_inspected)
	var debug := HBoxContainer.new(); body.add_child(debug)
	var city_names := CheckButton.new(); city_names.text="城市名称"; city_names.button_pressed=view.text_layer.show_city_names; debug.add_child(city_names)
	city_names.toggled.connect(func(value): view.text_layer.show_city_names=value; view.text_layer.rebuild())
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
	button(history_row,"返回当前",view.return_to_current)
	add_child(footer); footer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var messages := VBoxContainer.new(); footer.add_child(messages); messages.mouse_filter=Control.MOUSE_FILTER_IGNORE
	messages.add_child(diplomacy_row); observer_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; observer_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; diplomacy_row.add_child(observer_label)
	button(diplomacy_row,"普通国色",view.restore_country_colors)
	relation_legend.text="本国：国色 · 敌对：红 · 同盟：绿 · 藩属：灰 · 中立：黑"
	relation_legend.add_theme_font_size_override("font_size",12); relation_legend.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; relation_legend.mouse_filter=Control.MOUSE_FILTER_IGNORE; messages.add_child(relation_legend)
	diplomacy_row.hide(); relation_legend.hide()
	view.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; view.status.mouse_filter=Control.MOUSE_FILTER_IGNORE; messages.add_child(view.status)
	view.military_status.add_theme_font_size_override("font_size",12); view.military_status.add_theme_color_override("font_color",Style.MUTED); view.military_status.mouse_filter=Control.MOUSE_FILTER_IGNORE; messages.add_child(view.military_status)
	add_child(view.details); view.details.hide()
	resized.connect(place); place()
	footer.resized.connect(func(): footer.position.y=size.y-footer.size.y-14)

func refresh_diplomacy() -> void:
	var source: GameState=host.information_source()
	var id: int=host.diplomatic_observer
	var valid: bool=host.Diplomacy.valid(source,id)
	diplomacy_row.visible=valid; relation_legend.visible=valid and host.diplomacy_enabled
	if valid:
		var suffix := "外交着色" if host.diplomacy_enabled and host.mode_control.selected==0 else "其他图层保留原色" if host.diplomacy_enabled else "普通国色"
		observer_label.text="观察国：%s · %s"%[source.nations[id].name,suffix]
	countries.refresh()

func _process(_delta: float) -> void:
	# A wrapped startup message can initially have a large minimum height before
	# its width is assigned. Refit this small status capsule as its text settles.
	footer.size.y=footer.get_combined_minimum_size().y
	footer.position.y=size.y-footer.size.y-14
	if countries.visible: countries.size.y=maxf(160,footer.position.y-countries.position.y-8)
	if host==null: return
	var blocked: bool=not host.time_controls_available()
	pause_button.disabled=blocked
	step_button.disabled=blocked or (host.simulation!=null and (not host.simulation.paused or host.simulation.runtime_day_in_progress()))
	slower_button.disabled=blocked; faster_button.disabled=blocked
	var speed: float=host.simulation.speed_multiplier() if host.simulation!=null else 1.
	speed_label.text=str(speed)+"×"
	pause_button.text="继续" if host.simulation==null or host.simulation.paused else "暂停"
	for row in speed_buttons:
		row.node.disabled=blocked; row.node.set_pressed_no_signal(is_equal_approx(speed,row.multiplier))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_MIDDLE and not event.pressed:
		host.dragging=false # Release remains visible even when the card handles GUI input.
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		if tools.visible: tools.hide(); get_viewport().set_input_as_handled()
		elif countries.visible: countries.hide(); get_viewport().set_input_as_handled()
func button(parent: Control,text_value: String,callback: Callable) -> Button:
	var control := Button.new(); control.text=text_value; control.pressed.connect(callback); parent.add_child(control)
	return control
func place() -> void:
	if host==null or host.info_panel==null: return
	var width := 372. if size.x>=1100 else 340.
	host.info_panel.position=Vector2(14,14); host.info_panel.size=Vector2(minf(width,maxf(300,size.x-28)),maxf(240,size.y-28))
	toolbar.position=Vector2(maxf(14,size.x-430),14); toolbar.size=Vector2(416,88)
	tools.position=Vector2(maxf(14,size.x-446),116); tools.size=Vector2(432,minf(380,size.y-140))
	countries.position=Vector2(maxf(14,size.x-430),116); countries.size=Vector2(416,maxf(200,size.y-144))
	var footer_width := minf(620,maxf(300,size.x-width-42))
	footer.position=Vector2(size.x-footer_width-14,size.y-footer.size.y-14); footer.size.x=footer_width
