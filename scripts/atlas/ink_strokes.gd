extends RefCounted
## Canvas round joins/caps implemented as cached native stroke meshes.
## Keeps complete dash paths instead of restarting a stroke at every curve segment.
const Maths = preload("res://scripts/atlas/math.gd")

static func dashes(path: PackedVector2Array,dash: float,gap: float,vary_pen: bool = false) -> Array:
	var out: Array = []; var phase := 0.0; var current := PackedVector2Array(); var tier := 0
	for i in range(1,path.size()):
		var ax := float(path[i-1].x); var ay := float(path[i-1].y); var dx := float(path[i].x)-ax; var dy := float(path[i].y)-ay
		var length := sqrt(dx*dx+dy*dy); var t := 0.0
		while t<length:
			var in_dash := phase<dash; var step := minf((dash if in_dash else dash+gap)-phase,length-t)
			if in_dash:
				var x := ax+dx*t/length; var y := ay+dy*t/length
				if current.is_empty():
					current.append(Vector2(x,y))
					if vary_pen:
						var w := Maths.value_noise(x/7,y/7,23); tier = mini(2,floori(w*w*3*1.6))
				current.append(Vector2(ax+dx*(t+step)/length,ay+dy*(t+step)/length))
			t += step; phase += step
			if phase>=dash and not current.is_empty(): out.append({"path":current,"tier":tier}); current = PackedVector2Array()
			if phase>=dash+gap: phase -= dash+gap
	if not current.is_empty(): out.append({"path":current,"tier":tier})
	return out

static func build(paths: Array,width: float,aa_width: float,end_type: int = Geometry2D.END_ROUND) -> ArrayMesh:
	var vertices := PackedVector3Array(); var colors := PackedColorArray(); var indices := PackedInt32Array()
	var open_paths: Array = []
	for path in paths:
		# A closed offset yields an outer polygon plus a hole. Split the ribbon to
		# avoid treating the hole as a filled polygon in Godot's triangulator.
		if path.size()>3 and path[0].distance_to(path[-1])<1e-5:
			var middle: int = path.size()/2; open_paths.append(path.slice(0,middle+1)); open_paths.append(path.slice(middle))
		else: open_paths.append(path)
	for path in open_paths:
		if path.size()<2: continue
		var enlarged := PackedVector2Array()
		for p in path: enlarged.append(p*64.)
		# Clipper's fixed arc tolerance is measured in input units. Work enlarged
		# so round caps stay round at 8x, then return to native map coordinates.
		for polygon in Geometry2D.offset_polyline(enlarged,width*32.,Geometry2D.JOIN_ROUND,end_type):
			for i in range(polygon.size()): polygon[i] /= 64.
			if polygon.size()<3: continue
			var triangles := Geometry2D.triangulate_polygon(polygon)
			if triangles.is_empty(): continue
			var base := vertices.size(); var count := polygon.size(); var sign_value := -1.0 if Geometry2D.is_polygon_clockwise(polygon) else 1.0
			for p in polygon: vertices.append(Vector3(p.x,p.y,0)); colors.append(Color.WHITE)
			for index in triangles: indices.append(base+index)
			for i in range(count):
				var before: Vector2 = polygon[i]-polygon[posmod(i-1,count)]; var after: Vector2 = polygon[(i+1)%count]-polygon[i]
				var a := Vector2(before.y,-before.x).normalized(); var b := Vector2(after.y,-after.x).normalized(); var normal := (a+b).normalized()*sign_value
				var outer: Vector2 = polygon[i]+normal*aa_width/maxf(.2,normal.dot(a*sign_value))
				vertices.append(Vector3(outer.x,outer.y,0)); colors.append(Color(1,1,1,0))
			for i in range(count):
				var j := (i+1)%count
				indices.append_array(PackedInt32Array([base+i,base+j,base+count+j,base+i,base+count+j,base+count+i]))
	var mesh := ArrayMesh.new()
	if vertices.is_empty(): return mesh
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); return mesh
