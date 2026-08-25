extends SceneTree
## 国家粮食快照专项：
## 1. 旧档兼容：Nation 新字段默认 0，未月结时详情面板不报错。
## 2. 月结入口：_resolve_economy() 一次性发布粮仓存量、预计月产/月需/月净。
## 3. UI 文本：粮食与贸易两行数学一致，零值不显示 +0/-0。
## 4. 产量口径：按 nation 汇总完整半年产量后统一 /6 rounding，不逐城 rounding。

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_legacy_defaults_and_zero_trade_ui()
	_test_change_city_food_storage()
	_test_deposit_food_immediate_aggregate()
	_test_resolve_trade_purchases_conjures_resources()
	_test_setup_snapshot_production_estimate()
	_test_monthly_production_rounds_after_nation_sum()
	_test_monthly_snapshot_and_ui_math()
	if _failures.is_empty():
		print("NATION_FOOD_SNAPSHOT_OK checks=%d" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("NATION_FOOD_SNAPSHOT_FAIL: " + failure)
	print("NATION_FOOD_SNAPSHOT_INVALID checks=%d failures=%d" % [
		_checks, _failures.size(),
	])
	quit(1)


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	var message := label
	if not detail.is_empty():
		message += " :: " + detail
	_failures.append(message)


func _test_legacy_defaults_and_zero_trade_ui() -> void:
	var fresh := Nation.new()
	_check(
		fresh.last_food_estimated_production == 0
			and fresh.last_food_estimated_consumption == 0
			and fresh.last_food_estimated_balance == 0,
		"legacy/default_snapshot_fields_zero"
	)

	var state := _make_single_nation_state()
	var sections := MapRenderer.nation_detail_sections(state, 0)
	var trade_line := _section_line(sections, "粮食与贸易", 1)
	_check(
		sections.size() > 0,
		"legacy/nation_detail_sections_no_error"
	)
	_check(
		trade_line.find("商路 0") >= 0
			and trade_line.find("商贸金 0") >= 0
			and trade_line.find("购粮 0") >= 0
			and trade_line.find("购人 0") >= 0
			and trade_line.find("+0") == -1
			and trade_line.find("-0") == -1,
		"legacy/zero_trade_ui_without_signed_zero",
		trade_line
	)


func _test_monthly_snapshot_and_ui_math() -> void:
	var state := _make_trade_pair_state()
	var expected_trade := TradeNetwork.build(state)
	var expected_import_0 := int(expected_trade["nation_food_import"][0])
	var expected_export_0 := int(expected_trade["nation_food_export"][0])
	var expected_import_1 := int(expected_trade["nation_food_import"][1])
	var expected_export_1 := int(expected_trade["nation_food_export"][1])
	_check(
		expected_import_0 + expected_import_1 > 0,
		"snapshot/fixture_has_nonzero_food_trade",
		str(expected_trade)
	)

	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	state.day = Simulation.DAYS_PER_MONTH
	state.month = 1
	sim._resolve_economy()

	var nation_0 := state.nations[0]
	var nation_1 := state.nations[1]
	var expected_prod_0 := int(round(
		float(Simulation.city_food_output(state, state.cities[0], {})) / 6.0
	))
	var expected_prod_1 := int(round(
		float(Simulation.city_food_output(state, state.cities[1], {})) / 6.0
	))
	_check(
		nation_0.granary_food > 0 and nation_1.granary_food > 0,
		"snapshot/granary_food_nonzero_after_settlement",
		"n0=%d n1=%d" % [nation_0.granary_food, nation_1.granary_food]
	)
	_check(
		nation_0.last_food_estimated_production == expected_prod_0
			and nation_1.last_food_estimated_production == expected_prod_1,
		"snapshot/monthly_production_matches_half_year_fold",
		"actual=%d/%d expected=%d/%d" % [
			nation_0.last_food_estimated_production,
			nation_1.last_food_estimated_production,
			expected_prod_0,
			expected_prod_1,
		]
	)
	_check(
		nation_0.last_food_estimated_consumption == nation_0.last_food_demand
			and nation_1.last_food_estimated_consumption == nation_1.last_food_demand,
		"snapshot/monthly_consumption_reuses_last_food_demand",
		"actual=%d/%d demand=%d/%d" % [
			nation_0.last_food_estimated_consumption,
			nation_1.last_food_estimated_consumption,
			nation_0.last_food_demand,
			nation_1.last_food_demand,
		]
	)
	_check(
		nation_0.last_food_estimated_balance
			== nation_0.last_food_estimated_production
				- nation_0.last_food_estimated_consumption
				+ nation_0.last_trade_food_import
				- nation_0.last_trade_food_export
			and nation_1.last_food_estimated_balance
				== nation_1.last_food_estimated_production
					- nation_1.last_food_estimated_consumption
					+ nation_1.last_trade_food_import
					- nation_1.last_trade_food_export,
		"snapshot/net_balance_matches_display_math",
		"n0=%d n1=%d" % [
			nation_0.last_food_estimated_balance,
			nation_1.last_food_estimated_balance,
		]
	)
	_check(
		nation_0.last_trade_food_import == expected_import_0
			and nation_0.last_trade_food_export == expected_export_0
			and nation_1.last_trade_food_import == expected_import_1
			and nation_1.last_trade_food_export == expected_export_1,
		"snapshot/trade_snapshot_matches_trade_network",
		"actual=%d/%d %d/%d expected=%d/%d %d/%d" % [
			nation_0.last_trade_food_import,
			nation_0.last_trade_food_export,
			nation_1.last_trade_food_import,
			nation_1.last_trade_food_export,
			expected_import_0,
			expected_export_0,
			expected_import_1,
			expected_export_1,
		]
	)

	var sections_0 := MapRenderer.nation_detail_sections(state, 0)

	var food_line_0 := _section_line(sections_0, "粮食与贸易", 0)
	var trade_line_0 := _section_line(sections_0, "粮食与贸易", 1)
	_check(
		food_line_0.find("粮仓 %d" % nation_0.granary_food) >= 0
			and food_line_0.find("月产(预计) %d" % nation_0.last_food_estimated_production) >= 0
			and food_line_0.find("月需(预计) %d" % nation_0.last_food_estimated_consumption) >= 0
			and food_line_0.find(
				"月净(预计) %s" % _signed_or_zero(nation_0.last_food_estimated_balance)
			) >= 0,
		"ui/food_line_matches_snapshot",
		food_line_0
	)
	_check(
		trade_line_0.find("商路 %d" % nation_0.last_trade_route_count) >= 0
			and trade_line_0.find(
				"商贸金 %s" % _signed_or_zero(nation_0.last_trade_gold)
			) >= 0
			and trade_line_0.find(
				"购粮 %d" % maxi(nation_0.last_trade_food_import, 0)
			) >= 0
			and trade_line_0.find(
				"购人 %d" % maxi(nation_0.last_trade_manpower_import, 0)
			) >= 0,
		"ui/trade_line_matches_snapshot",
		trade_line_0
	)

	sim.free()


func _test_change_city_food_storage() -> void:
	var state := _make_single_nation_state()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)

	var city := state.cities[0]
	var nation := state.nations[0]
	var initial_storage := city.food_storage
	var initial_granary := nation.granary_food

	_check(
		city.has_warehouse and city.owner_nation == 0,
		"change_storage/fixture_has_valid_warehouse"
	)
	_check(
		initial_granary == initial_storage,
		"change_storage/granary_matches_city_storage_after_setup",
		"granary=%d storage=%d" % [initial_granary, initial_storage]
	)

	var ret_pos := state.change_city_food_storage(0, 7)
	_check(ret_pos == 7, "change_storage/positive_returns_delta",
		"ret=%d" % ret_pos)
	_check(
		city.food_storage == initial_storage + 7,
		"change_storage/city_storage_increased",
		"old=%d new=%d" % [initial_storage, city.food_storage]
	)
	_check(
		nation.granary_food == initial_granary + 7,
		"change_storage/nation_granary_increased",
		"old=%d new=%d" % [initial_granary, nation.granary_food]
	)

	var current_storage := city.food_storage
	var current_granary := nation.granary_food
	var overdraw := -(current_storage + 10)
	var ret_neg := state.change_city_food_storage(0, overdraw)
	_check(
		ret_neg == -current_storage,
		"change_storage/negative_clamps_to_zero",
		"ret=%d expected=%d" % [ret_neg, -current_storage]
	)
	_check(
		city.food_storage == 0,
		"change_storage/city_storage_zeroed",
		"storage=%d" % city.food_storage
	)
	_check(
		nation.granary_food == current_granary - current_storage,
		"change_storage/nation_granary_reduced_by_exact_old",
		"granary=%d expected=%d" % [
			nation.granary_food,
			current_granary - current_storage
		]
	)
	_check(
		nation.granary_food >= 0,
		"change_storage/nation_granary_nonnegative",
		"granary=%d" % nation.granary_food
	)

	var ret_invalid_neg := state.change_city_food_storage(-1, 5)
	_check(
		ret_invalid_neg == 0,
		"change_storage/invalid_city_negative_id_returns_zero",
		"ret=%d" % ret_invalid_neg
	)
	var ret_invalid_overflow := state.change_city_food_storage(999, 5)
	_check(
		ret_invalid_overflow == 0,
		"change_storage/invalid_city_overflow_id_returns_zero",
		"ret=%d" % ret_invalid_overflow
	)
	var ret_zero := state.change_city_food_storage(0, 0)
	_check(
		ret_zero == 0,
		"change_storage/delta_zero_returns_zero",
		"ret=%d" % ret_zero
	)
	_check(
		city.food_storage == 0,
		"change_storage/no_side_effects_after_invalid_calls",
		"storage=%d" % city.food_storage
	)

	# --- Negative old storage + positive delta: repair negative ---
	city.food_storage = -5
	state.change_city_food_storage(0, 10)
	_check(
		city.food_storage == 5,
		"change_storage/negative_old_positive_delta_repairs",
		"storage=%d expected=5" % city.food_storage
	)

	# --- Negative old storage + negative delta: clamp to zero, actual_delta < raw delta ---
	city.food_storage = -3
	state.change_city_food_storage(0, -10)
	_check(
		city.food_storage == 0,
		"change_storage/negative_old_negative_delta_clamps_zero",
		"storage=%d" % city.food_storage
	)

	# --- Invalid owner (city.owner_nation != valid nation): mutates city but not aggregate ---
	city.food_storage = 20
	var saved_granary := nation.granary_food
	city.owner_nation = 99
	state.change_city_food_storage(0, 5)
	_check(
		city.food_storage == 25,
		"change_storage/invalid_owner_mutates_city",
		"storage=%d" % city.food_storage
	)
	_check(
		nation.granary_food == saved_granary,
		"change_storage/invalid_owner_no_aggregate_change",
		"granary=%d expected=%d" % [nation.granary_food, saved_granary]
	)

	sim.free()


