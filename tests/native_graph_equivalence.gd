extends SceneTree
## Exact public query outputs, including Dictionary insertion order and predecessor ties.
const BACKEND_PATH := "res://scripts/core/native_compute.gd"
var _backend: Script
var _checks := 0
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not ResourceLoader.exists(BACKEND_PATH):
		printerr("NATIVE_GRAPH_RED missing runtime backend")
		quit(1)
		return
	_backend = load(BACKEND_PATH)
	if not _backend.has_method("set_backend_for_tests"):
		printerr("NATIVE_GRAPH_RED missing backend selection API")
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--blockers-only"):
		enemy_blocker_order()
		for message in _failures:printerr("NATIVE_GRAPH_FAIL ",message)
		print("NATIVE_BLOCKERS_RESULT checks=%d failures=%d"%[_checks,_failures.size()])
		quit(0 if _failures.is_empty() else 1)
		return
	for mirror in [false, true]:
		var state := fixture(mirror)
		for start in [0, 3, 4, 6]:
			for owner in [-1, 0, 1, 2]:
				for goal in [-1, 1, 2]:
					for danger in [false, true]:
						for contested in [false, true]:
							compare_path(state,start,owner,contested,danger,goal)
		for blocked in [{4:true}, {6:true}, {1:true}]:
			compare_path(state,0,0,false,true,-1,blocked)
		for start in [0,3,4,6]:
			for owner in [0,1,2]:
				for logistics in [false,true]:
					compare_supply(state,start,owner,[] as Array[int],logistics)
					compare_supply(state,start,owner,[3,4,3] as Array[int],logistics)
		for start in range(state.cities.size()):
			compare_threat(state,start)
		for operational in [false,true]:
			compare_trade(state,[0,3,0] as Array[int],operational,{}, {})
			compare_trade(state,[3,0] as Array[int],operational,{4:true},{GameState.edge_key(5,6):true})
			compare_trade(state,[0,3] as Array[int],operational,{},{},PackedByteArray())
			compare_trade(state,[0,3] as Array[int],operational,{},{},PackedByteArray([1,1]))
		state.edges[0].precise_distance=3000000.0
		compare_trade(state,[0] as Array[int],false,{}, {})
		state.edges[0].precise_distance=1.0
		state.cities[0].owner_nation=1
		state.ownership_revision+=1
		compare_path(state,4,0,false,true,-1,{},0)
		compare_path(state,4,0,false,true)
		compare_connectivity(state)
	invalid_kernel_inputs()
	city_editor_geometry()
	filtered_connectivity()
	segmented_route_capacity()
	strategic_route_boundaries()
	enemy_blocker_order()
	for message in _failures: printerr("NATIVE_GRAPH_FAIL ",message)
	print("NATIVE_GRAPH_RESULT checks=%d failures=%d"%[_checks,_failures.size()])
	quit(0 if _failures.is_empty() else 1)

func compare_path(state:GameState,start:int,owner:int,contested:bool,danger:bool,goal:int=-1,blocked:Dictionary={},exit_city:int=-1)->void:
	var random_before:=state.rng.state
	select_backend("gdscript")
	var expected:=Pathfinding.dijkstra_field(state,start,owner,contested,danger,goal,15000,blocked,exit_city)
	select_backend("native")
	var actual:=Pathfinding.dijkstra_field(state,start,owner,contested,danger,goal,15000,blocked,exit_city)
	check(var_to_bytes(expected)==var_to_bytes(actual),"path start=%d owner=%d goal=%d danger=%s contested=%s exit=%d"%[start,owner,goal,danger,contested,exit_city])
	check(random_before==state.rng.state,"path does not consume RNG")

func compare_supply(state:GameState,start:int,owner:int,origins:Array[int],logistics:bool)->void:
	select_backend("gdscript")
	var expected:=Pathfinding._supply_loss_field(state,start,owner,{},false,origins,logistics)
	select_backend("native")
	var actual:=Pathfinding._supply_loss_field(state,start,owner,{},false,origins,logistics)
	check(var_to_bytes(expected)==var_to_bytes(actual),"supply start=%d owner=%d origins=%s logistics=%s"%[start,owner,origins,logistics])

func compare_threat(state:GameState,start:int)->void:
	select_backend("gdscript")
	var oracle:=ThreatField.new()
	var expected:=oracle._travel_days_field(state,start,0)
	select_backend("native")
	var subject:=ThreatField.new()
	var actual:=subject._travel_days_field(state,start,0)
	check(var_to_bytes(expected)==var_to_bytes(actual),"threat ordered distances start=%d"%start)

