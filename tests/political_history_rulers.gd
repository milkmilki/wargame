extends SceneTree
const Info = preload("res://scripts/atlas/information_model.gd")
const FamilyModel = preload("res://scripts/atlas/family_model.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures+=1; printerr("HISTORY_RULERS_FAIL ",message)
func value(doc: Dictionary,label: String) -> String:
	for group in doc.sections:
		if group.title!="君主信息": continue
		for entry in group.rows:
			if entry.label==label: return str(entry.value)
	return ""
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var state := preload("res://tests/succession_chain.gd").fixture()
	var sim := Simulation.new(); sim.setup(state); sim.paused=true
	var nation := state.nations[0]
	sim.set_ruler_profile(0,RulerProfile.CONQUEROR,[RulerProfile.TRAIT_AMBITIOUS,RulerProfile.TRAIT_DILIGENT])
	nation.ruler_started_day=30; state.day=120
	var first_name := nation.ruler_name; var first_id := nation.ruler_person_id
	var first_policy := nation.trade_policy
	var first_heir: String=PrincePolitics.person(state,0,nation.crown_prince_person_id).get("name","未记录")
	var history := PoliticalHistory.new(); history.reset(state)
	sim.set_ruler_profile(0,RulerProfile.MERCHANT,[RulerProfile.TRAIT_FRUGAL])
	state.day=150; history.maybe_capture(state)
	state.day=RulerProfile.succession_due_day(nation,state.world_seed)
	sim._resolve_ruler_successions()
	check(nation.ruler_person_id!=first_id,"fixture uses a real ruler death and accession")
	sim.set_ruler_profile(0,RulerProfile.GUARDIAN,[RulerProfile.TRAIT_FORTIFIER])
	state.day+=posmod(-state.day,30); history.maybe_capture(state)
	var current_name := nation.ruler_name
	var later := Nation.new(); later.id=1; later.ruler_name="未来君主"; later.ruler_archetype=RulerProfile.TYRANT
	later.ruler_traits=[RulerProfile.TRAIT_HARSH]; later.trade_policy=RulerProfile.POLICY_FOOD; state.nations.append(later)
	var live_before := NativeSnapshotBuilder.build(state); var rng_before := state.rng.state
	var past := history.build_view_state(state,0)
	var doc := Info.historical(Info.nation(past,0),"nation")
	check(value(doc,"君主")==first_name,"historical ruler name remains visible")
	check(value(doc,"君主类型")==RulerProfile.archetype_name(RulerProfile.CONQUEROR),"historical country card exposes the recorded ruler type")
	check(value(doc,"类型说明")==RulerProfile.archetype_description(RulerProfile.CONQUEROR),"historical type description matches that ruler")
	check(value(doc,"君主特质").contains(RulerProfile.trait_name(RulerProfile.TRAIT_DILIGENT)),"historical traits are visible")
	check(value(doc,"就任日期")=="第30天" and value(doc,"已在位").begins_with("90天"),"tenure is measured at the selected snapshot date")
	check(value(doc,"继承人")==first_heir,"heir comes from the captured family")
	check(past.nations[0].trade_policy==first_policy and value(doc,"贸易政策")==RulerProfile.trade_policy_name(first_policy),"trade policy does not leak from a later ruler")
	check(doc.sections.all(func(group): return not group.has("ruler")),"historical ruler information has no editor controls")
	var family_doc := FamilyModel.person_document(FamilyModel.capture(past,0),first_id)
	check(family_doc.title==first_name,"recorded ruler link resolves to the historical person")
	var unrecorded := Info.historical(Info.nation(past,1),"nation")
	check(past.nations[1].ruler_name.is_empty() and value(unrecorded,"君主")=="未记录","an unborn nation cannot expose its future ruler")
	past=history.build_view_state(state,1); doc=Info.historical(Info.nation(past,0),"nation")
	check(value(doc,"君主类型")==RulerProfile.archetype_name(RulerProfile.MERCHANT),"later snapshot records a changed profile independently")
	past=history.build_view_state(state,2); doc=Info.historical(Info.nation(past,0),"nation")
	check(value(doc,"君主")==current_name and value(doc,"君主类型")==RulerProfile.archetype_name(RulerProfile.GUARDIAN),"post-succession snapshot displays the successor")
	history.build_view_state(state,0)
	check(NativeSnapshotBuilder.build(state)==live_before and state.rng.state==rng_before,"history queries cannot mutate the live ruler, family or random stream")
	sim.free(); print("POLITICAL_HISTORY_RULERS failures=",failures); quit(1 if failures else 0)
