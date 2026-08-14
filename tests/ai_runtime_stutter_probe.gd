extends SceneTree
## 真实运行路径的卡顿探针。此前所有 profiling 都跑同步 _advance_day(false)，
## 而真实游戏跑的是 _process 帧循环 + spread_runtime_work=true（后台线程+分帧）。
## 本探针把 Simulation 作为子节点交给引擎自然逐帧驱动，测量每帧墙钟耗时，
## 专抓 AI 决策日（每 10 天）的单帧尖峰——玩家感知的"卡一下"。
## 可调：AI_STUT_NATIONS(40) AI_STUT_CITIES(160) AI_STUT_DAYS(120) AI_STUT_SPEED(8)

var _sim: Simulation
var _state: GameState
var _frame_times: Array[float] = []
var _ai_day_frame_peak: Array[float] = []
var _target_days: int
var _prev_day: int = 0
var _last_frame_usec: int = 0
var _done := false
var _peak_frame_ms: float = 0.0
var _peak_frame_day: int = 0
var _peak_is_month: bool = false
var _peak_stage: StringName = &""
var _slow_frames_by_stage: Dictionary = {}


func _init() -> void:
	var nations := _env_int("AI_STUT_NATIONS", 40)
	var cities := _env_int("AI_STUT_CITIES", 160)
	_target_days = _env_int("AI_STUT_DAYS", 120)
	var speed := _env_int("AI_STUT_SPEED", 8)

	_state = GameState.new()
	_state.generate_world(12345, nations, cities)
	_sim = Simulation.new()
	root.add_child(_sim)
	_sim.setup(_state)
	_sim.runtime_day_committed.connect(_on_runtime_day_committed)
	_sim.runtime_stage_profiling_enabled = true
	_sim.supply_network_parallel_prebuild_disabled = (
		OS.get_environment(
			"AI_STUT_SERIAL_SUPPLY_NETWORKS"
		) == "1"
	)
	_sim.supply_network_cache_disabled = (
		OS.get_environment(
			"AI_STUT_REBUILD_SUPPLY_NETWORKS"
		) == "1"
	)
	_sim.ai_staggered_decisions = (
		OS.get_environment(
			"AI_STUT_FORCE_ALL_AI"
		) != "1"
	)
	_sim.set_speed_multiplier(float(speed))

	print(
		(
			"=== 真实运行路径卡顿探针 国=%d 城=%d "
			+ "目标天=%d 倍率=%dx 补给网络=%s ==="
		) % [
			nations,
			cities,
			_target_days,
			speed,
			(
				"串行worker"
				if _sim
					.supply_network_parallel_prebuild_disabled
				else "多核分片"
			),
		]
	)
	_last_frame_usec = Time.get_ticks_usec()


## 引擎自然逐帧回调；Simulation 作为子节点已被引擎自动 _process。
## 这里只测量「帧间墙钟间隔」——若某帧主线程被 AI 阻塞，间隔会飙高。
## 返回 true 会退出 SceneTree，因此常态返回 false。
func _process(_delta: float) -> bool:
	if _done:
		return false
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _last_frame_usec) / 1000.0
	_last_frame_usec = now
	_frame_times.append(frame_ms)

	if _state.day != _prev_day:
		if _state.day % Simulation.AI_DECISION_INTERVAL_DAYS == 0:
			_ai_day_frame_peak.append(frame_ms)
		_prev_day = _state.day
	if frame_ms > _peak_frame_ms:
		_peak_frame_ms = frame_ms
		_peak_frame_day = _state.day
		_peak_is_month = (_state.day % 30 == 0)
		_peak_stage = _current_runtime_stage()
	if frame_ms > 16.0:
		var stage := str(_current_runtime_stage())
		if not _slow_frames_by_stage.has(stage):
			_slow_frames_by_stage[stage] = {
				"over_16": 0,
				"over_33": 0,
				"peak_ms": 0.0,
			}
		var stage_report: Dictionary = (
			_slow_frames_by_stage[stage]
		)
		stage_report["over_16"] = (
			int(stage_report["over_16"]) + 1
		)
		if frame_ms > 33.0:
			stage_report["over_33"] = (
				int(stage_report["over_33"]) + 1
			)
		stage_report["peak_ms"] = maxf(
			float(stage_report["peak_ms"]),
			frame_ms
		)

	if (
		(_state.day >= _target_days or _state.winner != -1)
		and not _sim.runtime_day_in_progress()
	):
		_finish()
	return false


func _on_runtime_day_committed(day: int) -> void:
	if day >= _target_days:
		_sim.paused = true


func _finish() -> void:
	_done = true
	# 丢弃第 1 帧（含启动开销）。
	if _frame_times.size() > 1:
		_frame_times.remove_at(0)
	var overall_peak := 0.0
	var overall_sum := 0.0
	for t in _frame_times:
		overall_peak = maxf(overall_peak, t)
		overall_sum += t
	var ai_peak := 0.0
	var ai_sum := 0.0
	for t in _ai_day_frame_peak:
		ai_peak = maxf(ai_peak, t)
		ai_sum += t
	var over_16 := 0
	var over_33 := 0
	var over_100 := 0
	for t in _frame_times:
		if t > 100.0:
			over_100 += 1
		elif t > 33.0:
			over_33 += 1
		elif t > 16.0:
			over_16 += 1

	print("推进至第 %d 天 总帧数=%d" % [_state.day, _frame_times.size()])
	print("全部帧: 峰值=%.1fms 均值=%.2fms" % [
		overall_peak,
		overall_sum / maxf(float(_frame_times.size()), 1.0),
	])
	print("AI决策日帧: n=%d 峰值=%.1fms 均值=%.1fms" % [
		_ai_day_frame_peak.size(),
		ai_peak,
		ai_sum / maxf(float(_ai_day_frame_peak.size()), 1.0),
	])
	print("掉帧统计: 16-33ms=%d  33-100ms=%d  >100ms=%d (总%d帧)" % [
		over_16, over_33, over_100, _frame_times.size(),
	])
	print("峰值帧落在第 %d 天 (月结算日=%s, 阶段=%s)" % [
		_peak_frame_day,
		"是" if _peak_is_month else "否",
		str(_peak_stage) if not _peak_stage.is_empty() else "startup",
	])
	var stage_names := _slow_frames_by_stage.keys()
	stage_names.sort()
	print("慢帧阶段归因:")
	for stage in stage_names:
		var report: Dictionary = _slow_frames_by_stage[stage]
		print("  %-24s >16ms=%d >33ms=%d 峰值=%.1fms" % [
			stage,
			int(report["over_16"]),
			int(report["over_33"]),
			float(report["peak_ms"]),
		])
	print("verdict=STUTTER_PROBE_DONE")
	_sim.queue_free()
	_quit_after_worker_cleanup.call_deferred()


func _quit_after_worker_cleanup() -> void:
	await process_frame
	await process_frame
	quit(0)


func _current_runtime_stage() -> StringName:
	if _state.day <= 0:
		return &"startup"
	if not _sim.runtime_day_in_progress():
		return &"idle"
	return (
		_sim.runtime_profile_stage
		if not _sim.runtime_profile_stage.is_empty()
		else &"unknown"
	)


func _env_int(key: String, fallback: int) -> int:
	var v := OS.get_environment(key)
	return int(v) if not v.is_empty() else fallback
