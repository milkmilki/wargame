extends SceneTree
var failures := 0
var checks := 0
class CountingState extends GameState:
	var alliance_queries := 0
	func alliance_bloc(nation_id: int,alive_only: bool = true) -> Array[int]:
		alliance_queries+=1; return super.alliance_bloc(nation_id,alive_only)
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("ATLAS_PREWAR_BATCH_FAIL ",message)
func _initialize():
	var ai=load("res://scripts/ai/diplomacy_ai.gd")
	if not ai.get_script_method_list().any(func(method): return method.name=="prewar_launch_requirement"):
		check(false,"prewar queries reuse batch alliance components"); quit(1); return
	var state := CountingState.new()
	for id in range(4):
		var nation := Nation.new();nation.id=id;nation.capital_city_id=id;state.nations.append(nation)
		var city := City.new();city.id=id;city.owner_nation=1 if id==2 else id;city.map_position=Vector2(id,0);city.garrison_manpower=1000
		state.cities.append(city);state.recognized_city_owners.append(city.owner_nation);state.administrative_center_by_city.append(1 if id==2 else id)
	state.set_diplomatic_relation(0,3,GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.ALLIED)
	for id in range(4):
		var army := Army.new();army.id=id;army.owner_nation=id;army.location_city=1;army.size=30000 if id==1 else 20000
		state.armies.append(army)
	var expected := state.campaign_prewar_launch_requirement(0,1,1)
	state.alliance_queries=0;var cache := {}
	for query in range(20): check(ai.prewar_launch_requirement(state,0,1,1,cache)==expected,"live demand matches direct query")
	check(state.alliance_queries==2,"two alliance builds for the entire batch, instead of three per query")
	state.armies[1].size=80000
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==200000,"army size changes remain live inside a batch")
	state.armies[2].starving=true
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==160000,"ineffective defender removed immediately")
	state.armies[1].on_edge=true;state.armies[1].move_from=1;state.armies[1].move_to=2
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==160000,"same-state edge endpoints never double count one army")
	state.armies[1].move_from=0;state.armies[1].move_to=3
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==45000,"army leaving target state changes live demand")
	state.armies[1].on_edge=false;state.armies[1].location_city=1;state.armies[2].starving=false
	state.set_diplomatic_relation(1,2,GameState.DiplomaticRelation.NEUTRAL)
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==160000,"diplomacy change invalidates cached defender bloc")
	state.cities[1].garrison_manpower=100000
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==300000,"garrison changes remain live")
	state.cities[2].owner_nation=0;state.ownership_revision+=1
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==160000,"captured prefecture reduces live siege requirement")
	for center in [-1,2,999]: check(ai.prewar_launch_requirement(state,0,1,center,cache)==0,"invalid or non-center objective unchanged")
	state.nations[1].alive=false
	check(ai.prewar_launch_requirement(state,0,1,1,cache)==state.campaign_prewar_launch_requirement(0,1,1),"dead target uses direct legacy contract")
	print("ATLAS_PREWAR_BATCH checks=",checks," failures=",failures);quit(1 if failures else 0)
