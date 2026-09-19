extends SceneTree


func _init() -> void:
	var state := GameState.new()
	state.generate_grid_world(88201)
	var owners: Array[int] = []
	var legal: Array[int] = []
	var sponsors: Array[int] = []
	owners.resize(state.cities.size())
	legal.resize(state.cities.size())
	sponsors.resize(state.cities.size())
	for city in state.cities:
		owners[city.id] = 1
		legal[city.id] = 1
		sponsors[city.id] = -1
	# Cities 0 and 1 are adjacent core territory; city 63 is a detached
	# land pocket surrounded by nation 1.
	owners[0] = 0
	legal[0] = 0
	owners[1] = 0
	legal[1] = 0
	owners[63] = 0
	legal[63] = 0
	var draft := {
		"owners": owners,
		"legal": legal,
		"sponsors": sponsors,
		"operation_by_city": {},
	}
	var sim := Simulation.new()
	sim.setup(state)
	var moved := sim._plan_coalition_enclave_transfers(draft)
	var valid := (
		moved == 1
		and int((draft["owners"] as Array)[63]) == 1
		and int((draft["legal"] as Array)[63]) == 1
	)
	sim.free()
	if valid:
		print("PEACE_ENCLAVE_OK moved=%d" % moved)
		quit(0)
		return
	push_error("PEACE_ENCLAVE_FAILED moved=%d" % moved)
	quit(1)