func compare_trade(state:GameState,starts:Array[int],operational:bool,besieged:Dictionary,blocked:Dictionary,mask_override:Variant=null)->void:
	var adjacency:Array=[]
	for city in state.cities:adjacency.append(state.neighbors(city.id))
	var graph:Dictionary={"adjacency":adjacency,"edge_lookup":state.edge_lookup,"edges":state.edges}
	var allowed:=PackedByteArray()
	allowed.resize(state.cities.size())
	allowed.fill(1)
	allowed[2]=0
	if mask_override is PackedByteArray:allowed=mask_override
	select_backend("gdscript")
	var expected:=TradeNetwork._dijkstra_field(state,graph,starts,allowed,operational,besieged,blocked)
	select_backend("native")
	var actual:=TradeNetwork._dijkstra_field(state,graph,starts,allowed,operational,besieged,blocked)
	check(var_to_bytes(expected)==var_to_bytes(actual),"trade packed int64 cost / int32 heap starts=%s operational=%s"%[starts,operational])

func city_editor_geometry()->void:
	var state:=fixture(false)
	for id in [4,5]:
		state.cities[id].node_kind=City.NodeKind.SETTLEMENT
		state.cities[id].owner_nation=0
		state.cities[id].politically_active=true
	select_backend("native")
	var before:=Pathfinding.dijkstra_field(state,0,0,false,false)
	var previous_graph:RefCounted=_backend.call("_state_graph",state).graph
	var edited:=state.apply_city_editor_changes(4,{"terrain_height":.75,"terrain_relief":.25})
	check(bool(edited.get("ok",false)),"actual city editor accepts terrain geometry edit")
	# Keep native selected: switching backends would clear the cache and hide the defect.
	var expected:=Pathfinding._dijkstra_field_gdscript(state,0,0,false,false)
	var actual:=Pathfinding.dijkstra_field(state,0,0,false,false)
	check(var_to_bytes(before)!=var_to_bytes(expected),"terrain edit changes actual equal-distance predecessor choice")
	check(var_to_bytes(expected)==var_to_bytes(actual),"city editor invalidates native terrain tie keys without backend reset")
	check(previous_graph!=_backend.call("_state_graph",state).graph,"city editor retires cached native geometry")

func connectivity_result(state:GameState)->Dictionary:
	var snapshot:=StrategicMapSnapshot.new()
	snapshot._state=state
	snapshot.nation_id=0
	for city in state.cities:
		snapshot.city_value[city.id]=float(city.id)+.125
		if city.owner_nation==0:snapshot._total_friendly_value+=float(city.id)+.125
	snapshot._compute_connectivity()
	return {"disc":snapshot._disc,"low":snapshot._low,"subtree":snapshot._subtree_value,"articulation":snapshot.articulation_impact,"bridges":snapshot.bridge_impact,"values":snapshot.city_value}

func compare_connectivity(state:GameState)->void:
	state.atlas_layout={}
	for city in state.cities:
		if city.is_traffic:city.owner_nation=0
	select_backend("gdscript")
	var expected:=connectivity_result(state)
	select_backend("native")
	var actual:=connectivity_result(state)
	check(var_to_bytes(expected)==var_to_bytes(actual),"connectivity exact values and insertion order")
	check(not expected.bridges.is_empty(),"connectivity fixture includes bridges")
	check(not expected.articulation.is_empty(),"connectivity fixture includes articulation points")

func invalid_kernel_inputs()->void:
	if not ClassDB.class_exists("NativeGraphSnapshot"):
		check(false,"native kernel is actually loaded")
		return
	var invalid:RefCounted=ClassDB.instantiate("NativeGraphSnapshot")
	check(not bool(invalid.call("configure",PackedInt32Array([0,2]),PackedInt32Array([0]),PackedInt32Array([0]),PackedInt32Array([0]),PackedFloat64Array([.1,.2,.3,.4,.5]))),"invalid CSR offsets rejected")
	var subject:RefCounted=ClassDB.instantiate("NativeGraphSnapshot")
	var offsets:=PackedInt32Array([0,1,2])
	var targets:=PackedInt32Array([1,0])
	var ids:=PackedInt32Array([0,0])
	var controls:=PackedInt32Array([0])
	var geometry:=PackedFloat64Array([.1,.2,.3,.4,.5,.2,.3,.4,.5,.6])
	check(bool(subject.call("configure",offsets,targets,ids,controls,geometry)),"valid CSR accepted")
	check(not bool(subject.call("configure",offsets,targets,ids,controls,geometry)),"snapshot cannot be configured twice")
	check(var_to_bytes(subject.call("make_access_mask",PackedInt32Array([0,1]),{0:true,1:false}))==var_to_bytes({"mask":PackedByteArray([1])}),"native access-mask respects control owner permission")
	check((subject.call("make_access_mask",PackedInt32Array([0]),{0:true}) as Dictionary).has("error"),"native access-mask rejects invalid owner array")
	check((subject.call("make_access_mask",PackedInt32Array([0,1]),{0:1}) as Dictionary).has("error"),"native access-mask rejects nonboolean permission")

