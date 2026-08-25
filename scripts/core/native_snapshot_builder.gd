class_name NativeSnapshotBuilder
extends RefCounted
## 将脚本对象图一次性冻结为 NativeSimulationCore 的版本化 SoA 快照。
## 该桥只允许在日提交边界调用；native tick 接管后，展示层将改读反向只读快照。

const SCHEMA_VERSION: int = 11


static func build(state: GameState) -> Dictionary:
	var nations := _build_nations(state)
	var cities := _build_cities(state)
	var edges_and_indices := _build_edges(state)
	var armies_and_indices := _build_armies(state)
	var battles := _build_battles(
		state,
		edges_and_indices["indices"],
		armies_and_indices["indices"]
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"revision": state.day,
		"day": state.day,
		"rng_state": state.rng.state,
		"next_army_id": state._next_army_id,
		"next_battle_id": state._next_battle_id,
		"winner": state.winner,
		"uses_heightmap": int(state.uses_heightmap),
		"ownership_revision": state.ownership_revision,
		"diplomacy_revision": state.diplomacy_revision,
		"fortification_revision":
			state.fortification_revision,
		"nations": nations,
		"cities": cities,
		"edges": edges_and_indices["snapshot"],
		"armies": armies_and_indices["snapshot"],
		"battles": battles,
	}


