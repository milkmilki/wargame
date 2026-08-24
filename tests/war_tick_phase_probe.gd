extends SceneTree
## 战争/和平每日阶段耗时探针。开启 Simulation 的默认关闭 profiling，
## 按 tick 结束后的实际战争对数量分桶，报告各阶段平均/峰值与总耗时占比。
##
## 可调：
##   PHASE_NATIONS(默认4) PHASE_CITIES(默认160) PHASE_DAYS(默认365)

const STAGES: Array[String] = [
	"maintenance",
	"monthly",
	"line_emergencies",
	"supply",
	"morale_merge",
	"ai",
	"campaign",
	"movement_battles",
	"cleanup",
	"total",
]

const AI_STAGES: Array[String] = [
	"ai_view_setup",
	"ai_shared_army_index",
	"ai_reconcile_roles",
	"ai_build_view",
	"ai_snapshot",
	"ai_snapshot_cache_seed",
	"ai_snapshot_forecast_structure_fingerprint",
	"ai_snapshot_forecast_structure_stage",
	"ai_snapshot_forecast_structure_inputs",
	"ai_snapshot_forecast_structure_graph",
	"ai_snapshot_forecast_structure_domestic",
	"ai_snapshot_forecast_structure_domestic_ideal_graph_fingerprint",
	"ai_snapshot_forecast_structure_domestic_prep",
	"ai_snapshot_forecast_structure_domestic_context",
	"ai_snapshot_forecast_structure_domestic_context_mask_block_key",
	"ai_snapshot_forecast_structure_domestic_context_ideal_field",
	"ai_snapshot_forecast_structure_domestic_context_ideal_field_cache_hits",
	"ai_snapshot_forecast_structure_domestic_context_ideal_field_cache_misses",
	"ai_snapshot_forecast_structure_domestic_context_ideal_field_cache_builds",
	"ai_snapshot_forecast_structure_domestic_context_operational_field",
	"ai_snapshot_forecast_structure_domestic_route_select",
	"ai_snapshot_forecast_structure_domestic_route_explain",
	"ai_snapshot_forecast_structure_domestic_route_materialize",
	"ai_snapshot_forecast_structure_domestic_unaccounted",
	"ai_snapshot_forecast_structure_international_candidates",
	"ai_snapshot_forecast_structure_international_candidates_hubs_prep",
	"ai_snapshot_forecast_structure_international_candidates_ideal_field",
	"ai_snapshot_forecast_structure_international_candidates_ideal_field_builds",
	"ai_snapshot_forecast_structure_international_candidates_ideal_field_local_hits",
	"ai_snapshot_forecast_structure_international_candidates_ideal_field_source_sets",
	"ai_snapshot_forecast_structure_international_candidates_endpoint_scan",
	"ai_snapshot_forecast_structure_international_candidates_union_gate",
	"ai_snapshot_forecast_structure_international_candidates_score",
	"ai_snapshot_forecast_structure_international_candidates_value",
	"ai_snapshot_forecast_structure_international_candidates_emit",
	"ai_snapshot_forecast_structure_international_candidates_sort",
	"ai_snapshot_forecast_structure_international_candidates_emitted",
	"ai_snapshot_forecast_structure_international_candidates_pair_loop_total",
	"ai_snapshot_forecast_structure_international_candidates_pair_iteration_total",
	"ai_snapshot_forecast_structure_international_candidates_pair_iteration_count",
	"ai_snapshot_forecast_structure_international_candidates_hub_score_calls",
	"ai_snapshot_forecast_structure_international_candidates_hub_sort_calls",
	"ai_snapshot_forecast_structure_international_candidates_hub_value_calls",
	"ai_snapshot_forecast_structure_international_candidates_unaccounted",
	"ai_snapshot_forecast_structure_international_routes",
	"ai_snapshot_forecast_structure_international_routes_ideal_lookup",
	"ai_snapshot_forecast_structure_international_routes_ideal_lookup_builds",
	"ai_snapshot_forecast_structure_international_routes_ideal_lookup_local_hits",
	"ai_snapshot_forecast_structure_international_routes_ideal_lookup_source_sets",
	"ai_snapshot_forecast_structure_international_routes_endpoint_select",
	"ai_snapshot_forecast_structure_international_routes_operational_field",
	"ai_snapshot_forecast_structure_international_routes_operational_field_builds",
	"ai_snapshot_forecast_structure_international_routes_operational_field_local_hits",
	"ai_snapshot_forecast_structure_international_routes_operational_field_source_sets",
	"ai_snapshot_forecast_structure_international_routes_explain_details",
	"ai_snapshot_forecast_structure_international_routes_materialize",
	"ai_snapshot_forecast_structure_international_routes_unaccounted",
	"ai_snapshot_forecast_structure_result",
	"ai_snapshot_forecast_settlement_token",
	"ai_snapshot_forecast_settlement_stage",
	"ai_snapshot_forecast_trade_settle",
	"ai_snapshot_forecast_gold_flows",
	"ai_snapshot_initialize",
	"ai_snapshot_frontier",
	"ai_snapshot_connectivity",
	"ai_snapshot_supply_corridors",
	"ai_snapshot_finalize_edges",
	"ai_snapshot_offensive",
	"ai_snapshot_priority",
	"ai_snapshot_build_total",
	"ai_snapshot_unaccounted",
	"ai_threat",
	"ai_snapshot_threat",
	"ai_defense",
	"ai_declaration_launches",
	"ai_force_structure",
	"ai_force_context",
	"ai_force_wars",
	"ai_force_food",
	"ai_force_food_plan",
	"ai_force_food_armies",
	"ai_force_gold_flows",
	"ai_force_gold_report",
	"ai_force_commit",
	"ai_campaign_planning",
	"ai_army_decisions",
	"ai_commit",
]

