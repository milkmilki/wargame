extends SceneTree
## 国际贸易候选连通性预筛等价守卫。
## Godot --headless --path . --script res://tests/trade_connectivity_prefilter_equivalence.gd

const SEEDS: Array[int] = [12345, 24680, 97531, 86420, 13579]
const SCENARIOS: Array[String] = [
	"all_neutral",
	"single_war",
	"alliance_block",
	"multi_war",
	"closed_cut",
	"sieged_cut",
	"third_party_occupied_cut",
]

var _checks := 0
var _failures: Array[String] = []
var _direct_candidate_dijkstra_fields := 0
var _legacy_connectivity_legacy_bfs_searches := 0
var _union_candidate_dijkstra_fields := 0
var _union_connectivity_queries := 0
var _union_connectivity_union_graph_builds := 0
var _union_connectivity_rejections := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for seed in SEEDS:
		for scenario in SCENARIOS:
			_assert_equivalent(_make_state(seed, scenario), seed, scenario)
	_assert_direct_union_cache_guards()
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(true)
	_check(
		_direct_candidate_dijkstra_fields > 0,
		"counters/direct_builds_candidate_dijkstra_fields"
	)
	_check(
		_union_candidate_dijkstra_fields < _direct_candidate_dijkstra_fields,
		"counters/union_reduces_candidate_dijkstra_fields",
		"direct=%d union=%d" % [
			_direct_candidate_dijkstra_fields, _union_candidate_dijkstra_fields,
		]
	)
	_check(
		_union_candidate_dijkstra_fields == 0,
		"counters/union_uses_no_candidate_dijkstra_fields",
		"union=%d" % _union_candidate_dijkstra_fields
	)
	_check(
		_union_connectivity_queries > 0
			and _union_connectivity_union_graph_builds > 0
			and _union_connectivity_union_graph_builds
				< _union_connectivity_queries,
		"counters/union_graph_builds_below_queries",
		"queries=%d builds=%d" % [
			_union_connectivity_queries,
			_union_connectivity_union_graph_builds,
		]
	)
	_check(
		_union_connectivity_union_graph_builds
			< _legacy_connectivity_legacy_bfs_searches,
		"counters/union_graph_builds_below_legacy_searches",
		"builds=%d legacy_searches=%d" % [
			_union_connectivity_union_graph_builds,
			_legacy_connectivity_legacy_bfs_searches,
		]
	)
	_check(
		_legacy_connectivity_legacy_bfs_searches > 0,
		"counters/legacy_bfs_exercised",
		"legacy_bfs=%d" % _legacy_connectivity_legacy_bfs_searches
	)
	_check(
		int(_union_candidate_dijkstra_fields) == 0,
		"counters/union_path_uses_no_candidate_dijkstra"
	)
	_check(
		_union_connectivity_rejections > 0,
		"counters/disconnected_candidates_rejected"
	)
	print("=== 贸易候选连通性预筛等价校验 ===")
	print("candidate_dijkstra_fields direct=%d union=%d" % [
		_direct_candidate_dijkstra_fields, _union_candidate_dijkstra_fields,
	])
	print("connectivity legacy_bfs=%d union_queries=%d union_graph_builds=%d rejections=%d" % [
		_legacy_connectivity_legacy_bfs_searches,
		_union_connectivity_queries,
		_union_connectivity_union_graph_builds,
		_union_connectivity_rejections,
	])
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TRADE_CONNECTIVITY_PREFILTER_EQUIVALENT")
		quit(0)
		return
	for failure in _failures:
		push_error("TRADE_CONNECTIVITY_PREFILTER_FAIL: " + failure)
	print("TRADE_CONNECTIVITY_PREFILTER_DIVERGED")
	quit(1)


