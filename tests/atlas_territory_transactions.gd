extends SceneTree
## Small Atlas fixture: fixed州/府 administration plus one ownerless traffic node.
## No Earth cache; captures and peace cleanup use the real runtime lifecycle.

const TRAFFIC_ID := 14
const ORDINARY_CENTER := 4

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_ownerless_traffic_and_real_transaction()
	_test_traffic_cannot_receive_territory()
	_test_center_capture_defects_only_enemy_fu()
	_test_capital_victory(false)
	_test_capital_victory(true)
	for message in _failures:
		push_error("ATLAS_TERRITORY_FAIL: " + message)
	print("ATLAS_TERRITORY_%s checks=%d failures=%d" % [
		"OK" if _failures.is_empty() else "FAILED", _checks, _failures.size(),
	])
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _fixture(mixed_fu: bool = false) -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state._reset_world(94160)
	state._generate_nations(GameState.DiplomaticRelation.NEUTRAL, 4, false)
	state.trade_enabled = false
	var members: Array = [[0, 5], [1, 6, 7, 8], [2, 9], [3, 10], [4, 11, 12, 13]]
	var center_by_city := PackedInt32Array([0, 1, 2, 3, 4, 0, 1, 1, 1, 2, 3, 4, 4, 4])
	var owners: Array[int] = [0, 1, 2, 3, 1, 0, 1, 1, 1, 2, 3, 1, 1, 1]
	if mixed_fu:
		owners[12] = 2
		owners[13] = 3
	for city_id in range(TRAFFIC_ID + 1):
		var city := City.new()
		city.id = city_id
		city.name = "夹具城%d" % city_id
		city.short_name = String.chr(0x4e00 + city_id)
		city.map_position = Vector2(float(city_id % 5) * 0.15, float(city_id / 5) * 0.15)
		if city_id == TRAFFIC_ID:
			city.node_kind = City.NodeKind.TRAFFIC
			city.politically_active = false
		else:
			city.owner_nation = owners[city_id]
			city.loyalty_target_nation = owners[city_id]
			city.manpower_per_month = 10000
			city.gold_per_month = 100
			city.food_per_half_year = 100000
		state.cities.append(city)
		state.adjacency[city_id] = [] as Array[int]
		state.region_ids.append(-1 if city.is_traffic else center_by_city[city_id])
		state.recognized_city_owners.append(city.owner_nation)
	var pairs: Array[Vector2i] = [Vector2i(0, 4), Vector2i(1, 4), Vector2i(1, 2), Vector2i(2, 3)]
	for group in members:
		for index in range(1, group.size()):
			pairs.append(Vector2i(group[0], group[index]))
	var settlement_adjacency := {}
	for city_id in range(TRAFFIC_ID):
		settlement_adjacency[city_id] = [] as Array[int]
	for pair in pairs:
		(settlement_adjacency[pair.x] as Array[int]).append(pair.y)
		(settlement_adjacency[pair.y] as Array[int]).append(pair.x)
		if pair == Vector2i(0, 4):
			continue
		state._add_edge(pair.x, pair.y)
	state._add_edge(0, TRAFFIC_ID)
	state._add_edge(TRAFFIC_ID, 4)
	for edge in state.edges:
		edge.max_manpower = 50000
		edge.base_max_manpower = 50000
		edge.control_city_id = 4 if edge.city_a == 4 else edge.city_a
	state.atlas_layout = {
		"model": "atlas-military-v1",
		"hierarchy": {
			"members": members,
			"center_by_city": center_by_city,
			"state_by_city": center_by_city.duplicate(),
			"state_parents": PackedInt32Array([0, 1, 2, 3, 4]),
		},
		"settlement_adjacency": settlement_adjacency,
		"territorial_pairs": pairs,
		"strategic_routes": {"0:4": [0, TRAFFIC_ID, 4]},
	}
	state.rebuild_administrative_regions()
	state._initialize_manpower_pools()
	state._initialize_capitals_and_warehouses()
	state.refresh_derived()
	return state


