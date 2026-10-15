extends SceneTree
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")
const TitleAudit = preload("res://tests/royal_title_audit.gd")
const FamilyModel = preload("res://scripts/atlas/family_model.gd")
const FamilyPanel = preload("res://scripts/atlas/family_panel.gd")
class Host extends RefCounted:
	var state: GameState
	var simulation: Simulation
	var historical_view := false
	func information_source() -> GameState: return state
	func show_information(_kind: String,_id: int) -> void: pass
var failures := 0
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FOREIGN_RECALL_FAIL ",message)
func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(73003,false)
	state.region_ids.fill(-1)
	for nation in state.nations:
		for other in state.nations:
			if nation.id<other.id: state.set_diplomatic_relation(nation.id,other.id,GameState.DiplomaticRelation.NEUTRAL)
		FamilyFixture.ensure_candidates(state,nation.id,3)
	return state
func _initialize() -> void: call_deferred("run")
func run() -> void:
	test_foreign_household()
	test_separate_branches()
	test_early_collateral()
	await test_family_navigation()
	print("ROYAL_FOREIGN_RECALL checks=",checks," failures=",failures); quit(1 if failures else 0)
func test_foreign_household() -> void:
	var state := fixture()
	var foreign := state.nations[1]; var king := foreign.ruler_person_id
	var tree_id := foreign.family_tree_id; var tree: Dictionary=state.family_trees[tree_id]
	var members: Dictionary=tree.members; var surname := FamilyTree.surname_for_nation(state,1)
	var children := RoyalTitles.children(members,king)
	var original_blood := {}
	for id in members: original_blood[id]=members[id].parent_id
	check(state.accept_submission(1,2) and state.accept_submission(0,1),"real foreign submission supports a lower independent household")
	var lower_before: Dictionary=state.family_trees[state.nations[2].family_tree_id].duplicate(true)
	var history := PoliticalHistory.new(); history.reset(state)
	var gold := state.nations[0].treasury_gold+foreign.treasury_gold
	var rng := state.rng.state; state.day=30
	check(state.revoke_vassal(1),"foreign overlord relationship is peacefully revoked through the real territory transaction")
	check(foreign.family_tree_id==tree_id and state.nations[0].family_tree_id!=tree_id,"foreign genealogy stays independent after recall")
	check(state.nations[0].treasury_gold==gold and foreign.treasury_gold==0,"treasury transfers exactly once")
	check(state.nations[2].alive and state.overlord_of(2)==0,"lower foreign fief reparents and remains alive")
	for id in lower_before.members:
		var actual: Dictionary=state.family_trees[state.nations[2].family_tree_id].members[id]
		for key in ["id","parent_id","name","title_payer_id","title_generation_nation_id"]:
			check(actual.get(key)==lower_before.members[id].get(key),"lower fief retains bloodline and generation: "+key)
	for id in original_blood: check(members[id].parent_id==original_blood[id],"original foreign ancestry is preserved")
	check(RoyalTitles.effective_rank(state,members[king])==RoyalTitles.COMMANDERY,"foreign recalled king receives an active commandery title")
	if RoyalTitles.effective_rank(state,members[king])!=RoyalTitles.COMMANDERY: return
	for child in children:
		check(RoyalTitles.effective_rank(state,members[child])==RoyalTitles.DUKE and int(members[child].title_branch_id)==king,"foreign children join their own descending-rank branch")
	check(RoyalTitles.report(state,0).counts[2]==2 and RoyalTitles.report(state,1).basis_points==0 and RoyalTitles.report(state,2).basis_points==0,"the receiving overlord pays both recalled and reparented commandery households once")
	check(TitleAudit.inspect(state).is_empty(),"foreign title census and domestic branch references are consistent")
	var after := state.family_trees.duplicate(true)
	check(not state.revoke_vassal(1) and state.family_trees==after,"a repeated recall cannot duplicate foreign grants or descendants")
	check(state.rng.state==rng,"foreign recall does not consume simulation randomness")
	var snapshot := NativeSnapshotBuilder.build(state)
	check(NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(),"snapshot accepts legitimate foreign household grants")
	for field in ["title_origin_nation_id","title_branch_id","title_rank"]:
		var invalid := snapshot.duplicate(true)
		for family in invalid.family_trees:
			if family.id!=tree_id: continue
			for record in family.members:
				if record.id==king: record[field]=1 if field=="title_origin_nation_id" else state.nations[0].ruler_person_id if field=="title_branch_id" else RoyalTitles.PRINCE
		check(not NativeSnapshotBuilder.succession_validation_error(invalid).is_empty(),"snapshot still rejects foreign title corruption: "+field)
	history.maybe_capture(state)
	var past := history.build_view_state(state,0)
	check(past.nations[1].alive and int(past.family_trees[tree_id].members[king].get("title_rank",0))==2 and int(past.family_trees[tree_id].members[king].enfeoffed_nation_id)==1,"pre-recall history retains landed commandery rank")
	var current := history.build_view_state(state,1)
	check(current.family_trees[tree_id].members[king].title_rank==RoyalTitles.COMMANDERY,"post-recall history retains the new foreign grant")
	var model := FamilyModel.capture(state,1)
	check(model.tree_id==tree_id and model.members[king].display_title==members[king].current_title,"foreign family presentation exposes the actual new title")
	check(int(model.members[king].get("archetype",-1))==foreign.ruler_archetype and model.members[king].get("traits",[])==foreign.ruler_traits,"recalled former ruler retains his known type and traits after leaving office")
	var title: String=members[king].current_title
	check(PrincePolitics.accede(state,0),"actual overlord accession advances the foreign household cohort")
	check(not members[king].alive and RoyalTitles.effective_rank(state,members[children[0]])==RoyalTitles.COMMANDERY,"foreign eldest child inherits through the normal title lifecycle")
	check(members[children[0]].current_title==title,"foreign succession preserves its exact princely designation")
	check(not members[king].title_history.back().end_reason.is_empty(),"foreign prince's death closes the old title record")
	check(state.nations[0].ruler_person_id not in members,"foreign nobility cannot become the overlord's royal successor")
	check(members[children[0]].children_initialized,"the foreign title heir receives a normal one-time birth result")
	for child in children:
		for grandchild in RoyalTitles.children(members,child):
			check(members[grandchild].name.begins_with(surname) and not FamilyTree.tree_for_nation(state,0).members.has(grandchild),"new foreign descendants keep their surname and original tree")
	check(TitleAudit.inspect(state).is_empty() and NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"foreign inheritance and births remain valid in the full snapshot")
