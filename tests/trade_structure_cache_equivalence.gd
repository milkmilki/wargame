extends SceneTree
## 贸易结构缓存守卫：结构层只包含路线/税收依赖，库存、国库与需求变化
## 可复用同一 structure 动态结算；所有公开结果必须与 direct build 逐字段相同。
##
## Godot --headless --path . --script res://tests/trade_structure_cache_equivalence.gd

var _checks := 0
var _failures := 0


func _init() -> void:
	_test_direct_and_reused_settlement()
	_test_structure_dependencies()
	_test_dynamic_exclusions()
	_test_war_and_battle_exclusions()
	_test_result_alias_safety()
	_test_stale_dimensions_rebuild()
	print("=== 贸易结构缓存等价校验 ===")
	print("checks=%d failures=%d" % [_checks, _failures])
	print("verdict=%s" % (
		"TRADE_STRUCTURE_CACHE_EQUIVALENT"
		if _failures == 0
		else "TRADE_STRUCTURE_CACHE_DIVERGED"
	))
	quit(0 if _failures == 0 else 1)


func _test_direct_and_reused_settlement() -> void:
	var state := _make_state()
	var structure := TradeNetwork.build_structure(state)
	var baseline_token := TradeNetwork.structure_fingerprint(state)
	var initial_direct := TradeNetwork.build(state)
	_check(
		initial_direct == TradeNetwork.settle(state, structure),
		"equivalence/initial_direct_equals_structure_settle"
	)
	_check(
		structure.get("fingerprint", PackedByteArray()) == baseline_token,
		"structure/embeds_exact_fingerprint"
	)

	# 库存反转使粮食方向改变，但路线与税收结构仍可复用。
	state.cities[0].food_storage = 0
	state.cities[2].food_storage = 1400
	state.refresh_derived()
	_assert_reused_equals_direct(
		state, structure, baseline_token, "dynamic/inventory"
	)
	_check(
		TradeNetwork.build(state) != initial_direct,
		"dynamic/inventory_actually_changes_settlement"
	)

	state.nations[0].treasury_gold = 0
	state.nations[1].treasury_gold = 17
	_assert_reused_equals_direct(
		state, structure, baseline_token, "dynamic/treasury"
	)

	state.nations[0].treasury_gold = 1000
	state.nations[0].last_food_demand = 240
	state.nations[1].last_food_demand = 2
	state.nations[2].food_demand_ema = 55.25
	_assert_reused_equals_direct(
		state, structure, baseline_token, "dynamic/demand"
	)

	state.day += 91
	state.month += 3
	_assert_reused_equals_direct(
		state, structure, baseline_token, "dynamic/calendar"
	)

	# 清空结算需求快照后，城内军队兵力成为 fallback demand，仍只属 settle。
	for nation in state.nations:
		nation.last_food_demand = 0
		nation.food_demand_ema = 0.0
	state.armies[0].size = 12345
	_assert_reused_equals_direct(
		state, structure, baseline_token, "dynamic/in_city_army_size"
	)


func _assert_reused_equals_direct(
	state: GameState, structure: Dictionary, expected_token: PackedByteArray,
	label: String
) -> void:
	_check(
		TradeNetwork.structure_fingerprint(state) == expected_token,
		label + "_keeps_structure_token"
	)
	_check(
		TradeNetwork.settle(state, structure) == TradeNetwork.build(state),
		label + "_reused_equals_direct"
	)


