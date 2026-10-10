# Exact cf80691 reserve-balancing implementation, retained as a regression oracle.
extends "res://scripts/simulation/simulation.gd"

func _balance_national_reserves(
	nation_id: int,
	defense_plan: CityDefensePlan,
	mobilization_claims: Dictionary = {}
) -> bool:
	if defense_plan == null or defense_plan.view == null:
		return false
	var centers: Array[int] = []
	for center_value in state.administrative_center_city_ids:
		var center_id := int(center_value)
		if state.cities[center_id].owner_nation == nation_id:
			centers.append(center_id)
	if centers.size() <= 1:
		return false
	EquivariantOrder.sort_city_ids(centers, state, nation_id)
	var counts := {}
	for center_id in centers:
		counts[center_id] = 0
	var reserves: Array[Army] = []
	for army in state.armies:
		if (
			army.owner_nation != nation_id
			or mobilization_claims.has(army.id)
			or not state.army_effective_for_field_campaign(army)
			or army.state != Army.State.IDLE
			or army.on_edge
			or state.campaign_assignment_center(army.id) >= 0
			or army.campaign_war_id >= 0
			or army.battle_id >= 0
		):
			continue
		reserves.append(army)
		var current_center := state.administrative_center_of(
			army.location_city
		)
		if counts.has(current_center):
			counts[current_center] = int(counts[current_center]) + 1
	reserves.sort_custom(func(a: Army, b: Army) -> bool:
		return EquivariantOrder.army_less(state, nation_id, a, b)
	)
	var changed := false
	for army in reserves:
		var current_center := state.administrative_center_of(
			army.location_city
		)
		var target_center := -1
		var target_distance := INF
		var field := defense_plan.view.path_field(
			army.location_city, nation_id, false, true, -1, army.max_size
		)
		for center_id in centers:
			var distance := float(field["dist"].get(center_id, INF))
			if distance == INF:
				continue
			if target_center < 0:
				target_center = center_id
				target_distance = distance
				continue
			var target_count := int(counts[target_center])
			var candidate_count := int(counts[center_id])
			var equally_loaded_but_better := (
				candidate_count == target_count
				and (
					distance < target_distance
					or (
						is_equal_approx(distance, target_distance)
						and EquivariantOrder.mirror_orbit_city_less(
							state, center_id, target_center
						)
					)
				)
			)
			if candidate_count < target_count or equally_loaded_but_better:
				target_center = center_id
				target_distance = distance
		if target_center < 0:
			continue
		if current_center == target_center and army.location_city == target_center:
			continue
		if (
			counts.has(current_center)
			and int(counts[current_center])
				<= int(counts[target_center]) + 1
		):
			continue
		var redeploy := ActionCandidate.make(
			ActionCandidate.Kind.REINFORCE,
			900.0,
			"国家预备队：军%d均衡驻扎州治%d" % [army.id, target_center],
			target_center
		)
		redeploy.minimum_commit_days = CAMPAIGN_OFFENSIVE_COMMIT_DAYS
		redeploy.defensive_deployment = true
		if not _execute_ai_candidate(army, redeploy):
			continue
		if counts.has(current_center):
			counts[current_center] = maxi(int(counts[current_center]) - 1, 0)
		counts[target_center] = int(counts[target_center]) + 1
		changed = true
	return changed


