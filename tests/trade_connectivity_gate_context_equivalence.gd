extends SceneTree
## 贸易连通性 gate-context 开关等价守卫。
## Godot --headless --path . --script res://tests/trade_connectivity_gate_context_equivalence.gd

const SEEDS: Array[int] = [7, 31, 97]
const SCENARIOS: Array[String] = [
	"all_neutral",
	"single_war",
	"alliance_block",
	"multi_war",
	"closed_cut",
	"sieged_cut",
	"third_party_occupied_cut",
	"shared_enemy_merge",
]
const GATE_ENV_KEY := "TRADE_LEGACY_CONNECTIVITY_GATE_CONTEXT"
const ENV_FIXTURE_SEED := 97
const ENV_FIXTURE_SCENARIO := "shared_enemy_merge"

var _checks := 0
var _failures: Array[String] = []
var _total_queries := 0
var _total_build_contexts := 0
var _total_signature_builds := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for seed in SEEDS:
		for scenario in SCENARIOS:
			_assert_equivalent(_make_state(seed, scenario), seed, scenario)
	TradeNetwork.set_connectivity_gate_context_enabled(true)
	_check(
		_total_queries > 0,
		"aggregate/total_queries_positive",
		"total_queries=%d" % _total_queries
	)
	_check(
		_total_build_contexts > 0,
		"aggregate/total_build_contexts_positive",
		"total_build_contexts=%d" % _total_build_contexts
	)
	_check(
		_total_signature_builds > 0,
		"aggregate/total_signature_builds_positive",
		"total_signature_builds=%d" % _total_signature_builds
	)
	_run_env_rollback_tests()
	TradeNetwork.set_connectivity_gate_context_enabled(true)
	print("=== 贸易连通性 gate-context 等价校验 ===")
	print("total_queries=%d build_contexts=%d signature_builds=%d" % [
		_total_queries, _total_build_contexts, _total_signature_builds,
	])
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("TRADE_CONNECTIVITY_GATE_CONTEXT_EQUIVALENT")
		quit(0)
		return
	for failure in _failures:
		push_error("TRADE_CONNECTIVITY_GATE_CONTEXT_FAIL: " + failure)
	print("TRADE_CONNECTIVITY_GATE_CONTEXT_DIVERGED")
	quit(1)


func _run_env_rollback_tests() -> void:
	var state := _make_state(ENV_FIXTURE_SEED, ENV_FIXTURE_SCENARIO)
	var had_original_env := OS.get_environment(GATE_ENV_KEY) != ""
	var original_env := OS.get_environment(GATE_ENV_KEY)
	# env "1" overrides to legacy (gate disabled) even when setter is true.
	OS.set_environment(GATE_ENV_KEY, "1")
	TradeNetwork.set_connectivity_gate_context_enabled(true)
	TradeNetwork.reset_connectivity_prefilter_counters()
	var env_legacy_structure := TradeNetwork.build_structure(state, true)
	var env_legacy_stats := TradeNetwork.connectivity_prefilter_counters()
	var gate_disabled_builds := int(
		env_legacy_stats["connectivity_gate_build_contexts"]
	)
	var gate_disabled_signatures := int(
		env_legacy_stats["connectivity_gate_signature_context_builds"]
	)
	var env_queries := int(env_legacy_stats["candidate_connectivity_queries"])
	_check(
		gate_disabled_builds == 0,
		"env/gate_disabled/build_contexts_zero",
		"build_contexts=%d" % gate_disabled_builds
	)
	_check(
		gate_disabled_signatures == 0,
		"env/gate_disabled/signature_context_builds_zero",
		"signature=%d" % gate_disabled_signatures
	)
	_check(
		env_queries > 0,
		"env/gate_disabled/queries_positive",
		"queries=%d" % env_queries
	)
	# Compare env-legacy (env "1"+setter true) against setter-disabled legacy.
	TradeNetwork.set_connectivity_gate_context_enabled(false)
	TradeNetwork.reset_connectivity_prefilter_counters()
	var setter_legacy_structure := TradeNetwork.build_structure(state, true)
	_check(
		env_legacy_structure == setter_legacy_structure,
		"env/gate_disabled/matches_setter_disabled_legacy"
	)
	# env "0" forces gate enabled; setter false is overridden by env.
	OS.set_environment(GATE_ENV_KEY, "0")
	TradeNetwork.set_connectivity_gate_context_enabled(false)
	TradeNetwork.reset_connectivity_prefilter_counters()
	var env_enabled_structure := TradeNetwork.build_structure(state, true)
	var env_enabled_stats := TradeNetwork.connectivity_prefilter_counters()
	var env_enabled_builds := int(
		env_enabled_stats["connectivity_gate_build_contexts"]
	)
	var env_enabled_signatures := int(
		env_enabled_stats["connectivity_gate_signature_context_builds"]
	)
	var env_enabled_queries := int(
		env_enabled_stats["candidate_connectivity_queries"]
	)
	_check(
		env_enabled_builds > 0,
		"env/gate_enabled/build_contexts_positive",
		"build_contexts=%d" % env_enabled_builds
	)
	_check(
		env_enabled_signatures > 0,
		"env/gate_enabled/signature_context_builds_positive",
		"signature=%d" % env_enabled_signatures
	)
	_check(
		env_enabled_queries > 0,
		"env/gate_enabled/queries_positive",
		"queries=%d" % env_enabled_queries
	)
	_check(
		env_enabled_structure == env_legacy_structure,
		"env/gate_enabled/structure_still_equivalent"
	)
	if had_original_env:
		OS.set_environment(GATE_ENV_KEY, original_env)
	else:
		# Godot 4 提供 OS.unset_environment 清除继承值。
		OS.unset_environment(GATE_ENV_KEY)
	TradeNetwork.set_connectivity_gate_context_enabled(true)


