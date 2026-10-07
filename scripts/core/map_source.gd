class_name MapSource
extends RefCounted
## Single manifest entry point for replaceable packed map sources.

const DEFAULT_MANIFEST := "res://assets/terrain/map_source.json"
const FORMAT := "world-war-map-source"
const VERSION := 1
const EQUIRECTANGULAR := "equirectangular"
const WEB_MERCATOR := "web_mercator"
const MERCATOR_LATITUDE_LIMIT := 85.0511287798066
static var _cache: Dictionary = {}


static func validate_manifest(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "无法读取地图源清单：%s" % path
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return "地图源清单不是 JSON 对象：%s" % path
	var data := parsed as Dictionary
	if str(data.get("format", "")) != FORMAT or int(data.get("version", -1)) != VERSION:
		return "地图源清单格式或版本无效：%s" % path
	if not ResourceLoader.exists(str(data.get("texture", ""))):
		return "地图源纹理不存在：%s" % str(data.get("texture", ""))
	var bbox_value: Variant = data.get("bbox_wgs84")
	if not bbox_value is Array or bbox_value.size() != 4:
		return "地图源地理边界无效：%s" % path
	for value in bbox_value:
		if not (value is float or value is int) or not is_finite(float(value)):
			return "地图源地理边界无效：%s" % path
	if float(bbox_value[0]) >= float(bbox_value[2]) or float(bbox_value[1]) >= float(bbox_value[3]):
		return "地图源地理边界无效：%s" % path
	var projection := str(data.get("projection", EQUIRECTANGULAR))
	if projection not in [EQUIRECTANGULAR, WEB_MERCATOR]:
		return "不支持的地图投影：%s" % projection
	if projection == WEB_MERCATOR and (
		float(bbox_value[0]) < -180.0 or float(bbox_value[2]) > 180.0
		or float(bbox_value[1]) < -MERCATOR_LATITUDE_LIMIT
		or float(bbox_value[3]) > MERCATOR_LATITUDE_LIMIT
	):
		return "Web Mercator 地理边界超出有效范围：%s" % path
	return ""


static func load_manifest(path: String = DEFAULT_MANIFEST) -> Dictionary:
	if _cache.has(path):
		return (_cache[path] as Dictionary).duplicate(true)
	var validation_error := validate_manifest(path)
	assert(validation_error.is_empty(), validation_error)
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "无法读取地图源清单：%s" % path)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	var data := parsed as Dictionary
	_cache[path] = data.duplicate(true)
	return data


static func texture_path(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path)["texture"])


static func aspect_ratio(path: String = DEFAULT_MANIFEST) -> float:
	var bbox: Array = load_manifest(path)["bbox_wgs84"]
	if projection_type(path) == WEB_MERCATOR:
		return deg_to_rad(float(bbox[2]) - float(bbox[0])) / (
			_mercator_y(float(bbox[3])) - _mercator_y(float(bbox[1]))
		)
	return (float(bbox[2]) - float(bbox[0])) / (float(bbox[3]) - float(bbox[1]))


static func projection_type(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path).get("projection", EQUIRECTANGULAR))


static func latitude_limit(path: String = DEFAULT_MANIFEST) -> float:
	return MERCATOR_LATITUDE_LIMIT if projection_type(path) == WEB_MERCATOR else 90.0


static func _mercator_y(latitude: float) -> float:
	return log(tan(PI * 0.25 + deg_to_rad(latitude) * 0.5))


static func latitude_at_y(
	map_y: float, south: float, north: float,
	path: String = DEFAULT_MANIFEST
) -> float:
	if projection_type(path) == WEB_MERCATOR:
		var limit := MERCATOR_LATITUDE_LIMIT
		var projected_y := lerpf(
			_mercator_y(clampf(north, -limit, limit)),
			_mercator_y(clampf(south, -limit, limit)), map_y
		)
		return rad_to_deg(2.0 * atan(exp(projected_y)) - PI * 0.5)
	return lerpf(north, south, map_y)


## Keep geographic conversion in doubles; Vector2 is float32 in standard Godot.
static func lonlat_to_map(
	longitude: float, latitude: float, path: String = DEFAULT_MANIFEST
) -> PackedFloat64Array:
	var bbox: Array = load_manifest(path)["bbox_wgs84"]
	var south := float(bbox[1])
	var north := float(bbox[3])
	var y := (north - latitude) / (north - south)
	if projection_type(path) == WEB_MERCATOR:
		assert(absf(latitude) <= MERCATOR_LATITUDE_LIMIT, "纬度超出 Web Mercator 有效范围")
		y = (_mercator_y(north) - _mercator_y(latitude)) / (
			_mercator_y(north) - _mercator_y(south)
		)
	return PackedFloat64Array([
		(longitude - float(bbox[0])) / (float(bbox[2]) - float(bbox[0])), y
	])


static func map_to_lonlat(
	map_x: float, map_y: float, path: String = DEFAULT_MANIFEST
) -> PackedFloat64Array:
	var bbox: Array = load_manifest(path)["bbox_wgs84"]
	return PackedFloat64Array([
		lerpf(float(bbox[0]), float(bbox[2]), map_x),
		latitude_at_y(map_y, float(bbox[1]), float(bbox[3]), path)
	])


static func latitude_bounds(
	path: String = DEFAULT_MANIFEST
) -> Vector2:
	var bbox: Array = load_manifest(path)["bbox_wgs84"]
	return Vector2(float(bbox[1]), float(bbox[3]))


static func city_density_profile(
	path: String = DEFAULT_MANIFEST
) -> Dictionary:
	var manifest := load_manifest(path)
	var profile: Dictionary = manifest.get("city_density", {})
	return {
		"peak_latitude": float(profile.get("peak_latitude", 30.0)),
		"south_edge_multiplier": float(profile.get(
			"south_edge_multiplier", 0.5
		)),
		"north_edge_multiplier": float(profile.get(
			"north_edge_multiplier", 0.2
		)),
	}