func filtered_connectivity()->void:
	for variant in ["normal","mirror","zero_sign"]:
		var state:=GameState.new()
		state._reset_world(81623)
		state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,2,false)
		for id in range(34):
			var city:=City.new()
			city.id=id
			city.owner_nation=1 if id in [7,14,21] else 0
			city.map_position=Vector2(.1,.5) if id==0 else Vector2(.25,.3)
			if id>25:city.map_position=Vector2(.3+float(id-26)*.0125,.3)
			if variant=="mirror":city.map_position.x=1.0-city.map_position.x
			elif variant=="zero_sign":city.map_position.x=.5
			state.cities.append(city)
			state.adjacency[id]=[] as Array[int]
		for id in range(1,34):
			var edge:=Edge.new()
			edge.city_a=0
			edge.city_b=id
			edge.control_city_id=0
			edge.max_manpower=0 if id%5==0 else 20000
			state.edges.append(edge)
			state.edge_lookup[GameState.edge_key(0,id)]=edge
			(state.adjacency[0] as Array[int]).append(id)
			(state.adjacency[id] as Array[int]).append(0)
		state.nations[0].capital_city_id=0
		state.nations[1].capital_city_id=7
		state.atlas_layout={"model":"native-filtered-star","territorial_pairs":[],"settlement_adjacency":state.adjacency.duplicate(true),"strategic_routes":{}}
		select_backend("gdscript")
		var expected:=connectivity_result(state)
		select_backend("native")
		var actual:=connectivity_result(state)
		check(var_to_bytes(expected)==var_to_bytes(actual),"filtered connectivity >16-neighbor equal-key introsort "+variant)
		check(expected.disc.size()>16 and expected.articulation.has(0),"filtered connectivity star exercises sorted-neighbor and root articulation "+variant)
		check(not expected.disc.has(7) and not expected.disc.has(14),"filtered connectivity excludes enemy-owned nodes "+variant)

func segmented_route_capacity()->void:
	var state:=GameState.new()
	state._reset_world(77239)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,1,false)
	for id in range(3):
		var city:=City.new()
		city.id=id
		city.map_position=Vector2(.1+float(id)*.2,.5)
		city.owner_nation=0 if id!=1 else -1
		if id==1:
			city.node_kind=City.NodeKind.TRAFFIC
			city.politically_active=false
		state.cities.append(city)
		state.adjacency[id]=[] as Array[int]
	for pair in [[0,1],[1,2]]:
		var edge:=Edge.new()
		edge.city_a=pair[0]
		edge.city_b=pair[1]
		edge.control_city_id=0
		edge.max_manpower=20000
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(pair[0],pair[1])]=edge
		(state.adjacency[pair[0]] as Array[int]).append(pair[1])
		(state.adjacency[pair[1]] as Array[int]).append(pair[0])
	state.nations[0].capital_city_id=0
	state.atlas_layout={"model":"native-segmented-capacity","settlement_adjacency":{0:[2] as Array[int],1:[] as Array[int],2:[0] as Array[int]},"strategic_routes":{"0:2":[0,1,2]},"territorial_pairs":[]}
	select_backend("native")
	var first:=connectivity_result(state)
	check(first.bridges.has(GameState.edge_key(0,2)),"segmented strategic route is initially connected")
	var revision:=state.road_network_revision
	state.edges[0].max_manpower=0
	var closed:=connectivity_result(state)
	check(state.road_network_revision==revision,"fixture closure directly edits physical capacity without revision reset")
	check(state.strategic_edge_of(0,2).max_manpower==0,"live strategic aggregation observes closed physical segment")
	check(closed.bridges.is_empty(),"cached strategic CSR observes direct segment closure in standalone query")
	check(_backend.call("begin_frozen_batch",state,[0] as Array[int],true,true),"segmented route frozen batch starts")
	var frozen:=connectivity_result(state)
	check(frozen.bridges.is_empty(),"new frozen strategic masks observe direct segment closure")
	_backend.call("end_frozen_batch",state)

