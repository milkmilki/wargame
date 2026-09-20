extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(97531)
	var fixture := _find_foreign_border(state)
	if fixture.is_empty():
		push_error("ALLIED_FRONTIER_RELEASE_FAIL: no foreign border")
		quit(1)
		return
	var nation_id := int(fixture["nation_id"])
	var ally_id := int(fixture["neighbor_nation_id"])
	var border_city_id := int(fixture["city_id"])
	var border_edge: Edge = fixture["edge"]
	var enemy_id := _third_nation_id(state, nation_id, ally_id)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(
		nation_id, enemy_id, GameState.DiplomaticRelation.WAR
	)
	var before_view := AiWorldView.build(state, nation_id)
	var before_snapshot := StrategicMapSnapshot.build(before_view)
	before_snapshot.potential_frontier_cities = [
		border_city_id
	] as Array[int]
	before_snapshot.potential_frontier_edges = [
		border_edge
	] as Array[Edge]
	var topology := FrontierDefenseTopology.build(
		before_view, before_snapshot
	)
	state.set_diplomatic_relation(
		nation_id, ally_id, GameState.DiplomaticRelation.ALLIED
	)
	var after_view := AiWorldView.build(state, nation_id)
	var after_snapshot := StrategicMapSnapshot.build(after_view)
	var valid := (
		state.is_enemy(nation_id, enemy_id)
		and state.has_military_access(nation_id, ally_id)
		and not topology.matches(after_view, after_snapshot)
	)
	if valid:
		print("ALLIED_FRONTIER_RELEASE_OK")
		quit(0)
		return
	push_error(
		"ALLIED_FRONTIER_RELEASE_FAIL access=%s matches=%s"
		% [
			str(state.has_military_access(nation_id, ally_id)),
			str(topology.matches(after_view, after_snapshot)),
		]
	)
	quit(1)


func _find_foreign_border(state: GameState) -> Dictionary:
	for edge in state.edges:
		if edge.max_manpower <= 0:
			continue
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a >= 0 and owner_b >= 0 and owner_a != owner_b:
			return {
				"nation_id": owner_a,
				"neighbor_nation_id": owner_b,
				"city_id": edge.city_a,
				"edge": edge,
			}
	return {}


func _third_nation_id(
	state: GameState,
	nation_id: int,
	ally_id: int
) -> int:
	for nation in state.nations:
		if nation.id != nation_id and nation.id != ally_id:
			return nation.id
	return -1
