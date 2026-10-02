extends SceneTree

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_test_initial_base()
	_test_regroup_priority()
	_test_camp_context()
	_test_context_routes_and_promotion()
	_test_entry_cache_revisions()
	_test_shared_base_failure()
	_test_base_display_and_snapshot()
	_test_real_rout_and_second_wave()
	_test_real_capture_chain(false)
	_test_real_capture_chain(true)
	for message in failures:
		push_error("DIRECT_CENTER_CAMP_FAIL: " + message)
	print("DIRECT_CENTER_CAMP_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


static func fixture() -> GameState:
	var state := GameState.new()
	state.world_seed = 96481
	state.rng.seed = state.world_seed
	state.day = 100
	for owner in range(3):
		var nation := Nation.new()
		nation.id = owner
		nation.capital_city_id = [0, 3, 5][owner]
		nation.strategic_region_anchor_city_id = nation.capital_city_id
		nation.treasury_gold = 1000000
		nation.granary_food = 1000000
		nation.manpower_pool = 0
		nation.ruler_started_day = state.day
		nation.warehouse_city_ids = [nation.capital_city_id] as Array[int]
		state.nations.append(nation)
	for id in range(8):
		var city := City.new()
		city.id = id
		city.owner_nation = 1 if id in [3, 4] else (2 if id == 5 else 0)
		city.map_position = Vector2(float(id) / 7.0, 0)
		city.food_storage = 1000000
		city.food_per_half_year = 100000
		city.gold_per_month = 10000
		city.garrison_manpower = 1000 if id in [0, 3, 5, 6] else 0
		city.has_warehouse = id in [0, 3, 5, 6]
		state.cities.append(city)
		state.adjacency[id] = [] as Array[int]
		state.recognized_city_owners.append(city.owner_nation)
		state.region_ids.append(0)
		state.administrative_center_by_city.append(0 if id < 3 else (3 if id < 5 else (5 if id == 5 else 6)))
	state.administrative_center_city_ids = [0, 3, 5, 6] as Array[int]
	for pair in [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [1, 6], [6, 7]]:
		state._add_edge(pair[0], pair[1])
		state.edge_of(pair[0], pair[1]).distance = 0.1
	for a in range(3):
		for b in range(a + 1, 3):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	state.set_war_objective(0, 1, 3, "direct center camp fixture")
	return state


static func army(state: GameState, owner: int, city: int, size: int = 15000) -> Army:
	var troop := Army.new()
	troop.id = state.armies.size()
	troop.owner_nation = owner
	troop.location_city = city
	troop.move_from = city
	troop.size = size
	troop.max_size = maxi(15000, size)
	troop.morale = troop.max_morale
	state.armies.append(troop)
	return troop


static func front(state: GameState, troops: Array[Army]) -> CoalitionCampaignFront:
	var plan := state.create_campaign_front(state.war_id_between(0, 1), [0] as Array[int], 0, CoalitionCampaignFront.Mode.OFFENSE, 3)
	plan.staging_city_id = 2
	for troop in troops:
		troop.campaign_war_id = plan.war_id
		troop.campaign_front_id = plan.front_id
		plan.army_assignments[troop.id] = 2
	return plan


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _test_initial_base() -> void:
	for direct in [true, false]:
		var state := fixture()
		if not direct:
			state.edge_of(2, 3).max_manpower = 0
			state._add_edge(2, 4)
			state.road_network_revision += 1
		state.cities[3].garrison_manpower = 100000
		var troop := army(state, 0, 2)
		var plan := front(state, [troop])
		var sim := Simulation.new()
		sim.setup(state)
		sim._manage_administrative_campaign(plan)
		_check(plan.camp_city_id == (2 if direct else -1), "only direct-center fronts use the original assembly node as camp")
		_check(plan.phase == CoalitionCampaignFront.Phase.ASSEMBLE, "having a rear base is not evidence of captured fu or readiness")
		if direct:
			state.edge_of(2, 3).max_manpower = 0
			state.road_network_revision += 1
			_check(not sim._campaign_front_has_entry(plan), "a legal rear base does not mask a disconnected target")
		sim.free()


func _test_regroup_priority() -> void:
	var state := fixture()
	var weak := army(state, 0, 2, 3000)
	var fighting := army(state, 0, 3)
	var enemy := army(state, 1, 3, 60000)
	var plan := front(state, [weak, fighting])
	plan.camp_city_id = 2
	plan.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	var siege := state.new_battle(Battle.Kind.SIEGE)
	siege.city = state.cities[3]
	siege.siege_attacker_nation = 0
	siege.side_a.append(fighting)
	siege.side_b.append(enemy)
	fighting.state = Army.State.FIGHTING
	enemy.state = Army.State.FIGHTING
	fighting.battle_id = siege.id
	enemy.battle_id = siege.id
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(plan)
	_check(plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP and weak.is_at_city_node(2), "a residual siege cannot send an understrength regrouping force back into assault")
	_check(fighting.state == Army.State.FIGHTING and siege.has_army(fighting), "regrouping never administratively terminates another engagement")
	sim.free()


func _test_camp_context() -> void:
	var state := fixture()
	var troop := army(state, 0, 2)
	var plan := front(state, [troop])
	plan.camp_city_id = 2
	plan.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	var context := state.campaign_defense_context(1, 3, plan.war_id)
	_check(bool(context["active"]) and (context.get("enemy_camp_ids", []) as Array).has(2), "a populated direct rear camp remains a task of the original battlefield")
	_check(int(context["enemy_manpower"]) == 15000, "effective rear camp force contributes once to sortie demand")
	troop.state = Army.State.RECOVERING
	context = state.campaign_defense_context(1, 3, plan.war_id)
	_check(bool(context["active"]) and int(context["enemy_manpower"]) == 0 and int(context["requirement"]) == GameState.INITIAL_HEAVY_ARMY_SIZE, "recovering camp troops keep the task alive but never inflate effective manpower")
	troop.size = 0
	_check(not bool(state.campaign_defense_context(1, 3, plan.war_id)["active"]), "an empty base never keeps a defense task alive")
	state.nations[2].alive = true
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	_check(not bool(state.campaign_defense_context(2, 3, state.war_id_between(0, 2))["active"]), "rear bases cannot leak into a different war")
	troop.size = 15000
	plan.retiring = true
	_check(not bool(state.campaign_defense_context(1, 3, plan.war_id)["active"]), "a retired front cannot keep a rear-camp task alive")


func _test_context_routes_and_promotion() -> void:
	var state := fixture()
	var troop := army(state, 0, 2)
	var plan := front(state, [troop])
	plan.camp_city_id = 2
	troop.on_edge = true
	troop.state = Army.State.MOVING
	troop.move_to = 3
	troop.ai_target_city = 3
	troop.ai_action = ActionCandidate.Kind.ATTACK
	_check(int(state.campaign_defense_context(1, 3, plan.war_id)["enemy_manpower"]) == 15000, "incoming force at the base boundary is never counted twice")
	troop.state = Army.State.RETREATING
	troop.move_from = 3
	troop.move_to = 2
	_check((state.campaign_defense_context(1, 3, plan.war_id)["enemy_camp_ids"] as Array[int]) == [2], "physical retreat preserves the base task without effective manpower")
	state.edge_of(2, 3).max_manpower = 0
	state.road_network_revision += 1
	_check(not bool(state.campaign_defense_context(1, 3, plan.war_id)["active"]), "a broken return route is not a live base task")
	troop.on_edge = false
	troop.state = Army.State.IDLE
	troop.location_city = 2
	troop.move_from = 2
	troop.move_to = -1
	state.edge_of(2, 3).max_manpower = 30000
	state.cities[4].owner_nation = 0
	state.ownership_revision += 1
	state.road_network_revision += 1
	var sim := Simulation.new()
	sim.setup(state)
	sim._campaign_receiving_city(plan)
	_check(plan.camp_city_id == 2, "an isolated controlled fu behind the hostile center is not a usable forward base")
	state._add_edge(2, 4)
	state.road_network_revision += 1
	sim._campaign_receiving_city(plan)
	_check(plan.camp_city_id == 4 and state.campaign_has_forward_camp(plan), "captured fu advances the base instead of preserving the rear camp forever")
	sim.free()
	state = fixture()
	troop = army(state, 0, 2)
	plan = front(state, [troop])
	plan.camp_city_id = 2
	state.cities[2].owner_nation = 2
	state.ownership_revision += 1
	sim = Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(plan)
	_check(plan.failed_until_day <= state.day and state.campaign_offensive_cooldown_until(plan.war_id, [0] as Array[int]) <= state.day, "third-party base control is not a camp defeat")
	sim.free()


func _test_entry_cache_revisions() -> void:
	var state := fixture()
	var sim := Simulation.new()
	sim.setup(state)
	_check(sim._campaign_entry_fu(0, 3, [0] as Array[int]) == -1, "entry cache records a genuinely inaccessible rear fu")
	_check(sim._campaign_entry_fu(1, 0, [1] as Array[int]) == 2, "entry caches separate the proposing countries")
	state._add_edge(2, 4)
	state.road_network_revision += 1
	_check(sim._campaign_entry_fu(0, 3, [0] as Array[int]) == 4, "opening a real fu entry invalidates a cached empty result")
	state.edge_of(2, 4).max_manpower = 0
	state.road_network_revision += 1
	_check(sim._campaign_entry_fu(0, 3, [0] as Array[int]) == -1, "road closure invalidates the cached entry")
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	_check(sim._campaign_entry_fu(0, 3, [0, 2] as Array[int]) == 4, "wartime allied staging refreshes after diplomacy changes")
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	_check(sim._campaign_entry_fu(0, 3, [0] as Array[int]) == -1, "lost allied access cannot reuse an obsolete staging result")
	sim.free()


func _test_shared_base_failure() -> void:
	var state := fixture()
	state.cities[6].owner_nation = 1
	state.cities[7].owner_nation = 1
	state.ownership_revision += 1
	var first := front(state, [army(state, 0, 2)])
	first.camp_city_id = 2
	var second := state.create_campaign_front(first.war_id, [0] as Array[int], 0, CoalitionCampaignFront.Mode.OFFENSE, 6)
	second.staging_city_id = 2
	second.camp_city_id = 2
	var other := army(state, 0, 2)
	other.campaign_front_id = second.front_id
	other.campaign_war_id = second.war_id
	second.army_assignments[other.id] = 2
	_check(int(state.campaign_defense_context(1, 3, first.war_id)["enemy_manpower"]) == 15000, "shared physical base does not mix the troops of two target states")
	state.cities[2].owner_nation = 1
	state.ownership_revision += 1
	var sim := Simulation.new()
	sim.setup(state)
	sim._manage_administrative_campaign(first)
	sim._manage_administrative_campaign(second)
	_check(state.campaign_front(first.front_id) == null and state.campaign_front(second.front_id) == null, "one captured base retires both dependent fronts without relocating the lost base")
	_check(state.campaign_offensive_cooldown_until(first.war_id, [0] as Array[int]) == 160, "shared-base defeats do not stack or extend the cooldown")
	for troop in state.armies:
		_check(troop.campaign_front_id == -1 and troop.campaign_war_id == first.war_id and troop.size == 15000, "shared-base release preserves the original war pool and does not add rout losses")
	sim.free()


func _test_base_display_and_snapshot() -> void:
	var state := fixture()
	var plan := front(state, [army(state, 0, 2)])
	plan.camp_city_id = 2
	var lines := MapRenderer._nation_campaign_detail_lines(state, 0, plan, state.coalition_campaign_allocation(plan.war_id, 0))
	_check(lines.filter(func(line: String) -> bool: return line.begins_with("集结点／大营：")).size() == 1, "nation display combines coincident assembly and base")
	_check(lines.filter(func(line: String) -> bool: return line.begins_with("大营：")).is_empty(), "nation display never repeats the same base manpower")
	var sections := MapRenderer.city_detail_sections(state, 3)
	var city_lines: Array[String] = []
	for section in sections:
		city_lines.append_array(section["lines"])
	_check(city_lines.filter(func(line: String) -> bool: return line.begins_with("集结点／大营：")).size() == 1 and city_lines.filter(func(line: String) -> bool: return line.begins_with("大营：")).is_empty(), "city display also combines the two roles")
	var snapshot := NativeSnapshotBuilder.build(state)
	_check((snapshot["campaign_fronts"]["camp_cities"] as PackedInt32Array)[0] == 2, "existing native snapshot camp field records a rear base without schema additions")


func _test_real_rout_and_second_wave() -> void:
	var state := fixture()
	var attacker := army(state, 0, 3)
	var defender := army(state, 1, 3)
	var plan := front(state, [attacker])
	plan.phase = CoalitionCampaignFront.Phase.ASSAULT_CENTER
	attacker.morale = 0.1
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._campaign_receiving_city(plan)
	sim._start_or_join_siege(attacker, state.cities[3], state.edge_of(2, 3))
	var battle := sim._siege_battle_of(state.cities[3])
	_check(battle != null and battle.uses_field_combat_rules(), "direct-center defeat must be a real army field engagement")
	for _round in range(10):
		sim._resolve_battles()
		if battle.finished:
			break
	_check(battle.finished and plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP, "a real lost center engagement returns the entire front to regrouping")
	_check(attacker.state == Army.State.RETREATING and attacker.on_edge and attacker.move_to == 2, "routed survivor physically retreats toward the rear base")
	_check(not plan.combat_report_locked, "last field engagement reports the real surviving force")
	var recovery_day := -1
	for _day in range(100):
		state.day += 1
		sim._advance_movement()
		sim._recover_morale()
		sim._manage_administrative_campaign(plan)
		_check(plan.phase == CoalitionCampaignFront.Phase.HOLD_CAMP, "recovery and understrength remnants cannot start the next wave")
		if attacker.state == Army.State.RECOVERING:
			_check(attacker.location_city == 2, "recovery happens at the real campaign base")
		if attacker.state == Army.State.IDLE:
			recovery_day = state.day
			break
	_check(recovery_day > 100 and attacker.is_at_city_node(2), "routed troop marches home and actually completes morale recovery")
	var reserve := army(state, 0, 2, 45000)
	reserve.campaign_war_id = plan.war_id
	reserve.campaign_front_id = plan.front_id
	plan.army_assignments[reserve.id] = 2
	sim._manage_administrative_campaign(plan)
	_check(plan.phase == CoalitionCampaignFront.Phase.ASSAULT_CENTER and reserve.on_edge and reserve.ai_target_city == 3, "second wave departs only after actual ready base strength satisfies the requirement")
	print("DIRECT_CENTER_REGROUP_METRIC rout=100 recovered=%d next_wave=%d survivor=%d requirement=%d" % [recovery_day, state.day, attacker.size, state.campaign_attack_requirement(0, 3)])
	sim.free()


func _test_real_capture_chain(river: bool) -> void:
	var state := fixture()
	if river:
		state.edge_of(2, 3).max_manpower = 0
		var dock := City.new()
		dock.id = 8
		dock.is_dock = true
		dock.owner_nation = 1
		dock.map_position = Vector2(2.5 / 7.0, 0)
		state.cities.append(dock)
		state.adjacency[8] = [] as Array[int]
		state.recognized_city_owners.append(1)
		state.region_ids.append(-1)
		state.administrative_center_by_city.append(-1)
		for bank in [2, 3]:
			state._add_edge(bank, 8)
			state.edge_of(bank, 8).kind = Edge.Kind.LANDING
			state.edge_of(bank, 8).max_manpower = Edge.WATER_MANPOWER
			state.edge_of(bank, 8).distance = 0.1
		state.road_network_revision += 1
	var guards: Array[Army] = []
	for _index in range(3):
		var troop := army(state, 0, 2)
		troop.attack = 1
		troop.defense = 1
		guards.append(troop)
	var plan := front(state, guards)
	plan.phase = CoalitionCampaignFront.Phase.HOLD_CAMP
	for _index in range(4):
		army(state, 1, 3)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false
	sim._campaign_receiving_city(plan)
	var captured := -1
	var released := -1
	var counter_order := -1
	var new_defense := -1
	var cooldown_until := -1
	var counter_target := -1
	for _day in range(300):
		sim._advance_day()
		if captured < 0 and state.cities[2].owner_nation == 1:
			captured = state.day
			cooldown_until = state.campaign_offensive_cooldown_until(plan.war_id, [0] as Array[int])
		if captured >= 0 and released < 0 and state.campaign_front(plan.front_id) == null:
			released = state.day
		for troop in state.armies:
			var current := state.campaign_front(troop.campaign_front_id)
			if current != null and current.mode == CoalitionCampaignFront.Mode.OFFENSE and troop.owner_nation == 1 and (troop.on_edge or not troop.path.is_empty()):
				if counter_order < 0:
					counter_order = state.day
					counter_target = current.center_city_id
		if counter_target >= 0 and state.campaign_front_for(0, counter_target, CoalitionCampaignFront.Mode.DEFENSE, plan.war_id) != null:
			new_defense = state.day
			break
	_check(captured > 100, "original defender must march and actually capture the populated rear camp")
	_check(released >= captured and captured >= 0, "rear camp capture releases the old front only after real occupation")
	_check(counter_order > captured and counter_order >= released, "rear camp victory yields executable next-day same-war counteroffense")
	_check(new_defense >= counter_order and counter_order >= 0, "counteroffense causes the original attacker to build an actual defense")
	_check(cooldown_until == captured + 60, "rear camp defeat registers exactly the original sixty-day cooldown")
	_check(sim.ai_last_command_commit_failures == 0, "rear camp chain has no rejected movement orders")
	for pair in state.campaign_pairs.values():
		_check(pair.battlefields.size() <= 2, "rear camp pursuit never consumes an extra battlefield slot")
	print("DIRECT_CENTER_COUNTER_METRIC river=%s capture=%d release=%d counter_order=%d new_defense=%d cooldown=%d" % [river, captured, released, counter_order, new_defense, cooldown_until])
	sim.free()
