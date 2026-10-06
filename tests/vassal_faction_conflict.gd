extends SceneTree
## Real civil-war launch and capital transactions; never simulate extinction by toggling alive.

var checks := 0
var failures: Array[String] = []


class TracingSimulation extends Simulation:
	func _synchronize_alliance_wars(nation_a: int, nation_b: int,
		evaluation_cache: Dictionary = {}, frozen_gold_flows: Array[Dictionary] = []) -> void:
		print("FACTION_NORMALIZE_STEP_BEFORE pair=", [nation_a, nation_b],
			" bloc=", state.alliance_bloc(nation_a), " relations=", state.diplomatic_relations,
			" war_ids=", state.war_relation_ids)
		super._synchronize_alliance_wars(nation_a, nation_b, evaluation_cache, frozen_gold_flows)
		print("FACTION_NORMALIZE_STEP_AFTER pair=", [nation_a, nation_b],
			" bloc=", state.alliance_bloc(nation_a), " relations=", state.diplomatic_relations,
			" war_ids=", state.war_relation_ids)


func _init() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


static func fixture(isolated: bool = false) -> GameState:
	var state := GameState.new()
	state.world_seed = 96261
	state.rng.seed = 96261
	state.day = 730
	for owner in range(6):
		var nation := Nation.new()
		nation.id = owner
		nation.name = "国%d" % owner
		nation.short_name = "国%d" % owner
		nation.ruler_name = "李%d" % owner
		nation.capital_city_id = owner * 2
		nation.warehouse_city_ids = [owner * 2] as Array[int]
		nation.strategic_region_anchor_city_id = owner * 2
		nation.treasury_gold = 1000000
		nation.manpower_pool = 1000
		nation.ruler_archetype = RulerProfile.BALANCED
		state.nations.append(nation)
		state.administrative_center_city_ids.append(owner * 2)
		for offset in range(2):
			var city := City.new()
			city.id = state.cities.size()
			city.name = "城%d" % city.id
			city.short_name = "城%d" % city.id
			city.owner_nation = owner
			city.map_position = Vector2(owner * 0.1, offset * 0.1)
			city.coord = Vector2i(owner, offset)
			city.food_per_half_year = 100000
			city.manpower_per_month = 1000
			city.gold_per_month = 1000
			city.loyalty = 25.0 if owner == 2 else (25.1 if owner == 3 else 70.0)
			city.loyalty_target_nation = 0 if owner in [1, 2, 3] else owner
			city.has_warehouse = offset == 0
			city.is_capital = offset == 0
			city.food_storage = 800000 if owner == 0 and offset == 0 else 0
			state.cities.append(city)
			state.adjacency[city.id] = [] as Array[int]
			state.recognized_city_owners.append(owner)
			state.administrative_center_by_city.append(owner * 2)
			state.region_ids.append(owner)
		state._add_edge(owner * 2, owner * 2 + 1)
	for a in range(6):
		for b in range(a + 1, 6):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	for subject in [1, 2, 3]:
		state.suzerainty[subject] = {
			"overlord_id": 0, "tribute_rate": 0.0, "created_day": 0,
			"last_centralization_day": -1, "civil_war": false,
		}
		state.nations[subject].name_kind = WorldNaming.KIND_VASSAL
		state.set_diplomatic_relation(0, subject, GameState.DiplomaticRelation.ALLIED)
	# Root has reachable loyal and disloyal subjects. In the isolation case only
	# neutral outsider 4 connects the initiator, so no legitimate transit exists.
	for edge in [[0, 4], [0, 6], [4, 6]]:
		state._add_edge(edge[0], edge[1])
	if isolated:
		state._add_edge(0, 8)
		state._add_edge(8, 2)
	else:
		for edge in [[0, 2], [2, 4], [2, 6]]:
			state._add_edge(edge[0], edge[1])
		state.set_diplomatic_relation(0, 4, GameState.DiplomaticRelation.ALLIED)
	state.diplomacy_revision += 1
	state.ownership_revision += 1
	FamilyTree.ensure_all(state)
	state.refresh_derived()
	return state


