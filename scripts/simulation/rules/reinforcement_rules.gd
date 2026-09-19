class_name ReinforcementRules
extends RefCounted
## Pure reinforcement policy shared by synchronous and frame-sliced simulation.

## Replenishment is deliberately slow: a full 15000-person army can recover
## at most ten percent of its establishment each month.
const REINFORCE_PER_ARMY_PER_MONTH: int = 1500
const PEACETIME_MANPOWER_RESERVE: int = 5000
const PEACETIME_STRENGTH_RATIO: float = 0.30
const WARTIME_MANPOWER_RESERVE: int = 3000


static func monthly_reinforcement_cap(army: Army) -> int:
	return maxi(int(ceil(float(army.max_size) * 0.10)), 1)


static func bucket_armies_by_nation(state: GameState) -> Dictionary:
	var armies_by_nation := {}
	for army in state.armies:
		if not armies_by_nation.has(army.owner_nation):
			armies_by_nation[army.owner_nation] = [] as Array[Army]
		(armies_by_nation[army.owner_nation] as Array[Army]).append(army)
	return armies_by_nation


static func reinforcement_priority(state: GameState, army: Army) -> int:
	if army.state == Army.State.HOLDING:
		return 3
	var city_id := army.location_city
	if city_id < 0 and army.move_to >= 0:
		city_id = army.move_to
	if city_id < 0 or city_id >= state.cities.size():
		return 0
	var city := state.cities[city_id]
	if (
		city.id == state.nations[army.owner_nation].capital_city_id
		or city.has_warehouse
	):
		return 4
	if city.is_food_hub or city.is_manpower_hub or city.at_war:
		return 3
	return 1


static func wartime_manpower_reserve(armies: Array[Army]) -> int:
	var monthly_refill_need := 0
	for army in armies:
		if army.size <= 0 or army.size >= army.max_size:
			continue
		monthly_refill_need += mini(
			army.max_size - army.size,
			monthly_reinforcement_cap(army)
		)
	return maxi(WARTIME_MANPOWER_RESERVE, monthly_refill_need)


static func can_reinforce_army(
	state: GameState,
	army: Army,
	network_cache_disabled: bool,
	manpower_hub_network: Dictionary = {}
) -> bool:
	if army.size <= 0 or army.size >= army.max_size:
		return false
	if army.state in [Army.State.FIGHTING, Army.State.RETREATING]:
		return false
	if army.state not in [Army.State.IDLE, Army.State.RECOVERING]:
		return false
	# Recovery is only meaningful while the formation is safely settled in a
	# city.  A marching army must first reach a friendly garrison.
	if army.on_edge:
		return false
	var city_id := army.location_city
	if city_id < 0 or city_id >= state.cities.size():
		return false
	var city := state.cities[city_id]
	if city.is_dock and not state.has_military_access(army.owner_nation, city.owner_nation):
		return false
	if not state.has_military_access(army.owner_nation, city.owner_nation):
		return false
	return true
