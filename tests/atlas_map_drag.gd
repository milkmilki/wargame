extends SceneTree
class View extends "res://scripts/atlas/military_preview.gd":
	var selections: Array[Vector2]=[]
	func _ready() -> void: make_ui(); set_process(false); add_child(map_root)
	func select_at(point: Vector2) -> void: selections.append(point)
	func schedule_symbols() -> void: pass
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("MAP_DRAG_FAIL ",message)
func _initialize() -> void: call_deferred("run")
func mouse(point: Vector2,pressed: bool,button: MouseButton=MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=button; event.pressed=pressed
	Input.parse_input_event(event); await process_frame; await process_frame
func move(point: Vector2,relative: Vector2,mask: int=0) -> void:
	var event := InputEventMouseMotion.new(); event.position=point; event.global_position=point; event.relative=relative; event.button_mask=mask
	Input.parse_input_event(event); await process_frame; await process_frame
func run() -> void:
	root.size=Vector2i(1280,720)
	var view := View.new(); root.add_child(view); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.view_ready=true; view.zoom=2.; view.map_root.scale=Vector2.ONE*2.; view.map_root.position=Vector2(-1000,-200)
	await process_frame; await process_frame
	var point := Vector2(600,250); var before := view.map_root.position
	await move(point,Vector2.ZERO); await mouse(point,true)
	check(view.selections.is_empty(),"left press waits to distinguish a click from a drag")
	await move(point+Vector2(2,1),Vector2(2,1),MOUSE_BUTTON_MASK_LEFT); await mouse(point+Vector2(2,1),false)
	check(view.selections.size()==1 and view.map_root.position==before,"small hand jitter remains a single map click")
	view.selections.clear(); await mouse(point,true)
	await move(point+Vector2(40,20),Vector2(40,20),MOUSE_BUTTON_MASK_LEFT)
	check(view.dragging and view.map_root.position==before+Vector2(40,20),"left drag pans by the full pointer displacement")
	await mouse(point+Vector2(40,20),false)
	check(not view.dragging and view.selections.is_empty(),"drag release never selects the map underneath")
	# A map gesture remains captured over HUD controls and terminates there.
	await mouse(point,true); var toolbar_point: Vector2=view.interface.toolbar.get_global_rect().get_center()
	await move(toolbar_point,toolbar_point-point,MOUSE_BUTTON_MASK_LEFT); await mouse(toolbar_point,false)
	before=view.map_root.position; await move(point,point-toolbar_point)
	check(not view.dragging and view.map_root.position==before and view.selections.is_empty(),"release over UI cannot leave the camera stuck or trigger a map click")
	# Starting inside the timeline must never start a map gesture.
	point=view.history_control.get_global_rect().get_center(); before=view.map_root.position
	await move(point,Vector2.ZERO); await mouse(point,true)
	await move(point+Vector2(40,0),Vector2(40,0),MOUSE_BUTTON_MASK_LEFT); await mouse(point+Vector2(40,0),false)
	check(view.map_root.position==before and view.selections.is_empty(),"dragging timeline controls does not pan or select the map")
	point=Vector2(600,250); before=view.map_root.position
	await move(point,Vector2.ZERO); await mouse(point,true,MOUSE_BUTTON_MIDDLE)
	await move(point+Vector2(-25,5),Vector2(-25,5),MOUSE_BUTTON_MASK_MIDDLE); await mouse(point+Vector2(-25,5),false,MOUSE_BUTTON_MIDDLE)
	check(view.map_root.position==before+Vector2(-25,5) and not view.dragging,"middle-button panning remains available")
	view.queue_free(); await process_frame
	print("ATLAS_MAP_DRAG failures=",failures); quit(1 if failures else 0)
