extends SceneTree
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
const Model = preload("res://scripts/atlas/family_model.gd")
const Audit = preload("res://tests/royal_title_audit.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_grid_world(73003,false); state.region_ids.fill(-1)
	for a in range(state.nations.size()):
		for b in range(a+1,state.nations.size()): state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.NEUTRAL)
	FamilyFixture.ensure_candidates(state,0,3); FamilyFixture.ensure_candidates(state,1,3)
	for city in state.land_cities_of(0): state.region_ids[city.id]=10
	EmpireStatus.reconcile(state)
	return state
func enfeoff(state: GameState, home: int) -> int:
	for center in state.administrative_center_city_ids:
		if state.cities[center].owner_nation==home and center!=state.nations[home].capital_city_id:
			var result:=state.enfeoff(home,[center])
			if result>=0: return result
	return -1
func run() -> void:
	test_same_clan()
	test_foreign()
	test_hostile_annex(false)
	test_hostile_annex(true)
	test_stipend_suspension()
	test_multiple_courts()
	test_extinct_fief()
	for failure in failures: push_error("LANDED_TITLE_FAIL: "+failure)
	print("ROYAL_LANDED_TITLES checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
func test_same_clan() -> void:
	var state:=fixture(); var nation:=state.nations[0]
	var members: Dictionary=FamilyTree.tree_for_nation(state,0).members
	var king:=PrincePolitics.enfeoff_candidate(state,0)
	var old_title:=str(members[king].current_title)
	var old_history: Array=members[king].title_history.duplicate(true)
	var old_expense:=int(RoyalTitles.report(state,0).basis_points)
	var history:=PoliticalHistory.new(); history.reset(state)
	state.day=30
	var subject:=enfeoff(state,0)
	check(subject>=0 and state.nations[subject].ruler_person_id==king,"real enfeoffment retains the same person")
	if subject<0: return
	check(RoyalTitles.effective_rank(state,members[king])==RoyalTitles.PRINCE,"the landed king still holds prince rank")
	check(str(members[king].current_title)==old_title and members[king].title_history==old_history,"land allocation preserves the original open designation")
	check(int(members[king].get("title_payer_id",-1))==subject and int(members[king].get("title_funding_nation_id",-1))==0 and int(members[king].get("title_generation_nation_id",-1))==subject,"court, stipend and generation have independent homes")
	check(int(RoyalTitles.report(state,0).basis_points)==old_expense and int(RoyalTitles.report(state,subject).basis_points)==0,"the overlord pays existing titles once and the fief pays no duplicate stipend")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"landed rank validates before succession")
	var before_read:=state.family_trees.duplicate(true); var rng:=state.rng.state
	RoyalTitles.reconcile(state); FamilyTree.record_current_title(state,subject)
	check(state.family_trees==before_read and state.rng.state==rng,"reconciliation preserves open grants without consuming randomness")
	var children:=RoyalTitles.children(members,king)
	for child in children:
		check(RoyalTitles.effective_rank(state,members[child])==RoyalTitles.COMMANDERY,"existing children retain declining ranks")
		check(int(members[child].get("title_funding_nation_id",-1))==0 and int(members[child].get("title_generation_nation_id",-1))==subject,"children follow their own court's generations while receiving external stipends")
	check(PrincePolitics.select_successor(state,0).person_id!=state.nations[subject].crown_prince_person_id,"external funding alone does not import the fief's heir into the mother court")
	state.day=60
	check(PrincePolitics.accede(state,0),"real overlord succession completes")
	check(bool(members[king].get("alive",false)),"the landed king survives the overlord's death")
	for child in children: check(bool(members[child].get("alive",false)),"the fief's descendants are not settled with the overlord cohort")
	state.day=90
	var heir:=state.nations[subject].crown_prince_person_id
	check(PrincePolitics.accede(state,subject),"the actual fief successor accedes")
	check(heir>=0 and state.nations[subject].ruler_person_id==heir and RoyalTitles.effective_rank(state,members[heir])==RoyalTitles.PRINCE and str(members[heir].current_title)==old_title,"the lawful heir inherits the same rank, designation and actual fief")
	if heir<0: return
	var before_recall: Array=members[heir].title_history.duplicate(true)
	state.day=120
	check(state.revoke_vassal(subject),"the same actual fief is peacefully recalled")
	check(RoyalTitles.effective_rank(state,members[heir])==RoyalTitles.PRINCE and str(members[heir].current_title)==old_title,"recall removes the land without removing the prince's title")
	check(members[heir].title_history==before_recall,"recall does not terminate and regrant the same title")
	check(int(members[heir].get("enfeoffed_nation_id",-1))<0 and int(members[heir].get("title_generation_nation_id",-1))==0,"the recalled branch now follows its receiving court")
	var current:=Model.capture(state,0)
	check(current.members[king].get("title_steps",[]).any(func(step): return int(step.get("fief_nation_id",-1))==subject),"genealogy records the land-bearing phase alongside the rank")
	check(not Model.capture(history.build_view_state(state,0),0).members[king].get("title_steps",[]).any(func(step): return int(step.get("fief_nation_id",-1))>=0),"past genealogy does not borrow a later fief")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"combined land and rank validates after real succession and recall")
