class_name ArmyCoordinator
extends RefCounted
## 国家级军队协调：同位置合并与目标兵力预留。

var assigned_power: Dictionary = {}    ## target_city -> float
var assigned_size: Dictionary = {}     ## target_city -> 原始兵力
var assigned_armies: Dictionary = {}   ## target_city -> Array[int]
var city_defense_power: Dictionary = {} ## target_city -> 确定进入城市的防御战力
var city_defense_armies: Dictionary = {} ## target_city -> Array[int]
var edge_defense_power: Dictionary = {} ## "city:neighbor" -> 驻守该方向的战力
var edge_defense_armies: Dictionary = {} ## "city:neighbor" -> Array[int]
var _reserved_target_by_army: Dictionary = {} ## army.id -> target_city
var _reserved_power_by_army: Dictionary = {} ## army.id -> float
var _reserved_size_by_army: Dictionary = {} ## army.id -> int
var _city_defense_target_by_army: Dictionary = {} ## army.id -> city_id
var _edge_key_by_army: Dictionary = {} ## army.id -> String


## 从同一冻结视图建立国家级覆盖账本。所有调用方必须以此作为旧命令真源，
## 避免常规决策与重点城市逐日增援各自统计一遍、对同一在途军得出不同缺口。
static func from_view(view: AiWorldView) -> ArmyCoordinator:
	var coordinator := ArmyCoordinator.new()
	if view == null:
		return coordinator
	for army in view.friendly_armies:
		if army.size <= 0:
			continue
		if (
			army.ai_target_city >= 0
			and army.state in [
				Army.State.MOVING,
				Army.State.FIGHTING,
			]
		):
			var target_city := army.ai_target_city
			var defends_own_city := (
				target_city < view.state.cities.size()
				and view.state.cities[target_city].owner_nation
					== view.nation_id
			)
			coordinator.reserve(
				target_city,
				army,
				defends_own_city
			)
		elif army.state == Army.State.HOLDING and army.move_to != -1:
			var friendly_endpoint := army.move_from
			if not view.state.has_military_access(
				view.nation_id,
				view.state.cities[friendly_endpoint].owner_nation
			):
				friendly_endpoint = army.move_to
			var other_endpoint := (
				army.move_to
				if friendly_endpoint == army.move_from
				else army.move_from
			)
			coordinator.reserve_edge(
				friendly_endpoint,
				other_endpoint,
				army
			)
	return coordinator


func reserve(
	target_city: int,
	army: Army,
	counts_as_city_defense: bool = true
) -> void:
	if target_city < 0:
		return
	# 一支军在冻结决策周期内只能提供一份覆盖。战役规划、常规决策和
	# 重点城增援可能先后看见同一军。相同预留幂等，新命令则原子替换旧姿态。
	if (
		int(_reserved_target_by_army.get(army.id, -1))
			== target_city
		and not _edge_key_by_army.has(army.id)
		and _city_defense_target_by_army.has(army.id)
			== counts_as_city_defense
	):
		return
	_clear_reservation(army.id)
	_add_target_reservation(target_city, army)
	if counts_as_city_defense:
		_add_city_defense(target_city, army)


func _add_target_reservation(target_city: int, army: Army) -> void:
	_reserved_target_by_army[army.id] = target_city
	var power := ArmyPower.effective(army)
	_reserved_power_by_army[army.id] = power
	_reserved_size_by_army[army.id] = army.size
	assigned_power[target_city] = float(
		assigned_power.get(target_city, 0.0)
	) + power
	assigned_size[target_city] = int(assigned_size.get(target_city, 0)) + army.size
	if not assigned_armies.has(target_city):
		assigned_armies[target_city] = [] as Array[int]
	(assigned_armies[target_city] as Array[int]).append(army.id)


func power_reserved(target_city: int) -> float:
	return float(assigned_power.get(target_city, 0.0))


func size_reserved(target_city: int) -> int:
	return int(assigned_size.get(target_city, 0))


func city_defense_power_reserved(
	target_city: int,
	excluded: Army = null
) -> float:
	var result := float(city_defense_power.get(target_city, 0.0))
	if (
		excluded != null
		and int(_city_defense_target_by_army.get(
			excluded.id, -1
		)) == target_city
	):
		result -= float(_reserved_power_by_army.get(
			excluded.id, 0.0
		))
	return maxf(result, 0.0)


