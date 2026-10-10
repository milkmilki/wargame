extends SceneTree
const Lines = preload("res://scripts/atlas/visible_lines.gd")
const Ink = preload("res://scripts/atlas/preview_ink.gd")
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures += 1; printerr("ATLAS_VIEW_CACHE_FAIL ",message)
func _initialize():
	var seam := PackedVector2Array([Vector2(-3,10),Vector2(3,10)])
	var distant := PackedVector2Array([Vector2(800,10),Vector2(810,10)])
	var index := Lines.index([seam,distant])
	check(Lines.select(index,Rect2(2045,0,10,20))==[seam],"seam chains retain continuous coordinates and are selected once")
	check(Lines.select(index,Rect2(790,0,30,20))==[distant],"offscreen chains are culled without cutting dash phase")
	var ink := Ink.new(); ink.route_lines = {"road":[seam,distant],"trail":[]}
	ink.visible_world = Rect2(0,0,40,40); ink.prepare_strokes()
	var count := ink.stroke_build_count; var road: ArrayMesh = ink.stroke_cache.road
	ink.visible_world.position.x += 10; ink.prepare_strokes()
	check(ink.stroke_build_count==count and ink.stroke_cache.road==road,"small pan reuses road geometry")
	ink.visible_world.position.x = 780; ink.prepare_strokes()
	check(ink.stroke_build_count==count+1,"pan outside coverage rebuilds visible chains")
	count = ink.stroke_build_count; ink.view_zoom = 2.; ink.pen = .8; ink.prepare_strokes()
	check(ink.stroke_build_count==count+1,"zoom invalidates width and AA")
	count = ink.stroke_build_count
	ink.borders = [{"pts":PackedFloat32Array([800,5,810,5])}]; ink.prepare_strokes()
	check(ink.stroke_build_count==count+1,"political geometry changes invalidate border cache")
	check(ink.route_lines.road==[seam,distant],"display culling never mutates actual roads")
	ink.free(); print("ATLAS_VIEW_CACHES failures=",failures); quit(1 if failures else 0)
