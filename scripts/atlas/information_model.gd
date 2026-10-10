extends RefCounted
const Diplomacy = preload("res://scripts/atlas/diplomacy_view.gd")
## Read-only presentation of our simulation. No forecasting, RNG or rule changes.
static func row(label: String,value: Variant,kind: String = "",id: int = -1) -> Dictionary:
	return {"label":label,"value":str(value),"kind":kind,"id":id}
static func section(title: String,rows: Array) -> Dictionary:
	return {"title":title,"rows":rows}
static func nation_name(state: GameState,id: int) -> String:
	return state.nations[id].name if id>=0 and id<state.nations.size() else "无归属"
static func city_name(state: GameState,id: int) -> String:
	if id<0 or id>=state.cities.size(): return "无"
	return "道路岔口" if state.cities[id].is_traffic else state.cities[id].name
static func settlement_id(state: GameState,id: int) -> int:
	return id if id>=0 and id<state.cities.size() and state.cities[id].is_settlement() else -1
static func binding_name(id: int,unbound: String,increment: int = 0) -> String:
	return str(id+increment) if id>=0 else unbound
static func action(key: String,label: String,icon: String,id: int = -1) -> Dictionary:
	return {"key":key,"label":label,"icon":icon,"id":id,"disabled":id<0 and key not in ["focus","copy"]}
static func city(state: GameState,id: int) -> Dictionary:
	if id<0 or id>=state.cities.size() or not state.cities[id].is_settlement(): return {}
	var c := state.cities[id]; var owner := c.owner_nation; var center := state.administrative_center_of(id)
	var color := state.nations[owner].color if owner>=0 and owner<state.nations.size() else Color.GRAY
	var doc := {"title":c.name,"subtitle":"%s · 第%d天"%["州治" if center==id else "府",state.day],"color":color,"point":c.map_position*Vector2(2048,1024),"actions":[action("nation","所属国家","flag",owner),action("focus","设为中心","center"),action("order","行军至此","route",id),action("copy","复制信息","copy")],"sections":[]}
	var capital := owner>=0 and owner<state.nations.size() and state.nations[owner].capital_city_id==id
	doc.sections.append(section("概况",[row("实控国家",nation_name(state,owner),"nation",owner),row("法理国家",nation_name(state,state.recognized_owner_of(id)),"nation",state.recognized_owner_of(id)),row("隶属州治",city_name(state,center),"city",center),row("行政身份","州治" if center==id else "府"),row("首都","是" if capital else "否")]))
	var production := [row("月人口产出",c.manpower_per_month),row("月金钱产出",c.gold_per_month),row("半年粮食产出",c.food_per_half_year)]
	if c.has_warehouse: production.append(row("本城粮仓",c.food_storage))
	doc.sections.append(section("资源与产出",production))
	doc.sections.append(section("统治与秩序",[row("忠诚度","%.1f / 100"%c.loyalty),row("认同国家",nation_name(state,c.loyalty_target_nation),"nation",c.loyalty_target_nation),row("忠诚趋势","%+.2f"%c.loyalty_trend),row("动荡度","%.1f"%c.unrest),row("叛乱累积月数",c.rebellion_progress),row("忠诚变化原因",c.last_loyalty_reason if not c.last_loyalty_reason.is_empty() else "无"),row("占领责任方",nation_name(state,c.occupation_sponsor_nation),"nation",c.occupation_sponsor_nation)]))
	var military := [row("守军人数",c.garrison_manpower),row("守军容量",state.city_garrison_capacity(id)),row("守军供给率","%.0f%%"%(c.garrison_supply_ratio*100)),row("战时状态","战时" if c.at_war else "和平"),row("战争减产截止","第%d天"%c.war_disruption_until_day if c.war_disruption_until_day>state.day else "无")]
	for unit in state.armies:
		if unit.size>0 and not unit.on_edge and unit.location_city==id: military.append(row("军队%d"%unit.id,"%d人"%unit.size,"army",unit.id))
	doc.sections.append(section("军事",military))
	doc.sections.append(section("贸易",[row("状态","已启用" if state.trade_enabled else "未启用"),row("最近月度金钱加成",c.trade_gold_bonus),row("贸易线路",c.trade_route_count),row("最近月度粮食净流入",c.trade_food_balance)]))
	append_environment(doc,state,id)
	return doc
