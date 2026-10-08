extends SceneTree
## Regression: curved shared borders must also move the categorical fill and picking.
## Small fixtures deliberately cannot be reconstructed by a city Voronoi diagram.
const DISPLAY_SCRIPT := "res://scripts/view/atlas_display_geometry.gd"
var failures: Array[String] = []
var checks := 0
var display: Script

func _init() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("ATLAS_DISPLAY_GEOMETRY_FAIL: ", message)

func run() -> void:
	check(ResourceLoader.exists(DISPLAY_SCRIPT), "curved display implementation exists")
	if not failures.is_empty():
		finish()
		return
	display = load(DISPLAY_SCRIPT) as Script
	check(display != null and display.can_instantiate(), "display script compiles")
	if not failures.is_empty():
		finish()
		return
	test_non_voronoi_staircase()
	test_three_region_junction()
	test_near_boundary_seed()
	finish()

func finish() -> void:
	print("ATLAS_DISPLAY_GEOMETRY: %d checks / %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)

func test_non_voronoi_staircase() -> void:
	var state := GameState.new()
	state.province_map_size = Vector2i(12, 12)
	var divide := [5, 5, 6, 6, 4, 4, 5, 5, 7, 7, 6, 6]
	for y in range(12):
		for x in range(12):
			var label := 0 if x < divide[y] else 1
			if x == 0 or y == 0 or x == 11 or y == 11:
				label = -1
			elif y >= 9 and x >= 7:
				label = 3
			elif x == 9 and y == 7:
				label = 2 # A single-cell province must not disappear.
			elif x == 2 and y == 6:
				label = -1 # An intentional inland hole, not an ocean flood seed.
			state.province_ids.append(label)
	add_city(state, 0, Vector2(2.5, 2.5) / 12.0)
	add_city(state, 1, Vector2(8.5, 2.5) / 12.0)
	add_city(state, 2, Vector2(9.5, 7.5) / 12.0)
	add_city(state, 3, Vector2(8.5, 9.5) / 12.0)
	var before := state.province_ids.duplicate()
	var size := Vector2i(192, 192)
	var first: Dictionary = display.call("build", state, null, size)
	if not valid_channels(first, size):
		return
	var ids: Image = first.city_id
	var second: Dictionary = display.call("build", state, null, size)
	check(state.province_ids == before, "display does not mutate logical IDs")
	check(first.revision == second.revision, "revision deterministic")
	for key in ["city_id", "land_mask", "region_coverage", "region_edge", "region_distance"]:
		check((first[key] as Image).get_data() == (second[key] as Image).get_data(), "deterministic channel: " + key)
	check(first.topology == second.topology, "deterministic boundary topology")
	verify_labels(state, ids, true)
	verify_derived_channels(first)
	verify_topology(first.topology, ids, true)
	verify_border_motion(state, first.topology)
	for city in state.cities:
		check(int(display.call("city_at", ids, city.map_position)) == city.id, "seed retained: %d" % city.id)
	check(int(display.call("city_at", ids, Vector2(-0.01, 0.5))) == -1, "negative UV returns blank")
	check(int(display.call("city_at", ids, Vector2(1.01, 0.5))) == -1, "outside UV returns blank")
	# A land mask must never erase the intentional logical hole or assign sea.
	var height := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	height.fill(Color(1.0, 1.0, 1.0, 0.8))
	for y in range(192):
		for x in range(16):
			height.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.1))
	# Fine terrain may put a cove/strait inside a coarse labelled cell. This
	# water patch intersects the saved province boundary without touching seeds.
	for y in range(65, 95):
		for x in range(50, 90):
			height.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.1))
	# A bay enters an existing coarse coastline. Coastal ink cannot keep
	# describing the removed land while province ink has already been clipped.
	for y in range(16, 32):
		for x in range(110, 146):
			height.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.1))
	var masked: Dictionary = display.call("build", state, height, size)
	var sea_labels := 0
	var masked_ids: Image = masked.city_id
	var land: Image = masked.land_mask
	for y in range(192):
		for x in range(192):
			if land.get_pixel(x, y).r < 0.5 and masked_ids.get_pixel(x, y).r >= 0.0:
				sea_labels += 1
	check(sea_labels == 0, "no province assigned to sea")
	check(int(display.call("city_at", masked_ids, Vector2(2.5, 6.5) / 12.0)) == -1, "land-mask build retains inland blank")
	verify_derived_channels(masked)
	verify_topology(masked.topology, masked_ids, true)
	verify_coast_sides(masked.topology, masked_ids)
	# Editing current data must produce a fresh result without changing history.
	state.province_ids[2 * 12 + 4] = 1
	var edited: Dictionary = display.call("build", state, null, size)
	check(edited.revision != first.revision, "logical edit changes revision")
	check((first.city_id as Image).get_data() == (second.city_id as Image).get_data(), "saved historical image remains immutable")
	var resized: Dictionary = display.call("build", state, null, Vector2i(96, 96))
	check(resized.revision != edited.revision, "output resolution included in revision")

