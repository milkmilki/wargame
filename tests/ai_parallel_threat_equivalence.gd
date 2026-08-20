extends SceneTree
## 运行时 AI 优化等价性：两个同 seed 世界都走 _advance_day(true)。基线关闭
## Threat/Defense 多核及快照资源缓存复用；优化世界全部开启。
## 最终战略、军制、防区和命令状态必须完全一致。

var _phase := 0
var _target_days := 30
var _active_sim: Simulation
var _active_state: GameState
var _baseline_fingerprint := ""
var _baseline_elapsed_usec := 0
var _baseline_threat_usec := 0
var _baseline_threat_runs := 0
var _baseline_defense_usec := 0
var _baseline_defense_runs := 0
var _active_started_usec := 0
var _nation_count := 40
var _city_count := 160


func _init() -> void:
	_target_days = _env_int("AI_THREAT_EQUIV_DAYS", 30)
	_nation_count = _env_int("AI_THREAT_EQUIV_NATIONS", 40)
	_city_count = _env_int("AI_THREAT_EQUIV_CITIES", 160)
	_start_world(true)


func _start_world(serial_threat: bool) -> void:
	_active_state = GameState.new()
	_active_state.generate_world(12345, _nation_count, _city_count)
	_active_sim = Simulation.new()
	root.add_child(_active_sim)
	_active_sim.setup(_active_state)
	_active_sim.ai_staggered_decisions = false
	_active_sim.ai_parallel_threat_disabled = serial_threat
	_active_sim.ai_parallel_defense_disabled = serial_threat
	_active_sim.ai_snapshot_resource_cache_reuse_disabled = serial_threat
	_active_sim.runtime_day_committed.connect(_on_day_committed)
	_active_sim.set_speed_multiplier(32.0)
	_active_started_usec = Time.get_ticks_usec()


func _on_day_committed(day: int) -> void:
	if day >= _target_days:
		_active_sim.paused = true


func _process(_delta: float) -> bool:
	if _phase == 2:
		return false
	if (
		_active_state.day < _target_days
		or _active_sim.runtime_day_in_progress()
	):
		return false
	var elapsed := Time.get_ticks_usec() - _active_started_usec
	var fingerprint := _world_fingerprint(_active_state)
	if _phase == 0:
		_baseline_fingerprint = fingerprint
		_baseline_elapsed_usec = elapsed
		_baseline_threat_usec = _active_sim.ai_threat_worker_total_usec
		_baseline_threat_runs = _active_sim.ai_threat_worker_runs
		_baseline_defense_usec = _active_sim.ai_defense_worker_total_usec
		_baseline_defense_runs = _active_sim.ai_defense_worker_runs
		_active_sim.queue_free()
		_phase = 1
		_start_world(false)
		return false
	var equivalent := fingerprint == _baseline_fingerprint
	print("=== AI 运行时优化等价性 %d国/%d城/%d天 ===" % [
		_nation_count, _city_count, _target_days,
	])
	print("串行=%.1fms 多核=%.1fms 加速=%.2fx" % [
		float(_baseline_elapsed_usec) / 1000.0,
		float(elapsed) / 1000.0,
		float(_baseline_elapsed_usec) / maxf(float(elapsed), 1.0),
	])
	print("Threat worker: 串行=%.1fms(%d轮) 多核=%.1fms(%d轮,%d worker) 加速=%.2fx" % [
		float(_baseline_threat_usec) / 1000.0, _baseline_threat_runs,
		float(_active_sim.ai_threat_worker_total_usec) / 1000.0,
		_active_sim.ai_threat_worker_runs, _active_sim.ai_threat_worker_count_last,
		float(_baseline_threat_usec) / maxf(float(_active_sim.ai_threat_worker_total_usec), 1.0),
	])
	print("Defense worker: 串行=%.1fms(%d轮) 多核=%.1fms(%d轮,%d worker) 加速=%.2fx" % [
		float(_baseline_defense_usec) / 1000.0, _baseline_defense_runs,
		float(_active_sim.ai_defense_worker_total_usec) / 1000.0,
		_active_sim.ai_defense_worker_runs, _active_sim.ai_defense_worker_count_last,
		float(_baseline_defense_usec) / maxf(float(_active_sim.ai_defense_worker_total_usec), 1.0),
	])
	print("verdict=", "AI_RUNTIME_EQUIVALENT" if equivalent else "AI_RUNTIME_DIVERGED")
	_active_sim.queue_free()
	_finish.call_deferred(0 if equivalent else 1)
	_phase = 2
	return false


func _finish(exit_code: int) -> void:
	await process_frame
	await process_frame
	quit(exit_code)


func _world_fingerprint(state: GameState) -> String:
	var cities := []
	for city in state.cities:
		cities.append([city.id, city.owner_nation, city.fort_strength, city.food_storage])
	var nations := []
	for nation in state.nations:
		nations.append([
			nation.id, nation.alive, nation.treasury_gold, nation.manpower_pool,
			nation.granary_food, nation.last_food_demand, nation.food_demand_ema,
			nation.war_preparation_target_nation,
			nation.war_preparation_objective_city,
			nation.campaign_preparation_targets,
			nation.campaign_preparation_assignments,
			nation.campaign_preparation_group_assignments,
			nation.campaign_attack_assignments,
			nation.campaign_attack_echelons,
			nation.campaign_active_echelons,
			nation.campaign_launched_armies,
			_battle_groups_fingerprint(nation),
			_frontier_sectors_fingerprint(nation),
			nation.ai_last_force_action, nation.ai_last_force_day,
		])
	var armies := []
	for army in state.armies:
		armies.append([
			army.id, army.owner_nation, army.size, army.state, army.location_city,
			army.move_from, army.move_to, int(round(army.move_progress * 1000000.0)),
			army.path, int(round(army.morale * 1000000.0)),
			int(round(army.supply_ratio * 1000000.0)), army.starving,
			army.strategic_role, army.battle_group_id,
			army.line_assignment_city, army.line_assignment_posture,
			army.line_assignment_edge, army.ai_action, army.ai_target_city,
			army.ai_order_created_day, army.ai_order_until_day,
		])
	return str([state.day, state.winner, cities, nations, armies])


func _battle_groups_fingerprint(nation: Nation) -> Array:
	var result := []
	for group in nation.battle_groups:
		result.append([
			group.id, group.owner_nation, group.created_day,
		])
	return result


func _frontier_sectors_fingerprint(nation: Nation) -> Array:
	var result := []
	var city_ids := nation.frontier_defense_sectors.keys()
	city_ids.sort()
	for city_id_value in city_ids:
		var sector: FrontierDefenseSector = (
			nation.frontier_defense_sectors[city_id_value]
		)
		result.append([
			sector.city_id, sector.owner_nation,
			sector.topology_revision, sector.state,
			sector.edge_neighbors, sector.assigned_army_ids,
		])
	return result


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
