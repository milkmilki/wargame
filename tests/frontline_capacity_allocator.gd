extends SceneTree
## Deterministic frontline capacity regression:
## 1) all eligible LINE armies receive slots when valid defensive targets exist;
## 2) canonical tier1/tier2 keep sector ownership, while tier3 duplicates do not;
## 3) ownership changes recompute through CityDefensePlan.build() and preserve
##    the existing small-nation fallback path.

const LIGHT_SIZE := GameState.INITIAL_LIGHT_ARMY_SIZE


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_verify_capacity_and_tier_order()
	_verify_ownership_change_recompute()
	_verify_unreachable_frontier_surplus_fill()
	print("verdict=FRONTLINE_CAPACITY_ALLOCATOR_OK")
	quit()


func _verify_capacity_and_tier_order() -> void:
	var state := _make_frontline_pocket_state()
	_add_line_armies(state, 15, 25)
	var plan := _build_plan(state)
	var slots := plan._build_role_defense_slots(15)
	_assert(
		slots.size() >= 15,
		"expected at least 15 slots for 15 LINE armies, got=%d"
		% slots.size()
	)
	var expected_city_order := [25, 17, 9, 18, 10]
	for slot_index in range(expected_city_order.size()):
		var slot: Dictionary = slots[slot_index]
		_assert(
			int(slot["city_id"]) == expected_city_order[slot_index]
				and int(slot["posture"]) == CityDefensePlan.Posture.CITY
				and int(slot["priority"]) == 0
				and int(slot.get("sector_city", -1))
					== expected_city_order[slot_index]
				and int(slot.get("sector_slot", -1)) == 0,
			"tier1 city order mismatch at index=%d slot=%s"
			% [slot_index, str(slot)]
		)
	for slot_index in range(5, 10):
		var slot: Dictionary = slots[slot_index]
		_assert(
			int(slot["posture"]) == CityDefensePlan.Posture.EDGE
				and int(slot["priority"]) == 1
				and slot.has("sector_city")
				and slot.has("sector_slot")
				and int(slot["sector_slot"]) == 1,
			"tier2 first edge layer must remain canonical, slot=%s"
			% str(slot)
		)
	var second_layer_start := -1
	for idx in range(slots.size()):
		var s: Dictionary = slots[idx]
		if (
			int(s["posture"]) == CityDefensePlan.Posture.EDGE
				and int(s["priority"]) == 2
		):
			second_layer_start = idx
			break
	_assert(
		second_layer_start >= 0,
		"expected second edge layer in slots, slots=%s"
		% str(slots)
	)
	var tier3_start := -1
	for idx in range(slots.size()):
		var s: Dictionary = slots[idx]
		if (
			int(s["posture"]) == CityDefensePlan.Posture.CITY
				and int(s.get("priority", 0)) >= 3
		):
			tier3_start = idx
			break
	if tier3_start >= 0:
		var tier3_expected := [25, 9]
		for local_index in range(tier3_expected.size()):
			var slot: Dictionary = slots[tier3_start + local_index]
			_assert(
				int(slot["city_id"]) == tier3_expected[local_index]
					and int(slot["posture"]) == CityDefensePlan.Posture.CITY
					and int(slot["priority"]) == 3
					and not slot.has("sector_city")
					and not slot.has("sector_slot"),
				"tier3 duplicate slots must be city posture without sector ownership, slot=%s"
				% str(slot)
			)
	plan._assign_role_based_defense()
	_assert(
		plan.defense_assignment_slots == 15
			and plan.assigned_city_by_army.size() == 15,
		"assignment should keep all 15 eligible LINE armies active"
	)


func _verify_ownership_change_recompute() -> void:
	var state := _make_frontline_pocket_state()
	_add_line_armies(state, 8, 25)
	var before_plan := _build_plan(state)
	var before_slots := before_plan._build_role_defense_slots(8)
	_assert(
		before_slots.size() >= 8,
		"pre-capture build should have at least 8 slots, slots=%s"
		% str(before_slots)
	)
	state.cities[10].owner_nation = 1
	state.ownership_revision += 1
	var after_plan := _build_plan(state, before_plan)
	var after_slots := after_plan._build_role_defense_slots(4)
	_assert(
		after_plan._small_nation_survival_mode()
			and after_slots.size() >= 4,
		"post-capture build should recompute into small-nation path with >=4 slots, slots=%s"
		% str(after_slots)
	)
	var expected_small_nation_order := [25, 17, 9, 18]
	for slot_index in range(mini(after_slots.size(), expected_small_nation_order.size())):
		var slot: Dictionary = after_slots[slot_index]
		_assert(
			int(slot["city_id"]) == expected_small_nation_order[slot_index]
				and int(slot["posture"]) == CityDefensePlan.Posture.CITY
				and int(slot["priority"]) == 0,
			"ownership-change recompute should rebuild deterministic small-nation slots, slot=%s"
			% str(slot)
		)


func _verify_unreachable_frontier_surplus_fill() -> void:
	var state := _make_frontline_pocket_state()
	_add_line_armies(state, 15, 25)
	var plan := _build_plan(state)
	plan._assign_role_based_defense()
	_assert(
		plan.defense_assignment_slots >= 13
			and plan.assigned_city_by_army.size() == 15,
		"all 15 LINE armies must be assigned even when 5 frontier cities + edge layers yield only 15 canonical slots; assigned=%d slots=%d"
			% [plan.assigned_city_by_army.size(), plan.defense_assignment_slots]
	)
	var has_city_slot := false
	for army_id in plan.assigned_city_by_army.keys():
		var slot_city := int(plan.assigned_city_by_army[army_id])
		if plan.required_power.has(slot_city):
			has_city_slot = true
			break
	_assert(
		has_city_slot,
		"at least one surplus army should land on a required_power city"
	)


func _make_frontline_pocket_state() -> GameState:
	var state := GameState.new()
	state.generate_grid_world(7005)
	state.uses_heightmap = true
	state.armies.clear()
	for city in state.cities:
		city.owner_nation = 1
		city.is_capital = false
		city.has_warehouse = false
		city.is_food_hub = false
		city.is_manpower_hub = false
		city.is_dock = false
		city.fort_strength_max = 0
	for city_id in [9, 10, 17, 18, 25]:
		state.cities[city_id].owner_nation = 0
	state.cities[25].fort_strength_max = 30
	state.nations[0].capital_city_id = 25
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	return state


func _add_line_armies(
	state: GameState,
	count: int,
	city_id: int
) -> void:
	for _index in range(count):
		var army := state.create_army(
			0,
			city_id,
			LIGHT_SIZE,
			LIGHT_SIZE
		)
		if army == null:
			push_error(
				"failed to create LINE army at city=%d (capacity limit)"
				% city_id
			)
			return
		army.location_city = city_id
		army.move_from = city_id


func _build_plan(
	state: GameState,
	previous_plan: CityDefensePlan = null
) -> CityDefensePlan:
	var view := AiWorldView.build(state, 0)
	var snapshot := StrategicMapSnapshot.build(view)
	var threat := ThreatField.build(view)
	var plan := CityDefensePlan.prepare_evaluation(
		view,
		snapshot,
		threat
	)
	plan.evaluate_readonly(previous_plan)
	plan.commit_assignments()
	return plan


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
