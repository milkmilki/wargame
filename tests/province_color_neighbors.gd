extends SceneTree
class CountingState extends GameState:
	var submissions := 0
	func _add_province_neighbor_pair(a: int, b: int, seen: Dictionary) -> void:
		submissions += 1
		super._add_province_neighbor_pair(a,b,seen)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures.append(label)
func oracle(state: GameState) -> Array[Vector2i]:
	var pairs := {}
	for y in range(state.province_map_size.y):
		for x in range(state.province_map_size.x):
			var index := y * state.province_map_size.x + x
			var a := state.province_ids[index]
			for direction in [Vector2i(1,0),Vector2i(0,1)]:
				if x + direction.x >= state.province_map_size.x or y + direction.y >= state.province_map_size.y: continue
				var offset: int = direction.x + direction.y * state.province_map_size.x
				var b := state.province_ids[index + offset]
				if a >= 0 and a < state.cities.size() and b >= 0 and b < state.cities.size() and a != b:
					pairs[Vector2i(mini(a,b),maxi(a,b))] = true
	var result: Array[Vector2i] = []; result.assign(pairs.keys())
	result.sort_custom(func(a: Vector2i,b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result
func run():
	var state := CountingState.new()
	for id in range(4):
		var city := City.new(); city.id = id; state.cities.append(city)
	state.province_map_size = Vector2i(100,80)
	state.province_ids.resize(8000); state.province_ids.fill(0)
	check(state._province_neighbors_for_sovereign_colors().is_empty(), "uniform province has no self adjacency")
	check(state.submissions == 0, "uniform pixels never submit redundant self pairs")
	for mode in ["stripes","holes","checkerboard"]:
		for y in range(80):
			for x in range(100):
				var id := x / 25
				if mode == "holes" and (x + y) % 11 == 0: id = -1 if x % 2 == 0 else 99
				if mode == "checkerboard": id = (x + y) % 4
				state.province_ids[y * 100 + x] = id
		state._province_neighbor_pairs_ready = false; state.submissions = 0
		var expected := oracle(state)
		var actual := state._province_neighbors_for_sovereign_colors()
		check(actual == expected, mode + ": exact sorted adjacency including holes and row boundaries")
		if mode == "stripes": check(state.submissions == 240, "only the three real boundaries per row submit pairs")
		var calls := state.submissions
		check(state._province_neighbors_for_sovereign_colors() == expected and state.submissions == calls, mode + ": warm geometry reuses the same complete cache")
	for dimensions in [Vector2i(1,4),Vector2i(4,1)]:
		state.province_map_size = dimensions
		state.province_ids = PackedInt32Array([0,1,2,3])
		state._province_neighbor_pairs_ready = false
		check(state._province_neighbors_for_sovereign_colors() == oracle(state), str(dimensions) + ": single row or column boundaries")
	for failure in failures: printerr("PROVINCE_COLOR_NEIGHBORS_FAIL ",failure)
	print("PROVINCE_COLOR_NEIGHBORS_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
