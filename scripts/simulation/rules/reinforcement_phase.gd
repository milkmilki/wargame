class_name ReinforcementPhase
extends RefCounted
## Monthly reinforcement calculation. Simulation owns scheduling; this module
## owns the per-nation policy pipeline and deterministic budget allocation.


static func reinforce_nation(
	state: GameState,
	nation: Nation,
	nation_armies: Array[Army],
	food_cache: Dictionary,
	food_report_builder: Callable,
	food_budget_builder: Callable,
	network_cache_disabled: bool
) -> void:
	var at_war := not state.wars_of(nation.id).is_empty()
	var refill_candidates := _collect_refill_candidates(nation_armies, at_war)
	if refill_candidates.is_empty():
		return
	var food_report: Dictionary = food_report_builder.call(
		nation.id,
		nation_armies,
		food_cache
	)
	var food_manpower_budget := int(food_budget_builder.call(food_report))
	if food_manpower_budget <= 0:
		return
	var protected_reserve := (
		ReinforcementRules.PEACETIME_MANPOWER_RESERVE
		if not at_war
		else 0
	)
	var available_manpower := mini(
		maxi(nation.manpower_pool - protected_reserve, 0),
		food_manpower_budget
	)
	if available_manpower <= 0:
		return
	var manpower_hub_network := (
		{}
		if network_cache_disabled
		else Pathfinding.build_manpower_hub_network(state, nation.id)
	)
	var plan_result := _build_plans(
		state,
		nation.id,
		refill_candidates,
		at_war,
		network_cache_disabled,
		manpower_hub_network
	)
	var plans: Array = plan_result["plans"]
	if plans.is_empty():
		return
	_sort_plans(state, nation.id, plans)
	var forecast_limit := _forecast_refill_limit(state, nation.id, plans, mini(available_manpower, int(plan_result["total_deficit"])), int(plan_result["total_deficit"]), food_cache)
	available_manpower = mini(available_manpower, forecast_limit)
	_assign_grants(
		plans,
		mini(available_manpower, int(plan_result["total_deficit"])),
		int(plan_result["total_deficit"])
	)
	var spent := _apply_grants(plans)
	nation.manpower_pool -= spent
	if spent > 0:
		DiplomacyAI.commit_force_change(state, nation.id, spent, food_cache, plans)


static func _forecast_refill_limit(state: GameState, nation_id: int, plans: Array, desired: int, total_deficit: int, cache: Dictionary) -> int:
	var baseline := DiplomacyAI.resource_forecast(state, nation_id, -1, -1, cache)
	var current := int(baseline.input.troops)
	var low := 0
	var high := desired
	while low < high:
		var amount := (low + high + 1) / 2
		_assign_grants(plans, amount, total_deficit)
		var upkeep := 0
		var food := 0.0
		for plan in plans:
			var army: Army = plan.army
			var projected := army.size + int(plan.grant)
			upkeep += GameState.army_monthly_upkeep(projected) - GameState.army_monthly_upkeep(army.size)
			food += _grant_food_delta(army.size, projected, float(baseline.input.food_multiplier))
		var report := DiplomacyAI.resource_forecast(state, nation_id, current + amount, -1, cache, 0, {"base_upkeep_delta": upkeep, "field_food_delta": food})
		if bool(report.feasible):
			low = amount
		else:
			high = amount - 1
	return low


static func _grant_food_delta(old_size: int, new_size: int, multiplier: float) -> float:
	var before := ceilf(ceilf(old_size * Simulation.FOOD_PER_CAPITA) * Simulation.MAX_SUPPLY_MULT * multiplier)
	var after := ceilf(ceilf(new_size * Simulation.FOOD_PER_CAPITA) * Simulation.MAX_SUPPLY_MULT * multiplier)
	return maxf(after - before, 0)