func fingerprint(state: GameState) -> PackedByteArray:
	var cities: Array = []
	var nations: Array = []
	var armies: Array = []
	for city in state.cities:
		cities.append([city.owner_nation, city.food_storage, city.loyalty,
			city.loyalty_target_nation, city.has_warehouse, city.is_capital])
	for nation in state.nations:
		nations.append([nation.alive, nation.capital_city_id, nation.name,
			nation.name_kind, nation.treasury_gold, nation.manpower_pool,
			nation.last_rebellion_day, nation.ruler_person_id, nation.state_level])
	for army in state.armies:
		armies.append([army.id, army.owner_nation, army.size, army.location_city,
			army.campaign_war_id, army.battle_id])
	var conflicts: Dictionary = {}
	for property in state.get_property_list():
		if str(property.name) == "vassal_conflicts":
			conflicts = state.get("vassal_conflicts")
	return var_to_bytes([cities, nations, armies, state.suzerainty,
		state.diplomatic_relations, state.war_relation_ids, state.next_war_id,
		state.ownership_revision, state.diplomacy_revision,
		state.chronicle_events, state.diplomatic_history, state.rng.state,
		state.truce_until_day, state.war_objectives, state.family_trees, conflicts])


func total_food(state: GameState) -> int:
	var total := 0
	for city in state.cities:
		total += city.food_storage
	return total


func plan(state: GameState, subject: int) -> Dictionary:
	if not state.has_method("plan_vassal_conflict"):
		check(false, "GameState exposes the read-only conflict planner")
		return {}
	return state.call("plan_vassal_conflict", subject)


func test_read_only_and_independence() -> void:
	var state := fixture(true)
	var before := fingerprint(state)
	var proposed := plan(state, 1)
	check(str(proposed.get("mode", "")) == "independence", "neutral territory isolation plans direct independence")
	check(plan(state, 1) == proposed, "repeated isolation queries produce an identical proposal")
	check(fingerprint(state) == before, "planning leaves ownership, politics, stock, history and random stream untouched")
	var food_before := total_food(state)
	var nation_count := state.nations.size()
	var ruler_before := state.nations[1].ruler_person_id
	check(state.start_civil_war(1), "isolated launch successfully commits independence")
	check(not state.is_vassal(1) and not state.is_in_civil_war(1), "isolated initiator becomes independent without civil-war flag")
	check(state.wars_of(1).is_empty() and state.armies.is_empty(), "independence creates neither war nor uprising soldiers")
	check(state.nations.size() == nation_count and state.nations[1].ruler_person_id == ruler_before, "independence preserves nation and bloodline identity")
	check(state.overlord_of(2) == 0 and state.overlord_of(3) == 0
		and not state.is_in_civil_war(2) and not state.is_in_civil_war(3), "isolation never activates other princes' loyalties")
	check(not state.is_allied(1, 0) and not state.is_enemy(1, 0)
		and state.truce_until(1, 0) == state.day + 180, "independence is neutral with the former root and starts 180-day truce")
	check(state.truce_until(1, 2) == state.day + 180 and state.truce_until(1, 3) == state.day + 180, "truce covers former fellow princes")
	check(total_food(state) == food_before and state.food_pool_holder(1) == 1
		and state.cities[2].food_storage > 0, "direct independence splits food conservatively into a usable own pool")
	var committed := fingerprint(state)
	check(not state.start_civil_war(1) and fingerprint(state) == committed, "repeat independence launch has no side effects")


