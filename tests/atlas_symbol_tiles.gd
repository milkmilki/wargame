extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_TILES_FAIL ",message)
func _initialize(): call_deferred("run")
func ready_tiles(tiles):
	var deadline := Time.get_ticks_msec()+2000
	while not tiles.is_ready() and Time.get_ticks_msec()<deadline: await process_frame
	check(tiles.is_ready(),"visible tiles complete without stopping input")
func run():
	var service := preload("res://scripts/atlas/render_scheduler.gd").new(); root.add_child(service)
	var output := SubViewport.new(); output.size = Vector2i(256,256); root.add_child(output)
	var tiles := preload("res://scripts/atlas/symbol_tiles.gd").new(); root.add_child(tiles)
	var data := {"seed":1,"mesh":{"spacing":1.,"x":[],"y":[],"adj_start":[0],"adj":[]},"environment":{"water":[]}}
	tiles.setup(data,{"forest":PackedByteArray(),"glyphs":[]},service,output)
	tiles.set_camera(Vector2.ZERO,2.,Vector2(256,256)); await ready_tiles(tiles)
	for i in range(20): await process_frame
	var idle_updates: int = tiles.group_update_count
	for i in range(15): await process_frame
	check(tiles.group_update_count==idle_updates,"idle frames do not requery or compose frozen layers")
	check(output.render_target_update_mode!=SubViewport.UPDATE_ALWAYS,"symbol mask is event-driven")
	var count: int = tiles.tile_build_count
	for i in range(4): tiles.set_camera(Vector2(-i*2,0),2.,Vector2(256,256)); await process_frame
	check(tiles.tile_build_count<=count+3,"same-tier pan reuses previously rendered tiles")
	tiles.set_camera(Vector2.ZERO,4.,Vector2(256,256)); await ready_tiles(tiles)
	tiles.set_camera(Vector2.ZERO,2.,Vector2(256,256)); await ready_tiles(tiles)
	check(service.cache_bytes<=service.cache_budget,"resident tile allocation is accounted")
	root.remove_child(tiles); tiles.free(); root.remove_child(output); output.free()
	check(service.cache_bytes==0,"world disposal releases its cached resources")
	root.remove_child(service); service.free()
	print("ATLAS_SYMBOL_TILES failures=",failures); quit(1 if failures else 0)
