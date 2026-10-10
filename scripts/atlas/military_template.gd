extends RefCounted
## Version 9 Atlas new-game template: typed immutable geometry, no campaign state.
const NativeMap = preload("res://scripts/atlas/native_map.gd")
const Snapshot = preload("res://scripts/atlas/snapshot.gd")
static func encode(state: GameState) -> Dictionary:
	var payload: Dictionary = state.atlas_layout.duplicate(true)
	for record in payload.graph.edges:
		var edge := state.edge_of(record.a,record.b)
		record.danger = edge.danger; record.max_manpower = edge.max_manpower; record.base_max_manpower = edge.base_max_manpower
		record.travel_time_multiplier = edge.travel_time_multiplier; record.supply_loss_multiplier = edge.supply_loss_multiplier
		record.allows_holding = edge.allows_holding; record.protected = edge.is_backbone
	var nation_map := {}; var nations: Array = []
	for nation in state.nations:
		if not nation.alive or state.land_cities_of(nation.id).is_empty(): continue
		nation_map[nation.id] = nations.size()
		nations.append({"name":nation.name,"seat":state.cities[nation.capital_city_id].id,"color":[roundi(nation.color.r*255),roundi(nation.color.g*255),roundi(nation.color.b*255)]})
	payload.nations = nations; payload.settlement_records = []
	for c in range(payload.hierarchy.cities.size()):
		var city := state.cities[c]
		payload.settlement_records.append({"owner":nation_map[city.owner_nation],"name":city.name,"short_name":city.short_name,
			"budget":[city.manpower_per_month,city.gold_per_month,city.food_per_half_year]})
	for parent in range(payload.ownership.size()):
		var center: int = payload.hierarchy.guardian_by_parent[parent]
		payload.ownership[parent] = nation_map[state.cities[center].owner_nation] if center>=0 else -1
	# Paths in this payload are the actual simulation/display paths, not regenerated.
	return {"format":"world-war-map","version":9,"map_kind":"atlas_military","atlas_payload":Marshalls.raw_to_base64(var_to_bytes(payload)),
		"seed":state.world_seed,"nation_count":nations.size(),"settlement_count":payload.hierarchy.cities.size(),"node_count":state.cities.size(),"edge_count":state.edges.size()}

static func decode(definition: Dictionary) -> Dictionary:
	var value: Variant = bytes_to_var(Marshalls.base64_to_raw(str(definition.get("atlas_payload",""))))
	return value if value is Dictionary else {}

