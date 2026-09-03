extends SceneTree
## 战争期运行时调度等价守卫：同步月度经济/单帧行军与 worker+分帧路径
## 推进相同的 60 天，最终完整 GameState 必须逐属性一致。

var _phase := 0
var _baseline_fingerprint := PackedByteArray()
var _active_sim: Simulation
var _active_state: GameState
var _target_days: int


func _init() -> void:
	_target_days = _env_int("WAR_RUNTIME_EQ_DAYS", 60)
	_start_world(true)


func _start_world(disable_optimized_scheduling: bool) -> void:
	_active_state = GameState.new()
	_active_state.generate_world(12345, 20, 100)
	_force_adjacent_wars(_active_state, 4)
	_active_sim = Simulation.new()
	root.add_child(_active_sim)
	_active_sim.setup(_active_state)
	_active_sim.monthly_economy_worker_disabled = disable_optimized_scheduling
	_active_sim.movement_frame_slicing_disabled = disable_optimized_scheduling
	_active_sim.runtime_day_committed.connect(_on_runtime_day_committed)
	_active_sim.set_speed_multiplier(32.0)


func _process(_delta: float) -> bool:
	if _phase >= 2:
		return false
	if _active_state.day < _target_days or _active_sim.runtime_day_in_progress():
		return false
	if _phase == 0:
		_baseline_fingerprint = _state_fingerprint(_active_state)
		_active_sim.queue_free()
		_phase = 1
		_start_world(false)
		return false
	var optimized_fingerprint := _state_fingerprint(_active_state)
	var equivalent := optimized_fingerprint == _baseline_fingerprint
	print("=== 战争/外交运行时调度等价校验 %d天 ===" % _target_days)
	print("verdict=%s" % (
		"WAR_DIPLOMACY_RUNTIME_EQUIVALENT"
		if equivalent
		else "WAR_DIPLOMACY_RUNTIME_DIVERGED"
	))
	_phase = 2
	_active_sim.queue_free()
	quit(0 if equivalent else 1)
	return false


func _on_runtime_day_committed(day: int) -> void:
	if day >= _target_days:
		_active_sim.paused = true


func _force_adjacent_wars(state: GameState, count: int) -> void:
	var pairs: Array[Vector2i] = []
	for edge in state.edges:
		var owner_a := state.cities[edge.city_a].owner_nation
		var owner_b := state.cities[edge.city_b].owner_nation
		if owner_a < 0 or owner_b < 0:
			continue
		var pair := Vector2i(mini(owner_a, owner_b), maxi(owner_a, owner_b))
		if owner_a != owner_b and not pairs.has(pair):
			pairs.append(pair)
	pairs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y)
	)
	var used := {}
	var selected := 0
	for pair in pairs:
		if selected >= count:
			break
		if used.has(pair.x) or used.has(pair.y):
			continue
		state.set_diplomatic_relation(
			pair.x, pair.y, GameState.DiplomaticRelation.WAR
		)
		used[pair.x] = true
		used[pair.y] = true
		selected += 1


func _state_fingerprint(game_state: GameState) -> PackedByteArray:
	return var_to_bytes(_snapshot_value(game_state))


func _snapshot_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			return _snapshot_object(value as Object)
		TYPE_ARRAY:
			var result: Array = []
			for item in value as Array:
				result.append(_snapshot_value(item))
			return result
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
			var result: Array = ["Dictionary"]
			for entry in entries:
				result.append([entry[1], entry[2]])
			return result
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
	var names: Array[String] = []
	for property_value in value.get_property_list():
		var property: Dictionary = property_value
		var name := str(property.get("name", ""))
		if (
			name != "script"
			and int(property.get("usage", 0)) & PROPERTY_USAGE_STORAGE != 0
		):
			names.append(name)
	names.sort()
	var properties: Array = []
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


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return fallback if raw.is_empty() else int(raw)
