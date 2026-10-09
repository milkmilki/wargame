extends SceneTree
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_TRAFFIC_FAIL ",message)
func _initialize() -> void:
	var builder = load("res://scripts/atlas/traffic_graph.gd")
	if builder==null: print("ATLAS_TRAFFIC_FAIL missing builder"); quit(1); return
	var mesh := {"n":5,"width":2048.,"height":1024.,"x":PackedFloat32Array([100,110,120,110,110]),"y":PackedFloat32Array([100,100,100,90,110]),"adj_start":PackedInt32Array([0,1,5,6,7,8]),"adj":PackedInt32Array([1,0,2,3,4,1,1,1])}
	var hierarchy := {"cities":[{"cell":0,"role":"zhou"},{"cell":2,"role":"fu"}],"district_of_cell":PackedInt32Array([0,0,1,0,1])}
	var network := {"slots":PackedByteArray([2,2,2,2,2,2,2,2]),"protected_slots":PackedByteArray([2,2,2,0,0,2,0,0])}
	var graph: Dictionary = builder.build(mesh,hierarchy,network)
	check(graph.nodes.size()>2,"junction and boundary traffic nodes")
	var keys := {}; var length := 0.
	for edge in graph.edges:
		var key: int = mini(edge.a,edge.b)*graph.nodes.size()+maxi(edge.a,edge.b)
		check(edge.a!=edge.b and not keys.has(key),"simple undirected interface preserved"); keys[key] = true
		check(edge.control_city in [0,1],"segment has one controlling district")
		for i in range(1,edge.path.size()): length += edge.path[i-1].distance_to(edge.path[i])
	check(is_equal_approx(length,40.),"sharing and boundary splits preserve physical length")
	check(graph.nodes[0].role=="zhou" and graph.nodes[1].role=="fu","settlement identity preserved")
	var parallel_mesh := {"n":4,"width":2048.,"height":1024.,"x":PackedFloat32Array([100,120,110,110]),"y":PackedFloat32Array([100,100,90,110]),"adj_start":PackedInt32Array([0,2,4,6,8]),"adj":PackedInt32Array([2,3,2,3,0,1,0,1])}
	var parallel_h := {"cities":[{"cell":0,"role":"zhou"},{"cell":1,"role":"fu"}],"district_of_cell":PackedInt32Array([0,0,0,0])}
	graph = builder.build(parallel_mesh,parallel_h,network)
	check(graph.edges.size()==3 and graph.nodes.size()==3,"parallel roads retained with intermediate traffic point")
	var loop_mesh := {"n":4,"width":2048.,"height":1024.,"x":PackedFloat32Array([100,110,110,100]),"y":PackedFloat32Array([100,100,110,110]),"adj_start":PackedInt32Array([0,2,4,6,8]),"adj":PackedInt32Array([1,3,0,2,1,3,0,2])}
	var loop_h := {"cities":[{"cell":0,"role":"zhou"}],"district_of_cell":PackedInt32Array([0,0,0,0])}
	graph = builder.build(loop_mesh,loop_h,network)
	check(graph.edges.size()==3,"loop retained without self-loop edge")
	keys.clear()
	for edge in graph.edges:
		var key: int = mini(edge.a,edge.b)*graph.nodes.size()+maxi(edge.a,edge.b)
		check(edge.a!=edge.b and not keys.has(key),"loop simple interface"); keys[key] = true
	var repeated: Dictionary = builder.build(loop_mesh,loop_h,network)
	check(var_to_bytes(graph)==var_to_bytes(repeated),"stable traffic node IDs")
	print("ATLAS_TRAFFIC_GRAPH failures=",failures); quit(1 if failures else 0)
