class_name EquivariantOrder
extends RefCounted
## 镜像等变的确定性排序唯一真源。
##
## 城市 id / 军队 id 由创建顺序决定，在左右镜像下会反向，不能用于行为决胜。
## 本类以势力首都（无首都时用势力城市质心）定义局部横轴：位于地图左半侧的势力
## 向右为正，右半侧势力向左为正。水平镜像后局部横坐标与全局 y 坐标保持不变，
## 因而镜像国家得到相同排序。完全同位置、同状态的军队物理上可交换，比较返回 false。

const POSITION_SCALE: float = 1000000.0
const VALUE_SCALE: float = 1000000.0
const MAX_RANK_CACHE_ENTRIES: int = 2048

static var _city_rank_cache: Dictionary = {}


static func city_id_less(
	state: GameState,
	nation_id: int,
	a_id: int,
	b_id: int,
	anchor_city_id: int = -1
) -> bool:
	if a_id == b_id:
		return false
	if not _valid_city(state, a_id):
		return false
	if not _valid_city(state, b_id):
		return true
	var rank := city_rank_map(
		state,
		nation_id,
		anchor_city_id
	)
	return int(rank[a_id]) < int(rank[b_id])


static func city_less(
	state: GameState,
	nation_id: int,
	a: City,
	b: City,
	anchor_city_id: int = -1
) -> bool:
	if a == b:
		return false
	return city_id_less(state, nation_id, a.id, b.id, anchor_city_id)


static func sort_city_ids(
	values: Array,
	state: GameState,
	nation_id: int,
	anchor_city_id: int = -1
) -> void:
	var rank := city_rank_map(
		state,
		nation_id,
		anchor_city_id
	)
	values.sort_custom(func(a, b) -> bool:
		return int(rank.get(int(a), 1 << 30)) < int(
			rank.get(int(b), 1 << 30)
		)
	)


static func city_rank_map(
	state: GameState,
	nation_id: int,
	anchor_city_id: int = -1
) -> Dictionary:
	var capital_id := -1
	if nation_id >= 0 and nation_id < state.nations.size():
		capital_id = state.nations[nation_id].capital_city_id
	var cache_key := "%d:%d:%d:%d:%d" % [
		state.get_instance_id(),
		nation_id,
		capital_id,
		anchor_city_id,
		state.ownership_revision,
	]
	if _city_rank_cache.has(cache_key):
		return _city_rank_cache[cache_key]
	var ids: Array[int] = []
	var keys := {}
	for city in state.cities:
		ids.append(city.id)
		keys[city.id] = city_key(
			state,
			nation_id,
			city.id,
			anchor_city_id
		)
	ids.sort_custom(func(a: int, b: int) -> bool:
		return _key_less(keys[a], keys[b])
	)
	var rank := {}
	var current_rank := 0
	for index in range(ids.size()):
		if index > 0:
			var previous_id := ids[index - 1]
			var current_id := ids[index]
			if (
				_key_less(keys[previous_id], keys[current_id])
				or _key_less(keys[current_id], keys[previous_id])
			):
				current_rank = index
		rank[ids[index]] = current_rank
	if _city_rank_cache.size() >= MAX_RANK_CACHE_ENTRIES:
		_city_rank_cache.clear()
	_city_rank_cache[cache_key] = rank
	return rank


static func city_key(
	state: GameState,
	nation_id: int,
	city_id: int,
	anchor_city_id: int = -1
) -> Array[int]:
	if not _valid_city(state, city_id):
		return [1 << 30, 1 << 30]
	var origin := _nation_anchor(state, nation_id)
	if _valid_city(state, anchor_city_id):
		origin = state.cities[anchor_city_id].map_position
	var position := state.cities[city_id].map_position
	var sign := _nation_forward_sign(state, nation_id)
	return [
		_quantize(
			_oriented_x(position, origin, sign),
			POSITION_SCALE
		),
		_quantize(position.y, POSITION_SCALE),
		_quantize(absf(position.x - 0.5), POSITION_SCALE),
		_quantize(state.cities[city_id].terrain_height, VALUE_SCALE),
		_quantize(state.cities[city_id].terrain_relief, VALUE_SCALE),
	]


