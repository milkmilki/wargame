extends SceneTree
const Roads = preload("res://scripts/atlas/roads.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("EARTH_ROUTE_FAIL ",message)
static func root_of(parent: PackedInt32Array,cell: int) -> int:
	var root := cell
	while parent[root]!=root: root = parent[root]
	while parent[cell]!=cell:
		var next := parent[cell]; parent[cell] = root; cell = next
	return root
static func join(parent: PackedInt32Array,a: int,b: int) -> void:
	parent[root_of(parent,b)] = root_of(parent,a)
func _initialize() -> void:
	var payload: Dictionary = FileAccess.open("res://.dbg/atlas-native-generated-earth-rainfall-v4.bin",FileAccess.READ).get_var(false)
	var data: Dictionary = payload.data; var mesh: Dictionary = data.mesh
	var terrain := PackedInt32Array(); terrain.resize(mesh.n)
	for cell in range(mesh.n): terrain[cell] = cell
	var network := terrain.duplicate(); var pieces := terrain.duplicate()
	for cell in range(mesh.n):
		for at in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var other: int = mesh.adj[at]
			if Roads.passable(data.environment,cell) and Roads.passable(data.environment,other): join(terrain,cell,other)
			if data.regions.of[cell]>=0 and data.regions.of[cell]==data.regions.of[other]: join(pieces,cell,other)
	var edges := {}
	for road in data.roads:
		for at in range(1,road.cells.size()):
			var a: int = road.cells[at-1]; var b: int = road.cells[at]
			check(Roads.passable(data.environment,a) and Roads.passable(data.environment,b),"blocked shared segment")
			check(Roads.slot_of(mesh,a,b)>=0,"nonadjacent segment")
			var key := mini(a,b)*int(mesh.n)+maxi(a,b)
			check(not edges.has(key),"duplicate shared segment"); edges[key] = true; join(network,a,b)
	var components := {}
	for city in data.cities:
		check(data.environment.suitability[city.cell]>1,"threshold is not strict")
		var island := root_of(terrain,city.cell); var connected := root_of(network,city.cell)
		if components.has(island): check(components[island]==connected,"disconnected cities")
		else: components[island] = connected
	for cell in range(mesh.n):
		var region: int = data.regions.of[cell]
		if region>=0: check(root_of(pieces,cell)==root_of(pieces,data.regions.seat[region]),"province fragment")
	for connection in data.connections:
		check(connection.cells[0]==data.cities[connection.a].cell and connection.cells[-1]==data.cities[connection.b].cell,"connection endpoints")
		for at in range(1,connection.cells.size()):
			var a: int = connection.cells[at-1]; var b: int = connection.cells[at]
			check(edges.has(mini(a,b)*int(mesh.n)+maxi(a,b)),"connection uses removed road")
	print("EARTH_ROUTE_COMPONENTS ",components.size())
	print("ATLAS_NATIVE_EARTH_ROUTES failures=",failures); quit(1 if failures else 0)