func test_three_region_junction() -> void:
	var state := GameState.new()
	state.province_map_size = Vector2i(8, 8)
	for y in range(8):
		for x in range(8):
			state.province_ids.append(2 if y >= 4 else (0 if x < 4 else 1))
	add_city(state, 0, Vector2(0.25, 0.25))
	add_city(state, 1, Vector2(0.75, 0.25))
	add_city(state, 2, Vector2(0.5, 0.75))
	var result: Dictionary = display.call("build", state, null, Vector2i(128, 128))
	if not valid_channels(result, Vector2i(128, 128)):
		return
	verify_labels(state, result.city_id, false)
	verify_topology(result.topology, result.city_id, false)
	verify_border_motion(state, result.topology)
	var segments: PackedVector2Array = result.topology.province
	var pairs_at_junction := {}
	for i in range(result.topology.province_a.size()):
		if segments[i * 2].distance_to(Vector2(0.5, 0.5)) < 0.00001 or segments[i * 2 + 1].distance_to(Vector2(0.5, 0.5)) < 0.00001:
			var a: int = result.topology.province_a[i]
			var b: int = result.topology.province_b[i]
			pairs_at_junction["%d:%d" % [mini(a, b), maxi(a, b)]] = true
	check(pairs_at_junction.size() == 3, "all three shared chains keep the same pinned junction")

func add_city(state: GameState, id: int, uv: Vector2) -> void:
	var city := City.new()
	city.id = id
	city.map_position = uv
	state.cities.append(city)

func test_near_boundary_seed() -> void:
	var state := GameState.new()
	state.province_map_size = Vector2i(8, 8)
	for y in range(8):
		for x in range(8):
			state.province_ids.append(0 if x < (6 if y < 4 else 4) else 1)
	add_city(state, 0, Vector2(0.25, 0.25))
	# This is a valid province-1 city just inside the L-shaped boundary corner.
	# Restoring only its single output pixel after smoothing creates an island.
	var seed := Vector2(4.03125, 4.03125) / 8.0
	add_city(state, 1, seed)
	var result: Dictionary = display.call("build", state, null, Vector2i(128, 128))
	if not valid_channels(result, Vector2i(128, 128)):
		return
	var ids: Image = result.city_id
	check(int(display.call("city_at", ids, seed)) == 1, "near-boundary seed remains in its own province")
	var p := Vector2i(seed * Vector2(ids.get_size()))
	var attached := false
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var q: Vector2i = p + offset
		if int(ids.get_pixelv(q).r) == 1:
			attached = true
	check(attached, "protecting near-boundary seed does not leave an isolated display pixel")

func valid_channels(result: Dictionary, size: Vector2i) -> bool:
	var valid := true
	for key in ["city_id", "land_mask", "region_coverage", "region_edge", "region_distance"]:
		var image := result.get(key) as Image
		var ok := image != null and image.get_size() == size
		check(ok, "valid display channel: " + key)
		valid = valid and ok
	check(result.has("revision") and result.has("topology") and result.has("regions"), "revision/topology/regions contract")
	return valid and result.has("topology") and result.has("revision")

