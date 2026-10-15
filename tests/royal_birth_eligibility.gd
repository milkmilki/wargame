extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("ROYAL_BIRTH_FAIL ",message)
func _initialize() -> void:
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(73003)
	var nation := state.nations[0]
	nation.state_level=EmpireStatus.EMPIRE; nation.royal_titles_initialized=true
	var members: Dictionary=FamilyTree.tree_for_nation(state,0).members
	var untitled := PrincePolitics._create_person(state,0,nation.ruler_person_id,100)
	RoyalTitles._grant(state,members[untitled],RoyalTitles.COMMON,0,untitled,true)
	var before := state.next_family_person_id
	var revision := state.family_revision
	var rng := state.rng.state
	check(PrincePolitics.initialize_children(state,0,untitled).is_empty(),"an untitled adult cannot produce children through the shared birth entry")
	check(state.next_family_person_id==before and state.family_revision==revision,"a blocked birth cannot add people or mutate the family")
	check(not members[untitled].children_initialized,"being untitled cannot consume a later titled birth opportunity")
	RoyalTitles._generate_children(state,members[untitled])
	check(not bool(members[untitled].get("title_children_generated",false)),"the title coordinator cannot mark an untitled family as reproduced")
	RoyalTitles._grant(state,members[untitled],RoyalTitles.PRINCE,0,untitled,true)
	RoyalTitles._generate_children(state,members[untitled])
	check(members[untitled].children_initialized and members[untitled].title_children_generated,"receiving a real title enables the normal one-time birth result")
	var children := RoyalTitles.children(members,untitled)
	before=state.next_family_person_id
	for repeat in range(3): RoyalTitles._generate_children(state,members[untitled])
	check(state.next_family_person_id==before and RoyalTitles.children(members,untitled)==children,"a zero or nonzero birth result is never rerolled")
	var waiting := PrincePolitics._create_person(state,0,untitled,100)
	RoyalTitles._grant(state,members[waiting],RoyalTitles.COMMANDERY,0,untitled,false)
	check(PrincePolitics.initialize_children(state,0,waiting).is_empty() and not members[waiting].children_initialized,"a titled waiting-generation child does not start another family early")
	var old_children := RoyalTitles.children(members,untitled)
	RoyalTitles.end_title(state,members[untitled],"retitled")
	check(PrincePolitics.initialize_children(state,0,untitled)==old_children,"losing a title preserves existing descendants without new births")
	check(state.rng.state==rng,"birth eligibility and title grants do not consume the simulation random stream")
	# Ordinary rulers and landed princes carry an office, not a virtual title.
	var ordinary := GameState.new(); ordinary.world_seed=42
	var ruler := Nation.new(); ruler.id=0; ruler.name="晋"; ruler.ruler_name="赵甲"; ordinary.nations.append(ruler)
	FamilyTree.ensure_nation_lineage(ordinary,0)
	PrincePolitics.ensure_generation(ordinary,0)
	var current := PrincePolitics.person(ordinary,0,ruler.ruler_person_id)
	check(current.children_initialized,"an ordinary country's actual ruler still produces a normal inheritance family")
	check(not ruler.royal_titles_initialized,"generating the ruler's heirs cannot create an imperial title institution")
	print("ROYAL_BIRTH_ELIGIBILITY checks=",checks," failures=",failures); quit(1 if failures else 0)
