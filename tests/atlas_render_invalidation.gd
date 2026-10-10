extends SceneTree
## Static administrative lines must reuse CanvasItem draw commands while idle.
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready() -> void: pass
var draws := 0
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_RENDER_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var view := View.new(); view.state = GameState.new()
	view.simulation = Simulation.new(); view.simulation.paused = true
	view.last_owner_revision = view.state.ownership_revision; view.history.reset(view.state)
	view.overlay = preload("res://scripts/atlas/military_overlay.gd").new()
	view.overlay.state = view.state
	view.overlay.state_lines = [PackedVector2Array([Vector2.ZERO,Vector2(20,20)])]
	view.add_child(view.overlay); view.add_child(view.simulation)
	view.overlay.draw.connect(func(): draws += 1)
	root.add_child(view)
	await process_frame; await process_frame
	var before := draws
	for i in range(6): await process_frame
	check(draws==before,"idle frames repeatedly rebuild static state/district borders")
	view.zoom = 2.; view.overlay.scale = Vector2.ONE*2.
	view.overlay.set_view(2.,Rect2(0,0,2048,1024))
	await process_frame; await process_frame
	check(draws==before+1,"zoom invalidates static line widths exactly once")
	before = draws; view.overlay.position += Vector2(15,0)
	for i in range(3): await process_frame
	check(draws==before,"pan reuses the cached static draw commands")
	view.overlay.high_performance = true; view.overlay.queue_redraw()
	await process_frame; await process_frame
	var builds: int = view.overlay.static_build_count
	var geometry: ArrayMesh = view.overlay.persistent_layers[0].chunks[0].mesh
	view.overlay.scale = Vector2.ONE*4.; view.overlay.set_view(4.,Rect2(1,1,512,256))
	await process_frame; await process_frame
	check(view.overlay.static_build_count==builds,"persistent geometry is reused on zoom")
	check(view.overlay.persistent_layers[0].chunks[0].mesh==geometry,"zoom retains the uploaded mesh resource")
	root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_RENDER_INVALIDATION failures=",failures); quit(1 if failures else 0)
