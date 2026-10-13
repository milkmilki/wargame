extends SceneTree
## Compare the worker-side pure plan with the original committed set_view,
## including the actual MultiMesh bytes it published. The oracle lives in
## memory only; no shadow source, developer cache or run archive is written.
const Markers = preload("res://scripts/atlas/city_markers.gd")
const BASE_REF := "f3ab57a:scripts/atlas/city_markers.gd"
var checks := 0
var failures := 0
var original: GDScript
var model := GameState.new()
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks += 1
	if not ok: failures += 1; printerr("CITY_MARKER_PREP_FAIL ",message)
func finish():
	print("ATLAS_CITY_MARKER_PREPARATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func fixture() -> Dictionary:
	var positions := [Vector2(96,100),Vector2(96,100),Vector2(106,104),Vector2(145,100),
		Vector2(500,100),Vector2(504,100),Vector2(600,140),Vector2(650,140),
		Vector2(2044,140),Vector2(4,140),Vector2(1100,520),Vector2(1250,700)]
	var cities: Array = []; var x: Array = []; var y: Array = []
	for id in range(positions.size()):
		cities.append({"region":id,"cell":id,"role":"zhou" if id%3 == 0 else "fu","major":id%2 == 0})
		x.append(positions[id].x); y.append(positions[id].y)
	return {"cities":cities,"ownership":PackedInt32Array([0,0,0,0,1,1,1,-1,2,2,2,2]),
		"nations":[{"seat":0,"color":[100,80,60]},{"seat":4,"color":[30,120,180]},{"seat":10,"color":[180,90,150]}],
		"mesh":{"x":x,"y":y},"rng":model.rng}
func large_fixture() -> Dictionary:
	var cities: Array = []; var x: Array = []; var y: Array = []; var owners := PackedInt32Array()
	for id in range(2350):
		cities.append({"region":id,"cell":id,"role":"fu" if id < 2150 else "zhou","major":false})
		x.append((id%70)*28.+14.); y.append((id/70)*28.+14.); owners.append(0)
	return {"cities":cities,"ownership":owners,"nations":[{"seat":0,"color":[110,130,150]}],"mesh":{"x":x,"y":y},"rng":model.rng}
func load_original() -> bool:
	var output: Array = []
	var status := OS.execute("git",["-C",ProjectSettings.globalize_path("res://"),"show",BASE_REF],output,true)
	check(status == 0 and not output.is_empty(),"the committed pre-refactor marker implementation is available")
	if status != 0 or output.is_empty(): return false
	original = GDScript.new(); original.source_code = output[0]
	check(original.reload() == OK,"the original marker oracle compiles without a filesystem shadow")
	return original.can_instantiate()
func run():
	var probe := Markers.new()
	check(probe.has_method("prepare_instances") and probe.has_method("apply_instances"),"city instance preparation is independent of main-thread uploads")
	probe.free()
	if failures or not load_original(): finish(); return
	model.rng.seed = 91232
	var rng_before := model.rng.state
	var base := fixture()
	var occupation := base.duplicate(true); occupation.ownership[1] = 1; occupation.ownership[5] = 2
	var capitals := occupation.duplicate(true); capitals.nations[0].seat = 3; capitals.nations[1].seat = 1
	var unowned := capitals.duplicate(true); unowned.ownership[4] = -1; unowned.nations[2].color = [80,200,40]
	var scenarios: Array = [base,occupation,capitals,unowned]
	for scenario in range(scenarios.size()):
		for detail in [1.,4.,8.]:
			for rect in [Rect2(0,0,2048,1024),Rect2(80,80,130,80),Rect2(-20,100,60,80),Rect2(1700,800,100,100)]:
				compare_case(scenarios[scenario],rect,detail,[],"scenario=%d detail=%s rect=%s" % [scenario,detail,rect])
		compare_case(scenarios[scenario],Rect2(0,0,2048,1024),4.,[{"index":0},{"index":2},{"index":5},{"index":9}],"accepted subset scenario=%d" % scenario)
	var large := large_fixture()
	var result := compare_case(large,Rect2(0,0,2048,1024),4.,[],"instance capacity growth")
	check(result.counts[2] > 2048 and result.counts[3] > 128,"capacity fixture actually exceeds house and tower template allocations")
	check(model.rng.state == rng_before,"main-thread and worker preparation never consume the simulation random stream")
	finish()
func compare_case(source: Dictionary,rect: Rect2,detail: float,accepted: Array,label: String) -> Dictionary:
	var before := var_to_bytes(source)
	var reference: Node2D = original.new(); reference.setup(source); reference.set_view(rect,detail,accepted)
	var ids: Array = Array(reference.index.query(rect.grow(24./detail)))
	var actual := Markers.prepare_instances(source,ids,detail,accepted)
	check(actual.ids == ids and actual.detail == detail,label+": plan belongs to the requested visible cities and detail")
	check(var_to_bytes(actual.hit_boxes) == var_to_bytes(reference.hit_boxes),label+": collision ordering and selectable bounds exactly match committed behavior")
	var count := 0
	for kind in range(5):
		check(actual.counts[kind] == reference.layers[kind].mesh.visible_instance_count,label+": glyph counts match the original renderer")
		check(actual.buffers[kind].to_byte_array() == reference.layers[kind].mesh.buffer.to_byte_array(),label+": prepared transform/color/id bytes match original GPU publication")
		count += actual.counts[kind]
	check(count == reference.visible_count,label+": total visible cities match the committed renderer")
	var mailbox := {}
	var task := WorkerThreadPool.add_task(func(): mailbox.value = Markers.prepare_instances(source,ids,detail,accepted),false,"CityMarker preparation regression")
	WorkerThreadPool.wait_for_task_completion(task)
	check(var_to_bytes(mailbox.value) == var_to_bytes(actual),label+": worker and synchronous preparation are exactly equivalent")
	check(var_to_bytes(source) == before,label+": all pure computations preserve input ownership, seats and positions")
	var current := Markers.new(); current.setup(source)
	current.apply_instances(actual)
	check(var_to_bytes(current.hit_boxes) == var_to_bytes(reference.hit_boxes),label+": main-thread application preserves clickable bounds")
	for kind in range(5):
		check(current.layers[kind].mesh.buffer.to_byte_array() == reference.layers[kind].mesh.buffer.to_byte_array(),label+": main-thread application publishes the same GPU buffer")
		check(current.layers[kind].mesh.visible_instance_count == reference.layers[kind].mesh.visible_instance_count,label+": main-thread application publishes the same instance counts")
		for copy in range(3):
			check(current.layers[kind].nodes[copy].position == reference.layers[kind].nodes[copy].position,label+": wrapped glyph transforms remain identical")
	reference.free(); current.free()
	return actual
