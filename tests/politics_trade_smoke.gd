extends SceneTree
## 政治、命名与贸易系统的集中 headless smoke。
##
## 独立运行：
## Godot --headless --path . --script res://tests/politics_trade_smoke.gd

const SEED: int = 24680

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== POLITICS_TRADE_SMOKE ===")
	_test_world_naming()
	_test_ruler_profiles()
	_test_trade_network()
	_test_rebellion_system()
	_test_monthly_publication()
	if _failures.is_empty():
		print("POLITICS_TRADE_SMOKE_OK checks=", _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("POLITICS_TRADE_SMOKE_FAIL: " + failure)
	print(
		"POLITICS_TRADE_SMOKE_INVALID checks=", _checks,
		" failures=", _failures.size()
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


func _approx(actual: float, expected: float, tolerance: float = 0.0001) -> bool:
	return absf(actual - expected) <= tolerance


func _test_world_naming() -> void:
	var first := _make_naming_state()
	var second := _make_naming_state()
	var first_rng_state := first.rng.state
	var second_rng_state := second.rng.state
	WorldNaming.assign_initial_names(first, SEED)
	WorldNaming.assign_initial_names(second, SEED)
	_check(
		first.rng.state == first_rng_state and second.rng.state == second_rng_state,
		"naming/rng_isolated",
		"before=%d/%d after=%d/%d" % [
			first_rng_state, second_rng_state, first.rng.state, second.rng.state,
		]
	)
	_check(
		_naming_fingerprint(first) == _naming_fingerprint(second),
		"naming/same_seed_deterministic"
	)
	var revision := first.naming_revision
	var fingerprint := _naming_fingerprint(first)
	WorldNaming.assign_initial_names(first, SEED)
	_check(
		first.naming_revision == revision
			and _naming_fingerprint(first) == fingerprint,
		"naming/idempotent",
		"revision %d -> %d" % [revision, first.naming_revision]
	)

	var city_names := {}
	var city_shorts := {}
	var city_contract := true
	for city in first.cities:
		var clean_name := city.name.strip_edges()
		var clean_short := city.short_name.strip_edges()
		city_contract = city_contract and (
			not clean_name.is_empty()
			and not city_names.has(clean_name)
			and clean_short.length() == 1
			and not city_shorts.has(clean_short)
		)
		city_names[clean_name] = true
		city_shorts[clean_short] = true
	_check(
		city_contract,
		"naming/unique_full_city_names_and_unique_single_shorts",
		"cities=%d unique=%d shorts=%d" % [
			first.cities.size(), city_names.size(), city_shorts.size()
		]
	)

	var sovereign_contract := true
	for nation in first.nations:
		var founding_id := nation.founding_city_id
		sovereign_contract = sovereign_contract and (
			founding_id >= 0
			and founding_id < first.cities.size()
			and nation.name.length() == 1
			and nation.short_name == nation.name
			and nation.name == first.cities[founding_id].short_name
		)
	_check(
		sovereign_contract,
		"naming/sovereign_symbol_from_exact_founding_city",
		_naming_fingerprint(first)
	)
	var founding_before := first.nations[0].founding_city_id
	first.nations[0].capital_city_id = 3
	WorldNaming.assign_initial_names(first, SEED)
	_check(
		first.nations[0].founding_city_id == founding_before
			and first.nations[0].name == first.cities[founding_before].short_name,
		"naming/founding_city_survives_capital_relocation"
	)
	var definition := MapDefinition.from_state(first)
	var definition_uses_two_city_names := true
	for city_value in definition["cities"]:
		var city_record := city_value as Dictionary
		definition_uses_two_city_names = (
			definition_uses_two_city_names
			and city_record.has("name")
			and city_record.has("short_name")
			and not city_record.has("region_symbol")
		)
	_check(
		definition_uses_two_city_names,
		"naming/map_definition_contains_only_full_and_short_city_names"
	)
	var restored := _make_naming_state()
	WorldNaming.assign_from_definition(restored, definition, SEED)
	var persisted := true
	for nation in restored.nations:
		persisted = persisted and nation.founding_city_id == int(
			(definition["nations"] as Array)[nation.id]["founding_city_id"]
		)
	_check(persisted, "naming/founding_city_roundtrip")
	var missing_founding := definition.duplicate(true)
	(missing_founding["nations"] as Array)[0].erase("founding_city_id")
	_check(
		not MapDefinition.validate(missing_founding).is_empty(),
		"naming/v3_requires_founding_city"
	)

	var sovereign_collision := _make_naming_state()
	sovereign_collision.cities[1].short_name = (
		sovereign_collision.cities[0].short_name
	)
	WorldNaming.assign_initial_names(sovereign_collision, SEED)
	_check(
		sovereign_collision.nations[0].name
			== sovereign_collision.cities[0].short_name
			and sovereign_collision.nations[1].name
				== sovereign_collision.cities[1].short_name
			and sovereign_collision.nations[0].name
				!= sovereign_collision.nations[1].name,
		"naming/duplicate_city_short_is_repaired_before_sovereign_naming"
	)
	_test_preferred_city_short_collision()

	var vassal := _make_vassal_naming_state(4)
	WorldNaming.assign_initial_names(vassal, SEED)
	vassal.nations[1].name_kind = WorldNaming.KIND_VASSAL
	_add_historical_name_collision(vassal, "河间王")
	_add_historical_name_collision(vassal, "冀王")
	WorldNaming.assign_vassal_name(vassal, 1, [1, 2, 3, 4])
	var small_display := WorldNaming.nation_display_name(vassal, 1)
	_check(
		small_display == "河间王",
		"naming/vassal_under_five_exact_capital_despite_collision",
		small_display
	)
	var fifth := City.new()
	fifth.id = vassal.cities.size()
	fifth.owner_nation = 1
	fifth.name = "襄阳"
	fifth.short_name = "荆"
	fifth.map_position = Vector2(0.85, 0.75)
	vassal.cities.append(fifth)
	var large_display := WorldNaming.nation_display_name(vassal, 1)
	_check(
		large_display == "冀王",
		"naming/vassal_five_exact_capital_symbol_despite_collision",
		large_display
	)
	fifth.owner_nation = 0
	var reduced_display := WorldNaming.nation_display_name(vassal, 1)
	_check(
		reduced_display == "冀王",
		"naming/vassal_single_char_ratchet_never_reverts_after_losing_city",
		reduced_display
	)
	_test_naming_sovereign_promotions()


func _make_naming_state() -> GameState:
	var state := GameState.new()
	state.world_seed = SEED
	state.rng.seed = 998877
	for nation_id in range(3):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.capital_city_id = nation_id
		state.nations.append(nation)
	var names: Array[String] = ["幽州", "冀州", "荆州", "长安", "成都", "建业"]
	var shorts: Array[String] = ["燕", "赵", "楚", "秦", "蜀", "吴"]
	var owners: Array[int] = [0, 1, 2, 0, 1, 2]
	for city_id in range(names.size()):
		var city := City.new()
		city.id = city_id
		city.name = names[city_id]
		city.short_name = shorts[city_id]
		city.owner_nation = owners[city_id]
		city.map_position = Vector2(0.1 + 0.15 * city_id, 0.4)
		state.cities.append(city)
		state.adjacency[city_id] = [] as Array[int]
	return state


func _make_vassal_naming_state(vassal_city_count: int) -> GameState:
	var state := GameState.new()
	state.world_seed = SEED
	for nation_id in range(2):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		state.nations.append(nation)
	var names: Array[String] = ["幽州", "河间", "常山", "中山", "巨鹿"]
	var shorts: Array[String] = ["燕", "冀", "赵", "赵", "赵"]
	for city_id in range(1 + vassal_city_count):
		var city := City.new()
		city.id = city_id
		city.owner_nation = 0 if city_id == 0 else 1
		city.name = names[city_id]
		city.short_name = shorts[city_id]
		city.map_position = Vector2(0.15 * city_id, 0.5)
		state.cities.append(city)
		state.adjacency[city_id] = [] as Array[int]
	state.nations[0].capital_city_id = 0
	state.nations[1].capital_city_id = 1
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation
	return state


func _test_preferred_city_short_collision() -> void:
	var state := GameState.new()
	var names: Array[String] = ["雍州", "咸阳", "长安"]
	for city_id in range(names.size()):
		var city := City.new()
		city.id = city_id
		city.name = names[city_id]
		state.cities.append(city)
		state.adjacency[city_id] = [] as Array[int]
	WorldNaming.assign_initial_names(state, SEED)
	var allocated := {}
	var resolved_shorts: Array[String] = []
	for city in state.cities:
		allocated[city.short_name] = true
		resolved_shorts.append(city.short_name)
	_check(
		resolved_shorts == ["秦", "咸", "长"]
			and allocated.size() == names.size(),
		"naming/preferred_short_collision_is_deterministically_unique",
		"shorts=%s" % str(resolved_shorts)
	)


func _add_historical_name_collision(state: GameState, name: String) -> void:
	var historical := Nation.new()
	historical.id = state.nations.size()
	historical.alive = false
	historical.name = name
	historical.short_name = name
	historical.name_kind = WorldNaming.KIND_VASSAL
	state.nations.append(historical)


func _test_naming_sovereign_promotions() -> void:
	var succession := _make_vassal_naming_state(4)
	WorldNaming.assign_initial_names(succession, SEED)
	succession.nations[1].name_kind = WorldNaming.KIND_VASSAL
	WorldNaming.assign_vassal_name(succession, 1, [1, 2, 3, 4])
	var succession_founding := succession.nations[1].founding_city_id
	var succession_symbol := succession.cities[succession_founding].short_name
	succession.nations[0].name = succession_symbol
	succession.nations[0].short_name = succession_symbol
	succession.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	succession.suzerainty[1] = {
		"overlord_id": 0, "tribute_rate": 0.25, "created_day": 0,
		"last_centralization_day": -1, "civil_war": false,
	}
	succession.nations[0].alive = false
	var succession_pruned := succession.prune_dead_suzerainty()
	_check(
		succession_pruned
			and not succession.is_vassal(1)
			and succession.nations[1].founding_city_id == succession_founding
			and succession.nations[1].name == succession_symbol
			and succession.nations[1].short_name == succession_symbol
			and succession.nations[1].name_kind != WorldNaming.KIND_VASSAL,
		"naming/dead_overlord_uses_unified_sovereign_promotion"
	)

	var civil := _make_vassal_naming_state(4)
	WorldNaming.assign_initial_names(civil, SEED)
	civil.nations[1].name_kind = WorldNaming.KIND_VASSAL
	WorldNaming.assign_vassal_name(civil, 1, [1, 2, 3, 4])
	var civil_founding := civil.nations[1].founding_city_id
	var civil_symbol := civil.cities[civil_founding].short_name
	civil.nations[0].name = civil_symbol
	civil.nations[0].short_name = civil_symbol
	civil.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	civil.suzerainty[1] = {
		"overlord_id": 0, "tribute_rate": 0.25, "created_day": 0,
		"last_centralization_day": 0, "civil_war": true,
	}
	var sim := Simulation.new()
	sim.setup(civil)
	var civil_resolved := sim._resolve_civil_war_capital_capture(0, 1)
	_check(
		civil_resolved
			and not civil.nations[0].alive
			and not civil.is_vassal(1)
			and civil.nations[1].founding_city_id == civil_founding
			and civil.nations[1].name == civil_symbol
			and civil.nations[1].short_name == civil_symbol
			and civil.nations[1].name_kind != WorldNaming.KIND_VASSAL,
		"naming/civil_war_takeover_uses_unified_sovereign_promotion"
	)
	sim.free()


func _naming_fingerprint(state: GameState) -> String:
	var fields: Array[String] = []
	for city in state.cities:
		fields.append("C%d:%s:%s" % [
			city.id, city.name, city.short_name
		])
	for nation in state.nations:
		fields.append("N%d:%s:%s:%s:%s:%d" % [
			nation.id, nation.name, nation.short_name,
			nation.name_kind, nation.ruler_name, nation.founding_city_id,
		])
	return "|".join(fields)


func _test_ruler_profiles() -> void:
	var archetypes := RulerProfile.all_archetypes()
	var traits := RulerProfile.all_traits()
	var valid_catalog := archetypes.size() == 9 and traits.size() == 12
	for archetype in archetypes:
		valid_catalog = valid_catalog and (
			RulerProfile.is_valid_archetype(archetype)
			and not RulerProfile.archetype_name(archetype).is_empty()
			and not RulerProfile.archetype_description(archetype).is_empty()
		)
	for trait_id in traits:
		valid_catalog = valid_catalog and (
			RulerProfile.is_valid_trait(trait_id)
			and not RulerProfile.trait_name(trait_id).is_empty()
			and not RulerProfile.trait_description(trait_id).is_empty()
		)
	_check(valid_catalog, "ruler/catalog_9_archetypes_12_traits")

	var deterministic := true
	for nation_id in range(128):
		var first_traits := RulerProfile.traits_for(SEED, nation_id, 7)
		var second_traits := RulerProfile.traits_for(SEED, nation_id, 7)
		deterministic = deterministic and (
			RulerProfile.archetype_for(SEED, nation_id, 7)
				== RulerProfile.archetype_for(SEED, nation_id, 7)
			and first_traits == second_traits
			and RulerProfile.ruler_name_for(SEED, nation_id, 7)
				== RulerProfile.ruler_name_for(SEED, nation_id, 7)
			and first_traits.size() <= RulerProfile.MAX_TRAITS
			and not (
				first_traits.has(RulerProfile.TRAIT_CENTRALIZER)
				and first_traits.has(RulerProfile.TRAIT_FEUDALIST)
			)
		)
	_check(deterministic, "ruler/deterministic_stable_traits")

	var conqueror := RulerProfile.modifiers(RulerProfile.CONQUEROR)
	var guardian := RulerProfile.modifiers(RulerProfile.GUARDIAN)
	var inept := RulerProfile.modifiers(RulerProfile.INEPT)
	var tyrant := RulerProfile.modifiers(RulerProfile.TYRANT)
	_check(
		_approx(float(conqueror[RulerProfile.KEY_AGGRESSION]), 1.35)
			and _approx(float(conqueror[RulerProfile.KEY_MANPOWER_OUTPUT]), 1.12)
			and _approx(float(conqueror[RulerProfile.KEY_UPKEEP]), 1.08)
			and bool(conqueror[RulerProfile.KEY_OFFENSIVE_ALLOWED]),
		"ruler/conqueror_key_multipliers"
	)
	_check(
		_approx(float(guardian[RulerProfile.KEY_DEFENSE]), 1.18)
			and _approx(float(guardian[RulerProfile.KEY_CITY_DEFENSE]), 1.25)
			and int(guardian[RulerProfile.KEY_RESERVE_MONTHS]) == 3
			and not bool(guardian[RulerProfile.KEY_OFFENSIVE_ALLOWED]),
		"ruler/guardian_key_multipliers_and_gate"
	)
	_check(
		_approx(float(inept[RulerProfile.KEY_GOLD_OUTPUT]), 0.82)
			and _approx(float(inept[RulerProfile.KEY_UPKEEP]), 1.20)
			and _approx(float(inept[RulerProfile.KEY_LOYALTY]), 0.80)
			and not bool(inept[RulerProfile.KEY_OFFENSIVE_ALLOWED]),
		"ruler/inept_key_multipliers_and_gate"
	)
	_check(
		_approx(float(tyrant[RulerProfile.KEY_GOLD_OUTPUT]), 1.12)
			and _approx(float(tyrant[RulerProfile.KEY_MANPOWER_OUTPUT]), 1.12)
			and _approx(float(tyrant[RulerProfile.KEY_CENTRALIZE]), 1.42)
			and _approx(float(tyrant[RulerProfile.KEY_LOYALTY]), 0.76)
			and bool(tyrant[RulerProfile.KEY_OFFENSIVE_ALLOWED]),
		"ruler/tyrant_key_multipliers_and_gate"
	)
	_check(
		not RulerProfile.offensive_allowed(RulerProfile.DIPLOMAT),
		"ruler/diplomat_offensive_gate"
	)


func _test_trade_network() -> void:
	var limit_state := _make_trade_limit_state()
	var before := _trade_state_fingerprint(limit_state)
	var first := TradeNetwork.build(limit_state)
	var second := TradeNetwork.build(limit_state)
	_check(
		first == second and before == _trade_state_fingerprint(limit_state),
		"trade/build_deterministic_and_pure",
		"signature=%s" % str(first.get("signature", -1))
	)
	var required_fields: Array[String] = [
		"id", "international", "kind", "nation_a", "nation_b",
		"source", "destination", "source_city", "destination_city",
		"city_path", "preferred_city_path", "edge_keys", "bottleneck",
		"bottleneck_capacity", "transport_cost", "status", "gold_tax",
		"gold_to_a", "gold_to_b", "transit_gold", "city_gold_bonus",
		"food_transfer", "food_exporter", "food_importer", "food_cost_gold",
	]
	var route_contract := true
	var international_counts: Array[int] = []
	international_counts.resize(limit_state.nations.size())
	international_counts.fill(0)
	var routes: Array = first["routes"]
	for index in range(routes.size()):
		var route: Dictionary = routes[index]
		for key in required_fields:
			route_contract = route_contract and route.has(key)
		route_contract = route_contract and (
			int(route.get("id", -1)) == index
			and int(route.get("source", -1)) == int(route.get("source_city", -2))
			and int(route.get("destination", -1))
				== int(route.get("destination_city", -2))
			and int(route.get("bottleneck", -1))
				== int(route.get("bottleneck_capacity", -2))
			and int(route.get("gold", -1)) == int(route.get("gold_tax", -2))
			and int(route.get("food", -1)) == int(route.get("food_transfer", -2))
			and int(route.get("food_cost", -1))
				== int(route.get("food_cost_gold", -2))
		)
		if bool(route.get("international", false)):
			international_counts[int(route["nation_a"])] += 1
			international_counts[int(route["nation_b"])] += 1
	for count in international_counts:
		route_contract = route_contract and (
			count <= TradeNetwork.MAX_INTERNATIONAL_ROUTES_PER_NATION
		)
	_check(
		route_contract,
		"trade/route_schema_and_per_nation_limit",
		"counts=%s" % str(international_counts)
	)

	var pair_state := _make_trade_pair_state()
	var neutral := TradeNetwork.build(pair_state)
	var neutral_route := _international_route(neutral, 0, 1)
	_check(
		not neutral_route.is_empty()
			and int(neutral_route["status"]) == TradeNetwork.ACTIVE
			and int(neutral_route["gold_tax"]) > 0,
		"trade/neutral_nations_trade",
		str(neutral_route)
	)
	_check(
		(neutral_route.get("preferred_city_path", []) as Array).size() - 1
			>= TradeNetwork.MIN_INTERNATIONAL_ROUTE_HOPS,
		"trade/international_endpoints_respect_minimum_hops",
		str(neutral_route.get("preferred_city_path", []))
	)
	pair_state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var wartime := TradeNetwork.build(pair_state)
	var wartime_route := _international_route(wartime, 0, 1)
	_check(
		not wartime_route.is_empty()
			and int(wartime_route["status"]) == int(neutral_route["status"])
			and wartime_route["city_path"] == neutral_route["city_path"]
			and wartime_route["edge_keys"] == neutral_route["edge_keys"]
			and str(wartime_route["blocked_reason"])
				== str(neutral_route["blocked_reason"]),
		"trade/war_keeps_route_fixed",
		str(wartime_route)
	)
	_check(
		int(wartime_route["gold_to_a"]) == int(floor(
			float(neutral_route["gold_to_a"])
			* TradeNetwork.WARTIME_TRADE_GOLD_MULTIPLIER
		))
			and int(wartime_route["gold_to_b"]) == int(floor(
				float(neutral_route["gold_to_b"])
				* TradeNetwork.WARTIME_TRADE_GOLD_MULTIPLIER
			)),
		"trade/war_halves_belligerent_bonus",
		"neutral=%s wartime=%s" % [str(neutral_route), str(wartime_route)]
	)
	pair_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.NEUTRAL
	)
	_check(
		TradeNetwork.build(pair_state) == neutral,
		"trade/peace_restores_bonus_and_original_routes"
	)

	var transit_state := _make_trade_transit_state()
	var transit := TradeNetwork.build(transit_state)
	var transit_route := _international_route(transit, 0, 2)
	var allocation_sum := _sum_dictionary_ints(
		transit_route.get("city_gold_bonus", {}) as Dictionary
	)
	_check(
		not transit_route.is_empty()
			and int(transit_route["gold_tax"]) == allocation_sum
			and int(transit_route["gold_tax"]) == (
				int(transit_route["gold_to_a"])
				+ int(transit_route["gold_to_b"])
				+ int(transit_route["transit_gold"])
			)
			and int(transit_route["transit_gold"]) > 0,
		"trade/tax_allocation_conserved_including_transit",
		str(transit_route)
	)
	var transit_peace_gold: Array = (
		transit["nation_trade_gold"] as Array
	).duplicate()
	transit_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.WAR
	)
	var transit_war := TradeNetwork.build(transit_state)
	for nation_id in range(transit_state.nations.size()):
		var expected_trade_gold := int(transit_peace_gold[nation_id])
		if nation_id in [0, 2]:
			expected_trade_gold = int(floor(
				float(expected_trade_gold)
				* TradeNetwork.WARTIME_TRADE_GOLD_MULTIPLIER
			))
		_check(
			int(transit_war["nation_trade_gold"][nation_id])
				== expected_trade_gold,
			"trade/wartime_multiplier_nation_%d" % nation_id,
			"peace=%d war=%d expected=%d" % [
				int(transit_peace_gold[nation_id]),
				int(transit_war["nation_trade_gold"][nation_id]),
				expected_trade_gold,
			]
		)
	var nation_zero_once := int(transit_war["nation_trade_gold"][0])
	transit_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	_check(
		int(TradeNetwork.build(transit_state)["nation_trade_gold"][0])
			== nation_zero_once,
		"trade/multiple_wars_do_not_stack_penalty"
	)

	var food_state := _make_trade_pair_state()
	food_state.cities[0].food_storage = 100
	food_state.cities[1].food_storage = 0
	food_state.nations[0].last_food_demand = 1
	food_state.nations[1].last_food_demand = 1
	food_state.nations[1].treasury_gold = 1000
	food_state.refresh_derived()
	var food_trade := TradeNetwork.build(food_state)
	var imports := _sum_int_array(food_trade["nation_food_import"])
	var exports := _sum_int_array(food_trade["nation_food_export"])
	var costs := _sum_int_array(food_trade["nation_food_cost"])
	var sales := _sum_int_array(food_trade["nation_food_sale_income"])
	# 简化版 EU4 贸易：钱凭空买粮，所以进口>0、出口恒为 0、销售收入恒为 0；
	# 贸易金恒等于路线税（无销售收入项）。
	var gold_identity := true
	for nation_id in range(food_state.nations.size()):
		gold_identity = gold_identity and (
			int(food_trade["nation_trade_gold"][nation_id])
			== int(food_trade["nation_trade_tax"][nation_id])
				+ int(food_trade["nation_food_sale_income"][nation_id])
		)
	_check(
		imports > 0 and exports == 0 and sales == 0 and costs > 0
			and gold_identity,
		"trade/food_conjured_from_gold",
		"food=%d/%d gold_cost=%d sales=%d" % [imports, exports, costs, sales]
	)
	var food_before := food_state.cities[0].food_storage + food_state.cities[1].food_storage
	var treasury_before := food_state.nations[0].treasury_gold + food_state.nations[1].treasury_gold
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(food_state)
	sim._resolve_trade_purchases(food_trade)
	var flows := Simulation._monthly_gold_flows_from_trade(food_state, food_trade)
	for nation_id in range(food_state.nations.size()):
		food_state.nations[nation_id].treasury_gold += int(flows[nation_id]["trade_net_income"])
	var food_after := food_state.cities[0].food_storage + food_state.cities[1].food_storage
	var treasury_after := food_state.nations[0].treasury_gold + food_state.nations[1].treasury_gold
	var tax_total := _sum_int_array(food_trade["nation_trade_tax"])
	var manpower_cost_total := _sum_int_array(food_trade["nation_manpower_cost"])
	# 粮食凭空产生：库存净增 = 进口量；国库净变动 = 路线税 - 买粮花费 - 买人花费。
	_check(
		food_after - food_before == imports
			and treasury_after - treasury_before
				== tax_total - costs - manpower_cost_total,
		"trade/applied_conjured_food_and_gold_cost",
		"food %d->%d gold_delta=%d tax=%d food_cost=%d mp_cost=%d" % [
			food_before, food_after, treasury_after - treasury_before,
			tax_total, costs, manpower_cost_total,
		]
	)
	sim.free()


