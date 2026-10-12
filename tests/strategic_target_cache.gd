extends SceneTree
## A snapshot's objective evaluation shares its frozen diplomacy inputs.
class CountingState extends GameState:
	var eligibility_checks := 0
	func army_effective_for_field_campaign(army: Army) -> bool:
		eligibility_checks += 1
		return super.army_effective_for_field_campaign(army)

var failures := 0
func _initialize():
	create_timer(60.).timeout.connect(func(): printerr("STRATEGIC_TARGET_CACHE_TIMEOUT"); quit(1))
	call_deferred("run")
func check(ok: bool, label: String):
	if not ok: failures += 1; printerr("STRATEGIC_TARGET_CACHE_FAIL ",label)
func fixture() -> CountingState:
	var state := CountingState.new()
	for owner in range(3):
		var nation := Nation.new(); nation.id = owner
		nation.capital_city_id = [0,1,3][owner]; state.nations.append(nation)
	for id in range(4):
		var city := City.new(); city.id = id; city.owner_nation = [0,1,1,2][id]
		city.map_position = Vector2(.1+id*.2,.5); state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
	state.administrative_center_by_city = PackedInt32Array([0,1,1,3])
	state.administrative_center_city_ids = PackedInt32Array([0,1,3])
	for pair in [Vector2i(0,2),Vector2i(2,1),Vector2i(3,1)]:
		var edge := Edge.new(); edge.city_a = pair.x; edge.city_b = pair.y
		state.edges.append(edge); state.edge_lookup[GameState.edge_key(pair.x,pair.y)] = edge
		(state.adjacency[pair.x] as Array[int]).append(pair.y)
		(state.adjacency[pair.y] as Array[int]).append(pair.x)
	for owner in range(3):
		var army := Army.new(); army.id = owner; army.owner_nation = owner
		army.location_city = state.nations[owner].capital_city_id
		army.size = 10000; army.max_size = 10000; state.armies.append(army)
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0,1,1,"strategic_target_cache")
	return state
func run():
	var state := fixture(); var view := AiWorldView.build(state,0)
	view.strategic_planning_enabled = false
	var cache := {}; var target := DiplomacyAI.administrative_tactical_target(state,0,1,1,-1,false,cache)
	check(target == 2,"fixture has a reachable enemy prefecture")
	state.eligibility_checks = 0
	var snapshot := StrategicMapSnapshot.build(view,cache)
	check(state.eligibility_checks == 0,"priority evaluation reuses the seeded reinforcement threat index")
	var later_phase_cache := {}
	var fresh := StrategicMapSnapshot.build(view,later_phase_cache)
	check(not later_phase_cache.has("campaign_v_index:0"),"objective threat indexes do not leak into later force commits")
	check(snapshot.priority_enemy_cities == fresh.priority_enemy_cities,"warm and cold snapshots choose the same ordered targets")
	check(snapshot.priority_enemy_cities.has(target),"the reachable diplomatic objective remains in the priority list")
	var bytes := var_to_bytes(NativeSnapshotBuilder.build(state)); var rng_state := state.rng.state
	StrategicMapSnapshot.build(view,cache)
	check(bytes == var_to_bytes(NativeSnapshotBuilder.build(state)) and rng_state == state.rng.state,"snapshot evaluation leaves gameplay state and RNG unchanged")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
	var peaceful := StrategicMapSnapshot.build(AiWorldView.build(state,0),{})
	check(peaceful.priority_enemy_cities.is_empty(),"a new peaceful batch clears enemy targets")
	print("STRATEGIC_TARGET_CACHE failures=",failures); quit(1 if failures else 0)
