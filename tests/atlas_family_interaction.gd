extends SceneTree
const Fixture = preload("res://tests/succession_chain.gd")
const FamilyPanel = preload("res://scripts/atlas/family_panel.gd")
const Model = preload("res://scripts/atlas/family_model.gd")
class Host extends RefCounted:
	var state: GameState
	var simulation: Simulation
	var historical_view := false
	var navigation: Array = []
	func information_source() -> GameState: return state
	func show_information(kind: String, id: int) -> void: navigation.append([kind,id])
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if not ok: failures.append(label)
func settle():
	for frame in range(4): await process_frame
func run():
	root.size = Vector2i(1280,720)
	var host := Host.new(); host.state = Fixture.fixture()
	# Presentation-only shared-family fixture; no territorial/political writes
	# are exercised here (those have separate real-transaction regressions).
	var first := host.state.nations[0]; var second := Nation.new()
	second.id=1; second.name="同族支系"; host.state.nations.append(second)
	second.family_tree_id = first.family_tree_id
	second.ruler_person_id = first.prince_person_ids[1]
	second.ruler_name = PrincePolitics.person(host.state,0,second.ruler_person_id).name
	var members: Dictionary = FamilyTree.tree_for_nation(host.state,0).members
	var same_names: Array[int] = [first.ruler_person_id,second.ruler_person_id]
	for id in same_names: members[id].name = "同名人物"
	var before := var_to_bytes(host.state.family_trees)
	var revision := host.state.family_revision; var rng := host.state.rng.state
	host.simulation = Simulation.new()
	host.simulation.paused = false; host.simulation.set_process(false)
	var panel := FamilyPanel.new(); panel.host = host; root.add_child(panel)
	panel.open(0); await settle()
	check(not host.simulation.paused,"opening preserves running state")
	check(panel.model.countries.size()==2 and panel.model.members.size()==members.size(),"shared family shown once across countries")
	check(panel.model.members[second.ruler_person_id].active_ruler and panel.canvas.person_marker(second.ruler_person_id,panel.model.members[second.ruler_person_id])=="在位","another living same-family ruler is marked in office instead of former ruler")
	var layouts := panel.canvas.layout_count
	panel.open(1); await settle()
	check(panel.model.current==second.ruler_person_id and panel.canvas.layout_count==layouts,"same family country switch changes highlight without layout")
	panel.search.text="同名人物"; panel.search_next(); var found := panel.canvas.focus_id
	panel.search_next()
	check(found!=panel.canvas.focus_id and same_names.has(found) and same_names.has(panel.canvas.focus_id),"duplicate names cycle deterministically")
	panel.search.text=str(first.ruler_person_id); panel.search_next()
	check(panel.canvas.focus_id==first.ruler_person_id,"numeric search locates person")
	panel.inspector.navigate.emit("person",second.ruler_person_id)
	check(panel.canvas.focus_id==second.ruler_person_id and host.navigation.is_empty(),"person links do not select map nation")
	root.size=Vector2i(900,600); await settle()
	check(panel.compact and panel.selector.visible and not panel.side.visible,"compact window has country selector")
	check(panel.size.x<=900 and panel.size.y<=600,"compact panel fits viewport")
	panel.inspector.navigate.emit("nation",1)
	check(not panel.visible and host.navigation==[["nation",1]],"explicit country link navigates and closes family panel: visible=%s navigation=%s"%[panel.visible,host.navigation])
	check(var_to_bytes(host.state.family_trees)==before and host.state.family_revision==revision and host.state.rng.state==rng,"all viewing interactions are read only")
	check(not host.simulation.paused,"closing preserves running state")
	panel.queue_free(); host.simulation.free(); await process_frame
	for failure in failures: push_error(failure)
	print("ATLAS_FAMILY_INTERACTION: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
