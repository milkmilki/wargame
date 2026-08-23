extends SceneTree
## 包围值索引等价守卫。独立 legacy oracle 保留优化前算法的三个关键语义：
## 删除目标城后的军事通行 BFS、按 state.armies 原顺序累加浮点战力，以及按
## max_size 分桶判断目标城驻军是否存在合法撤退路。
##
## 运行：
## /Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path . \
##   --script res://tests/encirclement_index_equivalence.gd

const EPSILON: float = 0.000001
const WORLD_SEEDS: Array[int] = [20260821, 20260822, 20260823]
const NATION_COUNT: int = 5
const LAND_CITY_COUNT: int = 30
const SENTINEL_KEY: String = "__encirclement_equivalence_sentinel"

var _checks: int = 0
var _failures: Array[String] = []
var _value_candidates: int = 0
var _snapshot_candidates: int = 0
var _index_builds: int = 0
var _cache_hits: int = 0
var _cache_misses: int = 0


func _init() -> void:
	var original_index_enabled := (
		DiplomacyAI.encirclement_index_enabled
	)
	_test_invalid_inputs()
	for world_seed in WORLD_SEEDS:
		var state := _make_world(world_seed)
		_test_all_values(state, world_seed)
		_test_strategic_snapshots(state, world_seed)
	DiplomacyAI.encirclement_index_enabled = original_index_enabled

	print(
		"=== 包围值索引等价校验（%d seed/%d国/%d陆城）==="
		% [WORLD_SEEDS.size(), NATION_COUNT, LAND_CITY_COUNT]
	)
	print("逐项包围候选=%d 战略前线候选=%d" % [
		_value_candidates, _snapshot_candidates,
	])
	print("索引 build=%d hit=%d miss=%d" % [
		_index_builds, _cache_hits, _cache_misses,
	])
	if _failures.is_empty():
		print("ENCIRCLEMENT_INDEX_EQUIVALENT checks=%d" % _checks)
	else:
		for failure in _failures:
			push_error("ENCIRCLEMENT_INDEX_FAIL: " + failure)
		print("ENCIRCLEMENT_INDEX_DIVERGED checks=%d failures=%d" % [
			_checks, _failures.size(),
		])
	quit(0 if _failures.is_empty() else 1)


func _test_invalid_inputs() -> void:
	DiplomacyAI.encirclement_index_enabled = true
	DiplomacyAI.reset_encirclement_cache_counters()
	var state := GameState.new()
	state.generate_grid_world(20260823)
	var cache := {SENTINEL_KEY: "invalid"}
	_check(
		DiplomacyAI.encirclement_value(null, 0, 0, cache) == 0.0,
		"invalid/null_state_returns_zero"
	)
	_check(
		DiplomacyAI.encirclement_value(state, -1, 0, cache) == 0.0
			and DiplomacyAI.encirclement_value(
				state, state.cities.size(), 0, cache
			) == 0.0,
		"invalid/city_returns_zero"
	)
	_check(
		DiplomacyAI.encirclement_value(state, 0, -1, cache) == 0.0
			and DiplomacyAI.encirclement_value(
				state, 0, state.nations.size(), cache
			) == 0.0,
		"invalid/nation_returns_zero"
	)
	_check(
		EncirclementIndex.new(null, 0).value_for(0) == 0.0,
		"invalid/direct_index_null_state_returns_zero"
	)
	var counters := DiplomacyAI.encirclement_cache_counters()
	_check(
		_counter(counters, "index_builds") == 0
			and _counter(counters, "cache_hits") == 0
			and _counter(counters, "cache_misses") == 0,
		"invalid/does_not_touch_cache :: %s" % str(counters)
	)


func _make_world(world_seed: int) -> GameState:
	var state := GameState.new()
	state.generate_world(world_seed, NATION_COUNT, LAND_CITY_COUNT)
	# 正式小地图默认是中立关系；全体两两开战，确保每个国家的真实边界都
	# 进入 StrategicMapSnapshot 的敌方候选集合。
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.WAR
			)
	return state


