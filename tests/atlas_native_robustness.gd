extends SceneTree
const Generator = preload("res://scripts/atlas/generator.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
var failures := 0
static func fingerprint(value: Variant) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(var_to_bytes(value)); return context.finish().hex_encode()
static func root(parent: PackedInt32Array,i: int) -> int:
	var r := i
	while parent[r]!=r: r = parent[r]
	while parent[i]!=i:
		var next := parent[i]; parent[i] = r; i = next
	return r
static func join(parent: PackedInt32Array,a: int,b: int) -> void:
	parent[root(parent,b)] = root(parent,a)
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ROBUSTNESS_FAIL ",message)
func _initialize() -> void:
	var seed_value := 12345; var repeat := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): seed_value = int(arg.get_slice("=",1))
		if arg=="--repeat": repeat = true
	var payload := Generator.generate(seed_value); var data: Dictionary = payload.data; var mesh: Dictionary = data.mesh
	var parent := PackedInt32Array(); parent.resize(mesh.n)
	for i in range(mesh.n): parent[i] = i
	var route_parent := parent.duplicate(); var region_parent := parent.duplicate()
	for i in range(mesh.n):
		for k in range(mesh.adj_start[i],mesh.adj_start[i+1]):
			var j: int = mesh.adj[k]
			if Roads.passable(data.environment,i) and Roads.passable(data.environment,j): join(parent,i,j)
			if data.regions.of[i]>=0 and data.regions.of[i]==data.regions.of[j]: join(region_parent,i,j)
	var links := {}
	for route in data.roads:
		for t in range(route.cells.size()):
			var i: int = route.cells[t]; check(Roads.passable(data.environment,i),"blocked road")
			if t==0: continue
			var a: int = route.cells[t-1]; check(Roads.slot_of(mesh,a,i)>=0,"nonadjacent road")
			var key := mini(a,i)*int(mesh.n)+maxi(a,i)
			check(not links.has(key),"duplicate shared segment"); links[key] = true; join(route_parent,a,i)
	var city_component := {}
	for city in data.cities:
		check(data.environment.suitability[city.cell]>1,"city threshold")
		var component := root(parent,city.cell); var road_component := root(route_parent,city.cell)
		if city_component.has(component): check(city_component[component]==road_component,"disconnected cities on one passable land component")
		else: city_component[component] = road_component
	for i in range(mesh.n):
		var r: int = data.regions.of[i]
		if r>=0: check(root(region_parent,i)==root(region_parent,data.regions.seat[r]),"province fragment")
	for connection in data.connections:
		check(connection.cells.size()>=2,"empty complete connection")
		if connection.cells.is_empty(): continue
		check(connection.cells[0]==data.cities[connection.a].cell and connection.cells[-1]==data.cities[connection.b].cell,"connection endpoints")
		for t in range(1,connection.cells.size()):
			var a: int = connection.cells[t-1]; var b: int = connection.cells[t]
			check(links.has(mini(a,b)*int(mesh.n)+maxi(a,b)),"connection references removed segment")
	var province_hash := fingerprint(data.regions)
	var empty_cities := Roads.seat_cities(mesh,data.environment,data.regions,1e12)
	var empty_roads := Roads.build(mesh,data.environment,empty_cities)
	check(empty_cities.is_empty() and empty_roads.routes.is_empty() and empty_roads.connections.is_empty(),"world without eligible cities")
	check(fingerprint(data.regions)==province_hash,"threshold mutated provinces")
	if repeat:
		var again := Generator.generate(seed_value)
		for key in ["data","raster","display"]: check(fingerprint(payload[key])==fingerprint(again[key]),"nondeterministic "+key)
	print("ROBUSTNESS_COUNTS seed=",seed_value," cities=",data.cities.size()," components=",city_component.size()," regions=",data.regions.count," roads=",data.roads.size())
	print("ROBUSTNESS_TIMING ",payload.timing)
	print("ATLAS_NATIVE_ROBUSTNESS failures=",failures); quit(1 if failures else 0)
