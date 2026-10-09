extends SceneTree
const Hierarchy = preload("res://scripts/atlas/zhoufu.gd")
const Roads = preload("res://scripts/atlas/zhoufu_roads.gd")
const Traffic = preload("res://scripts/atlas/traffic_graph.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_SEEDS_FAIL ",message)
func _initialize() -> void:
	for seed_value in [1,7,2024]:
		var base: Dictionary = preload("res://tests/atlas_military_inputs.gd").base(seed_value,false)
		var data: Dictionary = base.data
		var parent := var_to_bytes(data.regions); var environment := var_to_bytes(data.environment)
		var h := Hierarchy.build(data.mesh,data.environment,data.regions,data.cities,seed_value,1.)
		var repeated := Hierarchy.build(data.mesh,data.environment,data.regions,data.cities,seed_value,1.)
		check(var_to_bytes(h)==var_to_bytes(repeated),"deterministic hierarchy seed %d"%seed_value)
		check(parent==var_to_bytes(data.regions) and environment==var_to_bytes(data.environment),"original province and climate unchanged")
		var network := Roads.build(data.mesh,data.environment,data.regions,h)
		var repeated_network := Roads.build(data.mesh,data.environment,data.regions,h)
		check(var_to_bytes(network)==var_to_bytes(repeated_network),"deterministic road network seed %d"%seed_value)
		var graph := Traffic.build(data.mesh,h,network)
		for edge in graph.edges: check(edge.control_city>=0 and edge.control_city<h.cities.size(),"single valid jurisdiction per physical segment")
		var total := [0,0,0]
		for city in h.cities:
			for kind in range(3): total[kind] += city.budget[kind]
		check(total==[data.cities.size()*3000,data.cities.size()*28,data.cities.size()*680],"budget conserved independently of prefecture count")
		print("ATLAS_SEED seed=",seed_value," states=",data.cities.size()," settlements=",h.cities.size()," nodes=",graph.nodes.size()," edges=",graph.edges.size())
	print("ATLAS_HIERARCHY_SEEDS failures=",failures); quit(1 if failures else 0)
