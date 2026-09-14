extends SceneTree

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var occupied := _make_corridor_state(true)
	var occupied_sim := Simulation.new()
	occupied_sim.setup(occupied)
	var result := occupied_sim._make_coalition_peace(0, 1)
	var all_cut_territory_transferred := true
	for city_id in range(1, 8):
		all_cut_territory_transferred = (
			all_cut_territory_transferred
			and occupied.cities[city_id].owner_nation == 0
			and occupied.recognized_owner_of(city_id) == 0
		)
	_check(bool(result.get("changed", false)), "有真实占领时议和必须成功")
	_check(
		all_cut_territory_transferred
			and occupied.cities[0].owner_nation == 1,
		"占领城3的两跳范围1至5及其造成的飞地6至7必须全部割让，首都0保留"
	)
	_check(
		int(result.get("territories_transferred", -1)) == 7,
		"战争结算必须报告两跳扩张与飞地合计7城"
	)
	occupied_sim.free()

	var peaceful := _make_corridor_state(false)
	var peaceful_sim := Simulation.new()
	peaceful_sim.setup(peaceful)
	var no_occupation_result := peaceful_sim._make_coalition_peace(0, 1)
	var defender_retained_all := true
	for city_id in range(8):
		defender_retained_all = (
			defender_retained_all
			and peaceful.cities[city_id].owner_nation == 1
			and peaceful.recognized_owner_of(city_id) == 1
		)
	_check(
		bool(no_occupation_result.get("changed", false))
			and defender_retained_all
			and int(no_occupation_result.get("territories_transferred", -1)) == 0,
		"没有占领防守方城市时只能停战，不得割让任何地区"
	)
	peaceful_sim.free()
	_finish()


func _make_corridor_state(with_occupation: bool) -> GameState:
	var state := GameState.new()
	state.generate_grid_world(95201)
	state.armies.clear()
	state.battles.clear()
	for city in state.cities:
		city.owner_nation = 2
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		state.recognized_city_owners[city.id] = 2
	for city_id in range(8):
		state.cities[city_id].owner_nation = 1
		state.recognized_city_owners[city_id] = 1
	state.cities[8].owner_nation = 0
	state.recognized_city_owners[8] = 0
	state.nations[0].capital_city_id = 8
	state.nations[0].warehouse_city_ids = [8] as Array[int]
	state.cities[8].is_capital = true
	state.cities[8].has_warehouse = true
	state.nations[1].capital_city_id = 0
	state.nations[1].warehouse_city_ids = [0] as Array[int]
	state.cities[0].is_capital = true
	state.cities[0].has_warehouse = true
	state.nations[2].capital_city_id = 63
	state.nations[2].warehouse_city_ids = [63] as Array[int]
	state.cities[63].is_capital = true
	state.cities[63].has_warehouse = true
	state.nations[3].capital_city_id = -1
	state.nations[3].warehouse_city_ids.clear()
	for edge in state.edges:
		edge.max_manpower = 0
	for city_id in range(7):
		state.edge_of(city_id, city_id + 1).max_manpower = Edge.STANDARD_MANPOWER
	if with_occupation:
		state.cities[3].owner_nation = 0
		state.cities[3].occupation_sponsor_nation = 0
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.ownership_revision += 1
	state.road_network_revision += 1
	state.refresh_derived()
	return state


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PEACE_TWO_HOP_CESSION_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("PEACE_TWO_HOP_CESSION_FAIL: " + failure)
	quit(1)
