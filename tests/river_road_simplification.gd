extends SceneTree
const Generator = preload("res://scripts/core/terrain_map_generator.gd")
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
const SIZE := Vector2i(32,32)
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("RIVER_ROAD_SIMPLIFICATION_FAIL: ",message)

func fixture() -> Dictionary:
	var ids := PackedInt32Array()
	ids.resize(SIZE.x*SIZE.y)
	ids.fill(0)
	var image := Image.create(256,256,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,(128.0+12.7)/255.0))
	return {"ids":ids,"image":image}

func strict_path(f: Dictionary,from: Vector2,to: Vector2,blocked: Dictionary = {},rivers: Array[PackedVector2Array] = []) -> PackedVector2Array:
	return Generator.province_pair_path(f.ids,SIZE,from,to,0,0,blocked,{"strict":true,"image":f.image,"aspect":1.0,"river_paths":rivers})

func safe_segments(path: PackedVector2Array,image: Image,rivers: Array[PackedVector2Array],label: String) -> void:
	for i in range(path.size()-1):
		var a := path[i]
		var b := path[i+1]
		for river in rivers:
			for k in range(river.size()-1):
				check(Geometry2D.segment_intersects_segment(a,b,river[k],river[k+1]) == null,label+" segment must not cross or touch main river")
		var steps := maxi(1,ceili(((b-a)*Vector2(image.get_size())).length()*4.0))
		var minimum := INF
		var maximum := -INF
		for k in range(steps+1):
			var point := a.lerp(b,float(k)/steps)
			var pixel := Vector2i(point*Vector2(image.get_size())).clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)
			var alpha := image.get_pixelv(pixel).a*255.0
			if alpha <= 128.0:
				check(false,label+" segment enters sea")
				break
			var height := maxf((alpha-128.0)/127.0,0.0)
			minimum = minf(minimum,height)
			maximum = maxf(maximum,height)
		check(maximum-minimum <= 0.20001,label+" segment crosses a height difference above 0.2")

func run() -> void:
	var f := fixture()
	var from := Vector2(4.5,7.5)/Vector2(SIZE)
	var to := Vector2(25.5,23.5)/Vector2(SIZE)
	# Keep a harmless blocked edge to exercise the former unconditional raw-path
	# branch without introducing a river across the desired diagonal shortcut.
	var blocked := {Hydro.edge_key(0,1,SIZE.x*SIZE.y):true}
	var legacy := Generator.province_pair_path(f.ids,SIZE,from,to,0,0,blocked)
	var flat := strict_path(f,from,to,blocked)
	check(legacy.size() > 2,"legacy blocked-edge call keeps raw grid route")
	for i in range(legacy.size()-1):
		var delta := legacy[i+1]-legacy[i]
		check(absf(delta.x) < 0.000001 or absf(delta.y) < 0.000001,"legacy route remains orthogonal")
	check(flat.size() == 2 and flat[0] == from and flat[1] == to,"strict flat route simplifies to exact endpoints")
	safe_segments(flat,f.image,[],"flat")
	var river := PackedVector2Array([Vector2(0.5,0.25),Vector2(0.5,0.75)])
	var feature := MapFeatureContract.make_river(0,river,MapFeatureContract.SOURCE_PROCEDURAL_HYDROLOGY)
	var river_blocked := Hydro.barriers([feature],SIZE)
	var start := Vector2(0.2,0.5)
	var end := Vector2(0.8,0.5)
	var detour := strict_path(f,start,end,river_blocked,[river])
	check(detour.size() > 2,"finite river requires a genuine source/mouth detour")
	safe_segments(detour,f.image,[river],"finite river")
	var road_ids: PackedInt32Array = f.ids.duplicate()
	for y in range(SIZE.y):
		for x in range(SIZE.x): road_ids[y*SIZE.x+x] = 0 if x < SIZE.x/2 else 1
	var road_image: Image = f.image.duplicate()
	road_image.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_NEAREST)
	var land := PackedByteArray()
	land.resize(SIZE.x*SIZE.y)
	land.fill(1)
	var points: Array[Vector2] = [start,end]
	var pixels: Array[Vector2i] = [Vector2i(start*Vector2(SIZE)),Vector2i(end*Vector2(SIZE))]
	var paths: Array[Array] = [Array(river)]
	var roads := Generator._build_roads(road_image,land,{"positions":points,"pixels":pixels},1.0,{"size":SIZE,"ids":road_ids,"routing_options":{"strict":true,"image":road_image,"aspect":1.0,"river_paths":[river]}},paths,river_blocked)
	check(not roads.roads.is_empty(),"road builder retains legal source detour")
	for road in roads.roads:
		if road.has("map_path"):
			check(is_equal_approx(road.length,Generator.metric_polyline_length(road.map_path,1.0)),"stored road distance uses detour length, not endpoint chord")
	for kind in ["sea","cliff"]:
		var terrain := fixture()
		for y in range(8,24):
			for x in range(15,17): terrain.ids[y*SIZE.x+x] = -1
		for y in range(64,192):
			for x in range(120,136): terrain.image.set_pixel(x,y,Color(1,1,1,0.4 if kind == "sea" else (128.0+63.5)/255.0))
		var path := strict_path(terrain,start,end)
		check(path.size() > 2,kind+" has a legal grid detour and must not simplify through obstacle")
		safe_segments(path,terrain.image,[],kind)
	# Fine DEM barriers may be absent from the coarse province raster. If even
	# the next raw grid hop is unsafe, simplification must not emit it by fallback.
	for kind in ["sea","cliff"]:
		var fine := fixture()
		for y in range(256): fine.image.set_pixel(128,y,Color(1,1,1,0.4 if kind == "sea" else (128.0+63.5)/255.0))
		var impossible := strict_path(fine,start,end)
		check(impossible.is_empty(),"unrepresented full-height fine "+kind+" barrier fails closed instead of emitting unsafe raw hop")
		safe_segments(impossible,fine.image,[],"fine "+kind)
	print("RIVER_ROAD_SIMPLIFICATION_DIAGNOSTIC legacy_points=%d flat_points=%d river_detour_points=%d" % [legacy.size(),flat.size(),detour.size()])
	print("RIVER_ROAD_SIMPLIFICATION: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
