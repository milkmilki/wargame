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
	state.prepare(); var first: Dictionary = state.update(Rect2(50,50,100,100)); var count: int = first.completed
	var next: Dictionary = state.update(Rect2(55,50,100,100))
	check(next.completed==count and next.rows==first.rows,"small pan preserves accepted label placement")
	var second: Dictionary = state.update(Rect2(250,50,100,100))
	check(second.completed>count,"entering another region adds candidates incrementally")
	check(second.rows.any(func(row): return row.glyphs==first.rows[0].glyphs),"existing labels retain their world anchors")
	print("ATLAS_INCREMENTAL_TEXT failures=",failures); quit(1 if failures else 0)
