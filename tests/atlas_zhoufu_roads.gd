extends SceneTree
const Hierarchy = preload("res://scripts/atlas/zhoufu.gd")
const Roads = preload("res://scripts/atlas/roads.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ZHOUFU_ROADS_FAIL ",message)
func _initialize() -> void:
	var builder = load("res://scripts/atlas/zhoufu_roads.gd")
	if builder==null: print("ZHOUFU_ROADS_FAIL missing builder"); quit(1); return
	var data: Dictionary = preload("res://tests/atlas_military_inputs.gd").base().data
	var h := Hierarchy.build(data.mesh,data.environment,data.regions,data.cities,1,1.)
	var network: Dictionary = builder.build(data.mesh,data.environment,data.regions,h)
	for connection in network.connections:
		check(connection.cells.size()>=2,"complete connection retained")
		for index in range(1,connection.cells.size()):
			var a: int = connection.cells[index-1]; var b: int = connection.cells[index]
			check(Roads.passable(data.environment,a) and Roads.passable(data.environment,b),"passable land")
			var slot := Roads.slot_of(data.mesh,a,b)
			check(slot>=0 and network.slots[slot]>0,"connection follows physical network")
			if connection.get("protected",false): check(data.regions.of[a]==connection.parent and data.regions.of[b]==connection.parent,"administrative road stays in state")
	for connection in h.mandatory_connections:
		check(not Roads.network_path(data.mesh,network.slots,h.cities[connection.a].cell,h.cities[connection.b].cell).is_empty(),"mandatory prefecture connection")
	# Each passable component's settlements must remain connected after pruning.
	var land_component := PackedInt32Array(); land_component.resize(data.mesh.n); land_component.fill(-1)
	var physical_component := land_component.duplicate(); var component := 0
	for root_cell in range(data.mesh.n):
		if land_component[root_cell]>=0 or not Roads.passable(data.environment,root_cell): continue
		var queue: Array[int] = [root_cell]; land_component[root_cell] = component
		while not queue.is_empty():
			var cell: int = queue.pop_back()
			for slot in range(data.mesh.adj_start[cell],data.mesh.adj_start[cell+1]):
				var next: int = data.mesh.adj[slot]
				if land_component[next]<0 and Roads.passable(data.environment,next): land_component[next] = component; queue.append(next)
		component += 1
	component = 0
	var expected := {}
	for city in h.cities:
		if physical_component[city.cell]<0:
			var queue: Array[int] = [city.cell]; physical_component[city.cell] = component
			while not queue.is_empty():
				var cell: int = queue.pop_back()
				for slot in range(data.mesh.adj_start[cell],data.mesh.adj_start[cell+1]):
					var next: int = data.mesh.adj[slot]
					if network.slots[slot]>0 and physical_component[next]<0: physical_component[next] = component; queue.append(next)
			component += 1
		var land: int = land_component[city.cell]
		if not expected.has(land): expected[land] = physical_component[city.cell]
		check(expected[land]==physical_component[city.cell],"passable land component retains all settlements")
	var seen := {}
	for route in network.routes:
		for index in range(1,route.cells.size()):
			var a: int = route.cells[index-1]; var b: int = route.cells[index]
			var key := mini(a,b)*int(data.mesh.n)+maxi(a,b)
			check(not seen.has(key),"physical segment drawn once"); seen[key] = true
	print("ATLAS_ZHOUFU_ROADS settlements=",h.cities.size()," connections=",network.connections.size()," failures=",failures)
	quit(1 if failures else 0)
