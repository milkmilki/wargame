extends SceneTree
## Atlas jurisdiction regression. Small fixed州/府 fixture, no Earth cache.
## Default execution bounds recursive leg entry while running the real superclass.
## --unguarded-repat reproduces the engine stack overflow without that guard.

class BoundedSimulation:
	extends Simulation
	var leg_depth := 0
	var deepest_leg_entry := 0
	var recursive_cycle := false

	func _begin_next_leg(army: Army) -> void:
		leg_depth += 1
		deepest_leg_entry = maxi(deepest_leg_entry, leg_depth)
		if leg_depth > 16:
			recursive_cycle = true
			leg_depth -= 1
			return
		super._begin_next_leg(army)
		leg_depth -= 1

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_cmdline_user_args().has("--unguarded-repat"):
		_test_diplomatic_repatriation(true)
	else:
		_test_attack_respects_control_jurisdictions()
		_test_runtime_refuses_forbidden_attack_leg()
		_test_retreat_can_exit_lost_jurisdiction()
		_test_retreat_cannot_transit_another_enemy()
		_test_diplomatic_repatriation(false)
	print("ATLAS_ACCESS_%s checks=%d failures=%d" % [
		"OK" if _failures.is_empty() else "FAILED", _checks, _failures.size(),
	])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		print("ATLAS_ACCESS_FAIL: ", message)


func _fixture(roads: Array[Vector3i]) -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state._reset_world(94161)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 4, false)
	state.trade_enabled = false
	var owners: Array[int] = [0, 1, 2, 3, 1]
	for city_id in range(9):
		var city := City.new()
		city.id = city_id
		city.name = "权限夹具%d" % city_id
		city.short_name = String.chr(0x4e20 + city_id)
		city.map_position = Vector2(float(city_id) / 10.0, 0.5)
		if city_id >= owners.size():
			city.node_kind = City.NodeKind.TRAFFIC
			city.politically_active = false
		else:
			city.owner_nation = owners[city_id]
			city.loyalty_target_nation = owners[city_id]
			city.manpower_per_month = 10000
			city.gold_per_month = 100
			city.food_per_half_year = 100000
		state.cities.append(city)
		state.adjacency[city_id] = [] as Array[int]
		state.recognized_city_owners.append(city.owner_nation)
		state.region_ids.append(city_id if city_id < owners.size() else -1)
	for road in roads:
		state._add_edge(road.x, road.y)
		var edge := state.edge_of(road.x, road.y)
		edge.control_city_id = road.z
		edge.max_manpower = 50000
		edge.base_max_manpower = 50000
		edge.precise_distance = 1.0
		edge.distance = 1
		edge.danger = 0.0
	state.atlas_layout = {
		"model": "atlas-military-v1",
		"hierarchy": {
			"members": [[0], [1], [2], [3], [4]],
			"center_by_city": PackedInt32Array([0, 1, 2, 3, 4]),
			"state_by_city": PackedInt32Array([0, 1, 2, 3, 4]),
			"state_parents": PackedInt32Array([0, 1, 2, 3, 4]),
		},
		"settlement_adjacency": {},
		"territorial_pairs": [] as Array[Vector2i],
	}
	state.rebuild_administrative_regions()
	state._initialize_manpower_pools()
	state._initialize_capitals_and_warehouses()
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	state.refresh_derived()
	return state


func _army(state: GameState, city_id: int) -> Army:
	var army := Army.new()
	army.id = 941610
	army.owner_nation = 0
	army.size = 15000
	army.max_size = 15000
	army.morale = army.max_morale
	army.location_city = city_id
	army.move_from = city_id
	state.armies.append(army)
	return army


func _attack_path(state: GameState, start: int, goal: int) -> Array[int]:
	var field := Pathfinding.dijkstra_field(state, start, 0, false, true, goal)
	return Pathfinding.reconstruct(field.prev, start, goal)


func _finish_leg(sim: Simulation, army: Army) -> void:
	army.move_progress = 1.0
	sim._arrive_at_node(army)


