extends SceneTree
const Inputs = preload("res://tests/atlas_military_inputs.gd")
const Information = preload("res://scripts/atlas/information_model.gd")
const Template = preload("res://scripts/atlas/military_template.gd")
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok: failures+=1; printerr("ENVIRONMENT_ATLAS_FAIL ",message)
func signature(state: GameState) -> Array:
	return [state.cities.map(func(c):return [c.name,c.short_name]),state.nations.map(func(n):return [n.name,n.short_name,n.environment_kind,n.founding_city_id])]
func run():
	var payload := Inputs.eurasia_military()
	var payload_hash := hash(payload)
	var state := GameState.new()
	var started := Time.get_ticks_usec()
	check(state.generate_from_atlas(payload).ok,"real Eurasia world installs")
	var install_usec := Time.get_ticks_usec()-started
	var roots := {}; var counts := {}
	var profiles: Dictionary = state.atlas_layout.nation_environment.profiles
	for city in state.land_cities():
		if not state.is_zhou_city(city.id):
			check(not RegionalNames.reserved(city.short_name),"prefecture short does not consume state pool")
			continue
		var kind: String = profiles[city.id].kind
		var pool: Dictionary = RegionalNames.data().pools[kind]
		check((str(pool.preferred)+str(pool.extension)).contains(city.short_name),"root stays inside its environment pool")
		check(not roots.has(city.short_name) and city.name.contains(city.short_name),"paired unique short and full names")
		roots[city.short_name]=true; counts[kind]=int(counts.get(kind,0))+1
	for nation in state.nations:
		var city: City = state.cities[nation.founding_city_id]
		check(nation.environment_kind==profiles[city.id].kind,"nation takes founding environment")
		check(nation.name==city.short_name and nation.name==nation.short_name,"country persists founding root")
		check(str(RegionalNames.data().pools[nation.environment_kind].preferred).contains(nation.name),"capitals receive preferred characters first")
		check(Information.nation(state,nation.id).title==state.nation_display_name(nation.id),"country inspector uses formal title")
	check(hash(payload)==payload_hash,"install does not mutate cached payload")
	var duplicate := GameState.new(); duplicate.generate_from_atlas(payload)
	check(var_to_bytes(NativeSnapshotBuilder.build(state))==var_to_bytes(NativeSnapshotBuilder.build(duplicate)) and state.generation_metadata==duplicate.generation_metadata,"same input preserves complete authoritative snapshot and deterministic metadata")
	var rng_state := state.rng.state; var identity := signature(state)
	WorldNaming.assign_initial_names(state,state.world_seed)
	check(signature(state)==identity and state.rng.state==rng_state,"names are stable and RNG independent")
	var definition := MapDefinition.from_state(state)
	check(MapDefinition.validate(definition).is_empty(),"new version-9 template validates")
	var restored := GameState.new(); restored.generate_from_map_definition(definition)
	check(signature(restored)==identity,"types and paired names survive template roundtrip")
	var legacy := Template.decode(definition)
	for nation in legacy.nations: nation.erase("environment_kind")
	legacy.erase("nation_environment")
	var legacy_definition := definition.duplicate(); legacy_definition.atlas_payload=Marshalls.raw_to_base64(var_to_bytes(legacy))
	check(Template.validate(legacy_definition).is_empty(),"old v9 template without environment metadata validates")
	restored.generate_from_map_definition(legacy_definition)
	check(signature(restored)==identity,"old explicit names preserved and type derived from founding city")
	legacy.nations[0].environment_kind="invalid"
	legacy_definition.atlas_payload=Marshalls.raw_to_base64(var_to_bytes(legacy))
	check(not Template.validate(legacy_definition).is_empty(),"invalid optional environment is rejected")
	for field in ["flux","riverThreshold"]:
		var malformed := Template.decode(definition)
		malformed.data.environment.erase(field)
		var invalid := definition.duplicate(); invalid.atlas_payload=Marshalls.raw_to_base64(var_to_bytes(malformed))
		check(not Template.validate(invalid).is_empty(),"missing founding-geography input is rejected before reconstruction: "+field)
	# Force capacity overflow before install, retaining all live references and RNG.
	var overflow := payload.duplicate(); var fake := {}
	for id in range(1025): fake[id]={"kind":"farm"}
	overflow.nation_environment={"version":NationEnvironment.VERSION,"profiles":fake}
	var old_city: City = state.cities[0]; var old_nation: Nation=state.nations[0]
	var rejected := state.generate_from_atlas(overflow)
	check(not rejected.ok and str(rejected.error).contains("1025"),"capacity overflow fails explicitly")
	check(state.cities[0]==old_city and state.nations[0]==old_nation and signature(state)==identity and state.rng.state==rng_state,"overflow retains complete old world and its references")
	var global_payload := Inputs.military()
	started=Time.get_ticks_usec()
	var global_profiles := NationEnvironment.prepare(global_payload.data,global_payload.hierarchy)
	var global_usec := Time.get_ticks_usec()-started
	check(RegionalNames.capacity_error(global_profiles.profiles).is_empty(),"global map satisfies all seven capacities")
	print("ENVIRONMENT_ATLAS checks=",checks," failures=",failures," eurasia_counts=",counts," install_ms=",install_usec/1000.," naming_ms=",float(state.get_meta("atlas_naming_usec",0))/1000.," global_classification_ms=",global_usec/1000.," global_states=",global_profiles.profiles.size())
	quit(1 if failures else 0)
