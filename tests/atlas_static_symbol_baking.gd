extends SceneTree
## Production startup must bound transient render attachments independently of
## the fixed world image size. Headless observes allocation requests, so this
## regression never needs to provoke the original GPU out-of-memory failure.
const Symbols = preload("res://scripts/atlas/symbol_tiles.gd")
const Scheduler = preload("res://scripts/atlas/render_scheduler.gd")
const Preview = preload("res://scripts/atlas/preview.gd")
const LegacySymbols = preload("res://scripts/atlas/symbols.gd")
const MAX_TEMPORARY_DIMENSION := 1280
const MAX_TEMPORARY_ATTACHMENT_PIXELS := MAX_TEMPORARY_DIMENSION * MAX_TEMPORARY_DIMENSION * 6
var failures := 0
var checks := 0
var publications := 0
var peak_dimension := 0
var peak_views := 0
var peak_attachment_pixels := 0

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("ATLAS_SYMBOL_BAKING_FAIL ",message)

func _initialize() -> void:
	call_deferred("run")

func observe_temporary_views(layer: Node) -> void:
	var views := 0
	var attachment_pixels := 0
	for child in layer.get_children():
		# queue_free still retains the attachments until the frame ends.
		if child is not SubViewport: continue
		var view: SubViewport = child
		views += 1
		peak_dimension = maxi(peak_dimension,maxi(view.size.x,view.size.y))
		attachment_pixels += view.size.x * view.size.y * (5 if view.msaa_2d == Viewport.MSAA_4X else 1)
	peak_views = maxi(peak_views,views)
	peak_attachment_pixels = maxi(peak_attachment_pixels,attachment_pixels)

func run() -> void:
	await check_symbol_viewport_setup()
	var service := Scheduler.new()
	root.add_child(service)
	var output := SubViewport.new()
	output.size = Vector2i(256,256)
	root.add_child(output)
	var screen := Sprite2D.new()
	screen.centered = false
	root.add_child(screen)
	var layer := Symbols.new()
	layer.static_world = true
	layer.world_screen = screen
	root.add_child(layer)
	layer.world_ready.connect(func(): publications += 1)
	layer.setup({"seed":1,"mesh":{"spacing":1.,"x":[],"y":[],"adj_start":[0],"adj":[]},"environment":{"water":[]}}, {"forest":PackedByteArray(),"glyphs":[]},service,output)
	var deadline := Time.get_ticks_msec() + 15000
	while not layer.is_ready() and Time.get_ticks_msec() < deadline:
		observe_temporary_views(layer)
		check(screen.texture == null,"incomplete world image remains unpublished")
		await process_frame
	observe_temporary_views(layer)
	check(layer.is_ready(),"fixed world image becomes ready")
	check(peak_dimension > 0 and peak_views > 0,"startup observation includes temporary render attachments")
	check(peak_dimension <= MAX_TEMPORARY_DIMENSION,"temporary viewport dimension is bounded: observed %d" % peak_dimension)
	check(peak_views <= 2,"at most one forest/symbol viewport pair is live: observed %d" % peak_views)
	check(peak_attachment_pixels <= MAX_TEMPORARY_ATTACHMENT_PIXELS,"temporary render attachments stay within one bounded pair: observed %d pixels" % peak_attachment_pixels)
	check(publications == 1,"completed world image publishes exactly once")
	check(layer.overview.get("pad",0) == 1,"completed image has only the shared edge padding")
	check(layer.overview.get("region_size",Vector2.ZERO) == Vector2(8192,4096),"completed image retains four pixels per world unit")
	check(screen.region_rect == Rect2(1,1,8192,4096),"world sprite displays the complete padded image")
	check(screen.texture != null,"completed image is attached to the world sprite")
	check(layer.groups.is_empty() and layer.world_copies.size() == 2,"static map seam copies need no camera compositor viewports")
	await process_frame
	check(not layer.get_children().any(func(child): return child is SubViewport),"completed image releases every temporary render viewport")
	check(service.cache_bytes <= 8194*4098*4,"only resolved world image pixels count against the retained cache")
	var texture: Texture2D = screen.texture
	var builds: int = layer.tile_build_count
	for i in range(20):
		layer.set_camera(Vector2(-i*150,i*5),[.625,1.,2.,4.,8.][i%5],Vector2(1280+i,720+i))
		await process_frame
	check(layer.tile_build_count == builds and screen.texture == texture,"camera changes reuse the completed image without rebuilding tiles")
	check(publications == 1,"camera changes never republish the fixed image")
	for copy in layer.world_copies:
		check(copy.texture == texture,"seam copy shares the completed texture")
	root.remove_child(layer)
	layer.free()
	await process_frame
	check(screen.texture == null and not screen.region_enabled,"disposing the layer detaches the world image")
	check(screen.get_child_count() == 0,"disposing the layer releases seam copies")
	check(service.cache_bytes == 0 and service.cache.is_empty(),"disposing the layer releases its retained image cache")
	await check_cancel_and_reload(service,screen,output)
	root.remove_child(screen)
	screen.free()
	root.remove_child(output)
	output.free()
	root.remove_child(service)
	service.free()
	print("ATLAS_STATIC_SYMBOL_BAKING checks=",checks," failures=",failures," peak_dimension=",peak_dimension," peak_views=",peak_views," peak_attachment_pixels=",peak_attachment_pixels)
	quit(1 if failures else 0)