func _test_structure_dependencies() -> void:
	var cases: Array[Dictionary] = [
		{"name": "city_id", "mutate": func(s: GameState) -> void:
			s.cities[0].id += 20},
		{"name": "city_owner", "mutate": func(s: GameState) -> void:
			s.cities[1].owner_nation = 1},
		{"name": "city_is_dock", "mutate": func(s: GameState) -> void:
			s.cities[1].is_dock = not s.cities[1].is_dock},
		{"name": "city_position", "mutate": func(s: GameState) -> void:
			s.cities[1].map_position.x += 0.03125},
		{"name": "city_gold", "mutate": func(s: GameState) -> void:
			s.cities[0].gold_per_month += 1},
		{"name": "city_food", "mutate": func(s: GameState) -> void:
			s.cities[0].food_per_half_year += 1},
		{"name": "city_is_capital", "mutate": func(s: GameState) -> void:
			s.cities[1].is_capital = true},
		{"name": "city_has_warehouse", "mutate": func(s: GameState) -> void:
			s.cities[1].has_warehouse = true},
		{"name": "city_port_market", "mutate": func(s: GameState) -> void:
			s.cities[1].is_port_market = not s.cities[1].is_port_market},
		{"name": "city_crossroads", "mutate": func(s: GameState) -> void:
			s.cities[1].is_crossroads = not s.cities[1].is_crossroads},
		{"name": "city_food_hub", "mutate": func(s: GameState) -> void:
			s.cities[1].is_food_hub = not s.cities[1].is_food_hub},
		{"name": "nation_alive", "mutate": func(s: GameState) -> void:
			s.nations[0].alive = false},
		{"name": "nation_capital", "mutate": func(s: GameState) -> void:
			s.nations[0].capital_city_id = 1},
		{"name": "nation_policy", "mutate": func(s: GameState) -> void:
			s.nations[0].trade_policy = TradeNetwork.GOLD},
		{"name": "ruler_trade_multiplier", "mutate": func(s: GameState) -> void:
			s.nations[0].ruler_traits = (
				[RulerProfile.TRAIT_MERCANTILE] as Array[String]
			)},
		{"name": "edge_endpoint", "mutate": func(s: GameState) -> void:
			s.edges[0].city_b = 2},
		{"name": "edge_kind", "mutate": func(s: GameState) -> void:
			s.edges[0].kind = Edge.Kind.RIVER},
		{"name": "edge_capacity", "mutate": func(s: GameState) -> void:
			s.edges[0].max_manpower += 1},
		{"name": "edge_base_capacity", "mutate": func(s: GameState) -> void:
			s.edges[0].base_max_manpower += 1},
		{"name": "edge_distance", "mutate": func(s: GameState) -> void:
			s.edges[0].distance += 1},
		{"name": "edge_travel_cost", "mutate": func(s: GameState) -> void:
			s.edges[0].travel_time_multiplier += 0.125},
		{"name": "edge_danger_cost", "mutate": func(s: GameState) -> void:
			s.edges[0].danger += 0.125},
		{"name": "edge_supply_cost", "mutate": func(s: GameState) -> void:
			s.edges[0].supply_loss_multiplier += 0.125},
		{"name": "map_aspect_ratio", "mutate": func(s: GameState) -> void:
			s.map_aspect_ratio += 0.25},
	]
	for case in cases:
		var state := _make_state()
		var before := TradeNetwork.structure_fingerprint(state)
		(case["mutate"] as Callable).call(state)
		_check(
			TradeNetwork.structure_fingerprint(state) != before,
			"fingerprint/changes_for_" + str(case["name"])
		)


func _test_dynamic_exclusions() -> void:
	var cases: Array[Dictionary] = [
		{"name": "food_storage", "mutate": func(s: GameState) -> void:
			s.cities[0].food_storage += 777},
		{"name": "granary_projection", "mutate": func(s: GameState) -> void:
			s.nations[0].granary_food += 777},
		{"name": "treasury", "mutate": func(s: GameState) -> void:
			s.nations[0].treasury_gold += 777},
		{"name": "last_food_demand", "mutate": func(s: GameState) -> void:
			s.nations[0].last_food_demand += 777},
		{"name": "food_demand_ema", "mutate": func(s: GameState) -> void:
			s.nations[0].food_demand_ema += 7.75},
		{"name": "day_and_month", "mutate": func(s: GameState) -> void:
			s.day += 400
			s.month += 13},
		{"name": "in_city_army_size", "mutate": func(s: GameState) -> void:
			s.armies[0].size += 7777},
		{"name": "war_graph", "mutate": func(s: GameState) -> void:
			s.set_diplomatic_relation(
				0, 2, GameState.DiplomaticRelation.WAR
			)},
		{"name": "besieged_city", "mutate": func(s: GameState) -> void:
			_add_siege(s, 1)},
		{"name": "army_edge_occupancy", "mutate": func(s: GameState) -> void:
			_add_edge_army(s, 2, 1, 3, 500)},
	]
	for case in cases:
		var state := _make_state()
		var before := TradeNetwork.structure_fingerprint(state)
		(case["mutate"] as Callable).call(state)
		_check(
			TradeNetwork.structure_fingerprint(state) == before,
			"fingerprint/ignores_" + str(case["name"])
		)


