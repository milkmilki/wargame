extends SceneTree
const FamilyFixture = preload("res://tests/ruler_family_fixture.gd")

var failures: Array[String] = []
func _init() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

static func fixture() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.world_seed = 137
	state.rng.seed = 137
	var nation := Nation.new()
	nation.id = 0
	nation.ruler_name = "李安"
	nation.capital_city_id = 0
	nation.warehouse_city_ids = [0] as Array[int]
	nation.treasury_gold = 1000000
	state.nations.append(nation)
	for id in range(3):
		var city := City.new()
		city.id = id
		city.owner_nation = 0
		city.food_storage = 1000000 if id == 0 else 0
		city.has_warehouse = id == 0
		city.garrison_manpower = 500 if id == 0 else 0
		city.manpower_per_month = 1000
		city.food_per_half_year = 1000000
		city.gold_per_month = 10000
		city.map_position = Vector2(id * 0.3, 0.5)
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.recognized_city_owners.append(0)
		state.administrative_center_by_city.append(0)
		state.region_ids.append(0)
	state.administrative_center_city_ids = [0] as Array[int]
	for id in [1, 2]:
		state._add_edge(0, id)
		state.edge_of(0, id).distance = 0.1
	FamilyTree.ensure_all(state)
	FamilyFixture.ensure_candidates(state, 0)
	state.refresh_derived()
	return state

func run() -> void:
	var state := fixture(); var n:=state.nations[0]; var challenger:=n.prince_person_ids[1]
	PrincePolitics.person(state,0,challenger).archetype=RulerProfile.CONQUEROR
	var troop:=state.create_army(0,1,15000); troop.political_person_id=challenger
	var crown:=state.create_army(0,0,1000); crown.political_person_id=n.crown_prince_person_id
	var sim:=Simulation.new(); sim.setup(state)
	check(SuccessionRules.begin_preparation(state,0,challenger),"start")
	for i in range(180):
		state.day+=1; sim._update_succession_conflicts()
		if not state.succession_conflicts.has(0): break
	check(n.crown_prince_person_id==challenger and n.ruler_name=="李安","new_heir_not_ruler")
	check(troop.size==15000 and crown.size==1000 and state.battles.is_empty(),"virtual_losses_only")
	check(state.succession_conflicts.is_empty(),"finished")
	sim.free()
	for failure in failures: push_error(failure)
	print("SUCCESSION_CHAIN: %d failures"%failures.size()); quit(0 if failures.is_empty() else 1)
