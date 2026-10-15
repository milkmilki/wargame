extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("ENVIRONMENT_NATIONS_FAIL ",message)
func run():
	var source := "res://scripts/core/nation_environment.gd"
	check(ResourceLoader.exists(source), "environment classifier is available")
	if not ResourceLoader.exists(source): quit(1); return
	var rules = load(source)
	for row in [{"biome":8,"elevation":1499.0,"expected":"nomad"}, {"biome":8,"elevation":1500.0,"expected":"highland"}, {"elevation":1300.0,"expected":"farm"}, {"elevation":1300.1,"expected":"highland"}, {"lake":true,"expected":"lake"}, {"coast":true,"sea_roll":0.0,"expected":"sea"}, {"major_river":true,"expected":"river"}, {"biome":5,"expected":"forest"}, {"biome":9,"expected":"farm"}]:
		check(rules.classify(row) == row.expected, "ordered classification: "+str(row))
	for row in [{"biome":8,"lake":true,"coast":true,"expected":"nomad"},{"elevation":1400.,"lake":true,"expected":"highland"},{"lake":true,"major_river":true,"expected":"lake"},{"coast":true,"harbor":true,"sea_roll":0.349999,"expected":"sea"},{"coast":true,"harbor":true,"sea_roll":0.35,"expected":"farm"},{"coast":true,"island":true,"sea_roll":0.399999,"expected":"sea"},{"coast":true,"island":true,"sea_roll":0.4,"expected":"farm"},{"coast":true,"sea_roll":0.079999,"expected":"sea"},{"coast":true,"sea_roll":0.08,"expected":"farm"},{"biome":5,"coast_distance":3,"expected":"farm"}]:
		check(rules.classify(row) == row.expected,"priority and exact boundary: "+str(row))
	test_mesh()
	test_pools()
	test_titles()
	test_affinity()
	print("ENVIRONMENT_NATIONS checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func test_mesh():
	var count := 7
	var starts := PackedInt32Array([0]); var adjacency := PackedInt32Array()
	for cell in range(count):
		if cell>0: adjacency.append(cell-1)
		if cell<count-1: adjacency.append(cell+1)
		starts.append(adjacency.size())
	var zeros := PackedFloat32Array(); zeros.resize(count)
	var areas := zeros.duplicate(); areas.fill(1.)
	var agriculture := zeros.duplicate(); agriculture.fill(55.)
	var data := {"seed":1,"mesh":{"n":count,"adj_start":starts,"adj":adjacency,"areas":areas},
		"environment":{"water":PackedByteArray([0,2,2,2,2,2,0]),"flux":zeros.duplicate(),"riverThreshold":1.,"suitability":areas,"agricultural_potential":agriculture},
		"regions":{"landmass":PackedInt32Array([0]),"biome":PackedByteArray([9]),"elevation":PackedFloat32Array([0]),"cellStart":PackedInt32Array([0,count]),"cells":PackedInt32Array([0,1,2,3,4,5,6])}}
	var hierarchy := {"cities":[{"role":"zhou","region":0,"cell":0}]}
	var initial := hash(data)
	var result := NationEnvironment.prepare(data,hierarchy)
	check(result.profiles[0].kind=="lake", "five connected water cells form a large lake")
	check(is_equal_approx(result.profiles[0].affinities.farm,0.5), "agricultural potential is normalized from the existing 0–110 scale")
	check(hash(data)==initial,"classification leaves cached geographic inputs immutable")
	check(result==NationEnvironment.prepare(data,hierarchy),"classification is deterministic")
	data.environment.water[5]=0
	check(NationEnvironment.prepare(data,hierarchy).profiles[0].kind=="farm","four connected lake cells are not a large lake")
	data.environment.flux[0]=5.999
	check(not NationEnvironment.prepare(data,hierarchy).profiles[0].major_river,"river just below six times threshold is minor")
	data.environment.flux[0]=6.
	check(NationEnvironment.prepare(data,hierarchy).profiles[0].kind=="river","seat on a major river is river type")
	data.environment.flux[0]=0.; data.environment.water[1]=0; data.environment.flux[1]=6.
	check(NationEnvironment.prepare(data,hierarchy).profiles[0].kind=="river","seat adjacent to a major river is river type")

func test_pools():
	var roots := {}; var font: Font = load("res://assets/atlas/lxgw-wenkai-gb-500.ttf")
	for kind in NationEnvironment.KINDS:
		var pool: Dictionary = RegionalNames.data().pools[kind]
		check(str(pool.preferred).length()>=128,"128 preferred roots: "+kind)
		check((str(pool.preferred)+str(pool.extension)).length()==1024,"1024 total roots: "+kind)
		for character in str(pool.preferred)+str(pool.extension):
			check(not roots.has(character),"root belongs to a single regional pool: "+character)
			check(font.has_char(character.unicode_at(0)),"same Medium font covers root: "+character)
			roots[character]=kind
		for ending in pool.endings: check(font.has_char(str(ending).unicode_at(0)),"font covers suffix: "+str(ending))
	check(roots.size()==7168,"seven disjoint pools")
	var profiles := {}
	for index in range(1024): profiles[index]={"kind":"farm"}
	check(RegionalNames.capacity_error(profiles).is_empty(),"exact capacity succeeds")
	profiles[1024]={"kind":"farm"}
	check(not RegionalNames.capacity_error(profiles).is_empty(),"overflow gives a clear error")

func test_titles():
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(73001)
	var nation: Nation = state.nations[0]; nation.name="秦"; nation.short_name="秦"; nation.name_kind=WorldNaming.KIND_WARRING_STATE
	for kind in NationEnvironment.KINDS:
		nation.environment_kind=kind; nation.state_level=0
		check(state.nation_display_name(0)==("秦部" if kind=="nomad" else "秦国"),"low formal title: "+kind)
		check(FamilyTree.title_for_nation(state,0)=="秦君","environment does not change personal ruler title")
		nation.state_level=1
		check(state.nation_display_name(0)==("秦汗" if kind=="nomad" else "秦"),"high formal title: "+kind)
		check(FamilyTree.title_for_nation(state,0)=="秦帝","environment does not change imperial personal title")
		check(WorldNaming.nation_display_name(state,0,true)=="秦" and nation.name=="秦", "map and persistent root remain fixed")
	nation.environment_kind="nomad"; nation.state_level=0
	var history := PoliticalHistory.new(); history.reset(state)
	var before := state.nation_display_name(0)
	ChronicleRules.record_ultimatum(state,0,1,0)
	var event_index := state.chronicle_events.size()-1
	var event_text: String = state.chronicle_events.back().text
	state.region_ids.fill(-1)
	var land := state.land_cities_of(0)
	state.region_ids[land[0].id]=10
	EmpireStatus.reconcile(state)
	check(nation.state_level==1 and state.nation_display_name(0)=="秦汗","nomad uses the real one-region recognition path")
	var events := state.chronicle_events.size(); EmpireStatus.reconcile(state)
	check(state.chronicle_events.size()==events,"repeated recognition records once")
	check(state.chronicle_events[event_index].text==event_text and state.chronicle_events[event_index].actor_name==before,"old event preserves its occurrence-time title")
	var historical := history.build_view_state(state,0)
	check(historical.nations[0].environment_kind=="nomad" and historical.nation_display_name(0)=="秦部","history preserves environment and pre-upgrade title")
	var snapshot := NativeSnapshotBuilder.build(state)
	check(snapshot.schema_version==31 and snapshot.nations.environment_kind[0]=="nomad","v31 retains environment")
	check(NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(),"new runtime snapshot validates")
	snapshot.schema_version=29
	check(not NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(),"v29 runtime snapshot is explicitly rejected")
	snapshot.schema_version=31; snapshot.nations.environment_kind[0]="invalid"
	check(not NativeSnapshotBuilder.succession_validation_error(snapshot).is_empty(),"invalid environment is rejected")
	state.region_ids.fill(-1); EmpireStatus.reconcile(state)
	check(nation.state_level==1,"territory loss cannot downgrade")
	nation.name_kind=WorldNaming.KIND_REBEL; nation.name="李明军"; nation.short_name="李明军"
	check(state.nation_display_name(0)=="李明军","rebel titles never acquire sovereign suffixes")

func test_affinity():
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(91022, false)
	state.region_ids.fill(0); state.region_analysis_revision+=1
	var centers: Array[int] = []
	for city in state.cities:
		state.administrative_center_by_city[city.id]=city.id
		if not city.is_dock: centers.append(city.id)
	state.administrative_center_city_ids=PackedInt32Array(centers); state.administrative_region_revision+=1
	var profiles := {}
	for center in centers: profiles[center]={"kind":"farm","area":1.,"affinities":{"farm":0.,"nomad":0.,"sea":0.,"highland":0.,"river":0.,"lake":0.,"forest":0.}}
	state.atlas_layout={"settlement_adjacency":state.adjacency,"nation_environment":{"version":NationEnvironment.VERSION,"profiles":profiles}}
	# Atlas route previews require road jurisdictions as well as adjacency.
	for edge in state.edges:
		edge.control_city_id=edge.city_b if state.cities[edge.city_b].owner_nation==1 else edge.city_a
	state.armies.clear()
	for city in state.cities_of(1):
		city.gold_per_month=10; city.food_per_half_year=100; city.manpower_per_month=10
		city.is_capital=false; city.has_warehouse=false; city.is_food_hub=false; city.is_manpower_hub=false; city.garrison_manpower=0
	var rng_state := state.rng.state
	var base := DiplomacyAI.select_war_objective(state,0,1)
	check(not base.is_empty(),"fixture has legal reachable objectives")
	if base.is_empty(): return
	var candidates: Array[int] = []
	for city in state.cities_of(1):
		var excluded := {}
		for center in centers:
			if center!=city.id: excluded[center]=true
		var single := DiplomacyAI.select_war_objective(state,0,1,{},-1,false,excluded)
		if not single.is_empty() and int(single.city_id)!=int(base.city_id) and absf(float(single.value)-float(base.value))<2.: candidates.append(int(single.city_id))
	check(not candidates.is_empty(),"equally legal alternatives fall within the preference bonus")
	if candidates.is_empty(): return
	var preferred := candidates[0]; profiles[preferred].affinities.nomad=1.
	state.nations[0].environment_kind="nomad"
	var cache := {}
	var selected := DiplomacyAI._cached_war_objective(state,0,1,cache)
	check(selected.city_id==preferred,"nomad land affinity changes new objective choice")
	check(is_equal_approx(selected.selection_score,selected.value+2.),"preference is a separate selection score")
	state.nations[0].environment_kind="farm"
	var neutral := DiplomacyAI._cached_war_objective(state,0,1,cache)
	check(neutral.city_id==base.city_id,"cached objective includes requesting environment")
	check(is_equal_approx(neutral.value,base.value),"base economic/strategic valuation remains unchanged")
	check(state.rng.state==rng_state,"land scoring never consumes randomness")
	profiles[preferred].area=3.
	check(is_equal_approx(NationEnvironment.region_affinity(state,0,0),0.),"region cache does not mix country types")
	state.nations[0].environment_kind="nomad"
	check(is_equal_approx(NationEnvironment.region_affinity(state,0,0),3./(centers.size()+2.)),"regional affinity counts state land area once")
