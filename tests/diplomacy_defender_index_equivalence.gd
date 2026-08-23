extends SceneTree
## 守军索引 v2 等价守卫。逐 seed / attacker / city 对比 legacy oracle，
## 并验证共享 evaluation_cache 只构建一次，而 legacy 路径按 attacker
## 触发多次全军扫描。
##
## 运行：
## /Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . \
##   --script res://tests/diplomacy_defender_index_equivalence.gd

const WORLD_SEEDS: Array[int] = [20260821, 20260822, 20260823]
const NATION_COUNT: int = 5
const LAND_CITY_COUNT: int = 30

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	var original_disabled := DiplomacyAI.city_defender_index_disabled

	_test_invalid_inputs()
	for world_seed in WORLD_SEEDS:
		var state := _make_world(world_seed)
		_test_per_attacker_city_equivalence(state, world_seed)
		_test_objective_equivalence(state, world_seed)
		_test_choose_actions_equivalence(state, world_seed)
		_test_counters(state, world_seed)

	DiplomacyAI.city_defender_index_disabled = original_disabled

	print(
		"=== 外交守军索引等价校验（%d seed/%d国/%d陆城）==="
		% [WORLD_SEEDS.size(), NATION_COUNT, LAND_CITY_COUNT]
	)
	if _failures.is_empty():
		print("DIPLOMACY_DEFENDER_INDEX_EQUIVALENT checks=%d" % _checks)
	else:
		for failure in _failures:
			push_error("DIPLOMACY_DEFENDER_INDEX_FAIL: " + failure)
		print("DIPLOMACY_DEFENDER_INDEX_DIVERGED checks=%d failures=%d" % [
			_checks, _failures.size(),
		])
	quit(0 if _failures.is_empty() else 1)


func _make_world(world_seed: int) -> GameState:
	var state := GameState.new()
	state.generate_world(world_seed, NATION_COUNT, LAND_CITY_COUNT)
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.WAR
			)
	return state


func _test_invalid_inputs() -> void:
	DiplomacyAI.city_defender_index_disabled = false
	DiplomacyAI.reset_city_defender_index_counters()
	var state := GameState.new()
	state.generate_grid_world(20260823)
	var negative := DiplomacyAI._city_defender_troop_index(state, -1, {})
	var overflow := DiplomacyAI._city_defender_troop_index(
		state,
		state.nations.size(),
		{}
	)
	_check(negative is Dictionary, "invalid/negative_nation_returns_dict")
	_check(overflow is Dictionary, "invalid/out_of_range_nation_returns_dict")
	var counters := DiplomacyAI.city_defender_index_counters()
	_check(
		int(counters.get("legacy_scans", 0)) >= 2,
		"invalid/empty_cache_uses_legacy :: %s" % str(counters)
	)


func _test_per_attacker_city_equivalence(
	state: GameState,
	world_seed: int
) -> void:
	DiplomacyAI.city_defender_index_disabled = true
	var legacy_by_attacker := {}
	for nation in state.nations:
		legacy_by_attacker[nation.id] = DiplomacyAI._city_defender_troop_index(
			state,
			nation.id,
			{}
		)

	DiplomacyAI.city_defender_index_disabled = false
	DiplomacyAI.reset_city_defender_index_counters()
	var shared_cache := {"__sentinel": "shared"}
	for nation in state.nations:
		var attacker := nation.id
		var indexed := DiplomacyAI._city_defender_troop_index(
			state,
			attacker,
			shared_cache
		)
		var legacy: Dictionary = legacy_by_attacker[attacker]
		for city in state.cities:
			var city_id := city.id
			_check(
				int(indexed.get(city_id, 0)) == int(legacy.get(city_id, 0)),
				"seed=%d/attacker=%d/city=%d/index=%d legacy=%d"
				% [
					world_seed,
					attacker,
					city_id,
					int(indexed.get(city_id, 0)),
					int(legacy.get(city_id, 0)),
				]
			)
		var cached := DiplomacyAI._city_defender_troop_index(
			state,
			attacker,
			shared_cache
		)
		_check(
			str(cached) == str(indexed),
			"seed=%d/attacker=%d/repeated_query_matches"
			% [world_seed, attacker]
		)
	var counters := DiplomacyAI.city_defender_index_counters()
	_check(
		int(counters.get("builds", 0)) == 1,
		"seed=%d/per_attacker_shared_cache_build_once :: %s"
		% [world_seed, str(counters)]
	)
	_check(
		int(counters.get("hits", 0)) == state.nations.size(),
		"seed=%d/per_attacker_repeated_hits :: %s"
		% [world_seed, str(counters)]
	)


