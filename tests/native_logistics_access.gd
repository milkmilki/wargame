extends SceneTree
const Fixture = preload("res://tests/support/native_runtime_fixture.gd")
class CustomState extends GameState:
	var access_calls := 0
	func has_logistics_access(traveler: int, owner: int) -> bool:
		access_calls += 1
		return traveler == owner
var checks:=0
var failures:=0
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures+=1;printerr("LOGISTICS_ACCESS_FAIL ",message)
func oracle(travelers: PackedInt64Array,owners: PackedInt64Array,identities: PackedByteArray,relations: Dictionary,allied: int=2,missing: int=1) -> Array:
	var rows: Array=[]
	for traveler in travelers:
		var row:=PackedByteArray()
		for owner in owners:
			var allowed:=traveler==owner
			if not allowed and traveler>=0 and owner>=0 and traveler<identities.size() and owner<identities.size() and identities[traveler]==0 and identities[owner]==0:
				allowed=int(relations.get("%d:%d"%[mini(traveler,owner),maxi(traveler,owner)],missing))==allied
			row.append(int(allowed))
		rows.append(row)
	return rows
func run():
	var graph:RefCounted=ClassDB.instantiate("NativeGraphSnapshot")
	if graph==null or not graph.has_method("query_logistics_access"):
		check(false,"native logistics access matrix is registered");finish();return
	var random:=RandomNumberGenerator.new();random.seed=80691
	for size in [0,1,8,32,64]:
		var identities:=PackedByteArray();identities.resize(size)
		var relations:Dictionary={}
		for a in range(size):
			identities[a]=int(random.randf()<.2)
			for b in range(a+1,size):relations["%d:%d"%[a,b]]=random.randi_range(0,2)
		for count in [0,1,16,64]:
			var travelers:=PackedInt64Array()
			var owners:=PackedInt64Array()
			var extremes: Array=[-1,-(1<<35),1<<35,9223372036854775807,0,size-1,size]
			for index in range(count):
				travelers.append(extremes[index%extremes.size()] if index%3==0 else random.randi_range(-1,size))
				owners.append(extremes[(index+1)%extremes.size()] if index%4==0 else random.randi_range(-1,size))
			for codes in [[2,1],[1,2],[2,2]]:
				var result:Dictionary=graph.call("query_logistics_access",travelers,owners,identities,relations,codes[0],codes[1])
				check(bool(result.get("supported",false)) and var_to_bytes(result.get("rows"))==var_to_bytes(oracle(travelers,owners,identities,relations,codes[0],codes[1])),"exact ordered matrix, nations=%d requests=%d"%[size,count])
	var travelers:=PackedInt64Array([0,1,0,-1])
	var owners:=PackedInt64Array([1,0,1,-1])
	var identities:=PackedByteArray([0,0])
	var relations:Dictionary={"0:1":2}
	for value in [0,1,2]:
		relations["0:1"]=value
		check(var_to_bytes(graph.call("query_logistics_access",travelers,owners,identities,relations,2,1).rows)==var_to_bytes(oracle(travelers,owners,identities,relations)),"direct diplomacy changes and duplicate IDs remain live")
	identities[1]=1
	check(var_to_bytes(graph.call("query_logistics_access",travelers,owners,identities,relations,2,1).rows)==var_to_bytes(oracle(travelers,owners,identities,relations)),"unresolved succession identity rejects foreign alliances but retains self access")
	identities[1]=0
	for value in [2.0,"2",true,null]:
		relations["0:1"]=value
		check(graph.call("query_logistics_access",travelers,owners,identities,relations,2,1)=={"supported":false},"nonscalar relationship representation delegates to the script callback")
	var large := PackedInt64Array(); large.resize(65536)
	check(graph.call("query_logistics_access", large, large, PackedByteArray(), {}, 2, 1).has("error"), "oversized matrix is rejected before allocation")
	adapter_cases()
	finish()

func fixture(custom: bool = false) -> GameState:
	var state: GameState = CustomState.new() if custom else GameState.new()
	state._reset_world(80691)
	state._generate_nations(GameState.DiplomaticRelation.ALLIED, 6, false)
	state.atlas_layout = {"test": true}
	for id in range(6):
		var city := City.new(); city.id = id; city.owner_nation = id
		city.food_storage = 10000; city.has_warehouse = true
		state.cities.append(city)
		state.nations[id].capital_city_id = id
		state.nations[id].warehouse_city_ids = [id] as Array[int]
		var army := Army.new(); army.id = id; army.owner_nation = id
		army.location_city = id; army.size = 1000; state.armies.append(army)
	return state

