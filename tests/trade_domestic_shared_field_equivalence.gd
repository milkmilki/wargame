extends SceneTree
## 国内贸易共享 field 等价守卫。
## Godot --headless --path . --script res://tests/trade_domestic_shared_field_equivalence.gd

const SEEDS: Array[int] = [12345, 24680, 97531, 86420, 13579]
const SCENARIOS: Array[String] = [
	"baseline",
	"siege",
	"capacity",
	"enemy_occupied",
	"tie",
]

var _checks := 0
var _failures: Array[String] = []
var _legacy_context_builds := 0
var _optimized_context_builds := 0
var _legacy_field_builds := 0
var _optimized_field_builds := 0
var _legacy_route_queries := 0
var _optimized_route_queries := 0
var _legacy_derive_calls := 0
var _optimized_derive_calls := 0
var _status_counts := {
	"ACTIVE": 0,
	"REROUTED": 0,
	"BLOCKED": 0,
}
var _obstruction_reason_counts := {}
var _tie_validated := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for seed in SEEDS:
		for scenario in SCENARIOS:
			_assert_equivalent(_make_state(seed, scenario), seed, scenario)
	_run_deterministic_cases()
	_assert_direct_field_tie_cases()
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_domestic_shared_field_context_enabled(true)
	_check(
		_legacy_derive_calls > 0,
		"counters/legacy_derive_calls_exercised"
	)
	_check(
		_optimized_context_builds > 0,
		"counters/optimized_context_builds_exercised"
	)
	_check(
		_optimized_context_builds < _legacy_derive_calls,
		"counters/context_builds_below_legacy_derives",
		"optimized_context=%d legacy_derive=%d" % [
			_optimized_context_builds, _legacy_derive_calls,
		]
	)
	_check(
		_optimized_field_builds <= _legacy_field_builds,
		"counters/optimized_field_builds_not_higher",
		"optimized=%d legacy=%d" % [
			_optimized_field_builds, _legacy_field_builds,
		]
	)
	_check(
		_optimized_derive_calls == 0,
		"counters/optimized_uses_no_legacy_derive_calls",
		"optimized_derive=%d" % _optimized_derive_calls
	)
	_check(
		_optimized_route_queries == _legacy_derive_calls,
		"counters/optimized_route_queries_match_legacy_derives",
		"optimized_queries=%d legacy_derives=%d" % [
			_optimized_route_queries, _legacy_derive_calls,
		]
	)
	for status_name in ["ACTIVE", "REROUTED", "BLOCKED"]:
		_check(
			int(_status_counts[status_name]) > 0,
			"coverage/status_%s_exercised" % status_name.to_lower()
		)
	for blocked_reason in ["capacity", "unreachable"]:
		_check(
			int(_obstruction_reason_counts.get(blocked_reason, 0)) > 0,
			"coverage/obstruction_reason_%s_exercised" % blocked_reason
		)
	_check(_tie_validated, "coverage/tie_fixture_validated")
	print("=== 国内贸易共享field等价校验 ===")
	print("context_builds legacy=%d optimized=%d" % [
		_legacy_context_builds, _optimized_context_builds,
	])
	print("field_builds legacy=%d optimized=%d" % [
		_legacy_field_builds, _optimized_field_builds,
	])
	print("route_queries legacy=%d optimized=%d legacy_derive=%d optimized_derive=%d" % [
		_legacy_route_queries, _optimized_route_queries,
		_legacy_derive_calls, _optimized_derive_calls,
	])
	print("status_counts active=%d rerouted=%d blocked=%d" % [
		int(_status_counts["ACTIVE"]),
		int(_status_counts["REROUTED"]),
		int(_status_counts["BLOCKED"]),
	])
	print("obstruction_reasons siege=%d capacity=%d enemy_occupied_edge=%d unreachable=%d" % [
		int(_obstruction_reason_counts.get("siege", 0)),
		int(_obstruction_reason_counts.get("capacity", 0)),
		int(_obstruction_reason_counts.get("enemy_occupied_edge", 0)),
		int(_obstruction_reason_counts.get("unreachable", 0)),
	])
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TRADE_DOMESTIC_SHARED_FIELD_EQUIVALENT")
		quit(0)
		return
	for failure in _failures:
		push_error("TRADE_DOMESTIC_SHARED_FIELD_FAIL: " + failure)
	print("TRADE_DOMESTIC_SHARED_FIELD_DIVERGED")
	quit(1)


