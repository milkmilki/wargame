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
	var state := fixture()
	var nation := state.nations[0]
	var challenger := nation.prince_person_ids[1]
	PrincePolitics.person(state, 0, challenger).archetype = RulerProfile.CONQUEROR
	var troop := state.create_army(0, 0, 15000)
	troop.political_person_id = challenger
	var crown := state.create_army(0, 0, 1500)
	crown.political_person_id = nation.crown_prince_person_id
	var central := state.create_army(0, 0, 15000)
	central.political_person_id = -1
	var sim := Simulation.new()
	sim.setup(state)
	check(SuccessionRules.begin_preparation(state, 0, challenger), "secret_preparation")
	var conflict: SuccessionConflict = state.succession_conflicts.get(0)
	if conflict != null:
		var moved := false
		var fought := false
		var lost := false
		for tick in range(300):
			state.day += 1
			state.month = state.day / 30
			sim._plan_succession_conflicts()
			sim._resolve_supply()
			sim._advance_movement()
			moved = moved or troop.on_edge
			fought = fought or troop.state == Army.State.FIGHTING
			lost = lost or troop.size < 15000 or crown.size < 1500 or state.cities[0].garrison_manpower < 500
			check(central.battle_id < 0 and central.size == 15000, "central_neutral_%d" % tick)
			sim._update_succession_conflicts()
			if not state.succession_conflicts.has(0):
				break
		check(moved, "real_movement")
		check(fought, "real_combat")
		check(lost, "real_losses")
		check(nation.crown_prince_person_id == challenger, "capital_changes_crown")
		check(nation.ruler_name == "李安", "emperor_unchanged")
		check(state.succession_conflicts.is_empty(), "real_chain_cleanup")
		check(state.cities[conflict.camp_city_id].owner_nation == 0 and state.cities[0].owner_nation == 0, "territory_restored")
		check(troop.owner_nation == 0 and troop.campaign_war_id < 0, "troops_restored")
	sim.free()
	var synchronous := await scheduled_chain(false, false)
	var sliced := await scheduled_chain(true, false)
	var mirrored := await scheduled_chain(false, true)
	check(synchronous == sliced, "full_scheduler_sync_sliced_equivalence")
	check(synchronous == mirrored, "full_scheduler_mirror_equivalence")
	for failure in failures:
		push_error("SUCCESSION_CHAIN_FAIL: " + failure)
	print("SUCCESSION_CHAIN: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func scheduled_chain(sliced: bool, mirrored: bool) -> PackedByteArray:
	var state := fixture()
	var nation := state.nations[0]
	var prince := nation.prince_person_ids[1]
	PrincePolitics.person(state, 0, prince).archetype = RulerProfile.CONQUEROR
	var attacker := state.create_army(0, 0, 15000)
	attacker.political_person_id = prince
	var crown := state.create_army(0, 0, 1500)
	crown.political_person_id = nation.crown_prince_person_id
	var central := state.create_army(0, 0, 15000)
	central.political_person_id = -1
	if mirrored:
		for city in state.cities:
			city.map_position.x = 1.0 - city.map_position.x
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.set_process(false)
	check(SuccessionRules.begin_preparation(state, 0, prince), "scheduler_preparation")
	for day in range(180):
		await sim._advance_day(sliced)
		check(central.battle_id < 0 and central.size == 15000, "scheduler_central_neutral")
		for battle in state.battles:
			for unit in battle.side_a + battle.side_b:
				if unit.size > 0 and not unit.is_city_garrison:
					check(unit.state == Army.State.FIGHTING and unit.battle_id == battle.id, "scheduler_battle_binding")
	check(nation.crown_prince_person_id == prince and nation.succession_competition_closed and state.succession_conflicts.is_empty(), "scheduler_real_political_result")
	var snapshot := NativeSnapshotBuilder.build(state)
	if mirrored:
		for id in range(state.cities.size()):
			snapshot.cities.position_x[id] = Vector2(id * 0.3, 0.5).x
	# Only map geometry is reflected; all runtime politics/combat data must agree.
	var result := var_to_bytes(snapshot)
	sim.free()
	return result
