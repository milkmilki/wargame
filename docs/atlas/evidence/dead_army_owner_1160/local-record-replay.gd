extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var snapshot: Dictionary=FileAccess.open("res://.dbg/atlas-thirty-year-v5-dead-owner-1160/final.snapshot",FileAccess.READ).get_var(false)
	var state:=GameState.new(); var nations: Dictionary=snapshot.nations; var cities: Dictionary=snapshot.cities
	state._reset_world(1)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,nations.count,false)
	state.atlas_layout={"model":"failure-record-replay","territorial_pairs":[] as Array[Vector2i]}
	for id in range(nations.count):
		var nation:=state.nations[id]
		nation.succession_identity=nations.succession_identity[id]!=0
	for index in range(cities.count):
		var city:=City.new(); city.id=index; city.owner_nation=cities.owner[index]
		if city.owner_nation<0: city.node_kind=City.NodeKind.TRAFFIC; city.politically_active=false
		state.cities.append(city)
	state._initialize_recognized_city_owners(); state.refresh_derived()
	var army:=Army.new(); var armies: Dictionary=snapshot.armies
	for index in range(armies.count):
		if armies.id[index]!=1791:continue
		army.id=armies.id[index];army.owner_nation=armies.owner[index]
		army.size=armies.size[index];army.max_size=armies.max_size[index]
		army.location_city=armies.location[index];army.move_from=armies.move_from[index];army.move_to=armies.move_to[index]
		army.on_edge=armies.on_edge[index]!=0;army.move_progress=armies.move_progress[index]
		army.state=armies.state[index];army.battle_id=armies.battle_id[index]
	state.armies.append(army)
	var edge:=Edge.new();edge.city_a=mini(army.move_from,army.move_to);edge.city_b=maxi(army.move_from,army.move_to)
	edge.passing_count=1;edge.occupied=true
	state.edges.append(edge);state.edge_lookup[GameState.edge_key(edge.city_a,edge.city_b)]=edge
	var sim:=Simulation.new();sim.state=state
	var before: Dictionary={"source_day":snapshot.day,"army":army.id,"nation":army.owner_nation,
		"alive":state.nations[army.owner_nation].alive,"size":army.size,"road":[edge.city_a,edge.city_b],"passing":edge.passing_count}
	sim._resolve_eliminated_nation_capitulations()
	assert(not state.armies.has(army) and army.size==0 and edge.passing_count==0 and not edge.occupied)
	var result: Dictionary={"scope":"Local replay of actual army/road/city-control fields; not a full simulation restore",
		"before":before,"after":{"armies":state.armies.size(),"size":army.size,"passing":edge.passing_count},
		"simulation_sha256":FileAccess.get_sha256("res://scripts/simulation/simulation.gd")}
	FileAccess.open("res://.dbg/dead-owner-record-replay.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result));sim.free();quit()