func _assert_equivalent(
	state: GameState, seed: int, scenario: String
) -> void:
	var label := "%s/seed_%d" % [scenario, seed]
	_assert_equivalent_case(state, label, scenario)


func _assert_equivalent_case(
	state: GameState, label: String, scenario: String
) -> void:
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_domestic_shared_field_context_enabled(false)
	var legacy_structure := TradeNetwork.build_structure(state, true)
	var legacy_structure_stats := TradeNetwork.connectivity_prefilter_counters()
	if scenario.begins_with("deterministic_"):
		_validate_deterministic_legacy(
			state, legacy_structure, label, scenario
		)
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_domestic_shared_field_context_enabled(true)
	var optimized_structure := TradeNetwork.build_structure(state, true)
	var optimized_structure_stats := TradeNetwork.connectivity_prefilter_counters()
	_check(
		optimized_structure == legacy_structure,
		label + "/build_structure_exact"
	)
	_check(
		not bool(legacy_structure_stats["domestic_shared_field_context_enabled"])
			and bool(optimized_structure_stats["domestic_shared_field_context_enabled"]),
		label + "/structure_toggle_effective",
		"legacy=%s optimized=%s" % [
			str(legacy_structure_stats["domestic_shared_field_context_enabled"]),
			str(optimized_structure_stats["domestic_shared_field_context_enabled"]),
		]
	)
	_check_routes_equal(
		legacy_structure["routes"], optimized_structure["routes"],
		label + "/route_fields"
	)
	_accumulate_stats(legacy_structure_stats, optimized_structure_stats)

	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_domestic_shared_field_context_enabled(false)
	var legacy_result := TradeNetwork.build(state, true)
	var legacy_build_stats := TradeNetwork.connectivity_prefilter_counters()
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_domestic_shared_field_context_enabled(true)
	var optimized_result := TradeNetwork.build(state, true)
	var optimized_build_stats := TradeNetwork.connectivity_prefilter_counters()
	_check(
		optimized_result == legacy_result,
		label + "/build_exact"
	)
	_check(
		not bool(legacy_build_stats["domestic_shared_field_context_enabled"])
			and bool(optimized_build_stats["domestic_shared_field_context_enabled"]),
		label + "/build_toggle_effective",
		"legacy=%s optimized=%s" % [
			str(legacy_build_stats["domestic_shared_field_context_enabled"]),
			str(optimized_build_stats["domestic_shared_field_context_enabled"]),
		]
	)
	_accumulate_stats(legacy_build_stats, optimized_build_stats)
	_check(
		int(legacy_structure_stats["domestic_legacy_derive_calls"]) > 0
			or int(legacy_build_stats["domestic_legacy_derive_calls"]) > 0,
		label + "/legacy_domestic_exercised"
	)
	_check(
		int(optimized_structure_stats["domestic_context_builds"]) > 0
			or int(optimized_build_stats["domestic_context_builds"]) > 0,
		label + "/optimized_domestic_exercised"
	)
	_record_coverage(legacy_structure, label, scenario)
	TradeNetwork.set_domestic_shared_field_context_enabled(true)


func _check_routes_equal(
	legacy_routes: Array, optimized_routes: Array, label: String
) -> void:
	_check(
		legacy_routes.size() == optimized_routes.size(),
		label + "/same_route_count",
		"legacy=%d optimized=%d" % [
			legacy_routes.size(), optimized_routes.size(),
		]
	)
	var count := mini(legacy_routes.size(), optimized_routes.size())
	for route_index in range(count):
		var legacy_route := legacy_routes[route_index] as Dictionary
		var optimized_route := optimized_routes[route_index] as Dictionary
		for key in [
			"id",
			"international",
			"kind",
			"nation_a",
			"nation_b",
			"source",
			"destination",
			"source_city",
			"destination_city",
			"city_path",
			"preferred_city_path",
			"preferred_transport_cost",
			"edge_keys",
			"bottleneck",
			"bottleneck_capacity",
			"transport_cost",
			"status",
			"blocked_reason",
			"blocked_city",
			"blocked_edge_key",
			"uses_water",
			"preferred_uses_water",
			"dock_count",
		]:
			_check(
				legacy_route.get(key) == optimized_route.get(key),
				"%s/route_%d/%s" % [label, route_index, key],
				"legacy=%s optimized=%s" % [
					str(legacy_route.get(key)),
					str(optimized_route.get(key)),
				]
			)