func test_foreign() -> void:
	var state:=fixture(); var foreign:=state.nations[1]
	var tree_id:=foreign.family_tree_id; var king:=foreign.ruler_person_id
	var members: Dictionary=FamilyTree.tree_for_nation(state,1).members
	check(state.accept_submission(0,1),"a real foreign submission succeeds")
	check(foreign.family_tree_id==tree_id and RoyalTitles.effective_rank(state,members[king])==RoyalTitles.COMMANDERY,"a foreign fief holds commandery rank in its own genealogy")
	check(int(members[king].get("title_funding_nation_id",-1))==0 and int(members[king].get("title_generation_nation_id",-1))==1,"the foreign house uses separate finance and generation domains")
	var document:=Model.person_document(Model.capture(state,1),king)
	var rows: Array=document.sections[0].rows
	check(rows.any(func(row):return row.label=="俸禄供养" and row.id==0),"a foreign genealogy can display and link its external stipend court")
	for child in RoyalTitles.children(members,king): check(RoyalTitles.effective_rank(state,members[child])==RoyalTitles.DUKE,"foreign fief children follow existing declining rank grants")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"the landed foreign grant is snapshot-valid")
	for field in ["title_funding_nation_id","title_generation_nation_id"]:
		var invalid:=NativeSnapshotBuilder.build(state)
		for family in invalid.family_trees:
			for member in family.members:
				if member.id==king: member[field]=1 if field=="title_funding_nation_id" else 0
		check(not NativeSnapshotBuilder.succession_validation_error(invalid).is_empty(),"snapshot rejects a crossed title domain: "+field)
	var old:=NativeSnapshotBuilder.build(state); old.schema_version=30
	check(not NativeSnapshotBuilder.succession_validation_error(old).is_empty(),"v30 runtime snapshots are explicitly rejected")
	var saved: Array=members[king].get("title_history",[]).duplicate(true)
	check(state.revoke_vassal(1),"foreign peaceful recall commits")
	check(RoyalTitles.effective_rank(state,members[king])==RoyalTitles.COMMANDERY and members[king].title_history==saved,"a foreign recall keeps its existing commandery title open")

func test_hostile_annex(reverse: bool) -> void:
	var state:=fixture(); var subject:=enfeoff(state,0)
	check(subject>=0,"wartime fixture uses a real landed house")
	if subject<0: return
	var king:=state.nations[subject].ruler_person_id
	var member:=PrincePolitics.person(state,subject,king)
	var winner:=subject if reverse else 0; var loser:=0 if reverse else subject
	var army:=state.create_army(loser,state.nations[loser].capital_city_id,1000)
	check(army!=null,"wartime fixture has an actual army")
	var gold:=state.nations[winner].treasury_gold+state.nations[loser].treasury_gold
	state.set_diplomatic_relation(0,subject,GameState.DiplomaticRelation.WAR)
	var declarations:=state.chronicle_events.filter(func(e):return e.get("kind","")=="war_started").size()
	state.day=180
	check(state.annex_nation(winner,loser),"real wartime annexation completes in either victory direction")
	var simulation:=Simulation.new(); simulation.state=state
	simulation._resolve_eliminated_nation_capitulations()
	ChronicleRules.finalize_pending(state)
	check(not state.nations[loser].alive and state.nations[loser].treasury_gold==0 and state.nations[winner].treasury_gold==gold,"annexation settles treasury once")
	check(army.owner_nation==winner and army.campaign_war_id<0 and state.wars_of(loser).is_empty(),"annexation transfers army and releases the defeated war")
	check(state.chronicle_events.filter(func(e):return e.get("kind","")=="war_started").size()==declarations,"annexation does not create another declaration")
	check(state.chronicle_events.filter(func(e):return e.get("kind","")=="external_war").size()==1,"the normal war lifecycle emits one final event")
	if reverse:
		check(int(member.enfeoffed_nation_id)==-1 and int(member.title_rank)==0,"the counterattacking sovereign leaves landed peerage")
		check(member.title_history.back().end_reason=="independence","counter-conquest closes the actual former peerage")
	else:
		check(int(member.title_rank)==0 and member.title_history.back().end_reason=="annexation","hostile absorption ends a grant even when the victor originally issued it")
	var after:=state.family_trees.duplicate(true); var treasury:=state.nations[winner].treasury_gold
	check(not state.annex_nation(winner,loser) and state.family_trees==after and state.nations[winner].treasury_gold==treasury,"repeated defeated-state annexation cannot settle titles or resources again")
	simulation._resolve_eliminated_nation_capitulations(); ChronicleRules.finalize_pending(state); simulation.free()
	check(state.chronicle_events.filter(func(e):return e.get("kind","")=="external_war").size()==1,"repeated cleanup does not duplicate the final war event")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"both annexation directions leave a valid snapshot")