func _test_objective_equivalence(
	state: GameState,
	world_seed: int
) -> void:
	DiplomacyAI.city_defender_index_disabled = true
	var legacy_cache := {"__sentinel": "legacy_objective"}
	var legacy_results := {}
	for attacker in state.nations:
		for target in state.nations:
			if attacker.id == target.id:
				continue
			legacy_results["%d:%d" % [attacker.id, target.id]] = (
				DiplomacyAI.select_war_objective(
					state,
					attacker.id,
					target.id,
					legacy_cache
				)
			)

	DiplomacyAI.city_defender_index_disabled = false
	DiplomacyAI.reset_city_defender_index_counters()
	var indexed_cache := {"__sentinel": "indexed_objective"}
	for attacker in state.nations:
		for target in state.nations:
			if attacker.id == target.id:
				continue
			var key := "%d:%d" % [attacker.id, target.id]
			var indexed := DiplomacyAI.select_war_objective(
				state,
				attacker.id,
				target.id,
				indexed_cache
			)
			_check(
				str(indexed) == str(legacy_results[key]),
				"seed=%d/objective=%s/index=%s legacy=%s"
				% [world_seed, key, str(indexed), str(legacy_results[key])]
			)


func _test_choose_actions_equivalence(
	state: GameState,
	world_seed: int
) -> void:
	DiplomacyAI.city_defender_index_disabled = true
	var legacy_actions := DiplomacyAI.choose_actions(state, {}, false, {})

	DiplomacyAI.city_defender_index_disabled = false
	var indexed_actions := DiplomacyAI.choose_actions(state, {}, false, {})

	_check(
		str(indexed_actions) == str(legacy_actions),
		"seed=%d/choose_actions/index=%s legacy=%s"
		% [world_seed, str(indexed_actions), str(legacy_actions)]
	)


func _test_counters(state: GameState, world_seed: int) -> void:
	DiplomacyAI.city_defender_index_disabled = true
	DiplomacyAI.reset_city_defender_index_counters()
	for nation in state.nations:
		DiplomacyAI._city_defender_troop_index(state, nation.id, {})
	var legacy_counters := DiplomacyAI.city_defender_index_counters()
	var legacy_scans := int(legacy_counters.get("legacy_scans", 0))
	_check(
		legacy_scans >= state.nations.size(),
		"seed=%d/legacy_scans=%d nations=%d"
		% [world_seed, legacy_scans, state.nations.size()]
	)
	_check(
		int(legacy_counters.get("builds", 0)) == 0
			and int(legacy_counters.get("hits", 0)) == 0,
		"seed=%d/legacy_counter_shape :: %s"
		% [world_seed, str(legacy_counters)]
	)

	DiplomacyAI.city_defender_index_disabled = false
	DiplomacyAI.reset_city_defender_index_counters()
	var shared_cache := {"__sentinel": "counter"}
	for nation in state.nations:
		DiplomacyAI._city_defender_troop_index(state, nation.id, shared_cache)
	var index_counters := DiplomacyAI.city_defender_index_counters()
	_check(
		int(index_counters.get("builds", 0)) == 1,
		"seed=%d/build_once :: %s" % [world_seed, str(index_counters)]
	)
	_check(
		int(index_counters.get("hits", 0)) == 0,
		"seed=%d/no_hits_on_first_pass :: %s"
		% [world_seed, str(index_counters)]
	)
	_check(
		int(index_counters.get("legacy_scans", 0)) == 0,
		"seed=%d/index_no_legacy_scan :: %s"
		% [world_seed, str(index_counters)]
	)
	_check(
		int(index_counters.get("builds", 0)) < legacy_scans,
		"seed=%d/index_build_lt_legacy_scans :: index=%s legacy=%d"
		% [world_seed, str(index_counters), legacy_scans]
	)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < 30:
		_failures.append(label)
	elif _failures.size() == 30:
		_failures.append("additional failures omitted")
