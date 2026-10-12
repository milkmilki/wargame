extends SceneTree
const Model = preload("res://scripts/atlas/battle_information.gd")
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready(): make_ui(); set_process(false)
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("BATTLE_COMPARISON_FAIL ",message)
func run():
	root.size=Vector2i(900,600)
	var state:=GameState.new()
	var a:=Army.new(); a.id=2; a.size=12000; a.morale=.8; a.owner_nation=0
	var b:=Army.new(); b.id=4; b.size=9000; b.morale=.5; b.owner_nation=1
	var battle:=Battle.new(); battle.id=3; battle.side_a=[a]; battle.side_b=[b]
	battle.ensure_opening_dice(1,true); state.battles=[battle]
	var doc:=Model.document(state,3)
	var groups: Array=doc.sections.filter(func(group): return group.has("columns"))
	check(groups.size()==1,"battle has one aligned comparison table instead of sequential side sections")
	if groups.size()!=1: quit(1); return
	var group: Dictionary=groups[0]
	check(group.columns==["甲方","乙方"],"side order matches actual battle sides")
	check(doc.sections[0]==group,"comparison appears before background context and rosters")
	check(group.rows[0].cells==["12000 人","9000 人"],"current strength is in corresponding side columns")
	check(group.rows.any(func(row): return row.label=="有效士气" and row.cells.size()==2),"morale is directly comparable")
	check(group.rows.any(func(row): return row.label=="下轮有效火力" and row.cells.size()==2),"actual fire is directly comparable")
	check(group.rows.all(func(row): return row.cells.size()==2 and row.value.contains("甲方") and row.value.contains("乙方")),"copyable text includes both side labels and values")
	var panel:=preload("res://scripts/atlas/information_panel.gd").new(); root.add_child(panel)
	panel.position=Vector2(14,14); panel.size=Vector2(560,572); panel.show_document(doc)
	await process_frame; await process_frame
	var table=panel.section_cache["0:"+group.title].get("table")
	check(table!=null,"comparison uses native aligned controls")
	if table==null: panel.queue_free(); quit(1); return
	var controls: Array=table.cells.duplicate(); var builds: int=panel.build_count
	for entry in table.cells:
		check(entry.nodes[0].get_global_rect().position.y==entry.nodes[1].get_global_rect().position.y,"both sides share a row baseline")
		check(is_equal_approx(entry.nodes[0].size.x,entry.nodes[1].size.x),"side columns have equal width")
		check(entry.nodes[1].get_global_rect().end.x<=panel.get_global_rect().end.x,"values stay inside the inspector")
	a.size=11000; a.morale=.3; panel.show_document(Model.document(state,3))
	check(panel.build_count==builds and table.cells[0].nodes[0]==controls[0].nodes[0],"live values update without rebuilding comparison controls")
	check(table.cells[0].nodes[0].text=="11000 人" and table.cells[0].nodes[1].text=="9000 人","refresh updates the correct side cell")
	battle.kind=Battle.Kind.SIEGE; battle.side_b_defends_city=false
	panel.show_document(Model.document(state,3))
	check(panel.section_cache["0:"+group.title].table.headers[1].text=="挑战方","phase changes update side headings")
	root.remove_child(panel); panel.queue_free(); await process_frame
	var view:=View.new(); view.state=state; view.view_ready=true
	root.add_child(view); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.show_information("battle",3)
	for i in range(4): await process_frame
	var wheel:=InputEventMouseButton.new(); wheel.position=view.info_panel.scroll.get_global_rect().get_center()
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed=true; Input.parse_input_event(wheel)
	await process_frame
	wheel=wheel.duplicate(); wheel.pressed=false; Input.parse_input_event(wheel); await process_frame
	var center: Vector2=view.info_panel.close_button.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new(); motion.position=center; Input.parse_input_event(motion); await process_frame
	var target: Control=root.gui_get_hovered_control()
	check(target==view.info_panel.close_button,"compact comparison close is the actual mouse target: %s"%[target.get_path() if target!=null else "none"])
	var event:=InputEventMouseButton.new(); event.position=center; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event)
	for i in range(4): await process_frame
	check(not view.info_panel.visible,"actual close click dismisses compact comparison")
	root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_BATTLE_COMPARISON failures=",failures); quit(1 if failures else 0)