func _accumulate_stats(legacy: Dictionary, optimized: Dictionary) -> void:
	_legacy_context_builds += int(legacy["domestic_context_builds"])
	_optimized_context_builds += int(optimized["domestic_context_builds"])
	_legacy_field_builds += int(legacy["domestic_field_builds"])
	_optimized_field_builds += int(optimized["domestic_field_builds"])
	_legacy_route_queries += int(legacy["domestic_route_queries"])
	_optimized_route_queries += int(optimized["domestic_route_queries"])
	_legacy_derive_calls += int(legacy["domestic_legacy_derive_calls"])
	_optimized_derive_calls += int(optimized["domestic_legacy_derive_calls"])


func _record_coverage(
	structure: Dictionary, label: String, scenario: String
) -> void:
	var routes: Array = structure["routes"]
	var domestic_routes: Array[Dictionary] = []
	for route_value in routes:
		var route := route_value as Dictionary
		if not bool(route.get("international", true)):
			domestic_routes.append(route)
			var reason := str(route.get("blocked_reason", ""))
			if not reason.is_empty():
				_obstruction_reason_counts[reason] = int(
					_obstruction_reason_counts.get(reason, 0)
				) + 1
			match int(route.get("status", -1)):
				TradeNetwork.ACTIVE:
					_status_counts["ACTIVE"] = int(_status_counts["ACTIVE"]) + 1
				TradeNetwork.REROUTED:
					_status_counts["REROUTED"] = int(_status_counts["REROUTED"]) + 1
				TradeNetwork.BLOCKED:
					_status_counts["BLOCKED"] = int(_status_counts["BLOCKED"]) + 1
	_check(
		not domestic_routes.is_empty(),
		label + "/domestic_routes_present"
	)
	match scenario:
		"baseline", "tie", "deterministic_active_direct":
			_check(
				_has_status(domestic_routes, TradeNetwork.ACTIVE),
				label + "/hits_active"
			)
		"deterministic_rerouted_siege", "deterministic_blocked_siege", "deterministic_blocked_enemy_occupied":
			_check(
				_has_status(domestic_routes, TradeNetwork.ACTIVE),
				label + "/war_events_keep_route_active"
			)
		"deterministic_blocked_capacity":
			_check(
				_has_blocked_reason(domestic_routes, "capacity"),
				label + "/blocked_capacity_hits_reason"
			)
		"deterministic_blocked_unreachable":
			_check(
				_has_blocked_reason(domestic_routes, "unreachable"),
				label + "/blocked_unreachable_hits_reason"
			)


func _has_status(routes: Array[Dictionary], status: int) -> bool:
	for route in routes:
		if int(route.get("status", -1)) == status:
			return true
	return false


func _has_blocked_reason(routes: Array[Dictionary], reason: String) -> bool:
	for route in routes:
		if (
			int(route.get("status", -1)) == TradeNetwork.BLOCKED
			and str(route.get("blocked_reason", "")) == reason
		):
			return true
	return false


func _run_deterministic_cases() -> void:
	_assert_equivalent_case(
		_make_deterministic_active_direct_state(),
		"deterministic/active_direct",
		"deterministic_active_direct"
	)
	_assert_equivalent_case(
		_make_deterministic_rerouted_siege_state(),
		"deterministic/rerouted_siege",
		"deterministic_rerouted_siege"
	)
	_assert_equivalent_case(
		_make_deterministic_blocked_siege_state(),
		"deterministic/blocked_siege",
		"deterministic_blocked_siege"
	)
	_assert_equivalent_case(
		_make_deterministic_blocked_capacity_state(),
		"deterministic/blocked_capacity",
		"deterministic_blocked_capacity"
	)
	_assert_equivalent_case(
		_make_deterministic_blocked_enemy_occupied_state(),
		"deterministic/blocked_enemy_occupied",
		"deterministic_blocked_enemy_occupied"
	)
	_assert_equivalent_case(
		_make_deterministic_blocked_unreachable_state(),
		"deterministic/blocked_unreachable",
		"deterministic_blocked_unreachable"
	)
	_assert_equivalent_case(
		_make_deterministic_route_limit_order_state(),
		"deterministic/route_limit_order",
		"deterministic_route_limit_order"
	)


