extends RefCounted
const Diplomacy = preload("res://scripts/atlas/diplomacy_view.gd")
const Calendar = preload("res://scripts/core/game_calendar.gd")
## Read-only presentation of our simulation. No forecasting, RNG or rule changes.
static func row(label: String,value: Variant,kind: String = "",id: int = -1) -> Dictionary:
	return {"label":label,"value":str(value),"kind":kind,"id":id}
static func section(title: String,rows: Array) -> Dictionary:
	return {"title":title,"rows":rows}
static func nation_name(state: GameState,id: int) -> String:
	return WorldNaming.nation_display_name(state,id) if id>=0 and id<state.nations.size() else "无归属"
static func prince_report(state: GameState,id: int) -> Dictionary:
	if state.has_meta("historical_prince_reports"): return state.get_meta("historical_prince_reports").get(id,{"status":"未记录","princes":[],"central":0})
	return PrincePolitics.report(state,id,PrincePolitics.military_index(state).get(id,{}))
static func city_name(state: GameState,id: int) -> String:
	if id<0 or id>=state.cities.size(): return "无"
	return "道路岔口" if state.cities[id].is_traffic else state.cities[id].name
static func settlement_id(state: GameState,id: int) -> int:
	return id if id>=0 and id<state.cities.size() and state.cities[id].is_settlement() else -1
static func binding_name(id: int,unbound: String,increment: int = 0) -> String:
	return str(id+increment) if id>=0 else unbound
static func action(key: String,label: String,icon: String,id: int = -1) -> Dictionary:
	return {"key":key,"label":label,"icon":icon,"id":id,"disabled":id<0 and key not in ["focus","copy"]}
const CAMPAIGN_PHASE_NAMES := {
	CoalitionCampaignFront.Phase.ASSEMBLE:"集结",
	CoalitionCampaignFront.Phase.BREAK_IN:"突破州域",
	CoalitionCampaignFront.Phase.RAID_FU:"争夺属府",
	CoalitionCampaignFront.Phase.RECALL_CAMP:"回营重整",
	CoalitionCampaignFront.Phase.HOLD_CAMP:"驻营补充",
	CoalitionCampaignFront.Phase.ASSAULT_CENTER:"强攻州治",
	CoalitionCampaignFront.Phase.CLEANUP:"清理残部",
	CoalitionCampaignFront.Phase.HOLD_AND_REINFORCE:"固守增援",
	CoalitionCampaignFront.Phase.SORTIE:"出击反攻",
	CoalitionCampaignFront.Phase.BLOCKADE_RAID:"封锁并分遣",
	CoalitionCampaignFront.Phase.BLOCKADE_ONLY:"持续封锁",
	CoalitionCampaignFront.Phase.DEFENSE_REGROUP:"后方重整",
	CoalitionCampaignFront.Phase.RELIEVE_CENTER:"集中解围",
}
static func campaign_rows(state: GameState,nation_id: int) -> Array:
	var records := state.state_campaigns_for_nation(nation_id)
	if records.is_empty(): return execution_campaign_rows(state,nation_id)
	var groups := {}; var entries := []; var fronts := {}; var offense := 0
	for record in records:
		var mode := record.mode_for(nation_id)
		var key := str(record.campaign_id) if mode==CoalitionCampaignFront.Mode.OFFENSE else "%d:%d:%s"%[record.war_id,record.center_city_id,str(record.defender_members)]
		var front := state.campaign_front(record.offense_front_id if mode==CoalitionCampaignFront.Mode.OFFENSE else record.defense_front_id)
		if groups.has(key):
			var entry: Dictionary=groups[key]
			entry.opponents.append_array(record.attacker_members)
			if record.lifecycle==StateCampaign.Lifecycle.ACTIVE: entry.record=record; entry.front=front
			continue
		var entry := {"record":record,"mode":mode,"front":front,"opponents":record.defender_members.duplicate() if mode==CoalitionCampaignFront.Mode.OFFENSE else record.attacker_members.duplicate()}
		groups[key]=entry; entries.append(entry)
		if mode==CoalitionCampaignFront.Mode.OFFENSE: offense+=1
	for entry in entries:
		if entry.front!=null: fronts[entry.front.front_id]=[0,0,0,0]
	for unit in state.armies:
		if unit.size<=0 or not fronts.has(unit.campaign_front_id): continue
		var front := state.campaign_front(unit.campaign_front_id)
		if front==null or unit.campaign_war_id!=front.war_id: continue
		var count: Array=fronts[front.front_id]; count[2]+=1; count[3]+=unit.size
		if unit.owner_nation==nation_id: count[0]+=1; count[1]+=unit.size
	var rows: Array=[row("进行中","%d场 · 进攻%d／防守%d"%[entries.size(),offense,entries.size()-offense])]
	for entry in entries:
		var record: StateCampaign=entry.record
		var front: CoalitionCampaignFront=entry.front
		var mode: int=entry.mode
		var status := "结束处理中" if record.lifecycle==StateCampaign.Lifecycle.ENDING else ("准备" if record.lifecycle==StateCampaign.Lifecycle.PREPARING else ("等待动员" if front==null or front.army_assignments.is_empty() else "执行"))
		var enemies := {}; var enemy_names: Array[String]=[]
		for id in entry.opponents:
			if not enemies.has(id): enemies[id]=true; enemy_names.append(nation_name(state,id))
		rows.append_array([
			row("战役%d"%record.campaign_id,"%s · %s"%["进攻" if mode==CoalitionCampaignFront.Mode.OFFENSE else "防守","未宣战" if record.war_id<0 else "战争%d"%(record.war_id+1)]),
			row("战役状态",status),row("对手","、".join(enemy_names)),
		])
		if front!=null:
			rows.append_array(execution_front_rows(state,front,fronts[front.front_id]))
		else:
			rows.append_array([
				row("目标州",city_name(state,record.center_city_id),"city",record.center_city_id),
				row("当前阶段","战前集结" if record.lifecycle==StateCampaign.Lifecycle.PREPARING else ("州治失守" if mode==CoalitionCampaignFront.Mode.DEFENSE and not record.defender_members.has(state.cities[record.center_city_id].owner_nation) else "等待动员")),
				row("主导国家",nation_name(state,record.initiator_nation_id if mode==CoalitionCampaignFront.Mode.OFFENSE else record.defender_nation_id)),
				row("本国投入","0支 · 0人"),row("战线总兵力","0支 · 0人"),
			])
		if record.lifecycle==StateCampaign.Lifecycle.ENDING: rows.append(row("结束原因",record.end_reason))
	return rows