func _test_attack_respects_control_jurisdictions() -> void:
	print("ATLAS_ACCESS_CASE attack jurisdiction boundaries")
	var state := _fixture([
		Vector3i(0, 5, 0), Vector3i(5, 1, 1),
		Vector3i(0, 6, 0), Vector3i(6, 7, 2), Vector3i(7, 1, 1),
		Vector3i(0, 8, 3), Vector3i(8, 1, 1),
		Vector3i(0, 4, 4), Vector3i(4, 1, 1),
	] as Array[Vector3i])
	# Make forbidden corridors cheaper so the route assertion proves permissions.
	for edge in state.edges:
		if edge != state.edge_of(0, 5) and edge != state.edge_of(5, 1):
			edge.precise_distance = 0.1
	_check(_attack_path(state, 0, 1) == [5, 1],
		"attack may enter only final enemy jurisdiction, ignoring shorter forbidden routes")
	var ordinary := Pathfinding.dijkstra_field(state, 0, 0)
	_check(is_inf(ordinary.dist[1]), "ordinary movement cannot enter enemy jurisdiction without attack goal")
	_check(not state.atlas_edge_access(state.edge_of(6, 7), 0, 1),
		"neutral third-country jurisdiction is not attack transit")
	_check(not state.atlas_edge_access(state.edge_of(0, 8), 0, 1),
		"another enemy nation's jurisdiction is not attack transit")
	_check(not state.atlas_edge_access(state.edge_of(0, 4), 0, 1),
		"same enemy nation's different settlement jurisdiction is not attack transit")
	_check(state.atlas_edge_access(state.edge_of(5, 1), 0, 1),
		"final enemy settlement jurisdiction remains a legal attack leg")
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	_check(state.atlas_edge_access(state.edge_of(6, 7), 0, 1),
		"allied third-country jurisdiction retains ordinary military access")


func _test_runtime_refuses_forbidden_attack_leg() -> void:
	print("ATLAS_ACCESS_CASE stale runtime attack route")
	var state := _fixture([Vector3i(0, 8, 3), Vector3i(8, 1, 1)] as Array[Vector3i])
	var army := _army(state, 0)
	army.state = Army.State.MOVING
	army.path.assign([8, 1])
	var sim := BoundedSimulation.new()
	sim.setup(state)
	sim._begin_next_leg(army)
	_check(not army.on_edge and army.move_to == -1 and army.path.is_empty(),
		"runtime rejects stale route into another enemy jurisdiction")
	_check(state.edge_of(0, 8).passing_count == 0 and army.size == 15000,
		"rejected normal attack never acquires road occupancy or invents losses")
	_check(not sim.recursive_cycle, "rejected attack from home settles without recursion")
	sim.free()


func _test_retreat_can_exit_lost_jurisdiction() -> void:
	print("ATLAS_ACCESS_CASE retreat exits current lost jurisdiction")
	var state := _fixture([
		Vector3i(1, 5, 1), Vector3i(5, 6, 1), Vector3i(6, 0, 0),
		Vector3i(1, 7, 1), Vector3i(7, 8, 3), Vector3i(8, 0, 0),
	] as Array[Vector3i])
	for pair in [Vector2i(1, 7), Vector2i(7, 8), Vector2i(8, 0)]:
		state.edge_of(pair.x, pair.y).precise_distance = 0.1
	var army := _army(state, 1)
	var route := Pathfinding.strategic_retreat_city(state, army, 1)
	_check(route == [5, 6, 0],
		"retreat exits several road segments of starting hostile jurisdiction without crossing another enemy: %s" % str(route))
	var sim := BoundedSimulation.new()
	sim.setup(state)
	sim._start_morale_retreat_from_city(army, 1, 1)
	_check(army.size == 15000 and army.state == Army.State.RETREATING
		and army.on_edge and army.move_from == 1 and army.move_to == 5,
		"army in freshly lost city starts a real evacuation through current jurisdiction")
	if army.on_edge and army.move_to == 5:
		_finish_leg(sim, army)
		_check(army.on_edge and army.move_from == 5 and army.move_to == 6,
			"evacuation permission persists through traffic segments of original lost jurisdiction")
		_finish_leg(sim, army)
		_check(army.on_edge and army.move_from == 6 and army.move_to == 0,
			"evacuation leaves original jurisdiction into home territory")
		_finish_leg(sim, army)
		_check(army.size == 15000 and army.location_city == 0 and not army.on_edge
			and army.state in [Army.State.IDLE, Army.State.RECOVERING],
			"ordinary retreat arrives home without dispersal or teleportation")
	_check(not sim.recursive_cycle, "lost-jurisdiction evacuation never recursively retries same rejected leg")
	sim.free()