func _test_deposit_food_immediate_aggregate() -> void:
	var state := _make_single_nation_state()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)

	var city := state.cities[0]
	var nation := state.nations[0]
	var initial_storage := city.food_storage
	var initial_granary := nation.granary_food

	_check(
		state.deposit_food(0, 12),
		"deposit/positive_returns_true"
	)
	_check(
		city.food_storage == initial_storage + 12,
		"deposit/city_storage_increased",
		"old=%d new=%d" % [initial_storage, city.food_storage]
	)
	_check(
		nation.granary_food == initial_granary + 12,
		"deposit/nation_granary_increased_immediately",
		"old=%d new=%d" % [initial_granary, nation.granary_food]
	)

	_check(
		not state.deposit_food(0, 0),
		"deposit/zero_amount_returns_false"
	)
	_check(
		not state.deposit_food(-1, 5),
		"deposit/invalid_nation_returns_false"
	)

	sim.free()


func _test_resolve_trade_purchases_conjures_resources() -> void:
	var state := _make_single_nation_state()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)

	var nation := state.nations[0]
	var initial_granary := nation.granary_food
	var initial_manpower := nation.manpower_pool

	# 简化版 EU4 贸易：钱凭空买粮、买人；直接落到粮池与人力库，不动他国。
	var trade := {
		"nation_food_import": [9] as Array[int],
		"nation_food_export": [0] as Array[int],
		"nation_manpower_import": [400] as Array[int],
	}
	sim._resolve_trade_purchases(trade)
	_check(
		nation.granary_food == initial_granary + 9,
		"trade_purchase/nation_granary_increased_immediately",
		"old=%d new=%d" % [initial_granary, nation.granary_food]
	)
	_check(
		nation.manpower_pool == initial_manpower + 400,
		"trade_purchase/manpower_pool_increased_immediately",
		"old=%d new=%d" % [initial_manpower, nation.manpower_pool]
	)

	sim.free()


