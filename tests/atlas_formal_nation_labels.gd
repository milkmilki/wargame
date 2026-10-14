extends SceneTree
const Direct = preload("res://tests/direct_center_camp.gd")
const Labels = preload("res://scripts/atlas/polity_labels.gd")
const TextState = preload("res://scripts/atlas/text_state.gd")
class View extends "res://scripts/atlas/military_preview.gd":
	var publications := 0
	func _ready(): set_process(false)
	func refresh_ownership(): publications += 1
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("FORMAL_NATION_LABEL_FAIL ", message)
func run():
	var view := View.new(); root.add_child(view)
	var state := Direct.fixture(); view.state = state
	var nomads: Array = RegionalNames.data().nomad_names.preferred
	for id in range(3):
		var nation: Nation = state.nations[id]
		nation.name = str(nomads[id]) if id < 2 else "秦"
		nation.short_name = nation.name; nation.name_kind = WorldNaming.KIND_WARRING_STATE
		nation.environment_kind = "nomad" if id < 2 else "farm"
		nation.state_level = 1 if id == 1 else 0
	var cities := []; var x := PackedFloat32Array(); var y := PackedFloat32Array()
	var areas := PackedFloat32Array(); var districts := PackedInt32Array()
	for id in range(state.cities.size()):
		cities.append({"cell": id, "role": "zhou"}); x.append(100. + id * 200.); y.append(500.)
		areas.append(1.); districts.append(id)
	view.military_payload = {"data": {"mesh": {"n": cities.size(), "x": x, "y": y, "areas": areas}, "regions": {}, "environment": {"suitability": areas}}, "hierarchy": {"cities": cities, "district_of_cell": districts}, "network": {"routes": []}, "graph": {}}
	var before := state.nations.map(func(n): return [n.name, n.short_name])
	view.data = view.visual_data(); view.display = {"nations": view.data.nations}
	var expected := [str(nomads[0]) + "部", str(nomads[1]) + "汗", "秦国"]
	check(view.data.nations.map(func(n): return n.name) == expected, "initial map publishes complete formal country names")
	view.sync_nations(state)
	check(view.data.nations.map(func(n): return n.name) == expected, "live refresh retains suffixes")
	check(state.nations.map(func(n): return [n.name, n.short_name]) == before, "map formatting preserves founding roots")
	view.simulation = Simulation.new(); view.simulation.state = state; view.simulation.paused = true
	view.overlay = preload("res://scripts/atlas/military_overlay.gd").new(); view.overlay.state = state
	view.view_ready = true; view.last_owner_revision = state.ownership_revision
	view.history.reset(state)
	var historical := view.history.build_view_state(state, 0)
	view._process(0.)
	var owner_revision := state.ownership_revision
	state.nations[0].state_level = 1; state.family_revision += 1
	view._process(0.)
	check(state.ownership_revision == owner_revision and view.data.nations[0].name == str(nomads[0]) + "汗", "promotion refreshes map without an ownership change")
	check(view.publications == 1, "promotion publishes one label revision")
	for frame in range(5): view._process(0.)
	state.family_revision += 1; view._process(0.)
	check(view.publications == 1, "idle frames and unrelated family changes reuse country layout")
	view.historical_view = true; view.sync_nations(historical)
	check(view.data.nations.map(func(n): return n.name) == expected, "historical map retains titles at snapshot time")
	view.historical_view = false; view.last_owner_revision = -1; view._process(0.)
	check(view.data.nations[0].name == str(nomads[0]) + "汗", "returning to current map restores current title")
	state.nations[2].name = "李明军"; state.nations[2].short_name = "李明军"; state.nations[2].name_kind = WorldNaming.KIND_REBEL
	state.naming_revision += 1; view._process(0.)
	check(view.data.nations[2].name == "李明军", "special military names do not acquire sovereign suffixes")
	state.nations[2].name = "长名称国"; state.nations[2].name_kind = WorldNaming.KIND_WARRING_STATE
	state.naming_revision += 1; view._process(0.)
	check(view.data.nations[2].name == "长名称国", "legacy explicit names remain complete without double suffixes")
	test_layout(view.data)
	view.overlay.free(); view.simulation.free(); view.queue_free(); await process_frame
	print("ATLAS_FORMAL_NATION_LABELS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
func test_layout(data: Dictionary):
	var grid := PackedInt32Array(); grid.resize(512 * 256)
	for i in range(grid.size()): grid[i] = [0, 3, 5][mini(2, (i % 512) * 3 / 512)]
	var field := Labels.field(grid, PackedInt32Array(data.ownership), 512, 256)
	var labels := Labels.fit_all(data, field)
	check(labels.size() == 3 and labels.all(func(row): return row.text == data.nations[row.polity].name), "territory fitting keeps complete text")
	var text := TextState.new(); text.data = data; text.labels = labels; text.show_cities = false
	text.zoom = 4.; text.canvas_size = Vector2(8192, 4096)
	text.owners.resize(2048 * 1024)
	for i in range(text.owners.size()): text.owners[i] = mini(2, (i % 2048) * 3 / 2048)
	var water := PackedByteArray(); water.resize(text.owners.size()); text.raster = {"water": water}
	text.prepare(); var output: Dictionary = text.update(Rect2(Vector2.ZERO, text.canvas_size))
	var strings: Array = output.rows.map(func(row): return "".join(row.glyphs.map(func(glyph): return glyph.ch)))
	for nation in data.nations: check(strings.has(nation.name), "accepted glyph layout includes whole name: " + nation.name)
