extends SceneTree
## Preserve complete blocking state while avoiding battle-count × army-count scans.
class CountedSimulation extends Simulation:
	var inspected := 0
	func _is_travelling(army: Army) -> bool:
		inspected += 1
		return super._is_travelling(army)

const Legacy = preload("res://tests/support/legacy_contact_simulation.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func _initialize(): call_deferred("run")
func fixture(count: int, history_only: bool = false) -> GameState:
	var state := GameState.new()
	state._reset_world(123)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 4, false)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(2, 0, GameState.DiplomaticRelation.WAR)
	for id in range(count * 2):
		var city := City.new(); city.id = id; city.owner_nation = id % 4
		city.map_position = Vector2(float(id) / (count * 2), .5)
		state.cities.append(city)
	for index in range(count):
		var edge := Edge.new(); edge.city_a = index * 2; edge.city_b = index * 2 + 1
		edge.precise_distance = .1
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(edge.city_a, edge.city_b)] = edge
		var battle := state.new_battle(Battle.Kind.FIELD); battle.edge = edge
		battle.finished = history_only; battle.contact_dist_a = .05; battle.contact_dist_b = .05
		for owner in range(4):
			for reverse in [false, true]:
				for position in [.1, .495, .505, .9]:
					var army := Army.new(); army.id = state.armies.size(); army.owner_nation = owner
					army.size = 100; army.max_size = 100; army.location_city = edge.city_a
					army.move_from = edge.city_b if reverse else edge.city_a
					army.move_to = edge.city_a if reverse else edge.city_b
					army.move_progress = position; army.on_edge = true
					army.state = Army.State.RETREATING if reverse else Army.State.MOVING
					state.armies.append(army)
		battle.side_a.append(state.armies[index * 32]); battle.side_b.append(state.armies[index * 32 + 8])
		# Sequential clamps on the same edge must retain battle order.
		if index == 0:
			var second := state.new_battle(Battle.Kind.FIELD); second.edge = edge; second.finished = history_only
			second.contact_dist_a = .049; second.contact_dist_b = .049
			second.side_a.assign(battle.side_a); second.side_b.assign(battle.side_b)
	return state
func run():
	for history_only in [false, true]:
		var current := CountedSimulation.new(); current.state = fixture(48, history_only)
		var legacy := Legacy.new(); legacy.state = fixture(48, history_only)
		var started := Time.get_ticks_usec(); legacy._block_passthrough(); var before := Time.get_ticks_usec() - started
		started = Time.get_ticks_usec(); current._block_passthrough(); var after := Time.get_ticks_usec() - started
		check(NativeSnapshotBuilder.build(current.state) == NativeSnapshotBuilder.build(legacy.state), "full state and sequential clamps equal oracle")
		check(current.inspected <= current.state.armies.size(), "inspect each army at most once regardless of battle count")
		if history_only: check(current.inspected == 0, "finished history needs no army scan")
		else:
			check(current.state.armies[18].move_progress == .49, "hostile third country stops at successive front lines")
			check(current.state.armies[26].move_progress == .505, "neutral third country remains unchanged")
		print("CONTACT_INDEX history_only=", history_only, " before_us=", before, " after_us=", after, " inspected=", current.inspected)
		current.free(); legacy.free()
	for failure in failures: printerr("CONTACT_INDEX_FAIL ", failure)
	print("CONTACT_INDEX_RESULT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
