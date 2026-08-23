class_name EncirclementIndex
extends RefCounted
## 单个目标国家的围困价值索引。构造时固化城市与军队聚合，按目标城惰性缓存结果。


var _state: GameState
var _target_nation: int
var _target_nation_is_valid: bool = false
var _capital: int = -1
var _owned_city_ids: Array[int] = []
var _army_nodes: Array[int] = []
var _army_powers: Array[float] = []
var _army_required_manpower: Array[int] = []
var _total_power: float = 0.0
var _value_by_target_city: Dictionary = {}


func _init(state: GameState, target_nation: int) -> void:
	_state = state
	_target_nation = target_nation
	if state == null:
		return
	_target_nation_is_valid = (
		target_nation >= 0
		and target_nation < state.nations.size()
	)
	if not _target_nation_is_valid:
		return

	_capital = state.nations[target_nation].capital_city_id
	for city in state.cities:
		if city.owner_nation == target_nation:
			_owned_city_ids.append(city.id)
	for army in state.armies:
		if army.owner_nation != target_nation or army.size <= 0:
			continue
		var power := ArmyPower.effective(army)
		_army_nodes.append(army.current_city_node())
		_army_powers.append(power)
		_army_required_manpower.append(maxi(army.max_size, 1))
		_total_power += power


func has_cached(target_city: int) -> bool:
	return _value_by_target_city.has(target_city)


func value_for(target_city: int) -> float:
	if _value_by_target_city.has(target_city):
		return float(_value_by_target_city[target_city])

	var value := 0.0
	if (
		_target_nation_is_valid
		and target_city >= 0
		and target_city < _state.cities.size()
	):
		var effect := _target_encirclement_effect(target_city)
		value = (
			float(effect["cut_city_ratio"]) * 6.0
			+ float(effect["cut_troop_ratio"]) * 8.0
			+ _isolated_garrison_power_ratio(target_city) * 8.0
		)

	_value_by_target_city[target_city] = value
	return value


func _target_encirclement_effect(target_city: int) -> Dictionary:
	# 与 DiplomacyAI._target_encirclement_effect 保持同一删除节点 BFS 顺序。
	if _capital < 0 or _capital == target_city:
		return {
			"cut_city_ratio": 0.0,
			"cut_troop_ratio": 0.0,
		}

	var reachable := {_capital: true}
	var queue: Array[int] = [_capital]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor in _state.neighbors(current):
			if neighbor == target_city or reachable.has(neighbor):
				continue
			var edge := _state.edge_of(current, neighbor)
			if (
				edge == null
				or edge.max_manpower <= 0
				or not _state.has_military_access(
					_target_nation,
					_state.cities[neighbor].owner_nation
				)
			):
				continue
			reachable[neighbor] = true
			queue.append(neighbor)

	var total := 0
	var cut := 0
	for city_id in _owned_city_ids:
		if city_id == target_city:
			continue
		total += 1
		if not reachable.has(city_id):
			cut += 1

	var cut_power := 0.0
	for index in range(_army_nodes.size()):
		var node_city := _army_nodes[index]
		if (
			node_city >= 0
			and node_city != target_city
			and not reachable.has(node_city)
		):
			cut_power += _army_powers[index]
	return {
		"cut_city_ratio": (
			float(cut) / float(maxi(total, 1))
		),
		"cut_troop_ratio": (
			cut_power / maxf(_total_power, 1.0)
		),
	}


func _isolated_garrison_power_ratio(city_id: int) -> float:
	var isolated_power := 0.0
	var retreat_route_by_capacity := {}
	for index in range(_army_nodes.size()):
		if _army_nodes[index] != city_id:
			continue
		var required_manpower := _army_required_manpower[index]
		if not retreat_route_by_capacity.has(required_manpower):
			retreat_route_by_capacity[required_manpower] = (
				Pathfinding.has_friendly_retreat_route_from_city(
					_state,
					_target_nation,
					city_id,
					required_manpower
				)
			)
		if not bool(retreat_route_by_capacity[required_manpower]):
			isolated_power += _army_powers[index]
	return isolated_power / maxf(_total_power, 1.0)