func _test_setup_snapshot_production_estimate() -> void:
	var state := _make_single_nation_state()
	var army := state.create_army(0, 0, 5000)
	_check(
		army != null,
		"setup_snapshot/army_created",
		"army_id=%d size=%d" % [army.id, army.size]
	)

	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)

	var city := state.cities[0]
	var nation := state.nations[0]
	var garrison_index := Simulation.build_garrison_index(state)

	var half_year_total := 0
	for c in state.cities:
		if c.owner_nation == 0:
			half_year_total += Simulation.city_food_output(
				state, c, garrison_index
			)
	var expected_prod := int(round(
		float(half_year_total) / 6.0
	))
	_check(
		nation.last_food_estimated_production == expected_prod,
		"setup_snapshot/production_estimate_matches_half_year_fold",
		"actual=%d expected=%d half_year=%d" % [
			nation.last_food_estimated_production,
			expected_prod,
			half_year_total
		]
	)

	var expected_demand := (
		TradeNetwork.projected_nation_monthly_food_demand(state, 0)
	)
	_check(
		expected_demand > 0,
		"setup_snapshot/demand_positive_with_army",
		"demand=%d" % expected_demand
	)
	_check(
		nation.last_food_demand == expected_demand,
		"setup_snapshot/demand_matches_projected",
		"actual=%d expected=%d" % [
			nation.last_food_demand, expected_demand
		]
	)
	_check(
		nation.last_food_estimated_consumption == expected_demand,
		"setup_snapshot/consumption_equals_projected_demand",
		"actual=%d expected=%d" % [
			nation.last_food_estimated_consumption, expected_demand
		]
	)

	var expected_trade := TradeNetwork.build(state)
	var expected_import := int(
		expected_trade["nation_food_import"][0]
	)
	var expected_export := int(
		expected_trade["nation_food_export"][0]
	)
	_check(
		nation.last_trade_food_import == expected_import
			and nation.last_trade_food_export == expected_export,
		"setup_snapshot/trade_snapshot_matches_trade_network",
		"imp_actual=%d imp_exp=%d exp_actual=%d exp_exp=%d" % [
			nation.last_trade_food_import,
			expected_import,
			nation.last_trade_food_export,
			expected_export
		]
	)

	var expected_balance := (
		nation.last_food_estimated_production
		- nation.last_food_estimated_consumption
		+ expected_import
		- expected_export
	)
	_check(
		nation.last_food_estimated_balance == expected_balance,
		"setup_snapshot/balance_equals_prod_minus_cons_plus_net_trade",
		"actual=%d expected=%d prod=%d cons=%d imp=%d exp=%d" % [
			nation.last_food_estimated_balance,
			expected_balance,
			nation.last_food_estimated_production,
			nation.last_food_estimated_consumption,
			expected_import,
			expected_export
		]
	)

	_check(
		state.trade_routes.size() == int(expected_trade.get("routes", []).size()),
		"setup_snapshot/trade_routes_count_matches_forecast",
		"actual_routes=%d expected_routes=%d" % [
			state.trade_routes.size(),
			int(expected_trade.get("routes", []).size())
		]
	)

	_check(
		state.trade_revision >= 1,
		"setup_snapshot/trade_revision_advanced_after_setup",
		"trade_revision=%d" % state.trade_revision
	)

	var expected_routes: Array = expected_trade.get("routes", [])
	for i in range(min(state.trade_routes.size(), expected_routes.size())):
		var actual_route: Dictionary = state.trade_routes[i]
		var expected_route: Dictionary = expected_routes[i]
		_check(
			int(actual_route.get("nation_a", -1))
				== int(expected_route.get("nation_a", -1))
				and int(actual_route.get("nation_b", -1))
					== int(expected_route.get("nation_b", -1))
				and int(actual_route.get("food_transfer", -1))
					== int(expected_route.get("food_transfer", -1))
				and int(actual_route.get("food_source_city", -1))
					== int(expected_route.get("food_source_city", -1))
				and int(actual_route.get("food_destination_city", -1))
					== int(expected_route.get("food_destination_city", -1)),
			"setup_snapshot/trade_route_field_matches_forecast",
			"route_idx=%d actual=%s expected=%s" % [
				i, str(actual_route), str(expected_route)
			]
		)

	sim.free()