func test_factions_and_external_war() -> void:
	var state := fixture()
	# A separate pre-existing external war must not merge into the civil war.
	state.set_diplomatic_relation(0, 5, GameState.DiplomaticRelation.WAR)
	var external_id := state.war_id_between(0, 5)
	var before := fingerprint(state)
	check(str(plan(state, 1).get("mode", "")) == "war", "a connected initiator plans a faction war")
	check(fingerprint(state) == before, "faction planning is read-only, including random stream")
	var food_before := total_food(state)
	check(state.start_civil_war(1), "faction launch succeeds")
	var war_id := state.war_id_between(0, 1)
	check(war_id >= 0 and war_id != external_id, "civil conflict receives its own war ID")
	for central in [0, 3]:
		for rebel in [1, 2]:
			check(state.is_enemy(central, rebel) and state.war_id_between(central, rebel) == war_id,
				"all opposing princes share civil war: %d/%d" % [central, rebel])
	check(state.has_military_access(1, 2) and state.has_military_access(2, 1)
		and state.has_military_access(0, 3) and state.has_military_access(3, 0), "same-side princes grant bidirectional military transit")
	check(state.is_allied(1, 2) and state.is_allied(0, 3), "same-side members are allied rather than merely sharing an enemy")
	check(not state.is_enemy(4, 1) and not state.is_enemy(4, 2), "ordinary outside ally is not enrolled against rebels")
	check(state.war_id_between(0, 5) == external_id and not state.is_enemy(1, 5), "external war retains independent identity and participants")
	check(state.food_pool_holder(0) == 0 and state.food_pool_holder(3) == 0
		and state.food_pool_holder(1) != 0 and state.food_pool_holder(2) != 0,
		"loyal pool remains linked while both rebels leave the root food pool")
	check(total_food(state) == food_before, "simultaneous rebel food split and uprising conserve total stored food")
	var uprising_owners: Array[int] = []
	for army in state.armies:
		if army.size > 0:
			uprising_owners.append(army.owner_nation)
	check(not uprising_owners.is_empty() and uprising_owners.all(func(owner): return owner == 1),
		"only the original initiator receives uprising armies")
	for city in state.land_cities_of(2):
		city.loyalty = 100
	for city in state.land_cities_of(3):
		city.loyalty = 0
	var committed := fingerprint(state)
	check(not state.start_civil_war(3) and fingerprint(state) == committed, "an active system cannot re-roll sides or launch another war")
	check(state.is_enemy(0, 2) and state.is_enemy(1, 3), "faction membership remains fixed after loyalty changes")


func test_reject_is_atomic() -> void:
	var state := fixture()
	state.nations[1].capital_city_id = -1
	var before := fingerprint(state)
	check(str(plan(state, 1).get("mode", "")) == "reject", "invalid capital is rejected by planning")
	check(not state.start_civil_war(1) and fingerprint(state) == before, "failed transaction leaves armies, stock, relations and history untouched")
	check(not state.start_civil_war(-1) and fingerprint(state) == before, "invalid initiator is rejected without mutation")


