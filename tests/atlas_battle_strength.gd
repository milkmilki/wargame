extends SceneTree
var failures := 0
func _initialize(): call_deferred("run")
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_BATTLE_STRENGTH_FAIL ",message)
func troop(size: int,guard: bool=false) -> Army:
	var army:=Army.new();army.size=size;army.max_size=30000;army.is_city_garrison=guard;army.owner_nation=0;army.location_city=0
	return army
func run():
	var overlay:=preload("res://scripts/atlas/military_overlay.gd").new()
	if not overlay.has_method("battle_strength"):
		printerr("ATLAS_BATTLE_STRENGTH_FAIL no battle manpower presentation");overlay.free();quit(1);return
	await pure_siege()
	var battle:=Battle.new();battle.id=0;battle.kind=Battle.Kind.SIEGE;battle.side_b_defends_city=true
	var guard:=troop(1500,true);var defender:=troop(20000);var attacker:=troop(20000)
	battle.side_b=[guard,defender];battle.side_a=[attacker,troop(0)]
	var row: Dictionary=overlay.call("battle_strength",battle)
	check(row.counts==[1500,20000,20000],"split actual garrison and defender manpower, no establishment accounting")
	check(row.total==41500 and is_equal_approx(row.fractions[0],1500./41500.),"widths use exact population ratio")
	check(row.labels==["守军","守方","攻方"],"defender side precedes attacker")
	guard.size=0;defender.size=10000;row=overlay.call("battle_strength",battle)
	check(row.counts==[0,10000,20000] and is_zero_approx(row.fractions[0]),"casualties update counts and an absent guard has no width")
	battle.kind=Battle.Kind.FIELD;battle.side_b_defends_city=false;battle.side_a=[attacker];battle.side_b=[defender]
	row=overlay.call("battle_strength",battle)
	check(row.counts==[0,20000,10000] and row.labels==["守军","甲方","乙方"],"field combat uses two sides without fabricated garrison")
	attacker.size=0;defender.size=0;row=overlay.call("battle_strength",battle)
	check(row.total==0 and row.fractions==[0.,0.,0.],"zero troops never divide by zero")
	var state:=GameState.new();var city:=City.new();city.id=0;city.map_position=Vector2(.5,.5);state.cities.append(city)
	var nation:=Nation.new();state.nations.append(nation);battle.city=city;state.battles.append(battle);overlay.state=state
	root.add_child(overlay);await process_frame;await process_frame
	var stamp: int=overlay.marker_redraw_count
	for i in range(4): await process_frame
	check(overlay.marker_redraw_count==stamp,"paused battle keeps recorded canvas commands")
	defender.size=1200;await process_frame;await process_frame
	check(overlay.marker_redraw_count>stamp,"army absent from field army list still invalidates battle bar after casualty change")
	stamp=overlay.marker_redraw_count;battle.finished=true;await process_frame;await process_frame
	check(overlay.marker_redraw_count>stamp,"finished battle removes its marker and bar")
	root.remove_child(overlay);overlay.free()
	print("ATLAS_BATTLE_STRENGTH failures=",failures);quit(1 if failures else 0)

func pure_siege() -> void:
	var state:=preload("res://tests/support/grid_world.gd").new();state.generate_grid_world(94002)
	state.armies.clear();state.battles.clear()
	var city: City=state.cities[state.administrative_center_city_ids[0]];city.garrison_manpower=1500
	var attacker:=troop(1000);attacker.id=9000;attacker.owner_nation=(city.owner_nation+1)%state.nations.size()
	attacker.location_city=state.adjacency[city.id][0];attacker.move_from=attacker.location_city;attacker.move_to=city.id;state.armies.append(attacker)
	var sim:=Simulation.new();sim.setup(state);sim._start_or_join_siege(attacker,city,state.edge_of(attacker.move_from,city.id))
	check(state.battles.size()==1,"actual siege entry retains a garrison-only city")
	if state.battles.is_empty():sim.free();return
	var battle: Battle=state.battles[0]
	var overlay:=preload("res://scripts/atlas/military_overlay.gd").new();overlay.state=state;root.add_child(overlay)
	var row: Dictionary=overlay.battle_strength(battle)
	check(battle.side_b.is_empty() and row.counts==[1500,0,1000] and row.labels==["守军","守方","攻方"],"pure siege reads persistent city garrison despite empty side_b/false defender flag")
	await process_frame;await process_frame
	var stamp: int=overlay.marker_redraw_count
	sim._resolve_battles();await process_frame;await process_frame
	row=overlay.battle_strength(battle)
	check(not battle.finished and battle.side_b.is_empty() and city.garrison_manpower<1500 and row.counts==[city.garrison_manpower,0,attacker.size],"blockade attrition updates persistent garrison outside the temporary combat array")
	check(overlay.marker_redraw_count>stamp,"city garrison attrition invalidates the recorded bar")
	var attached:=sim._attach_city_garrison(battle)
	check(attached!=null and overlay.battle_strength(battle).counts[0]==city.garrison_manpower,"temporary garrison is not added to persistent garrison twice")
	if attached!=null:
		attached.size=1200
		check(overlay.battle_strength(battle).counts[0]==1200,"temporary live combat garrison takes precedence until written back")
		sim._detach_city_garrison(battle,attached)
		check(battle.side_b.is_empty() and overlay.battle_strength(battle).counts==[1200,0,attacker.size],"pure siege survives temporary guard detach")
	var defender:=troop(5000);defender.owner_nation=city.owner_nation;battle.side_b=[defender];battle.side_b_defends_city=true
	check(overlay.battle_strength(battle).counts==[1200,5000,attacker.size],"siege with real defenders also shows the separate city defense reserve")
	battle.side_b_defends_city=false
	check(overlay.battle_strength(battle).counts==[0,attacker.size,5000],"two competing field forces outside a third country's city do not inherit its garrison")
	root.remove_child(overlay);overlay.free();sim.free()
