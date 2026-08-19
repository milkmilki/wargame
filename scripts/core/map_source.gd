class_name MapSource
extends RefCounted
## Single manifest entry point for replaceable packed map sources.

const DEFAULT_MANIFEST := "res://assets/terrain/map_source.json"
const FORMAT := "world-war-map-source"
const VERSION := 1
static var _cache: Dictionary = {}


static func load_manifest(path: String = DEFAULT_MANIFEST) -> Dictionary:
	if _cache.has(path):
		return (_cache[path] as Dictionary).duplicate(true)
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "无法读取地图源清单：%s" % path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Dictionary, "地图源清单不是 JSON 对象：%s" % path)
	var data := parsed as Dictionary
	assert(str(data.get("format", "")) == FORMAT)
	assert(int(data.get("version", -1)) == VERSION)
	var texture_path := str(data.get("texture", ""))
	assert(ResourceLoader.exists(texture_path), "地图源纹理不存在：%s" % texture_path)
	var bbox: Array = data.get("bbox_wgs84", [])
	assert(bbox.size() == 4 and float(bbox[0]) < float(bbox[2]) and float(bbox[1]) < float(bbox[3]))
	_cache[path] = data.duplicate(true)
	return data


static func texture_path(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path)["texture"])


static func aspect_ratio(path: String = DEFAULT_MANIFEST) -> float:
	var bbox: Array = load_manifest(path)["bbox_wgs84"]
	return (float(bbox[2]) - float(bbox[0])) / (float(bbox[3]) - float(bbox[1]))
