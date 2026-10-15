extends SceneTree
const Model = preload("res://scripts/atlas/family_model.gd")
const Layout = preload("res://scripts/atlas/family_layout.gd")
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
const FamilyPanel = preload("res://scripts/atlas/family_panel.gd")
const Canvas = preload("res://scripts/atlas/family_canvas.gd")
class Host extends RefCounted:
	var state: GameState
	var simulation: Simulation
	var historical_view := false
	func information_source() -> GameState: return state
	func show_information(_kind: String,_id: int) -> void: pass
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func run() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(73003, false)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.NEUTRAL)
	FamilyFixture.ensure_candidates(state,0,3)
	state.region_ids.fill(-1)
	for city in state.land_cities_of(0): state.region_ids[city.id] = 10
	EmpireStatus.reconcile(state)
	var nation := state.nations[0]
	var members: Dictionary = FamilyTree.tree_for_nation(state,0).members
	var candidate := PrincePolitics.enfeoff_candidate(state,0)
	var first := Model.capture(state,0)
	check(first.members[candidate].get("title_steps",[]).size() == 1,"princely grant is a recorded initial identity")
	var history := PoliticalHistory.new(); history.reset(state)
	var subject := -1
	state.day = 30
	for center in state.administrative_center_city_ids:
		if state.cities[center].owner_nation == 0 and center != nation.capital_city_id:
			subject = state.enfeoff(0,[center])
			if subject >= 0: break
	check(subject >= 0 and state.nations[subject].ruler_person_id == candidate,"real enfeoffment reuses the titled prince")
	if subject >= 0:
		state.day = 60
		check(state.revoke_vassal(subject),"real peaceful recall succeeds")
		var entries: Array = members[candidate].get("identity_history",[])
		check(entries.size() == 3,"prince to vassal to prince preserves all three stages: "+JSON.stringify(entries))
		if entries.size() == 3:
			check(entries[0].kind == "noble" and entries[0].rank == 3 and entries[1].kind == "vassal" and entries[2].rank == 3,"actual office and virtual rank remain distinct")
			check(entries[0].end_day == 30 and entries[1].start_day == 30 and entries[1].end_day == 60 and entries[2].start_day == 60,"transition dates reflect the successful transactions")
		var captured := Model.capture(state,0)
		check(captured.members[candidate].get("title_steps",[]).size() == 3,"tree exposes the repeated title instead of deduplicating it")
		check(Model.capture(history.build_view_state(state,0),0).members[candidate].get("title_steps",[]).size() == 1,"past genealogy cannot borrow later titles")
	var before := var_to_bytes(state.family_trees); var rng := state.rng.state
	var model := Model.capture(state,0)
	var surname := FamilyTree.surname_for_nation(state,0)
	check(model.members[nation.ruler_person_id].get("tree_name","") == nation.ruler_name.trim_prefix(surname),"tree omits only its own known surname")
	check(Model.person_document(model,nation.ruler_person_id).title == nation.ruler_name,"details retain full name")
	check(model.members[nation.ruler_person_id].was_emperor,"imperial recognition marks the actual emperor")
	FamilyTree.record_current_title(state,0)
	check(var_to_bytes(state.family_trees) == before and state.rng.state == rng,"repeated recording and viewing are idempotent and random-free")
	# A legacy unordered titles list is not evidence for a chronological cycle.
	var legacy: Dictionary = members[candidate].duplicate(true); legacy.erase("identity_history")
	var isolated := state.family_trees.duplicate(true)
	state.family_trees[nation.family_tree_id].members[candidate] = legacy
	var legacy_model := Model.capture(state,0)
	check(legacy_model.members[candidate].get("history_partial",false),"incomplete old office history is explicitly marked")
	state.family_trees = isolated
	var snapshot := NativeSnapshotBuilder.build(state)
	check(NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(),"identity ledger is captured and validated")
	var broken := snapshot.duplicate(true)
	for tree in broken.family_trees:
		for member in tree.members:
			if int(member.id)==candidate: member.identity_history[1].nation_id=999999
	check(not NativeSnapshotBuilder.succession_validation_error(broken).is_empty(),"snapshot rejects a broken historical country reference")
	var stress := {"root":0,"members":{}}
	for id in range(40):
		stress.members[id] = {"parent_id":(id-1)/3 if id>0 else -1,"birth_order":id,"title_steps":[{"title":"琅琊王","label":"藩王"}] if id%3 else Array()}
	stress.members[1].title_steps = []
	for i in range(12): stress.members[1].title_steps.append({"title":"琅琊王","label":"亲王"})
	var geometry := Layout.build(stress)
	check(geometry.get("rects",{}).size() == 40,"variable vertical boxes cover every person")
	if geometry.has("rects"):
		check(geometry.rects[1].size.y > geometry.rects[2].size.y,"long title trajectories expand without truncation")
		for id in stress.members:
			var parent := int(geometry.parents[id])
			if parent >= 0: check(geometry.rects[id].position.y > geometry.rects[parent].end.y,"generation links clear the full title trajectory")
	await test_canvas(stress)
	await test_panel(state,candidate)
	var emperor := nation.ruler_person_id
	state.day=90
	check(PrincePolitics.accede(state,0),"real imperial succession completes")
	var final_model:=Model.capture(state,0)
	check(final_model.members[emperor].was_emperor and not final_model.members[emperor].alive,"the deceased emperor keeps his imperial marker")
	check(final_model.members[emperor].identity_history.back().end_day==90 and final_model.members[emperor].identity_history.back().end_reason=="death","actual death closes the former emperor's reign")
	check(final_model.members[nation.ruler_person_id].was_emperor,"the actual successor receives the imperial marker")
	for failure in failures: push_error("FAMILY_GENEALOGY_FAIL: " + failure)
	print("FAMILY_GENEALOGY checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func settle() -> void:
	for i in range(4): await process_frame

func test_canvas(stress: Dictionary) -> void:
	var canvas := Canvas.new(); canvas.size=Vector2(500,400); canvas.clip_contents=true; root.add_child(canvas)
	stress["current"]=-1
	canvas.update_model(stress)
	var rect: Rect2=canvas.layout.rects[1]
	# Only the bottom of a long trajectory is in view; its name cell is offscreen.
	canvas.offset=-rect.position-Vector2(0,rect.size.y-200)
	check(canvas.visible_ids().has(1),"culling retains the visible bottom of a tall trajectory")
	check(canvas.visible_ids().count(1)==1,"multi-cell indexing never draws the same person twice")
	var point:=Vector2(50,100)
	var press:=InputEventMouseButton.new(); press.position=point; press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true
	canvas._gui_input(press); var release: InputEventMouseButton=press.duplicate(); release.pressed=false; canvas._gui_input(release)
	check(canvas.focus_id==1,"the full tall title history remains clickable")
	var count: int=canvas.layout_count
	canvas.offset+=Vector2(20,30); canvas.queue_redraw(); await process_frame
	check(canvas.layout_count==count,"dragging only redraws the cached genealogy")
	var expanded: Dictionary=stress.duplicate(true)
	expanded.members[2].title_steps.append({"title":"晋王","label":"亲王"})
	canvas.update_model(expanded)
	check(canvas.layout_count==count+1,"new title stages invalidate geometry even when ancestry is unchanged")
	canvas.queue_free(); await process_frame

func test_panel(state: GameState, candidate: int) -> void:
	var host:=Host.new(); host.state=state
	root.size=Vector2i(1280,720)
	var panel:=FamilyPanel.new(); panel.host=host; root.add_child(panel); panel.open(0,candidate)
	await settle()
	check(panel.model.members[candidate].title_steps.size()==3 and panel.canvas.focus_id==candidate,"panel opens the actual three-stage person")
	await capture("1280-person")
	panel.inspector.hide(); panel.canvas.show(); panel.canvas.fit_all(); await settle()
	await capture("1280-overview")
	panel.canvas.locate(state.nations[0].ruler_person_id); panel.inspector.hide(); panel.canvas.show(); await settle()
	await capture("1280-emperor")
	root.size=Vector2i(900,600); await settle()
	panel.canvas.locate(candidate); panel.inspector.hide(); panel.canvas.show(); await settle()
	check(panel.canvas.get_global_rect().end.x<=900 and panel.canvas.get_global_rect().end.y<=600,"vertical tree fits the compact viewport")
	await capture("900-tree")
	panel.canvas.selected.emit(candidate); await settle()
	check(panel.inspector.visible and not panel.canvas.visible,"compact click opens full dated title details")
	await capture("900-person")
	panel.queue_free(); await process_frame

func capture(label: String) -> void:
	if "--genealogy-capture" not in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute("res://.dbg/genealogy")
	await settle(); RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png("res://.dbg/genealogy/"+label+".png")
