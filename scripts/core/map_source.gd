class_name MapSource
extends RefCounted
## Single manifest entry point for replaceable packed map sources.

const DEFAULT_MANIFEST := "res://assets/terrain/map_source.json"
const FORMAT := "world-war-map-source"
const VERSION := 1
const EQUIRECTANGULAR := "equirectangular"
const WEB_MERCATOR := "web_mercator"
const LEGACY_SETTLEMENT := "legacy"
const ENVIRONMENT_SETTLEMENT := "environment_v1"
const LEGACY_HYDROLOGY := "boundary"
const TERRAIN_HYDROLOGY := "terrain_v1"
const FLOW_RIVER_SETTLEMENT := "flow_weighted"
const UNIFORM_RIVER_SETTLEMENT := "uniform_v1"
const VALLEY_RIVER_SETTLEMENT := "valley_v1"
const STRICT_RIVER_TRANSPORT := "strict_banks_v1"
const FULL_RIVER_TRANSPORT := "full_network_v1"
const VISIBILITY_ROAD_PATH := "visibility_v1"
const ENVIRONMENT_ONLY_RIVERS := "environment_only"
const ATLAS_ROADS := "atlas_city_graph_v1"
const ATLAS_STYLE := "atlas_handdrawn_v1"
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
	if str(data.get("settlement_model", LEGACY_SETTLEMENT)) not in [LEGACY_SETTLEMENT, ENVIRONMENT_SETTLEMENT]:
		return "不支持的城市选址模型：%s" % str(data["settlement_model"])
	var density_error := validate_density_bounds(data.get("settlement_density_bounds",{}))
	if not density_error.is_empty(): return density_error
	if data.has("settlement_density_bounds") and str(data.get("settlement_model",LEGACY_SETTLEMENT)) != ENVIRONMENT_SETTLEMENT:
		return "城市密度上下限需要环境选址模型。"
	if str(data.get("hydrology_model", LEGACY_HYDROLOGY)) not in [LEGACY_HYDROLOGY, TERRAIN_HYDROLOGY]:
		return "不支持的水文模型。"
	if str(data.get("hydrology_model", LEGACY_HYDROLOGY)) == TERRAIN_HYDROLOGY and str(data.get("settlement_model", LEGACY_SETTLEMENT)) != ENVIRONMENT_SETTLEMENT:
		return "地形水文需要环境城市模型。"
	var road_path_model := str(data.get("road_path_model", "legacy"))
	if str(data.get("river_usage", "full")) not in ["full", ENVIRONMENT_ONLY_RIVERS]:
		return "不支持的河流使用模式。"
	if str(data.get("road_network_model", "legacy")) not in ["legacy", ATLAS_ROADS]:
		return "不支持的道路生成模型。"
	if str(data.get("map_visual_style", "legacy")) not in ["legacy", ATLAS_STYLE]:
		return "不支持的地图绘制样式。"
	if str(data.get("road_network_model", "legacy")) == ATLAS_ROADS and str(data.get("river_usage", "full")) != ENVIRONMENT_ONLY_RIVERS:
		return "图集道路目前需要仅用于环境的河流水文。"
	if str(data.get("river_usage", "full")) == ENVIRONMENT_ONLY_RIVERS and str(data.get("hydrology_model", LEGACY_HYDROLOGY)) != TERRAIN_HYDROLOGY:
		return "环境供水模式需要地形水文。"
	if road_path_model not in ["legacy", VISIBILITY_ROAD_PATH]: return "不支持的道路路径模型。"
	if road_path_model == VISIBILITY_ROAD_PATH and str(data.get("hydrology_model", LEGACY_HYDROLOGY)) != TERRAIN_HYDROLOGY:
		return "道路可见性简化需要地形水文地图。"
	if data.has("ferry_interval"):
		var interval: Variant = data.ferry_interval
		if not (interval is float or interval is int) or not is_finite(float(interval)) or float(interval)<=0 or float(interval)>1:
			return "渡口间隔必须是大于零且不超过1的地图高度单位。"
		if str(data.get("hydrology_model", LEGACY_HYDROLOGY)) != TERRAIN_HYDROLOGY:
			return "按河长布置渡口需要地形水文地图。"
	if data.has("ferry_max_per_river"):
		var maximum: Variant = data.ferry_max_per_river
		if not (maximum is int or maximum is float) or not is_finite(float(maximum)) or float(maximum)<1 or float(maximum)!=floorf(float(maximum)):
			return "每条河渡口上限必须是正整数。"
		if not data.has("ferry_interval"): return "每条河渡口上限需要按河长布置模式。"
	if str(data.get("boundary_inflow", "none")) not in ["none", "estimated"]:
		return "不支持的边界来水模式。"
	var network_path := str(data.get("hydrology_network", ""))
	var transport := str(data.get("river_transport_model", "legacy"))
	if transport not in ["legacy", STRICT_RIVER_TRANSPORT, FULL_RIVER_TRANSPORT]: return "不支持的河流交通模型。"
	if transport in [STRICT_RIVER_TRANSPORT, FULL_RIVER_TRANSPORT] and str(data.get("hydrology_model", LEGACY_HYDROLOGY)) != TERRAIN_HYDROLOGY:
		return "严格双岸交通需要地形水文河网。"
	var river_settlement := str(data.get("river_settlement_model", FLOW_RIVER_SETTLEMENT))
	if river_settlement not in [FLOW_RIVER_SETTLEMENT, UNIFORM_RIVER_SETTLEMENT, VALLEY_RIVER_SETTLEMENT]:
		return "不支持的河岸供水模型。"
	if river_settlement != FLOW_RIVER_SETTLEMENT and (str(data.get("settlement_model", LEGACY_SETTLEMENT)) != ENVIRONMENT_SETTLEMENT or str(data.get("hydrology_model", LEGACY_HYDROLOGY)) != TERRAIN_HYDROLOGY or network_path.is_empty()):
		return "统一河岸供水需要环境选址及矢量水文河网。"
	if not network_path.is_empty():
		if not FileAccess.file_exists(network_path): return "水文预处理缓存不存在：%s" % network_path
		var network: Variant = JSON.parse_string(FileAccess.get_file_as_string(network_path))
		if not network is Dictionary or network.get("format", "") != "terrain-vector-drainage" or int(network.get("version", -1)) != 1:
			return "水文预处理缓存格式无效。"
		if network.get("bbox_wgs84", []) != bbox_value or network.get("projection", "") != data.get("projection", EQUIRECTANGULAR):
			return "水文预处理缓存与地图范围或投影不匹配。"
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