const CAMPAIGN_STAGES: Array[String] = [
	"campaign_objective",
	"campaign_ensure_plan",
	"campaign_launch_eval",
	"campaign_staging",
]

const SUPPLY_STAGES: Array[String] = [
	"supply_prepare",
	"supply_build_plans",
	"supply_sort",
	"supply_withdraw",
]

const MONTHLY_STAGES: Array[String] = [
	"monthly_economy",
	"monthly_reinforcements",
	"monthly_diplomacy",
]

const DIPLOMACY_STAGES: Array[String] = [
	"diplomacy_normalize",
	"diplomacy_trade_seed",
	"diplomacy_preparation_viability",
	"diplomacy_choose",
	"diplomacy_commit",
	"diplomacy_commit_declare_war",
	"diplomacy_commit_other",
	"diplomacy_mobilization_posture",
	"diplomacy_mobilization_capacity",
	"diplomacy_mobilization_troops",
	"diplomacy_mobilization_food",
	"diplomacy_declare_blocs",
	"diplomacy_declare_set_war",
	"diplomacy_declare_objective",
	"diplomacy_declare_cache_seed",
	"diplomacy_declare_mobilization",
	"diplomacy_declare_launch",
	"diplomacy_set_war_snapshot",
	"diplomacy_set_war_relations",
	"diplomacy_peace",
	"diplomacy_leave_alliance",
	"diplomacy_war",
	"diplomacy_alliance",
	"diplomacy_enfeoff",
	"diplomacy_centralization",
	"peace_blocs",
	"peace_coalition_breakdown",
	"peace_power_wars",
	"peace_situation",
	"peace_resources",
	"peace_external_threat",
	"peace_attitude",
	"war_gate",
	"war_resources_food",
	"war_objective",
	"war_power_scoring",
	"war_attitude_unification",
	"war_collect_precheck",
	"war_collect_candidates",
	"war_collect_finalize",
	"war_existing_preparation",
	"alliance_gate",
	"alliance_common_power",
	"alliance_shared_threat",
	"alliance_frontier_release",
	"alliance_attitude_unification",
	"attitude_history",
	"attitude_frontier_objective",
	"attitude_political",
]


