extends SceneTree
var failures := 0
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready(): pass
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("BATTLE_INFORMATION_INPUT_FAIL ",message)
func run():
	var view:=View.new(); root.add_child(view); view.set_process(false); view.view_ready=true
	view.state=GameState.new(); view.zoom=2.; view.map_root.scale=Vector2.ONE*2.
	var city:=City.new(); city.id=0; city.name="战场城"; city.map_position=Vector2(.5,.5); city.owner_nation=0
	view.state.cities=[city]
	var nation:=Nation.new(); nation.id=0; nation.name="测试国"; view.state.nations=[nation]
	var a:=Army.new(); a.id=2; a.size=1000; a.owner_nation=0; a.location_city=0
	var b:=Army.new(); b.id=9; b.size=2000; b.owner_nation=0; b.location_city=0
	var battle:=Battle.new(); battle.id=37; battle.city=city; battle.side_a=[a]; battle.side_b=[b]
	view.state.armies=[a,b]; view.state.battles=[battle]
	view.overlay=preload("res://scripts/atlas/military_overlay.gd").new(); view.overlay.state=view.state; view.map_root.add_child(view.overlay)
	view.info_panel=preload("res://scripts/atlas/information_panel.gd").new(); view.add_child(view.info_panel)
	view.info_panel.size=Vector2(372,650); view.info_panel.closed.connect(view.close_information)
	view.info_panel.navigate.connect(view.show_information)
	view.data={"ownership":PackedInt32Array([0])}; view.mode_control.add_item("政治")
	view.province_labels.resize(2048*1024); view.province_labels.fill(-2); view.political_labels=view.province_labels.duplicate()
	var point:=city.map_position*Vector2(2048,1024)+Vector2(0,-25)/view.zoom
	view.select_at(point)
	check(view.information_kind=="battle" and view.information_id==37 and view.info_panel.visible,"clicking the drawn bar opens its battle detail")
	if view.information_kind!="battle":
		root.remove_child(view); view.free(); quit(1); return
	check(view.pick_map(point+Vector2(2048,0)).id==37,"longitude copies use the same battle target")
	check(view.pick_map(point+Vector2(130,0)).kind!="battle","clicks outside drawn bar do not select it")
	var builds: int=view.info_panel.build_count; a.morale=.4; a.size=800
	view.info_panel.show_document(view.information_document())
	check(view.info_panel.build_count==builds,"live casualty and morale updates reuse controls")
	var rng_before: int=view.state.rng.state
	var original_state: GameState=view.state
	view.state.battles.clear(); view.info_panel.show_document(view.information_document())
	check(view.info_panel.document.notice.contains("已结束") and view.info_panel.document.notice.contains("最后"),"removed battle retains an explicitly dated final observed snapshot")
	check(view.pick_map(point).kind!="battle","ended battles lose their map hit target")
	view.historical_view=true; view.overlay.state=GameState.new()
	check(view.information_document().notice.contains("未记录"),"political history cannot display live combat data")
	view.historical_view=false; view.state=GameState.new()
	check(view.information_document().is_empty(),"a new world never reuses an old battle snapshot")
	view.info_panel.close_button.pressed.emit()
	check(not view.info_panel.visible and view.information_kind.is_empty(),"close returns to map")
	check(original_state.rng.state==rng_before,"inspection and closure do not consume simulation RNG")
	root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_BATTLE_INFORMATION_INTERACTION failures=",failures); quit(1 if failures else 0)
