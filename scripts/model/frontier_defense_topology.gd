class_name FrontierDefenseTopology
extends RefCounted
## 防区的稳定拓扑缓存。只保存控制区和外交派生的城市/道路集合，
## 不保存威胁、兵力或最终 Assignment。

var nation_id: int = -1
var ownership_revision: int = -1
var diplomacy_revision: int = -1
var frontier_signature: Array[int] = []
var primary_city_ids: Array[int] = []
var frontline_city_ids: Array[int] = []
var edge_neighbors_by_city: Dictionary = {}


static func build(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot
) -> FrontierDefenseTopology:
	var topology := FrontierDefenseTopology.new()
	topology.nation_id = view.nation_id
	topology.ownership_revision = (
		view.state.ownership_revision
	)
	topology.diplomacy_revision = (
		view.state.diplomacy_revision
	)
	topology.frontier_signature = _signature(
		view.state,
		snapshot
	)
	var primary_seen := {}
	for city_id_value in snapshot.frontier_cities:
		primary_seen[int(city_id_value)] = true
	for city_id_value in snapshot.potential_frontier_cities:
		primary_seen[int(city_id_value)] = true
	topology.primary_city_ids.assign(primary_seen.keys())
	EquivariantOrder.sort_city_ids(
		topology.primary_city_ids,
		view.state,
		view.nation_id
	)
	var frontline_seen := primary_seen.duplicate()
	for city_id in topology.primary_city_ids:
		for neighbor in view.state.neighbors(city_id):
			if (
				view.state.cities[neighbor].owner_nation
					== view.nation_id
			):
				frontline_seen[neighbor] = true
	topology.frontline_city_ids.assign(
		frontline_seen.keys()
	)
	EquivariantOrder.sort_city_ids(
		topology.frontline_city_ids,
		view.state,
		view.nation_id
	)
	return topology


func matches(
	view: AiWorldView,
	snapshot: StrategicMapSnapshot
) -> bool:
	return (
		nation_id == view.nation_id
		and ownership_revision
			== view.state.ownership_revision
		and diplomacy_revision
			== view.state.diplomacy_revision
		and frontier_signature
			== _signature(view.state, snapshot)
	)


static func _signature(
	state: GameState,
	snapshot: StrategicMapSnapshot
) -> Array[int]:
	var actual_cities: Array = (
		snapshot.frontier_cities.duplicate()
	)
	var potential_cities: Array = (
		snapshot.potential_frontier_cities.duplicate()
	)
	actual_cities.sort()
	potential_cities.sort()
	var actual_edges: Array[int] = []
	for edge in snapshot.frontier_edges:
		actual_edges.append(
			GameState.edge_key(edge.city_a, edge.city_b)
		)
	actual_edges.sort()
	var potential_edges: Array[int] = []
	for edge in snapshot.potential_frontier_edges:
		potential_edges.append(
			GameState.edge_key(edge.city_a, edge.city_b)
		)
	potential_edges.sort()
	var result: Array[int] = [
		state.ownership_revision,
		state.diplomacy_revision,
		actual_cities.size(),
	]
	for city_id in actual_cities:
		result.append(int(city_id))
	result.append(potential_cities.size())
	for city_id in potential_cities:
		result.append(int(city_id))
	result.append(actual_edges.size())
	result.append_array(actual_edges)
	result.append(potential_edges.size())
	result.append_array(potential_edges)
	return result