func _assert_equivalent(
	state: GameState, seed: int, scenario: String
) -> void:
	var label := "%s/seed_%d" % [scenario, seed]
	TradeNetwork.set_connectivity_gate_context_enabled(false)
	TradeNetwork.reset_connectivity_prefilter_counters()
	var legacy_structure := TradeNetwork.build_structure(state, true)
	var legacy_stats := TradeNetwork.connectivity_prefilter_counters()

	TradeNetwork.set_connectivity_gate_context_enabled(true)
	TradeNetwork.reset_connectivity_prefilter_counters()
	var gated_structure := TradeNetwork.build_structure(state, true)
	var gated_stats := TradeNetwork.connectivity_prefilter_counters()

	_check(
		legacy_structure == gated_structure,
		label + "/structure_exact_equivalent"
	)

	var gate_builds := int(gated_stats["connectivity_gate_build_contexts"])
	var signature_builds := int(
		gated_stats["connectivity_gate_signature_context_builds"]
	)
	var queries := int(gated_stats["candidate_connectivity_queries"])
	var legacy_builds := int(
		legacy_stats["connectivity_gate_build_contexts"]
	)
	var legacy_signatures := int(
		legacy_stats["connectivity_gate_signature_context_builds"]
	)
	_check(
		legacy_builds == 0,
		label + "/counters/disabled_build_contexts_zero",
		"disabled_build_contexts=%d" % legacy_builds
	)
	_check(
		legacy_signatures == 0,
		label + "/counters/disabled_signature_builds_zero",
		"disabled_signatures=%d" % legacy_signatures
	)

	_total_queries += queries
	_total_build_contexts += gate_builds
	_total_signature_builds += signature_builds

	if queries > 0:
		_check(
			gate_builds > 0,
			label + "/counters/build_contexts_positive"
		)
		_check(
			signature_builds > 0,
			label + "/counters/signature_context_builds_positive"
		)
		_check(
			gate_builds <= queries,
			label + "/counters/build_contexts_lte_queries",
			"build_contexts=%d queries=%d" % [gate_builds, queries]
		)
		_check(
			signature_builds <= queries,
			label + "/counters/signature_context_builds_lte_queries",
			"signature_builds=%d queries=%d" % [signature_builds, queries]
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
		"shared_enemy_merge":
			state.set_diplomatic_relation(
				0, 2, GameState.DiplomaticRelation.WAR
			)
			state.set_diplomatic_relation(
				1, 2, GameState.DiplomaticRelation.WAR
			)
			state.set_diplomatic_relation(
				0, 3, GameState.DiplomaticRelation.WAR
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
