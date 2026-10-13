extends SceneTree
## Presentation caches must retain Edge's distance parametrization without
## changing the simulation model, including geometry edits and longitude copies.
const CACHE_PATH := "res://scripts/atlas/military_marker_state.gd"
var failures := 0
var checks := 0
var cache_script: Script

func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("MILITARY_CACHE_FAIL ", message)
func near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < .003
func fixture() -> GameState:
	var state := GameState.new(); state.rng.seed = 8124
	for point in [Vector2(.1,.3), Vector2(.75,.4)]:
		var city := City.new(); city.id = state.cities.size(); city.map_position = point
		state.cities.append(city)
	var edge := Edge.new(); edge.city_a = 0; edge.city_b = 1
	state.edges.append(edge); state.edge_lookup[GameState.edge_key(0,1)] = edge
	var army := Army.new(); army.id = 44; army.size = 15000; army.owner_nation = 0
	army.on_edge = true; army.move_from = 0; army.move_to = 1; army.location_city = 0
	state.armies.append(army)
	return state
func source_signature(state: GameState) -> Array:
	var army: Army = state.armies[0]
	var edge: Edge = state.edges[0]
	return [state.rng.state, state.road_network_revision, state.cities[0].map_position,
		state.cities[1].map_position, edge.map_path.duplicate(), edge.spherical_path,
		army.id, army.size, army.state, army.path.duplicate(), army.on_edge,
		army.location_city, army.move_from, army.move_to, army.move_progress]
func expected(state: GameState, army: Army) -> Vector2:
	if not army.on_edge:
		return state.cities[army.location_city].map_position * Vector2(2048,1024)
	var edge: Edge = state.edge_of(army.move_from,army.move_to)
	return edge.map_position_at(army.move_progress if army.move_from == edge.city_a else 1. - army.move_progress,
		state.cities[edge.city_a].map_position, state.cities[edge.city_b].map_position, 2.) * Vector2(2048,1024)
func run():
	if not FileAccess.file_exists(CACHE_PATH):
		check(false, "the presentation path cache is missing")
		finish(); return
	cache_script = load(CACHE_PATH)
	if cache_script == null:
		check(false, "the presentation path cache loads")
		finish(); return
	var cache = cache_script.new()
	check(cache.has_method("position") and cache_script.has_method("visible_copies"), "cache exposes position and visible copy queries")
	if not cache.has_method("position") or not cache_script.has_method("visible_copies"):
		finish(); return
	for spherical in [false, true]:
		for points in [PackedVector2Array(),
			PackedVector2Array([Vector2(.1,.3),Vector2(.11,.6),Vector2(.7,.7),Vector2(.75,.4)]),
			PackedVector2Array([Vector2(.98,.2),Vector2(1.02,.25),Vector2(1.08,.4)]),
			PackedVector2Array([Vector2(.1,.3),Vector2(.1,.3),Vector2(.4,.6),Vector2(.75,.4)]),
			PackedVector2Array([Vector2(.2,.4),Vector2(.2,.4),Vector2(.2,.4)])]:
			var state := fixture(); state.edges[0].map_path = points; state.edges[0].spherical_path = spherical
			for backwards in [false,true]:
				var army: Army = state.armies[0]; army.move_from = 1 if backwards else 0; army.move_to = 0 if backwards else 1
				for progress in [-.1, 0., .01, .25, .5, .99, 1., 1.2]:
					army.move_progress = progress
					var before := source_signature(state)
					check(near(cache.position(state,army),expected(state,army)), "cached road position matches real distance parametrization spherical=%s backwards=%s progress=%s" % [spherical,backwards,progress])
					check(source_signature(state) == before, "position lookup does not mutate model geometry, movement or RNG")
	test_path_reuse_and_edits(cache)
	test_world_copies()
	finish()
func test_path_reuse_and_edits(cache):
	var state := fixture(); var edge: Edge = state.edges[0]; var army: Army = state.armies[0]
	edge.map_path = PackedVector2Array([Vector2(.1,.3),Vector2(.11,.6),Vector2(.75,.4)])
	army.move_progress = .37; cache.position(state,army)
	var builds := int(cache.get("build_count"))
	for i in range(40):
		army.move_progress = float(i) / 39.
		check(near(cache.position(state,army),expected(state,army)), "movement updates retain accurate cached distance interpolation")
	check(int(cache.get("build_count")) == builds, "movement does not rebuild unchanged road lengths")
	var same_road := Army.new(); same_road.id = 95; same_road.on_edge = true
	same_road.move_from = 1; same_road.move_to = 0; same_road.move_progress = .63
	check(near(cache.position(state,same_road),expected(state,same_road)), "a second formation shares the reverse route metric")
	check(int(cache.get("build_count")) == builds, "formations on one road share the cached path lengths")
	army.move_progress = .37
	var previous: Vector2 = cache.position(state,army)
	edge.map_path = PackedVector2Array([Vector2(.1,.3),Vector2(.65,.9),Vector2(.75,.4)])
	check(near(cache.position(state,army),expected(state,army)) and not near(cache.position(state,army),previous), "replacing a road path invalidates its cached position without a capacity revision")
	previous = cache.position(state,army); edge.map_path[1] = Vector2(.18,.8)
	check(near(cache.position(state,army),expected(state,army)) and not near(cache.position(state,army),previous), "editing an existing road vertex invalidates its cached metric")
	edge.spherical_path = true
	check(near(cache.position(state,army),expected(state,army)), "changing distance geometry invalidates the planar metric")
	edge.map_path = PackedVector2Array()
	cache.position(state,army); state.cities[1].map_position = Vector2(.35,.9)
	check(near(cache.position(state,army),expected(state,army)), "straight road fallback follows changed city endpoints")
	var changed := fixture(); changed.cities[0].map_position = Vector2(.3,.7); changed.armies[0].move_progress = .37
	check(near(cache.position(changed,changed.armies[0]),expected(changed,changed.armies[0])), "a different world with reused army IDs cannot reuse prior positions")
	army.on_edge = false; army.location_city = 1
	check(near(cache.position(state,army),state.cities[1].map_position * Vector2(2048,1024)), "arrival switches from the cached road to the actual city")
func test_world_copies():
	for input in [
		[Vector2(2040,100),Rect2(-20,80,40,40),0.],
		[Vector2(-8,100),Rect2(-20,80,40,40),0.],
		[Vector2(80,100),Rect2(6100,80,200,40),0.],
		[Vector2(80,100),Rect2(-4100,80,10300,40),0.],
		[Vector2(100,100),Rect2(106,90,10,20),7.],
		[Vector2(100,-20),Rect2(0,0,200,200),0.],
		[Vector2(100,100),Rect2(0,0,20,20),0.]]:
		var point: Vector2 = input[0]; var rect: Rect2 = input[1]; var padding: float = input[2]
		var out: Array = cache_script.visible_copies(point,rect,padding)
		var wanted: Array[Vector2] = []
		for shift in range(-8,9):
			var copy := Vector2(fposmod(point.x,2048.) + shift * 2048.,point.y)
			if rect.grow(padding).has_point(copy): wanted.append(copy)
		check(out.size() == wanted.size() and wanted.all(func(copy): return out.has(copy)), "only visible longitude copies are submitted, including distant seams and wide views")
		var unique := {}
		for copy in out: unique[copy] = true
		check(out.size() == unique.size(), "a world copy is never submitted twice")
func finish():
	print("ATLAS_MILITARY_MARKER_CACHE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