func _init() -> void:
	if OS.get_environment(
		"PHASE_DIPLOMACY_CACHE_EQUIVALENCE"
	) == "1":
		_run_diplomacy_cache_equivalence()
		return
	DiplomacyAI.encirclement_index_enabled = (
		OS.get_environment("PHASE_LEGACY_ENCIRCLEMENT") != "1"
	)
	var nations := _env_int("PHASE_NATIONS", 4)
	var cities := _env_int("PHASE_CITIES", 160)
	var days := _env_int("PHASE_DAYS", 365)
	var state := GameState.new()
	state.generate_world(12345, nations, cities)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.ai_snapshot_resource_cache_reuse_disabled = (
		OS.get_environment("PHASE_COLD_FORCE_RESOURCES") == "1"
	)
	sim.tick_phase_profiling_enabled = true
	sim.ai_snapshot_substage_profiling_enabled = (
		OS.get_environment("PHASE_SNAPSHOT_SUBSTAGES") == "1"
	)
	sim.ai_force_resource_cache_disabled = (
		OS.get_environment("PHASE_DISABLE_FORCE_RESOURCE_CACHE") == "1"
	)
	sim.ai_decision_context_disabled = (
		OS.get_environment("PHASE_DISABLE_AI_CONTEXT") == "1"
	)
	sim.reinforcement_network_cache_disabled = (
		OS.get_environment(
			"PHASE_LEGACY_REINFORCEMENT_NETWORKS"
		) == "1"
	)
	sim.diplomacy_structure_cache_disabled = (
		OS.get_environment(
			"PHASE_LEGACY_DIPLOMACY_STRUCTURE_CACHE"
		) == "1"
	)
	var domestic_ideal_cache_disabled := (
		OS.get_environment(
			"PHASE_LEGACY_DOMESTIC_IDEAL_FIELD_CACHE"
		) == "1"
	)
	sim.trade_domestic_ideal_field_cache_disabled = (
		domestic_ideal_cache_disabled
	)
	TradeNetwork.set_domestic_ideal_shared_cache_enabled(
		not domestic_ideal_cache_disabled
	)

	var peaceful := _new_bucket()
	var wartime := _new_bucket()
	for _d in range(days):
		sim._advance_day(false)
		var bucket: Dictionary = (
			wartime if _war_pairs(state) > 0 else peaceful
		)
		_record(bucket, sim.tick_profile_last_usec)

	print("=== 战争/和平阶段耗时 国=%d 城=%d 推进=%d天 ===" % [
		nations, cities, state.day,
	])
	_print_bucket("和平日", peaceful)
	_print_bucket("战争日", wartime)
	print("外交动员 action 缓存构建=%d" % [
		sim.diplomacy_mobilization_evaluation_cache_total,
	])
	print("贸易 domestic ideal cache build=%d hit=%d miss=%d generation_clear=%d graph_fp_build=%d graph_fp_total=%.2fms" % [
		sim.trade_domestic_ideal_cache_build_total,
		sim.trade_domestic_ideal_cache_hit_total,
		sim.trade_domestic_ideal_cache_miss_total,
		sim.trade_domestic_ideal_cache_generation_clear_total,
		sim.trade_domestic_ideal_graph_fingerprint_total,
		float(sim.trade_domestic_ideal_graph_fingerprint_usec_total) / 1000.0,
	])
	print("verdict=WAR_PHASE_PROBE_DONE")
	sim.free()
	quit(0)


