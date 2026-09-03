extends SceneTree
## 500 城贸易动态结算细分探针。结构层只构建一次，随后分别测完整月结和
## 外交摘要结算，避免把路线搜索时间混入动态阶段。


func _init() -> void:
	var nations := _env_int("TRADE_SETTLE_NATIONS", 80)
	var cities := _env_int("TRADE_SETTLE_CITIES", 500)
	var iterations := _env_int("TRADE_SETTLE_ITERATIONS", 5)
	var war_pairs := _env_int("TRADE_SETTLE_WAR_PAIRS", 10)
	var state := GameState.new()
	state.generate_world(12345, nations, cities)
	_force_adjacent_wars(state, war_pairs)
	var structure := TradeNetwork.build_structure(state)
	var wartime_mask := TradeNetwork.wartime_nation_mask(state)
	var full_profiles: Array[Dictionary] = []
	var summary_profiles: Array[Dictionary] = []
	for _iteration in range(iterations):
		var full_profile := {"enabled": true}
		TradeNetwork.settle(
			state, structure, full_profile, wartime_mask
		)
		full_profiles.append(full_profile)
		var summary_profile := {"enabled": true}
		TradeNetwork.settle_nation_summary(
			state, structure, summary_profile, wartime_mask
		)
		summary_profiles.append(summary_profile)
	print("=== 贸易动态结算细分 %d国/%d城 wars=%d n=%d ===" % [
		nations, cities, war_pairs, iterations,
	])
	_print_profiles("完整结算", full_profiles)
	_print_profiles("外交摘要", summary_profiles)
	print("verdict=TRADE_SETTLE_PHASE_PROBE_DONE")
	quit(0)


func _print_profiles(label: String, profiles: Array[Dictionary]) -> void:
	var keys := {}
	for profile in profiles:
		for key in profile:
			if key != "enabled":
				keys[key] = true
	var sorted_keys := keys.keys()
	sorted_keys.sort()
	print(label + ":")
	for key_value in sorted_keys:
		var key := str(key_value)
		var values: Array[int] = []
		for profile in profiles:
			values.append(int(profile.get(key, 0)))
		values.sort()
		var total := 0
		for value in values:
			total += value
		print("  %-24s avg=%7.2fms median=%7.2fms max=%7.2fms" % [
			key,
			float(total) / float(maxi(values.size(), 1)) / 1000.0,
			float(values[values.size() / 2]) / 1000.0,
			float(values.back()) / 1000.0,
		])


func _force_adjacent_wars(state: GameState, count: int) -> void:
	var candidates: Array[Vector2i] = []
	for edge in state.edges:
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a < 0 or owner_b < 0 or owner_a == owner_b:
			continue
		var pair := Vector2i(mini(owner_a, owner_b), maxi(owner_a, owner_b))
		if not candidates.has(pair):
			candidates.append(pair)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	for index in range(mini(count, candidates.size())):
		var pair := candidates[index]
		state.set_diplomatic_relation(
			pair.x, pair.y, GameState.DiplomaticRelation.WAR
		)


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return fallback if raw.is_empty() else int(raw)