func _test_setup_trade_snapshot_two_nation_consistency() -> void:
	var state := _make_trade_pair_state()

	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)

	var expected_trade := TradeNetwork.build(state)
	var expected_routes: Array = expected_trade.get("routes", [])

	_check(
		state.trade_routes.size() == expected_routes.size(),
		"setup_two_nation/trade_routes_count_matches_trade_network",
		"actual=%d expected=%d" % [
			state.trade_routes.size(), expected_routes.size()
		]
	)

	_check(
		state.trade_revision >= 1,
		"setup_two_nation/trade_revision_advanced_after_setup",
		"trade_revision=%d" % state.trade_revision
	)

	var expected_import_0 := int(expected_trade["nation_food_import"][0])
	var expected_export_0 := int(expected_trade["nation_food_export"][0])
	var expected_import_1 := int(expected_trade["nation_food_import"][1])
	var expected_export_1 := int(expected_trade["nation_food_export"][1])

	var nation_0 := state.nations[0]
	var nation_1 := state.nations[1]
	_check(
		nation_0.last_trade_food_import == expected_import_0
			and nation_0.last_trade_food_export == expected_export_0
			and nation_1.last_trade_food_import == expected_import_1
			and nation_1.last_trade_food_export == expected_export_1,
		"setup_two_nation/nation_trade_fields_match_trade_network",
		"n0_imp=%d n0_exp=%d exp_imp=%d exp_exp=%d n1_imp=%d n1_exp=%d exp_imp=%d exp_exp=%d" % [
			nation_0.last_trade_food_import,
			expected_import_0,
			nation_0.last_trade_food_export,
			expected_export_0,
			nation_1.last_trade_food_import,
			expected_import_1,
			nation_1.last_trade_food_export,
			expected_export_1
		]
	)

	for i in range(min(state.trade_routes.size(), expected_routes.size())):
		var actual_route: Dictionary = state.trade_routes[i]
		var expected_route: Dictionary = expected_routes[i]
		_check(
			int(actual_route.get("nation_a", -1))
				== int(expected_route.get("nation_a", -1))
				and int(actual_route.get("nation_b", -1))
					== int(expected_route.get("nation_b", -1))
				and int(actual_route.get("food_transfer", -1))
					== int(expected_route.get("food_transfer", -1))
				and int(actual_route.get("food_source_city", -1))
					== int(expected_route.get("food_source_city", -1))
				and int(actual_route.get("food_destination_city", -1))
					== int(expected_route.get("food_destination_city", -1)),
			"setup_two_nation/trade_route_field_matches_trade_network",
			"route_idx=%d actual=%s expected=%s" % [
				i, str(actual_route), str(expected_route)
			]
		)

	sim.free()


