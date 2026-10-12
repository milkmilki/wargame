extends SceneTree
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready(): make_ui(); set_process(false)
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("FAMILY_CLOSE_INPUT_FAIL ",message)
func settle():
	for i in range(4): await process_frame
func run():
	root.size=Vector2i(1280,720)
	var view:=View.new(); view.state=preload("res://tests/succession_chain.gd").fixture()
	view.simulation=Simulation.new(); view.simulation.state=view.state; view.simulation.paused=true
	view.view_ready=true; root.add_child(view); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng_before: int=view.state.rng.state; var day_before: int=view.state.day
	for dimensions in [Vector2i(1280,720),Vector2i(900,600)]:
		root.size=dimensions; view.family_panel.open(0); await settle()
		var button: Button=view.family_panel.get_child(0).get_child(0).get_child(1)
		var center:=button.get_global_rect().get_center()
		var motion:=InputEventMouseMotion.new(); motion.position=center; Input.parse_input_event(motion); await process_frame
		var event:=InputEventMouseButton.new(); event.position=center; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
		Input.parse_input_event(event); await process_frame
		event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await settle()
		check(not view.family_panel.visible,"actual mouse click closes family panel at %s; target=%s"%[dimensions,get_root().gui_get_hovered_control()])
		check(view.simulation.paused and view.state.day==day_before,"close click does not reach underlying timeline")
		view.family_panel.close()
	check(view.state.rng.state==rng_before,"closing changes no simulation RNG")
	root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_FAMILY_CLOSE_INPUT failures=",failures); quit(1 if failures else 0)