func test_separate_branches() -> void:
	var state := fixture()
	var heirs := {}; var names := {}; var family_ids := {}
	for subject in [1,2]:
		var members: Dictionary=FamilyTree.tree_for_nation(state,subject).members
		var king := state.nations[subject].ruler_person_id
		heirs[subject]=RoyalTitles.children(members,king)[0]; family_ids[subject]=state.nations[subject].family_tree_id
		check(state.accept_submission(0,subject) and state.revoke_vassal(subject),"each foreign household is actually recalled")
		names[subject]=str(members[king].current_title)
		check(RoyalTitles.effective_rank(state,members[king])==RoyalTitles.COMMANDERY,"each foreign king receives an independent commandery grant")
	if RoyalTitles.report(state,0).counts[2]!=2: return
	check(PrincePolitics.accede(state,0),"one overlord succession settles several foreign households")
	for subject in [1,2]:
		var members: Dictionary=state.family_trees[family_ids[subject]].members
		check(RoyalTitles.effective_rank(state,members[heirs[subject]])==RoyalTitles.COMMANDERY and members[heirs[subject]].current_title==names[subject],"each foreign title stays in its own bloodline and branch")
	check(TitleAudit.inspect(state).is_empty(),"parallel foreign title succession has no duplicate stipends")

func test_early_collateral() -> void:
	var state := fixture()
	var members: Dictionary=FamilyTree.tree_for_nation(state,1).members
	var king := state.nations[1].ruler_person_id
	var children := RoyalTitles.children(members,king)
	check(state.accept_submission(0,1) and state.revoke_vassal(1),"early inheritance fixture recalls a real foreign state")
	if RoyalTitles.effective_rank(state,members[king])!=RoyalTitles.COMMANDERY: return
	var title: String=members[king].current_title
	members[king].alive=false
	RoyalTitles.settle_death(state,0,king)
	check(RoyalTitles.effective_rank(state,members[children[0]])==RoyalTitles.COMMANDERY,"early death settles an external household's direct heir")
	members[children[0]].alive=false
	RoyalTitles.settle_death(state,0,children[0])
	check(RoyalTitles.effective_rank(state,members[children[1]])==RoyalTitles.COMMANDERY and members[children[1]].current_title==title,"childless foreign heir passes the same title to its nearest own collateral")
	check(NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state)).is_empty(),"foreign early-death title history stays snapshot-valid")
	var tree := FamilyTree.tree_for_nation(state,1); var surname := FamilyTree.surname_for_nation(state,1)
	tree.erase("surname")
	var new_person := PrincePolitics._create_person(state,0,int(tree.root_person_id),100)
	check(members[new_person].name.begins_with(surname),"an uncached foreign surname comes from its own genealogy, including unknown ancestors")

func test_family_navigation() -> void:
	root.size=Vector2i(1280,720)
	var host := Host.new(); host.state=fixture()
	check(host.state.accept_submission(0,1) and host.state.revoke_vassal(1),"family navigation uses a real foreign recall")
	var panel := FamilyPanel.new(); panel.host=host; root.add_child(panel)
	panel.open(0); await process_frame; await process_frame
	var before := host.state.family_trees.duplicate(true); var rng := host.state.rng.state
	var foreign_index := -1
	for index in range(panel.selector.item_count):
		if panel.selector.get_item_id(index)==1: foreign_index=index
	check(foreign_index>=0,"overlord family view provides a separate foreign-household entry")
	await capture("court-1280")
	if foreign_index>=0:
		panel.selector.item_selected.emit(foreign_index); await process_frame; await process_frame
		check(panel.nation_id==1 and panel.model.tree_id==host.state.nations[1].family_tree_id,"family selector opens the original foreign genealogy")
		await capture("foreign-1280")
		root.size=Vector2i(900,600); await process_frame; await process_frame
		await capture("foreign-900")
		var own_index := -1
		for index in range(panel.selector.item_count):
			if panel.selector.get_item_id(index)==0: own_index=index
		check(own_index>=0,"external household can return to the paying court's own genealogy")
		if own_index>=0: panel.selector.item_selected.emit(own_index)
	check(host.state.family_trees==before and host.state.rng.state==rng,"switching separate family views cannot mutate titles, births or random state")
	panel.queue_free(); await process_frame; await process_frame

func capture(name_value: String) -> void:
	if "--foreign-recall-capture" not in OS.get_cmdline_user_args(): return
	DirAccess.make_dir_recursive_absolute("res://.dbg/foreign-recall")
	await process_frame; RenderingServer.force_draw(true)
	root.get_texture().get_image().save_png("res://.dbg/foreign-recall/"+name_value+".png")