static func _build_nations(state: GameState) -> Dictionary:
	var ids := PackedInt32Array()
	var capitals := PackedInt32Array()
	var gold := PackedInt32Array()
	var manpower := PackedInt32Array()
	var last_military_upkeep := PackedInt32Array()
	var unpaid_military_upkeep := PackedInt32Array()
	var payment_ratio := PackedFloat64Array()
	var last_offensive_gold_cost := PackedInt32Array()
	var last_offensive_gold_day := PackedInt32Array()
	var granary_food := PackedInt32Array()
	var last_food_demand := PackedInt32Array()
	var food_demand_ema := PackedFloat64Array()
	var overlord := PackedInt32Array()
	var effective_tribute_rate := PackedFloat64Array()
	var food_pool_holder := PackedInt32Array()
	var suzerainty_tribute_rate := PackedFloat64Array()
	var suzerainty_created_day := PackedInt32Array()
	var suzerainty_last_centralization_day := PackedInt32Array()
	var suzerainty_civil_war := PackedByteArray()
	var next_battle_group_id := PackedInt32Array()
	var battle_group_offsets := PackedInt32Array([0])
	var battle_group_ids := PackedInt32Array()
	var battle_group_created_day := PackedInt32Array()
	var ai_aggression := PackedFloat64Array()
	var war_preparation_target := PackedInt32Array()
	var war_preparation_objective := PackedInt32Array()
	var war_preparation_started_day := PackedInt32Array()
	var campaign_last_offensive_day := PackedInt32Array()
	var campaign_next_offensive_day := PackedInt32Array()
	var campaign_offensive_count := PackedInt32Array()
	var campaign_preparation_started_day := PackedInt32Array()
	var campaign_launched_attack_multiplier := PackedFloat64Array()
	var campaign_launched_bonus_days := PackedInt32Array()
	var campaign_plan_wave := PackedInt32Array()
	var campaign_plan_primary_city := PackedInt32Array()
	var campaign_theater_anchor_city := PackedInt32Array()
	var campaign_theater_started_day := PackedInt32Array()
	var alive := PackedByteArray()
	for nation in state.nations:
		ids.append(nation.id)
		capitals.append(nation.capital_city_id)
		gold.append(nation.treasury_gold)
		manpower.append(nation.manpower_pool)
		last_military_upkeep.append(nation.last_military_upkeep)
		unpaid_military_upkeep.append(
			nation.unpaid_military_upkeep
		)
		payment_ratio.append(nation.military_payment_ratio)
		last_offensive_gold_cost.append(
			nation.last_offensive_gold_cost
		)
		last_offensive_gold_day.append(nation.last_offensive_gold_day)
		granary_food.append(nation.granary_food)
		last_food_demand.append(nation.last_food_demand)
		food_demand_ema.append(nation.food_demand_ema)
		overlord.append(state.overlord_of(nation.id))
		effective_tribute_rate.append(
			Simulation.effective_tribute_rate(
				state,
				nation.id
			)
		)
		food_pool_holder.append(
			state.food_pool_holder(nation.id)
		)
		var suzerainty_record := state.suzerainty_record(nation.id)
		suzerainty_tribute_rate.append(float(
			suzerainty_record.get("tribute_rate", 0.0)
		))
		suzerainty_created_day.append(int(
			suzerainty_record.get("created_day", -1)
		))
		suzerainty_last_centralization_day.append(int(
			suzerainty_record.get(
				"last_centralization_day",
				-1
			)
		))
		suzerainty_civil_war.append(int(
			suzerainty_record.get("civil_war", false)
		))
		next_battle_group_id.append(nation.next_battle_group_id)
		for group in nation.battle_groups:
			battle_group_ids.append(group.id)
			battle_group_created_day.append(group.created_day)
		battle_group_offsets.append(battle_group_ids.size())
		ai_aggression.append(nation.ai_aggression)
		war_preparation_target.append(
			nation.war_preparation_target_nation
		)
		war_preparation_objective.append(
			nation.war_preparation_objective_city
		)
		war_preparation_started_day.append(
			nation.war_preparation_started_day
		)
		campaign_last_offensive_day.append(
			nation.campaign_last_offensive_day
		)
		campaign_next_offensive_day.append(
			nation.campaign_next_offensive_day
		)
		campaign_offensive_count.append(
			nation.campaign_offensive_count
		)
		campaign_preparation_started_day.append(
			nation.campaign_preparation_started_day
		)
		campaign_launched_attack_multiplier.append(
			nation.campaign_launched_attack_multiplier
		)
		campaign_launched_bonus_days.append(
			nation.campaign_launched_bonus_days
		)
		campaign_plan_wave.append(nation.campaign_plan_wave)
		campaign_plan_primary_city.append(
			nation.campaign_plan_primary_city
		)
		campaign_theater_anchor_city.append(
			nation.campaign_theater_anchor_city
		)
		campaign_theater_started_day.append(
			nation.campaign_theater_started_day
		)
		alive.append(int(nation.alive))

	var diplomacy := PackedByteArray()
	var diplomacy_since_day := PackedInt32Array()
	var truce_until_day := PackedInt32Array()
	var war_objective_city := PackedInt32Array()
	var war_objective_started_day := PackedInt32Array()
	for nation_a in range(state.nations.size()):
		for nation_b in range(state.nations.size()):
			diplomacy.append(
				state.relation_between(nation_a, nation_b)
			)
			diplomacy_since_day.append(
				state.relation_since(nation_a, nation_b)
			)
			truce_until_day.append(
				state.truce_until(nation_a, nation_b)
			)
			var objective := state.war_objective(
				nation_a,
				nation_b
			)
			var directed := (
				not objective.is_empty()
				and int(objective.get("attacker", -1)) == nation_a
				and int(objective.get("defender", -1)) == nation_b
			)
			war_objective_city.append(
				int(objective.get("city_id", -1))
				if directed
				else -1
			)
			war_objective_started_day.append(
				int(objective.get("started_day", -1))
				if directed
				else -1
			)
	return {
		"count": state.nations.size(),
		"ids": ids,
		"capitals": capitals,
		"gold": gold,
		"manpower": manpower,
		"last_military_upkeep": last_military_upkeep,
		"unpaid_military_upkeep": unpaid_military_upkeep,
		"payment_ratio": payment_ratio,
		"last_offensive_gold_cost": last_offensive_gold_cost,
		"last_offensive_gold_day": last_offensive_gold_day,
		"granary_food": granary_food,
		"last_food_demand": last_food_demand,
		"food_demand_ema": food_demand_ema,
		"overlord": overlord,
		"effective_tribute_rate": effective_tribute_rate,
		"food_pool_holder": food_pool_holder,
		"suzerainty_tribute_rate": suzerainty_tribute_rate,
		"suzerainty_created_day": suzerainty_created_day,
		"suzerainty_last_centralization_day":
			suzerainty_last_centralization_day,
		"suzerainty_civil_war": suzerainty_civil_war,
		"next_battle_group_id": next_battle_group_id,
		"battle_group_offsets": battle_group_offsets,
		"battle_group_ids": battle_group_ids,
		"battle_group_created_day": battle_group_created_day,
		"ai_aggression": ai_aggression,
		"war_preparation_target": war_preparation_target,
		"war_preparation_objective": war_preparation_objective,
		"war_preparation_started_day":
			war_preparation_started_day,
		"campaign_last_offensive_day":
			campaign_last_offensive_day,
		"campaign_next_offensive_day":
			campaign_next_offensive_day,
		"campaign_offensive_count":
			campaign_offensive_count,
		"campaign_preparation_started_day":
			campaign_preparation_started_day,
		"campaign_launched_attack_multiplier":
			campaign_launched_attack_multiplier,
		"campaign_launched_bonus_days":
			campaign_launched_bonus_days,
		"campaign_plan_wave": campaign_plan_wave,
		"campaign_plan_primary_city":
			campaign_plan_primary_city,
		"campaign_theater_anchor_city":
			campaign_theater_anchor_city,
		"campaign_theater_started_day":
			campaign_theater_started_day,
		"alive": alive,
		"diplomacy": diplomacy,
		"diplomacy_since_day": diplomacy_since_day,
		"truce_until_day": truce_until_day,
		"war_objective_city": war_objective_city,
		"war_objective_started_day":
			war_objective_started_day,
	}


