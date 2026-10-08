extends SceneTree
const SOURCE := "res://assets/terrain/eurasia_transport_map_source.json"
var failures: Array[String] = []

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("TRANSPORT_COMPATIBILITY_FAIL ", message)

func run() -> void:
	var state := GameState.new()
	var template_path := OS.get_environment("TRANSPORT_TEMPLATE")
	if template_path.is_empty():
		check(state.generate_world(12345, 40, 500, "", {}, 12345, "", SOURCE), state.last_generation_error)
	else:
		var definition: Variant = JSON.parse_string(FileAccess.get_file_as_string(template_path))
		check(definition is Dictionary and MapDefinition.validate(definition).is_empty(), "input template validates")
		if failures.is_empty(): state.generate_from_map_definition(definition, 12345)
	if not failures.is_empty(): quit(1); return
	print("TRANSPORT_COMPATIBILITY_START pid=", OS.get_process_id(), " seed=", state.world_seed, " world_index=0 source=", state.map_source_manifest)
	check(state.map_source_manifest == SOURCE, "candidate retains its source")
	var before := MapDefinition.from_state(state)
	var history := PoliticalHistory.new()
	history.reset(state)
	var snapshot := history.build_view_state(state, 0)
	check(snapshot.province_ids == state.province_ids and snapshot.river_features == state.river_features, "history keeps the same provinces and rivers")
	var original: Vector2 = state.cities[0].map_position
	var rejected := state.apply_city_editor_changes(0, {"map_x": state.cities[1].map_position.x, "map_y": state.cities[1].map_position.y})
	check(not rejected.ok and MapDefinition.from_state(state) == before, "invalid duplicate seed edit is transactional")
	var moved := state.apply_city_editor_changes(0, {"map_x": original.x + 0.00001, "map_y": original.y})
	if moved.ok:
		check(state.territory_structure_valid(), "successful edit preserves territory bindings")
		check(state.river_features == snapshot.river_features, "editing keeps river geometry")
	else:
		check(MapDefinition.from_state(state) == before, "unsafe shore rebuild preserves the complete original world")
	print("TRANSPORT_EDIT_RESULT ", moved)
	check(snapshot.province_ids == PackedInt32Array(before.province_ids), "editing does not mutate historical province IDs")
	var restored := GameState.new()
	var after := MapDefinition.from_state(state)
	restored.generate_from_map_definition(after, 12345)
	var round_trip := MapDefinition.from_state(restored)
	# Templates start a fresh campaign and normalize regional food pools. A
	# road edit can move their storage city; compare geometry exactly and
	# require each nation's food total to survive that existing normalization.
	var expected := after.duplicate(true)
	var actual := round_trip.duplicate(true)
	var before_food := {}
	var after_food := {}
	for record in expected.cities:
		before_food[record.owner_nation] = int(before_food.get(record.owner_nation, 0)) + int(record.food_storage)
		record.erase("food_storage")
	for record in actual.cities:
		after_food[record.owner_nation] = int(after_food.get(record.owner_nation, 0)) + int(record.food_storage)
		record.erase("food_storage")
	check(before_food == after_food, "template normalization preserves national food totals")
	if actual != expected:
		FileAccess.open("res://.dbg/transport-edited-before.json", FileAccess.WRITE).store_string(JSON.stringify(after))
		FileAccess.open("res://.dbg/transport-edited-after.json", FileAccess.WRITE).store_string(JSON.stringify(round_trip))
	check(actual == expected, "edited template round trip preserves actual geometry, paths and city attributes")
	# Rendering consumes the saved labels and paths; it never regenerates them.
	root.size = Vector2i(1600, 900)
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.paused = true
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(state, simulation)
	renderer.set_city_names_visible(false)
	renderer.set_nation_names_visible(true)
	renderer.set_army_icon_scale(0.25)
	renderer.set_world_layer_visible(false)
	var view := StrategicMap3D.new()
	root.add_child(view)
	view.setup(state, simulation, renderer)
	var started := Time.get_ticks_msec()
	while view._terrain == null or view._terrain.land_cell_count() <= 0:
		if Time.get_ticks_msec() - started > 90000: check(false, "terrain preview timed out"); quit(1); return
		await process_frame
	var ids: PackedByteArray = renderer.visual_atlas().city_id.get_data()
	var output := OS.get_environment("TRANSPORT_VISUAL_DIR")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	for mode in [MapRenderer.MapMode.POLITICAL, MapRenderer.MapMode.LOYALTY, MapRenderer.MapMode.TRADE]:
		view.set_map_mode(mode)
		await process_frame
		check(renderer.visual_atlas().city_id.get_data() == ids, "all view modes keep identical province IDs")
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(output.path_join("transport-mode-%d.png" % mode)) == OK, "save preview")
	for uv in [Vector2(0.2, 0.4), Vector2(0.5, 0.5), Vector2(0.8, 0.5)]:
		var screen := view._camera.unproject_position(view._terrain.map_to_world(uv))
		check(view._screen_to_map_position(screen).distance_to(uv) < 0.015, "3D picking remains aligned")
	view.free()
	renderer.free()
	simulation.free()
	print("TRANSPORT_COMPATIBILITY failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