func test_stipend_suspension() -> void:
	var state:=fixture(); var subject:=enfeoff(state,0)
	if subject<0: check(false,"stipend fixture creates a landed house"); return
	var king:=PrincePolitics.person(state,subject,state.nations[subject].ruler_person_id)
	var paid:=int(RoyalTitles.report(state,0).basis_points)
	state.set_diplomatic_relation(0,subject,GameState.DiplomaticRelation.WAR)
	check(int(RoyalTitles.report(state,0).basis_points)<paid and RoyalTitles.effective_rank(state,king)==3,"hostility invalidates stipend census without deleting peerage")
	state.set_diplomatic_relation(0,subject,GameState.DiplomaticRelation.ALLIED)
	check(int(RoyalTitles.report(state,0).basis_points)==paid,"peace restores the same stipend obligation once")

func test_multiple_courts() -> void:
	var state:=fixture(); var subject:=enfeoff(state,0)
	if subject<0: check(false,"multiple-court fixture creates a real fief"); return
	check(state.accept_submission(0,1),"a second independent foreign family joins the same overlord")
	for cycle in range(8):
		state.day+=360
		# Keep a domestic heir so this scenario does not deliberately exercise
		# the separate, valid accession of a landed collateral into the mother court.
		FamilyFixture.ensure_candidates(state,0,3)
		var kings: Array[int]=[state.nations[subject].ruler_person_id,state.nations[1].ruler_person_id]
		check(PrincePolitics.accede(state,0),"overlord succession in cycle "+str(cycle))
		for index in range(2):
			var home: int=[subject,1][index]
			var previous:=PrincePolitics.person(state,home,kings[index])
			check(not previous.is_empty() and bool(previous.get("alive",true)),"externally funded ruler survives the overlord cohort cycle=%d home=%d person=%d" % [cycle,home,kings[index]])
			check(PrincePolitics.accede(state,home),"the fief advances its own actual dynasty")
			var incumbent:=PrincePolitics.person(state,home,state.nations[home].ruler_person_id)
			check(RoyalTitles.effective_rank(state,incumbent)==(3 if home==subject else 2),"lawful landed heirs retain the proper clan rank")
		check(Audit.inspect(state).is_empty(),"independent stipend and cohort audit in cycle "+str(cycle))
		check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"multi-court snapshot remains valid in cycle "+str(cycle))

func test_extinct_fief() -> void:
	var state:=fixture(); var subject:=enfeoff(state,0)
	if subject<0: check(false,"extinction fixture creates a real fief"); return
	var affected: Array[Dictionary]=[]
	for tree in state.family_trees.values():
		for member in tree.members.values():
			if int(member.get("title_payer_id",-1))==subject and int(member.get("title_rank",0))>0: affected.append(member)
	var operations: Array[Dictionary]=[]
	for city in state.land_cities_of(subject):
		operations.append({"city_id":city.id,"controller_id":1,"legal_owner_id":1,"sponsor_id":-1,"stock_policy":GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,"reason":"fief_extinction"})
	state.day=30
	check(state.apply_territory_transaction(operations).ok,"actual territory transaction removes every fief city without household annexation")
	check(not state.nations[subject].alive and state.nations[subject].absorbed_into_nation_id<0 and state.nations[0].alive,"the court is extinct while its original issuer remains alive")
	RoyalTitles.reconcile(state)
	for member in affected:
		check(int(member.title_rank)==0 and member.title_history.back().end_reason=="institution_extinct","extinct fief closes each actual open grant")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"a vanished fief cannot leave invalid active peerage in the snapshot")
