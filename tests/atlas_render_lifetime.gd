extends SceneTree
const Scheduler = preload("res://scripts/atlas/render_scheduler.gd")
const Stroke = preload("res://scripts/atlas/persistent_strokes.gd")
class View extends "res://scripts/atlas/preview.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func political_front_snapshot() -> Dictionary: return {"signature":0}
	func refresh_political_materials() -> void: pass
	func political_display_ready() -> void: pass
	func update_mode() -> void: pass
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("RENDER_LIFETIME_FAIL ",label)
func drain(service: Node) -> void:
	var deadline := Time.get_ticks_msec()+5000
	while service.pending() and Time.get_ticks_msec()<deadline:
		service._process(0.); await process_frame
	check(not service.pending(),"the numerical and upload queues finish")
func run() -> void:
	await test_dead_listener()
	await test_published_geometry_budget()
	print("ATLAS_RENDER_LIFETIME checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func test_dead_listener() -> void:
	var service := Scheduler.new(); root.add_child(service); service.set_process(false)
	var paths: Array = [PackedVector2Array([Vector2(10,10),Vector2(100,10),Vector2(150,40)])]
	var dead := Stroke.new(); dead.scheduler=service; root.add_child(dead); dead.set_paths(paths)
	var survivor := Stroke.new(); survivor.scheduler=service; root.add_child(survivor); survivor.set_paths(paths)
	check(service.geometry_pending.size()==1,"both real layers subscribe to a shared pending geometry")
	dead.free()
	await drain(service)
	check(not survivor.preparing and not survivor.chunks.is_empty(),"a freed peer cannot prevent the live layer from receiving geometry")
	check(service.geometry_pending.is_empty(),"completed geometry drops pending callbacks")
	survivor.free()
	check(service.geometry_users.is_empty(),"destroying all layers removes their ownership registry entries")
	service.queue_free(); await process_frame; await process_frame
func test_published_geometry_budget() -> void:
	var view := View.new()
	# Attach the ordinary scene-owned nodes without starting map generation.
	for property in view.get_property_list():
		if not int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var value = view.get(property.name)
		if value is Node and value.get_parent()==null: view.add_child(value)
	root.add_child(view); view.render_scheduler.set_process(false)
	view.render_scheduler.cache_budget=4096
	view.data={"ownership":PackedInt32Array([0])}
	var retired: WeakRef
	for revision in range(24):
		view.political_revision=revision
		var paths: Array = [PackedVector2Array([Vector2(revision,10),Vector2(revision+100,20)])]
		var keys := {"normal":hash(paths),"front":hash([revision,1]),"teeth":hash([revision,2])}
		var result := {"stroke_plans":{"normal":Stroke.plan(paths),"front":[],"teeth":[]},"stroke_keys":keys,"segments":{},"edge":{},
			"cache":{"tiles":[],"ownership":view.data.ownership},"lines":[],"index":{},"labels":PackedInt32Array(),"names":[],"marker_plan":{},"content_changed":true}
		view.publish_political(result,0,revision)
		await drain(view.render_scheduler)
		if revision==0:
			retired=first_mesh_ref(view.render_scheduler)
	check(view.render_scheduler.cache_bytes<=view.render_scheduler.cache_budget,"successive political revisions respect the geometry memory budget")
	check(view.render_scheduler.cache.values().all(func(entry): return not entry.pinned),"a preuploaded border without live consumers is not permanently pinned")
	check(retired!=null and retired.get_ref()==null,"an evicted obsolete GPU mesh is actually released")
	view.queue_free(); await process_frame; await process_frame

func first_mesh_ref(service: Node) -> WeakRef:
	# Keep the inspection array out of the test's long-lived coroutine frame.
	for entry in service.cache.values():
		if entry.value is Array and not entry.value.is_empty(): return weakref(entry.value[0].mesh)
	return null