func _assert_equivalent(
	state: GameState, seed: int, scenario: String
) -> void:
	var label := "%s/seed_%d" % [scenario, seed]
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(false)
	var direct_structure := TradeNetwork.build_structure(state, false)
	var direct_structure_stats := (
		TradeNetwork.connectivity_prefilter_counters()
	)
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(false)
	var legacy_structure := TradeNetwork.build_structure(state, true)
	var legacy_structure_stats := TradeNetwork.connectivity_prefilter_counters()
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(true)
	var union_structure := TradeNetwork.build_structure(state, true)
	var union_structure_stats := TradeNetwork.connectivity_prefilter_counters()
	_check(direct_structure == legacy_structure, label + "/direct_vs_legacy_structure_exact")
	_check(union_structure == legacy_structure, label + "/build_structure_exact")
	_accumulate_stats(
		direct_structure_stats, legacy_structure_stats, union_structure_stats
	)

	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(false)
	var direct_result := TradeNetwork.build(state, false)
	var direct_build_stats := TradeNetwork.connectivity_prefilter_counters()
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(false)
	var legacy_result := TradeNetwork.build(state, true)
	var legacy_build_stats := TradeNetwork.connectivity_prefilter_counters()
	TradeNetwork.reset_connectivity_prefilter_counters()
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(true)
	# 不传第二参，锁定公开 build() 默认启用 union-cache prefilter。
	var union_result := TradeNetwork.build(state)
	var union_build_stats := TradeNetwork.connectivity_prefilter_counters()
	_check(direct_result == legacy_result, label + "/direct_vs_legacy_build_exact")
	_check(union_result == legacy_result, label + "/build_exact")
	_accumulate_stats(
		direct_build_stats, legacy_build_stats, union_build_stats
	)
	_check(
		int(direct_structure_stats["candidate_dijkstra_field_builds"]) > 0
			and int(direct_build_stats["candidate_dijkstra_field_builds"]) > 0,
		label + "/direct_candidate_dijkstra_exercised"
	)
	_check(
		int(union_structure_stats["candidate_dijkstra_field_builds"]) == 0
			and int(union_build_stats["candidate_dijkstra_field_builds"]) == 0,
		label + "/union_candidate_dijkstra_eliminated"
	)
	_check(
		int(legacy_structure_stats["candidate_connectivity_legacy_bfs_searches"]) > 0
			and int(legacy_build_stats["candidate_connectivity_legacy_bfs_searches"]) > 0,
		label + "/legacy_bfs_exercised"
	)
	_check(
		int(union_structure_stats["candidate_connectivity_queries"]) > 0
			and int(union_build_stats["candidate_connectivity_queries"]) > 0,
		label + "/union_connectivity_exercised"
	)
	_check(
		int(union_structure_stats["candidate_connectivity_union_graph_builds"]) > 0
			and int(union_build_stats["candidate_connectivity_union_graph_builds"]) > 0,
		label + "/union_graph_builds_exercised"
	)
	_check(
		int(union_structure_stats["candidate_connectivity_union_graph_builds"])
			< int(union_structure_stats["candidate_connectivity_queries"])
			and int(union_build_stats["candidate_connectivity_union_graph_builds"])
				< int(union_build_stats["candidate_connectivity_queries"]),
		label + "/union_graph_builds_below_queries"
	)
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(true)


func _accumulate_stats(
	direct_stats: Dictionary,
	legacy_stats: Dictionary,
	union_stats: Dictionary
) -> void:
	_direct_candidate_dijkstra_fields += int(
		direct_stats["candidate_dijkstra_field_builds"]
	)
	_legacy_connectivity_legacy_bfs_searches += int(
		legacy_stats["candidate_connectivity_legacy_bfs_searches"]
	)
	_union_candidate_dijkstra_fields += int(
		union_stats["candidate_dijkstra_field_builds"]
	)
	_union_connectivity_queries += int(
		union_stats["candidate_connectivity_queries"]
	)
	_union_connectivity_union_graph_builds += int(
		union_stats["candidate_connectivity_union_graph_builds"]
	)
	_union_connectivity_rejections += int(
		union_stats["candidate_connectivity_rejections"]
	)