func _validate_deterministic_legacy(
	state: GameState, structure: Dictionary, label: String, scenario: String
) -> void:
	match scenario:
		"deterministic_active_direct":
			var active_route := _find_domestic_route(structure["routes"], 0, 1)
			_check(not active_route.is_empty(), label + "/legacy_route_present")
			_check(
				int(active_route.get("status", -1)) == TradeNetwork.ACTIVE,
				label + "/legacy_status_active",
				"status=%s" % str(active_route.get("status"))
			)
			_check(
				active_route.get("city_path", []) == [0, 1],
				label + "/legacy_city_path_direct",
				"path=%s" % str(active_route.get("city_path"))
			)
			_check(
				active_route.get("preferred_city_path", []) == [0, 1],
				label + "/legacy_preferred_path_direct",
				"path=%s" % str(active_route.get("preferred_city_path"))
			)
		"deterministic_rerouted_siege":
			var rerouted := _find_domestic_route(structure["routes"], 0, 2)
			_check(not rerouted.is_empty(), label + "/legacy_route_present")
			_check(
				int(rerouted.get("status", -1)) == TradeNetwork.ACTIVE,
				label + "/siege_does_not_reroute",
				"status=%s" % str(rerouted.get("status"))
			)
			_check(
				rerouted.get("preferred_city_path", []) == [0, 1, 2],
				label + "/legacy_preferred_path_ideal",
				"path=%s" % str(rerouted.get("preferred_city_path"))
			)
			_check(
				rerouted.get("city_path", []) == [0, 1, 2],
				label + "/siege_keeps_preferred_path",
				"path=%s" % str(rerouted.get("city_path"))
			)
		"deterministic_blocked_siege":
			var blocked_siege := _find_domestic_route(structure["routes"], 0, 2)
			_check(not blocked_siege.is_empty(), label + "/legacy_route_present")
			_check(
				int(blocked_siege.get("status", -1)) == TradeNetwork.ACTIVE,
				label + "/siege_does_not_block",
				"status=%s" % str(blocked_siege.get("status"))
			)
			_check(
				blocked_siege.get("city_path", []) == [0, 1, 2],
				label + "/legacy_city_path_preferred_when_blocked",
				"path=%s" % str(blocked_siege.get("city_path"))
			)
			_check(
				str(blocked_siege.get("blocked_reason", "")).is_empty(),
				label + "/siege_has_no_blocked_reason",
				"reason=%s" % str(blocked_siege.get("blocked_reason"))
			)
		"deterministic_blocked_capacity":
			var blocked_capacity := _find_domestic_route(structure["routes"], 0, 2)
			var capacity_edge_key := GameState.edge_key(1, 2)
			_check(not blocked_capacity.is_empty(), label + "/legacy_route_present")
			_check(
				int(blocked_capacity.get("status", -1)) == TradeNetwork.BLOCKED,
				label + "/legacy_status_blocked",
				"status=%s" % str(blocked_capacity.get("status"))
			)
			_check(
				str(blocked_capacity.get("blocked_reason", "")) == "capacity",
				label + "/legacy_blocked_reason_capacity",
				"reason=%s" % str(blocked_capacity.get("blocked_reason"))
			)
			_check(
				int(blocked_capacity.get("blocked_edge_key", -1)) == capacity_edge_key,
				label + "/legacy_capacity_edge_key",
				"edge=%s" % str(blocked_capacity.get("blocked_edge_key"))
			)
		"deterministic_blocked_enemy_occupied":
			var blocked_enemy := _find_domestic_route(structure["routes"], 0, 2)
			_check(not blocked_enemy.is_empty(), label + "/legacy_route_present")
			_check(
				int(blocked_enemy.get("status", -1)) == TradeNetwork.ACTIVE,
				label + "/enemy_occupancy_does_not_block",
				"status=%s" % str(blocked_enemy.get("status"))
			)
			_check(
				blocked_enemy.get("city_path", []) == [0, 1, 2]
					and str(blocked_enemy.get("blocked_reason", "")).is_empty(),
				label + "/enemy_occupancy_keeps_path",
				"route=%s" % str(blocked_enemy)
			)
		"deterministic_blocked_unreachable":
			var unreachable := _find_domestic_route(structure["routes"], 0, 2)
			_check(not unreachable.is_empty(), label + "/legacy_route_present")
			_check(
				int(unreachable.get("status", -1)) == TradeNetwork.BLOCKED,
				label + "/legacy_status_blocked",
				"status=%s" % str(unreachable.get("status"))
			)
			_check(
				(unreachable.get("preferred_city_path", []) as Array).is_empty(),
				label + "/legacy_preferred_path_empty",
				"path=%s" % str(unreachable.get("preferred_city_path"))
			)
			_check(
				(unreachable.get("city_path", []) as Array).is_empty(),
				label + "/legacy_city_path_empty",
				"path=%s" % str(unreachable.get("city_path"))
			)
			_check(
				str(unreachable.get("blocked_reason", "")) == "unreachable",
				label + "/legacy_blocked_reason_unreachable",
				"reason=%s" % str(unreachable.get("blocked_reason"))
			)
		"deterministic_route_limit_order":
			var domestic_routes := _domestic_routes_for_nation(
				structure["routes"], 0
			)
			var destinations: Array[int] = []
			for route in domestic_routes:
				destinations.append(int(route.get("destination", -1)))
			_check(
				domestic_routes.size() == TradeNetwork.MAX_DOMESTIC_ROUTES_PER_NATION,
				label + "/legacy_route_limit_respected",
				"count=%d" % domestic_routes.size()
			)
			_check(
				destinations == [1, 2, 3, 4],
				label + "/legacy_route_order_respected",
				"destinations=%s" % str(destinations)
			)
			_check(
				_find_domestic_route(structure["routes"], 0, 5).is_empty(),
				label + "/legacy_fifth_destination_trimmed"
			)


