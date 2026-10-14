extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("SHIPPING_FAIL ",message)
func run():
	var path := "res://scripts/atlas/shipping.gd"
	check(ResourceLoader.exists(path),"trade-only sea route generation exists")
	if not ResourceLoader.exists(path): quit(1); return
	var shipping = load(path)
	var starts := PackedInt32Array([0]); var adjacency := PackedInt32Array(); var lengths := PackedFloat32Array()
	var links := [[0,1],[1,2],[2,3],[3,4],[0,7],[6,5],[5,2]]
	for cell in range(8):
		for link in links:
			if cell==link[0]: adjacency.append(link[1]); lengths.append(10.)
			elif cell==link[1]: adjacency.append(link[0]); lengths.append(10.)
		starts.append(adjacency.size())
	var mesh := {"n":8,"width":2048.,"height":1024.,"x":PackedFloat32Array([900,910,920,930,940,920,920,900]),"y":PackedFloat32Array([500,500,500,500,500,510,520,510]),"adj_start":starts,"adj":adjacency,"lengths":lengths}
	var data := {"mesh":mesh,"environment":{"water":PackedByteArray([0,1,1,1,0,2,0,0]),"biome":PackedByteArray([9,1,1,1,9,1,9,9])}}
	var hierarchy := {"cities":[{"cell":0},{"cell":4},{"cell":6},{"cell":7}]}
	mesh.xyz=PackedFloat32Array()
	for cell in range(mesh.n):
		var longitude: float=float(mesh.x[cell])/2048.*TAU
		mesh.xyz.append_array(PackedFloat32Array([cos(longitude),sin(longitude),0.]))
	var initial := hash([data,hierarchy])
	var result: Dictionary = shipping.build(data,hierarchy)
	check(result.routes.size()==1 and result.ports==[0,1],"only sea-coastal settlements become ports; lake shore is excluded")
	check(hash([data,hierarchy])==initial and result==shipping.build(data,hierarchy),"shipping generation is deterministic and leaves geography unchanged")
	if result.routes.is_empty(): quit(1); return
	for index in range(1,result.routes[0].cells.size()-1): check(data.environment.water[result.routes[0].cells[index]]==1,"intermediate shipping cells stay in the sea")
	var state := GameState.new()
	for id in range(2):
		var nation := Nation.new(); nation.id=id; nation.capital_city_id=id; state.nations.append(nation)
	for id in range(4):
		var city := City.new(); city.id=id; city.owner_nation=0 if id in [0,3] else 1
		city.map_position=Vector2(mesh.x[hierarchy.cities[id].cell]/2048.,mesh.y[hierarchy.cities[id].cell]/1024.); city.gold_per_month=10
		state.cities.append(city); state.adjacency[id]=[] as Array[int]
	state.region_ids=PackedInt32Array([0,1,2,0]); state.administrative_center_by_city=PackedInt32Array([0,1,2,3])
	var land := Edge.new(); land.city_a=0; land.city_b=3; state.edges.append(land); state.edge_lookup[GameState.edge_key(0,3)]=land
	state.adjacency[0]=[3] as Array[int]; state.adjacency[3]=[0] as Array[int]
	state.atlas_layout={"shipping":result,"settlement_adjacency":state.adjacency}
	var trade = load("res://scripts/core/trade_network.gd")
	var graph: Dictionary = trade.call("_build_trade_graph",state)
	check(graph.edge_lookup.has(GameState.edge_key(0,1)),"trade graph includes generated shipping")
	check(state.edge_of(0,1)==null and state.edges.size()==1 and state.neighbors(0)==[3],"military graph and land adjacency are unchanged")
	check(not TradeNetwork._build_graph(state).edge_lookup.has(GameState.edge_key(0,1)),"base graph used by regional logic stays land-only")
	var details := TradeNetwork._path_details(state,graph,[0,1] as Array[int])
	check(details.uses_water and details.bottleneck==Edge.WATER_MANPOWER,"shipping uses existing sea trade capacity")
	state.trade_routes=[{"city_path":[0,1],"status":TradeNetwork.ACTIVE}] as Array[Dictionary]
	var segments := preload("res://scripts/atlas/trade_view.gd").route_segments(state)
	check(segments.size()==1 and segments[0].path.size()>=2,"published trade view resolves actual sea geometry")
	print("ATLAS_SHIPPING checks=",checks," failures=",failures)
	quit(1 if failures else 0)
