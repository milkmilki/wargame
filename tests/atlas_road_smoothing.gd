extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_ROAD_SMOOTH_FAIL ",message)
func _initialize() -> void:
	var builder = load("res://scripts/atlas/road_geometry.gd")
	if builder==null: print("ATLAS_ROAD_SMOOTH_FAIL missing builder"); quit(1); return
	var water := PackedByteArray(); water.resize(2048*1024)
	var owners := PackedInt32Array(); owners.resize(water.size())
	var raw := PackedVector2Array([Vector2(100,100),Vector2(110,100),Vector2(110,110)])
	var raster := {"water":water,"w":2048,"h":1024}
	var good: Dictionary = builder.smooth_path(raw,raster,owners,0,{},-1)
	check(good.rounds==3 and good.path[0]==raw[0] and good.path[-1]==raw[-1],"legal curves with fixed connections")
	for y in range(101,110):
		for x in range(101,110): water[y*2048+x] = 1
	raster.water = water
	var blocked: Dictionary = builder.smooth_path(raw,raster,owners,0,{},-1)
	check(blocked.rounds==0 and blocked.path==raw,"illegal coast shortcut falls back to raw")
	raster.water.fill(0)
	var crossing := PackedVector2Array([Vector2(108,101),Vector2(108,109)])
	var index: Dictionary = builder.index_paths([crossing])
	var junction: Dictionary = builder.smooth_path(raw,raster,owners,0,index,1)
	check(not builder.intersects_others(junction.path,index,1),"no invented road intersections")
	var equator := PackedVector2Array([Vector2(0,512),Vector2(10,512)])
	var sixty := PackedVector2Array([Vector2(0,1024./6.),Vector2(10,1024./6.)])
	check(is_equal_approx(builder.length_units(equator),10.*40000./2048./250.),"equatorial kilometer scale")
	check(absf(builder.length_units(sixty)/builder.length_units(equator)-.5)<.0001,"high latitude uses spherical length rather than stretched projection")
	check(is_equal_approx(builder.length_units(PackedVector2Array([Vector2(2040,512),Vector2(2050,512)])),builder.length_units(equator)),"wrapped meridian length")
	print("ATLAS_ROAD_SMOOTHING failures=",failures); quit(1 if failures else 0)
