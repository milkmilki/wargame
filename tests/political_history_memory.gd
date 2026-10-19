extends SceneTree
## Monthly history must retain facts, not duplicate every unchanged ancestor.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("HISTORY_MEMORY_FAIL ",label)

func run() -> void:
	var state := preload("res://tests/succession_chain.gd").fixture()
	var sim := Simulation.new(); sim.setup(state)
	var tree_id := state.nations[0].family_tree_id
	var tree: Dictionary = state.family_trees[tree_id]
	var template: Dictionary = tree.members[state.nations[0].ruler_person_id]
	for id in range(10000,11200):
		var person: Dictionary = template.duplicate(true)
		person.id=id; person.name="先人%d"%id; person.alive=false
		person.traits=(person.get("traits",[]) as Array).duplicate()
		tree.members[id]=person
	state.next_family_person_id=11200
	ChronicleRules.begin_war(state,777,[0],[])
	var rng_before := state.rng.state
	var history := PoliticalHistory.new(); history.reset(state)
	var first: Dictionary = history._snapshots[0]
	var memory_before := OS.get_static_memory_usage()
	for month in range(1,61):
		state.day=month*30; history.maybe_capture(state)
	var memory_growth := OS.get_static_memory_usage()-memory_before
	check(history.snapshot_count()==61,"all monthly dates remain available")
	check(memory_growth<16*1024*1024,"sixty unchanged 1200-person histories stay below 16 MiB extra memory")
	check(is_same(first.family_trees[tree_id],history._snapshots.back().family_trees[tree_id]),"an unchanged family shares its frozen history record")
	if memory_growth>=16*1024*1024:
		# Fail before the longer workload can exhaust the test host if the
		# original full-copy implementation is accidentally reintroduced.
		print("POLITICAL_HISTORY_MEMORY checks=",checks," failures=",failures.size()," growth_bytes=",memory_growth)
		sim.free(); quit(1); return
	var old_name: String=first.family_trees[tree_id].members[10000].name
	tree.members[10000].name="后续改名"
	tree.members[10000].traits.append(RulerProfile.TRAIT_HARSH)
	state.day+=30; history.maybe_capture(state)
	var latest: Dictionary=history._snapshots.back().family_trees[tree_id]
	check(first.family_trees[tree_id].members[10000].name==old_name,"live nested edits cannot rewrite an earlier ancestor")
	check(not first.family_trees[tree_id].members[10000].traits.has(RulerProfile.TRAIT_HARSH),"nested arrays stay isolated from the live family")
	check(latest.members[10000].name=="后续改名","a changed person is recorded at the new date without relying on revision counters")
	check(is_same(first.family_trees[tree_id].members[10001],latest.members[10001]),"changing one person does not duplicate unrelated ancestors")
	ChronicleRules.record_casualties(state,777,0,12)
	state.day+=30; history.maybe_capture(state)
	var context: Dictionary=history._snapshots.back().war_chronicle_contexts[777]
	check(first.war_chronicle_contexts[777].casualties_by_nation.is_empty() and context.casualties_by_nation[0]==12,"later casualties cannot rewrite historical war records")
	check(is_same(context.baseline_owners,first.war_chronicle_contexts[777].baseline_owners),"changing casualties reuses unchanged territorial baselines")
	state.region_ids[0]=3
	check(first.region_ids[0]==0,"packed region arrays retain copy-on-write isolation")
	var view:=history.build_view_state(state,0)
	view.family_trees[tree_id].members[10001].name="查看端改名"
	check(first.family_trees[tree_id].members[10001].name!="查看端改名" and tree.members[10001].name!="查看端改名","the mutable detached view cannot alter a shared snapshot or live data")
	var changing_before:=OS.get_static_memory_usage()
	for month in range(63,783):
		state.day=month*30
		sim.set_ruler_profile(0,RulerProfile.GUARDIAN if month%2 else RulerProfile.CONQUEROR,[])
		history.maybe_capture(state)
		if OS.get_static_memory_usage()-changing_before>=128*1024*1024: break
	var changing_growth:=OS.get_static_memory_usage()-changing_before
	check(history.snapshot_count()==783,"changing monthly history retains more than sixty years of dates")
	check(changing_growth<128*1024*1024,"720 changed ruler records do not duplicate 1200 unchanged ancestors")
	check(is_same(first.family_trees[tree_id].members[10001],history._snapshots.back().family_trees[tree_id].members[10001]),"old ancestor records remain shared across changed generations")
	check(state.rng.state==rng_before,"snapshot sharing consumes no random draws")
	print("POLITICAL_HISTORY_MEMORY checks=",checks," failures=",failures.size()," growth_bytes=",memory_growth," changing_growth_bytes=",changing_growth)
	sim.free(); quit(1 if not failures.is_empty() else 0)