func test_capital_winner(winner: int, captor_owner: int) -> void:
	var state := fixture()
	check(state.start_civil_war(1), "capital transaction starts civil conflict")
	var loser := 1 if winner == 0 else 0
	var war_id := state.war_id_between(0, 1)
	var loser_cities: Array[int] = []
	for city in state.land_cities_of(loser):
		loser_cities.append(city.id)
	var capital := state.nations[loser].capital_city_id
	var army := state.create_army(captor_owner, state.nations[captor_owner].capital_city_id, 15000)
	check(army != null, "capturing ally has a real army")
	if army == null:
		return
	army.campaign_war_id = war_id
	army.location_city = capital
	army.move_from = capital
	army.move_to = capital
	army.state = Army.State.MOVING
	army.occupation_claimant_nation = loser
	var gold_before := state.nations[winner].treasury_gold + state.nations[loser].treasury_gold
	var manpower_before := state.nations[winner].manpower_pool + state.nations[loser].manpower_pool
	var garrison_before := state.cities[capital].garrison_manpower
	var sim := Simulation.new()
	sim.setup(state)
	# Explicit actual occupying prince ensures resolution cannot just rely on
	# ordinary allied-occupation claimant redirection.
	sim._capture_city(army, state.cities[capital], captor_owner)
	check(not state.nations[loser].alive and state.nations[winner].alive,
		"real capital capture extinguishes only the losing leader: winner%d captor%d" % [winner, captor_owner])
	check(state.nations[winner].treasury_gold == gold_before and state.nations[loser].treasury_gold == 0,
		"all absorbed treasury belongs to faction leader after actual victory")
	var garrison_added := maxi(state.cities[capital].garrison_manpower - garrison_before, 0)
	check(state.nations[winner].manpower_pool == mini(manpower_before, state.manpower_pool_capacity(winner)) - garrison_added
		and state.nations[loser].manpower_pool == 0,
		"absorbed manpower fills capital garrison from faction leader pool under the existing capacity limit")
	check(army.location_city == capital and army.move_to == -1 and army.state == Army.State.IDLE
		and army.occupation_claimant_nation == -1,
		"actual captor completes movement and clears occupation claim after leader or ally victory")
	for city_id in loser_cities:
		check(state.cities[city_id].owner_nation == winner and state.recognized_owner_of(city_id) == winner,
			"leader receives the loser territory rather than capturing prince: city%d" % city_id)
	check(state.nations[2].alive and state.nations[3].alive
		and state.overlord_of(2) == winner and state.overlord_of(3) == winner,
		"surviving princes keep their countries and submit to victorious leader")
	check(not state.is_vassal(winner), "victorious faction head is sovereign")
	for a in [0, 1, 2, 3]:
		for b in [0, 1, 2, 3]:
			check(not state.is_enemy(a, b), "civil war fully ends for pair%d/%d" % [a, b])
	for member in [winner, 2, 3]:
		check(not state.is_in_civil_war(member), "civil marker cleared for surviving member%d" % member)
	check(not state.war_relation_ids.values().has(war_id), "finished civil-war ID has no remaining diplomatic bindings")
	for surviving_army in state.armies:
		check(surviving_army.campaign_war_id != war_id, "finished war releases every participant army")
	check(state.territory_structure_valid() and state.suzerainty_structure_valid(), "real victory maintains political and territory invariants")
	var settled := fingerprint(state)
	sim._resolve_civil_war_capital_capture(loser, captor_owner)
	check(fingerprint(state) == settled, "repeated resolution cannot transfer resources or emit another event")
	sim.free()


func test_nonleader_capital_is_occupation() -> void:
	var state := fixture()
	check(state.start_civil_war(1), "nonleader capture starts conflict")
	var war_id := state.war_id_between(0, 1)
	var army := state.create_army(1, 2, 15000)
	var sim := Simulation.new()
	sim.setup(state)
	sim._capture_city(army, state.cities[6], 1)
	check(state.nations[0].alive and state.nations[1].alive
		and state.nations[3].alive and state.cities[6].owner_nation == 1
		and state.recognized_owner_of(6) == 3, "nonleader capital is temporary occupation without leader annexation")
	check(state.war_id_between(0, 1) == war_id, "nonleader loss does not conclude the whole war")
	sim._capture_city(army, state.cities[0], 1)
	check(state.nations[3].alive and state.cities[6].owner_nation == 3
		and state.overlord_of(3) == 1, "war settlement restores surviving prince's temporarily occupied capital")
	sim.free()


