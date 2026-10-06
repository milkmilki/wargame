class_name DebugRunLog
extends RefCounted
## 调试运行的复现索引；独立于模拟随机流，写入后立即落盘。

const DIRECTORY := "user://debug_runs"
const CHECKPOINT_DAYS := 30
var path: String = ""
var _file: FileAccess
var _world_index: int = 0
var _last_day: int = 0

func begin(scene: String) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if directory_error != OK: return directory_error
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	path = DIRECTORY.path_join("run-%s-%d-%d.jsonl" % [stamp, OS.get_process_id(), Time.get_ticks_usec()])
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null: return FileAccess.get_open_error()
	record("session_start", {"scene": scene, "engine": Engine.get_version_info(),
		"code": _code_revision(), "combat_rules_version": Combat.COMBAT_RULES_VERSION,
		"snapshot_schema": NativeSnapshotBuilder.SCHEMA_VERSION})
	print("[DEBUG_RUN] 日志：" + ProjectSettings.globalize_path(path))
	return OK

func world_started(state: GameState, settings: Dictionary, source: String) -> void:
	if _file == null: return
	_world_index += 1
	_last_day = state.day
	var template_path := path.get_basename() + "-world%d-map.json" % _world_index
	var template := FileAccess.open(template_path, FileAccess.WRITE)
	var template_error := FileAccess.get_open_error()
	if template != null:
		template.store_string(JSON.stringify(MapDefinition.from_state(state)))
		template.flush()
		template_error = template.get_error()
		template.close()
	var summary := {"seed": state.world_seed, "world_index": _world_index, "source": source,
		"day": state.day, "settings": settings, "nation_count": state.nations.size(),
		"city_count": state.cities.size(), "army_count": state.armies.size(),
		"rng_state": str(state.rng.state), "initial_map_template": template_path if template_error == OK else "",
		"map_template_error": error_string(template_error)}
	record("world_start", summary)
	print("[DEBUG_RUN] 新局%d seed=%d source=%s" % [_world_index, state.world_seed, source])

func checkpoint(state: GameState) -> void:
	if _file == null or state == null or state.day < _last_day + CHECKPOINT_DAYS: return
	_last_day = state.day
	record("checkpoint", _progress(state))

func record(event: String, details: Dictionary) -> void:
	if _file == null: return
	var entry := details.duplicate()
	entry["event"] = event
	entry["utc"] = Time.get_datetime_string_from_system(true)
	_file.store_line(JSON.stringify(entry))
	_file.flush()
	if _file.get_error() != OK:
		push_warning("调试日志写入失败：" + ProjectSettings.globalize_path(path))
		_file.close()
		_file = null

func close(state: GameState) -> void:
	record("session_end", _progress(state) if state != null else {})
	if _file != null:
		_file.close()
		_file = null

func _progress(state: GameState) -> Dictionary:
	var wars := state.war_relation_ids.values().duplicate()
	wars.sort()
	var unique_wars: Array = []
	for id in wars:
		if unique_wars.is_empty() or unique_wars.back() != id: unique_wars.append(id)
	var successions: Array = []
	for value in state.succession_conflicts.values():
		var conflict := value as SuccessionConflict
		successions.append({"nation": conflict.nation_id, "rebel": conflict.rebel_nation_id,
			"war_id": conflict.war_id, "challenger_person": conflict.challenger_person_id,
			"crown_person": conflict.crown_person_id, "challenger_armies": conflict.army_ids,
			"crown_armies": conflict.crown_army_ids})
	return {"world_index": _world_index, "seed": state.world_seed, "day": state.day,
		"nation_count": state.nations.size(), "army_count": state.armies.size(),
		"battle_count": state.battles.size(), "war_ids": unique_wars,
		"succession_conflicts": successions, "rng_state": str(state.rng.state)}

func _code_revision() -> Dictionary:
	var project := ProjectSettings.globalize_path("res://")
	if not DirAccess.dir_exists_absolute(project.path_join(".git")) and not FileAccess.file_exists(project.path_join(".git")):
		return {"git_available": false}
	var head: Array = []
	var status: Array = []
	var head_error := OS.execute("git", ["-C", project, "rev-parse", "HEAD"], head, false)
	var status_error := OS.execute("git", ["-C", project, "status", "--porcelain=v1"], status, false)
	return {"git_available": head_error == 0 and status_error == 0,
		"head": str(head[0]).strip_edges() if head_error == 0 and not head.is_empty() else "",
		"worktree_status": str(status[0]).strip_edges() if status_error == 0 and not status.is_empty() else ""}
