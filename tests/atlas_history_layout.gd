extends SceneTree
func _init() -> void:
	var state:=GameState.new();state.generate_grid_world(73)
	state.map_source_manifest="res://assets/terrain/eurasia_atlas_map_source.json"
	state.province_map_size=Vector2i(4,4);state.province_ids=PackedInt32Array([0,0,1,1,0,0,1,1,2,2,3,3,2,2,3,3])
	var old:=state.province_ids.duplicate();var old_position:=state.cities[0].map_position
	var history:=PoliticalHistory.new();history.reset(state,1)
	state.province_ids[0]=1;state.cities[0].map_position+=Vector2(0.001,0.001);state.day=1
	history.maybe_capture(state)
	var first:=history.build_view_state(state,0)
	var failures:=0
	if first.province_ids!=old: failures+=1;printerr("ATLAS_HISTORY_FAIL old IDs must belong to recorded layout")
	if first.cities[0].map_position!=old_position: failures+=1;printerr("ATLAS_HISTORY_FAIL seed position must belong to recorded layout")
	var second:=history.build_view_state(state,1)
	if second.province_ids!=state.province_ids or second.cities[0].map_position!=state.cities[0].map_position: failures+=1;printerr("ATLAS_HISTORY_FAIL later layout")
	print("ATLAS_HISTORY_LAYOUT failures=",failures);quit(1 if failures else 0)