func _test_war_and_battle_exclusions() -> void:
	var state := _make_state()
	var peaceful_structure := TradeNetwork.build_structure(state)
	var peaceful_result := TradeNetwork.settle(state, peaceful_structure)
	var peaceful_token := TradeNetwork.structure_fingerprint(state)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	var wartime_structure := TradeNetwork.build_structure(state)
	var wartime_result := TradeNetwork.settle(state, peaceful_structure)
	_check(
		TradeNetwork.structure_fingerprint(state) == peaceful_token
			and wartime_structure == peaceful_structure,
		"fixed_network/war_keeps_structure_exact"
	)
	var wartime_mask := TradeNetwork.wartime_nation_mask(state)
	for city in state.cities:
		var peaceful_bonus := int(peaceful_result["city_gold_bonus"][city.id])
		var expected := (
			int(floor(
				float(peaceful_bonus)
				* TradeNetwork.WARTIME_TRADE_GOLD_MULTIPLIER
			))
			if wartime_mask[city.owner_nation] != 0
			else peaceful_bonus
		)
		_check(
			int(wartime_result["city_gold_bonus"][city.id]) == expected,
			"fixed_network/wartime_city_bonus_%d" % city.id
		)
	_check(
		wartime_result == TradeNetwork.build(state),
		"fixed_network/reused_wartime_settlement_matches_direct"
	)
	var blocker := _add_edge_army(state, 2, 1, 3, 500)
	_add_siege(state, 1)
	_check(
		TradeNetwork.structure_fingerprint(state) == peaceful_token
			and TradeNetwork.build_structure(state) == peaceful_structure,
		"fixed_network/siege_and_enemy_occupancy_keep_structure_exact"
	)
	blocker.size = 15000
	blocker.move_from = 3
	blocker.move_to = 2
	_check(
		TradeNetwork.structure_fingerprint(state) == peaceful_token,
		"fixed_network/ignores_blocker_size_and_position"
	)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	_check(
		TradeNetwork.build(state) == peaceful_result,
		"fixed_network/peace_restores_full_trade_bonus"
	)


func _test_result_alias_safety() -> void:
	var state := _make_state()
	var structure := TradeNetwork.build_structure(state)
	var structure_snapshot: Dictionary = structure.duplicate(true)
	var expected := TradeNetwork.settle(state, structure)
	var mutated := TradeNetwork.settle(state, structure)
	(mutated["city_gold_bonus"] as Array)[0] = 999999
	(mutated["nation_trade_gold"] as Array)[0] = 999999
	(mutated["nation_trade_tax"] as Array)[0] = 999999
	(mutated["nation_food_import"] as Array)[0] = 999999
	var routes: Array = mutated["routes"]
	if not routes.is_empty():
		var route: Dictionary = routes[0]
		(route["city_path"] as Array).append(999999)
		(route["preferred_city_path"] as Array).append(999999)
		(route["edge_keys"] as Array).append(999999)
		(route["city_gold_bonus"] as Dictionary)[999999] = 1
		route["food_transfer"] = 999999
	_check(
		structure == structure_snapshot,
		"alias/mutating_result_does_not_change_structure"
	)
	_check(
		TradeNetwork.settle(state, structure) == expected,
		"alias/later_settlement_not_contaminated"
	)
	var structure_food_is_zero := true
	for route_value in structure["routes"]:
		var route: Dictionary = route_value
		structure_food_is_zero = structure_food_is_zero and (
			int(route["food_transfer"]) == 0
			and int(route["food_cost_gold"]) == 0
		)
	_check(
		structure_food_is_zero,
		"alias/structure_keeps_unsettled_food_fields"
	)


func _test_stale_dimensions_rebuild() -> void:
	var city_state := _make_state()
	var city_structure := TradeNetwork.build_structure(city_state)
	_add_city(city_state, 0, Vector2(0.34, 0.18), 7, 300, 0)
	_check(
		TradeNetwork.settle(city_state, city_structure)
			== TradeNetwork.build(city_state),
		"stale/city_count_mismatch_rebuilds"
	)

	var nation_state := _make_state()
	var nation_structure := TradeNetwork.build_structure(nation_state)
	var nation := Nation.new()
	nation.id = nation_state.nations.size()
	nation.alive = false
	nation.trade_policy = TradeNetwork.BALANCED
	nation.ruler_archetype = RulerProfile.BALANCED
	nation_state.nations.append(nation)
	_check(
		TradeNetwork.settle(nation_state, nation_structure)
			== TradeNetwork.build(nation_state),
		"stale/nation_count_mismatch_rebuilds"
	)


