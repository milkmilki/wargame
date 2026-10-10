extends RefCounted
## Independent, validated Godot variant snapshot. Never deserializes objects.
const NativeMap = preload("res://scripts/atlas/native_map.gd")
const SettlementMask = preload("res://scripts/atlas/settlement_mask.gd")
const FORMAT := "atlas-preview"
const VERSION := 1

static func validate(payload: Variant) -> String:
	if not payload is Dictionary or payload.get("format")!=FORMAT or payload.get("version")!=VERSION: return "快照格式或版本不支持"
	for key in ["data","display","raster"]:
		if not payload.get(key) is Dictionary: return "缺少 "+key
	var data: Dictionary = payload.data; var error := NativeMap.validate(data)
	if not error.is_empty(): return error
	var n: int = data.mesh.x.size(); var count: int = data.regions.seat.size()
	if data.mesh.get("n")!=n or data.mesh.get("width")!=2048 or data.mesh.get("height")!=1024 or data.regions.get("count")!=count: return "世界或省份尺寸不一致"
	if not data.get("params") is Dictionary or not is_finite(float(data.params.get("seed",NAN))) or not is_finite(float(data.get("seed",NAN))): return "缺少生成种子"
	if not data.get("options") is Dictionary or not is_finite(float(data.options.get("city_threshold",NAN))): return "缺少城市阈值配置"
	var mask_error := SettlementMask.validate(data.options.get("settlement_mask",{}))
	if not mask_error.is_empty(): return mask_error
	var mask := SettlementMask.normalize(data.options.get("settlement_mask",{}))
	if mask.get("enabled",false):
		if not NativeMap.numeric_array(data.environment.get("capacity")) or data.environment.capacity.size()!=n: return "城市生成范围缺少承载量"
		for cell in range(n):
			if not SettlementMask.contains_cell(data.mesh,cell,mask) and (data.environment.suitability[cell]!=0. or data.environment.capacity[cell]!=0.): return "城市生成范围外适宜度或承载量非零"
	if data.regions.has("names"):
		if not data.regions.names is Array or data.regions.names.size()!=count: return "省份名称维度无效"
		for name_value in data.regions.names:
			if not name_value is String: return "省份名称类型无效"
	for field in ["x","y","xyz","areas","lengths"]:
		if not NativeMap.numeric_array(data.mesh.get(field)): return "缺少世界字段："+field
		for value in data.mesh[field]:
			if not is_finite(float(value)): return "非有限世界坐标或面积"
	if data.mesh.areas.size()!=n or data.mesh.lengths.size()!=data.mesh.adj.size(): return "世界面积或边长维度错误"
	for field in ["temperature","biome","seaIce"]:
		if not NativeMap.numeric_array(data.environment.get(field)) or data.environment[field].size()!=n: return "环境字段无效："+field
	if not is_finite(float(data.environment.get("maxElevation",NAN))): return "缺少最高高程"
	for field in ["annual_precipitation","seasonal_precipitation","agricultural_potential","climate_suitability","potential_evaporation","aridity_index","growing_months"]:
		if not data.environment.has(field): continue
		if not NativeMap.numeric_array(data.environment[field]) or data.environment[field].size()!=n: return "气候字段维度无效："+field
		for value in data.environment[field]:
			if not is_finite(float(value)) or value<0: return "气候字段数值无效："+field
	if data.environment.has("climate_suitability"):
		for field in ["potential_evaporation","aridity_index","growing_months","agricultural_potential"]:
			if not data.environment.has(field): return "气候适宜度缺少配套字段："+field
		for factor in data.environment.climate_suitability:
			if factor>1.: return "气候适宜度超出范围"
		for months in data.environment.growing_months:
			if months>12.: return "生长季长度超出范围"
	if data.environment.has("quarter_precipitation"):
		if not data.environment.quarter_precipitation is Array or data.environment.quarter_precipitation.size()!=4: return "季节降雨数量无效"
		for quarter in data.environment.quarter_precipitation:
			if not NativeMap.numeric_array(quarter) or quarter.size()!=n: return "季节降雨维度无效"
			for value in quarter:
				if not is_finite(float(value)) or value<0: return "季节降雨数值无效"
	if data.environment.has("seasonal_winds"):
		if not data.environment.seasonal_winds is Array or data.environment.seasonal_winds.size()!=4: return "季节风场数量无效"
		for wind in data.environment.seasonal_winds:
			if not wind is Dictionary: return "季节风场类型无效"
			for axis in ["u","v"]:
				if not NativeMap.numeric_array(wind.get(axis)) or wind[axis].size()!=n: return "季节风场维度无效"
				for value in wind[axis]:
					if not is_finite(float(value)): return "季节风场数值无效"
	if payload.has("default_owners"):
		if not NativeMap.numeric_array(payload.default_owners) or payload.default_owners.size()!=count: return "默认归属维度无效"
		for owner in payload.default_owners:
			if int(owner)!=owner or owner< -1 or owner>=data.nations.size(): return "默认归属越界"
	for city in data.cities:
		if not SettlementMask.contains_cell(data.mesh,city.cell,mask): return "城市位于生成范围外"
		if not city.get("major") is bool: return "缺少城市等级"
	for road in data.roads:
		if road.get("kind") not in ["road","trail"] or road.cells.size()<2: return "无效道路类型或长度"
		for k in range(1,road.cells.size()):
			var a: int = road.cells[k-1]; var b: int = road.cells[k]; var connected := false
			for j in range(data.mesh.adj_start[a],data.mesh.adj_start[a+1]):
				if data.mesh.adj[j]==b: connected = true; break
			if not connected: return "道路地块不接壤"
	if data.has("places"):
		if not data.places is Array: return "无效地理标注"
		for p in data.places:
			if not p is Dictionary or p.get("kind") not in ["sea","mountains","lake","island","desert"] or not p.get("name") is String or not NativeMap.numeric_array(p.get("path")) or p.path.size()<2 or p.path.size()%2: return "无效地理标注路径"
			for value in p.path:
				if not is_finite(float(value)): return "非有限地理标注路径"
			for field in ["rank","size","cell"]:
				if not is_finite(float(p.get(field,NAN))): return "缺少地理标注等级或锚点"
			if p.cell<0 or p.cell>=n or p.rank<1 or p.rank>3: return "地理标注锚点或等级越界"
	var raster: Dictionary = payload.raster
	if raster.get("w")!=2048 or raster.get("h")!=1024: return "栅格尺寸无效"
	for key in ["cell","water","elev","biome","ice","temp"]:
		if not NativeMap.numeric_array(raster.get(key)) or raster[key].size()!=2048*1024: return "栅格字段无效："+key
	if not NativeMap.numeric_array(payload.get("provinces")) or payload.provinces.size()!=2048*1024: return "缺少省份显示输入"
	for i in range(2048*1024):
		if raster.cell[i]<0 or raster.cell[i]>=data.mesh.x.size(): return "栅格地块越界"
		if raster.water[i]<0 or raster.water[i]>2 or raster.biome[i]<0 or raster.biome[i]>15: return "无效地表类型"
		if payload.provinces[i]< -1 or payload.provinces[i]>=data.regions.seat.size(): return "栅格省份越界"
		if not is_finite(raster.elev[i]) or not is_finite(raster.temp[i]) or not is_finite(raster.ice[i]): return "非有限栅格数值"
	var display: Dictionary = payload.display
	if not display.get("glyphs") is Array or not display.get("nations") is Array: return "缺少显示符号和颜色"
	if not NativeMap.numeric_array(display.get("forest")) or display.forest.size()!=data.mesh.x.size(): return "森林规划无效"
	for glyph in display.glyphs:
		if not glyph is Dictionary: return "无效地形符号"
		for key in ["x","y","s","v","a","c","cell","z","kind"]:
			if not glyph.has(key) or not is_finite(float(glyph[key])): return "缺少符号字段："+key
		if glyph.cell<0 or glyph.cell>=data.mesh.x.size(): return "符号地块越界"
	if display.nations.size()!=data.nations.size(): return "国家显示数量不一致"
	for nation in data.nations+display.nations:
		if not nation is Dictionary or not nation.get("name") is String or not nation.get("color") is Array or nation.color.size()!=3: return "无效国家颜色或名称"
		if int(nation.get("seat",-1))<0 or nation.seat>=count: return "国家治所越界"
		for value in nation.color:
			if not is_finite(float(value)) or value<0 or value>255: return "国家颜色越界"
	return ""

static func save_file(path: String,payload: Dictionary) -> String:
	var error := validate(payload)
	if not error.is_empty(): return error
	var absolute := ProjectSettings.globalize_path(path); var temporary := absolute+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if not file: return "无法写入快照"
	file.store_var(payload,false); file.flush(); file.close()
	var result := DirAccess.rename_absolute(temporary,absolute)
	return "" if result==OK else "快照文件替换失败：%d"%result

static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if not file: return {"error":"无法打开快照"}
	var payload = file.get_var(false); file.close(); var error := validate(payload)
	return {"error":error} if not error.is_empty() else {"payload":payload}
