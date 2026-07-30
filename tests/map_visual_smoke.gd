extends SceneTree
## 地图视觉烟测：构造占领省份与攻势事件，供 Movie Maker/截图回归使用。


func _init() -> void:
	root.size = Vector2i(1280, 720)
	var state := GameState.new()
	state.generate_world(12345)
	state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)

	var occupied_city := state.cities[0]
	occupied_city.owner_nation = (occupied_city.owner_nation + 1) % state.nations.size()
	state.ownership_revision += 1

	var target_city := -1
	var origin_cities: Array[int] = []
	for edge in state.edges:
		if (
			state.cities[edge.city_a].owner_nation
			!= state.cities[edge.city_b].owner_nation
		):
			origin_cities = [edge.city_a]
			target_city = edge.city_b
			break
	if target_city >= 0:
		state.add_campaign_visual_event(
			state.cities[origin_cities[0]].owner_nation,
			target_city,
			origin_cities,
			1,
			Simulation.CAMPAIGN_ARROW_DURATION_DAYS
		)
