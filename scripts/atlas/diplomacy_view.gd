extends RefCounted
## Legacy political relationship semantics, independent of map generation.
const COLORS := {"enemy":Color(.72,.08,.06),"ally":Color(.10,.56,.20),"vassal":Color(.42,.42,.42),"neutral":Color.BLACK}
const LABELS := {"self":"本国","enemy":"敌对","ally":"同盟","vassal":"藩属","neutral":"中立","":"未选观察国"}
static func valid(state: GameState,id: int) -> bool:
	return state!=null and id>=0 and id<state.nations.size() and state.nations[id].alive
static func kind(state: GameState,observer: int,target: int) -> String:
	if not valid(state,observer) or not valid(state,target): return ""
	if target==observer: return "self"
	if state.is_enemy(observer,target): return "enemy"
	var current := target; var guard := state.nations.size()
	while state.is_vassal(current) and guard>0:
		if state.is_in_civil_war(current): break
		current=state.overlord_of(current)
		if current==observer: return "vassal"
		guard-=1
	return "ally" if state.is_allied(observer,target) else "neutral"
static func color(state: GameState,observer: int,target: int) -> Color:
	var category := kind(state,observer,target)
	return COLORS[category] if COLORS.has(category) else state.nations[target].color if target>=0 and target<state.nations.size() else Color(.45,.45,.43)
static func rows(state: GameState,observer: int,search: String = "") -> Array:
	var result: Array=[]
	if state==null: return result
	var counts := PackedInt32Array(); counts.resize(state.nations.size())
	for city in state.cities:
		if city.is_settlement() and city.owner_nation>=0 and city.owner_nation<counts.size(): counts[city.owner_nation]+=1
	var query := search.strip_edges().to_lower()
	for nation in state.nations:
		if not nation.alive or (not query.is_empty() and not nation.name.to_lower().contains(query)): continue
		var capital := nation.capital_city_id
		result.append({"id":nation.id,"name":nation.name,"capital":state.cities[capital].name if capital>=0 and capital<state.cities.size() else "无","count":counts[nation.id],"relation":LABELS[kind(state,observer,nation.id)],"color":color(state,observer,nation.id)})
	result.sort_custom(func(a,b): return a.id<b.id)
	return result
