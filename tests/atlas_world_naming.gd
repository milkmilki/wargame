extends SceneTree
const Inputs = preload("res://tests/atlas_military_inputs.gd")
const Information = preload("res://scripts/atlas/information_model.gd")
var failures := 0
var checks := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("ATLAS_NAMING_FAIL ",message)
func field(document: Dictionary, label: String) -> String:
	for section in document.get("sections",[]):
		for row in section.rows:
			if row.label == label: return str(row.value)
	return ""
func identity(state: GameState) -> Array:
	return [state.cities.map(func(city): return [city.name,city.short_name]), state.nations.map(func(nation): return [nation.name,nation.short_name,nation.name_kind,nation.founding_city_id])]
func run():
	var payload := Inputs.eurasia_military()
	var before := hash([payload.nations,payload.hierarchy.cities])
	var state := GameState.new(); state.generate_from_atlas(payload)
	var names := {}; var shorts := {}; var historic := 0
	for city in state.land_cities():
		check(not city.name.is_empty() and not names.has(city.name), "settlement full names are assigned and unique")
		names[city.name] = true
		check(not city.name.contains("·府"), "prefectures have their own names instead of numbered state placeholders")
		if WorldNaming.HISTORIC_CITY_NAMES.has(city.name): historic += 1
		if not state.is_zhou_city(city.id): continue
		check(city.short_name.length() == 1 and not shorts.has(city.short_name), "state seats have unique single-character short names")
		shorts[city.short_name] = true
		check(field(Information.city(state,city.id),"简称") == city.short_name, "state seat inspector exposes the persistent short name")
	for city in state.cities:
		if city.is_traffic: check(city.name == "交通点%d"%city.id and city.short_name == String.chr(0x4e00+city.id), "road junctions do not consume city naming identities")
	check(historic > 0, "Atlas imports the existing ancient-style settlement vocabulary")
	for nation in state.nations:
		var capital := state.cities[nation.capital_city_id]
		check(nation.name == capital.short_name and nation.short_name == capital.short_name, "initial country name is its capital's short name")
		check(nation.founding_city_id == capital.id, "country retains its original capital as the stable naming anchor")
	check(hash([payload.nations,payload.hierarchy.cities]) == before, "naming does not mutate the cached geography or generation payload")
	var first := identity(state); var rng := state.rng.state
	WorldNaming.assign_initial_names(state,state.world_seed)
	check(identity(state) == first and state.rng.state == rng, "repeated naming is stable and never advances simulation randomness")
	var duplicate := GameState.new(); duplicate.generate_from_atlas(payload)
	check(identity(duplicate) == first and duplicate.rng.state == rng, "same seed and layout reproduce names and simulation random state")
	test_capital_loss_and_template(state)
	print("ATLAS_WORLD_NAMING checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func test_capital_loss_and_template(state: GameState):
	var actor := -1
	for nation in state.nations:
		if state.land_cities_of(nation.id).filter(func(city): return state.is_zhou_city(city.id)).size() >= 2: actor = nation.id; break
	check(actor >= 0, "fixture supports a real capital loss without extinction")
	if actor < 0: return
	var opponent := (actor+1)%state.nations.size()
	var nation: Nation = state.nations[actor]
	var old_capital := nation.capital_city_id; var old_name := nation.name
	state.set_diplomatic_relation(actor,opponent,GameState.DiplomaticRelation.WAR)
	var changed := state.apply_territory_transaction([{"city_id":old_capital,"controller_id":opponent,"legal_owner_id":actor,"sponsor_id":opponent,"reason":"naming_capital_loss"}] as Array[Dictionary])
	check(changed.get("ok",false) and nation.capital_city_id != old_capital, "real occupation relocates the losing country's capital")
	check(nation.name == old_name and nation.founding_city_id == old_capital, "capital loss preserves country name and founding anchor")
	check(field(Information.nation(state,actor),"国号来源") == state.cities[old_capital].name, "country inspector identifies its original naming seat")
	var definition := MapDefinition.from_state(state)
	var error := MapDefinition.validate(definition)
	check(error.is_empty(), "named map template validates: "+error)
	if not error.is_empty(): return
	var restored := GameState.new(); restored.generate_from_map_definition(definition)
	check(identity(restored) == identity(state), "map template preserves full names, short names and founding references after migration")
	if identity(restored) != identity(state):
		for id in range(state.cities.size()):
			if [state.cities[id].name,state.cities[id].short_name] != [restored.cities[id].name,restored.cities[id].short_name]:
				printerr("NAMING_TEMPLATE_CITY_DIFFERENCE id=",id," traffic=",state.cities[id].is_traffic," source=",[state.cities[id].name,state.cities[id].short_name]," restored=",[restored.cities[id].name,restored.cities[id].short_name]); break
	var history := PoliticalHistory.new(); history.reset(restored)
	var view := history.build_view_state(restored,0)
	check(identity(view) == identity(restored), "historical view preserves naming without allocating new identities")
	test_template_naming_fields(definition,state)
func test_template_naming_fields(definition: Dictionary, state: GameState):
	var template := preload("res://scripts/atlas/military_template.gd")
	var payload := template.decode(definition)
	for change in [{"field":"short_name","value":12},{"field":"name_kind","value":"unknown"},{"field":"founding_city_id","value":payload.hierarchy.cities.size()}]:
		var saved: Variant = payload.nations[0][change.field]
		payload.nations[0][change.field] = change.value
		var invalid := definition.duplicate(); invalid.atlas_payload = Marshalls.raw_to_base64(var_to_bytes(payload))
		check(not template.validate(invalid).is_empty(), "invalid naming metadata is rejected before world replacement: "+str(change.field))
		payload.nations[0][change.field] = saved
	for nation in payload.nations:
		for key in ["short_name","name_kind","founding_city_id"]: nation.erase(key)
	var legacy := definition.duplicate(); legacy.atlas_payload = Marshalls.raw_to_base64(var_to_bytes(payload))
	check(template.validate(legacy).is_empty(), "existing version-9 templates can omit the optional naming metadata")
	var restored := GameState.new(); restored.generate_from_map_definition(legacy)
	check(restored.nations.map(func(nation): return nation.name) == state.nations.map(func(nation): return nation.name), "legacy custom country names are preserved")
	check(restored.land_cities().map(func(city): return [city.name,city.short_name]) == state.land_cities().map(func(city): return [city.name,city.short_name]), "legacy explicit city names and short names are preserved")
	var kind := state.nations[0].name_kind; state.nations[0].name_kind = WorldNaming.KIND_REBEL
	var rebuilt := template.decode(template.encode(state))
	check(rebuilt.nations[0].name_kind == WorldNaming.KIND_WARRING_STATE, "new-game templates do not import runtime rebellion roles as naming types")
	state.nations[0].name_kind = kind
