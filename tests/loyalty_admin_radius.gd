extends SceneTree
## 行政半径驱动的忠诚度距离衰减与远地分封压力专项。
##
## Godot --headless --path . --script res://tests/loyalty_admin_radius.gd

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== LOYALTY_ADMIN_RADIUS ===")
	_test_public_helpers_and_targets()
	_test_vassal_capital_loyalty_restores_after_enfeoff()
	_test_ai_enfeoff_governance_trigger()
	if _failures.is_empty():
		print("LOYALTY_ADMIN_RADIUS_OK checks=%d" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("LOYALTY_ADMIN_RADIUS_FAIL: " + failure)
	print(
		"LOYALTY_ADMIN_RADIUS_INVALID checks=%d failures=%d"
		% [_checks, _failures.size()]
	)
	quit(1)


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if condition:
		return
	var message := label
	if not detail.is_empty():
		message += " :: " + detail
	_failures.append(message)


func _make_linear_state(
	owner_count: int = 11,
	neutral_tail: int = 0
) -> GameState:
	var state := GameState.new()
	for nation_id in range(3):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.trade_policy = RulerProfile.POLICY_BALANCED
		nation.capital_city_id = 0 if nation_id == 0 else -1
		nation.treasury_gold = 1000
		nation.manpower_pool = 100000
		nation.military_payment_ratio = 1.0
		state.nations.append(nation)
	for city_id in range(owner_count + neutral_tail):
		var city := City.new()
		city.id = city_id
		city.name = "城%d" % city_id
		city.short_name = String.chr(0x4E00 + city_id)
		city.owner_nation = 0 if city_id < owner_count else 1
		city.map_position = Vector2(float(city_id) / 20.0, 0.5)
		city.coord = Vector2i(city_id, 0)
		city.loyalty = 75.0
		city.loyalty_target_nation = city.owner_nation
		city.gold_per_month = 10
		city.manpower_per_month = 10
		city.food_per_half_year = 600
		city.is_capital = city_id == 0
		city.has_warehouse = city_id == 0
		if city.owner_nation == 1 and state.nations[1].capital_city_id < 0:
			state.nations[1].capital_city_id = city_id
			city.is_capital = true
			city.has_warehouse = true
		state.cities.append(city)
		state.adjacency[city_id] = [] as Array[int]
	for city_id in range(state.cities.size() - 1):
		var edge := Edge.new()
		edge.city_a = city_id
		edge.city_b = city_id + 1
		edge.max_manpower = Edge.STANDARD_MANPOWER
		edge.distance = 1
		state.edge_lookup[state.edge_key(edge.city_a, edge.city_b)] = edge
		(state.adjacency[edge.city_a] as Array[int]).append(edge.city_b)
		(state.adjacency[edge.city_b] as Array[int]).append(edge.city_a)
	for city_id in state.adjacency.keys():
		(state.adjacency[city_id] as Array[int]).sort()
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	return state


func _configure_ruler(
	nation: Nation,
	archetype: int,
	traits: Array[String] = []
) -> void:
	nation.ruler_archetype = archetype
	nation.ruler_traits = traits.duplicate()


func _find_action(actions: Array[Dictionary], kind: int, nation_id: int) -> Dictionary:
	for action_value in actions:
		var action: Dictionary = action_value
		if (
			int(action.get("kind", -1)) == kind
			and int(action.get("a", -1)) == nation_id
		):
			return action
	return {}


func _test_public_helpers_and_targets() -> void:
	var state := _make_linear_state(11, 0)
	var hops := RebellionSystem.capital_hops(state, 0)
	var inept := state.nations[0]
	_configure_ruler(inept, RulerProfile.INEPT)
	var balanced := Nation.new()
	balanced.ruler_archetype = RulerProfile.BALANCED
	var centralizer := Nation.new()
	centralizer.ruler_archetype = RulerProfile.REFORMER
	centralizer.ruler_traits = [RulerProfile.TRAIT_CENTRALIZER]

	var inept_radius := RebellionSystem.administrative_radius(inept)
	var balanced_radius := RebellionSystem.administrative_radius(balanced)
	var centralizer_radius := RebellionSystem.administrative_radius(centralizer)
	var inept_soft := RebellionSystem.administrative_soft_stability_hops(inept)
	var balanced_soft := RebellionSystem.administrative_soft_stability_hops(balanced)
	var centralizer_soft := RebellionSystem.administrative_soft_stability_hops(centralizer)
	_check(
		absf(inept_radius - 4.54) <= 0.01
			and absf(balanced_radius - 6.1) <= 0.01
			and absf(centralizer_radius - 7.80) <= 0.01,
		"helper/radius_values_locked",
		"inept=%.2f balanced=%.2f strong=%.2f"
			% [inept_radius, balanced_radius, centralizer_radius]
	)
	_check(
		inept_soft >= 4.0 and inept_soft < 5.0,
		"helper/inept_soft_hops_near_4",
		"radius=%.2f soft=%.2f" % [inept_radius, inept_soft]
	)
	_check(
		balanced_soft >= 7.0 and balanced_soft < 8.0,
		"helper/balanced_soft_hops_near_7",
		"radius=%.2f soft=%.2f" % [balanced_radius, balanced_soft]
	)
	_check(
		centralizer_soft >= 7.0 and centralizer_radius > balanced_radius,
		"helper/centralizer_radius_exceeds_balanced",
		"balanced=%.2f/%.2f strong=%.2f/%.2f"
			% [balanced_radius, balanced_soft, centralizer_radius, centralizer_soft]
	)

	var inept_hop4 := RebellionSystem.loyalty_target(state, 4, hops)
	var inept_hop5 := RebellionSystem.loyalty_target(state, 5, hops)
	_check(
		float(inept_hop4["value"]) >= RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD
			and float(inept_hop5["value"]) < RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD,
		"target/inept_4_stable_5_unstable",
		"hop4=%.1f hop5=%.1f" % [inept_hop4["value"], inept_hop5["value"]]
	)

	_configure_ruler(state.nations[0], RulerProfile.BALANCED)
	var balanced_hop7 := RebellionSystem.loyalty_target(state, 7, hops)
	var balanced_hop8 := RebellionSystem.loyalty_target(state, 8, hops)
	_check(
		float(balanced_hop7["value"]) >= RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD
			and float(balanced_hop8["value"]) < RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD,
		"target/balanced_7_stable_8_unstable",
		"hop7=%.1f hop8=%.1f" % [balanced_hop7["value"], balanced_hop8["value"]]
	)

	_configure_ruler(
		state.nations[0],
		RulerProfile.REFORMER,
		[RulerProfile.TRAIT_CENTRALIZER]
	)
	var strong_hop7 := RebellionSystem.loyalty_target(state, 7, hops)
	_check(
		float(strong_hop7["value"]) >= RebellionSystem.LOYALTY_SOFT_STABILITY_THRESHOLD
			and float(strong_hop7["administrative_radius"]) > float(balanced_hop7["administrative_radius"]),
		"target/strong_centralizer_still_stable_at_7",
		"strong7=%.1f balanced_radius=%.2f strong_radius=%.2f"
			% [
				strong_hop7["value"],
				balanced_hop7["administrative_radius"],
				strong_hop7["administrative_radius"],
			]
	)
	_check(
		absf(
			float(strong_hop7["administrative_radius"])
				- float(balanced_hop7["administrative_radius"])
				- 1.70
		) <= 0.01,
		"helper/centralizer_trait_marginal_radius",
		"balanced=%.2f strong=%.2f"
			% [
				balanced_hop7["administrative_radius"],
				strong_hop7["administrative_radius"],
			]
	)


func _test_vassal_capital_loyalty_restores_after_enfeoff() -> void:
	var state := _make_linear_state(11, 0)
	_configure_ruler(state.nations[0], RulerProfile.INEPT)
	var before := RebellionSystem.loyalty_target(state, 8)
	var region: Array[int] = [8, 9, 10]
	var subject_id := state.enfeoff(0, region)
	var subject_capital := state.nations[subject_id].capital_city_id if subject_id >= 0 else -1
	var after := (
		RebellionSystem.loyalty_target(state, subject_capital)
		if subject_capital >= 0
		else {}
	)
	_check(
		subject_id >= 0
			and subject_capital >= 0
			and float(after.get("value", 0.0)) >= 75.0
			and float(after.get("value", 0.0)) - float(before["value"]) >= 20.0,
		"enfeoff/local_capital_loyalty_restores",
		"subject=%d capital=%d before=%.1f after=%.1f"
			% [subject_id, subject_capital, before["value"], after.get("value", -1.0)]
	)


func _test_ai_enfeoff_governance_trigger() -> void:
	var state := _make_linear_state(14, 2)
	_configure_ruler(state.nations[0], RulerProfile.INEPT)
	var region: Array[int] = [11, 12, 13]
	for city_id in region:
		state.cities[city_id].gold_per_month = 1
		state.cities[city_id].food_per_half_year = 60000
	var retained_city := 0
	for army in state.armies:
		army.location_city = retained_city
		army.move_from = retained_city
		army.move_to = -1
		army.on_edge = false
		army.state = Army.State.IDLE
	var governance := DiplomacyAI.evaluate_region_governance_pressure(
		state,
		0,
		region,
		RebellionSystem.capital_hops(state, 0)
	)
	var grown_region := DiplomacyAI._grow_enfeoff_region(state, 0, {})
	var burden := DiplomacyAI.evaluate_region_burden(state, 0, grown_region)
	var actions: Array[Dictionary] = []
	var evaluation_cache := {}
	DiplomacyAI.reset_encirclement_cache_counters()
	DiplomacyAI._collect_enfeoff_actions(state, actions, {}, evaluation_cache)
	var enfeoff := _find_action(actions, DiplomacyAI.Action.ENFEOFF, 0)
	var cache_counters := DiplomacyAI.encirclement_cache_counters()
	_check(
		int(governance["pressured_city_count"]) >= 2
			and grown_region.size() >= DiplomacyAI.ENFEOFF_MIN_REGION_CITIES
			and float(governance["pressure_score"])
				>= DiplomacyAI.ENFEOFF_GOVERNANCE_PRESSURE_THRESHOLD
			and int(burden["monthly_fiscal_benefit"]) <= 0
			and float(burden["burden_ratio"])
				< DiplomacyAI.ENFEOFF_BURDEN_RATIO_THRESHOLD
			and not enfeoff.is_empty()
			and (enfeoff.get("region_cities", []) as Array).has(13)
			and str(enfeoff.get("reason", "")).contains("治理压力"),
		"ai/governance_pressure_triggers_enfeoff",
		"grown=%s burden=%s pressure=%s reason=%s region=%s" % [
			str(grown_region),
			str(burden),
			str(governance),
			str(enfeoff.get("reason", "")),
			str(enfeoff.get("region_cities", [])),
		]
	)
	_check(
		evaluation_cache.has("capital_hops:0")
			and (evaluation_cache["capital_hops:0"] as Dictionary)
				== RebellionSystem.capital_hops(state, 0)
			and int(cache_counters.get("capital_hops_builds", -1)) >= 1
			and int(cache_counters.get("capital_hops_builds", -1)) <= state.nations.size(),
		"ai/capital_hops_cached_once_per_enfeoff_evaluation",
		"keys=%s counters=%s" % [
			str(evaluation_cache.keys()),
			str(cache_counters),
		]
	)

	var enclave_state := _make_linear_state(8, 0)
	_configure_ruler(enclave_state.nations[0], RulerProfile.BALANCED)
	enclave_state.cities[7].owner_nation = 0
	enclave_state.recognized_city_owners[7] = 0
	var left_edge := enclave_state.edge_of(6, 7)
	if left_edge != null:
		left_edge.max_manpower = 0
	var enclave_pressure := DiplomacyAI.evaluate_region_governance_pressure(
		enclave_state,
		0,
		[7],
		RebellionSystem.capital_hops(enclave_state, 0)
	)
	_check(
		int(enclave_pressure["pressured_city_count"]) == 1
			and float(enclave_pressure["pressure_score"])
				>= RebellionSystem.UNREACHABLE_DISTANCE_EXCESS_FLOOR,
		"ai/unreachable_enclave_counts_as_pressure",
		str(enclave_pressure)
	)

	var shallow_state := _make_linear_state(14, 2)
	_configure_ruler(shallow_state.nations[0], RulerProfile.BALANCED)
	for city_id in range(7, 13):
		shallow_state.cities[city_id].owner_nation = 1
		shallow_state.recognized_city_owners[city_id] = 1
	shallow_state.nations[1].capital_city_id = 7
	shallow_state.cities[7].is_capital = true
	shallow_state.cities[7].has_warehouse = true
	shallow_state.cities[13].gold_per_month = 1
	shallow_state.cities[13].food_per_half_year = 60000
	var shallow_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(shallow_state, shallow_actions, {}, {})
	var shallow_enfeoff := _find_action(
		shallow_actions,
		DiplomacyAI.Action.ENFEOFF,
		0
	)
	var shallow_pressure := DiplomacyAI.evaluate_region_governance_pressure(
		shallow_state,
		0,
		[13],
		RebellionSystem.capital_hops(shallow_state, 0)
	)
	_check(
		int(shallow_pressure["pressured_city_count"]) == 1
			and float(shallow_pressure["pressure_score"]) > 0.0
			and shallow_enfeoff.is_empty(),
		"ai/single_shallow_overflow_not_enough",
		"pressure=%s action=%s" % [str(shallow_pressure), str(shallow_enfeoff)]
	)