func _test_all_values(state: GameState, world_seed: int) -> void:
	var candidates := _all_owned_city_candidates(state)
	_value_candidates += candidates.size()
	_check(
		not candidates.is_empty(),
		"seed=%d/value_candidates/nonempty" % world_seed
	)
	var expected_by_key := {}
	for candidate in candidates:
		var target_city := int(candidate[0])
		var target_nation := int(candidate[1])
		expected_by_key[_candidate_key(target_city, target_nation)] = (
			_legacy_encirclement_value(
				state, target_city, target_nation
			)
		)

	# 非空 cache 刻意配合关闭开关，证明公开入口确实由开关进入 legacy 路径；
	# sentinel 也保证两条路径都显式复用调用方提供的共享 Dictionary。
	DiplomacyAI.encirclement_index_enabled = false
	DiplomacyAI.reset_encirclement_cache_counters()
	var legacy_cache := {SENTINEL_KEY: "legacy:%d" % world_seed}
	for candidate in candidates:
		var target_city := int(candidate[0])
		var target_nation := int(candidate[1])
		var expected := float(expected_by_key[
			_candidate_key(target_city, target_nation)
		])
		var actual := DiplomacyAI.encirclement_value(
			state, target_city, target_nation, legacy_cache
		)
		_check_close(
			expected,
			actual,
			"seed=%d/legacy/city=%d/nation=%d"
			% [world_seed, target_city, target_nation]
		)
	var legacy_counters := DiplomacyAI.encirclement_cache_counters()
	_check_counter_shape(legacy_counters, world_seed, "legacy")
	_check(
		_counter(legacy_counters, "index_builds") == 0
			and _counter(legacy_counters, "cache_hits") == 0
			and _counter(legacy_counters, "cache_misses") == 0,
		"seed=%d/legacy/bypasses_index :: %s"
		% [world_seed, str(legacy_counters)]
	)

	# 同一批候选打开索引后逐项对 oracle，并显式复用调用方提供的 cache。
	DiplomacyAI.encirclement_index_enabled = true
	DiplomacyAI.reset_encirclement_cache_counters()
	var cached_cache := {SENTINEL_KEY: "cached:%d" % world_seed}
	for candidate in candidates:
		var target_city := int(candidate[0])
		var target_nation := int(candidate[1])
		var expected := float(expected_by_key[
			_candidate_key(target_city, target_nation)
		])
		var actual := DiplomacyAI.encirclement_value(
			state, target_city, target_nation, cached_cache
		)
		_check_close(
			expected,
			actual,
			"seed=%d/cached/city=%d/nation=%d"
			% [world_seed, target_city, target_nation]
		)
	var first_pass := DiplomacyAI.encirclement_cache_counters()
	_check_counter_shape(first_pass, world_seed, "cached_first")
	_check(
		_counter(first_pass, "index_builds") > 0
			and _counter(first_pass, "cache_misses") > 0,
		"seed=%d/cached/first_pass_builds :: %s"
		% [world_seed, str(first_pass)]
	)

	# 完整重复相同请求；值仍须等价，且只能命中已有索引，不能重建。
	for candidate in candidates:
		var target_city := int(candidate[0])
		var target_nation := int(candidate[1])
		var expected := float(expected_by_key[
			_candidate_key(target_city, target_nation)
		])
		var repeated := DiplomacyAI.encirclement_value(
			state, target_city, target_nation, cached_cache
		)
		_check_close(
			expected,
			repeated,
			"seed=%d/repeated/city=%d/nation=%d"
			% [world_seed, target_city, target_nation]
		)
	var repeated_pass := DiplomacyAI.encirclement_cache_counters()
	_check_counter_shape(repeated_pass, world_seed, "cached_repeated")
	_check(
		_counter(repeated_pass, "cache_hits")
			> _counter(first_pass, "cache_hits"),
		"seed=%d/repeated/records_hit :: first=%s repeated=%s"
		% [world_seed, str(first_pass), str(repeated_pass)]
	)
	_check(
		_counter(repeated_pass, "index_builds")
			== _counter(first_pass, "index_builds")
			and _counter(repeated_pass, "cache_misses")
				== _counter(first_pass, "cache_misses"),
		"seed=%d/repeated/no_rebuild :: first=%s repeated=%s"
		% [world_seed, str(first_pass), str(repeated_pass)]
	)
	_accumulate_counters(repeated_pass)