func _assert_direct_union_cache_guards() -> void:
	var state := _make_state(SEEDS[0], "all_neutral")
	var graph := TradeNetwork._build_graph(state)
	var cache := {}
	var sources_a := [0] as Array[int]
	var destinations_a := [1] as Array[int]
	var sources_b := [2] as Array[int]
	var destinations_b := [3] as Array[int]
	var same_city_sources := [0, -1, state.cities.size()] as Array[int]
	var same_city_destinations := [0] as Array[int]
	var invalid_sources := [-1, state.cities.size(), state.cities.size() + 17] as Array[int]
	var invalid_destinations := [-1, state.cities.size(), state.cities.size() + 23] as Array[int]
	var pair_a := Vector2i(0, 1)
	var pair_b := Vector2i(2, 3)
	TradeNetwork.reset_connectivity_prefilter_counters()
	var first_pair_connected := TradeNetwork._has_operational_connection_union(
		state, graph, sources_a, destinations_a, pair_a.x, pair_a.y,
		{}, [] as Array[Dictionary], cache
	)
	var second_pair_connected := TradeNetwork._has_operational_connection_union(
		state, graph, sources_b, destinations_b, pair_b.x, pair_b.y,
		{}, [] as Array[Dictionary], cache
	)
	var same_city_rejected := not TradeNetwork._has_operational_connection_union(
		state, graph, same_city_sources, same_city_destinations, pair_a.x, pair_a.y,
		{}, [] as Array[Dictionary], cache
	)
	var invalid_endpoint_rejected := not TradeNetwork._has_operational_connection_union(
		state, graph, invalid_sources, invalid_destinations, pair_b.x, pair_b.y,
		{}, [] as Array[Dictionary], cache
	)
	var stats := TradeNetwork.connectivity_prefilter_counters()
	_check(
		first_pair_connected and second_pair_connected,
		"direct_helper/union_connectivity_accepts_distinct_valid_endpoints"
	)
	_check(
		same_city_rejected and invalid_endpoint_rejected,
		"direct_helper/union_connectivity_rejects_same_city_and_invalid_endpoints"
	)
	_check(
		int(stats["candidate_connectivity_queries"]) == 4
			and int(stats["candidate_connectivity_union_graph_builds"]) == 1
			and int(stats["candidate_connectivity_rejections"]) == 2,
		"direct_helper/same_enemy_union_signature_reuses_one_context",
		"queries=%d builds=%d rejections=%d" % [
			int(stats["candidate_connectivity_queries"]),
			int(stats["candidate_connectivity_union_graph_builds"]),
			int(stats["candidate_connectivity_rejections"]),
		]
	)
	TradeNetwork.set_connectivity_prefilter_union_cache_enabled(true)


func _make_state(seed: int, scenario: String) -> GameState:
	var state := GameState.new()
	state.generate_grid_world(seed)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	match scenario:
		"all_neutral":
			pass
		"single_war":
			state.set_diplomatic_relation(
				0, 1, GameState.DiplomaticRelation.WAR
			)
		"alliance_block":
			state.set_diplomatic_relation(
				0, 2, GameState.DiplomaticRelation.ALLIED
			)
			state.set_diplomatic_relation(
				1, 3, GameState.DiplomaticRelation.ALLIED
			)
			state.set_diplomatic_relation(
				0, 1, GameState.DiplomaticRelation.WAR
			)
		"closed_cut":
			_check(
				_close_vertical_cut(state) == GameState.GRID,
				"closed_cut/seed_%d/covers_full_cut" % seed
			)
		"multi_war":
			for pair in [[0, 1], [0, 3], [2, 3], [1, 2]]:
				state.set_diplomatic_relation(
					pair[0], pair[1], GameState.DiplomaticRelation.WAR
				)
		"sieged_cut":
			_check(
				_add_sieged_column(state) == GameState.GRID,
				"sieged_cut/seed_%d/covers_full_column" % seed
			)
		"third_party_occupied_cut":
			for other in [0, 1, 3]:
				state.set_diplomatic_relation(
					2, other, GameState.DiplomaticRelation.WAR
				)
			_check(
				_add_enemy_occupied_cut(state, 2) == GameState.GRID,
				"enemy_occupied_cut/seed_%d/covers_full_cut" % seed
			)
		_:
			_check(false, "unknown_scenario/" + scenario)
	return state


func _close_vertical_cut(state: GameState) -> int:
	var changed := 0
	for edge in state.edges:
		if _crosses_vertical_cut(edge):
			edge.max_manpower = 0
			changed += 1
	return changed


func _add_sieged_column(state: GameState) -> int:
	var count := 0
	for city in state.cities:
		if city.coord.x != GameState.GRID / 2:
			continue
		var battle := state.new_battle(Battle.Kind.SIEGE)
		battle.city = city
		battle.finished = false
		count += 1
	return count


func _add_enemy_occupied_cut(state: GameState, owner: int) -> int:
	var count := 0
	for edge in state.edges:
		if not _crosses_vertical_cut(edge):
			continue
		var army := Army.new()
		army.id = state.armies.size()
		army.owner_nation = owner
		army.size = 1
		army.on_edge = true
		army.move_from = edge.city_a
		army.move_to = edge.city_b
		state.armies.append(army)
		count += 1
	return count


func _crosses_vertical_cut(edge: Edge) -> bool:
	var column_a := edge.city_a % GameState.GRID
	var column_b := edge.city_b % GameState.GRID
	return (
		mini(column_a, column_b) == GameState.GRID / 2 - 1
		and maxi(column_a, column_b) == GameState.GRID / 2
	)


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	var message := label
	if not detail.is_empty():
		message += " :: " + detail
	_failures.append(message)
