extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_COUNTRIES_FAIL ",message)
func _initialize(): call_deferred("run")
func run():
	var state := GameState.new()
	for i in range(3):
		var n := Nation.new(); n.id=i; n.name="国家%d"%i; state.nations.append(n)
	var list := preload("res://scripts/atlas/nation_list.gd").new(); root.add_child(list); list.size=Vector2(416,420)
	list.source_provider=func(): return state
	list.observer_provider=func(): return 0
	list.open(); await process_frame
	var first: Button=list.entries[0]; var refreshes: int=list.refresh_count
	list.refresh(); check(list.entries[0]==first and list.refresh_count==refreshes,"unchanged list reuses controls")
	list.search.text="国家2"; list.refresh()
	check(list.entries.values().filter(func(b): return b.visible).size()==1 and list.entries[2].visible,"search hides unmatched IDs")
	list.search.text=""; state.nations[0].name="改名"; state.nations[1].alive=false; list.refresh()
	check(list.entries[0]==first and first.text.contains("改名") and not list.entries[1].visible,"rename and extinction update existing entries")
	var selected: Array=[]; list.selected.connect(func(id): selected.append(id)); list.entries[2].pressed.emit()
	check(selected==[2] and not list.visible,"button uses stable nation ID and closes list")
	check(not list.mouse_force_pass_scroll_events,"country scrolling cannot leak into map zoom")
	root.remove_child(list); list.queue_free(); await process_frame
	print("ATLAS_NATION_LIST failures=",failures); quit(1 if failures else 0)
