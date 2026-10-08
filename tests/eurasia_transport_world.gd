extends SceneTree
## End-to-end acceptance of the province_ids/full-network transport candidate.
## Deliberately permits new city coordinates; only the actual generated world
## and its saved template are required to agree.
const SOURCE := "res://assets/terrain/eurasia_transport_map_source.json"
const Banks = preload("res://scripts/core/river_province_constraints.gd")
const Hydro = preload("res://scripts/core/terrain_hydrology.gd")
var failures: Array[String] = []
var current_seed: int = 0

func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		var detail := "seed=%d %s" % [current_seed, message]
		failures.append(detail)
		printerr("EURASIA_TRANSPORT_WORLD_FAIL ", detail)

func save_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "cannot write acceptance artifact: " + path)
	if file != null: file.store_string(JSON.stringify(value))

func run() -> void:
	var seeds := [2342006650, 12345, 23456, 34567, 45678, 1470349411]
	if not OS.get_environment("HYDROLOGY_SEED").is_empty(): seeds = [int(OS.get_environment("HYDROLOGY_SEED"))]
	OS.set_environment("HYDROLOGY_DIAGNOSE", "1")
	var manifest_error := MapSource.validate_manifest(SOURCE)
	check(manifest_error.is_empty(), "candidate manifest: " + manifest_error)
	if not manifest_error.is_empty():
		finish()
		return
	var density := MapSource.settlement_density_bounds(SOURCE)
	check(absf(float(density.minimum) - 0.02) < 0.000001 and absf(float(density.maximum) - 1.0) < 0.000001, "candidate explicitly uses density bounds [0.02, 1.0]")
	for seed_value in seeds:
		current_seed = int(seed_value)
		run_seed()
	finish()