static func execution_campaign_rows(state: GameState,nation_id: int) -> Array:
	var fronts:=state.campaign_fronts_for_nation(nation_id)
	if fronts.is_empty(): return [row("进行中","暂无州战役")]
	# Stable presentation order is independent of the simulation's tactical
	# priority. Only live Army bindings count; reports can be frozen in combat.
	fronts.sort_custom(func(a,b): return a.war_id<b.war_id if a.war_id!=b.war_id else a.front_id<b.front_id)
	var by_id: Dictionary={}; var totals: Dictionary={}; var offense:=0
	for front in fronts:
		by_id[front.front_id]=front; totals[front.front_id]=[0,0,0,0]
		if front.mode==CoalitionCampaignFront.Mode.OFFENSE: offense+=1
	for unit in state.armies:
		if unit.size<=0 or not by_id.has(unit.campaign_front_id): continue
		var front: CoalitionCampaignFront=by_id[unit.campaign_front_id]
		if unit.campaign_war_id!=front.war_id: continue
		var count: Array=totals[front.front_id]
		count[2]+=1; count[3]+=unit.size
		if unit.owner_nation==nation_id: count[0]+=1; count[1]+=unit.size
	var rows: Array=[row("进行中","%d场 · 进攻%d／防守%d"%[fronts.size(),offense,fronts.size()-offense])]
	for front in fronts:
		var count: Array=totals[front.front_id]
		rows.append(row("战役%d"%front.front_id,"%s · 战争%s"%["进攻" if front.mode==CoalitionCampaignFront.Mode.OFFENSE else "防守",binding_name(front.war_id,"未绑定",1)]))
		rows.append_array(execution_front_rows(state,front,count))
	return rows

