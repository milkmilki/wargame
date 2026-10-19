extends SceneTree
## Public roads do not grant access to neutral or unconquered enemy cities.
const Access=preload("res://tests/atlas_access_and_repatriation.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("PUBLIC_ROADS_FAIL ",label)
func run() -> void:
	for backend in ["gdscript","native"]:
		NativeCompute.set_backend_for_tests(backend)
		for control in [-1,2,3,4]:
			var state:=Access._fixture([Vector3i(0,5,control),Vector3i(5,6,control),Vector3i(6,1,control)] as Array[Vector3i])
			state.atlas_layout.settlement_adjacency={0:[1] as Array[int],1:[0] as Array[int]}
			var rng:=state.rng.state
			var ordinary:=Pathfinding.dijkstra_field(state,0,0,false,false)
			check(is_finite(float(ordinary.dist[6])) and not is_finite(float(ordinary.dist[1])),backend+": ordinary movement uses every road but stops before enemy city")
			check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1])),backend+": declared attack reaches its terminal enemy city")
			check(DiplomacyAI._prewar_attack_route_ready(state,0,0,1,{}),backend+": preparation previews the same public road")
			check(MilitaryReachability.contact(state,[0],[1],[0,1]),backend+": projected contact ignores road jurisdictions")
			var supply:=Pathfinding._supply_loss_field(state,0,0,{},true,[] as Array[int],true)
			check(is_finite(float(supply.dist[6])) and not is_finite(float(supply.dist[1])),backend+": rear supply uses public roads without opening enemy city transit")
			var unit:=Army.new();unit.id=0;unit.owner_nation=0;unit.size=15000;unit.max_size=15000
			unit.location_city=6;unit.move_from=6
			check(Pathfinding.can_reach_manpower_hub(state,unit),backend+": manpower reaches ownerless traffic nodes along public roads")
			check(Pathfinding.can_reach_manpower_hub_from_network(state,unit,Pathfinding.build_manpower_hub_network(state,0)),backend+": batched manpower uses the same city-node access")
			unit.location_city=0;unit.move_from=0;unit.state=Army.State.MOVING
			unit.ai_action=ActionCandidate.Kind.ATTACK;unit.ai_target_city=1;unit.path=[5,6,1] as Array[int]
			state.armies.append(unit)
			var sim:=Simulation.new();sim.setup(state);sim._begin_next_leg(unit)
			check(unit.on_edge and unit.move_to==5,backend+": runtime starts along public roads without controller permission")
			check(state._campaign_has_live_route(unit,1),backend+": live warning uses city permissions too")
			check(state.rng.state==rng,backend+": routing and dispatch preserve RNG")
			sim.free()
			state.cities[1].owner_nation=0
			check(state.capital_hop_distances(0).has(1),backend+": own-city administrative links also use public roads")
			check(NativeCompute.administrative_fields(state,[0] as Array[int]).get(0,{}).has(1),backend+": native administrative field follows the same public roads")
		for gate in [2,4]:
			var state:=Access._fixture([Vector3i(0,5,0),Vector3i(5,gate,0),Vector3i(gate,6,0),Vector3i(6,1,0)] as Array[Vector3i])
			check(not is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1])),backend+": actual neutral/enemy city blocks a rear attack")
			check(not DiplomacyAI._prewar_attack_route_ready(state,0,0,1,{}),backend+": preparation cannot jump a blocked city")
			check(not is_finite(float(Pathfinding._supply_loss_field(state,0,0,{},true,[] as Array[int],true).dist[6])),backend+": the same actual city blocks rear supply")
			if gate==2:
				check(not is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,2).dist[2])),backend+": naming a neutral city as goal cannot bypass its access rule")
				state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
			else:
				check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,4).dist[4])),backend+": the front enemy city can be attacked first")
				state.transfer_city_control(4,0,0,GameState.TerritoryStockDisposition.CAPTURE_SPOILS,"public_road_fixture")
			check(is_finite(float(Pathfinding.dijkstra_field(state,0,0,false,false,1).dist[1])),backend+": permission or front-city capture opens the next attack")
			check(is_finite(float(Pathfinding._supply_loss_field(state,0,0,{},true,[] as Array[int],true).dist[6])),backend+": supply sees the same change of city access")
		for gate in [2,4]:
			var state:=Access._fixture([Vector3i(0,5,0),Vector3i(5,gate,0),Vector3i(gate,6,0),Vector3i(6,3,0)] as Array[Vector3i])
			state.cities[3].owner_nation=0
			state.edge_of(0,5).precise_distance=100.
			var unit:=Army.new();unit.id=0;unit.owner_nation=0;unit.size=15000;unit.max_size=15000
			unit.location_city=5;unit.move_from=5;unit.move_to=gate;unit.move_progress=.9;unit.on_edge=true
			unit.state=Army.State.MOVING;unit.path=[gate,6,3] as Array[int];state.armies.append(unit)
			state.edge_of(5,gate).passing_count=1;state.edge_of(5,gate).occupied=true
			check(Pathfinding.strategic_retreat_route_from_edge(state,unit).get("endpoint",-1)==5,backend+": edge retreat cannot use an inaccessible city as a new origin")
			check(Pathfinding.nearest_friendly_route_from_edge(state,unit).get("endpoint",-1)==5,backend+": ordinary retreat also turns back before the city barrier")
			var sim:=Simulation.new();sim.setup(state);sim._retreat(unit)
			check(unit.on_edge and unit.move_to==5 and is_equal_approx(unit.move_progress,.1),backend+": actual rout reverses on the same road without entering the blocked city")
			sim.free()
	NativeCompute.set_backend_for_tests("native")
	print("PUBLIC_ROADS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
