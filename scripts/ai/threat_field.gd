class_name ThreatField
extends RefCounted
## 未来时间窗内的敌军威胁与友军支援场。

const HORIZON_DAYS: float = 60.0
const DECAY_DAYS: float = 30.0

var nation_id: int
var day: int
var threat_by_city: Dictionary = {}
var support_by_city: Dictionary = {}
var travel_distance_cache: Dictionary = {}
## 多核构建时只读共享的已完成缓存；新条目只写 travel_distance_cache。
## 主线程等待全部 worker 完成后再按固定顺序合并，避免 Dictionary 并发写。
var travel_distance_base_cache: Dictionary = {}


static func build(
	view: AiWorldView,
	shared_travel_cache: Dictionary = {},
	local_write_cache: Dictionary = {},
	use_readonly_base_cache: bool = false
) -> ThreatField:
	var field := ThreatField.new()
	field.nation_id = view.nation_id
	field.day = view.day
	if use_readonly_base_cache:
		field.travel_distance_base_cache = shared_travel_cache
		field.travel_distance_cache = local_write_cache
	else:
		field.travel_distance_cache = shared_travel_cache
	for city in view.state.cities:
		field.threat_by_city[city.id] = 0.0
		field.support_by_city[city.id] = 0.0
	var enemy_sources := field._aggregate_sources(view.state, view.enemy_armies)
	var friendly_sources := field._aggregate_sources(view.state, view.friendly_armies)
	field._accumulate(view.state, enemy_sources, field.threat_by_city)
	field._accumulate(view.state, friendly_sources, field.support_by_city)
	return field


## ThreatField 中 D/I 缓存与观察国无关。多核阶段先按唯一
## (起点,编制容量) 预热这些图搜索结果，随后各国 worker 只读复用。
static func build_shared_travel_request(
	state: GameState,
	start: int,
	required_manpower: int,
	output: Dictionary
) -> void:
	var field := ThreatField.new()
	field.nation_id = 0
	field.travel_distance_cache = output
	field._influence_field(state, start, required_manpower)


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
		EquivariantOrder.sort_city_ids(
			source_ids,
			state,
			nation_id
		)
		for source_id in source_ids:
			var power := float(sources[source_id])
			var influence := _influence_field(
				state,
				int(source_id),
				required_manpower
			)
			var city_ids := _ordered_influence_city_ids(
				state,
				int(source_id),
				required_manpower,
				influence
			)
			for city_id in city_ids:
				output[city_id] = (
					float(output.get(city_id, 0.0))
					+ power * float(influence[city_id])
				)


func _influence_field(
	state: GameState,
	start: int,
	required_manpower: int
) -> Dictionary:
	var cache_key := "I:%d:%d" % [
		start,
		required_manpower,
	]
	if _travel_cache_has(cache_key):
		return _travel_cache_get(cache_key)
	var distances := _travel_days_field(
		state,
		start,
		required_manpower
	)
	var influence := {}
	for city_id in distances:
		influence[city_id] = exp(
			-float(distances[city_id]) / DECAY_DAYS
		)
	travel_distance_cache[cache_key] = influence
	return influence


func _ordered_influence_city_ids(
	state: GameState,
	start: int,
	required_manpower: int,
	influence: Dictionary
) -> Array:
	var cache_key := "O:%d:%d:%d" % [
		nation_id,
		start,
		required_manpower,
	]
	if _travel_cache_has(cache_key):
		return _travel_cache_get(cache_key)
	var city_ids := influence.keys()
	EquivariantOrder.sort_city_ids(
		city_ids,
		state,
		nation_id,
		state.nations[nation_id].capital_city_id
	)
	travel_distance_cache[cache_key] = city_ids
	return city_ids


func _travel_days_field(
	state: GameState,
	start: int,
	required_manpower: int
) -> Dictionary:
	var cache_key := "D:%d:%d" % [
		start,
		required_manpower,
	]
	if _travel_cache_has(cache_key):
		return _travel_cache_get(cache_key)
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
	travel_distance_cache[cache_key] = dist
	return dist


func _travel_cache_has(key: String) -> bool:
	return (
		travel_distance_cache.has(key)
		or travel_distance_base_cache.has(key)
	)


func _travel_cache_get(key: String) -> Variant:
	if travel_distance_cache.has(key):
		return travel_distance_cache[key]
	return travel_distance_base_cache[key]


static func _edge_days(edge: Edge) -> float:
	return Simulation.edge_travel_days(edge)


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
