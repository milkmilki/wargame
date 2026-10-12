extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func edge(state: GameState,a: int,b: int,control: int) -> Edge:
	var road:=Edge.new();road.city_a=a;road.city_b=b;road.control_city_id=control
	state.edges.append(road);state.adjacency[a].append(b);state.adjacency[b].append(a)
	state.edge_lookup[GameState.edge_key(a,b)]=road
	return road
func _init() -> void:
	var state:=GameState.new()
	for id in range(2):
		var nation:=Nation.new();nation.id=id;nation.capital_city_id=0 if id==0 else 3;state.nations.append(nation)
	for id in range(5):
		var city:=City.new();city.id=id;city.owner_nation=0 if id<3 else 1 if id==3 else -1
		city.node_kind=City.NodeKind.TRAFFIC if id==4 else City.NodeKind.SETTLEMENT
		city.politically_active=id!=4
		state.cities.append(city);state.adjacency[id]=[] as Array[int]
	state.atlas_layout={"model":"atlas-military-v1"}
	edge(state,0,4,0);var rear:=edge(state,4,1,1);edge(state,0,2,2)
	check(state.enfeoff_region_closure(0,[2] as Array[int])==[2],"ownerless junction keeps home city connected without bloating fief")
	check(state.cities[4].owner_nation==-1,"junction remains politically ownerless")
	rear.control_city_id=2
	check(state.enfeoff_region_closure(0,[2] as Array[int])==[1,2],"road crossing granted jurisdiction really cuts the home city")
	rear.control_city_id=3
	check(state.enfeoff_region_closure(0,[2] as Array[int])==[1,2],"foreign road cannot preserve direct administration")
	rear.control_city_id=-1
	check(state.enfeoff_region_closure(0,[2] as Array[int])==[1,2],"unassigned Atlas road cannot provide administrative access")
	rear.control_city_id=1;rear.max_manpower=0
	check(state.enfeoff_region_closure(0,[2] as Array[int])==[1,2],"blocked-capacity road still creates a real enclave")
	rear.max_manpower=15000;state.atlas_layout.clear()
	check(state.enfeoff_region_closure(0,[2] as Array[int])==[1,2],"legacy graph retains owner-based endpoint rule")
	print("ATLAS_ENFEOFF_CONNECTIVITY checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
