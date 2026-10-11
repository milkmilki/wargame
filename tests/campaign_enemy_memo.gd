extends SceneTree
class CountState extends "res://tests/support/grid_world.gd":
	var enemy_queries := 0
	func is_enemy(a: int,b: int) -> bool:
		enemy_queries += 1
		return super.is_enemy(a,b)
var checks := 0
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks += 1
	if not ok: failures.append(label)
# Original build order, not a call to the optimized helper.
func original_index(state: GameState,attacker: int) -> Dictionary:
	var result := {}
	for army in state.armies:
		if not state.army_effective_for_field_campaign(army) or army.is_city_garrison or not state.is_enemy(attacker,army.owner_nation): continue
		var centers := {}
		if army.on_edge:
			for id in [army.move_from,army.move_to]:
				var center := state.administrative_center_of(id)
				if center>=0: centers[center]=true
		elif army.location_city>=0:
			var center := state.administrative_center_of(army.location_city)
			if center>=0: centers[center]=true
		for center in centers: result[center]=int(result.get(center,0))+army.size
	return result
func run():
	for seed_value in [1,7,2024]:
		var state := CountState.new(); state.generate_world(seed_value,4,32)
		for a in range(4):
			for b in range(a+1,4): state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.WAR)
		for id in range(80):
			var army := Army.new();army.id=1000+id;army.owner_nation=id%4;army.size=100+id;army.location_city=id%32
			if id%5==0:
				army.on_edge=true;army.state=Army.State.MOVING;army.move_from=id%32;army.move_to=(id+1)%32
			if id%7==0: army.state=Army.State.RECOVERING
			if id%11==0: army.starving=true
			if id%13==0: army.is_city_garrison=true
			if id%17==0: army.supply_ratio=0
			if id%19==0: army.size=0
			state.armies.append(army)
		for scenario in ["war","neutral","succession","peace_again"]:
			if scenario=="neutral": state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
			if scenario=="succession":
				state.nations[3].succession_identity=true
				var conflict := SuccessionConflict.new();conflict.nation_id=0;conflict.rebel_nation_id=3;conflict.war_id=7;state.succession_conflicts[0]=conflict
			if scenario=="peace_again":
				state.nations[3].succession_identity=false;state.succession_conflicts.clear();state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
			for attacker in range(4):
				var expected := original_index(state,attacker)
				var owners := {}
				for army in state.armies:
					if state.army_effective_for_field_campaign(army) and not army.is_city_garrison: owners[army.owner_nation]=true
				state.enemy_queries=0
				var cache := {}
				DiplomacyAI._cached_campaign_reinforcement_threat(state,attacker,0,cache)
				check(state.enemy_queries==owners.size(),"one relation query per eligible army owner")
				check(var_to_bytes(cache["campaign_v_index:%d"%attacker])==var_to_bytes(expected),"entire index preserves integer sums and insertion order")
				var before := state.enemy_queries
				for center in state.administrative_center_city_ids:
					check(DiplomacyAI._cached_campaign_reinforcement_threat(state,attacker,center,cache)==int(expected.get(center,0)),"cached center value")
				check(state.enemy_queries==before,"warm index performs no more relation queries")
		var cache := {"__disable_structure_cache":true}
		var center := state.administrative_center_city_ids[0]
		check(DiplomacyAI._cached_campaign_reinforcement_threat(state,0,center,cache)==state.campaign_reinforcement_threat(0,center),"legacy guard retains direct behavior")
	var empty := CountState.new();empty.generate_world(1,4,32);empty.armies.clear();empty.enemy_queries=0
	var empty_cache := {}
	check(DiplomacyAI._cached_campaign_reinforcement_threat(empty,0,0,empty_cache)==0,"no eligible armies returns zero")
	check(empty.enemy_queries==0,"empty army pool makes no relation query")
	check((empty_cache["campaign_v_index:0"] as Dictionary).is_empty(),"empty index retains original cache contract")
	var none := GameState.new()
	check(DiplomacyAI._cached_campaign_reinforcement_threat(none,-1,-1,{})==0,"empty world and invalid center")
	for failure in failures: printerr("CAMPAIGN_ENEMY_MEMO_FAIL ",failure)
	print("CAMPAIGN_ENEMY_MEMO_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