static func army_less(
	state: GameState,
	nation_id: int,
	a: Army,
	b: Army,
	anchor_city_id: int = -1
) -> bool:
	if a == b:
		return false
	var origin := _nation_anchor(state, nation_id)
	if _valid_city(state, anchor_city_id):
		origin = state.cities[anchor_city_id].map_position
	var sign := _nation_forward_sign(state, nation_id)
	var position_a := army_position(state, a)
	var position_b := army_position(state, b)
	var comparison := _compare_int(
		_quantize(
			_oriented_x(position_a, origin, sign),
			POSITION_SCALE
		),
		_quantize(
			_oriented_x(position_b, origin, sign),
			POSITION_SCALE
		)
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		_quantize(position_a.y, POSITION_SCALE),
		_quantize(position_b.y, POSITION_SCALE)
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(a.state, b.state)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		1 if a.encounter_blocked else 0,
		1 if b.encounter_blocked else 0
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(a.size, b.size)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(a.max_size, b.max_size)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(a.attack, b.attack)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(a.defense, b.defense)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		_quantize(a.morale, VALUE_SCALE),
		_quantize(b.morale, VALUE_SCALE)
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		_quantize(a.supply_ratio, VALUE_SCALE),
		_quantize(b.supply_ratio, VALUE_SCALE)
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(a.holding_days, b.holding_days)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		_quantize(a.move_progress, VALUE_SCALE),
		_quantize(b.move_progress, VALUE_SCALE)
	)
	if comparison != 0:
		return comparison < 0
	var target_a := a.move_to if a.move_to >= 0 else a.ai_target_city
	var target_b := b.move_to if b.move_to >= 0 else b.ai_target_city
	if target_a != target_b:
		return city_id_less(
			state,
			nation_id,
			target_a,
			target_b,
			anchor_city_id
		)
	comparison = _compare_int(a.ai_action, b.ai_action)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		a.ai_order_until_day,
		b.ai_order_until_day
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		a.defensive_deployment_until_day,
		b.defensive_deployment_until_day
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		_quantize(
			a.offensive_attack_multiplier,
			VALUE_SCALE
		),
		_quantize(
			b.offensive_attack_multiplier,
			VALUE_SCALE
		)
	)
	if comparison != 0:
		return comparison < 0
	comparison = _compare_int(
		a.offensive_bonus_until_day,
		b.offensive_bonus_until_day
	)
	if comparison != 0:
		return comparison < 0
	return false


static func army_key(
	state: GameState,
	nation_id: int,
	army: Army,
	anchor_city_id: int = -1
) -> Array[int]:
	var origin := _nation_anchor(state, nation_id)
	if _valid_city(state, anchor_city_id):
		origin = state.cities[anchor_city_id].map_position
	var position := army_position(state, army)
	var sign := _nation_forward_sign(state, nation_id)
	var move_target_key := city_key(
		state,
		nation_id,
		army.move_to if army.move_to >= 0 else army.ai_target_city,
		anchor_city_id
	)
	return [
		_quantize(
			_oriented_x(position, origin, sign),
			POSITION_SCALE
		),
		_quantize(position.y, POSITION_SCALE),
		army.state,
			1 if army.encounter_blocked else 0,
		army.size,
		army.max_size,
		army.attack,
		army.defense,
		_quantize(army.morale, VALUE_SCALE),
		_quantize(army.supply_ratio, VALUE_SCALE),
		army.holding_days,
		_quantize(army.move_progress, VALUE_SCALE),
		move_target_key[0],
		move_target_key[1],
		army.ai_action,
		army.ai_order_until_day,
		army.defensive_deployment_until_day,
		_quantize(army.offensive_attack_multiplier, VALUE_SCALE),
		army.offensive_bonus_until_day,
	]


static func army_position(state: GameState, army: Army) -> Vector2:
	if (
		army.on_edge
		and _valid_city(state, army.move_from)
		and _valid_city(state, army.move_to)
	):
		return state.cities[army.move_from].map_position.lerp(
			state.cities[army.move_to].map_position,
			clampf(army.move_progress, 0.0, 1.0)
		)
	if _valid_city(state, army.location_city):
		return state.cities[army.location_city].map_position
	if _valid_city(state, army.move_from):
		return state.cities[army.move_from].map_position
	return Vector2.ZERO