## 两个相同的双成员联盟执行同一次宣战。legacy 每个成员使用独立评估
## 上下文，正式路径在单 action 内共享；完整 GameState 必须逐属性等价。
func _run_diplomacy_cache_equivalence() -> void:
	var legacy := _make_diplomacy_cache_fixture(true)
	var cached := _make_diplomacy_cache_fixture(false)
	var action := {
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": 0,
		"b": 1,
		"objective_city": -1,
		"mobilization_armies": -1,
		"reason": "外交动员共享缓存等价回归",
	}
	legacy._commit_diplomacy_actions([action.duplicate(true)])
	cached._commit_diplomacy_actions([action.duplicate(true)])

	var failures: Array[String] = []
	if _state_fingerprint(legacy.state) != _state_fingerprint(cached.state):
		failures.append("共享缓存前后完整 GameState 不一致")
	for attacker in [0, 3]:
		for defender in [1, 2]:
			if not cached.state.is_enemy(attacker, defender):
				failures.append(
					"集团敌对缺失 %d-%d" % [attacker, defender]
				)
	for nation_id in [0, 3, 1, 2]:
		if cached.state.nations[
			nation_id
		].war_mobilization_target_troops < 0:
			failures.append("国%d动员目标非法" % nation_id)
	if legacy.diplomacy_mobilization_evaluation_cache_total != 4:
		failures.append(
			"legacy 应建立4份成员缓存，实际%d"
			% legacy.diplomacy_mobilization_evaluation_cache_total
		)
	if cached.diplomacy_mobilization_evaluation_cache_total != 1:
		failures.append(
			"正式路径应只建立1份 action 缓存，实际%d"
			% cached.diplomacy_mobilization_evaluation_cache_total
		)
	_test_multi_action_frozen_gold_flows(failures)

	print("=== 外交动员共享缓存等价校验 ===")
	print("legacy缓存=%d shared缓存=%d" % [
		legacy.diplomacy_mobilization_evaluation_cache_total,
		cached.diplomacy_mobilization_evaluation_cache_total,
	])
	if failures.is_empty():
		print("DIPLOMACY_MOBILIZATION_CACHE_EQUIVALENT")
	else:
		for failure in failures:
			push_error("DIPLOMACY_MOBILIZATION_CACHE_FAIL: " + failure)
		print("DIPLOMACY_MOBILIZATION_CACHE_DIVERGED failures=%d" % [
			failures.size(),
		])
	legacy.free()
	cached.free()
	quit(0 if failures.is_empty() else 1)


## 同一决策批次的多次宣战共用 choose 前财政快照，且提交不重建贸易。
func _test_multi_action_frozen_gold_flows(
	failures: Array[String]
) -> void:
	var sim := _make_neutral_diplomacy_fixture()
	var evaluation_cache := sim._seed_trade_forecast({})
	var frozen_flows: Array[Dictionary] = (
		evaluation_cache["monthly_gold_flows"]
	)
	var structure_builds_before := sim.trade_structure_build_total
	var forecast_builds_before := sim.trade_forecast_build_total
	var actions: Array[Dictionary] = [
		{
			"kind": DiplomacyAI.Action.DECLARE_WAR,
			"a": 0, "b": 1, "objective_city": -1,
			"mobilization_armies": -1, "reason": "批次冻结一",
		},
		{
			"kind": DiplomacyAI.Action.DECLARE_WAR,
			"a": 2, "b": 3, "objective_city": -1,
			"mobilization_armies": -1, "reason": "批次冻结二",
		},
	]
	sim._commit_diplomacy_actions(
		actions, evaluation_cache, frozen_flows
	)
	for nation_id in range(4):
		var expected := maxi(
			int(frozen_flows[nation_id]["net_income"]), 0
		)
		var nation := sim.state.nations[nation_id]
		if (
			nation.war_gold_income_snapshot != expected
			or nation.war_gold_income_snapshot_day != sim.state.day
		):
			failures.append(
				"国%d冻结收入错误 expected=%d actual=%d day=%d" % [
					nation_id, expected,
					nation.war_gold_income_snapshot,
					nation.war_gold_income_snapshot_day,
				]
			)
	if (
		sim.trade_structure_build_total != structure_builds_before
		or sim.trade_forecast_build_total != forecast_builds_before
	):
		failures.append(
			"多 action 提交重建贸易 before=%d/%d after=%d/%d" % [
				structure_builds_before, forecast_builds_before,
				sim.trade_structure_build_total,
				sim.trade_forecast_build_total,
			]
		)
	if sim.diplomacy_mobilization_evaluation_cache_total != actions.size():
		failures.append(
			"多 action 缓存隔离错误 expected=%d actual=%d" % [
				actions.size(),
				sim.diplomacy_mobilization_evaluation_cache_total,
			]
		)
	sim.free()