static func execution_front_rows(state: GameState,front: CoalitionCampaignFront,count: Array) -> Array:
	var rows: Array=[
			row("目标州",city_name(state,front.center_city_id),"city",settlement_id(state,front.center_city_id)),
			row("当前阶段",CAMPAIGN_PHASE_NAMES.get(front.phase,"未识别阶段")),
			row("主导国家",nation_name(state,front.anchor_nation_id),"nation",front.anchor_nation_id),
			row("本国投入","%d支 · %d人"%[count[0],count[1]]),
			row("战线总兵力","%d支 · %d人"%[count[2],count[3]]),
			row("集结地",city_name(state,front.staging_city_id),"city",settlement_id(state,front.staging_city_id)),
			row("驻营地",city_name(state,front.camp_city_id),"city",settlement_id(state,front.camp_city_id)),
			row("重试等待","至"+Calendar.date(front.failed_until_day) if front.failed_until_day>state.day else "无"),
	]
	if front.mode==CoalitionCampaignFront.Mode.OFFENSE:
		var counts: Array[int]=[0,0,0,0]
		for task in front.detachments.values(): counts[int(task.status)]+=1
		rows.append(row("单轮分遣","%s · 出征%d／归队中%d／已归队%d／结束%d"%["已使用" if state.campaign_raid_used(front) else "未启动",counts[0],counts[1],counts[2],counts[3]]))
	if front.tactical_target_city_ids.is_empty(): rows.append(row("战术目标","未指定"))
	else:
		for target in front.tactical_target_city_ids:
			rows.append(row("战术目标",city_name(state,target),"city",settlement_id(state,target)))
	return rows