func _make_trade_limit_state() -> GameState:
	var state := _make_empty_state(6)
	for nation_id in range(6):
		_add_city(state, nation_id, Vector2(0.1 + 0.15 * nation_id, 0.5), 12, 600)
	for a in range(6):
		for b in range(a + 1, 6):
			_add_edge(state, a, b, 20000, 1 + abs(a - b))
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	_configure_capitals_and_warehouses(state, 50)
	state.refresh_derived()
	return state


func _make_trade_pair_state() -> GameState:
	var state := _make_empty_state(2)
	_add_city(state, 0, Vector2(0.2, 0.5), 20, 600)
	_add_city(state, 1, Vector2(0.8, 0.5), 18, 600)
	var dock_a := _add_city(state, 0, Vector2(0.4, 0.5), 0, 0)
	var dock_b := _add_city(state, 1, Vector2(0.6, 0.5), 0, 0)
	state.cities[dock_a].is_dock = true
	state.cities[dock_b].is_dock = true
	_add_edge(state, 0, dock_a, 20000, 1)
	_add_edge(state, dock_a, dock_b, 20000, 1)
	_add_edge(state, dock_b, 1, 20000, 1)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	_configure_capitals_and_warehouses(state, 20)
	state.refresh_derived()
	return state


func _make_trade_transit_state() -> GameState:
	var state := _make_empty_state(3)
	_add_city(state, 0, Vector2(0.1, 0.5), 30, 600)
	_add_city(state, 1, Vector2(0.5, 0.5), 8, 300)
	_add_city(state, 2, Vector2(0.9, 0.5), 28, 600)
	_add_edge(state, 0, 1, 20000, 1)
	var transit_dock := _add_city(
		state, 1, Vector2(0.7, 0.5), 0, 0
	)
	state.cities[transit_dock].is_dock = true
	_add_edge(state, 1, transit_dock, 20000, 1)
	_add_edge(state, transit_dock, 2, 20000, 1)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	_configure_capitals_and_warehouses(state, 20)
	state.refresh_derived()
	return state


