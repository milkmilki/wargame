extends SceneTree
## 等价性守卫：在「同一运行时分帧路径」下，证明补给分帧驱动
## (_resolve_supply_over_frames) 与补给同步驱动 (_resolve_supply) 逐军逐字节等价。
## 两个世界都作为子节点由引擎逐帧驱动 _advance_day(true)，唯一区别是基线世界置
## supply_frame_slicing_disabled=true（补给仍同步一次跑完）。这样隔离出「补给分帧
## 本身」的影响，排除运行时/同步两条路径既有的其他差异。二者应完全一致。

var _phase := 0            # 0=跑基线, 1=跑分帧, 2=完成
var _baseline_state: GameState
var _sliced_sim: Simulation
var _sliced_state: GameState
var _baseline_by_id: Dictionary = {}
var _target_days: int
var _nations: int
var _cities: int
var _active_sim: Simulation
var _active_state: GameState


func _init() -> void:
	_target_days = _env_int("SUPPLY_SLICE_DAYS", 200)
	_nations = _env_int("SUPPLY_SLICE_NATIONS", 40)
	_cities = _env_int("SUPPLY_SLICE_CITIES", 160)
	_start_world(true)   # 先跑基线（补给不分帧，但仍走运行时路径）


func _start_world(disable_slicing: bool) -> void:
	_active_state = GameState.new()
	_active_state.generate_world(12345, _nations, _cities)
	_active_sim = Simulation.new()
	root.add_child(_active_sim)
	_active_sim.setup(_active_state)
	_active_sim.supply_frame_slicing_disabled = disable_slicing
	_active_sim.set_speed_multiplier(32.0)


func _process(_delta: float) -> bool:
	if _phase == 2:
		return false
	if _active_state.day < _target_days and _active_state.winner == -1:
		return false
	# 当前世界推进到目标天。
	if _phase == 0:
		_baseline_state = _active_state
		for army in _baseline_state.armies:
			_baseline_by_id[army.id] = _army_fp(army)
		_active_sim.queue_free()
		_phase = 1
		_start_world(false)   # 再跑分帧世界
		return false
	# _phase == 1：分帧世界完成，比对。
	_sliced_sim = _active_sim
	_sliced_state = _active_state
	_finish()
	return false


func _finish() -> void:
	_phase = 2
	var mismatches := 0
	var checked := 0
	if _baseline_state.armies.size() != _sliced_state.armies.size():
		print("军队数不一致 基线=%d 分帧=%d" % [
			_baseline_state.armies.size(),
			_sliced_state.armies.size(),
		])
		mismatches += 1
	for sliced_army in _sliced_state.armies:
		checked += 1
		var baseline_fp: String = _baseline_by_id.get(sliced_army.id, "")
		if baseline_fp.is_empty():
			mismatches += 1
			if mismatches <= 10:
				print("基线世界缺失 army=%d" % sliced_army.id)
			continue
		if baseline_fp != _army_fp(sliced_army):
			mismatches += 1
			if mismatches <= 10:
				print("army=%d 不一致\n  基线=%s\n  分帧=%s" % [
					sliced_army.id, baseline_fp, _army_fp(sliced_army),
				])
	print("=== 补给分帧等价校验 (同一运行时路径, 基线%d天/分帧%d天) ===" % [
		_target_days, _sliced_state.day,
	])
	print("对比军队=%d 不一致=%d" % [checked, mismatches])
	print("verdict=%s" % (
		"SUPPLY_SLICE_EQUIVALENT" if mismatches == 0 else "SUPPLY_SLICE_DIVERGED"
	))
	_sliced_sim.queue_free()
	quit(0 if mismatches == 0 else 1)


func _army_fp(army: Army) -> String:
	return "sz=%d st=%d mor=%d sr=%d fd=%d sd=%d starv=%s" % [
		army.size,
		army.state,
		int(round(army.morale * 1000000.0)),
		int(round(army.supply_ratio * 1000000.0)),
		int(round(army.supply_food_debt * 1000000.0)),
		int(round(army.supply_debt * 1000000.0)),
		"1" if army.starving else "0",
	]


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
