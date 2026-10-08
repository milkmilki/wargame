extends SceneTree
const Roads=preload("res://scripts/core/atlas_road_network.gd")
const Pixel=preload("res://scripts/core/province_pixel_route.gd")
func _init() -> void:
	var d: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://.dbg/atlas-road-failure.json"))
	var ids:=PackedInt32Array(d.ids);var grid:=Vector2i(d.grid[0],d.grid[1])
	var source: Image=(load("res://assets/terrain/eurasia_mercator_elevation_white_4096.png") as Texture2D).get_image()
	var a:=Vector2(d.positions[2][0],d.positions[2][1]);var b:=Vector2(d.positions[8][0],d.positions[8][1])
	var options: Dictionary={"image":source,"aspect":2.879,"maximum_height":1.0,"river_paths":[]}
	OS.set_environment("HYDROLOGY_DIAGNOSE","1")
	for scale in [4,1]:
		var path:=Pixel._find(ids,grid,a,b,2,8,options,scale)
		print("ATLAS_PROBE scale=",scale," points=",path.size()," legal=",Roads.path_valid(path,{"ids":ids,"size":grid},2,8,options))
		if path.size()>0:
			for i in range(path.size()-1):
				if not Roads.path_valid(PackedVector2Array([path[i],path[i+1]]),{"ids":ids,"size":grid},2,8,options): print("ILLEGAL_SEGMENT ",i," ",path[i]," ",path[i+1])
	quit()
