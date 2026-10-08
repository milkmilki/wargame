extends SceneTree
const Transport = preload("res://scripts/core/river_transport.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr(message)
func _init() -> void:
	var image := Image.create(1024,16,false,Image.FORMAT_RGBA8)
	for x in range(1024):
		for y in range(16): image.set_pixel(x,y,Color(1,1,1,(129.0+100.0*x/1023.0)/255.0))
	var river := MapFeatureContract.make_river(0,PackedVector2Array([Vector2(0.05,0.5),Vector2(0.95,0.5)]),MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)
	var docks := [{"city_id":0,"river_id":0,"river_progress":0.0,"position":river.points[0]},{"city_id":1,"river_id":0,"river_progress":1.0,"position":river.points[1]}]
	check(Transport.build([river],docks,image,1.0).is_empty(),"legacy whole range remains blocked")
	var roads := Transport.build([river],docks,image,1.0,true)
	check(roads.size()==1,"long gentle river should navigate")
	if not roads.is_empty():
		var edge:=Edge.new()
		edge.kind=Edge.Kind.RIVER
		edge.max_height_difference=roads[0].height_difference
		edge.river_navigation=roads[0].river_navigation
		check(edge.max_height_difference>0.2 and edge.river_is_navigable(),"runtime must use local assessment")
	# An intermediate dock cannot hide a short steep climb split across two links.
	for x in range(1024):
		var height:=0.0 if x<500 else (0.15 if x<504 else 0.30)
		for y in range(16): image.set_pixel(x,y,Color(1,1,1,(129.0+126.0*height)/255.0))
	var middle:=Vector2(502.0/1024.0,0.5)
	docks.append({"city_id":2,"river_id":0,"river_progress":(middle.x-0.05)/0.9,"position":middle})
	check(Transport.build([river],docks,image,1.0,true).is_empty(),"dock split must not reopen local cliff")
	print("RIVER_NAVIGATION_NETWORK failures=",failures)
	quit(0 if failures==0 else 1)
