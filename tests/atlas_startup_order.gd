extends SceneTree
var failures := 0
func check(ok: bool,message: String):
	if not ok: failures+=1; printerr("ATLAS_STARTUP_ORDER_FAIL ",message)
func _initialize():
	var script=load("res://scripts/core/equivariant_order.gd")
	check(script.get_script_method_list().any(func(method): return method.name=="_city_key_in_frame"),"bulk ranking can reuse a single immutable nation frame")
	for mirrored in [false,true]:
		var state := GameState.new(); var nation := Nation.new(); nation.id=0; nation.capital_city_id=-1; state.nations.append(nation)
		for point in [Vector2(.2,.4),Vector2(.3,.5),Vector2(.4,.4),Vector2(.8,.6)]:
			var city := City.new(); city.id=state.cities.size(); city.owner_nation=0; city.map_position=Vector2(1.-point.x,point.y) if mirrored else point; state.cities.append(city)
		var rank := EquivariantOrder.city_rank_map(state,0)
		check([rank[0],rank[1],rank[2],rank[3]]==[0,1,2,3],"frozen scalar ranking, including no-capital nation centroid and horizontal mirror")
		for anchor in [-1,1]:
			var actual := EquivariantOrder.city_rank_map(state,0,anchor)
			for a in range(4):
				for b in range(4):
					var ka := EquivariantOrder.city_key(state,0,a,anchor); var kb := EquivariantOrder.city_key(state,0,b,anchor)
					check((int(actual[a])<int(actual[b]))==EquivariantOrder._key_less(ka,kb),"bulk and scalar order remain equivalent")
	print("ATLAS_STARTUP_ORDER failures=",failures); quit(1 if failures else 0)
