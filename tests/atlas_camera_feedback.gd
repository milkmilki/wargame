extends SceneTree
class View extends "res://scripts/atlas/preview.gd":
	func _ready(): pass
class SymbolLayer extends Node2D:
	var detail_zoom := 1.
	var visible_world := Rect2()
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_CAMERA_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var view := View.new(); view.size = Vector2(1280,720); view.zoom = 2.
	view.high_performance_renderer = false # Explicit developer comparator remains covered.
	view.data = {"mesh":{"spacing":1.}}
	view.symbol_view.size = Vector2i(1664,1104); view.forest_view.size = view.symbol_view.size
	view.add_child(view.map_root); view.add_child(view.symbol_screen)
	view.add_child(view.symbol_view); view.add_child(view.forest_view); view.add_child(view.text_layer)
	view.navigation_timer.one_shot = true; view.navigation_timer.wait_time = .14
	view.navigation_timer.timeout.connect(view.navigation_timeout); view.add_child(view.navigation_timer)
	view.paper_material = ShaderMaterial.new(); view.paper_material.shader = load("res://assets/atlas/paper.gdshader")
	view.forest_material = ShaderMaterial.new(); view.forest_material.shader = load("res://assets/atlas/forest.gdshader")
	view.crown_material = ShaderMaterial.new(); view.crown_material.shader = load("res://assets/atlas/crown_clip.gdshader")
	var layer := SymbolLayer.new(); view.symbol_view.add_child(layer); view.symbol_layers = [layer]
	var coast = load("res://scripts/atlas/coast_ink.gd").new(); coast.chunks = [[],[],[],[],[]]
	for i in range(3):
		var ripple = load("res://scripts/atlas/coast_ink.gd").Ripple.new(); coast.add_child(ripple); coast.ripple_nodes.append(ripple)
	view.map_root.add_child(coast); view.coast_ink = coast
	root.add_child(view); view.map_root.position = Vector2(-2000,-200); view.map_root.scale = Vector2.ONE*2
	view.refresh_symbols(); var renders := view.symbol_build_count; var layouts := view.camera_layout_count
	view.start_navigation(); view.map_root.position.x += 50; view.refresh_symbols()
	view.navigation_timeout()
	check(view.navigation_in_progress,"an old long frame cannot immediately flush freshly restarted navigation")
	check(view.symbol_build_count==renders and view.camera_layout_count==layouts,"pan input reprojects without texture/layout rebuild")
	check(view.symbol_screen.position==Vector2(50-View.SYMBOL_PAD,-View.SYMBOL_PAD),"cached symbols follow camera exactly")
	check(view.text_layer.position==Vector2(50,0),"cached labels follow camera exactly")
	view.finish_navigation()
	check(view.symbol_build_count==renders and view.camera_layout_count==layouts+1,"small settled pan reuses padded symbols and lays out labels once")
	view.start_navigation(); view.zoom = 4.; view.map_root.scale = Vector2.ONE*4; view.refresh_symbols()
	check(view.symbol_build_count==renders and view.symbol_screen.scale==Vector2.ONE*2,"scroll reprojects the old texture immediately")
	view.finish_navigation()
	check(view.symbol_build_count==renders+1 and view.symbol_screen.scale==Vector2.ONE,"settled zoom rebuilds exact detail and resets reprojection")
	renders = view.symbol_build_count; view.map_root.position.x += 2048*view.zoom; view.refresh_symbols()
	check(view.symbol_build_count==renders,"equivalent dateline wrap reuses symbol texture")
	view.map_root.position.x += 400; view.refresh_symbols()
	check(view.symbol_build_count==renders+1,"leaving padded coverage refreshes symbols")
	root.remove_child(view); view.queue_free(); await process_frame
	print("ATLAS_CAMERA_FEEDBACK failures=",failures); quit(1 if failures else 0)
