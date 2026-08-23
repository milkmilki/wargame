extends SceneTree
## 国际贸易候选连通性预筛等价守卫。
## Godot --headless --path . --script res://tests/trade_connectivity_prefilter_equivalence.gd

const SEEDS: Array[int] = [12345, 24680, 97531]
const SCENARIOS: Array[String] = [
	"peace", "war", "closed_cut", "sieged_cut",
	"enemy_occupied_cut",
]

var _checks := 0
var _failures: Array[String] = []
var _legacy_candidate_dijkstra_fields := 0
var _fast_candidate_dijkstra_fields := 0
var _fast_connectivity_queries := 0
var _fast_connectivity_searches := 0
var _fast_connectivity_rejections := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for seed in SEEDS:
		for scenario in SCENARIOS:
			_assert_equivalent(_make_state(seed, scenario), seed, scenario)
	TradeNetwork.reset_connectivity_prefilter_counters()
	_check(
		_legacy_candidate_dijkstra_fields > 0,
		"counters/legacy_builds_candidate_dijkstra_fields"
	)
	_check(
		_fast_candidate_dijkstra_fields < _legacy_candidate_dijkstra_fields,
		"counters/fast_reduces_candidate_dijkstra_fields",
		"legacy=%d fast=%d" % [
			_legacy_candidate_dijkstra_fields, _fast_candidate_dijkstra_fields,
		]
	)
	_check(
		_fast_candidate_dijkstra_fields == 0,
		"counters/fast_uses_no_candidate_dijkstra_fields",
		"fast=%d" % _fast_candidate_dijkstra_fields
	)
	_check(
		_fast_connectivity_queries > 0 and _fast_connectivity_searches > 0
			and _fast_connectivity_searches <= _fast_connectivity_queries,
		"counters/fast_uses_connectivity_search",
		"queries=%d searches=%d" % [
			_fast_connectivity_queries, _fast_connectivity_searches,
		]
	)
	_check(
		_fast_connectivity_rejections > 0,
		"counters/disconnected_candidates_rejected"
	)
	print("=== 贸易候选连通性预筛等价校验 ===")
	print("candidate_dijkstra_fields legacy=%d fast=%d" % [
		_legacy_candidate_dijkstra_fields, _fast_candidate_dijkstra_fields,
	])
	print("fast_connectivity queries=%d searches=%d rejections=%d" % [
		_fast_connectivity_queries, _fast_connectivity_searches,
		_fast_connectivity_rejections,
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
	var legacy_structure := TradeNetwork.build_structure(state, false)
	var legacy_structure_stats := TradeNetwork.connectivity_prefilter_counters()
	TradeNetwork.reset_connectivity_prefilter_counters()
	var fast_structure := TradeNetwork.build_structure(state, true)
	var fast_structure_stats := TradeNetwork.connectivity_prefilter_counters()
	_check(fast_structure == legacy_structure, label + "/build_structure_exact")
	_accumulate_stats(legacy_structure_stats, fast_structure_stats)

	TradeNetwork.reset_connectivity_prefilter_counters()
	var legacy_result := TradeNetwork.build(state, false)
	var legacy_build_stats := TradeNetwork.connectivity_prefilter_counters()
	TradeNetwork.reset_connectivity_prefilter_counters()
	# 不传第二参，锁定公开 build() 默认启用 fast prefilter。
	var fast_result := TradeNetwork.build(state)
	var fast_build_stats := TradeNetwork.connectivity_prefilter_counters()
	_check(fast_result == legacy_result, label + "/build_exact")
	_accumulate_stats(legacy_build_stats, fast_build_stats)
	_check(
		int(legacy_structure_stats["candidate_dijkstra_field_builds"]) > 0
			and int(legacy_build_stats["candidate_dijkstra_field_builds"]) > 0,
		label + "/legacy_candidate_dijkstra_exercised"
	)
	_check(
		int(fast_structure_stats["candidate_dijkstra_field_builds"]) == 0
			and int(fast_build_stats["candidate_dijkstra_field_builds"]) == 0,
		label + "/fast_candidate_dijkstra_eliminated"
	)
	_check(
		int(fast_structure_stats["candidate_connectivity_queries"]) > 0
			and int(fast_build_stats["candidate_connectivity_queries"]) > 0,
		label + "/fast_connectivity_exercised"
	)


func _accumulate_stats(legacy: Dictionary, fast: Dictionary) -> void:
	_legacy_candidate_dijkstra_fields += int(legacy["candidate_dijkstra_field_builds"])
	_fast_candidate_dijkstra_fields += int(fast["candidate_dijkstra_field_builds"])
	_fast_connectivity_queries += int(fast["candidate_connectivity_queries"])
	_fast_connectivity_searches += int(fast["candidate_connectivity_searches"])
	_fast_connectivity_rejections += int(
		fast["candidate_connectivity_rejections"]
	)


func _make_state(seed: int, scenario: String) -> GameState:
	var state := GameState.new()
	state.generate_grid_world(seed)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	match scenario:
		"peace":
			pass
		"war":
			state.set_diplomatic_relation(
				0, 1, GameState.DiplomaticRelation.WAR
			)
		"closed_cut":
			_check(
				_close_vertical_cut(state) == GameState.GRID,
				"closed_cut/seed_%d/covers_full_cut" % seed
			)
		"sieged_cut":
			_check(
				_add_sieged_column(state) == GameState.GRID,
				"sieged_cut/seed_%d/covers_full_column" % seed
			)
		"enemy_occupied_cut":
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
