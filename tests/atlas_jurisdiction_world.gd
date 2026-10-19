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
	# This regression names exact cities/roads from the pre-coastline world.
	# Never replace it with a freshly generated map whose IDs can change.
	var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/atlas_borokhul_roads.json"))
	var path:="res://tests/fixtures/atlas_borokhul_roads.bin"
	assert(FileAccess.get_sha256(path)==metadata.fixture_sha256,"historical road fixture hash")
	var file:=FileAccess.open_compressed(path,FileAccess.READ)
	var payload:Dictionary=file.get_var(false);file.close()
	# Road rebuilding uses the retained water/district pixels. Decorative
	# noise columns are unnecessary for this scenario; restore valid display
	# columns from its unchanged cell environment for template roundtrips.
	var raster:Dictionary=payload.raster;var env:Dictionary=payload.data.environment
	for pair in [["elev","elevation"],["temp","temperature"],["precip","precipitation"],["ice","seaIce"]]:
		var values:=PackedFloat32Array();values.resize(raster.cell.size())
		for pixel in range(values.size()):values[pixel]=env[pair[1]][raster.cell[pixel]]
		raster[pair[0]]=values
	var biome:=PackedByteArray();biome.resize(raster.cell.size())
	for pixel in range(biome.size()):biome[pixel]=env.biome[raster.cell[pixel]]
	raster.biome=biome
	return payload
func run() -> void:
	var original := original_payload(); var source_hash := hash(original)
	var payload := original.duplicate()
	var started := Time.get_ticks_usec()
	payload.network=Builder.build(payload.data.mesh,payload.data.environment,payload.data.regions,payload.hierarchy)
	var roads_ms := (Time.get_ticks_usec()-started)/1000.
	check(payload.network.model=="atlas-zhoufu-roads-v1" and not payload.network.has("jurisdiction_repair"),"uses original sparse road construction without general border repair")
	check(payload.network.slots==original.network.slots,"original cached v1 physical road slots remain byte-for-byte identical")
	payload.graph=Traffic.build(payload.data.mesh,payload.hierarchy,payload.network)
	preload("res://scripts/atlas/road_geometry.gd").apply(payload.graph,payload.raster,payload.district_pixels)
	payload.settlement_adjacency=MilitaryMap.settlement_adjacency(payload.graph,payload.hierarchy.cities.size())
	payload.strategic_routes=MilitaryMap.settlement_routes(payload.graph,payload.hierarchy.cities.size())
	var state:=GameState.new(); state.generate_from_atlas(payload)
	check(state.world_seed==1 and state.map_models.settlement_mask==preload("res://scripts/atlas/settlement_mask.gd").EURASIA,"reported seed and actual Eurasia mask")
	check(state.cities[172].name=="博尔忽" and state.cities[461].name=="泰兀","regression identifies the original Borokhul state and prefecture")
	check(MilitaryReachability.prewar_entries(state,25,461,{}).has(379),"Guanggu has a lawful prewar entry into Taiwu")
	check(payload.graph.edges.size()==original.graph.edges.size(),"no new physical segments or junctions")
	check(RegionalStrategy.allows_objective(state,25,172),"Borokhul remains an allowed regional objective")
	var objective := DiplomacyAI.select_war_objective(state,25,30,{})
	check(int(objective.get("city_id",-1))==172,"ordinary AI can select Borokhul without a ruler exception")
	verify_borokhul_dispatch(payload)
	var definition:=MapDefinition.from_state(state)
	var validation:=MapDefinition.validate(definition)
	check(validation.is_empty(),"original physical graph validates as a version-nine template: "+validation)
	if validation.is_empty():
		var restored:=GameState.new();restored.generate_from_map_definition(definition)
		check(MilitaryReachability.prewar_entries(restored,25,461,{}).has(379),"template roundtrip preserves the original road and its lawful entry")
	check(hash(original)==source_hash,"rebuilding original roads leaves cached inputs unchanged")
	var reverse_goal := -1
	for adjacent in state.strategic_neighbors(461):
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
		check(battle_state.battles.any(func(b):return b.city!=null and b.city.id==direction.z and (b.side_a.has(army) or b.side_b.has(army))),"real army traverses the original road and starts combat at the target")
		check(Pathfinding._attack_supply_links(battle_state,direction.z,direction.z,direction.x,{}).has(direction.y),"the original attack road also connects its real rear supply corridor")
		var retreat:=Pathfinding.dijkstra_field(battle_state,direction.z,direction.x,false,false,-1)
		check(is_finite(float(retreat.dist[direction.y])),"original road supports withdrawal across the same rural jurisdictions")
		sim.free()
	print("JURISDICTION_WORLD checks=",checks," failures=",failures," roads_ms=",roads_ms," physical_segments=",original.graph.edges.size(),"->",payload.graph.edges.size())
	quit(1 if failures else 0)

func verify_borokhul_dispatch(payload:Dictionary) -> void:
	var state:=GameState.new();state.generate_from_atlas(payload)
	state.set_diplomatic_relation(25,30,GameState.DiplomaticRelation.WAR)
	state.set_war_objective(25,30,172,"original Borokhul road regression")
	var front:=state.create_campaign_front(state.war_id_between(25,30),[25] as Array[int],25,CoalitionCampaignFront.Mode.OFFENSE,172)
	var count:=0
	for army in state.armies:
		if army.owner_nation!=25:continue
		army.location_city=379;army.move_from=379
		army.campaign_front_id=front.front_id;army.campaign_war_id=front.war_id
		front.army_assignments[army.id]=172;count+=1
	var sim:=Simulation.new();sim.setup(state)
	check(count>0 and sim._campaign_entry_fu(25,172,[25] as Array[int])==461,"Borokhul planner chooses Taiwu on the original road as its entry")
	sim._manage_administrative_campaign(front)
	check(state.armies.any(func(a):return a.owner_nation==25 and a.on_edge and a.ai_action==ActionCandidate.Kind.ATTACK and a.ai_target_city==461),"real campaign controller immediately dispatches rallied forces toward Taiwu")
	sim.free()
