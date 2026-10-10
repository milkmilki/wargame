extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_SHARED_STROKE_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var service := preload("res://scripts/atlas/render_scheduler.gd").new(); root.add_child(service)
	var first := preload("res://scripts/atlas/persistent_strokes.gd").new(); first.scheduler = service; root.add_child(first)
	var second := preload("res://scripts/atlas/persistent_strokes.gd").new(); second.scheduler = service; root.add_child(second)
	var paths: Array = [PackedVector2Array([Vector2(10,10),Vector2(100,10),Vector2(150,40)])]
	first.set_paths(paths); second.set_paths(paths)
	var deadline := Time.get_ticks_msec()+2000
	while (first.preparing or second.preparing) and Time.get_ticks_msec()<deadline: await process_frame
	check(not first.preparing and not second.preparing,"joined layers complete async preparation")
	check(first.chunks[0].mesh==second.chunks[0].mesh,"paper and ink reuse the actual same GPU mesh")
	check(service.cache_bytes>0,"persistent geometry is included in the cache budget")
	var old: ArrayMesh = first.chunks[0].mesh
	first.set_paths([PackedVector2Array([Vector2(10,10),Vector2(50,40)])])
	check(first.chunks[0].mesh==old,"old complete geometry remains until replacement is ready")
	while first.preparing and Time.get_ticks_msec()<deadline: await process_frame
	check(first.chunks[0].mesh!=old and second.chunks[0].mesh==old,"one changed layer does not invalidate its unrelated peer")
	root.remove_child(first); first.free(); root.remove_child(second); second.free()
	check(service.geometry_users.values().all(func(value): return value==0),"destroyed layers release their cache pins")
	root.remove_child(service); service.free(); print("ATLAS_SHARED_STROKE_CACHE failures=",failures); quit(1 if failures else 0)
