extends RefCounted
const Calendar = preload("res://scripts/core/game_calendar.gd")
## Read-only battle disclosure. Reuse Combat's pure allocation/stat helpers;
## never resolve a round, attach a guard, or generate opening dice for display.
const Info = preload("res://scripts/atlas/information_model.gd")

static func position(state: GameState,battle: Battle) -> Vector2:
	if battle.traffic_node_id>=0 and battle.traffic_node_id<state.cities.size():
		return state.cities[battle.traffic_node_id].map_position*Vector2(2048,1024)
	if battle.city!=null: return battle.city.map_position*Vector2(2048,1024)
	if battle.edge!=null:
		var edge:=battle.edge
		return edge.map_position_at((battle.contact_dist_a+battle.contact_dist_b)*.5/maxf(.000001,edge.distance_units()),state.cities[edge.city_a].map_position,state.cities[edge.city_b].map_position,2.)*Vector2(2048,1024)
	return Vector2.ZERO

static func display_guard(state: GameState,battle: Battle) -> Army:
	# Match the temporary assault guard without adding it to either live array.
	var city:=battle.city; var guard:=Army.new()
	guard.is_city_garrison=true; guard.owner_nation=city.owner_nation
	guard.size=maxi(0,city.garrison_manpower); guard.morale=1.; guard.max_morale=1.
	if city.owner_nation>=0 and city.owner_nation<state.nations.size():
		guard.funding_multiplier=Army.funding_from_payment(state.nations[city.owner_nation].military_payment_ratio)
	var attacker:=battle.siege_attacker_nation
	if attacker<0 and not battle.side_a.is_empty(): attacker=battle.side_a[0].owner_nation
	guard.city_garrison_defense_bonus=state.city_garrison_defense_bonus(attacker,city.id)
	guard.city_garrison_combat_multiplier=maxf(city.ruler_city_defense_multiplier,.1)*(Combat.SIEGE_STARVE_DEF_MULT if city.food_storage<=0 else 1.)*lerpf(Combat.SIEGE_STARVE_DEF_MULT,1.,clampf(city.garrison_supply_ratio,0.,1.))
	return guard

static func snapshot(state: GameState,battle: Battle) -> Dictionary:
	var field:=battle.uses_field_combat_rules()
	var side_b: Array[Army]=battle.side_b.duplicate()
	if not field and battle.city!=null and not side_b.any(func(a): return a.is_city_garrison):
		side_b.append(display_guard(state,battle))
	var blockade:=false; var need:=0
	if not field and battle.city!=null and not battle.finished:
		var attacker:=battle.siege_attacker_nation
		if attacker<0 and not battle.side_a.is_empty(): attacker=battle.side_a[0].owner_nation
		var front:=state.campaign_front_for(attacker,battle.city.id,CoalitionCampaignFront.Mode.OFFENSE)
		need=state.campaign_attack_requirement(front.anchor_nation_id if front!=null else attacker,battle.city.id,false)
		var ready:=0
		for army in battle.side_a:
			if army.size>0 and army.combat_morale()>Combat.ARMY_ROUT_THRESHOLD: ready+=army.size
		blockade=ready<need
	return {"field":field,"blockade":blockade,"assault_requirement":need,
		"dice_ready":Battle.valid_dice(battle.opening_dice()),
		"guard_reserve":maxi(0,battle.city.garrison_manpower) if field and battle.city!=null and battle.side_b_defends_city else 0,
		"a":side_snapshot(battle,battle.side_a,1,field),"b":side_snapshot(battle,side_b,2,field)}

