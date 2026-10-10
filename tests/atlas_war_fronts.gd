extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("ATLAS_FRONT_FAIL ",message)
func _initialize() -> void:
	if not FileAccess.file_exists("res://scripts/atlas/war_fronts.gd"):
		check(false,"hostile-border front renderer is missing"); quit(1); return
	var Front = load("res://scripts/atlas/war_fronts.gd")
	var state := preload("res://tests/support/grid_world.gd").new(); state.generate_grid_world(7351)
	for a in range(4):
		for b in range(a+1,4): state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.NEUTRAL)
	var points := PackedFloat32Array([10,10,30,10])
	var borders := [{"left":0,"right":1,"pts":points,"closed":false},{"left":1,"right":2,"pts":points,"closed":false},{"left":0,"right":-1,"pts":points,"closed":false}]
	var front = Front.new()
	front.configure(borders,state)
	check(front.fronts.is_empty() and front.normal_borders.size()==3,"peaceful/coastal boundaries stay ordinary")
	var simulation := Simulation.new(); simulation.setup(state); simulation.paused = true
	simulation._set_coalition_war([0] as Array[int],[1] as Array[int])
	front.configure(borders,state)
	check(front.fronts.size()==1 and front.normal_borders.size()==2,"only the real shared hostile border becomes a front")
	check(front.fronts[0].path==PackedVector2Array([Vector2(10,10),Vector2(30,10)]),"right defender retains line direction")
	var count: int = front.classification_count
	front.configure(borders,state); check(front.classification_count==count,"unchanged diplomacy and geometry reuse classification")
	# A counterattack objective must not change the original defending side.
	state.set_war_objective(1,0,0,"counterattack",state.war_id_between(0,1))
	front.configure(borders,state)
	check(front.fronts[0].defender==1,"original war sides survive defender counterattack")
	var teeth: Array = Front.teeth(PackedVector2Array([Vector2.ZERO,Vector2(2,0),Vector2(2,8)]),6.5,3.45)
	check(teeth.size()==2 and teeth[0][0].is_equal_approx(Vector2(2,1.25)),"tooth spacing carries over vertices")
	check(teeth[0][1].is_equal_approx(Vector2(5.45,1.25)),"teeth use the canvas-left normal")
	check(Front.teeth(PackedVector2Array([Vector2.ZERO,Vector2.ZERO]),6.5,3.45).is_empty(),"zero-length segments are harmless")
	check(is_equal_approx(Front.unit(3.),2./3.) and is_equal_approx(Front.unit(.5),1.),"upstream 3x zoom gives 2x screen width")
	var history := PoliticalHistory.new(); history.reset(state)
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.NEUTRAL)
	front.configure(borders,state); check(front.fronts.is_empty(),"peace removes front without territory change")
	var old := history.build_view_state(state,0)
	front.configure(borders,old); check(front.fronts.size()==1 and front.fronts[0].defender==1,"historical diplomacy and original war roles are frozen")
	old.nations[1].alive = false; front.configure(borders,old)
	check(front.fronts.is_empty(),"a dead nation cannot keep a front")
	state.set_diplomatic_relation(0,1,GameState.DiplomaticRelation.WAR)
	state.set_war_objective(1,0,0,"new declaration")
	state.war_chronicle_contexts.clear(); front.configure(borders,state)
	check(front.fronts[0].path[0]==Vector2(30,10),"left defender reverses line")
	var seam := [{"left":0,"right":1,"pts":PackedFloat32Array([2045,20,2051,20]),"closed":false}]
	front.configure(seam,state)
	check(absf(front.fronts[0].path[1].x-front.fronts[0].path[0].x)==6.,"continuous date-line geometry stays unwrapped")
	check(borders[0].pts==points,"render classification does not mutate logical border geometry")
	front.free(); simulation.free()
	print("ATLAS_WAR_FRONTS checks=",checks," failures=",failures); quit(1 if failures else 0)