func test_external_leader_annexation(loser: int) -> void:
	var state := fixture()
	check(state.start_civil_war(1), "external annexation begins with actual internal war")
	var war_id := state.war_id_between(0, 1)
	state.set_diplomatic_relation(5, loser, GameState.DiplomaticRelation.WAR)
	var external_id := state.war_id_between(5, loser)
	var loser_cities: Array[int] = []
	for city in state.land_cities_of(loser):
		loser_cities.append(city.id)
	var survivor := 1 if loser == 0 else 0
	for owner in [survivor, 2, 3]:
		var army := state.create_army(owner, state.nations[owner].capital_city_id, 15000)
		army.campaign_war_id = war_id
	var front := state.create_campaign_front(war_id, [survivor] as Array[int], survivor,
		CoalitionCampaignFront.Mode.OFFENSE, state.nations[loser].capital_city_id)
	check(front != null, "external interruption has a real campaign to release")
	check(state.annex_nation(5, loser), "external third country commits real leader annexation")
	check(not state.nations[loser].alive and state.nations[survivor].alive,
		"external annexation extinguishes the leader without inventing an internal victor")
	for city_id in loser_cities:
		check(state.cities[city_id].owner_nation == 5 and state.recognized_owner_of(city_id) == 5,
			"external winner retains actual annexed territory city%d" % city_id)
	check(state.nations[2].alive and state.nations[3].alive, "external interruption preserves other participating princes")
	var record: Dictionary = state.vassal_conflicts.get(war_id, {})
	check(not record.is_empty() and not bool(record.get("active", true)), "external leader extinction immediately archives the faction conflict")
	check(str(record.get("outcome", "")) == "external_leader_loss", "external extinction records administrative interruption")
	check(not state.war_relation_ids.values().has(war_id), "external interruption removes all internal war bindings")
	for army in state.armies:
		check(army.campaign_war_id != war_id, "external interruption releases every participant's army")
	for campaign in state.campaign_fronts.values():
		check(campaign.war_id != war_id, "external interruption removes stale internal campaigns")
	for a in [survivor, 2, 3]:
		for b in [survivor, 2, 3]:
			check(not state.is_enemy(a, b), "external interruption restores internal peace%d/%d" % [a, b])
	check(external_id != war_id and state.territory_structure_valid()
		and state.suzerainty_structure_valid(), "external and internal transactions preserve separate identities and invariants")
	var before := fingerprint(state)
	VassalConflict.reconcile(state)
	check(fingerprint(state) == before, "repeated external reconciliation never emits duplicate event or resource transfer")


func test_native_conflict_validation() -> void:
	var state := fixture()
	check(state.start_civil_war(1), "native fixture starts actual faction conflict")
	var snapshot := NativeSnapshotBuilder.build(state)
	var war_id := state.war_id_between(0, 1)
	check(int(snapshot.get("schema_version", -1)) == 26, "faction snapshots use Native26")
	check(snapshot.get("vassal_conflicts", {}) == state.vassal_conflicts,
		"Native26 preserves factions, leaders, loyalty, days and activity")
	var snapshot_error := NativeSnapshotBuilder.succession_validation_error(snapshot)
	check(snapshot_error.is_empty(), "valid faction snapshot passes the formal native validator: " + snapshot_error)
	var old := snapshot.duplicate(true)
	old.schema_version = 25
	check(not NativeSnapshotBuilder.succession_validation_error(old).is_empty(), "Native25 faction runtime snapshot is explicitly rejected")
	var invalid := snapshot.duplicate(true)
	var native_record: Dictionary = invalid.vassal_conflicts[war_id]
	native_record.central.append(2)
	check(not NativeSnapshotBuilder.succession_validation_error(invalid).is_empty(), "native validator rejects a prince present in both factions")
	invalid = snapshot.duplicate(true)
	(invalid.vassal_conflicts[war_id] as Dictionary).rebel_leader = 3
	check(not NativeSnapshotBuilder.succession_validation_error(invalid).is_empty(), "native validator rejects a leader outside their faction")
	invalid = snapshot.duplicate(true)
	(invalid.nations as Dictionary).erase("overlord")
	check(not NativeSnapshotBuilder.succession_validation_error(invalid).is_empty(), "native rejects missing overlord column with a formal error")
	invalid = snapshot.duplicate(true)
	invalid.nations.suzerainty_civil_war = PackedByteArray([0])
	check(not NativeSnapshotBuilder.succession_validation_error(invalid).is_empty(), "native rejects truncated civil-war column with a formal error")
	invalid = snapshot.duplicate(true)
	invalid.nations.alive = 42
	check(not NativeSnapshotBuilder.succession_validation_error(invalid).is_empty(), "native rejects a non-array alive column without returning an empty error")
	check(VassalConflict.validation_error(state).is_empty(), "live validator accepts an actual valid war")
	var record: Dictionary = state.vassal_conflicts[war_id]
	record.central.append(2)
	check(not VassalConflict.validation_error(state).is_empty(), "live validator rejects overlapping faction membership")
	record.central.erase(2)
	check(VassalConflict.validation_error(state).is_empty(), "restoring membership makes live state valid again")
	var frozen_before := var_to_bytes(snapshot.vassal_conflicts)
	record.loyalty[2] = 99.0
	check(var_to_bytes(snapshot.vassal_conflicts) == frozen_before, "native faction record is frozen independently of future live updates")