func _make_empty_state(nation_count: int) -> GameState:
	var state := GameState.new()
	state.world_seed = SEED
	state.map_aspect_ratio = 1.0
	for nation_id in range(nation_count):
		var nation := Nation.new()
		nation.id = nation_id
		nation.alive = true
		nation.trade_policy = TradeNetwork.BALANCED
		nation.treasury_gold = 1000
		nation.last_food_demand = 1
		nation.ruler_archetype = RulerProfile.BALANCED
		state.nations.append(nation)
	return state


func _add_city(
	state: GameState,
	owner: int,
	position: Vector2,
	gold: int = 10,
	food: int = 300
) -> int:
	var city := City.new()
	city.id = state.cities.size()
	city.owner_nation = owner
	city.map_position = position
	city.gold_per_month = gold
	city.food_per_half_year = food
	city.loyalty_target_nation = owner
	city.loyalty = RebellionSystem.LOYALTY_DEFAULT
	city.at_war = false
	state.cities.append(city)
	state.adjacency[city.id] = [] as Array[int]
	return city.id


func _add_edge(
	state: GameState,
	a: int,
	b: int,
	capacity: int = 20000,
	distance: int = 1
) -> void:
	var edge := Edge.new()
	edge.city_a = mini(a, b)
	edge.city_b = maxi(a, b)
	edge.max_manpower = capacity
	edge.base_max_manpower = maxi(capacity, 20000)
	edge.distance = distance
	state.edges.append(edge)
	state.edge_lookup[GameState.edge_key(a, b)] = edge
	(state.adjacency[a] as Array[int]).append(b)
	(state.adjacency[b] as Array[int]).append(a)