func _find_domestic_route(
	routes: Array, nation_id: int, destination: int
) -> Dictionary:
	for route_value in routes:
		var route := route_value as Dictionary
		if (
			not bool(route.get("international", true))
			and int(route.get("nation_a", -1)) == nation_id
			and int(route.get("destination", -1)) == destination
		):
			return route
	return {}


func _domestic_routes_for_nation(routes: Array, nation_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route_value in routes:
		var route := route_value as Dictionary
		if (
			not bool(route.get("international", true))
			and int(route.get("nation_a", -1)) == nation_id
		):
			result.append(route)
	return result


func _assert_direct_field_tie_cases() -> void:
	var endpoint_state := _make_deterministic_endpoint_tie_state()
	var endpoint_graph := TradeNetwork._build_graph(endpoint_state)
	var endpoint_cache := {}
	var endpoint_allowed := TradeNetwork._ideal_city_mask(endpoint_state)
	var endpoint_field := TradeNetwork._get_domestic_preferred_endpoint_field(
		endpoint_state,
		endpoint_graph,
		[0] as Array[int],
		endpoint_allowed,
		false,
		{},
		{},
		endpoint_cache
	)
	var endpoint_selection := TradeNetwork._select_preferred_endpoints_from_field(
		endpoint_state,
		[0] as Array[int],
		[1, 2] as Array[int],
		endpoint_field
	)
	_check(
		int(endpoint_selection["source"]) == 0
			and int(endpoint_selection["destination"]) == 1,
		"deterministic/direct_field_endpoint_tie_prefers_lower_destination",
		"selection=%s" % str(endpoint_selection)
	)
	_check(
		endpoint_selection["path"] == [0, 1],
		"deterministic/direct_field_endpoint_tie_path",
		"path=%s" % str(endpoint_selection["path"])
	)

	var diamond_state := _make_deterministic_diamond_tie_state()
	var diamond_graph := TradeNetwork._build_graph(diamond_state)
	var diamond_cache := {}
	var diamond_allowed := TradeNetwork._ideal_city_mask(diamond_state)
	var diamond_field := TradeNetwork._get_domestic_preferred_endpoint_field(
		diamond_state,
		diamond_graph,
		[0] as Array[int],
		diamond_allowed,
		false,
		{},
		{},
		diamond_cache
	)
	var diamond_selection := TradeNetwork._select_preferred_endpoints_from_field(
		diamond_state,
		[0] as Array[int],
		[3] as Array[int],
		diamond_field
	)
	_check(
		diamond_selection["path"] == [0, 1, 3],
		"deterministic/direct_field_diamond_tie_prefers_lower_prev_city",
		"path=%s" % str(diamond_selection["path"])
	)
	_check(
		int(diamond_selection["destination"]) == 3,
		"deterministic/direct_field_diamond_destination",
		"selection=%s" % str(diamond_selection)
	)
	_tie_validated = true


func _make_deterministic_active_direct_state() -> GameState:
	var state := _make_small_trade_state(2)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 800, 100)
	_add_trade_city(state, 0, Vector2(0.28, 0.50), 4, 420, 0)
	_add_trade_city(state, 1, Vector2(0.72, 0.50), 0, 760, 90)
	_add_trade_city(state, 1, Vector2(0.90, 0.50), 3, 380, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 2, 3, 20000, 1)
	return _finalize_trade_state(state)


