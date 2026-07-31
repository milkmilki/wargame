class_name ThreatField
extends RefCounted
## 未来时间窗内的敌军威胁与友军支援场。

const HORIZON_DAYS: float = 60.0
const DECAY_DAYS: float = 30.0

var nation_id: int
var day: int
var threat_by_city: Dictionary = {}
var support_by_city: Dictionary = {}


static func build(view: AiWorldView) -> ThreatField:
	var field := ThreatField.new()
	field.nation_id = view.nation_id
	field.day = view.day
	for city in view.state.cities:
		field.threat_by_city[city.id] = 0.0
		field.support_by_city[city.id] = 0.0
	var enemy_sources := field._aggregate_sources(view.state, view.enemy_armies)
	var friendly_sources := field._aggregate_sources(view.state, view.friendly_armies)
	field._accumulate(view.state, enemy_sources, field.threat_by_city)
	field._accumulate(view.state, friendly_sources, field.support_by_city)
	return field


func threat_at(city_id: int) -> float:
	return float(threat_by_city.get(city_id, 0.0))


func support_at(city_id: int) -> float:
	return float(support_by_city.get(city_id, 0.0))


func _aggregate_sources(state: GameState, armies: Array[Army]) -> Dictionary:
	var sources_by_manpower := {}
	for army in armies:
		var power := ArmyPower.effective(army)
		if power <= 0.0:
			continue
		var required_manpower := maxi(army.max_size, 1)
		if not sources_by_manpower.has(required_manpower):
			sources_by_manpower[required_manpower] = {}
		var sources: Dictionary = (
			sources_by_manpower[required_manpower]
		)
		if army.on_edge and army.move_to != -1:
			var edge := state.edge_of(army.move_from, army.move_to)
			if edge == null:
				continue
			var days := _edge_days(edge)
			var progress := clampf(army.move_progress, 0.0, 1.0)
			_add_source(sources, army.move_from, power, progress * days)
			_add_source(sources, army.move_to, power, (1.0 - progress) * days)
		else:
			var city_id := army.location_city
			if city_id >= 0 and city_id < state.cities.size():
				_add_source(sources, city_id, power, 0.0)
	return sources_by_manpower


func _add_source(sources: Dictionary, city_id: int, power: float, offset_days: float) -> void:
	var discounted := power * exp(-offset_days / DECAY_DAYS)
	sources[city_id] = float(sources.get(city_id, 0.0)) + discounted


func _accumulate(
	state: GameState,
	sources_by_manpower: Dictionary,
	output: Dictionary
) -> void:
	var manpower_levels := sources_by_manpower.keys()
	manpower_levels.sort()
	for manpower_value in manpower_levels:
		var required_manpower := int(manpower_value)
		var sources: Dictionary = (
			sources_by_manpower[required_manpower]
		)
		var source_ids := sources.keys()
		source_ids.sort()
		for source_id in source_ids:
			var power := float(sources[source_id])
			var distances := _travel_days_field(
				state,
				int(source_id),
				required_manpower
			)
			for city_id in distances.keys():
				var arrival := float(distances[city_id])
				if arrival <= HORIZON_DAYS:
					output[city_id] = (
						float(output.get(city_id, 0.0))
						+ power * exp(
							-arrival / DECAY_DAYS
						)
					)


static func _travel_days_field(
	state: GameState,
	start: int,
	required_manpower: int
) -> Dictionary:
	var dist := {start: 0.0}
	var heap: Array = []
	_heap_push(heap, [0.0, start])
	while not heap.is_empty():
		var item: Array = _heap_pop(heap)
		var current_dist: float = item[0]
		var city_id: int = item[1]
		if current_dist > float(dist.get(city_id, INF)) + 0.0001:
			continue
		if current_dist > HORIZON_DAYS:
			continue
		for neighbor in state.neighbors(city_id):
			var edge := state.edge_of(city_id, neighbor)
			if (
				edge == null
				or edge.max_manpower < required_manpower
			):
				continue
			var next_dist := current_dist + _edge_days(edge)
			if next_dist > HORIZON_DAYS:
				continue
			if next_dist < float(dist.get(neighbor, INF)):
				dist[neighbor] = next_dist
				_heap_push(heap, [next_dist, neighbor])
	return dist


static func _edge_days(edge: Edge) -> float:
	return clampf(10.0 + float(maxi(edge.distance, 1) - 1) * 5.0, 10.0, 30.0)


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if _heap_less(heap[parent], item):
			break
		heap[index] = heap[parent]
		index = parent
	heap[index] = item


static func _heap_pop(heap: Array) -> Array:
	var result: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return result
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := left
		if right < heap.size() and _heap_less(heap[right], heap[left]):
			child = right
		if _heap_less(last, heap[child]):
			break
		heap[index] = heap[child]
		index = child
	heap[index] = last
	return result


static func _heap_less(a: Array, b: Array) -> bool:
	var da: float = a[0]
	var db: float = b[0]
	return da < db or (is_equal_approx(da, db) and int(a[1]) < int(b[1]))
