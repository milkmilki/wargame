extends SceneTree
const Mask = preload("res://scripts/atlas/settlement_mask.gd")
var failures := 0
class View extends "res://scripts/atlas/military_preview.gd":
	var requests := 0
	var fail_generation := false
	func _ready() -> void: make_ui()
	func load_native(_seed_value: int) -> void:
		requests+=1
		if not fail_generation: data={"options":native_generation_options()}
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("ATLAS_MASK_CONTROLS_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var scene := (load("res://atlas_military.tscn") as PackedScene).instantiate()
	check(scene.settlement_mask==Mask.EURASIA,"formal scene uses the user-selected Eurasia rectangle")
	scene.free()
	var view := View.new(); root.add_child(view)
	var controls=view.mask_controls
	check(not controls.enabled.button_pressed,"missing template configuration remains global")
	controls.enabled.button_pressed=true; controls.fields.south.value=20.; controls.fields.north.value=55.
	await controls.apply_settings()
	check(view.requests==1 and view.settlement_mask==Mask.EURASIA,"apply forwards normalized generation options")
	view.historical_view=true; await controls.apply_settings()
	check(view.requests==1,"history cannot start generation through stale callbacks")
	view.historical_view=false; view.generating=true; await controls.apply_settings()
	check(view.requests==1,"generation cannot reenter")
	view.generating=false; controls.fields.south.value=60.; await controls.apply_settings()
	check(view.requests==1 and not view.status.text.is_empty(),"invalid bounds rejected before generation")
	controls.fields.south.value=20.; controls.fields.west.value=0.; view.fail_generation=true
	await controls.apply_settings()
	check(view.requests==2 and view.settlement_mask==Mask.EURASIA and controls.fields.west.value==-15.,"failed generation restores the previous world's policy")
	view.fail_generation=false; controls.enabled.button_pressed=false; await controls.apply_settings()
	check(view.requests==3 and not view.settlement_mask.enabled,"switching the mask off restores global generation")
	view.data={"options":{}}; view.sync_settlement_mask()
	check(view.settlement_mask.is_empty() and not controls.enabled.button_pressed,"old unmasked imports reset controls")
	for viewport in [Vector2i(1280,720),Vector2i(900,600)]:
		root.size=viewport; view.size=viewport; view.interface.tools.show(); view.interface.place()
		await process_frame; await process_frame
		check(view.interface.tools.position.x>=0 and view.interface.tools.position.x+view.interface.tools.size.x<=viewport.x,"tool panel fits window width %s"%viewport)
	view.free(); await process_frame
	print("ATLAS_SETTLEMENT_MASK_CONTROLS failures=",failures); quit(1 if failures else 0)
