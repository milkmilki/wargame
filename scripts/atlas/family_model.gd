extends RefCounted
const Calendar = preload("res://scripts/core/game_calendar.gd")
## Read-only family presentation. No ensure/reconcile/accession calls here.
const Info = preload("res://scripts/atlas/information_model.gd")
static func capture(state: GameState, nation_id: int) -> Dictionary:
	if nation_id < 0 or nation_id >= state.nations.size(): return {}
	var nation := state.nations[nation_id]
	var tree := FamilyTree.tree_for_nation(state, nation_id)
	if tree.is_empty(): return {}
	var members: Dictionary = tree.members.duplicate(true)
	var countries: Array = []
	for n in state.nations:
		if n.family_tree_id != nation.family_tree_id: continue
		countries.append({"id":n.id,"name":WorldNaming.nation_display_name(state,n.id),"ruler":n.ruler_person_id,"alive":n.alive,"started":n.ruler_started_day})
		# Nation is authoritative for an active ruler. Resolve missing/stale
		# family profiles only in this source's detached presentation copy.
		if n.alive and members.has(n.ruler_person_id):
			var member: Dictionary=members[n.ruler_person_id]
			member["archetype"]=n.ruler_archetype
			member["traits"]=n.ruler_traits.duplicate()
	var reigns := {}; var reign_ends := {}
	for event in state.chronicle_events:
		if event.get("kind","") != "ruler_succession": continue
		var persons: Array = event.get("person_ids",[])
		if persons.size() == 2 and members.has(persons[1]): reigns[persons[1]] = int(event.day)
		if persons.size() == 2 and members.has(persons[0]): reign_ends[persons[0]] = int(event.day)
	for n in countries: reigns[n.ruler] = int(n.started)
	for id in members:
		var m: Dictionary = members[id]
		m["display_title"] = FamilyTree.display_title(m,int(id),int(tree.get("root_person_id",-1)),state)
		m["title_lines"] = FamilyTree.title_history_lines(m)
		m["was_ruler"] = not m.get("nation_ids",[]).is_empty() or reigns.has(id) or int(m.get("office_nation_id",-1)) >= 0 or FamilyTree.was_emperor(m)
		m["was_emperor"] = FamilyTree.was_emperor(m)
		m["last_reign"] = int(reigns.get(id,-1))
		m["reign_end"] = int(reign_ends.get(id,-1))
	var events: Array = []
	for e in state.chronicle_events:
		if e.get("kind","") == "succession" and (members.has(e.get("person_ids",[-1])[0])): events.append(e.duplicate(true))
	return {"source":state.get_instance_id(),"day":state.day,"tree_id":nation.family_tree_id,
		"nation_id":nation_id,"name":WorldNaming.nation_display_name(state,nation_id),"current":nation.ruler_person_id if nation.alive else -1,"last_ruler":nation.ruler_person_id,
		"heir":nation.crown_prince_person_id,"members":members,"countries":countries,"events":events,
		"root":int(tree.get("root_person_id",-1))}

static func structural_key(model: Dictionary) -> int:
	var shape: Array = []
	var ids: Array = model.members.keys(); ids.sort()
	for id in ids:
		var m: Dictionary=model.members[id]
		shape.append([id,m.get("parent_id",-1),m.get("birth_order",0)])
	return hash(shape)

static func person_document(model: Dictionary,id: int) -> Dictionary:
	if model.is_empty() or not model.members.has(id): return {}
	var m: Dictionary = model.members[id]
	var archetype := int(m.get("archetype",-1))
	var recorded := RulerProfile.is_valid_archetype(archetype)
	var rows: Array = [Info.row("身份",m.display_title),Info.row("状态","在世" if m.get("alive",true) else "已故"),
		Info.row("人物类型",RulerProfile.archetype_name(archetype) if recorded else "未记录")]
	if recorded: rows.append(Info.row("类型说明",RulerProfile.archetype_description(archetype)))
	var traits: Array = []
	for trait_id in m.get("traits",[]): traits.append(RulerProfile.trait_name(str(trait_id)))
	rows.append(Info.row("特质","、".join(traits) if not traits.is_empty() else "无" if m.has("traits") else "未记录"))
	for trait_id in m.get("traits",[]):
		rows.append(Info.row("特质 · "+RulerProfile.trait_name(str(trait_id)),RulerProfile.trait_description(str(trait_id))))
	rows.append(Info.row("太子","是" if m.get("crown",false) else "否"))
	rows.append(Info.row("生卒 / 年龄","未记录"))
	rows.append(Info.row("即位起日",Calendar.date(int(m.last_reign))))
	rows.append(Info.row("即位止日",Calendar.date(int(m.reign_end))))
	rows.append(Info.row("太祖","是" if m.get("taizu",false) else "否"))
	rows.append(Info.row("帝号记录","曾有帝号" if m.was_emperor else "无"))
	var fief:=int(m.get("enfeoffed_nation_id",-1))
	for n in model.countries:
		if n.id==fief: rows.append(Info.row("实封",n.name,"nation",fief))
	var parent := int(m.get("parent_id",-1))
	rows.append(Info.row("父亲",model.members.get(parent,{}).get("name","未记录"),"person",parent if model.members.has(parent) else -1))
	var children: Array = []
	for child in model.members:
		if int(model.members[child].get("parent_id",-1)) == id: children.append(child)
	children.sort_custom(func(a,b): return int(model.members[a].get("birth_order",0)) < int(model.members[b].get("birth_order",0)) if model.members[a].get("birth_order",0)!=model.members[b].get("birth_order",0) else a<b)
	for child in children: rows.append(Info.row("子嗣",model.members[child].get("name","未记录"),"person",child))
	for n in model.countries:
		if n.ruler == id: rows.append(Info.row("现任国家" if n.alive else "曾任国家",n.name,"nation",n.id))
	var title_rows: Array = []
	for line in m.title_lines: title_rows.append(Info.row("爵号履历",line))
	if title_rows.is_empty(): title_rows.append(Info.row("爵号履历","未记录"))
	var events: Array = []
	for e in model.events:
		if e.get("person_ids",[]).has(id): events.append(Info.row(Calendar.date(int(e.day)),Calendar.event_text(e)))
	return {"title":m.get("name","未记录"),"subtitle":"人物 %d · %s"%[id,Calendar.date(model.day)],"color":Color("007aff"),"point":Vector2.ZERO,
		"notice":"家谱仅供查看；未记录的年龄与生卒不推测。","actions":[],
		"sections":[Info.section("人物",rows),Info.section("爵号历史",title_rows),Info.section("夺嫡记录",events if not events.is_empty() else [Info.row("记录","暂无")])]}