func strategic_route_boundaries()->void:
	for kind in ["single_node","missing_route","missing_segment"]:
		# Every case and backend gets a fresh world: no previous CSR can mask a
		# difference in the Atlas route dictionary used by the real DFS interface.
		var oracle:=strategic_route_fixture(kind)
		select_backend("gdscript")
		var expected:=connectivity_result(oracle)
		var open:bool=kind=="single_node"
		var strategic:=oracle.strategic_edge_of(0,2)
		check((strategic!=null and strategic.max_manpower>0)==open,"legacy strategic edge availability "+kind)
		check(expected.bridges.has(GameState.edge_key(0,2))==open,"legacy connectivity distinguishes available and missing routes "+kind)
		for mode in ["native","compare"]:
			var subject:=strategic_route_fixture(kind)
			var random_before:=subject.rng.state
			select_backend(mode)
			var actual:=connectivity_result(subject)
			check(var_to_bytes(expected)==var_to_bytes(actual),"strategic route boundary exact dictionaries "+kind+" "+mode)
			check(subject.rng.state==random_before,"strategic route boundary preserves RNG "+kind+" "+mode)

func strategic_route_fixture(kind:String)->GameState:
	var state:=GameState.new()
	state._reset_world(77241)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,1,false)
	for id in range(3):
		var city:=City.new()
		city.id=id
		city.map_position=Vector2(.1+float(id)*.2,.5)
		city.owner_nation=0 if id!=1 else -1
		if id==1:
			city.node_kind=City.NodeKind.TRAFFIC
			city.politically_active=false
		state.cities.append(city)
		state.adjacency[id]=[] as Array[int]
	# One physical segment exists; the [0,1,2] case is missing its second segment.
	var edge:=Edge.new()
	edge.city_a=0
	edge.city_b=1
	edge.control_city_id=0
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(0,1)]=edge
	(state.adjacency[0] as Array[int]).append(1)
	(state.adjacency[1] as Array[int]).append(0)
	state.nations[0].capital_city_id=0
	var routes:Dictionary={}
	if kind=="single_node":routes["0:2"]=[0]
	elif kind=="missing_segment":routes["0:2"]=[0,1,2]
	state.atlas_layout={"model":"native-route-boundary","settlement_adjacency":{0:[2] as Array[int],1:[] as Array[int],2:[0] as Array[int]},"strategic_routes":routes,"territorial_pairs":[]}
	return state

func blocker_army(state:GameState,owner:int,from_city:int,to_city:int,size:int,on_edge:bool=true)->void:
	var army:=Army.new()
	army.id=state.armies.size()
	army.owner_nation=owner
	army.move_from=from_city
	army.move_to=to_city
	army.size=size
	army.on_edge=on_edge
	state.armies.append(army)

func compare_blockers(state:GameState,label:String)->void:
	var before:=state.rng.state
	for observer in [-1,0,1,2]:
		var expected:=Pathfinding._enemy_occupied_edge_keys_gdscript(state,observer)
		var actual:=Pathfinding._enemy_occupied_edge_keys(state,observer)
		check(var_to_bytes(expected)==var_to_bytes(actual),"ordered army blockers "+label+" observer=%d"%observer)
		check(var_to_bytes(actual)==var_to_bytes(Pathfinding._enemy_occupied_edge_keys(state,observer)),"repeat army blockers remain exact "+label+" observer=%d"%observer)
	check(before==state.rng.state,"blocker queries preserve RNG "+label)

