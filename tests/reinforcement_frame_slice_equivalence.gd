extends SceneTree
## 等价性守卫：在「同一运行时分帧路径」下，证明补员分帧驱动
## (_resolve_reinforcements_over_frames) 与补员同步驱动 (_resolve_reinforcements)
## 逐军逐字节等价。两个世界都由引擎逐帧驱动 _advance_day(true)，唯一区别是基线世界
## 置 reinforcement_frame_slicing_disabled=true。补员每月一次，200 天覆盖多次月结算。

var _phase := 0
var _baseline_by_id: Dictionary = {}
var _sliced_sim: Simulation
var _sliced_state: GameState
var _target_days: int
var _nations: int
var _cities: int
var _active_sim: Simulation
var _active_state: GameState


func _init() -> void:
	_target_days = _env_int("REINF_SLICE_DAYS", 200)
	_nations = _env_int("REINF_SLICE_NATIONS", 40)
	_cities = _env_int("REINF_SLICE_CITIES", 160)
	_start_world(true)


func _start_world(disable_slicing: bool) -> void:
	_active_state = GameState.new()
	_active_state.generate_world(12345, _nations, _cities)
	_active_sim = Simulation.new()
	root.add_child(_active_sim)
	_active_sim.setup(_active_state)
	_active_sim.reinforcement_frame_slicing_disabled = disable_slicing
	_active_sim.set_speed_multiplier(32.0)


func _process(_delta: float) -> bool:
	if _phase == 2:
		return false
	if _active_state.day < _target_days and _active_state.winner == -1:
		return false
	if _phase == 0:
		for army in _active_state.armies:
			_baseline_by_id[army.id] = _army_fp(army)
		_active_sim.queue_free()
		_phase = 1
		_start_world(false)
		return false
	_sliced_sim = _active_sim
	_sliced_state = _active_state
	_finish()
	return false


func _finish() -> void:
	_phase = 2
	var mismatches := 0
	var checked := 0
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
	print("=== 补员分帧等价校验 (同一运行时路径, 基线%d天/分帧%d天) ===" % [
		_target_days, _sliced_state.day,
	])
	print("对比军队=%d 不一致=%d" % [checked, mismatches])
	print("verdict=%s" % (
		"REINF_SLICE_EQUIVALENT" if mismatches == 0 else "REINF_SLICE_DIVERGED"
	))
	_sliced_sim.queue_free()
	quit(0 if mismatches == 0 else 1)


## 补员只改变 army.size 与 nation.manpower_pool，故指纹取 size 即可捕获其结果；
## 附带 state 只为对齐 supply 守卫格式，不参与补员判定。
func _army_fp(army: Army) -> String:
	return "sz=%d own=%d st=%d" % [army.size, army.owner_nation, army.state]


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
