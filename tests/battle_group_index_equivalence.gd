extends SceneTree
## Audit equivalence includes corrupt metadata: nation.id is not necessarily
## its array index, and legacy membership/lookups use those differently.
const Legacy = preload("res://tests/support/legacy_battle_group_state.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fixture() -> GameState:
	var state := GameState.new()
	state.world_seed = 77861; state.rng.seed = state.world_seed
	for index in range(2):
		var nation := Nation.new(); nation.id = index
		nation.battle_groups.append(group(index, 10 + index * 10))
		state.nations.append(nation)
		state.armies.append(army(index, index, 10 + index * 10))
	return state

func group(owner: int, id: int) -> BattleGroup:
	var result := BattleGroup.new(); result.id = id; result.owner_nation = owner
	return result

func army(id: int, owner: int, group_id: int) -> Army:
	var result := Army.new(); result.id = id; result.owner_nation = owner
	result.battle_group_id = group_id; result.size = 15000; result.max_size = 15000
	return result

func fingerprint(state: GameState) -> Array:
	return [state.rng.state,
		state.nations.map(func(n): return [n.id, n.battle_groups.map(func(g): return [g.id, g.owner_nation])]),
		state.armies.map(func(a): return [a.id, a.owner_nation, a.battle_group_id, a.size, a.max_size])]

func compare(state: GameState, label: String, expected: bool) -> void:
	var legacy := Legacy.new()
	legacy.nations = state.nations; legacy.armies = state.armies
	var before := fingerprint(state)
	var old_valid: bool = legacy._battle_group_structure_valid()
	var new_valid := state._battle_group_structure_valid()
	check(old_valid == expected, label + " old invariant expectation")
	check(new_valid == old_valid, label + " exact audit verdict preserved")
	check(before == fingerprint(state), label + " auditing leaves membership, metadata and RNG unchanged")

func run() -> void:
	compare(fixture(), "valid registered armies", true)
	var state := fixture(); state.armies.clear(); compare(state, "empty groups", true)
	state = fixture(); state.armies[0].size = 0; state.armies[0].max_size = 20000
	state.armies[0].owner_nation = -99; state.armies[0].battle_group_id = -99
	compare(state, "dead army with invalid metadata is ignored", true)
	state = fixture(); state.armies[0].size = -1; state.armies[0].max_size = 0
	compare(state, "negative size is ignored by this structural audit", true)
	state = fixture(); state.armies[0].size = 1; compare(state, "understrength valid formation", true)
	state = fixture(); state.armies[0].size = 16000; compare(state, "size cap belongs to separate invariant", true)
	state = fixture(); state.armies.append(army(2,0,10)); compare(state, "over group capacity", false)
	state = fixture(); state.armies[0].max_size = 12000; compare(state, "nonstandard formation", false)
	state = fixture(); state.armies[0].owner_nation = -1; compare(state, "negative owner", false)
	state = fixture(); state.armies[0].owner_nation = 2; compare(state, "owner outside nation array", false)
	state = fixture(); state.armies[0].battle_group_id = 999; compare(state, "unregistered group", false)
	state = fixture(); state.nations[0].battle_groups[0].id = -1
	state.armies[0].battle_group_id = -1; compare(state, "negative group never resolves", false)
	state = fixture(); state.nations[0].battle_groups.append(group(0,-1))
	compare(state, "unused negative group record", true)
	state = fixture(); state.nations[0].battle_groups.append(group(0,10))
	compare(state, "duplicate group records share same members", true)
	state.armies.append(army(2,0,10)); compare(state, "duplicate record does not add capacity", false)
	state = fixture(); state.nations[1].battle_groups[0].id = 10
	state.armies[1].battle_group_id = 10; compare(state, "same group id across distinct nations", true)
	state = fixture(); state.nations[0].battle_groups[0].owner_nation = 1
	compare(state, "legacy ignores group owner metadata", true)
	state = fixture(); state.nations[0].id = 1; state.nations[1].id = 0
	state.armies.append(army(2,0,10)); compare(state, "swapped nation ids with disjoint group ids", true)
	state = fixture(); state.nations[0].id = 1; state.nations[1].id = 0
	state.nations[1].battle_groups[0].id = 10; state.armies[1].battle_group_id = 10
	state.armies.append(army(2,0,10)); compare(state, "swapped ids with shared group id still check capacity", false)
	state = fixture(); state.nations[1].id = 0; state.armies.append(army(2,1,20))
	compare(state, "duplicate nation ids retain old skipped capacity check", true)
	state = fixture(); state.nations[0].id = 99; state.armies.append(army(2,0,10))
	compare(state, "invalid nation metadata retains index-based group lookup", true)
	state = fixture(); state.nations.clear(); compare(state, "alive armies without registered nation", false)
	state.armies.clear(); compare(state, "empty world", true)
	_real_scale()
	for failure in failures: printerr("BATTLE_GROUP_INDEX_FAIL ", failure)
	print("BATTLE_GROUP_INDEX_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _real_scale() -> void:
	var state := GameState.new()
	state.generate_from_atlas(preload("res://tests/atlas_military_inputs.gd").military())
	state.armies.clear()
	for nation in state.nations: nation.battle_groups.clear()
	for id in range(1700):
		var owner := id % state.nations.size()
		state.nations[owner].battle_groups.append(group(owner,id))
		var troop := army(id,owner,id); troop.location_city = state.nations[owner].capital_city_id
		troop.move_from = troop.location_city; state.armies.append(troop)
	compare(state,"actual Earth graph with 1700 registered armies",true)
	var legacy := Legacy.new(); legacy.nations = state.nations; legacy.armies = state.armies
	var old_times: Array[int] = []; var new_times: Array[int] = []
	for _repeat in range(3):
		var started := Time.get_ticks_usec(); legacy._battle_group_structure_valid()
		old_times.append(Time.get_ticks_usec()-started)
		started = Time.get_ticks_usec(); state._battle_group_structure_valid()
		new_times.append(Time.get_ticks_usec()-started)
	old_times.sort(); new_times.sort()
	print("BATTLE_GROUP_SCALE nodes=", state.cities.size(), " armies=", state.armies.size(),
		" baseline_median_us=",old_times[1]," indexed_median_us=",new_times[1])