func _test_retreat_cannot_transit_another_enemy() -> void:
	print("ATLAS_ACCESS_CASE no retreat bridge through other enemy")
	var state := _fixture([
		Vector3i(1, 7, 1), Vector3i(7, 8, 3), Vector3i(8, 0, 0),
	] as Array[Vector3i])
	var army := _army(state, 1)
	_check(Pathfinding.strategic_retreat_city(state, army, 1).is_empty(),
		"current-jurisdiction escape exception cannot manufacture a route through another enemy")
	var sim := BoundedSimulation.new()
	sim.setup(state)
	sim._start_morale_retreat_from_city(army, 1, 1)
	_check(not army.on_edge and state.edge_of(7, 8).passing_count == 0,
		"blocked ordinary retreat never occupies another enemy's jurisdiction")
	_check(not sim.recursive_cycle, "unreachable ordinary retreat terminates without recursive retries")
	sim.free()


func _test_diplomatic_repatriation(unguarded: bool) -> void:
	print("ATLAS_ACCESS_CASE diplomatic repatriation unguarded=", unguarded)
	var state := _fixture([
		Vector3i(2, 7, 2), Vector3i(7, 8, 3), Vector3i(8, 0, 0),
	] as Array[Vector3i])
	var army := _army(state, 2)
	var route := Pathfinding.nearest_home_city_for_repatriation(state, army, 2)
	_check(route == [7, 8, 0], "diplomatic planner retains existing unrestricted transit route")
	var sim: Simulation = Simulation.new() if unguarded else BoundedSimulation.new()
	sim.setup(state)
	print("ATLAS_ACCESS_REPAT_ENTER real _start_diplomatic_repatriation from neutral city2")
	sim._start_diplomatic_repatriation(army, 2)
	if not unguarded:
		var bounded := sim as BoundedSimulation
		_check(not bounded.recursive_cycle,
			"diplomatic repatriation must not recursively reject/recompute its route (depth=%d)" % bounded.deepest_leg_entry)
	_check(army.diplomatic_repatriation and army.size == 15000 and army.on_edge
		and army.move_from == 2 and army.move_to == 7,
		"real diplomatic repatriation can leave neutral territory on planned positive-capacity road")
	if army.on_edge and army.move_to == 7:
		_finish_leg(sim, army)
		_check(army.diplomatic_repatriation and army.on_edge
			and army.move_from == 7 and army.move_to == 8,
			"diplomatic repatriation retains crossing exception through another enemy jurisdiction")
		_finish_leg(sim, army)
		_check(army.on_edge and army.move_from == 8 and army.move_to == 0,
			"diplomatic repatriation proceeds into actual home territory")
		_finish_leg(sim, army)
		_check(army.location_city == 0 and not army.on_edge and army.size == 15000
			and not army.diplomatic_repatriation and army.battle_id == -1,
			"arrival home releases repatriation status and battle binding without losses")
		for edge in state.edges:
			_check(edge.passing_count == 0 and not edge.occupied,
				"completed repatriation releases every traversed edge")
	_check(state.battles.is_empty(), "diplomatic repatriation never starts attacks in crossed foreign jurisdictions")
	sim.free()
