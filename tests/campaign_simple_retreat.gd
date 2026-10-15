extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)
func fixture() -> GameState:
	var state := GameState.new();state._reset_world(94012)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,2,false)
	for id in range(3):
		var city := City.new();city.id=id;city.map_position=Vector2(.1+id*.1,.5)
		city.owner_nation=0 if id!=1 else -1
		city.node_kind=City.NodeKind.TRAFFIC if id==1 else City.NodeKind.SETTLEMENT
		city.politically_active=id!=1
		state.cities.append(city);state.adjacency[id]=[] as Array[int]
	for pair in [Vector2i(0,1),Vector2i(1,2)]:
		var edge := Edge.new();edge.city_a=pair.x;edge.city_b=pair.y;edge.control_city_id=0 if pair.x==0 else 2
		edge.max_manpower=100;state.edges.append(edge);state.edge_lookup[GameState.edge_key(pair.x,pair.y)]=edge
		state.adjacency[pair.x].append(pair.y);state.adjacency[pair.y].append(pair.x)
	state.nations[0].capital_city_id=0;state.nations[1].capital_city_id=2
	state.atlas_layout={"model":"atlas-military-v1","territorial_pairs":[] as Array[Vector2i]}
	return state
func soldier(state: GameState) -> Army:
	var army := Army.new();army.id=9000;army.owner_nation=0;army.location_city=0
	army.size=1000;army.max_size=15000;army.morale=0;army.move_from=0
	state.armies.append(army);return army
func _init() -> void:
	var garrison := Army.new();garrison.is_city_garrison=true
	check(is_equal_approx(Combat._city_garrison_attack_multiplier(garrison),.1),"virtual garrison independently uses ten percent attack")
	check(is_equal_approx(Combat.holding_attack_multiplier(true),.5),"real holding attack remains unchanged")
	var state := fixture();var army := soldier(state);var sim := Simulation.new();sim.state=state
	check(Pathfinding.has_friendly_retreat_route_from_city(state,0,0,army.max_size),"full route through ownerless junction is a legal retreat")
	sim._start_morale_retreat_from_city(army,0,0)
	check(army.size==1000 and army.state==Army.State.RETREATING and not army.path.is_empty() and army.path.back()==2,"zero morale is not annihilated when a remote fu is reachable")
	check(state.edges[0].passing_count==1,"retreat occupies its actual physical edge")
	sim.free()
	state=fixture();army=soldier(state);state.edges[1].max_manpower=0
	sim=Simulation.new();sim.state=state;sim._start_morale_retreat_from_city(army,0,0)
	check(army.size==0 and not army.on_edge,"last capital with no complete retreat route annihilates real defeated army")
	check(state.nations[0].alive,"field annihilation does not itself destroy the nation")
	sim.free()
	state=fixture();army=soldier(state);state.cities[2].owner_nation=1
	check(not Pathfinding.has_friendly_retreat_route_from_city(state,0,0),"neutral territory is not a retreat")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	check(Pathfinding.has_friendly_retreat_route_from_city(state,0,0),"allied safe fu is a fallback retreat")
	check(Combat.COMBAT_RULES_VERSION==7 and NativeSnapshotBuilder.SCHEMA_VERSION==31,"morale rout-only combat uses v7; landed peerage uses snapshot v31")
	print("CAMPAIGN_SIMPLE_RETREAT checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
