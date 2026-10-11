extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_INFO_PANEL_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var panel := preload("res://scripts/atlas/information_panel.gd").new(); root.add_child(panel); panel.size=Vector2(372,650)
	var doc := {"title":"清远郡","subtitle":"州治 · 第1天","color":Color.RED,"notice":"","actions":[{"key":"nation","label":"所属国家","icon":"flag","id":1,"disabled":false}],"sections":[{"title":"概况","rows":[{"label":"所属国","value":"甲国","kind":"nation","id":1},{"label":"人数","value":"100","kind":"","id":-1}]}]}
	panel.show_document(doc); await process_frame; await process_frame
	var builds: int=panel.build_count; var row_control: Control=panel.rows[0].node
	var updated := doc.duplicate(true); updated.subtitle="州治 · 第2天"; updated.sections[0].rows[0].value="乙国"; updated.sections[0].rows[0].id=2; updated.sections[0].rows[1].value="120"; updated.actions[0].id=2
	panel.show_document(updated)
	check(panel.build_count==builds and panel.rows[0].node==row_control,"ordinary updates reuse the same controls")
	var selection := []; panel.navigate.connect(func(kind,id): selection.append([kind,id]))
	row_control.pressed.emit(); check(selection==[["nation",2]],"navigation uses the latest controller, not the old callback target")
	var actions := []; panel.act.connect(func(key,id): actions.append([key,id]))
	panel.buttons[0].node.pressed.emit(); check(actions==[["nation",2]],"actions use the current document")
	updated.sections.append({"title":"军队","rows":[{"label":"军队1","value":"5000人","kind":"army","id":1}]})
	var action_control: Control=panel.buttons[0].node
	panel.show_document(updated)
	check(panel.rows[0].node==row_control and panel.buttons[0].node==action_control,"roster growth preserves overview and action controls")
	var state:=GameState.new()
	for id in range(2):
		var n:=Nation.new(); n.id=id; n.name="战役国%d"%id; n.capital_city_id=id; state.nations.append(n)
		var c:=City.new(); c.id=id; c.name="目标州%d"%id; c.owner_nation=id; state.cities.append(c)
	state.administrative_center_by_city=PackedInt32Array([0,1])
	var front:=state.create_campaign_front(0,[0] as Array[int],0,CoalitionCampaignFront.Mode.OFFENSE,1)
	var model=preload("res://scripts/atlas/information_model.gd")
	panel.show_document(model.nation(state,0))
	var target: Control
	for slot in panel.rows:
		if slot.row.label=="目标州": target=slot.node; break
	check(target is Button,"campaign objective is a native information-card link")
	var campaign_builds: int=panel.build_count
	front.center_city_id=0; front.phase=CoalitionCampaignFront.Phase.ASSAULT_CENTER
	panel.show_document(model.nation(state,0))
	check(panel.build_count==campaign_builds and is_instance_valid(target),"campaign phase and target updates reuse card controls")
	if target is Button:
		target.pressed.emit(); check(selection.back()==["city",0],"campaign navigation follows the refreshed objective")
	var overview: Control=panel.rows[0].node
	state.create_campaign_front(1,[0] as Array[int],0,CoalitionCampaignFront.Mode.DEFENSE,0)
	panel.show_document(model.nation(state,0))
	check(panel.rows[0].node==overview,"a second state campaign does not rebuild national overview")
	check(panel.mouse_filter==Control.MOUSE_FILTER_STOP,"the panel stops map clicks and wheel input")
	check(not panel.mouse_force_pass_scroll_events and not panel.scroll.mouse_force_pass_scroll_events,"wheel input does not propagate at scroll limits")
	check(panel.scroll.get_global_rect().end.y<=panel.get_global_rect().end.y,"scrolling content stays inside the panel")
	var escape := InputEventKey.new(); escape.pressed=true; escape.keycode=KEY_ESCAPE; panel._unhandled_key_input(escape)
	check(not panel.visible,"Escape closes the information card")
	root.remove_child(panel); panel.queue_free(); await process_frame
	print("ATLAS_INFORMATION_PANEL failures=",failures); quit(1 if failures else 0)