func verify_labels(state: GameState, ids: Image, must_curve: bool) -> void:
	var changed := 0
	var displaced_too_far := 0
	var blank_changed := 0
	var pick_mismatch := 0
	var unknown := 0
	var source_size := state.province_map_size
	var source_regions := {}
	for label in state.province_ids:
		source_regions[label] = true
	for y in range(ids.get_height()):
		for x in range(ids.get_width()):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(ids.get_size())
			var label := int(ids.get_pixel(x, y).r)
			var old := state.province_city_at(uv)
			if not source_regions.has(label):
				unknown += 1
			if int(display.call("city_at", ids, uv)) != label:
				pick_mismatch += 1
			if old == -1 and label != -1:
				blank_changed += 1
			if label == old:
				continue
			changed += 1
			var point := uv * Vector2(source_size)
			var nearest := INF
			for sy in range(maxi(0, int(point.y) - 1), mini(source_size.y, int(point.y) + 2)):
				for sx in range(maxi(0, int(point.x) - 1), mini(source_size.x, int(point.x) + 2)):
					if state.province_ids[sy * source_size.x + sx] != label:
						continue
					var closest := Vector2(clampf(point.x, sx, sx + 1), clampf(point.y, sy, sy + 1))
					nearest = minf(nearest, point.distance_to(closest))
			if nearest > 0.50001:
				displaced_too_far += 1
	check(changed > 0 if must_curve else true, "staircase fill actually follows curves, rather than nearest-neighbor enlargement")
	check(displaced_too_far == 0, "changed pixel labels move at most half a logical cell")
	check(blank_changed == 0, "coasts and intentional logical blanks are retained")
	check(unknown == 0, "no invented regions")
	check(pick_mismatch == 0, "every display pixel and city_at agree")
	# Centers are away from the rounding band, including tiny provinces/holes.
	var center_mismatch := 0
	for y in range(source_size.y):
		for x in range(source_size.x):
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(source_size)
			if int(display.call("city_at", ids, uv)) != state.province_ids[y * source_size.x + x]:
				center_mismatch += 1
	check(center_mismatch == 0, "logical cell interiors, tiny province and hole survive")

func verify_topology(topology: Dictionary, ids: Image, must_curve: bool) -> void:
	for key in ["province", "coast", "province_a", "province_b", "province_side_a", "province_side_b", "coast_province", "coast_side"]:
		check(topology.has(key), "boundary contract key: " + key)
		if not topology.has(key):
			return
	var segments: PackedVector2Array = topology.province
	var count := segments.size() / 2
	check(segments.size() % 2 == 0, "province endpoints paired")
	for key in ["province_a", "province_b", "province_side_a", "province_side_b"]:
		check(topology[key].size() == count, "metadata count: " + key)
		if topology[key].size() != count:
			return
	check(topology.coast.size() == topology.coast_province.size() * 2 and topology.coast_side.size() == topology.coast_province.size(), "coast metadata count")
	var oblique := 0
	var mismatches := 0
	var sampled := 0
	var invalid_normals := 0
	var epsilon := 1.0 / float(maxi(ids.get_width(), ids.get_height()))
	for i in range(count):
		var a: Vector2 = segments[i * 2]
		var b: Vector2 = segments[i * 2 + 1]
		var delta := b - a
		if absf(delta.x) > 0.000001 and absf(delta.y) > 0.000001:
			oblique += 1
		var side_a: Vector2 = topology.province_side_a[i]
		var side_b: Vector2 = topology.province_side_b[i]
		if absf(side_a.length() - 1.0) > 0.001 or side_a.dot(side_b) > -0.999:
			invalid_normals += 1
		# Avoid junction ambiguity from segments shorter than two output pixels.
		if delta.length() < epsilon * 2.0:
			continue
		var middle := (a + b) * 0.5
		var actual_a := int(display.call("city_at", ids, middle + side_a * epsilon))
		var actual_b := int(display.call("city_at", ids, middle + side_b * epsilon))
		sampled += 1
		if actual_a != int(topology.province_a[i]) or actual_b != int(topology.province_b[i]):
			mismatches += 1
	check(oblique > 0 if must_curve else true, "shared boundary has curved/oblique geometry")
	check(invalid_normals == 0, "side metadata contains opposing inward unit normals")
	check(sampled > 0, "tested boundary-side samples")
	check(mismatches == 0, "fill and canonical curve side labels agree (%d/%d mismatches)" % [mismatches, sampled])