static func nation_less(
	state: GameState,
	observer_nation: int,
	a_nation: int,
	b_nation: int
) -> bool:
	if a_nation == b_nation:
		return false
	var observer_anchor := _nation_anchor(state, observer_nation)
	var sign := _nation_forward_sign(state, observer_nation)
	var a := _nation_anchor(state, a_nation)
	var b := _nation_anchor(state, b_nation)
	var key_a := [
		_quantize(
			_oriented_x(a, observer_anchor, sign),
			POSITION_SCALE
		),
		_quantize(a.y, POSITION_SCALE),
	]
	var key_b := [
		_quantize(
			_oriented_x(b, observer_anchor, sign),
			POSITION_SCALE
		),
		_quantize(b.y, POSITION_SCALE),
	]
	return _key_less(key_a, key_b)


static func edge_less(
	state: GameState,
	nation_id: int,
	a: Edge,
	b: Edge,
	anchor_city_id: int = -1
) -> bool:
	if a == b:
		return false
	return _key_less(
		edge_key(state, nation_id, a, anchor_city_id),
		edge_key(state, nation_id, b, anchor_city_id)
	)


static func edge_key(
	state: GameState,
	nation_id: int,
	edge: Edge,
	anchor_city_id: int = -1
) -> Array[int]:
	var a_key := city_key(
		state,
		nation_id,
		edge.city_a,
		anchor_city_id
	)
	var b_key := city_key(
		state,
		nation_id,
		edge.city_b,
		anchor_city_id
	)
	if _key_less(b_key, a_key):
		var swap := a_key
		a_key = b_key
		b_key = swap
	var result: Array[int] = []
	result.append_array(a_key)
	result.append_array(b_key)
	result.append(edge.distance)
	result.append(_quantize(edge.danger, VALUE_SCALE))
	result.append(edge.max_manpower)
	return result


## 不依赖势力朝向的镜像轨道键。用于战斗随机指纹：水平镜像前后保持相同。
static func mirror_orbit_position_key(position: Vector2) -> Array[int]:
	return [
		_quantize(absf(position.x - 0.5), POSITION_SCALE),
		_quantize(position.y, POSITION_SCALE),
	]


static func mirror_orbit_city_less(
	state: GameState,
	a_id: int,
	b_id: int
) -> bool:
	if a_id == b_id:
		return false
	if not _valid_city(state, a_id):
		return false
	if not _valid_city(state, b_id):
		return true
	var a_key := mirror_orbit_position_key(
		state.cities[a_id].map_position
	)
	var b_key := mirror_orbit_position_key(
		state.cities[b_id].map_position
	)
	return _key_less(a_key, b_key)


static func mirror_orbit_army_less(
	state: GameState,
	a: Army,
	b: Army
) -> bool:
	if a == b:
		return false
	return _key_less(
		mirror_orbit_army_key(state, a),
		mirror_orbit_army_key(state, b)
	)


static func mirror_orbit_army_key(
	state: GameState,
	army: Army
) -> Array[int]:
	var result := mirror_orbit_position_key(army_position(state, army))
	var nation_anchor_key := mirror_orbit_position_key(
		_nation_anchor(state, army.owner_nation)
	)
	result.append_array(nation_anchor_key)
	result.append(army.state)
	result.append(1 if army.encounter_blocked else 0)
	result.append(army.size)
	result.append(army.max_size)
	result.append(army.attack)
	result.append(army.defense)
	result.append(_quantize(army.morale, VALUE_SCALE))
	result.append(_quantize(army.supply_ratio, VALUE_SCALE))
	result.append(army.holding_days)
	return result


## 战斗侧的稳定随机身份：只使用镜像轨道位置、势力中心和行军方向，不含实体 id 或战力参数。
static func tactical_side_key(
	state: GameState,
	army: Army
) -> int:
	var values := mirror_orbit_position_key(
		army_position(state, army)
	)
	values.append_array(mirror_orbit_position_key(
		_nation_anchor(state, army.owner_nation)
	))
	if _valid_city(state, army.move_from):
		values.append_array(mirror_orbit_position_key(
			state.cities[army.move_from].map_position
		))
	if _valid_city(state, army.move_to):
		values.append_array(mirror_orbit_position_key(
			state.cities[army.move_to].map_position
		))
	var result := 17
	for value in values:
		result = posmod(
			result * 48271 + int(value) + 1,
			2147483647
		)
	return maxi(result, 1)