func test_alliance_normalization_does_not_expand_conflict() -> void:
	var state := fixture()
	state.set_diplomatic_relation(1, 5, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 5, GameState.DiplomaticRelation.WAR)
	var external_id := state.war_id_between(0, 5)
	check(state.start_civil_war(1), "normalization fixture starts a faction war with intersecting external alliances")
	var internal_id := state.war_id_between(0, 1)
	var sim := TracingSimulation.new()
	sim.setup(state)
	sim._normalize_alliance_wars()
	for central in [0, 3]:
		for rebel in [1, 2]:
			check(state.is_enemy(central, rebel) and state.war_id_between(central, rebel) == internal_id,
				"alliance normalization preserves scoped internal edge%d/%d" % [central, rebel])
	check(not state.is_enemy(4, 1) and not state.is_enemy(4, 2), "external root ally is not enrolled into civil war by normalization")
	check(state.is_enemy(0, 5) and state.war_id_between(0, 5) == external_id and external_id != internal_id,
		"normalization preserves the pre-existing external war without merging it into civil war")
	check(VassalConflict.validation_error(state).is_empty(), "normalized mixed alliance fixture has valid fixed factions")
	sim.free()


func test_external_member_annexation() -> void:
	var state := fixture()
	check(state.start_civil_war(1), "member-extinction fixture launches actual civil conflict")
	var war_id := state.war_id_between(0, 1)
	state.set_diplomatic_relation(5, 2, GameState.DiplomaticRelation.WAR)
	check(state.annex_nation(5, 2), "external power annexes an ordinary faction member through real transaction")
	var record: Dictionary = state.vassal_conflicts.get(war_id, {})
	check(not state.nations[2].alive and state.nations[0].alive and state.nations[1].alive,
		"ordinary member loss never extinguishes either internal leader")
	check(not record.is_empty() and bool(record.get("active", false))
		and not (record.get("central", []) as Array).has(2)
		and not (record.get("rebels", []) as Array).has(2), "ordinary extinct member is removed while internal war remains active")
	check(state.war_id_between(0, 1) == war_id and not state.is_enemy(5, 1),
		"remaining internal participants retain war ID without enrolling the external annexer")
	check(VassalConflict.validation_error(state).is_empty(), "member extinction immediately leaves a valid faction record")


