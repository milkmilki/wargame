extends SceneTree
const Builder = preload("res://scripts/atlas/zhoufu_roads.gd")
const Traffic = preload("res://scripts/atlas/traffic_graph.gd")
const MilitaryMap = preload("res://scripts/atlas/military_map.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("JURISDICTION_WORLD_FAIL ",message)
func original_payload() -> Dictionary:
	return preload("res://tests/atlas_military_inputs.gd").eurasia_military()
func run() -> void:
	var original := original_payload(); var source_hash := hash(original)
	var payload := original.duplicate()
	var started := Time.get_ticks_usec()
	payload.network=Builder.build(payload.data.mesh,payload.data.environment,payload.data.regions,payload.hierarchy)
	var roads_ms := (Time.get_ticks_usec()-started)/1000.
	payload.graph=Traffic.build(payload.data.mesh,payload.hierarchy,payload.network)
	preload("res://scripts/atlas/road_geometry.gd").apply(payload.graph,payload.raster,payload.district_pixels)
	payload.settlement_adjacency=MilitaryMap.settlement_adjacency(payload.graph,payload.hierarchy.cities.size())
	payload.strategic_routes=MilitaryMap.settlement_routes(payload.graph,payload.hierarchy.cities.size())
	var state:=GameState.new(); state.generate_from_atlas(payload)
	check(state.world_seed==1 and state.map_models.settlement_mask==preload("res://scripts/atlas/settlement_mask.gd").EURASIA,"reported seed and actual Eurasia mask")
	check(state.cities[172].name=="博尔忽" and state.cities[461].name=="泰兀","regression identifies the original Borokhul state and prefecture")
	check(MilitaryReachability.prewar_entries(state,25,461,{}).has(379),"Guanggu has a lawful prewar entry into Taiwu")
	# New land links can change the trade partition. Query the reported goal
	# explicitly rather than assuming its old Leiden community is unchanged.
	state.nations[25].strategic_region_anchor_city_id=172
	check(RegionalStrategy.allows_objective(state,25,172),"Borokhul remains an allowed regional objective")
	var objective := DiplomacyAI.select_war_objective(state,25,30,{})
	check(int(objective.get("city_id",-1))==172,"ordinary AI can select Borokhul without a ruler exception")
	var definition:=MapDefinition.from_state(state)
	var validation:=MapDefinition.validate(definition)
	check(validation.is_empty(),"repaired physical graph validates as a version-nine template: "+validation)
	if validation.is_empty():
		var restored:=GameState.new();restored.generate_from_map_definition(definition)
		check(MilitaryReachability.prewar_entries(restored,25,461,{}).has(379),"template roundtrip preserves the repaired entry")
	check(hash(original)==source_hash,"building repaired roads leaves cached inputs unchanged")
	var added_borders:={}
	for connection in payload.network.connections:
		if not connection.get("jurisdiction_entry",false):continue
		var a: int=payload.hierarchy.center_by_city[connection.a]
		var b: int=payload.hierarchy.center_by_city[connection.b]
		if a==b:continue
		var pair:=Vector2i(mini(a,b),maxi(a,b))
		check(not added_borders.has(pair),"each neighboring state pair needs at most one added entry")
		added_borders[pair]=true
	var extra_cost := Builder.costs(payload.data.mesh,payload.data.environment)
	var slot_hash := hash(payload.network.slots)
	var second := Builder.ensure_jurisdiction_entries(payload.data.mesh,payload.hierarchy,payload.network,extra_cost)
	check(second.added_connections==0 and hash(payload.network.slots)==slot_hash,"repair is idempotent on the real world")
	var reverse_goal := -1
	for adjacent in state.territorial_border_neighbors(461):
		if state.cities[adjacent].owner_nation==25 and MilitaryReachability.prewar_entries(state,30,adjacent,{}).has(461):
			reverse_goal=adjacent;break
	check(reverse_goal>=0,"Borokhul has a lawful counterattack entry into its actual neighboring enemy jurisdiction")
	var directions := [Vector3i(25,379,461)]
	if reverse_goal>=0:directions.append(Vector3i(30,461,reverse_goal))
	for direction in directions:
		var battle_state:=GameState.new(); battle_state.generate_from_atlas(payload)
		battle_state.set_diplomatic_relation(25,30,GameState.DiplomaticRelation.WAR)
		var army: Army=null
		for candidate in battle_state.armies:
			if candidate.owner_nation==direction.x:army=candidate;break
		if army==null:check(false,"actor has an army");continue
		army.location_city=direction.y;army.move_from=direction.y
		for defender in battle_state.armies:
			if defender.owner_nation==battle_state.cities[direction.z].owner_nation:
				defender.location_city=direction.z;defender.move_from=direction.z;break
		var sim:=Simulation.new(); sim.setup(battle_state); sim.paused=true; root.add_child(sim); sim.set_process(false)
		NativeCompute.set_backend_for_tests("gdscript")
		var reference := Pathfinding.dijkstra_field(battle_state,direction.y,direction.x,false,false,direction.z)
		NativeCompute.set_backend_for_tests("native")
		var field := Pathfinding.dijkstra_field(battle_state,direction.y,direction.x,false,false,direction.z)
		check(is_finite(float(field.dist[direction.z])) and field==reference,"native and GDScript agree on the lawful forward/counterattack route")
		var route := Pathfinding.reconstruct(field.prev,direction.y,direction.z)
		check(army!=null and not route.is_empty(),"real world has an army and a complete attack path")
		if route.is_empty():sim.free();continue
		army.location_city=direction.y; army.move_from=direction.y; army.path=route
		army.state=Army.State.MOVING; army.ai_action=ActionCandidate.Kind.ATTACK; army.ai_target_city=direction.z
		sim._begin_next_leg(army)
		for _leg in range(battle_state.cities.size()):
			if not army.on_edge:break
			army.move_progress=1.;sim._arrive_at_node(army)
		check(battle_state.battles.any(func(b):return b.city!=null and b.city.id==direction.z and (b.side_a.has(army) or b.side_b.has(army))),"real army traverses the repaired road and starts combat at the target")
		sim.free()
	print("JURISDICTION_WORLD checks=",checks," failures=",failures," roads_ms=",roads_ms," repair=",payload.network.jurisdiction_repair," physical_segments=",original.graph.edges.size(),"->",payload.graph.edges.size())
	quit(1 if failures else 0)
