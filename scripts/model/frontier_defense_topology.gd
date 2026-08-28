class_name FrontierDefenseTopology
extends RefCounted
## 防区的稳定拓扑缓存。只保存控制区和外交派生的城市/道路集合，
## 不保存威胁、兵力或最终 Assignment。

var nation_id: int = -1
var ownership_revision: int = -1
var diplomacy_revision: int = -1
var road_network_revision: int = -1
var frontier_signature: Array[int] = []
var owned_city_ids: Array[int] = []
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
	topology.road_network_revision = (
		view.state.road_network_revision
	)
	topology.frontier_signature = _signature(
		view.state,
		snapshot
	)
	for city in view.friendly_cities:
		topology.owned_city_ids.append(city.id)
	topology.owned_city_ids.sort()
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
	# LINE 防区只在控制权或外交关系发生结构变化时重建。
	# potential_frontier_* 会随敌军集结、国力和威胁阈值波动；把它放进
	# matches 会导致同一场长期战争里不断删建防区，清空持久 assignment。
	# 首次构建时仍可吸收当时的潜在边境，之后动态风险由 MAIN 响应。
	var current_owned_city_ids: Array[int] = []
	for city in view.friendly_cities:
		current_owned_city_ids.append(city.id)
	current_owned_city_ids.sort()
	return (
		nation_id == view.nation_id
		and owned_city_ids == current_owned_city_ids
		and road_network_revision
			== view.state.road_network_revision
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
	actual_cities.sort()
	var actual_edges: Array[int] = []
	for edge in snapshot.frontier_edges:
		actual_edges.append(
			GameState.edge_key(edge.city_a, edge.city_b)
		)
	actual_edges.sort()
	var result: Array[int] = [
		actual_cities.size(),
	]
	for city_id in actual_cities:
		result.append(int(city_id))
	result.append(actual_edges.size())
	result.append_array(actual_edges)
	return result
