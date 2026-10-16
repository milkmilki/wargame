extends SceneTree
const Builder = preload("res://scripts/atlas/zhoufu_roads.gd")
const Traffic = preload("res://scripts/atlas/traffic_graph.gd")
const Access = preload("res://tests/atlas_access_and_repatriation.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("JURISDICTION_ROADS_FAIL ",message)
static func fixture(block_border: bool = false) -> Dictionary:
	# A and B share a long border road; the cheap shortcut crosses neutral C.
	var points := [Vector2(100,500),Vector2(100,480),Vector2(105,510),Vector2(110,500),Vector2(110,480),Vector2(105,500)]
	var mesh := {"n":6,"width":2048.,"height":1024.,"x":PackedFloat32Array(),"y":PackedFloat32Array(),"xyz":PackedFloat32Array(),"adj":PackedInt32Array(),"adj_start":PackedInt32Array(),"lengths":PackedFloat32Array()}
	var neighbors := [[1,5],[0,4],[5],[4,5],[1,3],[0,2,3]]
	for id in range(6):
		mesh.x.append(points[id].x); mesh.y.append(points[id].y)
		var lon: float=points[id].x/2048.*TAU-PI; var lat: float=PI*.5-points[id].y/1024.*PI
		mesh.xyz.append_array(PackedFloat32Array([cos(lat)*cos(lon),cos(lat)*sin(lon),sin(lat)]))
		mesh.adj_start.append(mesh.adj.size())
		for next in neighbors[id]: mesh.adj.append(next); mesh.lengths.append(points[id].distance_to(points[next]))
	mesh.adj_start.append(mesh.adj.size())
	var environment := {"water":PackedByteArray([0,0,0,0,0,0]),"biome":PackedByteArray([1,1,1,1,1,1]),"elevation":PackedFloat32Array([0,0,0,0,0,0])}
	if block_border: environment.water[4]=1
	var labels := PackedInt32Array([0,0,2,1,1,2])
	var hierarchy := {"cities":[{"cell":0,"role":"zhou","major":false},{"cell":3,"role":"zhou","major":false},{"cell":2,"role":"zhou","major":false}],"district_of_cell":labels,"center_by_city":PackedInt32Array([0,1,2]),"mandatory_connections":[]}
	return {"mesh":mesh,"environment":environment,"hierarchy":hierarchy,"regions":{"of":labels}}
static func install(graph: Dictionary) -> GameState:
	var state := Access._fixture([] as Array[Vector3i])
	state.edges.clear(); state.edge_lookup.clear()
	for id in range(state.cities.size()):
		state.adjacency[id]=[] as Array[int]
		if id>=3:
			state.cities[id].node_kind=City.NodeKind.TRAFFIC; state.cities[id].politically_active=false; state.cities[id].owner_nation=-1
	for edge in graph.edges:
		state._add_edge(edge.a,edge.b)
		state.edge_of(edge.a,edge.b).control_city_id=edge.control_city
	state.road_network_revision+=1
	return state
func run() -> void:
	for blocked in [false,true]:
		var input := fixture(blocked)
		var network := Builder.build(input.mesh,input.environment,input.regions,input.hierarchy)
		for connection in network.connections:
			if not connection.get("jurisdiction_entry",false):continue
			check(connection.cells[0]==input.hierarchy.cities[connection.a].cell and connection.cells[-1]==input.hierarchy.cities[connection.b].cell,"new connection has its real settlement endpoints")
			for cell in connection.cells:
				check(input.hierarchy.district_of_cell[cell] in [connection.a,connection.b] and input.environment.water[cell]==0,"added road stays on land in its two real jurisdictions")
			for index in range(1,connection.cells.size()):
				var slot:=preload("res://scripts/atlas/roads.gd").slot_of(input.mesh,connection.cells[index-1],connection.cells[index])
				check(network.slots[slot]>0 and network.protected_slots[slot]>0,"local entry is protected from later pruning")
		var state := install(Traffic.build(input.mesh,input.hierarchy,network))
		check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1]))!=blocked,"forward attack uses only its two jurisdictions, respecting a water break")
		check(is_finite(float(Pathfinding.dijkstra_field(state,1,1,false,false,0).dist[0]))!=blocked,"counterattack has the same lawful land connection")
		check(state.relation_between(0,2)==GameState.DiplomaticRelation.NEUTRAL,"repair keeps the third country neutral")
		check(not is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,-1).dist[2])),"neutral city cannot become a transit shortcut")
		var duplicate := Builder.build(input.mesh,input.environment,input.regions,input.hierarchy)
		check(var_to_bytes(duplicate)==var_to_bytes(network),"road repair is deterministic")
	for centers in [PackedInt32Array([0,0,0]),PackedInt32Array([0,1,1])]:
		var input:=fixture()
		input.hierarchy.center_by_city=centers
		var network:=Builder.build(input.mesh,input.environment,input.regions,input.hierarchy)
		check(network.jurisdiction_repair.added_connections==0,"connected state interiors and existing state-border entries do not gain redundant shortcuts")
	print("JURISDICTION_ROADS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
