extends SceneTree
const Front = preload("res://scripts/atlas/war_fronts.gd")
var failures := 0
var checks := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	var state := preload("res://tests/support/grid_world.gd").new();state.generate_grid_world(7351)
	for a in range(4):
		for b in range(a+1,4):state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.NEUTRAL)
	var points := PackedFloat32Array([10,10,30,10])
	var borders := [{"left":0,"right":1,"pts":points,"closed":false},{"left":1,"right":2,"pts":points,"closed":false},{"left":0,"right":3,"pts":points,"closed":false}]
	state.suzerainty[1]={"overlord_id":0,"tribute_rate":.25,"created_day":0,"civil_war":false}
	state.suzerainty[2]={"overlord_id":0,"tribute_rate":.25,"created_day":0,"civil_war":false}
	var front := Front.new();front.configure(borders,state)
	check(front.get("vassal_borders")!=null,"peaceful vassal boundary classification exists")
	if front.get("vassal_borders")==null:front.free();quit(1);return
	check(front.vassal_borders.size()==2 and front.normal_borders.size()==1 and front.fronts.is_empty(),"parent-child and sibling borders are internal, unrelated nations remain ordinary")
	front.high_performance=true;front.update_persistent()
	check(front.persistent_layers.size()==6,"persistent front and vassal layers coexist")
	var ink: Node=front.persistent_layers[5]
	check(is_equal_approx(ink.material.get_shader_parameter("dash_length"),3.6) and is_equal_approx(ink.material.get_shader_parameter("gap_length"),2.4),"short dash/gap use referenced upstream ratio")
	var builds: int=ink.build_count
	var classification: int=front.classification_count
	for zoom in [1.,2.,4.,8.]:front.set_view_zoom(zoom)
	check(ink.build_count==builds and front.classification_count==classification,"camera zoom reuses geometry and classification")
	var history:=PoliticalHistory.new();history.reset(state)
	state.suzerainty.erase(1)
	front.configure(borders,state)
	check(front.vassal_borders.is_empty() and front.normal_borders.size()==3,"removing bond reclassifies without territory or diplomacy revision")
	var past:=history.build_view_state(state,0);front.configure(borders,past)
	check(front.vassal_borders.size()==2,"history uses frozen vassal relations")
	past.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	front.configure(borders,past)
	check(front.fronts.size()==1 and front.vassal_borders.size()==1,"civil hostility takes priority over internal short dashes")
	past.nations[1].alive=false;front.configure(borders,past)
	check(front.vassal_borders.is_empty() and front.fronts.is_empty(),"dead subject leaves neither front nor internal border")
	check(borders[0].pts==points,"styling leaves source geometry unchanged")
	front.high_performance=false;front.prepare_meshes()
	check(front.meshes.size()==6,"legacy development renderer supports the same two categories")
	front.free();print("ATLAS_VASSAL_BORDERS checks=%d failures=%d"%[checks,failures]);quit(0 if failures==0 else 1)