func _make_deterministic_rerouted_siege_state() -> GameState:
	var state := _make_small_trade_state(2)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.30, 0.50), 4, 420, 0)
	_add_trade_city(state, 0, Vector2(0.50, 0.50), 3, 520, 0)
	_add_trade_city(state, 0, Vector2(0.30, 0.72), 2, 260, 0)
	_add_trade_city(state, 1, Vector2(0.78, 0.48), 0, 760, 100)
	_add_trade_city(state, 1, Vector2(0.92, 0.48), 2, 300, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 1, 2, 20000, 1)
	_add_trade_edge(state, 0, 3, 20000, 2)
	_add_trade_edge(state, 3, 2, 20000, 1)
	_add_trade_edge(state, 4, 5, 20000, 1)
	_add_siege_to_city(state, 1)
	return _finalize_trade_state(state)


func _make_deterministic_blocked_siege_state() -> GameState:
	var state := _make_small_trade_state(2)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.30, 0.50), 4, 420, 0)
	_add_trade_city(state, 0, Vector2(0.50, 0.50), 3, 520, 0)
	_add_trade_city(state, 1, Vector2(0.78, 0.48), 0, 760, 100)
	_add_trade_city(state, 1, Vector2(0.92, 0.48), 2, 300, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 1, 2, 20000, 1)
	_add_trade_edge(state, 3, 4, 20000, 1)
	_add_siege_to_city(state, 1)
	return _finalize_trade_state(state)


func _make_deterministic_blocked_capacity_state() -> GameState:
	var state := _make_small_trade_state(2)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.30, 0.50), 4, 420, 0)
	_add_trade_city(state, 0, Vector2(0.50, 0.50), 3, 520, 0)
	_add_trade_city(state, 1, Vector2(0.78, 0.48), 0, 760, 100)
	_add_trade_city(state, 1, Vector2(0.92, 0.48), 2, 300, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 1, 2, 0, 1)
	_add_trade_edge(state, 3, 4, 20000, 1)
	return _finalize_trade_state(state)


func _make_deterministic_blocked_enemy_occupied_state() -> GameState:
	var state := _make_small_trade_state(2)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.30, 0.50), 4, 420, 0)
	_add_trade_city(state, 0, Vector2(0.50, 0.50), 3, 520, 0)
	_add_trade_city(state, 1, Vector2(0.78, 0.48), 0, 760, 100)
	_add_trade_city(state, 1, Vector2(0.92, 0.48), 2, 300, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 1, 2, 20000, 1)
	_add_trade_edge(state, 3, 4, 20000, 1)
	state = _finalize_trade_state(state)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	_add_edge_army(state, 1, 1, 2, 2000)
	state.refresh_derived()
	return state


