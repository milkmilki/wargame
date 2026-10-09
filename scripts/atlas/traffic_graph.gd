extends RefCounted
## One simulation edge per shared physical chain, split at jurisdiction changes.
const Sphere = preload("res://scripts/atlas/sphere_mesh.gd")
const Geometry = preload("res://scripts/atlas/display_geometry.gd")
const MODEL := "atlas-physical-traffic-v1"

static func vertex(mesh: Dictionary,cell: int) -> Dictionary:
	return {"cell":cell,"position":Vector2(mesh.x[cell],mesh.y[cell]),"role":"traffic"}

static func link(vertices: Array,links: Array,a: int,b: int,control: int,tier: int,protected: bool,danger: float = 0.) -> void:
	var id := links.size()
	links.append({"a":a,"b":b,"control_city":control,"tier":tier,"protected":protected,"danger":danger})
	vertices[a].links.append(id); vertices[b].links.append(id)

static func build(mesh: Dictionary,h: Dictionary,network: Dictionary) -> Dictionary:
	var vertices: Array = []; var cell_vertex := {}; var links: Array = []
	for c in range(h.cities.size()):
		var record := vertex(mesh,h.cities[c].cell); record.role = h.cities[c].role; record.city = c; record.links = []
		cell_vertex[record.cell] = vertices.size(); vertices.append(record)
	for cell in range(mesh.n):
		var exists := false
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			if network.slots[slot]>0: exists = true; break
		if not exists or cell_vertex.has(cell): continue
		var record := vertex(mesh,cell); record.links = []; cell_vertex[cell] = vertices.size(); vertices.append(record)
	for cell in range(mesh.n):
		for slot in range(mesh.adj_start[cell],mesh.adj_start[cell+1]):
			var next: int = mesh.adj[slot]
			if next<=cell or network.slots[slot]==0: continue
			var a: int = cell_vertex[cell]; var b: int = cell_vertex[next]
			var tier: int = network.slots[slot]
			var protected: bool = not network.get("protected_slots",PackedByteArray()).is_empty() and network.protected_slots[slot]>0
			var left: int = h.district_of_cell[cell]; var right: int = h.district_of_cell[next]
			var danger := float(network.terrain_danger[slot]) if network.has("terrain_danger") else 0.
			if left==right: link(vertices,links,a,b,left,tier,protected,danger); continue
			var p: Vector2 = vertices[a].position; var q: Vector2 = vertices[b].position
			q.x = Sphere.near_x(q.x,p.x,mesh.width)
			var middle := vertices.size()
			vertices.append({"cell":-1,"position":p.lerp(q,.5),"role":"traffic","links":[]})
			link(vertices,links,a,middle,left,tier,protected,danger); link(vertices,links,middle,b,right,tier,protected,danger)
	var stops := {}; var nodes: Array = []
	for id in range(vertices.size()):
		var record: Dictionary = vertices[id]; var stop: bool = record.role!="traffic" or record.links.size()!=2
		if not stop:
			var a: Dictionary = links[record.links[0]]; var b: Dictionary = links[record.links[1]]
			stop = a.control_city!=b.control_city or a.tier!=b.tier
		if stop: stops[id] = nodes.size(); nodes.append(record.duplicate(true))
	var link_risk := {}
	for edge in links: link_risk["%d:%d"%[mini(edge.a,edge.b),maxi(edge.a,edge.b)]] = edge.danger
	var graph := {"model":MODEL,"nodes":nodes,"edges":[],"keys":{},"vertices":vertices,"stops":stops,"link_risk":link_risk}
	var used := PackedByteArray(); used.resize(links.size())
	for pass_value in [0,1]:
		for id in range(vertices.size()):
			if pass_value==0 and not stops.has(id): continue
			for first in vertices[id].links:
				if used[first]: continue
				if not stops.has(id): stops[id] = nodes.size(); nodes.append(vertices[id].duplicate(true))
				var chain := PackedInt32Array([id]); var current := id; var edge_id: int = first; var protected := false
				while true:
					used[edge_id] = 1; protected = protected or links[edge_id].protected
					current = links[edge_id].b if links[edge_id].a==current else links[edge_id].a
					chain.append(current)
					if stops.has(current): break
					var available: Array = vertices[current].links
					edge_id = available[1] if available[0]==edge_id else available[0]
					if used[edge_id]: break
				install(graph,chain,links[first].control_city,links[first].tier,protected,mesh.width)
	for record in nodes: record.erase("links")
	graph.erase("keys"); graph.erase("vertices"); graph.erase("stops"); graph.erase("link_risk")
	return graph

static func install(graph: Dictionary,chain: PackedInt32Array,control: int,tier: int,protected: bool,width: float) -> void:
	var a: int = graph.stops[chain[0]]; var b: int = graph.stops[chain[-1]]
	var key := "%d:%d"%[mini(a,b),maxi(a,b)]
	if a==b or graph.keys.has(key):
		assert(chain.size()>2,"Parallel paths must have a distinct internal point")
		var middle: int = chain.size()/2; var id: int = chain[middle]
		if not graph.stops.has(id): graph.stops[id] = graph.nodes.size(); graph.nodes.append(graph.vertices[id].duplicate(true))
		install(graph,chain.slice(0,middle+1),control,tier,protected,width)
		install(graph,chain.slice(middle),control,tier,protected,width); return
	graph.keys[key] = true
	var points := PackedVector2Array()
	for id in chain:
		var point: Vector2 = graph.vertices[id].position
		if not points.is_empty(): point.x = Sphere.near_x(point.x,points[-1].x,width)
		points.append(point)
	var risk := 0.; var length := 0.
	for index in range(1,chain.size()):
		var weight := Edge.spherical_angle(points[index-1]/Vector2(2048,1024),points[index]/Vector2(2048,1024))
		length += weight; risk += weight*float(graph.link_risk["%d:%d"%[mini(chain[index-1],chain[index]),maxi(chain[index-1],chain[index])]])
	graph.edges.append({"a":a,"b":b,"control_city":control,"tier":tier,"protected":protected,"danger":risk/maxf(.000001,length),"path":points,"raw_path":points.duplicate(),"smooth_rounds":0})
