extends SceneTree
const Frozen = preload("res://tests/campaign_frozen_reinforcement.gd")
class CountingState extends GameState:
	var effective_queries := 0
	func army_effective_for_field_campaign(army: Army) -> bool:
		effective_queries += 1
		return super.army_effective_for_field_campaign(army)
var checks := 0
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("LOCAL_THREAT_FAIL ",label)
func fixture() -> CountingState:
	var helper := Frozen.new()
	var original := helper.fixture()
	helper.free()
	var state := CountingState.new()
	for property in original.get_property_list():
		var key: String = property.name
		if key != "script" and int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			state.set(key,original.get(key))
	for record in [[7,2,3],[8,-1,3],[9,2,99]]:
		var troop := state.armies[int(record[0])]
		troop.on_edge = true
		troop.move_from = int(record[1])
		troop.move_to = int(record[2])
	state.armies.append(null)
	return state
func budget(state: GameState, center: int) -> int:
	var result := 0
	for army in state.armies:
		if army == null or army.is_city_garrison: continue
		var locations := [army.move_from,army.move_to] if army.on_edge else [army.location_city]
		for location in locations:
			if location >= 0 and state.administrative_center_of(location) == center:
				result += 1; break
	return result
func prewar_oracle(state: GameState, attacker: int, target: int, center: int) -> int:
	var defenders := state.alliance_bloc(target)
	var attackers := state.alliance_bloc(attacker)
	var result := 0
	for row in DiplomacyAI._capture_campaign_reinforcement_rows(state):
		if defenders.has(int(row[0])) and not attackers.has(int(row[0])) and (row[2] == center or row[3] == center):
			result += int(row[1])
	return result
func compare(state: CountingState, label: String):
	for attacker in [-1,0,1,2,3,1 << 40]:
		var expected_cache := {}
		var enemy_budget := 0
		for army in state.armies:
			if army != null and not army.is_city_garrison and state.is_enemy(attacker,army.owner_nation): enemy_budget += 1
		for center in state.administrative_center_city_ids:
			state.effective_queries = 0
			var expected := DiplomacyAI._cached_campaign_reinforcement_threat(state,attacker,center,expected_cache)
			check(state.effective_queries <= enemy_budget,label + ": indexed eligibility checks only hostile owners")
			state.effective_queries = 0
			check(state.campaign_reinforcement_threat(attacker,center) == expected,label + ": wartime exact wide integer total")
			check(state.effective_queries <= budget(state,center),label + ": wartime eligibility checks stay local")
			for target in range(4):
				expected = prewar_oracle(state,attacker,target,center)
				state.effective_queries = 0
				check(state.campaign_prewar_reinforcement_threat(attacker,target,center) == expected,label + ": prewar bloc exclusion and wide total")
				check(state.effective_queries <= budget(state,center),label + ": prewar eligibility checks stay local")
func run():
	var state := fixture()
	compare(state,"war")
	state.armies.pop_back()
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0,2,GameState.DiplomaticRelation.NEUTRAL)
	state.nations[3].succession_identity = true
	var conflict := SuccessionConflict.new(); conflict.nation_id = 0; conflict.rebel_nation_id = 3; conflict.battle = Battle.new()
	state.succession_conflicts[0] = conflict
	state.armies.append(null)
	compare(state,"mixed relations and succession")
	var sim := Simulation.new(); sim.state = state
	state.effective_queries = 0
	var expected := false
	for army in state.armies:
		if army != null and state.army_effective_for_field_campaign(army) and state.is_enemy(0,army.owner_nation) and army.location_city == 11: expected = true
	state.effective_queries = 0
	check(sim._campaign_camp_threatened(0,11) == expected,"camp threat matches live local enemies")
	check(state.effective_queries < 15,"camp threat ignores unrelated locations")
	sim.free()
	print("LOCAL_THREAT_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
