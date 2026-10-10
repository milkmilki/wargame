extends SceneTree
var failures := 0
class ProbeSimulation extends Simulation:
	func _advance_day(_spread: bool = false) -> void:
		state.day += 1
		await get_tree().process_frame
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready() -> void: make_ui()
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_TIME_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var view := View.new(); root.add_child(view)
	view.simulation=ProbeSimulation.new(); view.simulation.state=GameState.new(); view.simulation.paused=true; view.add_child(view.simulation)
	view.view_ready=true
	if not view.has_method("set_time_speed"):
		check(false,"常驻时间控制尚未接入"); root.remove_child(view); view.queue_free(); await process_frame; quit(1); return
	for row in view.interface.speed_buttons:
		row.node.pressed.emit(); check(view.simulation.speed_multiplier()==row.multiplier,"each shortcut button requests its own multiplier")
	view.set_time_speed(100.); check(view.simulation.speed_multiplier()==32.,"upper multiplier clamp")
	view.set_time_speed(.01); check(view.simulation.speed_multiplier()==.25,"lower multiplier clamp")
	view.set_time_speed(4.); view.toggle_pause(); check(not view.simulation.paused,"pause control resumes")
	view.step_day(); check(view.simulation.state.day==0,"single step cannot run during continuous play")
	view.toggle_pause(); view.step_day(); view.step_day()
	check(view.simulation.state.day==1 and view.simulation.runtime_day_in_progress(),"duplicate actions cannot overlap day advancement")
	await process_frame; await process_frame
	check(not view.simulation.runtime_day_in_progress(),"day commit releases the pending guard")
	view.historical_view=true; view.set_time_speed(8.); view.toggle_pause(); view.step_day()
	check(view.simulation.paused and view.simulation.speed_multiplier()==4. and view.simulation.state.day==1,"history disables direct stale actions")
	view.historical_view=false
	var key := InputEventKey.new(); key.keycode=KEY_BRACKETRIGHT; key.pressed=true
	view._unhandled_input(key); check(view.simulation.speed_multiplier()==8.,"bracket keyboard multiplier")
	view.player_nation.get_line_edit().grab_focus(); key.keycode=KEY_MINUS; view._unhandled_input(key)
	check(view.simulation.speed_multiplier()==8.,"editing a spin box never changes speed")
	view.player_nation.get_line_edit().release_focus()
	view.interface.speed_buttons[0].node.grab_focus(); key.keycode=KEY_KP_ADD; view._unhandled_input(key)
	check(view.simulation.speed_multiplier()==16.,"non-editing button focus does not disable speed shortcuts")
	key.keycode=KEY_SPACE; view._unhandled_input(key)
	check(view.simulation.paused,"Space belongs to a focused button")
	view.interface.speed_buttons[0].node.release_focus()
	view.generating=true; view.toggle_pause(); view.set_time_speed(2.)
	check(view.simulation.paused and view.simulation.speed_multiplier()==16.,"generation disables timeline actions")
	root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_TIME_CONTROLS failures=",failures); quit(1 if failures else 0)
