extends SceneTree
func _initialize():
	var builder := preload("res://scripts/atlas/symbol_mesh.gd").new()
	builder.polygon(PackedVector2Array([Vector2.ZERO,Vector2(4,0),Vector2(2,4)]),Color.RED)
	builder.line(PackedVector2Array([Vector2.ZERO,Vector2(1,2),Vector2(3,0)]),Color(.2,.3,.4,.8),1.)
	var row := builder.arrays(); var mesh := builder.resource(row)
	if mesh.get_surface_count()!=1 or row.indices.size()!=39 or row.colors[0]!=Color.RED:
		printerr("ATLAS_SYMBOL_MESH_FAIL ordered native triangles"); quit(1); return
	print("ATLAS_SYMBOL_MESH passed"); quit()
