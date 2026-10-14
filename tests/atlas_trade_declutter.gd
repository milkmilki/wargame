extends SceneTree
const View = preload("res://scripts/atlas/trade_view.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("TRADE_DECLUTTER_FAIL ",message)
func run():
	var module=load("res://scripts/atlas/trade_view.gd")
	if not module.get_script_method_list().any(func(method):return method.name=="drawing_segments"):
		check(false,"sea corridors merge shared physical geometry for drawing"); quit(1); return
	var source := [
		{"path":PackedVector2Array([Vector2(10,10),Vector2(20,10),Vector2(30,10)]),"water":true,"active_count":5,"route_count":5},
		{"path":PackedVector2Array([Vector2(40,10),Vector2(30,10),Vector2(20,10)]),"water":true,"active_count":3,"route_count":3},
		{"path":PackedVector2Array([Vector2(15,20),Vector2(30,20)]),"water":false,"main":false,"active_count":1,"route_count":1},
	]
	var before := var_to_bytes(source)
	var drawn: Array=module.call("drawing_segments",source)
	check(drawn.size()==4,"two sea edges sharing a segment draw the physical overlap once")
	check(var_to_bytes(source)==before,"merging ink cannot change actual route publications")
	var layer := View.Routes.new(); root.add_child(layer)
	layer.set_segments(source)
	layer.set_view(.625,Rect2(0,0,2048,1024))
	check(not layer.stroke_layers[0].visible and layer.stroke_layers[3].visible,"world view emphasizes trunk routes and suppresses minor branches")
	layer.set_view(3.,Rect2(0,0,500,500))
	check(layer.stroke_layers[0].visible,"zooming in restores minor routes without changing the network")
	var builds: int=layer.build_count
	layer.set_view(4.,Rect2(20,20,500,500))
	check(layer.build_count==builds,"zoom decluttering never rebuilds route geometry")
	layer.free(); print("TRADE_DECLUTTER checks=",checks," failures=",failures)
	quit(1 if failures else 0)
