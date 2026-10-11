extends SceneTree
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready(): make_ui()
var failures:=0
var activations:=0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_SPACE_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var view:=View.new(); root.add_child(view)
	view.simulation=Simulation.new(); view.simulation.state=GameState.new(); view.simulation.paused=true; view.view_ready=true
	var key:=InputEventKey.new(); key.keycode=KEY_SPACE; key.pressed=true
	var button: Button=view.interface.speed_buttons[0].node
	button.pressed.connect(func(): activations+=1)
	button.grab_focus(); root.push_input(key,true)
	check(not view.simulation.paused and activations==0,"real GUI event toggles timeline without activating focused button")
	key.pressed=false; root.push_input(key,true)
	check(activations==0,"Space release cannot activate a button")
	view.simulation.paused=true
	view.mode_control.grab_focus(); key.pressed=true; root.push_input(key,true)
	check(not view.simulation.paused and not view.mode_control.get_popup().visible,"Space cannot open dropdown")
	view.simulation.paused=true
	var popup:=view.mode_control.get_popup(); popup.popup(); await process_frame
	popup.push_input(key,true)
	check(not view.simulation.paused and view.mode_control.selected==0,"already-open popup routes Space to pause without choosing an item")
	key.pressed=false; popup.push_input(key,true); popup.hide()
	view.generating=true; view.simulation.paused=true; button.grab_focus()
	key.pressed=true; root.push_input(key,true)
	check(view.simulation.paused and activations==0,"disabled timeline still consumes Space")
	view.simulation.free(); root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_SPACE_ROUTING failures=",failures); quit(1 if failures else 0)