func _set_all_relations(state: GameState, relation: int) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(nation_a, nation_b, relation)


func _configure_capitals_and_warehouses(state: GameState, food: int) -> void:
	for nation in state.nations:
		var capital_id := -1
		for city in state.cities:
			if city.owner_nation == nation.id and not city.is_dock:
				capital_id = city.id
				break
		if capital_id < 0:
			continue
		nation.capital_city_id = capital_id
		nation.warehouse_city_ids = [capital_id] as Array[int]
		state.cities[capital_id].is_capital = true
		state.cities[capital_id].has_warehouse = true
		state.cities[capital_id].food_storage = food
	state.recognized_city_owners.resize(state.cities.size())
	for city in state.cities:
		state.recognized_city_owners[city.id] = city.owner_nation


func _international_route(result: Dictionary, nation_a: int, nation_b: int) -> Dictionary:
	for route_value in result.get("routes", []):
		var route: Dictionary = route_value
		if (
			bool(route.get("international", false))
			and int(route.get("nation_a", -1)) == mini(nation_a, nation_b)
			and int(route.get("nation_b", -1)) == maxi(nation_a, nation_b)
		):
			return route
	return {}


func _trade_state_fingerprint(state: GameState) -> String:
	var fields: Array[String] = [
		str(state.trade_revision), str(state.trade_routes),
	]
	for city in state.cities:
		fields.append("C%d:%d:%d:%d:%d" % [
			city.id, city.food_storage, city.trade_gold_bonus,
			city.trade_route_count, city.trade_food_balance,
		])
	for nation in state.nations:
		fields.append("N%d:%d:%d:%d:%d:%d" % [
			nation.id, nation.treasury_gold, nation.last_trade_gold,
			nation.last_trade_food_import, nation.last_trade_food_export,
			nation.last_trade_route_count,
		])
	return "|".join(fields)


