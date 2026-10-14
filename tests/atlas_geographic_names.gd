extends SceneTree
const Text=preload("res://scripts/atlas/map_text.gd")
const State=preload("res://scripts/atlas/text_state.gd")
class View extends "res://scripts/atlas/military_preview.gd":
	func _ready():
		add_child(map_root); add_child(render_scheduler); make_ui(); set_process(false)
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("GEOGRAPHIC_NAMES_FAIL ",message)
func run():
	var text := Text.new(); var numerical := State.new()
	check(text.get("show_geography")==false and numerical.get("show_geography")==false,"geographic names default off in both rendering paths")
	if text.get("show_geography")==null: text.free(); quit(1); return
	numerical.data={"cities":[],"nations":[{"color":[100,80,60]}],"ownership":[],"mesh":{"x":[],"y":[]},"places":[{"name":"测试海","kind":"sea","rank":1,"size":100,"path":[500.,200.,600.,200.]}]}
	numerical.labels=[{"polity":0,"text":"秦","regions":2,"size":15.,"vertical":false,"path":[100.,100.,300.,100.]}]
	numerical.prepare()
	check(not numerical.all_jobs.any(func(job):return job.type=="place") and numerical.all_jobs.any(func(job):return job.type=="nation"),"default hides only geography and retains country labels")
	numerical.set("show_geography",true); numerical.prepare()
	check(numerical.all_jobs.any(func(job):return job.type=="place"),"opt-in restores geography jobs")
	var view := View.new(); root.add_child(view)
	var control: CheckButton
	for child in view.interface.tools.find_children("*","CheckButton",true,false):
		if child.text=="地理名称": control=child
	check(control!=null and not control.button_pressed,"tools expose an unchecked geographic name toggle")
	if control!=null:
		control.button_pressed=true
		check(view.text_layer.show_geography and view.text_layer.show_names and view.text_layer.show_polities,"enabling geography retains independent country/overall controls")
		control.button_pressed=false
		check(not view.text_layer.show_geography and view.text_layer.show_names,"geography can be disabled again without hiding countries")
	view.queue_free(); text.free(); await process_frame
	var service := preload("res://scripts/atlas/render_scheduler.gd").new(); root.add_child(service)
	var layer := Text.new(); root.add_child(layer); layer.high_performance=true; layer.static_world=true; layer.scheduler=service
	var water := PackedByteArray(); water.resize(2048*1024); water.fill(1)
	layer.data=numerical.data; layer.labels=numerical.labels; layer.raster={"water":water}
	layer.owners.resize(water.size()); layer.owners.fill(0)
	layer.rebuild(); layer.set_camera(Vector2.ZERO,1.,Vector2(1280,720)); await settle(layer)
	check(layer.static_geography.rows.is_empty() and not layer.static_geography.visible and layer.static_countries.visible,"static renderer defers hidden geography but retains countries")
	layer.show_geography=true; layer.rebuild(); await settle(layer)
	check(not layer.static_geography.rows.is_empty() and layer.static_geography.visible,"static geographic labels appear when enabled")
	var builds: int=layer.static_build_count
	layer.show_geography=false; layer.rebuild(); await settle(layer)
	check(not layer.static_geography.visible and layer.static_countries.visible,"static toggle hides geography independently")
	layer.show_geography=true; layer.rebuild(); await settle(layer)
	check(layer.static_geography.visible and layer.static_build_count==builds,"reopening reuses prepared geographic labels")
	layer.queue_free(); service.queue_free(); await process_frame
	print("GEOGRAPHIC_NAMES checks=",checks," failures=",failures); quit(1 if failures else 0)
func settle(layer):
	var deadline := Time.get_ticks_msec()+5000
	while not layer.is_ready() and Time.get_ticks_msec()<deadline: await process_frame
	check(layer.is_ready(),"geographic label publication completes")
