extends SceneTree
const Fixture=preload("res://tests/succession_chain.gd")
const FamilyPanel=preload("res://scripts/atlas/family_panel.gd")
const Model=preload("res://scripts/atlas/family_model.gd")
const Info=preload("res://scripts/atlas/information_model.gd")
class Host extends RefCounted:
	var state: GameState; var simulation: Simulation; var historical_view:=false
	func information_source() -> GameState: return state
	func show_information(_kind: String,_id: int) -> void: pass
var failures: Array[String]=[]
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func setup() -> Dictionary:
	var state: GameState=Fixture.fixture(); var n:=state.nations[0]; var challenger:=n.prince_person_ids[1]
	PrincePolitics.person(state,0,challenger).archetype=RulerProfile.CONQUEROR
	var a:=state.create_army(0,1,15000); a.political_person_id=challenger
	var b:=state.create_army(0,0,3000); b.political_person_id=n.crown_prince_person_id
	var sim:=Simulation.new(); root.add_child(sim); sim.setup(state); sim.paused=true; sim.set_process(false)
	SuccessionRules.begin_preparation(state,0,challenger)
	return {"state":state,"sim":sim}
func run() -> void:
	root.size=Vector2i(1280,720)
	var a:=setup(); var b:=setup()
	var host:=Host.new(); host.state=b.state; host.simulation=b.sim
	var panel:=FamilyPanel.new(); panel.host=host; root.add_child(panel); panel.open(0)
	for i in range(60):
		a.sim._advance_day(false)
		b.sim._runtime_day_in_progress=true
		await b.sim._advance_runtime_day()
		panel.refresh_model()
		check(NativeSnapshotBuilder.build(a.state)==NativeSnapshotBuilder.build(b.state),"sync_sliced_open_ui_%d"%i)
	var results: Array=a.state.succession_events.filter(func(e): return e.event=="finish")
	check(not results.is_empty() and int(results[0].details.outcome)==SuccessionConflict.Outcome.CROWN_CHANGED,"full_day_cleanup_cannot_suppress_copies")
	var layouts: int=panel.canvas.layout_count
	panel.canvas.offset+=Vector2(100,20); panel.canvas.scale_value*=1.2; panel.canvas.queue_redraw()
	await process_frame
	check(panel.canvas.layout_count==layouts,"pan_zoom_no_layout")
	var history:=PoliticalHistory.new(); history.reset(b.state)
	var historic:=history.build_view_state(b.state,0)
	var before:=Model.capture(historic,0)
	PrincePolitics.person(b.state,0,b.state.nations[0].ruler_person_id).name="未来修改"
	check(Model.capture(historic,0)==before,"historical_no_current_leak")
	var history_case := setup()
	var private_history := PoliticalHistory.new(); private_history.reset(history_case.state)
	var private_past := private_history.build_view_state(history_case.state,0)
	var frozen_report := Info.prince_report(private_past,0).duplicate(true)
	var frozen_doc := Info.historical(Info.nation(private_past,0),"nation")
	check(frozen_doc.sections.any(func(group): return group.title=="继承与王爵"),"historical_card_includes_recorded_private_progress")
	var active: SuccessionConflict = history_case.state.succession_conflicts[0]
	history_case.state.day+=1; SuccessionRules.advance(history_case.state,active)
	check(Info.prince_report(private_past,0)==frozen_report and Info.historical(Info.nation(private_past,0),"nation")==frozen_doc,"historical_private_round_cannot_leak_current_progress")
	history_case.sim.queue_free()
	panel.close(); var draws: int=panel.canvas.draw_count
	for i in range(3): await process_frame
	check(panel.canvas.draw_count==draws and panel.canvas.layout_count==layouts,"closed_no_work")
	panel.queue_free(); a.sim.queue_free(); b.sim.queue_free(); await process_frame
	for failure in failures: push_error("ATLAS_FAMILY_RUNTIME_FAIL: "+failure)
	print("ATLAS_FAMILY_RUNTIME: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