func run_seed() -> void:
	print("EURASIA_TRANSPORT_START pid=", OS.get_process_id(), " seed=", current_seed, " world_index=0 source=", SOURCE)
	var first_failure := failures.size()
	var started := Time.get_ticks_usec()
	var started_unix := int(Time.get_unix_time_from_system())
	var state := GameState.new()
	var ok := state.generate_world(current_seed, 40, 500, "", {}, current_seed, "", SOURCE)
	var generated_usec := Time.get_ticks_usec() - started
	var path := "res://.dbg/transport-world-%d.json" % current_seed
	var report := {"seed": current_seed, "source": SOURCE, "generated": ok, "generation_seconds": float(generated_usec) / 1000000.0, "error": state.last_generation_error}
	if not ok:
		check(false, "generation returned failure: " + state.last_generation_error)
		var failure_path := "res://.dbg/hydrology-generation-failure-%d.json" % current_seed
		if FileAccess.file_exists(failure_path) and FileAccess.get_modified_time(failure_path) >= started_unix:
			var failure_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(failure_path))
			if failure_report.get("seed", -1) == current_seed and failure_report.get("source", "") == SOURCE: report["generation_failure"] = failure_report
		report["failures"] = failures.slice(first_failure)
		save_json(path, report)
		print("EURASIA_TRANSPORT_WORLD seed=%d generated=false error=%s seconds=%.3f" % [current_seed, state.last_generation_error, report.generation_seconds])
		return
	check(state.land_cities().size() == 500 and state.nations.size() == 40, "world must have 500 land cities and 40 nations")
	check(state.map_source_manifest == SOURCE, "world retains the actual candidate source")
	check(state.territory_structure_valid(), "initial territory and military bindings are valid")
	var size := state.province_map_size
	check(size.x > 0 and size.y > 0 and state.province_ids.size() == size.x * size.y, "logical province raster has valid dimensions")
	if size.x <= 0 or size.y <= 0 or state.province_ids.size() != size.x * size.y:
		report["failures"] = failures.slice(first_failure)
		save_json(path, report)
		return
	var source := (load(state.current_terrain_map_path()) as Texture2D).get_image()
	var coarse: Image = source.duplicate()
	coarse.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	var land: PackedByteArray = TerrainMapGenerator._all_land_geometry(coarse).mask
	var blocked := Hydro.barriers(state.river_features, size)
	var components := Hydro.components(land, size, blocked)
	var constraints := Banks.build(state.river_features, size, state.map_aspect_ratio)
	var bank_errors := Banks.validate(state.province_ids, constraints)
	check(bank_errors.is_empty(), "major-river opposite-bank ownership: %s" % str(bank_errors))
	var seeds := {}
	var seeded_components := {}
	var city_ids := {}
	var invalid_land: Array[int] = []
	var duplicate_seeds: Array[int] = []
	var disconnected: Array[int] = []
	var wrong_seed_owner: Array[int] = []
	for city in state.land_cities():
		city_ids[city.id] = true
		var uv: Vector2 = city.map_position
		if uv.x < 0 or uv.x >= 1 or uv.y < 0 or uv.y >= 1:
			invalid_land.append(city.id)
			continue
		var original_pixel := Vector2i(uv * Vector2(source.get_size()))
		if not TerrainMapGenerator.packed_is_land(source.get_pixelv(original_pixel)): invalid_land.append(city.id)
		var cell := Vector2i(uv * Vector2(size))
		var index := cell.y * size.x + cell.x
		if seeds.has(index): duplicate_seeds.append(city.id)
		seeds[index] = city.id
		if components[index] >= 0: seeded_components[components[index]] = true
		if state.province_ids[index] != city.id: wrong_seed_owner.append(city.id)
		if not Banks._connected(state.province_ids, size, cell, city.id, blocked): disconnected.append(city.id)
	check(invalid_land.is_empty(), "all city positions lie on original land; invalid=%s" % str(invalid_land))
	check(duplicate_seeds.is_empty(), "province seed cells are unique; duplicates=%s" % str(duplicate_seeds))
	check(wrong_seed_owner.is_empty(), "every city owns its logical seed cell; wrong=%s" % str(wrong_seed_owner))
	check(disconnected.is_empty(), "every assigned province cell connects to its city without crossing a main river; disconnected=%s" % str(disconnected))
	var gaps: Array[int] = []
	var invalid_owners: Array[int] = []
	var unseeded_blank := 0
	for i in range(land.size()):
		var owner := state.province_ids[i]
		if owner >= 0 and not city_ids.has(owner): invalid_owners.append(i)
		if land[i] == 0 or owner >= 0: continue
		if seeded_components.has(components[i]): gaps.append(i)
		else: unseeded_blank += 1
	check(invalid_owners.is_empty(), "province raster only references actual land cities; cells=%s" % str(invalid_owners.slice(0, 12)))
	check(gaps.is_empty(), "seeded land components are fully assigned; count=%d examples=%s" % [gaps.size(), str(gaps.slice(0, 12))])
	var west := nearest_city(state, 3.0, 46.0)
	var middle := nearest_city(state, 60.0, 40.0)
	var east := nearest_city(state, 108.9, 34.3)
	var west_middle := reachable(state, west, middle)
	var middle_east := reachable(state, middle, east)
	check(west_middle and middle_east, "Western Europe, Central Asia and China connect without SEA edges: %d -> %d -> %d" % [west, middle, east])
	var definition := MapDefinition.from_state(state)
	var template_error := MapDefinition.validate(definition)
	check(template_error.is_empty(), "template validates: " + template_error)
	var template_round_trip := false
	if template_error.is_empty():
		var restored := GameState.new()
		restored.generate_from_map_definition(definition, current_seed)
		template_round_trip = MapDefinition.from_state(restored) == definition
		check(template_round_trip, "template round-trip preserves source, city coordinates, province IDs, river network and final traffic paths")
		check(restored.province_ids == state.province_ids and restored.map_source_manifest == SOURCE, "restored world reads the same province_ids and map source")
	report.merge({"land_cities": state.land_cities().size(), "nations": state.nations.size(), "docks": state.cities.size() - state.land_cities().size(), "metadata": state.generation_metadata, "duplicate_seed_cities": duplicate_seeds, "invalid_land_cities": invalid_land, "disconnected_provinces": disconnected, "wrong_seed_owners": wrong_seed_owner, "seeded_gaps": gaps, "unseeded_blank_cells": unseeded_blank, "bank_errors": bank_errors, "route_cities": [west, middle, east], "west_middle": west_middle, "middle_east": middle_east, "template_round_trip": template_round_trip, "failures": failures.slice(first_failure), "total_seconds": float(Time.get_ticks_usec() - started) / 1000000.0})
	# Keep the primary artifact directly loadable by the editor and simulation
	# audit; diagnostics are adjacent rather than injected into template data.
	save_json(path, definition)
	save_json("res://.dbg/transport-world-%d-diagnostics.json" % current_seed, report)
	print("EURASIA_TRANSPORT_WORLD seed=%d cities=%d nations=%d docks=%d seeded_gaps=%d disconnected=%d bank_errors=%s generation_seconds=%.3f failures=%d" % [current_seed, state.land_cities().size(), state.nations.size(), report.docks, gaps.size(), disconnected.size(), str(bank_errors), report.generation_seconds, failures.size() - first_failure])

func nearest_city(state: GameState, lon: float, lat: float) -> int:
	var uv := MapSource.lonlat_to_map(lon, lat, SOURCE)
	var point := Vector2(uv[0], uv[1])
	var closest := -1
	var distance := INF
	for city in state.land_cities():
		var candidate := TerrainMapGenerator.metric_length_between(point, city.map_position, state.map_aspect_ratio)
		if candidate < distance:
			closest = city.id
			distance = candidate
	return closest

func reachable(state: GameState, start: int, target: int) -> bool:
	if start < 0 or target < 0: return false
	var queue: Array[int] = [start]
	var seen := {start: true}
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		if current == target: return true
		for neighbor in state.neighbors(current):
			var edge: Edge = state.edge_of(current, neighbor)
			if edge == null or edge.kind == Edge.Kind.SEA or edge.max_manpower <= 0 or seen.has(neighbor): continue
			seen[neighbor] = true
			queue.append(neighbor)
	return false

func finish() -> void:
	print("EURASIA_TRANSPORT_WORLD failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
