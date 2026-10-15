extends SceneTree

var failures := 0
class ProbeSimulation extends Simulation:
	func _advance_day(_spread: bool = false) -> void:
		state.day += 1
		await get_tree().process_frame
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready() -> void: make_ui()
	func _process(_delta: float) -> void: pass
	func refresh_ownership() -> void: pass
	func refresh_diplomacy() -> void: pass
	func update_mode() -> void: pass

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; printerr("HISTORY_TIMELINE_FAIL ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var view := View.new(); root.add_child(view); view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame; await process_frame
	var timeline: Control=view.interface.history_timeline
	check(timeline.first_date.text=="开局 · 1年1天","opening date uses year and day")
	check(not view.interface.footer.is_ancestor_of(timeline),"history occupies an independent bottom bar")
	check(absf(timeline.get_global_rect().get_center().x-640.)<1.,"history bar is horizontally centered")
	check(view.interface.footer.get_global_rect().end.y<timeline.get_global_rect().position.y,"status capsule stays above the independent bar")
	if not view.history_control.is_class("HSlider") or not view.has_method("select_history"):
		check(false,"a visible draggable history timeline must replace the hidden snapshot number picker")
		view.queue_free(); await process_frame; quit(1); return
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(12345)
	view.state=state; view.view_ready=true
	view.simulation=ProbeSimulation.new(); view.simulation.state=state; view.simulation.paused=true; view.add_child(view.simulation)
	view.simulation.runtime_day_committed.connect(view.capture_history)
	view.overlay=view.Overlay.new(); view.overlay.state=state; view.overlay.hide(); view.add_child(view.overlay)
	view.data={"cities":[],"ownership":PackedInt32Array(),"nations":[]}; view.display={}
	view.history.reset(state)
	var owner := state.cities[0].owner_nation
	state.day=29
	view.simulation.advance_one_day()
	check(view.history.snapshot_count()==1,"an unfinished day cannot publish a history point")
	await process_frame; await process_frame
	check(view.history.snapshot_days()==PackedInt32Array([0,30]),"monthly capture runs on the simulation commit even without a map frame")
	state.day=65; state.cities[0].owner_nation=(owner+1)%state.nations.size()
	var rng_before := state.rng.state
	view.simulation.paused=false; view.mode_control.select(2)
	view.history_control.value=0
	check(view.historical_view and view.information_source().day==0,"dragging to the first point displays day zero")
	check(view.simulation.paused and view.information_source().cities[0].owner_nation==owner,"history pauses and displays captured ownership")
	view.mode_control.select(1); view.history_control.value=1
	timeline.refresh()
	check(view.information_source().day==30,"another slider stop selects the corresponding snapshot")
	check(timeline.date.text=="1年31天 · 历史回看","selected history date uses its own calendar date")
	view.history_control.value=2
	timeline.refresh()
	check(not view.historical_view and view.information_source()==state,"the rightmost stop restores the live world")
	check(timeline.live_date.text=="现在 · 1年66天","live date stays distinct from the selected history date")
	check(not view.simulation.paused and view.mode_control.selected==2,"return restores the original running state and map mode")
	check(state.day==65 and state.cities[0].owner_nation!=owner and state.rng.state==rng_before,"scrubbing never rewinds or mutates the live simulation")
	view.simulation.paused=true; view.select_history(0); view.return_to_current()
	check(view.simulation.paused,"a world paused before browsing stays paused")
	# Scrubbing during a sliced day must finish that transaction, then honor only the latest request.
	view.simulation.advance_one_day(); view.select_history(0); view.select_history(1)
	check(not view.historical_view and not view.time_controls_available(),"pending history waits for the day commit and blocks new day commands")
	await process_frame; await process_frame
	check(view.historical_view and view.information_source().day==30,"rapid pending selections show only the last requested date")
	view.return_to_current()
	view.simulation.advance_one_day(); view.select_history(0); view.return_to_current()
	await process_frame; await process_frame
	check(not view.historical_view and view.information_source()==state,"return cancels a pending history request without a late switch")
	view.generating=true; view.select_history(0)
	check(not view.historical_view,"world generation blocks stale timeline actions")
	view.generating=false; state.day=12684; timeline.refresh()
	check(timeline.live_date.text=="现在 · 36年85天","large accumulated days remain readable")
	state.day=12660; view.history.reset(state)
	state.day=12684; view.capture_history(state.day); view.select_history(0); timeline.refresh()
	for width in [1280,768]:
		root.size=Vector2i(width,720); await process_frame; await process_frame
		check(timeline.date.text=="36年61天 · 历史回看" and timeline.live_date.text=="现在 · 36年85天","large history and live dates retain independent labels")
		check(timeline.get_global_rect().end.x<=width and timeline.date.size.x>200.,"long dates fit the viewport at %dpx"%width)
		if "--calendar-capture" in OS.get_cmdline_user_args():
			DirAccess.make_dir_recursive_absolute("res://.dbg/calendar")
			RenderingServer.force_draw(true)
			root.get_texture().get_image().save_png("res://.dbg/calendar/timeline-%d.png"%width)
	view.queue_free(); await process_frame
	print("ATLAS_HISTORY_TIMELINE failures=",failures); quit(1 if failures else 0)
