extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_TEXT_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var state := preload("res://scripts/atlas/text_state.gd").new()
	state.zoom = 2.; state.canvas_size = Vector2(4096,2048)
	var water := PackedByteArray(); water.resize(2048*1024)
	state.raster = {"water":water}; state.owners.resize(water.size()); state.owners.fill(0)
	state.data = {"cities":[{"region":0,"cell":0,"major":false,"name":"甲城"},{"region":1,"cell":1,"major":false,"name":"乙城"}],"ownership":[0,0],"nations":[{"seat":0,"color":[100,80,60]}],"mesh":{"x":[100.,300.],"y":[100.,100.]},"places":[]}
	state.prepare()
	check(not state.all_jobs.any(func(job): return job.type=="city"),"default layout creates no city name jobs")
	var hidden: Dictionary = state.update(Rect2(50,50,100,100))
	check(not hidden.marks.is_empty() and hidden.rows.is_empty(),"hidden names retain selectable settlement marks")
	var enabled := preload("res://scripts/atlas/text_state.gd").new()
	enabled.data=state.data; enabled.raster=state.raster; enabled.owners=state.owners
	enabled.zoom=state.zoom; enabled.canvas_size=state.canvas_size
	state=enabled; state.show_city_names = true; state.prepare()
	check(state.all_jobs.any(func(job): return job.type=="city"),"enabling city names restores layout candidates")
	var first: Dictionary = state.update(Rect2(50,50,100,100)); var count: int = first.completed
	var next: Dictionary = state.update(Rect2(55,50,100,100))
	check(next.completed==count and next.rows==first.rows,"small pan preserves accepted label placement")
	var second: Dictionary = state.update(Rect2(250,50,100,100))
	check(second.completed>count,"entering another region adds candidates incrementally")
	check(second.rows.any(func(row): return row.glyphs==first.rows[0].glyphs),"existing labels retain their world anchors")
	print("ATLAS_INCREMENTAL_TEXT failures=",failures); quit(1 if failures else 0)
