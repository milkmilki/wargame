extends SceneTree
const FamilyPanel = preload("res://scripts/atlas/family_panel.gd")
const Layout = preload("res://scripts/atlas/family_layout.gd")
class Host extends RefCounted:
	var state: GameState
	var simulation: Simulation
	var historical_view := false
	func information_source() -> GameState: return state
	func show_information(_kind: String,_id: int) -> void: pass
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("FAMILY_PERSON_TYPE_FAIL ",message)
func value(doc: Dictionary,label: String) -> String:
	for group in doc.sections:
		for entry in group.rows:
			if entry.label==label: return str(entry.value)
	return ""
func settle() -> void:
	for i in range(4): await process_frame
func click_person(panel,id: int,name_value: String) -> void:
	panel.inspector.hide(); panel.canvas.show(); await settle()
	panel.canvas.focus_id=-1; panel.canvas.scale_value=1.
	panel.canvas.offset=panel.canvas.size*.5-panel.canvas.layout.positions[id]-Layout.BOX*.5; panel.canvas.queue_redraw()
	await settle()
	var point: Vector2=panel.canvas.get_global_rect().position+panel.canvas.layout.positions[id]+Layout.BOX*.5+panel.canvas.offset
	var motion := InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; Input.parse_input_event(motion); await process_frame
	var event := InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await settle()
	check(panel.inspector.visible and panel.canvas.focus_id==id,"real family-node click opens the selected person's inspector: "+name_value)
	if "--family-person-capture" in OS.get_cmdline_user_args():
		RenderingServer.force_draw(true); root.get_texture().get_image().save_png("res://.dbg/family-person-types/"+name_value+".png")
func run() -> void:
	root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://.dbg/family-person-types")
	var state := preload("res://tests/succession_chain.gd").fixture()
	var nation := state.nations[0]; var king := nation.ruler_person_id; var child := nation.prince_person_ids[0]
	var members: Dictionary=FamilyTree.tree_for_nation(state,0).members
	# Old/current first-ruler records may lack a person profile while Nation has it.
	members[king].erase("archetype"); members[king].erase("traits")
	nation.ruler_archetype=RulerProfile.CONQUEROR; nation.ruler_traits=[RulerProfile.TRAIT_AMBITIOUS]
	members[child].archetype=RulerProfile.MERCHANT; members[child].traits=[RulerProfile.TRAIT_FRUGAL]
	var ancestor: int=FamilyTree.tree_for_nation(state,0).root_person_id
	members[ancestor].erase("archetype")
	var history := PoliticalHistory.new(); history.reset(state)
	var before := var_to_bytes(state.family_trees); var rng := state.rng.state
	var host := Host.new(); host.state=state
	var panel := FamilyPanel.new(); panel.host=host; root.add_child(panel); panel.open(0); await settle()
	await click_person(panel,king,"ruler-1280")
	check(value(panel.inspector.document,"人物类型")==RulerProfile.archetype_name(RulerProfile.CONQUEROR),"current ruler uses the recorded national type")
	check(value(panel.inspector.document,"类型说明")==RulerProfile.archetype_description(RulerProfile.CONQUEROR),"clicked ruler shows the type description")
	await click_person(panel,child,"relative-1280")
	check(value(panel.inspector.document,"人物类型")==RulerProfile.archetype_name(RulerProfile.MERCHANT),"relative keeps his own type instead of the current ruler's")
	check(value(panel.inspector.document,"特质").contains(RulerProfile.trait_name(RulerProfile.TRAIT_FRUGAL)),"relative keeps his own traits")
	await click_person(panel,ancestor,"unknown-1280")
	check(value(panel.inspector.document,"人物类型")=="未记录","unknown ancestors are not silently assigned the balanced type")
	root.size=Vector2i(900,600); await settle(); await click_person(panel,child,"relative-900")
	check(panel.compact and not panel.canvas.visible and value(panel.inspector.document,"人物类型")==RulerProfile.archetype_name(RulerProfile.MERCHANT),"compact click also exposes the selected type")
	check(var_to_bytes(state.family_trees)==before and state.rng.state==rng,"viewing never fills profiles into the live family")
	members[king].archetype=RulerProfile.INEPT; members[king].traits=[]; state.family_revision+=1; panel.refresh_model()
	var stale_before := var_to_bytes(state.family_trees)
	await click_person(panel,king,"current-ruler-stale-900")
	check(value(panel.inspector.document,"人物类型")==RulerProfile.archetype_name(RulerProfile.CONQUEROR),"current ruler's active national profile takes precedence over a stale family entry")
	check(value(panel.inspector.document,"特质").contains(RulerProfile.trait_name(RulerProfile.TRAIT_AMBITIOUS)),"current ruler's traits match his active national profile")
	check(var_to_bytes(state.family_trees)==stale_before and state.rng.state==rng,"resolving a stale display entry cannot rewrite the family")
	nation.ruler_archetype=RulerProfile.GUARDIAN; members[child].archetype=RulerProfile.INEPT; state.family_revision+=1
	host.state=history.build_view_state(state,0); host.historical_view=true; panel.open(0); await settle()
	await click_person(panel,king,"historical-ruler-900")
	check(value(panel.inspector.document,"人物类型")==RulerProfile.archetype_name(RulerProfile.CONQUEROR),"historical first ruler uses his snapshot, not the current type")
	await click_person(panel,child,"historical-relative-900")
	check(value(panel.inspector.document,"人物类型")==RulerProfile.archetype_name(RulerProfile.MERCHANT),"historical relative retains the earlier type")
	panel.queue_free(); await process_frame
	print("ATLAS_FAMILY_PERSON_TYPES failures=",failures); quit(1 if failures else 0)