func _test_monthly_production_rounds_after_nation_sum() -> void:
	var state := _make_rounding_fixture_state()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	state.day = Simulation.DAYS_PER_MONTH
	state.month = 1
	sim._resolve_economy()
	var nation := state.nations[0]
	_check(
		nation.last_food_estimated_production == 2,
		"rounding/nation_sum_then_divide_by_six",
		"half_year_total=9 actual=%d" % nation.last_food_estimated_production
	)
	var sections := MapRenderer.nation_detail_sections(state, 0)
	var food_line := _section_line(sections, "粮食与贸易", 0)
	_check(
		food_line.find("月产(预计) 2") >= 0
			and food_line.find("月需(预计) 0") >= 0,
		"rounding/ui_static_entry_uses_rounded_total",
		food_line
	)
	sim.free()


func _make_single_nation_state() -> GameState:
	var state := GameState.new()
	state.world_seed = 9988
	state.map_aspect_ratio = 1.0
	var nation := Nation.new()
	nation.id = 0
	nation.alive = true
	nation.trade_policy = TradeNetwork.BALANCED
	nation.ruler_archetype = RulerProfile.BALANCED
	nation.treasury_gold = 100
	state.nations.append(nation)
	var city := City.new()
	city.id = 0
	city.owner_nation = 0
	city.map_position = Vector2(0.5, 0.5)
	city.gold_per_month = 12
	city.food_per_half_year = 120
	city.food_storage = 30
	city.has_warehouse = true
	city.is_capital = true
	city.loyalty = RebellionSystem.LOYALTY_DEFAULT
	city.loyalty_target_nation = 0
	state.cities.append(city)
	state.adjacency[0] = [] as Array[int]
	state.nations[0].capital_city_id = 0
	state.nations[0].warehouse_city_ids = [0] as Array[int]
	state.recognized_city_owners = PackedInt32Array([0])
	state.refresh_derived()
	return state


