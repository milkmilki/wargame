extends SceneTree
const Fixture = preload("res://tests/support/native_runtime_fixture.gd")
class CustomState extends GameState:
	func army_effective_for_field_campaign(_army: Army) -> bool: return false
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FROZEN_REINFORCEMENT_FAIL ", label)
func fixture() -> GameState:
	var state := GameState.new(); state._reset_world(79163)
	state._generate_nations(GameState.DiplomaticRelation.WAR, 4, false)
	for id in range(12):
		var city := City.new(); city.id = id; city.owner_nation = id % 4
		state.cities.append(city); state.administrative_center_by_city.append(id / 3 * 3)
	state.administrative_center_city_ids = PackedInt32Array([0,3,6,9])
	for id in range(100):
		var army := Army.new(); army.id = id; army.owner_nation = id % 4
		army.size = 100 + id; army.location_city = id % 12
		if id % 3 == 0:
			army.on_edge = true; army.move_from = id % 12; army.move_to = (id + 1) % 12
		if id % 11 == 0: army.state = Army.State.RECOVERING
		if id % 13 == 0: army.state = Army.State.RETREATING
		if id % 17 == 0: army.starving = true
		if id % 19 == 0: army.is_city_garrison = true
		if id % 23 == 0: army.supply_ratio = 0.0
		if id % 29 == 0: army.size = 0
		state.armies.append(army)
	state.armies[1].size = (1 << 54) + 1
	state.armies[2].owner_nation = 1 << 40
	state.armies[3].owner_nation = -1
	state.armies[4].location_city = -1
	state.armies[5].on_edge = true; state.armies[5].move_from = -1; state.armies[5].move_to = 99
	state.armies[6].supply_ratio = NAN
	return state
func compare(state: GameState, label: String):
	var before := var_to_bytes(Fixture.snapshot(state))
	var cache := {"__freeze_campaign_v_armies": true}
	for attacker in [-1, 0, 1, 2, 3, 1 << 40]:
		var old_cache := {}
		for center in state.administrative_center_city_ids:
			var expected := state.campaign_reinforcement_threat(attacker, center)
			check(DiplomacyAI._cached_campaign_reinforcement_threat(state, attacker, center, cache) == expected, label + " exact live reference threat")
			DiplomacyAI._cached_campaign_reinforcement_threat(state, attacker, center, old_cache)
		var key := "campaign_v_index:%d" % attacker
		check(var_to_bytes(cache[key]) == var_to_bytes(old_cache[key]), label + " full index preserves integer sums and insertion order")
	check(cache.has("campaign_v_army_rows"), label + " attackers share captured army rows")
	check(var_to_bytes(Fixture.snapshot(state)) == before, label + " queries preserve state and RNG")
func run():
	var state := fixture()
	compare(state, "war")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.NEUTRAL)
	state.nations[3].succession_identity = true
	var conflict := SuccessionConflict.new(); conflict.nation_id = 0; conflict.rebel_nation_id = 3; conflict.battle = Battle.new()
	state.succession_conflicts[0] = conflict
	compare(state, "mixed relations and succession")
	for army in state.armies:
		army.size += 71; army.location_city = 9 - army.location_city % 4
		army.starving = false; army.supply_ratio = 1.0
	state.administrative_center_by_city[8] = 3
	compare(state, "new frozen pass sees direct army and region edits")
	var ordinary := {}
	DiplomacyAI._cached_campaign_reinforcement_threat(state, 0, 0, ordinary)
	state.armies[1].size += 9000
	var changed_center := state.administrative_center_of(state.armies[1].location_city)
	check(DiplomacyAI._cached_campaign_reinforcement_threat(state, 2, changed_center, ordinary) == state.campaign_reinforcement_threat(2, changed_center) and not ordinary.has("campaign_v_army_rows"), "ordinary cache reads live armies for a new attacker")
	var custom := CustomState.new()
	var cache := {"__freeze_campaign_v_armies": true}
	check(DiplomacyAI._cached_campaign_reinforcement_threat(custom, 0, 0, cache) == 0 and not cache.has("campaign_v_army_rows"), "custom callbacks retain original path")
	state.armies.clear()
	compare(state, "empty army pool")
	var disabled := {"__freeze_campaign_v_armies": true, "__disable_structure_cache": true}
	check(DiplomacyAI._cached_campaign_reinforcement_threat(state,0,0,disabled) == 0 and not disabled.has("campaign_v_army_rows"), "disabled cache retains direct callback")
	print("FROZEN_REINFORCEMENT checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
