extends Simulation
## Current pre-v9 fiscal probe, oracle only.

func _trade_structure_runtime_probe() -> Array:
	var result: Array = [
		state.get_instance_id(),
		state.cities.size(),
		state.nations.size(),
		state.edges.size(),
		state.ownership_revision,
		state.road_network_revision,
	]
	if not state.atlas_layout.is_empty(): result.append_array([state.day / DAYS_PER_MONTH,state.family_revision,state.diplomacy_revision])
	for city in state.cities:
		if city_war_disrupted(state, city):
			result.append([city.id, city.war_disruption_until_day])
	for nation in state.nations:
		result.append_array([
			nation.id, nation.alive, nation.capital_city_id,
			nation.trade_policy, nation.ruler_revision,
		])
	return result
