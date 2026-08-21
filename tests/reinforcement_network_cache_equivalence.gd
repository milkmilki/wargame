extends SceneTree
## 等价性守卫：在相同真实运行时路径下，证明“每国一次补员可达网络”与
## “每支军队单独图搜索”旧逻辑产生完全相同的世界状态。两个世界都保留补员
## 分帧，唯一区别是 reinforcement_network_cache_disabled。

var _phase := 0
var _baseline_state_fp: String = ""
var _active_sim: Simulation
var _active_state: GameState
var _target_days: int
var _nations: int
var _cities: int


func _init() -> void:
	_target_days = _env_int("REINF_NETWORK_EQUIV_DAYS", 90)
	_nations = _env_int("REINF_NETWORK_EQUIV_NATIONS", 40)
	_cities = _env_int("REINF_NETWORK_EQUIV_CITIES", 160)
	_start_world(true)


func _start_world(disable_cache: bool) -> void:
	_active_state = GameState.new()
	_active_state.generate_world(12345, _nations, _cities)
	_active_sim = Simulation.new()
	root.add_child(_active_sim)
	_active_sim.setup(_active_state)
	_active_sim.reinforcement_network_cache_disabled = disable_cache
	_active_sim.runtime_day_committed.connect(
		_on_runtime_day_committed
	)
	_active_sim.set_speed_multiplier(32.0)


func _process(_delta: float) -> bool:
	if _phase == 2:
		return false
	if (
		_active_state.day < _target_days
		and _active_state.winner == -1
	):
		return false
	# state.day 在 tick 开头递增；必须等整天提交、后台 worker 全部回收后
	# 才能快照或释放 Simulation，否则会把仍写结果数组的任务悬空。
	if _active_sim.runtime_day_in_progress():
		return false
	if _phase == 0:
		_baseline_state_fp = _state_fp(_active_state)
		_active_sim.queue_free()
		_phase = 1
		_start_world(false)
		return false
	_finish()
	return false


func _finish() -> void:
	_phase = 2
	var optimized_fp := _state_fp(_active_state)
	var reachability_mismatches := _reachability_mismatches(
		_active_state
	)
	var equivalent := (
		optimized_fp == _baseline_state_fp
		and reachability_mismatches == 0
	)
	print(
		"=== 补员可达网络等价校验 (%d国/%d城/%d天) ==="
		% [_nations, _cities, _active_state.day]
	)
	print("状态逐字段等价=%s" % str(equivalent))
	print("逐军可达性不一致=%d" % reachability_mismatches)
	if not equivalent:
		print("baseline_hash=%d optimized_hash=%d" % [
			hash(_baseline_state_fp),
			hash(optimized_fp),
		])
	print(
		"verdict=%s"
		% (
			"REINF_NETWORK_EQUIVALENT"
			if equivalent
			else "REINF_NETWORK_DIVERGED"
		)
	)
	_active_sim.queue_free()
	quit(0 if equivalent else 1)


func _on_runtime_day_committed(day: int) -> void:
	if day >= _target_days:
		_active_sim.paused = true


func _reachability_mismatches(world: GameState) -> int:
	var networks := {}
	for nation in world.nations:
		networks[nation.id] = (
			Pathfinding.build_manpower_hub_network(
				world,
				nation.id
			)
		)
	var mismatches := 0
	for army in world.armies:
		var legacy := Pathfinding.can_reach_manpower_hub(
			world,
			army
		)
		var optimized := (
			Pathfinding.can_reach_manpower_hub_from_network(
				world,
				army,
				networks[army.owner_nation]
			)
		)
		if legacy == optimized:
			continue
		mismatches += 1
		if mismatches <= 10:
			print(
				"army=%d owner=%d legacy=%s optimized=%s"
				% [
					army.id,
					army.owner_nation,
					str(legacy),
					str(optimized),
				]
			)
	return mismatches


func _state_fp(world: GameState) -> String:
	var cities_fp: Array = []
	for city in world.cities:
		cities_fp.append([
			city.id,
			city.owner_nation,
			world.recognized_owner_of(city.id),
			city.fort_strength,
			city.food_storage,
		])
	var nations_fp: Array = []
	for nation in world.nations:
		nations_fp.append([
			nation.id,
			nation.alive,
			nation.manpower_pool,
			nation.treasury_gold,
			nation.granary_food,
			nation.war_preparation_target_nation,
			nation.campaign_preparation_targets,
			nation.campaign_preparation_assignments,
			nation.campaign_attack_assignments,
		])
	var armies_fp: Array = []
	for army in world.armies:
		armies_fp.append([
			army.id,
			army.owner_nation,
			army.size,
			army.state,
			army.location_city,
			army.move_from,
			army.move_to,
			army.move_progress,
			army.path,
			army.morale,
			army.supply_ratio,
			army.ai_action,
			army.ai_target_city,
			army.line_assignment_city,
		])
	return str([
		world.day,
		world.winner,
		world.ownership_revision,
		world.diplomacy_revision,
		cities_fp,
		nations_fp,
		armies_fp,
	])


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
