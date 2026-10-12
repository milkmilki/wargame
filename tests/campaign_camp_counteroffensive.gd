extends SceneTree

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_test_lost_camp_releases_front_and_cools_component()
	_test_inflight_and_blocked_detachments_withdraw()
	_test_cooldown_preserves_another_active_front()
	_test_parallel_engagement_defers_release()
	_test_captured_center_is_not_camp_failure()
	_test_center_capture_after_recorded_camp_loss_continues_cleanup()
	_test_nonhostile_camp_change_is_not_defeat()
	_test_real_camp_capture_becomes_counteroffensive()
	_test_real_camp_capture_becomes_counteroffensive(true)
	for message in failures:
		push_error("CAMP_COUNTEROFFENSIVE_FAIL: " + message)
	print("CAMP_COUNTEROFFENSIVE_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _state() -> GameState:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.rng.seed = 96417
	for nation_id in range(2):
		var nation := Nation.new()
		nation.id = nation_id
		nation.capital_city_id = 0 if nation_id == 0 else 3
		nation.treasury_gold = 1000000
		nation.manpower_pool = 0
		nation.warehouse_city_ids = [nation.capital_city_id] as Array[int]
		state.nations.append(nation)
	for city_id in range(9):
		var city := City.new()
		city.id = city_id
		city.owner_nation = 0 if city_id < 3 else 1
		city.map_position = Vector2(city_id, 0)
		city.food_storage = 1000000
		city.food_per_half_year = 100000
		city.gold_per_month = 10000
		city.has_warehouse = city_id in [0, 3]
		city.garrison_manpower = 1000 if city_id in [0, 3, 6] else 0
		state.cities.append(city)
		state.adjacency[city_id] = [] as Array[int]
		state.region_ids.append(0)
		state.administrative_center_by_city.append((city_id / 3) * 3)
		state.recognized_city_owners.append(city.owner_nation)
	state.administrative_center_city_ids = [0, 3, 6] as Array[int]
	for pair in [[0, 1], [1, 2], [2, 4], [4, 3], [3, 5], [2, 7], [7, 6], [6, 8], [3, 6]]:
		state._add_edge(pair[0], pair[1])
		state.edge_of(pair[0], pair[1]).distance = 0.1
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0, 1, 3, "camp counteroffensive fixture")
	state.day = 100
	return state