func enemy_blocker_order()->void:
	var state:=fixture(false)
	# Existing first army blocks 0--4. Later duplicate keys must keep that position.
	blocker_army(state,2,6,8,15000)
	blocker_army(state,1,4,0,12000)
	blocker_army(state,1,6,7,5000)
	blocker_army(state,1,7,6,15000)
	blocker_army(state,2,3,6,11000)
	blocker_army(state,1,6,8,0)
	blocker_army(state,1,3,6,9000,false)
	blocker_army(state,1,4,-1,6000)
	blocker_army(state,0,5,6,7000)
	select_backend("native")
	compare_blockers(state,"war+neutral+duplicate+inactive+invalid destination sentinel")
	var initial:=Pathfinding._enemy_occupied_edge_keys(state,0)
	check(initial.keys()==[GameState.edge_key(0,4),GameState.edge_key(6,7)],"duplicate enemy formations preserve first-edge insertion order")
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.WAR)
	compare_blockers(state,"second owner changes from neutral to war")
	check(Pathfinding._enemy_occupied_edge_keys(state,0).keys()==[GameState.edge_key(0,4),GameState.edge_key(6,8),GameState.edge_key(6,7),GameState.edge_key(3,6)],"owner memoization retains global army-order insertion across multiple owners")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	compare_blockers(state,"former enemy becomes ally")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	# Legacy identity compatibility is intentionally excluded from map blockers,
	# even though is_enemy(identity,parent) remains true.
	var conflict:=SuccessionConflict.new()
	conflict.nation_id=0
	conflict.rebel_nation_id=1
	conflict.battle=Battle.new()
	state.succession_conflicts[0]=conflict
	state.nations[1].succession_identity=true
	check(state.succession_identity_pair(1,0) and state.is_enemy(1,0),"private identity pair exercises explicit blocker exclusion")
	compare_blockers(state,"private succession identity pair")
	check(not Pathfinding._enemy_occupied_edge_keys(state,0).has(GameState.edge_key(0,4)),"private political opponent does not block map roads")
	state.succession_conflicts.clear()
	state.nations[1].succession_identity=false
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.NEUTRAL)
	compare_blockers(state,"private identity retired and external war ends")
	# Only move_to == -1 is filtered by the legacy contract. Keep other malformed
	# raw keys exact rather than quietly strengthening this helper's validation.
	blocker_army(state,1,-1,4,6000)
	compare_blockers(state,"legacy raw invalid origin key")

func select_backend(name:String)->void:
	_backend.call("set_backend_for_tests",name)
	check(str(_backend.call("backend"))==name,"requested backend selected "+name)

func check(condition:bool,label:String)->void:
	_checks+=1
	if not condition and _failures.size()<20: _failures.append(label)

func fixture(mirror:bool)->GameState:
	var state:=GameState.new()
	state._reset_world(77991)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,3,false)
	var positions:=[Vector2(.1,.5),Vector2(.9,.5),Vector2(.8,.8),Vector2(.6,.5),Vector2(.25,.3),Vector2(.2500001,.3),Vector2(.4,.5),Vector2(.7,.5),Vector2(.6,.8),Vector2(.2,.2),Vector2(.3,.7),Vector2(.2,.7)]
	for id in range(positions.size()):
		var city:=City.new()
		city.id=id
		city.owner_nation=id if id in [1,2] else 0
		city.map_position=positions[id]
		if mirror: city.map_position.x=1.0-city.map_position.x
		if id>=4:
			city.node_kind=City.NodeKind.TRAFFIC
			city.owner_nation=-1
			city.politically_active=false
		state.cities.append(city)
		state.adjacency[id]=[] as Array[int]
		state.administrative_center_by_city.append(id if id<4 else -1)
	state.administrative_center_city_ids=[0,1,2,3] as Array[int]
	for owner in range(3): state.nations[owner].capital_city_id=owner
	state.atlas_layout={"model":"native-graph-test","territorial_pairs":[]}
	state._initialize_recognized_city_owners()
	for record in [[0,4,0,1.,.1],[0,5,0,1.,0.],[4,6,0,1.,0.],[5,6,0,1.,.1],[6,3,3,1.,0.],[6,7,1,1.,.2],[7,1,1,1.,0.],[6,8,2,1.,0.],[8,2,2,1.,0.],[0,9,0,.25,0.],[9,3,3,.25,0.],[6,10,0,1.,0.],[10,11,0,1.,0.],[5,11,0,1.,0.]]:
		var edge:=Edge.new()
		edge.city_a=mini(record[0],record[1])
		edge.city_b=maxi(record[0],record[1])
		edge.control_city_id=record[2]
		edge.precise_distance=record[3]
		edge.danger=record[4]
		if edge.city_a==0 and edge.city_b==9: edge.max_manpower=0
		state.edges.append(edge)
		state.edge_lookup[GameState.edge_key(edge.city_a,edge.city_b)]=edge
		(state.adjacency[edge.city_a] as Array[int]).append(edge.city_b)
		(state.adjacency[edge.city_b] as Array[int]).append(edge.city_a)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	var enemy:=Army.new()
	enemy.id=0
	enemy.owner_nation=1
	enemy.size=15000
	enemy.on_edge=true
	enemy.move_from=0
	enemy.move_to=4
	enemy.move_progress=.5
	state.armies.append(enemy)
	return state
