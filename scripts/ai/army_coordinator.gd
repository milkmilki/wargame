class_name ArmyCoordinator
extends RefCounted
## 国家级军队协调：同位置合并与目标兵力预留。

var assigned_power: Dictionary = {}    ## target_city -> float
var assigned_size: Dictionary = {}     ## target_city -> 原始兵力
var assigned_armies: Dictionary = {}   ## target_city -> Array[int]
var city_defense_power: Dictionary = {} ## target_city -> 确定进入城市的防御战力


func reserve(
	target_city: int,
	army: Army,
	counts_as_city_defense: bool = true
) -> void:
	if target_city < 0:
		return
	var power := ArmyPower.effective(army)
	assigned_power[target_city] = float(
		assigned_power.get(target_city, 0.0)
	) + power
	assigned_size[target_city] = int(assigned_size.get(target_city, 0)) + army.size
	if not assigned_armies.has(target_city):
		assigned_armies[target_city] = [] as Array[int]
	(assigned_armies[target_city] as Array[int]).append(army.id)
	if counts_as_city_defense:
		city_defense_power[target_city] = float(
			city_defense_power.get(target_city, 0.0)
		) + power


func power_reserved(target_city: int) -> float:
	return float(assigned_power.get(target_city, 0.0))


func size_reserved(target_city: int) -> int:
	return int(assigned_size.get(target_city, 0))


func city_defense_power_reserved(target_city: int) -> float:
	return float(city_defense_power.get(target_city, 0.0))


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
		group.sort_custom(func(a: Army, b: Army) -> bool: return a.id < b.id)
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
	if army.state in [Army.State.IDLE, Army.State.RECOVERING]:
		return "%d:C:%d:S:%d" % [army.owner_nation, army.location_city, army.state]
	if army.state == Army.State.HOLDING and army.on_edge and army.move_to != -1:
		var lo := mini(army.move_from, army.move_to)
		var hi := maxi(army.move_from, army.move_to)
		var norm := army.move_progress if army.move_from == lo else 1.0 - army.move_progress
		return "%d:E:%d:%d:P:%d" % [
			army.owner_nation, lo, hi, int(round(norm * 10000.0))
		]
	return ""


static func _merge_into(state: GameState, survivor: Army, other: Army) -> void:
	var size_a := maxi(survivor.size, 0)
	var size_b := mini(maxi(other.size, 0), maxi(survivor.max_size - size_a, 0))
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