func _make_state() -> GameState:
	var state := GameState.new()
	state.world_seed = 24680
	state.map_aspect_ratio = 1.4
	for nation_id in range(3):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.capital_city_id = nation_id * 2
		nation.warehouse_city_ids = [nation.capital_city_id] as Array[int]
		nation.trade_policy = TradeNetwork.BALANCED
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits = [] as Array[String]
		nation.treasury_gold = 1000
		nation.last_food_demand = [10, 120, 20][nation_id]
		state.nations.append(nation)

	_add_city(state, 0, Vector2(0.08, 0.32), 24, 900, 1000)
	_add_city(state, 0, Vector2(0.25, 0.38), 16, 620, 0)
	_add_city(state, 1, Vector2(0.92, 0.35), 21, 700, 0)
	_add_city(state, 1, Vector2(0.75, 0.42), 15, 500, 0)
	_add_city(state, 2, Vector2(0.47, 0.65), 18, 820, 180)
	_add_city(state, 2, Vector2(0.56, 0.58), 12, 480, 0)
	for capital_id in [0, 2, 4]:
		state.cities[capital_id].is_capital = true
		state.cities[capital_id].has_warehouse = true
	state.cities[0].is_port_market = true
	state.cities[1].is_crossroads = true
	state.cities[4].is_food_hub = true
	state.cities[5].is_dock = true

	_add_edge(state, 0, 1, 20000, 2, 1.00, 0.10, 0.80)
	_add_edge(state, 1, 3, 20000, 3, 1.10, 0.05, 1.00)
	_add_edge(state, 3, 2, 20000, 2, 1.00, 0.15, 0.90)
	_add_edge(state, 1, 4, 10000, 2, 1.20, 0.20, 1.20)
	_add_edge(state, 4, 5, 50000, 1, 0.72, 0.05, 0.70, Edge.Kind.RIVER)
	_add_edge(state, 5, 3, 50000, 2, 0.62, 0.10, 0.60, Edge.Kind.SEA)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)

	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	var in_city_army := Army.new()
	in_city_army.id = 0
	in_city_army.owner_nation = 0
	in_city_army.location_city = 0
	in_city_army.size = 4000
	state.armies.append(in_city_army)
	state.refresh_derived()
	return state


func _add_city(
	state: GameState, owner: int, position: Vector2, gold: int, food: int,
	storage: int
) -> void:
	var city := City.new()
	city.id = state.cities.size()
	city.owner_nation = owner
	city.map_position = position
	city.gold_per_month = gold
	city.food_per_half_year = food
	city.food_storage = storage
	state.cities.append(city)
	state.adjacency[city.id] = [] as Array[int]


func _add_edge(
	state: GameState, a: int, b: int, capacity: int, distance: int,
	travel: float, danger: float, supply_loss: float,
	kind: int = Edge.Kind.LAND
) -> void:
	var edge := Edge.new()
	edge.city_a = mini(a, b)
	edge.city_b = maxi(a, b)
	edge.kind = kind
	edge.max_manpower = capacity
	edge.base_max_manpower = capacity
	edge.distance = distance
	edge.travel_time_multiplier = travel
	edge.danger = danger
	edge.supply_loss_multiplier = supply_loss
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(a, b)] = edge
	(state.adjacency[a] as Array[int]).append(b)
	(state.adjacency[b] as Array[int]).append(a)


func _set_all_relations(state: GameState, relation: int) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(nation_a, nation_b, relation)


func _add_siege(state: GameState, city_id: int) -> void:
	var battle := Battle.new()
	battle.id = state.battles.size()
	battle.kind = Battle.Kind.SIEGE
	battle.city = state.cities[city_id]
	battle.finished = false
	state.battles.append(battle)


func _add_edge_army(
	state: GameState, owner: int, from_city: int, to_city: int, size: int
) -> Army:
	var army := Army.new()
	army.id = state.armies.size()
	army.owner_nation = owner
	army.size = size
	army.on_edge = true
	army.move_from = from_city
	army.move_to = to_city
	state.armies.append(army)
	return army


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAILED: %s" % label)