static func _build_cities(state: GameState) -> Dictionary:
	var ids := PackedInt32Array()
	var position_x := PackedFloat64Array()
	var position_y := PackedFloat64Array()
	var terrain_height := PackedFloat64Array()
	var terrain_relief := PackedFloat64Array()
	var owner := PackedInt32Array()
	var recognized_owner := PackedInt32Array()
	var occupation_sponsor := PackedInt32Array()
	var fort := PackedInt32Array()
	var fort_max := PackedInt32Array()
	var fort_last_capture_day := PackedInt32Array()
	var manpower_output := PackedInt32Array()
	var food := PackedInt32Array()
	var gold_output := PackedInt32Array()
	var food_output := PackedInt32Array()
	var warehouse := PackedByteArray()
	var food_hub := PackedByteArray()
	var manpower_hub := PackedByteArray()
	var at_war := PackedByteArray()
	var war_disruption_until_day := PackedInt32Array()
	for city in state.cities:
		ids.append(city.id)
		position_x.append(city.map_position.x)
		position_y.append(city.map_position.y)
		terrain_height.append(city.terrain_height)
		terrain_relief.append(city.terrain_relief)
		owner.append(city.owner_nation)
		recognized_owner.append(state.recognized_owner_of(city.id))
		occupation_sponsor.append(city.occupation_sponsor_nation)
		fort.append(city.fort_strength)
		fort_max.append(city.fort_strength_max)
		fort_last_capture_day.append(city.fort_last_capture_day)
		manpower_output.append(city.manpower_per_month)
		food.append(city.food_storage)
		gold_output.append(city.gold_per_month)
		food_output.append(city.food_per_half_year)
		warehouse.append(int(city.has_warehouse))
		food_hub.append(int(city.is_food_hub))
		manpower_hub.append(int(city.is_manpower_hub))
		at_war.append(int(city.at_war))
		war_disruption_until_day.append(
			city.war_disruption_until_day
		)
	return {
		"count": state.cities.size(),
		"ids": ids,
		"position_x": position_x,
		"position_y": position_y,
		"terrain_height": terrain_height,
		"terrain_relief": terrain_relief,
		"owner": owner,
		"recognized_owner": recognized_owner,
		"occupation_sponsor": occupation_sponsor,
		"fort": fort,
		"fort_max": fort_max,
		"fort_last_capture_day": fort_last_capture_day,
		"manpower_output": manpower_output,
		"food": food,
		"gold_output": gold_output,
		"food_output": food_output,
		"warehouse": warehouse,
		"food_hub": food_hub,
		"manpower_hub": manpower_hub,
		"at_war": at_war,
		"war_disruption_until_day": war_disruption_until_day,
	}


static func _build_edges(state: GameState) -> Dictionary:
	var city_a := PackedInt32Array()
	var city_b := PackedInt32Array()
	var kind := PackedInt32Array()
	var capacity := PackedInt32Array()
	var distance := PackedInt32Array()
	var danger := PackedFloat64Array()
	var travel_multiplier := PackedFloat64Array()
	var supply_multiplier := PackedFloat64Array()
	var allows_holding := PackedByteArray()
	var occupied := PackedByteArray()
	var passing_count := PackedInt32Array()
	var indices := {}
	for index in range(state.edges.size()):
		var edge: Edge = state.edges[index]
		indices[edge] = index
		city_a.append(edge.city_a)
		city_b.append(edge.city_b)
		kind.append(edge.kind)
		capacity.append(edge.max_manpower)
		distance.append(edge.distance)
		danger.append(edge.danger)
		travel_multiplier.append(edge.travel_time_multiplier)
		supply_multiplier.append(edge.supply_loss_multiplier)
		allows_holding.append(int(edge.allows_holding))
		occupied.append(int(edge.occupied))
		passing_count.append(edge.passing_count)
	return {
		"indices": indices,
		"snapshot": {
			"count": state.edges.size(),
			"a": city_a,
			"b": city_b,
			"kind": kind,
			"capacity": capacity,
			"distance": distance,
			"danger": danger,
			"travel_multiplier": travel_multiplier,
			"supply_multiplier": supply_multiplier,
			"allows_holding": allows_holding,
			"occupied": occupied,
			"passing_count": passing_count,
		},
	}


