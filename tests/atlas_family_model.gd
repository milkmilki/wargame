extends SceneTree
const Fixture = preload("res://tests/succession_chain.gd")
const Model = preload("res://scripts/atlas/family_model.gd")
const Layout = preload("res://scripts/atlas/family_layout.gd")
const FamilyPanel = preload("res://scripts/atlas/family_panel.gd")
var failures: Array[String]=[]
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func run() -> void:
	var state: GameState=Fixture.fixture()
	var before := var_to_bytes(state.family_trees); var rng := state.rng.state; var revision:=state.family_revision
	var model := Model.capture(state,0)
	var layout := Layout.build(model)
	check(layout.positions.size()==model.members.size(),"all_members_once")
	for id in model.members: check(not Model.person_document(model,id).is_empty(),"person_document_%d"%id)
	check(var_to_bytes(state.family_trees)==before and state.rng.state==rng and state.family_revision==revision,"read_only")
	var stress := {"members":{},"root":0}
	for id in range(5000): stress.members[id]={"parent_id":id-200 if id>=200 else -1,"birth_order":id%200,"last_reign":id}
	var started:=Time.get_ticks_usec(); var large:=Layout.build(stress)
	check(large.positions.size()==5000,"5000_people_25_generations")
	var by_row: Dictionary={}
	for id in large.positions:
		var point: Vector2=large.positions[id]
		if not by_row.has(point.y): by_row[point.y]=[]
		by_row[point.y].append(point.x)
	for row in by_row.values():
		row.sort()
		for i in range(1,row.size()): check(row[i]-row[i-1]>=Layout.BOX.x,"no_subtree_overlap")
	print("ATLAS_FAMILY_MODEL: %d failures; large layout %.2fms"%[failures.size(),(Time.get_ticks_usec()-started)/1000.])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
