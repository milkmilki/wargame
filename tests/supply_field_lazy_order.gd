extends SceneTree
const Reference = preload("res://tests/support/supply_field_order_reference.gd")
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks+=1
	if not ok:failures.append(message)
func run():
	for seed_value in [1,7,2024,12345]:
		for mirrored in [false,true]:
			for case_id in range(6):
				var atlas := case_id%2==1
				var state:=preload("res://tests/support/grid_world.gd").new();state.generate_world(seed_value,4,64)
				if atlas:
					state.atlas_layout={"model":"supply-order-test"}
					for city in state.cities:
						if city.id%4==3:city.node_kind=City.NodeKind.TRAFFIC;city.politically_active=false;city.owner_nation=-1
					for edge in state.edges:edge.control_city_id=edge.city_a if edge.city_a%4!=3 else edge.city_a-1
				if mirrored:
					for city in state.cities:city.map_position.x=1.0-city.map_position.x
				for nation in state.nations:
					if case_id/2==1:nation.capital_city_id=-1
					elif case_id/2==2:state.cities[nation.capital_city_id].map_position.x=.5
				for edge in state.edges:
					edge.precise_distance=.1 if seed_value==1 else .1+float((edge.city_a+edge.city_b)%3)*1e-8
					edge.danger=0.0;edge.supply_loss_multiplier=1.0
				state.edges[0].max_manpower=0
				for start in [0,16,32,48]:
					var nation_id:int=state.cities[start].owner_nation
					for logistics in [false,true]:
						for origins in [[] as Array[int],[start,start+1,start+1,-1,999] as Array[int]]:
							EquivariantOrder._city_rank_cache.clear()
							var actual:=Pathfinding._supply_loss_field(state,start,nation_id,{},true,origins,logistics)
							if atlas:check(EquivariantOrder._city_rank_cache.is_empty(),"Atlas field does not rank all global nodes")
							var expected:=Reference._supply_loss_field(state,start,nation_id,{},true,origins,logistics)
							check(var_to_bytes(actual)==var_to_bytes(expected),"complete distances and predecessors retain eager rank order")
							var blocked:={GameState.edge_key(state.edges[2].city_a,state.edges[2].city_b):true}
							check(var_to_bytes(Pathfinding._supply_loss_field(state,start,nation_id,blocked,true,origins,logistics))==var_to_bytes(Reference._supply_loss_field(state,start,nation_id,blocked,true,origins,logistics)),"blocked roads preserve exact field")
	print("SUPPLY_FIELD_LAZY_ORDER checks=%d failures=%d"%[checks,failures.size()])
	for failure in failures:print("FAIL ",failure)
	quit(0 if failures.is_empty() else 1)
