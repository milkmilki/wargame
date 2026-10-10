extends RefCounted
## Generation policy only: climate and terrain remain global and unchanged.
const VERSION := "atlas-geographic-mask-v1"
const EURASIA := {"enabled":true,"south":20.,"north":55.,"west":-15.,"east":145.,"version":VERSION}
const EPSILON := .00002 # Equirectangular Float32 coordinates, about two metres.

static func validate(value: Variant) -> String:
	if not value is Dictionary: return "城市生成范围配置须为字典。"
	if value.is_empty(): return ""
	if not value.get("enabled",false) is bool: return "城市生成范围开关无效。"
	if value.get("version",VERSION)!=VERSION: return "城市生成范围版本不支持。"
	for key in ["south","north","west","east"]:
		var number = value.get(key,EURASIA[key])
		if not (number is float or number is int) or not is_finite(float(number)):
			return "城市生成范围坐标无效："+key
		if absf(float(number))>(90. if key in ["south","north"] else 180.):
			return "城市生成范围坐标越界："+key
	if float(value.get("south",20.))>=float(value.get("north",55.)): return "纬度南界须小于北界。"
	if float(value.get("west",-15.))==float(value.get("east",145.)): return "经度西界与东界不能相同。"
	return ""

static func normalize(value: Dictionary) -> Dictionary:
	if value.is_empty() or not validate(value).is_empty(): return {}
	return {"enabled":value.get("enabled",false),"south":float(value.get("south",20.)),
		"north":float(value.get("north",55.)),"west":float(value.get("west",-15.)),
		"east":float(value.get("east",145.)),"version":VERSION}

static func contains(longitude: float, latitude: float, settings: Dictionary) -> bool:
	if settings.is_empty() or not settings.get("enabled",false): return true
	if latitude<float(settings.south)-EPSILON or latitude>float(settings.north)+EPSILON: return false
	var lon := fposmod(longitude+180.,360.)-180.
	return (lon>=float(settings.west)-EPSILON and lon<=float(settings.east)+EPSILON) if settings.west<settings.east else (lon>=float(settings.west)-EPSILON or lon<=float(settings.east)+EPSILON)

static func contains_cell(mesh: Dictionary, cell: int, settings: Dictionary) -> bool:
	return contains(float(mesh.x[cell])/float(mesh.width)*360.-180.,
		90.-float(mesh.y[cell])/float(mesh.height)*180.,settings)

static func apply(mesh: Dictionary, fields: Dictionary, settings: Dictionary) -> void:
	var options := normalize(settings)
	if options.is_empty() or not options.enabled: return
	var suitability = fields.suitability.duplicate()
	var capacity = fields.capacity.duplicate()
	for cell in range(mesh.n):
		if not contains_cell(mesh,cell,options):
			suitability[cell]=0.; capacity[cell]=0.
	fields.suitability=suitability; fields.capacity=capacity
