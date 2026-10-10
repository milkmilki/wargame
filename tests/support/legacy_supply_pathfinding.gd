# Exact source selection before the second daily optimization; test oracle only.
extends Pathfinding

static func supply_sources_from_network(
	state: GameState,
	army: Army,
	network: Array[Dictionary]
) -> Array[Dictionary]:
	var start := _origin_of(army)
	if start < 0 or start >= state.cities.size():
		return []
	var start_city := state.cities[start]
	if (
		not army.on_edge
		and state.city_under_siege(start) and not state.succession_supply_city(start)
		and state.has_logistics_access(
			army.owner_nation,
			start_city.owner_nation
		)
	):
		if (
			start_city.has_warehouse
			and start_city.food_storage > 0
			and state.nations[
				start_city.owner_nation
			].warehouse_city_ids.has(start)
		):
			return [{
				"city_id": start,
				"owner_nation": start_city.owner_nation,
				"loss": 0.0,
			}]
		return []
	var edge: Edge = null
	var edge_loss := 0.0
	var progress := 0.0
	if army.on_edge and army.move_to != -1:
		edge = state.edge_of(army.move_from, army.move_to)
		if edge == null:
			return []
		edge_loss = _supply_edge_loss(edge)
		progress = clampf(army.move_progress, 0.0, 1.0)
	var result: Array[Dictionary] = []
	for source in network:
		var dist: PackedFloat64Array = source["dist"]
		var loss := INF
		if edge == null:
			loss = dist[start]
		else:
			if state.has_logistics_access(
				army.owner_nation,
				state.cities[army.move_from].owner_nation
			):
				loss = minf(
					loss,
					progress * edge_loss
						+ dist[army.move_from]
				)
			if state.has_logistics_access(
				army.owner_nation,
				state.cities[army.move_to].owner_nation
			):
				loss = minf(
					loss,
					(1.0 - progress) * edge_loss
						+ dist[army.move_to]
				)
		if loss == INF:
			continue
		result.append({
			"city_id": source["city_id"],
			"owner_nation": source["owner_nation"],
			"loss": loss,
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(
			float(a["loss"]),
			float(b["loss"])
		):
			return float(a["loss"]) < float(b["loss"])
		return EquivariantOrder.city_id_less(
			state,
			army.owner_nation,
			int(a["city_id"]),
			int(b["city_id"]),
			start
		)
	)
	return result