static func _build_armies(state: GameState) -> Dictionary:
	var ids := PackedInt32Array()
	var owner := PackedInt32Array()
	var size := PackedInt32Array()
	var max_size := PackedInt32Array()
	var speed_factor := PackedFloat64Array()
	var attack := PackedInt32Array()
	var defense := PackedInt32Array()
	var strategic_role := PackedInt32Array()
	var battle_group_id := PackedInt32Array()
	var line_assignment_city := PackedInt32Array()
	var line_assignment_posture := PackedInt32Array()
	var line_assignment_edge := PackedInt32Array()
	var states := PackedInt32Array()
	var location := PackedInt32Array()
	var move_from := PackedInt32Array()
	var move_to := PackedInt32Array()
	var battle_id := PackedInt32Array()
	var path_offsets := PackedInt32Array([0])
	var path_cities := PackedInt32Array()
	var path_cursor := PackedInt32Array()
	var move_progress := PackedFloat64Array()
	var morale := PackedFloat64Array()
	var max_morale := PackedFloat64Array()
	var supply_ratio := PackedFloat64Array()
	var supply_debt := PackedFloat64Array()
	var supply_food_debt := PackedFloat64Array()
	var holding_days := PackedInt32Array()
	var hold_target_progress := PackedFloat64Array()
	var offensive_multiplier := PackedFloat64Array()
	var offensive_until_day := PackedInt32Array()
	var defensive_deployment_until_day := PackedInt32Array()
	var defensive_blocked_edge_a := PackedInt32Array()
	var defensive_blocked_edge_b := PackedInt32Array()
	var occupation_claimant := PackedInt32Array()
	var ai_action := PackedInt32Array()
	var ai_target_city := PackedInt32Array()
	var ai_order_created_day := PackedInt32Array()
	var ai_order_until_day := PackedInt32Array()
	var ai_order_score := PackedFloat64Array()
	var campaign_preparation_target := PackedInt32Array()
	var campaign_attack_target := PackedInt32Array()
	var campaign_echelon := PackedInt32Array()
	var on_edge := PackedByteArray()
	var encounter_blocked := PackedByteArray()
	var starving := PackedByteArray()
	var resume_holding_after_battle := PackedByteArray()
	var forced_retreat := PackedByteArray()
	var diplomatic_repatriation := PackedByteArray()
	var campaign_launched := PackedByteArray()
	var indices := {}
	for index in range(state.armies.size()):
		var army: Army = state.armies[index]
		indices[army] = index
		ids.append(army.id)
		owner.append(army.owner_nation)
		size.append(army.size)
		max_size.append(army.max_size)
		speed_factor.append(army.speed_factor)
		attack.append(army.attack)
		defense.append(army.defense)
		strategic_role.append(army.strategic_role)
		battle_group_id.append(army.battle_group_id)
		line_assignment_city.append(army.line_assignment_city)
		line_assignment_posture.append(army.line_assignment_posture)
		line_assignment_edge.append(army.line_assignment_edge)
		states.append(army.state)
		location.append(army.location_city)
		move_from.append(army.move_from)
		move_to.append(army.move_to)
		battle_id.append(army.battle_id)
		path_cities.append_array(PackedInt32Array(army.path))
		path_offsets.append(path_cities.size())
		path_cursor.append(0)
		move_progress.append(army.move_progress)
		morale.append(army.morale)
		max_morale.append(army.max_morale)
		supply_ratio.append(army.supply_ratio)
		supply_debt.append(army.supply_debt)
		supply_food_debt.append(army.supply_food_debt)
		holding_days.append(army.holding_days)
		hold_target_progress.append(army.hold_target_progress)
		offensive_multiplier.append(
			army.offensive_attack_multiplier
		)
		offensive_until_day.append(army.offensive_bonus_until_day)
		defensive_deployment_until_day.append(
			army.defensive_deployment_until_day
		)
		defensive_blocked_edge_a.append(
			army.defensive_blocked_edge_a
		)
		defensive_blocked_edge_b.append(
			army.defensive_blocked_edge_b
		)
		occupation_claimant.append(
			army.occupation_claimant_nation
		)
		ai_action.append(army.ai_action)
		ai_target_city.append(army.ai_target_city)
		ai_order_created_day.append(army.ai_order_created_day)
		ai_order_until_day.append(army.ai_order_until_day)
		ai_order_score.append(army.ai_order_score)
		campaign_preparation_target.append(int(
			state.nations[army.owner_nation]
				.campaign_preparation_assignments.get(army.id, -1)
		))
		campaign_attack_target.append(int(
			state.nations[army.owner_nation]
				.campaign_attack_assignments.get(army.id, -1)
		))
		campaign_echelon.append(int(
			state.nations[army.owner_nation]
				.campaign_attack_echelons.get(army.id, -1)
		))
		on_edge.append(int(army.on_edge))
		encounter_blocked.append(int(army.encounter_blocked))
		starving.append(int(army.starving))
		resume_holding_after_battle.append(
			int(army.resume_holding_after_battle)
		)
		forced_retreat.append(int(army.forced_retreat))
		diplomatic_repatriation.append(
			int(army.diplomatic_repatriation)
		)
		campaign_launched.append(int(
			state.nations[army.owner_nation]
				.campaign_launched_armies.has(army.id)
		))
	return {
		"indices": indices,
		"snapshot": {
			"count": state.armies.size(),
			"id": ids,
			"owner": owner,
			"size": size,
			"max_size": max_size,
			"speed_factor": speed_factor,
			"attack": attack,
			"defense": defense,
			"strategic_role": strategic_role,
			"battle_group_id": battle_group_id,
			"line_assignment_city": line_assignment_city,
			"line_assignment_posture": line_assignment_posture,
			"line_assignment_edge": line_assignment_edge,
			"state": states,
			"location": location,
			"move_from": move_from,
			"move_to": move_to,
			"battle_id": battle_id,
			"path_offsets": path_offsets,
			"path_cities": path_cities,
			"path_cursor": path_cursor,
			"move_progress": move_progress,
			"morale": morale,
			"max_morale": max_morale,
			"supply_ratio": supply_ratio,
			"supply_debt": supply_debt,
			"supply_food_debt": supply_food_debt,
			"holding_days": holding_days,
			"hold_target_progress": hold_target_progress,
			"offensive_multiplier": offensive_multiplier,
			"offensive_until_day": offensive_until_day,
			"defensive_deployment_until_day":
				defensive_deployment_until_day,
			"defensive_blocked_edge_a":
				defensive_blocked_edge_a,
			"defensive_blocked_edge_b":
				defensive_blocked_edge_b,
			"occupation_claimant": occupation_claimant,
			"ai_action": ai_action,
			"ai_target_city": ai_target_city,
			"ai_order_created_day": ai_order_created_day,
			"ai_order_until_day": ai_order_until_day,
			"ai_order_score": ai_order_score,
			"campaign_preparation_target":
				campaign_preparation_target,
			"campaign_attack_target": campaign_attack_target,
			"campaign_echelon": campaign_echelon,
			"on_edge": on_edge,
			"encounter_blocked": encounter_blocked,
			"starving": starving,
			"resume_holding_after_battle":
				resume_holding_after_battle,
			"forced_retreat": forced_retreat,
			"diplomatic_repatriation":
				diplomatic_repatriation,
			"campaign_launched": campaign_launched,
		},
	}