static func hydrology_model(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path).get("hydrology_model", LEGACY_HYDROLOGY))


static func environment_only_rivers(path: String) -> bool:
	return str(load_manifest(path).get("river_usage", "full")) == ENVIRONMENT_ONLY_RIVERS


static func atlas_roads(path: String) -> bool:
	return str(load_manifest(path).get("road_network_model", "legacy")) == ATLAS_ROADS


static func atlas_style(path: String) -> bool:
	return str(load_manifest(path).get("map_visual_style", "legacy")) == ATLAS_STYLE

static func road_path_model(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path).get("road_path_model", "legacy"))

static func ferry_interval(path: String = DEFAULT_MANIFEST) -> float:
	return float(load_manifest(path).get("ferry_interval", 0.0))

static func ferry_max_per_river(path: String = DEFAULT_MANIFEST) -> int:
	return int(load_manifest(path).get("ferry_max_per_river", 0))


static func strict_river_transport(path: String = DEFAULT_MANIFEST) -> bool:
	return str(load_manifest(path).get("river_transport_model", "legacy")) in [STRICT_RIVER_TRANSPORT, FULL_RIVER_TRANSPORT]

static func full_river_transport(path: String) -> bool:
	return str(load_manifest(path).get("river_transport_model", "legacy")) == FULL_RIVER_TRANSPORT

## Eurasian hydrological maps display their generated province IDs directly.
static func uses_province_ids(path: String = DEFAULT_MANIFEST) -> bool:
	return hydrology_model(path) == TERRAIN_HYDROLOGY

static func hydrology_network(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path).get("hydrology_network", ""))


static func river_settlement_model(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path).get("river_settlement_model", FLOW_RIVER_SETTLEMENT))


static func validate_density_bounds(bounds: Variant) -> String:
	if not bounds is Dictionary: return "城市密度上下限必须是对象。"
	var minimum: Variant=bounds.get("minimum",0.0)
	var maximum: Variant=bounds.get("maximum",1.0)
	if not (minimum is float or minimum is int) or not (maximum is float or maximum is int): return "城市密度上下限必须是数值。"
	if not is_finite(float(minimum)) or not is_finite(float(maximum)) or float(minimum)<0.0 or float(maximum)<=0.0 or float(maximum)>1.0 or float(minimum)>float(maximum):
		return "城市密度上下限必须满足 0 ≤ 最低 ≤ 最高 ≤ 1，且最高大于零。"
	return ""


static func settlement_density_bounds(path: String = DEFAULT_MANIFEST) -> Dictionary:
	var bounds: Dictionary=load_manifest(path).get("settlement_density_bounds",{})
	return {"minimum":float(bounds.get("minimum",0.0)),"maximum":float(bounds.get("maximum",1.0))}

static func estimated_boundary_inflow(path: String = DEFAULT_MANIFEST) -> bool:
	return str(load_manifest(path).get("boundary_inflow", "none")) == "estimated"


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


static func settlement_model(path: String = DEFAULT_MANIFEST) -> String:
	return str(load_manifest(path).get("settlement_model", LEGACY_SETTLEMENT))

static func model_descriptor(path: String=DEFAULT_MANIFEST) -> Dictionary:
	var config:=load_manifest(path)
	return {
		"river_usage":str(config.get("river_usage","full")),
		"road_network_model":str(config.get("road_network_model","legacy")),
		"map_visual_style":str(config.get("map_visual_style","legacy")),
		"road_version":load("res://scripts/core/atlas_road_network.gd").VERSION if atlas_roads(path) else "legacy",
		"visual_version":load("res://scripts/view/atlas_display_geometry.gd").VERSION if atlas_style(path) else "legacy",
	}
