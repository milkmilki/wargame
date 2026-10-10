extends SceneTree

class CountState extends "res://tests/support/grid_world.gd":
	var capacity_queries := 0
	func manpower_pool_capacity(nation_id: int) -> int:
		capacity_queries += 1
		return super.manpower_pool_capacity(nation_id)
	func food_storage_capacity(nation_id: int) -> int:
		capacity_queries += 1
		return super.food_storage_capacity(nation_id)

class ProxyState extends CountState:
	func financial_nation_of(nation_id: int) -> int:
		return 0 if nation_id == 3 else super.financial_nation_of(nation_id)

var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures.append(message)
func verify_capacities(state: GameState, label: String):
	var capacities: Dictionary = state.call("base_resource_capacities")
	for nation in state.nations:
		check(capacities.manpower[nation.id] == state.manpower_pool_capacity(nation.id), label+": manpower%d" % nation.id)
		check(capacities.food[nation.id] == state.food_storage_capacity(nation.id), label+": food%d" % nation.id)
func run():
	var state := CountState.new(); state.generate_world(1,4,24)
	state.capacity_queries = 0
	state.clamp_resource_capacities()
	check(state.capacity_queries == 0, "monthly clamp does not repeat per-country city scans")
	check(state.has_method("base_resource_capacities"), "capacity batch API exists")
	check(state.has_method("add_manpower_batch"), "monthly admission batch API exists")
	if not state.has_method("base_resource_capacities") or not state.has_method("add_manpower_batch"):
		finish(); return
	for seed_value in [1,7,2024]:
		for mutation in ["plain","vassal","civil_war","cycle","production","proxy"]:
			var actual := ProxyState.new() if mutation == "proxy" else CountState.new()
			var expected := ProxyState.new() if mutation == "proxy" else CountState.new()
			for world in [actual,expected]:
				world.generate_world(seed_value,4,24)
				if mutation in ["vassal","civil_war","cycle"]:
					world.suzerainty[1] = {"overlord_id":0,"tribute_rate":.25,"civil_war":false}
					world.suzerainty[2] = {"overlord_id":1,"tribute_rate":.25,"civil_war":mutation=="civil_war"}
					if mutation == "cycle": world.suzerainty[0] = {"overlord_id":2,"tribute_rate":.25,"civil_war":false}
				if mutation == "production":
					world.cities[0].manpower_per_month = 1 << 33
					world.cities[1].food_per_half_year = 1 << 33
					world.cities[2].is_dock = true
					world.cities[3].manpower_per_month = -10
					world.cities[4].food_per_half_year = -10
					world.cities[5].node_kind = City.NodeKind.TRAFFIC
					world.cities[6].politically_active = false
					world.cities[7].owner_nation = -1
				world.nations[3].alive = false
				for nation in world.nations: nation.manpower_pool = world.manpower_pool_capacity(nation.id) - 5
			verify_capacities(actual,"%d/%s" % [seed_value,mutation])
			var amounts: Array[int] = [100,0,-10,1 << 34]
			var accepted: Array[int] = []
			for nation in expected.nations: accepted.append(expected.add_manpower(nation.id,amounts[nation.id]))
			actual.capacity_queries = 0
			check(actual.call("add_manpower_batch",amounts) == accepted,"batch admission retains scalar amounts and order")
			check(actual.capacity_queries == 0,"batch admission avoids scalar capacity scans")
			check(var_to_bytes(NativeSnapshotBuilder.build(actual)) == var_to_bytes(NativeSnapshotBuilder.build(expected)),"entire state matches scalar admission")
			# Change output and ownership directly without a revision bump: batches are fresh.
			for world in [actual,expected]:
				world.cities[0].owner_nation = 2; world.cities[0].manpower_per_month = 13
				world.cities[0].food_per_half_year = 23
				for nation in world.nations: nation.manpower_pool = 1 << 40
				for city in world.cities:
					if city.has_warehouse: city.food_storage = 1 << 40
				world.refresh_derived()
			verify_capacities(actual,"fresh"+mutation)
			legacy_clamp(expected)
			actual.clamp_resource_capacities()
			check(var_to_bytes(NativeSnapshotBuilder.build(actual)) == var_to_bytes(NativeSnapshotBuilder.build(expected)),"entire clamp state matches legacy, including warehouse withdrawal")
	var empty := GameState.new()
	check(empty.call("base_resource_capacities") == {"manpower":[] as Array[int],"food":[] as Array[int]},"empty world capacity arrays")
	check(empty.call("add_manpower_batch",[] as Array[int]).is_empty(),"empty admission")
	empty.clamp_resource_capacities()
	finish()
func legacy_clamp(state: GameState):
	var changed := false
	for nation in state.nations:
		nation.manpower_pool = clampi(nation.manpower_pool,0,state.manpower_pool_capacity(nation.id))
		if state.food_pool_holder(nation.id) != nation.id: continue
		var excess := state._food_pool_stock(nation.id) - state.food_storage_capacity(nation.id)
		if excess > 0:
			state._withdraw_food_from_warehouses(nation,excess); changed = true
	if changed: state.refresh_derived()
func finish():
	for failure in failures: printerr("RESOURCE_CAPACITY_BATCH_FAIL ",failure)
	print("RESOURCE_CAPACITY_BATCH_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