func _test_rebellion_system() -> void:
	var loyalty_state := _make_loyalty_state()
	var near := RebellionSystem.loyalty_target(loyalty_state, 1)
	var far := RebellionSystem.loyalty_target(loyalty_state, 3)
	loyalty_state.nations[0].military_payment_ratio = 0.0
	var unpaid := RebellionSystem.loyalty_target(loyalty_state, 1)
	loyalty_state.nations[0].military_payment_ratio = 1.0
	var garrison := RebellionSystem.monthly_city_loyalty(
		loyalty_state, 1, {0: RebellionSystem.capital_hops(loyalty_state, 0)}, {1: 10000}
	)
	loyalty_state.nations[0].ruler_archetype = RulerProfile.TYRANT
	var tyrant := RebellionSystem.loyalty_target(loyalty_state, 1)
	loyalty_state.nations[0].ruler_archetype = RulerProfile.REFORMER
	var reformer := RebellionSystem.loyalty_target(loyalty_state, 1)
	_check(
		_approx(float(near["value"]), 75.0)
			and _approx(float(far["value"]), 71.0)
			and _approx(float(near["value"]) - float(unpaid["value"]), 20.0)
			and _approx(float(garrison["garrison_bonus"]), 4.0)
			and float(tyrant["value"]) < float(near["value"])
			and float(reformer["value"]) > float(near["value"]),
		"rebellion/loyalty_distance_unpaid_garrison_ruler",
		"near=%s far=%s unpaid=%s garrison=%s tyrant=%s reformer=%s" % [
			near["value"], far["value"], unpaid["value"],
			garrison["garrison_bonus"], tyrant["value"], reformer["value"],
		]
	)

	var progress_city := loyalty_state.cities[1]
	# 外族实控配合暴君影响，让目标持续低于 25，才能精确验证连续三月。
	loyalty_state.nations[0].ruler_archetype = RulerProfile.TYRANT
	progress_city.loyalty = 20.0
	progress_city.loyalty_target_nation = 1
	progress_city.rebellion_progress = 0
	progress_city.rebellion_cooldown_until_day = -1
	var progress_ok := true
	for month in range(1, RebellionSystem.REBELLION_PROGRESS_MONTHS + 1):
		loyalty_state.day = month * Simulation.DAYS_PER_MONTH
		var snapshot := RebellionSystem.monthly_city_loyalty(loyalty_state, 1)
		progress_ok = progress_ok and int(snapshot["rebellion_progress"]) == month
		progress_city.loyalty = float(snapshot["loyalty"])
		progress_city.rebellion_progress = int(snapshot["rebellion_progress"])
	progress_city.rebellion_cooldown_until_day = (
		loyalty_state.day + RebellionSystem.REBELLION_COOLDOWN_DAYS
	)
	loyalty_state.day = progress_city.rebellion_cooldown_until_day - 1
	var before_cooldown := RebellionSystem.monthly_city_loyalty(loyalty_state, 1)
	loyalty_state.day += 1
	var at_cooldown := RebellionSystem.monthly_city_loyalty(loyalty_state, 1)
	_check(
		progress_ok
			and not bool(before_cooldown["eligible"])
			and bool(at_cooldown["eligible"]),
		"rebellion/three_month_progress_and_720_day_cooldown"
	)

	var region_state := _make_rebellion_transaction_state()
	for city_id in [1, 2, 3]:
		region_state.cities[city_id].loyalty = 20.0
		region_state.cities[city_id].loyalty_target_nation = 1
		region_state.cities[city_id].rebellion_progress = 3
	var connected := RebellionSystem.collect_rebellion_regions(
		region_state, 0, [3, 1, 2]
	)
	region_state.edge_of(2, 3).max_manpower = 0
	var split := RebellionSystem.collect_rebellion_regions(
		region_state, 0, [3, 1, 2]
	)
	region_state.edge_of(2, 3).max_manpower = 20000
	region_state.cities[3].loyalty_target_nation = 0
	var target_split := RebellionSystem.collect_rebellion_regions(
		region_state, 0, [3, 1, 2]
	)
	_check(
		connected == [[1, 2, 3]]
			and split == [[1, 2], [3]]
			and target_split == [[1, 2], [3]],
		"rebellion/regions_connected_and_target_partitioned",
		"connected=%s split=%s target=%s" % [connected, split, target_split]
	)

	var alliance_conflict := _make_empty_state(3)
	_set_all_relations(
		alliance_conflict, GameState.DiplomaticRelation.NEUTRAL
	)
	alliance_conflict.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	alliance_conflict.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.ALLIED
	)
	alliance_conflict.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.WAR
	)
	_check(
		alliance_conflict.alliance_bloc(0) == [0, 1]
			and alliance_conflict.alliance_bloc(2) == [2],
		"rebellion/alliance_bloc_war_blocks_third_party_bridge",
		"p=%s r=%s" % [
			alliance_conflict.alliance_bloc(0),
			alliance_conflict.alliance_bloc(2),
		]
	)
	var alliance_chain := _make_empty_state(3)
	_set_all_relations(alliance_chain, GameState.DiplomaticRelation.NEUTRAL)
	alliance_chain.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	alliance_chain.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.ALLIED
	)
	_check(
		alliance_chain.alliance_bloc(0) == [0, 1, 2]
			and alliance_chain.alliance_bloc(2) == [0, 1, 2],
		"rebellion/alliance_bloc_keeps_non_hostile_chain"
	)

	var diplomacy_state := _make_rebellion_diplomacy_state()
	var diplomacy_rebel := diplomacy_state.start_regional_rebellion(
		0, [1, 2]
	)
	_check(
		diplomacy_rebel == 3
			and diplomacy_state.is_enemy(0, diplomacy_rebel)
			and diplomacy_state.relation_between(1, diplomacy_rebel)
				== GameState.DiplomaticRelation.NEUTRAL
			and diplomacy_state.is_enemy(2, diplomacy_rebel)
			and not diplomacy_state.alliance_bloc(0).has(diplomacy_rebel),
		"rebellion/local_rebel_does_not_inherit_parent_alliance",
		"bloc=%s ally_relation=%d" % [
			diplomacy_state.alliance_bloc(0),
			diplomacy_state.relation_between(1, diplomacy_rebel),
		]
	)

	var start_state := _make_rebellion_transaction_state()
	var totals_before := _nation_resource_totals(start_state)
	var legal_before := [
		start_state.recognized_owner_of(1), start_state.recognized_owner_of(2),
	]
	var rebel_id := start_state.start_regional_rebellion(0, [2, 1])
	var totals_after := _nation_resource_totals(start_state)
	var start_ok := rebel_id == 1
	for city_id in [1, 2]:
		start_ok = start_ok and (
			start_state.cities[city_id].owner_nation == rebel_id
			and start_state.recognized_owner_of(city_id) == legal_before[city_id - 1]
			and start_state.cities[city_id].occupation_sponsor_nation == rebel_id
		)
	start_ok = start_ok and (
		start_state.is_enemy(0, rebel_id)
		and not start_state.nations[rebel_id].color.is_equal_approx(
			start_state.nations[0].color
		)
		and not start_state.nations[rebel_id].color.is_equal_approx(
			start_state._derive_vassal_color(
				start_state.nations[0].color, rebel_id
			)
		)
		and start_state.rebellion_structure_valid()
		and start_state.territory_structure_valid()
		and totals_before == totals_after
	)
	_check(
		start_ok,
		"rebellion/start_changes_control_not_legal_title_and_conserves",
		"rebel=%d before=%s after=%s" % [rebel_id, totals_before, totals_after]
	)
	var uprising_main_armies := 0
	for army in start_state.armies:
		if (
			army.owner_nation == rebel_id
			and army.size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and army.strategic_role == Army.StrategicRole.MAIN
			and army.location_city == start_state.nations[rebel_id].capital_city_id
		):
			uprising_main_armies += 1
	_check(
		uprising_main_armies
			== int(ceil(
				0.1 * float(start_state.land_cities_of(rebel_id).size())
			))
			and start_state._battle_group_structure_valid(),
		"rebellion/regional_rebel_gets_civil_war_mars_armies",
		"main=%d" % uprising_main_armies
	)
	var parent_attitude := DiplomacyAI.diplomatic_attitude_breakdown(
		start_state, 0, rebel_id
	)
	var rebel_attitude := DiplomacyAI.diplomatic_attitude_breakdown(
		start_state, rebel_id, 0
	)
	_check(
		_approx(
			float(parent_attitude.get("parent_rebel_component", 0.0)),
			DiplomacyAI.PARENT_REBEL_ATTITUDE
		)
			and _approx(
				float(rebel_attitude.get("parent_rebel_component", 0.0)),
				0.0
			),
		"rebellion/parent_has_directional_natural_hostility"
	)
	start_state.day += (
		RebellionSystem.REGIONAL_REBELLION_MIN_WAR_DAYS - 1
	)
	var early_sim := Simulation.new()
	early_sim.setup(start_state)
	var early_coalition_peace := early_sim._make_coalition_peace(
		0, rebel_id
	)
	early_sim.free()
	var early_peace_blocked := not start_state.set_diplomatic_relation(
		0, rebel_id, GameState.DiplomaticRelation.NEUTRAL
	)
	var early_assessment := DiplomacyAI.peace_assessment(
		start_state, 0, rebel_id
	)
	start_state.day += 1
	var peace_unlocked := start_state.set_diplomatic_relation(
		0, rebel_id, GameState.DiplomaticRelation.NEUTRAL
	)
	_check(
		not bool(early_coalition_peace.get("changed", false))
			and early_peace_blocked
			and start_state.day == 450
			and bool(early_assessment.get("rebellion_war_locked", false))
			and peace_unlocked,
		"rebellion/parent_war_locked_for_one_year"
	)
	var recognized := start_state.recognize_regional_rebellion(rebel_id)
	var recognize_ok := recognized
	for city_id in [1, 2]:
		recognize_ok = recognize_ok and (
			start_state.recognized_owner_of(city_id) == rebel_id
			and start_state.cities[city_id].occupation_sponsor_nation == -1
		)
	recognize_ok = recognize_ok and (
		not bool(start_state.rebellions[rebel_id]["active"])
		and bool(start_state.rebellions[rebel_id]["recognized"])
		and start_state.rebellion_structure_valid()
		and start_state.territory_structure_valid()
	)
	_check(recognize_ok, "rebellion/recognize_commits_legal_title")

	var suppress_state := _make_rebellion_transaction_state()
	var suppress_rebel := suppress_state.start_regional_rebellion(0, [1, 2])
	var suppressed := suppress_state.suppress_regional_rebellion(suppress_rebel)
	var suppress_ok := suppressed and not suppress_state.nations[suppress_rebel].alive
	for city_id in [1, 2]:
		suppress_ok = suppress_ok and (
			suppress_state.cities[city_id].owner_nation == 0
			and suppress_state.cities[city_id].loyalty_target_nation == 0
			and _approx(suppress_state.cities[city_id].loyalty, 45.0)
			and suppress_state.cities[city_id].rebellion_progress == 0
			and suppress_state.cities[city_id].rebellion_cooldown_until_day
				== suppress_state.day + RebellionSystem.REBELLION_COOLDOWN_DAYS
		)
	suppress_ok = suppress_ok and (
		not bool(suppress_state.rebellions[suppress_rebel]["active"])
		and not bool(suppress_state.rebellions[suppress_rebel]["recognized"])
		and suppress_state.rebellion_structure_valid()
		and suppress_state.territory_structure_valid()
	)
	_check(suppress_ok, "rebellion/suppress_restores_parent_and_cooldown")

	# 战时被占领的法理地（城1：实控0、法理1、双方交战）属于活跃前线战果，
	# 不能再通过忠诚复国机制凭空反正——这正是"打下的城过一阵自己跳回原主"的
	# 根因。只有本国自有边境城（城2：实控0、法理0、政治目标1）可离心归附敌国。
	var restore_state := _make_loyalty_restoration_state()
	var restore_count_before := restore_state.nations.size()
	var restore_totals_before := _nation_resource_totals(restore_state)
	var restore_events := RebellionSystem.resolve_month(restore_state)
	var restore_totals_after := _nation_resource_totals(restore_state)
	var restore_ok := (
		restore_state.nations.size() == restore_count_before
		and restore_state.rebellions.is_empty()
		and restore_events.size() == 1
		and str(restore_events[0].get("kind", ""))
			== "loyalty_target_restored"
		and int(restore_events[0].get("target_id", -1)) == 1
		and (restore_events[0].get("city_ids", []) as Array) == [2]
		and restore_totals_before == restore_totals_after
	)
	# 城2离心归附：实控转给敌国 1，法理仍属 0。
	restore_ok = restore_ok and (
		restore_state.cities[2].owner_nation == 1
		and restore_state.cities[2].loyalty_target_nation == 1
		and restore_state.cities[2].rebellion_progress == 0
		and restore_state.cities[2].rebellion_cooldown_until_day
			== restore_state.day + RebellionSystem.REBELLION_COOLDOWN_DAYS
		and restore_state.recognized_owner_of(2) == 0
		and restore_state.cities[2].occupation_sponsor_nation == 1
	)
	# 城1是战时占领地：实控与占领声明必须原样保留，不得被忠诚机制自动反正。
	restore_ok = restore_ok and (
		restore_state.cities[1].owner_nation == 0
		and restore_state.recognized_owner_of(1) == 1
		and restore_state.cities[1].occupation_sponsor_nation == 0
		and restore_state.is_enemy(0, 1)
		and restore_state.territory_structure_valid()
	)
	_check(
		restore_ok,
		"rebellion/wartime_occupation_locked_only_defection_restored",
		"events=%s before=%s after=%s owner1=%d owner2=%d" % [
			restore_events, restore_totals_before, restore_totals_after,
			restore_state.cities[1].owner_nation,
			restore_state.cities[2].owner_nation,
		]
	)

	# 同一恢复事务从和平开始时，必须先原子进入战争再形成 owner/legal
	# 不一致；任何完整事务都不能留下和平占领。
	var peaceful_restore_state := _make_loyalty_restoration_state()
	peaceful_restore_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.NEUTRAL
	)
	var peaceful_restore_events := RebellionSystem.resolve_month(
		peaceful_restore_state
	)
	var peaceful_restore_event_count := 0
	for event_value in peaceful_restore_events:
		var restore_event: Dictionary = event_value
		if str(restore_event.get("kind", "")) == "loyalty_target_restored":
			peaceful_restore_event_count += 1
	_check(
		peaceful_restore_event_count == 1
			and peaceful_restore_state.is_enemy(0, 1)
			and peaceful_restore_state.cities[1].owner_nation == 1
			and peaceful_restore_state.recognized_owner_of(1) == 1
			and peaceful_restore_state.cities[1]
				.occupation_sponsor_nation == -1
			and peaceful_restore_state.cities[2].owner_nation == 1
			and peaceful_restore_state.recognized_owner_of(2) == 0
			and peaceful_restore_state.cities[2]
				.occupation_sponsor_nation == 1
			and peaceful_restore_state.territory_structure_valid(),
		"rebellion/peacetime_restore_declares_war_before_control_transfer",
		"events=%s relation=%d owner/legal=%d/%d" % [
			peaceful_restore_events,
			peaceful_restore_state.relation_between(0, 1),
			peaceful_restore_state.cities[2].owner_nation,
			peaceful_restore_state.recognized_owner_of(2),
		]
	)

	# 和平宗藩关系不能由地方忠诚事务擅自改成内战或外战；拒绝时状态原子不变。
	var vassal_restore_state := _make_loyalty_restoration_state()
	vassal_restore_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	vassal_restore_state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	for warehouse_id in vassal_restore_state.nations[1].warehouse_city_ids:
		vassal_restore_state.cities[warehouse_id].has_warehouse = false
		vassal_restore_state.cities[warehouse_id].food_storage = 0
	vassal_restore_state.nations[1].warehouse_city_ids.clear()
	vassal_restore_state.refresh_derived()
	var vassal_owner_before := vassal_restore_state.cities[2].owner_nation
	var vassal_legal_before := vassal_restore_state.recognized_owner_of(2)
	var vassal_totals_before := _nation_resource_totals(vassal_restore_state)
	var vassal_restore_rejected := (
		not vassal_restore_state.restore_regional_loyalty_target(
			0, 1, [1, 2] as Array[int]
		)
	)
	_check(
		vassal_restore_rejected
			and vassal_restore_state.is_allied(0, 1)
			and not vassal_restore_state.is_enemy(0, 1)
			and vassal_restore_state.cities[2].owner_nation
				== vassal_owner_before
			and vassal_restore_state.recognized_owner_of(2)
				== vassal_legal_before
			and _nation_resource_totals(vassal_restore_state)
				== vassal_totals_before
			and vassal_restore_state.suzerainty_structure_valid()
			and vassal_restore_state.territory_structure_valid(),
		"rebellion/peaceful_suzerainty_restore_rejected_atomically"
	)

	var dead_target_state := _make_dead_loyalty_target_state()
	var dead_target_count_before := dead_target_state.nations.size()
	var dead_target_events := RebellionSystem.resolve_month(dead_target_state)
	var dead_target_rebel := dead_target_count_before
	_check(
		dead_target_state.nations.size() == dead_target_count_before + 1
			and dead_target_state.nations[dead_target_rebel].alive
			and dead_target_events.size() == 1
			and str(dead_target_events[0].get("kind", ""))
				== "regional_rebellion"
			and int(dead_target_events[0].get("rebel_id", -1))
				== dead_target_rebel
			and dead_target_state.cities[1].owner_nation == dead_target_rebel
			and dead_target_state.cities[2].owner_nation == dead_target_rebel,
		"rebellion/dead_loyalty_target_creates_local_rebel",
		"events=%s nations=%d" % [
			dead_target_events, dead_target_state.nations.size(),
		]
	)

	var vassal_food_state := _make_vassal_regional_rebellion_state()
	var vassal_food_before := _nation_resource_totals(vassal_food_state)
	var root_food_before := vassal_food_state.cities[0].food_storage
	var vassal_rebel := vassal_food_state.start_regional_rebellion(1, [3])
	var vassal_food_after := _nation_resource_totals(vassal_food_state)
	_check(
		vassal_rebel == 2
			and vassal_food_before == vassal_food_after
			and root_food_before == 800
			and vassal_food_state.cities[0].food_storage == 600
			and vassal_food_state.cities[3].food_storage == 200
			and vassal_food_state.cities[3].has_warehouse
			and vassal_food_state.nations[1].warehouse_city_ids.is_empty()
			and vassal_food_state.territory_structure_valid(),
		"rebellion/vassal_region_splits_shared_food_pool_conservatively",
		"before=%s after=%s root=%d rebel=%d" % [
			vassal_food_before, vassal_food_after,
			vassal_food_state.cities[0].food_storage,
			vassal_food_state.cities[3].food_storage,
		]
	)


