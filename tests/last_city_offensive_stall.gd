extends SceneTree
## 终局回归：国家0仅剩城9和四支5000守军；国家1控制其他全部城市，
## 从零重建主战军。城9入口容量10000，15000重军不得计入可入场兵力。

const REMNANT_ID: int = 0
const DOMINANT_ID: int = 1
const LAST_CITY_ID: int = 9
const RUN_DAYS: int = 720


func _init() -> void:
	var state := _build_fixture()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false
	var launched := false
	var captured := false
	for _day in range(RUN_DAYS):
		sim._advance_day()
		var nation := state.nations[DOMINANT_ID]
		launched = launched or nation.campaign_offensive_count > 0
		captured = state.cities[LAST_CITY_ID].owner_nation == DOMINANT_ID
		if captured or not state.is_enemy(DOMINANT_ID, REMNANT_ID):
			break
	print(
		"verdict=%s day=%d launched=%s owner9=%d"
		% [
			"LAST_CITY_CAPTURED" if captured else "LAST_CITY_STALLED",
			state.day,
			str(launched),
			state.cities[LAST_CITY_ID].owner_nation,
		]
	)
	sim.free()
	quit(0 if captured else 1)


func _build_fixture() -> GameState:
	var state := GameState.new()
	state.generate_world(12345, 4)
	state.day = 60 * 365
	state.armies.clear()
	state.battles.clear()
	for nation in state.nations:
		nation.battle_groups.clear()
		nation.next_battle_group_id = 0
		nation.alive = nation.id in [REMNANT_ID, DOMINANT_ID]
		nation.warehouse_city_ids.clear()
		nation.capital_city_id = -1
		nation.war_preparation_target_nation = -1
		nation.war_preparation_objective_city = -1
		nation.campaign_next_offensive_day = -1
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	for city in state.cities:
		city.owner_nation = (
			REMNANT_ID
			if city.id == LAST_CITY_ID
			else DOMINANT_ID
		)
		state.recognized_city_owners[city.id] = city.owner_nation
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
	state.set_diplomatic_relation(
		REMNANT_ID,
		DOMINANT_ID,
		GameState.DiplomaticRelation.WAR
	)
	state.set_war_objective(
		DOMINANT_ID,
		REMNANT_ID,
		LAST_CITY_ID,
		"last-city route-capacity regression"
	)
	var staging := DiplomacyAI.staging_cities_for_objective(
		state,
		DOMINANT_ID,
		LAST_CITY_ID
	)
	assert(not staging.is_empty(), "城9必须存在合法集结城市")
	var entry_edge := state.edge_of(staging[0], LAST_CITY_ID)
	assert(
		entry_edge != null
			and entry_edge.max_manpower == 10000,
		"回归夹具要求城9入口容量为10000"
	)
	var dominant_capital := staging[0]
	var farthest_distance := -1.0
	for city in state.land_cities_of(DOMINANT_ID):
		var distance := city.map_position.distance_squared_to(
			state.cities[LAST_CITY_ID].map_position
		)
		if distance > farthest_distance:
			farthest_distance = distance
			dominant_capital = city.id
	state.nations[REMNANT_ID].capital_city_id = LAST_CITY_ID
	state.nations[REMNANT_ID].warehouse_city_ids = [
		LAST_CITY_ID
	] as Array[int]
	state.cities[LAST_CITY_ID].is_capital = true
	state.cities[LAST_CITY_ID].has_warehouse = true
	state.cities[LAST_CITY_ID].food_storage = 10000
	state.nations[DOMINANT_ID].capital_city_id = dominant_capital
	state.nations[DOMINANT_ID].warehouse_city_ids = [
		dominant_capital
	] as Array[int]
	state.cities[dominant_capital].is_capital = true
	state.cities[dominant_capital].has_warehouse = true
	state.cities[dominant_capital].food_storage = 1000000
	state.nations[REMNANT_ID].treasury_gold = 1000
	state.nations[REMNANT_ID].manpower_pool = 0
	state.nations[DOMINANT_ID].treasury_gold = 1000000
	state.nations[DOMINANT_ID].manpower_pool = 1000000
	state.nations[DOMINANT_ID].military_payment_ratio = 1.0
	for garrison_index in range(4):
		var garrison := state.create_army(
			REMNANT_ID,
			LAST_CITY_ID,
			GameState.INITIAL_LIGHT_ARMY_SIZE,
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		if garrison == null:
			garrison = Army.new()
			garrison.id = 100000 + garrison_index
			garrison.owner_nation = REMNANT_ID
			garrison.size = GameState.INITIAL_LIGHT_ARMY_SIZE
			garrison.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
			garrison.max_morale = Army.LIGHT_MAX_MORALE
			garrison.morale = Army.LIGHT_MAX_MORALE
			garrison.location_city = LAST_CITY_ID
			garrison.move_from = LAST_CITY_ID
			garrison.state = Army.State.IDLE
			state.armies.append(garrison)
		garrison.attack = 10
		garrison.defense = 10
	var initial_groups := _env_int("LAST_CITY_MAIN_GROUPS", 0)
	for _group_index in range(initial_groups):
		var group := state.create_battle_group(DOMINANT_ID)
		for _light_index in range(BattleGroup.MAX_LIGHT_ARMIES):
			var light := state.create_army(
				DOMINANT_ID,
				dominant_capital,
				GameState.INITIAL_LIGHT_ARMY_SIZE,
				GameState.INITIAL_LIGHT_ARMY_SIZE
			)
			light.attack = 15
			light.defense = 15
			assert(state.assign_army_to_battle_group(light, group.id))
		for _heavy_index in range(BattleGroup.MAX_HEAVY_ARMIES):
			var heavy := state.create_army(
				DOMINANT_ID,
				dominant_capital,
				GameState.INITIAL_HEAVY_ARMY_SIZE,
				GameState.INITIAL_HEAVY_ARMY_SIZE
			)
			heavy.attack = 15
			heavy.defense = 15
			assert(state.assign_army_to_battle_group(heavy, group.id))
	state.refresh_derived()
	return state


func _env_int(key: String, fallback: int) -> int:
	var raw := OS.get_environment(key)
	return int(raw) if not raw.is_empty() else fallback