func city_defense_army_ids(target_city: int) -> Array[int]:
	return (
		city_defense_armies.get(
			target_city,
			[] as Array[int]
		) as Array[int]
	).duplicate()


func reserve_edge(
	friendly_city: int,
	other_city: int,
	army: Army
) -> void:
	var key := _edge_defense_key(friendly_city, other_city)
	if (
		int(_reserved_target_by_army.get(army.id, -1))
			== friendly_city
		and str(_edge_key_by_army.get(army.id, "")) == key
	):
		return
	_clear_reservation(army.id)
	_add_target_reservation(friendly_city, army)
	_edge_key_by_army[army.id] = key
	edge_defense_power[key] = float(
		edge_defense_power.get(key, 0.0)
	) + ArmyPower.effective(army)
	if not edge_defense_armies.has(key):
		edge_defense_armies[key] = [] as Array[int]
	(edge_defense_armies[key] as Array[int]).append(army.id)


func edge_defense_power_reserved(
	friendly_city: int,
	other_city: int,
	excluded: Army = null
) -> float:
	var key := _edge_defense_key(friendly_city, other_city)
	var result := float(edge_defense_power.get(key, 0.0))
	if (
		excluded != null
		and str(_edge_key_by_army.get(excluded.id, "")) == key
	):
		result -= float(_reserved_power_by_army.get(
			excluded.id, 0.0
		))
	return maxf(result, 0.0)


func _add_city_defense(target_city: int, army: Army) -> void:
	_city_defense_target_by_army[army.id] = target_city
	city_defense_power[target_city] = float(
		city_defense_power.get(target_city, 0.0)
	) + ArmyPower.effective(army)
	if not city_defense_armies.has(target_city):
		city_defense_armies[target_city] = [] as Array[int]
	(
		city_defense_armies[target_city] as Array[int]
	).append(army.id)


func _city_defense_contains(target_city: int, army_id: int) -> bool:
	return (
		city_defense_armies.get(
			target_city,
			[] as Array[int]
		) as Array[int]
	).has(army_id)


func _clear_reservation(army_id: int) -> void:
	if not _reserved_target_by_army.has(army_id):
		return
	var target_city := int(_reserved_target_by_army[army_id])
	var power := float(_reserved_power_by_army.get(army_id, 0.0))
	var size := int(_reserved_size_by_army.get(army_id, 0))
	assigned_power[target_city] = maxf(
		float(assigned_power.get(target_city, 0.0)) - power,
		0.0
	)
	assigned_size[target_city] = maxi(
		int(assigned_size.get(target_city, 0)) - size,
		0
	)
	if assigned_armies.has(target_city):
		(assigned_armies[target_city] as Array[int]).erase(army_id)
	if _city_defense_target_by_army.has(army_id):
		var defense_city := int(
			_city_defense_target_by_army[army_id]
		)
		city_defense_power[defense_city] = maxf(
			float(city_defense_power.get(defense_city, 0.0))
				- power,
			0.0
		)
		if city_defense_armies.has(defense_city):
			(
				city_defense_armies[defense_city]
				as Array[int]
			).erase(army_id)
	if _edge_key_by_army.has(army_id):
		var edge_key := str(_edge_key_by_army[army_id])
		edge_defense_power[edge_key] = maxf(
			float(edge_defense_power.get(edge_key, 0.0))
				- power,
			0.0
		)
		if edge_defense_armies.has(edge_key):
			(
				edge_defense_armies[edge_key]
				as Array[int]
			).erase(army_id)
	_reserved_target_by_army.erase(army_id)
	_reserved_power_by_army.erase(army_id)
	_reserved_size_by_army.erase(army_id)
	_city_defense_target_by_army.erase(army_id)
	_edge_key_by_army.erase(army_id)


static func _edge_defense_key(
	friendly_city: int,
	other_city: int
) -> String:
	return "%d:%d" % [friendly_city, other_city]


