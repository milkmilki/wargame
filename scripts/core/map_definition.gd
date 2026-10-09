class_name MapDefinition
extends RefCounted
## Atlas new-game templates. Campaign state is deliberately excluded.
const FORMAT := "world-war-map"
const VERSION := 9
const MIN_SUPPORTED_VERSION := 9
const USER_MAP_DIRECTORY := "user://maps"

static func from_state(state: GameState) -> Dictionary:
	if state.atlas_layout.is_empty(): return {}
	return load("res://scripts/atlas/military_template.gd").encode(state)

static func validate(data: Dictionary) -> String:
	if data.get("map_kind") != "atlas_military":
		return "仅支持 Atlas 2D 地图模板（版本9）；旧地图模板已移除。"
	return load("res://scripts/atlas/military_template.gd").validate(data)

static func safe_user_path(file_name: String) -> String:
	var clean := file_name.strip_edges().get_file()
	if clean.is_empty():
		clean = "custom_map.json"
	if not clean.to_lower().ends_with(".json"):
		clean += ".json"
	return USER_MAP_DIRECTORY.path_join(clean)


static func save_state(state: GameState, file_name: String) -> Dictionary:
	var definition := from_state(state)
	var validation_error := validate(definition)
	if not validation_error.is_empty():
		return {"ok": false, "error": validation_error}
	var path := safe_user_path(file_name)
	var absolute_directory := ProjectSettings.globalize_path(
		USER_MAP_DIRECTORY
	)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		absolute_directory
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "无法创建地图目录。"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": "无法写入地图文件（错误码 %d）。"
				% FileAccess.get_open_error(),
		}
	file.store_string(JSON.stringify(definition, "  "))
	file.close()
	return {"ok": true, "path": path}


static func load_file(file_name: String) -> Dictionary:
	var path := safe_user_path(file_name)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "地图文件不存在：%s" % path}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "error": "地图 JSON 格式错误。"}
	var data := parsed as Dictionary
	var validation_error := validate(data)
	if not validation_error.is_empty():
		return {"ok": false, "error": validation_error}
	return {"ok": true, "path": path, "data": data}