func _make_deterministic_blocked_unreachable_state() -> GameState:
	var state := _make_small_trade_state(2)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.30, 0.50), 4, 420, 0)
	_add_trade_city(state, 0, Vector2(0.60, 0.50), 3, 520, 0)
	_add_trade_city(state, 1, Vector2(0.78, 0.48), 0, 760, 100)
	_add_trade_city(state, 1, Vector2(0.92, 0.48), 2, 300, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 3, 4, 20000, 1)
	return _finalize_trade_state(state)


func _make_deterministic_route_limit_order_state() -> GameState:
	var state := _make_small_trade_state(2)
	_add_trade_city(state, 0, Vector2(0.08, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.22, 0.30), 8, 620, 0)
	_add_trade_city(state, 0, Vector2(0.24, 0.70), 7, 560, 0)
	_add_trade_city(state, 0, Vector2(0.36, 0.32), 6, 500, 0)
	_add_trade_city(state, 0, Vector2(0.38, 0.68), 5, 440, 0)
	_add_trade_city(state, 0, Vector2(0.52, 0.50), 1, 120, 0)
	_add_trade_city(state, 1, Vector2(0.78, 0.48), 0, 760, 100)
	_add_trade_city(state, 1, Vector2(0.92, 0.48), 2, 300, 0)
	_finalize_trade_city_roles(state)
	for destination in [1, 2, 3, 4, 5]:
		_add_trade_edge(state, 0, destination, 20000, 1)
	for pair in [[6, 7]]:
		_add_trade_edge(state, pair[0], pair[1], 20000, 1)
	return _finalize_trade_state(state)


func _make_deterministic_endpoint_tie_state() -> GameState:
	var state := _make_small_trade_state(1)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.30, 0.35), 4, 420, 0)
	_add_trade_city(state, 0, Vector2(0.30, 0.65), 3, 520, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 0, 2, 20000, 1)
	return _finalize_trade_state(state)


func _make_deterministic_diamond_tie_state() -> GameState:
	var state := _make_small_trade_state(1)
	_add_trade_city(state, 0, Vector2(0.10, 0.50), 0, 900, 120)
	_add_trade_city(state, 0, Vector2(0.28, 0.35), 4, 420, 0)
	_add_trade_city(state, 0, Vector2(0.28, 0.65), 3, 400, 0)
	_add_trade_city(state, 0, Vector2(0.50, 0.50), 2, 520, 0)
	_finalize_trade_city_roles(state)
	_add_trade_edge(state, 0, 1, 20000, 1)
	_add_trade_edge(state, 1, 3, 20000, 1)
	_add_trade_edge(state, 0, 2, 20000, 1)
	_add_trade_edge(state, 2, 3, 20000, 1)
	return _finalize_trade_state(state)


func _make_small_trade_state(nation_count: int) -> GameState:
	var state := GameState.new()
	state.world_seed = 90817
	state.map_aspect_ratio = 1.0
	for nation_id in range(nation_count):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.trade_policy = TradeNetwork.BALANCED
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits = [] as Array[String]
		nation.treasury_gold = 1000
		nation.last_food_demand = 20
		state.nations.append(nation)
	return state


func _add_trade_city(
	state: GameState,
	owner: int,
	position: Vector2,
	gold: int,
	food: int,
	storage: int
) -> void:
	var city := City.new()
	city.id = state.cities.size()
	city.owner_nation = owner
	city.map_position = position
	city.gold_per_month = gold
	city.food_per_half_year = food
	city.food_storage = storage
	city.loyalty = RebellionSystem.LOYALTY_DEFAULT
	city.loyalty_target_nation = owner
	state.cities.append(city)
	state.adjacency[city.id] = [] as Array[int]


func _finalize_trade_city_roles(state: GameState) -> void:
	for nation in state.nations:
		var first_city := -1
		for city in state.cities:
			if city.owner_nation != nation.id:
				continue
			if first_city < 0:
				first_city = city.id
				city.is_capital = true
				city.has_warehouse = true
				nation.capital_city_id = city.id
				nation.warehouse_city_ids = [city.id] as Array[int]
				continue
			city.is_capital = false
			city.has_warehouse = false


