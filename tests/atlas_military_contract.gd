extends SceneTree
const Map = preload("res://scripts/atlas/military_map.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_MILITARY_FAIL ",message)
func _initialize() -> void:
	var importer = load("res://scripts/atlas/military_import.gd")
	if importer==null: print("ATLAS_MILITARY_FAIL missing importer"); quit(1); return
	var base: Dictionary = preload("res://tests/atlas_military_inputs.gd").base()
	var payload := Map.prepare(base)
	var state := GameState.new(); state.generate_from_atlas(payload)
	check(state.land_cities().size()==payload.hierarchy.cities.size(),"traffic excluded from cities")
	check(state.nations.size()==40,"forty populated nations")
	for nation in state.nations:
		check(state.is_zhou_city(nation.capital_city_id),"capital is state center")
	for city in state.cities:
		if not city.is_traffic: continue
		check(state.administrative_center_of(city.id)==-1 and city.owner_nation==-1,"traffic has no administrative or political identity")
		check(city.manpower_per_month==0 and city.food_per_half_year==0 and city.gold_per_month==0,"traffic has no output")
	for edge in state.edges: check(edge.precise_distance>0. and edge.control_city_id>=0,"precise physical distance and district control")
	for city in state.land_cities():
		for neighbor in state.strategic_neighbors(city.id):
			check(not state.cities[neighbor].is_traffic,"AI quotient contains settlements only")
			check(state.strategic_edge_of(city.id,neighbor)!=null,"AI quotient edge maps to physical route")
	var fixed := state.administrative_center_by_city.duplicate(); state.rebuild_administrative_regions()
	check(fixed==state.administrative_center_by_city,"road rebuild retains administrative mapping")
	check(not state.trade_enabled and not state.random_ruler_profiles_enabled(),"preview military excludes trade and dynastic events")
	check(TradeNetwork.build_structure(state).routes.is_empty(),"disabled trade produces no routes")
	for pair in state.territorial_border_pairs():
		check(state.cities[pair.x].is_settlement() and state.cities[pair.y].is_settlement(),"political borders exclude traffic nodes")
	print("ATLAS_MILITARY_CONTRACT nodes=",state.cities.size()," edges=",state.edges.size()," failures=",failures)
	quit(1 if failures else 0)
