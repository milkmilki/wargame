extends SceneTree
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("NOMAD_NAMES_FAIL ",message)
func run():
	check(RegionalNames.data().has("nomad_names"),"nomadic transliteration vocabulary exists")
	if not RegionalNames.data().has("nomad_names"): quit(1); return
	var vocabulary: Dictionary=RegionalNames.data().nomad_names
	var seen := {}; var font: Font=load("res://assets/atlas/lxgw-wenkai-gb-500.ttf")
	check(vocabulary.preferred.size()>=128 and vocabulary.preferred.size()+vocabulary.extension.size()==1024 and vocabulary.towns.size()==1024,"nomadic seats and prefectures have independent complete pools")
	for phase in ["preferred","extension","towns"]:
		for name in vocabulary[phase]:
			check(not seen.has(name),"nomadic names are unique across the two pools")
			seen[name]=true
			for character in str(name): check(font.has_char(character.unicode_at(0)),"font covers nomadic names")
	check(vocabulary.preferred.has("桂由") and vocabulary.preferred.has("拖雷"),"requested names are available")
	var profiles := {}
	for id in range(1025): profiles[id]={"kind":"nomad"}
	check(not RegionalNames.capacity_error(profiles).is_empty(),"nomadic seat capacity is checked against whole-name vocabulary")
	var towns: Array=[]; var centers := PackedInt32Array()
	for _id in range(1025): towns.append({"role":"fu"}); centers.append(0)
	check(not RegionalNames.capacity_error({0:{"kind":"nomad"}},{"cities":towns,"center_by_city":centers}).is_empty(),"nomadic prefecture overflow fails before world installation")
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(2)
	state.atlas_layout={"nation_environment":{"profiles":{0:{"kind":"nomad"}}}}
	state.administrative_center_by_city[0]=0
	state.cities[0].name=""; state.cities[0].short_name=""
	state.nations[0].capital_city_id=0; state.nations[0].founding_city_id=0; state.nations[0].environment_kind="nomad"
	var rng := state.rng.state
	WorldNaming.assign_initial_names(state,state.world_seed)
	var name := state.cities[0].name
	check(vocabulary.preferred.has(name) and name==state.cities[0].short_name,"nomadic seat full name equals its complete transliteration short name")
	check(WorldNaming.city_short_name(state,0)==name and state.nations[0].name==name,"founding country inherits the entire nomadic name")
	check(state.nation_display_name(0)==name+"部","low nomadic title uses full root")
	state.nations[0].state_level=1
	check(state.nation_display_name(0)==name+"汗","high nomadic title uses full root")
	check(FamilyTree.title_for_nation(state,0)==name+"帝","personal title still uses the fixed root")
	WorldNaming.assign_initial_names(state,state.world_seed)
	check(state.cities[0].name==name and state.cities[0].short_name==name and state.rng.state==rng,"nomadic naming is stable and RNG independent")
	print("NOMAD_NAMES checks=",checks," failures=",failures)
	quit(1 if failures else 0)