static func side_snapshot(battle: Battle,side: Array[Army],index: int,field: bool) -> Dictionary:
	var total:=battle.side_size(side); var morale:=battle.side_morale(side)
	if field: morale=float(battle.shared_morale_summary(side).effective)
	var maximum:=0.; var supply:=0.; var funding:=0.; var ruler_attack:=0.; var ruler_defense:=0.; var ruler_morale:=0.
	for army in side:
		if army.size<=0: continue
		var weight:=float(army.size)/maxi(1,total)
		maximum+=army.combat_max_morale()*weight; supply+=clampf(army.supply_ratio,0.,1.)*weight
		funding+=army.funding_multiplier*weight
		ruler_attack+=(1. if army.is_city_garrison else maxf(army.ruler_attack_multiplier,.1))*weight
		ruler_defense+=(1. if army.is_city_garrison else maxf(army.ruler_defense_multiplier,.1))*weight
		ruler_morale+=(1. if army.is_city_garrison else maxf(army.ruler_morale_multiplier,.1))*weight
	var dice:=battle.opening_dice(); var ready:=Battle.valid_dice(dice)
	var performance:=Battle.dice_multiplier(dice[index-1]) if ready else 1.
	var expansion:=Battle.dice_multiplier(dice[index+1]) if ready else 1.
	var frontage:=int(Combat.combat_frontage(battle)*expansion)
	var priority: Dictionary=battle.frontline_priority_a if index==1 else battle.frontline_priority_b
	var frontline:=Combat.frontline_allocation(side,frontage,priority,field)
	var danger:=battle.edge.danger if battle.edge!=null else 0.
	var holding:=field and battle.holding_side==index
	var terrain_attack:=Combat.attack_multiplier(danger) if field else 1.
	var terrain_defense:=Combat.defense_multiplier(danger,battle.holding_days if holding else 0.) if field else 1.
	var hold_attack:=Combat.holding_attack_multiplier(holding)
	var hold_defense:=Combat.holding_defense_multiplier(holding)
	var direction:=Combat.siege_attack_damage_multiplier(battle) if index==1 else 1.
	return {"size":total,"morale":morale,"maximum":maximum,"supply":supply,"funding":funding,
		"ruler_attack":ruler_attack,"ruler_defense":ruler_defense,"ruler_morale":ruler_morale,
		"frontage":frontage,"engaged":Combat._frontline_size(frontline),"performance":performance,"expansion":expansion,
		"terrain_attack":terrain_attack,"terrain_defense":terrain_defense,"holding_attack":hold_attack,"holding_defense":hold_defense,"direction":direction,
		"fire":Combat._frontline_attack(frontline)*terrain_attack*hold_attack*performance*direction,
		"defense":Combat._frontline_avg_defense(frontline)*terrain_defense*hold_defense*performance}

static func side_rows(stats: Dictionary,ready: bool,blockade: bool,guard_city: City = null) -> Array:
	var percentage: float=stats.morale/stats.maximum*100. if stats.maximum>0. else 0.
	return [Info.row("当前兵力","%d 人"%stats.size),
		Info.row("有效士气","%.2f / %.2f（%.0f%%）"%[stats.morale,stats.maximum,percentage]),
		Info.row("军队供给均值" if guard_city==null else "守军供给","%.0f%%"%((stats.supply if guard_city==null else guard_city.garrison_supply_ratio)*100.)),
		Info.row("君主攻／防均值","×%.2f / ×%.2f"%[stats.ruler_attack,stats.ruler_defense]),
		Info.row("君主士气均值","×%.2f"%stats.ruler_morale),
		Info.row("军费倍率均值","×%.2f"%stats.funding),
		Info.row("地形攻／防","×%.2f / ×%.2f"%[stats.terrain_attack,stats.terrain_defense]),
		Info.row("驻防攻／防","×%.2f / ×%.2f"%[stats.holding_attack,stats.holding_defense]),
		Info.row("多方向进攻","×%.2f"%stats.direction),
		Info.row("发挥／展开",("×%.2f / ×%.2f"%[stats.performance,stats.expansion]) if ready else "待开场"),
		Info.row("展开宽度",("%d 人"%stats.frontage) if ready else "待开场"),
		Info.row("前线／预备",("%d / %d 人"%[stats.engaged,stats.size-stats.engaged]) if ready and not blockade else "封锁中" if blockade else "待开场"),
		Info.row("下轮有效火力",("%.1f"%stats.fire) if ready and not blockade else "封锁中" if blockade else "待开场"),
		Info.row("下轮平均防御",("%.2f"%stats.defense) if ready and not blockade else "封锁中" if blockade else "待开场")]

static func roster(state: GameState,side: Array[Army]) -> Array:
	var rows: Array=[]; var nations: Array[int]=[]
	for army in side:
		if army.size<=0 or army.is_city_garrison: continue
		if not nations.has(army.owner_nation): nations.append(army.owner_nation)
	for nation in nations: rows.append(Info.row("参战国家",Info.nation_name(state,nation),"nation",nation))
	for army in side:
		if army.size>0 and not army.is_city_garrison:
			rows.append(Info.row("军队%d"%army.id,"%d人 · 士气%.2f · 补给%.0f%%"%[army.size,army.combat_morale(),army.supply_ratio*100.],"army",army.id))
	return rows if not rows.is_empty() else [Info.row("参战部队","城市守军" if side.any(func(a): return a.is_city_garrison) else "无野战军")]