func verify_derived_channels(result: Dictionary) -> void:
	var ids: Image = result.city_id
	var coverage: Image = result.region_coverage
	var edge: Image = result.region_edge
	var distance: Image = result.region_distance
	var coverage_errors := 0
	var edge_errors := 0
	var distance_errors := 0
	for y in range(ids.get_height()):
		for x in range(ids.get_width()):
			var label := int(ids.get_pixel(x, y).r)
			if (coverage.get_pixel(x, y).r > 0.5) != (label >= 0):
				coverage_errors += 1
			if label < 0:
				continue
			var touches_other := false
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var p: Vector2i = Vector2i(x, y) + offset
				if p.x >= 0 and p.y >= 0 and p.x < ids.get_width() and p.y < ids.get_height() and int(ids.get_pixelv(p).r) != label:
					touches_other = true
			if touches_other and edge.get_pixel(x, y).r <= 0.5:
				edge_errors += 1
			if touches_other and absf(distance.get_pixel(x, y).r) > 0.001:
				distance_errors += 1
	check(coverage_errors == 0, "coverage follows final categorical display")
	check(edge_errors == 0, "edge channel follows final categorical transitions")
	check(distance_errors == 0, "distance zero at final display boundaries")

func verify_coast_sides(topology: Dictionary, ids: Image) -> void:
	var segments: PackedVector2Array = topology.coast
	var mismatches := 0
	var sampled := 0
	var epsilon := 1.0 / float(maxi(ids.get_width(), ids.get_height()))
	for i in range(topology.coast_province.size()):
		var a := segments[i * 2]
		var b := segments[i * 2 + 1]
		if a.distance_to(b) < epsilon * 2.0:
			continue
		var normal: Vector2 = topology.coast_side[i]
		var middle := (a + b) * 0.5
		# Coastlines trace categorical pixel edges, so inspect their directly
		# adjacent pixels instead of skipping into a second inland pixel.
		var land_side := int(display.call("city_at", ids, middle + normal * epsilon * 0.5))
		var sea_side := int(display.call("city_at", ids, middle - normal * epsilon * 0.5))
		sampled += 1
		if land_side != int(topology.coast_province[i]) or sea_side != -1:
			mismatches += 1
	check(sampled > 0, "tested coastal boundary-side samples")
	check(mismatches == 0, "coastal topology follows final DEM-masked labels (%d/%d mismatches)" % [mismatches, sampled])

func verify_border_motion(state: GameState, topology: Dictionary) -> void:
	var grid := state.province_map_size
	var raw := []
	for y in range(grid.y):
		for x in range(grid.x):
			var label := state.province_ids[y * grid.x + x]
			if label < 0:
				continue
			if x + 1 < grid.x:
				var other := state.province_ids[y * grid.x + x + 1]
				if other >= 0 and label != other:
					raw.append([Vector2(x + 1, y), Vector2(x + 1, y + 1), label, other])
			if y + 1 < grid.y:
				var other := state.province_ids[(y + 1) * grid.x + x]
				if other >= 0 and label != other:
					raw.append([Vector2(x, y + 1), Vector2(x + 1, y + 1), label, other])
	var too_far := 0
	var segments: PackedVector2Array = topology.province
	for i in range(topology.province_a.size()):
		var left: int = topology.province_a[i]
		var right: int = topology.province_b[i]
		var a := segments[i * 2] * Vector2(grid)
		var b := segments[i * 2 + 1] * Vector2(grid)
		for p in [a, (a + b) * 0.5, b]:
			var nearest := INF
			for source in raw:
				if not (source[2] in [left, right] and source[3] in [left, right]):
					continue
				var q := Geometry2D.get_closest_point_to_segment(p, source[0], source[1])
				nearest = minf(nearest, p.distance_to(q))
			if nearest > 0.50001:
				too_far += 1
	check(too_far == 0, "canonical curve stays within half a cell of its original shared boundary")