func _army(state: GameState, owner: int, city_id: int) -> Army:
	var army := Army.new()
	army.id = 941600 + state.armies.size()
	army.owner_nation = owner
	army.location_city = city_id
	army.move_from = city_id
	army.size = 15000
	army.max_size = 15000
	army.morale = army.max_morale
	state.armies.append(army)
	return army


func _capture(state: GameState, sim: Simulation, army: Army, city_id: int) -> Battle:
	var battle := state.new_battle(Battle.Kind.SIEGE)
	battle.city = state.cities[city_id]
	battle.siege_attacker_nation = army.owner_nation
	battle.siege_claimant_nation = army.owner_nation
	army.location_city = city_id
	army.move_from = city_id
	sim._enter_battle(battle, army, 1)
	sim._complete_siege_capture(battle)
	return battle


func _check_traffic(state: GameState, label: String) -> void:
	var city := state.cities[TRAFFIC_ID]
	_check(city.is_traffic and not city.is_dock and not city.is_settlement(), label + ": traffic retains node type")
	_check(city.owner_nation == -1 and state.recognized_owner_of(TRAFFIC_ID) == -1
		and city.occupation_sponsor_nation == -1, label + ": traffic remains unowned and unclaimed")
	_check(not city.politically_active and not city.is_capital and not city.has_warehouse
		and city.garrison_manpower == 0 and city.food_storage == 0
		and city.manpower_per_month == 0 and city.gold_per_month == 0
		and city.food_per_half_year == 0, label + ": traffic has no political or resource state")
	_check(state.administrative_center_of(TRAFFIC_ID) == -1
		and not state.is_zhou_city(TRAFFIC_ID), label + ": traffic has no administrative seat")


func _resource_fingerprint(state: GameState) -> Array:
	var resources: Array = []
	for nation in state.nations:
		resources.append([nation.id, nation.treasury_gold, nation.manpower_pool])
	for city in state.cities:
		resources.append([city.id, city.owner_nation, city.food_storage, city.garrison_manpower])
	for army in state.armies:
		resources.append([army.id, army.owner_nation, army.size, army.morale])
	return resources


func _test_ownerless_traffic_and_real_transaction() -> void:
	var state := _fixture()
	_check(state.territory_structure_valid(), "ownerless traffic must not invalidate a complete Atlas territory")
	var fixed_mapping := state.administrative_center_by_city.duplicate()
	state.rebuild_administrative_regions()
	_check(state.administrative_center_by_city == fixed_mapping,
		"fixed州/府 hierarchy survives an administrative rebuild with traffic")
	var no_op := state.apply_territory_transaction([] as Array[Dictionary])
	_check(bool(no_op.get("ok", false)), "ownerless traffic must not reject a no-op transaction: %s" % no_op)
	var result := state.apply_territory_transaction([{
		"city_id": 11, "controller_id": 0, "legal_owner_id": 1,
		"sponsor_id": 0, "reason": "atlas_fixture_occupation",
	}] as Array[Dictionary])
	_check(bool(result.get("ok", false)) and bool(result.get("changed", false)),
		"real settlement occupation must commit despite unrelated traffic: %s" % result)
	_check(state.cities[11].owner_nation == 0 and state.recognized_owner_of(11) == 1
		and state.cities[11].occupation_sponsor_nation == 0, "occupation preserves controller/legal/sponsor tuple")
	_check(state.territory_structure_valid(), "settlement transaction retains territory invariants")
	_check_traffic(state, "settlement transaction")
	state.cities[TRAFFIC_ID].politically_active = true
	_check(not state.territory_structure_valid(), "politically active traffic must fail the territory audit")
	state.cities[TRAFFIC_ID].politically_active = false
	state.cities[11].owner_nation = -1
	_check(not state.territory_structure_valid(), "ordinary settlement cannot inherit the ownerless traffic exception")
	var invalid_settlement := state.apply_territory_transaction([] as Array[Dictionary])
	_check(not bool(invalid_settlement.get("ok", false)),
		"transaction snapshot still rejects an ownerless ordinary settlement")


