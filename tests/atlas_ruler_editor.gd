extends SceneTree
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready(): make_ui()
var failures:=0
func check(ok: bool,message: String):
	if not ok: failures+=1;printerr("RULER_EDITOR_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	if not FileAccess.file_exists("res://scripts/atlas/ruler_editor.gd"):
		check(false,"nation card has editable ruler dropdowns");quit(1);return
	var state:=preload("res://tests/support/grid_world.gd").new();state.generate_world(77301,3,8)
	var sim:=Simulation.new();sim.setup(state);sim.paused=true
	var view:=View.new();root.add_child(view);view.state=state;view.simulation=sim;view.view_ready=true
	view.information_kind="nation";view.information_id=0
	view.info_panel.show_document(view.information_document())
	var editor
	for group in view.info_panel.section_cache.values():
		if group.has("editor"):editor=group.editor
	check(editor!=null,"ruler controls appear inside the shared information panel")
	if editor==null: sim.free();view.queue_free();quit(1);return
	var nation:=state.nations[0];var identity: Array=[nation.ruler_name,nation.ruler_person_id,nation.ruler_revision,nation.ruler_started_day,state.rng.state]
	var builds: int=view.info_panel.build_count
	editor.archetype.get_popup().index_pressed.emit(editor.archetype.get_item_index(RulerProfile.CONQUEROR))
	check(nation.ruler_archetype==RulerProfile.CONQUEROR,"dropdown changes actual ruler through the simulation")
	check([nation.ruler_name,nation.ruler_person_id,nation.ruler_revision,nation.ruler_started_day,state.rng.state]==identity,"editing preserves person, reign and random stream")
	var tree:=FamilyTree.tree_for_nation(state,0)
	check(tree.members[nation.ruler_person_id].archetype==nation.ruler_archetype,"current family person agrees with national ruler")
	for army in state.armies:
		if army.owner_nation==0:check(is_equal_approx(army.ruler_attack_multiplier,RulerProfile.attack_multiplier(nation)),"existing army receives edited ruler combat multiplier")
	editor.traits[0].select(1+RulerProfile.TRAIT_IDS.find(RulerProfile.TRAIT_DILIGENT));editor.traits[0].item_selected.emit(editor.traits[0].selected)
	check(nation.ruler_traits.has(RulerProfile.TRAIT_DILIGENT),"trait dropdown changes actual modifiers")
	check(editor.traits[1].is_item_disabled(1+RulerProfile.TRAIT_IDS.find(RulerProfile.TRAIT_DILIGENT)),"duplicate trait cannot be selected")
	editor.traits[0].select(1+RulerProfile.TRAIT_IDS.find(RulerProfile.TRAIT_CENTRALIZER));editor.traits[0].item_selected.emit(editor.traits[0].selected)
	check(editor.traits[1].is_item_disabled(1+RulerProfile.TRAIT_IDS.find(RulerProfile.TRAIT_FEUDALIST)),"centralizer and feudalist remain mutually exclusive")
	for control in editor.traits:
		control.select(0);control.item_selected.emit(0)
	check(nation.ruler_traits.is_empty(),"both empty slots remove extra traits")
	check(view.info_panel.build_count==builds,"edits reuse existing inspector controls")
	sim._runtime_day_in_progress=true;view.info_panel.show_document(view.information_document())
	check(editor.archetype.disabled and editor.traits[0].disabled,"in-progress day disables all ruler controls")
	check(not view.edit_ruler(0,RulerProfile.MERCHANT,[]),"in-progress day refuses a stale popup event")
	sim._runtime_day_in_progress=false
	view.historical_view=true
	check(not view.edit_ruler(0,RulerProfile.MERCHANT,[]),"history cannot modify current ruler")
	view.historical_view=false;view.generating=true
	check(not view.edit_ruler(0,RulerProfile.MERCHANT,[]),"generation blocks stale editing")
	view.generating=false
	view.info_panel.show_document(view.information_document())
	for group in view.info_panel.section_cache.values():
		if group.has("editor"):editor=group.editor
	var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=true
	var popup: PopupMenu=editor.archetype.get_popup();popup.popup();await process_frame;popup.push_input(key,true)
	check(not sim.paused and nation.ruler_archetype==RulerProfile.CONQUEROR,"Space in ruler dropdown only toggles pause")
	popup.hide();sim.paused=true
	view.information_id=1;view.info_panel.show_document(view.information_document())
	check(editor.nation_id==1,"reused editor targets newly selected nation")
	editor.archetype.select(editor.archetype.get_item_index(RulerProfile.MERCHANT));editor.archetype.item_selected.emit(editor.archetype.selected)
	check(state.nations[1].ruler_archetype==RulerProfile.MERCHANT and nation.ruler_archetype==RulerProfile.CONQUEROR,"switching cards never edits the old nation")
	check(not view.edit_ruler(0,RulerProfile.MERCHANT,[]),"a stale previous-card request is rejected")
	sim.free();root.remove_child(view);view.queue_free();await process_frame
	print("RULER_EDITOR_RESULT failures=",failures);quit(1 if failures else 0)