func compare_state(state: GameState, travelers: Array[int], label: String) -> void:
	var before := var_to_bytes(Fixture.snapshot(state))
	var reference := {}
	for traveler in travelers:
		var row := PackedByteArray()
		for nation in state.nations: row.append(int(state.has_logistics_access(traveler, nation.id)))
		reference[traveler] = row
	var warehouses := SupplyRules.warehouse_availability(state, {})
	var owners := SupplyRules.network_owner_rows(state, warehouses, {})
	for mode in ["native", "compare"]:
		NativeCompute.set_backend_for_tests(mode)
		var rows := NativeCompute.logistics_access_rows(state, travelers)
		check(var_to_bytes(rows) == var_to_bytes(reference), label + " " + mode + " exact permission rows")
		for traveler in travelers:
			if traveler < 0 or traveler >= state.nations.size(): continue
			check(var_to_bytes(SupplyRules.network_fingerprint(state, traveler, warehouses, {8: true, 2: true}, {}, owners, rows[traveler])) == var_to_bytes(SupplyRules.network_fingerprint(state, traveler, warehouses, {8: true, 2: true}, {}, owners)), label + " exact complete fingerprint")
	check(var_to_bytes(Fixture.snapshot(state)) == before, label + " preserves gameplay state and RNG")

func adapter_cases() -> void:
	var state := fixture()
	var travelers: Array[int] = [0, 1, 2, 3, 4, 5, 0, -1, 1 << 40]
	compare_state(state, travelers, "canonical allies")
	state.nations[2].succession_identity = true
	state.nations[3].succession_identity = true
	var conflict := SuccessionConflict.new(); conflict.nation_id = 0; conflict.rebel_nation_id = 2
	state.succession_conflicts[0] = conflict
	compare_state(state, travelers, "resolved and unresolved succession identities")
	conflict.nation_id = 1
	compare_state(state, travelers, "financial root changed without revision")
	for root_id in [-1, 1 << 40]:
		conflict.nation_id = root_id
		compare_state(state, travelers, "invalid financial root %d" % root_id)
	conflict.nation_id = 1
	state.diplomatic_relations["0:1"] = GameState.DiplomaticRelation.WAR
	state.diplomatic_relations.erase("0:4")
	compare_state(state, travelers, "direct diplomacy edits and missing relations")
	for value in [2.0, "2"]:
		state.diplomatic_relations["0:1"] = value
		check(NativeCompute.logistics_access_rows(state, travelers).is_empty(), "converted relation value retains script path")
	state.diplomatic_relations["0:1"] = GameState.DiplomaticRelation.ALLIED
	NativeCompute.set_backend_for_tests("gdscript")
	check(NativeCompute.logistics_access_rows(state, travelers).is_empty(), "script backend retains callbacks")
	NativeCompute.set_backend_for_tests("native")
	check(NativeCompute.logistics_access_rows(state, [] as Array[int]).is_empty(), "empty batch")
	state.atlas_layout.clear()
	check(NativeCompute.logistics_access_rows(state, travelers).is_empty(), "legacy world retains callbacks")
	state.atlas_layout = {"test": true}
	var custom := fixture(true) as CustomState
	check(NativeCompute.logistics_access_rows(custom, travelers).is_empty() and custom.access_calls == 0, "custom state is delegated before native queries")
	var expected := SupplyRules.network_fingerprint(custom, 0, {}, {}, {})
	custom.access_calls = 0
	check(var_to_bytes(SupplyRules.network_fingerprint(custom, 0, {}, {}, {}, {}, PackedByteArray([1]))) == var_to_bytes(expected) and custom.access_calls == 6, "wrong-width row retains custom callbacks")
	var sim := Simulation.new(); sim.state = state
	NativeCompute.set_profiling_for_tests(true)
	sim._prepare_supply_network_caches()
	check(int(NativeCompute.profile_snapshot().get("logistics_access_native_call_count", 0)) == 1, "one native permission matrix for the complete supply pass")
	check(sim._prepared_supply_access_rows.is_empty(), "permission rows are discarded before workers")
	var warehouses := SupplyRules.warehouse_availability(state, {})
	var owner_rows := SupplyRules.network_owner_rows(state, warehouses, {})
	for nation in state.nations:
		var fp := SupplyRules.network_fingerprint(state, nation.id, warehouses, {}, {}, owner_rows)
		fp.append(1)
		check(var_to_bytes(sim._supply_network_fingerprints[nation.id]) == var_to_bytes(fp), "supply preparation retains full fingerprint bytes")
	state.diplomatic_relations["0:1"] = GameState.DiplomaticRelation.WAR
	check(var_to_bytes(sim._supply_network_fingerprint(0, warehouses, {}, {}, owner_rows)) == var_to_bytes(SupplyRules.network_fingerprint(state, 0, warehouses, {}, {}, owner_rows)), "standalone fingerprint sees post-batch diplomacy edits")
	sim._prepared_supply_access_rows[0] = PackedByteArray([1, 1, 1, 1, 1, 1])
	state.atlas_layout.clear()
	sim.setup(state)
	check(sim._prepared_supply_access_rows.is_empty(), "world setup clears temporary permission rows")
	NativeCompute.set_profiling_for_tests(false)
	sim.free()
	NativeCompute.set_backend_for_tests("native")
func finish():
	print("NATIVE_LOGISTICS_ACCESS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