func _make_loyalty_state() -> GameState:
	var state := _make_empty_state(2)
	for city_id in range(4):
		_add_city(state, 0, Vector2(0.15 + 0.2 * city_id, 0.5))
	for city_id in range(3):
		_add_edge(state, city_id, city_id + 1, 20000, 1)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	_configure_capitals_and_warehouses(state, 100)
	state.nations[0].capital_city_id = 0
	for city in state.cities:
		city.is_capital = city.id == 0
		city.has_warehouse = city.id == 0
		city.loyalty_target_nation = 0
	state.nations[0].ruler_archetype = RulerProfile.BALANCED
	state.nations[0].ruler_traits.clear()
	state.nations[0].military_payment_ratio = 1.0
	state.refresh_derived()
	return state


func _make_rebellion_transaction_state() -> GameState:
	var state := _make_empty_state(1)
	for city_id in range(4):
		_add_city(
			state, 0, Vector2(0.15 + 0.2 * city_id, 0.5),
			10 + city_id, 300 + city_id * 50
		)
	for city_id in range(3):
		_add_edge(state, city_id, city_id + 1, 20000, 1)
	_configure_capitals_and_warehouses(state, 400)
	state.nations[0].treasury_gold = 1000
	state.nations[0].manpower_pool = 3000
	state.day = 90
	state.refresh_derived()
	return state