func _army(state: GameState, id: int, owner: int, city_id: int, size: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner
	army.location_city = city_id
	army.move_from = city_id
	army.size = size
	army.max_size = maxi(15000, size)
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	state.armies.append(army)
	return army


func _front(state: GameState, center: int, camp: int, troops: Array[Army]) -> CoalitionCampaignFront:
	var front := state.create_campaign_front(
		state.war_id_between(0, 1), [0] as Array[int], 0,
		CoalitionCampaignFront.Mode.OFFENSE, center
	)
	front.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	front.camp_city_id = camp
	front.staging_city_id = 2
	for army in troops:
		army.campaign_war_id = front.war_id
		army.campaign_front_id = front.front_id
		front.army_assignments[army.id] = camp
	return front


func _component(state: GameState, owner: int) -> Dictionary:
	for component in state.coalition_campaign_components():
		if (component["members"] as Array[int]).has(owner):
			return component
	return {}


func _cooldown(state: GameState, war_id: int, members: Array[int]) -> int:
	_check(state.has_method("campaign_offensive_cooldown_until"),
		"GameState must expose the component offense cooldown query")
	if not state.has_method("campaign_offensive_cooldown_until"):
		return -1
	return int(state.call("campaign_offensive_cooldown_until", war_id, members))


func _test_lost_camp_releases_front_and_cools_component() -> void:
	var state := _state()
	var idle := _army(state, 10, 0, 2, 15000)
	var moving := _army(state, 11, 0, 2, 15000)
	moving.state = Army.State.MOVING
	moving.on_edge = true
	moving.move_to = 4
	moving.move_progress = 0.4
	moving.ai_target_city = 4
	var front := _front(state, 3, 4, [idle, moving])
	var war_id := front.war_id
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(front)
	_check(state.campaign_front(front.front_id) == null,
		"lost enemy-controlled camp must release the failed offensive front")
	_check(idle.campaign_front_id == -1 and moving.campaign_front_id == -1,
		"failed front must release both idle and moving state bindings")
	_check(idle.campaign_war_id == war_id and moving.campaign_war_id == war_id,
		"camp failure must retain the original war pool for all survivors")
	_check(moving.on_edge and moving.move_from == 2 and moving.move_to == 4
		and is_equal_approx(moving.move_progress, 0.4),
		"camp failure must not reverse or teleport the current movement leg")
	_check(idle.size == 15000 and is_equal_approx(idle.morale, idle.max_morale),
		"administrative release must not cause rout losses or morale reset")
	_check(_cooldown(state, war_id, [0] as Array[int]) == 160,
		"camp loss at day100 must cool all new offense through day160")
	state.day = 110
	sim._plan_coalition_component(_component(state, 0), [] as Array[int], {})
	_check(state.campaign_fronts_for_nation(0, war_id, CoalitionCampaignFront.Mode.OFFENSE).is_empty(),
		"released war-pool troops must not immediately recreate the lost offense")
	_check(_cooldown(state, war_id, [0] as Array[int]) == 160,
		"repeat planning must not renew the same defeat's sixty-day deadline")
	# A pending state remains occupied while the released army is still approaching it.
	for _step in range(20):
		sim._advance_movement()
	_check(not moving.on_edge and moving.location_city == 2
		and moving.state in [Army.State.IDLE, Army.State.RECOVERING],
		"deadline test must first let the released incoming army physically withdraw")
	state.day = 160
	sim._plan_coalition_component(_component(state, 0), [] as Array[int], {})
	_check(not state.campaign_fronts_for_nation(0, war_id, CoalitionCampaignFront.Mode.OFFENSE).is_empty(),
		"offense creation must resume when the original cooldown expires")
	if state.campaign_fronts_for_nation(0, war_id, CoalitionCampaignFront.Mode.OFFENSE).is_empty():
		print("CAMP_EXPIRY_DIAG pairs=%s" % state.campaign_pairs.values().map(func(pair: CoalitionCampaignPair) -> Dictionary:
			return {"slots": pair.battlefields, "cooldowns": pair.cooldown_until_by_nation}))
		for troop in state.armies:
			print("CAMP_EXPIRY_DIAG army=%d state=%d city=%d target=%d action=%d locked=%d" % [
				troop.id, troop.state, troop.location_city, troop.ai_target_city, troop.ai_action, troop.ai_order_until_day])
	sim.free()


func _test_cooldown_preserves_another_active_front() -> void:
	var state := _state()
	state.cities[7].owner_nation = 0
	state.ownership_revision += 1
	var failed_troop := _army(state, 20, 0, 2, 15000)
	var surviving_troop := _army(state, 21, 0, 7, 15000)
	var lost := _front(state, 3, 4, [failed_troop])
	var active := _front(state, 6, 7, [surviving_troop])
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(lost)
	sim._plan_coalition_component(_component(state, 0), [] as Array[int], {})
	_check(state.campaign_front(lost.front_id) == null,
		"failed first front must not remain beside the surviving front")
	_check(state.campaign_front(active.front_id) != null
		and surviving_troop.campaign_front_id == active.front_id,
		"component cooldown must not close or detach its existing second offense")
	_check(state.campaign_fronts_for_nation(0, lost.war_id, CoalitionCampaignFront.Mode.OFFENSE).size() == 1,
		"cooldown permits the surviving offense but prohibits a replacement front")
	sim.free()


func _test_inflight_and_blocked_detachments_withdraw() -> void:
	var state := _state()
	var inflight := _army(state, 70, 0, 2, 15000)
	inflight.state = Army.State.MOVING
	inflight.on_edge = true
	inflight.move_to = 4
	inflight.move_progress = 0.4
	inflight.ai_target_city = 3
	inflight.path = [3] as Array[int]
	var blocked := _army(state, 71, 0, 1, 15000)
	blocked.state = Army.State.MOVING
	blocked.on_edge = false
	blocked.move_to = 2
	blocked.ai_target_city = 3
	blocked.path = [4, 3] as Array[int]
	var front := _front(state, 3, 4, [inflight, blocked])
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false
	sim._manage_administrative_campaign(front)
	_check(inflight.on_edge and inflight.move_from == 2 and inflight.move_to == 4
		and is_equal_approx(inflight.move_progress, 0.4),
		"released inflight detachment must finish the original physical leg")
	_check(inflight.ai_action == ActionCandidate.Kind.RETREAT and inflight.ai_target_city == 2,
		"inflight detachment must replace its future attack with a withdrawal order")
	_check(blocked.ai_action == ActionCandidate.Kind.RETREAT and blocked.ai_target_city == 2
		and blocked.state == Army.State.MOVING and blocked.move_to == 2,
		"off-edge blocked mover must replace the stale attack with executable withdrawal")
	var visited_enemy_endpoint := false
	var stale_battle := false
	for _step in range(20):
		sim._advance_day()
		visited_enemy_endpoint = visited_enemy_endpoint or inflight.location_city == 4 or inflight.move_from == 4
		for battle in state.battles:
			if battle.city != null and battle.city.id in [3, 4]:
				stale_battle = true
		if (inflight.location_city == 2 and inflight.state == Army.State.IDLE
				and blocked.location_city == 2 and blocked.state == Army.State.IDLE):
			break
	_check(visited_enemy_endpoint,
		"withdrawal must first finish the old leg and physically reach its enemy endpoint")
	_check(not stale_battle and state.cities[4].owner_nation == 1,
		"released detachments must not reopen siege or occupy Fu at the old endpoint")
	_check(inflight.location_city == 2 and inflight.state == Army.State.IDLE
		and blocked.location_city == 2 and blocked.state == Army.State.IDLE,
		"both detachments must actually return along legal paths to the staging city")
	_check(inflight.size == 15000 and blocked.size == 15000,
		"camp-failure administrative withdrawal must not apply rout casualties")
	_check(inflight.campaign_war_id == front.war_id and blocked.campaign_war_id == front.war_id
		and inflight.campaign_front_id == -1 and blocked.campaign_front_id == -1,
		"withdrawn detachments must retain only their original war-pool binding")
	sim.free()


func _test_parallel_engagement_defers_release() -> void:
	var state := _state()
	var first_troop := _army(state, 30, 0, 2, 15000)
	var second_troop := _army(state, 31, 0, 2, 15000)
	var front := _front(state, 3, 4, [first_troop, second_troop])
	var sim := Simulation.new()
	sim.setup(state)
	var battles: Array[Battle] = []
	for index in range(2):
		var own := first_troop if index == 0 else second_troop
		var enemy := _army(state, 32 + index, 1, 2, 15000)
		own.state = Army.State.FIGHTING
		enemy.state = Army.State.FIGHTING
		var battle := state.new_battle(Battle.Kind.FIELD)
		battle.side_a.append(own)
		battle.side_b.append(enemy)
		own.battle_id = battle.id
		enemy.battle_id = battle.id
		sim._lock_campaign_reports_for_battle(battle)
		battles.append(battle)
	sim._manage_administrative_campaign(front)
	_check(state.campaign_front(front.front_id) != null and front.combat_report_locked,
		"camp loss must retain a locked front while its parallel field battles remain")
	_check(_cooldown(state, front.war_id, [0] as Array[int]) == 160,
		"pending field battles must not postpone recording the camp-loss cooldown")
	battles[0].finished = true
	sim._finish_campaign_reports_for_battle(battles[0])
	_check(front.combat_report_locked and state.campaign_front(front.front_id) != null,
		"first parallel field finish must not unlock or release the failed front")
	battles[1].finished = true
	sim._finish_campaign_reports_for_battle(battles[1])
	state.day += 1
	sim._plan_coalition_component(_component(state, 0), [] as Array[int], {})
	_check(state.campaign_front(front.front_id) == null,
		"last field report must permit release on the next planning day")
	_check(first_troop.campaign_war_id == front.war_id and second_troop.campaign_war_id == front.war_id,
		"deferred release must preserve both survivors' war pool")
	sim.free()


func _test_captured_center_is_not_camp_failure() -> void:
	var state := _state()
	state.cities[3].owner_nation = 0
	state.ownership_revision += 1
	var army := _army(state, 40, 0, 3, 15000)
	var front := _front(state, 3, 4, [army])
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(front)
	_check(state.campaign_front(front.front_id) != null and front.camp_city_id == 3,
		"captured center must become cleanup camp even if its old camp was lost")
	_check(_cooldown(state, front.war_id, [0] as Array[int]) <= state.day,
		"captured-center cleanup must not create an offensive defeat cooldown")
	sim.free()


func _test_real_camp_capture_becomes_counteroffensive(conqueror: bool = false) -> void:
	# The old proactive camp sortie is replaced by actual capital relief.
	var state:=_state();state.armies.clear();state.battles.clear()
	for city in state.cities:
		city.loyalty_target_nation=city.owner_nation
		city.is_capital=city.id in [0,3]
	var attacker:=_army(state,8000,0,3,10000)
	var defender:=_army(state,8001,1,4,60000)
	if conqueror:state.nations[1].ruler_archetype=RulerProfile.Archetype.CONQUEROR
	var offense:=_front(state,3,2,[attacker]);offense.phase=CoalitionCampaignFront.Phase.BLOCKADE_ONLY
	var defense:=state.create_campaign_front(offense.war_id,[1] as Array[int],1,CoalitionCampaignFront.Mode.DEFENSE,3)
	defender.campaign_front_id=defense.front_id;defender.campaign_war_id=defense.war_id;defense.army_assignments[defender.id]=4
	var battle:=state.new_battle(Battle.Kind.SIEGE);battle.city=state.cities[3];battle.siege_attacker_nation=0;battle.side_a=[attacker] as Array[Army]
	attacker.state=Army.State.FIGHTING;attacker.battle_id=battle.id
	state.cities[3].garrison_manpower=60000
	state.refresh_derived()
	var sim:=Simulation.new();sim.setup(state);sim.diplomacy_enabled=false
	sim._execute_coalition_defense(defense)
	_check(defense.phase==CoalitionCampaignFront.Phase.RELIEVE_CENTER and defender.ai_target_city==3,"real rear force receives center relief order")
	var relieved:=false
	for day in range(180):
		sim._advance_movement()
		if sim._siege_battle_of(state.cities[3])==null:relieved=true;break
	_check(relieved and state.cities[3].owner_nation==1,"real city field victory relieves the capital")
	_check(attacker.state in [Army.State.RETREATING,Army.State.RECOVERING] or attacker.size<=0,"defeated attacker retreats or is encircled")
	_check(defender.size>0 and defender.location_city==3,"victorious relief force holds the center")
	_check(state.territory_structure_valid(),"actual relief preserves territory structure")
	sim.free()


func _test_center_capture_after_recorded_camp_loss_continues_cleanup() -> void:
	var state := _state()
	var army := _army(state, 80, 0, 3, 15000)
	var front := _front(state, 3, 4, [army])
	var sim := Simulation.new()
	sim.setup(state)
	# Occupation can record the camp loss before a parallel siege captures the center.
	sim._record_campaign_camp_failure(front)
	_check(front.failed_until_day == 160,
		"fixture must first register an actual camp-loss deadline")
	var pair: Variant = state.call("find_campaign_pair", front.war_id, 0, 1)
	_check(pair != null and bool(pair.get("battlefields")[front.battlefield_slot]["counterattack"]),
		"recorded camp defeat must initially offer the original defender a counterattack succession")
	state.cities[3].owner_nation = 0
	state.ownership_revision += 1
	state.day += 1
	sim._manage_administrative_campaign(front)
	_check(state.campaign_front(front.front_id) != null
		and front.phase == CoalitionCampaignFront.Phase.CLEANUP and front.camp_city_id == 3,
		"subsequent center capture must bypass the recorded camp-loss guard and continue cleanup")
	_check(army.campaign_front_id == front.front_id and army.campaign_war_id == front.war_id,
		"successful center capture must retain the army for the existing cleanup front")
	var slot: Dictionary = pair.get("battlefields")[front.battlefield_slot] if pair != null else {}
	_check(not bool(slot.get("counterattack", true)) and int(slot.get("preferred_nation_id", -1)) == 0,
		"parallel successful center capture must cancel the defender's obsolete counterattack priority")
	_check(_cooldown(state, front.war_id, [0] as Array[int]) == 160,
		"cleanup must not unconditionally delete a shared war cooldown that another defeat may need")
	sim.free()


func _test_nonhostile_camp_change_is_not_defeat() -> void:
	var state := _state()
	var neutral := Nation.new()
	neutral.id = 2
	neutral.capital_city_id = 6
	state.nations.append(neutral)
	state.cities[4].owner_nation = 2
	state.cities[6].owner_nation = 2
	state.ownership_revision += 1
	var army := _army(state, 60, 0, 2, 15000)
	var front := _front(state, 3, 4, [army])
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(front)
	_check(front.failed_until_day <= state.day,
		"neutral third-party camp ownership must not become a hostile camp defeat")
	_check(_cooldown(state, front.war_id, [0] as Array[int]) <= state.day,
		"neutral camp changes must not cool new offense across the entire war")
	sim.free()
