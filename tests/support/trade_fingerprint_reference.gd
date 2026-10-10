extends RefCounted
## Independent pre-packing fingerprint, including the optional annual-route adapter.
static func fingerprint(state: GameState) -> PackedByteArray:
	if state == null:
		return var_to_bytes(["trade_structure_v5", null])
	if not state.trade_enabled:
		return var_to_bytes(["trade_disabled_v1",state.cities.size(),state.nations.size()])
	var fields: Array = [
		"trade_structure_v5",
		["counts", state.cities.size(), state.nations.size()],
		["map_aspect_ratio", state.map_aspect_ratio],
	]
	var gateway := TradeNetwork.new()
	if not state.atlas_layout.is_empty() and gateway.has_method("_prepare_atlas_trade_cache"):
		gateway.call("_prepare_atlas_trade_cache",state)
		var atlas: Dictionary = state.get("atlas_trade_cache")
		fields.append(["atlas_annual_routes_v1",atlas.centers,atlas.geometry_key])
		fields.append(["financial_owners",state.nations.map(func(n): return state.financial_nation_of(n.id))])
	var non_trade_gold_outputs := CityOutputRules.city_potential_gold_outputs(state)
	for city in state.cities:
		var region_id := (
			int(state.region_ids[city.id])
			if city.id >= 0 and city.id < state.region_ids.size()
			else -1
		)
		var non_trade_gold_output := (
			int(non_trade_gold_outputs[city.id])
			if city.id >= 0 and city.id < non_trade_gold_outputs.size()
			else CityOutputRules.city_potential_gold_output(state, city)
		)
		fields.append([
			"city", city.id, city.owner_nation, city.is_dock, city.node_kind,
			city.map_position, city.gold_per_month, city.food_per_half_year,
			non_trade_gold_output,
			city.is_capital, city.has_warehouse, city.is_port_market,
			city.is_crossroads, city.is_food_hub, region_id,
			int(city.get_meta("initial_owner_city", -1)),
		])
	for nation in state.nations:
		fields.append([
			"nation", nation.id, nation.alive, nation.capital_city_id,
			TradeNetwork._policy_of(nation), TradeNetwork._ruler_trade_multiplier(nation),
		])

	# edges 的数组顺序也保留：重复端点时 _build_graph() 采用第一条边。
	for edge in state.edges:
		fields.append([
			"edge", edge.city_a, edge.city_b, edge.kind,
			edge.max_manpower, edge.base_max_manpower, edge.distance, edge.precise_distance, edge.control_city_id,
			edge.travel_time_multiplier, edge.danger,
			edge.supply_loss_multiplier,
		])
	return var_to_bytes(fields)
