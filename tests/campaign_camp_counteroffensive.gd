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
	var state := GameState.new()
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


func _test_real_camp_capture_becomes_counteroffensive(cross_region: bool = false) -> void:
	var state := _state()
	if cross_region:
		# Keep both rulers in their original regions; only this battle's succession may cross.
		for nation in state.nations:
			nation.ruler_traits = [RulerProfile.TRAIT_CAUTIOUS] as Array[String]
		state.nations[0].strategic_region_anchor_city_id = 0
		state.nations[1].strategic_region_anchor_city_id = 3
		for city_id in range(3, 9):
			state.region_ids[city_id] = 1
		for city_id in range(9, 12):
			var city := City.new()
			city.id = city_id
			city.owner_nation = 0
			city.map_position = Vector2(city_id, 0)
			city.food_storage = 1000000
			city.food_per_half_year = 100000
			city.gold_per_month = 10000
			city.garrison_manpower = 1000 if city_id == 9 else 0
			state.cities.append(city)
			state.adjacency[city_id] = [] as Array[int]
			state.region_ids.append(0)
			state.administrative_center_by_city.append(9)
			state.recognized_city_owners.append(0)
		state.administrative_center_city_ids.append(9)
		# The first counterattack must capture a non-capital state so the war can continue.
		state.nations[0].capital_city_id = 9
		state.nations[0].warehouse_city_ids.append(9)
		state.cities[9].has_warehouse = true
		for edge in [[1, 10], [10, 9], [9, 11]]:
			state._add_edge(edge[0], edge[1])
			state.edge_of(edge[0], edge[1]).distance = 0.1
		state.administrative_region_revision += 1
		state.regional_strategy_revision += 1
		_check(not RegionalStrategy.allows_objective(state, 1, 0)
			and not RegionalStrategy.allows_objective(state, 1, 9),
			"ordinary regional eligibility must forbid both enemy states before camp victory")
	state.cities[4].owner_nation = 0
	state.ownership_revision += 1
	var camp_guards: Array[Army] = []
	for index in range(3):
		var camp_guard := _army(state, 50 + index, 0, 4, 15000)
		camp_guard.attack = 1
		camp_guard.defense = 1
		camp_guards.append(camp_guard)
	var failed := _front(state, 3, 4, camp_guards)
	var defenders: Array[Army] = []
	for index in range(4):
		defenders.append(_army(state, 53 + index, 1, 3, 15000))
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false
	var captured_day := -1
	var captured_cooldown_until := -1
	var released_day := -1
	var counter_order_day := -1
	var attacker_defense_day := -1
	var counter_target := -1
	var counter_capture_day := -1
	var illegal_continuation := false
	var saw_camp_battle := false
	var premature_counter_order := false
	var cooldown_violations := 0
	var duplicate_bindings := 0
	for _step in range(600 if cross_region else 300):
		sim._advance_day()
		for battle in state.battles:
			if battle.city != null and battle.city.id == 4:
				saw_camp_battle = true
		if captured_day < 0 and state.cities[4].owner_nation == 1:
			captured_day = state.day
			captured_cooldown_until = int(state.call(
				"campaign_offensive_cooldown_until", failed.war_id, [0] as Array[int]))
		if captured_day < 0:
			for army in defenders:
				var current := state.campaign_front(army.campaign_front_id)
				if current != null and current.mode == CoalitionCampaignFront.Mode.OFFENSE:
					premature_counter_order = true
		if captured_day >= 0 and released_day < 0 and state.campaign_front(failed.front_id) == null:
			released_day = state.day
		if released_day >= 0:
			var until := int(state.call("campaign_offensive_cooldown_until", failed.war_id, [0] as Array[int]))
			if until > state.day and not state.campaign_fronts_for_nation(
					0, failed.war_id, CoalitionCampaignFront.Mode.OFFENSE).is_empty():
				cooldown_violations += 1
		var seen := {}
		for current in state.campaign_fronts.values():
			for army_id in current.army_assignments:
				if seen.has(army_id):
					duplicate_bindings += 1
				seen[army_id] = true
		if released_day >= 0:
			for army in defenders:
				var current := state.campaign_front(army.campaign_front_id)
				if (current != null and current.mode == CoalitionCampaignFront.Mode.OFFENSE
						and current.war_id == failed.war_id and army.state == Army.State.MOVING):
					if counter_order_day < 0:
						counter_order_day = state.day
						counter_target = current.center_city_id
		if counter_order_day >= 0:
			var defense := state.campaign_front_for(0, counter_target, CoalitionCampaignFront.Mode.DEFENSE, failed.war_id)
			if defense != null:
				if attacker_defense_day < 0:
					attacker_defense_day = state.day
				if not cross_region:
					break
		if cross_region and counter_target >= 0:
			if counter_capture_day < 0 and state.cities[counter_target].owner_nation == 1:
				counter_capture_day = state.day
			if counter_capture_day >= 0:
				for current in state.campaign_fronts_for_nation(1, failed.war_id, CoalitionCampaignFront.Mode.OFFENSE):
					if current.center_city_id != counter_target \
							and not RegionalStrategy.allows_objective(state, 1, current.center_city_id):
						illegal_continuation = true
				if state.day >= counter_capture_day + 30:
					break
	_check(saw_camp_battle and captured_day >= 0,
		"daily simulation must fight for and actually capture the hostile camp")
	_check(not premature_counter_order,
		"fixture must retain the defense force until the enemy camp is actually recaptured")
	_check(captured_cooldown_until == captured_day + 60,
		"offensive cooldown must start at actual camp capture, not the later planning day")
	_check(released_day >= captured_day and released_day >= 0,
		"actual camp capture must release the defeated offensive front")
	_check(counter_order_day >= released_day and counter_order_day >= 0,
		"original defender must execute same-war counteroffensive movement after recapture")
	_check(attacker_defense_day >= counter_order_day and attacker_defense_day >= 0,
		"real counteroffensive arrival or incoming orders must create original attacker's defense")
	_check(sim.ai_last_command_commit_failures == 0,
		"actual camp-to-counteroffense chain must not reject commands")
	_check(cooldown_violations == 0 and duplicate_bindings == 0,
		"daily counteroffense chain must have no cooldown violations or duplicate army bindings")
	if cross_region:
		_check(counter_target == 0 and not RegionalStrategy.allows_objective(state, 1, counter_target),
			"camp victory must permit an actual one-state counterattack outside the ruler's region")
		_check(counter_capture_day >= counter_order_day and counter_capture_day >= 0,
			"cross-region counterattack must actually capture its center, not merely create a plan")
		_check(state.nations[0].alive and state.nations[1].alive,
			"counterattack fixture must preserve both countries for next-state eligibility checks")
		_check(not illegal_continuation and state.day >= counter_capture_day + 30,
			"completed counterattack must not grant unrestricted out-of-region next-state conquest")
	if counter_order_day < 0:
		for army in state.armies:
			print("CAMP_COUNTER_DIAG army=%d owner=%d size=%d state=%d location=%d target=%d war=%d front=%d supply=%f morale=%f deploy=%d until=%d" % [
				army.id, army.owner_nation, army.size, army.state, army.location_city, army.ai_target_city,
				army.campaign_war_id, army.campaign_front_id, army.supply_ratio, army.morale,
				army.defensive_deployment_until_day, army.ai_order_until_day])
		for current in state.campaign_fronts.values():
			print("CAMP_COUNTER_DIAG front=%d mode=%d center=%d camp=%d members=%s phase=%d assigned=%s" % [
				current.front_id, current.mode, current.center_city_id, current.camp_city_id,
				current.participant_nation_ids, current.phase, current.army_assignments])
		print("CAMP_COUNTER_DIAG owners=%s context=%s" % [
			state.cities.map(func(city: City) -> int: return city.owner_nation),
			state.campaign_defense_context(1, 3, failed.war_id)])
		print("CAMP_COUNTER_DIAG allocation=%s" % state.coalition_campaign_allocation(failed.war_id, 1))
	print("CAMP_COUNTEROFFENSIVE_METRICS capture=%d release=%d counter_order=%d new_defense=%d cooldown_violations=%d duplicate_bindings=%d cross_region=%s counter_target=%d counter_capture=%d" % [
		captured_day, released_day, counter_order_day, attacker_defense_day,
		cooldown_violations, duplicate_bindings, cross_region, counter_target, counter_capture_day])
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