static func append_environment(doc: Dictionary,state: GameState,id: int) -> void:
	var layout: Dictionary = state.atlas_layout
	if layout.is_empty() or id>=layout.hierarchy.cities.size(): return
	var cell: int = layout.hierarchy.cities[id].cell; var data: Dictionary = layout.data; var environment: Dictionary = data.environment
	var rows := [row("宜居度","%.3f"%environment.suitability[cell]),row("高程","%.0f m"%environment.elevation[cell]) if environment.has("elevation") else row("地理编号",cell),row("经纬度","%.2f° / %.2f°"%[state.cities[id].map_position.x*360-180,90-state.cities[id].map_position.y*180])]
	if environment.has("temperature"): rows.append(row("年均温度","%.1f °C"%environment.temperature[cell]))
	if environment.has("precipitation"): rows.append(row("年降水","%.0f mm"%environment.precipitation[cell]))
	if environment.has("quarter_precipitation"):
		for q in range(4): rows.append(row(["冬季降水","春季降水","夏季降水","秋季降水"][q],"%.0f mm"%(environment.quarter_precipitation[q][cell]*.25)))
	if environment.has("aridity_index"): rows.append(row("干燥指数","%.2f"%environment.aridity_index[cell]))
	if environment.has("growing_months"): rows.append(row("适宜季节折算","%.2f 月"%environment.growing_months[cell]))
	doc.sections.append(section("地理与气候",rows))
static func nation(state: GameState,id: int) -> Dictionary:
	if id<0 or id>=state.nations.size(): return {}
	var n := state.nations[id]; var centers := 0; var seats := 0; var troops := 0; var army_rows: Array = []
	for c in state.cities:
		if c.is_settlement() and c.owner_nation==id:
			seats += 1
			if state.administrative_center_of(c.id)==c.id: centers += 1
	for unit in state.armies:
		if unit.owner_nation==id and unit.size>0:
			troops += unit.size; army_rows.append(row("军队%d"%unit.id,"%d人"%unit.size,"army",unit.id))
	var stock := 0
	for c in n.warehouse_city_ids:
		if c>=0 and c<state.cities.size() and state.cities[c].owner_nation==id: stock += state.cities[c].food_storage
	var capital := n.capital_city_id
	var point := state.cities[capital].map_position*Vector2(2048,1024) if capital>=0 and capital<state.cities.size() else Vector2(1024,512)
	var doc := {"title":n.name,"subtitle":"%s · 第%d天"%["帝国" if n.state_level>0 else "国家",state.day],"color":n.color,"point":point,"actions":[action("city","查看首都","city",capital),action("focus","设为中心","center"),action("player","操控此国","flag",id),action("declare","对其宣战","war",id)],"sections":[]}
	doc.sections.append(section("概况",[row("状态","存续" if n.alive else "已灭亡"),row("首都",city_name(state,capital),"city",capital),row("控制治所",seats),row("控制州治",centers),row("控制府",seats-centers),row("君主",n.ruler_name if not n.ruler_name.is_empty() else "未记录"),row("君主特质","、".join(n.ruler_traits) if not n.ruler_traits.is_empty() else "中性"),row("平均忠诚度","%.1f"%n.average_loyalty)]))
	doc.sections.append(section("国库与人口库",[row("金钱库存",n.treasury_gold),row("可用人口库",n.manpower_pool),row("粮仓库存",stock)]))
	doc.sections.append(section("最近月度结算",[row("野战军维护费",n.last_field_army_upkeep),row("守军维护费",n.last_garrison_upkeep),row("全军维护费",n.last_military_upkeep),row("欠付军费",n.unpaid_military_upkeep),row("军费支付率","%.0f%%"%(n.military_payment_ratio*100)),row("预计粮食月产",n.last_food_estimated_production),row("预计粮食月需",n.last_food_estimated_consumption),row("预计粮食结余",n.last_food_estimated_balance)]))
	var relations: Array = []
	for other in state.nations:
		if other.id==id or not other.alive: continue
		var relation := Diplomacy.kind(state,id,other.id)
		if relation not in ["neutral",""]:
			relations.append(row(Diplomacy.LABELS[relation],other.name,"nation",other.id))
	doc.sections.append(section("外交关系",relations if not relations.is_empty() else [row("关系","暂无敌对或同盟")]))
	doc.sections.append(section("军队",[row("野战兵力",troops)]+army_rows))
	doc.sections.append(section("贸易",[row("状态","已启用" if state.trade_enabled else "未启用"),row("最近月度贸易收入",n.last_trade_gold),row("贸易线路",n.last_trade_route_count),row("粮食进口",n.last_trade_food_import),row("粮食出口",n.last_trade_food_export),row("人口进口",n.last_trade_manpower_import)]))
	return doc
