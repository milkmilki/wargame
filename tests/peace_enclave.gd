extends SceneTree


func _init() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
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
	# Retain complete administrative states at opposite corners. A legal
	# enclave may transfer only when its seat and all fu belong to that owner.
	var core_members: Array[int] = []
	# Multiple adjacent northern states make the retained mainland larger
	# than the southern enclave; equal/smaller components use deterministic size order.
	for northern_city in range(8):
		for member in state.administrative_members(state.administrative_center_of(northern_city)):
			if not core_members.has(member):
				core_members.append(member)
	var enclave_members := state.administrative_members(state.administrative_center_of(63))
	for city_id in core_members + enclave_members:
		owners[city_id] = 0
		legal[city_id] = 0
	var draft := {
		"owners": owners,
		"legal": legal,
		"sponsors": sponsors,
		"operation_by_city": {},
	}
	var sim := Simulation.new()
	sim.setup(state)
	# The old single-fu fixture must remain unchanged: ceding city 63 alone
	# would split its state further rather than clean up a complete enclave.
	var partial_owners := owners.duplicate()
	var partial_legal := legal.duplicate()
	for city_id in enclave_members:
		if city_id != 63:
			partial_owners[city_id] = 1
			partial_legal[city_id] = 1
	var partial_draft := {
		"owners": partial_owners, "legal": partial_legal,
		"sponsors": sponsors.duplicate(), "operation_by_city": {},
	}
	var partial_before := partial_draft.duplicate(true)
	var partial_moved := sim._plan_coalition_enclave_transfers(
		partial_draft, [0, 1] as Array[int]
	)
	var excluded_draft := {
		"owners": owners.duplicate(),
		"legal": legal.duplicate(),
		"sponsors": sponsors.duplicate(),
		"operation_by_city": {},
	}
	var excluded_moved := sim._plan_coalition_enclave_transfers(
		excluded_draft, [1] as Array[int]
	)
	var moved := sim._plan_coalition_enclave_transfers(
		draft, [0, 1] as Array[int]
	)
	var valid := (
		excluded_moved == 0
		and int((excluded_draft["owners"] as Array)[63]) == 0
		and partial_moved == 0
		and partial_draft == partial_before
		and moved == enclave_members.size()
		and not core_members.has(63)
	)
	for city_id in enclave_members:
		valid = (valid and int(draft.owners[city_id]) == 1
			and int(draft.legal[city_id]) == 1 and int(draft.sponsors[city_id]) == -1)
	for city_id in core_members:
		valid = valid and int(draft.owners[city_id]) == 0 and int(draft.legal[city_id]) == 0
	sim.free()
	if valid:
		print("PEACE_ENCLAVE_OK moved=%d" % moved)
		quit(0)
		return
	push_error(
		"PEACE_ENCLAVE_FAILED excluded=%d partial=%d moved=%d expected=%d"
		% [excluded_moved, partial_moved, moved, enclave_members.size()]
	)
	quit(1)
