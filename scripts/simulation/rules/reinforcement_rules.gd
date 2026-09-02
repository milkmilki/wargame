class_name ReinforcementRules
extends RefCounted
## Pure reinforcement policy shared by synchronous and frame-sliced simulation.

const REINFORCE_PER_ARMY_PER_MONTH: int = 750
const PEACETIME_MANPOWER_RESERVE: int = 5000
const PEACETIME_STRENGTH_RATIO: float = 0.30
const WARTIME_MANPOWER_RESERVE: int = 3000


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
			REINFORCE_PER_ARMY_PER_MONTH
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
	if army.state not in [
		Army.State.IDLE,
		Army.State.MOVING,
		Army.State.RECOVERING,
		Army.State.HOLDING,
	]:
		return false
	if network_cache_disabled or manpower_hub_network.is_empty():
		return Pathfinding.can_reach_manpower_hub(state, army)
	return Pathfinding.can_reach_manpower_hub_from_network(
		state,
		army,
		manpower_hub_network
	)