func _add_trade_edge(
	state: GameState,
	a: int,
	b: int,
	capacity: int,
	distance: int,
	kind: int = Edge.Kind.LAND
) -> void:
	var edge := Edge.new()
	edge.city_a = mini(a, b)
	edge.city_b = maxi(a, b)
	edge.kind = kind
	edge.max_manpower = capacity
	edge.base_max_manpower = capacity
	edge.distance = distance
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(a, b)] = edge
	(state.adjacency[a] as Array[int]).append(b)
	(state.adjacency[b] as Array[int]).append(a)


func _add_siege_to_city(state: GameState, city_id: int) -> void:
	var battle := Battle.new()
	battle.id = state.battles.size()
	battle.kind = Battle.Kind.SIEGE
	battle.city = state.cities[city_id]
	battle.finished = false
	state.battles.append(battle)


func _add_edge_army(
	state: GameState,
	owner: int,
	from_city: int,
	to_city: int,
	size: int
) -> void:
	var army := Army.new()
	army.id = state.armies.size()
	army.owner_nation = owner
	army.size = size
	army.on_edge = true
	army.move_from = from_city
	army.move_to = to_city
	state.armies.append(army)


func _finalize_trade_state(state: GameState) -> GameState:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	state.refresh_derived()
	return state


func _make_state(seed: int, scenario: String) -> GameState:
	var state := GameState.new()
	state.generate_grid_world(seed)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	match scenario:
		"baseline":
			pass
		"siege":
			_add_domestic_siege(state, 0)
		"capacity":
			_cut_domestic_capital_edges(state, 0)
		"enemy_occupied":
			_add_domestic_enemy_occupied_edges(state, 0, 1)
		"tie":
			_make_equal_cost_tie(state, 0)
		_:
			_check(false, "unknown_scenario/" + scenario)
	return state


func _add_domestic_siege(state: GameState, nation_id: int) -> void:
	for city in state.cities:
		if city.owner_nation != nation_id or city.is_dock:
			continue
		if city.id == state.nations[nation_id].capital_city_id:
			continue
		var battle := state.new_battle(Battle.Kind.SIEGE)
		battle.city = city
		battle.finished = false
		return


func _cut_domestic_capital_edges(state: GameState, nation_id: int) -> void:
	var capital := state.nations[nation_id].capital_city_id
	for edge in state.edges:
		if edge.city_a == capital or edge.city_b == capital:
			edge.max_manpower = 0
			return


func _add_domestic_enemy_occupied_edges(
	state: GameState, nation_id: int, enemy_id: int
) -> void:
	state.set_diplomatic_relation(
		nation_id, enemy_id, GameState.DiplomaticRelation.WAR
	)
	var capital := state.nations[nation_id].capital_city_id
	for edge in state.edges:
		if edge.city_a != capital and edge.city_b != capital:
			continue
		var army := Army.new()
		army.id = state.armies.size()
		army.owner_nation = enemy_id
		army.size = 1
		army.on_edge = true
		army.move_from = edge.city_a
		army.move_to = edge.city_b
		state.armies.append(army)
		return


func _make_equal_cost_tie(state: GameState, nation_id: int) -> void:
	var capital := state.nations[nation_id].capital_city_id
	var same_owner: Array[int] = []
	for city in state.cities:
		if city.owner_nation == nation_id and city.id != capital and not city.is_dock:
			same_owner.append(city.id)
	if same_owner.size() < 2:
		return
	var left := same_owner[0]
	var right := same_owner[1]
	for edge in state.edges:
		if (
			(edge.city_a == capital and edge.city_b == left)
			or (edge.city_a == left and edge.city_b == capital)
			or (edge.city_a == capital and edge.city_b == right)
			or (edge.city_a == right and edge.city_b == capital)
		):
			edge.distance = 10
			edge.travel_time_multiplier = 1.0
			edge.danger = 0.0
			edge.supply_loss_multiplier = 0.0
			edge.max_manpower = maxi(edge.max_manpower, 1)
			edge.base_max_manpower = maxi(edge.base_max_manpower, 1)


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	var message := label
	if not detail.is_empty():
		message += " :: " + detail
	_failures.append(message)