func _make_diplomacy_cache_fixture(disable_cache: bool) -> Simulation:
	var fixture_state := GameState.new()
	fixture_state.generate_grid_world(32021)
	for nation_a in range(fixture_state.nations.size()):
		for nation_b in range(nation_a + 1, fixture_state.nations.size()):
			fixture_state.set_diplomatic_relation(
				nation_a, nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	fixture_state.set_diplomatic_relation(
		0, 3, GameState.DiplomaticRelation.ALLIED
	)
	fixture_state.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.ALLIED
	)
	var fixture_sim := Simulation.new()
	fixture_sim.diplomacy_mobilization_cache_disabled = disable_cache
	root.add_child(fixture_sim)
	fixture_sim.setup(fixture_state)
	return fixture_sim


func _make_neutral_diplomacy_fixture() -> Simulation:
	var fixture_state := GameState.new()
	fixture_state.generate_grid_world(32022)
	for nation_a in range(fixture_state.nations.size()):
		for nation_b in range(nation_a + 1, fixture_state.nations.size()):
			fixture_state.set_diplomatic_relation(
				nation_a, nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var fixture_sim := Simulation.new()
	root.add_child(fixture_sim)
	fixture_sim.setup(fixture_state)
	return fixture_sim


func _state_fingerprint(game_state: GameState) -> PackedByteArray:
	return var_to_bytes(_snapshot_value(game_state))


func _snapshot_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			return _snapshot_object(value as Object)
		TYPE_ARRAY:
			var array_result: Array = []
			for item in value as Array:
				array_result.append(_snapshot_value(item))
			return array_result
		TYPE_DICTIONARY:
			var entries: Array = []
			for key in value as Dictionary:
				var encoded_key: Variant = _snapshot_value(key)
				entries.append([
					str(encoded_key), encoded_key,
					_snapshot_value((value as Dictionary)[key]),
				])
			entries.sort_custom(func(a: Array, b: Array) -> bool:
				return str(a[0]) < str(b[0])
			)
			var dictionary_result: Array = ["Dictionary"]
			for entry in entries:
				dictionary_result.append([entry[1], entry[2]])
			return dictionary_result
		_:
			return value


func _snapshot_object(value: Object) -> Variant:
	if value == null:
		return null
	if value is RandomNumberGenerator:
		return ["RandomNumberGenerator", value.seed, value.state]
	var script_path := ""
	var script_value: Variant = value.get_script()
	if script_value is Script:
		script_path = (script_value as Script).resource_path
	var properties: Array = []
	var names: Array[String] = []
	for property_value in value.get_property_list():
		var property: Dictionary = property_value
		var name := str(property.get("name", ""))
		if (
			name == "script"
			or int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE == 0
		):
			continue
		names.append(name)
	names.sort()
	for name in names:
		properties.append([name, _snapshot_value(value.get(name))])
	var meta_names := value.get_meta_list()
	meta_names.sort()
	for meta_name in meta_names:
		properties.append([
			"@meta:" + str(meta_name),
			_snapshot_value(value.get_meta(meta_name)),
		])
	return [value.get_class(), script_path, properties]


func _new_bucket() -> Dictionary:
	var values := {}
	for stage in (
		STAGES
		+ AI_STAGES
		+ CAMPAIGN_STAGES
		+ SUPPLY_STAGES
		+ MONTHLY_STAGES
		+ DIPLOMACY_STAGES
	):
		values[stage] = [] as Array[int]
	return {
		"count": 0,
		"values": values,
	}


func _record(bucket: Dictionary, profile: Dictionary) -> void:
	bucket["count"] = int(bucket["count"]) + 1
	var values: Dictionary = bucket["values"]
	for stage in (
		STAGES
		+ AI_STAGES
		+ CAMPAIGN_STAGES
		+ SUPPLY_STAGES
		+ MONTHLY_STAGES
		+ DIPLOMACY_STAGES
	):
		(values[stage] as Array[int]).append(
			int(profile.get(stage, 0))
		)


func _print_bucket(label: String, bucket: Dictionary) -> void:
	var count := int(bucket["count"])
	if count <= 0:
		print("%s: n=0" % label)
		return
	var values: Dictionary = bucket["values"]
	var total_avg := _average(values["total"])
	print("%s: n=%d total均值=%.2fms total峰值=%.2fms" % [
		label,
		count,
		total_avg / 1000.0,
		float(_peak(values["total"])) / 1000.0,
	])
	for stage in STAGES:
		if stage == "total":
			continue
		var avg := _average(values[stage])
		var share := 100.0 * avg / maxf(total_avg, 1.0)
		print("  %-18s 均值=%7.2fms 峰值=%7.2fms 占比=%5.1f%%" % [
			stage,
			avg / 1000.0,
			float(_peak(values[stage])) / 1000.0,
			share,
		])
	print("  AI 内部：")
	for stage in AI_STAGES:
		var avg := _average(values[stage])
		if avg <= 0.0:
			continue
		if _is_count_stage(stage):
			print("    %-22s 均值=%7.2f 峰值=%7d" % [
				stage,
				avg,
				_peak(values[stage]),
			])
		else:
			print("    %-22s 均值=%7.2fms 峰值=%7.2fms" % [
				stage,
				avg / 1000.0,
				float(_peak(values[stage])) / 1000.0,
			])
	print("  战役规划内部：")
	for stage in CAMPAIGN_STAGES:
		var avg := _average(values[stage])
		if avg <= 0.0:
			continue
		print("    %-22s 均值=%7.2fms 峰值=%7.2fms" % [
			stage,
			avg / 1000.0,
			float(_peak(values[stage])) / 1000.0,
		])
	print("  补给内部：")
	for stage in SUPPLY_STAGES:
		var avg := _average(values[stage])
		if avg <= 0.0:
			continue
		print("    %-22s 均值=%7.2fms 峰值=%7.2fms" % [
			stage,
			avg / 1000.0,
			float(_peak(values[stage])) / 1000.0,
		])
	print("  月度内部：")
	for stage in MONTHLY_STAGES:
		var avg := _average(values[stage])
		if avg <= 0.0:
			continue
		print("    %-22s 均值=%7.2fms 峰值=%7.2fms" % [
			stage,
			avg / 1000.0,
			float(_peak(values[stage])) / 1000.0,
		])
	print("  外交内部：")
	for stage in DIPLOMACY_STAGES:
		var avg := _average(values[stage])
		if avg <= 0.0:
			continue
		print("    %-22s 均值=%7.2fms 峰值=%7.2fms" % [
			stage,
			avg / 1000.0,
			float(_peak(values[stage])) / 1000.0,
		])


func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += int(value)
	return float(total) / float(values.size())


func _peak(values: Array) -> int:
	var result := 0
	for value in values:
		result = maxi(result, int(value))
	return result


func _is_count_stage(stage: String) -> bool:
	return (
		stage.ends_with("_builds")
		or stage.ends_with("_hits")
		or stage.ends_with("_misses")
		or stage.ends_with("_source_sets")
		or stage.ends_with("_emitted")
		or stage.ends_with("_count")
		or stage.ends_with("_hub_score_calls")
		or stage.ends_with("_hub_sort_calls")
		or stage.ends_with("_hub_value_calls")
	)


func _war_pairs(state: GameState) -> int:
	var result := 0
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			if state.is_enemy(a, b):
				result += 1
	return result


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