func _test_traffic_cannot_receive_territory() -> void:
	var state := _fixture()
	var revision := state.ownership_revision
	var result := state.apply_territory_transaction([{
		"city_id": TRAFFIC_ID, "controller_id": 0, "legal_owner_id": 0,
		"sponsor_id": -1, "reason": "invalid_traffic_claim",
	}] as Array[Dictionary])
	_check(not bool(result.get("ok", false)) and state.ownership_revision == revision,
		"traffic claim must reject atomically")
	_check_traffic(state, "rejected traffic claim")


func _test_center_capture_defects_only_enemy_fu() -> void:
	var state := _fixture(true)
	state.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var sim := Simulation.new()
	sim.setup(state)
	var captor := _army(state, 0, ORDINARY_CENTER)
	var battle := _capture(state, sim, captor, ORDINARY_CENTER)
	_check(battle.finished and battle.winner_side == 1, "ordinary state siege records actual attacking victory")
	for city_id in [ORDINARY_CENTER, 11]:
		_check(state.cities[city_id].owner_nation == 0 and state.recognized_owner_of(city_id) == 1
			and state.cities[city_id].occupation_sponsor_nation == 0,
			"captured州治 and hostile府 defect through real occupation: city%d" % city_id)
	_check(state.cities[12].owner_nation == 2 and state.recognized_owner_of(12) == 2,
		"third-party府 keeps controller and legal owner")
	_check(state.cities[13].owner_nation == 3 and state.recognized_owner_of(13) == 3,
		"allied府 keeps controller and legal owner")
	_check(state.nations[1].alive and state.is_enemy(0, 1), "ordinary州治 loss preserves defender capital and ongoing war")
	_check(state.territory_structure_valid(), "state defection retains territory invariants")
	_check_traffic(state, "state defection")
	sim.free()