func _make_trade_pair_state() -> GameState:
	var state := GameState.new()
	state.world_seed = 24680
	state.map_aspect_ratio = 1.0
	for nation_id in range(2):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.trade_policy = TradeNetwork.BALANCED
		nation.treasury_gold = 1000
		nation.last_food_demand = 1
		nation.ruler_archetype = RulerProfile.BALANCED
		state.nations.append(nation)

	var exporter := City.new()
	exporter.id = 0
	exporter.owner_nation = 0
	exporter.map_position = Vector2(0.2, 0.5)
	exporter.gold_per_month = 20
	exporter.food_per_half_year = 600
	exporter.food_storage = 100
	exporter.has_warehouse = true
	exporter.is_capital = true
	exporter.loyalty = RebellionSystem.LOYALTY_DEFAULT
	exporter.loyalty_target_nation = 0
	state.cities.append(exporter)
	state.adjacency[0] = [] as Array[int]

	var importer := City.new()
	importer.id = 1
	importer.owner_nation = 1
	importer.map_position = Vector2(0.8, 0.5)
	importer.gold_per_month = 18
	importer.food_per_half_year = 0
	importer.food_storage = 0
	importer.has_warehouse = true
	importer.is_capital = true
	importer.loyalty = RebellionSystem.LOYALTY_DEFAULT
	importer.loyalty_target_nation = 1
	state.cities.append(importer)
	state.adjacency[1] = [] as Array[int]

	var edge := Edge.new()
	edge.city_a = 0
	edge.city_b = 1
	edge.max_manpower = 20000
	edge.base_max_manpower = 20000
	edge.distance = 2
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(0, 1)] = edge
	(state.adjacency[0] as Array[int]).append(1)
	(state.adjacency[1] as Array[int]).append(0)

	for nation_id in range(2):
		state.nations[nation_id].capital_city_id = nation_id
		state.nations[nation_id].warehouse_city_ids = [nation_id] as Array[int]
	state.recognized_city_owners = PackedInt32Array([0, 1])
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	state.refresh_derived()
	return state


func _make_rounding_fixture_state() -> GameState:
	var state := GameState.new()
	state.world_seed = 13579
	state.map_aspect_ratio = 1.0
	var nation := Nation.new()
	nation.id = 0
	nation.alive = true
	nation.trade_policy = TradeNetwork.BALANCED
	nation.treasury_gold = 100
	nation.last_food_demand = 0
	nation.ruler_archetype = RulerProfile.BALANCED
	state.nations.append(nation)
	for city_index in range(2):
		var city := City.new()
		city.id = city_index
		city.owner_nation = 0
		city.map_position = Vector2(0.3 + 0.3 * city_index, 0.5)
		city.gold_per_month = 0
		city.food_per_half_year = 4 if city_index == 0 else 5
		city.food_storage = 20 if city_index == 0 else 0
		city.has_warehouse = city_index == 0
		city.is_capital = city_index == 0
		city.loyalty = RebellionSystem.LOYALTY_DEFAULT
		city.loyalty_target_nation = 0
		state.cities.append(city)
		state.adjacency[city.id] = [] as Array[int]
	state.nations[0].capital_city_id = 0
	state.nations[0].warehouse_city_ids = [0] as Array[int]
	state.recognized_city_owners = PackedInt32Array([0, 0])
	var edge := Edge.new()
	edge.city_a = 0
	edge.city_b = 1
	edge.max_manpower = 20000
	edge.base_max_manpower = 20000
	edge.distance = 1
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(0, 1)] = edge
	(state.adjacency[0] as Array[int]).append(1)
	(state.adjacency[1] as Array[int]).append(0)
	state.refresh_derived()
	return state


func _section_line(
	sections: Array[Dictionary],
	title: String,
	line_index: int
) -> String:
	for section in sections:
		if str(section.get("title", "")) != title:
			continue
		var lines: Array = section.get("lines", [])
		if line_index < 0 or line_index >= lines.size():
			return ""
		return str(lines[line_index])
	return ""


func _signed_or_zero(value: int) -> String:
	if value > 0:
		return "+%d" % value
	if value < 0:
		return "%d" % value
	return "0"
