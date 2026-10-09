extends SceneTree
const Strokes = preload("res://scripts/atlas/ink_strokes.gd")
const Contours = preload("res://scripts/atlas/contours.gd")
var errors := 0
func check(ok: bool,label: String) -> void:
	if not ok: errors += 1; print("STROKE_FAIL ",label)
func covered(mesh: ArrayMesh,point: Vector2) -> bool:
	var arrays := mesh.surface_get_arrays(0); var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		var a := verts[indices[i]]; var b := verts[indices[i+1]]; var c := verts[indices[i+2]]
		if Geometry2D.is_point_in_polygon(point,PackedVector2Array([Vector2(a.x,a.y),Vector2(b.x,b.y),Vector2(c.x,c.y)])): return true
	return false
func _initialize() -> void:
	var loop := PackedVector2Array([Vector2(10,10),Vector2(40,10),Vector2(40,40),Vector2(10,40),Vector2(10,10)])
	var mesh := Strokes.build([loop],2,.1)
	check(not covered(mesh,Vector2(25,25)),"closed loop filled province interior")
	check(covered(mesh,Vector2(20,10)),"closed boundary missing")
	var dashes := Strokes.dashes(PackedVector2Array([Vector2.ZERO,Vector2(2,0),Vector2(2,5)]),4,2)
	check(dashes.size()==2 and dashes[0].path.size()==3,"dash must cross polyline vertex")
	check(dashes[0].path[-1]==Vector2(2,2),"dash length changed at corner")
	var cap := Strokes.build([PackedVector2Array([Vector2.ZERO,Vector2(10,0)])],2,.1)
	check(covered(cap,Vector2(-.6,.6)) and not covered(cap,Vector2(-1.,1.)),"round cap footprint")
	var mask := PackedByteArray([0,0,0,0,0,1,0,0,0,0,0,0]); var contours := Contours.trace(4,3,mask)
	check(contours.size()==1 and contours[0][0]==contours[0][-2],"closed island contour")
	var wrapped := Contours.trace(4,3,PackedByteArray([0,0,0,0,1,0,0,1,0,0,0,0]))
	check(wrapped.size()==1,"seam island split")
	for p in wrapped:
		for i in range(2,p.size(),2): check(absf(p[i]-p[i-2])<=2,"seam contour crossed world")
	print("ATLAS_NATIVE_STROKES failures=",errors); quit(1 if errors else 0)