func _make_rebellion_diplomacy_state() -> GameState:
	var state := _make_empty_state(3)
	for city_id in range(4):
		_add_city(
			state, 0, Vector2(0.15 + 0.2 * city_id, 0.5),
			10 + city_id, 300 + city_id * 50
		)
	for city_id in range(3):
		_add_edge(state, city_id, city_id + 1, 20000, 1)
	_add_city(state, 1, Vector2(0.2, 0.8), 10, 300)
	_add_city(state, 2, Vector2(0.8, 0.8), 10, 300)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	_configure_capitals_and_warehouses(state, 400)
	state.nations[0].treasury_gold = 1000
	state.nations[0].manpower_pool = 3000
	state.day = 90
	state.refresh_derived()
	return state


func _make_loyalty_restoration_state() -> GameState:
	var state := _make_empty_state(2)
	for city_id in range(4):
		_add_city(
			state, 0, Vector2(0.15 + 0.2 * city_id, 0.5),
			10 + city_id, 300 + city_id * 50
		)
	# 目标国保留一座合法存续领土。城 1 是目标国被占领的法理地，城 2 则
	# 只有政治归附目标，用同一事务覆盖“复国”和“归附后仍保留原法理”。
	_add_city(state, 1, Vector2(0.9, 0.8), 10, 300)
	for city_id in range(3):
		_add_edge(state, city_id, city_id + 1, 20000, 1)
	_add_edge(state, 3, 4, 20000, 1)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	_configure_capitals_and_warehouses(state, 400)
	state.recognized_city_owners[1] = 1
	state.cities[1].occupation_sponsor_nation = 0
	for city_id in [1, 2]:
		var city := state.cities[city_id]
		city.loyalty = 20.0
		city.loyalty_target_nation = 1
		city.rebellion_progress = RebellionSystem.REBELLION_PROGRESS_MONTHS - 1
		city.rebellion_cooldown_until_day = -1
	state.nations[0].treasury_gold = 1000
	state.nations[0].manpower_pool = 3000
	state.nations[0].ruler_archetype = RulerProfile.TYRANT
	state.day = 90
	state.refresh_derived()
	return state


