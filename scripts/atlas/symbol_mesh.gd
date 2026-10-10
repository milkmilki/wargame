extends RefCounted
## Ordered triangles replace thousands of native vector draw commands. Numerical
## arrays are constructed on the worker; material clipping stays on the GPU.
var vertices := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var offset := Vector2.ZERO
var aa := .55
var finished: Array = []
func transform(value: Vector2) -> void: offset = value
func vertex(point: Vector2,color: Color) -> int:
	var id := vertices.size(); vertices.append(point+offset); colors.append(color); return id
func triangle(a: int,b: int,c: int) -> void: indices.append_array(PackedInt32Array([a,b,c]))
func polygon(points: PackedVector2Array,color: Color) -> void:
	if points.size()<3: return
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty(): return
	var base := vertices.size()
	for point in points: vertex(point,color)
	for i in triangles: indices.append(base+i)
	finish_command()
func line(points: PackedVector2Array,color: Color,width: float,_antialias: bool = true) -> void:
	if points.size()<2: return
	var closed := points.size()>2 and points[0].is_equal_approx(points[-1]); var count := points.size()-1 if closed else points.size()
	var base := vertices.size(); var half := width*.5
	for i in range(count):
		var before: Vector2 = points[i]-points[posmod(i-1,count)] if i>0 or closed else points[1]-points[0]
		var after: Vector2 = points[posmod(i+1,count)]-points[i] if i+1<count or closed else before
		if before.length_squared()<1e-10: before = after
		if after.length_squared()<1e-10: after = before
		var n0 := Vector2(-before.y,before.x).normalized(); var n1 := Vector2(-after.y,after.x).normalized()
		var normal := (n0+n1).normalized(); var miter := normal/maxf(.35,absf(normal.dot(n0)))
		var fade := Color(color,0.)
		vertex(points[i]-miter*(half+aa),fade); vertex(points[i]-miter*half,color)
		vertex(points[i]+miter*half,color); vertex(points[i]+miter*(half+aa),fade)
	for i in range(count if closed else count-1):
		var a := base+i*4; var b := base+posmod(i+1,count)*4
		for j in range(3): triangle(a+j,a+j+1,b+j+1); triangle(a+j,b+j+1,b+j)
	finish_command()
func segment(a: Vector2,b: Vector2,color: Color,width: float,_antialias: bool = true) -> void:
	line(PackedVector2Array([a,b]),color,width)
func arc(center: Vector2,radius: float,start: float,end: float,count: int,color: Color,width: float,_antialias: bool = true) -> void:
	var points := PackedVector2Array()
	for i in range(count+1): points.append(center+Vector2(cos(lerpf(start,end,float(i)/count)),sin(lerpf(start,end,float(i)/count)))*radius)
	line(points,color,width)
func arrays() -> Dictionary:
	var row := {"vertices":vertices,"colors":colors,"indices":indices}
	return row if finished.is_empty() else {"parts":finished+[row]}
func finish_command() -> void:
	if vertices.size()<16384: return
	finished.append({"vertices":vertices,"colors":colors,"indices":indices})
	vertices = PackedVector2Array(); colors = PackedColorArray(); indices = PackedInt32Array()
static func resource(row: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for part in row.get("parts",[row]): append(mesh,part)
	return mesh
static func append(mesh: ArrayMesh,row: Dictionary) -> void:
	if row.vertices.is_empty(): return
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = row.vertices; arrays[Mesh.ARRAY_COLOR] = row.colors; arrays[Mesh.ARRAY_INDEX] = row.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
