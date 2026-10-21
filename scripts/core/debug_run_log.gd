class_name DebugRunLog
extends RefCounted
## 调试运行的复现索引；独立于模拟随机流，写入后立即落盘。

const DIRECTORY := "res://.dbg/debug_runs"
const CHECKPOINT_DAYS := 30
var path: String = ""
var _file: FileAccess
var _world_index: int = 0
var _last_day: int = 0
var _last_vassal_result: Dictionary = {}
var _latest_template: String = ""

func _directory() -> String:
	return DIRECTORY

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _file != null:
		# A RefCounted instance cannot call its own methods after reaching zero.
		DebugRunLog._finish(_file, path, {})
		_file = null

func begin(scene: String) -> Error:
	close(null)
	path = ""
	var directory := ProjectSettings.globalize_path(_directory())
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK: return directory_error
	# Fixed-width start times order sessions even when an older process exits last.
	path = directory.path_join("run-%020d-%010d-%020d.jsonl" % [int(Time.get_unix_time_from_system() * 1000000), OS.get_process_id(), Time.get_ticks_usec()])
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		path = ""
		return FileAccess.get_open_error()
	_world_index = 0
	_last_day = 0
	_last_vassal_result.clear()
	_latest_template = ""
	record("session_start", {"scene": scene, "engine": Engine.get_version_info(),
		"code": _code_revision(), "combat_rules_version": Combat.COMBAT_RULES_VERSION,
		"snapshot_schema": NativeSnapshotBuilder.SCHEMA_VERSION})
	if _file == null:
		DirAccess.remove_absolute(path)
		path = ""
		return ERR_FILE_CANT_WRITE
	_prune(directory)
	print("[DEBUG_RUN] 日志：" + ProjectSettings.globalize_path(path))
	return OK

func world_started(state: GameState, settings: Dictionary, source: String) -> void:
	if _file == null: return
	_world_index += 1
	_last_day = state.day
	_last_vassal_result.clear()
	var template_path := path.get_basename() + "-world%d-map.json" % _world_index
	var template := FileAccess.open(template_path, FileAccess.WRITE)
	var template_error := FileAccess.get_open_error()
	if template != null:
		template.store_string(JSON.stringify(MapDefinition.from_state(state)))
		template.flush()
		template_error = template.get_error()
		template.close()
	if template_error == OK:
		# Publish the replacement before dropping the last good template.
		if not _latest_template.is_empty(): DirAccess.remove_absolute(_latest_template)
		_latest_template = template_path
	elif FileAccess.file_exists(template_path):
		DirAccess.remove_absolute(template_path)
	var summary := {"seed": state.world_seed, "world_index": _world_index, "source": source,
		"day": state.day, "settings": settings, "nation_count": state.nations.size(),
		"city_count": state.cities.size(), "army_count": state.armies.size(),
		"rng_state": str(state.rng.state), "initial_map_template": template_path if template_error == OK else "",
		"map_template_error": error_string(template_error), "generation_metadata": state.generation_metadata.duplicate(true)}
	record("world_start", summary)
	print("[DEBUG_RUN] 新局%d seed=%d source=%s" % [_world_index, state.world_seed, source])

func checkpoint(state: GameState) -> void:
	if state != null and state.last_vassal_conflict_result != _last_vassal_result:
		_last_vassal_result = state.last_vassal_conflict_result.duplicate(true)
		record("vassal_conflict_planning_result", {"seed": state.world_seed, "day": state.day, "result": _last_vassal_result})
	if _file == null or state == null or state.day < _last_day + CHECKPOINT_DAYS: return
	_last_day = state.day
	record("checkpoint", _progress(state))

func record(event: String, details: Dictionary) -> void:
	if _file == null: return
	if _write_record(_file, event, details) != OK:
		push_warning("调试日志写入失败：" + path)
		_file.close()
		_file = null

static func _write_record(file: FileAccess, event: String, details: Dictionary) -> Error:
	var entry := details.duplicate()
	entry["event"] = event
	entry["pid"] = OS.get_process_id()
	entry["utc"] = Time.get_datetime_string_from_system(true)
	file.store_line(JSON.stringify(entry))
	file.flush()
	return file.get_error()

func close(state: GameState) -> void:
	if _file == null: return
	_finish(_file, path, _progress(state) if state != null else {})
	_file = null

static func _finish(file: FileAccess, output_path: String, details: Dictionary) -> void:
	if _write_record(file, "session_end", details) != OK:
		push_warning("调试日志写入失败：" + output_path)
	file.close()
	var closed := FileAccess.open(output_path + ".closed", FileAccess.WRITE)
	if closed != null: closed.close()
	_prune(output_path.get_base_dir())

## Only files with our exact session naming scheme are owned by retention.
## Never recurse: unrelated files, saved maps and other .dbg folders are excluded.
static func _prune(directory: String) -> void:
	var pattern := RegEx.create_from_string("^(run-[0-9]{20}-([0-9]{10})-[0-9]{20})(?:\\.jsonl(?:\\.closed)?|-world[0-9]+-map\\.json)$")
	var runs := {}
	var newest := ""
	for name_value in DirAccess.get_files_at(directory):
		var matched := pattern.search(name_value)
		if matched == null: continue
		var base := matched.get_string(1)
		if not runs.has(base): runs[base] = {"pid": int(matched.get_string(2)), "files": []}
		runs[base].files.append(name_value)
		if name_value == base + ".jsonl" and base > newest: newest = base
	for base in runs:
		if base == newest: continue
		var closed := FileAccess.file_exists(directory.path_join(base + ".jsonl.closed"))
		if not closed and OS.is_process_running(int(runs[base].pid)): continue
		for name_value in runs[base].files:
			var file_path := directory.path_join(name_value)
			var error := DirAccess.remove_absolute(file_path)
			if error != OK and FileAccess.file_exists(file_path):
				push_warning("无法清理旧调试记录：" + ProjectSettings.globalize_path(file_path))

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
		"succession_conflicts": successions, "vassal_conflicts": state.vassal_conflicts.duplicate(true), "rng_state": str(state.rng.state)}

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
