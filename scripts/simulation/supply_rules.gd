class_name SupplyRules
extends RefCounted
## Deterministic supply calculations. Simulation owns scheduling and caches;
## this module owns fingerprints, weighting, and warehouse withdrawals.


static func morale_recovery_payment_multiplier(payment_ratio: float) -> float:
	return 0.5 + 0.5 * clampf(payment_ratio, 0.0, 1.0)


static func sources_have_food(
	state: GameState,
	sources: Array[Dictionary]
) -> bool:
	for source in sources:
		var city_id := int(source["city_id"])
		if (
			city_id >= 0
			and city_id < state.cities.size()
			and state.cities[city_id].food_storage > 0
		):
			return true
	return false


static func network_fingerprint(
	state: GameState,
	nation_id: int,
	warehouse_state: Dictionary,
	enemy_edges: Dictionary,
	besieged: Dictionary
) -> Array[int]:
	var result: Array[int] = [
		state.ownership_revision,
		state.diplomacy_revision,
	]
	for owner in state.nations:
		if not state.has_military_access(nation_id, owner.id):
			continue
		result.append(-1)
		result.append(owner.id)
		result.append_array(
			warehouse_state.get(owner.id, [] as Array[int]) as Array[int]
		)
		if not owner.warehouse_city_ids.is_empty():
			result.append(-3)
			for capital_id in state.food_pool_relay_capitals(owner.id):
				result.append(capital_id)
				result.append(1 if besieged.has(capital_id) else 0)
	result.append(-2)
	var enemy_keys := enemy_edges.keys()
	enemy_keys.sort()
	for edge_key_value in enemy_keys:
		result.append(int(edge_key_value))
	return result


static func warehouse_availability(
	state: GameState,
	besieged: Dictionary
) -> Dictionary:
	var result := {}
	for owner in state.nations:
		var usable: Array[int] = []
		for warehouse in state.warehouse_cities_of(owner.id):
			if warehouse.food_storage > 0 and not besieged.has(warehouse.id):
				usable.append(warehouse.id)
		usable.sort()
		result[owner.id] = usable
	return result


static func position_key(army: Army) -> String:
	return (
		"E:%d:%d:%d"
		% [
			army.move_from,
			army.move_to,
			int(round(army.move_progress * 10000.0)),
		]
		if army.on_edge and army.move_to != -1
		else "C:%d" % army.location_city
	)


static func weighted_loss(
	state: GameState,
	sources: Array[Dictionary]
) -> float:
	if sources.is_empty():
		return INF
	var total_weight := 0.0
	var weighted_route_loss := 0.0
	for source in sources:
		var city_id := int(source["city_id"])
		if city_id < 0 or city_id >= state.cities.size():
			continue
		var stock := state.cities[city_id].food_storage
		if stock <= 0:
			continue
		var route_loss := float(source["loss"])
		var weight := source_weight(stock, route_loss)
		total_weight += weight
		weighted_route_loss += route_loss * weight
	return weighted_route_loss / maxf(total_weight, 0.001)


static func withdraw_weighted(
	state: GameState,
	sources: Array[Dictionary],
	demand: int,
	order_nation: int
) -> int:
	var remaining := maxi(demand, 0)
	var supplied := 0
	while remaining > 0:
		var weighted: Array[Dictionary] = []
		var total_weight := 0.0
		for source in sources:
			var city_id := int(source["city_id"])
			if city_id < 0 or city_id >= state.cities.size():
				continue
			var city := state.cities[city_id]
			if city.food_storage <= 0:
				continue
			var weight := source_weight(
				city.food_storage, float(source["loss"])
			)
			total_weight += weight
			weighted.append({
				"city": city,
				"weight": weight,
				"city_id": city_id,
			})
		if weighted.is_empty() or total_weight <= 0.0:
			break
		var distributed := 0
		var remainders: Array[Dictionary] = []
		for entry in weighted:
			var exact := float(remaining) * float(entry["weight"]) / total_weight
			var share := int(floor(exact))
			if share > 0:
				var actual_delta := state.change_city_food_storage(
					int(entry["city_id"]), -share
				)
				var removed := -actual_delta
				distributed += removed
			remainders.append({
				"city": entry["city"],
				"city_id": entry["city_id"],
				"fraction": exact - floor(exact),
			})
		remaining -= distributed
		supplied += distributed
		if remaining <= 0:
			break
		remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(
				float(a["fraction"]), float(b["fraction"])
			):
				return float(a["fraction"]) > float(b["fraction"])
			return EquivariantOrder.city_id_less(
				state,
				order_nation,
				int(a["city_id"]),
				int(b["city_id"])
			)
		)
		var residual_distributed := 0
		for entry in remainders:
			if remaining <= 0:
				break
			var city: City = entry["city"]
			if city.food_storage <= 0:
				continue
			var actual_delta := state.change_city_food_storage(city.id, -1)
			var removed := -actual_delta
			if removed > 0:
				remaining -= removed
				supplied += removed
				residual_distributed += removed
		if distributed == 0 and residual_distributed == 0:
			break
	return supplied


static func source_weight(stock: int, route_loss: float) -> float:
	return float(maxi(stock, 0)) / sqrt(maxf(1.0 + route_loss, 0.001))