func _test_capital_victory(counterattack: bool) -> void:
	var state := _fixture()
	# Nation 0 declares in both cases; only the battlefield winner changes.
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0, 1, ORDINARY_CENTER, "Atlas lifecycle regression")
	var war_id := state.war_id_between(0, 1)
	ChronicleRules.begin_war(state, war_id, [0], [1])
	_check(war_id >= 0 and state.war_chronicle_contexts[war_id].actor_ids == [0]
		and state.war_chronicle_contexts[war_id].target_ids == [1],
		"both victories retain nation0 as declaring actor and nation1 as declared target")
	var winner := 1 if counterattack else 0
	var loser := 0 if counterattack else 1
	var label := "defender counter-conquest" if counterattack else "initiator victory"
	var loser_city_ids: Array[int] = []
	for city in state.land_cities_of(loser):
		loser_city_ids.append(city.id)
	var target_capital := state.nations[loser].capital_city_id
	var winner_capital := state.nations[winner].capital_city_id
	state.cities[winner_capital].food_storage = 10000
	state.cities[target_capital].food_storage = 20000
	var expected_winner_food := 10000 + int(floor(20000.0 * GameState.TERRITORY_CAPTURE_SPOILS_RATE))
	var unaffected_resources: Array = []
	for nation_id in [2, 3]:
		var nation := state.nations[nation_id]
		unaffected_resources.append([nation.treasury_gold, nation.manpower_pool,
			state.cities[nation.capital_city_id].food_storage])
	var captor := _army(state, winner, state.nations[winner].capital_city_id)
	var loser_army := _army(state, loser, target_capital)
	for army in [captor, loser_army]:
		var front := state.create_campaign_front(war_id, [army.owner_nation] as Array[int],
			army.owner_nation, CoalitionCampaignFront.Mode.OFFENSE, target_capital)
		army.campaign_war_id = war_id
		army.campaign_front_id = front.front_id
		front.army_assignments[army.id] = target_capital
	var sim := Simulation.new()
	sim.setup(state)
	if not counterattack:
		_capture(state, sim, captor, ORDINARY_CENTER)
		_check(state.cities[ORDINARY_CENTER].owner_nation == winner
			and state.nations[loser].alive, label + ": ordinary州治 falls before capital")
	var battle := _capture(state, sim, captor, target_capital)
	sim._resolve_eliminated_nation_capitulations()
	ChronicleRules.finalize_pending(state)
	_check(battle.finished and battle.winner_side == 1 and battle.side_a.has(captor),
		label + ": capital capture keeps actual winner for replay")
	_check(state.nations[winner].alive and not state.nations[loser].alive,
		label + ": real territory commit extinguishes only defeated nation")
	for city_id in loser_city_ids:
		_check(state.cities[city_id].owner_nation == winner
			and state.recognized_owner_of(city_id) == winner
			and state.cities[city_id].occupation_sponsor_nation == -1,
			label + ": winner receives settled territory city%d" % city_id)
	_check(state.nations[loser].capital_city_id == -1 and state.nations[loser].warehouse_city_ids.is_empty(),
		label + ": eliminated nation clears capital and warehouse indices")
	_check(state.cities[winner_capital].owner_nation == winner
		and state.cities[winner_capital].food_storage == expected_winner_food
		and state.cities[target_capital].food_storage == 0,
		label + ": captured capital spoils credit actual winner's food pool once")
	for index in range(2):
		var nation := state.nations[index + 2]
		_check([nation.treasury_gold, nation.manpower_pool,
			state.cities[nation.capital_city_id].food_storage] == unaffected_resources[index],
			label + ": uninvolved nation%d retains treasury, manpower and food" % nation.id)
	_check(not state.is_enemy(0, 1) and state.war_id_between(0, 1) == -1
		and not state.war_relation_ids.values().has(war_id), label + ": normal capitulation releases war relation")
	_check(captor.state == Army.State.IDLE and captor.location_city == target_capital
		and captor.battle_id == -1 and captor.size == 15000,
		label + ": actual capturing army settles without duplicate losses")
	for army in state.armies:
		_check(army.campaign_war_id != war_id and army.campaign_front_id == -1,
			label + ": army%d releases finished war and campaign bindings" % army.id)
	for front in state.campaign_fronts.values():
		_check(front.war_id != war_id, label + ": completed war leaves no campaign front")
	_check(not state.war_chronicle_contexts.has(war_id), label + ": completed war releases chronicle ledger")
	var completed_wars := state.chronicle_events.filter(
		func(event: Dictionary) -> bool: return event.get("kind", "") == "external_war"
	)
	_check(completed_wars.size() == 1, label + ": real conquest records one completed external war")
	if completed_wars.size() == 1:
		var views: Dictionary = completed_wars[0].views
		_check(str(views.get(loser, "")).ends_with("国除")
			and not str(views.get(winner, "")).contains("国除"),
			label + ": each nation's final perspective follows actual survival")
	var event_count := state.chronicle_events.size()
	var ownership_revision := state.ownership_revision
	var resources := _resource_fingerprint(state)
	sim._resolve_eliminated_nation_capitulations()
	ChronicleRules.finalize_pending(state)
	_check(state.chronicle_events.size() == event_count and state.ownership_revision == ownership_revision,
		label + ": repeated eliminated-nation cleanup does not settle twice")
	_check(_resource_fingerprint(state) == resources,
		label + ": repeated cleanup preserves treasury, manpower, food, garrisons and armies")
	_check(state.territory_structure_valid(), label + ": territory invariants hold after actual conquest")
	_check_traffic(state, label)
	sim.free()
