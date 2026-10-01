extends SceneTree

var checks := 0
var failures: Array[String] = []


func _init() -> void:
	_test_two_sides_share_two_battlefields()
	_test_disconnected_enemy_components_get_independent_pairs()
	_test_empty_pool_does_not_create_offense()
	_test_second_battlefield_manpower_threshold()
	_test_offense_and_defense_share_one_slot()
	_test_two_enemy_components_share_one_defense()
	_test_pair_topology_merge_and_split()
	_test_merge_trims_excess_theaters_by_committed_force()
	_test_pair_cooldown_isolation()
	_test_single_reserve_is_not_reused_by_two_pairs()
	_test_pending_counterattack_right_is_not_cloned_on_split()
	_test_same_state_front_merge_repairs_slot_references()
	_test_retiring_overflow_preserves_battle_and_withdraws_detachment()
	_test_war_exit_cleans_pair_permissions()
	_test_third_party_target_change_has_no_counterattack_right()
	_test_third_party_change_revokes_pending_counterattack_permission()
	_test_unreachable_old_target_does_not_block_reselection()
	_test_pending_slot_reserves_its_state()
	_test_pending_mobilization_protects_new_reserves()
	_test_pending_succession_reserves_fallback_side()
	_test_second_slot_counts_existing_marching_force()
	_test_duplicate_slot_retires_extra_executor()
	_test_pending_mobilization_uses_eligible_allied_proposer()
	_test_reflected_map_keeps_pair_and_task_snapshots()
	_test_first_slot_inherits_earliest_declaration()
	_test_pair_cooldown_keeps_existing_front_mobilization()
	_test_mobilization_claim_is_not_a_command()
	for message in failures:
		push_error("COALITION_PAIR_FAIL: " + message)
	print("COALITION_PAIR_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _state(nation_count: int = 2) -> GameState:
	var state := GameState.new()
	state.rng.seed = 130061
	state.day = 100
	for owner in range(nation_count):
		var nation := Nation.new()
		nation.id = owner
		nation.capital_city_id = owner * 4
		nation.treasury_gold = 1000000
		nation.manpower_pool = 0
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		state.nations.append(nation)
		for offset in range(4):
			var city := City.new()
			city.id = owner * 4 + offset
			city.owner_nation = owner
			city.map_position = Vector2(offset, owner * 2)
			city.food_storage = 1000000
			city.food_per_half_year = 100000
			city.gold_per_month = 10000
			city.garrison_manpower = 1000 if offset % 2 == 0 else 0
			state.cities.append(city)
			state.adjacency[city.id] = [] as Array[int]
			state.region_ids.append(0)
			state.administrative_center_by_city.append(owner * 4 + (offset / 2) * 2)
			state.recognized_city_owners.append(owner)
		state.administrative_center_city_ids.append(owner * 4)
		state.administrative_center_city_ids.append(owner * 4 + 2)
		state._add_edge(owner * 4, owner * 4 + 1)
		state._add_edge(owner * 4 + 1, owner * 4 + 3)
		state._add_edge(owner * 4 + 2, owner * 4 + 3)
	for nation_a in range(nation_count):
		for nation_b in range(nation_a + 1, nation_count):
			state.set_diplomatic_relation(nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL)
	return state


func _war(state: GameState, attacker: int, enemies: Array[int]) -> int:
	var war_id := -1
	for enemy in enemies:
		state.set_diplomatic_relation(attacker, enemy, GameState.DiplomaticRelation.WAR)
		var current := state.war_id_between(attacker, enemy)
		if war_id < 0:
			war_id = current
		else:
			state.merge_war_ids(war_id, current)
	return war_id


func _army(state: GameState, owner: int, size: int = 15000, city_id: int = -1) -> Army:
	var army := Army.new()
	army.id = 1000 + state.armies.size()
	army.owner_nation = owner
	army.location_city = owner * 4 + 1 if city_id < 0 else city_id
	army.move_from = army.location_city
	army.size = size
	army.max_size = maxi(15000, size)
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	state.armies.append(army)
	return army


func _reserve(state: GameState, owner: int, manpower: int) -> void:
	while manpower > 0:
		var amount := mini(manpower, 15000)
		_army(state, owner, amount)
		manpower -= amount


func _sim(state: GameState) -> Simulation:
	var sim := Simulation.new()
	sim.setup(state)
	# Simulation setup can generate random profiles; fixture eligibility is explicit.
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
	return sim


func _pairs(state: GameState, owner: int, war_id: int) -> Array:
	_check(state.has_method("campaign_pairs_for_nation"), "shared pair query must exist")
	if not state.has_method("campaign_pairs_for_nation"):
		return []
	return state.call("campaign_pairs_for_nation", owner, war_id)


func _pair_members(pair: Object) -> Array:
	var members: Array = pair.get("side_a_nation_ids").duplicate()
	members.append_array(pair.get("side_b_nation_ids"))
	members.sort()
	return members


func _offenses(state: GameState, war_id: int) -> Array[CoalitionCampaignFront]:
	var result: Array[CoalitionCampaignFront] = []
	for value in state.campaign_fronts.values():
		var front := value as CoalitionCampaignFront
		if front.war_id == war_id and front.mode == CoalitionCampaignFront.Mode.OFFENSE:
			result.append(front)
	return result


func _check_unique_bindings(state: GameState) -> void:
	var assignments := {}
	for front in state.campaign_fronts.values():
		for army_id in front.army_assignments:
			_check(not assignments.has(army_id), "army must not be promised to multiple tasks")
			assignments[army_id] = front.front_id
	for army in state.armies:
		_check(army.campaign_front_id == int(assignments.get(army.id, -1)),
			"army direct binding must agree with the single assigned task")


func _test_two_sides_share_two_battlefields() -> void:
	var state := _state()
	state._add_edge(1, 5)
	state._add_edge(3, 7)
	var war_id := _war(state, 0, [1] as Array[int])
	_reserve(state, 0, 180000)
	_reserve(state, 1, 180000)
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	var fronts := _offenses(state, war_id)
	print("COALITION_PAIR_METRIC scenario=two_armed_sides active_offense_tasks=%d" % fronts.size())
	_check(not fronts.is_empty(), "a legal armed war must open a real battlefield")
	_check(fronts.size() <= 2, "both sides combined must not create four offensive theaters")
	var pairs := _pairs(state, 0, war_id)
	_check(pairs.size() == 1, "two connected enemy sides create exactly one pair")
	if pairs.size() == 1:
		var pair: Object = pairs[0]
		_check(_pair_members(pair) == [0, 1], "pair records both participating sides")
		var slots: Array = pair.get("battlefields")
		_check(slots.size() == 2, "sufficient initial force opens the pair's two slots")
		for front in fronts:
			_check(not front.army_assignments.is_empty(), "new active offense must receive real troops")
			_check(int(front.get("campaign_pair_id")) == int(pair.get("pair_id")),
				"all offense tasks refer to the shared pair")
			var slot := int(front.get("battlefield_slot"))
			_check(slot >= 0 and slot < slots.size(), "offense task refers to a real shared slot")
			if slot >= 0 and slot < slots.size():
				_check(int(slots[slot].get("offense_front_id", -1)) == front.front_id,
					"slot links the unique offense executor")
	_check_unique_bindings(state)
	sim.free()


func _test_disconnected_enemy_components_get_independent_pairs() -> void:
	var state := _state(4)
	for owners in [[1, 2], [1, 3], [2, 3]]:
		state.set_diplomatic_relation(owners[0], owners[1], GameState.DiplomaticRelation.ALLIED)
	for enemy_fu in [5, 7, 9, 11, 13, 15]:
		state._add_edge(1, enemy_fu)
	state._add_edge(11, 13)
	var war_id := _war(state, 0, [1, 2, 3] as Array[int])
	_reserve(state, 0, 360000)
	for owner in [1, 2, 3]:
		_reserve(state, owner, 120000)
	var sim := _sim(state)
	var components := state.coalition_campaign_components(war_id)
	_check(components.size() == 3, "fixture must separate B from connected CD despite their alliance")
	sim._manage_coalition_campaigns()
	var pairs := _pairs(state, 0, war_id)
	_check(pairs.size() == 2, "A-B and A-CD must have independent pair records")
	var member_sets := []
	for value in pairs:
		var pair := value as Object
		member_sets.append(_pair_members(pair))
		var slots: Array = pair.get("battlefields")
		_check(slots.size() <= 2, "each component pair has at most two battlefields")
		_check(not slots.is_empty(), "each reachable armed pair must open at least one battlefield")
		var offense_count := 0
		for front in _offenses(state, war_id):
			if int(front.get("campaign_pair_id")) == int(pair.get("pair_id")):
				offense_count += 1
		_check(offense_count <= 2, "pair limit counts offenses from either side together")
	_check(member_sets.has([0, 1]) and member_sets.has([0, 2, 3]),
		"disconnected allies must not collapse into a single theater pair")
	_check_unique_bindings(state)
	sim.free()


func _test_empty_pool_does_not_create_offense() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	print("COALITION_PAIR_METRIC scenario=empty_pool active_offense_tasks=%d" % _offenses(state, war_id).size())
	_check(_offenses(state, war_id).is_empty(), "zero available armies must not create active empty offense")
	sim.free()


func _test_second_battlefield_manpower_threshold() -> void:
	for manpower in [89999, 90000]:
		var state := _state()
		state._add_edge(1, 5)
		state._add_edge(3, 7)
		var war_id := _war(state, 0, [1] as Array[int])
		_reserve(state, 0, manpower)
		var sim := _sim(state)
		sim._manage_coalition_campaigns()
		var expected := 1 if manpower < 90000 else 2
		print("COALITION_PAIR_METRIC scenario=second_slot effective=%d active_offense_tasks=%d expected=%d" % [
			manpower, _offenses(state, war_id).size(), expected])
		_check(_offenses(state, war_id).size() == expected,
			"second battlefield opens at effective90000, not below: C=%d" % manpower)
		var pairs := _pairs(state, 0, war_id)
		if pairs.size() == 1:
			_check((pairs[0].get("battlefields") as Array).size() == expected,
				"shared slot count must obey the same effective-force threshold")
		sim.free()


func _test_offense_and_defense_share_one_slot() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	_reserve(state, 0, 45000)
	_reserve(state, 1, 15000)
	var invader := _army(state, 0, 15000, 5)
	var front := state.create_campaign_front(war_id, [0] as Array[int], 0,
		CoalitionCampaignFront.Mode.OFFENSE, 4)
	front.staging_city_id = 1
	front.phase = CoalitionCampaignFront.Phase.BREAK_IN
	front.had_forces = true
	front.army_assignments[invader.id] = 5
	invader.campaign_war_id = war_id
	invader.campaign_front_id = front.front_id
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	_check(state.campaign_front_for(1, 4, CoalitionCampaignFront.Mode.DEFENSE, war_id) != null,
		"the registered invaded state must have its defender task")
	var pairs := _pairs(state, 0, war_id)
	if pairs.size() == 1:
		var slots: Array = pairs[0].get("battlefields")
		var matching := 0
		for slot in slots:
			if int(slot.get("center_city_id", -1)) == 4:
				matching += 1
		_check(matching == 1, "offense and corresponding defense occupy one shared battlefield")
	_check_unique_bindings(state)
	sim.free()


func _test_two_enemy_components_share_one_defense() -> void:
	var state := _state(3)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state._add_edge(1, 9)
	state._add_edge(5, 9)
	var war_id := _war(state, 2, [0, 1] as Array[int])
	for attacker in [0, 1]:
		var invader := _army(state, attacker, 15000, 9)
		var front := state.create_campaign_front(war_id, [attacker] as Array[int], attacker,
			CoalitionCampaignFront.Mode.OFFENSE, 8)
		front.phase = CoalitionCampaignFront.Phase.BREAK_IN
		front.staging_city_id = attacker * 4 + 1
		front.had_forces = true
		front.army_assignments[invader.id] = 9
		invader.campaign_war_id = war_id
		invader.campaign_front_id = front.front_id
	_reserve(state, 2, 60000)
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	var defenses := state.campaign_fronts_for_nation(2, war_id, CoalitionCampaignFront.Mode.DEFENSE)
	var count := 0
	for front in defenses:
		if front.center_city_id == 8:
			count += 1
	_check(count == 1, "two attacking enemy components must share one same-state defense task")
	var pairs := _pairs(state, 2, war_id)
	_check(pairs.size() == 2, "same defender can participate in two enemy component pairs")
	_check_unique_bindings(state)
	sim.free()


func _three_side_state() -> GameState:
	var state := _state(3)
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
	state._add_edge(1, 5)
	state._add_edge(1, 9)
	_war(state, 0, [1, 2] as Array[int])
	return state


func _bound_offense(state: GameState, center: int, manpower: int) -> CoalitionCampaignFront:
	var front := state.create_campaign_front(state.war_id_between(0, 1), [0] as Array[int], 0,
		CoalitionCampaignFront.Mode.OFFENSE, center)
	front.staging_city_id = 1
	front.had_forces = true
	var army := _army(state, 0, manpower)
	front.army_assignments[army.id] = 1
	army.campaign_war_id = front.war_id
	army.campaign_front_id = front.front_id
	return front


func _test_pair_topology_merge_and_split() -> void:
	var state := _three_side_state()
	var first := _bound_offense(state, 4, 30000)
	var second := _bound_offense(state, 8, 45000)
	var war_id := first.war_id
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	_check(_pairs(state, 0, war_id).size() == 2, "disconnected allied territories initially make two pairs")
	state.record_campaign_offensive_failure(war_id, [1] as Array[int], 160, [0] as Array[int])
	state.record_campaign_offensive_failure(war_id, [2] as Array[int], 180, [0] as Array[int])
	state._add_edge(5, 9)
	state.road_network_revision += 1
	sim._prepare_coalition_campaign_batch()
	var merged := _pairs(state, 0, war_id)
	_check(merged.size() == 1, "real allied border merges the two enemy components")
	if merged.size() == 1:
		_check((merged[0].get("battlefields") as Array).size() == 2,
			"merging two one-slot pairs retains both theaters exactly once")
		_check(first.get("campaign_pair_id") == second.get("campaign_pair_id"),
			"both retained execution tasks migrate to one pair")
		_check(int(merged[0].call("cooldown_until", [1, 2] as Array[int])) == 180,
			"merged side uses its latest member cooldown deadline")
	state.edges.erase(state.edge_of(5, 9))
	state.edge_lookup.erase(GameState.edge_key(5, 9))
	(state.adjacency[5] as Array[int]).erase(9)
	(state.adjacency[9] as Array[int]).erase(5)
	state.road_network_revision += 1
	sim._prepare_coalition_campaign_batch()
	var split := _pairs(state, 0, war_id)
	_check(split.size() == 2, "road border removal splits the enemy component again")
	var slot_count := 0
	for value in split:
		var pair := value as Object
		var slots: Array = pair.get("battlefields")
		slot_count += slots.size()
		print("COALITION_PAIR_METRIC scenario=topology_split members=%s slots=%s" % [_pair_members(pair), slots])
		_check(slots.size() == 1, "split does not clone each parent slot into both child pairs")
		if slots.size() == 1:
			var owner := state.cities[int(slots[0]["center_city_id"])].owner_nation
			var members := _pair_members(pair)
			_check(members.has(owner), "split theater follows the target's actual opposing component")
	_check(slot_count == 2, "split preserves two theaters without duplicating pending metadata")
	_check(first.get("campaign_pair_id") != second.get("campaign_pair_id"),
		"retained fronts now point at distinct child pairs")
	_check(state.campaign_offensive_cooldown_until(war_id, [1] as Array[int], [0] as Array[int]) == 160,
		"split preserves B's own deadline without extending it to C's later cooldown")
	_check(state.campaign_offensive_cooldown_until(war_id, [2] as Array[int], [0] as Array[int]) == 180,
		"split preserves C's own later deadline")
	_check_unique_bindings(state)
	sim.free()


func _test_merge_trims_excess_theaters_by_committed_force() -> void:
	var state := _three_side_state()
	var weak := _bound_offense(state, 4, 15000)
	var medium := _bound_offense(state, 6, 30000)
	var strong := _bound_offense(state, 8, 45000)
	var war_id := weak.war_id
	var weak_army_id := int(weak.army_assignments.keys()[0])
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	state._add_edge(5, 9)
	state.road_network_revision += 1
	sim._prepare_coalition_campaign_batch()
	var pairs := _pairs(state, 0, war_id)
	_check(pairs.size() == 1, "merge overflow belongs to one component pair")
	if pairs.size() == 1:
		_check((pairs[0].get("battlefields") as Array).size() == 2,
			"merged three-theater inheritance is trimmed to two slots")
	_check(state.campaign_front(weak.front_id) == null,
		"without siege or camp the lowest effective-force offense retires")
	_check(state.campaign_front(medium.front_id) != null and state.campaign_front(strong.front_id) != null,
		"merge retains the two more committed theaters")
	for army in state.armies:
		if army.id == weak_army_id:
			_check(army.campaign_front_id == -1 and army.campaign_war_id == war_id,
				"overflow release preserves troops in their original war pool")
	_check_unique_bindings(state)
	sim.free()


func _test_pair_cooldown_isolation() -> void:
	var state := _three_side_state()
	var war_id := state.war_id_between(0, 1)
	_reserve(state, 0, 90000)
	var sim := _sim(state)
	state.record_campaign_offensive_failure(war_id, [0] as Array[int], 160, [1] as Array[int])
	sim._manage_coalition_campaigns()
	_check(state.campaign_offensive_cooldown_until(war_id, [0] as Array[int], [1] as Array[int]) == 160,
		"camp defeat cooldown remains attached to the failed opponent pair")
	_check(state.campaign_offensive_cooldown_until(war_id, [0] as Array[int], [2] as Array[int]) < state.day,
		"A-B defeat does not cool A-C in the same war")
	var pair_ab := state.find_campaign_pair(war_id, 0, 1)
	var pair_ac := state.find_campaign_pair(war_id, 0, 2)
	_check(pair_ab != null and pair_ac != null, "cooldown scenario has both independent pairs")
	if pair_ab != null and pair_ac != null:
		_check(pair_ab.battlefields.is_empty(), "failed pair must not reopen offense during cooldown")
		_check(not pair_ac.battlefields.is_empty(), "the other pair can still mobilize a real offense")
		for front in _offenses(state, war_id):
			_check(front.campaign_pair_id == pair_ac.pair_id,
				"every new offense during failed-pair cooldown belongs to the unaffected pair")
	_check_unique_bindings(state)
	sim.free()


func _test_single_reserve_is_not_reused_by_two_pairs() -> void:
	var state := _three_side_state()
	var war_id := state.war_id_between(0, 1)
	var reserve := _army(state, 0)
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	_check(_pairs(state, 0, war_id).size() == 2, "one national reserve faces two eligible opponent pairs")
	var fronts := _offenses(state, war_id)
	_check(fronts.size() == 1, "one fifteen-thousand reserve cannot launch two active pair tasks")
	var promised := 0
	for front in fronts:
		promised += sim._front_effective_manpower(front)
	_check(promised == 15000 and reserve.campaign_front_id >= 0,
		"the shared national reserve is committed once rather than promised separately")
	_check_unique_bindings(state)
	sim.free()


func _test_pending_counterattack_right_is_not_cloned_on_split() -> void:
	var state := _three_side_state()
	state._add_edge(5, 9)
	state.road_network_revision += 1
	var war_id := state.war_id_between(0, 1)
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	var initial := _pairs(state, 0, war_id)
	_check(initial.size() == 1, "pending-right fixture begins with merged opposing allies")
	if initial.size() != 1:
		sim.free()
		return
	var pair := initial[0] as Object
	# The old battle ended in A's territory; the right to counterattack belongs to A.
	(pair.get("battlefields") as Array).append({"center_city_id": 0, "offense_front_id": -1,
		"preferred_nation_id": 0, "counterattack": true})
	state.edges.erase(state.edge_of(5, 9))
	state.edge_lookup.erase(GameState.edge_key(5, 9))
	(state.adjacency[5] as Array[int]).erase(9)
	(state.adjacency[9] as Array[int]).erase(5)
	state.road_network_revision += 1
	sim._prepare_coalition_campaign_batch()
	var retained_rights := 0
	for child in _pairs(state, 0, war_id):
		for slot in child.get("battlefields") as Array:
			if int(slot.get("preferred_nation_id", -1)) == 0 and bool(slot.get("counterattack", false)):
				retained_rights += 1
	_check(retained_rights == 1,
		"one pending cross-region counterattack right follows one child, never both")
	sim.free()


func _test_same_state_front_merge_repairs_slot_references() -> void:
	var state := _state(3)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state._add_edge(1, 9)
	state._add_edge(5, 9)
	var war_id := _war(state, 2, [0, 1] as Array[int])
	var originals: Array[CoalitionCampaignFront] = []
	for owner in [0, 1]:
		var front := state.create_campaign_front(war_id, [owner] as Array[int], owner,
			CoalitionCampaignFront.Mode.OFFENSE, 8)
		front.staging_city_id = owner * 4 + 1
		front.had_forces = true
		var army := _army(state, owner)
		front.army_assignments[army.id] = front.staging_city_id
		army.campaign_war_id = war_id
		army.campaign_front_id = front.front_id
		originals.append(front)
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	state._add_edge(1, 5)
	state.road_network_revision += 1
	sim._prepare_coalition_campaign_batch()
	var pairs := _pairs(state, 0, war_id)
	_check(pairs.size() == 1, "same-state attacking components merge to one pair")
	var offenses := _offenses(state, war_id)
	_check(offenses.size() == 1, "same state and mode merge into one execution task")
	if pairs.size() == 1 and offenses.size() == 1:
		var slots: Array = pairs[0].get("battlefields")
		_check(slots.size() == 1, "duplicate same-state inherited slots collapse to one")
		if slots.size() == 1:
			_check(int(slots[0]["offense_front_id"]) == offenses[0].front_id,
				"merged slot references the surviving front, never the removed one")
		_check(offenses[0].army_assignments.size() == 2,
			"both countries' existing armies remain on the surviving task")
	_check_unique_bindings(state)
	sim.free()


func _test_retiring_overflow_preserves_battle_and_withdraws_detachment() -> void:
	var state := _three_side_state()
	var weak := _bound_offense(state, 4, 15000)
	_bound_offense(state, 6, 45000)
	_bound_offense(state, 8, 60000)
	var fighter := state.armies[0]
	var moving := _army(state, 0, 15000, 1)
	moving.campaign_war_id = weak.war_id
	moving.campaign_front_id = weak.front_id
	weak.army_assignments[moving.id] = 5
	moving.state = Army.State.MOVING
	moving.on_edge = true
	moving.move_from = 1
	moving.move_to = 5
	moving.move_progress = 0.4
	moving.path = [4] as Array[int]
	moving.ai_action = ActionCandidate.Kind.ATTACK
	moving.ai_target_city = 4
	state.edge_of(1, 5).distance = 0.1
	var enemy := _army(state, 1, 15000, 0)
	fighter.state = Army.State.FIGHTING
	enemy.state = Army.State.FIGHTING
	var battle := state.new_battle(Battle.Kind.FIELD)
	battle.edge = state.edge_of(0, 1)
	battle.side_a.append(fighter)
	battle.side_b.append(enemy)
	fighter.battle_id = battle.id
	enemy.battle_id = battle.id
	var sim := _sim(state)
	sim._lock_campaign_reports_for_battle(battle)
	sim._prepare_coalition_campaign_batch()
	state._add_edge(5, 9)
	state.road_network_revision += 1
	sim._prepare_coalition_campaign_batch()
	_check(state.campaign_front(weak.front_id) != null and weak.retiring,
		"overflow front keeps only retiring battle references until its real field ends")
	_check(not battle.finished and fighter.campaign_front_id == weak.front_id and weak.combat_report_locked,
		"administrative trim must preserve live combat and its report lock")
	_check(moving.campaign_front_id == -1 and moving.campaign_war_id == weak.war_id,
		"nonfighting detachment leaves the retiring task but stays in its war pool")
	_check(moving.on_edge and moving.move_from == 1 and moving.move_to == 5
		and is_equal_approx(moving.move_progress, 0.4), "trim cannot reverse or teleport an in-flight leg")
	_check(moving.ai_action == ActionCandidate.Kind.RETREAT and moving.ai_target_city == 1,
		"retiring detachment replaces its future assault with a real staging withdrawal")
	var reserve := _army(state, 0)
	for component in state.coalition_campaign_components(weak.war_id):
		if (component["members"] as Array[int]).has(0):
			sim._allocate_coalition_fronts(component)
	_check(reserve.campaign_front_id != weak.front_id,
		"retiring battlefield cannot receive new nationwide reinforcement")
	var visited_old_endpoint := false
	for _step in range(20):
		state.day += 1
		sim._advance_travelling_armies()
		sim._arrive_retreating_armies()
		sim._arrive_travelling_armies()
		sim._recover_morale()
		visited_old_endpoint = visited_old_endpoint or moving.location_city == 5 or moving.move_from == 5
		if moving.location_city == 1 and moving.state == Army.State.IDLE:
			break
	_check(visited_old_endpoint and moving.location_city == 1 and moving.state == Army.State.IDLE,
		"detachment physically reaches its old leg endpoint before returning to staging")
	print("COALITION_PAIR_METRIC scenario=retiring_detachment visited_endpoint=%s final_city=%d state=%d action=%d path=%s from=%d to=%d progress=%s" % [
		visited_old_endpoint, moving.location_city, moving.state, moving.ai_action, moving.path,
		moving.move_from, moving.move_to, moving.move_progress])
	var stale_siege := false
	for active_battle in state.battles:
		stale_siege = stale_siege or (active_battle.city != null and active_battle.city.id in [4, 5])
	_check(not stale_siege and state.cities[5].owner_nation == 1,
		"in-flight withdrawal must not resume occupation or reopen the canceled city siege")
	_check(moving.size == 15000, "administrative retirement causes no rout casualty penalty")
	battle.finished = true
	sim._finish_campaign_reports_for_battle(battle)
	state.day += 1
	sim._prepare_coalition_campaign_batch()
	_check(state.campaign_front(weak.front_id) == null,
		"retiring front is removed after its final real field engagement ends")
	sim.free()


func _test_war_exit_cleans_pair_permissions() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	var front := _bound_offense(state, 4, 30000)
	var army := state.armies[0]
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	state.record_campaign_offensive_failure(war_id, [0] as Array[int], 160, [1] as Array[int])
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	sim._prepare_coalition_campaign_batch()
	_check(_pairs(state, 0, war_id).is_empty(), "peace removes the extinct pair and pending permissions")
	_check(state.campaign_front(front.front_id) == null and army.campaign_front_id == -1
		and army.campaign_war_id == -1, "leaving war releases task and pool ownership together")
	_check(state.campaign_offensive_cooldown_until(war_id, [0] as Array[int]) < state.day,
		"finished war leaves no pair-scoped cooldown")
	sim.free()


func _test_third_party_target_change_has_no_counterattack_right() -> void:
	var state := _state(3)
	state._add_edge(1, 5)
	state._add_edge(3, 7)
	var war_id := _war(state, 0, [1] as Array[int])
	var front := _bound_offense(state, 4, 30000)
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	state.cities[4].owner_nation = 2
	state.cities[5].owner_nation = 2
	state.ownership_revision += 1
	sim._manage_coalition_campaigns()
	_check(state.campaign_front(front.front_id) == null, "neutral third-party province ceases to be this war's objective")
	for pair in _pairs(state, 0, war_id):
		for slot in pair.get("battlefields") as Array:
			_check(not bool(slot.get("counterattack", false)),
				"third-party control change must never create a cross-region counterattack privilege")
	_check(state.campaign_offensive_cooldown_until(war_id, [0] as Array[int]) < state.day,
		"third-party objective invalidation is not an enemy camp defeat")
	sim.free()


func _test_unreachable_old_target_does_not_block_reselection() -> void:
	var state := _state(3)
	state._add_edge(1, 5)
	state._add_edge(3, 7)
	state._add_edge(1, 9)
	state._add_edge(9, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	var old := _bound_offense(state, 4, 30000)
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	state.edges.erase(state.edge_of(1, 5))
	state.edge_lookup.erase(GameState.edge_key(1, 5))
	(state.adjacency[1] as Array[int]).erase(5)
	(state.adjacency[5] as Array[int]).erase(1)
	state.road_network_revision += 1
	state.day += 10
	_check(sim._campaign_entry_fu(0, 4, state.alliance_bloc(0)) < 0,
		"old target has no legal frontier Fu after its real border route is removed")
	_check(sim._campaign_entry_fu(0, 6, state.alliance_bloc(0)) == 7,
		"replacement state retains its legal border entrance despite global graph connectivity")
	sim._manage_coalition_campaigns()
	_check(state.campaign_front(old.front_id) == null,
		"disconnected legal entry retires old target rather than occupying the slot indefinitely")
	var reassigned := false
	for front in _offenses(state, war_id):
		reassigned = reassigned or (front.center_city_id == 6 and not front.army_assignments.is_empty())
	_check(reassigned, "released pool must actually bind the other legally reachable enemy state")
	_check(state.campaign_offensive_cooldown_until(war_id, [0] as Array[int]) < state.day,
		"lost deployment route does not confer camp-defeat cooldown or counterattack rights")
	_check_unique_bindings(state)
	sim.free()


func _test_third_party_change_revokes_pending_counterattack_permission() -> void:
	var state := _state(3)
	state._add_edge(1, 5)
	state._add_edge(3, 7)
	var war_id := _war(state, 0, [1] as Array[int])
	_army(state, 1, 15000, 7)
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	var pair := state.find_campaign_pair(war_id, 0, 1)
	_check(pair != null, "pending-permission invalidation has its original enemy pair")
	if pair == null:
		sim.free()
		return
	pair.battlefields.append({"center_city_id": 4, "offense_front_id": -1,
		"preferred_nation_id": 1, "counterattack": true})
	state.cities[4].owner_nation = 2
	state.cities[5].owner_nation = 2
	state.ownership_revision += 1
	sim._manage_coalition_campaigns()
	for slot in pair.battlefields:
		_check(not bool(slot.get("counterattack", false)),
			"third-party removal of the old battlefield revokes its pending privileged succession")
	for front in _offenses(state, war_id):
		_check(front.selection_reason == 0,
			"ordinary new targets cannot inherit a canceled battlefield's cross-region privilege")
	sim.free()


func _test_pending_slot_reserves_its_state() -> void:
	var state := _state(3)
	state._add_edge(1, 5)
	state.cities[6].owner_nation = 2
	state.cities[7].owner_nation = 2
	var war_id := _war(state, 0, [1] as Array[int])
	_reserve(state, 0, 90000)
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	var pair := state.find_campaign_pair(war_id, 0, 1)
	var pending := CoalitionCampaignPair.make_battlefield(4, -1, 0)
	pending["awaiting_mobilization"] = true
	pair.battlefields.append(pending)
	var new_slot := CoalitionCampaignPair.make_battlefield(-1, -1)
	_check(sim._pair_proposal(pair, [0] as Array[int], new_slot, {}).is_empty(),
		"a pending state's center cannot also become the pair's second battlefield")
	_check(not sim._pair_proposal(pair, [0] as Array[int], pending, {}).is_empty(),
		"the pending slot itself may mobilize for its original legal state")
	sim.free()


func _test_pending_mobilization_protects_new_reserves() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	state.set_war_objective(0, 1, 4, "mobilization fixture", war_id)
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	_check(_offenses(state, war_id).is_empty(), "pending declaration is not an empty active front")
	for amount in [14000, 15000, 16000, 17000]:
		_army(state, 0, amount, 0)
	sim._ai_planned_armies.clear()
	sim._manage_coalition_campaigns()
	var reserved: Dictionary = sim._coalition_campaign_query_cache["mobilization_claims"].duplicate()
	_check(not reserved.is_empty(), "new recruits are reserved before the next group due day")
	_check(_offenses(state, war_id).is_empty(), "reservation does not bypass the ten-day group schedule")
	state.armies.reverse()
	sim._ai_planned_armies.clear()
	sim._manage_coalition_campaigns()
	_check(reserved == sim._coalition_campaign_query_cache["mobilization_claims"], "mobilization reservation is independent of stored army order")
	var view := AiWorldView.build(state, 0)
	var plan := CityDefensePlan.build(view, StrategicMapSnapshot.build(view), ThreatField.build(view))
	var snapshot := {}
	for army in state.armies:
		snapshot[army.id] = true
	sim._begin_ai_command_collection(snapshot)
	sim._balance_national_reserves(0, plan, reserved)
	for army in state.armies:
		if reserved.has(army.id):
			_check(army.defensive_deployment_until_day <= state.day,
				"national garrison deployment must not take pending mobilization troops")
	sim._clear_ai_command_collection()
	state.day += 10
	sim._ai_planned_armies.clear()
	sim._manage_coalition_campaigns()
	_check(not _offenses(state, war_id).is_empty(), "reserved recruits actually bind a battlefield on its due day")
	_check_unique_bindings(state)
	sim.free()


func _test_mobilization_claim_is_not_a_command() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	state.set_war_objective(0, 1, 4, "claim fixture", war_id)
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	var recruits: Array[Army] = []
	var snapshot := {}
	for index in range(5):
		var army := _army(state, 0, 15000, 0)
		recruits.append(army)
		snapshot[army.id] = true
	sim._begin_ai_command_collection(snapshot)
	sim._manage_coalition_campaigns()
	_check(sim._ai_planned_armies.is_empty(), "pending mobilization cannot masquerade as submitted commands")
	if not sim.has_method("_campaign_mobilization_claims"):
		_check(false, "national planners must receive an explicit mobilization claim set")
		sim.free()
		return
	var claims: Dictionary = sim._coalition_campaign_query_cache.get("mobilization_claims", {})
	_check(claims.size() == 3, "pending slot reserves only its 45000 deficit, not all national reserves")
	var view := AiWorldView.build(state, 0)
	var plan := CityDefensePlan.build(view, StrategicMapSnapshot.build(view), ThreatField.build(view))
	sim.call("_balance_national_reserves", 0, plan, claims)
	for army in recruits:
		if claims.has(army.id):
			_check(not sim._ai_planned_armies.has(army.id), "claim is separate from command deduplication")
			_check(army.defensive_deployment_until_day <= state.day, "a real command batch cannot deploy claimed recruits as garrisons")
	_check(not sim._ai_planned_armies.is_empty(), "unclaimed surplus can still receive national garrison orders")
	sim._commit_ai_command_collection([0] as Array[int])
	_check(sim.ai_last_command_commit_failures == 0, "claim-aware national orders must commit normally")
	sim.free()


func _test_pending_succession_reserves_fallback_side() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	var pair := state.find_campaign_pair(war_id, 0, 1)
	pair.battlefields.append(CoalitionCampaignPair.make_battlefield(4, -1, 1, true))
	var army := _army(state, 0)
	sim._prepare_coalition_campaign_batch()
	var claims := sim._campaign_mobilization_claims()
	_check(claims.has(army.id),
		"when priority side has no troops, eligible fallback recruits retain war mobilization priority")
	sim.free()


func _test_second_slot_counts_existing_marching_force() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	var pair := state.find_campaign_pair(war_id, 0, 1)
	var front := state.create_campaign_front(war_id, [0] as Array[int], 0,
		CoalitionCampaignFront.Mode.OFFENSE, 4)
	front.campaign_pair_id = pair.pair_id
	var marching := _army(state, 0, 75000)
	marching.campaign_war_id = war_id
	marching.campaign_front_id = front.front_id
	front.army_assignments[marching.id] = 1
	marching.state = Army.State.MOVING
	marching.on_edge = true
	_army(state, 0, 15000)
	_check(sim._pair_proposal_force(pair, [0] as Array[int]) == 90000,
		"second-slot capacity includes existing effective offensive troops already marching")
	sim.free()


func _test_duplicate_slot_retires_extra_executor() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	var pair := state.find_campaign_pair(war_id, 0, 1)
	var first := state.create_campaign_front(war_id, [0] as Array[int], 0,
		CoalitionCampaignFront.Mode.OFFENSE, 4)
	var extra := state.create_campaign_front(war_id, [1] as Array[int], 1,
		CoalitionCampaignFront.Mode.OFFENSE, 4)
	for front in [first, extra]:
		front.campaign_pair_id = pair.pair_id
		front.staging_city_id = 1 if front.anchor_nation_id == 0 else 5
		var army := _army(state, front.anchor_nation_id, 30000 if front == first else 15000)
		army.campaign_front_id = front.front_id
		army.campaign_war_id = war_id
		front.army_assignments[army.id] = front.staging_city_id
		pair.battlefields.append(CoalitionCampaignPair.make_battlefield(4, front.front_id, front.anchor_nation_id))
	sim._reconcile_campaign_battlefields()
	_check(pair.battlefields.size() == 1, "merged duplicate state slots count once")
	_check(state.campaign_front(extra.front_id) == null or extra.retiring,
		"dropping a duplicate slot also retires its executor instead of resurrecting it next batch")
	_check_unique_bindings(state)
	sim.free()


func _test_pending_mobilization_uses_eligible_allied_proposer() -> void:
	var state := _state(3)
	state._add_edge(1, 5)
	state._add_edge(5, 9)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	var war_id := _war(state, 0, [2] as Array[int])
	state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	state.merge_war_ids(war_id, state.war_id_between(1, 2))
	var sim := _sim(state)
	state.nations[0].ruler_archetype = RulerProfile.DIPLOMAT
	sim._prepare_coalition_campaign_batch()
	var pair := state.find_campaign_pair(war_id, 1, 2)
	pair.battlefields.append(CoalitionCampaignPair.make_battlefield(8, -1, 0))
	var army := _army(state, 1)
	sim._prepare_coalition_campaign_batch()
	var claims := sim._campaign_mobilization_claims()
	_check(claims.has(army.id),
		"a forbidden anchor cannot suppress an eligible ally's pending mobilization")
	sim.free()


func _test_reflected_map_keeps_pair_and_task_snapshots() -> void:
	var snapshots: Array[Dictionary] = []
	for reflected in [false, true]:
		var state := _state()
		state._add_edge(1, 5)
		state._add_edge(3, 7)
		_war(state, 0, [1] as Array[int])
		for owner in [0, 1]:
			for index in range(12):
				_army(state, owner, 14000 + index * 100)
		if reflected:
			for city in state.cities:
				city.map_position.x = 1.0 - city.map_position.x
			state.armies.reverse()
		var sim := _sim(state)
		sim._manage_coalition_campaigns()
		var snapshot := NativeSnapshotBuilder.build(state)
		snapshots.append({"pairs": snapshot["campaign_pairs"], "fronts": snapshot["campaign_fronts"]})
		sim.free()
	_check(snapshots[0] == snapshots[1],
		"reflection and storage reorder preserve pair IDs, slots, task phases, and army bindings")


func _test_first_slot_inherits_earliest_declaration() -> void:
	var state := _state(4)
	state._add_edge(1, 5)
	state._add_edge(9, 13)
	state._add_edge(1, 9)
	state._add_edge(5, 13)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(2, 3, GameState.DiplomaticRelation.ALLIED)
	var war_id := _war(state, 0, [2, 3] as Array[int])
	for opponent in [2, 3]:
		state.set_diplomatic_relation(1, opponent, GameState.DiplomaticRelation.WAR)
		state.merge_war_ids(war_id, state.war_id_between(1, opponent))
	state.set_war_objective(0, 2, 8, "earlier declaration", war_id)
	state.day += 1
	state.set_war_objective(3, 1, 4, "later opposing declaration", war_id)
	_army(state, 0, 30000)
	_army(state, 3, 30000)
	var sim := _sim(state)
	sim._manage_coalition_campaigns()
	var pair := state.find_campaign_pair(war_id, 0, 2)
	_check(pair != null and pair.battlefields.size() == 1, "two small sides share only the first battlefield")
	_check(pair != null and pair.battlefields[0]["center_city_id"] == 8,
		"first slot inherits the earliest legal declaration across both opposing components")
	sim.free()


func _test_pair_cooldown_keeps_existing_front_mobilization() -> void:
	var state := _state()
	state._add_edge(1, 5)
	var war_id := _war(state, 0, [1] as Array[int])
	var sim := _sim(state)
	sim._prepare_coalition_campaign_batch()
	var pair := state.find_campaign_pair(war_id, 0, 1)
	var front := state.create_campaign_front(war_id, [0] as Array[int], 0,
		CoalitionCampaignFront.Mode.OFFENSE, 4)
	front.campaign_pair_id = pair.pair_id
	var bound := _army(state, 0)
	bound.campaign_front_id = front.front_id
	bound.campaign_war_id = war_id
	front.army_assignments[bound.id] = 1
	pair.battlefields.append(CoalitionCampaignPair.make_battlefield(4, front.front_id, 0))
	pair.cooldown_until_by_nation[0] = state.day + 60
	var reinforcement := _army(state, 0)
	sim._prepare_coalition_campaign_batch()
	var claims := sim._campaign_mobilization_claims()
	_check(claims.has(reinforcement.id),
		"a different lost camp's pair cooldown must not starve an existing active front's reinforcement")
	sim.free()
