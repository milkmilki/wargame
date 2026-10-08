extends SceneTree
const Roads = preload("res://scripts/core/atlas_road_network.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); printerr("ATLAS_ROADS_FAIL ", message)
func _init() -> void: call_deferred("run")
func run() -> void:
	check(Roads.step_cost(0.0, 0.0, 1.0, 100.0, true, true) == 0.5, "existing road discount")
	check(Roads.step_cost(0.0, 0.0, 1.0, 100.0, false, false) == 2.0, "non-city penalty")
	check(Roads.step_cost(0.0, 0.3, 1.0, 100.0, false, true) > 1.0, "mountains cost more")
	var links: Array[Dictionary] = [{"a":0,"b":1,"cost":1.0},{"a":1,"b":2,"cost":1.0},{"a":0,"b":2,"cost":3.0},{"a":3,"b":4,"cost":1.0}]
	var kept := Roads.prune_links(links, 5)
	check(kept.size() == 3, "Urquhart removes triangle redundancy and keeps separate forest")
	var image := Image.create(48, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,0.55))
	var positions: Array[Vector2] = [Vector2(0.15,0.5),Vector2(0.5,0.5),Vector2(0.85,0.5)]
	var pixels: Array[Vector2i] = [Vector2i(7,12),Vector2i(24,12),Vector2i(40,12)]
	var ids := PackedInt32Array()
	for y in range(24):
		for x in range(48): ids.append(0 if x < 16 else (1 if x < 32 else 2))
	var samples := {"positions":positions,"pixels":pixels}
	var provinces := {"size":Vector2i(48,24),"ids":ids}
	var first := Roads.build(image,image,samples,provinces,2.0)
	check(first.get("ok",false), "flat mainland builds")
	check(first.get("roads",[]).size() == 2, "third province cannot be bypassed")
	check(not Roads.path_valid(PackedVector2Array([positions[0], positions[2]]), provinces, 0, 2, {"image":image,"maximum_height":1.0}), "direct shortcut through third province rejected")
	var repeat := Roads.build(image,image,samples,provinces,2.0)
	check(first.get("roads", []) == repeat.get("roads", []), "deterministic geometry")
	for key in ["road_network_version", "major_city_ids", "candidate_count", "fine_fallbacks"]:
		check(first.metadata[key] == repeat.metadata[key], "deterministic metadata: " + key)
	for road in first.get("roads",[]):
		check(road.map_path[0] == positions[road.a] and road.map_path[-1] == positions[road.b], "exact city endpoints")
		check(Roads.path_valid(road.map_path,provinces,road.a,road.b,{"image":image,"maximum_height":1.0}), "canonical route is legal")
	# A sea band splits a pair: no fake mainland road may be created.
	for y in range(24):
		for x in range(15,18): image.set_pixel(x,y,Color(1,1,1,0.3))
	var split := Roads.build(image,image,samples,provinces,2.0)
	for road in split.get("roads",[]):
		if road.kind == Edge.Kind.LAND: check(not (road.a == 0 and road.b == 1), "sea is not crossed by land")
	test_flat_diagonal_and_coast_corners()
	test_mountain_detour()
	test_actual_reuse_detour()
	test_illegal_smoothing_falls_back()
	test_shared_canonical_geometry()
	test_corner_endpoint_direction_invariance()
	test_diagonal_reuse_registration()
	test_legacy_terrain_capacity_rules()
	print("ATLAS_ROADS_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func flat_image(size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.55))
	return image

func split_provinces(size: Vector2i) -> Dictionary:
	var ids := PackedInt32Array()
	for y in range(size.y):
		for x in range(size.x):
			ids.append(0 if x < size.x / 2 else 1)
	return {"size":size,"ids":ids}

func route_context(image: Image, provinces: Dictionary, positions: Array[Vector2]) -> Dictionary:
	var size: Vector2i = provinces.size
	var points := PackedVector2Array()
	var heights := PackedFloat32Array()
	for y in range(size.y):
		for x in range(size.x):
			points.append((Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(size))
			heights.append(TerrainMapGenerator.packed_altitude(image.get_pixel(x, y)))
	var city_cells := {}
	for position in positions:
		var cell := Vector2i(position * Vector2(size))
		city_cells[cell.y * size.x + cell.x] = true
	return {"grid":size,"points":points,"heights":heights,"aspect":1.0,"km_per_height":4330.0,"options":{"image":image,"maximum_height":1.0},"city_cells":city_cells,"legal":{}}

func test_flat_diagonal_and_coast_corners() -> void:
	var size := Vector2i(16, 16)
	var image := flat_image(size)
	var provinces := split_provinces(size)
	var positions: Array[Vector2] = [Vector2(2.5, 2.5) / 16.0, Vector2(13.5, 13.5) / 16.0]
	var path := Roads._route(0, 1, positions, provinces, route_context(image, provinces, positions), {})
	check(path.size() > 2, "flat diagonal has an actual raster route")
	check(is_equal_approx(TerrainMapGenerator.metric_polyline_length(path, 1.0), sqrt(2.0) * 11.0 / 16.0), "eight-neighbor flat route follows Euclidean diagonal")
	check(Roads.path_valid(path, provinces, 0, 1, {"image":image,"maximum_height":1.0}), "flat diagonal canonical path is legal")
	var corner := flat_image(Vector2i(2, 2))
	corner.set_pixel(1, 0, Color(1, 1, 1, 0.3))
	corner.set_pixel(0, 1, Color(1, 1, 1, 0.3))
	var corner_provinces := split_provinces(Vector2i(2, 2))
	var corner_cities: Array[Vector2] = [Vector2(0.25, 0.25), Vector2(0.75, 0.75)]
	check(not Roads.path_valid(PackedVector2Array(corner_cities), corner_provinces, 0, 1, {"image":corner,"maximum_height":1.0}), "diagonal cannot cut two orthogonal sea corners")
	check(Roads._route(0, 1, corner_cities, corner_provinces, route_context(corner, corner_provinces, corner_cities), {}).is_empty(), "eight-neighbor search cannot join diagonal land islands")

func test_mountain_detour() -> void:
	var size := Vector2i(16, 16)
	var image := flat_image(size)
	for y in range(5, 11):
		for x in range(7, 10):
			image.set_pixel(x, y, Color(1, 1, 1, 0.95))
	var provinces := split_provinces(size)
	var positions: Array[Vector2] = [Vector2(2.5, 8.5) / 16.0, Vector2(13.5, 8.5) / 16.0]
	var path := Roads._route(0, 1, positions, provinces, route_context(image, provinces, positions), {})
	check(path.size() > 2, "mountain route exists")
	var high_points := 0
	for point in path:
		var pixel := Vector2i(point * Vector2(size))
		if image.get_pixelv(pixel).a > 0.8:
			high_points += 1
	check(high_points == 0, "terrain cost chooses low valley around mountain block")
	check(TerrainMapGenerator.metric_polyline_length(path, 1.0) > 11.0 / 16.0, "valley route takes meaningful detour")
	check(Roads.path_valid(path, provinces, 0, 1, {"image":image,"maximum_height":1.0}), "mountain detour stays inside its two provinces")

func test_actual_reuse_detour() -> void:
	var size := Vector2i(16, 16)
	var image := flat_image(size)
	var provinces := split_provinces(size)
	var positions: Array[Vector2] = [Vector2(2.5, 8.5) / 16.0, Vector2(13.5, 8.5) / 16.0]
	var context := route_context(image, provinces, positions)
	var direct := Roads._route(0, 1, positions, provinces, context, {})
	var direct_cost: float = context.last_route_cost
	var established: Array[Vector2i] = [Vector2i(2, 8), Vector2i(2, 7), Vector2i(2, 6)]
	for x in range(3, 14):
		established.append(Vector2i(x, 6))
	established.append(Vector2i(13, 7))
	established.append(Vector2i(13, 8))
	var reused := {}
	for i in range(established.size() - 1):
		var a := established[i].y * 16 + established[i].x
		var b := established[i + 1].y * 16 + established[i + 1].x
		reused[mini(a, b) * 256 + maxi(a, b)] = true
	var routed := Roads._route(0, 1, positions, provinces, context, reused)
	var touches_old_road := false
	for point in routed:
		if int(point.y * 16.0) == 6:
			touches_old_road = true
	check(touches_old_road, "actual A* joins a longer established road")
	check(float(context.last_route_cost) < direct_cost, "reuse discount lowers actual complete route cost")
	check(TerrainMapGenerator.metric_polyline_length(routed, 1.0) > TerrainMapGenerator.metric_polyline_length(direct, 1.0), "discount changes geometry rather than only metadata")
	check(Roads.path_valid(routed, provinces, 0, 1, {"image":image,"maximum_height":1.0}), "reused detour remains legal")

func test_illegal_smoothing_falls_back() -> void:
	var size := Vector2i(12, 12)
	var image := flat_image(size)
	image.fill(Color(1, 1, 1, 0.3))
	for x in range(2, 9):
		image.set_pixel(x, 2, Color(1, 1, 1, 0.55))
	for y in range(2, 10):
		image.set_pixel(8, y, Color(1, 1, 1, 0.55))
	var provinces := split_provinces(size)
	var raw := PackedVector2Array([Vector2(2.5, 2.5) / 12.0, Vector2(8.5, 2.5) / 12.0, Vector2(8.5, 9.5) / 12.0])
	var options := {"image":image,"maximum_height":1.0}
	check(Roads.path_valid(raw, provinces, 0, 1, options), "one-pixel coastal L corridor supports original route")
	for rounds in [1, 2, 3]:
		check(not Roads.path_valid(Roads.chaikin(raw, rounds), provinces, 0, 1, options), "Chaikin round %d would cut coastal water" % rounds)
	var roads: Array[Dictionary] = [{"a":0,"b":1,"map_path":raw}]
	Roads._smooth_network(roads, provinces, options, image, 1.0)
	check(roads[0].map_path == raw, "invalid rounds fall back to complete unsmoothed canonical route")
	check(roads[0].map_path[0] == raw[0] and roads[0].map_path[-1] == raw[-1], "fallback retains city endpoints")
	# Coarse sampling can miss this narrow shoreline corridor. Fine fallback
	# must retain valid turns when shortcut simplification would cut a sea corner.
	var coarse := split_provinces(Vector2i(4, 4))
	var validator_options := {"image":image,"maximum_height":1.0}
	var fine_options := {"image":image,"aspect":1.0,"maximum_height":1.0,"segment_validator":func(a: Vector2, b: Vector2, left: int, right: int) -> bool:
		return Roads.path_valid(PackedVector2Array([a, b]), coarse, left, right, validator_options)}
	var fine := Roads.PixelRoute.find(coarse.ids, coarse.size, raw[0], raw[-1], 0, 1, fine_options)
	check(fine.size() >= 3, "fine fallback finds the narrow L corridor")
	check(Roads.path_valid(fine, coarse, 0, 1, validator_options), "fine route simplification retains every sea-corner constraint")
	check(fine[0] == raw[0] and fine[-1] == raw[-1] if fine.size() >= 2 else false, "fine fallback keeps exact city endpoints")

func test_shared_canonical_geometry() -> void:
	var size := Vector2i(16, 16)
	var image := flat_image(size)
	var ids := PackedInt32Array()
	for y in range(16):
		for x in range(16):
			ids.append(0 if x < 8 else (1 if y < 7 else 2))
	var provinces := {"size":size,"ids":ids}
	var trunk := PackedVector2Array([Vector2(2.5, 7.5) / 16.0, Vector2(4.5, 7.5) / 16.0, Vector2(4.5, 4.5) / 16.0, Vector2(7.5, 4.5) / 16.0])
	var first := trunk.duplicate()
	first.append(Vector2(10.5, 4.5) / 16.0)
	var second := trunk.duplicate()
	second.append(Vector2(7.5, 9.5) / 16.0)
	second.append(Vector2(10.5, 9.5) / 16.0)
	var roads: Array[Dictionary] = [{"a":0,"b":1,"map_path":first},{"a":0,"b":2,"map_path":second}]
	var options := {"image":image,"maximum_height":1.0}
	Roads._smooth_network(roads, provinces, options, image, 1.0)
	var prefixes: Array[PackedVector2Array] = []
	for road in roads:
		var prefix := PackedVector2Array()
		for point in road.map_path:
			prefix.append(point)
			if point.is_equal_approx(trunk[-1]):
				break
		prefixes.append(prefix)
		check(Roads.path_valid(road.map_path, provinces, road.a, road.b, options), "shared canonical road valid for its own province pair")
	check(prefixes[0].size() > trunk.size(), "shared trunk actually smoothed")
	check(prefixes[0] == prefixes[1], "both complete edges carry identical smoothed shared trunk")
	check(roads[0].map_path[-1] == first[-1] and roads[1].map_path[-1] == second[-1], "shared trunk keeps both distinct destinations")

func test_corner_endpoint_direction_invariance() -> void:
	var size := Vector2i(4, 4)
	var image := flat_image(size)
	image.set_pixel(1, 0, Color(1, 1, 1, 0.3))
	var a := Vector2(3.5, 0.5) / 4.0
	var b := Vector2(2.0, 1.0) / 4.0
	var forward := Roads._safe_segment(a, b, {"image":image,"maximum_height":1.0})
	var backward := Roads._safe_segment(b, a, {"image":image,"maximum_height":1.0})
	check(forward == backward, "grid-corner endpoint legality is independent of traversal direction")
	var forward_cells := Roads.supercover(a, b, size)
	var reverse_cells := Roads.supercover(b, a, size)
	var forward_set := {}
	var reverse_set := {}
	for cell in forward_cells:
		forward_set[cell] = true
	for cell in reverse_cells:
		reverse_set[cell] = true
	check(forward_set == reverse_set, "supercover visits the same physical cells in either direction")
	var overrun := false
	for cell in forward_cells:
		if cell.x < 1 or cell.y > 1:
			overrun = true
	check(not overrun, "negative-axis endpoint does not continue past t=1")

func test_diagonal_reuse_registration() -> void:
	var registration: Script = load("res://scripts/core/atlas_road_network.gd")
	check(registration.has_method("_register_reuse"), "actual-path reuse registration is available")
	if not registration.has_method("_register_reuse"):
		return
	var size := Vector2i(8, 8)
	var actual := PackedVector2Array([Vector2(2.5, 2.5) / 8.0, Vector2(3.5, 3.5) / 8.0])
	var registered := {}
	registration.call("_register_reuse", actual, size, registered)
	var from := 2 * 8 + 2
	var to := 3 * 8 + 3
	check(registered.has(from * 64 + to), "actual diagonal road receives its own reuse discount")
	check(registered.size() == 1, "supercover corner-check cells do not create phantom reusable segments")
	var long_diagonal := PackedVector2Array([Vector2(1.5, 1.5) / 8.0, Vector2(4.5, 4.5) / 8.0])
	registered = {}
	registration.call("_register_reuse", long_diagonal, size, registered)
	check(registered.size() == 3, "long diagonal records three physical grid steps")
	for i in range(1, 4):
		from = i * 8 + i
		to = (i + 1) * 8 + i + 1
		check(registered.has(from * 64 + to), "long diagonal retains physical step %d" % i)
	# Use a route produced by the real A* and register it through the same
	# public module helper used by build. Every step should then cost half.
	size = Vector2i(16, 16)
	var image := flat_image(size)
	var provinces := split_provinces(size)
	var positions: Array[Vector2] = [Vector2(2.5, 2.5) / 16.0, Vector2(13.5, 13.5) / 16.0]
	var context := route_context(image, provinces, positions)
	var fresh := Roads._route(0, 1, positions, provinces, context, {})
	var fresh_cost: float = context.last_route_cost
	registered = {}
	registration.call("_register_reuse", fresh, size, registered)
	var reused := Roads._route(0, 1, positions, provinces, context, registered)
	check(reused == fresh, "registering the diagonal keeps the actual established route")
	check(is_equal_approx(float(context.last_route_cost), fresh_cost * 0.5), "real registered diagonal route receives complete 0.5 cost discount")

func test_legacy_terrain_capacity_rules() -> void:
	# Reverse terrain order deliberately; applying relative rules must not
	# reorder the main-first network nor overwrite canonical route distances.
	var roads: Array[Dictionary] = []
	for i in range(19, -1, -1):
		roads.append({"a":i,"b":i+1,"height_difference":i*0.01,"terrain_connector":false,"backbone":i%3==0 or i==19,"road_tier":Edge.RoadTier.MAIN if i%2==0 else Edge.RoadTier.LOCAL,"distance":100+i,"length":1.0+i*0.01})
	var original := roads.duplicate(true)
	Roads._apply_legacy_terrain_rules(roads)
	var standard := 0
	var low := 0
	var blocked := 0
	var closed_backbone := 0
	var danger_errors := 0
	var mutated_geometry := 0
	var reordered := 0
	for i in range(roads.size()):
		var road := roads[i]
		if road.base_max_manpower == Edge.TERRAIN_STANDARD_MANPOWER:
			standard += 1
		elif road.base_max_manpower == Edge.TERRAIN_LOW_MANPOWER:
			low += 1
		if road.max_manpower == 0:
			blocked += 1
			if road.backbone:
				closed_backbone += 1
		if not is_equal_approx(float(road.danger), float(road.a) / 19.0):
			danger_errors += 1
		if road.distance != original[i].distance or road.length != original[i].length:
			mutated_geometry += 1
		if road.a != original[i].a or road.b != original[i].b:
			reordered += 1
	check(standard == 5 and low == 15, "legacy terrain allocation retains 25 percent standard and 75 percent low base capacity")
	check(blocked == 2, "legacy rules close 10 percent non-backbone roads")
	check(closed_backbone == 0, "relative terrain closure never closes the connectivity skeleton")
	check(danger_errors == 0, "danger follows relative terrain percentile")
	check(mutated_geometry == 0, "capacity classification never rewrites measured distance or length")
	check(reordered == 0, "capacity classification preserves existing network record order")
	var different_tiers: Array[Dictionary] = original.duplicate(true)
	for road in different_tiers:
		road.road_tier = Edge.RoadTier.LOCAL if road.road_tier == Edge.RoadTier.MAIN else Edge.RoadTier.MAIN
	Roads._apply_legacy_terrain_rules(different_tiers)
	var tier_changes_physics := 0
	for i in range(roads.size()):
		for key in ["max_manpower", "base_max_manpower", "danger", "distance"]:
			if roads[i][key] != different_tiers[i][key]:
				tier_changes_physics += 1
	check(tier_changes_physics == 0, "main/local road drawing tier cannot change capacity danger or distance")
	# Even the nominal best quarter must stay low-capacity when every route
	# is a high-relief terrain connector. Preserve all-backbone connectivity.
	var highland: Array[Dictionary] = []
	for i in range(4):
		highland.append({"a":i,"b":i+1,"height_difference":0.25+i*0.05,"terrain_connector":true,"backbone":true,"road_tier":Edge.RoadTier.MAIN,"distance":50+i})
	Roads._apply_legacy_terrain_rules(highland)
	var connector_errors := 0
	for i in range(highland.size()):
		if highland[i].max_manpower != Edge.TERRAIN_LOW_MANPOWER or highland[i].base_max_manpower != Edge.TERRAIN_LOW_MANPOWER or highland[i].distance != 50+i:
			connector_errors += 1
	check(connector_errors == 0, "all high-relief connectors retain low capacity and complete canonical distance")