static func city(state: GameState,id: int) -> Dictionary:
	if id<0 or id>=state.cities.size() or not state.cities[id].is_settlement(): return {}
	var c := state.cities[id]; var owner := c.owner_nation; var center := state.administrative_center_of(id)
	var color := state.nations[owner].color if owner>=0 and owner<state.nations.size() else Color.GRAY
	var doc := {"title":c.name,"subtitle":"%s · %s"%["州治" if center==id else "府",Calendar.date(state.day)],"color":color,"point":c.map_position*Vector2(2048,1024),"actions":[action("nation","所属国家","flag",owner),action("focus","设为中心","center"),action("order","行军至此","route",id),action("copy","复制信息","copy")],"sections":[]}
	var capital := owner>=0 and owner<state.nations.size() and state.nations[owner].capital_city_id==id
	doc.sections.append(section("概况",[row("实控国家",nation_name(state,owner),"nation",owner),row("法理国家",nation_name(state,state.recognized_owner_of(id)),"nation",state.recognized_owner_of(id)),row("隶属州治",city_name(state,center),"city",center),row("行政身份","州治" if center==id else "府"),row("首都","是" if capital else "否")]))
	if center==id: doc.sections[0].rows.append(row("简称",c.short_name if not c.short_name.is_empty() else "未记录"))
	var production := [row("月人口产出",c.manpower_per_month),row("月金钱产出",c.gold_per_month),row("半年粮食产出",c.food_per_half_year)]
	if c.has_warehouse: production.append(row("本城粮仓",c.food_storage))
	doc.sections.append(section("资源与产出",production))
	doc.sections.append(section("统治与秩序",[row("忠诚度","%.1f / 100"%c.loyalty),row("认同国家",nation_name(state,c.loyalty_target_nation),"nation",c.loyalty_target_nation),row("忠诚趋势","%+.2f"%c.loyalty_trend),row("动荡度","%.1f"%c.unrest),row("叛乱累积月数",c.rebellion_progress),row("忠诚变化原因",c.last_loyalty_reason if not c.last_loyalty_reason.is_empty() else "无"),row("占领责任方",nation_name(state,c.occupation_sponsor_nation),"nation",c.occupation_sponsor_nation)]))
	var military := [row("守军人数",c.garrison_manpower),row("守军容量",state.city_garrison_capacity(id)),row("守军供给率","%.0f%%"%(c.garrison_supply_ratio*100)),row("战时状态","战时" if c.at_war else "和平"),row("战争减产截止",Calendar.date(c.war_disruption_until_day) if c.war_disruption_until_day>state.day else "无")]
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
static func recorded_ruler_rows(state: GameState,id: int) -> Array:
	var n := state.nations[id]
	var rows := [row("君主",n.ruler_name if not n.ruler_name.is_empty() else "未记录","person",n.ruler_person_id)]
	if n.ruler_name.is_empty() and n.ruler_person_id<0:
		rows.append(row("君主类型","未记录")); return rows
	rows.append(row("君主类型",RulerProfile.archetype_name(n.ruler_archetype)))
	rows.append(row("类型说明",RulerProfile.archetype_description(n.ruler_archetype)))
	var traits: Array[String]=[]
	for trait_id in n.ruler_traits: traits.append(RulerProfile.trait_name(trait_id))
	rows.append(row("君主特质","、".join(traits) if not traits.is_empty() else "无附加特质"))
	for trait_id in n.ruler_traits:
		rows.append(row("特质 · "+RulerProfile.trait_name(trait_id),RulerProfile.trait_description(trait_id)))
	rows.append(row("就任日期",Calendar.date(n.ruler_started_day)))
	if n.alive:
		var tenure := maxi(0,state.day-n.ruler_started_day)
		rows.append(row("已在位",Calendar.duration(tenure)))
	var person := PrincePolitics.person(state,id,n.ruler_person_id)
	rows.append(row("继承来源",{"crown":"太子","direct":"直系","collateral":"旁系宗室","remote":"远支"}.get(str(person.get("accession_source","")),"未记录")))
	var heir := PrincePolitics.person(state,id,n.crown_prince_person_id)
	rows.append(row("继承人",heir.get("name","未记录"),"person",n.crown_prince_person_id))
	rows.append(row("贸易政策",RulerProfile.trade_policy_name(n.trade_policy)))
	return rows

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
	var doc := {"title":nation_name(state,id),"subtitle":"%s · %s"%["帝国" if n.state_level>0 else "国家",Calendar.date(state.day)],"color":n.color,"point":point,"actions":[action("city","查看首都","city",capital),action("focus","设为中心","center"),action("player","操控此国","flag",id),action("declare","对其宣战","war",id),action("family","家族树","flag",id)],"sections":[]}
	doc["politics_recorded"] = state.has_meta("historical_prince_reports")
	if doc.politics_recorded: doc.sections.append(section("君主信息",recorded_ruler_rows(state,id)))
	var traits: Array[String] = []
	for trait_id in n.ruler_traits: traits.append(RulerProfile.trait_name(trait_id))
	doc.sections.append(section("概况",[row("状态","存续" if n.alive else "已灭亡"),row("首都",city_name(state,capital),"city",capital),row("控制治所",seats),row("控制州治",centers),row("控制府",seats-centers),row("君主",n.ruler_name if not n.ruler_name.is_empty() else "未记录","person",n.ruler_person_id),row("君主特质","、".join(traits) if not traits.is_empty() else "无附加特质"),row("平均忠诚度","%.1f"%n.average_loyalty)]))
	doc.sections[0].rows.append(row("国号来源",city_name(state,n.founding_city_id),"city",settlement_id(state,n.founding_city_id)))
	doc.sections[0].rows.append(row("建国环境",NationEnvironment.LABELS.get(n.environment_kind,"农耕")))
	doc.sections[0].rows.append(row("土地偏好",{"farm":"农业适宜的土地","nomad":"草原、荒漠与稀树草原","sea":"海岸","highland":"高地","river":"大河沿岸","lake":"大湖沿岸","forest":"林地、苔原与湿地"}.get(n.environment_kind,"农业适宜的土地")))
	var crown := PrincePolitics.person(state,id,n.crown_prince_person_id)
	var politics := [row("继承人",crown.get("name","未记录"),"person",n.crown_prince_person_id),
		row("竞争状态",prince_report(state,id).get("status","未记录")),
		row("帝国晋升",Calendar.date(n.empire_recognized_day) if n.empire_recognized_day>=0 else "尚未晋升"),
		row("晋升条件","和平宗藩体系完成一个贸易区域的法理与实控整合"),
		row("月结爵位人数","一字王%d · 郡王%d · 国公%d · 无爵%d"%[n.last_royal_title_counts[3],n.last_royal_title_counts[2],n.last_royal_title_counts[1],n.last_royal_title_counts[0]]),row("俸禄占税收","%.2f%%"%(n.last_royal_expense_basis_points/100.)),
		row("本君主继承来源",{"crown":"太子","direct":"直系","collateral":"旁系宗室","remote":"远支"}.get(str(PrincePolitics.person(state,id,n.ruler_person_id).get("accession_source","")),"未记录"))]
	if EmpireStatus.protecting_empire(state,id)>=0:
		politics.append(row("帝国守备","合法整合州治守军上限30000，沿用人力与供给规则逐月补充"))
	var report_data: Dictionary = prince_report(state,id)
	var internal: Dictionary=report_data.get("internal_battle",{})
	if not internal.is_empty():
		doc["notice"]="内部虚拟夺嫡：伤亡不影响真实军队，地图不生成战斗。"
		politics.append(row("挑战皇子",PrincePolitics.person(state,id,int(internal.challenger_person_id)).get("name","未记录"),"person",int(internal.challenger_person_id)))
		politics.append(row("守位太子",PrincePolitics.person(state,id,int(internal.crown_person_id)).get("name","未记录"),"person",int(internal.crown_person_id)))
	for line in PrincePolitics.display_lines(report_data): politics.append(row("宗室",line))
	for index in range(state.chronicle_events.size()-1,-1,-1):
		var event: Dictionary=state.chronicle_events[index]
		if event.get("kind","")=="succession" and event.get("actor_ids",[]).has(id):
			politics.append(row("最近夺嫡结果",Calendar.event_text(event))); break
	doc.sections.append(section("继承与王爵",politics))
	doc.sections.append(section("州战役",campaign_rows(state,id)))
	var target := RegionalStrategy.target_region(state,id)
	var integration := RegionalStrategy.integration_report(state,id,target)
	var ruler_section := section("君主与经营区域",[
		row("君主类型",RulerProfile.archetype_name(n.ruler_archetype)),row("特质","、".join(traits) if not traits.is_empty() else "无"),
		row("贸易政策",RulerProfile.trade_policy_name(n.trade_policy)),row("就任日期",Calendar.date(n.ruler_started_day)),
		row("经营区域",str(target+1) if target>=0 else "无"),row("区域锚点",city_name(state,n.strategic_region_anchor_city_id),"city",n.strategic_region_anchor_city_id),
		row("区域整合","%d / %d 治所"%[integration.integrated,integration.total]),
		row("主动扩张", "允许在经营区域内选择目标" if RulerProfile.offensive_allowed(n) else "仅允许收复或内战目标")])
	ruler_section.ruler={"id":id,"archetype":n.ruler_archetype,"traits":n.ruler_traits.duplicate(),"disabled":not n.alive}
	# Preserve text rows for copying; the inspector replaces them with controls.
	ruler_section.rows[0].ruler_field=true;ruler_section.rows[1].ruler_field=true
	doc.sections.append(ruler_section)
	doc.sections.append(section("国库与人口库",[row("金钱库存",n.treasury_gold),row("可用人口库",n.manpower_pool),row("粮仓库存",stock)]))
	doc.sections.append(section("最近月度结算",[row("野战军维护费",n.last_field_army_upkeep),row("守军维护费",n.last_garrison_upkeep),row("全军维护费",n.last_military_upkeep),row("欠付军费",n.unpaid_military_upkeep),row("军费支付率","%.0f%%"%(n.military_payment_ratio*100)),row("预计粮食月产",n.last_food_estimated_production),row("预计粮食月需",n.last_food_estimated_consumption),row("预计粮食结余",n.last_food_estimated_balance)]))
	var relations: Array = []
	for other in state.nations:
		if other.id==id or not other.alive: continue
		var relation := Diplomacy.kind(state,id,other.id)
		if relation not in ["neutral",""]:
			relations.append(row(Diplomacy.LABELS[relation],nation_name(state,other.id),"nation",other.id))
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
		var strength := [row("人数",unit.size),row("满编人数",unit.max_size),row("士气","%.2f"%unit.morale),row("有效士气／上限","%.2f / %.2f"%[unit.combat_morale(),unit.combat_max_morale()]),row("君主士气倍率","×%.2f"%maxf(unit.ruler_morale_multiplier,.1)),row("供给率","%.0f%%"%(unit.supply_ratio*100)),row("粮食补给欠额","%.2f"%unit.supply_food_debt),row("基础攻击",unit.attack),row("基础防御",unit.defense),row("君主攻击倍率","×%.2f"%maxf(unit.ruler_attack_multiplier,.1)),row("君主防御倍率","×%.2f"%maxf(unit.ruler_defense_multiplier,.1)),row("军费倍率","%.2f"%unit.funding_multiplier),row("修正后攻击","%.2f"%unit.combat_attack()),row("修正后防御","%.2f"%unit.combat_defense())]
		var deployment := [
			row("状态",["驻扎","行军","交战","败退","恢复","部署"][unit.state]),
			row("所在节点",city_name(state,unit.location_city),"city",settlement_id(state,unit.location_city)),
			row("当前道路进度","%.0f%%"%(unit.move_progress*100)),
			row("目标",city_name(state,target),"city",settlement_id(state,target)),
			row("战团",binding_name(unit.battle_group_id,"未编组")),
			row("战争",binding_name(unit.campaign_war_id,"未参战",1)),
			row("战线",binding_name(unit.campaign_front_id,"未绑定")),
			row("战斗",binding_name(unit.battle_id,"未交战"),"battle",unit.battle_id),
			row("命令原因",unit.ai_order_reason if not unit.ai_order_reason.is_empty() else "无")]
		return {"title":"军队%d"%id,"subtitle":"%s · %s"%[nation_name(state,owner),Calendar.date(state.day)],"color":color,"point":point,
			"actions":[action("nation","所属国家","flag",owner),action("focus","设为中心","center"),action("select_army","选中军队","war",id),action("copy","复制信息","copy")],
			"sections":[section("兵力与补给",strength),section("部署与行动",deployment)]}
	return {}