static func validate(definition: Dictionary) -> String:
	if definition.get("format")!="world-war-map": return "不是 WorldWar 地图文件。"
	if int(definition.get("version",0))!=9 or not definition.get("atlas_payload") is String: return "Atlas 模板格式无效。"
	var payload := decode(definition)
	if payload.get("model")!="atlas-military-v1": return "Atlas 模型不支持。"
	for key in ["data","hierarchy","graph","raster","display","network","settlement_adjacency","strategic_routes"]:
		if not payload.get(key) is Dictionary: return "Atlas 模板缺少 "+key
	if not payload.get("nations") is Array or payload.nations.is_empty(): return "Atlas 国家资料无效。"
	if not payload.get("district_pixels") is PackedInt32Array or not payload.get("ownership") is PackedInt32Array: return "Atlas 显示编号格式无效。"
	for nation in payload.nations:
		if not nation is Dictionary or not nation.get("name") is String or not nation.get("color") is Array or nation.color.size()!=3: return "Atlas 国家资料无效。"
		for channel in nation.color:
			if not whole_number(channel,0,256): return "Atlas 国家颜色无效。"
	var error := NativeMap.validate(payload.data)
	if not error.is_empty(): return error
	var cell_count: int = payload.data.mesh.x.size(); var parent_count: int = payload.data.regions.seat.size()
	if payload.data.mesh.get("n")!=cell_count or payload.data.regions.get("count")!=parent_count: return "Atlas 世界维度无效。"
	if not payload.data.get("options") is Dictionary or not NativeMap.numeric_array(payload.data.mesh.get("areas")): return "Atlas 世界配置无效。"
	for field in ["cell","water"]:
		if not NativeMap.numeric_array(payload.raster.get(field)) or payload.raster[field].size()!=2048*1024: return "Atlas 栅格无效。"
	var parent_pixels := PackedInt32Array(); parent_pixels.resize(2048*1024)
	for pixel in range(parent_pixels.size()):
		if not whole_number(payload.raster.cell[pixel],0,cell_count): return "Atlas 栅格地块编号无效。"
		parent_pixels[pixel] = payload.data.regions.of[int(payload.raster.cell[pixel])] if payload.raster.water[pixel]==0 else -1
	# Reuse the native preview contract for every environment/display dependency,
	# before a loader can swap the live world and create GPU resources.
	error = Snapshot.validate({"format":Snapshot.FORMAT,"version":Snapshot.VERSION,"data":payload.data,"raster":payload.raster,"display":payload.display,"provinces":parent_pixels})
	if not error.is_empty(): return error
	if payload.ownership.size()!=parent_count: return "Atlas 原省份归属维度无效。"
	var h: Dictionary = payload.hierarchy; var graph: Dictionary = payload.graph
	if not h.get("cities") is Array or not h.get("members") is Array or not graph.get("nodes") is Array or not graph.get("edges") is Array: return "Atlas 州府或交通维度无效。"
	if h.cities.is_empty() or graph.nodes.size()<h.cities.size(): return "Atlas 缺少治所。"
	for key in ["district_of_cell","center_by_city","state_by_city","state_parents","guardian_by_parent","state_by_parent"]:
		if not h.get(key) is PackedInt32Array: return "Atlas 固定映射格式无效。"
	if h.center_by_city.size()!=h.cities.size() or h.state_by_city.size()!=h.cities.size() or h.state_parents.size()!=h.members.size(): return "Atlas 行政映射维度无效。"
	if h.guardian_by_parent.size()!=parent_count or h.state_by_parent.size()!=parent_count: return "Atlas 托管映射维度无效。"
	if h.district_of_cell.size()!=payload.data.mesh.n or payload.district_pixels.size()!=2048*1024: return "Atlas 辖区维度无效。"
	if not payload.get("settlement_records") is Array or payload.settlement_records.size()!=h.cities.size(): return "Atlas 初始治所归属无效。"
	var mask := Snapshot.SettlementMask.normalize(payload.data.options.get("settlement_mask",{}))
	var counts := {}; var keys := {}
	for c in range(h.cities.size()):
		if not h.cities[c] is Dictionary or not whole_number(h.cities[c].get("cell"),0,cell_count) or not whole_number(h.cities[c].get("region"),0,parent_count): return "Atlas 治所坐标无效。"
		if not Snapshot.SettlementMask.contains_cell(payload.data.mesh,h.cities[c].cell,mask): return "Atlas 治所位于生成范围外。"
		if h.state_by_city[c]!=h.center_by_city[c] or h.state_by_city[c]<0 or h.state_by_city[c]>=h.members.size(): return "Atlas 州编号无效。"
		if h.cities[c].get("role")!=("zhou" if c<h.members.size() else "fu") or not h.cities[c].get("budget") is Array or h.cities[c].budget.size()!=3: return "Atlas 治所身份或预算无效。"
		for value in h.cities[c].budget:
			if not whole_number(value,0,2147483647): return "Atlas 固定预算无效。"
		if not payload.settlement_records[c] is Dictionary: return "Atlas 治所资料无效。"
		var record: Dictionary = payload.settlement_records[c]; var owner := int(record.get("owner",-1))
		if not whole_number(record.get("owner"),0,payload.nations.size()): return "Atlas 治所归属无效。"
		if owner<0 or owner>=payload.nations.size(): return "Atlas 治所归属越界。"
		counts[owner] = counts.get(owner,0)+1
		if h.center_by_city[c]<0 or h.center_by_city[c]>=h.members.size(): return "Atlas 固定行政映射无效。"
		if h.district_of_cell[h.cities[c].cell]!=c: return "Atlas 治所种子归属无效。"
		if not record.get("name") is String or not record.get("short_name") is String or not record.get("budget") is Array or record.budget.size()!=3: return "Atlas 治所资料无效。"
		for value in record.budget:
			if not (value is int or value is float) or not is_finite(value) or value<0 or value!=floor(value): return "Atlas 治所预算无效。"
	var members := {}
	for center in range(h.members.size()):
		if h.state_parents[center]<0 or h.state_parents[center]>=parent_count or h.cities[center].region!=h.state_parents[center]: return "Atlas 州治与州域映射无效。"
		if not h.members[center] is Array or not h.members[center].has(center) or h.members[center].size()>4: return "Atlas 州府成员无效。"
		for city_id in h.members[center]:
			if city_id<0 or city_id>=h.cities.size() or members.has(city_id) or h.center_by_city[city_id]!=center: return "Atlas 州府成员重复或映射冲突。"
			members[city_id] = true
	if members.size()!=h.cities.size(): return "Atlas 有未分配的治所。"
	for parent in range(parent_count):
		var guardian: int = h.guardian_by_parent[parent]
		if guardian<0 or guardian>=h.members.size() or payload.ownership[parent]<0 or payload.ownership[parent]>=payload.nations.size(): return "Atlas 托管或原省份归属无效。"
		var region: int = h.state_by_parent[parent]
		if region< -1 or region>=h.members.size() or (region>=0 and h.state_parents[region]!=parent): return "Atlas 固定州域无效。"
	for cell in range(cell_count):
		var district: int = h.district_of_cell[cell]; var parent: int = payload.data.regions.of[cell]
		if district< -1 or district>=h.cities.size(): return "Atlas 辖区编号越界。"
		if parent>=0 and payload.data.environment.water[cell]==0:
			if district<0: return "Atlas 陆地辖区缺失。"
			if h.state_by_parent[parent]>=0 and h.cities[district].region!=parent: return "Atlas 子辖区越过州界。"
		elif district>=0: return "Atlas 辖区吞并海湖。"
	for district in payload.district_pixels:
		if district< -1 or district>=h.cities.size(): return "Atlas 显示辖区越界。"
	for id in range(graph.nodes.size()):
		if not graph.nodes[id] is Dictionary: return "Atlas 节点格式无效。"
		var node: Dictionary = graph.nodes[id]
		if not node.get("position") is Vector2 or not node.position.is_finite() or node.position.y<0 or node.position.y>1024: return "Atlas 节点坐标无效。"
		if node.get("role") not in ["zhou","fu","traffic"] or (id<h.cities.size())!=(node.role!="traffic"): return "Atlas 节点身份无效。"
		if id<h.cities.size():
			var cell: int = h.cities[id].cell
			var offset: Vector2 = node.position-Vector2(payload.data.mesh.x[cell],payload.data.mesh.y[cell])
			offset.x = wrapf(offset.x,-1024.,1024.)
			if offset.length()>.01 or node.role!=h.cities[id].role: return "Atlas 治所交通锚点不一致。"
	for owner in range(payload.nations.size()):
		if not counts.has(owner): return "Atlas 国家没有治所。"
	for edge in graph.edges:
		if not edge is Dictionary: return "Atlas 道路格式无效。"
		for field in ["a","b"]:
			if not whole_number(edge.get(field),0,graph.nodes.size()): return "Atlas 道路端点格式无效。"
		if not whole_number(edge.get("control_city"),0,h.cities.size()): return "Atlas 道路控制引用无效。"
		if edge.a<0 or edge.b<0 or edge.a>=graph.nodes.size() or edge.b>=graph.nodes.size() or edge.a==edge.b or edge.control_city<0 or edge.control_city>=h.cities.size(): return "Atlas 道路端点或控制引用无效。"
		var key := "%d:%d"%[mini(edge.a,edge.b),maxi(edge.a,edge.b)]
		if keys.has(key): return "Atlas 共享道路重复。"
		keys[key] = true
		if not edge.path is PackedVector2Array or edge.path.size()<2: return "Atlas 道路路径无效。"
		for point in edge.path:
			if not point.is_finite(): return "Atlas 道路坐标无效。"
		var start: Vector2 = edge.path[0]-graph.nodes[edge.a].position
		var end: Vector2 = edge.path[-1]-graph.nodes[edge.b].position
		start.x = wrapf(start.x,-1024.,1024.); end.x = wrapf(end.x,-1024.,1024.)
		if start.length()>.01 or end.length()>.01: return "Atlas 道路未连接端点。"
		if not whole_number(edge.get("tier"),1,3) or not edge.get("protected") is bool: return "Atlas 道路等级无效。"
		if not (edge.get("danger") is float or edge.get("danger") is int) or not is_finite(float(edge.danger)) or edge.danger<0 or edge.danger>1: return "Atlas 道路地形代价无效。"
		for field in ["max_manpower","base_max_manpower"]:
			if edge.has(field) and not whole_number(edge[field],0,2147483647): return "Atlas 道路容量无效。"
		for field in ["travel_time_multiplier","supply_loss_multiplier"]:
			if not edge.has(field): continue
			if not (edge[field] is int or edge[field] is float) or not is_finite(float(edge[field])) or edge[field]<0 or (field=="travel_time_multiplier" and edge[field]==0): return "Atlas 道路费用系数无效。"
		if edge.has("allows_holding") and not edge.allows_holding is bool: return "Atlas 驻防属性无效。"
	return ""

static func whole_number(value: Variant,minimum: int,exclusive_maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value==floor(value) and value>=minimum and value<exclusive_maximum