func _test_strategic_snapshots(
	state: GameState,
	world_seed: int
) -> void:
	var legacy_snapshots: Array[StrategicMapSnapshot] = []
	var cached_snapshots: Array[StrategicMapSnapshot] = []
	var legacy_cache := {SENTINEL_KEY: "snapshot_legacy:%d" % world_seed}
	var cached_cache := {SENTINEL_KEY: "snapshot_cached:%d" % world_seed}

	DiplomacyAI.encirclement_index_enabled = false
	DiplomacyAI.reset_encirclement_cache_counters()
	for nation in state.nations:
		var view := AiWorldView.build(state, nation.id)
		legacy_snapshots.append(
			StrategicMapSnapshot.build(view, legacy_cache)
		)
	var legacy_counters := DiplomacyAI.encirclement_cache_counters()
	_check(
		_counter(legacy_counters, "index_builds") == 0
			and _counter(legacy_counters, "cache_hits") == 0
			and _counter(legacy_counters, "cache_misses") == 0,
		"seed=%d/snapshot_legacy/bypasses_index :: %s"
		% [world_seed, str(legacy_counters)]
	)

	DiplomacyAI.encirclement_index_enabled = true
	DiplomacyAI.reset_encirclement_cache_counters()
	for nation in state.nations:
		var view := AiWorldView.build(state, nation.id)
		cached_snapshots.append(
			StrategicMapSnapshot.build(view, cached_cache)
		)
	var cached_counters := DiplomacyAI.encirclement_cache_counters()
	_check_counter_shape(cached_counters, world_seed, "snapshot_cached")
	_check(
		_counter(cached_counters, "index_builds") > 0
			and _counter(cached_counters, "cache_misses") > 0,
		"seed=%d/snapshot_cached/exercises_index :: %s"
		% [world_seed, str(cached_counters)]
	)
	_accumulate_counters(cached_counters)

	for nation_index in range(state.nations.size()):
		var legacy := legacy_snapshots[nation_index]
		var cached := cached_snapshots[nation_index]
		_snapshot_candidates += legacy.frontier_enemy_cities.size()
		_check(
			not legacy.frontier_enemy_cities.is_empty(),
			"seed=%d/nation=%d/frontier_candidates/nonempty"
			% [world_seed, nation_index]
		)
		_check(
			legacy.offensive_value == cached.offensive_value,
			"seed=%d/nation=%d/snapshot/offensive_value :: %s"
			% [
				world_seed, nation_index,
				_first_offensive_difference(legacy, cached),
			]
		)
		_check(
			legacy.priority_enemy_cities
				== cached.priority_enemy_cities,
			"seed=%d/nation=%d/snapshot/priority_enemy_cities"
			% [world_seed, nation_index]
		)
		_check(
			legacy.campaign_target == cached.campaign_target,
			"seed=%d/nation=%d/snapshot/campaign_target :: %d != %d"
			% [
				world_seed, nation_index,
				legacy.campaign_target, cached.campaign_target,
			]
		)


func _all_owned_city_candidates(state: GameState) -> Array[Array]:
	var result: Array[Array] = []
	for city in state.cities:
		if (
			city.owner_nation < 0
			or city.owner_nation >= state.nations.size()
			or not state.nations[city.owner_nation].alive
		):
			continue
		result.append([city.id, city.owner_nation])
	return result


func _candidate_key(target_city: int, target_nation: int) -> String:
	return "%d:%d" % [target_city, target_nation]


func _legacy_encirclement_value(
	state: GameState,
	target_city: int,
	target_nation: int
) -> float:
	if (
		target_nation < 0
		or target_nation >= state.nations.size()
		or target_city < 0
		or target_city >= state.cities.size()
	):
		return 0.0
	var effect := _legacy_target_encirclement_effect(
		state, target_city, target_nation
	)
	return (
		float(effect["cut_city_ratio"]) * 6.0
		+ float(effect["cut_troop_ratio"]) * 8.0
		+ _legacy_isolated_garrison_power_ratio(
			state, target_city, target_nation
		) * 8.0
	)


