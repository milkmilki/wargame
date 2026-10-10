extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_SCHEDULER_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var script = load("res://scripts/atlas/render_scheduler.gd")
	if script==null: quit(1); return
	var scheduler = script.new(); root.add_child(scheduler)
	var a: int = scheduler.choose_lod(2.,-1)
	check(scheduler.choose_lod(2.01,a)==a,"small zoom movement keeps the detail tier")
	check(scheduler.choose_lod(4.,a)!=a,"large zoom changes the tier")
	var received: Array = []
	scheduler.submit("labels",func(): return 11,func(value): received.append(value),0)
	scheduler.invalidate("labels")
	scheduler.submit("labels",func(): return 22,func(value): received.append(value),0)
	var deadline := Time.get_ticks_msec()+2000
	while scheduler.pending() and Time.get_ticks_msec()<deadline: await process_frame
	check(received==[22],"stale worker output cannot overwrite the new version")
	scheduler.cache_budget = 100
	scheduler.remember("overview",{},60,true)
	scheduler.remember("old",{},30)
	scheduler.remember("new",{},30)
	check(scheduler.cache.has("overview") and not scheduler.cache.has("old") and scheduler.cache.has("new"),"LRU respects the pinned overview")
	check(scheduler.cache_bytes<=100,"cache respects its byte budget")
	root.remove_child(scheduler); scheduler.free()
	print("ATLAS_RENDER_SCHEDULER failures=",failures); quit(1 if failures else 0)
