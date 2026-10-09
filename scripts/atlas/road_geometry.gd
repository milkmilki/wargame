extends RefCounted
## Display and simulation share these validated curves; raw paths remain recoverable.
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const BUCKET := 16.

static func length_units(path: PackedVector2Array) -> float:
	var angle := 0.
	for index in range(1,path.size()): angle += Edge.spherical_angle(path[index-1]/Vector2(2048,1024),path[index]/Vector2(2048,1024))
	return angle*40000./TAU/250.

static func bucket_keys(a: Vector2,b: Vector2) -> Array[int]:
	var keys: Array[int] = []
	for y in range(floori(minf(a.y,b.y)/BUCKET),floori(maxf(a.y,b.y)/BUCKET)+1):
		for x in range(floori(minf(a.x,b.x)/BUCKET),floori(maxf(a.x,b.x)/BUCKET)+1): keys.append(y*128+posmod(x,128))
	return keys

static func insert(index: Dictionary,path: PackedVector2Array,id: int) -> void:
	for i in range(1,path.size()):
		var segment := {"a":path[i-1],"b":path[i],"id":id}
		for key in bucket_keys(segment.a,segment.b):
			if not index.has(key): index[key] = []
			index[key].append(segment)

static func index_paths(paths: Array) -> Dictionary:
	var index := {}
	for id in range(paths.size()): insert(index,paths[id],id)
	return index

static func intersects_others(path: PackedVector2Array,index: Dictionary,id: int) -> bool:
	for i in range(1,path.size()):
		var a := path[i-1]; var b := path[i]
		for key in bucket_keys(a,b):
			for segment in index.get(key,[]):
				if segment.id==id: continue
				var shift: float = round((a.x-segment.a.x)/2048.)*2048.
				var p: Vector2 = segment.a+Vector2(shift,0.); var q: Vector2 = segment.b+Vector2(shift,0.)
				var intersection: Variant = Geometry2D.segment_intersects_segment(a,b,p,q)
				if intersection==null: continue
				# Only an actual shared endpoint is a legal junction.
				var common: bool = (intersection.distance_to(path[0])<.001 or intersection.distance_to(path[-1])<.001) and (intersection.distance_to(p)<.001 or intersection.distance_to(q)<.001)
				if not common: return true
	return false

static func surface_legal(path: PackedVector2Array,raster: Dictionary,districts: PackedInt32Array,owner: int) -> bool:
	for i in range(1,path.size()):
		var a := path[i-1]; var b := path[i]; var samples := maxi(1,ceili(a.distance_to(b)/.5))
		for sample in range(samples+1):
			var point := a.lerp(b,float(sample)/samples); var x := floori(fposmod(point.x,2048.)); var y := floori(point.y)
			if y<0 or y>=1024: return false
			var offset := y*2048+x
			if raster.water[offset]!=0: return false
			# Border endpoints are fixed; tolerate the raster's subpixel endpoint tie.
			if districts[offset]!=owner and point.distance_to(path[0])>1. and point.distance_to(path[-1])>1.: return false
	return true

static func smooth_path(raw: PackedVector2Array,raster: Dictionary,districts: PackedInt32Array,owner: int,index: Dictionary,id: int) -> Dictionary:
	for rounds in [3,2,1]:
		var path := Geometry.chaikin(raw,false,rounds)
		if surface_legal(path,raster,districts,owner) and not intersects_others(path,index,id): return {"path":path,"rounds":rounds}
	return {"path":raw.duplicate(),"rounds":0}

static func apply(graph: Dictionary,raster: Dictionary,districts: PackedInt32Array) -> Dictionary:
	var paths: Array = []
	for edge in graph.edges: paths.append(edge.raw_path)
	var index := index_paths(paths); var histogram := [0,0,0,0]
	for id in range(graph.edges.size()):
		var edge: Dictionary = graph.edges[id]
		var result := smooth_path(edge.raw_path,raster,districts,edge.control_city,index,id)
		edge.path = result.path; edge.smooth_rounds = result.rounds; histogram[result.rounds] += 1
		edge.distance_units = length_units(edge.path)
		if result.rounds>0: insert(index,edge.path,id)
	return {"rounds_histogram":histogram}