func _legacy_target_encirclement_effect(
	state: GameState,
	target_city: int,
	target_nation: int
) -> Dictionary:
	var capital := state.nations[target_nation].capital_city_id
	if capital < 0 or capital == target_city:
		return {
			"cut_city_ratio": 0.0,
			"cut_troop_ratio": 0.0,
		}
	var reachable := {capital: true}
	var queue: Array[int] = [capital]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor in state.neighbors(current):
			if neighbor == target_city or reachable.has(neighbor):
				continue
			var edge := state.edge_of(current, neighbor)
			if (
				edge == null
				or edge.max_manpower <= 0
				or not state.has_military_access(
					target_nation,
					state.cities[neighbor].owner_nation
				)
			):
				continue
			reachable[neighbor] = true
			queue.append(neighbor)

	var total := 0
	var cut := 0
	for city in state.cities:
		if city.owner_nation != target_nation or city.id == target_city:
			continue
		total += 1
		if not reachable.has(city.id):
			cut += 1

	# 不排序：浮点加法顺序是 legacy 行为的一部分。
	var total_power := 0.0
	var cut_power := 0.0
	for army in state.armies:
		if army.owner_nation != target_nation or army.size <= 0:
			continue
		var power := ArmyPower.effective(army)
		total_power += power
		var node_city := army.current_city_node()
		if (
			node_city >= 0
			and node_city != target_city
			and not reachable.has(node_city)
		):
			cut_power += power
	return {
		"cut_city_ratio": float(cut) / float(maxi(total, 1)),
		"cut_troop_ratio": cut_power / maxf(total_power, 1.0),
	}


func _legacy_isolated_garrison_power_ratio(
	state: GameState,
	city_id: int,
	nation_id: int
) -> float:
	var total_power := 0.0
	var isolated_power := 0.0
	var retreat_route_by_capacity := {}
	# 与 legacy 一致按 state.armies 原顺序累加，且以 max_size（不是 size）
	# 作为完整编制撤退所需道路容量。
	for army in state.armies:
		if army.owner_nation != nation_id or army.size <= 0:
			continue
		var power := ArmyPower.effective(army)
		total_power += power
		if army.current_city_node() != city_id:
			continue
		var required_manpower := maxi(army.max_size, 1)
		if not retreat_route_by_capacity.has(required_manpower):
			retreat_route_by_capacity[required_manpower] = (
				Pathfinding.has_friendly_retreat_route_from_city(
					state, nation_id, city_id, required_manpower
				)
			)
		if not bool(retreat_route_by_capacity[required_manpower]):
			isolated_power += power
	return isolated_power / maxf(total_power, 1.0)


func _first_offensive_difference(
	legacy: StrategicMapSnapshot,
	cached: StrategicMapSnapshot
) -> String:
	if legacy.offensive_value.size() != cached.offensive_value.size():
		return "size %d != %d" % [
			legacy.offensive_value.size(), cached.offensive_value.size(),
		]
	for city_id in legacy.offensive_value:
		if (
			not cached.offensive_value.has(city_id)
			or legacy.offensive_value[city_id]
				!= cached.offensive_value[city_id]
		):
			return "city=%s legacy=%s cached=%s" % [
				str(city_id),
				str(legacy.offensive_value[city_id]),
				str(cached.offensive_value.get(city_id)),
			]
	return "dictionary ordering/value mismatch"


func _check_close(expected: float, actual: float, label: String) -> void:
	_check(
		absf(expected - actual) <= EPSILON,
		"%s :: oracle=%.9f actual=%.9f delta=%.9f"
		% [label, expected, actual, absf(expected - actual)]
	)


func _check_counter_shape(
	counters: Dictionary,
	world_seed: int,
	phase: String
) -> void:
	for key in ["index_builds", "cache_hits", "cache_misses"]:
		_check(
			counters.has(key),
			"seed=%d/%s/counter_missing=%s :: %s"
			% [world_seed, phase, key, str(counters)]
		)


func _counter(counters: Dictionary, key: String) -> int:
	return int(counters.get(key, -1))


func _accumulate_counters(counters: Dictionary) -> void:
	_index_builds += _counter(counters, "index_builds")
	_cache_hits += _counter(counters, "cache_hits")
	_cache_misses += _counter(counters, "cache_misses")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < 30:
		_failures.append(label)
	elif _failures.size() == 30:
		_failures.append("additional failures omitted")
