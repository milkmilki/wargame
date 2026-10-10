extends SceneTree
func _initialize() -> void:
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(12345)
	# Isolate Atlas cache policy from the geometric graph adapter.
	state.atlas_layout = {"model":"atlas-military-v1"}
	var cache := {}; var expected := Pathfinding.dijkstra_field(state,0)
	for day in range(120):
		state.day = day
		AiWorldView.cached_path_field(state,day,cache,0,-1,true,false)
	assert(cache.size()<=33,"Atlas does not retain every obsolete daily path field")
	for city in state.cities: AiWorldView.cached_path_field(state,state.day,cache,city.id)
	assert(cache.size()<=33,"Atlas path fields have a bounded live working set")
	var actual := AiWorldView.cached_path_field(state,state.day,cache,0)
	assert(actual==expected,"eviction does not change path results")
	state.day += 1
	var next_day := AiWorldView.cached_path_field(state,state.day,cache,0)
	assert(is_same(actual,next_day),"static path fields survive a day without road or diplomacy changes")
	for start in range(1,mini(40,state.cities.size())):
		AiWorldView.cached_path_field(state,state.day,cache,start)
		assert(is_same(actual,AiWorldView.cached_path_field(state,state.day,cache,0)),"hot fields survive bounded LRU eviction")
	var previous_revision := actual
	state.road_network_revision += 1
	actual = AiWorldView.cached_path_field(state,state.day,cache,0)
	assert(not is_same(previous_revision,actual) and actual==expected,"road edits invalidate fields without changing unchanged routes")
	var contested := AiWorldView.cached_path_field(state,state.day,cache,0,-1,true,false)
	state.day += 1
	assert(not is_same(contested,AiWorldView.cached_path_field(state,state.day,cache,0,-1,true,false)),"contested path fields still refresh daily")
	print("ATLAS_PATH_CACHE_LIFECYCLE PASS entries=",cache.size()); quit(0)
