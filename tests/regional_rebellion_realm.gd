extends SceneTree
const Fixture = preload("res://tests/state_rebellion.gd")
const Direct = preload("res://tests/direct_center_camp.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _init() -> void:
	var state := Fixture.fixture()
	for id in [2,3,4,5]:
		var nation := Nation.new(); nation.id=id; nation.alive=true
		state.nations.append(nation)
	state.cities[5].owner_nation=2; state.recognized_city_owners[5]=2
	state.nations[2].capital_city_id=5
	var nested_city := City.new(); nested_city.id=9; nested_city.owner_nation=4
	nested_city.is_capital=true; nested_city.has_warehouse=true
	state.cities.append(nested_city); state.recognized_city_owners.append(4)
	state.administrative_center_by_city.append(9); state.administrative_region_ids.append(4)
	state.administrative_center_city_ids.append(9); state.administrative_region_count+=1
	state.region_ids.append(2); state.adjacency[9]=[] as Array[int]
	state.nations[4].capital_city_id=9
	for a in range(state.nations.size()):
		for b in range(a+1,state.nations.size()):
			state.set_diplomatic_relation(a,b,GameState.DiplomaticRelation.NEUTRAL)
	check(state.accept_submission(1,0), "real parent submission")
	check(state.accept_submission(1,2), "real sibling submission")
	check(state.accept_submission(2,4), "real nested submission")
	state.set_diplomatic_relation(1,3,GameState.DiplomaticRelation.ALLIED)
	var rebel := state.start_regional_rebellion(0,[2,3,4] as Array[int])
	check(rebel>=0,"real full-state uprising")
	if rebel>=0:
		var war := state.war_id_between(0,rebel)
		for member in [0,1,2,4]:
			check(state.is_enemy(member,rebel),"realm member joins rebellion war %d"%member)
			check(state.war_id_between(member,rebel)==war,"one shared war %d"%member)
			check(state.regional_rebellion_peace_locked(member,rebel),"realm peace lock %d"%member)
		check(not state.is_enemy(3,rebel),"ordinary external ally stays neutral")
		check(not state.set_diplomatic_relation(3,rebel,GameState.DiplomaticRelation.WAR),"external ally cannot join scoped uprising")
		check(not state.set_diplomatic_relation(5,rebel,GameState.DiplomaticRelation.WAR),"unrelated country cannot join")
		check(state.rebellion_structure_valid(),"shared suppression is a valid political state")
		var sim := Simulation.new(); sim.setup(state)
		sim._synchronize_alliance_wars(1,3)
		check(not state.is_enemy(3,rebel),"alliance closure cannot recruit foreign ally")
		# A sibling's actual city assault must be legal and clean up all realm edges.
		state.armies.clear()
		var edge := Edge.new(); edge.city_a=2; edge.city_b=5; edge.max_manpower=20000
		state.edges.append(edge); state.edge_lookup[state.edge_key(2,5)]=edge
		state.adjacency[2].append(5); state.adjacency[5].append(2)
		var army := Direct.army(state,2,5,60000)
		army.attack=1000; army.defense=1000; army.supply_ratio=1.0
		army.campaign_war_id=war; army.occupation_claimant_nation=2
		army.move_to=2; army.move_from=5; army.move_progress=1.0; army.on_edge=true
		state.cities[2].garrison_manpower=3000
		sim._arrive_at_node(army)
		var battle := sim._siege_battle_of(state.cities[2])
		check(battle!=null,"sibling actually enters rebel city siege")
		if battle!=null:
			for tick in range(30):
				state.day+=1; sim._advance_siege(battle)
				if battle.finished: break
			check(battle.finished and battle.winner_side==1,"sibling wins real siege")
			sim._resolve_eliminated_nation_capitulations(); state.prune_rebellions()
			check(not state.nations[rebel].alive,"sibling suppresses full rebel state")
			for member in [0,1,2,4]:
				check(not state.is_enemy(member,rebel),"suppression clears realm war %d"%member)
			check(army.campaign_war_id==-1,"winning army releases war binding")
		sim.free()
	print("REGIONAL_REBELLION_REALM checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