func _make_vassal_regional_rebellion_state() -> GameState:
	var state := _make_empty_state(2)
	for city_id in range(4):
		var owner := 0 if city_id == 0 else 1
		_add_city(
			state, owner, Vector2(0.15 + 0.2 * city_id, 0.5),
			10, 100
		)
	for city_id in range(3):
		_add_edge(state, city_id, city_id + 1, 20000, 1)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	_configure_capitals_and_warehouses(state, 0)
	state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	state.nations[1].capital_city_id = 1
	state.nations[1].warehouse_city_ids = [] as Array[int]
	state.cities[1].is_capital = true
	state.cities[1].has_warehouse = false
	state.cities[1].food_storage = 0
	state.cities[0].food_storage = 800
	state.nations[1].treasury_gold = 900
	state.nations[1].manpower_pool = 3000
	state.day = 90
	state.refresh_derived()
	return state


func _make_dead_loyalty_target_state() -> GameState:
	var state := _make_empty_state(2)
	for city_id in range(4):
		_add_city(
			state, 0, Vector2(0.15 + 0.2 * city_id, 0.5),
			10 + city_id, 300 + city_id * 50
		)
	for city_id in range(3):
		_add_edge(state, city_id, city_id + 1, 20000, 1)
	_set_all_relations(state, GameState.DiplomaticRelation.NEUTRAL)
	_configure_capitals_and_warehouses(state, 400)
	state.nations[0].treasury_gold = 1000
	state.nations[0].manpower_pool = 3000
	state.nations[0].military_payment_ratio = 0.0
	state.day = 90
	state.refresh_derived()
	for city_id in [1, 2]:
		var city := state.cities[city_id]
		city.loyalty = 20.0
		city.loyalty_target_nation = 1
		city.rebellion_progress = RebellionSystem.REBELLION_PROGRESS_MONTHS - 1
		city.rebellion_cooldown_until_day = -1
	return state


func _nation_resource_totals(state: GameState) -> Array[int]:
	var gold := 0
	var manpower := 0
	var food := 0
	for nation in state.nations:
		gold += nation.treasury_gold
		manpower += nation.manpower_pool
	for city in state.cities:
		food += city.food_storage
	return [gold, manpower, food] as Array[int]


func _test_monthly_publication() -> void:
	var state := _make_trade_pair_state()
	state.day = 28
	state.month = 0
	for nation in state.nations:
		nation.ruler_archetype = RulerProfile.BALANCED
		nation.ruler_traits.clear()
		nation.military_payment_ratio = 1.0
	for city in state.cities:
		city.loyalty = 50.0
		city.loyalty_target_nation = city.owner_nation
		city.rebellion_progress = 0
		city.gold_per_month = 0
		city.manpower_per_month = 0
		city.food_per_half_year = 0
	state.armies.clear()
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim.diplomacy_enabled = false
	for nation in state.nations:
		sim.ai_policy_overrides[nation.id] = (
			func(_state: GameState, _nation_id: int, _sim: Simulation) -> void:
				pass
		)
	var loyalty_28 := state.cities[0].loyalty
	var treasury_28 := state.nations[0].treasury_gold
	var trade_revision_28 := state.trade_revision
	var routes_28 := state.trade_routes.duplicate(true)
	sim._advance_day()
	_check(
		state.day == 29
			and state.month == 0
			and _approx(state.cities[0].loyalty, loyalty_28)
			and state.nations[0].treasury_gold == treasury_28
			and state.trade_revision == trade_revision_28
			and state.trade_routes == routes_28,
		"monthly/day_29_has_no_monthly_settlement"
	)
	sim._advance_day()
	var loyalty_30 := state.cities[0].loyalty
	var treasury_30 := state.nations[0].treasury_gold
	var trade_revision_30 := state.trade_revision
	var routes_30 := state.trade_routes.duplicate(true)
	# Setup publishes initial trade snapshot on day 30; unchanged monthly
	# trade content legitimately keeps the revision stable.
	_check(
		state.day == 30
			and state.month == 1
			and _approx(loyalty_30 - loyalty_28, 5.0)
			and state.nations[0].average_loyalty > loyalty_28
			and not routes_30.is_empty()
			and trade_revision_30 >= trade_revision_28
			and state.cities[0].trade_route_count > 0
			and state.nations[0].last_trade_route_count > 0,
		"monthly/day_30_publishes_trade_and_loyalty",
		"loyalty=%.1f routes=%d revision=%d" % [
			loyalty_30, routes_30.size(), trade_revision_30,
		]
	)
	sim._advance_day()
	_check(
		state.day == 31
			and state.month == 1
			and _approx(state.cities[0].loyalty, loyalty_30)
			and state.nations[0].treasury_gold == treasury_30
			and state.trade_revision == trade_revision_30
			and state.trade_routes == routes_30,
		"monthly/day_31_does_not_double_settle"
	)
	sim.free()


func _sum_int_array(values: Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total


func _sum_dictionary_ints(values: Dictionary) -> int:
	var total := 0
	for value in values.values():
		total += int(value)
	return total