func test_explicit_external_declaration(rebel_ally: bool) -> void:
	var state := fixture()
	if rebel_ally:
		state.set_diplomatic_relation(5, 1, GameState.DiplomaticRelation.ALLIED)
	check(state.start_civil_war(1), "explicit external declaration begins with an active scoped civil war")
	var internal_id := state.war_id_between(0, 1)
	state._add_edge(10, 0)
	state.road_network_revision += 1
	state.nations[5].strategic_region_anchor_city_id = 0
	var in_range := DiplomacyAI.can_initiate_war_at_range(state, 5, 0)
	var permitted := state.can_alliance_declare_war(5, 0)
	check(in_range and permitted, "real external declaration fixture passes border and alliance gates: range=%s alliance=%s attackers=%s defenders=%s" % [
		str(in_range), str(permitted), str(state.alliance_bloc(5)), str(state.alliance_bloc(0))])
	var sim := Simulation.new()
	sim.setup(state)
	var declared := sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR, "a": 5, "b": 0,
		"objective_city": 0, "objective_reason": "外部战争", "reason": "外部战争",
	})
	check(declared and state.is_enemy(5, 0), "explicit ordinary external declaration remains allowed during faction conflict")
	var external_id := state.war_id_between(5, 0)
	check(external_id >= 0 and external_id != internal_id, "explicit external declaration has a separate valid war ID")
	for central in [0, 3]:
		for rebel in [1, 2]:
			check(state.is_enemy(central, rebel) and state.war_id_between(central, rebel) == internal_id,
				"explicit exterior objective never rewrites internal war edge%d/%d" % [central, rebel])
	var snapshot_error := NativeSnapshotBuilder.succession_validation_error(NativeSnapshotBuilder.build(state))
	check(snapshot_error.is_empty(), "explicit exterior declaration leaves a valid Native26 state: " + snapshot_error)
	sim.free()


func test_nonexpanding_campaign() -> void:
	var state := fixture()
	state.nations[2].ruler_archetype = RulerProfile.GUARDIAN
	state.nations[2].ruler_traits = [RulerProfile.TRAIT_CAUTIOUS] as Array[String]
	check(not RulerProfile.offensive_allowed(state.nations[2]), "campaign actor truly has a nonexpanding ruler")
	check(state.start_civil_war(1), "nonexpanding ruler participates through actual allegiance")
	for formation in range(4):
		var army := state.create_army(2, 4, 15000)
		var group := state.create_battle_group(2)
		state.assign_army_to_battle_group(army, group.id)
	state.refresh_derived()
	var sim := Simulation.new()
	sim.setup(state)
	var objective := sim._cached_campaign_objective(2, 0, {})
	check(not objective.is_empty(), "nonexpanding rebel can select a reachable enemy state outside its own operating region")
	var view := AiWorldView.build(state, 2)
	var map := StrategicMapSnapshot.build(view)
	var threat := ThreatField.build(view)
	var defense := CityDefensePlan.build(view, map, threat)
	await sim._run_ai_campaign_planning_phase([2] as Array[int],
		{2: {"view": view, "threat": threat, "defense_plan": defense}},
		{2: {"wars": state.wars_of(2)}}, {}, false, Time.get_ticks_usec())
	check(not state.campaign_fronts_for_nation(2).is_empty(), "nonexpanding rebel creates a real reachable administrative campaign")
	var bound := false
	for army in state.armies:
		if army.owner_nation == 2 and army.campaign_front_id >= 0:
			bound = true
	check(bound, "the real campaign binds actual rebel armies rather than remaining empty")
	sim.free()


func run() -> void:
	test_read_only_and_independence()
	test_factions_and_external_war()
	test_reject_is_atomic()
	for victory in [[0, 0], [1, 1], [0, 3], [1, 2]]:
		test_capital_winner(victory[0], victory[1])
	test_nonleader_capital_is_occupation()
	for leader in [0, 1]:
		test_external_leader_annexation(leader)
	test_native_conflict_validation()
	test_alliance_normalization_does_not_expand_conflict()
	test_external_member_annexation()
	for allied in [false, true]:
		test_explicit_external_declaration(allied)
	await test_nonexpanding_campaign()
	for failure in failures:
		push_error("VASSAL_FACTION_CONFLICT_FAIL: " + failure)
	print("VASSAL_FACTION_CONFLICT_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
