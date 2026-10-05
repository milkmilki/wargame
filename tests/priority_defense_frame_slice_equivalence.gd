extends SceneTree
## 等价性守卫：比较重点城市防御梯队同步推进与分帧推进。
## 两个固定种子世界同步推进到相同日期，再只对目标函数执行同步/分帧 A/B。

var _target_days: int
var _nations: int
var _cities: int
var _baseline_sim: Simulation
var _baseline_state: GameState
var _sliced_sim: Simulation
var _sliced_state: GameState
var _succession_mismatches := 0
const Direct = preload("res://tests/direct_center_camp.gd")


func _init() -> void:
	_target_days = _env_int("PRIORITY_SLICE_DAYS", 75)
	_nations = _env_int("PRIORITY_SLICE_NATIONS", 40)
	_cities = _env_int("PRIORITY_SLICE_CITIES", 160)
	call_deferred("_run")


func _run() -> void:
	await _verify_real_succession_dispatch()
	_baseline_state = GameState.new()
	_baseline_state.generate_world(12345, _nations, _cities)
	_baseline_sim = Simulation.new()
	root.add_child(_baseline_sim)
	_baseline_sim.setup(_baseline_state)
	_baseline_sim.set_process(false)
	_sliced_state = GameState.new()
	_sliced_state.generate_world(12345, _nations, _cities)
	_sliced_sim = Simulation.new()
	root.add_child(_sliced_sim)
	_sliced_sim.setup(_sliced_state)
	_sliced_sim.set_process(false)
	for _day in range(_target_days):
		_baseline_sim._advance_day(false)
		_sliced_sim._advance_day(false)
	_baseline_sim._advance_priority_city_defense_reinforcements()
	await _sliced_sim._advance_priority_city_defense_reinforcements(true)
	_finish()


func _finish() -> void:
	var mismatches := _succession_mismatches
	var checked := 0
	if _baseline_state.armies.size() != _sliced_state.armies.size():
		mismatches += 1
		print("军队数不一致 同步=%d 分帧=%d" % [
			_baseline_state.armies.size(),
			_sliced_state.armies.size(),
		])
	var baseline_by_id := {}
	for baseline_army in _baseline_state.armies:
		baseline_by_id[baseline_army.id] = _army_fp(
			baseline_army
		)
	for sliced_army in _sliced_state.armies:
		checked += 1
		var baseline_fp: String = baseline_by_id.get(
			sliced_army.id,
			""
		)
		if baseline_fp != _army_fp(sliced_army):
			mismatches += 1
			if mismatches <= 10:
				print("army=%d 不一致\n  同步=%s\n  分帧=%s" % [
					sliced_army.id,
					baseline_fp,
					_army_fp(sliced_army),
				])
	print("=== 重点城市防御分帧等价校验 (%d天) ===" % _target_days)
	print("对比军队=%d 不一致=%d" % [checked, mismatches])
	print("verdict=%s" % (
		"PRIORITY_DEFENSE_SLICE_EQUIVALENT"
		if mismatches == 0
		else "PRIORITY_DEFENSE_SLICE_DIVERGED"
	))
	_baseline_sim.queue_free()
	_sliced_sim.queue_free()
	quit(0 if mismatches == 0 else 1)


func _verify_real_succession_dispatch() -> void:
	var fingerprints: Array[String] = []
	for sliced in [false, true]:
		var state: GameState = Direct.fixture()
		var attacker: Army = Direct.army(state, 0, 3, 30000)
		var guard: Army = Direct.army(state, 1, 3, 1000)
		var reserve: Army = Direct.army(state, 1, 4, 30000)
		var conflict := SuccessionConflict.new()
		conflict.nation_id = 1
		conflict.rebel_nation_id = 0
		conflict.capital_city_id = 3
		conflict.camp_city_id = 2
		conflict.war_id = state.war_id_between(0, 1)
		conflict.army_ids = [attacker.id]
		conflict.crown_army_ids = [guard.id, reserve.id]
		state.succession_conflicts[1] = conflict
		var battle := state.new_battle(Battle.Kind.SIEGE)
		battle.city = state.cities[3]
		battle.siege_attacker_nation = 0
		battle.side_a = [attacker]
		battle.side_b = [guard]
		var sim := Simulation.new()
		root.add_child(sim)
		sim.setup(state)
		sim.set_process(false)
		if sliced:
			await sim._advance_priority_city_defense_reinforcements(true)
		else:
			sim._advance_priority_city_defense_reinforcements()
		if reserve.state != Army.State.MOVING:
			_succession_mismatches += 1
		fingerprints.append(_army_fp(reserve))
		sim.free()
	if fingerprints[0] != fingerprints[1]:
		_succession_mismatches += 1
	print("SUCCESSION_PRIORITY_REAL_DISPATCH mismatches=%d" % _succession_mismatches)


func _army_fp(army: Army) -> String:
	return "own=%d st=%d loc=%d mf=%d mt=%d mp=%d sz=%d target=%d action=%d" % [
		army.owner_nation,
		army.state,
		army.location_city,
		army.move_from,
		army.move_to,
		int(round(army.move_progress * 1000000.0)),
		army.size,
		army.ai_target_city,
		army.ai_action,
	]


func _env_int(key: String, fallback: int) -> int:
	var value := OS.get_environment(key)
	return int(value) if not value.is_empty() else fallback
