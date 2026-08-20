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
	"ai_threat",
	"ai_snapshot_threat",
	"ai_defense",
	"ai_declaration_launches",
	"ai_force_structure",
	"ai_force_context",
	"ai_force_wars",
	"ai_force_food",
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
	"diplomacy_peace",
	"diplomacy_leave_alliance",
	"diplomacy_war",
	"diplomacy_alliance",
	"diplomacy_enfeoff",
	"diplomacy_centralization",
]


func _init() -> void:
	var nations := _env_int("PHASE_NATIONS", 4)
	var cities := _env_int("PHASE_CITIES", 160)
	var days := _env_int("PHASE_DAYS", 365)
	var state := GameState.new()
	state.generate_world(12345, nations, cities)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.tick_phase_profiling_enabled = true
	sim.ai_force_resource_cache_disabled = (
		OS.get_environment("PHASE_DISABLE_FORCE_RESOURCE_CACHE") == "1"
	)
	sim.ai_decision_context_disabled = (
		OS.get_environment("PHASE_DISABLE_AI_CONTEXT") == "1"
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
	print("verdict=WAR_PHASE_PROBE_DONE")
	sim.free()
	quit(0)


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