func check_symbol_viewport_setup() -> void:
	# Keep previews outside the tree: running _ready would generate a map and
	# obscure the allocation contract of the scene's actual setup entry point.
	var preview := Preview.new()
	preview.size = Vector2(320,180)
	preview.high_performance_renderer = true
	preview.setup_symbol_viewports()
	check(preview.forest_view.get_child_count() == 0 and preview.symbol_view.get_child_count() == 0 and preview.symbol_layers.is_empty(),"high-performance setup creates no legacy forest, crown or glyph draw nodes")
	check(preview.forest_view.size == Vector2i(2,2) and preview.symbol_view.size == Vector2i(320,180),"high-performance setup uses only a tiny forest placeholder and screen-sized symbol target")
	check(preview.forest_view.msaa_2d == Viewport.MSAA_DISABLED and preview.symbol_view.msaa_2d == Viewport.MSAA_DISABLED,"unused high-performance viewport attachments disable MSAA")
	check(preview.forest_view.render_target_update_mode == SubViewport.UPDATE_DISABLED and preview.symbol_view.render_target_update_mode == SubViewport.UPDATE_DISABLED,"high-performance placeholders never render the old whole-world symbol pass")
	var forest_id: int = preview.forest_view.get_instance_id()
	var symbol_id: int = preview.symbol_view.get_instance_id()
	var screen_id: int = preview.symbol_screen.get_instance_id()
	preview.free()
	await process_frame
	check(not is_instance_id_valid(forest_id) and not is_instance_id_valid(symbol_id) and not is_instance_id_valid(screen_id),"an unparented preview releases its placeholder viewports and unused screen member")
	var legacy := Preview.new()
	legacy.size = Vector2(320,180)
	legacy.high_performance_renderer = false
	legacy.data = {"seed":1,"mesh":{"spacing":1.,"x":[],"y":[],"adj_start":[0],"adj":[]},"environment":{"water":[]}}
	legacy.display = {"forest":PackedByteArray(),"glyphs":[]}
	legacy.setup_symbol_viewports()
	check(legacy.symbol_layers.size() == 3 and legacy.symbol_layers.all(func(layer): return layer.get_script() == LegacySymbols),"legacy setup preserves all three original symbol drawing layers")
	check(legacy.symbol_layers.map(func(layer): return layer.layer) == ["forest","crowns","glyphs"],"legacy drawing layers retain their distinct forest, crown and glyph content")
	check(legacy.forest_view.render_target_update_mode == SubViewport.UPDATE_ONCE and legacy.symbol_view.render_target_update_mode == SubViewport.UPDATE_ONCE,"legacy symbol drawing retains the original single viewport update")
	var expected_msaa := Viewport.MSAA_DISABLED if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Viewport.MSAA_4X
	check(legacy.symbol_view.msaa_2d == expected_msaa,"legacy symbol viewport retains renderer-appropriate antialiasing")
	var legacy_layers := legacy.symbol_layers.map(func(layer): return layer.get_instance_id())
	forest_id = legacy.forest_view.get_instance_id()
	symbol_id = legacy.symbol_view.get_instance_id()
	legacy.free()
	await process_frame
	check(not is_instance_id_valid(forest_id) and not is_instance_id_valid(symbol_id) and legacy_layers.all(func(id): return not is_instance_id_valid(id)),"disposing the legacy preview releases its viewports and every drawing layer")

