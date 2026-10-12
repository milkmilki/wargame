extends SceneTree
const Eager = preload("res://tests/support/eager_threat_reference.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("THREAT_SHARED_FAIL ", label)

func view_for(state: GameState, observer: int) -> AiWorldView:
	var view := AiWorldView.new()
	view.state = state
	view.day = state.day
	view.nation_id = observer
	for army in state.armies:
		if army.owner_nation == observer: view.friendly_armies.append(army)
		else: view.enemy_armies.append(army)
	return view

func build_worker(job: Dictionary) -> void:
	# Compare the independent eager algorithm with the runtime worker's
	# prepared travel inputs, keeping cache state and execution context equal.
	job.expected = Eager.build(job.view, job.cache, {}, true)
	job.field = ThreatField.build(job.view, job.cache, {}, true, job.inputs)

func compare_field(actual: ThreatField, expected: RefCounted, label: String) -> void:
	for id in range(64):
		check(var_to_bytes(actual.threat_at(id)) == var_to_bytes(expected.threat_at(id)), label + ": threat")
		check(var_to_bytes(actual.support_at(id)) == var_to_bytes(expected.support_at(id)), label + ": support")
	check(var_to_bytes(actual.threat_by_city) == var_to_bytes(expected.threat_by_city), label + ": threat order")
	check(var_to_bytes(actual.support_by_city) == var_to_bytes(expected.support_by_city), label + ": support order")

func run() -> void:
	for seed_value in [1, 7, 2024]:
		var state := preload("res://tests/support/grid_world.gd").new()
		state.generate_world(seed_value, 4, 64)
		for index in range(state.armies.size()):
			var army := state.armies[index]
			army.size = 1000 + index * 137
			army.supply_ratio = .2 + .2 * (index % 4)
			if index % 2 == 0:
				army.on_edge = true
				army.move_from = army.location_city
				army.move_to = state.neighbors(army.location_city)[0]
				army.move_progress = .31
		var sim := Simulation.new()
		sim.state = state
		var subset := AiWorldView.new()
		subset.friendly_armies = [state.armies[0], state.armies[1]] as Array[Army]
		subset.enemy_armies = [state.armies[0]] as Array[Army]
		var second_id := state.armies[1].id
		state.armies[1].id = state.armies[0].id
		var selected := sim._ai_threat_travel_requests([{"view": subset}])
		var expected_starts := {
			state.armies[0].move_from: true, state.armies[0].move_to: true,
			state.armies[1].location_city: true,
		}
		check(selected.size() == expected_starts.size(), "requests deduplicate objects and preserve distinct objects with duplicate logical IDs")
		for request in selected:
			check(expected_starts.has(request.x) and request.y == 0, "requests include each visible source endpoint")
		check(selected.size() < sim._ai_threat_travel_requests().size(), "prepared jobs omit unrelated army sources while default queries retain them")
		state.armies[1].id = second_id
		sim.free()
		var cache := {}
		var requests: Array[Vector2i] = []
		for start in range(64):
			requests.append(Vector2i(start, 0))
			ThreatField.build_shared_travel_request(state, start, 0, cache)
		var before_rng := state.rng.state
		var before_cache := var_to_bytes(cache)
		var inputs := ThreatField.freeze_shared_inputs(state, cache, requests)
		check(state.rng.state == before_rng, "snapshot does not consume RNG")
		check(var_to_bytes(cache) == before_cache and not cache.is_read_only(), "snapshot leaves caller cache mutable and unchanged")
		check(inputs.is_read_only() and inputs.city_ids.is_read_only() and inputs.influences.is_read_only(), "shared inputs are read only")
		for value in inputs.influences.values():
			check(value.is_read_only(), "each shared influence is read only")
		var jobs: Array[Dictionary] = []
		var expected: Array[RefCounted] = []
		for observer in range(4):
			var view := view_for(state, observer)
			jobs.append({"view": view, "cache": cache, "inputs": inputs, "field": null})
			expected.append(Eager.build(view))
		var task_ids: Array[int] = []
		for job in jobs: task_ids.append(WorkerThreadPool.add_task(build_worker.bind(job)))
		for task_id in task_ids: WorkerThreadPool.wait_for_task_completion(task_id)
		for index in range(jobs.size()):
			var field: ThreatField = jobs[index].field
			check(is_same(field._frozen_city_ids, inputs.city_ids), "fields reuse one ordered city snapshot")
			compare_field(field, jobs[index].expected, "parallel")
		var serial := ThreatField.build(jobs[0].view, cache, {}, false, inputs)
		compare_field(serial, expected[0], "serial")
		# Changing caller-owned data must not change either old point queries or
		# deferred full materialization, including the captured city key order.
		var deferred := ThreatField.build(jobs[0].view, cache, {}, true, inputs)
		for value in cache.values(): value.clear()
		cache.clear()
		for army in state.armies: army.size = 0
		for edge in state.edges: edge.max_manpower = 0
		state.cities[0].id = (1 << 40) + 1
		compare_field(deferred, expected[0], "frozen after caller edits")
		var next_inputs := ThreatField.freeze_shared_inputs(state, cache, [] as Array[Vector2i])
		check(next_inputs.city_ids[0] == (1 << 40) + 1 and inputs.city_ids[0] == 0, "next phase captures live 64 bit city IDs independently")
		var next_field := ThreatField.build(jobs[0].view, cache, {}, true, next_inputs)
		var next_expected = Eager.build(jobs[0].view)
		check(var_to_bytes(next_field.threat_by_city) == var_to_bytes(next_expected.threat_by_city), "new phase sees changed cities and sources")
		var other: ThreatField = jobs[1].field
		var other_before := var_to_bytes(other.threat_by_city)
		(jobs[0].field as ThreatField).threat_by_city[0] = 123.0
		check(var_to_bytes(other.threat_by_city) == other_before, "public field dictionaries remain independent and mutable")
	print("THREAT_SHARED_INPUTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