static func army(state: GameState,id: int) -> Dictionary:
	for unit in state.armies:
		if unit.id!=id: continue
		var owner := unit.owner_nation; var color := state.nations[owner].color if owner>=0 and owner<state.nations.size() else Color.GRAY
		var point := state.cities[unit.location_city].map_position*Vector2(2048,1024) if unit.location_city>=0 and unit.location_city<state.cities.size() else Vector2.ZERO
		if unit.on_edge:
			var edge := state.edge_of(unit.move_from,unit.move_to)
			if edge!=null: point = edge.map_position_at(unit.move_progress if unit.move_from==edge.city_a else 1.-unit.move_progress,state.cities[edge.city_a].map_position,state.cities[edge.city_b].map_position,2.)*Vector2(2048,1024)
		var target := unit.path[-1] if not unit.path.is_empty() else -1
		var strength := [row("人数",unit.size),row("满编人数",unit.max_size),row("士气","%.2f"%unit.morale),row("供给率","%.0f%%"%(unit.supply_ratio*100)),row("粮食补给欠额","%.2f"%unit.supply_food_debt),row("基础攻击",unit.attack),row("基础防御",unit.defense),row("军费倍率","%.2f"%unit.funding_multiplier)]
		var deployment := [
			row("状态",["驻扎","行军","交战","败退","恢复","部署"][unit.state]),
			row("所在节点",city_name(state,unit.location_city),"city",settlement_id(state,unit.location_city)),
			row("当前道路进度","%.0f%%"%(unit.move_progress*100)),
			row("目标",city_name(state,target),"city",settlement_id(state,target)),
			row("战团",binding_name(unit.battle_group_id,"未编组")),
			row("战争",binding_name(unit.campaign_war_id,"未参战",1)),
			row("战线",binding_name(unit.campaign_front_id,"未绑定")),
			row("战斗",binding_name(unit.battle_id,"未交战")),
			row("命令原因",unit.ai_order_reason if not unit.ai_order_reason.is_empty() else "无")]
		return {"title":"军队%d"%id,"subtitle":"%s · 第%d天"%[nation_name(state,owner),state.day],"color":color,"point":point,
			"actions":[action("nation","所属国家","flag",owner),action("focus","设为中心","center"),action("select_army","选中军队","war",id),action("copy","复制信息","copy")],
			"sections":[section("兵力与补给",strength),section("部署与行动",deployment)]}
	return {}
static func road(state: GameState,id: int) -> Dictionary:
	if id<0 or id>=state.edges.size(): return {}
	var e := state.edges[id]; var a := state.cities[e.city_a].map_position; var b := state.cities[e.city_b].map_position
	return {"title":"%s — %s"%[city_name(state,e.city_a),city_name(state,e.city_b)],"subtitle":"道路 · 第%d天"%state.day,"color":Color(.43,.32,.21),"point":e.map_position_at(.5,a,b,2.)*Vector2(2048,1024),"actions":[action("focus","设为中心","center"),action("copy","复制信息","copy")],"sections":[section("道路",[row("端点A",city_name(state,e.city_a),"city",e.city_a if not state.cities[e.city_a].is_traffic else -1),row("端点B",city_name(state,e.city_b),"city",e.city_b if not state.cities[e.city_b].is_traffic else -1),row("控制辖区",city_name(state,e.control_city_id),"city",e.control_city_id),row("长度","%.1f 公里"%(e.distance_units()*250)),row("道路容量",e.max_manpower),row("当前通行军队",e.passing_count),row("危险系数","%.2f"%e.danger),row("行军时间倍率","%.2f"%e.travel_time_multiplier),row("补给损耗倍率","%.2f"%e.supply_loss_multiplier)])]}

static func historical(document: Dictionary,kind: String) -> Dictionary:
	# PoliticalHistory freezes ownership, rulers, diplomacy and layout. Its view
	# state carries some copied live fields, not a complete economic/army save.
	var allowed := ["概况","地理与气候","选中道路"] if kind=="city" else ["概况","外交关系"] if kind=="nation" else ["道路"]
	document.sections=document.sections.filter(func(s): return s.title in allowed)
	for group in document.sections:
		group.rows=group.rows.filter(func(r): return r.label not in ["平均忠诚度","当前通行军队","危险系数","行军时间倍率","补给损耗倍率"])
	document.sections.append(section("快照范围",[row("经济与兵力","此政治快照未记录")]))
	return document