static func comparison(data: Dictionary,labels: Array[String],city: City) -> Dictionary:
	var left:=side_rows(data.a,data.dice_ready,data.blockade)
	var right:=side_rows(data.b,data.dice_ready,data.blockade,city if not data.field else null)
	var rows: Array=[]; var remaining: Array=[]
	for index in range(left.size()):
		var label: String="供给率" if left[index].label in ["军队供给均值","守军供给"] else left[index].label
		var row:=Info.row(label,"%s：%s；%s：%s"%[labels[0],left[index].value,labels[1],right[index].value])
		row.cells=[left[index].value,right[index].value]; remaining.append(row)
	# Put current strength and derived combat power ahead of modifier details.
	for label in ["当前兵力","有效士气","下轮有效火力","下轮平均防御"]:
		for row in remaining:
			if row.label==label: rows.append(row); break
	for row in remaining:
		if not rows.has(row): rows.append(row)
	return {"title":"双方对比","columns":labels,"rows":rows}

static func document(state: GameState,id: int) -> Dictionary:
	var battle: Battle=null
	for candidate in state.battles:
		if candidate.id==id: battle=candidate; break
	if battle==null: return {}
	var data:=snapshot(state,battle)
	var phase: String="道路野战" if battle.kind==Battle.Kind.FIELD else "城下野战" if data.field else "封锁" if data.blockade else "攻城"
	var labels: Array[String]=["甲方","乙方"]
	if battle.kind==Battle.Kind.SIEGE:
		labels=["围城方","守城方" if battle.side_b_defends_city or not data.field else "挑战方"]
	var status: String=(labels[battle.winner_side-1]+"获胜" if battle.winner_side in [1,2] else "结束／未决") if battle.finished else "进行中"
	var overview: Array=[Info.row("状态",status),Info.row("已结算回合",battle.round_no),
		Info.row("双方兵力","%d : %d"%[data.a.size,data.b.size]),
		Info.row("双方士气","%.2f : %.2f"%[data.a.morale,data.b.morale]),
		Info.row("基础展开宽度","%d 人"%Combat.combat_frontage(battle)),
		Info.row("溃败士气阈值","%.2f"%Combat.SIDE_ROUT_THRESHOLD)]
	if battle.city!=null: overview.append(Info.row("战场",battle.city.name,"city",Info.settlement_id(state,battle.city.id)))
	if battle.holding_side in [1,2] and data.field: overview.append(Info.row("连续驻防","%s · %s"%[labels[battle.holding_side-1],Calendar.duration(roundi(battle.holding_days))]))
	var doc: Dictionary={"title":"战斗%d"%id,"subtitle":"%s · %s · %s"%[phase,status,Calendar.date(state.day)],"color":Color("c35e56"),"point":position(state,battle),
		"notice":"左列为%s，右列为%s；士气只决定溃败，火力按当前前线与开场骰计算，均值按兵力加权。"%labels,
		"preferred_width":560.,
		"actions":[Info.action("focus","定位战场","center"),Info.action("copy","复制信息","copy")],
		"sections":[comparison(data,labels,battle.city),Info.section("战况",overview)]}
	for index in range(2):
		doc.sections.append(Info.section(labels[index]+" · 参战部队",roster(state,battle.side_a if index==0 else battle.side_b)))
	if battle.city!=null and (not data.field or battle.side_b_defends_city):
		var city:=battle.city
		doc.sections.append(Info.section("城内守军",[Info.row("实际守军","%d 人"%maxi(0,city.garrison_manpower)),
			Info.row("本轮参与","不参与城下野战" if data.field else "封锁中，尚未交战" if data.blockade else "单独参加攻城回合"),
			Info.row("守军士气","固定为 1.00"),Info.row("城内粮食",city.food_storage),Info.row("守军供给","%.0f%%"%(city.garrison_supply_ratio*100.)),
			Info.row("君主城防","×%.2f"%maxf(city.ruler_city_defense_multiplier,.1)),
			Info.row("断粮攻防倍率","×%.2f"%(Combat.SIEGE_STARVE_DEF_MULT if city.food_storage<=0 else 1.))]))
		if not data.field:
			var guard:=display_guard(state,battle)
			doc.sections.back().rows.append(Info.row("守军供给攻防","×%.2f"%lerpf(Combat.SIEGE_STARVE_DEF_MULT,1.,clampf(city.garrison_supply_ratio,0.,1.))))
			doc.sections.back().rows.append(Info.row("守军攻击倍率","×%.2f"%Combat.CITY_GARRISON_ATTACK_MULTIPLIER))
			doc.sections.back().rows.append(Info.row("工事防御倍率","×%.2f"%guard.city_garrison_defense_bonus))
			doc.sections.back().rows.append(Info.row("强攻所需兵力","%d 人"%data.assault_requirement))
	return doc