static func mirror_orbit_edge_less(
	state: GameState,
	a: Edge,
	b: Edge
) -> bool:
	if a == b:
		return false
	return _key_less(
		_mirror_orbit_edge_key(state, a),
		_mirror_orbit_edge_key(state, b)
	)


static func encounter_pair_less(
	state: GameState,
	a1: Army,
	a2: Army,
	b1: Army,
	b2: Army
) -> bool:
	return _key_less(
		encounter_pair_key(state, a1, a2),
		encounter_pair_key(state, b1, b2)
	)


static func encounter_pair_equivalent(
	state: GameState,
	a1: Army,
	a2: Army,
	b1: Army,
	b2: Army
) -> bool:
	var a_key := encounter_pair_key(state, a1, a2)
	var b_key := encounter_pair_key(state, b1, b2)
	return not _key_less(a_key, b_key) and not _key_less(
		b_key,
		a_key
	)


static func encounter_pair_key(
	state: GameState,
	a1: Army,
	a2: Army
) -> Array[int]:
	var a_key_1 := mirror_orbit_army_key(state, a1)
	var a_key_2 := mirror_orbit_army_key(state, a2)
	if _key_less(a_key_2, a_key_1):
		var a_swap := a_key_1
		a_key_1 = a_key_2
		a_key_2 = a_swap
	var a_pair: Array[int] = []
	a_pair.append_array(a_key_1)
	a_pair.append_array(a_key_2)
	return a_pair


static func _mirror_orbit_edge_key(
	state: GameState,
	edge: Edge
) -> Array[int]:
	var a_key := mirror_orbit_position_key(
		state.cities[edge.city_a].map_position
	)
	var b_key := mirror_orbit_position_key(
		state.cities[edge.city_b].map_position
	)
	if _key_less(b_key, a_key):
		var swap := a_key
		a_key = b_key
		b_key = swap
	var result: Array[int] = []
	result.append_array(a_key)
	result.append_array(b_key)
	result.append(edge.distance)
	result.append(_quantize(edge.danger, VALUE_SCALE))
	result.append(edge.max_manpower)
	return result


static func _nation_anchor(state: GameState, nation_id: int) -> Vector2:
	if nation_id >= 0 and nation_id < state.nations.size():
		var capital_id := state.nations[nation_id].capital_city_id
		if _valid_city(state, capital_id):
			return state.cities[capital_id].map_position
	var sum := Vector2.ZERO
	var count := 0
	for city in state.cities:
		if city.owner_nation == nation_id:
			sum += city.map_position
			count += 1
	if count > 0:
		return sum / float(count)
	return Vector2(0.5, 0.5)


static func _nation_forward_sign(state: GameState, nation_id: int) -> float:
	var anchor := _nation_anchor(state, nation_id)
	if anchor.x < 0.5:
		return 1.0
	if anchor.x > 0.5:
		return -1.0
	# 中轴势力用质心相对世界中心定向；首都和质心均完全居中时返回 0，
	# 调用方改用 abs(x-0.5) 镜像轨道，不能任意固定 +1。
	var centroid := Vector2.ZERO
	var count := 0
	for city in state.cities:
		if city.owner_nation == nation_id:
			centroid += city.map_position
			count += 1
	if count > 0 and centroid.x / float(count) > 0.5:
		return -1.0
	if count > 0 and centroid.x / float(count) < 0.5:
		return 1.0
	return 0.0


static func _oriented_x(
	position: Vector2,
	origin: Vector2,
	sign: float
) -> float:
	if is_zero_approx(sign):
		return absf(position.x - 0.5)
	return (position.x - origin.x) * sign


static func _key_less(a: Array, b: Array) -> bool:
	var count := mini(a.size(), b.size())
	for i in range(count):
		if a[i] != b[i]:
			return a[i] < b[i]
	return a.size() < b.size()


static func _compare_int(a: int, b: int) -> int:
	if a < b:
		return -1
	if a > b:
		return 1
	return 0


static func _quantize(value: float, scale: float) -> int:
	return int(round(value * scale))


static func _valid_city(state: GameState, city_id: int) -> bool:
	return city_id >= 0 and city_id < state.cities.size()
