extends SceneTree
## Runtime road tuning contract: deterministic capacities, preserved river
## transport, connected backbone, and active-road protection.


func _init() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("ROAD_NETWORK_RUNTIME_FAILED: " + message)
	quit(1)


func _run() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	var preserved_transport := {}
	for edge in state.edges:
		if edge.kind != Edge.Kind.LAND:
			preserved_transport[
				GameState.edge_key(edge.city_a, edge.city_b)
			] = [
				edge.kind,
				edge.max_manpower,
				edge.distance,
			]
	var settings := {
		"minimum_land_ratio": 0.94,
		"maximum_relief": 0.42,
		"blocked_branch_share": 0.22,
		"terrain_capacity_penalty": 0.58,
		"capacity_multiplier": 1.35,
	}
	var first := state.recalculate_road_network(settings)
	if not bool(first.get("ok", false)):
		_fail(str(first.get("error", "first rebuild failed")))
		return
	if int(first["blocked_count"]) <= 0:
		_fail("aggressive tuning must close at least one branch")
		return
	for edge in state.edges:
		if edge.is_backbone and edge.max_manpower <= 0:
			_fail("backbone edge became impassable")
			return
		if edge.kind == Edge.Kind.LAND:
			continue
		var key := GameState.edge_key(edge.city_a, edge.city_b)
		if not preserved_transport.has(key):
			_fail("river/landing edge identity changed")
			return
		if preserved_transport[key] != [
			edge.kind,
			edge.max_manpower,
			edge.distance,
		]:
			_fail("river/landing edge attributes changed")
			return
	var capacities := PackedInt32Array()
	for edge in state.edges:
		capacities.append(edge.max_manpower)
	var second := state.recalculate_road_network(settings)
	if not bool(second.get("ok", false)):
		_fail("second rebuild failed")
		return
	var second_capacities := PackedInt32Array()
	for edge in state.edges:
		second_capacities.append(edge.max_manpower)
	if capacities != second_capacities:
		_fail("same settings must produce identical capacities")
		return
	var protected_edge: Edge = null
	for edge in state.edges:
		if (
			edge.kind == Edge.Kind.LAND
			and not edge.is_backbone
			and edge.max_manpower > 0
		):
			protected_edge = edge
			break
	if protected_edge == null:
		_fail("no land edge available for active-road protection")
		return
	var army := state.armies[0]
	army.move_from = protected_edge.city_a
	army.move_to = protected_edge.city_b
	army.on_edge = true
	var protected_capacity := protected_edge.max_manpower
	var protected_result := state.recalculate_road_network({
		"minimum_land_ratio": 1.0,
		"maximum_relief": 0.05,
		"blocked_branch_share": 0.45,
		"terrain_capacity_penalty": 0.90,
		"capacity_multiplier": 0.25,
	})
	army.on_edge = false
	army.move_from = army.location_city
	army.move_to = -1
	if not bool(protected_result.get("ok", false)):
		_fail("active-road rebuild must remain available")
		return
	if int(protected_result.get("protected_count", 0)) <= 0:
		_fail("active road was not reported as protected")
		return
	if protected_edge.max_manpower != protected_capacity:
		_fail("active road capacity changed during rebuild")
		return
	print(
		"ROAD_NETWORK_RUNTIME_OK open=",
		first["open_count"],
		" blocked=",
		first["blocked_count"],
		" avg_capacity=",
		first["average_capacity"],
		" transport_edges=",
		preserved_transport.size()
	)
	quit(0)