static func _build_battles(
	state: GameState,
	edge_indices: Dictionary,
	army_indices: Dictionary
) -> Dictionary:
	var ids := PackedInt32Array()
	var kind := PackedInt32Array()
	var edge_index := PackedInt32Array()
	var city_index := PackedInt32Array()
	var contact_dist_a := PackedFloat64Array()
	var contact_dist_b := PackedFloat64Array()
	var holding_side := PackedInt32Array()
	var holding_days := PackedFloat64Array()
	var round_no := PackedInt32Array()
	var reinforcement_morale_a := PackedFloat64Array()
	var reinforcement_morale_b := PackedFloat64Array()
	var tactical_key_a := PackedInt32Array()
	var tactical_key_b := PackedInt32Array()
	var siege_progress := PackedFloat64Array()
	var siege_required := PackedInt32Array()
	var has_garrison := PackedByteArray()
	var finished := PackedByteArray()
	var winner_side := PackedInt32Array()
	var side_a_offsets := PackedInt32Array([0])
	var side_a_armies := PackedInt32Array()
	var side_b_offsets := PackedInt32Array([0])
	var side_b_armies := PackedInt32Array()
	var fresh_a_offsets := PackedInt32Array([0])
	var fresh_a_armies := PackedInt32Array()
	var fresh_b_offsets := PackedInt32Array([0])
	var fresh_b_armies := PackedInt32Array()
	var routed_a_offsets := PackedInt32Array([0])
	var routed_a_armies := PackedInt32Array()
	var routed_b_offsets := PackedInt32Array([0])
	var routed_b_armies := PackedInt32Array()
	var side_a_priority := PackedInt32Array()
	var side_b_priority := PackedInt32Array()
	for battle in state.battles:
		ids.append(battle.id)
		kind.append(battle.kind)
		edge_index.append(
			int(edge_indices.get(battle.edge, -1))
		)
		city_index.append(
			battle.city.id if battle.city != null else -1
		)
		contact_dist_a.append(battle.contact_dist_a)
		contact_dist_b.append(battle.contact_dist_b)
		holding_side.append(battle.holding_side)
		holding_days.append(battle.holding_days)
		round_no.append(battle.round_no)
		reinforcement_morale_a.append(
			battle.reinforcement_morale_gained_a
		)
		reinforcement_morale_b.append(
			battle.reinforcement_morale_gained_b
		)
		tactical_key_a.append(battle.tactical_key_a)
		tactical_key_b.append(battle.tactical_key_b)
		siege_progress.append(battle.siege_progress)
		siege_required.append(battle.siege_required)
		has_garrison.append(int(battle.has_garrison))
		finished.append(int(battle.finished))
		winner_side.append(battle.winner_side)
		for army in battle.side_a:
			side_a_armies.append(
				int(army_indices.get(army, -1))
			)
			side_a_priority.append(
				int(battle.frontline_priority_a.get(
					army,
					1 << 30
				))
			)
		side_a_offsets.append(side_a_armies.size())
		for army in battle.side_b:
			side_b_armies.append(
				int(army_indices.get(army, -1))
			)
			side_b_priority.append(
				int(battle.frontline_priority_b.get(
					army,
					1 << 30
				))
			)
		side_b_offsets.append(side_b_armies.size())
		for army in battle.reinforce_fresh_a:
			fresh_a_armies.append(
				int(army_indices.get(army, -1))
			)
		fresh_a_offsets.append(fresh_a_armies.size())
		for army in battle.reinforce_fresh_b:
			fresh_b_armies.append(
				int(army_indices.get(army, -1))
			)
		fresh_b_offsets.append(fresh_b_armies.size())
		for army in battle.routed_a:
			routed_a_armies.append(
				int(army_indices.get(army, -1))
			)
		routed_a_offsets.append(routed_a_armies.size())
		for army in battle.routed_b:
			routed_b_armies.append(
				int(army_indices.get(army, -1))
			)
		routed_b_offsets.append(routed_b_armies.size())
	return {
		"count": state.battles.size(),
		"id": ids,
		"kind": kind,
		"edge_index": edge_index,
		"city_index": city_index,
		"contact_dist_a": contact_dist_a,
		"contact_dist_b": contact_dist_b,
		"holding_side": holding_side,
		"holding_days": holding_days,
		"round_no": round_no,
		"reinforcement_morale_a": reinforcement_morale_a,
		"reinforcement_morale_b": reinforcement_morale_b,
		"tactical_key_a": tactical_key_a,
		"tactical_key_b": tactical_key_b,
		"siege_progress": siege_progress,
		"siege_required": siege_required,
		"has_garrison": has_garrison,
		"finished": finished,
		"winner_side": winner_side,
		"side_a_offsets": side_a_offsets,
		"side_a_armies": side_a_armies,
		"side_b_offsets": side_b_offsets,
		"side_b_armies": side_b_armies,
		"fresh_a_offsets": fresh_a_offsets,
		"fresh_a_armies": fresh_a_armies,
		"fresh_b_offsets": fresh_b_offsets,
		"fresh_b_armies": fresh_b_armies,
		"routed_a_offsets": routed_a_offsets,
		"routed_a_armies": routed_a_armies,
		"routed_b_offsets": routed_b_offsets,
		"routed_b_armies": routed_b_armies,
		"side_a_priority": side_a_priority,
		"side_b_priority": side_b_priority,
	}
