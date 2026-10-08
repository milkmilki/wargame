extends SceneTree
func _init() -> void:
	var road=load("res://scripts/core/atlas_road_network.gd")
	var image:=Image.create(48,24,false,Image.FORMAT_RGBA8);image.fill(Color(1,1,1,0.55))
	var positions: Array[Vector2]=[Vector2(0.15,0.5),Vector2(0.5,0.5),Vector2(0.85,0.5)]
	var ids:=PackedInt32Array()
	for y in range(24):
		for x in range(48): ids.append(0 if x<16 else (1 if x<32 else 2))
	var provinces: Dictionary={"ids":ids,"size":Vector2i(48,24)}
	var points: PackedVector2Array=road._representatives(image,image,provinces)
	var heights:=PackedFloat32Array();heights.resize(ids.size());heights.fill(0.1)
	var context: Dictionary={"points":points,"heights":heights,"options":{"image":image,"maximum_height":1.0},"city_cells":{583:true,600:true,616:true},"aspect":2.0,"km_per_height":4330.0,"legal":{}}
	var path: PackedVector2Array=road._route(0,1,positions,provinces,context,{})
	print(path)
	for i in range(path.size()-1):
		if not road.path_valid(PackedVector2Array([path[i],path[i+1]]),provinces,0,1,context.options): print("INVALID ",path[i]," ",path[i+1])
	quit()
