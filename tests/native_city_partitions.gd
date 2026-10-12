extends SceneTree
class CustomState extends GameState:
	func is_external_enemy(_a: int, _b: int) -> bool: return false
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("CITY_PARTITIONS_FAIL ", label)
func oracle(cities: Array[City], ids: PackedInt64Array, owners: PackedInt64Array, traffic: PackedByteArray, actor: int, relations: Dictionary, visible: Dictionary, limited: bool) -> Dictionary:
	var friendly: Array[City] = []; var enemy: Array[City] = []
	var allied: Array[City] = []; var neutral: Array[City] = []
	for index in range(cities.size()):
		if traffic[index]: continue
		if owners[index] == actor: friendly.append(cities[index])
		elif limited and not visible.has(ids[index]): continue
		else:
			match relations.get(owners[index], 0):
				1: enemy.append(cities[index])
				2: allied.append(cities[index])
				_: neutral.append(cities[index])
	return {"friendly": friendly, "enemy": enemy, "allied": allied, "neutral": neutral}
func run():
	var graph: RefCounted = ClassDB.instantiate("NativeGraphSnapshot")
	if graph == null or not graph.has_method("query_city_partitions"):
		check(false, "native city partition query is registered"); finish(); return
	var random := RandomNumberGenerator.new(); random.seed = 75491
	for count in [0, 1, 16, 64, 1192]:
		var cities: Array[City] = []
		var ids := PackedInt64Array(); var owners := PackedInt64Array(); var traffic := PackedByteArray()
		var visible := {}; var relations := {-1: 1, 0: 0, 1: 2, 2: 1, 1 << 40: 2}
		for index in range(count):
			var city := City.new(); city.id = index
			cities.append(cities[0] if index % 11 == 1 else city)
			ids.append((1 << 54) + index % 7 if index % 5 == 0 else index % 17)
			owners.append(1 << 40 if index % 13 == 0 else random.randi_range(-1, 4))
			traffic.append(int(index % 3 == 0))
			if index % 2: visible[ids[index]] = true
		for actor in [-1, 0, 1, 1 << 40]:
			for limited in [false, true]:
				var expected := oracle(cities, ids, owners, traffic, actor, relations, visible, limited)
				var actual: Dictionary = graph.call("query_city_partitions", cities, ids, owners, traffic, actor, relations, visible, limited)
				check(var_to_bytes(actual) == var_to_bytes(expected), "exact ordered typed city groups")
				for key in actual:
					check(actual[key].get_typed_script() == cities.get_typed_script(), "group retains City array type")
		check(graph.call("query_city_partitions", cities, PackedInt64Array([1]), owners, traffic, 0, {}, {}, false).has("error") == (count != 1), "mismatched input lengths are rejected")
	integration()
	finish()

func view_bytes(view: AiWorldView) -> PackedByteArray:
	return var_to_bytes([view.friendly_cities, view.enemy_cities, view.allied_cities, view.neutral_cities])

func integration():
	var state := GameState.new(); state._reset_world(75491)
	state._generate_nations(GameState.DiplomaticRelation.WAR, 4, false)
	state.atlas_layout = {"test": true}
	for index in range(64):
		var city := City.new(); city.id = index; city.owner_nation = index % 4
		city.map_position = Vector2(float(index % 8)/8., float(index/8)/8.)
		if index % 7 == 0: city.node_kind = City.NodeKind.TRAFFIC
		state.cities.append(city)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.NEUTRAL)
	state.nations[3].succession_identity = true
	var before := var_to_bytes(preload("res://tests/support/native_runtime_fixture.gd").snapshot(state))
	for mode in ["native", "compare"]:
		NativeCompute.set_backend_for_tests(mode)
		var shared := AiWorldView.build_army_index(state)
		shared["city_partition_inputs"] = NativeCompute.city_partition_inputs(state)
		for actor in range(4):
			var expected := AiWorldView.build(state, actor)
			NativeCompute.set_profiling_for_tests(true)
			var cache := {}
			var actual := AiWorldView.build(state, actor, {}, {}, cache, shared)
			check(view_bytes(actual) == view_bytes(expected), "complete sorted view keeps city identities and order")
			check(int(NativeCompute.profile_snapshot().get("city_partitions_native_call_count",0)) == 1, "one native classification for a cold view")
			actual = AiWorldView.build(state, actor, {}, {}, cache, shared)
			check(view_bytes(actual) == view_bytes(expected) and int(NativeCompute.profile_snapshot().get("city_partitions_native_call_count",0)) == 1, "warm partition cache retains exact view without another native call")
			NativeCompute.set_profiling_for_tests(false)
		var visible := {1: true, 6: true, 13: false}
		var groups := NativeCompute.city_partitions(state,0,shared["city_partition_inputs"],visible,true)
		var inputs: Dictionary = shared["city_partition_inputs"]
		var relations := {1:2,2:0,3:0}
		check(var_to_bytes(groups) == var_to_bytes(oracle(state.cities, inputs.ids, inputs.owners, inputs.traffic, 0, relations, visible, true)), "limited visibility keeps own cities and excludes foreign hidden cities")
	check(before == var_to_bytes(preload("res://tests/support/native_runtime_fixture.gd").snapshot(state)), "grouping leaves gameplay and RNG unchanged")
	state.cities[5].owner_nation = 2; state.cities[6].node_kind = City.NodeKind.TRAFFIC
	var fresh := NativeCompute.city_partition_inputs(state)
	check(fresh.owners[5] == 2 and fresh.traffic[6] == 1, "new phase reads direct city edits without revision changes")
	NativeCompute.set_backend_for_tests("gdscript")
	check(NativeCompute.city_partition_inputs(state).is_empty(), "reference backend retains script classification")
	NativeCompute.set_backend_for_tests("native")
	var custom := CustomState.new(); custom.atlas_layout = {"test":true}
	check(NativeCompute.city_partition_inputs(custom).is_empty(), "custom diplomacy callbacks retain script classification")
	state.atlas_layout.clear()
	check(NativeCompute.city_partition_inputs(state).is_empty(), "legacy worlds retain script classification")
func finish():
	print("NATIVE_CITY_PARTITIONS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