static func road(state: GameState,id: int) -> Dictionary:
	if id<0 or id>=state.edges.size(): return {}
	var e := state.edges[id]; var a := state.cities[e.city_a].map_position; var b := state.cities[e.city_b].map_position
	return {"title":"%s — %s"%[city_name(state,e.city_a),city_name(state,e.city_b)],"subtitle":"道路 · "+Calendar.date(state.day),"color":Color(.43,.32,.21),"point":e.map_position_at(.5,a,b,2.)*Vector2(2048,1024),"actions":[action("focus","设为中心","center"),action("copy","复制信息","copy")],"sections":[section("道路",[row("端点A",city_name(state,e.city_a),"city",e.city_a if not state.cities[e.city_a].is_traffic else -1),row("端点B",city_name(state,e.city_b),"city",e.city_b if not state.cities[e.city_b].is_traffic else -1),row("控制辖区",city_name(state,e.control_city_id),"city",e.control_city_id),row("长度","%.1f 公里"%(e.distance_units()*250)),row("道路容量",e.max_manpower),row("当前通行军队",e.passing_count),row("危险系数","%.2f"%e.danger),row("行军时间倍率","%.2f"%e.travel_time_multiplier),row("补给损耗倍率","%.2f"%e.supply_loss_multiplier)])]}

static func historical(document: Dictionary,kind: String) -> Dictionary:
	# PoliticalHistory freezes ownership, rulers, diplomacy and layout. Its view
	# state carries some copied live fields, not a complete economic/army save.
	var allowed := ["概况","地理与气候","选中道路"] if kind=="city" else ["概况","外交关系"] if kind=="nation" else ["道路"]
	if kind=="nation" and document.get("politics_recorded",false): allowed.append_array(["君主信息","继承与王爵"])
	document.sections=document.sections.filter(func(s): return s.title in allowed)
	for group in document.sections:
		group.rows=group.rows.filter(func(r): return r.label not in ["平均忠诚度","当前通行军队","危险系数","行军时间倍率","补给损耗倍率"])
	var limits: Array=[row("经济与兵力","此政治快照未记录")]
	if kind=="nation": limits.append(row("州战役","此政治快照未记录"))
	document.sections.append(section("快照范围",limits))
	return document