static func _collect_refill_candidates(
	nation_armies: Array[Army],
	at_war: bool
) -> Array[Army]:
	var candidates: Array[Army] = []
	for army in nation_armies:
		if (
			army.size <= 0
			or army.size >= army.max_size
			or army.state in [Army.State.FIGHTING, Army.State.RETREATING]
			or army.state not in [
				Army.State.IDLE,
				Army.State.MOVING,
				Army.State.RECOVERING,
				Army.State.HOLDING,
			]
		):
			continue
		if army.size < _target_size(army, at_war):
			candidates.append(army)
	return candidates


static func _build_plans(
	state: GameState,
	nation_id: int,
	candidates: Array[Army],
	at_war: bool,
	network_cache_disabled: bool,
	manpower_hub_network: Dictionary
) -> Dictionary:
	var plans: Array = []
	var total_deficit := 0
	for army in candidates:
		if not ReinforcementRules.can_reinforce_army(
			state,
			army,
			network_cache_disabled,
			manpower_hub_network
		):
			continue
		var deficit := mini(
			maxi(_target_size(army, at_war) - army.size, 0),
			ReinforcementRules.monthly_reinforcement_cap(army)
		)
		if deficit <= 0:
			continue
		plans.append({
			"army": army,
			"deficit": deficit,
			"grant": 0,
			"priority": ReinforcementRules.reinforcement_priority(state, army),
		})
		total_deficit += deficit
	return {"plans": plans, "total_deficit": total_deficit}


static func _sort_plans(
	state: GameState,
	nation_id: int,
	plans: Array
) -> void:
	plans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var army_a: Army = a["army"]
		var army_b: Army = b["army"]
		var priority_a := int(a["priority"])
		var priority_b := int(b["priority"])
		if priority_a != priority_b:
			return priority_a > priority_b
		var fill_a := float(army_a.size) / float(maxi(army_a.max_size, 1))
		var fill_b := float(army_b.size) / float(maxi(army_b.max_size, 1))
		if not is_equal_approx(fill_a, fill_b):
			return fill_a < fill_b
		return EquivariantOrder.army_less(
			state,
			nation_id,
			army_a,
			army_b
		)
	)


static func _assign_grants(
	plans: Array,
	budget: int,
	total_deficit: int
) -> void:
	for plan in plans:
		plan.grant = 0
	if budget >= total_deficit:
		for plan in plans:
			plan["grant"] = plan["deficit"]
		return
	var remainder := budget
	var index := 0
	while index < plans.size() and remainder > 0:
		var priority := int(plans[index]["priority"])
		var end := index
		var tier_deficit := 0
		while end < plans.size() and int(plans[end]["priority"]) == priority:
			tier_deficit += int(plans[end]["deficit"])
			end += 1
		var tier_budget := mini(remainder, tier_deficit)
		var tier_granted := 0
		for plan_index in range(index, end):
			var share := int(floor(
				float(tier_budget)
					* float(plans[plan_index]["deficit"])
					/ float(maxi(tier_deficit, 1))
			))
			plans[plan_index]["grant"] = share
			tier_granted += share
		var tier_remainder := tier_budget - tier_granted
		for plan_index in range(index, end):
			if tier_remainder <= 0:
				break
			if (
				int(plans[plan_index]["grant"])
					>= int(plans[plan_index]["deficit"])
			):
				continue
			plans[plan_index]["grant"] = int(plans[plan_index]["grant"]) + 1
			tier_remainder -= 1
		remainder -= tier_budget
		index = end


static func _apply_grants(plans: Array) -> int:
	var spent := 0
	for plan in plans:
		var grant := int(plan["grant"])
		var army: Army = plan["army"]
		plan.old_size = army.size
		army.size += grant
		spent += grant
	return spent


static func _target_size(army: Army, at_war: bool) -> int:
	# A damaged formation eventually returns to its establishment in both war
	# and peace; the ten-percent monthly cap controls the pace.
	return army.max_size
