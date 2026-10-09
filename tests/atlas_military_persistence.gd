extends SceneTree
const Map = preload("res://scripts/atlas/military_map.gd")
var failures := 0
func check(ok: bool,message: String) -> void:
	if not ok: failures += 1; print("ATLAS_PERSISTENCE_FAIL ",message)
func _initialize() -> void:
	var base: Dictionary = preload("res://tests/atlas_military_inputs.gd").base()
	var payload := Map.prepare(base); var state := preload("res://tests/support/grid_world.gd").new(); state.generate_from_atlas(payload)
	var definition := MapDefinition.from_state(state)
	check(definition.version==9,"version nine")
	var error := MapDefinition.validate(definition); check(error.is_empty(),"template validates: "+error)
	if not error.is_empty(): quit(1); return
	var restored := preload("res://tests/support/grid_world.gd").new(); restored.generate_from_map_definition(JSON.parse_string(JSON.stringify(definition)))
	check(restored.province_ids==state.province_ids and restored.administrative_center_by_city==state.administrative_center_by_city,"geometry and fixed administration roundtrip")
	check(restored.edges.size()==state.edges.size() and restored.cities.size()==state.cities.size(),"graph roundtrip")
	for id in range(state.edges.size()): check(state.edges[id].map_path==restored.edges[id].map_path and state.edges[id].precise_distance==restored.edges[id].precise_distance,"path and length retained")
	var history := PoliticalHistory.new(); history.reset(state)
	var view := history.build_view_state(state,0)
	check(not view.atlas_layout.is_empty(),"history retains Atlas hierarchy")
	check(view.administrative_center_by_city==state.administrative_center_by_city,"historical administrative mapping")
	check(view.edges[0]!=state.edges[0] and view.edges[0].precise_distance==state.edges[0].precise_distance,"history owns frozen physical graph")
	var original_position: Vector2 = state.cities[0].map_position
	var original_path: PackedVector2Array = state.edges[0].map_path.duplicate()
	state.cities[0].map_position += Vector2(.01,.01); state.edges[0].map_path[0] += Vector2(.01,.01)
	state.day = 30; history.maybe_capture(state)
	view = history.build_view_state(state,0)
	check(view.cities[0].map_position==original_position and view.edges[0].map_path==original_path,"historical layout ignores current positions and roads")
	view = history.build_view_state(state,1)
	check(view.cities[0].map_position==state.cities[0].map_position,"new layout snapshot restores its own positions")
	check(not state.apply_city_editor_changes(0,{"map_x":.25}).ok,"fixed Atlas seed cannot be moved through legacy terrain editor")
	check(not state.apply_city_editor_changes(state.land_cities().size(),{"owner_nation":0}).ok,"traffic cannot be edited into a political city")
	var road := state.edges[0]
	state.cities[0].map_position = original_position; state.edges[0].map_path = original_path
	check(not state.apply_edge_editor_changes(road.city_a,road.city_b,{"kind":Edge.Kind.RIVER}).ok and road.kind==Edge.Kind.LAND,"road editor cannot reintroduce hydrology")
	state.apply_edge_editor_changes(road.city_a,road.city_b,{"danger":.3,"max_manpower":0,"travel_time_multiplier":1.5,"supply_loss_multiplier":.7})
	var edited := preload("res://tests/support/grid_world.gd").new(); edited.generate_from_map_definition(MapDefinition.from_state(state))
	var saved_road := edited.edge_of(road.city_a,road.city_b)
	check(saved_road.max_manpower==0 and is_equal_approx(saved_road.danger,.3) and is_equal_approx(saved_road.travel_time_multiplier,1.5) and is_equal_approx(saved_road.supply_loss_multiplier,.7),"template saves actual edited road rules")
	check(not MapDefinition.validate({"format":"world-war-map","version":8}).is_empty(),"obsolete map template is explicitly rejected")
	print("ATLAS_MILITARY_PERSISTENCE failures=",failures); quit(1 if failures else 0)