func check_cancel_and_reload(service: Node,screen: Sprite2D,output: SubViewport) -> void:
	var cancelled := Symbols.new()
	cancelled.static_world = true
	cancelled.world_screen = screen
	root.add_child(cancelled)
	var emitted := {"cancelled":0,"replacement":0}
	cancelled.world_ready.connect(func(): emitted.cancelled += 1)
	# Leave the queued mesh uploads available to invalidate after the first
	# viewport allocation. No fake publisher or manually altered model state.
	var prior_budget: int = service.frame_budget_usec
	service.frame_budget_usec = 100
	cancelled.setup({"seed":2,"mesh":{"spacing":1.,"x":[],"y":[],"adj_start":[0],"adj":[]},"environment":{"water":[]}}, {"forest":PackedByteArray(),"glyphs":[]},service,output)
	var deadline := Time.get_ticks_msec() + 5000
	while not cancelled.get_children().any(func(child): return child is SubViewport) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(cancelled.get_children().any(func(child): return child is SubViewport),"cancellation interrupts a real allocated bake viewport")
	check(not cancelled.is_ready() and screen.texture == null and emitted.cancelled == 0,"first partial tile never exposes an incomplete world image")
	root.remove_child(cancelled)
	cancelled.free()
	service.frame_budget_usec = prior_budget
	await process_frame
	check(screen.texture == null and not screen.region_enabled and screen.get_child_count() == 0,"cancelling the bake leaves neither partial texture nor seam sprites")
	check(service.cache_bytes == 0 and service.cache.is_empty(),"cancelling the bake leaves no retained image cache")
	var replacement := Symbols.new()
	replacement.static_world = true
	replacement.world_screen = screen
	root.add_child(replacement)
	replacement.world_ready.connect(func(): emitted.replacement += 1)
	replacement.setup({"seed":3,"mesh":{"spacing":1.,"x":[],"y":[],"adj_start":[0],"adj":[]},"environment":{"water":[]}}, {"forest":PackedByteArray(),"glyphs":[]},service,output)
	deadline = Time.get_ticks_msec() + 15000
	while not replacement.is_ready() and Time.get_ticks_msec() < deadline:
		check(screen.texture == null and emitted.cancelled == 0,"cancelled callbacks cannot publish into the replacement world")
		await process_frame
	check(replacement.is_ready() and emitted.replacement == 1,"a replacement world completes after cancelling the prior bake")
	check(screen.texture != null and screen.texture == replacement.overview.get("texture"),"replacement world publishes its own completed image")
	check(screen.region_rect == Rect2(1,1,8192,4096) and screen.get_child_count() == 2,"replacement retains complete dimensions and only its own seam copies")
	var replacement_texture: Texture2D = screen.texture
	deadline = Time.get_ticks_msec() + 5000
	while service.pending() and Time.get_ticks_msec() < deadline: await process_frame
	for i in range(5): await process_frame
	check(not service.pending(),"old and replacement scheduler work drains")
	check(emitted.cancelled == 0 and emitted.replacement == 1 and screen.texture == replacement_texture,"late old work cannot overwrite or republish the replacement image")
	root.remove_child(replacement)
	replacement.free()
	await process_frame
	check(screen.texture == null and not screen.region_enabled and screen.get_child_count() == 0,"disposing the replacement releases its published display")
	check(service.cache_bytes == 0 and service.cache.is_empty(),"all cancelled and replacement image resources leave the cache")
