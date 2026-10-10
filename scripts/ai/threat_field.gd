class_name ThreatField
extends RefCounted
## 未来时间窗内的敌军威胁与友军支援场。

const HORIZON_DAYS: float = 60.0
const DECAY_DAYS: float = 30.0

var nation_id: int
var day: int
## Point queries memoize only requested nodes. Public dictionaries retain their
## original complete, ordered and mutable behavior when explicitly read.
var threat_by_city: Dictionary:
	get:
		if not _threat_materialized:
			_threat_values = _materialize(_threat_values, _threat_sources)
			_threat_sources.clear()
			_threat_materialized = true
		return _threat_values
	set(value):
		_threat_values = value
		_threat_sources.clear()
		_threat_materialized = true
var support_by_city: Dictionary:
	get:
		if not _support_materialized:
			_support_values = _materialize(_support_values, _support_sources)
			_support_sources.clear()
			_support_materialized = true
		return _support_values
	set(value):
		_support_values = value
		_support_sources.clear()
		_support_materialized = true
var _threat_values: Dictionary = {}
var _support_values: Dictionary = {}
var _threat_sources: Array[Dictionary] = []
var _support_sources: Array[Dictionary] = []
var _frozen_city_ids: Array[int] = []
var _threat_materialized := true
var _support_materialized := true
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
		field._frozen_city_ids.append(city.id)
	var enemy_sources := field._aggregate_sources(view.state, view.enemy_armies)
	var friendly_sources := field._aggregate_sources(view.state, view.friendly_armies)
	field._threat_sources = field._freeze_sources(view.state, enemy_sources)
	field._support_sources = field._freeze_sources(view.state, friendly_sources)
	field._threat_materialized = false
	field._support_materialized = false
	return field


## ThreatField 中 D/I 缓存与观察国无关。军队无视正容量道路的吞吐后，
## 多核阶段只需按唯一的起点预热，随后各国 worker 只读复用。
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
	if _threat_materialized:
		return float(_threat_values.get(city_id, 0.0))
	return _value_at(city_id, _threat_values, _threat_sources)


func support_at(city_id: int) -> float:
	if _support_materialized:
		return float(_support_values.get(city_id, 0.0))
	return _value_at(city_id, _support_values, _support_sources)


static func _value_at(city_id: int, values: Dictionary, sources: Array[Dictionary]) -> float:
	if values.has(city_id):
		return float(values[city_id])
	var total := 0.0
	for source in sources:
		var influence: Dictionary = source.influence
		if influence.has(city_id):
			total += float(source.power) * float(influence[city_id])
	values[city_id] = total
	return total


func _materialize(values: Dictionary, sources: Array[Dictionary]) -> Dictionary:
	var complete := {}
	for city_id in _frozen_city_ids:
		complete[city_id] = _value_at(city_id, values, sources)
	return complete


func _aggregate_sources(state: GameState, armies: Array[Army]) -> Dictionary:
	var sources_by_manpower := {}
	for army in armies:
		var power := ArmyPower.effective(army)
		if power <= 0.0:
			continue
		var required_manpower := 0
		if not sources_by_manpower.has(required_manpower):
			sources_by_manpower[required_manpower] = {}
		var sources: Dictionary = (
			sources_by_manpower[required_manpower]
		)
		if army.on_edge and army.move_to != -1:
			var edge := state.edge_of(army.move_from, army.move_to)
			if edge == null:
				continue
			var days := _edge_days(edge, army.max_size)
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


func _freeze_sources(
	state: GameState,
	sources_by_manpower: Dictionary
) -> Array[Dictionary]:
	var prepared: Array[Dictionary] = []
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
			# Caller-owned travel caches can change after build. Preserve the old
			# eager field's snapshot semantics, including source summation order.
			prepared.append({"power":power, "influence":influence.duplicate()})
	return prepared


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


func _travel_days_field(
	state: GameState,
	start: int,
	required_manpower: int
) -> Dictionary:
	var cache_key := "D:%d" % start
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
				or edge.max_manpower <= 0
			):
				continue
			var next_dist := current_dist + _edge_days(
				edge, required_manpower
			)
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


static func _edge_days(edge: Edge, formation_size: int = 0) -> float:
	return Simulation.edge_travel_days(edge, formation_size)


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
