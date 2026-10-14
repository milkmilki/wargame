extends SceneTree
var failures:=0
class LegacySimulation extends Simulation:
	func _campaign_staging_cities(nation:int,target:int) -> Array[int]:
		return DiplomacyAI.staging_cities_for_objective(state,nation,target)
func check(ok:bool,label:String):
	if not ok:failures+=1;push_error(label)
func _init():
	var state:=GameState.new();state._reset_world(944)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL,3,false)
	for id in range(4):
		var city:=City.new();city.id=id;city.owner_nation=[0,1,2,-1][id];city.map_position=Vector2(id*.1,.5)
		if id==3:city.node_kind=City.NodeKind.TRAFFIC;city.politically_active=false
		state.cities.append(city);state.adjacency[id]=[] as Array[int]
	state.atlas_layout={"territorial_pairs":[Vector2i(0,1)] as Array[Vector2i],"settlement_adjacency":{0:[1] as Array[int],1:[0] as Array[int]}}
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	for pair in [Vector2i(0,3),Vector2i(3,1)]:
		var edge:=Edge.new();edge.city_a=pair.x;edge.city_b=pair.y;edge.control_city_id=0 if pair.x==0 else 2;edge.max_manpower=15000
		state.edges.append(edge);state.edge_lookup[GameState.edge_key(pair.x,pair.y)]=edge;state.adjacency[pair.x].append(pair.y);state.adjacency[pair.y].append(pair.x)
	var sim:Simulation=LegacySimulation.new() if OS.get_cmdline_user_args().has("--baseline-repro") else Simulation.new();sim.state=state
	check(DiplomacyAI.staging_cities_for_objective(state,0,1).has(0),"coarse territorial border presents the friendly staging point")
	check(DiplomacyAI.war_staging_cities_for_objective(state,0,1).is_empty(),"objective selection shares the actual military road check")
	check(sim._campaign_staging_cities(0,1).is_empty(),"actual road through neutral jurisdiction cannot be a campaign entrance")
	var prewar_cache := {}
	check(DiplomacyAI.war_preparation_staging_cities(state,0,1,prewar_cache).is_empty(),"prewar qualification must reject the same unusable attack road before declaring")
	state.edges[1].control_city_id=1;state.road_network_revision+=1
	check(sim._campaign_staging_cities(0,1).has(0),"legal target-jurisdiction road allows the same entrance after invalidation")
	check(DiplomacyAI.war_preparation_staging_cities(state,0,1,prewar_cache).has(0),"road recovery invalidates cached prewar attack access")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
	var before_rng := state.rng.state
	check(DiplomacyAI.war_preparation_staging_cities(state,0,1,prewar_cache).has(0),"neutral preparation previews the terminal hostile jurisdiction without requiring an existing war")
	check(state.relation_between(0,1)==GameState.DiplomaticRelation.NEUTRAL and state.rng.state==before_rng,"route preview leaves diplomacy and random stream unchanged")
	state.edges[1].max_manpower=0;state.road_network_revision+=1
	check(DiplomacyAI.war_preparation_staging_cities(state,0,1,prewar_cache).is_empty(),"projected hostility cannot bypass a physically closed road")
	sim.free();print("CAMPAIGN_STAGING_LEGALITY failures=",failures);quit(0 if failures==0 else 1)