static func merge_colocated(state: GameState) -> int:
	var groups := {}
	for army in state.armies:
		if army.size <= 0 or army.battle_id != -1:
			continue
		var key := _merge_key(army)
		if key.is_empty():
			continue
		if not groups.has(key):
			groups[key] = [] as Array[Army]
		(groups[key] as Array[Army]).append(army)
	var removed := {}
	var merged_count := 0
	var keys := groups.keys()
	keys.sort()
	for key in keys:
		var group: Array[Army] = groups[key]
		if group.size() < 2:
			continue
		group.sort_custom(func(a: Army, b: Army) -> bool:
			if a.size != b.size:
				return a.size > b.size
			return EquivariantOrder.army_less(
				state,
				a.owner_nation,
				a,
				b
			)
		)
		var survivor := group[0]
		for i in range(1, group.size()):
			var other := group[i]
			var old_other_size := other.size
			_merge_into(state, survivor, other)
			if other.size < old_other_size:
				merged_count += 1
			if other.size <= 0:
				removed[other.id] = true
			if survivor.size >= survivor.max_size:
				break
	if not removed.is_empty():
		state.armies = state.armies.filter(
			func(army: Army) -> bool: return not removed.has(army.id)
		)
	return merged_count


static func _merge_key(army: Army) -> String:
	var bonus_key := "B:%d:%d" % [
		int(round(army.offensive_attack_multiplier * 1000.0)),
		army.offensive_bonus_until_day,
	]
	var role_key := "R:%d:G:%d:L:%d:%d:%d" % [
		army.strategic_role,
		army.battle_group_id,
		army.line_assignment_city,
		army.line_assignment_posture,
		army.line_assignment_edge,
	]
	if army.state in [Army.State.IDLE, Army.State.RECOVERING]:
		return "%d:C:%d:S:%d:%s:%s" % [
			army.owner_nation,
			army.location_city,
			army.state,
			role_key,
			bonus_key,
		]
	if army.state == Army.State.HOLDING and army.on_edge and army.move_to != -1:
		var lo := mini(army.move_from, army.move_to)
		var hi := maxi(army.move_from, army.move_to)
		var norm := army.move_progress if army.move_from == lo else 1.0 - army.move_progress
		return "%d:E:%d:%d:P:%d:%s:%s" % [
			army.owner_nation,
			lo,
			hi,
			int(round(norm * 10000.0)),
			role_key,
			bonus_key,
		]
	return ""


static func _merge_into(state: GameState, survivor: Army, other: Army) -> void:
	var size_a := maxi(survivor.size, 0)
	var other_size_before := maxi(other.size, 0)
	var size_b := mini(
		other_size_before,
		maxi(survivor.max_size - size_a, 0)
	)
	var total := size_a + size_b
	if size_b <= 0 or total <= 0:
		return
	survivor.attack = int(round(
		(float(survivor.attack * size_a) + float(other.attack * size_b)) / float(total)
	))
	survivor.defense = int(round(
		(float(survivor.defense * size_a) + float(other.defense * size_b)) / float(total)
	))
	survivor.speed_factor = (
		survivor.speed_factor * float(size_a) + other.speed_factor * float(size_b)
	) / float(total)
	survivor.morale = (
		survivor.morale * float(size_a) + other.morale * float(size_b)
	) / float(total)
	survivor.supply_ratio = (
		survivor.supply_ratio * float(size_a) + other.supply_ratio * float(size_b)
	) / float(total)
	survivor.holding_days = int(round(
		(float(survivor.holding_days * size_a) + float(other.holding_days * size_b))
		/ float(total)
	))
	survivor.starving = survivor.starving or other.starving
	var transferred_ratio := (
		float(size_b) / float(maxi(other_size_before, 1))
	)
	var transferred_supply_debt := (
		other.supply_debt * transferred_ratio
	)
	var transferred_food_debt := (
		other.supply_food_debt * transferred_ratio
	)
	survivor.supply_debt += transferred_supply_debt
	survivor.supply_food_debt += transferred_food_debt
	other.supply_debt -= transferred_supply_debt
	other.supply_food_debt -= transferred_food_debt
	survivor.size = total
	other.size -= size_b
	if other.size <= 0 and other.on_edge:
		var edge := state.edge_of(other.move_from, other.move_to)
		if edge != null and edge.passing_count > 0:
			edge.passing_count -= 1
			edge.occupied = edge.passing_count > 0
		other.on_edge = false
	if other.size <= 0:
		other.size = 0
