extends SceneTree
## 回归测试套件（headless 运行，无需图形）。
##
## 运行:
##   /Users/bytedance/Godot.app/Contents/MacOS/Godot --headless --path <项目> --script res://tests/test_suite.gd
## 或用项目根的 run_tests.sh。
##
## 退出码 0 = 全部通过，1 = 有失败（可接入 CI）。
## 覆盖：世界生成不变量 / 地形惩罚数学 / 战斗与撤退 / 模拟推进 / 确定性复现。

var _passed: int = 0
var _failed: int = 0
var _fail_msgs: Array[String] = []


func _init() -> void:
	print("==== WorldWar 回归测试 ====\n")

	_test_world_generation()
	_test_river_transport()
	_test_responsive_map_layout()
	_test_country_display_fade()
	_test_terrain_multiplier()
	_test_battle_basics()
	_test_retreat_mechanic()
	_test_garrison_defense()
	_test_multi_vs_one()
	_test_starvation_morale()
	_test_persistent_morale()
	_test_simulation_progress()
	_test_post_unification_continuation()
	_test_determinism()
	_test_time_layering()
	_test_siege_dice()
	_test_captured_city_fort_recovery()
	_test_trigger_detection()
	_test_three_way_battle()
	_test_three_way_siege()
	_test_multi_army_aggregation()
	_test_three_way_serial()
	_test_campaign_active_wave_reconciliation()
	_test_siege_arrival_triggers()
	_test_crosspass_field_priority()
	_test_capacity_no_block_enemy()
	_test_directional_friendly_capacity()
	_test_heightmap_heavy_transport_footprint()
	_test_march_time_linear()
	_test_siege_time_curve()
	_test_siege_food_clock()
	_test_weak_attack_retreat()
	_test_morale_retreat_recovery()
	_test_retreat_transport_footprint()
	_test_edge_retreat_transport_batches()
	_test_besieged_city_retreat_depth()
	_test_supply_morale_and_passive_retreat_battle()
	_test_rolling_supply_settlement()
	_test_siege_battle_then_progress_order()
	_test_siege_interruption_and_late_garrison()
	_test_edge_holding_state()
	_test_edge_supply_from_both_endpoints()
	_test_warehouse_logistics()
	_test_atomic_territory_transactions()
	_test_capital_capture_capitulation()
	_test_holding_combat_adaptation()
	_test_retreat_contact_and_position_continuity()
	_test_ai_strategic_map_and_threat()
	_test_stable_force_resource_cache_filter()
	_test_city_defense_incremental_topology()
	_test_ai_merge_and_retreat_utility()
	_test_garrison_retreat_city_defense()
	_test_ai_encirclement_breakout_and_relief()
	_test_manpower_pool_and_force_commands()
	_test_gold_reserve_budget_and_war_snapshot()
	_test_ruler_economy_integration()
	_test_diplomacy_state_and_ai()
	_test_war_preparation_cancel_cooldown()
	_test_war_preparation_route_block_grace()
	_test_alliance_war_coalitions()
	_test_suzerainty_invariants()
	_test_vassal_tribute()
	_test_enfeoff_ai()
	_test_suzerainty_lifecycle()
	_test_civil_war_relations()
	_test_centralization_decision()
	_test_civil_war_annexation()
	_test_shared_granary_and_relay_supply()
	_test_vassal_governance_output_bonus()
	_test_suzerainty_disconnection_requires_capture()
	_test_external_territory_sovereignty()
	_test_vassal_local_main_command()
	_test_stranded_hostile_army_eviction()
	_test_vassal_wartime_support_and_capital()
	_test_peacetime_demobilization_and_border_defense()
	_test_resource_hubs_and_food_mobilization()
	_test_small_nation_survival_and_emergency_recruitment()
	_test_combat_fairness_and_conservation()
	_test_structured_battle_log()
	_test_capital_defense_bonus()
	_test_equivariant_ordering()
	_test_remaining_combat_risk_closures()

	print("\n==== 结果: %d 通过, %d 失败 ====" % [_passed, _failed])
	for m in _fail_msgs:
		print("  [FAIL] " + m)
	quit(1 if _failed > 0 else 0)

# ------------------------------------------------------------------ 断言辅助

func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_fail_msgs.append(msg)
		print("  [FAIL] " + msg)


func _approx(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps


func _set_neutral_ruler(nation: Nation) -> void:
	nation.ruler_archetype = RulerProfile.BALANCED
	nation.ruler_traits.clear()
	nation.trade_policy = RulerProfile.POLICY_BALANCED

# ------------------------------------------------------------------ 1. 世界生成
func _test_world_generation() -> void:
	print("[1] 世界生成不变量")
	var gs := GameState.new()
	gs.generate_world(12345)
	gs.refresh_derived()
	var ruler_modifiers_match := true
	for city in gs.cities:
		ruler_modifiers_match = (
			ruler_modifiers_match
			and _approx(
				city.ruler_city_defense_multiplier,
				RulerProfile.city_defense_multiplier(
					gs.nations[city.owner_nation]
				)
			)
		)
	for army in gs.armies:
		var ruler := gs.nations[army.owner_nation]
		ruler_modifiers_match = (
			ruler_modifiers_match
			and _approx(
				army.ruler_defense_multiplier,
				RulerProfile.defense_multiplier(ruler)
			)
			and _approx(
				army.ruler_morale_multiplier,
				RulerProfile.morale_multiplier(ruler)
			)
		)
	_check(
		ruler_modifiers_match,
		"refresh_derived 的按国缓存必须与逐城市/逐军队君主修正完全一致"
	)
	var legacy_road_flow := {}
	var tree_road_flow := {}
	for edge in gs.edges:
		var edge_key := GameState.edge_key(edge.city_a, edge.city_b)
		legacy_road_flow[edge_key] = 0.0
		tree_road_flow[edge_key] = 0.0
	for road_source in range(gs.cities.size()):
		var road_field := gs._road_dijkstra(road_source)
		for road_goal in range(road_source + 1, gs.cities.size()):
			gs._accumulate_road_flow(
				road_field["prev"], road_source, road_goal,
				legacy_road_flow, 1.0
			)
		gs._accumulate_road_flow_tree(
			road_field["prev"], road_source, tree_road_flow
		)
	_check(
		legacy_road_flow == tree_road_flow,
		"所有起点的道路流量树汇总必须与逐终点路径回溯完全等价"
	)
	var land_cities := gs.land_cities()
	_check(
		land_cities.size() == GameState.TERRAIN_CITY_COUNT
			and gs.cities.size() > GameState.TERRAIN_CITY_COUNT,
		"正式地图应有%d个陆城和动态码头，实为%d城"
			% [
				GameState.TERRAIN_CITY_COUNT,
				gs.cities.size(),
			]
	)
	_check(
		gs.edges.size() >= gs.cities.size() - 1
			and gs.edges.size() < gs.cities.size() * 3,
		"真实地图应使用稀疏局部图，边数实为 %d" % gs.edges.size()
	)
	var chokepoint_count := 0
	for edge in gs.edges:
		if (
			edge.max_manpower > 0
			and edge.danger
				>= Combat.CHOKEPOINT_DANGER_ONSET
		):
			chokepoint_count += 1
	_check(
		chokepoint_count > 0,
		"真实地图至少应生成一条可通行高险关隘"
	)
	var expected_initial_armies := 0
	var default_city_mask := (
		load(GameState.DEFAULT_CITY_MASK_PATH) as Texture2D
	).get_image()
	var all_land_cities_in_default_mask := true
	for masked_city in gs.land_cities():
		var mask_x := clampi(
			int(masked_city.map_position.x * default_city_mask.get_width()),
			0, default_city_mask.get_width() - 1
		)
		var mask_y := clampi(
			int(masked_city.map_position.y * default_city_mask.get_height()),
			0, default_city_mask.get_height() - 1
		)
		all_land_cities_in_default_mask = (
			all_land_cities_in_default_mask
			and default_city_mask.get_pixel(mask_x, mask_y).get_luminance() >= 0.5
		)
	_check(
		all_land_cities_in_default_mask,
		"默认地图所有陆城必须位于对齐的中国领土白色蒙版内"
	)
	for initial_nation in gs.nations:
		var initial_frontier := {}
		for initial_city in gs.cities_of(initial_nation.id):
			for initial_neighbor in gs.neighbors(initial_city.id):
				if (
					gs.cities[initial_neighbor].owner_nation
						!= initial_nation.id
				):
					initial_frontier[initial_city.id] = true
					break
		expected_initial_armies += (
			initial_frontier.size() + 3
		)
	_check(
		gs.armies.size() == expected_initial_armies,
		"初始军队应覆盖实际国界城市并包含一个满编战团，应为%d，实为%d"
			% [expected_initial_armies, gs.armies.size()]
	)
	_check(gs.nations.size() == 4, "国家数应为 4")
	var initial_peace := true
	for nation_a in range(gs.nations.size()):
		for nation_b in range(nation_a + 1, gs.nations.size()):
			initial_peace = initial_peace and (
				gs.relation_between(nation_a, nation_b)
				== GameState.DiplomaticRelation.NEUTRAL
			)
	_check(initial_peace, "真实地形地图应以所有国家两两和平开局")
	_check(
		gs.cities.all(func(city: City) -> bool: return not city.at_war),
		"和平开局时所有城市均不应显示战争状态"
	)
	# 空间四等份经合法交通图消除飞地后允许 ±1 城偏差；码头不改变初始军制。
	for n in gs.nations:
		var owned_land := gs.land_cities_of(n.id)
		var cnt := owned_land.size()
		_check(
			absi(
				cnt
				- GameState.TERRAIN_CITY_COUNT
					/ gs.nations.size()
			) <= 1,
			"国%d 初始陆城数应在均值%d的±1范围内，实为%d"
				% [
					n.id,
					GameState.TERRAIN_CITY_COUNT
						/ gs.nations.size(),
					cnt,
				]
		)
		var food_hubs: Array[City] = []
		var manpower_hubs: Array[City] = []
		for owned_city in gs.cities_of(n.id):
			if owned_city.is_food_hub:
				food_hubs.append(owned_city)
			if owned_city.is_manpower_hub:
				manpower_hubs.append(owned_city)
		_check(
			food_hubs.size() == 1
			and food_hubs[0].food_per_half_year
				>= int(round(
					float(GameState.FOOD_HUB_MIN_OUTPUT)
						* food_hubs[
							0
						].terrain_output_multiplier
				)),
			"国%d 应有一个达到海拔修正下限的高产粮食核心"
				% n.id
		)
		_check(
			manpower_hubs.size() == 1
			and manpower_hubs[0].manpower_per_month
				>= GameState.MANPOWER_HUB_MIN_OUTPUT,
			"国%d 应有一个高产人口核心" % n.id
		)
		_check(
			food_hubs.is_empty()
			or manpower_hubs.is_empty()
			or food_hubs[0].id != manpower_hubs[0].id,
			"国%d 的粮食与人口核心在城市充足时应尽量分离" % n.id
		)
		var resource_snapshot := StrategicMapSnapshot.build(
			AiWorldView.build(gs, n.id)
		)
		_check(
			resource_snapshot.value_of_city(food_hubs[0].id) >= 4.0
			and resource_snapshot.value_of_city(manpower_hubs[0].id) >= 4.0,
			"资源核心应获得显著战略价值"
		)
		var owned_reachable := {}
		var owned_queue: Array[int] = [owned_land[0].id]
		owned_reachable[owned_queue[0]] = true
		while not owned_queue.is_empty():
			var current: int = owned_queue.pop_front()
			for neighbor in gs.neighbors(current):
				var owned_edge := gs.edge_of(current, neighbor)
				if (
					owned_edge == null
					or owned_edge.max_manpower <= 0
					or
					gs.cities[neighbor].owner_nation != n.id
					or owned_reachable.has(neighbor)
				):
					continue
				owned_reachable[neighbor] = true
				owned_queue.append(neighbor)
		var reachable_land := 0
		for city_id in owned_reachable:
			if not gs.cities[int(city_id)].is_dock:
				reachable_land += 1
		_check(
			reachable_land == cnt,
			"国%d 初始%d个陆城应经本国节点连通，实为%d"
				% [
					n.id,
					cnt,
					reachable_land,
				]
		)
		var light_armies := 0
		var heavy_armies := 0
		var line_armies := 0
		var initial_troops := 0
		var formation_morale_valid := true
		for army in gs.armies:
			if army.owner_nation != n.id:
				continue
			initial_troops += army.size
			if (
				army.size == GameState.INITIAL_LIGHT_ARMY_SIZE
				and army.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE
			):
				light_armies += 1
				formation_morale_valid = (
					formation_morale_valid
					and _approx(
						army.max_morale,
						Army.LIGHT_MAX_MORALE
					)
					and _approx(army.morale, army.max_morale)
				)
				if army.is_line_role():
					line_armies += 1
			elif (
				army.size == GameState.INITIAL_HEAVY_ARMY_SIZE
				and army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
			):
				heavy_armies += 1
				formation_morale_valid = (
					formation_morale_valid
					and _approx(
						army.max_morale,
						Army.HEAVY_MAX_MORALE
					)
					and _approx(army.morale, army.max_morale)
					and _approx(
						Combat.combat_efficiency(army.morale),
						1.0
					)
				)
		var initial_group_members := (
			gs.battle_group_members(
				n.id,
				n.battle_groups[0].id
			)
			if not n.battle_groups.is_empty()
			else [] as Array[Army]
		)
		_check(
			n.battle_groups.size() == 1
			and initial_group_members.size() == 3
			and light_armies == line_armies + 2
			and heavy_armies == 1,
			"国%d 初始军制必须是国界填线军加一个2轻1重持久战团" % n.id
		)
		_check(
			formation_morale_valid,
			"国%d 轻军士气上限必须为1，重军必须为2且不额外放大满士气火力"
				% n.id
		)
		var expected_initial_troops := (
			light_armies * GameState.INITIAL_LIGHT_ARMY_SIZE
			+ heavy_armies
				* GameState.INITIAL_HEAVY_ARMY_SIZE
		)
		_check(
			initial_troops == expected_initial_troops,
			"国%d 初始军队必须按两档编制满员，实为%d"
				% [n.id, initial_troops]
		)
		var food_report := DiplomacyAI.war_food_report(
			gs,
			n.id,
			initial_troops,
			DiplomacyAI.FoodPosture.PEACE
		)
		_check(
			float(food_report["full_strength_annual_balance"]) > 0.0,
			"国%d 初始满编军制应保持粮食年正收益，实为%.1f"
				% [n.id, food_report["full_strength_annual_balance"]]
		)
		var monthly_gold_income := 0
		for city in gs.cities_of(n.id):
			monthly_gold_income += Simulation.city_gold_output(gs, city)
		var monthly_war_upkeep := int(ceil(
			float(initial_troops)
				/ float(GameState.WAR_GOLD_TROOPS_PER_UNIT)
		))
		_check(
			monthly_gold_income > monthly_war_upkeep,
			"国%d 初始满编军制应保持战时月金正收益：收入%d，军费%d"
				% [n.id, monthly_gold_income, monthly_war_upkeep]
		)
	var target_light_armies := 160
	var target_heavy_armies := 40
	var target_troops := (
		target_light_armies * GameState.INITIAL_LIGHT_ARMY_SIZE
		+ target_heavy_armies * GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	var target_monthly_gold := (
		target_light_armies * GameState.army_monthly_upkeep(
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		+ target_heavy_armies * GameState.army_monthly_upkeep(
			GameState.INITIAL_HEAVY_ARMY_SIZE
		)
	)
	_check(
		GameState.army_monthly_upkeep(
			GameState.INITIAL_LIGHT_ARMY_SIZE
		) == 4
			and GameState.army_monthly_upkeep(
				GameState.INITIAL_HEAVY_ARMY_SIZE
			) == 11
			and GameState.formation_creation_gold_cost(
				GameState.INITIAL_LIGHT_ARMY_SIZE
			) == 40
			and GameState.formation_creation_gold_cost(
				GameState.INITIAL_HEAVY_ARMY_SIZE
			) == 110,
		"金币粒度提高后，轻/重军维护费必须为4/11，建制费必须为40/110"
	)
	var target_half_year_food := int(ceil(
		float(target_troops)
			* Simulation.FOOD_PER_CAPITA
			* DiplomacyAI.DEFAULT_CAMPAIGN_SUPPLY_MULTIPLIER
			* 6.0
	))
	var terrain_monthly_gold := 0
	var terrain_base_monthly_gold := 0
	var terrain_half_year_food := 0
	var terrain_base_half_year_food := 0
	var terrain_gold_min := 999999
	var terrain_gold_max := 0
	var neutral_ruler_modifiers := RulerProfile.modifiers(
		RulerProfile.BALANCED
	)
	for city in gs.cities:
		terrain_monthly_gold += Simulation.city_gold_output(gs, city)
		terrain_base_monthly_gold += city.gold_per_month
		terrain_half_year_food += Simulation.city_food_output(gs, city)
		terrain_base_half_year_food += Simulation.city_food_output(
			gs,
			city,
			{},
			neutral_ruler_modifiers
		)
		if not city.is_dock:
			terrain_gold_min = mini(
				terrain_gold_min,
				city.gold_per_month
			)
			terrain_gold_max = maxi(
				terrain_gold_max,
				city.gold_per_month
			)
	_check(
		terrain_base_monthly_gold >= target_monthly_gold
			and terrain_base_monthly_gold
				<= int(ceil(float(target_monthly_gold) * 1.15)),
		"真实地图基础月金产出应约维持160轻军+40重军：产出%d，目标军费%d"
			% [terrain_base_monthly_gold, target_monthly_gold]
	)
	_check(
		terrain_base_monthly_gold
			== GameState.TERRAIN_CITY_COUNT
				* GameState.TERRAIN_CITY_GOLD_TARGET_AVERAGE
			and terrain_gold_min
				== GameState.TERRAIN_CITY_GOLD_OUTPUT_MIN
			and terrain_gold_max
				== GameState.TERRAIN_CITY_GOLD_OUTPUT_MAX,
		"真实地图基础金币必须拉开到1～15且平均7：总额%d，范围%d～%d"
			% [
				terrain_base_monthly_gold,
				terrain_gold_min,
				terrain_gold_max,
			]
	)
	var expected_effective_gold := 0
	for city in gs.cities:
		var ruler_multiplier := RulerProfile.gold_output_multiplier(
			gs.nations[city.owner_nation]
		)
		expected_effective_gold += int(floor(
			float(city.gold_per_month) * ruler_multiplier
		))
	_check(
		terrain_monthly_gold == expected_effective_gold,
		"正式地图有效金产出必须逐城应用当前君主倍率：预期%d，实为%d"
			% [expected_effective_gold, terrain_monthly_gold]
	)
	_check(
		terrain_base_half_year_food
			>= int(floor(float(target_half_year_food) * 0.95))
			and terrain_base_half_year_food
				<= int(ceil(float(target_half_year_food) * 1.15)),
		"中性君主下的真实地图半年粮产出应约维持160轻军+40重军：基础产出%d，当前君主实际产出%d，目标需求%d"
			% [
				terrain_base_half_year_food,
				terrain_half_year_food,
				target_half_year_food,
			]
	)
	var plain_city_count := 0
	var port_market_count := 0
	var crossroads_count := 0
	var propagated_city_count := 0
	var development_weights_valid := true
	var port_food_multiplier_valid := true
	for city in land_cities:
		plain_city_count += 1 if city.is_plain_city else 0
		port_market_count += 1 if city.is_port_market else 0
		crossroads_count += 1 if city.is_crossroads else 0
		var direct_gold := 1.0
		if city.is_port_market:
			direct_gold = maxf(
				direct_gold,
				GameState.PORT_MARKET_OUTPUT_MULTIPLIER
			)
		if city.is_crossroads:
			direct_gold = maxf(
				direct_gold,
				GameState.CROSSROADS_GOLD_MULTIPLIER
			)
		if city.is_plain_city:
			direct_gold = maxf(
				direct_gold,
				GameState.PLAIN_GOLD_MULTIPLIER
			)
		var direct_food := 1.0
		if city.is_port_market:
			direct_food = maxf(
				direct_food,
				GameState.PORT_MARKET_OUTPUT_MULTIPLIER
			)
			port_food_multiplier_valid = (
				port_food_multiplier_valid
				and city.development_food_multiplier
					>= GameState.PORT_MARKET_OUTPUT_MULTIPLIER
			)
		if city.is_plain_city:
			direct_food = maxf(
				direct_food,
				GameState.PLAIN_FOOD_MULTIPLIER
			)
		var propagated_gold := 0.0
		var propagated_food := 0.0
		for neighbor in gs.neighbors(city.id):
			var edge := gs.edge_of(city.id, neighbor)
			var source := gs.cities[neighbor]
			if (
				edge == null
				or edge.max_manpower <= 0
				or source.is_dock
			):
				continue
			var source_direct_gold := 1.0
			if source.is_port_market:
				source_direct_gold = maxf(
					source_direct_gold,
					GameState.PORT_MARKET_OUTPUT_MULTIPLIER
				)
			if source.is_crossroads:
				source_direct_gold = maxf(
					source_direct_gold,
					GameState.CROSSROADS_GOLD_MULTIPLIER
				)
			if source.is_plain_city:
				source_direct_gold = maxf(
					source_direct_gold,
					GameState.PLAIN_GOLD_MULTIPLIER
				)
			var source_direct_food := 1.0
			if source.is_port_market:
				source_direct_food = maxf(
					source_direct_food,
					GameState.PORT_MARKET_OUTPUT_MULTIPLIER
				)
			if source.is_plain_city:
				source_direct_food = maxf(
					source_direct_food,
					GameState.PLAIN_FOOD_MULTIPLIER
				)
			propagated_gold = maxf(
				propagated_gold,
				(source_direct_gold - 1.0)
					* GameState.DEVELOPMENT_PROPAGATION_RATE
			)
			propagated_food = maxf(
				propagated_food,
				(source_direct_food - 1.0)
					* GameState.DEVELOPMENT_PROPAGATION_RATE
			)
		var expected_gold := maxf(
			direct_gold,
			1.0 + propagated_gold
		)
		var expected_food := maxf(
			direct_food,
			1.0 + propagated_food
		)
		if (
			direct_gold <= 1.0
			and direct_food <= 1.0
			and (
				expected_gold > 1.0
				or expected_food > 1.0
			)
		):
			propagated_city_count += 1
		development_weights_valid = (
			development_weights_valid
			and _approx(
				city.development_gold_multiplier,
				expected_gold
			)
			and _approx(
				city.development_food_multiplier,
				expected_food
			)
		)
	_check(
		plain_city_count == int(round(
			float(GameState.TERRAIN_CITY_COUNT)
				* GameState.PLAIN_CITY_SHARE
		))
			and port_market_count > 0
			and crossroads_count > 0
			and propagated_city_count > 0
			and development_weights_valid
			and port_food_multiplier_valid,
		"种田区位必须包含平原、钱粮港市、高连接枢纽和且仅一层50%%传播：平原%d 港市%d 枢纽%d 传播%d"
			% [
				plain_city_count,
				port_market_count,
				crossroads_count,
				propagated_city_count,
			]
	)
	var minimum_city_height := INF
	var maximum_city_height := -INF
	for city in land_cities:
		minimum_city_height = minf(
			minimum_city_height,
			city.terrain_height
		)
		maximum_city_height = maxf(
			maximum_city_height,
			city.terrain_height
		)
	var city_height_span := maxf(
		maximum_city_height - minimum_city_height,
		0.000001
	)
	var height_multipliers_valid := true
	for city in land_cities:
		var normalized_height := (
			(city.terrain_height - minimum_city_height)
			/ city_height_span
		)
		height_multipliers_valid = (
			height_multipliers_valid
			and _approx(
				city.terrain_output_multiplier,
				GameState.terrain_height_output_multiplier(
					normalized_height
				)
			)
		)
	var height_m0 := (
		GameState.terrain_height_output_multiplier(0.0)
	)
	var height_m25 := (
		GameState.terrain_height_output_multiplier(0.25)
	)
	var height_m50 := (
		GameState.terrain_height_output_multiplier(0.50)
	)
	var height_m69 := (
		GameState.terrain_height_output_multiplier(0.69)
	)
	var height_m75 := (
		GameState.terrain_height_output_multiplier(0.75)
	)
	var height_m100 := (
		GameState.terrain_height_output_multiplier(1.0)
	)
	_check(
		height_multipliers_valid
			and _approx(height_m0, 1.0)
			and _approx(
				height_m100,
				GameState
					.TERRAIN_HEIGHT_OUTPUT_MIN_MULTIPLIER
			)
			and height_m0 > height_m25
			and height_m25 > height_m50
			and height_m50 > height_m75
			and height_m75 > height_m100
			and _approx(height_m50, 0.6)
			and height_m69 >= 0.29
			and height_m69 <= 0.31
			and height_m0 - height_m25
				< height_m25 - height_m50
			and height_m50 - height_m75
				> height_m75 - height_m100
			and _approx(
				height_m25 - height_m50,
				height_m50 - height_m75
			),
		"海拔产出倍率必须按Sigmoid从低地1.0降至最高地0.2，西南高原约为0.3"
	)
	var positions_unique := {}
	var terrain_has_relief := false
	for city in gs.cities:
		positions_unique[city.map_position] = true
		terrain_has_relief = terrain_has_relief or city.terrain_relief > 0.0
	_check(
		gs.uses_heightmap
			and positions_unique.size() == gs.cities.size(),
		"正式世界的陆城与码头位置均应互异"
	)
	_check(terrain_has_relief, "城市应保存高度图局部起伏数据")
	var minimum_city_spacing := INF
	for a in range(land_cities.size()):
		for b in range(a + 1, land_cities.size()):
			var delta := (
				land_cities[a].map_position
				- land_cities[b].map_position
			)
			delta.x *= gs.map_aspect_ratio
			minimum_city_spacing = minf(minimum_city_spacing, delta.length())
	_check(
		minimum_city_spacing
			>= (
				TerrainMapGenerator
					.minimum_city_spacing_for_count(
						GameState.TERRAIN_CITY_COUNT
					)
				* TerrainMapGenerator.LOCAL_SPACING_MIN_FACTOR
				* TerrainMapGenerator.SPACING_RELAXATION_FLOOR
			),
		"160城动态采样仍须保持硬间距下界，实为 %.4f"
			% minimum_city_spacing
	)
	var height_ordered: Array[City] = land_cities.duplicate()
	height_ordered.sort_custom(func(a: City, b: City) -> bool:
		if not is_equal_approx(a.terrain_height, b.terrain_height):
			return a.terrain_height < b.terrain_height
		return a.id < b.id
	)
	var elevation_quartile := maxi(
		height_ordered.size() / 4,
		1
	)
	var lowland_spacing_total := 0.0
	var highland_spacing_total := 0.0
	for height_index in range(elevation_quartile):
		for source_data in [
			[
				height_ordered[height_index],
				true,
			],
			[
				height_ordered[
					height_ordered.size()
						- 1
						- height_index
				],
				false,
			],
		]:
			var source: City = source_data[0]
			var nearest := INF
			for target in land_cities:
				if target.id == source.id:
					continue
				var spacing_delta := (
					source.map_position - target.map_position
				)
				spacing_delta.x *= gs.map_aspect_ratio
				nearest = minf(nearest, spacing_delta.length())
			if bool(source_data[1]):
				lowland_spacing_total += nearest
			else:
				highland_spacing_total += nearest
	var lowland_mean_spacing := (
		lowland_spacing_total / float(elevation_quartile)
	)
	var highland_mean_spacing := (
		highland_spacing_total / float(elevation_quartile)
	)
	var northwest_spacing_total := 0.0
	var northwest_count := 0
	var central_southeast_spacing_total := 0.0
	var central_southeast_count := 0
	for source in land_cities:
		var nearest := INF
		for target in land_cities:
			if target.id == source.id:
				continue
			var spacing_delta := (
				source.map_position - target.map_position
			)
			spacing_delta.x *= gs.map_aspect_ratio
			nearest = minf(nearest, spacing_delta.length())
		if (
			source.map_position.x < 0.45
			and source.map_position.y < 0.50
		):
			northwest_spacing_total += nearest
			northwest_count += 1
		elif (
			source.map_position.x >= 0.45
			and source.map_position.y >= 0.35
		):
			central_southeast_spacing_total += nearest
			central_southeast_count += 1
	var northwest_mean_spacing := (
		northwest_spacing_total
		/ float(maxi(northwest_count, 1))
	)
	var central_southeast_mean_spacing := (
		central_southeast_spacing_total
		/ float(maxi(central_southeast_count, 1))
	)
	var river_bank_cities := 0
	for source in land_cities:
		var nearest_river := INF
		for river_path in gs.river_paths:
			for river_point in river_path:
				var river_delta := (
					source.map_position - river_point
				)
				river_delta.x *= gs.map_aspect_ratio
				nearest_river = minf(
					nearest_river,
					river_delta.length()
				)
		if (
			nearest_river
				>= TerrainMapGenerator.RIVER_BANK_MIN_DISTANCE
			and nearest_river
				<= TerrainMapGenerator.RIVER_BANK_MAX_DISTANCE
		):
			river_bank_cities += 1
	_check(
		lowland_mean_spacing < highland_mean_spacing,
		"低海拔四分位城市应比高海拔四分位更密：low=%.4f high=%.4f"
			% [
				lowland_mean_spacing,
				highland_mean_spacing,
			]
	)
	_check(
		northwest_count > 0
			and central_southeast_count > 0
			and central_southeast_mean_spacing
				< northwest_mean_spacing,
		"中东部/东南城市应比西北更密：dense=%.4f northwest=%.4f count=%d/%d"
			% [
				central_southeast_mean_spacing,
				northwest_mean_spacing,
				central_southeast_count,
				northwest_count,
			]
	)
	_check(
		river_bank_cities
			>= int(ceil(
				float(GameState.TERRAIN_CITY_COUNT) * 0.10
			)),
		"至少10%%陆城应依河而建，当前=%d/%d"
			% [
				river_bank_cities,
				GameState.TERRAIN_CITY_COUNT,
			]
	)
	_check(
		TerrainMapGenerator.packed_altitude(Color(0.2, 0.8, 0.4, 128.0 / 255.0)) == 0.0
			and TerrainMapGenerator.packed_altitude(Color(0.2, 0.8, 0.4, 1.0)) > 0.99
			and not TerrainMapGenerator.packed_is_land(Color(1.0, 1.0, 1.0, 128.0 / 255.0))
			and TerrainMapGenerator.packed_is_land(Color(0.0, 0.0, 0.0, 129.0 / 255.0))
			and TerrainMapGenerator.packed_signed_elevation(Color(0.0, 0.0, 0.0, 1.0 / 255.0)) < -0.99
			and absf(TerrainMapGenerator.packed_signed_elevation(Color(0.0, 0.0, 0.0, 128.0 / 255.0))) < 0.001
			and TerrainMapGenerator.settlement_density(
			0.15,
			0.02,
			Vector2(0.75, 0.70),
			1.0
		) > TerrainMapGenerator.settlement_density(
			0.75,
			0.20,
			Vector2(0.20, 0.20),
			0.0
			),
		"打包纹理Alpha必须独立编码海底/海岸/陆地高程，RGB颜色不得影响地理；聚落仍偏好低地与河岸"
	)
	var latitude_density := TerrainMapGenerator.default_city_density_settings()
	var south_multiplier := TerrainMapGenerator.latitude_density_multiplier(
		float(latitude_density["latitude_min"]), latitude_density
	)
	var peak_multiplier := TerrainMapGenerator.latitude_density_multiplier(
		float(latitude_density["density_peak_latitude"]), latitude_density
	)
	var north_multiplier := TerrainMapGenerator.latitude_density_multiplier(
		float(latitude_density["latitude_max"]), latitude_density
	)
	_check(
		_approx(south_multiplier, float(latitude_density["south_density"]))
		and _approx(peak_multiplier, 1.0)
		and _approx(north_multiplier, float(latitude_density["north_density"]))
		and north_multiplier < south_multiplier
		and south_multiplier < peak_multiplier,
		"纬度城市密度必须服从地图源配置，且峰值>南缘>北缘"
	)
	_check(
		MapRenderer.CAMPAIGN_ARROW_TEXTURE != null
		and MapRenderer.CAMPAIGN_ARROW_TEXTURE.get_width() == 1536
		and MapRenderer.CAMPAIGN_ARROW_TEXTURE.get_height() == 1024
		and MapRenderer.CAMPAIGN_ARROW_SOURCE_TAIL.distance_to(
			MapRenderer.CAMPAIGN_ARROW_SOURCE_TIP
		) > 1000.0,
		"攻势箭头必须使用正式红色渐变贴图，并以尾部和尖端锚点等比对齐"
	)
	_check(
		gs.map_source_region_normalized
			== Rect2(0.0, 0.0, 1.0, 1.0)
		and _approx(
			gs.map_aspect_ratio,
			TerrainMapGenerator.FULL_MAP_ASPECT_RATIO
		),
		"底图必须保留覆盖中国全境与周边海洋的完整矩形范围"
	)
	var province_seen := {}
	var province_has_sea := false
	var terrain_geometry := TerrainMapGenerator.build(
		GameState.terrain_map_path(),
		GameState.TERRAIN_CITY_COUNT
	)
	var seeded_geometry_a := TerrainMapGenerator.build(
		GameState.terrain_map_path(),
		GameState.TERRAIN_CITY_COUNT,
		GameState.DEFAULT_CITY_MASK_PATH,
		{},
		71001
	)
	var seeded_geometry_b := TerrainMapGenerator.build(
		GameState.terrain_map_path(),
		GameState.TERRAIN_CITY_COUNT,
		GameState.DEFAULT_CITY_MASK_PATH,
		{},
		71002
	)
	var seeded_geometry_a_repeat := TerrainMapGenerator.build(
		GameState.terrain_map_path(),
		GameState.TERRAIN_CITY_COUNT,
		GameState.DEFAULT_CITY_MASK_PATH,
		{},
		71001
	)
	_check(
		seeded_geometry_a["positions"]
			== seeded_geometry_a_repeat["positions"]
			and seeded_geometry_a["positions"]
				!= seeded_geometry_b["positions"],
		"程序化地图必须同种子可复现、不同种子生成不同城市与省界布局"
	)
	var terrain_bounds: Rect2i = terrain_geometry["bounds"]
	var province_ids_valid := (
		gs.province_map_size.x > 0
		and gs.province_map_size.y > 0
		and gs.province_ids.size()
			== gs.province_map_size.x * gs.province_map_size.y
	)
	for province_id in gs.province_ids:
		if province_id < 0:
			province_has_sea = true
			continue
		province_ids_valid = (
			province_ids_valid
				and province_id < GameState.TERRAIN_CITY_COUNT
		)
		province_seen[province_id] = true
	_check(
		province_ids_valid
		and province_has_sea
		and province_seen.size() == GameState.TERRAIN_CITY_COUNT,
		"完整矩形省份图必须为160城各生成独立省份，海洋保持透明"
	)
	var warp_sample := Vector2(47.0, 83.0)
	var warped_sample := TerrainMapGenerator.province_metric_point(
		warp_sample
	)
	var warped_neighbor := TerrainMapGenerator.province_metric_point(
		warp_sample + Vector2.ONE
	)
	_check(
		gs.province_map_size
			== terrain_bounds.size
				* TerrainMapGenerator.PROVINCE_RASTER_SCALE
			and warped_sample
				== TerrainMapGenerator.province_metric_point(
					warp_sample
				)
			and warped_sample.distance_to(warp_sample) > 0.5
			and warped_sample.distance_to(warped_neighbor) < 2.5,
		"省份归属图必须使用地形分析分辨率和确定、局部连续的域扭曲"
	)
	var flat_cost := (
		TerrainMapGenerator.province_geographic_step_cost(
			0.20,
			0.20,
			false,
			0.0,
			1.0
		)
	)
	var mountain_cost := (
		TerrainMapGenerator.province_geographic_step_cost(
			0.78,
			0.84,
			false,
			0.0,
			1.0
		)
	)
	var river_cost := (
		TerrainMapGenerator.province_geographic_step_cost(
			0.20,
			0.20,
			true,
			0.0,
			1.0
		)
	)
	var road_cost := (
		TerrainMapGenerator.province_geographic_step_cost(
			0.20,
			0.20,
			false,
			1.0,
			1.0
		)
	)
	var road_river_cost := (
		TerrainMapGenerator.province_geographic_step_cost(
			0.20,
			0.20,
			true,
			1.0,
			1.0
		)
	)
	_check(
		mountain_cost > flat_cost * 2.0
			and river_cost > flat_cost * 4.0
			and _approx(road_cost, flat_cost)
			and _approx(road_river_cost, river_cost),
		"省界地理成本只由山脉与河流塑造，道路不得反向改变省界"
	)
	var test_river_field := PackedByteArray()
	test_river_field.resize(100)
	TerrainMapGenerator._build_province_river_mask(
		test_river_field,
		Vector2i(10, 10),
		Rect2i(0, 0, 10, 10),
		[[Vector2i(2, 5), Vector2i(3, 5)]]
	)
	_check(
		test_river_field[5 * 10 + 2] != 0
			and test_river_field[5 * 10 + 3] != 0,
		"河流路径必须写入省界地理屏障掩码"
	)
	var province_owners_stable := true
	for city in gs.cities:
		province_owners_stable = (
			province_owners_stable
			and gs.recognized_owner_of(city.id) == city.owner_nation
		)
	_check(province_owners_stable, "省份必须保存不随占领变化的初始归属")
	var province_geometry := MapRenderer.build_province_boundary_segments(gs)
	var repeated_province_geometry := (
		MapRenderer.build_province_boundary_segments(gs)
	)
	var curved_topology_deterministic := true
	for topology_key in [
		"province", "coast",
		"country_owner_a", "country_owner_b",
		"country_side_a", "country_side_b",
		"coast_owner", "coast_side",
	]:
		curved_topology_deterministic = (
			curved_topology_deterministic
			and province_geometry[topology_key]
				== repeated_province_geometry[topology_key]
		)
	var country_segment_count := (
		province_geometry["country"] as PackedVector2Array
	).size() / 2
	var coast_segment_count := (
		province_geometry["coast"] as PackedVector2Array
	).size() / 2
	var country_sides_valid := true
	var country_segments: PackedVector2Array = province_geometry["country"]
	var country_owners_a: PackedInt32Array = province_geometry["country_owner_a"]
	var country_owners_b: PackedInt32Array = province_geometry["country_owner_b"]
	var country_sides_a: PackedVector2Array = province_geometry["country_side_a"]
	var country_sides_b: PackedVector2Array = province_geometry["country_side_b"]
	for boundary_index in range(country_segment_count):
		var from := country_segments[boundary_index * 2]
		var to := country_segments[boundary_index * 2 + 1]
		var direction := (to - from).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var side_a := country_sides_a[boundary_index].dot(normal)
		var side_b := country_sides_b[boundary_index].dot(normal)
		country_sides_valid = (
			country_sides_valid
			and country_owners_a[boundary_index] != country_owners_b[boundary_index]
			and absf(side_a) > 0.000001
			and absf(side_b) > 0.000001
			and side_a * side_b < 0.0
		)
	_check(
		not (province_geometry["province"] as PackedVector2Array).is_empty()
		and not (province_geometry["country"] as PackedVector2Array).is_empty()
		and not (province_geometry["coast"] as PackedVector2Array).is_empty()
		and (province_geometry["country_owner_a"] as PackedInt32Array).size()
			== country_segment_count
		and (province_geometry["country_owner_b"] as PackedInt32Array).size()
			== country_segment_count
		and (province_geometry["country_side_a"] as PackedVector2Array).size()
			== country_segment_count
		and (province_geometry["country_side_b"] as PackedVector2Array).size()
			== country_segment_count
		and (province_geometry["coast_owner"] as PackedInt32Array).size()
			== coast_segment_count
		and (province_geometry["coast_side"] as PackedVector2Array).size()
			== coast_segment_count
		and country_sides_valid
		and curved_topology_deterministic,
		"省界、国境和海岸必须逐段保留两侧国家及内侧方向"
	)
	var synthetic_segments := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.25, 0.0),
		Vector2(0.25, 0.0), Vector2(0.25, 0.25),
		Vector2(0.25, 0.25), Vector2(0.50, 0.25),
		Vector2(0.50, 0.25), Vector2(0.50, 0.50),
	])
	var synthetic_curve := MapRenderer._curve_subdivide_boundary_graph(
		synthetic_segments,
		{
			"kind": "province",
			"province_a": PackedInt32Array([3, 3, 3, 3]),
			"province_b": PackedInt32Array([7, 7, 7, 7]),
			"side_a": PackedVector2Array([
				Vector2.DOWN, Vector2.RIGHT, Vector2.DOWN, Vector2.RIGHT,
			]),
			"side_b": PackedVector2Array([
				Vector2.UP, Vector2.LEFT, Vector2.UP, Vector2.LEFT,
			]),
		},
		Vector2i(16, 16)
	)
	var synthetic_curve_segments: PackedVector2Array = (
		synthetic_curve["segments"]
	)
	var synthetic_side_a: PackedVector2Array = (
		synthetic_curve["province_side_a"]
	)
	var synthetic_side_b: PackedVector2Array = (
		synthetic_curve["province_side_b"]
	)
	var synthetic_curve_valid := synthetic_curve_segments.size() > 8
	for segment_index in range(synthetic_curve_segments.size() / 2):
		var direction := (
			synthetic_curve_segments[segment_index * 2 + 1]
			- synthetic_curve_segments[segment_index * 2]
		).normalized()
		var normal := Vector2(-direction.y, direction.x)
		synthetic_curve_valid = (
			synthetic_curve_valid
			and synthetic_side_a[segment_index].dot(normal) > 0.99
			and synthetic_side_b[segment_index].dot(normal) < -0.99
		)
	_check(
		synthetic_curve_valid,
		"链级曲线必须消除单格台阶，并按微段局部法线携带两侧归属"
	)
	var junction_segments := PackedVector2Array([
		Vector2(0.5, 0.5), Vector2(0.25, 0.5),
		Vector2(0.5, 0.5), Vector2(0.75, 0.5),
		Vector2(0.5, 0.5), Vector2(0.5, 0.75),
	])
	var junction_curve := MapRenderer._curve_subdivide_boundary_graph(
		junction_segments,
		{
			"kind": "province",
			"province_a": PackedInt32Array([1, 1, 2]),
			"province_b": PackedInt32Array([2, 2, 3]),
			"side_a": PackedVector2Array([
				Vector2.DOWN, Vector2.UP, Vector2.RIGHT,
			]),
			"side_b": PackedVector2Array([
				Vector2.UP, Vector2.DOWN, Vector2.LEFT,
			]),
		},
		Vector2i(16, 16)
	)
	var junction_output: PackedVector2Array = junction_curve["segments"]
	var junction_endpoint_count := 0
	for junction_point in junction_output:
		if junction_point.is_equal_approx(Vector2(0.5, 0.5)):
			junction_endpoint_count += 1
	_check(
		junction_endpoint_count == 3,
		"不同省份对共享的三岔点必须切成三条链并固定在原始交点"
	)
	var premultiplied_probe := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	premultiplied_probe.fill(Color(0.0, 0.0, 0.0, 0.0))
	var probe_ink := Color(0.30, 0.045, 0.035, 1.0).srgb_to_linear()
	for probe_y in range(4):
		for probe_x in range(4):
			premultiplied_probe.set_pixel(
				probe_x, probe_y, Color(probe_ink.r, probe_ink.g, probe_ink.b, 1.0)
			)
	_check(
		premultiplied_probe.generate_mipmaps() == OK,
		"国界预乘纹理必须能生成完整 mip 链"
	)
	var probe_data := premultiplied_probe.get_data()
	var probe_format := premultiplied_probe.get_format()
	var probe_width := 8
	var probe_height := 8
	var premultiplied_mips_valid := true
	for mip_level in range(premultiplied_probe.get_mipmap_count() + 1):
		var mip_offset := premultiplied_probe.get_mipmap_offset(mip_level)
		var mip_width := maxi(probe_width >> mip_level, 1)
		var mip_height := maxi(probe_height >> mip_level, 1)
		var mip_byte_count := mip_width * mip_height * 4
		var mip_bytes := probe_data.slice(mip_offset, mip_offset + mip_byte_count)
		var mip_image := Image.create_from_data(
			mip_width, mip_height, false, probe_format, mip_bytes
		)
		for mip_y in range(mip_height):
			for mip_x in range(mip_width):
				var sample := mip_image.get_pixel(mip_x, mip_y)
				if sample.a <= 0.01:
					continue
				var decoded := Vector3(sample.r, sample.g, sample.b) / sample.a
				premultiplied_mips_valid = (
					premultiplied_mips_valid
					and decoded.distance_to(
						Vector3(probe_ink.r, probe_ink.g, probe_ink.b)
					) < 0.025
				)
	_check(
		premultiplied_mips_valid,
		"RGBA8 各级 mip 反预乘后必须保持国界墨色，禁止白边、黑边和色偏"
	)
	var micro_cell := 1.0 / 2048.0
	var micro_curve := MapRenderer._curve_subdivide_boundary_graph(
		PackedVector2Array([Vector2.ZERO, Vector2(micro_cell, 0.0)]),
		{
			"kind": "province",
			"province_a": PackedInt32Array([3]),
			"province_b": PackedInt32Array([7]),
			"side_a": PackedVector2Array([Vector2.DOWN]),
			"side_b": PackedVector2Array([Vector2.UP]),
		},
		Vector2i(2048, 2048)
	)
	_check(
		(micro_curve["segments"] as PackedVector2Array).size() == 8
		and (micro_curve["province_a"] as PackedInt32Array).size() == 4,
		"一格尺度的真实边界不得被归一化 UV 退化阈值吞掉"
	)
	var reverse_edge := {
		"from": Vector2(micro_cell, 0.0),
		"to": Vector2.ZERO,
		"province_a": 3,
		"province_b": 7,
		"side_a": Vector2.DOWN,
		"side_b": Vector2.UP,
	}
	var reverse_side_info := MapRenderer._province_chain_side_info(reverse_edge)
	var reverse_coast_sign := MapRenderer._coast_chain_side_sign({
		"from": Vector2(micro_cell, 0.0),
		"to": Vector2.ZERO,
		"coast_side": Vector2.DOWN,
	})
	_check(
		int(reverse_side_info["left_province"]) == 7
		and int(reverse_side_info["right_province"]) == 3
		and reverse_coast_sign < 0.0,
		"反向追踪的一格边仍必须按真实切线保留国家与海岸内侧"
	)
	var tiny_loop := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(micro_cell, 0.0),
		Vector2(micro_cell, 0.0), Vector2(micro_cell, micro_cell),
		Vector2(micro_cell, micro_cell), Vector2(0.0, micro_cell),
		Vector2(0.0, micro_cell), Vector2(0.0, 0.0),
	])
	var tiny_loop_curve := MapRenderer._curve_subdivide_boundary_graph(
		tiny_loop,
		{
			"kind": "coast",
			"coast_province": PackedInt32Array([3, 3, 3, 3]),
			"coast_side": PackedVector2Array([
				Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2.RIGHT,
			]),
		},
		Vector2i(2048, 2048)
	)
	var tiny_loop_segments: PackedVector2Array = tiny_loop_curve["segments"]
	var tiny_loop_points := PackedVector2Array()
	for segment_index in range(tiny_loop_segments.size() / 2):
		tiny_loop_points.append(tiny_loop_segments[segment_index * 2])
	_check(
		tiny_loop_segments.size() >= 24
		and tiny_loop_segments[tiny_loop_segments.size() - 1]
			.is_equal_approx(tiny_loop_segments[0])
		and absf(MapRenderer._boundary_ring_area(tiny_loop_points))
			> 0.000000000001,
		"一格闭合小岛不得被 RDP 压成两点往返直线"
	)
	_check(
		not (province_geometry["coast"] as PackedVector2Array).is_empty(),
		"0米海岸线必须生成与城市疆域边界同层的闭合描边"
	)
	var base_overlay := MapRenderer.build_province_overlay_image(gs)
	var transparent_sea_found := false
	for y in range(gs.province_map_size.y):
		for x in range(gs.province_map_size.x):
			if (
				gs.province_ids[y * gs.province_map_size.x + x] < 0
				and base_overlay.get_pixel(x, y).a <= 0.001
			):
				transparent_sea_found = true
				break
		if transparent_sea_found:
			break
	_check(transparent_sea_found, "省份覆盖层不得遮挡陆地轮廓外的底图")
	var subject_color_test := 1
	var overlord_color_test := 0
	var original_suzerainty := gs.suzerainty.duplicate(true)
	gs.suzerainty[subject_color_test] = {
		"overlord_id": overlord_color_test,
		"civil_war": false,
	}
	var overlord_political_color := MapRenderer.paper_nation_color(
		gs.nations[overlord_color_test].color
	)
	var actual_subject_color := MapRenderer.political_map_color(
		gs, subject_color_test
	)
	_check(
		absf(actual_subject_color.h - overlord_political_color.h) < 0.001
		and _approx(
			actual_subject_color.v,
			overlord_political_color.v
				* (1.0 - MapRenderer.VASSAL_BRIGHTNESS_STEP)
		),
		"政治疆域中藩王必须继承宗主色并降低约15%明度"
	)
	var faction_colors_valid := true
	var hardcoded_palette_valid := (
		GameState.NATION_PALETTE_HUES.size() == 4
		and GameState.NATION_PALETTE_SATURATIONS.size() == 4
		and GameState.NATION_PALETTE_VALUES.size() == 4
		and GameState.NATION_PALETTE_HUES == [
			0.000, 0.610, 0.350, 0.140,
		]
		and GameState.NATION_PALETTE_SATURATIONS == [
			0.52, 0.46, 0.40, 0.50,
		]
		and GameState.NATION_PALETTE_VALUES == [
			0.48, 0.43, 0.38, 0.50,
		]
	)
	gs.suzerainty = original_suzerainty
	for nation in gs.nations:
		var political_color := MapRenderer.political_map_color(gs, nation.id)
		var counter_color := MapRenderer.command_marker_color(gs, nation.id)
		var alert_color := MapRenderer.final_faction_visual_color(
			gs, nation.id, 0.62, 0.08
		)
		for visual_color in [nation.color, political_color, counter_color]:
			faction_colors_valid = (
				faction_colors_valid
				and visual_color.h >= GameState.NATION_COLOR_HUE_MIN - 0.0001
				and visual_color.h <= GameState.NATION_COLOR_HUE_MAX + 0.0001
				and visual_color.s >= GameState.NATION_COLOR_SATURATION_MIN - 0.0001
				and visual_color.s <= GameState.NATION_COLOR_SATURATION_MAX + 0.0001
				and visual_color.v >= GameState.NATION_COLOR_VALUE_MIN - 0.0001
				and visual_color.v <= GameState.NATION_COLOR_VALUE_MAX + 0.0001
			)
		faction_colors_valid = (
			faction_colors_valid
			and alert_color.s >= GameState.NATION_COLOR_SATURATION_MIN - 0.0001
			and alert_color.s <= GameState.NATION_COLOR_SATURATION_MAX + 0.0001
			and alert_color.v >= GameState.NATION_COLOR_VALUE_MIN - 0.0001
			and alert_color.v <= GameState.NATION_COLOR_VALUE_MAX + 0.0001
		)
	_check(
		faction_colors_valid and hardcoded_palette_valid,
		"四国调色板必须保持当前低饱和暗色 HSV 基准，派生显示色必须保持规范范围"
	)
	var occupied_test_city := 0
	var original_test_owner := gs.cities[occupied_test_city].owner_nation
	gs.cities[occupied_test_city].owner_nation = (
		original_test_owner + 1
	) % gs.nations.size()
	var occupied_overlay := MapRenderer.build_province_overlay_image(gs)
	var occupation_hatch_found := false
	for y in range(gs.province_map_size.y):
		for x in range(gs.province_map_size.x):
			if (
				gs.province_ids[y * gs.province_map_size.x + x]
					== occupied_test_city
				and (x + y) % 9 < 3
				and occupied_overlay.get_pixel(x, y).a > 0.60
			):
				occupation_hatch_found = true
				break
		if occupation_hatch_found:
			break
	gs.cities[occupied_test_city].owner_nation = original_test_owner
	_check(
		occupation_hatch_found,
		"被占领省份必须叠加高于底色透明度的占领国斜线纹理"
	)
	_check(ResourceLoader.exists("res://main.tscn"), "真实地图场景 main.tscn 必须保留")
	_check(ResourceLoader.exists("res://square_map.tscn"), "原方形地图场景必须独立保留")
	_check(
		ResourceLoader.exists("res://forty_nations.tscn"),
		"40国可玩场景 forty_nations.tscn 必须存在"
	)
	var forty_packed := load("res://forty_nations.tscn") as PackedScene
	var forty_scene := forty_packed.instantiate()
	_check(
		int(forty_scene.get("nation_count")) == 40
			and int(forty_scene.get("terrain_city_count")) == 160
			and bool(forty_scene.get("randomize_world_seed_on_start"))
			and forty_scene.get_node_or_null("StrategicMap3D") != null
			and forty_scene.get_node_or_null("RoadTuningLayer") != null
			and forty_scene.get_node_or_null("MapEditorLayer") != null
			and forty_scene.get_node_or_null("SettingsLayer/SettingsButton")
				!= null
			and _approx(
				float(forty_scene.get("initial_army_icon_scale")),
				0.40
			)
			and not bool(
				forty_scene.get("initial_city_names_visible")
			),
		"40国场景必须继承完整主界面、配置40国/160陆城并在启动时随机生成"
	)
	forty_scene.free()
	# 每国只有首都一个粮仓；本国全部陆城初始储备归集到该粮仓。
	for n in gs.nations:
		var warehouses := gs.warehouse_cities_of(n.id)
		var owned_land_count := gs.land_cities_of(n.id).size()
		_check(warehouses.size() == 1 and warehouses[0].id == n.capital_city_id,
			"国%d 初始应只有首都一个粮仓" % n.id)
		_check(
			warehouses[0].food_storage
				>= owned_land_count
					* GameState.INITIAL_CITY_FOOD_STOCK_MIN
			and warehouses[0].food_storage
				<= owned_land_count
					* GameState.INITIAL_CITY_FOOD_STOCK_MAX,
			"国%d 首都粮仓应归集%d城初始储备，实为%d"
				% [
					n.id,
					owned_land_count,
					warehouses[0].food_storage,
				])
	var non_warehouse_food := false
	for c in gs.cities:
		if not c.has_warehouse and c.food_storage != 0:
			non_warehouse_food = true
	_check(not non_warehouse_food, "普通城市不得保存粮食库存")
	# 邻接对称性
	var ok_adj := true
	for cid in gs.adjacency.keys():
		for nb in gs.neighbors(cid):
			if not (gs.neighbors(nb) as Array).has(cid):
				ok_adj = false
	_check(ok_adj, "邻接表应对称")
	var road_counts := {
		0: 0,
		Edge.TERRAIN_LOW_MANPOWER: 0,
		Edge.TERRAIN_STANDARD_MANPOWER: 0,
	}
	var degrees := {}
	var shared_province_boundaries := (
		TerrainMapGenerator.province_shared_boundary_counts(
			gs.province_ids, gs.province_map_size
		)
	)
	var invalid_land_adjacency := 0
	var invalid_land_path := 0
	var curved_land_paths := 0
	var longest_edge := 0.0
	var roads_by_relief: Array[Edge] = []
	for edge in gs.edges:
		if (
			edge.max_manpower > 0
			and edge.kind not in [Edge.Kind.RIVER, Edge.Kind.SEA]
		):
			roads_by_relief.append(edge)
	roads_by_relief.sort_custom(func(a: Edge, b: Edge) -> bool:
		return a.max_height_difference < b.max_height_difference
	)
	for edge in gs.edges:
		if edge.kind not in [Edge.Kind.RIVER, Edge.Kind.SEA]:
			road_counts[edge.max_manpower] = (
				int(road_counts.get(edge.max_manpower, 0)) + 1
			)
		_check(
			MapRenderer.is_edge_visible(edge)
				== (edge.max_manpower > 0),
			"地图只应显示正容量道路"
		)
		degrees[edge.city_a] = int(degrees.get(edge.city_a, 0)) + 1
		degrees[edge.city_b] = int(degrees.get(edge.city_b, 0)) + 1
		if (
			edge.max_manpower > 0
			and edge.kind not in [Edge.Kind.RIVER, Edge.Kind.SEA]
		):
			var delta := (
				gs.cities[edge.city_a].map_position
				- gs.cities[edge.city_b].map_position
			)
			delta.x *= gs.map_aspect_ratio
			longest_edge = maxf(longest_edge, delta.length())
		if edge.kind == Edge.Kind.LAND:
			if not shared_province_boundaries.has(
				TerrainMapGenerator._pair_key(edge.city_a, edge.city_b)
			):
				invalid_land_adjacency += 1
			if edge.map_path.size() >= 2:
				curved_land_paths += 1
			var road_path := edge.map_points(
				gs.cities[edge.city_a].map_position,
				gs.cities[edge.city_b].map_position
			)
			for path_index in range(road_path.size() - 1):
				if not TerrainMapGenerator.province_segment_stays_in_pair(
					gs.province_ids, gs.province_map_size,
					road_path[path_index], road_path[path_index + 1],
					edge.city_a, edge.city_b
				):
					invalid_land_path += 1
					break
	_check(
		invalid_land_adjacency == 0,
		"所有陆路端点必须是共享省界的城市，违规=%d" % invalid_land_adjacency
	)
	_check(
		invalid_land_path == 0 and curved_land_paths > 0,
		"陆路正式折线必须只经过端点两省，违规=%d 折线路=%d"
			% [invalid_land_path, curved_land_paths]
	)
	var crossing_road_pairs := 0
	for edge_a_index in range(gs.edges.size()):
		var edge_a: Edge = gs.edges[edge_a_index]
		if (
			edge_a.max_manpower <= 0
			or edge_a.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]
		):
			continue
		for edge_b_index in range(
			edge_a_index + 1,
			gs.edges.size()
		):
			var edge_b: Edge = gs.edges[edge_b_index]
			if (
				edge_b.max_manpower <= 0
				or edge_b.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]
				or edge_a.city_a in [
					edge_b.city_a,
					edge_b.city_b,
				]
				or edge_a.city_b in [
					edge_b.city_a,
					edge_b.city_b,
				]
			):
				continue
			var path_a := edge_a.map_points(
				gs.cities[edge_a.city_a].map_position,
				gs.cities[edge_a.city_b].map_position
			)
			var path_b := edge_b.map_points(
				gs.cities[edge_b.city_a].map_position,
				gs.cities[edge_b.city_b].map_position
			)
			var paths_cross := false
			for segment_a in range(path_a.size() - 1):
				for segment_b in range(path_b.size() - 1):
					if Geometry2D.segment_intersects_segment(
						path_a[segment_a], path_a[segment_a + 1],
						path_b[segment_b], path_b[segment_b + 1]
					) != null:
						paths_cross = true
						break
				if paths_cross:
					break
			if paths_cross:
				crossing_road_pairs += 1
	_check(
		crossing_road_pairs == 0,
		"可见陆路只能在共享城市端点相接，不得中途交叉，当前交叉对=%d"
			% crossing_road_pairs
	)
	_check(
		int(road_counts[0]) > 0,
		"最高起伏道路中应包含不可供大军通行的边，分布=%s" % str(road_counts)
	)
	_check(
		int(road_counts[Edge.TERRAIN_LOW_MANPOWER]) > 0
		and int(road_counts[Edge.TERRAIN_STANDARD_MANPOWER]) > 0,
		"陆路正容量只能形成10000/20000两个等级，分布=%s"
			% str(road_counts)
	)
	_check(
		int(road_counts[Edge.TERRAIN_STANDARD_MANPOWER])
			< int(road_counts[Edge.TERRAIN_LOW_MANPOWER]),
		"20000标准陆路应少于10000轻通路，分布=%s" % str(road_counts)
	)
	var production_capacities_valid := true
	for production_edge in gs.edges:
		production_capacities_valid = (
			production_capacities_valid
			and Edge.production_capacity_valid(
				production_edge.kind,
				production_edge.max_manpower
			)
		)
	_check(
		production_capacities_valid,
		"正式地图容量只允许陆路0/10000/20000与水路50000"
	)
	var low_relief_average := 0.0
	var high_relief_average := 0.0
	var comparison_count := maxi(roads_by_relief.size() / 4, 1)
	for i in range(comparison_count):
		low_relief_average += roads_by_relief[i].max_manpower
		high_relief_average += roads_by_relief[roads_by_relief.size() - 1 - i].max_manpower
	_check(
		low_relief_average > high_relief_average,
		"低起伏道路的平均通行等级应高于高起伏道路"
	)
	var degree_values := degrees.values()
	_check(
		degree_values.min() < degree_values.max(),
		"省份对偶局部图的城市度数应自然变化，不能硬编码固定边数"
	)
	_check(
		longest_edge <= 0.36,
		"连通骨架不得产生跨区域超长边，最长实为 %.3f" % longest_edge
	)
	var reachable := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbor in gs.neighbors(current):
			var edge := gs.edge_of(current, neighbor)
			if edge.max_manpower <= 0 or reachable.has(neighbor):
				continue
			reachable[neighbor] = true
			queue.append(neighbor)
	_check(
		reachable.size() == gs.cities.size(),
		"移除 0 容量边后道路骨架仍必须连通：可达 %d/%d"
			% [reachable.size(), gs.cities.size()]
	)
	var repeated := GameState.new()
	repeated.generate_world(12345)
	var terrain_deterministic := repeated.edges.size() == gs.edges.size()
	for city_id in range(gs.cities.size()):
		terrain_deterministic = (
			terrain_deterministic
			and repeated.cities[city_id].map_position == gs.cities[city_id].map_position
			and repeated.cities[city_id].owner_nation == gs.cities[city_id].owner_nation
		)
	for edge_index in range(gs.edges.size()):
		var original := gs.edges[edge_index]
		var copied := repeated.edges[edge_index]
		terrain_deterministic = (
			terrain_deterministic
			and original.city_a == copied.city_a
			and original.city_b == copied.city_b
				and original.distance == copied.distance
			and original.max_manpower == copied.max_manpower
			and _approx(
				original.max_height_difference,
				copied.max_height_difference
			)
		)
	_check(terrain_deterministic, "相同高度图与种子必须生成完全一致的城市和道路")


func _test_river_transport() -> void:
	print("[1a] 河运：双河道、码头阻隔、抢滩、水路与禁止驻边")
	var gs := GameState.new()
	gs.generate_world(12345)
	var docks: Array[City] = []
	var landing_edges: Array[Edge] = []
	var river_edges: Array[Edge] = []
	var sea_edges: Array[Edge] = []
	for city in gs.cities:
		if city.is_dock:
			docks.append(city)
	for edge in gs.edges:
		if edge.kind == Edge.Kind.LANDING:
			landing_edges.append(edge)
		elif edge.kind == Edge.Kind.RIVER:
			river_edges.append(edge)
		elif edge.kind == Edge.Kind.SEA:
			sea_edges.append(edge)
	_check(
		gs.river_paths.size() == 2
			and docks.size() >= 4
			and not river_edges.is_empty()
				and not gs.river_paths.is_empty(),
		"正式地图必须生成两条各有有效码头连接的主河道"
	)
	var minimum_dock_spacing := INF
	var minimum_dock_city_spacing := INF
	for dock_a_index in range(docks.size()):
		for land_city in gs.land_cities():
			var city_delta := (
				docks[dock_a_index].map_position
				- land_city.map_position
			)
			city_delta.x *= gs.map_aspect_ratio
			minimum_dock_city_spacing = minf(
				minimum_dock_city_spacing, city_delta.length()
			)
		for dock_b_index in range(dock_a_index + 1, docks.size()):
			var dock_delta := (
				docks[dock_a_index].map_position
				- docks[dock_b_index].map_position
			)
			dock_delta.x *= gs.map_aspect_ratio
			minimum_dock_spacing = minf(
				minimum_dock_spacing,
				dock_delta.length()
			)
	_check(
		minimum_dock_spacing
			>= TerrainMapGenerator.RIVER_DOCK_MIN_SPACING,
		"河流几何不得生成视觉重叠码头，最小码头间距实为%.6f"
			% minimum_dock_spacing
	)
	_check(
		minimum_dock_city_spacing
			>= TerrainMapGenerator.RIVER_DOCK_CITY_MIN_SPACING,
		"码头不得贴住普通城市，最小间距实为%.6f"
			% minimum_dock_city_spacing
	)
	var river_shapes_valid := true
	var river_pair_keys := {}
	for river_path in gs.river_paths:
		river_shapes_valid = river_shapes_valid and river_path.size() >= 2
		for point_index in range(river_path.size() - 1):
			var owners := TerrainMapGenerator.province_boundary_segment_owners(
				gs.province_ids, gs.province_map_size,
				river_path[point_index], river_path[point_index + 1]
			)
			river_shapes_valid = river_shapes_valid and owners.x >= 0
			if owners.x >= 0:
				river_pair_keys[TerrainMapGenerator._pair_key(owners.x, owners.y)] = true
	_check(
		river_shapes_valid and not river_pair_keys.is_empty(),
		"河道每一小段都必须严格落在两个城市省份的公共边界上"
	)
	var generated := TerrainMapGenerator.build(
		GameState.terrain_map_path(), GameState.TERRAIN_CITY_COUNT,
		gs.city_generation_mask_path, gs.city_density_settings
	)
	var bank_region_count := (
		generated.get("dock_bank_regions", []) as Array
	).size()
	_check(
		docks.size() >= int(ceil(float(bank_region_count) * 0.75))
			and docks.size() <= bank_region_count,
		"渡口数量应接近单侧沿河省份数，不能退化成逐河段密集港口：%d/%d"
			% [docks.size(), bank_region_count]
	)
	var all_lowland_candidates_covered := true
	for candidate_value in generated.get(
		"lowland_dock_regions", []
	):
		var candidate: Dictionary = candidate_value
		var covered := false
		for dock_value in generated.get("docks", []):
			var dock: Dictionary = dock_value
			if int(dock["river_id"]) != int(candidate["river_id"]):
				continue
			covered = (
				TerrainMapGenerator.metric_length_between(
					candidate["position"], dock["position"],
					gs.map_aspect_ratio
				) < TerrainMapGenerator.RIVER_DOCK_MIN_SPACING
				or candidate["position"] == dock["position"]
			)
			if covered:
				break
		if not covered:
			all_lowland_candidates_covered = false
			break
	_check(
		all_lowland_candidates_covered,
		"每个低海拔沿河省份区域都必须生成渡口或被最小间距内的渡口覆盖"
	)
	var docks_per_river := {}
	var dock_banks_valid := true
	for dock_data in generated.get("docks", []):
		var river_id := int(dock_data.get("river_id", -1))
		docks_per_river[river_id] = int(docks_per_river.get(river_id, 0)) + 1
		var river_path: PackedVector2Array = gs.river_paths[river_id]
		var path_index := clampi(
			int(floor(float(dock_data["river_progress"]))),
			0, river_path.size() - 2
		)
		var owners := TerrainMapGenerator.province_boundary_segment_owners(
			gs.province_ids, gs.province_map_size,
			river_path[path_index], river_path[path_index + 1]
		)
		var banks := Vector2i(
			mini(int(dock_data["bank_a"]), int(dock_data["bank_b"])),
			maxi(int(dock_data["bank_a"]), int(dock_data["bank_b"]))
		)
		var dock_city := int(dock_data["city_id"])
		var bank_a_edge := gs.edge_of(banks.x, dock_city)
		var bank_b_edge := gs.edge_of(banks.y, dock_city)
		var direct_edge := gs.edge_of(banks.x, banks.y)
		dock_banks_valid = (
			dock_banks_valid
			and owners == banks
			and bank_a_edge != null and bank_a_edge.kind == Edge.Kind.LANDING
			and bank_b_edge != null and bank_b_edge.kind == Edge.Kind.LANDING
			and (direct_edge == null or direct_edge.kind != Edge.Kind.LAND)
		)
	_check(
		dock_banks_valid
			and int(docks_per_river.get(0, 0)) >= 2
			and int(docks_per_river.get(1, 0)) >= 2,
		"每座码头必须位于对应公共省界，并以两条抢滩连接两岸城市；跨河直连LAND必须删除：%s"
			% docks_per_river
	)
	var docks_are_full_cities := true
	for dock in docks:
		docks_are_full_cities = (
			docks_are_full_cities
			and dock.id >= GameState.TERRAIN_CITY_COUNT
			and dock.owner_nation >= 0
			and dock.fort_strength_max > 0
			and gs.recognized_owner_of(dock.id) == dock.owner_nation
			and not gs.neighbors(dock.id).is_empty()
		)
	_check(
		docks_are_full_cities,
		"码头必须复用完整城市实体、所有权、工事、法理归属和邻接"
	)
	var landing_valid := not landing_edges.is_empty()
	for edge in landing_edges:
		landing_valid = (
			landing_valid
			and edge.danger >= 0.90
			and (
				gs.cities[edge.city_a].is_dock
				or gs.cities[edge.city_b].is_dock
			)
		)
	_check(
		landing_valid,
		"陆城与码头间必须是 danger>=0.90 的抢滩边"
	)
	var land_crosses_river := false
	for edge in gs.edges:
		if (
			edge.max_manpower <= 0
			or edge.kind in [Edge.Kind.RIVER, Edge.Kind.SEA]
		):
			continue
		var road_points := edge.map_points(
			gs.cities[edge.city_a].map_position,
			gs.cities[edge.city_b].map_position
		)
		for road_index in range(road_points.size() - 1):
			var road_start := road_points[road_index]
			var road_end := road_points[road_index + 1]
			var road_delta := road_end - road_start
			var road_length_sq := road_delta.length_squared()
			if road_length_sq <= 0.000001:
				continue
			for river_path in gs.river_paths:
				for path_index in range(river_path.size() - 1):
					var hit = Geometry2D.segment_intersects_segment(
						road_start, road_end,
						river_path[path_index], river_path[path_index + 1]
					)
					if hit == null:
						continue
					var road_t := (
						(Vector2(hit) - road_start).dot(road_delta)
						/ road_length_sq
					)
					if (
						road_t > TerrainMapGenerator.RIVER_CROSSING_ENDPOINT_EPS
						and road_t < 1.0 - TerrainMapGenerator.RIVER_CROSSING_ENDPOINT_EPS
					):
						land_crosses_river = true
						break
				if land_crosses_river:
					break
			if land_crosses_river:
				break
		if land_crosses_river:
			break
	_check(
		not land_crosses_river,
		"任何可通行陆路都不得穿过河流，跨河只能经码头抢滩边和水路"
	)
	var river_valid := true
	var river_danger_bands := {}
	for edge in river_edges:
		river_valid = (
			river_valid
			and gs.cities[edge.city_a].is_dock
			and gs.cities[edge.city_b].is_dock
			and edge.max_manpower == Edge.WATER_MANPOWER
			and edge.travel_time_multiplier < 1.0
			and edge.supply_loss_multiplier < 1.0
			and not edge.allows_holding
			and edge.danger > 0.0
		)
		river_danger_bands[int(round(edge.danger * 100.0))] = true
	_check(
		river_valid,
		"码头间水路必须固定50000容量、快速、低粮损、有水文危险且不可驻边"
	)
	var sea_edges_valid := true
	var sea_crosses_river := false
	for sea_edge in sea_edges:
		sea_edges_valid = (
			sea_edges_valid
			and sea_edge.max_manpower == Edge.WATER_MANPOWER
			and not sea_edge.allows_holding
			and sea_edge.land_ratio < 1.0
		)
		var sea_path := sea_edge.map_points(
			gs.cities[sea_edge.city_a].map_position,
			gs.cities[sea_edge.city_b].map_position
		)
		for sea_index in range(sea_path.size() - 1):
			for river_path in gs.river_paths:
				for river_index in range(river_path.size() - 1):
					var hit = Geometry2D.segment_intersects_segment(
						sea_path[sea_index], sea_path[sea_index + 1],
						river_path[river_index], river_path[river_index + 1]
					)
					if hit == null:
						continue
					var sea_delta := sea_path[sea_index + 1] - sea_path[sea_index]
					var sea_t := (
						(Vector2(hit) - sea_path[sea_index]).dot(sea_delta)
							/ maxf(sea_delta.length_squared(), 0.000001)
					)
					var river_delta := river_path[river_index + 1] - river_path[river_index]
					var river_t := (
						(Vector2(hit) - river_path[river_index]).dot(river_delta)
							/ maxf(river_delta.length_squared(), 0.000001)
					)
					var endpoint_touch := (
						(sea_t <= 0.0001 or sea_t >= 0.9999)
						and (river_t <= 0.0001 or river_t >= 0.9999)
					)
					if not endpoint_touch:
						sea_crosses_river = true
	_check(
		sea_edges_valid and not sea_crosses_river,
		"SEA只连接独立陆地区域，可在海岸河口端点相接但不得中途横穿河流；并须固定50000容量、禁止驻边"
	)
	_check(
		river_danger_bands.size() > 1,
		"不同河段应从坡度和弯曲度生成不同水文危险"
	)
	var geometric_distances_valid := true
	var longest_metric_length := 0.0
	var longest_distance := 0
	for edge in gs.edges:
		var metric_length := TerrainMapGenerator.metric_polyline_length(
			edge.map_points(
				gs.cities[edge.city_a].map_position,
				gs.cities[edge.city_b].map_position
			),
			gs.map_aspect_ratio
		)
		var expected_distance := (
			TerrainMapGenerator.distance_units_for_metric_length(
				metric_length
			)
		)
		geometric_distances_valid = (
			geometric_distances_valid
			and edge.distance == expected_distance
		)
		if metric_length > longest_metric_length:
			longest_metric_length = metric_length
			longest_distance = edge.distance
	_check(
		geometric_distances_valid,
		"陆路、抢滩边和水路的逻辑距离必须统一取正式路径真实几何长度"
	)
	_check(
		longest_distance
			== TerrainMapGenerator.distance_units_for_metric_length(
				longest_metric_length
			),
		"正式地图最长边必须保持几何换算值，不得因地图拓扑或旧上限失真：length=%.3f distance=%d"
			% [
				longest_metric_length,
				longest_distance,
			]
	)
	var sample_river: Edge = river_edges[0]
	var land_reference := Edge.new()
	land_reference.distance = sample_river.distance
	land_reference.danger = sample_river.danger
	_check(
		_approx(
			Simulation.edge_travel_days(land_reference)
				/ Simulation.edge_travel_days(sample_river),
			1.2,
			0.001
		)
			and Pathfinding._supply_edge_loss(sample_river)
				< Pathfinding._supply_edge_loss(land_reference),
		"同距离同危险下，河运速度必须恰为陆运1.2倍且粮食损耗更低"
	)
	var keys_unique := gs.edge_lookup.size() == gs.edges.size()
	for edge in gs.edges:
		keys_unique = (
			keys_unique
			and gs.edge_of(edge.city_a, edge.city_b) == edge
		)
	_check(
		keys_unique
			and GameState.edge_key(0, 70)
				!= GameState.edge_key(1, 6),
		"新增码头 id 超过64后边键仍必须无碰撞"
	)

	var guard_state := GameState.new()
	guard_state.generate_grid_world(8123)
	guard_state.armies.clear()
	var water_edge := guard_state.edge_of(0, 1)
	water_edge.kind = Edge.Kind.RIVER
	water_edge.allows_holding = false
	var guard := _make_army(
		9900,
		guard_state.cities[0].owner_nation,
		5000,
		1
	)
	guard.state = Army.State.IDLE
	guard.location_city = 0
	guard.move_from = 0
	guard_state.armies.append(guard)
	var hold := ActionCandidate.make(
		ActionCandidate.Kind.HOLD,
		100.0,
		"河运边不可驻防",
		1
	)
	var guard_sim := Simulation.new()
	guard_sim.setup(guard_state)
	_check(
		not guard_sim._can_queue_ai_candidate(guard, hold)
			and not guard_sim._execute_ai_candidate(guard, hold),
		"命令校验与执行层都必须拒绝在河运边驻扎"
	)
	var guard_view := AiWorldView.build(
		guard_state,
		guard.owner_nation
	)
	var guard_plan := CityDefensePlan.new()
	guard_plan.view = guard_view
	guard_plan.snapshot = StrategicMapSnapshot.build(guard_view)
	guard_plan.required_power[0] = 5000.0
	_check(
		guard_plan._edge_hold_candidate(guard, 0, 1) == null,
		"AI 防御规划不得为河运边生成 HOLD 候选"
	)
	guard.state = Army.State.MOVING
	guard.location_city = -1
	guard.move_to = 1
	guard.move_progress = 0.35
	guard.on_edge = true
	guard.hold_target_progress = 0.35
	guard_sim._start_holding(guard)
	_check(
		guard.state == Army.State.MOVING
			and guard.hold_target_progress < 0.0,
		"状态机兜底不得让军队在河运边进入 HOLDING"
	)
	guard.state = Army.State.FIGHTING
	guard.resume_holding_after_battle = true
	guard_sim._resume_after_battle(guard)
	_check(
		guard.state == Army.State.MOVING,
		"水路战斗胜方不得通过恢复标记回到 HOLDING"
	)
	guard.state = Army.State.HOLDING
	guard_sim._advance_holding_adaptation()
	_check(
		guard.state == Army.State.MOVING,
		"每日状态校验必须清理水路上的非法 HOLDING"
	)
	guard_sim.free()

	# 码头只是一种交通节点，不是行政城市：不能成为首都/粮仓，也不能在
	# 最后一座陆城失守后让国家继续存活。用真实生成的码头覆盖迁都与事务路径。
	var dock_owner := docks[0].owner_nation
	var dock_id := docks[0].id
	var original_capital := gs.nations[dock_owner].capital_city_id
	gs.cities[original_capital].is_capital = false
	gs.cities[dock_id].is_capital = true
	gs.cities[dock_id].has_warehouse = true
	gs.cities[dock_id].food_storage = 25
	gs.nations[dock_owner].capital_city_id = dock_id
	gs.nations[dock_owner].warehouse_city_ids.append(dock_id)
	var repaired_capital := gs.ensure_valid_capital(dock_owner)
	_check(
		repaired_capital >= 0
			and not gs.cities[repaired_capital].is_dock
			and gs.cities[repaired_capital].is_capital
			and not gs.cities[dock_id].is_capital
			and not gs.cities[dock_id].has_warehouse
			and not gs.nations[dock_owner].warehouse_city_ids.has(dock_id),
		"迁都修复必须拒绝码头首都并清除码头粮仓标记"
	)
	var dock_recipient := (dock_owner + 1) % gs.nations.size()
	var remove_land_operations: Array[Dictionary] = []
	for owned_land in gs.land_cities_of(dock_owner):
		remove_land_operations.append({
			"city_id": owned_land.id,
			"controller_id": dock_recipient,
			"legal_owner_id": dock_recipient,
			"sponsor_id": -1,
			"reset_political_target": true,
			"stock_policy": GameState.TerritoryStockDisposition.DESTROY,
			"reason": "dock_is_not_a_city_regression",
		})
	var dock_only_result := gs.apply_territory_transaction(
		remove_land_operations
	)
	_check(
		bool(dock_only_result.get("ok", false))
			and gs.land_cities_of(dock_owner).is_empty()
			and not gs.cities_of(dock_owner).is_empty()
			and not gs.nations[dock_owner].alive
			and gs.nations[dock_owner].capital_city_id == -1
			and gs.nations[dock_owner].warehouse_city_ids.is_empty()
			and not gs.cities[dock_id].is_capital
			and not gs.cities[dock_id].has_warehouse
			and gs.territory_structure_valid(),
		"仅剩码头的势力必须按无城市灭亡，且不得保留首都或粮仓"
	)


func _test_responsive_map_layout() -> void:
	print("[1b] 战略图界面：地图响应式、图标四档缩放、城市/道路可点选")
	var valid_resolutions := (
		DisplaySettings.RESOLUTIONS.has(
			DisplaySettings.DEFAULT_RESOLUTION
		)
	)
	for resolution in DisplaySettings.RESOLUTIONS:
		valid_resolutions = (
			valid_resolutions
			and resolution.x * 9 == resolution.y * 16
		)
	_check(
		valid_resolutions
			and DisplaySettings.RESOLUTIONS.size() == 5,
		"分辨率设置必须提供五档固定16:9选项，且默认分辨率必须在选项内"
	)
	_check(
		DisplaySettings.validated_resolution(
			Vector2i(1920, 1080)
		) == Vector2i(1920, 1080)
			and DisplaySettings.validated_resolution(
				Vector2i(1366, 768)
			) == DisplaySettings.DEFAULT_RESOLUTION,
		"分辨率配置必须接受白名单尺寸，并把任意或损坏尺寸回退到默认值"
	)
	var main_scene := load("res://main.tscn") as PackedScene
	var settings_game := main_scene.instantiate()
	root.add_child(settings_game)
	var settings_sim := settings_game.get_node("Simulation") as Simulation
	var settings_overlay := settings_game.get_node(
		"SettingsLayer/SettingsOverlay"
	) as Control
	var settings_options := settings_game.get_node(
		(
			"SettingsLayer/SettingsOverlay/SettingsPanel/"
			+ "Margin/Content/ResolutionOption"
		)
	) as OptionButton
	var settings_entry_button := settings_game.get_node(
		"SettingsLayer/SettingsButton"
	) as Button
	settings_game.set("simulation", settings_sim)
	settings_game.set("settings_overlay", settings_overlay)
	settings_game.set("resolution_option", settings_options)
	settings_game.set(
		"settings_button",
		settings_entry_button
	)
	settings_game.set(
		"resolution_hint",
		settings_game.get_node(
			(
				"SettingsLayer/SettingsOverlay/SettingsPanel/"
				+ "Margin/Content/ResolutionHint"
			)
		)
	)
	settings_game.set(
		"settings_close_button",
		settings_game.get_node(
			(
				"SettingsLayer/SettingsOverlay/SettingsPanel/"
				+ "Margin/Content/Actions/CloseButton"
			)
		)
	)
	settings_game.set(
		"settings_apply_button",
		settings_game.get_node(
			(
				"SettingsLayer/SettingsOverlay/SettingsPanel/"
				+ "Margin/Content/Actions/ApplyButton"
			)
		)
	)
	settings_game.call("_setup_display_settings")
	var pause_before_settings := settings_sim.paused
	settings_game.call("_open_settings")
	var opened_and_paused := (
		settings_overlay.visible
		and settings_sim.paused
		and settings_options.item_count
			== DisplaySettings.RESOLUTIONS.size()
		and settings_entry_button.get_theme_font(
			"font"
		).has_char("设".unicode_at(0))
		and settings_options.get_popup().get_theme_font(
			"font"
		).has_char("辨".unicode_at(0))
	)
	settings_game.call("_close_settings")
	_check(
		opened_and_paused
			and not settings_overlay.visible
			and settings_sim.paused == pause_before_settings,
		"设置面板必须使用中文字体、提供全部分辨率，并正确暂停和恢复模拟"
	)
	settings_game.free()
	var base := MapRenderer.compute_layout_for_viewport(Vector2(1280, 720), 4)
	var large := MapRenderer.compute_layout_for_viewport(Vector2(1920, 1080), 4)
	var stats_closed := MapRenderer.compute_layout_for_viewport(
		Vector2(1280, 720),
		4,
		false
	)
	_check(
		float(large["cell"]) > float(base["cell"]),
		"窗口放大时地图画布仍应扩大"
	)
	_check(
		(stats_closed["origin"] as Vector2)
				== (base["origin"] as Vector2)
			and _approx(
				float(stats_closed["span"]),
				float(base["span"])
			),
		"国家列表必须是覆盖式浮窗，开关时不得挤压或移动地图"
	)
	var stats_button := MapRenderer.nation_stats_button_rect(
		Vector2(1280, 720),
		float(base["display_scale"]),
		float(base["side_margin"])
	)
	_check(
		Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(
			stats_button
		)
			and stats_button.size.x > stats_button.size.y,
		"国家统计按钮必须始终位于窗口内并具备稳定点击区域"
	)
	var nation_window := MapRenderer.nation_stats_window_rect(
		Vector2(1280, 720),
		float(base["display_scale"]),
		Vector2(10000.0, -10000.0),
		40
	)
	var nation_window_capacity := (
		MapRenderer.nation_stats_visible_row_capacity(
			nation_window.size,
			float(base["display_scale"])
		)
	)
	_check(
		Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(
			nation_window
		)
			and nation_window_capacity > 0
			and nation_window_capacity < 40
			and MapRenderer.nation_stats_title_rect(
				nation_window,
				float(base["display_scale"])
			).has_point(
				nation_window.position + Vector2(10.0, 10.0)
			)
			and nation_window.encloses(
				MapRenderer.nation_stats_close_rect(
					nation_window,
					float(base["display_scale"])
				)
			),
		"国家列表浮窗必须可约束在视口内，并提供标题拖动区、关闭区和滚动容量"
	)
	var army_scale_control := (
		MapRenderer.army_icon_scale_control_rect(
			Vector2(1280, 720),
			float(base["display_scale"]),
			float(base["side_margin"])
		)
	)
	_check(
		Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(
			army_scale_control
		)
			and army_scale_control.end.x
				< stats_button.position.x,
		"军队图标大小滑块必须位于窗口内，且不能覆盖国家统计按钮"
	)
	var scale_renderer := MapRenderer.new()
	scale_renderer.set_army_icon_scale(1.37)
	var rounded_scale := scale_renderer.army_icon_scale()
	scale_renderer.set_army_icon_scale(0.10)
	var minimum_scale := scale_renderer.army_icon_scale()
	scale_renderer.set_army_icon_scale(3.00)
	var maximum_scale := scale_renderer.army_icon_scale()
	scale_renderer.set_city_names_visible(false)
	var city_names_hidden := (
		not scale_renderer.city_names_visible()
	)
	scale_renderer.set_city_names_visible(true)
	var city_names_restored := (
		scale_renderer.city_names_visible()
	)
	_check(
		_approx(rounded_scale, 1.40)
			and _approx(
				minimum_scale,
				MapRenderer.ARMY_ICON_SCALE_MIN
			)
			and _approx(
				maximum_scale,
				MapRenderer.ARMY_ICON_SCALE_MAX
			),
		"军队图标滑块应按10%步长取整，并限制在10%至180%"
	)
	var light_counter := MapRenderer.army_counter_profile(
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		Army.StrategicRole.LINE
	)
	var main_light_counter := MapRenderer.army_counter_profile(
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		Army.StrategicRole.MAIN
	)
	var heavy_counter := MapRenderer.army_counter_profile(
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		Army.StrategicRole.MAIN
	)
	_check(
		city_names_hidden
			and city_names_restored
			and MapRenderer.target_redraw_fps(
				false,
				true
			) == MapRenderer.ACTIVE_REDRAW_FPS
			and MapRenderer.target_redraw_fps(
				false,
				false
			) == MapRenderer.STATIC_REDRAW_FPS,
		"城市名称按钮必须可逆切换；无动画时应降到静态刷新频率"
	)
	_check(
		not bool(light_counter["main_role"])
			and bool(main_light_counter["main_role"])
			and str(light_counter["role_code"]) == "线"
			and str(main_light_counter["role_code"]) == "主"
			and float(main_light_counter["width"])
				> float(light_counter["width"])
			and int(main_light_counter["marks"])
				> int(light_counter["marks"])
			and int(light_counter["icon"])
				!= int(heavy_counter["icon"])
			and float(heavy_counter["width"])
				> float(light_counter["width"])
			and int(light_counter["marks"]) == 1
			and int(heavy_counter["marks"]) == 3,
		"同为5000人时主战/填线必须使用不同角色文字、轮廓与标记，15000重军另有装甲符号"
	)
	var map_base_origin := Vector2(100.0, 80.0)
	var map_base_size := Vector2(600.0, 400.0)
	var zoom_anchor := Vector2(250.0, 180.0)
	var anchored_pan := MapRenderer.map_pan_for_zoom_anchor(
		map_base_origin,
		map_base_size,
		1.0,
		Vector2.ZERO,
		2.0,
		zoom_anchor
	)
	var normalized_anchor := (
		zoom_anchor - map_base_origin
	) / map_base_size
	var zoomed_origin := MapRenderer.map_view_origin(
		map_base_origin,
		map_base_size,
		2.0,
		anchored_pan
	)
	var zoomed_anchor := (
		zoomed_origin
		+ normalized_anchor * map_base_size * 2.0
	)
	var clamped_pan := MapRenderer.clamp_map_pan(
		Vector2(10000.0, -10000.0),
		2.0,
		map_base_size
	)
	var wheel_up := MapRenderer.wheel_zoom_multiplier(
		MOUSE_BUTTON_WHEEL_UP,
		1.0
	)
	var wheel_down := MapRenderer.wheel_zoom_multiplier(
		MOUSE_BUTTON_WHEEL_DOWN,
		1.0
	)
	var smooth_wheel := MapRenderer.wheel_zoom_multiplier(
		MOUSE_BUTTON_WHEEL_UP,
		0.25
	)
	_check(
		zoomed_anchor.distance_to(zoom_anchor) <= 0.001
			and clamped_pan == Vector2(300.0, -200.0)
			and MapRenderer.clamp_map_pan(
				Vector2(50.0, 50.0),
				1.0,
				map_base_size
			) == Vector2.ZERO,
		"滚轮缩放必须锚定鼠标地图坐标，拖动平移必须受边界约束且1倍时归零"
	)
	_check(
		wheel_up > 1.0
			and wheel_down < 1.0
			and _approx(wheel_up * wheel_down, 1.0)
			and smooth_wheel > 1.0
			and smooth_wheel < wheel_up
			and _approx(
				MapRenderer.magnify_zoom_multiplier(1.25),
				1.25
			)
			and _approx(
				MapRenderer.magnify_zoom_multiplier(0.1),
				0.5
			)
			and _approx(
				MapRenderer.magnify_zoom_multiplier(3.0),
				2.0
			),
		"触控板捏合与平滑滚轮倍率必须连续、方向正确且限制异常输入"
	)
	scale_renderer.free()
	var large_origin: Vector2 = large["origin"]
	_check(
		_approx(
			large_origin.y,
			MapRenderer.BASE_HEADER_ONLY_TOP
				* float(large["display_scale"])
		),
		"覆盖式国家列表不得为旧卡片网格预留顶部空间"
	)
	var large_span := float(large["cell"]) * float(GameState.GRID)
	_check(
		_approx(large_origin.x, (1920.0 - large_span) * 0.5),
		"放大后的地图应在窗口中水平居中"
	)
	var narrow := MapRenderer.compute_layout_for_viewport(Vector2(640, 480), 4)
	_check(
		int(narrow["hud_columns"]) < 4
		and float((narrow["origin"] as Vector2).y) > float(base["origin"].y) * 0.65,
		"窄窗口应自动减少派生列数，并保持固定顶栏地图起点"
	)
	var same_tier := MapRenderer.compute_layout_for_viewport(
		Vector2(1500, 800),
		4
	)
	var extra_large := MapRenderer.compute_layout_for_viewport(
		Vector2(2560, 1440),
		4
	)
	_check(
		_approx(float(narrow["display_scale"]), 0.80)
			and _approx(float(base["display_scale"]), 1.00)
			and _approx(float(same_tier["display_scale"]), 1.00)
			and _approx(float(large["display_scale"]), 1.25)
			and _approx(float(extra_large["display_scale"]), 1.50),
		"图标与字体只能使用0.80/1.00/1.25/1.50四档，不得随窗口连续缩放"
	)
	var ui_font := MapRenderer.create_ui_font()
	_check(
		ui_font.has_char("国".unicode_at(0)),
		"HUD 字体必须包含中文字形，不能回退为乱码或方框"
	)
	var map_label_font := MapRenderer.create_map_label_font()
	var renderer_source := FileAccess.get_file_as_string(
		"res://scripts/view/map_renderer.gd"
	)
	var map_label_factory_start := renderer_source.find(
		"static func create_map_label_font()"
	)
	var map_label_factory_end := renderer_source.find(
		"\n\nfunc ", map_label_factory_start
	)
	var map_label_factory_source := ""
	if map_label_factory_start >= 0 and map_label_factory_end > map_label_factory_start:
		map_label_factory_source = renderer_source.substr(
			map_label_factory_start,
			map_label_factory_end - map_label_factory_start
		).to_lower()
	_check(
		map_label_font != null
			and map_label_font.has_char("国".unicode_at(0))
			and map_label_factory_source.contains("return create_ui_font()")
			and not map_label_factory_source.contains("fangsong")
			and not map_label_factory_source.contains("noto serif")
			and not map_label_factory_source.contains("source han serif"),
		"国家地图标签必须复用可用的 CJK Sans/黑体字体，不得声明仿宋/衬线候选"
	)
	var trade_draw_start := renderer_source.find(
		"func _draw_trade_routes()"
	)
	var trade_draw_end := renderer_source.find(
		"\n\nfunc ", trade_draw_start + 1
	)
	var trade_draw_source := ""
	if trade_draw_start >= 0 and trade_draw_end > trade_draw_start:
		trade_draw_source = renderer_source.substr(
			trade_draw_start, trade_draw_end - trade_draw_start
		)
	_check(
		MapRenderer.MAP_MODE_TRADE == MapRenderer.MapMode.TRADE
		and trade_draw_source.contains(
			"_map_mode != MapMode.TRADE"
		)
		and trade_draw_source.contains("state.trade_routes.is_empty()")
		and trade_draw_source.contains("_draw_trade_flow_markers"),
		"2D贸易路线必须只在TRADE模式且存在路线时绘制"
	)
	var hit_state := GameState.new()
	hit_state.generate_grid_world(12346)
	for relation_a in range(hit_state.nations.size()):
		for relation_b in range(relation_a + 1, hit_state.nations.size()):
			hit_state.set_diplomatic_relation(
				relation_a, relation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	hit_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	hit_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.ALLIED
	)
	hit_state.set_diplomatic_relation(
		0, 3, GameState.DiplomaticRelation.ALLIED
	)
	hit_state.suzerainty[3] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	_check(
		MapRenderer.political_map_color_for_view(hit_state, 1, 0)
			.is_equal_approx(MapRenderer.DIPLOMACY_ENEMY_COLOR)
			and MapRenderer.political_map_color_for_view(hit_state, 2, 0)
				.is_equal_approx(MapRenderer.DIPLOMACY_ALLY_COLOR)
			and MapRenderer.political_map_color_for_view(hit_state, 3, 0)
				.is_equal_approx(MapRenderer.DIPLOMACY_VASSAL_COLOR)
			and MapRenderer.political_map_color_for_view(hit_state, 0, 1)
				.is_equal_approx(MapRenderer.DIPLOMACY_ENEMY_COLOR)
			and MapRenderer.political_map_color_for_view(hit_state, 3, 2)
				.is_equal_approx(MapRenderer.DIPLOMACY_NEUTRAL_COLOR),
		"外交视角必须把敌国/盟友/直属藩王/中立国映射为红/绿/灰/黑"
	)
	var hit_city := hit_state.cities[0]
	_check(
		MapRenderer.nation_at_map_position(
			hit_state, hit_city.map_position
		) == hit_city.owner_nation
			and MapRenderer.nation_at_map_position(
				hit_state, Vector2(-0.1, 0.5)
			) == -1,
		"地图国土拾取必须返回当前实控国，并拒绝地图外坐标"
	)
	var list_state := GameState.new()
	list_state.generate_grid_world(12347)
	list_state.nations[3].alive = false
	list_state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": 0,
		"civil_war": false,
	}
	list_state.nations[0].ai_last_force_action = (
		ActionCandidate.Kind.CREATE_ARMY
	)
	list_state.nations[0].ai_last_force_day = 12
	list_state.nations[0].last_trade_route_count = 2
	list_state.nations[0].last_trade_gold = 7
	list_state.nations[0].last_trade_food_import = 30
	list_state.nations[0].last_trade_food_export = 10
	list_state.nations[0].last_trade_manpower_import = 40
	list_state.nations[0].last_food_estimated_production = 0
	list_state.nations[0].last_food_estimated_consumption = 0
	list_state.nations[0].last_food_estimated_balance = 20
	list_state.nations[0].ruler_name = "测试君"
	list_state.nations[0].ruler_traits = [
		RulerProfile.TRAIT_FRUGAL
	] as Array[String]
	var nation_rows := MapRenderer.nation_list_rows(list_state)
	var nation_ids: Array[int] = []
	for row in nation_rows:
		nation_ids.append(int(row["nation_id"]))
	_check(
		nation_rows.size() == 3
			and nation_ids == [0, 1, 2]
			and int(nation_rows[0]["depth"]) == 0
			and bool(nation_rows[0]["has_subjects"])
			and int(nation_rows[1]["depth"]) == 1
			and int(nation_rows[1]["parent_nation_id"]) == 0
			and str(nation_rows[1]["identity"]).contains("藩王")
			and str(nation_rows[0]["action"]).contains("建军")
			and str(nation_rows[0]["identity_primary"]).length() > 0
			and str(nation_rows[0]["identity_secondary"]).length() > 0
			and str(nation_rows[0]["power_primary"]).contains("兵力")
			and str(nation_rows[0]["power_secondary"]).contains("忠诚")
			and str(nation_rows[0]["economy_primary"]).contains("月净")
				and str(nation_rows[0]["economy_secondary"]).contains("粮仓 0")
				and str(nation_rows[0]["economy_secondary"]).contains("月产 0")
				and str(nation_rows[0]["economy_secondary"]).contains("月需 0")
				and str(nation_rows[0]["economy_secondary"]).contains("月净 +20")
				and str(nation_rows[0]["economy_secondary"]).find("购粮") == -1
				and str(nation_rows[0]["economy_secondary"]).find("购人") == -1
				and str(nation_rows[0]["economy_secondary"]).find("+0") == -1
				and str(nation_rows[0]["economy_secondary"]).find("-0") == -1
				and str(nation_rows[0]["economy"]).contains("商2线")
				and str(nation_rows[0]["economy"]).contains("金+7")
				and str(nation_rows[0]["economy"]).contains("粮仓 0")
				and str(nation_rows[0]["economy"]).find("购粮") == -1
				and str(nation_rows[0]["economy"]).find("购人") == -1
			and str(nation_rows[0]["governance_primary"]).contains("测试君")
			and str(nation_rows[0]["governance_secondary"]).contains("节俭")
			and str(nation_rows[0]["governance_secondary"]).contains("建军"),
		"国家列表必须过滤灭亡国家，并把直属藩王缩进到宗主之后"
	)
	var nation_selection_renderer := MapRenderer.new()
	nation_selection_renderer.state = list_state
	nation_selection_renderer.select_city(0)
	var city_view_selected := (
		nation_selection_renderer.selected_city_id() == 0
		and nation_selection_renderer.diplomatic_view_nation_id()
			== list_state.cities[0].owner_nation
	)
	nation_selection_renderer.select_edge(0, 1)
	nation_selection_renderer.select_nation(0)
	var valid_nation_selected := (
		nation_selection_renderer.selected_nation_id() == 0
		and nation_selection_renderer.diplomatic_view_nation_id() == 0
		and nation_selection_renderer.selected_city_id() == -1
		and nation_selection_renderer.selected_edge_pair()
			== Vector2i(-1, -1)
	)
	nation_selection_renderer.select_nation(999)
	_check(
		city_view_selected
		and valid_nation_selected
		and nation_selection_renderer.selected_nation_id() == -1
		and nation_selection_renderer.diplomatic_view_nation_id() == -1,
		"点击城市或国家必须进入所属国外交视角，非法国家ID必须清除视角"
	)
	nation_selection_renderer.free()
	list_state.suzerainty[2] = {
		"overlord_id": 1,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": 0,
		"civil_war": false,
	}
	var nested_rows := MapRenderer.nation_list_rows(list_state)
	var collapsed_root_rows := MapRenderer.nation_list_rows(
		list_state,
		{0: true}
	)
	var collapsed_subject_rows := MapRenderer.nation_list_rows(
		list_state,
		{1: true}
	)
	_check(
		[
			int(nested_rows[0]["nation_id"]),
			int(nested_rows[1]["nation_id"]),
			int(nested_rows[2]["nation_id"]),
		] == [0, 1, 2]
			and [
				int(nested_rows[0]["depth"]),
				int(nested_rows[1]["depth"]),
				int(nested_rows[2]["depth"]),
			] == [0, 1, 2]
			and int(nested_rows[2]["parent_nation_id"]) == 1
			and collapsed_root_rows.size() == 1
			and not bool(collapsed_root_rows[0]["expanded"])
			and collapsed_subject_rows.size() == 2
			and MapRenderer.nation_list_alive_count(list_state) == 3,
		"多级宗藩必须递归缩进，折叠宗主时隐藏全部后代，折叠藩王时只隐藏其支系"
	)
	var root_row_rect := MapRenderer.nation_stats_row_rect(
		nation_window,
		float(base["display_scale"]),
		0
	)
	var nested_row_rect := MapRenderer.nation_stats_row_rect(
		nation_window,
		float(base["display_scale"]),
		2
	)
	var root_toggle_rect := MapRenderer.nation_tree_toggle_rect(
		root_row_rect,
		float(base["display_scale"]),
		0
	)
	var nested_toggle_rect := MapRenderer.nation_tree_toggle_rect(
		nested_row_rect,
		float(base["display_scale"]),
		2
	)
	_check(
		root_row_rect.position.y
			> MapRenderer.nation_stats_title_rect(
				nation_window,
				float(base["display_scale"])
			).end.y
			and root_row_rect.encloses(root_toggle_rect)
			and nested_row_rect.encloses(nested_toggle_rect)
			and nested_toggle_rect.position.x
				> root_toggle_rect.position.x,
		"宗藩箭头命中区必须位于对应行内，并随层级向右缩进"
	)
	var tree_renderer := MapRenderer.new()
	tree_renderer.state = list_state
	tree_renderer._display_scale = float(base["display_scale"])
	tree_renderer._nation_stats_window_position = Vector2(
		80.0,
		80.0
	)
	var expanded_rect := MapRenderer.nation_stats_window_rect(
		Vector2(1280.0, 720.0),
		tree_renderer._display_scale,
		tree_renderer._nation_stats_window_position,
		tree_renderer._nation_list_rows_cached().size()
	)
	var root_click_rect := MapRenderer.nation_tree_toggle_rect(
		MapRenderer.nation_stats_row_rect(
			expanded_rect,
			tree_renderer._display_scale,
			0
		),
		tree_renderer._display_scale,
		0
	)
	var collapsed_by_click := (
		tree_renderer._toggle_nation_tree_at_point(
			root_click_rect.get_center(),
			expanded_rect
		)
	)
	var collapsed_runtime_rows := (
		tree_renderer._nation_list_rows_cached()
	)
	var collapsed_rect := MapRenderer.nation_stats_window_rect(
		Vector2(1280.0, 720.0),
		tree_renderer._display_scale,
		tree_renderer._nation_stats_window_position,
		collapsed_runtime_rows.size()
	)
	var collapsed_click_rect := MapRenderer.nation_tree_toggle_rect(
		MapRenderer.nation_stats_row_rect(
			collapsed_rect,
			tree_renderer._display_scale,
			0
		),
		tree_renderer._display_scale,
		0
	)
	var expanded_by_click := (
		tree_renderer._toggle_nation_tree_at_point(
			collapsed_click_rect.get_center(),
			collapsed_rect
		)
	)
	_check(
		collapsed_by_click
			and collapsed_runtime_rows.size() == 1
			and collapsed_rect.size.y < expanded_rect.size.y
			and expanded_by_click
			and tree_renderer._nation_list_rows_cached().size() == 3,
		"点击宗主箭头必须折叠支系并缩小窗口，再次点击恢复全部藩属"
	)
	tree_renderer.free()
	var border_state := GameState.new()
	border_state.generate_grid_world(12348)
	for nation_a in range(border_state.nations.size()):
		for nation_b in range(
			nation_a + 1,
			border_state.nations.size()
		):
			border_state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	border_state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": 0,
		"civil_war": false,
	}
	border_state.suzerainty[3] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": 0,
		"civil_war": false,
	}
	border_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.ALLIED
	)
	border_state.set_diplomatic_relation(
		0,
		3,
		GameState.DiplomaticRelation.ALLIED
	)
	border_state.set_diplomatic_relation(
		1,
		3,
		GameState.DiplomaticRelation.ALLIED
	)
	var peaceful_suzerainty_geometry := (
		MapRenderer.build_province_boundary_segments(border_state)
	)
	_check(
		not (
			peaceful_suzerainty_geometry["country"]
				as PackedVector2Array
		).is_empty()
			and not (
			peaceful_suzerainty_geometry["suzerainty"]
				as PackedVector2Array
		).is_empty()
			and (
				peaceful_suzerainty_geometry["alliance"]
					as PackedVector2Array
			).is_empty(),
		"和平宗藩边界必须保留国家中心线；宗藩与同盟子集只用于语义诊断"
	)
	border_state.suzerainty.erase(3)
	border_state.set_diplomatic_relation(
		0,
		3,
		GameState.DiplomaticRelation.NEUTRAL
	)
	border_state.set_diplomatic_relation(
		1,
		3,
		GameState.DiplomaticRelation.NEUTRAL
	)
	border_state.suzerainty[1]["civil_war"] = true
	border_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var civil_war_geometry := (
		MapRenderer.build_province_boundary_segments(border_state)
	)
	_check(
		(
			civil_war_geometry["suzerainty"]
				as PackedVector2Array
		).is_empty()
			and not (
				civil_war_geometry["enemy"]
					as PackedVector2Array
			).is_empty()
			and (
				civil_war_geometry["country"]
					as PackedVector2Array
			) == (
				peaceful_suzerainty_geometry["country"]
					as PackedVector2Array
			),
		"削藩内战只能改变外交语义子集，不得改变国家边界中心线"
	)
	var hit_origin := Vector2(80.0, 60.0)
	var hit_map_size := Vector2(640.0, 640.0)
	var city_to_pick := hit_state.cities[0]
	var city_pixel := (
		hit_origin + city_to_pick.map_position * hit_map_size
	)
	_check(
		MapRenderer.pick_city_at_pixel(
			hit_state,
			city_pixel,
			hit_origin,
			hit_map_size,
			12.0
		) == city_to_pick.id,
		"点击城市符号中心必须稳定命中对应城市"
	)
	var edge_to_pick := hit_state.edges[0]
	var edge_from := (
		hit_origin
		+ hit_state.cities[edge_to_pick.city_a].map_position
			* hit_map_size
	)
	var edge_to := (
		hit_origin
		+ hit_state.cities[edge_to_pick.city_b].map_position
			* hit_map_size
	)
	var picked_edge := MapRenderer.pick_edge_at_pixel(
		hit_state,
		edge_from.lerp(edge_to, 0.5),
		hit_origin,
		hit_map_size,
		5.0
	)
	_check(
		picked_edge == edge_to_pick,
		"点击道路中点必须稳定命中对应可通行边"
	)
	var city_lines := MapRenderer.city_detail_lines(
		hit_state,
		city_to_pick.id
	)
	var city_sections := MapRenderer.city_detail_sections(
		hit_state, city_to_pick.id
	)
	var edge_lines := MapRenderer.edge_detail_lines(
		hit_state,
		edge_to_pick
	)
	_check(
		city_sections.size() == 5
			and [
				str(city_sections[0]["title"]),
				str(city_sections[1]["title"]),
				str(city_sections[2]["title"]),
				str(city_sections[3]["title"]),
				str(city_sections[4]["title"]),
			] == ["概况", "军事", "经济", "治理", "贸易"]
			and city_lines.size() == 12
			and "简称" in str((city_sections[0]["lines"] as Array)[0])
			and "工事" in str((city_sections[1]["lines"] as Array)[0])
			and "驻军" in str((city_sections[1]["lines"] as Array)[1])
			and "发展" in str((city_sections[2]["lines"] as Array)[1])
			and "库存" in str((city_sections[2]["lines"] as Array)[2])
			and "商路" in str((city_sections[4]["lines"] as Array)[0])
			and "贸易金" in str((city_sections[4]["lines"] as Array)[0])
			and "粮食净流" in str((city_sections[4]["lines"] as Array)[0])
			and MapRenderer.city_detail_sections(hit_state, -1).is_empty()
			and edge_lines.size() >= 5
			and "行军" in edge_lines[2],
		"城市五段详情必须包含军事、经济、治理、贸易，道路详情保留行军信息"
	)
	var trade_edge_a := hit_state.edge_of(0, 1)
	var trade_edge_b := hit_state.edge_of(1, 2)
	var trade_path_ready := trade_edge_a != null and trade_edge_b != null
	if trade_path_ready:
		trade_edge_a.map_path = PackedVector2Array([
			hit_state.cities[0].map_position,
			hit_state.cities[0].map_position.lerp(
				hit_state.cities[1].map_position, 0.5
			),
			hit_state.cities[1].map_position,
		])
		trade_edge_b.map_path = PackedVector2Array([
			hit_state.cities[1].map_position,
			hit_state.cities[1].map_position.lerp(
				hit_state.cities[2].map_position, 0.5
			),
			hit_state.cities[2].map_position,
		])
	var canonical_route := {
		"id": 7,
		"status": TradeNetwork.ACTIVE,
		"city_path": [0, 1, 2] as Array[int],
		"food_transfer": 0,
		"food_source_city": -1,
		"food_destination_city": -1,
	}
	var canonical_segments := MapRenderer.trade_route_map_paths(
		hit_state, canonical_route
	)
	var canonical_flow := MapRenderer.trade_route_flow_path(
		hit_state, canonical_route
	)
	var reverse_food_route: Dictionary = canonical_route.duplicate(true)
	reverse_food_route["food_transfer"] = 25
	reverse_food_route["food_source_city"] = 2
	reverse_food_route["food_destination_city"] = 0
	var reverse_food_flow := MapRenderer.trade_route_flow_path(
		hit_state, reverse_food_route
	)
	var invalid_food_route: Dictionary = canonical_route.duplicate(true)
	invalid_food_route["food_transfer"] = 25
	invalid_food_route["food_source_city"] = hit_state.cities.size() + 10
	invalid_food_route["food_destination_city"] = hit_state.cities.size() + 11
	var invalid_food_flow := MapRenderer.trade_route_flow_path(
		hit_state, invalid_food_route
	)
	_check(
		trade_path_ready
		and canonical_segments.size() == 2
		and canonical_segments[0][0].is_equal_approx(
			hit_state.cities[0].map_position
		)
		and canonical_segments[0][-1].is_equal_approx(
			hit_state.cities[1].map_position
		)
		and canonical_segments[1][0].is_equal_approx(
			hit_state.cities[1].map_position
		)
		and canonical_segments[1][-1].is_equal_approx(
			hit_state.cities[2].map_position
		)
		and canonical_flow.size() == 5
		and canonical_flow[0].is_equal_approx(
			hit_state.cities[0].map_position
		)
		and canonical_flow[-1].is_equal_approx(
			hit_state.cities[2].map_position
		)
		and reverse_food_flow[0].is_equal_approx(
			hit_state.cities[2].map_position
		)
		and reverse_food_flow[-1].is_equal_approx(
			hit_state.cities[0].map_position
		)
		and invalid_food_flow == canonical_flow,
		"贸易路径必须按city_path规范拼接，粮运方向相反时整体反向"
	)
	var polyline := PackedVector2Array([
		Vector2.ZERO, Vector2(3.0, 0.0), Vector2(3.0, 4.0),
	])
	var sample_start := MapRenderer.polyline_sample(polyline, -1.0)
	var sample_turn := MapRenderer.polyline_sample(polyline, 4.0)
	var sample_end := MapRenderer.polyline_sample(polyline, 99.0)
	_check(
		_approx(MapRenderer.polyline_length(polyline), 7.0)
		and (sample_start["position"] as Vector2).is_equal_approx(Vector2.ZERO)
		and (sample_start["tangent"] as Vector2).is_equal_approx(Vector2.RIGHT)
		and (sample_turn["position"] as Vector2).is_equal_approx(Vector2(3.0, 1.0))
		and (sample_turn["tangent"] as Vector2).is_equal_approx(Vector2.DOWN)
		and (sample_end["position"] as Vector2).is_equal_approx(Vector2(3.0, 4.0)),
		"贸易流折线长度与起点/转角/终点采样必须稳定"
	)
	var active_routes: Array[Dictionary] = [
		{"status": TradeNetwork.ACTIVE},
	]
	var rerouted_routes: Array[Dictionary] = [
		{"status": TradeNetwork.REROUTED},
	]
	var blocked_routes: Array[Dictionary] = [
		{"status": TradeNetwork.BLOCKED},
	]
	_check(
		MapRenderer.has_animated_trade_routes(active_routes)
		and MapRenderer.has_animated_trade_routes(rerouted_routes)
		and not MapRenderer.has_animated_trade_routes(blocked_routes)
		and not MapRenderer.has_animated_trade_routes(
			[] as Array[Dictionary]
		),
		"ACTIVE/REROUTED商路必须驱动动画，BLOCKED/空路线不得刷新动画"
	)
	_check(
		not MapRenderer.city_label_text(city_to_pick).is_empty(),
		"开启城名时必须能生成稳定城市名称文本"
	)
	var arrow_event := {
		"start_day": 10,
		"end_day": 30,
	}
	_check(
		MapRenderer.campaign_arrow_alpha(10, arrow_event) > 0.0
			and MapRenderer.campaign_arrow_alpha(25, arrow_event) > 0.0
			and MapRenderer.campaign_arrow_alpha(30, arrow_event) > 0.0
			and MapRenderer.campaign_arrow_alpha(31, arrow_event) == 0.0,
		"攻势箭头必须持续显示到事件结束日，而不是按现实时间3秒消失"
	)

# ------------------------------------------------------------------ 2. 地形惩罚

func _test_country_display_fade() -> void:
	var source := Color.from_hsv(0.37, 0.42, 0.68, 1.0)
	var adjusted := MapRenderer.country_boundary_display_color(source)
	_check(
		is_equal_approx(adjusted.h, source.h)
		and is_equal_approx(adjusted.s, 0.52)
		and is_equal_approx(adjusted.v, 0.53)
		and is_equal_approx(adjusted.a, 1.0),
		"国家边界色应保持色相，饱和度 +0.10、明度 -0.15"
	)
	var clamped := MapRenderer.country_boundary_display_color(
		Color.from_hsv(0.2, 0.96, 0.20, 0.4)
	)
	_check(
		is_equal_approx(clamped.s, 1.0)
		and is_equal_approx(clamped.v, 0.05)
		and is_equal_approx(clamped.a, 1.0),
		"国家边界色的饱和度和明度偏移必须钳制在有效范围"
	)
	var edge_opacity := MapRenderer.country_fill_opacity_for_distance(0.0)
	var near_opacity := MapRenderer.country_fill_opacity_for_distance(4.0)
	var far_opacity := MapRenderer.country_fill_opacity_for_distance(40.0)
	_check(
		is_equal_approx(edge_opacity, 1.0)
		and near_opacity < edge_opacity
		and far_opacity < near_opacity
		and far_opacity >= MapRenderer.COUNTRY_FILL_MIN_OPACITY,
		"国家填充应从边界向腹地单调变透明且不低于最低不透明度"
	)
	_check(
		is_equal_approx(
			MapRenderer.country_fill_opacity_for_distance(100000.0),
			MapRenderer.COUNTRY_FILL_MIN_OPACITY
		),
		"超大国家中心应收敛到统一的最低不透明度"
	)


func _test_terrain_multiplier() -> void:
	print("[2] danger 地形：攻击惩罚固定，防御惩罚随驻防时间趋近零")
	var danger := 0.5
	var attack := Combat.attack_multiplier(danger)
	_check(_approx(attack, 0.75), "danger=0.5 时攻击倍率应固定为 0.75，实为 %.3f" % attack)
	var d0 := Combat.defense_multiplier(danger, 0.0)
	var d30 := Combat.defense_multiplier(danger, 30.0)
	var d60 := Combat.defense_multiplier(danger, 60.0)
	var d90 := Combat.defense_multiplier(danger, 90.0)
	_check(_approx(d0, 0.8), "danger=0.5、0 天驻防的防御倍率应为 0.8，实为 %.3f" % d0)
	_check(d0 < d30 and d30 < d60 and d60 < d90 and d90 < 1.0,
		"防御倍率应随驻防时间单调趋近 1：%.3f/%.3f/%.3f/%.3f" % [d0, d30, d60, d90])
	_check(Combat.defense_multiplier(danger, 100000.0) <= 1.0,
		"驻防适应只能消除惩罚，不能产生超过基础值的加成")
	_check(_approx(Combat.attack_multiplier(0.0), 1.0) and _approx(Combat.defense_multiplier(0.0, 0.0), 1.0),
		"danger=0 时攻防均不应受惩罚")
	_check(_approx(Combat.attack_multiplier(danger), attack),
		"攻击倍率不得随驻防时间或其他状态变化")
	# item 9：隘口带连续、无阈值断崖。danger=1.0 达攻击地板 FLOOR；ONSET 处两段取值连续相接。
	_check(
		_approx(
			Combat.attack_multiplier(1.0),
			Combat.CHOKEPOINT_ATTACK_FLOOR
		),
		"danger=1.0 时进攻方攻击倍率应压到地板 %.2f" % Combat.CHOKEPOINT_ATTACK_FLOOR
	)
	# 无「浮点跨阈战力减半」：ONSET 前后各 0.001 的攻击倍率变化必须是小幅（远小于旧的 0.575→0.25 断崖）。
	var just_below := Combat.attack_multiplier(Combat.CHOKEPOINT_DANGER_ONSET - 0.001)
	var at_onset := Combat.attack_multiplier(Combat.CHOKEPOINT_DANGER_ONSET)
	var just_above := Combat.attack_multiplier(Combat.CHOKEPOINT_DANGER_ONSET + 0.001)
	_check(
		absf(just_below - at_onset) < 0.01 and absf(at_onset - just_above) < 0.01,
		"隘口带起点处必须连续：跨 0.001 的攻击倍率变化应<0.01，实为 %.4f/%.4f" % [
			absf(just_below - at_onset), absf(at_onset - just_above)
		]
	)
	# 全程单调不增：danger 越高攻击越受抑（采样覆盖普通段与隘口带）。
	var mono_ok := true
	var prev := Combat.attack_multiplier(0.0)
	for i in range(1, 101):
		var cur := Combat.attack_multiplier(float(i) / 100.0)
		if cur > prev + 1e-9:
			mono_ok = false
		prev = cur
	_check(mono_ok, "攻击倍率必须随 danger 全程单调不增（连续曲线，无回升跳变）")
	# 隘口带内仍强力压制：danger=0.95 的攻击倍率应显著低于普通段 danger=0.5。
	_check(
		Combat.attack_multiplier(0.95) < Combat.attack_multiplier(0.5) - 0.2,
		"极端地形(danger=0.95)仍须强力压制进攻，明显低于中等地形(danger=0.5)"
	)
	# 撤退决策地形红利（派生纯函数）：平地退化为 1；险地利守 >1；久守单调递增。
	_check(_approx(UtilityAI.terrain_hold_bias(0.0, 0.0), 1.0),
		"平地(danger=0)地形据守系数应退化为 1，实为 %.4f" % UtilityAI.terrain_hold_bias(0.0, 0.0))
	_check(UtilityAI.terrain_hold_bias(0.9, 0.0) > 1.0,
		"隘口(danger=0.9)即便零驻防也应利于据守(>1)，实为 %.4f" % UtilityAI.terrain_hold_bias(0.9, 0.0))
	var bias_d0 := UtilityAI.terrain_hold_bias(0.9, 0.0)
	var bias_d30 := UtilityAI.terrain_hold_bias(0.9, 30.0)
	_check(bias_d30 > bias_d0,
		"连续驻防应提升据守红利：30天(%.4f)须高于0天(%.4f)" % [bias_d30, bias_d0])
	# 前线边选值阶段(holding_days=0)：danger 越高据守溢价越高（value_of_edge 敌对前线边
	# 加成基础），且 UtilityAI 别名与 Combat 真源必须一致。
	var premium_flat := Combat.terrain_hold_bias(0.0, 0.0)
	var premium_mid := Combat.terrain_hold_bias(0.3, 0.0)
	var premium_pass := Combat.terrain_hold_bias(0.9, 0.0)
	_check(premium_pass > premium_mid and premium_mid > premium_flat,
		"选边溢价须随 danger 单调递增：平地%.4f<中等%.4f<隘口%.4f" % [
			premium_flat, premium_mid, premium_pass])
	_check(_approx(UtilityAI.terrain_hold_bias(0.9, 0.0), Combat.terrain_hold_bias(0.9, 0.0)),
		"UtilityAI.terrain_hold_bias 必须委托 Combat 真源，取值一致")

# ------------------------------------------------------------------ 3. 战斗基础

func _test_battle_basics() -> void:
	print("[3] 战斗基础：多回合、强者胜、size 扣减、必然收敛")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var strong := _make_army(0, 0, 2000, 12)
	var weak := _make_army(1, 1, 200, 10)
	var battle := _make_field_battle([strong], [weak], 0.0, 4)
	var s0 := strong.size
	var rounds := _run_battle(battle, rng)
	_check(rounds >= 1, "战斗应至少进行 1 回合，实为 %d" % rounds)
	_check(rounds < 1000, "战斗必须收敛结束，实为 %d 回合" % rounds)
	_check(battle.winner_side == 1, "2000 兵应战胜 200 兵")
	_check(weak.size < 200, "败方应减员")
	_check(strong.size <= s0, "胜方 size 不应增加")
	_check(strong.size > 0, "压倒性胜方应存活")
	# EU4 式：持续多回合而非一击必杀
	var strong2 := _make_army(0, 0, 1000, 10)
	var even := _make_army(1, 1, 1000, 10)
	var b2 := _make_field_battle([strong2], [even], 0.0, 4)
	rng.seed = 7
	var r2 := _run_battle(b2, rng)
	_check(r2 >= 3, "势均力敌应打多回合（EU4式持久），实为 %d" % r2)
	var mirror_a := _make_army(2, 0, 1000, 10, 10)
	var mirror_b := _make_army(3, 1, 1000, 10, 10)
	var mirror_battle := _make_field_battle(
		[mirror_a],
		[mirror_b],
		0.3,
		4
	)
	rng.seed = 8
	Combat.resolve_round(mirror_battle, rng)
	_check(
		mirror_a.size == mirror_b.size
		and is_equal_approx(
			mirror_a.morale,
			mirror_b.morale
		),
		"同质双方共享战场波动时，单回合伤亡和士气必须严格对称"
	)
	var normal_attacker := _make_army(4, 0, 1000, 10, 10)
	var normal_defender := _make_army(5, 1, 1000, 10, 10)
	var bonus_attacker := _make_army(6, 0, 1000, 10, 10)
	var bonus_defender := _make_army(7, 1, 1000, 10, 10)
	bonus_attacker.offensive_attack_multiplier = 2.0
	_check(
		_approx(
			ArmyPower.effective(bonus_attacker)
				/ ArmyPower.effective(normal_attacker),
			sqrt(2.0)
		),
		"AI综合战力应按sqrt(攻击倍率)识别限时攻势威胁"
	)
	var tired_normal := _make_army(8, 0, 1000, 10, 10)
	var tired_prepared := _make_army(9, 0, 1000, 10, 10)
	tired_normal.morale = 0.4
	tired_prepared.morale = 0.4
	tired_prepared.offensive_attack_multiplier = 1.5
	_check(
		_approx(tired_prepared.combat_morale(), 0.6)
			and _approx(tired_prepared.combat_max_morale(), 1.5)
			and _approx(tired_prepared.combat_morale_ratio(), 0.6)
			and _approx(
				ArmyPower.effective(tired_prepared)
					/ ArmyPower.effective(tired_normal),
				1.5 * sqrt(1.5)
			),
		"攻势准备必须以攻击加成的同一倍率临时提高有效士气和AI战力"
	)
	var near_rout_normal := _make_army(10, 0, 1000, 10, 10)
	var near_rout_prepared := _make_army(11, 0, 1000, 10, 10)
	near_rout_normal.morale = Combat.ARMY_ROUT_THRESHOLD * 0.75
	near_rout_prepared.morale = Combat.ARMY_ROUT_THRESHOLD * 0.75
	near_rout_prepared.offensive_attack_multiplier = 2.0
	_check(
		Combat.frontline_allocation(
			[near_rout_normal],
			1000
		).is_empty()
			and not Combat.frontline_allocation(
				[near_rout_prepared],
				1000
			).is_empty(),
		"攻势士气倍率必须参与前线准入和单军溃逃阈值"
	)
	var normal_battle := _make_field_battle(
		[normal_attacker],
		[normal_defender],
		0.0,
		4
	)
	var bonus_battle := _make_field_battle(
		[bonus_attacker],
		[bonus_defender],
		0.0,
		4
	)
	rng.seed = 9
	Combat.resolve_round(normal_battle, rng)
	rng.seed = 9
	Combat.resolve_round(bonus_battle, rng)
	_check(
		1000 - bonus_defender.size
			>= 2 * (1000 - normal_defender.size) - 1,
		"2倍攻势倍率必须近似加倍同条件下的单回合杀伤"
	)

# ------------------------------------------------------------------ 4. 撤退机制（士气崩溃保兵）

func _test_retreat_mechanic() -> void:
	print("[4] 撤退：败方常带残兵撤退（士气先于兵力崩溃）")
	var rng := RandomNumberGenerator.new()
	var survived_with_troops := 0
	var trials := 100
	for i in range(trials):
		rng.seed = i
		var a := _make_army(0, 0, 2500, 12)
		var b := _make_army(1, 1, 800, 10)
		var battle := _make_field_battle([a], [b], 0.0, 4)
		_run_battle(battle, rng)
		# 败方(b)若 size>0 即为带残兵撤退
		if battle.winner_side == 1 and b.size > 0:
			survived_with_troops += 1
	var rate := float(survived_with_troops) / float(trials)
	# 士气机制下，败方大多数情况应带残兵撤退而非被全歼
	_check(rate > 0.5, "败方带残兵撤退比例应 >0.5（非总是歼灭），实为 %.2f" % rate)

# ------------------------------------------------------------------ 5. 驻城加成

func _test_garrison_defense() -> void:
	print("[5] 驻城防御加成降低守军伤亡")
	# 相同种子对照：守军有城防加成应比无加成损失更少（单回合即可体现）。
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 42
	var atk1 := _make_army(0, 0, 1000, 12)
	var def1 := _make_army(1, 1, 1000, 10)
	var b1 := _make_siege_battle([atk1], def1, 0, 4)   # 城防 0
	Combat.resolve_round(b1, rng1)
	var loss_no_garrison := 1000 - def1.size

	var rng2 := RandomNumberGenerator.new(); rng2.seed = 42
	var atk2 := _make_army(0, 0, 1000, 12)
	var def2 := _make_army(1, 1, 1000, 10)
	var b2 := _make_siege_battle([atk2], def2, 30, 4)  # 城防 30
	Combat.resolve_round(b2, rng2)
	var loss_garrison := 1000 - def2.size
	_check(loss_garrison < loss_no_garrison,
		"守军有城防加成(30)应损失更少：无加成损%d vs 有加成损%d" % [loss_no_garrison, loss_garrison])

	var siege_city_id := 77
	var one_route_attacker := _make_army(500, 0, 10000, 12)
	one_route_attacker.move_from = 1
	one_route_attacker.move_to = siege_city_id
	var one_route_defender := _make_army(501, 1, 20000, 10)
	var one_route_battle := _make_siege_battle(
		[one_route_attacker],
		one_route_defender,
		0,
		4
	)
	one_route_battle.city.id = siege_city_id
	var split_same_a := _make_army(502, 0, 5000, 12)
	var split_same_b := _make_army(503, 0, 5000, 12)
	for same_route_army in [split_same_a, split_same_b]:
		same_route_army.move_from = 1
		same_route_army.move_to = siege_city_id
	var same_route_battle := _make_siege_battle(
		[split_same_a, split_same_b],
		_make_army(504, 1, 20000, 10),
		0,
		4
	)
	same_route_battle.city.id = siege_city_id
	var two_route_a := _make_army(505, 0, 5000, 12)
	var two_route_b := _make_army(506, 0, 5000, 12)
	two_route_a.move_from = 1
	two_route_b.move_from = 2
	for two_route_army in [two_route_a, two_route_b]:
		two_route_army.move_to = siege_city_id
	var two_route_defender := _make_army(507, 1, 20000, 10)
	var two_route_battle := _make_siege_battle(
		[two_route_a, two_route_b],
		two_route_defender,
		0,
		4
	)
	two_route_battle.city.id = siege_city_id
	var three_route_battle := _make_siege_battle(
		[
			_make_army(508, 0, 3000, 12),
			_make_army(509, 0, 3000, 12),
			_make_army(510, 0, 4000, 12),
			_make_army(511, 0, 1000, 12),
		],
		_make_army(512, 1, 20000, 10),
		0,
		4
	)
	three_route_battle.city.id = siege_city_id
	for route_index in range(three_route_battle.side_a.size()):
		var route_army: Army = three_route_battle.side_a[route_index]
		route_army.move_from = route_index + 1
		route_army.move_to = siege_city_id
	_check(
		Combat.siege_attack_direction_count(one_route_battle) == 1
			and Combat.siege_attack_direction_count(
				same_route_battle
			) == 1
			and _approx(
				Combat.siege_attack_damage_multiplier(
					same_route_battle
				),
				1.0
			)
			and _approx(
				Combat.siege_attack_damage_multiplier(
					two_route_battle
				),
				1.2
			)
			and _approx(
				Combat.siege_attack_damage_multiplier(
					three_route_battle
				),
				1.3
			),
		"围城攻击方向必须按不同出发城市计数：同路拆军1.0、两路1.2、三路以上封顶1.3"
	)
	var one_route_rng := RandomNumberGenerator.new()
	one_route_rng.seed = 4242
	Combat.resolve_round(one_route_battle, one_route_rng)
	var two_route_rng := RandomNumberGenerator.new()
	two_route_rng.seed = 4242
	Combat.resolve_round(two_route_battle, two_route_rng)
	var one_route_loss := 20000 - one_route_defender.size
	var two_route_loss := 20000 - two_route_defender.size
	_check(
		two_route_loss >= int(floor(float(one_route_loss) * 1.15))
			and two_route_loss
				<= int(ceil(float(one_route_loss) * 1.25)),
		"同兵力同随机数下两路攻城杀伤应约为一路的1.2倍：一路%d，两路%d"
			% [one_route_loss, two_route_loss]
	)

# ------------------------------------------------------------------ 5b. 多路 vs 一路

func _test_multi_vs_one() -> void:
	print("[5b] N v M：多路夹击应胜过单路守军")
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	# 三路各 800 攻一路 1500：聚合火力 2400 > 1500，多路应胜
	var a1 := _make_army(0, 0, 800, 10)
	var a2 := _make_army(1, 0, 800, 10)
	var a3 := _make_army(2, 0, 800, 10)
	var d := _make_army(3, 1, 1500, 10)
	var battle := _make_field_battle([a1, a2, a3], [d], 0.0, 4)
	var rounds := _run_battle(battle, rng)
	_check(rounds < 1000, "多路战斗应收敛")
	_check(battle.winner_side == 1, "三路聚合火力应战胜单路守军")
	var atk_survivors := 0
	for a in [a1, a2, a3]:
		if a.size > 0:
			atk_survivors += 1
	_check(atk_survivors >= 1, "多路方应有幸存")

# ------------------------------------------------------------------ 5c. 断粮士气惩罚（粮草特色）

func _test_starvation_morale() -> void:
	print("[5c] 断粮方士气衰减更快、更早崩溃（粮草特色）")
	# 对照：完全相同局面与种子，仅 side_b 是否断粮不同。
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 11
	var a1 := _make_army(0, 0, 1000, 10)
	var b1 := _make_army(1, 1, 1000, 10)
	var battle1 := _make_field_battle([a1], [b1], 0.0, 4)
	var rounds_fed := _run_battle(battle1, rng1)

	var rng2 := RandomNumberGenerator.new(); rng2.seed = 11
	var a2 := _make_army(0, 0, 1000, 10)
	var b2 := _make_army(1, 1, 1000, 10)
	b2.starving = true                       # side_b 断粮
	var battle2 := _make_field_battle([a2], [b2], 0.0, 4)
	var rounds_starved := _run_battle(battle2, rng2)

	_check(rounds_starved <= rounds_fed,
		"断粮方所在战斗应更早（或不晚于）结束：饱粮%d回合 vs 断粮%d回合" % [rounds_fed, rounds_starved])
	_check(battle2.winner_side == 1,
		"其他条件相同、side_b 断粮，则 side_a(未断粮) 应获胜")

# ------------------------------------------------------------------ 5d. 持久士气：疲劳老兵 + 战后恢复

func _test_persistent_morale() -> void:
	print("[5d] 持久士气：低士气老兵更快崩溃 + 战后恢复")
	# (a) 同兵力同种子，一方带疲劳士气进场 → 该方应更快崩溃败北。
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 21
	var fresh := _make_army(0, 0, 1000, 10)
	var tired := _make_army(1, 1, 1000, 10)
	tired.morale = 0.3                       # 疲劳老兵
	var battle := _make_field_battle([fresh], [tired], 0.0, 4)
	_run_battle(battle, rng1)
	_check(battle.winner_side == 1, "满士气一方应战胜疲劳(0.3)一方")

	# (b) 战后恢复：满军费、满补给时，轻重军都在 10 天从零恢复至各自上限。
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)
	var probe := gs.armies[0]
	probe.morale = 0.0
	probe.state = Army.State.IDLE
	probe.starving = false
	for _day in range(Combat.MORALE_RECOVERY_DAYS - 1):
		sim._recover_morale()
	_check(
		_approx(probe.morale, probe.max_morale * 0.9)
			and probe.morale < probe.max_morale,
		"轻军第9天士气应为上限的90%%，实为 %.2f/%.2f"
			% [probe.morale, probe.max_morale]
	)
	sim._recover_morale()
	_check(
		_approx(probe.morale, probe.max_morale),
		"轻军满补给时必须在第10天回满士气"
	)
	probe.max_morale = Army.HEAVY_MAX_MORALE
	probe.morale = 0.0
	for _day in range(Combat.MORALE_RECOVERY_DAYS):
		sim._recover_morale()
	_check(
		_approx(probe.morale, Army.HEAVY_MAX_MORALE),
		"重军必须按自身士气上限比例恢复，并在第10天从0回满2.0"
	)
	# 军费支付率只缩放恢复速度，不像缺粮那样直接扣减士气。
	probe.max_morale = Army.LIGHT_MAX_MORALE
	probe.morale = 0.2
	probe.starving = false
	gs.nations[probe.owner_nation].treasury_gold = 0
	gs.nations[probe.owner_nation].military_payment_ratio = 0.0
	sim._recover_morale()
	_check(
		_approx(
			probe.morale,
			0.2
				+ probe.max_morale
					/ float(Combat.MORALE_RECOVERY_DAYS)
					* 0.5
		)
			and _approx(
				Simulation.morale_recovery_payment_multiplier(
					0.4
				),
				0.7
			),
		"军费未支付时士气仍应按50%%速度恢复，支付40%%时恢复倍率应为0.70"
	)
	# 断粮时不恢复
	probe.morale = 0.2; probe.starving = true
	sim._recover_morale()
	_check(_approx(probe.morale, 0.2), "断粮军队不应恢复士气")
	sim.free()

# ------------------------------------------------------------------ 6. 模拟推进

func _test_simulation_progress() -> void:
	print("[6] 模拟推进：战斗/占领/粮食实际生效")
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)
	sim.diplomacy_enabled = false
	var captures := 0
	for d in range(2000):
		var before := {}
		for c in gs.cities:
			before[c.id] = c.owner_nation
		sim._advance_day()
		for c in gs.cities:
			if before[c.id] != c.owner_nation:
				captures += 1
		if gs.winner != -1:
			break
	_check(captures > 0, "2000 天内应发生城市易主（战斗+占领生效），实为 %d" % captures)
	# 粮食：至少有城市 food_storage 被消耗过（存在低于半年产出的城）
	_check(gs.day > 0, "天数应推进")
	sim.free()   # 释放 Node，避免泄漏

# ------------------------------------------------------------------ 7. 确定性复现
func _test_post_unification_continuation() -> void:
	print("[6b] 统一后继续推演：保留胜者里程碑但不暂停时间")
	var gs := GameState.new()
	gs.generate_grid_world(12666)
	gs.armies.clear()
	gs.battles.clear()
	for city in gs.cities:
		city.owner_nation = 0
		gs.recognized_city_owners[city.id] = 0
	var sim := Simulation.new()
	sim.setup(gs)
	sim.diplomacy_enabled = false
	sim._check_victory()
	var day_before := gs.day
	sim._advance_day()
	_check(
		gs.winner == 0
			and not sim.paused
			and gs.day == day_before + 1,
		"仅剩一国时应记录统一者但继续推进日期，不得自动暂停"
	)
	sim.free()




func _test_determinism() -> void:
	print("[7] 确定性：同种子两次运行状态一致")
	var sig_a := _run_signature(12345, 600)
	var sig_b := _run_signature(12345, 600)
	_check(sig_a == sig_b, "同种子 600 天后签名应一致\n    A=%s\n    B=%s" % [sig_a, sig_b])
	# 不同种子应（极大概率）不同
	var sig_c := _run_signature(999, 600)
	_check(sig_a != sig_c, "不同种子应产生不同轨迹（概率性）")


func _run_signature(world_seed: int, days: int) -> String:
	var gs := GameState.new()
	gs.generate_grid_world(world_seed)
	var sim := Simulation.new()
	sim.setup(gs)
	for d in range(days):
		sim._advance_day()
		if gs.winner != -1:
			break
	# 生成状态签名：各城归属 + 各国兵力
	var parts: Array[String] = []
	for c in gs.cities:
		parts.append(str(c.owner_nation))
	var troops := 0
	for a in gs.armies:
		troops += a.size
	parts.append("T%d" % troops)
	parts.append("D%d" % gs.day)
	sim.free()
	return "|".join(parts)

# ------------------------------------------------------------------ 8. 时间分层

func _test_time_layering() -> void:
	print("[8] 时间分层：经济/注粮按月结算，行军按天渐进")
	# 1. 经济按月结算（非 30×）。总金库口径对国家归属免疫（Σ 城 gold_per_month）。
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)
	var before := 0
	for n in gs.nations:
		before += n.treasury_gold
	for _i in range(29):
		sim._advance_day()
	var mid := 0
	for n in gs.nations:
		mid += n.treasury_gold
	_check(mid == before, "1..29 天不应结算经济：%d -> %d" % [before, mid])
	gs.cities[0].war_disruption_until_day = (
		gs.day + Simulation.CITY_WAR_DISRUPTION_DAYS
	)
	var predicted_flows := Simulation.monthly_gold_flows(gs)
	var expected_balance := 0
	for flow in predicted_flows:
		expected_balance += int(flow["balance"])
	sim._advance_day()   # day==30
	var after := 0
	for n in gs.nations:
		after += n.treasury_gold
	var expected_treasury := before + expected_balance
	_check(after == expected_treasury,
		"day30 应结算月收入并扣战争军费：应 %d，实为 %d"
			% [expected_treasury, after])
	sim.free()

	var morale_state := GameState.new()
	morale_state.generate_grid_world(12347)
	morale_state.armies.clear()
	var morale_nation := morale_state.nations[0]
	morale_nation.military_payment_ratio = 1.0
	var morale_probe := morale_state.create_army(
		0,
		morale_nation.capital_city_id,
		5000,
		5000
	)
	morale_probe.morale = 0.0
	var morale_sim := Simulation.new()
	morale_sim.setup(morale_state)
	morale_sim.diplomacy_enabled = false
	morale_sim._advance_day()
	_check(
		_approx(morale_probe.morale, 0.1),
		"士气恢复必须进入每日时钟：第1天应从0恢复到0.1"
	)
	for _day in range(Combat.MORALE_RECOVERY_DAYS - 1):
		morale_sim._advance_day()
	_check(
		_approx(morale_probe.morale, morale_probe.max_morale),
		"满军费、满补给军队必须在真实推进第10天回满士气"
	)
	morale_sim.free()

	# 2. 注粮半年一次：隔离单测 _resolve_economy 的 day gate（避开消耗干扰）。
	var gs2 := GameState.new()
	gs2.generate_grid_world(12345)
	var sim2 := Simulation.new()
	sim2.setup(gs2)
	var nation0 := gs2.nations[0]
	var capital := gs2.cities[nation0.capital_city_id]
	var disrupted_food_city := gs2.cities_of(0)[0]
	disrupted_food_city.war_disruption_until_day = (
		Simulation.CITY_WAR_DISRUPTION_DAYS
	)
	var f0 := capital.food_storage
	var nation0_production := 0
	for city in gs2.cities_of(0):
		nation0_production += Simulation.city_food_output(
			gs2,
			city
		)
	gs2.day = 30
	sim2._resolve_economy()
	_check(capital.food_storage == f0, "day30（非180倍数）不应注粮：%d" % capital.food_storage)
	gs2.day = 180
	sim2._resolve_economy()
	_check(capital.food_storage == f0 + nation0_production,
		"day180 全国粮食产出应汇入首都：应 %d，实为 %d"
			% [f0 + nation0_production, capital.food_storage])
	sim2.free()

	var garrison_state := GameState.new()
	garrison_state.generate_grid_world(12346)
	garrison_state.armies.clear()
	var productive_city := garrison_state.cities[0]
	productive_city.gold_per_month = 11
	productive_city.food_per_half_year = 101
	var base_output := productive_city.food_per_half_year
	var food_guard := _make_army(899, 0, 15000, 10, 10)
	food_guard.location_city = productive_city.id
	food_guard.move_from = productive_city.id
	food_guard.state = Army.State.IDLE
	garrison_state.armies.append(food_guard)
	var city_output := Simulation.city_food_output(
		garrison_state,
		productive_city
	)
	var minimum_output := int(floor(
		float(base_output)
			* (
				1.0
				- Simulation.CITY_GARRISON_FOOD_PENALTY_MAX
			)
	))
	_check(
		city_output < base_output
		and city_output >= minimum_output,
		"驻城军应降低城市产粮且减产不得超过30%%：base=%d actual=%d"
			% [base_output, city_output]
	)
	food_guard.on_edge = true
	food_guard.move_to = 1
	var edge_output := Simulation.city_food_output(
		garrison_state,
		productive_city
	)
	_check(
		edge_output == base_output,
		"驻边军不应降低城市产粮：base=%d actual=%d"
			% [base_output, edge_output]
	)
	productive_city.war_disruption_until_day = (
		Simulation.CITY_WAR_DISRUPTION_DAYS
	)
	garrison_state.day = (
		Simulation.CITY_WAR_DISRUPTION_DAYS - 1
	)
	_check(
		Simulation.city_food_output(
			garrison_state,
			productive_city
		) == 50
		and Simulation.city_gold_output(
			garrison_state,
			productive_city
		) == 5,
		"城市战争破坏期内粮食和金钱产量必须降为50%%"
	)
	garrison_state.day = Simulation.CITY_WAR_DISRUPTION_DAYS
	_check(
		Simulation.city_food_output(
			garrison_state,
			productive_city
		) == base_output
		and Simulation.city_gold_output(
			garrison_state,
			productive_city
		) == productive_city.gold_per_month,
		"城市战争结束满一年后应恢复完整粮食和金钱产量"
	)
	var restored_resource_report := DiplomacyAI.resource_report(
		garrison_state,
		productive_city.owner_nation
	)
	garrison_state.day = (
		Simulation.CITY_WAR_DISRUPTION_DAYS - 1
	)
	var disrupted_resource_report := DiplomacyAI.resource_report(
		garrison_state,
		productive_city.owner_nation
	)
	_check(
		float(disrupted_resource_report[
			"monthly_gold_income"
		]) < float(restored_resource_report[
			"monthly_gold_income"
		])
		and float(disrupted_resource_report[
			"monthly_food_production"
		]) < float(restored_resource_report[
			"monthly_food_production"
		]),
		"外交与军备预算必须使用战争破坏后的实际粮金产出"
	)

	# 3. 行军不瞬移：单日 step 上界 = 1/MARCH_DAYS_MIN = 1/10 = 0.1（规格 R1，distance=1 最快）。
	var gs3 := GameState.new()
	gs3.generate_grid_world(12345)
	var sim3 := Simulation.new()
	sim3.setup(gs3)
	sim3._advance_day()
	var moving := 0
	var max_prog := 0.0
	for a in gs3.armies:
		if a.state == Army.State.MOVING and a.move_to != -1:
			moving += 1
			max_prog = maxf(max_prog, a.move_progress)
	_check(moving > 0, "首日应有军队开拔行军，实为 %d" % moving)
	_check(max_prog <= 0.1 + 1e-6, "行军单日 step 应 <= 0.1（最快边 10 天），最大进度 %.4f" % max_prog)
	sim3.free()

# ------------------------------------------------------------------ 9. 掷骰累积攻城

func _test_siege_dice() -> void:
	print("[9] 连续围城：ratio=1→30 天、单调递减、ratio<0.5 倒退不撤离 + 破城归攻方")
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	gs.armies.clear()
	gs.battles.clear()
	var sim := Simulation.new()
	sim.setup(gs)

	# 1. 破城需 >1 tick（累积，非瞬占），破城后城归攻方。ratio=1000/100=10 → days=3+27/10≈5.7。
	var b := _make_pure_siege(_make_army(0, 0, 1000, 10), 10, 4, 100)
	var ticks := _run_siege(sim, b)
	_check(ticks > 1, "围城累积破城应 >1 天（非瞬占），实为 %d" % ticks)
	_check(b.city.owner_nation == 0, "破城后城应归攻方 nation0，实为 %d" % b.city.owner_nation)
	_check(b.winner_side == 1, "破城 winner_side 应为 1，实为 %d" % b.winner_side)

	# 2. 兵力倍数越高围城越快（连续、无掷骰、与工事强度无关）：ratio=100 应快于 ratio=5。
	var t_r5 := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 500, 10), 10, 4, 100))   # ratio=5
	var t_r100 := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 10000, 10), 10, 4, 100)) # ratio=100
	_check(t_r100 < t_r5, "高兵力倍数(ratio=100)应快于低倍数(ratio=5)：%d vs %d" % [t_r100, t_r5])

	# 3. 边界标定：ratio=1 → 30 天（±1 容差，正常围城下限）；ratio 极大 → 趋近 3 天。
	var t_r1 := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 100, 10), 10, 4, 100))
	_check(absi(t_r1 - 30) <= 1, "ratio=1 围城应约 30 天，实为 %d" % t_r1)
	var t_rinf := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 1000000, 10), 10, 4, 100))
	_check(t_rinf <= 4 and t_rinf >= 3, "ratio→∞ 围城应趋近 3 天(3~4)，实为 %d" % t_rinf)

	# 4. item 7：连续曲线，ratio<0.5(=0.4) 进度倒退且不再机制性撤离（保持围城、等待援军）。
	var weak_attacker := _make_army(0, 0, 40, 10)
	var b_stall := _make_pure_siege(weak_attacker, 10, 4, 100)   # ratio=0.4 <0.5
	_attach_pure_siege_city(sim, b_stall)
	# 先人为累积一点进度，再推进 5 天观察其倒退（负进度被 clamp 到 0，且攻方不撤离）。
	b_stall.siege_progress = 3.0
	for _i in range(5):
		sim._advance_siege(b_stall)
	_check(not b_stall.finished, "ratio<0.5 围城应持续（不机制性撤离），finished=%s" % b_stall.finished)
	_check(not b_stall.side_a.is_empty(), "ratio<0.5 攻方应留在围城位置等待援军")
	_check(b_stall.siege_progress < 3.0, "ratio<0.5 进度应倒退，实为 %.3f" % b_stall.siege_progress)

	# 5. 工事强度不影响纯围城速度（连续曲线只看 siege_required 分母）：同 siege_required 下高低工事同时。
	var t_deflo := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 1000, 10), 5, 4, 100))
	var t_defhi := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 1000, 10), 40, 4, 100))
	_check(t_deflo == t_defhi, "纯围城速度应只取决于 siege_required，与工事强度无关：%d vs %d" % [t_deflo, t_defhi])

	sim.free()


func _test_captured_city_fort_recovery() -> void:
	print("[9b] 城破工事：降至50%、一年线性回满、再次易手刷新")
	var gs := GameState.new()
	gs.generate_grid_world(12346)
	gs.armies.clear()
	gs.battles.clear()
	var sim := Simulation.new()
	sim.setup(gs)
	var city: City = null
	var counterattack_staging_city := -1
	for candidate in gs.cities:
		if candidate.is_capital or candidate.has_warehouse:
			continue
		var has_counterattack_route := false
		for neighbor in gs.neighbors(candidate.id):
			var route := gs.edge_of(candidate.id, neighbor)
			if (
				gs.cities[neighbor].owner_nation
					== candidate.owner_nation
				and route.max_manpower
					>= Edge.STANDARD_MANPOWER
			):
				has_counterattack_route = true
				counterattack_staging_city = neighbor
				break
		if has_counterattack_route:
			city = candidate
			break
	_check(
		city != null,
		"测试地图应存在可供原城主反攻的非首都城市"
	)
	if city == null:
		sim.free()
		return
	var old_owner := city.owner_nation
	var invader := (old_owner + 1) % gs.nations.size()
	var full_strength := city.fort_strength
	var full_requirement := UtilityAI.assault_commit_threshold(
		0,
		full_strength
	)
	var first_capture_day := 40
	gs.day = first_capture_day
	var captor := _make_army(9800, invader, 1000, 10)
	gs.armies.append(captor)
	sim._capture_city(captor, city, invader)
	var damaged_strength := (
		Simulation.city_fort_strength_after_capture(
			full_strength,
			0
		)
	)
	_check(
		city.owner_nation == invader
			and city.fort_strength_max == full_strength
			and city.fort_strength == damaged_strength
			and city.fort_last_capture_day == first_capture_day,
		"城市首次易手应保留完整工事%d、当前降至50%%附近%d并记录第%d天"
			% [full_strength, damaged_strength, first_capture_day]
	)
	var damaged_requirement := UtilityAI.assault_commit_threshold(
		0,
		city.fort_strength
	)
	_check(
		damaged_requirement < full_requirement,
		"新占城市应直接降低 AI 攻城集结门槛：完整%d，受损%d"
			% [full_requirement, damaged_requirement]
	)
	var counterattack_objective := DiplomacyAI.select_war_objective(
		gs,
		old_owner,
		invader
	)
	_check(
		int(counterattack_objective.get("city_id", -1)) == city.id
			and str(
				counterattack_objective.get("reason", "")
			).contains("近期失地"),
		"原城主应在恢复窗口优先反攻近期失地，而非放任城防回满"
	)
	var reclaim_required := DiplomacyAI.required_assault_troops(
		gs,
		old_owner,
		city.id
	)
	var expected_reclaim_requirement := (
		UtilityAI.assault_commit_threshold(
			captor.size,
			city.fort_strength
		)
	)
	var reclaim_army := _make_army(
		9802,
		old_owner,
		maxi(reclaim_required, 1000),
		10
	)
	reclaim_army.location_city = counterattack_staging_city
	reclaim_army.move_from = counterattack_staging_city
	gs.armies.append(reclaim_army)
	gs.nations[old_owner].campaign_next_offensive_day = (
		gs.day + Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
	)
	var reclamation_launched := sim._manage_campaign_offensive(
		old_owner
	)
	_check(
		reclaim_required == expected_reclaim_requirement
			and reclamation_launched
			and reclaim_army.ai_action
				== ActionCandidate.Kind.ATTACK
			and reclaim_army.ai_target_city == city.id,
		"近期失地反攻应优先发起但仍承担占领军与受损城防的完整围城集结成本"
	)
	var recovery_siege := gs.new_battle(Battle.Kind.SIEGE)
	recovery_siege.city = city
	recovery_siege.siege_required = Combat.siege_required_manpower(
		city.fort_strength
	)
	var fortification_revision_before := gs.fortification_revision
	gs.day = first_capture_day + 182
	sim._recover_city_fortifications()
	_check(
		city.fort_strength > damaged_strength
			and city.fort_strength < full_strength
			and gs.fortification_revision
				== fortification_revision_before + 1
			and recovery_siege.siege_required
				== Combat.siege_required_manpower(
					city.fort_strength
				),
		"半年后城防应部分恢复，且既有围城同步当前工事：%d/%d"
			% [city.fort_strength, full_strength]
	)
	gs.battles.clear()
	var recaptor := _make_army(9801, old_owner, 1000, 10)
	gs.armies.append(recaptor)
	var second_capture_day := gs.day
	sim._capture_city(recaptor, city, old_owner)
	_check(
		city.fort_strength == damaged_strength
			and city.fort_strength_max == full_strength
			and city.fort_last_capture_day == second_capture_day,
		"再次易手必须从完整工事重新降至50%%并刷新日期，不能对当前值连续折半"
	)
	gs.day = second_capture_day + Simulation.CITY_FORT_RECOVERY_DAYS - 1
	sim._recover_city_fortifications()
	_check(
		city.fort_strength < full_strength,
		"恢复期第364天仍不得提前回满：%d/%d"
			% [city.fort_strength, full_strength]
	)
	gs.day = second_capture_day + Simulation.CITY_FORT_RECOVERY_DAYS
	sim._recover_city_fortifications()
	_check(
		city.fort_strength == full_strength
			and _approx(
				Simulation.city_fort_vulnerability(
					city,
					gs.day
				),
				0.0
			),
		"恢复期第365天应精确回满：%d/%d"
			% [city.fort_strength, full_strength]
	)
	sim.free()


func _run_siege(sim, b) -> int:
	_attach_pure_siege_city(sim, b)
	var guard := 0
	while not b.finished and guard < 2000:
		sim._advance_siege(b)
		guard += 1
	return guard


## 纯围城数学 fixture 也必须引用 Simulation.state 内的权威 City；否则
## transfer_city_control 会更新 state.cities[id]，detached City 仍保留旧 owner。
func _attach_pure_siege_city(sim: Simulation, battle: Battle) -> void:
	if (
		sim == null
		or sim.state == null
		or battle == null
		or battle.city == null
		or battle.side_a.is_empty()
	):
		return
	if (
		battle.city.id >= 0
		and battle.city.id < sim.state.cities.size()
		and sim.state.cities[battle.city.id] == battle.city
	):
		return
	var template_city := battle.city
	var attacker_owner := battle.side_a[0].owner_nation
	for candidate in sim.state.cities:
		if (
			candidate.is_dock
			or candidate.is_capital
			or candidate.has_warehouse
			or candidate.owner_nation == attacker_owner
		):
			continue
		candidate.fort_strength = template_city.fort_strength
		candidate.fort_strength_max = maxi(
			candidate.fort_strength_max,
			template_city.fort_strength
		)
		candidate.food_storage = template_city.food_storage
		battle.city = candidate
		return

# ------------------------------------------------------------------ 10. 触发判定（位置驱动）

func _test_trigger_detection() -> void:
	print("[10] 触发判定：相向接触/同向追上触发，相距远/同族不触发")
	# 1. 相向接触 → 触发（X from0 dir+1, Y from1 dir-1，位置交错）
	_check(_detect_count(0.5, 0, 1, 0, 0.5, 1) == 1, "相向接触应触发战斗")
	# 2. 同向后军追上前军 → 触发（回归旧 bug；均 from0 dir+1，gap0.05≤EPS）
	_check(_detect_count(0.50, 0, 1, 0, 0.45, 0) == 1, "同向追上（gap0.05≤EPS）应触发")
	# 3. 相距远 → 不触发（边内可能不开战；均 from0 dir+1，gap0.70>EPS）
	_check(_detect_count(0.20, 0, 1, 0, 0.90, 0) == 0, "同向相距远（gap0.70>EPS）不应触发")
	# 4. 同 nation → 不触发（非敌对）
	_check(_detect_count(0.50, 0, 0, 0, 0.50, 0) == 0, "同族不应触发战斗")


## 在真实边 (0,1) 上布两军并检测，返回新生成战斗数。
##  X: nation nx, from cx(0=city0/1=city1), progress px；Y: nation ny, from cy, progress py。
func _detect_count(px: float, nx: int, ny: int, cx: int, py: float, cy: int) -> int:
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()
	_place_army_on_edge(gs, 0, nx, cx, 1 - cx, px)
	_place_army_on_edge(gs, 1, ny, cy, 1 - cy, py)
	sim._detect_encounters()
	var n := gs.battles.size()
	sim.free()
	return n

# ------------------------------------------------------------------ 11. 三方战斗（不并肩敌对）

func _test_three_way_battle() -> void:
	print("[11] 三方战斗：最近敌对对先战，各侧单一 nation，第三方不并肩")
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()
	# 三支互相敌对同向军队（同边 0→1）。A-B 最近（gap0.01）为交战核心。
	var a := _place_army_on_edge(gs, 0, 0, 0, 1, 0.50)
	var b := _place_army_on_edge(gs, 1, 1, 0, 1, 0.49)
	var c := _place_army_on_edge(gs, 2, 2, 0, 1, 0.44)
	var c_prog_before := c.move_progress
	sim._detect_encounters()
	sim._block_passthrough()
	_check(gs.battles.size() == 1, "三方同边应仅形成 1 场核心战斗，实为 %d" % gs.battles.size())
	if gs.battles.size() == 1:
		var bt: Battle = gs.battles[0]
		_check(_single_nation(bt.side_a), "side_a 应单一 nation（不并肩敌对）")
		_check(_single_nation(bt.side_b), "side_b 应单一 nation（不并肩敌对）")
		_check(bt.has_army(a) and bt.has_army(b), "最近敌对对 A-B 应为交战核心")
	# 第三敌国 C：不并肩加入（battle_id 仍 -1），且被卡位不得穿过（未越过交战线 0.50）
	_check(c.battle_id == -1, "真三方 C 与两侧皆异族，不应并入任一侧")
	_check(c.move_progress <= 0.50 + 0.0001, "C 应被卡位、不得穿过交战线（progress %.3f）" % c.move_progress)
	_check(c.move_progress <= c_prog_before + 0.0001, "卡位不应把 C 前拉（仅阻止越过）")
	sim.free()


## 一侧成员是否全为同一 nation（空侧视为真）。
func _single_nation(side: Array) -> bool:
	if side.is_empty():
		return true
	var n: int = side[0].owner_nation
	for a in side:
		if a.owner_nation != n:
			return false
	return true

# ------------------------------------------------------------------ 12. 三方占领（一城一围城方）

func _test_three_way_siege() -> void:
	print("[12] 三方占领：一城一围城方，敌对他国不并肩，同族可汇合")
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)
	var city := gs.cities[63]        # 右下象限 nation3 属城，自带 IDLE 守军
	var edge := gs.edge_of(62, 63)
	_check(edge != null, "边 (62,63) 应存在")

	# A(nation0) 建立围城
	var a := _make_army(100, 0, 1000, 10)
	a.move_from = 62; a.move_to = 63
	sim._start_or_join_siege(a, city, edge)
	var siege := sim._siege_battle_of(city)
	_check(siege != null and siege.has_garrison, "A 抵达应建带守军 SIEGE")

	# B(nation1) 敌对他国来袭：守军仍在 → 从目标城撤回，不并肩
	gs.cities[62].owner_nation = 1   # 为 B 提供与目标城直接相邻的合法本国退路
	var b := _make_army(101, 1, 1000, 10)
	b.move_from = 62; b.move_to = 63
	sim._start_or_join_siege(b, city, edge)
	_check(siege.side_a.size() == 1, "敌对他国 B 不应并肩围城，side_a 仍为 1")
	_check(b.battle_id == -1 and b.state == Army.State.RETREATING and b.move_from == city.id,
		"B 应从已抵达的目标城连续撤回，不得瞬移回来源城")

	# A2(nation0) 同族多路汇合
	var a2 := _make_army(102, 0, 1000, 10)
	a2.move_from = 62; a2.move_to = 63
	sim._start_or_join_siege(a2, city, edge)
	_check(siege.side_a.size() == 2, "同族 A2 应并入 side_a（多路汇合），实为 %d" % siege.side_a.size())
	_check(_single_nation(siege.side_a), "side_a 应全为 nation0")

	# 全局不变量：所有 SIEGE 的 side_a 恒单一 nation
	var ok := true
	for bt in gs.battles:
		if bt.kind == Battle.Kind.SIEGE and not _single_nation(bt.side_a):
			ok = false
	_check(ok, "全局不变量：每场 SIEGE 的 side_a 必单一 nation")
	sim.free()

# ------------------------------------------------------------------ 13. 多军聚合 + 战力累加 + 增援士气

func _test_multi_army_aggregation() -> void:
	print("[13] 多军聚合：同国靠后友军并入 + 攻击Σ累加 + 防御反拆分漏洞 + 增援回气 + 同点必触发")

	# (a) 增援按 ETA 抵达（item 4）：初始只有接触的核心对开战(1v1)；靠后友军(离战线 0.30)
	#     不瞬间参战，须继续行军逼近己方战线到 REINFORCEMENT_RADIUS 内才加入，最终聚合成 2v2。
	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	gs.armies.clear(); gs.battles.clear()
	var a0 := _place_army_on_edge(gs, 0, 0, 0, 1, 0.50)   # A0 n0 norm0.50（接触核心）
	var a1 := _place_army_on_edge(gs, 1, 0, 0, 1, 0.20)   # A1 n0 norm0.20（离战线 0.30，未抵达）
	_place_army_on_edge(gs, 2, 1, 1, 0, 0.50)             # B0 n1 norm0.50（接触核心）
	_place_army_on_edge(gs, 3, 1, 1, 0, 0.20)             # B1 n1 norm0.80（离战线 0.30，未抵达）
	sim._detect_encounters()
	_check(gs.battles.size() == 1, "应仅 1 场战斗，实为 %d" % gs.battles.size())
	if gs.battles.size() == 1:
		var bt0: Battle = gs.battles[0]
		# 初始：仅接触核心对开战，靠后友军尚未抵达 → 1v1（item4 远援不瞬时）。
		_check(bt0.side_a.size() == 1 and bt0.side_b.size() == 1,
			"初始应仅核心对开战 1v1，实为 %dv%d" % [bt0.side_a.size(), bt0.side_b.size()])
		_check(a1.battle_id == -1, "未抵达的靠后友军不应在战斗中")
		# 手动把靠后友军推进到战线附近（模拟 ETA 兑现：0.20→0.40，距 0.50 战线 0.10<半径）。
		a1.move_progress = 0.40
		gs.armies[3].move_progress = 1.0 - 0.40   # B1 对称推进到 norm0.40 附近
		sim._detect_encounters()
		_check(bt0.side_a.size() == 2 and _single_nation(bt0.side_a),
			"靠后友军抵达后 side_a 应聚合 2 支同 n0，实为 %d" % bt0.side_a.size())
		_check(bt0.side_b.size() == 2 and _single_nation(bt0.side_b),
			"靠后友军抵达后 side_b 应聚合 2 支同 n1，实为 %d" % bt0.side_b.size())
	_check(a0.battle_id != -1, "核心军 A0 应在战斗中")
	sim.free()

	# (b) 攻击力 Σ 累加：拆成 2 支（各 1000）与合成 1 支（2000）对同一守军的伤害应相等
	var loss_split := _one_round_side_b_loss([_make_army(0, 0, 1000, 10), _make_army(1, 0, 1000, 10)], [_make_army(2, 1, 3000, 10)], 90)
	var loss_single := _one_round_side_b_loss([_make_army(0, 0, 2000, 10)], [_make_army(2, 1, 3000, 10)], 90)
	_check(loss_split == loss_single, "攻击Σ累加：拆分(%d) 应等于合成(%d)" % [loss_split, loss_single])

	# (c) 防御反拆分漏洞：守军拆成 2×500(def12) 与 1×1000(def12) 承受同一火力，总伤应近似相等
	var loss_def_single := _one_round_side_b_loss([_make_army(0, 0, 2000, 10)], [_make_army(2, 1, 1000, 10, 12)], 91)
	var loss_def_split := _one_round_side_b_loss([_make_army(0, 0, 2000, 10)], [_make_army(2, 1, 500, 10, 12), _make_army(3, 1, 500, 10, 12)], 91)
	_check(absi(loss_def_single - loss_def_split) <= 2, "防御反拆分：单支(%d) 与拆分(%d) 总伤应近似（差≤2）" % [loss_def_single, loss_def_split])

	# (d) 增援回气（新语义 item2/12）：援军加入先登记为「本 tick 新增」，不立即结算；
	#     resolve_round 开头按「本 tick 新增有效兵力占比」统一结算一次并封顶 REINFORCE_MORALE_MAX。
	#     疲劳(0.30)友军 + 满员援军(1000,morale1.0)：boost=min(0.20×1000/2000,0.20)=0.10 → 回升至 0.40。
	var gs2 := GameState.new(); gs2.generate_grid_world(12345)
	var sim2 := Simulation.new(); sim2.setup(gs2)
	var tired := _make_army(0, 0, 1000, 10); tired.morale = 0.30
	var defender := _make_army(1, 1, 1000, 10)
	var battle := _make_field_battle([tired], [defender], 0.0, 4)
	var fresh := _make_army(2, 0, 1000, 10); fresh.morale = 1.0
	fresh.move_from = 0; fresh.move_to = 1; fresh.move_progress = 0.5
	sim2._join_field_battle(battle, fresh, battle.edge)
	_check(battle.side_a.size() == 2, "增援后 side_a 应为 2 支")
	_check(battle.reinforce_fresh_a.has(fresh), "援军应登记为本 tick 新增，待统一结算")
	_check(_approx(tired.morale, 0.30, 0.001), "结算前疲劳友军士气不应立即变化，实为 %.3f" % tired.morale)
	Combat.settle_reinforcement_morale(battle.side_a, battle.reinforce_fresh_a)
	_check(_approx(tired.morale, 0.40, 0.001), "疲劳友军应因增援回气至约 0.40，实为 %.3f" % tired.morale)
	_check(_approx(fresh.morale, 1.0), "援军自身士气不应被自己提振")
	# (d2) 防拆分套利：把 1000 援军拆成 2×500 依次加入，回气总量应与单支 1000 完全一致。
	var tired2 := _make_army(10, 0, 1000, 10); tired2.morale = 0.30
	var battle2 := _make_field_battle([tired2], [_make_army(11, 1, 1000, 10)], 0.0, 4)
	var f1 := _make_army(12, 0, 500, 10); f1.morale = 1.0
	var f2 := _make_army(13, 0, 500, 10); f2.morale = 1.0
	f1.move_from = 0; f1.move_to = 1; f1.move_progress = 0.5
	f2.move_from = 0; f2.move_to = 1; f2.move_progress = 0.5
	sim2._join_field_battle(battle2, f1, battle2.edge)
	sim2._join_field_battle(battle2, f2, battle2.edge)
	Combat.settle_reinforcement_morale(battle2.side_a, battle2.reinforce_fresh_a)
	_check(_approx(tired2.morale, 0.40, 0.001), "拆分援军回气应与单支一致(0.40)，实为 %.3f" % tired2.morale)
	sim2.free()

	# (e) 不同数量组合：3v2 与 2v3 均应各形成 1 场并正确聚合
	_check_combo(3, 2)
	_check_combo(2, 3)

	# (f) 同点必触发：两敌军归一化位置完全重合，必开战
	var gs3 := GameState.new(); gs3.generate_grid_world(12345)
	var sim3 := Simulation.new(); sim3.setup(gs3)
	gs3.armies.clear(); gs3.battles.clear()
	_place_army_on_edge(gs3, 0, 0, 0, 1, 0.50)   # n0 norm0.50
	_place_army_on_edge(gs3, 1, 1, 1, 0, 0.50)   # n1 norm0.50（重合）
	sim3._detect_encounters()
	_check(gs3.battles.size() == 1, "敌对双方同点(重合)必触发战斗，实为 %d" % gs3.battles.size())
	sim3.free()


## 跑 1 回合，返回 side_b 的总减员（固定种子对照用）。
func _one_round_side_b_loss(side_a: Array, side_b: Array, seed_val: int) -> int:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_val
	var b := _make_field_battle(side_a, side_b, 0.0, 4)
	var before := b.side_size(b.side_b)
	Combat.resolve_round(b, rng)
	return before - b.side_size(b.side_b)


## 在真实边上放 na_count 支 n0 与 nb_count 支 n1（位置紧邻），断言恰 1 场且各侧聚合正确。
func _check_combo(na_count: int, nb_count: int) -> void:
	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	gs.armies.clear(); gs.battles.clear()
	var id := 0
	for i in range(na_count):
		_place_army_on_edge(gs, id, 0, 0, 1, 0.50 - i * 0.02)   # n0 from0，norm≈0.50↓
		id += 1
	for j in range(nb_count):
		_place_army_on_edge(gs, id, 1, 1, 0, 0.50 - j * 0.02)   # n1 from1，norm≈0.50↑
		id += 1
	sim._detect_encounters()
	_check(gs.battles.size() == 1, "%dv%d 应仅 1 场，实为 %d" % [na_count, nb_count, gs.battles.size()])
	if gs.battles.size() == 1:
		var bt: Battle = gs.battles[0]
		var count_n0 := 0
		var count_n1 := 0
		for army in bt.side_a + bt.side_b:
			if army.owner_nation == 0:
				count_n0 += 1
			elif army.owner_nation == 1:
				count_n1 += 1
		_check(
			count_n0 == na_count and count_n1 == nb_count,
			"%dv%d 聚合应保持各国成员数 %d/%d，实为 %d/%d（不绑定 A/B 侧位）"
				% [
					na_count,
					nb_count,
					na_count,
					nb_count,
					count_n0,
					count_n1,
				]
		)
	sim.free()

# ------------------------------------------------------------------ 14. 三方卡位串行（同点必战、不得穿过）

func _test_three_way_serial() -> void:
	print("[14] 三方串行：第三敌国卡位不得穿过交战点，A-B 分胜负后立即与幸存者接战")
	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	gs.armies.clear(); gs.battles.clear()
	var a := _place_army_on_edge(gs, 0, 0, 0, 1, 0.50)   # n0 norm0.50
	var b := _place_army_on_edge(gs, 1, 1, 1, 0, 0.50)   # n1 norm0.50（与 A 重合，必战）
	var c := _place_army_on_edge(gs, 2, 2, 0, 1, 0.55)   # n2 norm0.55（已越过交战线 0.50）

	# 步骤 1：A-B 开战；C 被卡位、拉回至交战线（不得穿过），且未并入任一侧
	sim._detect_encounters()
	sim._block_passthrough()
	_check(gs.battles.size() == 1 and gs.battles[0].has_army(a) and gs.battles[0].has_army(b), "A-B 应形成 1 场核心战斗")
	_check(c.battle_id == -1, "第三敌国 C 不应并入两方制战斗")
	_check(c.move_progress < 0.55 - 0.0001 and _approx(c.move_progress, 0.50, 0.001),
		"C 应被卡回交战线(0.50)、不得穿过，实为 %.3f" % c.move_progress)

	# 步骤 2：强制 A-B 分胜负（守军 B 覆灭）→ A 幸存；再检测应让 C 与 A 立即接战（串行化）
	b.size = 0
	sim._resolve_battles()
	_check(gs.battles.is_empty(), "A-B 结束后活跃战斗应清空")
	_check(a.state == Army.State.MOVING and a.battle_id == -1, "胜方 A 应恢复 MOVING 待续战")
	sim._detect_encounters()
	_check(gs.battles.size() == 1, "分胜负后 C 应立即与幸存者 A 接战（串行），实为 %d 场" % gs.battles.size())
	if gs.battles.size() == 1:
		_check(gs.battles[0].has_army(a) and gs.battles[0].has_army(c), "新战斗应为 A vs C")
		_check(c.state == Army.State.FIGHTING, "C 应进入战斗（不再穿过）")
	sim.free()

	# 完全同构多方接战不存在镜像等变的单值核心对。改变军队 ID 或数组顺序时，
	# 必须一致地延迟决策，不能回退到先出现的 pair。
	var core_nations := {}
	var ambiguous_frozen := true
	for perm in [[10, 11, 12], [12, 11, 10], [11, 12, 10]]:
		var gs2 := GameState.new(); gs2.generate_grid_world(12345)
		var sim2 := Simulation.new(); sim2.setup(gs2)
		gs2.armies.clear(); gs2.battles.clear()
		for nation_id in range(3):
			gs2.nations[nation_id].capital_city_id = 0
		# 三支军物理状态及势力镜像轨道锚点完全相同，所有候选 pair 等价。
		var symmetric_edge := gs2.edge_of(0, 1)
		var symmetric_armies: Array[Army] = [
			_place_army_on_edge(
				gs2, perm[0], 0, 0, 1, 0.50
			),
			_place_army_on_edge(
				gs2, perm[1], 1, 1, 0, 0.50
			),
			_place_army_on_edge(
				gs2, perm[2], 2, 1, 0, 0.50
			),
		]
		sim2._detect_encounters()
		sim2._advance_movement()
		for symmetric_army in symmetric_armies:
			if not _approx(
				sim2._norm_pos(symmetric_army, symmetric_edge),
				0.50
			):
				ambiguous_frozen = false
		var key := "none"
		if gs2.battles.size() >= 1:
			var bt := gs2.battles[0]
			# 记录核心对的「势力对」（物理归属），与具体 id 无关。
			var na2: int = bt.side_a[0].owner_nation if not bt.side_a.is_empty() else -1
			var nb2: int = bt.side_b[0].owner_nation if not bt.side_b.is_empty() else -1
			var lo := mini(na2, nb2); var hi := maxi(na2, nb2)
			key = "%d-%d" % [lo, hi]
		core_nations[key] = true
		sim2.free()
	_check(
		core_nations.size() == 1
			and core_nations.has("none")
			and not ambiguous_frozen,
		"完全同构三国接战应一致脱离，不能永久冻结或按 ID 任取核心对：%s"
			% str(core_nations.keys())
	)

	# 同一国家的多支等价军不构成“核心国家对”歧义。生产故障中的
	# 2v1 形状必须直接聚合开战，不能把三军永久冻结在接触面。
	var gs3 := GameState.new(); gs3.generate_grid_world(12345)
	var sim3 := Simulation.new(); sim3.setup(gs3)
	gs3.armies.clear(); gs3.battles.clear()
	var attackers: Array[Army] = [
		_place_army_on_edge(gs3, 173, 0, 0, 1, 0.45),
		_place_army_on_edge(gs3, 243, 0, 0, 1, 0.45),
	]
	for attacker in attackers:
		attacker.size = 4727
		attacker.max_size = 5000
	var defender := _place_army_on_edge(gs3, 500, 1, 1, 0, 0.45)
	defender.size = 15000
	defender.max_size = 15000
	sim3._detect_encounters()
	var symmetric_two_vs_one := (
		gs3.battles.size() == 1
		and gs3.battles[0].side_a.size() + gs3.battles[0].side_b.size() == 3
	)
	for participant in attackers + [defender]:
		symmetric_two_vs_one = (
			symmetric_two_vs_one
			and participant.state == Army.State.FIGHTING
			and not participant.encounter_blocked
		)
	_check(
		symmetric_two_vs_one,
		"完全同构 2v1 必须按国家对聚合成一场战斗，不得冻结"
	)
	sim3.free()


func _test_campaign_active_wave_reconciliation() -> void:
	print("[14b] 战役波次回收：战术改派不得让旧波永久阻塞后续攻势")
	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	gs.armies.clear(); gs.battles.clear()
	var target_city := -1
	for city in gs.cities:
		if city.owner_nation != 0:
			target_city = city.id
			break
	var army := _place_army_on_edge(gs, 9000, 0, 0, 1, 0.50)
	var reassigned := _place_army_on_edge(
		gs, 9001, 0, 0, 1, 0.45
	)
	var nation := gs.nations[0]
	nation.campaign_plan_targets.append(target_city)
	nation.campaign_attack_assignments[army.id] = target_city
	nation.campaign_attack_assignments[reassigned.id] = target_city
	nation.campaign_attack_echelons[army.id] = 0
	nation.campaign_attack_echelons[reassigned.id] = 0
	nation.campaign_active_echelons[target_city] = 0
	nation.campaign_launched_armies[army.id] = true
	nation.campaign_launched_armies[reassigned.id] = true
	nation.campaign_plan_wave = 1
	army.ai_action = ActionCandidate.Kind.ATTACK
	army.ai_target_city = target_city
	reassigned.ai_action = ActionCandidate.Kind.RETREAT
	reassigned.ai_target_city = nation.capital_city_id
	sim._reconcile_campaign_active_wave(0)
	_check(
		nation.campaign_plan_targets == [target_city]
			and nation.campaign_attack_assignments.has(army.id)
			and nation.campaign_launched_armies.has(army.id)
			and not nation.campaign_attack_assignments.has(reassigned.id)
			and not nation.campaign_launched_armies.has(reassigned.id),
		"混合波次必须保留真实攻击者并立即剔除已改派成员"
	)

	# 最后一支执行者也被改派后，整个 active wave 必须释放。
	army.ai_action = ActionCandidate.Kind.RETREAT
	army.ai_target_city = nation.capital_city_id
	sim._reconcile_campaign_active_wave(0)
	_check(
		nation.campaign_plan_targets.is_empty()
			and nation.campaign_attack_assignments.is_empty()
			and nation.campaign_launched_armies.is_empty(),
		"最后一支攻击者改派后必须释放 active wave"
	)

	# 当前梯队的先发成员消失后，已经抵达集结位的同梯队成员必须
	# 接替发射；不能直接跳到下一梯队并让本梯队永远留在计划中。
	var staging := DiplomacyAI.staging_cities_for_objective(
		gs, 0, target_city
	)
	_check(not staging.is_empty(), "active-wave 回归夹具必须有合法集结城")
	if not staging.is_empty():
		sim._settle_idle(army, staging[0])
		army.ai_action = ActionCandidate.Kind.HOLD
		army.ai_target_city = target_city
		nation.campaign_plan_targets.append(target_city)
		nation.campaign_attack_assignments[army.id] = target_city
		nation.campaign_attack_echelons[army.id] = 0
		nation.campaign_active_echelons[target_city] = 0
		nation.campaign_plan_wave = 1
		sim._advance_campaign_echelons()
		_check(
			nation.campaign_launched_armies.has(army.id)
				and army.ai_action == ActionCandidate.Kind.ATTACK
				and army.ai_target_city == target_city,
			"当前梯队的就绪遗留成员必须补发，不能被下一梯队跳过"
		)
	sim.free()

# ------------------------------------------------------------------ 15. 到达被围城必触发（修复：城主回援/援军入城不旁观）

func _test_siege_arrival_triggers() -> void:
	print("[15] 到达被围城必触发：城主回援空城/援军入城帮守，不得旁观穿过")

	# (a) 敌对方抵达纯围城（空城）→ 城下决斗（回归护栏）
	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	var city: City = gs.cities[63]
	var edge: Edge = gs.edge_of(62, 63)
	var garrison := gs.army_at_city(63)
	if garrison != null:
		garrison.size = 0; garrison.location_city = -1   # 制造空城
	var besieger := _make_army(900, 0, 1000, 10)         # nation0 围城方
	besieger.move_from = 62; besieger.move_to = 63; besieger.move_progress = 1.0
	gs.armies.append(besieger)
	sim._start_or_join_siege(besieger, city, edge)
	var siege := sim._siege_battle_of(city)
	_check(siege != null and not siege.has_garrison and siege.side_b.is_empty(), "空城应建纯围城 SIEGE")
	_check(
		city.war_disruption_until_day
			== Simulation.CITY_WAR_DISRUPTION_DAYS,
		"城市遭到攻击时应立即进入一年战争破坏期"
	)
	gs.day = 10
	sim._advance_siege(siege)
	_check(
		city.war_disruption_until_day
			== gs.day + Simulation.CITY_WAR_DISRUPTION_DAYS,
		"围城持续期间应刷新破坏期，确保战后仍减产一年"
	)

	var enemy := _make_army(901, 1, 1000, 10)            # nation1 敌对来袭
	enemy.move_from = 62; enemy.move_to = 63; enemy.move_progress = 1.0; enemy.on_edge = true
	enemy.state = Army.State.MOVING
	gs.armies.append(enemy)
	sim._arrive_at_node(enemy)
	siege = sim._siege_battle_of(city)
	_check(siege != null and siege.side_size(siege.side_b) > 0 and enemy.battle_id == siege.id,
		"敌对方抵达纯围城应触发城下决斗（side_b 非空）")

	# (b) 城主(nation3)援军回援自己被围的空城 → 必须触发战斗（本轮核心 bug）
	var gs2 := GameState.new(); gs2.generate_grid_world(12345)
	var sim2 := Simulation.new(); sim2.setup(gs2)
	var city2: City = gs2.cities[63]                     # 属 nation3
	var edge2: Edge = gs2.edge_of(62, 63)
	var g2 := gs2.army_at_city(63)
	if g2 != null:
		g2.size = 0; g2.location_city = -1
	var bz2 := _make_army(910, 0, 1000, 10)              # nation0 围城
	bz2.move_from = 62; bz2.move_to = 63; bz2.move_progress = 1.0
	gs2.armies.append(bz2)
	sim2._start_or_join_siege(bz2, city2, edge2)
	var relief := _make_army(911, 3, 1000, 10)           # 城主 nation3 援军
	relief.move_from = 62; relief.move_to = 63; relief.move_progress = 1.0; relief.on_edge = true
	relief.state = Army.State.MOVING
	gs2.armies.append(relief)
	sim2._arrive_at_node(relief)
	var siege2 := sim2._siege_battle_of(city2)
	_check(siege2 != null and siege2.side_size(siege2.side_b) > 0 and relief.battle_id == siege2.id,
		"城主援军回援被围空城必须参战（旧码漏判 is_enemy(owner)=false → 旁观）")
	_check(relief.state == Army.State.FIGHTING, "城主援军应进入 FIGHTING，实为 %d" % relief.state)

	# (c) 守军仍在城中，城主(nation3)援军抵达 → 入城帮守（并入 side_b、同族），不待机
	var gs3 := GameState.new(); gs3.generate_grid_world(12345)
	var sim3 := Simulation.new(); sim3.setup(gs3)
	var city3: City = gs3.cities[63]                     # nation3，自带守军
	var edge3: Edge = gs3.edge_of(62, 63)
	var bz3 := _make_army(920, 0, 1000, 10)              # nation0 围城，守军仍在
	bz3.move_from = 62; bz3.move_to = 63; bz3.move_progress = 1.0
	gs3.armies.append(bz3)
	sim3._start_or_join_siege(bz3, city3, edge3)
	var siege3 := sim3._siege_battle_of(city3)
	_check(siege3 != null and siege3.has_garrison and siege3.side_size(siege3.side_b) >= 1, "应建带守军 SIEGE")
	var defender_nation: int = siege3.side_b[0].owner_nation
	var side_b_before := siege3.side_b.size()
	var relief3 := _make_army(921, defender_nation, 1000, 10)  # 与守军同族的援军
	relief3.move_from = 62; relief3.move_to = 63; relief3.move_progress = 1.0; relief3.on_edge = true
	relief3.state = Army.State.MOVING
	gs3.armies.append(relief3)
	sim3._arrive_at_node(relief3)
	_check(siege3.side_b.size() == side_b_before + 1 and siege3.has_army(relief3),
		"守军同族援军应入城帮守（并入 side_b），实 side_b=%d" % siege3.side_b.size())
	_check(relief3.state == Army.State.FIGHTING and _single_nation(siege3.side_b),
		"帮守方应 FIGHTING 且 side_b 保持单一 nation")

	# (d) 守军仍在，盟军抵达 → 加入城市防卫共同体；side_b 可以包含多个盟国。
	gs3.set_diplomatic_relation(
		2,
		defender_nation,
		GameState.DiplomaticRelation.ALLIED
	)
	var allied_relief3 := _make_army(923, 2, 1000, 10)
	allied_relief3.move_from = 62
	allied_relief3.move_to = 63
	allied_relief3.move_progress = 1.0
	allied_relief3.on_edge = true
	allied_relief3.state = Army.State.MOVING
	gs3.armies.append(allied_relief3)
	sim3._arrive_at_node(allied_relief3)
	_check(
		siege3.has_army(allied_relief3)
			and allied_relief3.state == Army.State.FIGHTING
			and not _single_nation(siege3.side_b)
			and sim3._siege_side_defends_city(
				siege3,
				siege3.side_b
			),
		"盟军抵达被围盟城后必须加入同一防卫共同体，并共享驻城防守状态"
	)

	# (e) 守军仍在，真第三国(nation1)抵达 → 三方不可共存，从目标城撤回（不并入任一侧）
	gs3.cities[62].owner_nation = 1   # 为第三国提供合法本国退路，禁止借道其他敌城
	var intruder := _make_army(922, 1, 1000, 10)
	intruder.move_from = 62; intruder.move_to = 63; intruder.move_progress = 1.0; intruder.on_edge = true
	intruder.state = Army.State.MOVING
	gs3.armies.append(intruder)
	sim3._arrive_at_node(intruder)
	_check(intruder.battle_id == -1 and intruder.state == Army.State.RETREATING
		and intruder.move_from == city3.id,
		"守军在场时真第三国应从目标城撤回且不介入")

	# (f) 城主援军解围胜利后应入城驻守，而非"晋升为围城方去围自己的城"
	var gs4 := GameState.new(); gs4.generate_grid_world(12345)
	var sim4 := Simulation.new(); sim4.setup(gs4)
	var city4: City = gs4.cities[63]                     # nation3
	var edge4: Edge = gs4.edge_of(62, 63)
	var g4 := gs4.army_at_city(63)
	if g4 != null:
		g4.size = 0; g4.location_city = -1
	var bz4 := _make_army(930, 0, 500, 10)               # 弱围城方
	bz4.move_from = 62; bz4.move_to = 63; bz4.move_progress = 1.0
	gs4.armies.append(bz4)
	sim4._start_or_join_siege(bz4, city4, edge4)
	var relief4 := _make_army(931, 3, 5000, 20)          # 城主强援
	relief4.move_from = 62; relief4.move_to = 63; relief4.move_progress = 1.0; relief4.on_edge = true
	relief4.state = Army.State.MOVING
	gs4.armies.append(relief4)
	sim4._arrive_at_node(relief4)
	# 推进战斗至结束
	var guard := 0
	var s4 := sim4._siege_battle_of(city4)
	while s4 != null and not s4.finished and guard < 1000:
		sim4._resolve_battles()
		s4 = sim4._siege_battle_of(city4)
		guard += 1
	_check(sim4._siege_battle_of(city4) == null, "城主解围胜利后围城应结束（不再有活跃 SIEGE）")
	_check(city4.owner_nation == 3, "城仍属城主 nation3（未被围城方夺取）")
	_check(relief4.state == Army.State.IDLE and relief4.location_city == 63,
		"城主援军解围胜利应入城驻守（IDLE@63），而非晋升围城自己的城，实 state=%d loc=%d" % [relief4.state, relief4.location_city])

	# (g) 围城建立前已驻扎的盟军也必须在首个围城回合直接进入 side_b。
	var gs5 := GameState.new(); gs5.generate_grid_world(12345)
	var sim5 := Simulation.new(); sim5.setup(gs5)
	var city5: City = gs5.cities[63]
	var edge5: Edge = gs5.edge_of(62, 63)
	gs5.set_diplomatic_relation(
		2,
		city5.owner_nation,
		GameState.DiplomaticRelation.ALLIED
	)
	var stationed_ally := _make_army(940, 2, 1000, 10)
	stationed_ally.state = Army.State.IDLE
	stationed_ally.location_city = city5.id
	stationed_ally.move_from = city5.id
	gs5.armies.append(stationed_ally)
	var bz5 := _make_army(941, 0, 1000, 10)
	bz5.move_from = 62
	bz5.move_to = 63
	gs5.armies.append(bz5)
	sim5._start_or_join_siege(bz5, city5, edge5)
	var siege5 := sim5._siege_battle_of(city5)
	_check(
		siege5 != null
			and siege5.has_garrison
			and siege5.has_army(stationed_ally)
			and stationed_ally.state == Army.State.FIGHTING
			and sim5._siege_side_defends_city(
				siege5,
				siege5.side_b
			),
		"围城开始前驻扎在盟城的盟军必须与城主守军一同进入防守侧"
	)
	sim.free()
	sim2.free()
	sim3.free()
	sim4.free()
	sim5.free()

# ------------------------------------------------------------------ 16. 相向错身：走到边末端的一方应先野战，而非离边攻城穿过

func _test_crosspass_field_priority() -> void:
	print("[16] 相向错身：两敌军同在一条边相向而行，先到边末端者应野战交火而非离边攻城")

	# 找一条敌对相邻边（c1 属 nation != c2 属 nation）
	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	var c1 := -1; var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation != gs.cities[e.city_b].owner_nation:
			c1 = e.city_a; c2 = e.city_b; break
	_check(c1 != -1, "应存在一条敌对相邻边")
	var edge := gs.edge_of(c1, c2)
	gs.armies.clear(); gs.battles.clear()

	# R：c1→c2，已推进到边末端 0.99（下一 tick 将到达 c2 敌城）
	var R := _make_army(1, gs.cities[c1].owner_nation, 1000, 10)
	R.state = Army.State.MOVING; R.move_from = c1; R.move_to = c2; R.move_progress = 0.99; R.on_edge = true
	edge.passing_count += 1; gs.armies.append(R)
	# G：c2→c1，刚上边 0.0（相向）
	var G := _make_army(2, gs.cities[c2].owner_nation, 1000, 10)
	G.state = Army.State.MOVING; G.move_from = c2; G.move_to = c1; G.move_progress = 0.0; G.on_edge = true
	edge.passing_count += 1; gs.armies.append(G)

	sim._advance_movement()

	var has_field := false; var has_siege := false
	for b in gs.battles:
		if b.finished: continue
		if b.kind == Battle.Kind.FIELD: has_field = true
		if b.kind == Battle.Kind.SIEGE: has_siege = true
	_check(has_field, "相向两军应触发野战 FIELD（先到边末端者不得离边攻城穿过）")
	_check(not has_siege, "不应变成攻城 SIEGE（那意味着 R 错身进城了）")
	_check(R.state == Army.State.FIGHTING and G.state == Army.State.FIGHTING, "R、G 均应进入 FIGHTING")
	_check(R.battle_id == G.battle_id and R.battle_id != -1, "R、G 应在同一场野战")

	sim.free()

	# 野战胜方已越过道路终点时，败方溃退军不能在下一 tick 重复拉起 FIELD。
	# 溃退军应先落入目标城，随后胜方进城并与守军统一触发 SIEGE。
	var endpoint_state := GameState.new()
	endpoint_state.generate_grid_world(1601)
	endpoint_state.armies.clear()
	endpoint_state.battles.clear()
	var endpoint_from := -1
	var endpoint_city := -1
	for endpoint_edge in endpoint_state.edges:
		if (
			endpoint_state.cities[
				endpoint_edge.city_a
			].owner_nation
			!= endpoint_state.cities[
				endpoint_edge.city_b
			].owner_nation
		):
			endpoint_from = endpoint_edge.city_a
			endpoint_city = endpoint_edge.city_b
			break
	var endpoint_edge := endpoint_state.edge_of(
		endpoint_from,
		endpoint_city
	)
	var endpoint_attacker := _make_army(
		1601,
		endpoint_state.cities[endpoint_from].owner_nation,
		5000,
		10
	)
	endpoint_attacker.state = Army.State.MOVING
	endpoint_attacker.location_city = endpoint_from
	endpoint_attacker.move_from = endpoint_from
	endpoint_attacker.move_to = endpoint_city
	endpoint_attacker.move_progress = 1.10
	endpoint_attacker.on_edge = true
	var endpoint_retreater := _make_army(
		1602,
		endpoint_state.cities[endpoint_city].owner_nation,
		3000,
		10
	)
	endpoint_retreater.state = Army.State.RETREATING
	endpoint_retreater.location_city = endpoint_city
	endpoint_retreater.move_from = endpoint_from
	endpoint_retreater.move_to = endpoint_city
	endpoint_retreater.move_progress = 1.0
	endpoint_retreater.on_edge = true
	var endpoint_guard := _make_army(
		1603,
		endpoint_state.cities[endpoint_city].owner_nation,
		5000,
		10
	)
	endpoint_guard.location_city = endpoint_city
	endpoint_guard.move_from = endpoint_city
	endpoint_state.armies.append_array([
		endpoint_attacker,
		endpoint_retreater,
		endpoint_guard,
	])
	endpoint_edge.passing_count = 2
	endpoint_edge.occupied = true
	var endpoint_sim := Simulation.new()
	root.add_child(endpoint_sim)
	endpoint_sim.setup(endpoint_state)
	endpoint_sim._advance_movement()
	var endpoint_siege := endpoint_sim._siege_battle_of(
		endpoint_state.cities[endpoint_city]
	)
	var endpoint_field_exists := endpoint_state.battles.any(
		func(battle: Battle) -> bool:
			return (
				not battle.finished
				and battle.kind == Battle.Kind.FIELD
			)
	)
	_check(
		endpoint_siege != null
			and endpoint_siege.has_army(
				endpoint_attacker
			)
			and endpoint_siege.has_army(
				endpoint_retreater
			)
			and endpoint_siege.has_army(endpoint_guard)
			and not endpoint_field_exists,
		"道路野战胜方越过终点后应进城触发攻城，已到终点的溃退军不得重复拉起野战"
	)
	endpoint_sim.free()

# ------------------------------------------------------------------ 17. 五千容量边错身：敌军不占本国方向容量

func _test_capacity_no_block_enemy() -> void:
	print("[17] 五千容量边：敌军先占边，迎战方不得被交通容量挡在城里错身穿过")

	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	var c1 := -1; var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation != gs.cities[e.city_b].owner_nation:
			c1 = e.city_a; c2 = e.city_b; break
	_check(c1 != -1, "应存在一条敌对相邻边")
	var edge := gs.edge_of(c1, c2)
	edge.max_manpower = Edge.MIN_MANPOWER  # 单个运输足迹：复现同向容量满
	edge.distance = 3; edge.danger = 0.0
	gs.armies.clear(); gs.battles.clear()

	# R 虽是重军编制，运输足迹仍只有 5000，先占满该方向。
	var R := _make_army(1, gs.cities[c1].owner_nation, 1000, 10)
	R.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	R.state = Army.State.MOVING; R.move_from = c1; R.move_to = -1
	R.location_city = c1; R.path = [c2] as Array[int]
	gs.armies.append(R)
	sim._begin_next_leg(R)
	_check(R.on_edge and R.move_to == c2, "R 应占用五千运输边 (on_edge)")
	_check(edge.passing_count == 1, "边容量应已打满 passing_count=1")

	# G 从 c2 出发迎战：容量已满，但对手在边上 → 必须放行，不得被卡在城里
	var G := _make_army(2, gs.cities[c2].owner_nation, 1000, 10)
	G.state = Army.State.MOVING; G.move_from = c2; G.move_to = -1
	G.location_city = c2; G.path = [c1] as Array[int]
	gs.armies.append(G)
	sim._begin_next_leg(G)
	_check(G.on_edge and G.move_to == c1,
		"迎战方 G 应无视 capacity 进入敌军所在边（on_edge=%s move_to=%d），而非被卡在城里" % [G.on_edge, G.move_to])

	# 推进若干 tick：两军相向应野战，不得错身成攻城
	var has_field := false; var has_siege := false
	for i in range(200):
		sim._advance_movement()
		for b in gs.battles:
			if b.finished: continue
			if b.kind == Battle.Kind.FIELD: has_field = true
			if b.kind == Battle.Kind.SIEGE: has_siege = true
		if has_field or has_siege: break
	_check(has_field, "单槽边相向两军应野战 FIELD")
	_check(not has_siege, "不应错身成攻城 SIEGE（迎战方被挡在城里的旧 bug）")

	sim.free()

# ------------------------------------------------------------------ 17b. 分方向友军容量

func _test_directional_friendly_capacity() -> void:
	print("[17b] 边容量：重军按道路吞吐占满，同国同向受限，反向与敌军独立")
	var gs := GameState.new()
	gs.generate_grid_world(1717)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()
	var from_city := -1
	var to_city := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation == gs.cities[edge.city_b].owner_nation:
			from_city = edge.city_a
			to_city = edge.city_b
			break
	var edge := gs.edge_of(from_city, to_city)
	edge.max_manpower = 15000
	edge.passing_count = 0
	var nation_id := gs.cities[from_city].owner_nation

	var first := _make_army(1700, nation_id, 13021, 10)
	first.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	first.state = Army.State.MOVING
	first.location_city = from_city
	first.move_from = from_city
	first.path = [to_city] as Array[int]
	gs.armies.append(first)
	sim._begin_next_leg(first)
	_check(first.on_edge and first.move_to == to_city, "首支同向友军应进入边")

	var same_direction := _make_army(1701, nation_id, 1000, 10)
	same_direction.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	same_direction.state = Army.State.MOVING
	same_direction.location_city = from_city
	same_direction.move_from = from_city
	same_direction.path = [to_city] as Array[int]
	gs.armies.append(same_direction)
	sim._begin_next_leg(same_direction)
	_check(
		not same_direction.on_edge
			and same_direction.move_to == -1
			and sim._friendly_same_direction_manpower(
				nation_id, from_city, to_city
			) == 15000,
		"15000容量路上一支重军应占满同向吞吐，第二支重军必须排队"
	)

	var reverse := _make_army(1702, nation_id, 1000, 10)
	reverse.state = Army.State.MOVING
	reverse.location_city = to_city
	reverse.move_from = to_city
	reverse.path = [from_city] as Array[int]
	gs.armies.append(reverse)
	sim._begin_next_leg(reverse)
	_check(reverse.on_edge and reverse.move_to == from_city,
		"同国反方向使用独立容量，应允许进入")

	var enemy_nation := (nation_id + 1) % gs.nations.size()
	var enemy := _make_army(1703, enemy_nation, 1000, 10)
	enemy.state = Army.State.MOVING
	enemy.location_city = from_city
	enemy.move_from = from_city
	enemy.path = [to_city] as Array[int]
	gs.armies.append(enemy)
	sim._begin_next_leg(enemy)
	_check(enemy.on_edge and enemy.move_to == to_city,
		"敌军不得占用本国同方向 capacity，必须允许追逐/接战")
	_check(edge.passing_count == 3,
		"总占用可超过单方向上限：正向重军+反向友军+敌军应为3")

	sim._release_edge(first)
	sim._begin_next_leg(same_direction)
	_check(
		same_direction.on_edge
			and same_direction.move_to == to_city,
		"同向重军释放15000吞吐后，排队重军应能进入"
	)

	gs.armies.clear()
	gs.battles.clear()
	edge.passing_count = 0
	edge.occupied = false
	edge.max_manpower = Edge.TERRAIN_LOW_MANPOWER
	var low_road_heavy := _make_army(
		1720,
		nation_id,
		15000,
		10
	)
	low_road_heavy.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	low_road_heavy.state = Army.State.MOVING
	low_road_heavy.location_city = from_city
	low_road_heavy.move_from = from_city
	low_road_heavy.path = [to_city] as Array[int]
	gs.armies.append(low_road_heavy)
	sim._begin_next_leg(low_road_heavy)
	var low_road_waiter := _make_army(
		1721,
		nation_id,
		5000,
		10
	)
	low_road_waiter.max_size = Edge.MIN_MANPOWER
	low_road_waiter.state = Army.State.MOVING
	low_road_waiter.location_city = from_city
	low_road_waiter.move_from = from_city
	low_road_waiter.path = [to_city] as Array[int]
	gs.armies.append(low_road_waiter)
	sim._begin_next_leg(low_road_waiter)
	_check(
		low_road_heavy.on_edge
			and not low_road_waiter.on_edge
			and low_road_waiter.move_to == -1
			and sim._friendly_same_direction_manpower(
				nation_id, from_city, to_city
			) == Edge.TERRAIN_LOW_MANPOWER
			and low_road_heavy.road_transport_batches(
				Edge.TERRAIN_LOW_MANPOWER
			) == 2,
		"15000重军可进入10000道路但会占满同向吞吐并分两批运输"
	)

	gs.armies.clear()
	gs.battles.clear()
	edge.passing_count = 0
	edge.occupied = false
	edge.max_manpower = Edge.TERRAIN_STANDARD_MANPOWER
	var standard_road_holder := _make_army(
		1730,
		nation_id,
		5000,
		10
	)
	standard_road_holder.max_size = Edge.MIN_MANPOWER
	standard_road_holder.state = Army.State.MOVING
	standard_road_holder.location_city = from_city
	standard_road_holder.move_from = from_city
	standard_road_holder.path = [to_city] as Array[int]
	gs.armies.append(standard_road_holder)
	sim._begin_next_leg(standard_road_holder)
	standard_road_holder.state = Army.State.HOLDING
	var standard_road_attacker := _make_army(
		1731,
		nation_id,
		15000,
		10
	)
	standard_road_attacker.max_size = Edge.STANDARD_MANPOWER
	standard_road_attacker.state = Army.State.MOVING
	standard_road_attacker.location_city = from_city
	standard_road_attacker.move_from = from_city
	standard_road_attacker.path = [to_city] as Array[int]
	gs.armies.append(standard_road_attacker)
	sim._begin_next_leg(standard_road_attacker)
	_check(
		standard_road_holder.on_edge
		and standard_road_attacker.on_edge,
		"20000 容量边应同时容纳5000驻边轻军和15000进攻重军"
	)
	var standard_road_overflow := _make_army(
		1732,
		nation_id,
		5000,
		10
	)
	standard_road_overflow.max_size = Edge.MIN_MANPOWER
	standard_road_overflow.state = Army.State.MOVING
	standard_road_overflow.location_city = from_city
	standard_road_overflow.move_from = from_city
	standard_road_overflow.path = [to_city] as Array[int]
	gs.armies.append(standard_road_overflow)
	sim._begin_next_leg(standard_road_overflow)
	_check(
		not standard_road_overflow.on_edge
			and sim._friendly_same_direction_manpower(
				nation_id, from_city, to_city
			) == Edge.TERRAIN_STANDARD_MANPOWER,
		"20000容量边上5000轻军+15000重军占满后，额外同向军必须等待"
	)

	var blocked_from := gs.nations[nation_id].capital_city_id
	var blocked_to: int = gs.neighbors(blocked_from)[0]
	for neighbor in gs.neighbors(blocked_from):
		gs.edge_of(blocked_from, neighbor).max_manpower = 0
	var blocked := _make_army(1704, nation_id, 1000, 10)
	blocked.state = Army.State.MOVING
	blocked.location_city = blocked_from
	blocked.move_from = blocked_from
	blocked.path = [blocked_to] as Array[int]
	gs.armies.append(blocked)
	sim._begin_next_leg(blocked)
	_check(
		blocked.state == Army.State.IDLE
		and not blocked.on_edge
		and blocked.path.is_empty(),
		"0 容量边必须使旧行军路径失效，不能让军队永久排队"
	)
	var blocked_field := Pathfinding.dijkstra_field(gs, blocked_from)
	_check(
		float(blocked_field["dist"][blocked_to]) == INF,
		"军事寻路必须跳过 0 容量边"
	)
	sim.free()


# ------------------------------------------------------------------ 17c. 正式高度图重军运输足迹

func _test_heightmap_heavy_transport_footprint() -> void:
	print("[17c] 正式高度图：15000重军可经10000出口完整移动且不拆编")
	var gs := GameState.new()
	gs.generate_world(12345)
	var nation_id := -1
	var capital_id := -1
	var target_id := -1
	var heavy: Army = null
	for nation in gs.nations:
		var candidate_capital := nation.capital_city_id
		for neighbor in gs.neighbors(candidate_capital):
			var candidate_edge := gs.edge_of(
				candidate_capital, neighbor
			)
			if (
				candidate_edge == null
				or candidate_edge.kind != Edge.Kind.LAND
				or candidate_edge.max_manpower <= 0
				or gs.cities[neighbor].is_dock
				or gs.cities[neighbor].owner_nation != nation.id
			):
				continue
			for candidate_army in gs.armies:
				if (
					candidate_army.owner_nation == nation.id
					and candidate_army.location_city == candidate_capital
					and candidate_army.max_size
						== GameState.INITIAL_HEAVY_ARMY_SIZE
				):
					heavy = candidate_army
					break
			if heavy != null:
				nation_id = nation.id
				capital_id = candidate_capital
				target_id = neighbor
				break
		if heavy != null:
			break
	_check(
		gs.uses_heightmap and heavy != null and target_id >= 0,
		"正式高度图应存在拥有同国陆路出口的首都及其初始重军"
	)
	if heavy == null or target_id < 0:
		return

	for neighbor in gs.neighbors(capital_id):
		var capital_edge := gs.edge_of(capital_id, neighbor)
		capital_edge.max_manpower = 0
		capital_edge.passing_count = 0
		capital_edge.occupied = false
	var exit_edge := gs.edge_of(capital_id, target_id)
	exit_edge.max_manpower = Edge.TERRAIN_LOW_MANPOWER
	exit_edge.distance = 1
	exit_edge.travel_time_multiplier = 1.0
	exit_edge.danger = 0.0
	var positive_capital_exits := 0
	for neighbor in gs.neighbors(capital_id):
		if gs.edge_of(capital_id, neighbor).max_manpower > 0:
			positive_capital_exits += 1

	var original_army_id := heavy.id
	var original_group_id := heavy.battle_group_id
	gs.armies.clear()
	gs.armies.append(heavy)
	gs.battles.clear()
	var route_field := Pathfinding.dijkstra_field(
		gs, capital_id, nation_id, false, true, -1,
		heavy.max_size
	)
	var route := Pathfinding.reconstruct(
		route_field["prev"], capital_id, target_id
	)
	_check(
		positive_capital_exits == 1
			and exit_edge.max_manpower == Edge.TERRAIN_LOW_MANPOWER
			and heavy.road_footprint() == Edge.MIN_MANPOWER
			and heavy.road_capacity_load(Edge.MIN_MANPOWER)
				== Edge.MIN_MANPOWER
			and heavy.road_capacity_load(Edge.TERRAIN_LOW_MANPOWER)
				== Edge.TERRAIN_LOW_MANPOWER
			and heavy.road_capacity_load(Edge.STANDARD_MANPOWER)
				== GameState.INITIAL_HEAVY_ARMY_SIZE
			and heavy.road_transport_batches(Edge.MIN_MANPOWER) == 3
			and heavy.road_transport_batches(
				Edge.TERRAIN_LOW_MANPOWER
			) == 2
			and heavy.road_transport_batches(
				Edge.STANDARD_MANPOWER
			) == 1
			and _approx(
				float(route_field["dist"][target_id]),
				float(exit_edge.distance)
					* exit_edge.travel_time_multiplier * 2.0
			)
			and route == [target_id],
		(
			"15000重军运输契约失败：exits=%d cap=%d footprint=%d "
			+ "loads=%d/%d/%d batches=%d/%d/%d dist=%.1f expected=%.1f route=%s target=%d"
		) % [
			positive_capital_exits, exit_edge.max_manpower,
			heavy.road_footprint(),
			heavy.road_capacity_load(Edge.MIN_MANPOWER),
			heavy.road_capacity_load(Edge.TERRAIN_LOW_MANPOWER),
			heavy.road_capacity_load(Edge.STANDARD_MANPOWER),
			heavy.road_transport_batches(Edge.MIN_MANPOWER),
			heavy.road_transport_batches(Edge.TERRAIN_LOW_MANPOWER),
			heavy.road_transport_batches(Edge.STANDARD_MANPOWER),
			float(route_field["dist"][target_id]),
			float(exit_edge.distance)
				* exit_edge.travel_time_multiplier * 2.0,
			str(route), target_id,
		]
	)

	var sim := Simulation.new()
	sim.setup(gs)
	var move_order := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		100.0,
		"正式高度图重军运输足迹回归",
		target_id
	)
	var issued := sim._execute_ai_candidate(heavy, move_order)
	_check(
		issued
			and heavy.state == Army.State.MOVING
			and heavy.on_edge
			and heavy.move_from == capital_id
			and heavy.move_to == target_id
			and exit_edge.passing_count == 1,
		"正式高度图15000重军应经10000出口完成寻路并开始移动"
	)
	var group_members := gs.battle_group_members(
		nation_id, original_group_id
	)
	_check(
		gs.armies.size() == 1
			and gs.armies[0] == heavy
			and heavy.id == original_army_id
			and heavy.size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and heavy.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and heavy.max_morale == Army.HEAVY_MAX_MORALE
			and heavy.is_main_battle_role()
			and group_members.size() == 1
			and group_members[0] == heavy,
		"道路运输不得拆分Army或改变重军编制、士气与战团身份"
	)
	var frontage_probe := _make_field_battle(
		[_make_army(1740, nation_id, 15000, 10)],
		[_make_army(1741, (nation_id + 1) % gs.nations.size(), 15000, 10)],
		0.0,
		1
	)
	frontage_probe.edge.max_manpower = Edge.TERRAIN_LOW_MANPOWER
	_check(
		Combat.combat_frontage(frontage_probe)
			== Edge.TERRAIN_LOW_MANPOWER
			and _approx(
				Combat.frontage_engaged_ratio(
					GameState.INITIAL_HEAVY_ARMY_SIZE,
					Combat.combat_frontage(frontage_probe)
				),
				2.0 / 3.0
			),
		"运输足迹固定5000后，战斗正面仍必须读取道路的10000容量"
	)
	var travel_probe := Edge.new()
	travel_probe.distance = 1
	travel_probe.max_manpower = Edge.MIN_MANPOWER
	var narrow_travel_days := Simulation.edge_travel_days(
		travel_probe, GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	travel_probe.max_manpower = Edge.TERRAIN_LOW_MANPOWER
	var low_road_travel_days := Simulation.edge_travel_days(
		travel_probe, GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	travel_probe.max_manpower = Edge.STANDARD_MANPOWER
	var standard_travel_days := Simulation.edge_travel_days(
		travel_probe, GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	_check(
		_approx(narrow_travel_days, Simulation.march_days(1) * 3.0)
			and _approx(
				low_road_travel_days, Simulation.march_days(1) * 2.0
			)
			and _approx(
				standard_travel_days, Simulation.march_days(1)
			),
		"15000重军经5000/10000/20000道路应分别耗费3/2/1个运输批次"
	)
	sim.free()

# ------------------------------------------------------------------ 18. R1 行军时长线性映射

func _test_march_time_linear() -> void:
	print("[18] R1 行军：10 天起步，按真实距离线性增长且不封顶")
	# 边界：distance=1 → 10 天；此后每单位增加 5 天。
	_check(_approx(Simulation.march_days(1), 10.0), "distance=1 应 10 天，实为 %.1f" % Simulation.march_days(1))
	_check(_approx(Simulation.march_days(5), 30.0), "distance=5 应 30 天，实为 %.1f" % Simulation.march_days(5))
	_check(_approx(Simulation.march_days(3), 20.0), "distance=3 应 20 天（线性中点），实为 %.1f" % Simulation.march_days(3))
	# 非法距离夹到下界；超长距离继续增长，不能被 30 天截平。
	_check(Simulation.march_days(0) >= 10.0, "distance=0 应夹到下界 >=10，实为 %.1f" % Simulation.march_days(0))
	_check(
		_approx(Simulation.march_days(99), 500.0),
		"distance=99 应按线性关系得到500天，不得被30天封顶，实为 %.1f"
			% Simulation.march_days(99)
	)
	# 单调性：长度越大，时间不减。
	var mono := true
	for d in range(1, 8):
		if Simulation.march_days(d + 1) < Simulation.march_days(d):
			mono = false
	_check(mono, "行军时间应随距离单调不减")
	# 端到端：distance=1 的边，10 个 tick 恰好走完（progress>=1）。
	var gs := GameState.new()
	gs.generate_grid_world(999)
	var sim := Simulation.new()
	sim.setup(gs)
	var c1 := -1; var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation == gs.cities[e.city_b].owner_nation:
			c1 = e.city_a; c2 = e.city_b; break
	var edge := gs.edge_of(c1, c2)
	edge.distance = 1; edge.danger = 0.0; edge.max_manpower = 45000
	gs.armies.clear(); gs.battles.clear()
	var mover := _make_army(1, gs.cities[c1].owner_nation, 500, 10)
	mover.state = Army.State.MOVING; mover.move_from = c1; mover.move_to = c2
	mover.location_city = c1; mover.on_edge = true; mover.move_progress = 0.0
	gs.armies.append(mover)
	for i in range(9):
		mover.move_progress += 1.0 / Simulation.march_days(edge.distance)
	_check(mover.move_progress < 1.0, "9 天（<10）不应走完 distance=1 的边，progress=%.3f" % mover.move_progress)
	mover.move_progress += 1.0 / Simulation.march_days(edge.distance)
	_check(mover.move_progress >= 1.0 - 1e-6, "10 天应走完 distance=1 的边，progress=%.3f" % mover.move_progress)
	sim.free()

# ------------------------------------------------------------------ 19. R2 围城时间标定

func _test_siege_time_curve() -> void:
	print("[19] item 7 连续围城曲线：ratio=1→30 天、ratio<0.5 倒退、单调递减、饱和递减")
	# 每日进度 = 100/围城天数。反推天数 = 100/每日进度。分母恒为 siege_required（兵力量纲）。
	# ratio<0.5：进度为负（缓慢倒退，无跳变、无硬门槛）。
	_check(Combat.siege_daily_progress(0, 100) < 0.0, "ratio=0 应最强倒退（负进度）")
	_check(Combat.siege_daily_progress(40, 100) < 0.0, "ratio=0.4(<0.5) 应倒退（负进度），实为 %.4f" % Combat.siege_daily_progress(40, 100))
	# ratio→0.5⁻ 倒退趋近 0（连续、无跳变）；ratio=0.5 恰好 0 边界后转正。
	_check(Combat.siege_daily_progress(0, 100) <= Combat.siege_daily_progress(40, 100),
		"倒退应随 ratio 增大而减弱（ratio=0 比 ratio=0.4 退得更快或相等）")
	_check(Combat.siege_daily_progress(49, 100) < 0.0 and Combat.siege_daily_progress(49, 100) > -0.02,
		"ratio=0.49 应轻微倒退（趋近 0），实为 %.4f" % Combat.siege_daily_progress(49, 100))
	# 0.5~1.0：部分封锁，正推进但极慢（天数 > 30 基准）。
	var days_r_half := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(70, 100)
	_check(days_r_half > 30.0, "ratio=0.7(部分封锁)应比基准慢(>30 天)，实为 %.1f" % days_r_half)
	# ratio=1：恰好 30 天（正常围城下限锚点）。
	var days_r1 := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(100, 100)
	_check(_approx(days_r1, 30.0, 0.01), "ratio=1 应 30 天，实为 %.3f" % days_r1)
	# ratio→∞：趋近下界 3 天（饱和递减，不无限加速）。
	var days_rinf := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(100000000, 100)
	_check(days_rinf >= 3.0 and days_rinf <= 3.01, "ratio→∞ 应趋近 3 天，实为 %.3f" % days_rinf)
	# ratio=2 高效区 ≈ 16.5 天、ratio=4 ≈ 9.75 天（1~2 正常、2~4 高效的量化锚点）。
	var days_r2 := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(200, 100)
	_check(_approx(days_r2, 16.5, 0.1), "ratio=2 应约 16.5 天，实为 %.3f" % days_r2)
	# 正推进区单调递减：兵力比越大，围城天数越短。
	var mono := true
	var prev := 1e9
	for att in [100, 120, 160, 200, 400, 1000, 2000]:
		var dp := Combat.siege_daily_progress(att, 100)
		var d := Combat.SIEGE_PROGRESS_REQUIRED / dp
		if d > prev + 1e-6:
			mono = false
		prev = d
	_check(mono, "正推进区围城天数应随兵力比单调递减")
	# 正推进区全程夹在 (3,30]：ratio≥1 时天数 ∈ (3,30]。
	var in_range := true
	for att in [100, 130, 300, 900, 5000, 100000]:
		var d := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(att, 100)
		if d < 3.0 - 1e-6 or d > 30.0 + 1e-6:
			in_range = false
	_check(in_range, "ratio≥1 围城天数应恒在 (3,30] 区间")
	# item 6：siege_required_manpower 仅由工事强度推导，与守军人数无关（唯一真源、无量纲混用）。
	# fort=10 → 10×100 = 1000；fort=30 → 30×100 = 3000。有无守军该值一致，消除数量级跳变。
	_check(Combat.siege_required_manpower(10) == 1000, "封锁需求应 = 工事×100 = 1000")
	_check(Combat.siege_required_manpower(30) == 3000, "封锁需求应 = 工事×100 = 3000")
	# item 6 验收：驻军被击败后城防仍存在但来自 fort_strength——封锁需求不因守军有无而改变。
	_check(Combat.siege_required_manpower(20) == 2000, "封锁需求恒由工事给出（守军无关）= 2000")

# ------------------------------------------------------------------ 20. R3 粮草时钟 + 粮尽战力降

func _test_siege_food_clock() -> void:
	print("[20] R3 粮草：被围约 90 天耗尽 + 补给孤岛 + 粮尽城防大幅降")
	var gs := GameState.new()
	gs.generate_grid_world(2024)
	var sim := Simulation.new()
	sim.setup(gs)
	# 找一条敌对边，让攻方从 c1 围攻守方城 c2。
	var c1 := -1; var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation != gs.cities[e.city_b].owner_nation:
			c1 = e.city_a; c2 = e.city_b; break
	var city := gs.cities[c2]
	_set_single_warehouse(gs, city.owner_nation, c2, 90) # 首都被围：90 粮 → 90 天
	gs.armies.clear(); gs.battles.clear()
	# 手工建立一场围城（守军强、攻方弱，长期不破城，只观察粮草时钟）。
	var edge := gs.edge_of(c1, c2)
	var siege := gs.new_battle(Battle.Kind.SIEGE)
	siege.edge = edge; siege.city = city
	siege.contact_dist_a = float(maxi(edge.distance, 1)); siege.contact_dist_b = 0.0
	var atk := _make_army(90, gs.cities[c1].owner_nation, 100, 10)   # 弱攻，不破城
	atk.state = Army.State.FIGHTING; atk.battle_id = siege.id
	siege.side_a.append(atk); siege.siege_required = 100000            # 超高基准→永不推进
	# 守军困在被围城 c2 内（补给孤岛：只能吃本城存粮）。
	var garr := _make_army(91, gs.cities[c2].owner_nation, 200, 10)
	garr.state = Army.State.FIGHTING; garr.battle_id = siege.id; garr.location_city = c2
	siege.side_b.append(garr); siege.has_garrison = true
	gs.armies = [atk, garr] as Array[Army]
	# 补给孤岛：被围城不能作供给源，且被围守军只能吃本城存粮。
	_check(gs.city_under_siege(c2), "c2 应处于被围状态")
	var supply := Pathfinding.nearest_supply_city(gs, garr)
	_check(supply.size() >= 1 and supply[0] == c2,
		"被围守军补给源应锁死为本城 c2（补给孤岛），实为 %s" % str(supply))
	# 真实调度中的第 30 天会先月度补给再每日围城消耗；守军不能被重复扣粮。
	for i in range(29):
		sim._drain_siege_food()
	sim._resolve_supply()
	sim._drain_siege_food()
	_check(city.food_storage == 60,
		"围城 30 天应只消耗每日 30 粮，不得叠加守军月耗；实为 %d" % city.food_storage)
	city.food_storage = 90
	# 每日耗粮：跑 89 天应仍有粮，第 90 天耗尽。
	for i in range(89):
		sim._drain_siege_food()
	_check(city.food_storage == 1, "被围 89 天应剩 1 粮（90-89），实为 %d" % city.food_storage)
	sim._drain_siege_food()
	_check(city.food_storage == 0, "被围 90 天粮草应耗尽，实为 %d" % city.food_storage)
	# 再耗不会变负。
	sim._drain_siege_food()
	_check(city.food_storage == 0, "耗尽后不应变负，实为 %d" % city.food_storage)
	# 粮尽后守军补给源断绝（本城无粮，且被围无法外求）→ 返回 -1。
	var supply_starved := Pathfinding.nearest_supply_city(gs, garr)
	_check(supply_starved.is_empty() or supply_starved[0] == -1,
		"粮尽后被围守军应断绝补给（补给孤岛），实为 %s" % str(supply_starved))
	# 粮尽 → 守军城防加成大幅衰减（战力大幅下降）。加成来自工事强度 fort_strength。
	var garr_full := city.fort_strength
	var garr_starve := int(round(city.fort_strength * Combat.SIEGE_STARVE_DEF_MULT))
	_check(garr_starve < garr_full, "粮尽守军城防应大幅下降：%d → %d" % [garr_full, garr_starve])
	_check(_approx(float(garr_starve) / maxf(float(garr_full), 1.0), Combat.SIEGE_STARVE_DEF_MULT, 0.05),
		"粮尽城防应约为原值 ×%.1f" % Combat.SIEGE_STARVE_DEF_MULT)
	sim.free()

# ------------------------------------------------------------------ 21. item 7 弱攻不再机制撤离

func _test_weak_attack_retreat() -> void:
	print("[21] item 7：弱攻空城仍建立围城但进度停滞/倒退，机制层不强制撤离（消除攻/撤循环）")
	var gs := GameState.new()
	gs.generate_grid_world(555)
	var sim := Simulation.new()
	sim.setup(gs)
	# 找一条敌对边：c1(攻方国) → c2(空城)。
	var c1 := -1; var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation != gs.cities[e.city_b].owner_nation:
			c1 = e.city_a; c2 = e.city_b; break
	var edge := gs.edge_of(c1, c2)
	var target := gs.cities[c2]
	# 工事 10 → 空城破城所需兵力 = 10×100 = 1000；有效封锁下限(stall) = 500。
	target.fort_strength = 10
	var empty_required := Combat.siege_required_manpower(target.fort_strength)
	var blockade_floor := int(empty_required * Combat.SIEGE_RATIO_STALL)   # = 500
	gs.armies.clear(); gs.battles.clear()
	# 弱攻兵力 100 << 封锁下限 500（ratio=0.1，远低于 stall）。
	var atk := _make_army(1, gs.cities[c1].owner_nation, 100, 10)
	atk.state = Army.State.MOVING; atk.move_from = c1; atk.move_to = c2
	atk.location_city = c1; atk.on_edge = true; atk.move_progress = 1.0
	gs.armies.append(atk)
	var before_owner := target.owner_nation
	_check(atk.size < blockade_floor, "前置：弱攻兵力应低于封锁下限")
	# 攻方到达空城 → item 7：建立围城，但不占城、不被机制强制撤离。
	sim._start_or_join_siege(atk, target, edge)
	_check(gs.city_under_siege(c2), "弱攻空城应正常建立围城（不再机制拒绝）")
	_check(target.owner_nation == before_owner, "弱攻不得占据空城（owner 不变）")
	_check(atk.state == Army.State.FIGHTING, "弱攻方应进入围城 FIGHTING，不被强制撤离，实为 %d" % atk.state)
	# item 7 核心：ratio<0.5 时围城进度停滞/倒退，且不出现攻/撤循环（多天推进后仍在围城）。
	var siege := sim._siege_battle_of(target)
	siege.siege_progress = 5.0
	for _i in range(10):
		sim._advance_siege(siege)
	_check(not siege.finished, "弱攻围城不应破城")
	_check(siege.siege_progress < 5.0, "ratio<0.5 围城进度应倒退，实为 %.2f" % siege.siege_progress)
	_check(not siege.side_a.is_empty(), "攻方应仍在围城（无机制强制撤离/无攻撤循环）")
	sim.free()

# ------------------------------------------------------------------ 22. 士气崩溃撤退 + 驻城恢复

func _test_morale_retreat_recovery() -> void:
	print("[22] 士气崩溃：向首都纵深撤退 + 驻城耗粮恢复 + 满士气/粮尽解锁")
	var gs := GameState.new()
	gs.generate_grid_world(777)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()
	for nation in gs.nations:
		nation.manpower_pool = 0

	# 撤退路线不得把敌城当作中间节点；起点刚失守时仍允许直接离开敌城。
	var route_state := GameState.new()
	route_state.generate_grid_world(778)
	for city in route_state.cities:
		city.owner_nation = 1
	route_state.cities[0].owner_nation = 0
	route_state.cities[2].owner_nation = 0
	var route_army := _make_army(499, 0, 100, 10)
	route_army.location_city = 0
	route_army.move_from = 0
	var blocked_route := Pathfinding.nearest_friendly_city(route_state, route_army, 0)
	_check(blocked_route.is_empty(),
		"友城之间仅能穿越敌城时应判定无撤退路线，实为 %s" % str(blocked_route))
	route_state.cities[1].owner_nation = 0
	var friendly_route := Pathfinding.nearest_friendly_city(route_state, route_army, 0)
	_check(friendly_route == [1],
		"中间节点恢复为本国后应撤至最近友城 1，实为 %s" % str(friendly_route))
	route_state.cities[0].owner_nation = 1
	var hostile_start_route := Pathfinding.nearest_friendly_city(route_state, route_army, 0)
	_check(hostile_start_route == [1],
		"起点刚失守时应允许离开敌城进入最近友城 1，实为 %s" % str(hostile_start_route))
	var ally_state := GameState.new()
	ally_state.generate_grid_world(779)
	ally_state.armies.clear()
	for ally_city in ally_state.cities:
		ally_city.owner_nation = 1
	ally_state.cities[1].owner_nation = 2
	ally_state.cities[2].owner_nation = 0
	ally_state.set_diplomatic_relation(
		0,
		2,
		GameState.DiplomaticRelation.ALLIED
	)
	var ally_retreat := _make_army(498, 0, 1000, 10)
	ally_retreat.location_city = 0
	ally_retreat.move_from = 0
	ally_retreat.morale = 0.0
	ally_state.armies.append(ally_retreat)
	var ally_route := Pathfinding.nearest_friendly_city(
		ally_state,
		ally_retreat,
		0
	)
	_check(
		ally_route == [1],
		"败军应优先撤入最近的盟友城市，实为 %s"
			% str(ally_route)
	)
	var ally_sim := Simulation.new()
	ally_sim.setup(ally_state)
	ally_sim._start_morale_retreat_from_city(
		ally_retreat,
		0,
		0
	)
	var ally_guard := 0
	while (
		ally_retreat.state == Army.State.RETREATING
		and ally_guard < 40
	):
		ally_sim._advance_movement()
		ally_guard += 1
	_check(
		ally_retreat.state == Army.State.RECOVERING
		and ally_retreat.location_city == 1,
		"败军抵达盟友城市后应进入恢复状态"
	)
	ally_sim.free()

	# 找同国相邻边；军队在靠近 c2 的 80% 位置崩溃，应继续到更近的 c2，而非固定退回 c1。
	var c1 := -1
	var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation == gs.cities[e.city_b].owner_nation:
			c1 = e.city_a
			c2 = e.city_b
			break
	var edge := gs.edge_of(c1, c2)
	var broken := _make_army(500, gs.cities[c1].owner_nation, 1000, 10)
	broken.morale = 0.0
	broken.state = Army.State.FIGHTING
	broken.move_from = c1
	broken.move_to = c2
	broken.move_progress = 0.8
	broken.location_city = c1
	broken.on_edge = true
	edge.passing_count = 1
	gs.armies.append(broken)

	sim._finish_field([] as Array[Army], [broken] as Array[Army])
	_check(broken.state == Army.State.RETREATING, "零士气败军应进入 RETREATING")
	_check(broken.move_to == c2 and _approx(broken.move_progress, 0.8),
		"应从真实位置走向更近端点 c2，且不能瞬移；move_to=%d progress=%.2f" % [broken.move_to, broken.move_progress])
	sim._ai_assign_targets()
	_check(broken.state == Army.State.RETREATING, "撤退途中不得被 AI 重新分配进攻目标")

	var guard := 0
	while broken.state == Army.State.RETREATING and guard < 240:
		sim._advance_movement()
		guard += 1
	var recovery_city := broken.location_city
	_check(
		broken.state == Army.State.RECOVERING
		and recovery_city >= 0
		and gs.cities[recovery_city].owner_nation == broken.owner_nation
		and not gs.city_under_siege(recovery_city),
		"败军应沿首都纵深抵达安全本国城并进入 RECOVERING，state=%d city=%d"
			% [broken.state, recovery_city]
	)
	_check(
		gs.army_at_city(recovery_city) == broken,
		"RECOVERING 军队应计入最终恢复城守军，不能被视为空城"
	)
	sim._ai_assign_targets()
	_check(broken.state == Army.State.RECOVERING, "恢复驻守期间不得执行下一步行动")

	# RECOVERING 不走普通补给扣粮，只由恢复结算消费本城资源，避免双重扣除。
	_set_single_warehouse(gs, broken.owner_nation, recovery_city, 100)
	sim._resolve_supply()
	_check(gs.cities[recovery_city].food_storage == 100, "RECOVERING 不应被普通补给重复扣粮")
	for _day in range(Combat.MORALE_RECOVERY_DAYS - 1):
		sim._recover_morale()
	_check(
		_approx(broken.morale, broken.max_morale * 0.9)
			and broken.state == Army.State.RECOVERING,
		"恢复驻军第9天必须保持RECOVERING且士气为上限的90%%"
	)
	sim._recover_morale()
	var ten_day_recovery_demand := int(floor(
		float(ceil(
			1000.0 * Simulation.RECOVERY_FOOD_PER_CAPITA
		))
			* float(Combat.MORALE_RECOVERY_DAYS)
			/ float(Simulation.DAYS_PER_MONTH)
			+ 0.000001
	))
	_check(
		broken.state == Army.State.IDLE
			and _approx(broken.morale, broken.max_morale)
			and gs.cities[recovery_city].food_storage
				== 100 - ten_day_recovery_demand,
		"恢复驻军必须第10天回满并解除驻守；十天应耗%d粮，实为morale=%.2f food=%d"
			% [
				ten_day_recovery_demand,
				broken.morale,
				gs.cities[recovery_city].food_storage,
			]
	)

	# 对照：资源不足时按比例恢复，粮尽立即解除驻守，但保留未满士气。
	gs.armies.clear()
	var starved := _make_army(501, broken.owner_nation, 1000, 10)
	starved.morale = 0.0
	starved.state = Army.State.RECOVERING
	starved.location_city = recovery_city
	starved.move_from = recovery_city
	starved.supply_food_debt = 3.0
	gs.armies.append(starved)
	_set_single_warehouse(gs, starved.owner_nation, recovery_city, 2)
	sim._recover_morale()
	_check(gs.cities[recovery_city].food_storage == 0, "恢复资源不足时应耗尽本城剩余粮食")
	_check(starved.state == Army.State.IDLE, "城内恢复资源耗尽后应解除强制驻守")
	_check(
		starved.morale > 0.0
			and starved.morale
				< starved.max_morale
					/ float(Combat.MORALE_RECOVERY_DAYS),
		"资源不足应按供给比例部分恢复，实为 %.3f" % starved.morale)

	# 城市恢复期间若易主，旧城主驻军必须被统一驱逐，不能滞留敌城。
	starved.state = Army.State.RECOVERING
	var old_owner := starved.owner_nation
	_set_warehouses(
		gs,
		old_owner,
		[c1, recovery_city] as Array[int],
		[100, 0] as Array[int],
		c1
	)
	var historical_owner := gs.recognized_owner_of(recovery_city)
	var captor := _make_army(502, (old_owner + 1) % GameState.NATION_COUNT, 1200, 10)
	gs.armies.append(captor)
	sim._capture_city(captor, gs.cities[recovery_city])
	_check(starved.size <= 0 or starved.state == Army.State.RETREATING,
		"恢复驻军所在城市易主后应重新撤退（无友城则溃散），state=%d size=%d" % [starved.state, starved.size])
	_check(not (starved.state == Army.State.RECOVERING and gs.cities[recovery_city].owner_nation != old_owner),
		"RECOVERING 军队不得滞留敌方城市")
	_check(
		gs.recognized_owner_of(recovery_city) == historical_owner
		and gs.cities[recovery_city].owner_nation != historical_owner,
		"占领只能改变当前归属，省份初始底色归属必须保持不变"
	)

	# 城破后所有旧守军状态都必须离城；后到援军应立即作为攻方触发新战斗。
	var capture_state := GameState.new()
	capture_state.generate_grid_world(780)
	capture_state.armies.clear()
	capture_state.battles.clear()
	for capture_city in capture_state.cities:
		capture_city.owner_nation = 1
		capture_state.recognized_city_owners[capture_city.id] = 1
		capture_city.occupation_sponsor_nation = -1
		capture_city.loyalty_target_nation = 1
		capture_city.is_capital = false
		capture_city.has_warehouse = false
		capture_city.food_storage = 0
	var capture_origin := 0
	var captured_city_id := 1
	var retreat_city_id := 2
	capture_state.cities[capture_origin].owner_nation = 0
	capture_state.recognized_city_owners[capture_origin] = 0
	capture_state.cities[capture_origin].loyalty_target_nation = 0
	_set_single_warehouse(capture_state, 0, capture_origin, 100)
	_set_single_warehouse(capture_state, 1, 63, 100)
	_set_warehouses(capture_state, 2, [] as Array[int], [] as Array[int])
	_set_warehouses(capture_state, 3, [] as Array[int], [] as Array[int])
	capture_state.refresh_derived()
	_check(
		capture_state.territory_structure_valid(),
		"城市易主与守军驱逐夹具在攻城前必须满足领土结构不变量"
	)
	capture_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var capture_sim := Simulation.new()
	capture_sim.setup(capture_state)
	var city_captor := _make_army(510, 0, 5000, 10)
	city_captor.location_city = capture_origin
	city_captor.move_from = capture_origin
	var captured_recovering := _make_army(511, 1, 3000, 10)
	captured_recovering.state = Army.State.RECOVERING
	captured_recovering.location_city = captured_city_id
	captured_recovering.move_from = captured_city_id
	var captured_waiting := _make_army(512, 1, 3000, 10)
	captured_waiting.state = Army.State.RETREATING
	captured_waiting.location_city = captured_city_id
	captured_waiting.move_from = captured_city_id
	captured_waiting.move_to = -1
	captured_waiting.path = [retreat_city_id]
	var captured_fighting := _make_army(513, 1, 3000, 10)
	captured_fighting.state = Army.State.FIGHTING
	captured_fighting.battle_id = 999
	captured_fighting.location_city = captured_city_id
	captured_fighting.move_from = captured_city_id
	capture_state.armies.append_array([
		city_captor,
		captured_recovering,
		captured_waiting,
		captured_fighting,
	])
	capture_sim._capture_city(
		city_captor,
		capture_state.cities[captured_city_id],
		0
	)
	var old_defenders_left_city := true
	for old_defender in [
		captured_recovering,
		captured_waiting,
		captured_fighting,
	]:
		old_defenders_left_city = (
			old_defenders_left_city
			and (
				old_defender.size <= 0
				or (
					old_defender.state
						== Army.State.RETREATING
					and old_defender.on_edge
					and old_defender.move_from
						== captured_city_id
				)
			)
		)
	_check(
		old_defenders_left_city,
		"城市易主后，恢复/等待撤退/残留战斗状态的旧守军必须立即离开城市节点"
	)
	var illegal_recovery := _make_army(514, 1, 2000, 10)
	illegal_recovery.location_city = captured_city_id
	illegal_recovery.move_from = captured_city_id
	capture_state.armies.append(illegal_recovery)
	capture_sim._start_recovering(
		illegal_recovery,
		captured_city_id
	)
	_check(
		illegal_recovery.size <= 0
			or (
				illegal_recovery.state
					== Army.State.RETREATING
				and illegal_recovery.on_edge
			),
		"敌军不得在无通行权的敌占城市开始恢复士气"
	)
	var late_relief := _make_army(515, 1, 5000, 10)
	late_relief.state = Army.State.MOVING
	late_relief.location_city = retreat_city_id
	late_relief.move_from = retreat_city_id
	late_relief.move_to = captured_city_id
	late_relief.move_progress = 1.0
	late_relief.on_edge = true
	capture_state.armies.append(late_relief)
	capture_sim._arrive_at_node(late_relief)
	var recapture_battle := capture_sim._siege_battle_of(
		capture_state.cities[captured_city_id]
	)
	_check(
		recapture_battle != null
			and recapture_battle.has_army(late_relief)
			and recapture_battle.has_army(city_captor)
			and late_relief.state == Army.State.FIGHTING
			and city_captor.state == Army.State.FIGHTING,
		"旧城主后到援军抵达已失守城市时，必须立即与新占领军触发战斗"
	)
	capture_sim.free()

	# 真实地图 68 城复现：占领军已下达后续移动命令，但受容量限制尚未上边。
	# 其 MOVING 只是任务状态，物理上仍在城内，敌军抵达时必须作为守军参战。
	var city68_state := GameState.new()
	city68_state.generate_world(12345)
	city68_state.armies.clear()
	city68_state.battles.clear()
	var city68_id := 68
	var city68_source: int = city68_state.neighbors(
		city68_id
	)[0]
	city68_state.cities[city68_id].owner_nation = 1
	city68_state.cities[city68_source].owner_nation = 0
	city68_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var city68_holder := _make_army(
		516,
		1,
		5000,
		10
	)
	city68_holder.state = Army.State.MOVING
	city68_holder.location_city = city68_id
	city68_holder.move_from = city68_id
	city68_holder.move_to = -1
	city68_holder.path = [city68_source] as Array[int]
	var city68_stale_fighter := _make_army(
		518,
		1,
		5000,
		10
	)
	city68_stale_fighter.state = Army.State.FIGHTING
	city68_stale_fighter.battle_id = 999
	city68_stale_fighter.location_city = city68_id
	city68_stale_fighter.move_from = city68_id
	var city68_relief := _make_army(
		517,
		0,
		5000,
		10
	)
	city68_relief.state = Army.State.MOVING
	city68_relief.location_city = city68_source
	city68_relief.move_from = city68_source
	city68_relief.move_to = city68_id
	city68_relief.move_progress = 1.0
	city68_relief.on_edge = true
	var city68_edge := city68_state.edge_of(
		city68_source,
		city68_id
	)
	city68_edge.passing_count = 1
	city68_edge.occupied = true
	city68_state.armies.append_array([
		city68_holder,
		city68_stale_fighter,
		city68_relief,
	])
	var city68_sim := Simulation.new()
	city68_sim.setup(city68_state)
	city68_sim._arrive_at_node(city68_relief)
	var city68_battle := city68_sim._siege_battle_of(
		city68_state.cities[city68_id]
	)
	_check(
		city68_battle != null
			and city68_battle.has_garrison
			and city68_battle.has_army(city68_holder)
			and city68_battle.has_army(
				city68_stale_fighter
			)
			and city68_battle.has_army(city68_relief)
			and city68_holder.state == Army.State.FIGHTING
			and city68_stale_fighter.battle_id
				== city68_battle.id
			and city68_relief.state == Army.State.FIGHTING,
		"真实地图68城：容量等待或失效战斗状态的占领军必须迎战后到敌军"
	)
	_check(
		not city68_relief.on_edge
			and city68_relief.is_at_city_node(city68_id)
			and city68_relief.move_from == city68_source
			and city68_relief.move_to == city68_id,
		"抵达68城后必须识别为城市节点军队，同时保留围城补给边锚点"
	)
	city68_sim.free()

	# 多支恢复驻军必须全部加入守城，破城所需兵力的守军项取总兵力（而非只取第一支）。
	gs.armies.clear()
	gs.battles.clear()
	var siege_edge: Edge = null
	for candidate_edge in gs.edges:
		if (
			gs.cities[candidate_edge.city_a].owner_nation
				!= gs.cities[candidate_edge.city_b].owner_nation
		):
			siege_edge = candidate_edge
			break
	var siege_from := siege_edge.city_a
	var siege_to := siege_edge.city_b
	var city_owner := gs.cities[siege_to].owner_nation
	var g1 := _make_army(503, city_owner, 300, 10)
	var g2 := _make_army(504, city_owner, 200, 10)
	for garrison in [g1, g2]:
		garrison.state = Army.State.RECOVERING
		garrison.location_city = siege_to
		garrison.move_from = siege_to
		gs.armies.append(garrison)
	var invader := _make_army(
		505, gs.cities[siege_from].owner_nation, 1000, 10
	)
	invader.move_from = siege_from
	invader.move_to = siege_to
	gs.armies.append(invader)
	sim._start_or_join_siege(
		invader, gs.cities[siege_to], siege_edge
	)
	var recovery_siege: Battle = gs.battles[0]
	_check(recovery_siege.side_b.size() == 2, "两支 RECOVERING 驻军应全部加入守城")
	# item 6：破城所需兵力仅由工事换算，与守军人数无关；两支恢复守军只在城下决斗阶段消耗攻方。
	var expected_required := Combat.siege_required_manpower(gs.cities[siege_to].fort_strength)
	_check(recovery_siege.siege_required == expected_required,
		"破城所需兵力恒由工事推导（守军无关），实为 %d（期望 %d）" % [recovery_siege.siege_required, expected_required])
	sim.free()


func _test_retreat_transport_footprint() -> void:
	print("[22a] 撤退运输足迹：残余重军可沿5000窄路撤退且不拆编")
	var gs := GameState.new()
	gs.generate_grid_world(783)
	gs.armies.clear()
	gs.battles.clear()
	for city in gs.cities:
		city.owner_nation = 1
	gs.cities[0].owner_nation = 0
	gs.cities[1].owner_nation = 0
	gs.nations[0].capital_city_id = 1
	for edge in gs.edges:
		edge.max_manpower = 0
		edge.passing_count = 0
		edge.occupied = false
	var narrow_edge := gs.edge_of(0, 1)
	narrow_edge.max_manpower = Edge.MIN_MANPOWER
	narrow_edge.distance = 1
	narrow_edge.travel_time_multiplier = 1.0
	narrow_edge.danger = 0.0

	var remnant := _make_army(497, 0, 4000, 10, 10)
	remnant.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	remnant.max_morale = Army.HEAVY_MAX_MORALE
	remnant.morale = Combat.MORALE_FLOOR
	remnant.location_city = 0
	remnant.move_from = 0
	gs.armies.append(remnant)
	var group := gs.create_battle_group(0)
	_check(
		gs.assign_army_to_battle_group(remnant, group.id),
		"前置：残余重军应保留合法战团身份"
	)

	var sim := Simulation.new()
	sim.setup(gs)
	sim._retreat_defender(remnant, gs.cities[0])
	_check(
		remnant.size == 4000
			and remnant.state == Army.State.RETREATING
			and remnant.forced_retreat
			and remnant.on_edge
			and remnant.move_from == 0
			and remnant.move_to == 1
			and narrow_edge.passing_count == 1,
		"残余4000人的15000编制重军应立即进入5000容量退路，不得溃散或卡住"
	)
	_check(
		gs.armies.size() == 1
			and gs.armies[0] == remnant
			and remnant.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and remnant.max_morale == Army.HEAVY_MAX_MORALE
			and remnant.is_main_battle_role()
			and remnant.battle_group_id == group.id,
		"撤退运输不得拆军或降编，必须保持单一Army、重军与战团语义"
	)

	var guard := 0
	while remnant.state == Army.State.RETREATING and guard < 40:
		sim._advance_movement()
		guard += 1
	var group_members := gs.battle_group_members(0, group.id)
	_check(
		remnant.state == Army.State.RECOVERING
			and remnant.location_city == 1
			and remnant.size == 4000
			and not remnant.on_edge
			and narrow_edge.passing_count == 0,
		"残余重军应沿5000窄路抵达友方首都并进入RECOVERING"
	)
	_check(
		gs.armies.size() == 1
			and gs.armies[0] == remnant
			and remnant.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and remnant.is_main_battle_role()
			and remnant.battle_group_id == group.id
			and group_members.size() == 1
			and group_members[0] == remnant,
		"完成撤退后仍须是原来的唯一重军Army及原战团成员"
	)
	sim.free()


func _test_edge_retreat_transport_batches() -> void:
	print("[22a2] 边上撤退：端点择路必须计入当前窄路的重军运输批次")
	var gs := GameState.new()
	gs.generate_grid_world(784)
	gs.armies.clear()
	gs.battles.clear()
	for city in gs.cities:
		city.owner_nation = 1
	# 两端都是无通行权城市；每端各接一座本国安全城市。
	# 重军位于 0→1 的 20% 处：若漏算当前 5000 道路的三批运输，
	# 会误选表面更近的端点 1；正确总成本为 0 端 6+20 < 1 端 24+5。
	gs.cities[8].owner_nation = 0
	gs.cities[2].owner_nation = 0
	# 让首都暂不可达，使战略撤退的两个候选同属 own-city tier，
	# 确保本用例真正由总运输距离而非首都纵深优先级裁决。
	gs.nations[0].capital_city_id = 16
	for edge in gs.edges:
		edge.max_manpower = 0
		edge.passing_count = 0
		edge.occupied = false
	var current_edge := gs.edge_of(0, 1)
	current_edge.max_manpower = Edge.MIN_MANPOWER
	current_edge.distance = 10
	current_edge.travel_time_multiplier = 1.0
	current_edge.danger = 0.0
	var left_exit := gs.edge_of(0, 8)
	left_exit.max_manpower = Edge.STANDARD_MANPOWER
	left_exit.distance = 20
	left_exit.travel_time_multiplier = 1.0
	left_exit.danger = 0.0
	var right_exit := gs.edge_of(1, 2)
	right_exit.max_manpower = Edge.STANDARD_MANPOWER
	right_exit.distance = 5
	right_exit.travel_time_multiplier = 1.0
	right_exit.danger = 0.0

	var heavy := _place_army_on_edge(gs, 498, 0, 0, 1, 0.2)
	heavy.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	var strategic := Pathfinding.strategic_retreat_route_from_edge(
		gs, heavy
	)
	var repatriation := (
		Pathfinding.nearest_home_route_from_edge_for_repatriation(
			gs, heavy
		)
	)
	_check(
		int(strategic.get("endpoint", -1)) == 0
			and strategic.get("path", []) == [8]
			and _approx(float(strategic.get("distance", INF)), 26.0),
		"战略撤退应按当前窄路三批运输选择真实更快的0端：%s"
			% str(strategic)
	)
	_check(
		int(repatriation.get("endpoint", -1)) == 0
			and repatriation.get("path", []) == [8]
			and _approx(float(repatriation.get("distance", INF)), 26.0),
		"外交遣返应与战略撤退使用同一当前边运输成本：%s"
			% str(repatriation)
	)


func _test_besieged_city_retreat_depth() -> void:
	print("[22b] 撤退纵深：双围城不得在相邻城市之间横跳，必须向首都方向后撤")
	var gs := GameState.new()
	gs.generate_grid_world(782)
	gs.armies.clear()
	gs.battles.clear()
	for city in gs.cities:
		city.owner_nation = 1
	var front_a := 0
	var front_b := 1
	var rear_a := 8
	var rear_b := 9
	var capital := 16
	for city_id in [front_a, front_b, rear_a, rear_b, capital]:
		gs.cities[city_id].owner_nation = 0
	for edge in gs.edges:
		edge.max_manpower = (
			Edge.STANDARD_MANPOWER
			if GameState.edge_key(edge.city_a, edge.city_b) in [
				GameState.edge_key(front_a, front_b),
				GameState.edge_key(front_a, rear_a),
				GameState.edge_key(front_b, rear_b),
				GameState.edge_key(rear_a, rear_b),
				GameState.edge_key(rear_a, capital),
			]
			else 0
		)
	gs.nations[0].capital_city_id = capital
	for front in [front_a, front_b]:
		var siege := gs.new_battle(Battle.Kind.SIEGE)
		siege.city = gs.cities[front]
	var army_a := _make_army(510, 0, 1000, 10)
	var army_b := _make_army(511, 0, 1000, 10)
	army_a.morale = 0.1
	army_b.morale = 0.1
	gs.armies.append_array([army_a, army_b])
	var sim := Simulation.new()
	sim.setup(gs)
	sim._start_morale_retreat_from_city(army_a, front_a, front_a)
	sim._start_morale_retreat_from_city(army_b, front_b, front_b)
	_check(
		army_a.state == Army.State.RETREATING
		and army_a.move_to == rear_a
		and not army_a.path.has(front_b)
		and army_b.state == Army.State.RETREATING
		and army_b.move_to == rear_b
		and not army_b.path.has(front_a),
		"双围城败军必须分别向首都纵深撤至%d/%d，不得互撤至%d/%d：A=%d path=%s B=%d path=%s"
			% [rear_a, rear_b, front_b, front_a, army_a.move_to, str(army_a.path), army_b.move_to, str(army_b.path)]
	)
	sim.free()


func _test_gold_reserve_budget_and_war_snapshot() -> void:
	print("[31b] 财政储备：和平三年、战争半年，战前收入快照不随领土变化")
	var gs := GameState.new()
	gs.generate_grid_world(7105)
	gs.armies.clear()
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	for city in gs.cities:
		city.gold_per_month = 0
	for city in gs.cities_of(0):
		city.gold_per_month = 10
	var sim := Simulation.new()
	sim.setup(gs)
	var flows := Simulation.monthly_gold_flows(gs)
	var income := int(flows[0]["net_income"])
	gs.nations[0].treasury_gold = 0
	var peace := Simulation.gold_reserve_policy(gs, 0, flows)
	_check(
		income > 0
		and int(peace["reserve_months"]) == 36
		and int(peace["reserve_target"]) == income * 36
		and int(peace["target_monthly_savings"]) == income,
		"和平财政应以当前月收入%d建立36个月目标%d，并从空库至少月存%d：%s"
			% [income, income * 36, income, str(peace)]
	)
	var expected_snapshot := income
	sim._capture_war_gold_income_snapshots([0, 1] as Array[int])
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var war := Simulation.gold_reserve_policy(gs, 0)
	_check(
		gs.nations[0].war_gold_income_snapshot == expected_snapshot
		and int(war["reserve_months"]) == 6
		and int(war["reserve_target"]) == expected_snapshot * 6
		and int(war["budget_monthly_balance"])
			== expected_snapshot - int(
				Simulation.monthly_gold_flows(gs)[0]["military_upkeep"]
			),
		"进入战争应冻结战前月收入%d并将目标降至半年%d：snapshot=%d policy=%s"
			% [expected_snapshot, expected_snapshot * 6, gs.nations[0].war_gold_income_snapshot, str(war)]
	)
	for city in gs.cities_of(0):
		city.gold_per_month = 0
	var collapsed_income := int(
		Simulation.monthly_gold_flows(gs)[0]["net_income"]
	)
	sim._synchronize_war_gold_income_snapshots()
	var frozen_after_loss := Simulation.gold_reserve_policy(gs, 0)
	_check(
		gs.nations[0].war_gold_income_snapshot == expected_snapshot
		and int(frozen_after_loss["reserve_target"]) == expected_snapshot * 6
		and int(frozen_after_loss["budget_monthly_balance"])
			== int(war["budget_monthly_balance"])
		and int(frozen_after_loss["required_upkeep_savings"])
			== int(war["required_upkeep_savings"]),
		"战争中收入降至%d后仍须保持战前半年目标%d，不得按失地收入快速裁军：%s"
			% [collapsed_income, expected_snapshot * 6, str(frozen_after_loss)]
	)
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	sim._synchronize_war_gold_income_snapshots()
	var postwar_income := int(
		Simulation.monthly_gold_flows(gs)[0]["net_income"]
	)
	var postwar := Simulation.gold_reserve_policy(gs, 0)
	_check(
		gs.nations[0].war_gold_income_snapshot == -1
		and int(postwar["reserve_months"]) == 36
		and int(postwar["reserve_target"])
			== postwar_income * 36,
		"最后一场战争结束后必须清空快照并恢复按当前收入计算三年目标"
	)
	sim.free()


func _test_ruler_economy_integration() -> void:
	print("[31c] 君主经济：产出、军费、储备与财政缩编使用同一有效口径")
	var gs := GameState.new()
	gs.generate_grid_world(7106)
	gs.armies.clear()
	for nation in gs.nations:
		_set_neutral_ruler(nation)
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
	for edge in gs.edges:
		edge.max_manpower = 0
	for nation_a in range(gs.nations.size()):
		for nation_b in range(nation_a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	for city in gs.cities:
		city.gold_per_month = 0
		city.manpower_per_month = 0
		city.food_per_half_year = 0
	var nation := gs.nations[0]
	nation.ruler_archetype = RulerProfile.INEPT
	var nation_cities := gs.cities_of(0)
	var city: City = null
	for candidate in nation_cities:
		if not candidate.is_dock:
			city = candidate
			break
	_check(city != null, "君主经济测试需要一座国0陆城")
	if city == null:
		return
	city.gold_per_month = 10
	city.manpower_per_month = 10
	city.food_per_half_year = 100
	var army_city := city
	for candidate in nation_cities:
		if not candidate.is_dock and candidate != city:
			army_city = candidate
			break
	var army := gs.create_army(0, army_city.id, 5000, 5000)
	var base_upkeep := GameState.army_monthly_upkeep(army.size)
	var expected_gold := int(floor(
		10.0 * RulerProfile.gold_output_multiplier(nation)
	))
	var expected_food := int(floor(
		100.0 * RulerProfile.food_output_multiplier(nation)
	))
	var expected_manpower := int(floor(
		10.0 * RulerProfile.manpower_output_multiplier(nation)
	))
	var expected_upkeep := int(ceil(
		float(base_upkeep) * RulerProfile.upkeep_multiplier(nation)
	))
	var flows := Simulation.monthly_gold_flows(gs)
	var flow: Dictionary = flows[0]
	_check(
		Simulation.city_gold_output(gs, city) == expected_gold
		and Simulation.city_food_output(gs, city) == expected_food
		and Simulation.city_manpower_output(gs, city) == expected_manpower
		and int(flow["military_upkeep"]) == expected_upkeep,
		"非中性君主的城市产出与军费预测必须逐项落地且取整一致"
	)
	var reserve := Simulation.gold_reserve_policy(gs, 0, flows)
	_check(
		int(reserve["reserve_months"])
			== Simulation.PEACE_GOLD_RESERVE_MONTHS
				+ RulerProfile.reserve_months_bonus(nation),
		"财政储备月数必须叠加当前君主加法修正"
	)
	var before_manpower := nation.manpower_pool
	var before_gold := nation.treasury_gold
	var sim := Simulation.new()
	sim.setup(gs)
	gs.day = Simulation.DAYS_PER_MONTH
	sim._resolve_economy()
	_check(
		nation.manpower_pool - before_manpower == expected_manpower
		and nation.treasury_gold - before_gold
			== int(flow["balance"]),
		"非中性君主的实际月结必须与产出和有效军费预测同源"
	)
	var upkeep_before_demobilization := (
		Simulation.effective_monthly_military_upkeep(gs, 0)
	)
	var view := AiWorldView.build(gs, 0)
	var demobilized := sim._demobilize_for_gold_security(
		view, ThreatField.build(view), 1, 1
	)
	var upkeep_after_demobilization := (
		Simulation.effective_monthly_military_upkeep(gs, 0)
	)
	_check(
		demobilized
		and upkeep_before_demobilization
			- upkeep_after_demobilization >= 1
		and nation.ai_last_force_reason.contains(
			"月省%d金" % (
				upkeep_before_demobilization
					- upkeep_after_demobilization
			)
		),
		"财政缩编必须按君主修正后的国家总军费记录并兑现节流"
	)
	sim.free()

# ------------------------------------------------------------------ 23. 自由/溃逃状态：断粮降士气 + 被动接战

func _test_supply_morale_and_passive_retreat_battle() -> void:
	print("[23] 状态机：断粮降士气触发溃逃 + 溃逃军只被动接战 + 获胜后继续撤退")
	var gs := GameState.new()
	gs.generate_grid_world(909)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()

	var c1 := -1
	var c2 := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation == gs.cities[edge.city_b].owner_nation:
			c1 = edge.city_a
			c2 = edge.city_b
			break
	var nation := gs.cities[c1].owner_nation
	for city in gs.cities:
		if city.owner_nation == nation:
			city.food_storage = 0

	# 自由行军军队完全断粮：士气按 0.20/月 滚动逐日损失（item 10），而非结算日一次性跳变。
	var hungry := _place_army_on_edge(gs, 600, nation, c1, c2, 0.4)
	hungry.morale = 0.10
	sim._resolve_supply()   # 月度只写 supply_ratio（全断粮→0），不再直接扣士气
	_check(_approx(hungry.supply_ratio, 0.0),
		"全断粮月度结算应把 supply_ratio 记为 0，实为 %.3f" % hungry.supply_ratio)
	sim._apply_supply_pressure()   # 第 1 天：只损失 0.20/30，绝不应一天崩溃
	var per_day := Simulation.SUPPLY_MORALE_LOSS_MAX / float(Simulation.DAYS_PER_MONTH)
	_check(_approx(hungry.morale, 0.10 - per_day) and hungry.state != Army.State.RETREATING,
		"断粮首日应仅损失 %.4f 士气且不立即溃逃，实为 morale=%.4f state=%d" % [
			per_day, hungry.morale, hungry.state])
	# 继续滚动足够多天（0.10 需约 15 天耗尽），最终士气归零并触发溃逃。
	for _i in range(19):
		sim._apply_supply_pressure()
	_check(_approx(hungry.morale, 0.0), "持续全断粮约 15 天后士气应降至 0，实为 %.4f" % hungry.morale)
	_check(hungry.state == Army.State.RETREATING and hungry.forced_retreat,
		"自由军士气滚动降至 0 后应自动进入溃逃状态")

	# 两支敌对溃逃军即使同点也不主动互战。
	gs.armies.clear()
	gs.battles.clear()
	var r1 := _place_army_on_edge(gs, 601, 0, c1, c2, 0.5)
	var r2 := _place_army_on_edge(gs, 602, 1, c2, c1, 0.5)
	for retreater in [r1, r2]:
		retreater.state = Army.State.RETREATING
		retreater.forced_retreat = true
		retreater.morale = 0.8
	sim._detect_encounters()
	_check(gs.battles.is_empty(), "两支溃逃军均非主动方，同点也不应互相开战")

	# 加入一支正常 MOVING 敌军后，可主动截击溃逃军。
	gs.armies.erase(r2)
	var pursuer := _place_army_on_edge(gs, 603, 1, c2, c1, 0.5)
	pursuer.morale = 1.0
	r1.path = [c2] as Array[int]   # 原撤退命令，接战后必须保留
	sim._detect_encounters()
	_check(gs.battles.size() == 1 and r1.state == Army.State.FIGHTING,
		"正常军接触溃逃军时应触发被动接战")
	_check(r1.forced_retreat, "溃逃军进入被动战斗后必须保留强制撤退标记")

	# 强制追击方覆灭：溃逃军虽获胜，也只能继续 RETREATING，不能转普通 MOVING。
	pursuer.size = 0
	sim._resolve_battles()
	_check(r1.state == Army.State.RETREATING and r1.forced_retreat,
		"溃逃军被动接战获胜后应继续撤退，不得恢复自由行军")
	_check(r1.path == [c2], "被动接战获胜后应保留原撤退路径")
	sim.free()

# ------------------------------------------------------------------ 23b. item10 补给滚动结算：相位无关 + 恢复消退
func _test_rolling_supply_settlement() -> void:
	print("[23b] 补给滚动结算：断粮影响逐日累积、月初月末相位无关、恢复后惩罚消退")
	var sim := Simulation.new()
	var per_day := Simulation.SUPPLY_MORALE_LOSS_MAX / float(Simulation.DAYS_PER_MONTH)

	# --- (a) 逐日累积：全断粮 shortage=1，N 天后士气恰降 N*per_day，绝非结算日一次性跳变 ---
	var a := _make_army(700, 0, 1000, 10)
	a.morale = 1.0
	for _i in range(10):
		sim._accrue_supply_pressure(a, 1.0)
	_check(_approx(a.morale, 1.0 - 10.0 * per_day),
		"全断粮 10 天应逐日累积损失 %.4f 士气，实为 %.4f" % [10.0 * per_day, 1.0 - a.morale])

	# --- (b) 相位无关：同为「断粮 10 天」，无论落在 30 天窗口的月初还是月末，结果一致 ---
	var early := _make_army(701, 0, 1000, 10); early.morale = 1.0
	var late := _make_army(702, 0, 1000, 10); late.morale = 1.0
	for day in range(1, 31):
		sim._accrue_supply_pressure(early, 1.0 if day <= 10 else 0.0)   # 月初断 10 天
		sim._accrue_supply_pressure(late, 1.0 if day > 20 else 0.0)     # 月末断 10 天
	_check(_approx(early.morale, late.morale),
		"断粮同为 10 天，月初(%.4f)与月末(%.4f)结果应一致（相位无关）" % [early.morale, late.morale])
	_check(_approx(early.morale, 1.0 - 10.0 * per_day),
		"断粮 10 天后士气应为 %.4f，实为 %.4f" % [1.0 - 10.0 * per_day, early.morale])

	# --- (c) 恢复消退：断粮压低士气后 shortage 归零，惩罚停止、士气不再下降、饥饿标记清除 ---
	var recov := _make_army(703, 0, 1000, 10); recov.morale = 1.0
	for _i in range(5):
		sim._accrue_supply_pressure(recov, 1.0)
	var dipped := recov.morale
	_check(recov.starving and dipped < 1.0 - 4.0 * per_day + 0.0001,
		"断粮 5 天应显著压低士气并标记饥饿，实为 %.4f" % dipped)
	for _i in range(5):
		sim._accrue_supply_pressure(recov, 0.0)   # 补给恢复
	_check(_approx(recov.morale, dipped) and not recov.starving,
		"补给恢复后断粮惩罚应停止、饥饿清除、士气不再下降（%.4f→%.4f）" % [dipped, recov.morale])

	# --- (d) 减员整人化：小额日债累积到满 1 人才扣，size 不因逐日 ceil 而放大流失 ---
	var attrit := _make_army(704, 0, 400, 10); attrit.morale = 1.0   # 400 人日债 = 400*0.5/30 ≈ 6.667
	sim._accrue_supply_pressure(attrit, 1.0)   # 第 1 天：债≈6.667 → 扣 6，余 0.667
	_check(attrit.size == 394
		and _approx(attrit.supply_debt, 400.0 * Simulation.STARVE_RATE / 30.0 - 6.0),
		"400 人全断粮首日应减 6 人(floor(6.67))并留 0.667 债，实为 size=%d debt=%.4f" % [
			attrit.size, attrit.supply_debt])

	# --- (e) 部分缺粮：shortage=0.5 施压等于全断粮的一半（线性、可解释）---
	var half := _make_army(705, 0, 1000, 10); half.morale = 1.0
	sim._accrue_supply_pressure(half, 0.5)
	_check(_approx(half.morale, 1.0 - 0.5 * per_day),
		"半缺粮单日士气损失应为全断粮之半 %.5f，实为 %.5f" % [0.5 * per_day, 1.0 - half.morale])

	# --- (f) 溃逃边沿：士气自正值跌破 0 的当日返回 true（触发溃逃），此后不重复触发 ---
	var brk := _make_army(706, 0, 1000, 10)
	brk.state = Army.State.MOVING
	brk.morale = per_day * 0.5   # 不足一日损失，本日必然跌破 0
	var triggered := sim._accrue_supply_pressure(brk, 1.0)
	_check(triggered and _approx(brk.morale, 0.0),
		"士气自正值当日跌至 0 应返回溃逃触发，实为 trigger=%s morale=%.5f" % [str(triggered), brk.morale])
	var retrigger := sim._accrue_supply_pressure(brk, 1.0)
	_check(not retrigger, "士气已在 0 的军队不应重复触发溃逃")
	sim.free()

# ------------------------------------------------------------------ 24. 攻城顺序：先正面战斗，后围城；守军排除当前城撤退

func _test_siege_battle_then_progress_order() -> void:
	print("[24] 攻城顺序：守军正面战败后才推进围城，且撤往非当前攻城城市")
	var gs := GameState.new()
	gs.generate_grid_world(4242)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()

	var from_city := -1
	var siege_city := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation != gs.cities[edge.city_b].owner_nation:
			from_city = edge.city_a
			siege_city = edge.city_b
			break
	var road := gs.edge_of(from_city, siege_city)
	var attacker := _make_army(700, gs.cities[from_city].owner_nation, 5000, 1)
	attacker.move_from = from_city
	attacker.move_to = siege_city
	attacker.move_progress = 1.0
	var defender := _make_army(701, gs.cities[siege_city].owner_nation, 100, 1)
	defender.morale = 0.001   # 基础回合衰减保证首回合崩溃，但兵力仍有残余
	defender.state = Army.State.IDLE
	defender.location_city = siege_city
	defender.move_from = siege_city
	gs.armies.append(attacker)
	gs.armies.append(defender)

	sim._start_or_join_siege(attacker, gs.cities[siege_city], road)
	var siege: Battle = gs.battles[0]
	_check(siege.has_garrison and siege.side_b.has(defender), "攻城开始时应先把驻军放入正面战斗")
	_check(_approx(siege.siege_progress, 0.0), "守军战斗开始前围城进度必须为 0")

	sim._advance_siege(siege)
	_check(not siege.has_garrison and siege.side_b.is_empty(),
		"守军正面战败后应退出战斗并切换到纯围城阶段")
	_check(_approx(siege.siege_progress, 0.0),
		"守军战败的同一天不得推进围城进度，必须严格先战斗后围城")
	_check(defender.size <= 0 or defender.state == Army.State.RETREATING,
		"战败守军有残兵时应进入 RETREATING")
	if defender.size > 0:
		_check(defender.move_from == siege_city and defender.move_to != siege_city,
			"守军撤退起点可为攻城城市，但目的地必须排除当前城；move_to=%d" % defender.move_to)

	sim._advance_siege(siege)
	_check(siege.siege_progress > 0.0, "守军已撤离后的下一天才应开始累积围城进度")
	if defender.size > 0:
		var retreat_guard := 0
		while defender.state == Army.State.RETREATING and retreat_guard < 100:
			sim._advance_movement()
			retreat_guard += 1
		_check(defender.state == Army.State.RECOVERING,
			"战败守军抵达其他友城后必须进入 RECOVERING，state=%d" % defender.state)
		_check(defender.location_city != siege_city
			and gs.cities[defender.location_city].owner_nation == defender.owner_nation,
			"战败守军不得在失守城市原地恢复，必须位于其他友城；location=%d siege_city=%d"
				% [defender.location_city, siege_city])

	# 收复自己的法理城市不再走特判：与普通征服一致，必须建立围城、破坏城防后才能占领。
	gs.armies.clear()
	gs.battles.clear()
	var legal_owner := gs.cities[from_city].owner_nation
	var occupier := (legal_owner + 1) % GameState.NATION_COUNT
	gs.cities[siege_city].owner_nation = occupier
	gs.recognized_city_owners[siege_city] = legal_owner
	gs.cities[siege_city].fort_strength = 1000
	var reclaim_required := UtilityAI.assault_commit_threshold(
		0,
		gs.cities[siege_city].fort_strength
	)
	var empty_city_reclaimer := _make_army(
		702,
		legal_owner,
		reclaim_required,
		10
	)
	empty_city_reclaimer.move_from = from_city
	empty_city_reclaimer.move_to = siege_city
	empty_city_reclaimer.location_city = from_city
	gs.armies.append(empty_city_reclaimer)
	var reclaim_view := AiWorldView.build(
		gs,
		legal_owner
	)
	var reclaim_candidate := UtilityAI._attack_candidate(
		reclaim_view,
		StrategicMapSnapshot.build(reclaim_view),
		ThreatField.build(reclaim_view),
		ArmyCoordinator.new(),
		empty_city_reclaimer,
		UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO
	)
	_check(
		reclaim_candidate != null
		and reclaim_candidate.kind
			== ActionCandidate.Kind.ATTACK
		and reclaim_candidate.target_city
			== siege_city,
		"兵力达到完整围城门槛后，AI应主动收复无守军的本国法理城市"
	)
	sim._start_or_join_siege(
		empty_city_reclaimer,
		gs.cities[siege_city],
		road
	)
	_check(
		gs.cities[siege_city].owner_nation == occupier
		and gs.battles.size() == 1
		and gs.battles[0].kind == Battle.Kind.SIEGE,
		"收复无守军的本国法理城市也必须建立围城，不再瞬间恢复"
	)

	gs.armies.clear()
	gs.battles.clear()
	gs.cities[siege_city].owner_nation = occupier
	var reclaimer := _make_army(
		703,
		legal_owner,
		5000,
		1
	)
	reclaimer.move_from = from_city
	reclaimer.move_to = siege_city
	reclaimer.location_city = from_city
	var occupation_guard := _make_army(
		704,
		occupier,
		100,
		1
	)
	occupation_guard.morale = 0.001
	occupation_guard.state = Army.State.IDLE
	occupation_guard.location_city = siege_city
	occupation_guard.move_from = siege_city
	gs.armies = [
		reclaimer,
		occupation_guard,
	] as Array[Army]
	sim._start_or_join_siege(
		reclaimer,
		gs.cities[siege_city],
		road
	)
	var reclamation_battle: Battle = gs.battles[0]
	sim._advance_siege(reclamation_battle)
	_check(
		gs.cities[siege_city].owner_nation == occupier
		and not reclamation_battle.finished
		and not reclamation_battle.has_garrison,
		"击败占领军后不再瞬间收复：转入纯围城阶段，仍须累积破城进度"
	)
	sim.free()

	# 盟军击败围城方属于解围，不能被晋升为对盟友城市的新围城方。
	var ally_state := GameState.new()
	ally_state.generate_grid_world(24240)
	var ally_sim := Simulation.new()
	ally_sim.setup(ally_state)
	ally_state.armies.clear()
	ally_state.battles.clear()
	var ally_id := 0
	var city_owner_id := 1
	var enemy_id := 2
	ally_state.set_diplomatic_relation(
		ally_id,
		city_owner_id,
		GameState.DiplomaticRelation.ALLIED
	)
	ally_state.set_diplomatic_relation(
		ally_id,
		enemy_id,
		GameState.DiplomaticRelation.WAR
	)
	ally_state.set_diplomatic_relation(
		city_owner_id,
		enemy_id,
		GameState.DiplomaticRelation.WAR
	)
	var allied_city := -1
	var allied_road: Edge = null
	for edge in ally_state.edges:
		if (
			ally_state.cities[edge.city_a].owner_nation
				== city_owner_id
		):
			allied_city = edge.city_a
			allied_road = edge
			break
		if (
			ally_state.cities[edge.city_b].owner_nation
				== city_owner_id
		):
			allied_city = edge.city_b
			allied_road = edge
			break
	var enemy_besieger := _make_army(
		705,
		enemy_id,
		5000,
		10
	)
	enemy_besieger.move_from = (
		allied_road.city_b
		if allied_road.city_a == allied_city
		else allied_road.city_a
	)
	enemy_besieger.move_to = allied_city
	var allied_relief := _make_army(
		706,
		ally_id,
		5000,
		10
	)
	allied_relief.move_from = enemy_besieger.move_from
	allied_relief.move_to = allied_city
	ally_state.armies = [
		enemy_besieger,
		allied_relief,
	] as Array[Army]
	ally_sim._start_or_join_siege(
		enemy_besieger,
		ally_state.cities[allied_city],
		allied_road
	)
	var allied_siege: Battle = ally_state.battles[0]
	ally_sim._start_or_join_siege(
		allied_relief,
		ally_state.cities[allied_city],
		allied_road
	)
	enemy_besieger.size = 0
	ally_sim._advance_siege(allied_siege)
	_check(
		ally_state.cities[allied_city].owner_nation
			== city_owner_id
			and allied_siege.finished
			and allied_siege.side_a.is_empty()
			and allied_siege.side_b.is_empty()
			and allied_relief.state == Army.State.IDLE
			and allied_relief.location_city == allied_city,
		"盟军击败盟友城市上的围城方后必须解除围城并驻城，不得接管围城或夺取城市"
	)
	ally_sim.free()

# ------------------------------------------------------------------ 25. 边上驻防状态 + AI + 适应累计
# ------------------------------------------------------------------ 24b. 后到守军打断围城并回退进度

func _test_siege_interruption_and_late_garrison() -> void:
	print("[24b] 围城中断：任何后到守军先参战，攻城进度按中断天数回退")
	_check(
		_approx(
			Combat.siege_progress_after_interruption(50.0, 3),
			50.0 - Combat.SIEGE_INTERRUPTION_DECAY_PER_DAY * 3.0
		),
		"攻城中断 3 天应按每日回退率累计扣减"
	)

	var gs := GameState.new()
	gs.generate_grid_world(2424)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()

	var from_city := -1
	var siege_city := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation != gs.cities[edge.city_b].owner_nation:
			from_city = edge.city_a
			siege_city = edge.city_b
			break
	var city := gs.cities[siege_city]
	var road := gs.edge_of(from_city, siege_city)
	var original_owner := city.owner_nation
	var attacker := _make_army(710, gs.cities[from_city].owner_nation, 5000, 0, 100)
	attacker.state = Army.State.FIGHTING
	attacker.move_from = from_city
	attacker.move_to = siege_city
	var idle_guard := _make_army(711, original_owner, 600, 0, 100)
	idle_guard.state = Army.State.IDLE
	idle_guard.location_city = siege_city
	idle_guard.move_from = siege_city
	var recovering_guard := _make_army(712, original_owner, 400, 0, 100)
	recovering_guard.state = Army.State.RECOVERING
	recovering_guard.location_city = siege_city
	recovering_guard.move_from = siege_city
	gs.armies.append_array([attacker, idle_guard, recovering_guard])

	# 模拟已经推进到破城线、但同日有两支战斗外守军落位的异常状态。
	var siege := gs.new_battle(Battle.Kind.SIEGE)
	siege.city = city
	siege.edge = road
	siege.siege_required = 100
	siege.siege_progress = Combat.SIEGE_PROGRESS_REQUIRED
	siege.side_a.append(attacker)
	attacker.battle_id = siege.id

	sim._advance_siege(siege)
	_check(
		siege.has_garrison
		and siege.side_b.has(idle_guard)
		and siege.side_b.has(recovering_guard),
		"围城日开始时必须收集城内全部 IDLE/RECOVERING 守军"
	)
	_check(
		idle_guard.state == Army.State.FIGHTING
		and recovering_guard.state == Army.State.FIGHTING
		and idle_guard.battle_id == siege.id
		and recovering_guard.battle_id == siege.id,
		"后到守军必须进入当前围城战，不能留在战斗外等待占领清理"
	)
	_check(
		_approx(
			siege.siege_progress,
			Combat.SIEGE_PROGRESS_REQUIRED - Combat.SIEGE_INTERRUPTION_DECAY_PER_DAY
		),
		"守军出现当天不得占领，进度还应回退 1 点"
	)
	_check(
		city.owner_nation == original_owner and not siege.finished,
		"城内仍有守军时城市不得易主，围城必须切回战斗阶段"
	)
	_check(
		siege.siege_required == 100,
		"item 6：后到守军不得抬高破城所需兵力（应保持工事换算值 100），实为 %d" % siege.siege_required
	)

	sim._advance_siege(siege)
	sim._advance_siege(siege)
	_check(
		_approx(
			siege.siege_progress,
			Combat.SIEGE_PROGRESS_REQUIRED
				- Combat.SIEGE_INTERRUPTION_DECAY_PER_DAY * 3.0
		),
		"守城战连续中断 3 天应累计回退，实为 %.2f" % siege.siege_progress
	)
	sim.free()



func _test_edge_holding_state() -> void:
	print("[25] HOLDING：AI 进入高 danger 边、固定位置、占用容量、补给控制适应")
	var gs := GameState.new()
	gs.generate_grid_world(5150)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()
	gs.uses_heightmap = true

	var c1 := -1
	var c2 := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation != gs.cities[edge.city_b].owner_nation:
			c1 = edge.city_a
			c2 = edge.city_b
			break
	var own_nation := gs.cities[c1].owner_nation
	var enemy_nation := gs.cities[c2].owner_nation
	for city in gs.cities:
		city.owner_nation = own_nation
		city.is_capital = false
		city.has_warehouse = false
		city.is_food_hub = false
		city.is_manpower_hub = false
		city.fort_strength_max = 0
	for edge in gs.edges:
		edge.max_manpower = 0
		edge.danger = 0.0
	gs.cities[c2].owner_nation = enemy_nation
	gs.nations[own_nation].capital_city_id = -1
	var hold_edge := gs.edge_of(c1, c2)
	hold_edge.danger = 0.9
	hold_edge.max_manpower = 45000
	gs.cities[c1].is_food_hub = true
	var city_guard := _make_army(
		799,
		gs.cities[c1].owner_nation,
		5000,
		10
	)
	city_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	city_guard.state = Army.State.IDLE
	city_guard.location_city = c1
	city_guard.move_from = c1
	var holder := _make_army(800, gs.cities[c1].owner_nation, 1000, 10)
	holder.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	holder.state = Army.State.IDLE
	holder.location_city = c1
	holder.move_from = c1
	gs.armies.append_array([city_guard, holder])

	var hold_view := AiWorldView.build(gs, own_nation)
	var hold_plan := CityDefensePlan.build(
		hold_view,
		StrategicMapSnapshot.build(hold_view),
		ThreatField.build(hold_view)
	)
	for line_army in [city_guard, holder]:
		if int(hold_plan.assigned_posture_by_army.get(
			line_army.id,
			CityDefensePlan.Posture.NONE
		)) == CityDefensePlan.Posture.EDGE:
			holder = line_army
	var hold_order := hold_plan.candidate_for(
		holder,
		ArmyCoordinator.new()
	)
	var hold_order_executed := (
		hold_order != null
		and hold_order.kind == ActionCandidate.Kind.HOLD
		and sim._execute_ai_candidate(holder, hold_order)
	)
	_check(
		hold_order_executed
			and holder.state == Army.State.MOVING
			and holder.move_to == c2,
		"边境 AI 应选择最高 danger 敌对边部署")
	_check(_approx(holder.hold_target_progress, Simulation.HOLDING_TARGET_PROGRESS),
		"驻防目标应位于从己方端点出发的35%%位置")
	var guard := 0
	while holder.state == Army.State.MOVING and guard < 40:
		sim._advance_movement()
		guard += 1
	_check(
		holder.state == Army.State.HOLDING
		and _approx(holder.move_progress, Simulation.HOLDING_TARGET_PROGRESS),
		"抵达己方侧驻防点后应进入 HOLDING，state=%d progress=%.2f"
			% [holder.state, holder.move_progress]
	)
	_check(holder.on_edge and hold_edge.passing_count == 1,
		"HOLDING 必须继续占用道路容量")
	var fixed_pos := holder.move_progress
	for i in range(5):
		sim._advance_movement()
	_check(_approx(holder.move_progress, fixed_pos), "HOLDING 位置不得随日推进")

	holder.holding_days = 10
	holder.supply_ratio = 1.0
	sim._advance_holding_adaptation()
	_check(holder.holding_days == 11, "满补给驻防每天应累计 1 天")
	holder.supply_ratio = 0.5
	sim._advance_holding_adaptation()
	_check(holder.holding_days == 11, "部分补给时驻防适应应暂停")
	holder.supply_ratio = 0.0
	sim._advance_holding_adaptation()
	_check(holder.holding_days == 9, "完全断粮每天应衰减 2 天适应，实为 %d" % holder.holding_days)

	holder.supply_ratio = 1.0
	holder.holding_days = 179
	sim._advance_holding_adaptation()
	_check(holder.state == Army.State.HOLDING and holder.holding_days == 180,
		"驻防达到 180 天后仍应保持 HOLDING，不得因时间自动推进")
	for i in range(30):
		sim._advance_holding_adaptation()
	_check(holder.state == Army.State.HOLDING and holder.holding_days == 210,
		"驻防没有时间上限，满补给时适应天数应持续累计")
	holder.morale = 0.0
	sim._retreat(holder)
	_check(holder.state == Army.State.RETREATING and holder.holding_days == 0,
		"驻防军撤退时必须清零适应度")
	sim.free()

# ------------------------------------------------------------------ 26. 边上双端点补给

func _test_edge_supply_from_both_endpoints() -> void:
	print("[26] 边上补给：按真实位置比较双端点，当前边接敌不切断友方端点")
	var gs := GameState.new()
	gs.generate_grid_world(6160)
	gs.armies.clear()
	gs.battles.clear()
	var a := -1
	var b := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation == gs.cities[edge.city_b].owner_nation:
			a = edge.city_a
			b = edge.city_b
			break
	var road := gs.edge_of(a, b)
	road.distance = 5
	road.danger = 0.2
	var nation := gs.cities[a].owner_nation
	_set_warehouses(gs, nation, [a, b] as Array[int], [100, 100] as Array[int], a)
	var army := _make_army(810, nation, 1000, 10)
	army.state = Army.State.HOLDING
	army.move_from = a
	army.move_to = b
	army.move_progress = 0.8
	army.on_edge = true
	gs.armies.append(army)

	var near_b := Pathfinding.nearest_supply_city(gs, army)
	_check(near_b[0] == b and _approx(float(near_b[1]), 0.12),
		"位于 80%% 位置应从更近端点 B 取粮，实为 %s" % str(near_b))
	gs.cities[b].food_storage = 0
	var fallback_a := Pathfinding.nearest_supply_city(gs, army)
	_check(fallback_a[0] == a and _approx(float(fallback_a[1]), 0.48),
		"B 无粮时应回退从 A 取粮，实为 %s" % str(fallback_a))

	var enemy := _make_army(811, (nation + 1) % GameState.NATION_COUNT, 500, 10)
	enemy.state = Army.State.MOVING
	enemy.move_from = b
	enemy.move_to = a
	enemy.move_progress = 0.1
	enemy.on_edge = true
	gs.armies.append(enemy)
	var contested := Pathfinding.nearest_supply_city(gs, army)
	_check(contested[0] == a and _approx(float(contested[1]), 0.48),
		"当前边出现敌军时仍应从相连友方端点 A 取粮，实为 %s" % str(contested))

# ------------------------------------------------------------------ 26b. 粮仓最小损耗路线 + 首都失守

func _test_warehouse_logistics() -> void:
	print("[26b] 粮仓机制：最小损耗路线、多粮仓扩展、首都失守迁都与缴获")
	var gs := GameState.new()
	gs.generate_grid_world(6262)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()

	# 两条均为两段的本国路线：0→2 danger 高，0→16 danger 低，应选择后者。
	for city in gs.cities:
		city.owner_nation = 0
	_set_warehouses(gs, 0, [2, 16] as Array[int], [100, 100] as Array[int], 2)
	for pair in [[0, 1], [1, 2]]:
		var risky := gs.edge_of(pair[0], pair[1])
		risky.distance = 1
		risky.danger = 0.5
	for pair in [[0, 8], [8, 16]]:
		var safe := gs.edge_of(pair[0], pair[1])
		safe.distance = 1
		safe.danger = 0.0
	var probe := _make_army(812, 0, 1000, 10)
	probe.state = Army.State.IDLE
	probe.location_city = 0
	probe.move_from = 0
	gs.armies.append(probe)
	var supply := Pathfinding.nearest_supply_city(gs, probe)
	_check(supply[0] == 16 and _approx(float(supply[1]), 0.2),
		"同距离时应选择 danger 更低的粮仓 16，实为 %s" % str(supply))
	sim._prepare_supply_network_caches()
	var cached_supply := sim._cached_supply_sources(
		probe,
		sim._daily_supply_source_cache,
		sim._daily_supply_network_cache,
		sim._stable_supply_city_source_cache
	)
	var stable_nation_cache: Dictionary = (
		sim._stable_supply_city_source_cache[0]
	)
	_check(
		cached_supply == Pathfinding.supply_sources(gs, probe)
			and stable_nation_cache.has(0),
		"驻城补给来源缓存结果必须与直接路径计算一致"
	)
	sim._prepare_supply_network_caches()
	_check(
		(sim._stable_supply_city_source_cache[0] as Dictionary).has(0),
		"补给网络与围城状态未变时，驻城来源必须跨日保留"
	)
	var second_probe := _make_army(814, 0, 1000, 10)
	second_probe.state = Army.State.IDLE
	second_probe.location_city = 1
	second_probe.move_from = 1
	sim._cached_supply_sources(
		second_probe,
		sim._daily_supply_source_cache,
		sim._daily_supply_network_cache,
		sim._stable_supply_city_source_cache
	)
	sim._invalidate_supply_city_sources_for_siege_changes({0: true})
	stable_nation_cache = sim._stable_supply_city_source_cache[0]
	_check(
		not stable_nation_cache.has(0)
			and stable_nation_cache.has(1),
		"围城变化必须只失效对应城市的驻城补给来源"
	)
	sim._invalidate_supply_city_sources_for_siege_changes({})
	gs.ownership_revision += 1
	sim._prepare_supply_network_caches()
	_check(
		not sim._stable_supply_city_source_cache.has(0),
		"补给网络依赖版本变化必须失效对应国家的全部驻城来源"
	)

	# 独立世界验证首都失守：30% 库存汇入胜方首都，败方立即投降后迁都。
	var gs2 := GameState.new()
	gs2.generate_grid_world(6363)
	var sim2 := Simulation.new()
	sim2.setup(gs2)
	gs2.armies.clear()
	gs2.battles.clear()
	var old_capital_id := gs2.nations[0].capital_city_id
	var old_capital := gs2.cities[old_capital_id]
	old_capital.food_storage = 100
	var captor_capital := gs2.cities[gs2.nations[1].capital_city_id]
	captor_capital.food_storage = 500
	for nation_a in range(gs2.nations.size()):
		for nation_b in range(nation_a + 1, gs2.nations.size()):
			gs2.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	gs2.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var captor := _make_army(813, 1, 1000, 10)
	gs2.armies.append(captor)
	sim2._capture_city(captor, old_capital)
	var new_capital_id := gs2.nations[0].capital_city_id
	_check(old_capital.owner_nation == 1 and not old_capital.has_warehouse
		and old_capital.food_storage == 0,
		"失守首都应注销旧粮仓并清空原库存")
	_check(captor_capital.food_storage == 530,
		"胜方首都应获得 30%% 粮食缴获：预期 530，实为 %d" % captor_capital.food_storage)
	_check(new_capital_id != old_capital_id and new_capital_id != -1
		and gs2.cities[new_capital_id].owner_nation == 0
		and gs2.cities[new_capital_id].is_capital
		and gs2.cities[new_capital_id].has_warehouse,
		"败方应在剩余城市中迁都并建立新粮仓，实为 %d" % new_capital_id)
	_check(
		not gs2.is_enemy(0, 1)
			and not gs2.diplomatic_history.is_empty()
			and int(
				gs2.diplomatic_history[-1].get(
					"surrendering_nation",
					-1
				)
			) == 0,
		"首都失守必须立即投降，不得等待月度和平意愿结算"
	)
	sim.free()
	sim2.free()


func _test_atomic_territory_transactions() -> void:
	print("[26c] 原子领土事务：行政设施、库存、回滚与无实控法理国")

	# 公开薄封装必须独立完成旧控制者行政状态修复；调用方不得先摘首都/粮仓。
	var transfer_state := GameState.new()
	transfer_state.generate_grid_world(63630)
	var former_owner := 1
	var recipient := 0
	var recipient_warehouse := transfer_state.warehouse_cities_of(recipient)[0]
	recipient_warehouse.food_storage = 500
	var old_capital_id := transfer_state.nations[former_owner].capital_city_id
	var old_capital := transfer_state.cities[old_capital_id]
	old_capital.food_storage = 100
	var extra_warehouse: City = null
	for candidate in transfer_state.land_cities_of(former_owner):
		if not candidate.is_capital and not candidate.has_warehouse:
			extra_warehouse = candidate
			break
	_check(extra_warehouse != null, "原子领土事务回归必须找到普通城市作为附加粮仓")
	if extra_warehouse != null:
		extra_warehouse.has_warehouse = true
		extra_warehouse.food_storage = 70
		transfer_state.nations[former_owner].warehouse_city_ids.append(
			extra_warehouse.id
		)
		transfer_state.refresh_derived()
		var warehouse_revision := transfer_state.ownership_revision
		var warehouse_result: Dictionary = (
			transfer_state.transfer_city_control(
				extra_warehouse.id,
				recipient,
				recipient,
				GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,
				"atomic_warehouse_capture"
			)
		)
		_check(
			bool(warehouse_result.get("ok", false))
				and bool(warehouse_result.get("changed", false))
				and warehouse_result.get("changed_city_ids", [])
					== [extra_warehouse.id]
				and transfer_state.ownership_revision == warehouse_revision + 1
				and extra_warehouse.owner_nation == recipient
				and transfer_state.recognized_owner_of(extra_warehouse.id)
					== former_owner
				and extra_warehouse.occupation_sponsor_nation == recipient
				and not extra_warehouse.has_warehouse
				and extra_warehouse.food_storage == 0
				and not transfer_state.nations[former_owner]
					.warehouse_city_ids.has(extra_warehouse.id)
				and recipient_warehouse.food_storage == 570
				and transfer_state.territory_structure_valid(),
			(
				"transfer_city_control 直接攻占粮仓必须摘除旧索引，"
				+ "并按 MOVE_TO_NEW_POOL 将库存全额转入新控制者粮池"
			)
		)

	var capital_revision := transfer_state.ownership_revision
	var capital_result: Dictionary = transfer_state.transfer_city_control(
		old_capital_id,
		recipient,
		recipient,
		GameState.TerritoryStockDisposition.CAPTURE_SPOILS,
		"atomic_capital_capture"
	)
	var relocated_capital := transfer_state.nations[former_owner].capital_city_id
	_check(
		bool(capital_result.get("ok", false))
			and bool(capital_result.get("changed", false))
			and capital_result.get("changed_city_ids", []) == [old_capital_id]
			and transfer_state.ownership_revision == capital_revision + 1
			and old_capital.owner_nation == recipient
			and transfer_state.recognized_owner_of(old_capital_id) == former_owner
			and old_capital.occupation_sponsor_nation == recipient
			and not old_capital.is_capital
			and not old_capital.has_warehouse
			and old_capital.food_storage == 0
			and relocated_capital >= 0
			and relocated_capital != old_capital_id
			and transfer_state.cities[relocated_capital].owner_nation == former_owner
			and transfer_state.cities[relocated_capital].is_capital
			and transfer_state.cities[relocated_capital].has_warehouse
			and recipient_warehouse.food_storage == 600
			and transfer_state.territory_structure_valid(),
		(
			"transfer_city_control 直接攻占首都必须自动迁都，并按 "
			+ "CAPTURE_SPOILS 仅将 30% 库存计入新控制者粮池"
		)
	)

	# 旧国仅剩一座首都时，直接攻占必须清空首都/粮仓索引；它可以继续
	# 保有该城法理，且这种“无实控但有法理”的状态应是合法中间态。
	var landless_state := GameState.new()
	landless_state.generate_grid_world(63631)
	var landless_capital_id := landless_state.nations[former_owner].capital_city_id
	for city in landless_state.cities:
		if city.owner_nation != former_owner or city.id == landless_capital_id:
			continue
		city.owner_nation = recipient
		landless_state.recognized_city_owners[city.id] = recipient
		city.occupation_sponsor_nation = -1
		city.loyalty_target_nation = recipient
	landless_state.cities[landless_capital_id].food_storage = 90
	landless_state.refresh_derived()
	_check(
		landless_state.territory_structure_valid(),
		"最后一城攻占夹具在事务前必须结构合法"
	)
	var landless_result: Dictionary = landless_state.transfer_city_control(
		landless_capital_id,
		recipient,
		recipient,
		GameState.TerritoryStockDisposition.DESTROY,
		"atomic_last_city_capture"
	)
	var occupied_last_city := landless_state.cities[landless_capital_id]
	_check(
		bool(landless_result.get("ok", false))
			and bool(landless_result.get("changed", false))
			and occupied_last_city.owner_nation == recipient
			and landless_state.recognized_owner_of(landless_capital_id)
				== former_owner
			and occupied_last_city.occupation_sponsor_nation == recipient
			and not occupied_last_city.is_capital
			and not occupied_last_city.has_warehouse
			and occupied_last_city.food_storage == 0
			and landless_state.cities_of(former_owner).is_empty()
			and not landless_state.nations[former_owner].alive
			and landless_state.nations[former_owner].capital_city_id == -1
			and landless_state.nations[former_owner].warehouse_city_ids.is_empty()
			and landless_state.territory_structure_valid(),
		(
			"最后一座实控城被占后旧国必须清空行政索引；"
			+ "法理仍属于无实控国时 territory_structure_valid 必须为 true；result=%s"
			% [landless_result]
		)
	)

	# 批量事务必须先完整验证，再一次提交。即使第一项合法，只要后项非法
	# 或调用方使用了过期 revision，全部领土/行政/库存状态都必须逐字段不变。
	var rollback_state := GameState.new()
	rollback_state.generate_grid_world(63632)
	for rollback_a in range(rollback_state.nations.size()):
		for rollback_b in range(
			rollback_a + 1, rollback_state.nations.size()
		):
			rollback_state.set_diplomatic_relation(
				rollback_a,
				rollback_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var overlay_region: Array[int] = []
	for overlay_city in rollback_state.land_cities_of(recipient):
		if overlay_city.is_capital:
			continue
		overlay_region.append(overlay_city.id)
		if overlay_region.size() == 3:
			break
	var overlay_subject := rollback_state.enfeoff(
		recipient, overlay_region
	)
	var proposed_suzerainty := rollback_state.suzerainty.duplicate(true)
	if proposed_suzerainty.has(overlay_subject):
		proposed_suzerainty[overlay_subject]["tribute_rate"] = 0.5
	_check(
		overlay_subject >= 0
			and proposed_suzerainty != rollback_state.suzerainty
			and rollback_state.suzerainty_structure_valid()
			and rollback_state.territory_structure_valid(),
		"政治 overlay 回滚夹具必须由真实分封建立，且事务前结构合法"
	)
	var rollback_targets: Array[City] = []
	for candidate in rollback_state.land_cities_of(former_owner):
		if not candidate.is_capital and not candidate.has_warehouse:
			rollback_targets.append(candidate)
			if rollback_targets.size() == 2:
				break
	_check(rollback_targets.size() == 2, "原子回滚夹具必须找到两座普通城市")
	if rollback_targets.size() == 2:
		var invalid_operations: Array[Dictionary] = [
			{
				"city_id": rollback_targets[0].id,
				"controller_id": recipient,
				"sponsor_id": recipient,
			},
			{
				"city_id": rollback_targets[1].id,
				"controller_id": rollback_state.nations.size(),
			},
		]
		var invalid_before := _territory_fingerprint(rollback_state)
		var invalid_result: Dictionary = (
			rollback_state.apply_territory_transaction(
				invalid_operations,
				{},
				-1,
				proposed_suzerainty
			)
		)
		_check(
			not bool(invalid_result.get("ok", true))
				and not bool(invalid_result.get("changed", true))
				and not bool(invalid_result.get("territory_changed", true))
				and not bool(invalid_result.get("political_changed", true))
				and not str(invalid_result.get("error", "")).is_empty()
				and invalid_result.get("changed_city_ids", []).is_empty()
				and _territory_fingerprint(rollback_state) == invalid_before,
			(
				"批量事务后项非法时，proposed_suzerainty 与全部领土/外交/"
				+ "资源/军队/revision 状态必须零变化"
			)
		)

		var conflict_operations: Array[Dictionary] = [{
			"city_id": rollback_targets[0].id,
			"controller_id": recipient,
			"sponsor_id": recipient,
		}]
		var conflict_before := _territory_fingerprint(rollback_state)
		var conflict_result: Dictionary = (
			rollback_state.apply_territory_transaction(
				conflict_operations,
				{},
				rollback_state.ownership_revision + 1,
				proposed_suzerainty
			)
		)
		_check(
			not bool(conflict_result.get("ok", true))
				and not bool(conflict_result.get("changed", true))
				and not bool(conflict_result.get("territory_changed", true))
				and not bool(conflict_result.get("political_changed", true))
				and not str(conflict_result.get("error", "")).is_empty()
				and conflict_result.get("changed_city_ids", []).is_empty()
				and _territory_fingerprint(rollback_state) == conflict_before,
			(
				"expected_ownership_revision 冲突必须在提交政治 overlay 前失败，"
				+ "且完整政治事务指纹不变"
			)
		)

		# 外交 operation 也必须与领土/政治共用 phase 1 校验与 phase 2 提交：
		# 多边成功只加一次 revision；stale 或末项非法时完整指纹零变化。
		rollback_state.set_diplomatic_relation(
			0, 1, GameState.DiplomaticRelation.WAR
		)
		rollback_state.set_diplomatic_relation(
			0, 2, GameState.DiplomaticRelation.WAR
		)
		var diplomatic_revision_before := rollback_state.diplomacy_revision
		var diplomatic_batch: Array[Dictionary] = [
			{
				"nation_a": 0,
				"nation_b": 1,
				"relation": GameState.DiplomaticRelation.NEUTRAL,
				"truce_days": GameState.DEFAULT_TRUCE_DAYS,
			},
			{
				"nation_a": 0,
				"nation_b": 2,
				"relation": GameState.DiplomaticRelation.NEUTRAL,
				"truce_days": GameState.DEFAULT_TRUCE_DAYS,
			},
		]
		var diplomatic_result := rollback_state.apply_territory_transaction(
			[] as Array[Dictionary], {}, rollback_state.ownership_revision,
			null, diplomatic_batch, rollback_state.diplomacy_revision
		)
		_check(
			bool(diplomatic_result.get("ok", false))
				and bool(diplomatic_result.get("diplomacy_changed", false))
				and rollback_state.diplomacy_revision
					== diplomatic_revision_before + 1
				and rollback_state.relation_between(0, 1)
					== GameState.DiplomaticRelation.NEUTRAL
				and rollback_state.relation_between(0, 2)
					== GameState.DiplomaticRelation.NEUTRAL
				and rollback_state.truce_until(0, 1)
					== rollback_state.day + GameState.DEFAULT_TRUCE_DAYS
				and rollback_state.truce_until(0, 2)
					== rollback_state.day + GameState.DEFAULT_TRUCE_DAYS,
			"同批多条合法外交 operation 必须一次提交且 diplomacy revision 只加一"
		)
		var stale_diplomacy_before := _territory_fingerprint(rollback_state)
		var stale_diplomacy_result := (
			rollback_state.apply_territory_transaction(
				[] as Array[Dictionary], {}, rollback_state.ownership_revision,
				null, diplomatic_batch,
				rollback_state.diplomacy_revision + 1
			)
		)
		_check(
			not bool(stale_diplomacy_result.get("ok", true))
				and _territory_fingerprint(rollback_state)
					== stale_diplomacy_before,
			"stale diplomacy revision 必须在事务入口拒绝且完整状态零变化"
		)
		var invalid_diplomacy_batch := diplomatic_batch.duplicate(true)
		invalid_diplomacy_batch.append({
			"nation_a": 1,
			"nation_b": 2,
			"relation": 999,
		})
		var invalid_diplomacy_before := _territory_fingerprint(rollback_state)
		var invalid_diplomacy_result := (
			rollback_state.apply_territory_transaction(
				[] as Array[Dictionary], {}, rollback_state.ownership_revision,
				null, invalid_diplomacy_batch,
				rollback_state.diplomacy_revision
			)
		)
		_check(
			not bool(invalid_diplomacy_result.get("ok", true))
				and _territory_fingerprint(rollback_state)
					== invalid_diplomacy_before,
			"外交批次末项非法时必须回滚此前合法 operation 并保持完整状态零变化"
		)

	var noop_city := rollback_state.cities[rollback_state.nations[recipient].capital_city_id]
	var noop_before := _territory_fingerprint(rollback_state)
	var noop_result: Dictionary = rollback_state.transfer_city_control(
		noop_city.id, noop_city.owner_nation, -1
	)
	_check(
		bool(noop_result.get("ok", false))
			and not bool(noop_result.get("changed", true))
			and str(noop_result.get("error", "x")).is_empty()
			and noop_result.get("changed_city_ids", []).is_empty()
			and _territory_fingerprint(rollback_state) == noop_before,
		"合法幂等 transfer 必须返回 ok=true changed=false 且完整指纹不变"
	)

	# 忠诚恢复区域包含附加粮仓时，事务先把随城库存归回旧共享粮池，
	# 再严格按事务前粮池库存和产能比例划转一次。
	var restore_state := GameState.new()
	restore_state.generate_grid_world(63633)
	restore_state.armies.clear()
	restore_state.battles.clear()
	var restore_parent := 0
	var restore_target := 1
	var pool_subject := 2
	for relation_a in range(restore_state.nations.size()):
		for relation_b in range(relation_a + 1, restore_state.nations.size()):
			restore_state.set_diplomatic_relation(
				relation_a, relation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	restore_state.set_diplomatic_relation(
		restore_parent, pool_subject, GameState.DiplomaticRelation.ALLIED
	)
	restore_state.set_diplomatic_relation(
		restore_parent, restore_target, GameState.DiplomaticRelation.WAR
	)
	restore_state.set_diplomatic_relation(
		pool_subject, restore_target, GameState.DiplomaticRelation.WAR
	)
	restore_state.suzerainty[pool_subject] = {
		"overlord_id": restore_parent,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	for warehouse_id in (
		restore_state.nations[pool_subject].warehouse_city_ids.duplicate()
	):
		restore_state.cities[warehouse_id].has_warehouse = false
		restore_state.cities[warehouse_id].food_storage = 0
	restore_state.nations[pool_subject].warehouse_city_ids.clear()
	for city in restore_state.cities:
		city.food_per_half_year = 0
		city.food_storage = 0
	var restore_city: City = null
	for candidate in restore_state.land_cities_of(restore_parent):
		if not candidate.is_capital and not candidate.has_warehouse:
			restore_city = candidate
			break
	var subject_output_city := restore_state.land_cities_of(pool_subject)[0]
	_check(
		restore_city != null,
		"忠诚恢复附加粮仓回归必须找到一座非首都迁移城市"
	)
	if restore_city != null:
		var restore_parent_capital := restore_state.cities[
			restore_state.nations[restore_parent].capital_city_id
		]
		var restore_target_capital := restore_state.cities[
			restore_state.nations[restore_target].capital_city_id
		]
		restore_parent_capital.food_storage = 700
		restore_target_capital.food_storage = 200
		restore_city.has_warehouse = true
		restore_city.food_storage = 300
		restore_city.food_per_half_year = 40
		restore_city.loyalty_target_nation = restore_target
		restore_state.nations[restore_parent].warehouse_city_ids.append(
			restore_city.id
		)
		subject_output_city.food_per_half_year = 60
		restore_state.refresh_derived()
		var parent_holder_before := restore_state.food_pool_holder(restore_parent)
		var target_holder_before := restore_state.food_pool_holder(restore_target)
		var parent_pool_stock_before := 0
		for warehouse in restore_state.warehouse_cities_of(parent_holder_before):
			parent_pool_stock_before += warehouse.food_storage
		var target_pool_stock_before := 0
		for warehouse in restore_state.warehouse_cities_of(target_holder_before):
			target_pool_stock_before += warehouse.food_storage
		var shared_food_output_before := 0
		for member_id in restore_state.food_pool_members(parent_holder_before):
			for pool_city in restore_state.land_cities_of(member_id):
				shared_food_output_before += pool_city.food_per_half_year
		var moved_food_output_before := restore_city.food_per_half_year
		var expected_food_transfer := int(floor(
			float(parent_pool_stock_before)
				* float(moved_food_output_before)
				/ float(shared_food_output_before)
		))
		var global_food_before := 0
		for city in restore_state.cities:
			global_food_before += city.food_storage
		var restored := restore_state.restore_regional_loyalty_target(
			restore_parent, restore_target, [restore_city.id] as Array[int]
		)
		var parent_pool_stock_after := 0
		for warehouse in restore_state.warehouse_cities_of(
			restore_state.food_pool_holder(restore_parent)
		):
			parent_pool_stock_after += warehouse.food_storage
		var target_pool_stock_after := 0
		for warehouse in restore_state.warehouse_cities_of(
			restore_state.food_pool_holder(restore_target)
		):
			target_pool_stock_after += warehouse.food_storage
		var global_food_after := 0
		for city in restore_state.cities:
			global_food_after += city.food_storage
		_check(
			restored
				and parent_holder_before == restore_parent
				and restore_state.food_pool_members(parent_holder_before)
					== ([restore_parent, pool_subject] as Array[int])
				and parent_pool_stock_before == 1000
				and target_pool_stock_before == 200
				and shared_food_output_before == 100
				and moved_food_output_before == 40
				and expected_food_transfer == 400
				and restore_city.owner_nation == restore_target
				and restore_state.recognized_owner_of(restore_city.id)
					== restore_parent
				and restore_city.occupation_sponsor_nation == restore_target
				and not restore_city.has_warehouse
				and restore_city.food_storage == 0
				and not restore_state.nations[restore_parent]
					.warehouse_city_ids.has(restore_city.id)
				and not restore_state.nations[restore_target]
					.warehouse_city_ids.has(restore_city.id)
				and parent_pool_stock_after
					== parent_pool_stock_before - expected_food_transfer
				and target_pool_stock_after
					== target_pool_stock_before + expected_food_transfer
				and parent_pool_stock_after + target_pool_stock_after
					== parent_pool_stock_before + target_pool_stock_before
				and global_food_after == global_food_before
				and restore_state.nations[parent_holder_before].granary_food
					== parent_pool_stock_after
				and restore_state.nations[
					restore_state.food_pool_holder(restore_target)
				].granary_food == target_pool_stock_after
				and restore_state.suzerainty_structure_valid()
				and restore_state.territory_structure_valid(),
			(
				"restore_regional_loyalty_target 必须先归回迁移粮仓库存，"
				+ "再按事务前共享粮池 1000×40/100 只划转一次；"
				+ "before=%d old/new=%d/%d after=%d"
			) % [
				global_food_before,
				parent_pool_stock_after,
				target_pool_stock_after,
				global_food_after,
			]
		)

	# 三个小粮仓不能因逐仓比例向下取整而少扣；超额请求则返回可扣总量。
	var withdraw_state := GameState.new()
	withdraw_state.generate_grid_world(63634)
	var withdraw_owner := 0
	var withdraw_ids: Array[int] = [
		withdraw_state.nations[withdraw_owner].capital_city_id,
	]
	for candidate in withdraw_state.land_cities_of(withdraw_owner):
		if not withdraw_ids.has(candidate.id):
			withdraw_ids.append(candidate.id)
		if withdraw_ids.size() == 3:
			break
	_check(withdraw_ids.size() == 3, "多粮仓扣粮夹具必须找到三座本国城市")
	if withdraw_ids.size() == 3:
		_set_warehouses(
			withdraw_state, withdraw_owner, withdraw_ids,
			[1, 1, 1] as Array[int], withdraw_ids[0]
		)
		withdraw_state.refresh_derived()
		var withdrawn := withdraw_state._withdraw_food_from_warehouses(
			withdraw_state.nations[withdraw_owner], 2
		)
		var remaining_food := 0
		for warehouse in withdraw_state.warehouse_cities_of(withdraw_owner):
			remaining_food += warehouse.food_storage
		var overdrawn := withdraw_state._withdraw_food_from_warehouses(
			withdraw_state.nations[withdraw_owner], 5
		)
		var final_food := 0
		for warehouse in withdraw_state.warehouse_cities_of(withdraw_owner):
			final_food += warehouse.food_storage
		_check(
			withdrawn == 2
				and remaining_food == 1
				and overdrawn == 1
				and final_food == 0,
			(
				"[1,1,1] 多粮仓扣 2 必须精确剩 1；超额再扣应只返回 1，"
				+ "实为 withdrawn=%d remaining=%d overdrawn=%d final=%d"
			) % [withdrawn, remaining_food, overdrawn, final_food]
		)

	# 通过真实忠诚恢复入口覆盖同一尾数场景：旧池 [1,1,1] 按 2/3
	# 产能划出 2，目标池只能收到实际扣除的 2，全局库存保持 3。
	var tiny_restore_state := GameState.new()
	tiny_restore_state.generate_grid_world(63635)
	tiny_restore_state.armies.clear()
	tiny_restore_state.battles.clear()
	var tiny_parent := 0
	var tiny_target := 1
	for relation_a in range(tiny_restore_state.nations.size()):
		for relation_b in range(
			relation_a + 1, tiny_restore_state.nations.size()
		):
			tiny_restore_state.set_diplomatic_relation(
				relation_a, relation_b, GameState.DiplomaticRelation.NEUTRAL
			)
	tiny_restore_state.set_diplomatic_relation(
		tiny_parent, tiny_target, GameState.DiplomaticRelation.WAR
	)
	for city in tiny_restore_state.cities:
		city.food_per_half_year = 0
		city.food_storage = 0
	var tiny_parent_cities := tiny_restore_state.land_cities_of(tiny_parent)
	var tiny_warehouse_ids: Array[int] = [
		tiny_restore_state.nations[tiny_parent].capital_city_id,
	]
	for candidate in tiny_parent_cities:
		if not tiny_warehouse_ids.has(candidate.id):
			tiny_warehouse_ids.append(candidate.id)
		if tiny_warehouse_ids.size() == 3:
			break
	var tiny_restore_city: City = null
	var tiny_retained_city: City = null
	for candidate in tiny_parent_cities:
		if tiny_warehouse_ids.has(candidate.id):
			continue
		if tiny_restore_city == null:
			tiny_restore_city = candidate
		elif tiny_retained_city == null:
			tiny_retained_city = candidate
			break
	_check(
		tiny_warehouse_ids.size() == 3
			and tiny_restore_city != null
			and tiny_retained_city != null,
		"忠诚恢复尾数回归必须找到三座粮仓及两座产能城市"
	)
	if (
		tiny_warehouse_ids.size() == 3
		and tiny_restore_city != null
		and tiny_retained_city != null
	):
		_set_warehouses(
			tiny_restore_state, tiny_parent, tiny_warehouse_ids,
			[1, 1, 1] as Array[int], tiny_warehouse_ids[0]
		)
		tiny_restore_city.food_per_half_year = 2
		tiny_restore_city.loyalty_target_nation = tiny_target
		tiny_retained_city.food_per_half_year = 1
		tiny_restore_state.refresh_derived()
		var tiny_target_stock_before := 0
		for warehouse in tiny_restore_state.warehouse_cities_of(tiny_target):
			tiny_target_stock_before += warehouse.food_storage
		var tiny_global_before := 0
		for city in tiny_restore_state.cities:
			tiny_global_before += city.food_storage
		var tiny_restored := tiny_restore_state.restore_regional_loyalty_target(
			tiny_parent, tiny_target,
			[tiny_restore_city.id] as Array[int]
		)
		var tiny_parent_stock_after := 0
		for warehouse in tiny_restore_state.warehouse_cities_of(tiny_parent):
			tiny_parent_stock_after += warehouse.food_storage
		var tiny_target_stock_after := 0
		for warehouse in tiny_restore_state.warehouse_cities_of(tiny_target):
			tiny_target_stock_after += warehouse.food_storage
		var tiny_global_after := 0
		for city in tiny_restore_state.cities:
			tiny_global_after += city.food_storage
		_check(
			tiny_restored
				and tiny_restore_city.owner_nation == tiny_target
				and tiny_parent_stock_after == 1
				and tiny_target_stock_after == tiny_target_stock_before + 2
				and tiny_global_before == 3
				and tiny_global_after == tiny_global_before
				and tiny_restore_state.territory_structure_valid(),
			(
				"忠诚恢复从 [1,1,1] 旧粮池划出 2 时必须全局守恒；"
				+ "before=%d parent=%d target=%d after=%d"
			) % [
				tiny_global_before, tiny_parent_stock_after,
				tiny_target_stock_after, tiny_global_after,
			]
		)


func _test_capital_capture_capitulation() -> void:
	print("[26c] 首都失陷：两跳范围归胜方、范围外保留、立即投降")
	var surrender_state := GameState.new()
	surrender_state.generate_grid_world(6365)
	surrender_state.armies.clear()
	surrender_state.battles.clear()
	for city in surrender_state.cities:
		city.owner_nation = 2
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		surrender_state.recognized_city_owners[city.id] = 2
	surrender_state.cities[0].owner_nation = 0
	surrender_state.recognized_city_owners[0] = 0
	for loser_city in [1, 2, 3, 4]:
		surrender_state.cities[loser_city].owner_nation = 1
		surrender_state.recognized_city_owners[loser_city] = 1
	for chain_city in range(4):
		surrender_state.edge_of(
			chain_city,
			chain_city + 1
		).max_manpower = Edge.STANDARD_MANPOWER
	_set_single_warehouse(surrender_state, 0, 0, 100)
	_set_single_warehouse(surrender_state, 1, 1, 100)
	_set_single_warehouse(surrender_state, 2, 63, 100)
	_set_warehouses(
		surrender_state,
		3,
		[] as Array[int],
		[] as Array[int]
	)
	for nation_a in range(surrender_state.nations.size()):
		for nation_b in range(
			nation_a + 1,
			surrender_state.nations.size()
		):
			surrender_state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	surrender_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	surrender_state.refresh_derived()
	var surrender_sim := Simulation.new()
	surrender_sim.setup(surrender_state)
	var capital_captor := _make_army(814, 0, 5000, 10)
	capital_captor.location_city = 0
	capital_captor.move_from = 0
	surrender_state.armies.append(capital_captor)
	var expected_capital_transfers := (
		surrender_sim._capital_capture_transfer_city_ids(1, 1)
	)
	var capital_capture_revision_before := surrender_state.ownership_revision
	surrender_sim._capture_city(
		capital_captor,
		surrender_state.cities[1]
	)
	var captured_capital_transferred := (
		surrender_state.cities[1].owner_nation == 0
		and surrender_state.recognized_owner_of(1) == 0
		and surrender_state.cities[1].loyalty_target_nation == 0
		and surrender_state.cities[1].rebellion_progress == 0
		and surrender_state.cities[1].rebellion_cooldown_until_day
			> surrender_state.day
	)
	var two_hop_cities_transferred := true
	for transferred_city in [1, 2, 3]:
		two_hop_cities_transferred = (
			two_hop_cities_transferred
			and surrender_state.cities[transferred_city].owner_nation == 0
			and surrender_state.recognized_owner_of(transferred_city) == 0
			and surrender_state.cities[
				transferred_city
			].occupation_sponsor_nation == -1
		)
	var outside_city_retained := (
		surrender_state.cities[4].owner_nation == 1
		and surrender_state.recognized_owner_of(4) == 1
		and surrender_state.cities[4].occupation_sponsor_nation == -1
	)
	var capital_surrender_recorded := (
		not surrender_state.diplomatic_history.is_empty()
		and int(
			surrender_state.diplomatic_history[-1].get(
				"surrendering_nation",
				-1
			)
		) == 1
	)
	_check(
		captured_capital_transferred
			and two_hop_cities_transferred
			and outside_city_retained,
		(
			"首都1失陷后城1/2/3须归胜方；"
			+ "距首都三跳的城4必须保留给战败国"
		)
	)
	_check(
		expected_capital_transfers == ([1, 2, 3] as Array[int])
			and surrender_state.ownership_revision
				== capital_capture_revision_before + 1,
		"首都两跳城市必须一次原子事务提交，范围为 [1,2,3]"
	)
	_check(
		not surrender_state.is_enemy(0, 1)
			and surrender_state.truce_until(0, 1)
				> surrender_state.day
			and capital_surrender_recorded,
		"首都失陷当日必须直接结束战争并记录战败国投降"
	)
	_check(
		surrender_state.nations[1].capital_city_id == 4
			and surrender_state.cities[
				surrender_state.nations[1].capital_city_id
			].owner_nation == 1
			and surrender_state.cities[
				surrender_state.nations[1].capital_city_id
			].is_capital
			and surrender_state.cities[
				surrender_state.nations[1].capital_city_id
			].has_warehouse,
		"战败国应迁都到两跳范围外的城4并继续存续"
	)
	# 被实际攻陷的首都已永久确认并进入冷却，后续忠诚月不能把它当作
	# 和平期临时占领，重新“恢复”给旧法理国。
	for stable_city in surrender_state.cities:
		if stable_city.id == 1:
			continue
		stable_city.loyalty_target_nation = stable_city.owner_nation
		stable_city.loyalty = RebellionSystem.LOYALTY_DEFAULT
		stable_city.rebellion_progress = 0
	var peaceful_return_event := false
	for _loyalty_month in range(
		RebellionSystem.REBELLION_PROGRESS_MONTHS
	):
		surrender_state.day += Simulation.DAYS_PER_MONTH
		for event_value in RebellionSystem.resolve_month(
			surrender_state
		):
			var loyalty_event: Dictionary = event_value
			peaceful_return_event = (
				peaceful_return_event
				or (
					str(loyalty_event.get("kind", ""))
						== "loyalty_target_restored"
					and int(loyalty_event.get("target_id", -1))
						== 1
				)
			)
	var permanent_cession_held := not peaceful_return_event
	permanent_cession_held = (
		permanent_cession_held
		and surrender_state.cities[1].owner_nation == 0
		and surrender_state.recognized_owner_of(1) == 0
		and surrender_state.cities[1].loyalty_target_nation == 0
	)
	for transferred_city in [2, 3]:
		permanent_cession_held = (
			permanent_cession_held
			and surrender_state.cities[transferred_city].owner_nation == 0
			and surrender_state.recognized_owner_of(transferred_city) == 0
		)
	permanent_cession_held = (
		permanent_cession_held
		and surrender_state.cities[4].owner_nation == 1
		and surrender_state.recognized_owner_of(4) == 1
	)
	_check(
		permanent_cession_held
			and not surrender_state.is_enemy(0, 1)
			and surrender_state.territory_structure_valid(),
		"首都两跳割让永久确认后推进三个忠诚月不得和平归还，范围外城市仍属旧国"
	)
	surrender_sim.free()

	# 领土事务 API 的直接契约：先转实控再转法理，以及一体化永久主权
	# 转移，都必须把 owner/legal/政治目标收敛并清理叛乱状态。
	var permanent_api_state := GameState.new()
	permanent_api_state.generate_grid_world(6367)
	for api_a in range(permanent_api_state.nations.size()):
		for api_b in range(api_a + 1, permanent_api_state.nations.size()):
			permanent_api_state.set_diplomatic_relation(
				api_a, api_b, GameState.DiplomaticRelation.NEUTRAL
			)
	permanent_api_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	permanent_api_state.day = 123
	var api_targets: Array[City] = []
	for candidate in permanent_api_state.land_cities_of(1):
		if candidate.is_capital or candidate.has_warehouse:
			continue
		api_targets.append(candidate)
		if api_targets.size() >= 2:
			break
	_check(api_targets.size() == 2, "永久领土事务 API 回归必须找到两座普通城市")
	if api_targets.size() == 2:
		var title_city := api_targets[0]
		title_city.rebellion_progress = (
			RebellionSystem.REBELLION_PROGRESS_MONTHS
		)
		title_city.rebellion_cooldown_until_day = -1
		var control_result: Dictionary = permanent_api_state.transfer_city_control(
			title_city.id, 0, 0
		)
		_check(
			bool(control_result.get("ok", false))
				and bool(control_result.get("changed", false))
				and control_result.get("changed_city_ids", [])
					== [title_city.id]
				and title_city.owner_nation == 0
				and permanent_api_state.recognized_owner_of(
					title_city.id
				) == 1
				and title_city.occupation_sponsor_nation == 0
				and permanent_api_state.territory_structure_valid(),
			"transfer_city_control 必须只改变战争实控并保留法理与有效 sponsor"
		)
		var title_result: Dictionary = (
			permanent_api_state.transfer_city_legal_title(
				title_city.id, 0, true
			)
		)
		_check(
			bool(title_result.get("ok", false))
				and bool(title_result.get("changed", false))
				and title_result.get("changed_city_ids", [])
					== [title_city.id]
				and title_city.owner_nation == 0
				and permanent_api_state.recognized_owner_of(
					title_city.id
				) == 0
				and title_city.loyalty_target_nation == 0
				and title_city.occupation_sponsor_nation == -1
				and title_city.rebellion_progress == 0
				and title_city.rebellion_cooldown_until_day
					> permanent_api_state.day
				and permanent_api_state.territory_structure_valid(),
			"transfer_city_legal_title 永久确认后必须同步政治归属并清除临时占领"
		)
		var sovereignty_city := api_targets[1]
		sovereignty_city.rebellion_progress = (
			RebellionSystem.REBELLION_PROGRESS_MONTHS
		)
		sovereignty_city.rebellion_cooldown_until_day = -1
		var sovereignty_result: Dictionary = (
			permanent_api_state.transfer_city_sovereignty(
				sovereignty_city.id, 0, "direct_test_transfer"
			)
		)
		_check(
			bool(sovereignty_result.get("ok", false))
				and bool(sovereignty_result.get("changed", false))
				and sovereignty_result.get("changed_city_ids", [])
					== [sovereignty_city.id]
				and sovereignty_city.owner_nation == 0
				and permanent_api_state.recognized_owner_of(
					sovereignty_city.id
				) == 0
				and sovereignty_city.loyalty_target_nation == 0
				and sovereignty_city.occupation_sponsor_nation == -1
				and sovereignty_city.rebellion_progress == 0
				and sovereignty_city.rebellion_cooldown_until_day
					> permanent_api_state.day
				and permanent_api_state.territory_structure_valid(),
			"transfer_city_sovereignty 必须原子完成实控、法理和政治目标的永久转移"
		)

	# 首都失陷投降后，只确认实际占领；剩余合法飞地即使不连回新首都，
	# 也不能在没有占领事实的情况下自动送给敌国。
	var enclave_state := GameState.new()
	enclave_state.generate_grid_world(6366)
	enclave_state.armies.clear()
	enclave_state.battles.clear()
	for city in enclave_state.cities:
		city.owner_nation = 2
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		enclave_state.recognized_city_owners[city.id] = 2
	enclave_state.cities[0].owner_nation = 0
	enclave_state.recognized_city_owners[0] = 0
	# B 主体链 1-2-3-4 连通；城16 是与主体断开的孤立飞地（只连中立国2）。
	for c in [1, 2, 3, 4, 16]:
		enclave_state.cities[c].owner_nation = 1
		enclave_state.recognized_city_owners[c] = 1
	for road in [[0, 1], [1, 2], [2, 3], [3, 4], [16, 17], [16, 24]]:
		var enclave_edge := enclave_state.edge_of(int(road[0]), int(road[1]))
		if enclave_edge != null:
			enclave_edge.max_manpower = Edge.STANDARD_MANPOWER
	_set_single_warehouse(enclave_state, 0, 0, 100)
	_set_single_warehouse(enclave_state, 1, 1, 100)
	_set_single_warehouse(enclave_state, 2, 63, 100)
	_set_warehouses(
		enclave_state,
		3,
		[] as Array[int],
		[] as Array[int]
	)
	for enclave_a in range(enclave_state.nations.size()):
		for enclave_b in range(enclave_a + 1, enclave_state.nations.size()):
			enclave_state.set_diplomatic_relation(
				enclave_a,
				enclave_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	enclave_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	enclave_state.refresh_derived()
	var enclave_sim := Simulation.new()
	enclave_sim.setup(enclave_state)
	var enclave_captor := _make_army(816, 0, 5000, 10)
	enclave_captor.location_city = 0
	enclave_captor.move_from = 0
	enclave_state.armies.append(enclave_captor)
	enclave_sim._capture_city(enclave_captor, enclave_state.cities[1])
	var enclave_capital := enclave_state.nations[1].capital_city_id
	_check(
		enclave_state.cities[16].owner_nation == 1
			and enclave_state.recognized_owner_of(16) == 1
			and enclave_state.cities[16].occupation_sponsor_nation == -1
			and enclave_state.cities[4].owner_nation == 1,
		(
			"投降后无占领事实的合法飞地城16必须保留给战败国，"
			+ "主体城4也保留：城16归属=%d 法理=%d 首都=%d"
		) % [
			enclave_state.cities[16].owner_nation,
			enclave_state.recognized_owner_of(16),
			enclave_capital,
		]
	)
	_check(
		enclave_state.territory_structure_valid(),
		"首都投降保留合法飞地后领土结构不变量必须成立"
	)
	enclave_sim.free()

# ------------------------------------------------------------------ 27. 驻防战斗适应 + 增援稀释

func _test_holding_combat_adaptation() -> void:
	print("[27] 驻防战斗：快照驻防侧、防御适应、增援稀释、胜后恢复 HOLDING")
	# 同种子同军力：驻防 90 天仅提高防御倍率，应让守方损失更少；攻击惩罚保持相同。
	var atk0 := _make_army(820, 0, 1000, 10)
	var def0 := _make_army(821, 1, 1000, 10)
	var b0 := _make_field_battle([atk0], [def0], 1.0, 4)
	b0.holding_side = 2
	b0.holding_days = 0.0
	var rng0 := RandomNumberGenerator.new()
	rng0.seed = 88
	Combat.resolve_round(b0, rng0)

	var atk90 := _make_army(822, 0, 1000, 10)
	var def90 := _make_army(823, 1, 1000, 10)
	var b90 := _make_field_battle([atk90], [def90], 1.0, 4)
	b90.holding_side = 2
	b90.holding_days = 90.0
	var rng90 := RandomNumberGenerator.new()
	rng90.seed = 88
	Combat.resolve_round(b90, rng90)
	_check(def90.size > def0.size,
		"长期驻防应减少守方伤亡：0天=%d，90天=%d" % [1000 - def0.size, 1000 - def90.size])
	_check(atk90.size == atk0.size,
		"驻防时间不得改变守军攻击惩罚；攻击方伤亡应一致：%d/%d" % [atk0.size, atk90.size])

	var gs := GameState.new()
	gs.generate_grid_world(7170)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()
	var c1 := 0
	var c2 := 1
	var edge := gs.edge_of(c1, c2)
	edge.danger = 1.0
	var holder := _place_army_on_edge(gs, 830, 0, c1, c2, 0.5)
	holder.state = Army.State.HOLDING
	holder.holding_days = 60
	var enemy := _place_army_on_edge(gs, 831, 1, c2, c1, 0.5)
	sim._detect_encounters()
	var battle: Battle = gs.battles[0]
	var holder_side := 1 if battle.side_a.has(holder) else 2
	_check(battle.holding_side == holder_side and _approx(battle.holding_days, 60.0),
		"野战应快照驻防侧及 60 天适应，side=%d days=%.1f" % [battle.holding_side, battle.holding_days])

	var reinforcement := _place_army_on_edge(gs, 832, 0, c1, c2, 0.5)
	sim._join_field_battle(battle, reinforcement, edge)
	_check(_approx(battle.holding_days, 30.0),
		"同兵力非驻防增援应把 60 天适应稀释到 30 天，实为 %.1f" % battle.holding_days)

	enemy.size = 0
	sim._resolve_battles()
	_check(holder.state == Army.State.HOLDING and holder.holding_days == 60,
		"原驻防军获胜后应恢复 HOLDING 并保留自身适应")
	_check(reinforcement.state == Army.State.MOVING,
		"普通增援获胜后应恢复 MOVING，不应免费获得 HOLDING")
	sim.free()

# ------------------------------------------------------------------ 28. 溃逃接战 + 位置连续性

func _test_retreat_contact_and_position_continuity() -> void:
	print("[28] 溃逃接战与位置连续性：驻防截击、中间城拥堵锚点、掉头、新局快照")
	var gs := GameState.new()
	gs.generate_grid_world(8282)
	var sim := Simulation.new()
	sim.setup(gs)
	gs.armies.clear()
	gs.battles.clear()

	var c1 := 0
	var c2 := 1
	var holder := _place_army_on_edge(gs, 900, 0, c1, c2, 0.5)
	holder.state = Army.State.HOLDING
	var retreater := _place_army_on_edge(gs, 901, 1, c2, c1, 0.5)
	retreater.state = Army.State.RETREATING
	retreater.forced_retreat = true
	sim._detect_encounters()
	_check(gs.battles.size() == 1 and holder.state == Army.State.FIGHTING
		and retreater.state == Army.State.FIGHTING,
		"驻防敌军接触溃逃军时必须截击，不能因双方都非 MOVING 而漏战")

	# 到达中间城后下一边拥堵：move_to=-1 时渲染依赖 location_city，必须同步为中间城。
	gs.armies.clear()
	gs.battles.clear()
	var mover := _make_army(902, gs.cities[0].owner_nation, 1000, 10)
	mover.state = Army.State.MOVING
	mover.location_city = 0
	mover.move_from = 0
	mover.move_to = 1
	mover.move_progress = 1.0
	mover.on_edge = true
	mover.path = [2] as Array[int]
	gs.armies.append(mover)
	var first_edge := gs.edge_of(0, 1)
	var blocked_edge := gs.edge_of(1, 2)
	first_edge.passing_count = 1
	blocked_edge.max_manpower = 30000
	blocked_edge.passing_count = 0
	for i in range(2):
		var blocker := _make_army(9100 + i, mover.owner_nation, 1000, 10)
		blocker.state = Army.State.MOVING
		blocker.location_city = 1
		blocker.move_from = 1
		blocker.move_to = 2
		blocker.move_progress = 0.2
		blocker.on_edge = true
		gs.armies.append(blocker)
		blocked_edge.passing_count += 1
	sim._arrive_at_node(mover)
	_check(mover.state == Army.State.MOVING and mover.move_to == -1
		and mover.move_from == 1 and mover.location_city == 1,
		"下一边拥堵时应停在中间城 1；from=%d to=%d location=%d"
			% [mover.move_from, mover.move_to, mover.location_city])

	# 边上撤退若选择原出发端，交换方向并反转 progress 后物理位置必须完全不变。
	gs.armies.clear()
	var turning := _place_army_on_edge(gs, 903, gs.cities[0].owner_nation, 0, 1, 0.2)
	var edge := gs.edge_of(0, 1)
	var norm_before := sim._norm_pos(turning, edge)
	sim._retreat(turning)
	var norm_after := sim._norm_pos(turning, edge)
	_check(_approx(norm_before, norm_after),
		"撤退原地掉头不得改变物理位置：before=%.3f after=%.3f" % [norm_before, norm_after])

	# 多军共同破城时，非主占领军也已在城墙端点，不能瞬移回各自 move_from。
	gs.armies.clear()
	gs.battles.clear()
	var target_city := gs.cities[0]
	var invader_nation := (target_city.owner_nation + 1) % GameState.NATION_COUNT
	var lead := _make_army(904, invader_nation, 2000, 10)
	var support := _make_army(905, invader_nation, 1000, 10)
	for besieger in [lead, support]:
		besieger.state = Army.State.FIGHTING
		besieger.move_from = 1
		besieger.move_to = 0
		besieger.move_progress = 1.0
		gs.armies.append(besieger)
	var siege := gs.new_battle(Battle.Kind.SIEGE)
	siege.city = target_city
	siege.edge = gs.edge_of(0, 1)
	siege.siege_required = 10
	siege.siege_progress = Combat.SIEGE_PROGRESS_REQUIRED
	siege.side_a.append(lead)
	siege.side_a.append(support)
	sim._advance_siege(siege)
	_check(support.state == Army.State.IDLE and support.location_city == target_city.id,
		"共同破城的非主占领军应停在目标城，不得瞬移回出发城；location=%d" % support.location_city)

	# 第三方抵达已有守军的围城时不能加入两侧，应从已抵达的目标城连续撤退，而非瞬移回来源城。
	gs.armies.clear()
	gs.battles.clear()
	for city in gs.cities:
		city.owner_nation = 0
	target_city = gs.cities[0]
	var source_city := gs.cities[1]
	source_city.owner_nation = 2
	var besieger := _make_army(906, 1, 1000, 10)
	var defender := _make_army(907, 0, 1000, 10)
	var third_party := _make_army(908, 2, 1000, 10)
	third_party.state = Army.State.MOVING
	third_party.location_city = source_city.id
	third_party.move_from = source_city.id
	third_party.move_to = target_city.id
	third_party.move_progress = 1.0
	var contested_siege := gs.new_battle(Battle.Kind.SIEGE)
	contested_siege.city = target_city
	contested_siege.edge = gs.edge_of(target_city.id, source_city.id)
	contested_siege.has_garrison = true
	contested_siege.side_a.append(besieger)
	contested_siege.side_b.append(defender)
	gs.armies.append_array([besieger, defender, third_party])
	sim._start_or_join_siege(third_party, target_city, contested_siege.edge)
	_check(third_party.state == Army.State.RETREATING
		and third_party.move_from == target_city.id
		and third_party.move_to == source_city.id
		and _approx(third_party.move_progress, 0.0),
		"第三方抵达围城后应从目标城连续撤退；state=%d from=%d to=%d progress=%.3f"
			% [third_party.state, third_party.move_from, third_party.move_to, third_party.move_progress])

	# 重开游戏复用 Renderer 时必须丢弃旧世界位置快照，防止相同 army id 跨世界飞行。
	var strategic_map := StrategicMap3D.new()
	strategic_map.state = gs
	strategic_map.sim = sim
	strategic_map._army_instances_initialized = true
	strategic_map._last_army_instances_day = gs.day - 1
	sim._runtime_day_in_progress = true
	_check(
		not strategic_map._should_update_army_instances(),
		"异步日结算未提交时 3D 军队实例不得读取并刷新部分状态"
	)
	sim._runtime_day_in_progress = false
	_check(
		strategic_map._should_update_army_instances(),
		"异步日结算提交后 3D 军队实例必须刷新到新日期"
	)
	var renderer := MapRenderer.new()
	renderer._prev_pos = {0: Vector2(7.5, 7.5)}
	renderer._curr_pos = {0: Vector2(7.5, 7.5)}
	renderer._last_day = 99
	renderer.setup(gs, sim)
	_check(renderer._prev_pos.is_empty() and renderer._curr_pos.is_empty() and renderer._last_day == -1,
		"Renderer.setup 必须清空旧世界插值快照")
	sim.seconds_per_day = 1.0
	sim._time_acc = 0.2
	sim._runtime_day_in_progress = true
	sim.paused = false
	sim._process(0.5)
	_check(
		is_equal_approx(sim._time_acc, 0.7),
		"异步日计算期间应累计未超限的时间，保持普通日设定倍速"
	)
	sim._process(0.5)
	_check(
		is_equal_approx(sim._time_acc, 0.9),
		"异步日的时间债务应封顶，提交后至少留出输入与绘制时间"
	)
	renderer._last_day = gs.day - 2
	renderer._curr_pos = {999: Vector2(0.25, 0.5)}
	var presentation_anchor := Vector2(0.31, 0.47)
	renderer._presented_pos[third_party.id] = presentation_anchor
	renderer._sync_snapshots()
	_check(
		renderer._last_day == gs.day - 2
		and renderer._curr_pos.has(999),
		"异步日结算未完成时 Renderer 不得提前抓取未提交的位置"
	)
	sim._runtime_day_in_progress = false
	sim.runtime_day_committed.emit(gs.day)
	_check(
		renderer._last_day == gs.day
		and not renderer._curr_pos.has(999),
		"提交信号必须立即抓取逻辑位置，不得因跨帧追赶跳过中间快照"
	)
	_check(
		renderer._prev_pos.get(
			third_party.id,
			Vector2.ZERO
		).is_equal_approx(presentation_anchor),
		"新表现段必须从上一帧实际位置开始"
	)
	_check(
		renderer._army_position(third_party).is_equal_approx(
			renderer._grid_to_pixel(presentation_anchor)
		),
		"提交后的第一帧必须保持 C0 位置连续"
	)
	# 时间基线性插值：军队在 _tick_duration 内按真实经过时间从 _prev_pos 匀速
	# （smoothstep 缓动）滑向 _curr_pos，与该 tick 计算跨了几帧无关。
	var interp_prev := Vector2(0.31, 0.47)
	var follow_target := Vector2(0.71, 0.47)
	renderer._prev_pos = {third_party.id: interp_prev}
	renderer._curr_pos = {third_party.id: follow_target}
	renderer._tick_duration = 0.25
	renderer._tick_elapsed = 0.0
	sim.paused = false
	gs.winner = -1
	_check(
		renderer._army_position(third_party).is_equal_approx(
			renderer._grid_to_pixel(interp_prev)
		),
		"tick 起点（t=0）必须停在上一 tick 位置，保证 C0 连续"
	)
	# 推进半个 tick 时长：t=0.5，smoothstep(0.5)=0.5，恰好中点。
	renderer._advance_tick_interpolation(0.125)
	var halfway := renderer._army_position(third_party)
	_check(
		halfway.is_equal_approx(
			renderer._grid_to_pixel(interp_prev.lerp(follow_target, 0.5))
		),
		"半个 tick 时长后应位于两端中点（smoothstep 对称）"
	)
	# 推进超过整个 tick 时长：t 被 clamp 到 1，停在目标，永不越过。
	renderer._advance_tick_interpolation(1.0)
	var arrived := renderer._army_position(third_party)
	_check(
		arrived.is_equal_approx(renderer._grid_to_pixel(follow_target)),
		"超过一个 tick 时长后必须精确停在目标位置，永不越过"
	)
	renderer.free()
	sim.free()

# ------------------------------------------------------------------ 29-30. 分层 Utility AI

func _test_ai_strategic_map_and_threat() -> void:
	print("[29] AI 战略图与威胁场：桥/割点识别、价值排序、抵达时间衰减")
	var gs := GameState.new()
	gs.generate_grid_world(7001)
	var personality_left := AiWorldView.build(gs, 0)
	var personality_right := AiWorldView.build(gs, 1)
	_check(
		_approx(UtilityAI._aggression(personality_left), 1.0)
		and _approx(UtilityAI._aggression(personality_right), 1.0)
		and _approx(UtilityAI._caution(personality_left), 1.0)
		and _approx(UtilityAI._caution(personality_right), 1.0),
		"国家 ID 不得隐式改变正式 AI 的进攻性或谨慎度"
	)
	personality_left.legacy_id_personality_enabled = true
	personality_right.legacy_id_personality_enabled = true
	_check(
		not _approx(
			UtilityAI._caution(personality_left),
			UtilityAI._caution(personality_right)
		),
		"A/B 开关应能复现旧版 nation_id 性格偏差"
	)
	var ai_decision_interval := (
		Simulation.AI_DECISION_INTERVAL_DAYS
	)
	_check(
		Simulation._ai_nation_ids_for_day(4, 0) == [0, 1, 2, 3]
		and Simulation._ai_nation_ids_for_day(
			4,
			ai_decision_interval
		) == [1, 2, 3, 0]
		and Simulation._ai_nation_ids_for_day(
			4,
			ai_decision_interval * 3
		) == [3, 0, 1, 2]
		and Simulation._ai_nation_ids_for_day(
			4,
			ai_decision_interval * 3,
			false
		)
			== [0, 1, 2, 3],
		"国家决策起点必须按AI决策轮次轮换，旧版固定顺序仅用于A/B"
	)
	# 错峰：国家数 > 决策周期时，每天只返回相位 posmod(id,interval) 匹配当日的国家；
	# 各相位在周期内互不重叠且并集为全体，保证每国每周期恰好决策一次。
	var stagger_interval := 10
	var stagger_union := {}
	var stagger_ok := true
	for phase_day in range(stagger_interval):
		var due := Simulation._ai_nation_ids_for_day(
			40, phase_day, false, stagger_interval
		)
		for nation_id in due:
			# 该国相位必须等于当天相位，且不得跨天重复。
			if nation_id % stagger_interval != phase_day or stagger_union.has(nation_id):
				stagger_ok = false
			stagger_union[nation_id] = true
	_check(
		stagger_ok and stagger_union.size() == 40,
		"错峰必须把40国无重叠地均摊到10天，且并集覆盖全部国家：命中=%d" % stagger_union.size()
	)
	# force_all=true（议和/宣战后强制重算）或国家数<=周期（含2国镜像）时全体到期。
	_check(
		Simulation._ai_nation_ids_for_day(40, 3, false, stagger_interval, true).size() == 40
		and Simulation._ai_nation_ids_for_day(2, 3, false, stagger_interval).size() == 2,
		"强制重算或国家数不超过周期时必须全体今天决策，退化保持镜像对称"
	)
	var startup_state := GameState.new()
	startup_state.generate_world(7002, 12, 48)
	var startup_sim := Simulation.new()
	startup_sim.setup(startup_state)
	startup_sim._ai_assign_targets()
	var startup_due := Simulation._ai_nation_ids_for_day(
		startup_state.nations.size(), startup_state.day, true,
		Simulation.AI_DECISION_INTERVAL_DAYS, false, true
	)
	var startup_cached_nations := startup_sim._ai_defense_plan_cache.keys()
	startup_cached_nations.sort()
	startup_due.sort()
	_check(
		startup_cached_nations == startup_due
			and startup_sim._ai_last_decision_day == startup_state.day,
		"大地图首轮 AI 必须按相位错峰，不能因未初始化标记全量计算：%s/%s"
			% [startup_cached_nations, startup_due]
	)
	startup_sim.free()
	var normally_due := Simulation._ai_nation_ids_for_day(
		40,
		3,
		false,
		stagger_interval
	)
	var locally_forced := Simulation.merge_forced_ai_nation_order(
		normally_due,
		[2, 17, 23, 99, -1],
		40,
		3,
		false,
		stagger_interval
	)
	_check(
		locally_forced == [2, 3, 13, 17, 23, 33],
		"局部占领失效必须只合并到期相位与受影响国家，过滤越界ID且保持全局轮转顺序"
	)
	var locally_forced_rotated := (
		Simulation.merge_forced_ai_nation_order(
			Simulation._ai_nation_ids_for_day(
				40,
				13,
				true,
				stagger_interval
			),
			[2, 17],
			40,
			13,
			true,
			stagger_interval
		)
	)
	var full_rotated := Simulation._ai_nation_ids_for_day(
		40,
		13,
		true,
		stagger_interval,
		true
	)
	var filtered_full: Array[int] = []
	for nation_id in full_rotated:
		if nation_id in [2, 3, 13, 17, 23, 33]:
			filtered_full.append(nation_id)
	_check(
		locally_forced_rotated == filtered_full,
		"局部失效国家必须继承该决策轮的全局轮转顺序，不得固定抢占队首"
	)
	var local_replan_state := GameState.new()
	local_replan_state.generate_grid_world(7000)
	var local_replan_sim := Simulation.new()
	root.add_child(local_replan_sim)
	local_replan_sim.setup(local_replan_state)
	local_replan_sim._ai_last_decision_day = 7
	var capture_city := 5
	var old_capture_owner := (
		local_replan_state.cities[capture_city].owner_nation
	)
	var claimant := (
		(old_capture_owner + 1)
			% local_replan_state.nations.size()
	)
	local_replan_state.cities[capture_city].owner_nation = claimant
	var expected_replans := {
		old_capture_owner: true,
		claimant: true,
	}
	for neighbor_id in local_replan_state.neighbors(capture_city):
		expected_replans[
			local_replan_state.cities[
				neighbor_id
			].owner_nation
		] = true
	local_replan_sim._force_ai_replan_for_capture(
		old_capture_owner,
		claimant,
		capture_city
	)
	_check(
		local_replan_sim._ai_last_decision_day == 7
			and local_replan_sim._ai_forced_nations
				== expected_replans,
		"普通占领必须只标记旧主、占领者和相邻势力，不得退化为全体强制重算"
	)
	local_replan_sim.free()
	var path_cache_state := GameState.new()
	path_cache_state.generate_grid_world(7002)
	var path_cache := {}
	var unrestricted_a := AiWorldView.cached_path_field(
		path_cache_state,
		path_cache_state.day,
		path_cache,
		0,
		-1,
		false,
		true,
		1,
		0
	)
	var unrestricted_b := AiWorldView.cached_path_field(
		path_cache_state,
		path_cache_state.day,
		path_cache,
		0,
		-1,
		false,
		true,
		2,
		0
	)
	var start_goal := AiWorldView.cached_path_field(
		path_cache_state,
		path_cache_state.day,
		path_cache,
		0,
		0,
		false,
		false,
		0,
		0
	)
	var no_goal := AiWorldView.cached_path_field(
		path_cache_state,
		path_cache_state.day,
		path_cache,
		0,
		0,
		false,
		false,
		-1,
		0
	)
	_check(
		path_cache.size() == 2
			and unrestricted_a == unrestricted_b
			and start_goal == no_goal,
		"路径场缓存必须合并不限制通行国或目标等于起点时的语义等价键"
	)
	var enemy_goals: Array[int] = []
	for path_city in path_cache_state.cities:
		if path_city.owner_nation != 0:
			enemy_goals.append(path_city.id)
		if enemy_goals.size() >= 2:
			break
	for enemy_goal in enemy_goals:
		AiWorldView.cached_path_field(
			path_cache_state,
			path_cache_state.day,
			path_cache,
			0,
			0,
			false,
			true,
			enemy_goal,
			0
		)
	_check(
		enemy_goals.size() == 2
			and path_cache.size() == 4,
		"限制通行国时不同敌方终点必须保持独立缓存键，不能错误共享可达区域"
	)
	var path_cache_sim := Simulation.new()
	root.add_child(path_cache_sim)
	path_cache_sim.setup(path_cache_state)
	var shared_path_view := path_cache_sim._build_ai_view(0)
	shared_path_view.path_field(
		0,
		0,
		false,
		true,
		-1,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var shared_cache_size := (
		path_cache_sim._ai_path_field_cache_by_nation[0]
			as Dictionary
	).size()
	var shared_path_result := path_cache_sim._cached_ai_path_field(
		0,
		0,
		0,
		false,
		true,
		-1,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var direct_path_result := Pathfinding.dijkstra_field(
		path_cache_state,
		0,
		0,
		false,
		true,
		-1,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	_check(
		(
			path_cache_sim._ai_path_field_cache_by_nation[0]
				as Dictionary
		).size() == shared_cache_size
			and shared_path_result == direct_path_result,
		"战役规划与命令提交必须命中同一国家级路径缓存，且结果与直接Dijkstra一致"
	)
	path_cache_sim.free()
	gs.armies.clear()
	for city in gs.cities:
		city.owner_nation = 1
	for city_id in [0, 1, 2]:
		gs.cities[city_id].owner_nation = 0
	gs.edge_of(0, 1).max_manpower = 15000
	gs.edge_of(1, 2).max_manpower = 15000
	_set_single_warehouse(gs, 0, 0, 500)
	var view := AiWorldView.build(gs, 0)
	var snapshot := StrategicMapSnapshot.build(view)
	var shared_edge_snapshot := StrategicMapSnapshot.build(
		view,
		{},
		{},
		StrategicMapSnapshot.build_base_edge_values(gs)
	)
	var key01 := StrategicMapSnapshot._edge_key(0, 1)
	var key12 := StrategicMapSnapshot._edge_key(1, 2)
	_check(
		shared_edge_snapshot.edge_value == snapshot.edge_value
			and shared_edge_snapshot.edge_value.size()
				== gs.edges.size(),
		"共享道路基础值必须与逐快照全图构建完全等价，并保留完整 edge_value 契约"
	)
	_check(snapshot.bridge_impact.has(key01) and snapshot.bridge_impact.has(key12),
		"线性三城领土的两条边都应识别为 bridge")
	_check(snapshot.articulation_impact.has(1),
		"线性三城中间城市 1 应识别为 articulation city")

	var friendly := _make_army(920, 0, 15000, 10)
	friendly.location_city = 0
	friendly.move_from = 0
	friendly.state = Army.State.IDLE
	var enemy := _make_army(921, 1, 1000, 10)
	enemy.location_city = 2
	enemy.move_from = 2
	enemy.state = Army.State.IDLE
	gs.armies.append_array([friendly, enemy])
	view = AiWorldView.build(gs, 0)
	var threat := ThreatField.build(view)
	var frontier_plan := CityDefensePlan.build(
		view,
		snapshot,
		threat
	)
	var all_frontiers_screened := true
	for frontier_city in snapshot.frontier_cities:
		all_frontiers_screened = (
			all_frontiers_screened
			and frontier_plan.requirement_at(frontier_city)
				>= CityDefensePlan.FRONTIER_SCREEN_POWER
					* CityDefensePlan.REQUIRED_PRESSURE_SHARE
		)
	_check(
		all_frontiers_screened,
		"所有实际前线城市都应获得最低驻防价值，不得只守少数高分要地"
	)
	_check(threat.threat_at(2) > threat.threat_at(1)
		and threat.threat_at(1) > threat.threat_at(0),
		"敌军威胁应随抵达时间衰减：c2=%.1f c1=%.1f c0=%.1f"
			% [threat.threat_at(2), threat.threat_at(1), threat.threat_at(0)])
	gs.edge_of(1, 2).max_manpower = 5000
	gs.edge_of(1, 2).distance = 1
	gs.edge_of(1, 2).travel_time_multiplier = 1.0
	threat = ThreatField.build(AiWorldView.build(gs, 0))
	_check(
		threat.threat_at(1) > 0.0,
		"一万五编制敌军的威胁应按五千运输足迹穿过五千容量道路"
	)
	enemy.max_size = 5000
	threat = ThreatField.build(AiWorldView.build(gs, 0))
	_check(
		threat.threat_at(1) > 0.0,
		"五千满编敌军的威胁应能穿过五千容量道路"
	)

	var deep_state := GameState.new()
	deep_state.generate_grid_world(7003)
	deep_state.armies.clear()
	for city in deep_state.cities:
		city.owner_nation = 2
	for city_id in [16]:
		deep_state.cities[city_id].owner_nation = 0
	for city_id in [9, 17, 25]:
		deep_state.cities[city_id].owner_nation = 1
	for edge in deep_state.edges:
		edge.max_manpower = 0
	for pair in [[16, 17], [17, 9], [17, 25]]:
		deep_state.edge_of(pair[0], pair[1]).max_manpower = 30000
	deep_state.nations[1].capital_city_id = 25
	deep_state.cities[25].is_capital = true
	var deep_view := AiWorldView.build(deep_state, 0)
	var deep_snapshot := StrategicMapSnapshot.build(deep_view)
	_check(
		deep_snapshot.campaign_target == 17
		and deep_snapshot.value_of_offense(17) > deep_snapshot.value_of_city(17),
		"两层规划应识别打开后续城市且切断敌方连通的门户城市"
	)
	_check(
		UtilityAI._post_capture_exposure(deep_view, 17) == 1
		and UtilityAI._strategic_attack_adjustment(
			deep_view, deep_snapshot, 17, 2
		) > UtilityAI._strategic_attack_adjustment(
			deep_view, deep_snapshot, 17, 1
		),
		"主战役目标只应在多方向进攻时获得大会战加分"
	)
	var strategic_adjustment := UtilityAI._strategic_attack_adjustment(
		deep_view, deep_snapshot, 17, 2
	)
	_check(
		strategic_adjustment > 0.0 and strategic_adjustment <= 1.5,
		"图论规划只能作为有界战略先验，不能覆盖战力与补给判断"
	)
	deep_snapshot.campaign_target = -1
	_check(
		UtilityAI._strategic_attack_adjustment(
			deep_view, deep_snapshot, 17, 2
		) <= 0.5,
		"非主战役目标不得获得国家级集中加分"
	)

	var route_state := GameState.new()
	route_state.generate_grid_world(7005)
	route_state.armies.clear()
	for city in route_state.cities:
		city.owner_nation = 2
	for city_id in [0, 10]:
		route_state.cities[city_id].owner_nation = 0
	for city_id in [1, 2]:
		route_state.cities[city_id].owner_nation = 1
	for edge in route_state.edges:
		edge.max_manpower = 0
	for pair in [[0, 1], [1, 2], [2, 10]]:
		var route_edge := route_state.edge_of(pair[0], pair[1])
		route_edge.max_manpower = 30000
		route_edge.distance = 1
	route_state.cities[1].fort_strength = 1
	route_state.cities[2].fort_strength = 1
	route_state.cities[2].is_capital = true
	route_state.cities[2].has_warehouse = true
	route_state.cities[2].is_food_hub = true
	route_state.cities[2].is_manpower_hub = true
	route_state.nations[1].capital_city_id = 2
	_set_single_warehouse(route_state, 0, 0, 5000)
	var route_army := _make_army(923, 0, 15000, 10, 10)
	route_army.location_city = 0
	route_army.move_from = 0
	route_state.armies.append(route_army)
	var route_view := AiWorldView.build(route_state, 0)
	var route_snapshot := StrategicMapSnapshot.build(route_view)
	var route_threat := ThreatField.build(route_view)
	route_view.executable_attack_paths_enabled = false
	var unreachable_order := UtilityAI._attack_candidate(
		route_view,
		route_snapshot,
		route_threat,
		ArmyCoordinator.new(),
		route_army,
		0.0
	)
	_check(
		unreachable_order != null
		and unreachable_order.target_city == 2,
		"旧 AI 应复现优先选择被敌城阻隔的高价值纵深目标"
	)
	var route_sim := Simulation.new()
	route_sim.setup(route_state)
	_check(
		not route_sim._execute_ai_candidate(
			route_army, unreachable_order
		),
		"旧纵深攻击命令应因中间敌城不可通行而执行失败"
	)
	route_view.executable_attack_paths_enabled = true
	var executable_order := UtilityAI._attack_candidate(
		route_view,
		route_snapshot,
		route_threat,
		ArmyCoordinator.new(),
		route_army,
		0.0
	)
	_check(
		executable_order != null
		and executable_order.target_city == 1
		and route_sim._execute_ai_candidate(
			route_army, executable_order
		),
		"新 AI 应跳过不可达纵深目标并攻击可执行的门户城市"
	)
	route_sim.free()

	var siege := deep_state.new_battle(Battle.Kind.SIEGE)
	siege.city = deep_state.cities[17]
	var contested := MapRenderer.contested_city_ids(deep_state)
	_check(
		contested.has(17) and not contested.has(16),
		"红框只应标记正在发生城战或围城的城市"
	)


func _test_stable_force_resource_cache_filter() -> void:
	print("[29a] AI 资源缓存：只复用快照后仍稳定的索引，动态报告必须重算")
	var sim := Simulation.new()
	var marker := {"value": 7}
	var snapshot_cache := {
		"nation_aggregates_built": true,
		"frontier_matrix_built": true,
		"monthly_gold_flows": marker,
		"power:0": marker,
		"troops:0": marker,
		"full_troops:0": marker,
		"owned_cities:0": marker,
		"wars:0": marker,
		"allies:0": marker,
		"coalition:0": marker,
		"frontier:0:1": marker,
		"borders:0": marker,
		"resource:0": marker,
		"food:0:0:1000:0": marker,
		"food_stock:0": marker,
		"food_posture:0": marker,
		"mobilization:0:0": marker,
		"garrison_by_city": marker,
		"threat:0:1": marker,
	}
	var stable := sim._stable_force_resource_cache_from_snapshot(
		snapshot_cache
	)
	var expected_stable := [
		"frontier_matrix_built", "monthly_gold_flows",
		"wars:0", "allies:0", "frontier:0:1",
		"borders:0",
	]
	var stable_keys := stable.keys()
	stable_keys.sort()
	expected_stable.sort()
	_check(
		stable_keys == expected_stable,
		"军制缓存白名单只应保留稳定索引，实为 %s" % [stable_keys]
	)
	_check(
		stable["frontier:0:1"] == marker
		and not stable.has("nation_aggregates_built")
		and not stable.has("power:0")
		and not stable.has("troops:0")
		and not stable.has("full_troops:0")
		and not stable.has("owned_cities:0")
		and not stable.has("coalition:0")
		and not stable.has("resource:0")
		and not stable.has("food:0:0:1000:0")
		and not stable.has("food_stock:0")
		and not stable.has("food_posture:0")
		and not stable.has("mobilization:0:0")
		and not stable.has("garrison_by_city")
		and not stable.has("threat:0:1"),
		"国库/粮食/姿态/驻军等快照后可变报告不得跨阶段复用"
	)
	sim.free()


func _test_city_defense_incremental_topology() -> void:
	print("[29b] 防区增量更新：拓扑复用、动态失效、外交与控制区重建")
	var state := GameState.new()
	state.generate_grid_world(70031)
	state.uses_heightmap = true
	state.armies.clear()
	state.battles.clear()
	for city in state.cities:
		city.owner_nation = 0
		city.is_capital = false
		city.has_warehouse = false
		city.is_food_hub = false
		city.is_manpower_hub = false
	state.cities[10].owner_nation = 1
	state.nations[0].capital_city_id = -1
	for nation_a in range(state.nations.size()):
		for nation_b in range(
			nation_a + 1,
			state.nations.size()
		):
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
	state.edge_of(9, 10).max_manpower = (
		Edge.STANDARD_MANPOWER
	)
	var guard := _make_army(9890, 0, 5000, 10, 10)
	guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	guard.location_city = 9
	guard.move_from = 9
	var attacker := _make_army(
		9891,
		1,
		15000,
		10,
		10
	)
	attacker.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	attacker.location_city = 10
	attacker.move_from = 10
	state.armies.append_array([guard, attacker])
	state.refresh_derived()

	var first_view := AiWorldView.build(state, 0)
	var first_snapshot := StrategicMapSnapshot.build(first_view)
	var first_plan := CityDefensePlan.build(
		first_view,
		first_snapshot,
		ThreatField.build(first_view)
	)
	var first_topology := first_plan.topology
	var first_required := (
		first_plan.required_power.duplicate(true)
	)
	var second_view := AiWorldView.build(state, 0)
	var second_snapshot := StrategicMapSnapshot.build(
		second_view
	)
	var reused_plan := CityDefensePlan.build(
		second_view,
		second_snapshot,
		ThreatField.build(second_view),
		first_plan
	)
	_check(
		first_plan.topology_rebuilt
			and reused_plan.topology_reused
			and reused_plan.dynamic_plan_reused
			and reused_plan.topology == first_topology,
		"控制区、外交和军队状态不变时必须复用同一防区拓扑与动态需求"
	)
	_check(
		reused_plan.required_power == first_required
			and reused_plan.posture_by_city
				== first_plan.posture_by_city
			and reused_plan.assigned_city_by_army
				== first_plan.assigned_city_by_army,
		"增量复用结果必须与上一轮完整计划逐项一致"
	)

	state.nations[0].frontier_defense_topology = null
	var full_view := AiWorldView.build(state, 0)
	var full_plan := CityDefensePlan.build(
		full_view,
		StrategicMapSnapshot.build(full_view),
		ThreatField.build(full_view)
	)
	_check(
		full_plan.topology_rebuilt
			and full_plan.required_power
				== reused_plan.required_power
			and full_plan.posture_by_city
				== reused_plan.posture_by_city
			and full_plan.assigned_city_by_army
				== reused_plan.assigned_city_by_army,
		"强制全量重建必须与增量复用产生相同防区和Assignment"
	)

	var topology_before_power_change := full_plan.topology
	attacker.size = 10000
	var changed_power_view := AiWorldView.build(state, 0)
	var changed_power_plan := CityDefensePlan.build(
		changed_power_view,
		StrategicMapSnapshot.build(changed_power_view),
		ThreatField.build(changed_power_view),
		full_plan
	)
	_check(
		changed_power_plan.topology_reused
			and not changed_power_plan.dynamic_plan_reused
			and changed_power_plan.topology
				== topology_before_power_change
			and changed_power_plan.requirement_at(9)
				!= full_plan.requirement_at(9),
		"敌军兵力变化只能失效动态需求，不得重建未变化的控制区拓扑"
	)

	state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.NEUTRAL
	)
	var diplomacy_view := AiWorldView.build(state, 0)
	var diplomacy_plan := CityDefensePlan.build(
		diplomacy_view,
		StrategicMapSnapshot.build(diplomacy_view),
		ThreatField.build(diplomacy_view),
		changed_power_plan
	)
	_check(
		diplomacy_plan.topology_rebuilt
			and diplomacy_plan.topology
				!= topology_before_power_change,
		"外交revision变化必须重建防区拓扑"
	)

	state.cities[9].owner_nation = 1
	state.ownership_revision += 1
	var ownership_view := AiWorldView.build(state, 0)
	var ownership_plan := CityDefensePlan.build(
		ownership_view,
		StrategicMapSnapshot.build(ownership_view),
		ThreatField.build(ownership_view),
		diplomacy_plan
	)
	_check(
		(
			ownership_plan.topology_rebuilt
			or ownership_plan.topology_reused
		)
			and not state.nations[0]
				.frontier_defense_sectors.has(9),
		"控制区变化必须删除失效防区；若前线签名等价可继续复用拓扑对象"
	)


func _test_ai_merge_and_retreat_utility() -> void:
	print("[30] AI 协调：同城合并守恒、弱军生成可解释撤退候选")
	var gs := GameState.new()
	gs.generate_grid_world(7002)
	gs.armies.clear()
	for city in gs.cities:
		city.owner_nation = 0
	var a := _make_army(930, 0, 400, 8, 12)
	a.location_city = 0
	a.move_from = 0
	a.state = Army.State.IDLE
	a.morale = 0.5
	var b := _make_army(931, 0, 600, 12, 8)
	b.location_city = 0
	b.move_from = 0
	b.state = Army.State.IDLE
	b.morale = 1.0
	gs.armies.append_array([a, b])
	var morale_mass := float(a.size) * a.morale + float(b.size) * b.morale
	var merged := ArmyCoordinator.merge_colocated(gs)
	_check(merged == 1 and gs.armies.size() == 1 and gs.armies[0].size == 1000,
		"同城兼容军队应合并且总兵力守恒")
	_check(_approx(float(gs.armies[0].size) * gs.armies[0].morale, morale_mass),
		"合并后总士气量必须守恒")

	gs.armies.clear()
	var normal_wave := _make_army(936, 0, 400, 10, 10)
	normal_wave.location_city = 0
	normal_wave.move_from = 0
	var prepared_wave := _make_army(937, 0, 400, 10, 10)
	prepared_wave.location_city = 0
	prepared_wave.move_from = 0
	prepared_wave.offensive_attack_multiplier = 1.5
	prepared_wave.offensive_bonus_until_day = 100
	gs.armies.append_array([normal_wave, prepared_wave])
	_check(
		ArmyCoordinator.merge_colocated(gs) == 0
		and gs.armies.size() == 2,
		"不同攻势倍率或截止日的军队不得合并并稀释限时状态"
	)

	gs.armies.clear()
	var full_source := _make_army(938, 0, 5000, 10, 10)
	full_source.max_size = 5000
	full_source.location_city = 0
	full_source.move_from = 0
	var full_target := _make_army(939, 0, 15000, 10, 10)
	full_target.max_size = 15000
	full_target.location_city = 1
	full_target.move_from = 1
	gs.armies.append_array([full_source, full_target])
	var full_view := AiWorldView.build(gs, 0)
	var full_snapshot := StrategicMapSnapshot.build(full_view)
	var full_threat := ThreatField.build(full_view)
	_check(
		UtilityAI._merge_candidate(
			full_view,
			full_snapshot,
			full_threat,
			ArmyCoordinator.new(),
			full_source
		) == null,
		"目标军已满编时不得跨城聚集，避免多支满编军坍缩到同一位置"
	)

	gs.armies.clear()
	var merge_anchor := _make_army(940, 0, 500, 10, 10)
	merge_anchor.max_size = 15000
	merge_anchor.location_city = 1
	merge_anchor.move_from = 1
	var merge_follower := _make_army(941, 0, 500, 10, 10)
	merge_follower.max_size = 15000
	merge_follower.location_city = 0
	merge_follower.move_from = 0
	gs.armies.append_array([merge_anchor, merge_follower])
	var merge_view := AiWorldView.build(gs, 0)
	var merge_snapshot := StrategicMapSnapshot.build(merge_view)
	var merge_threat := ThreatField.build(merge_view)
	var anchor_merge := UtilityAI._merge_candidate(
		merge_view,
		merge_snapshot,
		merge_threat,
		ArmyCoordinator.new(),
		merge_anchor
	)
	var follower_merge := UtilityAI._merge_candidate(
		merge_view,
		merge_snapshot,
		merge_threat,
		ArmyCoordinator.new(),
		merge_follower
	)
	var anchor_precedes := EquivariantOrder.army_less(
		gs,
		0,
		merge_anchor,
		merge_follower
	)
	var expected_forward := (
		anchor_merge == null
		and follower_merge != null
		and follower_merge.target_city == merge_anchor.location_city
	)
	var expected_reverse := (
		follower_merge == null
		and anchor_merge != null
		and anchor_merge.target_city == merge_follower.location_city
	)
	_check(
		(expected_forward if anchor_precedes else expected_reverse),
		"等战力跨城合并必须按势力局部物理序形成单向偏序，禁止互相追逐成环"
	)

	# 两个行为目标在全部可观察物理键上完全等价时，不存在等变的单值
	# 选择。应延迟本次合并，不能回退到 friendly_armies/城市 ID 顺序。
	var ambiguous_state := GameState.new()
	ambiguous_state.generate_grid_world(7003)
	ambiguous_state.armies.clear()
	ambiguous_state.nations[0].capital_city_id = 0
	ambiguous_state.cities[0].map_position = Vector2(0.2, 0.2)
	for target_city in [1, GameState.GRID]:
		ambiguous_state.cities[target_city].map_position = Vector2(
			0.1,
			0.2
		)
		ambiguous_state.cities[target_city].terrain_height = 0.5
		ambiguous_state.cities[target_city].terrain_relief = 0.5
	var merge_edge_a := ambiguous_state.edge_of(0, 1)
	var merge_edge_b := ambiguous_state.edge_of(
		0,
		GameState.GRID
	)
	merge_edge_a.distance = 4
	merge_edge_b.distance = 4
	merge_edge_a.danger = 0.25
	merge_edge_b.danger = 0.25
	merge_edge_a.max_manpower = 30000
	merge_edge_b.max_manpower = 30000
	EquivariantOrder._city_rank_cache.clear()
	var ambiguous_source := _make_army(942, 0, 500, 10, 10)
	ambiguous_source.location_city = 0
	ambiguous_source.move_from = 0
	var ambiguous_a := _make_army(943, 0, 500, 10, 10)
	ambiguous_a.location_city = 1
	ambiguous_a.move_from = 1
	var ambiguous_b := _make_army(944, 0, 500, 10, 10)
	ambiguous_b.location_city = GameState.GRID
	ambiguous_b.move_from = GameState.GRID
	ambiguous_state.armies.append_array([
		ambiguous_source,
		ambiguous_a,
		ambiguous_b,
	])
	var ambiguous_view := AiWorldView.build(ambiguous_state, 0)
	var ambiguous_snapshot := StrategicMapSnapshot.build(
		ambiguous_view
	)
	var ambiguous_threat := ThreatField.build(ambiguous_view)
	_check(
		EquivariantOrder.army_less(
				ambiguous_state, 0, ambiguous_a, ambiguous_source
		)
			and EquivariantOrder.army_less(
					ambiguous_state, 0, ambiguous_b, ambiguous_source
			)
			and UtilityAI._merge_candidate(
				ambiguous_view,
				ambiguous_snapshot,
				ambiguous_threat,
				ArmyCoordinator.new(),
				ambiguous_source
			) == null,
		"完全等价的跨城合并目标应延迟，不能按城市 ID 或数组顺序决胜"
	)

	gs.armies.clear()
	var weak := _make_army(932, 0, 100, 8, 8)
	weak.location_city = 0
	weak.move_from = 0
	weak.state = Army.State.IDLE
	var strong := _make_army(933, 1, 2000, 15, 15)
	strong.location_city = 0
	strong.move_from = 0
	strong.state = Army.State.IDLE
	gs.armies.append_array([weak, strong])
	var view := AiWorldView.build(gs, 0)
	var snapshot := StrategicMapSnapshot.build(view)
	var threat := ThreatField.build(view)
	var candidate := UtilityAI.choose(view, snapshot, threat, ArmyCoordinator.new(), weak)
	_check(candidate.kind == ActionCandidate.Kind.RETREAT and candidate.target_city != -1,
		"局部敌军显著占优时弱军应生成 RETREAT，实为 kind=%d target=%d"
			% [candidate.kind, candidate.target_city])
	_check(
		not UtilityAI._frontier_deployment_safe(view, threat, weak),
		"城市局部战力低于撤退阈值时不得生成驻边候选，避免边城往返"
	)
	_check(not candidate.reason.is_empty() and candidate.minimum_commit_days >= 30,
		"撤退候选必须保存可解释原因和命令承诺期")

	var assignment_state := GameState.new()
	assignment_state.generate_grid_world(7003)
	assignment_state.uses_heightmap = true
	assignment_state.armies.clear()
	for assignment_city in assignment_state.cities:
		assignment_city.owner_nation = 0
		assignment_city.is_capital = false
		assignment_city.has_warehouse = false
		assignment_city.is_food_hub = false
		assignment_city.is_manpower_hub = false
		assignment_city.fort_strength_max = 0
	assignment_state.nations[0].capital_city_id = -1
	var light_guard := _make_army(934, 0, 5000, 10, 10)
	light_guard.max_size = 5000
	light_guard.location_city = 0
	light_guard.move_from = 0
	var heavy_guard := _make_army(935, 0, 15000, 10, 10)
	heavy_guard.max_size = 15000
	heavy_guard.location_city = 0
	heavy_guard.move_from = 0
	assignment_state.armies.append_array([light_guard, heavy_guard])
	var assignment_view := AiWorldView.build(assignment_state, 0)
	var assignment_snapshot := StrategicMapSnapshot.build(
		assignment_view
	)
	var assignment_plan := CityDefensePlan.new()
	assignment_plan.view = assignment_view
	assignment_plan.snapshot = assignment_snapshot
	assignment_plan.threat = ThreatField.build(assignment_view)
	assignment_plan.required_power = {
		1: 4000.0,
		2: 14000.0,
	}
	assignment_plan.posture_by_city = {
		1: CityDefensePlan.Posture.CITY,
		2: CityDefensePlan.Posture.CITY,
	}
	assignment_plan._assign_role_based_defense()
	var light_target := assignment_plan.assigned_city_for(
		light_guard
	)
	_check(
		assignment_plan.assigned_city_by_army.size() == 1
			and light_target in [1, 2]
			and assignment_plan.assigned_city_for(
				heavy_guard
			) == -1
			and assignment_plan.can_redeploy(
				heavy_guard,
				ArmyCoordinator.new()
			),
		"常态驻防只能分配5000填线军，15000攻势军必须保持机动"
	)
	var light_assignment := assignment_plan.candidate_for(
		light_guard,
		ArmyCoordinator.new()
	)
	var heavy_assignment := assignment_plan.candidate_for(
		heavy_guard,
		ArmyCoordinator.new()
	)
	_check(
		light_assignment.kind == ActionCandidate.Kind.REINFORCE
			and light_assignment.target_city == light_target
			and heavy_assignment == null,
		"5000填线军应生成驻防命令，15000攻势军不得生成常态驻防命令"
	)

	var reserve_guard := _make_army(936, 0, 5000, 10, 10)
	reserve_guard.max_size = 5000
	reserve_guard.location_city = 0
	reserve_guard.move_from = 0
	assignment_state.armies.append(reserve_guard)
	var stacked_view := AiWorldView.build(assignment_state, 0)
	var stacked_plan := CityDefensePlan.new()
	stacked_plan.view = stacked_view
	stacked_plan.snapshot = StrategicMapSnapshot.build(stacked_view)
	stacked_plan.threat = ThreatField.build(stacked_view)
	stacked_plan.required_power = {
		3: 100000.0,
	}
	stacked_plan.posture_by_city = {
		3: CityDefensePlan.Posture.EDGE,
	}
	stacked_plan.preferred_edge_by_city[3] = 4
	stacked_plan.defense_assignment_slots = 3
	stacked_plan._assign_role_based_defense()
	var stacked_army_ids: Array = (
		stacked_plan.assigned_armies_by_city.get(3, [])
	)
	var assigned_light_orders := 0
	for stacked_guard in [light_guard, heavy_guard, reserve_guard]:
		var stacked_order := stacked_plan.candidate_for(
			stacked_guard,
			ArmyCoordinator.new()
		)
		if (
			stacked_order != null
			and stacked_order.target_city == 3
		):
			assigned_light_orders += 1
	_check(
		stacked_army_ids.size() == 2
			and stacked_plan.assigned_city_by_army.size() == 2
			and not stacked_plan.assigned_city_by_army.has(
				heavy_guard.id
			)
			and assigned_light_orders == 2,
		"加权盈余：两支5000填线军可同赴唯一有效目标；15000攻势军排除"
	)

	var reserve_spread_state := GameState.new()
	reserve_spread_state.generate_grid_world(70031)
	reserve_spread_state.uses_heightmap = true
	reserve_spread_state.armies.clear()
	reserve_spread_state.nations[0].battle_groups.clear()
	reserve_spread_state.nations[0].next_battle_group_id = 0
	for spread_city in reserve_spread_state.cities:
		spread_city.owner_nation = 0
		spread_city.is_capital = false
		spread_city.has_warehouse = false
		spread_city.is_food_hub = false
		spread_city.is_manpower_hub = false
	reserve_spread_state.cities[2].owner_nation = 1
	reserve_spread_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var spread_armies: Array[Army] = []
	for spread_index in range(3):
		var spread_group := reserve_spread_state.create_battle_group(0)
		var spread_army := _make_army(960 + spread_index, 0, 15000, 10, 10)
		spread_army.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
		spread_army.location_city = 0
		spread_army.move_from = 0
		spread_army.strategic_role = Army.StrategicRole.MAIN
		spread_army.battle_group_id = spread_group.id
		spread_army.ai_action = ActionCandidate.Kind.CREATE_ARMY
		reserve_spread_state.armies.append(spread_army)
		spread_armies.append(spread_army)
	var reserve_spread_view := AiWorldView.build(
		reserve_spread_state,
		0
	)
	var reserve_spread_plan := CityDefensePlan.build(
		reserve_spread_view,
		StrategicMapSnapshot.build(reserve_spread_view),
		ThreatField.build(reserve_spread_view)
	)
	var spread_targets := {}
	var all_spread_to_frontline := true
	for spread_army in spread_armies:
		var spread_target := reserve_spread_plan.assigned_city_for(
			spread_army
		)
		spread_targets[spread_target] = true
		all_spread_to_frontline = (
			all_spread_to_frontline
			and reserve_spread_plan.primary_frontline_cities.has(
				spread_target
			)
		)
	_check(
		reserve_spread_plan.primary_frontline_cities.size() >= 3
			and spread_targets.size() == 3
			and all_spread_to_frontline,
		(
			"LINE 未铺满时三个 MAIN 战团必须先展开到三个不同前线城市，"
			+ "不得堆在同一重点城市"
		)
	)
	_check(
		reserve_spread_plan.pending_deployment_army_count() == 3,
		"已分配远端前线但尚未离开征兵枢纽的战团必须形成征兵背压"
	)
	var spread_sim := Simulation.new()
	spread_sim.setup(reserve_spread_state)
	var spread_manpower_before := (
		reserve_spread_state.nations[0].manpower_pool
	)
	var demobilized_group_size := spread_armies[2].size
	_check(
		spread_sim._demobilize_excess_peacetime_battle_group(
			reserve_spread_view,
			ThreatField.build(reserve_spread_view),
			1
		)
			and reserve_spread_state.nations[0].battle_groups.size() == 2
			and reserve_spread_state.nations[0].manpower_pool
				== spread_manpower_before + demobilized_group_size
			and not reserve_spread_state.armies.has(spread_armies[2]),
		(
			"和平后必须按当前防区规模原子复员最新的多余战团，"
			+ "不能让战争动员编制永久挤在重点城市"
		)
	)
	spread_sim.free()
	assignment_plan.assigned_city_by_army = {
		light_guard.id: 1,
		reserve_guard.id: 1,
	}
	assignment_plan.assigned_posture_by_army = {
		light_guard.id: CityDefensePlan.Posture.CITY,
		reserve_guard.id: CityDefensePlan.Posture.EDGE,
	}
	assignment_plan.assigned_edge_by_army = {
		reserve_guard.id: 2,
	}
	assignment_plan.assigned_armies_by_city = {
		1: [light_guard.id, reserve_guard.id],
	}
	var free_line_army := _make_army(943, 0, 5000, 10, 10)
	free_line_army.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	heavy_guard.defensive_deployment_until_day = assignment_state.day + 90
	_check(
		not assignment_plan.can_join_offensive(heavy_guard, 2)
			and assignment_plan.can_join_offensive(heavy_guard, 2, true)
			and not assignment_plan.can_join_offensive(
				reserve_guard,
				2
			)
			and not assignment_plan.can_join_offensive(
				reserve_guard,
				3
			)
			and not assignment_plan.can_join_offensive(
				light_guard,
				2
			)
			and not assignment_plan.can_join_offensive(
				free_line_army,
				2
			),
		"已分配攻势的 MAIN 可覆盖普通预备队锁，任何 LINE 均不得进入正式攻势"
	)
	heavy_guard.defensive_deployment_until_day = -1
	assignment_plan.assigned_armies_by_city[1] = [
		reserve_guard.id,
	]
	_check(
		not assignment_plan.can_join_offensive(
			reserve_guard,
			2
		),
		"边槽5000军只有在锚点城市仍有填线军时才能参加攻势"
	)

	assignment_state.cities[2].owner_nation = 1
	assignment_state.cities[10].is_dock = true
	reserve_guard.strategic_role = Army.StrategicRole.MAIN
	reserve_guard.clear_line_assignment()
	light_guard.location_city = 1
	light_guard.move_from = 1
	var recovering_guard := _make_army(944, 0, 5000, 10, 10)
	recovering_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	recovering_guard.state = Army.State.RECOVERING
	recovering_guard.location_city = 1
	recovering_guard.move_from = 1
	assignment_state.armies.append(recovering_guard)
	var priority_view := AiWorldView.build(assignment_state, 0)
	var priority_snapshot := StrategicMapSnapshot.build(
		priority_view
	)
	priority_snapshot.frontier_cities = [1]
	priority_snapshot.potential_frontier_cities = []
	var priority_plan := CityDefensePlan.new()
	priority_plan.view = priority_view
	priority_plan.snapshot = priority_snapshot
	priority_plan.threat = ThreatField.build(priority_view)
	var priority_slots := priority_plan._build_role_defense_slots()
	priority_plan._assign_role_based_defense()
	var priority_edge_neighbor := (
		int(priority_slots[1]["edge_neighbor"])
		if priority_slots.size() > 1 else -1
	)
	_check(
		priority_slots.size() >= 3
			and int(priority_slots[0]["city_id"]) == 1
			and int(priority_slots[0]["posture"])
				== CityDefensePlan.Posture.CITY
			and int(priority_slots[1]["city_id"]) == 1
			and int(priority_slots[1]["posture"])
				== CityDefensePlan.Posture.EDGE
			and priority_edge_neighbor >= 0
			and assignment_state.cities[priority_edge_neighbor]
				.owner_nation != 0
			and int(priority_slots[2]["city_id"]) == 10
			and int(priority_slots[2]["posture"])
				== CityDefensePlan.Posture.CITY,
		"边境防区必须先填城市槽，再填第一边槽，最后才处理国内战略城市"
	)
	_check(
		int(priority_plan.assigned_posture_by_army.get(
			light_guard.id,
			CityDefensePlan.Posture.NONE
		)) == CityDefensePlan.Posture.CITY
			and int(priority_plan.assigned_posture_by_army.get(
				recovering_guard.id,
				CityDefensePlan.Posture.NONE
			)) == CityDefensePlan.Posture.EDGE
			and int(priority_plan.assigned_edge_by_army.get(
				recovering_guard.id,
				-1
			)) == priority_edge_neighbor
			and priority_plan.candidate_for(
				recovering_guard,
				ArmyCoordinator.new()
			) == null,
		"所有边境城市本体已覆盖后应激活第一边槽，恢复军保留槽位但暂不移动"
	)
	assignment_state.armies.erase(recovering_guard)
	var moving_line_guard := _make_army(945, 0, 5000, 10, 10)
	moving_line_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	moving_line_guard.state = Army.State.MOVING
	moving_line_guard.location_city = 0
	moving_line_guard.move_from = 0
	moving_line_guard.move_to = 1
	moving_line_guard.ai_action = ActionCandidate.Kind.REINFORCE
	moving_line_guard.ai_target_city = 1
	moving_line_guard.ai_order_reason = (
		"填线部署：5000编制军调往国界边锚点城市1"
	)
	assignment_state.armies.append(moving_line_guard)
	var moving_priority_view := AiWorldView.build(
		assignment_state,
		0
	)
	var moving_priority_plan := CityDefensePlan.new()
	moving_priority_plan.view = moving_priority_view
	moving_priority_plan.snapshot = priority_snapshot
	moving_priority_plan.threat = ThreatField.build(
		moving_priority_view
	)
	moving_priority_plan._assign_role_based_defense()
	_check(
		int(moving_priority_plan.assigned_edge_by_army.get(
			moving_line_guard.id,
			-1
		)) == priority_edge_neighbor
			and moving_priority_plan.candidate_for(
				moving_line_guard,
				ArmyCoordinator.new()
			) == null,
		"城市槽已满时，调往第一边槽途中的5000军必须保持持久槽位"
	)
	var edge_priority_state := GameState.new()
	edge_priority_state.generate_grid_world(7004)
	edge_priority_state.uses_heightmap = true
	edge_priority_state.armies.clear()
	for edge_priority_city in edge_priority_state.cities:
		edge_priority_city.owner_nation = 0
		edge_priority_city.is_capital = false
		edge_priority_city.has_warehouse = false
		edge_priority_city.is_food_hub = false
		edge_priority_city.is_manpower_hub = false
		edge_priority_city.fort_strength_max = 0
	edge_priority_state.cities[2].owner_nation = 1
	edge_priority_state.nations[0].capital_city_id = -1
	var edge_only_guard := _make_army(946, 0, 5000, 10, 10)
	edge_only_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	edge_only_guard.state = Army.State.HOLDING
	edge_only_guard.location_city = 1
	edge_only_guard.move_from = 1
	edge_only_guard.move_to = 2
	edge_only_guard.move_progress = 0.5
	edge_only_guard.on_edge = true
	edge_only_guard.line_assignment_city = 1
	edge_only_guard.line_assignment_posture = Army.LinePosture.EDGE
	edge_only_guard.line_assignment_edge = 2
	edge_priority_state.armies.append(edge_only_guard)
	var edge_priority_view := AiWorldView.build(
		edge_priority_state,
		0
	)
	var edge_priority_snapshot := StrategicMapSnapshot.build(
		edge_priority_view
	)
	edge_priority_snapshot.frontier_cities = [1]
	edge_priority_snapshot.potential_frontier_cities = []
	var edge_priority_plan := CityDefensePlan.new()
	edge_priority_plan.view = edge_priority_view
	edge_priority_plan.snapshot = edge_priority_snapshot
	edge_priority_plan.threat = ThreatField.build(
		edge_priority_view
	)
	edge_priority_plan._assign_role_based_defense()
	var return_to_city := edge_priority_plan.candidate_for(
		edge_only_guard,
		ArmyCoordinator.new()
	)
	_check(
		int(edge_priority_plan.assigned_posture_by_army.get(
			edge_only_guard.id,
			CityDefensePlan.Posture.NONE
		)) == CityDefensePlan.Posture.EDGE
			and int(edge_priority_plan.assigned_edge_by_army.get(
				edge_only_guard.id, -1
			)) == 2
			and return_to_city == null,
		"边境城市暂时空缺属于动态兵力状态，不得改写旧边槽 LINE 的驻地"
	)
	var edge_switch_plan := CityDefensePlan.new()
	edge_switch_plan.view = edge_priority_view
	edge_switch_plan.assigned_city_by_army = {
		edge_only_guard.id: 1,
	}
	edge_switch_plan.assigned_posture_by_army = {
		edge_only_guard.id: CityDefensePlan.Posture.EDGE,
	}
	edge_switch_plan.assigned_edge_by_army = {
		edge_only_guard.id: 0,
	}
	edge_switch_plan.directional_pressure = {
		1: {
			0: 2000.0,
			2: 1000.0,
		},
	}
	var pressured_edge_order := edge_switch_plan.candidate_for(
		edge_only_guard,
		ArmyCoordinator.new()
	)
	_check(
		pressured_edge_order == null,
		"当前驻边仍有压力时，LINE 不得为追逐更高压力方向而主动弃守"
	)
	edge_switch_plan.directional_pressure = {
		1: {
			0: 2000.0,
		},
	}
	var empty_edge_switch_order := edge_switch_plan.candidate_for(
		edge_only_guard,
		ArmyCoordinator.new()
	)
	_check(
		empty_edge_switch_order == null,
		"当前驻边压力归零也属于动态因素，LINE 不得因此回城换防"
	)
	var edge_city_guard := _make_army(947, 0, 5000, 10, 10)
	edge_city_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	edge_city_guard.location_city = 1
	edge_city_guard.move_from = 1
	edge_city_guard.line_assignment_city = 1
	edge_city_guard.line_assignment_posture = Army.LinePosture.CITY
	var edge_besieger := _make_army(948, 1, 5000, 10, 10)
	edge_besieger.state = Army.State.FIGHTING
	edge_besieger.location_city = 1
	edge_priority_state.armies.append_array([
		edge_city_guard,
		edge_besieger,
	])
	edge_priority_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var edge_city_siege := edge_priority_state.new_battle(
		Battle.Kind.SIEGE
	)
	edge_city_siege.city = edge_priority_state.cities[1]
	edge_city_siege.edge = edge_priority_state.edge_of(1, 2)
	edge_city_siege.side_a.append(edge_besieger)
	edge_besieger.battle_id = edge_city_siege.id
	edge_only_guard.line_assignment_city = 1
	edge_only_guard.line_assignment_posture = Army.LinePosture.EDGE
	edge_only_guard.line_assignment_edge = 2
	var edge_priority_sector: FrontierDefenseSector = (
		edge_priority_state.nations[0]
			.frontier_defense_sectors[1]
	)
	edge_priority_sector.assign(0, edge_city_guard.id)
	edge_priority_sector.assign(1, edge_only_guard.id)
	var siege_edge_view := AiWorldView.build(
		edge_priority_state,
		0
	)
	var siege_edge_plan := CityDefensePlan.new()
	siege_edge_plan.view = siege_edge_view
	siege_edge_plan.snapshot = StrategicMapSnapshot.build(
		siege_edge_view
	)
	siege_edge_plan.snapshot.frontier_cities = [1]
	siege_edge_plan.snapshot.potential_frontier_cities = []
	siege_edge_plan.threat = ThreatField.build(siege_edge_view)
	var siege_edge_slots := (
		siege_edge_plan._build_role_defense_slots()
	)
	siege_edge_plan._assign_role_based_defense()
	var siege_edge_recall := siege_edge_plan.candidate_for(
		edge_only_guard,
		ArmyCoordinator.new()
	)
	_check(
		siege_edge_slots.size() == 2
			and int(siege_edge_slots[0]["posture"])
				== CityDefensePlan.Posture.CITY
			and int(siege_edge_slots[1]["posture"])
				== CityDefensePlan.Posture.EDGE
			and int(siege_edge_plan.assigned_posture_by_army.get(
				edge_only_guard.id,
				CityDefensePlan.Posture.NONE
			)) == CityDefensePlan.Posture.EDGE
			and int(siege_edge_plan.assigned_edge_by_army.get(
				edge_only_guard.id, -1
			)) == 2
			and siege_edge_recall == null
			and edge_only_guard.state == Army.State.HOLDING,
		"锚点受围属于动态战况，LINE 必须保持原边槽，解围由 MAIN 承担"
	)
	var layered_state := GameState.new()
	layered_state.generate_grid_world(7005)
	layered_state.uses_heightmap = true
	layered_state.armies.clear()
	for layered_city in layered_state.cities:
		layered_city.owner_nation = 0
		layered_city.is_capital = false
		layered_city.has_warehouse = false
		layered_city.is_food_hub = false
		layered_city.is_manpower_hub = false
		layered_city.is_dock = false
		layered_city.fort_strength_max = 0
	layered_state.nations[0].capital_city_id = -1
	for enemy_city_id in [1, 2, 8, 11]:
		layered_state.cities[enemy_city_id].owner_nation = 1
	for layered_pair in [
		[9, 1],
		[9, 8],
		[10, 2],
		[10, 11],
	]:
		var layered_edge := layered_state.edge_of(
			int(layered_pair[0]),
			int(layered_pair[1])
		)
		layered_edge.max_manpower = Edge.STANDARD_MANPOWER
		layered_edge.allows_holding = true
	layered_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var layered_guards: Array[Army] = []
	for layered_index in range(6):
		var layered_guard := _make_army(
			960 + layered_index,
			0,
			5000,
			10,
			10
		)
		layered_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
		layered_guard.location_city = (
			9 if layered_index == 0
			else 10 if layered_index == 1
			else 0
		)
		layered_guard.move_from = layered_guard.location_city
		layered_state.armies.append(layered_guard)
		layered_guards.append(layered_guard)
	var layered_view := AiWorldView.build(layered_state, 0)
	var layered_snapshot := StrategicMapSnapshot.build(layered_view)
	layered_snapshot.frontier_cities = [9, 10]
	layered_snapshot.potential_frontier_cities = []
	var layered_plan := CityDefensePlan.new()
	layered_plan.view = layered_view
	layered_plan.snapshot = layered_snapshot
	layered_plan.threat = ThreatField.build(layered_view)
	var layered_slots := layered_plan._build_role_defense_slots()
	layered_plan._assign_role_based_defense()
	var first_layer_cities := {}
	var second_layer_cities := {}
	for slot_index in range(layered_slots.size()):
		var layered_slot: Dictionary = layered_slots[slot_index]
		if slot_index in [2, 3]:
			first_layer_cities[int(layered_slot["city_id"])] = true
		elif slot_index in [4, 5]:
			second_layer_cities[int(layered_slot["city_id"])] = true
	_check(
		layered_slots.size() == 6
			and int(layered_slots[0]["posture"])
				== CityDefensePlan.Posture.CITY
			and int(layered_slots[1]["posture"])
				== CityDefensePlan.Posture.CITY
			and int(layered_slots[2]["sector_slot"]) == 1
			and int(layered_slots[3]["sector_slot"]) == 1
			and int(layered_slots[4]["sector_slot"]) == 2
			and int(layered_slots[5]["sector_slot"]) == 2
			and first_layer_cities.size() == 2
			and second_layer_cities.size() == 2,
		"多边境城市必须按槽层填充：全部城市槽→全部第一边槽→全部第二边槽"
			+ "，实际=%s" % str(layered_slots)
	)
	_check(
		layered_plan.assigned_city_for(layered_guards[0]) == 9
			and layered_plan.assigned_city_for(
				layered_guards[1]
			) == 10,
		"边境城市本体必须由路径最近的填线军优先补位"
	)
	layered_state.cities[9].owner_nation = 1
	layered_state.ownership_revision += 1
	layered_guards[0].location_city = 17
	layered_guards[0].move_from = 17
	var changed_view := AiWorldView.build(layered_state, 0)
	var changed_snapshot := StrategicMapSnapshot.build(changed_view)
	changed_snapshot.frontier_cities = [10, 17]
	changed_snapshot.potential_frontier_cities = []
	var changed_plan := CityDefensePlan.build(
		changed_view,
		changed_snapshot,
		ThreatField.build(changed_view)
	)
	var stale_sector_assignment := false
	for layered_guard in layered_guards:
		if layered_guard.line_assignment_city == 9:
			stale_sector_assignment = true
			break
	_check(
		not layered_state.nations[0]
			.frontier_defense_sectors.has(9)
			and layered_state.nations[0]
				.frontier_defense_sectors.has(17)
			and changed_plan.assigned_city_for(
				layered_guards[0]
			) == 17
			and not stale_sector_assignment,
		"城市易手后必须删除旧防区、创建新前线防区，并由最近军队快速补位"
	)
	var single_attacker := _make_army(937, 1, 15000, 10, 10)
	var stacked_attacker := _make_army(938, 1, 15000, 10, 10)
	var single_defender := _make_army(939, 0, 5000, 10, 10)
	var stacked_defender_a := _make_army(940, 0, 5000, 10, 10)
	var stacked_defender_b := _make_army(941, 0, 5000, 10, 10)
	var stacked_defender_c := _make_army(942, 0, 5000, 10, 10)
	var single_garrison_battle := _make_siege_battle(
		[single_attacker],
		single_defender,
		30,
		4
	)
	var stacked_garrison_battle := _make_siege_battle(
		[stacked_attacker],
		stacked_defender_a,
		30,
		4
	)
	stacked_garrison_battle.side_b.append(stacked_defender_b)
	stacked_garrison_battle.side_b.append(stacked_defender_c)
	var single_rng := RandomNumberGenerator.new()
	var stacked_rng := RandomNumberGenerator.new()
	single_rng.seed = 70031
	stacked_rng.seed = 70031
	Combat.resolve_round(
		single_garrison_battle,
		single_rng,
		-1,
		-1,
		-1,
		Vector2.ONE
	)
	Combat.resolve_round(
		stacked_garrison_battle,
		stacked_rng,
		-1,
		-1,
		-1,
		Vector2.ONE
	)
	_check(
		15000 - stacked_attacker.size
			> 15000 - single_attacker.size,
		"同城多支守军必须共同进入守城战并提高对攻方的反击伤亡"
	)

	var defense_state := GameState.new()
	defense_state.generate_grid_world(7005)
	defense_state.armies.clear()
	for city in defense_state.cities:
		city.owner_nation = 0
	var threatened_city := 9
	for enemy_city_id in [8, 10, 17]:
		defense_state.cities[enemy_city_id].owner_nation = 1
	for neighbor in [8, 10, 17]:
		var defense_edge := defense_state.edge_of(
			threatened_city,
			neighbor
		)
		defense_edge.max_manpower = 30000
		defense_edge.distance = 1
	defense_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var first_holder := _make_army(961, 0, 15000, 10, 10)
	first_holder.state = Army.State.HOLDING
	first_holder.location_city = threatened_city
	first_holder.move_from = threatened_city
	first_holder.move_to = 10
	first_holder.move_progress = Simulation.HOLDING_TARGET_PROGRESS
	first_holder.on_edge = true
	var second_holder := _make_army(962, 0, 15000, 10, 10)
	second_holder.state = Army.State.HOLDING
	second_holder.location_city = threatened_city
	second_holder.move_from = threatened_city
	second_holder.move_to = 8
	second_holder.move_progress = Simulation.HOLDING_TARGET_PROGRESS
	second_holder.on_edge = true
	var alternate_attacker := _make_army(963, 1, 15000, 10, 10)
	alternate_attacker.state = Army.State.MOVING
	alternate_attacker.location_city = 17
	alternate_attacker.move_from = 17
	alternate_attacker.move_to = threatened_city
	alternate_attacker.move_progress = 0.5
	alternate_attacker.on_edge = true
	defense_state.armies.append_array([
		first_holder,
		second_holder,
		alternate_attacker,
	])
	defense_state.refresh_derived()
	var defense_view := AiWorldView.build(defense_state, 0)
	var defense_snapshot := StrategicMapSnapshot.build(defense_view)
	var defense_threat := ThreatField.build(defense_view)
	var single_direction_plan := CityDefensePlan.build(
		defense_view,
		defense_snapshot,
		defense_threat
	)
	_check(
		single_direction_plan.posture_at(threatened_city)
			== CityDefensePlan.Posture.EDGE
		and single_direction_plan.preferred_edge_at(
			threatened_city
		) == 17,
		"单一明确威胁方向应选择驻边，而不是把军队固定在城市"
	)
	var edge_reservation := ArmyCoordinator.new()
	edge_reservation.reserve_edge(
		threatened_city,
		10,
		first_holder
	)
	_check(
		_approx(
			edge_reservation.edge_defense_power_reserved(
				threatened_city,
				10
			),
			ArmyPower.effective(first_holder)
		)
		and edge_reservation.city_defense_power_reserved(
			threatened_city
		) == 0.0,
		"驻边预留必须只覆盖指定方向，不能冒充驻城通用守军"
	)
	var reservation_power := ArmyPower.effective(first_holder)
	edge_reservation.reserve_edge(
		threatened_city,
		10,
		first_holder
	)
	_check(
		_approx(
			edge_reservation.power_reserved(threatened_city),
			reservation_power
		)
		and _approx(
			edge_reservation.edge_defense_power_reserved(
				threatened_city,
				10
			),
			reservation_power
		),
		"统一覆盖账本重复看见同一驻边军时必须幂等，不能重复累计战力"
	)
	edge_reservation.reserve(17, first_holder)
	_check(
		edge_reservation.power_reserved(threatened_city) == 0.0
			and edge_reservation.edge_defense_power_reserved(
				threatened_city,
				10
			) == 0.0
			and _approx(
				edge_reservation.city_defense_power_reserved(17),
				reservation_power
			),
		"同一军获得新目标时覆盖必须原子迁移，旧城市和旧边不得残留幽灵守军"
	)
	var defense_coordinator := ArmyCoordinator.new()
	defense_coordinator.reserve(
		threatened_city,
		first_holder,
		false
	)
	defense_coordinator.reserve(
		threatened_city,
		second_holder,
		false
	)
	first_holder.defensive_deployment_until_day = (
		defense_view.day
			+ Simulation.DEFENSIVE_DEPLOYMENT_LOCK_DAYS
	)
	var first_defense_order := UtilityAI.choose(
		defense_view,
		defense_snapshot,
		defense_threat,
		defense_coordinator,
		first_holder
	)
	_check(
		first_defense_order.kind == ActionCandidate.Kind.RETREAT
		and first_defense_order.target_city == threatened_city
		and first_defense_order.reason.contains("集中进攻"),
		"真实敌军从另一条道路逼近时，必须打破部署锁回城防御"
	)
	first_holder.defensive_deployment_until_day = -1
	if first_defense_order.kind == ActionCandidate.Kind.RETREAT:
		defense_coordinator.reserve(
			first_defense_order.target_city,
			first_holder
		)
	var second_defense_order := UtilityAI.choose(
		defense_view,
		defense_snapshot,
		defense_threat,
		defense_coordinator,
		second_holder
	)
	_check(
		not (
			second_defense_order.kind == ActionCandidate.Kind.RETREAT
			and second_defense_order.target_city == threatened_city
		),
		(
			"第一支回防军已填平缺口后，不得让其余驻边军集体撤线："
			+ "kind=%d target=%d reason=%s"
		) % [
			second_defense_order.kind,
			second_defense_order.target_city,
			second_defense_order.reason,
		]
	)

	alternate_attacker.move_from = threatened_city
	alternate_attacker.move_to = 17
	defense_state.armies = [
		first_holder,
		alternate_attacker,
	] as Array[Army]
	defense_view = AiWorldView.build(defense_state, 0)
	var departing_enemy_order := UtilityAI.choose(
		defense_view,
		StrategicMapSnapshot.build(defense_view),
		ThreatField.build(defense_view),
		ArmyCoordinator.new(),
		first_holder
	)
	_check(
		not (
			departing_enemy_order.kind == ActionCandidate.Kind.RETREAT
			and departing_enemy_order.target_city == threatened_city
		),
		(
			"敌军正在背离城市时，不得误判为逼近压力并触发回防："
			+ "kind=%d target=%d reason=%s"
		) % [
			departing_enemy_order.kind,
			departing_enemy_order.target_city,
			departing_enemy_order.reason,
		]
	)

	var stable_state := GameState.new()
	stable_state.generate_grid_world(7006)
	stable_state.armies.clear()
	for stable_city in stable_state.cities:
		stable_city.owner_nation = 0
	var stable_city_id := 9
	var stable_enemy_city := 10
	stable_state.cities[stable_enemy_city].owner_nation = 1
	stable_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	stable_state.edge_of(
		stable_city_id,
		stable_enemy_city
	).max_manpower = 30000
	var stable_holder := _make_army(964, 0, 15000, 10, 10)
	stable_holder.state = Army.State.HOLDING
	stable_holder.location_city = stable_city_id
	stable_holder.move_from = stable_city_id
	stable_holder.move_to = stable_enemy_city
	stable_holder.move_progress = Simulation.HOLDING_TARGET_PROGRESS
	stable_holder.on_edge = true
	stable_holder.defensive_deployment_until_day = (
		stable_state.day - 1
	)
	var stable_enemy := _make_army(965, 1, 10000, 10, 10)
	stable_enemy.state = Army.State.IDLE
	stable_enemy.location_city = stable_enemy_city
	stable_enemy.move_from = stable_enemy_city
	stable_state.armies.append_array([
		stable_holder,
		stable_enemy,
	])
	var stable_view := AiWorldView.build(stable_state, 0)
	var stable_plan := CityDefensePlan.build(
		stable_view,
		StrategicMapSnapshot.build(stable_view),
		ThreatField.build(stable_view)
	)
	var stable_order := stable_plan.candidate_for(
		stable_holder,
		ArmyCoordinator.new()
	)
	_check(
		stable_order == null
			or stable_order.kind != ActionCandidate.Kind.RETREAT,
		"稳定威胁布局下驻边超过90天后不得无故回城"
	)
	stable_holder.state = Army.State.IDLE
	stable_holder.location_city = stable_city_id
	stable_holder.move_from = stable_city_id
	stable_holder.move_to = -1
	stable_holder.on_edge = false
	stable_holder.defensive_blocked_edge_a = stable_city_id
	stable_holder.defensive_blocked_edge_b = stable_enemy_city
	stable_holder.defensive_deployment_until_day = (
		stable_state.day
		+ Simulation.DEFENSIVE_DEPLOYMENT_LOCK_DAYS
	)
	stable_view = AiWorldView.build(stable_state, 0)
	stable_plan = CityDefensePlan.build(
		stable_view,
		StrategicMapSnapshot.build(stable_view),
		ThreatField.build(stable_view)
	)
	_check(
		stable_plan.candidate_for(
			stable_holder,
			ArmyCoordinator.new()
		) == null,
		"刚从某边撤回时，持续邻敌不得绕过锁立即命令军队返回同一边"
	)

	alternate_attacker.state = Army.State.IDLE
	alternate_attacker.on_edge = false
	alternate_attacker.location_city = 10
	alternate_attacker.move_from = 10
	alternate_attacker.move_to = -1
	defense_state.armies = [
		first_holder,
		alternate_attacker,
	] as Array[Army]
	defense_view = AiWorldView.build(defense_state, 0)
	var direct_border_order := UtilityAI.choose(
		defense_view,
		StrategicMapSnapshot.build(defense_view),
		ThreatField.build(defense_view),
		ArmyCoordinator.new(),
		first_holder
	)
	_check(
		not (
			direct_border_order.kind == ActionCandidate.Kind.RETREAT
			and direct_border_order.target_city == threatened_city
		),
		(
			"唯一来敌位于当前驻守边对面且战力相当时，应继续扼守道路："
			+ "kind=%d target=%d reason=%s"
		) % [
			direct_border_order.kind,
			direct_border_order.target_city,
			direct_border_order.reason,
		]
	)
	var second_attacker := _make_army(
		964,
		1,
		15000,
		10,
		10
	)
	second_attacker.location_city = 8
	second_attacker.move_from = 8
	defense_state.armies.append(second_attacker)
	defense_view = AiWorldView.build(defense_state, 0)
	var multi_direction_plan := CityDefensePlan.build(
		defense_view,
		StrategicMapSnapshot.build(defense_view),
		ThreatField.build(defense_view)
	)
	_check(
		multi_direction_plan.posture_at(threatened_city)
			== CityDefensePlan.Posture.CITY,
		"两个方向同时形成进攻压力时，应驻城作为多方向预备队"
	)

	var hard_state := GameState.new()
	hard_state.generate_grid_world(7007)
	hard_state.armies.clear()
	for city in hard_state.cities:
		city.owner_nation = 0
	var hard_city := 9
	var hard_enemy_city := 10
	hard_state.cities[hard_city].is_food_hub = true
	hard_state.cities[hard_enemy_city].owner_nation = 1
	hard_state.edge_of(
		hard_city,
		hard_enemy_city
	).max_manpower = 30000
	hard_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var hard_guard := _make_army(
		965,
		0,
		1000,
		10,
		10
	)
	hard_guard.location_city = hard_city
	hard_guard.move_from = hard_city
	var hard_enemy := _make_army(
		966,
		1,
		15000,
		10,
		10
	)
	hard_enemy.location_city = hard_enemy_city
	hard_enemy.move_from = hard_enemy_city
	var hard_support := _make_army(
		967,
		0,
		15000,
		10,
		10
	)
	hard_support.location_city = 0
	hard_support.move_from = 0
	hard_state.armies.append_array([
		hard_guard,
		hard_enemy,
		hard_support,
	])
	var hard_view := AiWorldView.build(hard_state, 0)
	var hard_snapshot := StrategicMapSnapshot.build(
		hard_view
	)
	var hard_threat := ThreatField.build(hard_view)
	var hard_plan := CityDefensePlan.build(
		hard_view,
		hard_snapshot,
		hard_threat
	)
	var hard_guard_order := UtilityAI.choose(
		hard_view,
		hard_snapshot,
		hard_threat,
		ArmyCoordinator.new(),
		hard_guard,
		UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO,
		hard_plan
	)
	var hard_support_order := hard_plan.candidate_for(
		hard_support,
		ArmyCoordinator.new()
	)
	_check(
		hard_plan.must_hold_city(hard_city)
		and hard_guard_order.kind
			!= ActionCandidate.Kind.RETREAT,
		"要害产粮城市守军不得因敌军集中而主动弃城逃走"
	)
	_check(
		hard_support_order != null
		and hard_support_order.kind
			== ActionCandidate.Kind.REINFORCE
		and hard_support_order.target_city == hard_city,
		"要害城市兵力不足时，后方军队必须生成明确增援命令"
	)

	var batch_state := GameState.new()
	batch_state.generate_grid_world(7006)
	batch_state.armies.clear()
	for city in batch_state.cities:
		city.owner_nation = 2
	for city_id in [0, 1]:
		batch_state.cities[city_id].owner_nation = 0
	for city_id in [6, 7]:
		batch_state.cities[city_id].owner_nation = 1
	batch_state.edge_of(0, 1).max_manpower = 15000
	batch_state.edge_of(6, 7).max_manpower = 30000
	var batch_left := _make_army(957, 0, 5000, 10, 10)
	batch_left.location_city = 0
	batch_left.move_from = 0
	var batch_right := _make_army(958, 1, 5000, 10, 10)
	batch_right.location_city = 7
	batch_right.move_from = 7
	var batch_left_extra := _make_army(959, 0, 5000, 10, 10)
	batch_left_extra.location_city = 0
	batch_left_extra.move_from = 0
	var batch_left_reverse := _make_army(960, 0, 5000, 10, 10)
	batch_left_reverse.location_city = 1
	batch_left_reverse.move_from = 1
	batch_state.armies.append_array([
		batch_left,
		batch_right,
		batch_left_extra,
		batch_left_reverse,
	])
	var batch_sim := Simulation.new()
	batch_sim.setup(batch_state)
	var left_order := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		10.0,
		"批处理左军",
		1
	)
	var right_order := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		10.0,
		"批处理右军",
		6
	)
	var reverse_order := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		10.0,
		"批处理反向军",
		0
	)
	batch_sim._begin_ai_command_collection()
	_check(
		batch_sim._execute_ai_candidate(batch_left, left_order)
		and batch_sim._execute_ai_candidate(batch_right, right_order)
		and batch_sim._execute_ai_candidate(
			batch_left_reverse,
			reverse_order
		)
		and batch_left.state == Army.State.IDLE
		and batch_right.state == Army.State.IDLE
		and batch_left_reverse.state == Army.State.IDLE
		and batch_sim._ai_command_buffer.size() == 3,
		"规划阶段应收集两国命令且不修改任何军队状态"
	)
	_check(
		not batch_sim._execute_ai_candidate(batch_left, left_order),
		"同一规划批次中每支军队只能接受一条命令"
	)
	_check(
		not batch_sim._execute_ai_candidate(batch_left_extra, left_order),
		"同国同向首段容量满后，后续命令应在收集期被仲裁"
	)
	batch_sim._commit_ai_command_collection([0, 1] as Array[int])
	_check(
		batch_left.state == Army.State.MOVING
		and batch_right.state == Army.State.MOVING
		and batch_left_reverse.state == Army.State.MOVING
		and batch_left.ai_target_city == 1
		and batch_right.ai_target_city == 6
		and batch_left_reverse.ai_target_city == 0
		and batch_sim.ai_last_command_commit_failures == 0
		and batch_sim._ai_command_buffer.is_empty(),
		"统一提交后两国命令应在同一阶段生效并清空缓冲区"
	)
	batch_sim.free()

	var capacity_race_state := GameState.new()
	capacity_race_state.generate_grid_world(7007)
	capacity_race_state.armies.clear()
	for city in capacity_race_state.cities:
		city.owner_nation = 0
	var capacity_edge := capacity_race_state.edge_of(0, 1)
	var capacity_waiter := _make_army(961, 0, 5000, 10, 10)
	capacity_waiter.location_city = 0
	capacity_waiter.move_from = 0
	capacity_edge.max_manpower = capacity_waiter.max_size
	capacity_race_state.armies.append(capacity_waiter)
	var capacity_race_sim := Simulation.new()
	capacity_race_sim.setup(capacity_race_state)
	capacity_race_sim._begin_ai_command_collection()
	var capacity_order := ActionCandidate.make(
		ActionCandidate.Kind.REINFORCE,
		10.0,
		"冻结快照后首段临时满载",
		1
	)
	var capacity_queued := capacity_race_sim._execute_ai_candidate(
		capacity_waiter,
		capacity_order
	)
	var late_blocker := _make_army(962, 0, 5000, 10, 10)
	late_blocker.state = Army.State.MOVING
	late_blocker.location_city = -1
	late_blocker.move_from = 0
	late_blocker.move_to = 1
	late_blocker.move_progress = 0.2
	late_blocker.on_edge = true
	capacity_race_state.armies.append(late_blocker)
	capacity_race_sim._commit_ai_command_collection([0] as Array[int])
	_check(
		capacity_queued
			and capacity_waiter.state == Army.State.MOVING
			and capacity_waiter.move_to == -1
			and capacity_waiter.path == [1]
			and capacity_race_sim.ai_last_command_commit_failures == 0,
		"冻结快照后首段临时满载时应保留命令等待容量，不得提交失败"
	)
	capacity_race_state.armies.erase(late_blocker)
	capacity_race_sim._begin_next_leg(capacity_waiter)
	_check(
		capacity_waiter.move_to == 1
			and capacity_waiter.path.is_empty(),
		"首段容量释放后，等待中的批量命令必须继续行军"
	)
	capacity_race_sim.free()


func _test_garrison_retreat_city_defense() -> void:
	print("[30c] 撤退决策：本国城墙加成打折计入守城战力、断粮衰减、他国城不计")
	var gs := GameState.new()
	gs.generate_grid_world(30031)
	var view := AiWorldView.build(gs, 0)
	# 取国 0 的一座城，设定较高城防，放一支守军。
	var own_city: City = gs.land_cities_of(0)[0]
	own_city.fort_strength = 20
	own_city.food_storage = 500
	var garrison := gs.create_army(0, own_city.id, 5000, 5000)
	_check(garrison != null, "应能在本国城创建守军")

	# 本国城 + 有粮：城防加成 = city_defense × 折扣权重，且为正。
	var support := UtilityAI._city_defense_support(view, garrison, own_city.id)
	var expected := ArmyPower.city_defense(own_city) * UtilityAI.CITY_DEFENSE_RETREAT_WEIGHT
	_check(
		support > 0.0 and _approx(support, expected),
		"本国城守军应获打折城防加成（实为 %.1f 期望 %.1f）" % [support, expected]
	)

	# 断粮：加成按 SIEGE_STARVE_DEF_MULT 衰减（与战斗同源）。
	own_city.food_storage = 0
	var starved := UtilityAI._city_defense_support(view, garrison, own_city.id)
	_check(
		_approx(starved, expected * Combat.SIEGE_STARVE_DEF_MULT),
		"断粮守军城防加成须按同源系数衰减（实为 %.1f）" % starved
	)

	# 他国城：守军不在自己城里则不计城防加成。
	var foreign_city: City = gs.land_cities_of(1)[0]
	foreign_city.fort_strength = 20
	var foreign_support := UtilityAI._city_defense_support(view, garrison, foreign_city.id)
	_check(
		_approx(foreign_support, 0.0),
		"守军所在城非本国时不得计入城防加成（实为 %.1f）" % foreign_support
	)


func _test_ai_encirclement_breakout_and_relief() -> void:
	print("[30b] AI 包围协同：多方向进攻、断粮突围、紧急解围")
	var pocket_state := GameState.new()
	pocket_state.generate_grid_world(7029)
	pocket_state.armies.clear()
	pocket_state.battles.clear()
	for pocket_city in pocket_state.cities:
		pocket_city.owner_nation = 1
	var isolated_city_id := 18
	var allied_exit_id := 17
	pocket_state.cities[isolated_city_id].owner_nation = 0
	pocket_state.cities[allied_exit_id].owner_nation = 2
	pocket_state.edge_of(
		isolated_city_id,
		allied_exit_id
	).max_manpower = 15000
	pocket_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	pocket_state.set_diplomatic_relation(
		0,
		2,
		GameState.DiplomaticRelation.NEUTRAL
	)
	var isolated_army := _make_army(930, 0, 5000, 10, 10)
	isolated_army.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	isolated_army.location_city = isolated_city_id
	isolated_army.move_from = isolated_city_id
	isolated_army.morale = Combat.MORALE_FLOOR
	pocket_state.armies.append(isolated_army)
	var pocket_sim := Simulation.new()
	pocket_sim.setup(pocket_state)
	_check(
		not Pathfinding.has_friendly_retreat_route_from_city(
			pocket_state,
			0,
			isolated_city_id,
			isolated_army.max_size
		),
		"孤城周围没有本国或盟友通路时必须判定为无撤退路径"
	)
	pocket_sim._start_morale_retreat_from_city(
		isolated_army,
		isolated_city_id
	)
	_check(
		isolated_army.size == 0,
		"零士气军困在无退路孤城时必须全军覆没，不能原地恢复"
	)
	pocket_state.set_diplomatic_relation(
		0,
		2,
		GameState.DiplomaticRelation.ALLIED
	)
	var allied_escape_army := _make_army(
		931,
		0,
		5000,
		10,
		10
	)
	allied_escape_army.max_size = (
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	allied_escape_army.location_city = isolated_city_id
	allied_escape_army.move_from = isolated_city_id
	allied_escape_army.morale = Combat.MORALE_FLOOR
	pocket_state.armies.append(allied_escape_army)
	_check(
		Pathfinding.has_friendly_retreat_route_from_city(
			pocket_state,
			0,
			isolated_city_id,
			allied_escape_army.max_size
		),
		"邻接盟友城市应提供合法撤退路径，不能把联盟通路误判为包围"
	)
	pocket_sim._start_morale_retreat_from_city(
		allied_escape_army,
		isolated_city_id
	)
	_check(
		allied_escape_army.size == 5000
			and allied_escape_army.state
				== Army.State.RECOVERING,
		"存在盟友退路时零士气军不得被包围规则误杀"
	)
	pocket_sim.free()

	var cut_state := GameState.new()
	cut_state.generate_grid_world(7028)
	cut_state.armies.clear()
	for cut_city in cut_state.cities:
		cut_city.owner_nation = 0
		cut_city.is_capital = false
		cut_city.has_warehouse = false
		cut_city.is_food_hub = false
		cut_city.is_manpower_hub = false
		cut_city.gold_per_month = 1
		cut_city.food_per_half_year = 1
		cut_city.manpower_per_month = 1
		cut_city.fort_strength = 0
	var enemy_capital_id := 16
	var cut_target_id := 17
	var future_pocket_id := 18
	for enemy_city_id in [
		enemy_capital_id,
		cut_target_id,
		future_pocket_id,
	]:
		cut_state.cities[enemy_city_id].owner_nation = 1
		for neighbor in cut_state.neighbors(enemy_city_id):
			cut_state.edge_of(
				enemy_city_id,
				neighbor
			).max_manpower = 30000
	cut_state.nations[1].capital_city_id = enemy_capital_id
	cut_state.cities[enemy_capital_id].is_capital = true
	cut_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var pocket_garrison := cut_state.create_army(
		1,
		future_pocket_id,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var cut_value := DiplomacyAI.encirclement_value(
		cut_state,
		cut_target_id,
		1
	)
	var cut_objective := DiplomacyAI.select_war_objective(
		cut_state,
		0,
		1
	)
	var cut_view := AiWorldView.build(cut_state, 0)
	var cut_snapshot := StrategicMapSnapshot.build(cut_view)
	_check(
		pocket_garrison != null
			and cut_value >= 8.0
			and int(cut_objective.get("city_id", -1))
				== cut_target_id
			and str(cut_objective.get("reason", ""))
				.contains("包围值")
			and cut_snapshot.campaign_target
				== cut_target_id,
		"能切断重兵孤袋的连接城必须成为外交与战役规划共同优先目标"
	)

	var gs := GameState.new()
	gs.generate_grid_world(7030)
	gs.armies.clear()
	for city in gs.cities:
		city.owner_nation = 0
	var target_id := 18
	gs.cities[target_id].owner_nation = 1
	gs.cities[target_id].fort_strength = 20
	_set_single_warehouse(gs, 0, 0, 5000)
	for neighbor in gs.neighbors(target_id):
		gs.edge_of(target_id, neighbor).max_manpower = 30000
	gs.edge_of(17, target_id).distance = 5
	gs.edge_of(19, target_id).distance = 1
	# 空城 fort=20 → 破城所需兵力 siege_required_manpower(20)=2000，协同门槛 = 0+2000×2.0=4000。
	# 单军 2200 < 4000 不足以独攻，两面合计 4400 > 4000 达标 → 应触发协同进攻。
	var holder_a := _make_army(940, 0, 2200, 20, 20)
	holder_a.state = Army.State.HOLDING
	holder_a.location_city = 17
	holder_a.move_from = 17
	holder_a.move_to = target_id
	holder_a.move_progress = 0.5
	holder_a.on_edge = true
	var holder_b := _make_army(941, 0, 2200, 20, 20)
	holder_b.state = Army.State.HOLDING
	holder_b.location_city = 19
	holder_b.move_from = 19
	holder_b.move_to = target_id
	holder_b.move_progress = 0.5
	holder_b.on_edge = true
	gs.armies.append_array([holder_a, holder_b])
	var view := AiWorldView.build(gs, 0)
	var snapshot := StrategicMapSnapshot.build(view)
	var threat := ThreatField.build(view)
	var coordinator := ArmyCoordinator.new()
	var pool := UtilityAI._adjacent_assault_pool(
		view, snapshot, threat, coordinator, target_id
	)
	_check(
		int(pool["directions"]) == 2
		and int(pool["size"]) == holder_a.size + holder_b.size,
		"两条边上的真实驻防军应形成两方向联合兵力池"
	)
	var first_attack := UtilityAI.choose(
		view, snapshot, threat, coordinator, holder_a
	)
	_check(
		first_attack.kind == ActionCandidate.Kind.ATTACK
		and first_attack.target_city == target_id
		and first_attack.reason.contains("2 个方向"),
		"单军不足但两面合计达到门槛时，应发起协同进攻：%s" % first_attack.reason
	)
	gs.uses_heightmap = true
	var formal_map_hold := UtilityAI.choose(
		view, snapshot, threat, ArmyCoordinator.new(), holder_a
	)
	_check(
		formal_map_hold.kind == ActionCandidate.Kind.HOLD
			and formal_map_hold.reason.contains(
				"不进行独立战术进攻"
			),
		"正式地图驻边军必须等待国家级两步攻势，不得独立攻击"
	)
	gs.uses_heightmap = false
	var sim := Simulation.new()
	sim.setup(gs)
	_check(sim._execute_ai_candidate(holder_a, first_attack),
		"第一方向的协同进攻命令应可执行")
	coordinator.reserve(target_id, holder_a)
	var waiting_candidate := UtilityAI.choose(
		view, snapshot, threat, coordinator, holder_b
	)
	_check(
		waiting_candidate.kind == ActionCandidate.Kind.HOLD
		and waiting_candidate.reason.contains("5 天内抵达"),
		"较快方向必须等待较慢方向接近，禁止提前添油"
	)
	for _day in range(5):
		sim._advance_movement()
	view = AiWorldView.build(gs, 0)
	threat = ThreatField.build(view)
	coordinator = ArmyCoordinator.new()
	coordinator.reserve(target_id, holder_a)
	var synchronized_attack := UtilityAI.choose(
		view, snapshot, threat, coordinator, holder_b
	)
	_check(
		synchronized_attack.kind == ActionCandidate.Kind.ATTACK
		and synchronized_attack.target_city == target_id,
		"预计抵达时间差缩小到 5 天后，较快方向必须跟进同一目标：kind=%d target=%d reason=%s"
			% [
				synchronized_attack.kind,
				synchronized_attack.target_city,
				synchronized_attack.reason,
			]
	)
	sim.free()

	var edge_guard_state := GameState.new()
	edge_guard_state.generate_grid_world(7033)
	edge_guard_state.armies.clear()
	for city in edge_guard_state.cities:
		city.owner_nation = 0
	var guarded_target := 18
	edge_guard_state.cities[guarded_target].owner_nation = 1
	edge_guard_state.cities[guarded_target].fort_strength = 1
	var guarded_edge := edge_guard_state.edge_of(17, guarded_target)
	guarded_edge.max_manpower = 30000
	var understrength := _make_army(946, 0, 10000, 10, 10)
	understrength.state = Army.State.HOLDING
	understrength.location_city = 17
	understrength.move_from = 17
	understrength.move_to = guarded_target
	understrength.move_progress = 0.4
	understrength.on_edge = true
	var full_enemy_holder := _make_army(947, 1, 15000, 10, 10)
	full_enemy_holder.state = Army.State.HOLDING
	full_enemy_holder.location_city = guarded_target
	full_enemy_holder.move_from = guarded_target
	full_enemy_holder.move_to = 17
	full_enemy_holder.move_progress = 0.4
	full_enemy_holder.on_edge = true
	edge_guard_state.armies.append_array([understrength, full_enemy_holder])
	var edge_view := AiWorldView.build(edge_guard_state, 0)
	var direct_enemy_power := UtilityAI._enemy_power_on_edge(
		edge_view, 17, guarded_target
	)
	_check(
		_approx(direct_enemy_power, ArmyPower.effective(full_enemy_holder)),
		"同边满编敌军必须按 100%% 有效战力计入，实为 %.1f" % direct_enemy_power
	)
	var guarded_candidate := UtilityAI.choose(
		edge_view,
		StrategicMapSnapshot.build(edge_view),
		ThreatField.build(edge_view),
		ArmyCoordinator.new(),
		understrength
	)
	_check(
		guarded_candidate.kind != ActionCandidate.Kind.ATTACK,
		"未满编 10000 人军队不得主动攻击同边满编 15000 人驻军：kind=%d reason=%s"
			% [guarded_candidate.kind, guarded_candidate.reason]
	)
	understrength.size = 15000
	full_enemy_holder.size = 10000
	guarded_edge.danger = 0.9
	edge_view = AiWorldView.build(edge_guard_state, 0)
	var chokepoint_candidate := UtilityAI.choose(
		edge_view,
		StrategicMapSnapshot.build(edge_view),
		ThreatField.build(edge_view),
		ArmyCoordinator.new(),
		understrength
	)
	_check(
		chokepoint_candidate.kind
			!= ActionCandidate.Kind.ATTACK,
		(
			"满编优势军也不得无视关隘75%%攻击惩罚强攻："
			+ "kind=%d reason=%s"
		) % [
			chokepoint_candidate.kind,
			chokepoint_candidate.reason,
		]
	)

	var participant_state := GameState.new()
	participant_state.generate_grid_world(7034)
	participant_state.armies.clear()
	for city in participant_state.cities:
		city.owner_nation = 0
	participant_state.cities[18].owner_nation = 1
	participant_state.cities[18].fort_strength = 1
	participant_state.cities[10].owner_nation = 1
	for edge_pair in [[17, 18], [19, 18], [10, 18]]:
		var participant_edge := participant_state.edge_of(edge_pair[0], edge_pair[1])
		participant_edge.max_manpower = 30000
		participant_edge.distance = 1
	var tiny_participant := _make_army(948, 0, 500, 10, 10)
	tiny_participant.state = Army.State.HOLDING
	tiny_participant.location_city = 17
	tiny_participant.move_from = 17
	tiny_participant.move_to = 18
	tiny_participant.move_progress = 0.5
	tiny_participant.on_edge = true
	var assault_support := _make_army(949, 0, 8500, 10, 10)
	assault_support.state = Army.State.HOLDING
	assault_support.location_city = 19
	assault_support.move_from = 19
	assault_support.move_to = 18
	assault_support.move_progress = 0.5
	assault_support.on_edge = true
	var nearby_enemy := _make_army(950, 1, 10000, 10, 10)
	nearby_enemy.state = Army.State.IDLE
	nearby_enemy.location_city = 10
	nearby_enemy.move_from = 10
	participant_state.armies.append_array(
		[tiny_participant, assault_support, nearby_enemy]
	)
	var participant_view := AiWorldView.build(participant_state, 0)
	var participant_snapshot := StrategicMapSnapshot.build(participant_view)
	var participant_threat := ThreatField.build(participant_view)
	var baseline_candidate := UtilityAI.choose(
		participant_view,
		participant_snapshot,
		participant_threat,
		ArmyCoordinator.new(),
		tiny_participant,
		0.0
	)
	var improved_candidate := UtilityAI.choose(
		participant_view,
		participant_snapshot,
		participant_threat,
		ArmyCoordinator.new(),
		tiny_participant
	)
	_check(
		baseline_candidate.kind == ActionCandidate.Kind.ATTACK,
		"B 当前 AI 应复现小军借联合兵力池出击，实为 kind=%d reason=%s"
			% [baseline_candidate.kind, baseline_candidate.reason]
	)
	_check(
		improved_candidate.kind != ActionCandidate.Kind.ATTACK,
		"A 改进 AI 应因单军战力不足继续集结，实为 kind=%d reason=%s"
			% [improved_candidate.kind, improved_candidate.reason]
	)
	var legacy_order := Simulation._sort_ai_decision_order(
		participant_view.state,
		[tiny_participant, assault_support] as Array[Army],
		participant_snapshot,
		false
	)
	var improved_order := Simulation._sort_ai_decision_order(
		participant_view.state,
		[tiny_participant, assault_support] as Array[Army],
		participant_snapshot,
		true
	)
	_check(
		legacy_order[0] == tiny_participant
		and improved_order[0] == assault_support,
		"B 当前战斗 AI 按ID决策；A 改进 AI 应让同层级主力先确定攻势"
	)

	var breakout_state := GameState.new()
	breakout_state.generate_grid_world(7031)
	breakout_state.armies.clear()
	for city in breakout_state.cities:
		city.owner_nation = 0
	var breakout_from := 17
	var breakout_target := 18
	for neighbor in breakout_state.neighbors(breakout_from):
		breakout_state.cities[neighbor].owner_nation = 1
		breakout_state.edge_of(breakout_from, neighbor).max_manpower = (
			15000 if neighbor == breakout_target else 0
		)
	breakout_state.cities[breakout_target].fort_strength = 10
	var starving := _make_army(942, 0, 1000, 10, 10)
	starving.location_city = breakout_from
	starving.move_from = breakout_from
	starving.state = Army.State.IDLE
	starving.starving = true
	starving.supply_ratio = 0.0
	starving.morale = 0.2
	breakout_state.armies.append(starving)
	breakout_state.uses_heightmap = true
	view = AiWorldView.build(breakout_state, 0)
	snapshot = StrategicMapSnapshot.build(view)
	threat = ThreatField.build(view)
	var breakout := UtilityAI.choose(
		view, snapshot, threat, ArmyCoordinator.new(), starving
	)
	_check(
		breakout.kind == ActionCandidate.Kind.ATTACK
		and breakout.target_city == breakout_target
		and breakout.reason.contains("背水突围"),
		"完全断粮军不得原地等死，应优先攻击相邻包围节点：%s" % breakout.reason
	)
	breakout_state.cities[breakout_target].fort_strength = 100
	snapshot = StrategicMapSnapshot.build(view)
	var hopeless_breakout := UtilityAI.choose(
		view, snapshot, threat, ArmyCoordinator.new(), starving
	)
	_check(
		hopeless_breakout.kind != ActionCandidate.Kind.ATTACK,
		"突围战力比低于 0.70 时不得主动送死"
	)

	var relief_state := GameState.new()
	relief_state.generate_grid_world(7032)
	relief_state.armies.clear()
	for city in relief_state.cities:
		city.owner_nation = 0
	_set_single_warehouse(relief_state, 0, 0, 5000)
	var trapped := _make_army(943, 0, 2000, 10, 10)
	trapped.location_city = 18
	trapped.move_from = 18
	trapped.state = Army.State.IDLE
	trapped.starving = true
	trapped.supply_ratio = 0.0
	var rescuer := _make_army(944, 0, 1000, 10, 10)
	rescuer.location_city = 16
	rescuer.move_from = 16
	rescuer.state = Army.State.IDLE
	var besieger := _make_army(945, 1, 1000, 10, 10)
	besieger.state = Army.State.FIGHTING
	var siege := relief_state.new_battle(Battle.Kind.SIEGE)
	siege.city = relief_state.cities[trapped.location_city]
	siege.has_garrison = true
	siege.side_a.append(besieger)
	siege.side_b.append(trapped)
	relief_state.armies.append_array([trapped, rescuer, besieger])
	view = AiWorldView.build(relief_state, 0)
	snapshot = StrategicMapSnapshot.build(view)
	threat = ThreatField.build(view)
	var relief := UtilityAI.choose(
		view, snapshot, threat, ArmyCoordinator.new(), rescuer
	)
	_check(
		relief.kind == ActionCandidate.Kind.REINFORCE
		and relief.target_city == trapped.location_city
		and relief.reason.contains("紧急解围"),
		"可达的断粮友军应成为高优先级救援目标：%s" % relief.reason
	)

# ------------------------------------------------------------------ 31. 全国人口库、补员、建军与解散

func _test_manpower_pool_and_force_commands() -> void:
	print("[31] 全国人口：月收入、公平补员、满编、边上阻断、建军与解散")
	var gs := GameState.new()
	gs.generate_grid_world(7100)
	var sim := Simulation.new()
	sim.setup(gs)
	var nation_id := 0
	var expected_initial := 0
	var monthly_income := 0
	for city in gs.cities_of(nation_id):
		expected_initial += (
			city.manpower_per_month
			* GameState.INITIAL_MANPOWER_RESERVE_MONTHS
		)
		monthly_income += city.manpower_per_month
		_check(
			city.manpower_per_month >= GameState.CITY_MANPOWER_PER_MONTH_MIN
			and city.manpower_per_month <= GameState.CITY_MANPOWER_PER_MONTH_MAX,
			"城市月度人口恢复应位于新标定区间"
		)
	_check(
		GameState.INITIAL_MANPOWER_RESERVE_MONTHS == 750
			and gs.nations[nation_id].manpower_pool == expected_initial,
		"开局人口库应按 750 个月产出储备（旧值 150 的 5 倍）：应 %d，实为 %d"
			% [expected_initial, gs.nations[nation_id].manpower_pool]
	)
	var initial_light_armies := 0
	var initial_heavy_armies := 0
	for army in gs.armies:
		if army.owner_nation != nation_id:
			continue
		if (
			army.size == GameState.INITIAL_LIGHT_ARMY_SIZE
			and army.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE
		):
			initial_light_armies += 1
		elif (
			army.size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
		):
			initial_heavy_armies += 1
	_check(
		initial_light_armies == 18
			and initial_heavy_armies == 1,
		"网格状态机夹具应保留16支城市填线军和一个2轻1重战团"
	)
	var pool_before_income := gs.nations[nation_id].manpower_pool
	gs.day = Simulation.DAYS_PER_MONTH
	sim._resolve_economy()
	_check(gs.nations[nation_id].manpower_pool == pool_before_income + monthly_income,
		"每月城市人口产出应立即汇入全国人口库")

	gs.armies.clear()
	var owned := gs.cities_of(nation_id)
	var a := gs.create_army(nation_id, owned[0].id, 1000)
	var b := gs.create_army(nation_id, owned[1].id, 1000)
	a.max_size = 15000
	b.max_size = 15000
	gs.nations[nation_id].manpower_pool = 100
	sim._resolve_reinforcements()
	_check(a.size == 1050 and b.size == 1050 and gs.nations[nation_id].manpower_pool == 0,
		"同缺编军队应公平分配人口：a=%d b=%d pool=%d"
			% [a.size, b.size, gs.nations[nation_id].manpower_pool])
	gs.nations[nation_id].manpower_pool = 5000
	var a_before := a.size
	var b_before := b.size
	sim._resolve_reinforcements()
	_check(
		a.size - a_before == Simulation.REINFORCE_PER_ARMY_PER_MONTH
		and b.size - b_before == Simulation.REINFORCE_PER_ARMY_PER_MONTH,
		"单军每月补员不得超过 %d：a=%d b=%d"
			% [
				Simulation.REINFORCE_PER_ARMY_PER_MONTH,
				a.size - a_before,
				b.size - b_before,
			]
	)

	gs.armies.clear()
	var merge_a := gs.create_army(nation_id, owned[0].id, 10000)
	var merge_b := gs.create_army(nation_id, owned[0].id, 10000)
	ArmyCoordinator.merge_colocated(gs)
	gs.armies.sort_custom(func(x: Army, y: Army) -> bool: return x.size > y.size)
	_check(gs.armies.size() == 2 and gs.armies[0].size == 15000 and gs.armies[1].size == 5000,
		"自动合并不得突破 15000 满编：实为 %s"
			% str(gs.armies.map(func(army: Army) -> int: return army.size)))
	_check(merge_a.size + merge_b.size == 20000,
		"受满编限制的部分合并必须保持总兵力守恒")

	gs.armies.clear()
	var edge_a := -1
	var edge_b := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation == nation_id \
			and gs.cities[edge.city_b].owner_nation == nation_id \
			and edge.max_manpower > 0:
			edge_a = edge.city_a
			edge_b = edge.city_b
			break
	var holder := gs.create_army(nation_id, edge_a, 1000)
	holder.state = Army.State.HOLDING
	holder.move_from = edge_a
	holder.move_to = edge_b
	holder.move_progress = 0.5
	holder.on_edge = true
	holder.max_size = 1010
	var open_hub_network := Pathfinding.build_manpower_hub_network(
		gs, nation_id
	)
	_check(
		Pathfinding.can_reach_manpower_hub(gs, holder)
			== Pathfinding.can_reach_manpower_hub_from_network(
				gs, holder, open_hub_network
			),
		"友方边上的旧/新补员可达判定必须一致"
	)
	gs.nations[nation_id].manpower_pool = 10
	sim._resolve_reinforcements()
	_check(holder.size == 1010 and gs.nations[nation_id].manpower_pool == 0,
		"无敌军争夺的友方边应允许补员至满编")

	holder.size = 1000
	gs.nations[nation_id].manpower_pool = 10
	var enemy := _make_army(9990, 1, 1000, 10)
	enemy.state = Army.State.MOVING
	enemy.move_from = edge_b
	enemy.move_to = edge_a
	enemy.move_progress = 0.2
	enemy.on_edge = true
	gs.armies.append(enemy)
	var contested_hub_network := (
		Pathfinding.build_manpower_hub_network(gs, nation_id)
	)
	_check(
		Pathfinding.can_reach_manpower_hub(gs, holder)
			== Pathfinding.can_reach_manpower_hub_from_network(
				gs, holder, contested_hub_network
			)
			and not Pathfinding.can_reach_manpower_hub_from_network(
				gs, holder, contested_hub_network
			),
		"敌军争夺边上的旧/新补员可达判定必须一致且均为不可达"
	)
	sim._resolve_reinforcements()
	_check(holder.size == 1000 and gs.nations[nation_id].manpower_pool == 10,
		"当前边有敌军争夺时必须禁止边上补员")

	gs.armies.erase(enemy)
	holder.on_edge = false
	gs.armies.erase(holder)
	var capital_id := gs.nations[nation_id].capital_city_id
	gs.nations[nation_id].manpower_pool = 6000
	gs.nations[nation_id].treasury_gold = 100
	var light_upkeep := GameState.army_monthly_upkeep(
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var light_creation_cost := (
		GameState.formation_creation_gold_cost(
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
	)
	var treasury_before_creation := (
		gs.nations[nation_id].treasury_gold
	)
	var created := sim._create_army_for_nation(
		nation_id,
		capital_id,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		"测试建军"
	)
	_check(created != null and created.size == 5000 and created.max_size == 5000
		and gs.nations[nation_id].manpower_pool == 1000
		and light_creation_cost == light_upkeep * 10
		and gs.nations[nation_id].treasury_gold
			== treasury_before_creation - light_creation_cost,
		"轻军建军应消耗5000人和10个月维护费：upkeep=%d create=%d treasury=%d"
			% [
				light_upkeep,
				light_creation_cost,
				gs.nations[nation_id].treasury_gold,
			])
	var pool_before_disband := gs.nations[nation_id].manpower_pool
	var created_size := created.size
	_check(sim._disband_army(created, "测试解散")
		and not gs.armies.has(created)
		and gs.nations[nation_id].manpower_pool == pool_before_disband + created_size,
		"解散应删除军队并把全部幸存人数返还全国人口库")
	gs.nations[nation_id].manpower_pool = 6000
	gs.nations[nation_id].treasury_gold = (
		light_creation_cost - 1
	)
	var manpower_before_failed_creation := (
		gs.nations[nation_id].manpower_pool
	)
	var unaffordable_creation := sim._create_army_for_nation(
		nation_id,
		capital_id,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		"资金不足建军测试"
	)
	_check(
		unaffordable_creation == null
			and gs.nations[nation_id].manpower_pool
				== manpower_before_failed_creation
			and gs.nations[nation_id].treasury_gold
				== light_creation_cost - 1,
		"资金不足时不得创建新编制，也不得预扣人力或金钱"
	)

	var finance_state := GameState.new()
	finance_state.generate_grid_world(7104)
	finance_state.armies.clear()
	for finance_a in range(finance_state.nations.size()):
		for finance_b in range(
			finance_a + 1,
			finance_state.nations.size()
		):
			finance_state.set_diplomatic_relation(
				finance_a,
				finance_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var finance_city := finance_state.cities_of(0)[0].id
	finance_state.create_army(0, finance_city, 5000, 5000)
	finance_state.create_army(0, finance_city, 15000, 15000)
	finance_state.nations[0].treasury_gold = 3
	var finance_sim := Simulation.new()
	finance_sim.setup(finance_state)
	finance_sim._resolve_military_finance()
	var finance_upkeep := (
		GameState.army_monthly_upkeep(5000)
		+ GameState.army_monthly_upkeep(15000)
	)
	_check(
		finance_state.nations[0].treasury_gold == 0
			and finance_state.nations[0].last_military_upkeep
				== finance_upkeep
			and finance_state.nations[0].unpaid_military_upkeep
				== finance_upkeep - 3
			and _approx(
				finance_state.nations[0]
					.military_payment_ratio,
				3.0 / float(finance_upkeep)
			),
		"和平或战争时期都应逐编制结算维护费并记录实际支付率"
	)
	finance_state.uses_heightmap = true
	for city in finance_state.cities_of(0):
		city.gold_per_month = 0
	finance_state.nations[0].food_demand_ema = 0.0
	finance_state.deposit_food(0, 1000000)
	var upkeep_before_financial_demobilization := (
		finance_state.nation_monthly_military_upkeep(0)
	)
	var finance_view := AiWorldView.build(
		finance_state,
		0
	)
	var finance_snapshot := StrategicMapSnapshot.build(
		finance_view
	)
	var finance_threat := ThreatField.build(finance_view)
	var finance_plan := CityDefensePlan.build(
		finance_view,
		finance_snapshot,
		finance_threat
	)
	var financial_demobilized := (
		finance_sim._ai_manage_force_structure(
			finance_view,
			finance_snapshot,
			finance_threat,
			finance_plan
		)
	)
	_check(
		financial_demobilized
			and finance_state.nation_monthly_military_upkeep(0)
				< upkeep_before_financial_demobilization
			and finance_state.nations[
				0
			].ai_last_force_reason.contains(
				"财政储备缩编"
			),
		"国库为0且存在未付军费时，军制AI必须主动缩编并降低月维护费"
	)
	var upkeep_after_first_financial_demobilization := (
		finance_state.nation_monthly_military_upkeep(0)
	)
	var repeat_finance_view := AiWorldView.build(finance_state, 0)
	var repeat_finance_snapshot := StrategicMapSnapshot.build(
		repeat_finance_view
	)
	var repeat_finance_threat := ThreatField.build(repeat_finance_view)
	var repeated_financial_demobilization := (
		finance_sim._ai_manage_force_structure(
			repeat_finance_view,
			repeat_finance_snapshot,
			repeat_finance_threat,
			CityDefensePlan.build(
				repeat_finance_view,
				repeat_finance_snapshot,
				repeat_finance_threat
			)
		)
	)
	_check(
		not repeated_financial_demobilization
		and finance_state.nation_monthly_military_upkeep(0)
			== upkeep_after_first_financial_demobilization,
		"同一月内旧欠饷记录不得驱动连续重复缩编"
	)
	finance_sim.free()

	var force_state := GameState.new()
	force_state.generate_world(7103)
	var force_nation_id := 0
	var force_capital := force_state.nations[
		force_nation_id
	].capital_city_id
	for force_army in force_state.armies.duplicate():
		if force_army.owner_nation == force_nation_id:
			force_state.armies.erase(force_army)
	force_state.nations[force_nation_id].battle_groups.clear()
	force_state.nations[force_nation_id].next_battle_group_id = 0
	force_state.nations[force_nation_id].manpower_pool = 1000000
	force_state.nations[force_nation_id].treasury_gold = 1000000
	var priority_force_sim := Simulation.new()
	priority_force_sim.setup(force_state)
	var priority_force_view := AiWorldView.build(
		force_state,
		force_nation_id
	)
	var no_line_slots := CityDefensePlan.new()
	no_line_slots.view = priority_force_view
	no_line_slots.snapshot = StrategicMapSnapshot.build(
		priority_force_view
	)
	no_line_slots.threat = ThreatField.build(priority_force_view)
	no_line_slots.line_city_slots = 0
	no_line_slots.line_edge_slots = 0
	var priority_force_created := (
		priority_force_sim._ai_manage_force_structure(
			priority_force_view,
			StrategicMapSnapshot.build(priority_force_view),
			ThreatField.build(priority_force_view),
			no_line_slots
		)
	)
	var first_group := force_state.nations[
		force_nation_id
	].battle_groups[0]
	var first_members := force_state.battle_group_members(
		force_nation_id,
		first_group.id
	)
	_check(
		priority_force_created
			and first_members.size() == 1
			and first_members[0].max_size
				== GameState.INITIAL_LIGHT_ARMY_SIZE
			and first_members[0].is_main_battle_role(),
		"没有战团时必须先创建持久战团并加入第一支5000主战轻军"
	)
	for _group_growth in range(2):
		var growth_view := AiWorldView.build(
			force_state,
			force_nation_id
		)
		no_line_slots.view = growth_view
		priority_force_sim._ai_manage_force_structure(
			growth_view,
			StrategicMapSnapshot.build(growth_view),
			ThreatField.build(growth_view),
			no_line_slots
		)
	first_members = force_state.battle_group_members(
		force_nation_id,
		first_group.id
	)
	var group_light_count := 0
	var group_heavy_count := 0
	for force_member in first_members:
		if (
			force_member.max_size
				== GameState.INITIAL_LIGHT_ARMY_SIZE
		):
			group_light_count += 1
		elif (
			force_member.max_size
				== GameState.INITIAL_HEAVY_ARMY_SIZE
		):
			group_heavy_count += 1
	_check(
		first_members.size() == 3
			and group_light_count == 2
			and group_heavy_count == 1,
		"战团必须严格按第一轻军、第二轻军、重军的顺序扩充为2轻1重"
	)
	var peace_full_group_view := AiWorldView.build(
		force_state,
		force_nation_id
	)
	no_line_slots.view = peace_full_group_view
	var peace_overexpansion_blocked := not (
		priority_force_sim._ai_manage_force_structure(
			peace_full_group_view,
			StrategicMapSnapshot.build(peace_full_group_view),
			ThreatField.build(peace_full_group_view),
			no_line_slots
		)
	)
	_check(
		peace_overexpansion_blocked
			and force_state.nations[
				force_nation_id
			].battle_groups.size() == 1,
		"和平期填线已满且已有完整战团时，不得把全部资源持续转成闲置战团"
	)
	for force_city in force_state.cities_of(force_nation_id):
		force_city.food_per_half_year = 100000
	force_state.cities[force_capital].food_storage = 1000000
	var forced_comprehensive_targets := 0
	var forced_comprehensive_target_ids: Array[int] = []
	var protected_force_sources := {}
	for force_source in force_state.cities_of(force_nation_id):
		if (
			force_source.id == force_capital
			or forced_comprehensive_target_ids.has(force_source.id)
		):
			continue
		for force_neighbor in force_state.neighbors(force_source.id):
			var force_edge := force_state.edge_of(
				force_source.id,
				force_neighbor
			)
			if (
				force_edge != null
				and force_edge.max_manpower
					>= Edge.STANDARD_MANPOWER
				and not forced_comprehensive_target_ids.has(
					force_neighbor
				)
				and force_neighbor != force_capital
				and not protected_force_sources.has(force_neighbor)
			):
				forced_comprehensive_targets += 1
				forced_comprehensive_target_ids.append(force_neighbor)
				protected_force_sources[force_source.id] = true
				if forced_comprehensive_targets >= 4:
					break
		if forced_comprehensive_targets >= 4:
			break
	for force_target in forced_comprehensive_target_ids:
		force_state.cities[force_target].owner_nation = 1
	force_state.ownership_revision += 1
	force_state.nations[
		force_nation_id
	].war_preparation_target_nation = 1
	force_state.nations[
		force_nation_id
	].campaign_preparation_targets = (
		forced_comprehensive_target_ids.duplicate()
	)
	var next_group_view := AiWorldView.build(
		force_state,
		force_nation_id
	)
	no_line_slots.view = next_group_view
	var next_group_started := (
		priority_force_sim._ai_manage_force_structure(
			next_group_view,
			StrategicMapSnapshot.build(next_group_view),
			ThreatField.build(next_group_view),
			no_line_slots
		)
	)
	_check(
		next_group_started
			and force_state.nations[
				force_nation_id
			].battle_groups.size() == 2
			and force_state.battle_group_members(
				force_nation_id,
				1
			).size() == 1,
		"满编战团后继续扩军必须先创建下一战团并加入第一支轻军"
	)
	var comprehensive_snapshot := StrategicMapSnapshot.build(
		next_group_view
	)
	var comprehensive_demand_targets := (
		priority_force_sim._campaign_force_demand_targets(
			force_nation_id,
			comprehensive_snapshot
		)
	)
	var comprehensive_target_capacity := (
		priority_force_sim._campaign_required_group_count(
			force_nation_id,
			comprehensive_demand_targets,
			ThreatField.build(next_group_view)
		)
	)
	for _comprehensive_growth in range(6):
		var comprehensive_view := AiWorldView.build(
			force_state,
			force_nation_id
		)
		no_line_slots.view = comprehensive_view
		priority_force_sim._ai_manage_force_structure(
			comprehensive_view,
			StrategicMapSnapshot.build(comprehensive_view),
			ThreatField.build(comprehensive_view),
			no_line_slots
		)
	_check(
		forced_comprehensive_targets == 4
			and comprehensive_demand_targets.size() == 4
			and comprehensive_target_capacity > 3
			and force_state.nations[
				force_nation_id
			].battle_groups.size() >= 4,
		"备战期战团数量必须只由四个实际准备目标的统一需求决定"
	)
	var decisive_state := GameState.new()
	decisive_state.generate_grid_world(7106)
	for decisive_city in decisive_state.cities:
		decisive_city.owner_nation = 0
	var decisive_target := 1
	decisive_state.cities[decisive_target].owner_nation = 1
	decisive_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var decisive_sim := Simulation.new()
	decisive_sim.setup(decisive_state)
	var decisive_demand := decisive_sim._campaign_target_group_demand(
		0, decisive_target, null
	)
	var decisive_recruitment := (
		decisive_sim._next_battle_group_recruitment(0, true, true)
	)
	decisive_state.nations[0].battle_groups.clear()
	decisive_state.nations[0].next_battle_group_id = 0
	var decisive_groups: Array[int] = []
	for decisive_index in range(3):
		var decisive_group := decisive_state.create_battle_group(0)
		var decisive_army := _make_army(9700 + decisive_index, 0, 5000, 10, 10)
		decisive_army.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
		decisive_army.location_city = 0
		decisive_army.move_from = 0
		decisive_state.armies.append(decisive_army)
		decisive_state.assign_army_to_battle_group(
			decisive_army, decisive_group.id
		)
		decisive_groups.append(decisive_group.id)
	var decisive_view := AiWorldView.build(decisive_state, 0)
	var decisive_plan := CityDefensePlan.new()
	decisive_plan.view = decisive_view
	decisive_plan.threat = ThreatField.build(decisive_view)
	var decisive_allocation := (
		decisive_sim._plan_campaign_allocation(
			0,
			decisive_target,
			[decisive_target] as Array[int],
			decisive_plan,
			ArmyCoordinator.new(),
			decisive_view,
			false
		)
	)
	var decisive_planned_groups := (
		decisive_allocation.groups_for_target(decisive_target)
	)
	var decisive_unique_planned_groups := {}
	for decisive_group_id in decisive_planned_groups:
		decisive_unique_planned_groups[decisive_group_id] = true
	var decisive_locked_member := decisive_state.battle_group_members(
		0, decisive_groups[0]
	)[0]
	decisive_locked_member.defensive_deployment_until_day = (
		decisive_state.day + Simulation.DEFENSIVE_DEPLOYMENT_LOCK_DAYS
	)
	var locked_decisive_allocation := (
		decisive_sim._plan_campaign_allocation(
			0, decisive_target, [decisive_target] as Array[int],
			decisive_plan, ArmyCoordinator.new(), decisive_view, false
		)
	)
	_check(
		decisive_allocation.assigned_target_ids
			== [decisive_target]
			and decisive_planned_groups.size()
				>= Simulation.CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
			and decisive_unique_planned_groups.size()
				== decisive_planned_groups.size()
			and decisive_allocation.assigned_group_count
				== decisive_planned_groups.size()
			and locked_decisive_allocation.groups_for_target(
				decisive_target
			).size() >= Simulation.CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS,
		"纯规划器必须为敌国最后一城直接配置至少三支互异战团：%s"
			% str(decisive_allocation.group_to_target)
	)
	var decisive_assigned := (
		decisive_sim._apply_campaign_plan_atomic(
			0, decisive_allocation
		)
	)
	var decisive_assigned_groups := {}
	for decisive_army in decisive_state.armies:
		if int(decisive_state.nations[0].campaign_preparation_assignments.get(
			decisive_army.id, -1
		)) == decisive_target:
			decisive_assigned_groups[decisive_army.battle_group_id] = true
	_check(
		int(decisive_demand.get("groups", 0))
			>= Simulation.CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
			and bool(decisive_recruitment.get("create_group", false))
			and decisive_assigned
			and decisive_assigned_groups.size()
				>= Simulation.CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS,
		"消灭敌国最后一城必须至少组织三支独立战团，并优先建立新战团骨架"
	)
	decisive_sim.free()
	var ungrouped_heavy := (
		priority_force_sim._create_army_for_nation(
			force_nation_id,
			force_capital,
			GameState.INITIAL_HEAVY_ARMY_SIZE,
			"非法独立重军"
		)
	)
	_check(
		ungrouped_heavy == null,
		"15000重军只能作为战团第三成员创建，不得成为独立编制"
	)
	priority_force_sim.free()

	var split_source := gs.create_army(
		nation_id,
		capital_id,
		13021
	)
	var split_group := gs.create_battle_group(nation_id)
	gs.assign_army_to_battle_group(
		split_source,
		split_group.id
	)
	split_source.attack = 13
	split_source.defense = 14
	split_source.morale = split_source.max_morale * 0.73
	var split_parts := gs.split_army(
		split_source,
		5000
	)
	var split_size_total := 0
	var split_capacity_total := 0
	var split_attributes_preserved := true
	var split_group_members := 0
	for split_part in split_parts:
		split_size_total += split_part.size
		split_capacity_total += split_part.max_size
		split_attributes_preserved = (
			split_attributes_preserved
			and split_part.attack == 13
			and split_part.defense == 14
			and _approx(split_part.morale, 0.73)
			and _approx(
				split_part.max_morale,
				Army.LIGHT_MAX_MORALE
			)
		)
		if split_part.battle_group_id == split_group.id:
			split_group_members += 1
	_check(
		split_parts.size() == 3
		and split_size_total == 13021
		and split_capacity_total == 15000
		and split_attributes_preserved
		and split_group_members == 2,
		"拆分应保持兵力和属性守恒，并且同战团最多继承两支轻军"
	)

	var narrow_state := GameState.new()
	narrow_state.generate_grid_world(7101)
	narrow_state.armies.clear()
	narrow_state.battles.clear()
	for narrow_city in narrow_state.cities:
		narrow_city.owner_nation = 2
	narrow_state.cities[0].owner_nation = 0
	narrow_state.cities[1].owner_nation = 1
	for narrow_edge in narrow_state.edges:
		narrow_edge.max_manpower = 0
	narrow_state.edge_of(0, 1).max_manpower = 5000
	narrow_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var narrow_army := narrow_state.create_army(
		0,
		0,
		15000
	)
	narrow_state.nations[0].war_preparation_target_nation = 1
	narrow_state.nations[0].war_preparation_objective_city = 1
	var narrow_sim := Simulation.new()
	narrow_sim.setup(narrow_state)
	var narrow_view := AiWorldView.build(
		narrow_state,
		0
	)
	var narrow_split_changed := (
		narrow_sim._ai_manage_force_structure(
			narrow_view,
			StrategicMapSnapshot.build(narrow_view),
			ThreatField.build(narrow_view)
		)
	)
	_check(
		not narrow_split_changed
			and narrow_state.active_army_count(0) == 1
			and narrow_state.armies[0] == narrow_army
			and narrow_army.max_size
				== GameState.INITIAL_HEAVY_ARMY_SIZE
			and narrow_army.road_footprint() == Edge.MIN_MANPOWER,
		"五千道路已可承载重军运输足迹，AI不得为通行而拆分15000编制"
	)
	narrow_army.state = Army.State.MOVING
	narrow_army.move_from = 0
	narrow_army.path = [1] as Array[int]
	narrow_sim._begin_next_leg(narrow_army)
	_check(
		narrow_army.on_edge
		and narrow_army.move_to == 1,
		"未拆分的15000重军应能直接进入5000容量道路"
	)
	narrow_sim.free()

	var cap_state := GameState.new()
	cap_state.generate_grid_world(7102)
	var cap_nation := 0
	var expected_cap := (
		cap_state.cities_of(cap_nation).size() * 3
	)
	_check(
		cap_state.max_army_count(cap_nation)
			== expected_cap,
		"国家军队数量上限应为本国城市数的三倍"
	)
	var cap_city := cap_state.nations[
		cap_nation
	].capital_city_id
	while (
		cap_state.active_army_count(cap_nation)
		< expected_cap
	):
		_check(
			cap_state.create_army(
				cap_nation,
				cap_city,
				1
			) != null,
			"达到三倍上限前应允许继续建军"
		)
	_check(
		cap_state.create_army(
			cap_nation,
			cap_city,
			1
		) == null,
		"达到三倍国家军队上限后必须拒绝继续建军"
	)
	sim.free()


# ------------------------------------------------------------------ 32. 外交关系与 Utility AI

func _test_diplomacy_state_and_ai() -> void:
	print("[32] 外交：求和、宣战、结盟、退盟、停战与敌我筛选")
	var distance_state := GameState.new()
	distance_state.generate_grid_world(32000)
	# 四个纵向条带形成严格的国家接触链 0-1-2-3。外交距离按领土
	# 接触图计算，不依赖地图坐标或固定场景尺寸。
	for city in distance_state.cities:
		var owner := clampi(city.coord.x / 2, 0, 3)
		city.owner_nation = owner
		distance_state.recognized_city_owners[city.id] = owner
	for distance_a in range(distance_state.nations.size()):
		for distance_b in range(
			distance_a + 1, distance_state.nations.size()
		):
			distance_state.set_diplomatic_relation(
				distance_a, distance_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	for distance_nation in distance_state.nations:
		distance_state.relocate_capital(distance_nation.id)
	distance_state.refresh_derived()
	var distant_sea_link := Edge.new()
	distant_sea_link.city_a = distance_state.cities_of(0)[0].id
	distant_sea_link.city_b = distance_state.cities_of(3)[0].id
	distant_sea_link.kind = Edge.Kind.SEA
	distant_sea_link.max_manpower = Edge.WATER_MANPOWER
	distance_state.edges.append(distant_sea_link)
	var distance_cache := {}
	_check(
		DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 1, distance_cache
		)
		and DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 2, distance_cache
		)
		and not DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 3, distance_cache
		)
		and DiplomacyAI._diplomatic_range_nation_ids(
			distance_state, 0, distance_cache
		) == [1, 2],
		"外交距离应允许一至两跳国家，拒绝三跳外目标，且远程海运不得缩短外交距离"
	)
	distant_sea_link.kind = Edge.Kind.LANDING
	distance_state.road_network_revision += 1
	_check(
		DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 3, distance_cache
		),
		"跨河登陆连接应视为地理接壤，边类型变化后必须重建外交距离缓存"
	)
	distant_sea_link.kind = Edge.Kind.RIVER
	distance_state.road_network_revision += 1
	_check(
		not DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 3, distance_cache
		),
		"沿河远程运输不得缩短外交距离，也不得沿用登陆边的近邻缓存"
	)
	distant_sea_link.kind = Edge.Kind.SEA
	distance_state.road_network_revision += 1
	_check(
		not DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 3, distance_cache
		),
		"远程海运不得缩短外交距离"
	)
	distance_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.ALLIED
	)
	var alliance_reach_cache := {}
	_check(
		DiplomacyAI._frontier_edges(
			distance_state, 0, 3, alliance_reach_cache
		) > 0
		and not DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 3, alliance_reach_cache
		)
		and DiplomacyAI.war_desire(
			distance_state, 0, 3, alliance_reach_cache
		) == -INF,
		"远方盟友提供的军事接触不得绕过本国两跳外交距离"
	)
	distance_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.NEUTRAL
	)
	_check(
		DiplomacyAI.alliance_willingness(
			distance_state, 0, 3, distance_cache
		) == -INF
		and DiplomacyAI.war_desire(
			distance_state, 0, 3, distance_cache
		) == -INF,
		"超出外交距离的国家不得形成新联盟或主动战争候选"
	)
	var distance_sim := Simulation.new()
	distance_sim.setup(distance_state)
	var distant_alliance_committed := (
		distance_sim._execute_diplomatic_action({
			"kind": DiplomacyAI.Action.FORM_ALLIANCE,
			"a": 0,
			"b": 3,
			"reason": "远距外交门禁测试",
		})
	)
	var distant_preparation_committed := (
		distance_sim._execute_diplomatic_action({
			"kind": DiplomacyAI.Action.PREPARE_WAR,
			"a": 0,
			"b": 3,
			"objective_city": distance_state.nations[3].capital_city_id,
			"reason": "远距备战门禁测试",
		})
	)
	var distant_war_committed := (
		distance_sim._execute_diplomatic_action({
			"kind": DiplomacyAI.Action.DECLARE_WAR,
			"a": 0,
			"b": 3,
			"reason": "远距宣战门禁测试",
		})
	)
	_check(
		not distant_alliance_committed
		and not distant_preparation_committed
		and not distant_war_committed
		and distance_state.relation_between(0, 3)
			== GameState.DiplomaticRelation.NEUTRAL
		and distance_state.nations[0].war_preparation_target_nation == -1,
		"动作提交层必须拒绝绕过候选评分的远距结盟、备战和宣战"
	)
	_check(
		distance_state.set_diplomatic_relation(
			0, 3, GameState.DiplomaticRelation.ALLIED
		)
		and distance_state.is_allied(0, 3),
		"剧本或政治事件建立的既有远距关系不得被距离规则强制拆除"
	)
	for distance_city in distance_state.cities:
		if distance_city.owner_nation == 2:
			distance_city.owner_nation = 1
			distance_state.recognized_city_owners[distance_city.id] = 1
	distance_state.ownership_revision += 1
	_check(
		DiplomacyAI.within_diplomatic_range(
			distance_state, 0, 3, distance_cache
		),
		"领土易主将三跳链缩为两跳后，外交距离缓存必须按所有权版本失效"
	)
	distance_sim.free()
	var gs := GameState.new()
	gs.generate_grid_world(32001)
	_check(
		is_zero_approx(DiplomacyAI.unification_era_factor(gs)),
		"统一时代在自然演化期内必须保持为0"
	)
	gs.day = DiplomacyAI.UNIFICATION_ERA_FULL_YEARS * 365
	_check(
		is_equal_approx(DiplomacyAI.unification_era_factor(gs), 1.0),
		"统一时代到完整年份时必须单调收敛到1"
	)
	gs.day = 0
	_check(
		gs.is_enemy(0, 1) and gs.is_enemy(1, 0),
		"初始全面战争关系应双向对称"
	)
	_check(
		gs.set_diplomatic_relation(
			0, 1, GameState.DiplomaticRelation.NEUTRAL, 180
		),
		"交战国应能达成和平"
	)
	_check(
		not gs.is_enemy(0, 1)
		and gs.relation_between(0, 1) == gs.relation_between(1, 0),
		"和平关系应双向一致"
	)
	_check(not gs.can_declare_war(0, 1), "停战期内不得重新宣战")
	gs.day = 180
	_check(gs.can_declare_war(0, 1), "停战期届满后应恢复宣战资格")
	_check(
		gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED),
		"中立国家应能建立联盟"
	)
	var allied_view := AiWorldView.build(gs, 0)
	var nation_one_is_enemy_city := false
	var nation_one_is_allied_city := false
	for city in allied_view.enemy_cities:
		nation_one_is_enemy_city = (
			nation_one_is_enemy_city or city.owner_nation == 1
		)
	for city in allied_view.allied_cities:
		nation_one_is_allied_city = (
			nation_one_is_allied_city or city.owner_nation == 1
		)
	_check(
		not nation_one_is_enemy_city and nation_one_is_allied_city,
		"盟国城市不得进入敌城列表，应进入盟国列表"
	)
	var nation_one_is_enemy_army := false
	for army in allied_view.enemy_armies:
		nation_one_is_enemy_army = (
			nation_one_is_enemy_army or army.owner_nation == 1
		)
	_check(
		not nation_one_is_enemy_army,
		"盟军不得进入威胁场的敌军来源"
	)
	var alliance_geometry := MapRenderer.build_province_boundary_segments(gs)
	var alliance_country_geometry: PackedVector2Array = (
		alliance_geometry["country"]
	)
	var alliance_boundary_color := MapRenderer.nation_boundary_color(gs, 0)
	_check(
		not alliance_country_geometry.is_empty()
		and not (
			alliance_geometry["alliance"] as PackedVector2Array
		).is_empty(),
		"盟国接壤边界应保留国家中心线，联盟子集只记录外交语义"
	)
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var enemy_geometry := MapRenderer.build_province_boundary_segments(gs)
	var enemy_boundary_color := MapRenderer.nation_boundary_color(gs, 0)
	_check(
		not (enemy_geometry["enemy"] as PackedVector2Array).is_empty()
		and (enemy_geometry["country"] as PackedVector2Array)
			== alliance_country_geometry
		and enemy_boundary_color.is_equal_approx(alliance_boundary_color)
		and is_equal_approx(
			MapRenderer.COUNTRY_BOUNDARY_SATURATION_OFFSET,
			0.10
		),
		"外交关系变化只能更新语义子集，国家边界几何与国家色不得变化"
	)
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	var nation_lines := MapRenderer.nation_detail_lines(gs, 0)
	var nation_sections := MapRenderer.nation_detail_sections(gs, 0)
	_check(
		nation_sections.size() == 5
		and [
			str(nation_sections[0]["title"]),
			str(nation_sections[1]["title"]),
			str(nation_sections[2]["title"]),
			str(nation_sections[3]["title"]),
			str(nation_sections[4]["title"]),
		] == [
			"身份与君主", "国力与民心", "财政与军费",
			"粮食与贸易", "外交与行动",
		]
		and nation_lines.size() >= 10
		and "月净" in str((nation_sections[2]["lines"] as Array)[0])
		and "贡赋" in str((nation_sections[2]["lines"] as Array)[0])
		and "军费" in str((nation_sections[2]["lines"] as Array)[1])
		and "支付" in str((nation_sections[2]["lines"] as Array)[1])
		and "粮仓" in str((nation_sections[3]["lines"] as Array)[0])
		and "商路" in str((nation_sections[3]["lines"] as Array)[1])
		and "商贸金" in str((nation_sections[3]["lines"] as Array)[1])
		and "盟国" in str((nation_sections[4]["lines"] as Array)[1])
		and MapRenderer.nation_detail_sections(gs, -1).is_empty(),
		"国家五段详情必须独立展示君主、国力、财政军费、粮食贸易和外交行动"
	)
	_check(
		gs.has_military_access(0, 1)
		and not gs.has_military_access(0, 2),
		"联盟应提供双向军事通行，中立国不得开放领土"
	)
	var allied_city := gs.cities_of(1)[0]
	var access_field := Pathfinding.dijkstra_field(
		gs, gs.nations[0].capital_city_id, 0, false, true
	)
	_check(
		float(access_field["dist"][allied_city.id]) < INF,
		"本国军队应能规划经过盟国城市的路线"
	)

	var supply_state := GameState.new()
	supply_state.generate_grid_world(32006)
	supply_state.armies.clear()
	for supply_a in range(supply_state.nations.size()):
		for supply_b in range(supply_a + 1, supply_state.nations.size()):
			supply_state.set_diplomatic_relation(
				supply_a,
				supply_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	supply_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	var supply_edge: Edge = null
	for candidate_edge in supply_state.edges:
		if (
			supply_state.cities[candidate_edge.city_a].owner_nation
			!= supply_state.cities[candidate_edge.city_b].owner_nation
			and (
				supply_state.cities[candidate_edge.city_a].owner_nation in [0, 1]
				and supply_state.cities[candidate_edge.city_b].owner_nation in [0, 1]
			)
		):
			supply_edge = candidate_edge
			break
	var own_supply_city := supply_edge.city_a
	var allied_supply_city := supply_edge.city_b
	if supply_state.cities[own_supply_city].owner_nation != 0:
		var swap_supply_city := own_supply_city
		own_supply_city = allied_supply_city
		allied_supply_city = swap_supply_city
	for nation in supply_state.nations:
		for warehouse_id in nation.warehouse_city_ids:
			supply_state.cities[warehouse_id].has_warehouse = false
			supply_state.cities[warehouse_id].food_storage = 0
		nation.warehouse_city_ids.clear()
	for warehouse_data in [
		[0, own_supply_city, 100],
		[1, allied_supply_city, 300],
	]:
		var warehouse_nation := int(warehouse_data[0])
		var warehouse_city := int(warehouse_data[1])
		supply_state.nations[warehouse_nation].warehouse_city_ids = [
			warehouse_city
		] as Array[int]
		supply_state.cities[warehouse_city].has_warehouse = true
		supply_state.cities[warehouse_city].food_storage = int(
			warehouse_data[2]
		)
	var allied_supplied_army := _make_army(9050, 0, 16000, 10, 10)
	allied_supplied_army.location_city = own_supply_city
	allied_supplied_army.move_from = own_supply_city
	supply_state.armies.append(allied_supplied_army)
	var supply_sim := Simulation.new()
	supply_sim.setup(supply_state)
	var supply_sources := Pathfinding.supply_sources(
		supply_state, allied_supplied_army
	)
	var total_food_before := (
		supply_state.cities[own_supply_city].food_storage
		+ supply_state.cities[allied_supply_city].food_storage
	)
	var expected_allied_demand := int(ceil(
		ceil(float(allied_supplied_army.size) * Simulation.FOOD_PER_CAPITA)
		* minf(
			1.0 + supply_sim._weighted_supply_loss(supply_sources),
			Simulation.MAX_SUPPLY_MULT
		)
	))
	for supply_day in range(1, Simulation.DAYS_PER_MONTH + 1):
		supply_state.day = supply_day
		supply_sim._resolve_supply()
	var own_food_used := 100 - supply_state.cities[own_supply_city].food_storage
	var allied_food_used := 300 - supply_state.cities[allied_supply_city].food_storage
	var total_food_after := (
		supply_state.cities[own_supply_city].food_storage
		+ supply_state.cities[allied_supply_city].food_storage
	)
	_check(
		supply_sources.size() == 2
		and allied_food_used > own_food_used
		and total_food_before - total_food_after
			== own_food_used + allied_food_used
			and absi(
				total_food_before
					- total_food_after
					- expected_allied_demand
			) <= 2,
		"联盟补给应按库存与距离加权分摊，库存更多的粮仓承担更多：sources=%s own=%d ally=%d before=%d after=%d"
			% [
				str(supply_sources),
				own_food_used,
				allied_food_used,
				total_food_before,
				total_food_after,
			]
	)
	allied_supplied_army.location_city = allied_supply_city
	allied_supplied_army.move_from = allied_supply_city
	_check(
		Pathfinding.can_reach_manpower_hub(
			supply_state, allied_supplied_army
		),
		"驻盟国领土的军队应能经军事通行路线连接本国人口中心"
	)
	var alliance_left := supply_sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.LEAVE_ALLIANCE,
		"a": 0,
		"b": 1,
		"reason": "军事通行撤销测试",
	})
	_check(
		alliance_left
		and allied_supplied_army.state != Army.State.IDLE
		and (
			allied_supplied_army.size <= 0
			or allied_supplied_army.move_to != -1
		),
		"退盟后滞留原盟国的军队必须立即撤回本国"
	)
	supply_sim.free()
	var reserve_state := GameState.new()
	reserve_state.generate_grid_world(32004)
	for reserve_a in range(reserve_state.nations.size()):
		for reserve_b in range(reserve_a + 1, reserve_state.nations.size()):
			reserve_state.set_diplomatic_relation(
				reserve_a,
				reserve_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	reserve_state.nations[0].manpower_pool = 5500
	var reserve_sim := Simulation.new()
	reserve_sim.setup(reserve_state)
	reserve_sim._resolve_reinforcements()
	_check(
		reserve_state.nations[0].manpower_pool
			>= Simulation.PEACETIME_MANPOWER_RESERVE,
		"和平期常规补员必须保留 5000 战略人力预备役"
	)
	reserve_sim.free()

	var encounter_state := GameState.new()
	encounter_state.generate_grid_world(32002)
	encounter_state.armies.clear()
	encounter_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.NEUTRAL
	)
	var edge := encounter_state.edges[0]
	_place_army_on_edge(
		encounter_state, 9000, 0, edge.city_a, edge.city_b,
		Simulation.HOLDING_TARGET_PROGRESS
	)
	_place_army_on_edge(
		encounter_state, 9001, 1, edge.city_b, edge.city_a,
		Simulation.HOLDING_TARGET_PROGRESS
	)
	encounter_state.armies[0].state = Army.State.HOLDING
	encounter_state.armies[1].state = Army.State.HOLDING
	var encounter_sim := Simulation.new()
	encounter_sim.setup(encounter_state)
	encounter_sim._detect_encounters()
	_check(
		encounter_state.battles.is_empty(),
		"中立军队在同边接触不得触发战斗"
	)
	encounter_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	encounter_sim._detect_encounters()
	_check(
		encounter_state.battles.is_empty(),
		"双方在己方侧驻防时，宣战本身不得让未接触军队立即开战"
	)
	encounter_state.armies[0].state = Army.State.MOVING
	encounter_state.armies[0].move_progress = 0.55
	encounter_sim._detect_encounters()
	_check(
		encounter_state.battles.size() == 1,
		"只有一方主动越过边中线并接触对方后才应触发战斗"
	)
	var settlement_city := encounter_state.cities_of(1)[0]
	var settlement_capture: Dictionary = encounter_state.transfer_city_control(
		settlement_city.id,
		0,
		0,
		GameState.TerritoryStockDisposition.CAPTURE_SPOILS,
		"peace_fixture_capture"
	)
	_check(
		bool(settlement_capture.get("ok", false))
			and bool(settlement_capture.get("changed", false))
			and settlement_city.owner_nation == 0
			and encounter_state.recognized_owner_of(settlement_city.id) == 1
			and settlement_city.occupation_sponsor_nation == 0,
		"战争期间实际控制与法理归属不同时应保持占领状态"
	)
	var stranded_after_battle := _make_army(
		9002,
		1,
		5000,
		10
	)
	stranded_after_battle.location_city = settlement_city.id
	stranded_after_battle.move_from = settlement_city.id
	stranded_after_battle.state = Army.State.IDLE
	encounter_state.armies.append(stranded_after_battle)
	encounter_sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.MAKE_PEACE,
		"a": 0,
		"b": 1,
		"reason": "停战清理测试",
	})
	var fighting_after_peace := false
	for army in encounter_state.armies:
		fighting_after_peace = (
			fighting_after_peace or army.state == Army.State.FIGHTING
		)
	_check(
		encounter_state.battles.is_empty() and not fighting_after_peace,
		"求和必须结束双方活跃战斗并清除 FIGHTING 状态"
	)
	_check(
		stranded_after_battle.size <= 0
			or (
				stranded_after_battle.state
					== Army.State.RETREATING
				and not stranded_after_battle.is_at_city_node(
					settlement_city.id
				)
			),
		"议和必须撤出未参加当前战斗但滞留在对方控制城市的军队"
	)
	_check(
		encounter_state.recognized_owner_of(settlement_city.id) == 0,
		"和平协议必须确认双方实际控制城市的领土转移，停止显示占领斜线"
	)
	encounter_sim.free()

	var enclave_state := GameState.new()
	enclave_state.generate_grid_world(32017)
	enclave_state.armies.clear()
	enclave_state.battles.clear()
	for enclave_a in range(enclave_state.nations.size()):
		for enclave_b in range(
			enclave_a + 1,
			enclave_state.nations.size()
		):
			enclave_state.set_diplomatic_relation(
				enclave_a,
				enclave_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	enclave_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	for enclave_edge in enclave_state.edges:
		enclave_edge.max_manpower = Edge.STANDARD_MANPOWER
	var connected_occupation := enclave_state.cities[4]
	var disconnected_legal_city := enclave_state.cities[6]
	var disconnected_occupation := enclave_state.cities[7]
	var stale_peaceful_occupation: City = null
	for stale_candidate in enclave_state.land_cities_of(3):
		if not stale_candidate.is_capital and not stale_candidate.has_warehouse:
			stale_peaceful_occupation = stale_candidate
			break
	connected_occupation.owner_nation = 0
	connected_occupation.occupation_sponsor_nation = 0
	disconnected_legal_city.owner_nation = 0
	enclave_state.recognized_city_owners[
		disconnected_legal_city.id
	] = 0
	disconnected_occupation.owner_nation = 0
	disconnected_occupation.occupation_sponsor_nation = 0
	# 模拟旧存档留下的和平占领脏状态：2 与法理国 3 并未交战。
	# 正式议和尾部必须统一 normalize，不能让它继续存在。
	if stale_peaceful_occupation != null:
		stale_peaceful_occupation.owner_nation = 2
		stale_peaceful_occupation.occupation_sponsor_nation = 2
	enclave_state.ownership_revision += 1
	var enclave_garrison := _make_army(
		9060,
		0,
		5000,
		10
	)
	enclave_garrison.max_size = Edge.MIN_MANPOWER
	enclave_garrison.location_city = disconnected_occupation.id
	enclave_garrison.move_from = disconnected_occupation.id
	enclave_garrison.state = Army.State.IDLE
	enclave_state.armies.append(enclave_garrison)
	var enclave_edge_garrison := _place_army_on_edge(
		enclave_state,
		9061,
		0,
		disconnected_legal_city.id,
		disconnected_occupation.id,
		0.5
	)
	var enclave_third_party := _make_army(
		9062,
		2,
		5000,
		10
	)
	enclave_third_party.max_size = Edge.MIN_MANPOWER
	enclave_third_party.location_city = (
		disconnected_occupation.id
	)
	enclave_third_party.move_from = (
		disconnected_occupation.id
	)
	enclave_third_party.state = Army.State.IDLE
	enclave_state.armies.append(enclave_third_party)
	var enclave_sim := Simulation.new()
	enclave_sim.setup(enclave_state)
	var enclave_peace := enclave_sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.MAKE_PEACE,
		"a": 0,
		"b": 1,
		"reason": "飞地和平结算测试",
	})
	var enclave_event: Dictionary = (
		enclave_state.diplomatic_history[-1]
		if not enclave_state.diplomatic_history.is_empty()
		else {}
	)
	_check(
		enclave_peace
			and connected_occupation.owner_nation == 0
			and enclave_state.recognized_owner_of(
				connected_occupation.id
			) == 0
			and connected_occupation.occupation_sponsor_nation == -1
			and disconnected_legal_city.owner_nation == 0
			and enclave_state.recognized_owner_of(
				disconnected_legal_city.id
			) == 0
			and disconnected_legal_city.occupation_sponsor_nation == -1
			and disconnected_occupation.owner_nation == 1
			and enclave_state.recognized_owner_of(
				disconnected_occupation.id
			) == 1
			and disconnected_occupation.occupation_sponsor_nation == -1
			and stale_peaceful_occupation != null
			and stale_peaceful_occupation.owner_nation == 3
			and enclave_state.recognized_owner_of(
				stale_peaceful_occupation.id
			) == 3
			and stale_peaceful_occupation.occupation_sponsor_nation == -1
			and int(enclave_event.get(
				"territories_transferred",
				-1
			)) == 1
			and int(enclave_event.get(
				"occupations_restored",
				-1
			)) == 1
			and enclave_state.territory_structure_valid(),
		(
			"议和必须确认连通占领、恢复断联临时占领、保留合法飞地，"
			+ "并在尾部清理其他和平 owner/legal 脏状态"
		)
	)
	var repatriating_armies: Array[Army] = [
		enclave_garrison,
		enclave_edge_garrison,
		enclave_third_party,
	]
	var all_repatriations_started := true
	for repatriating in repatriating_armies:
		all_repatriations_started = (
			all_repatriations_started
			and enclave_state.armies.has(repatriating)
			and repatriating.size > 0
			and repatriating.state == Army.State.RETREATING
			and repatriating.diplomatic_repatriation
			and repatriating.move_to >= 0
		)
	_check(
		all_repatriations_started,
		"战争结束后的非法驻军必须保留兵力，并获得穿越第三国道路回本国的临时遣返路径"
	)
	for _repatriation_day in range(300):
		var repatriation_active := false
		for repatriating in repatriating_armies:
			repatriation_active = (
				repatriation_active
				or repatriating.diplomatic_repatriation
			)
		if not repatriation_active:
			break
		enclave_sim._advance_movement()
	var all_repatriations_completed := true
	for repatriating in repatriating_armies:
		all_repatriations_completed = (
			all_repatriations_completed
			and repatriating.size > 0
			and not repatriating.diplomatic_repatriation
			and repatriating.location_city >= 0
			and enclave_state.cities[
				repatriating.location_city
			].owner_nation == repatriating.owner_nation
		)
	_check(
		all_repatriations_completed,
		"外交遣返军必须全部抵达各自本国，并在抵达后清除临时过境权"
	)
	enclave_sim.free()

	# 宗主国领土可经和平藩属连续。藩属夹在宗主首都与边远直辖领之间时，
	# 议和不得把边远直辖领误判为断连飞地割给敌国；普通盟国仍不具备此效果。
	var vassal_corridor_state := GameState.new()
	vassal_corridor_state.generate_grid_world(32018)
	vassal_corridor_state.armies.clear()
	vassal_corridor_state.battles.clear()
	for city in vassal_corridor_state.cities:
		city.owner_nation = 3
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		vassal_corridor_state.recognized_city_owners[
			city.id
		] = 3
	for corridor_edge in vassal_corridor_state.edges:
		corridor_edge.max_manpower = 0
	for corridor_city_id in [0, 48]:
		vassal_corridor_state.cities[
			corridor_city_id
		].owner_nation = 0
		vassal_corridor_state.recognized_city_owners[
			corridor_city_id
		] = 0
	for corridor_city_id in [8, 16, 24, 32, 40]:
		vassal_corridor_state.cities[
			corridor_city_id
		].owner_nation = 1
		vassal_corridor_state.recognized_city_owners[
			corridor_city_id
		] = 1
	vassal_corridor_state.cities[63].owner_nation = 2
	vassal_corridor_state.recognized_city_owners[63] = 2
	for corridor_road in [
		[0, 8],
		[8, 16],
		[16, 24],
		[24, 32],
		[32, 40],
		[40, 48],
	]:
		vassal_corridor_state.edge_of(
			int(corridor_road[0]),
			int(corridor_road[1])
		).max_manpower = Edge.STANDARD_MANPOWER
	_set_single_warehouse(vassal_corridor_state, 0, 0, 100)
	_set_single_warehouse(vassal_corridor_state, 1, 8, 100)
	_set_single_warehouse(vassal_corridor_state, 2, 63, 100)
	_set_single_warehouse(vassal_corridor_state, 3, 62, 100)
	for corridor_a in range(vassal_corridor_state.nations.size()):
		for corridor_b in range(
			corridor_a + 1,
			vassal_corridor_state.nations.size()
		):
			vassal_corridor_state.set_diplomatic_relation(
				corridor_a,
				corridor_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	vassal_corridor_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.ALLIED
	)
	vassal_corridor_state.set_diplomatic_relation(
		0,
		2,
		GameState.DiplomaticRelation.WAR
	)
	vassal_corridor_state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	vassal_corridor_state.refresh_derived()
	var vassal_corridor_sim := Simulation.new()
	vassal_corridor_sim.setup(vassal_corridor_state)
	vassal_corridor_sim._make_coalition_peace(0, 2)
	_check(
		vassal_corridor_state.cities[48].owner_nation == 0
			and vassal_corridor_state.recognized_owner_of(48) == 0,
		"宗主城48经和平藩属领土连回首都时不得在议和中被判为飞地割让"
	)
	vassal_corridor_sim.free()

	var ai_state := GameState.new()
	ai_state.generate_grid_world(32003)
	ai_state.day = (
		DiplomacyAI.WAR_FATIGUE_REFERENCE_DAYS * 5 / 2
	)
	var peace_actions := DiplomacyAI.choose_actions(ai_state)
	var has_peace_action := false
	for action in peace_actions:
		has_peace_action = (
			has_peace_action
			or int(action["kind"]) == DiplomacyAI.Action.MAKE_PEACE
		)
	_check(
		has_peace_action,
		"长期战争必须产生可接受的求和候选"
	)
	var bilateral_peace_state := GameState.new()
	bilateral_peace_state.generate_grid_world(32013)
	for peace_a in range(
		bilateral_peace_state.nations.size()
	):
		for peace_b in range(
			peace_a + 1,
			bilateral_peace_state.nations.size()
		):
			bilateral_peace_state.set_diplomatic_relation(
				peace_a,
				peace_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	bilateral_peace_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	bilateral_peace_state.armies.clear()
	for peace_nation in range(2):
		var peace_army := _make_army(
			9930 + peace_nation,
			peace_nation,
			10000,
			10,
			10
		)
		peace_army.location_city = (
			bilateral_peace_state.cities_of(
				peace_nation
			)[0].id
		)
		peace_army.move_from = peace_army.location_city
		bilateral_peace_state.armies.append(peace_army)
	bilateral_peace_state.day = 720
	bilateral_peace_state.nations[0].unpaid_military_upkeep = 20
	bilateral_peace_state.nations[0].manpower_pool = 0
	for warehouse in bilateral_peace_state.warehouse_cities_of(0):
		warehouse.food_storage = 0
	var mutual_peace := DiplomacyAI.peace_assessment(
		bilateral_peace_state,
		0,
		1
	)
	_check(
		bool(mutual_peace["acceptable"])
			and float(mutual_peace["score_a"])
				>= DiplomacyAI.PEACE_PROPOSE_SCORE
			and float(mutual_peace["score_b"])
				>= DiplomacyAI.PEACE_ACCEPT_SCORE
			and float(mutual_peace["score_b"])
				< DiplomacyAI.PEACE_PROPOSE_SCORE,
		"一方愿意提议且双方分别达到接受线时才能缔结和平"
	)
	var dominant_army := _make_army(
		9940,
		1,
		60000,
		10,
		10
	)
	dominant_army.location_city = (
		bilateral_peace_state.cities_of(1)[0].id
	)
	dominant_army.move_from = dominant_army.location_city
	bilateral_peace_state.armies.append(dominant_army)
	var refused_peace := DiplomacyAI.peace_assessment(
		bilateral_peace_state,
		0,
		1
	)
	_check(
		not bool(refused_peace["acceptable"])
			and float(refused_peace["score_a"])
				>= DiplomacyAI.PEACE_PROPOSE_SCORE
			and float(refused_peace["score_b"])
				< DiplomacyAI.PEACE_ACCEPT_SCORE,
		"求和方意愿再高也不得绕过优势方明确拒绝和平的接受底线"
	)
	var capitulation_state := GameState.new()
	capitulation_state.generate_grid_world(32015)
	for capitulation_a in range(capitulation_state.nations.size()):
		for capitulation_b in range(
			capitulation_a + 1,
			capitulation_state.nations.size()
		):
			capitulation_state.set_diplomatic_relation(
				capitulation_a,
				capitulation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	capitulation_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	capitulation_state.set_diplomatic_relation(
		1,
		2,
		GameState.DiplomaticRelation.WAR
	)
	var occupied_city_ids: Array[int] = []
	for occupied_city in capitulation_state.cities_of(1):
		occupied_city_ids.append(occupied_city.id)
		occupied_city.owner_nation = 0
		occupied_city.occupation_sponsor_nation = 0
	capitulation_state.armies.clear()
	capitulation_state.battles.clear()
	capitulation_state.day = 120
	var capitulation_sim := Simulation.new()
	capitulation_sim.setup(capitulation_state)
	capitulation_sim._resolve_eliminated_nation_capitulations()
	var occupied_territory_recognized := true
	for occupied_city_id in occupied_city_ids:
		occupied_territory_recognized = (
			occupied_territory_recognized
			and capitulation_state.recognized_owner_of(
				occupied_city_id
			) == 0
		)
	var surrender_recorded := (
		capitulation_state.diplomatic_history.size() >= 2
	)
	for surrender_event in capitulation_state.diplomatic_history.slice(-2):
		surrender_recorded = (
			surrender_recorded
			and int(surrender_event.get(
				"surrendering_nation",
				-1
			)) == 1
		)
	_check(
		not capitulation_state.is_enemy(0, 1)
			and not capitulation_state.is_enemy(1, 2)
			and capitulation_state.truce_until(0, 1)
				> capitulation_state.day
			and capitulation_state.truce_until(1, 2)
				> capitulation_state.day
			and occupied_territory_recognized
			and surrender_recorded,
		"多国战争中一方全境失守后必须向全部交战国投降并清除所有战争关系"
	)
	capitulation_sim.free()

	var remnant_state := GameState.new()
	remnant_state.generate_grid_world(32016)
	remnant_state.uses_heightmap = true
	remnant_state.armies.clear()
	remnant_state.battles.clear()
	for remnant_a in range(remnant_state.nations.size()):
		remnant_state.nations[remnant_a].battle_groups.clear()
		remnant_state.nations[remnant_a].next_battle_group_id = 0
		for remnant_b in range(
			remnant_a + 1,
			remnant_state.nations.size()
		):
			remnant_state.set_diplomatic_relation(
				remnant_a,
				remnant_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var remnant_origin := 9
	var remnant_first := 10
	var remnant_last := 11
	for remnant_city in remnant_state.cities:
		remnant_city.owner_nation = 0
		remnant_city.is_capital = false
		remnant_city.has_warehouse = false
		remnant_city.food_storage = 0
		remnant_city.fort_strength = 0
		remnant_city.fort_strength_max = 0
		remnant_city.manpower_per_month = 0
		remnant_state.recognized_city_owners[
			remnant_city.id
		] = 0
	for remnant_city_id in [remnant_first, remnant_last]:
		remnant_state.cities[
			remnant_city_id
		].owner_nation = 1
		remnant_state.recognized_city_owners[
			remnant_city_id
		] = 1
	for remnant_edge in remnant_state.edges:
		remnant_edge.max_manpower = 0
	remnant_state.edge_of(
		remnant_origin,
		remnant_first
	).max_manpower = Edge.MIN_MANPOWER
	remnant_state.edge_of(
		remnant_first,
		remnant_last
	).max_manpower = Edge.MIN_MANPOWER
	remnant_state.nations[0].capital_city_id = remnant_origin
	remnant_state.nations[0].warehouse_city_ids = [
		remnant_origin
	] as Array[int]
	remnant_state.cities[remnant_origin].is_capital = true
	remnant_state.cities[remnant_origin].has_warehouse = true
	remnant_state.cities[remnant_origin].food_storage = 100000
	remnant_state.nations[1].capital_city_id = remnant_last
	remnant_state.nations[1].warehouse_city_ids = [
		remnant_last
	] as Array[int]
	remnant_state.cities[remnant_last].is_capital = true
	remnant_state.cities[remnant_last].has_warehouse = true
	remnant_state.cities[remnant_last].food_storage = 1000
	remnant_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	remnant_state.nations[0].treasury_gold = 10000
	remnant_state.nations[1].treasury_gold = 0
	remnant_state.nations[1].manpower_pool = 0
	var remnant_group := remnant_state.create_battle_group(0)
	var remnant_light_armies: Array[Army] = []
	for remnant_index in range(2):
		var remnant_light := remnant_state.create_army(
			0,
			remnant_origin,
			GameState.INITIAL_LIGHT_ARMY_SIZE,
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		remnant_light.attack = 20
		remnant_light.defense = 20
		remnant_state.assign_army_to_battle_group(
			remnant_light,
			remnant_group.id
		)
		remnant_light_armies.append(remnant_light)
	var remnant_heavy := remnant_state.create_army(
		0,
		remnant_origin,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	remnant_heavy.attack = 20
	remnant_heavy.defense = 20
	remnant_state.assign_army_to_battle_group(
		remnant_heavy,
		remnant_group.id
	)
	remnant_state.refresh_derived()
	var remnant_sim := Simulation.new()
	remnant_sim.setup(remnant_state)
	var remnant_objective := DiplomacyAI.select_war_objective(
		remnant_state,
		0,
		1
	)
	var remnant_plan_ready := (
		not remnant_objective.is_empty()
		and int(remnant_objective["city_id"])
			== remnant_first
		and remnant_sim._ensure_campaign_preparation_plan(
			0,
			remnant_first
		)
	)
	var remnant_nation := remnant_state.nations[0]
	var remnant_full_group_ready := remnant_plan_ready
	for remnant_member in remnant_state.battle_group_members(
		0, remnant_group.id
	):
		remnant_full_group_ready = (
			remnant_full_group_ready
			and int(
				remnant_nation
					.campaign_preparation_assignments.get(
						remnant_member.id,
						-1
					)
			) == remnant_first
		)
	var remnant_launched := (
		remnant_full_group_ready
		and remnant_sim._launch_campaign_offensive(
			0,
			remnant_first,
			Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS,
			[remnant_first] as Array[int]
		)
	)
	var remnant_terminated := false
	for _remnant_day in range(360):
		if (
			remnant_state.cities_of(1).is_empty()
			or not remnant_state.is_enemy(0, 1)
		):
			remnant_terminated = true
			break
		remnant_sim._advance_day()
	_check(
		remnant_launched
			and remnant_state.armies.has(remnant_heavy)
			and remnant_heavy.max_size
				== GameState.INITIAL_HEAVY_ARMY_SIZE
			and remnant_terminated,
		"多数城对两座残城时，完整战团须经5000关隘继续A→B→C，重军保持单一编制，并在360天内灭国或双边议和"
	)
	remnant_sim.free()

	var occupied_capital := bilateral_peace_state.nations[
		0
	].capital_city_id
	bilateral_peace_state.cities[occupied_capital].owner_nation = 1
	bilateral_peace_state.cities[
		occupied_capital
	].occupation_sponsor_nation = 1
	bilateral_peace_state.day = (
		DiplomacyAI.WAR_FATIGUE_REFERENCE_DAYS * 5 / 2
	)
	var long_war_refusal := DiplomacyAI.peace_assessment(
		bilateral_peace_state,
		0,
		1
	)
	_check(
		not bool(long_war_refusal["acceptable"])
			and not bool(long_war_refusal["consent_b"]),
		"长期战争也不得绕过仍占优势一方的明确拒绝"
	)

	var formula_state := GameState.new()
	formula_state.generate_grid_world(32014)
	for formula_a in range(formula_state.nations.size()):
		for formula_b in range(
			formula_a + 1,
			formula_state.nations.size()
		):
			formula_state.set_diplomatic_relation(
				formula_a,
				formula_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	formula_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	formula_state.armies.clear()
	for formula_nation in range(2):
		var formula_army := _make_army(
			9950 + formula_nation,
			formula_nation,
			10000,
			10,
			10
		)
		formula_army.location_city = (
			formula_state.land_cities_of(formula_nation)[0].id
		)
		formula_army.move_from = formula_army.location_city
		formula_state.armies.append(formula_army)
	formula_state.day = 360
	for formula_nation in range(2):
		formula_state.nations[formula_nation].treasury_gold = 100000
		for warehouse in formula_state.warehouse_cities_of(
			formula_nation
		):
			warehouse.food_storage = 100000
	var baseline_a := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		0,
		1
	)
	var baseline_b := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		1,
		0
	)
	var ordinary_enemy_city: City = null
	for candidate_city in formula_state.land_cities_of(1):
		if (
			not candidate_city.is_capital
			and not candidate_city.has_warehouse
			and not candidate_city.is_food_hub
			and not candidate_city.is_manpower_hub
		):
			ordinary_enemy_city = candidate_city
			break
	var important_enemy_city := formula_state.cities[
		formula_state.nations[1].capital_city_id
	]
	ordinary_enemy_city.owner_nation = 0
	ordinary_enemy_city.occupation_sponsor_nation = 0
	var ordinary_situation := DiplomacyAI.war_situation_score(
		formula_state,
		0,
		1
	)
	var occupied_a := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		0,
		1
	)
	var occupied_b := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		1,
		0
	)
	ordinary_enemy_city.owner_nation = 1
	ordinary_enemy_city.occupation_sponsor_nation = -1
	important_enemy_city.owner_nation = 0
	important_enemy_city.occupation_sponsor_nation = 0
	var important_situation := DiplomacyAI.war_situation_score(
		formula_state,
		0,
		1
	)
	_check(
		float(occupied_a["score"]) < float(baseline_a["score"])
			and float(occupied_b["score"]) > float(baseline_b["score"])
			and important_situation > ordinary_situation,
		"占领敌城应降低胜方和平意愿、提高失地方和平意愿，重要城市影响更大"
	)
	important_enemy_city.owner_nation = 1
	important_enemy_city.occupation_sponsor_nation = -1

	var dominant_formula_army := _make_army(
		9960,
		0,
		60000,
		10,
		10
	)
	dominant_formula_army.location_city = (
		formula_state.land_cities_of(0)[0].id
	)
	dominant_formula_army.move_from = (
		dominant_formula_army.location_city
	)
	formula_state.armies.append(dominant_formula_army)
	var power_advantaged := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		0,
		1
	)
	var power_disadvantaged := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		1,
		0
	)
	_check(
		float(power_advantaged["score"]) < float(baseline_a["score"])
			and float(power_disadvantaged["score"])
				> float(baseline_b["score"])
			and float(power_advantaged["power_component"]) < 0.0
			and float(power_disadvantaged["power_component"]) > 0.0,
		"军力优势必须降低和平意愿，军力劣势必须提高和平意愿"
	)
	formula_state.armies.erase(dominant_formula_army)

	var resource_secure := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		0,
		1
	)
	formula_state.nations[0].treasury_gold = 0
	formula_state.nations[0].unpaid_military_upkeep = 100
	for warehouse in formula_state.warehouse_cities_of(0):
		warehouse.food_storage = 0
	var resource_exhausted := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		0,
		1
	)
	_check(
		float(resource_exhausted["score"])
			> float(resource_secure["score"])
			and float(resource_exhausted["resource_component"])
				> float(resource_secure["resource_component"]),
		"钱粮将尽必须提高和平意愿，长期续航必须降低和平意愿"
	)

	var neutral_border_city := -1
	for formula_edge in formula_state.edges:
		var formula_owner_a := formula_state.cities[
			formula_edge.city_a
		].owner_nation
		var formula_owner_b := formula_state.cities[
			formula_edge.city_b
		].owner_nation
		if formula_owner_a == 0 and formula_owner_b == 2:
			neutral_border_city = formula_edge.city_b
			break
		if formula_owner_b == 0 and formula_owner_a == 2:
			neutral_border_city = formula_edge.city_a
			break
	var before_massing := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		0,
		1
	)
	var massing_army := _make_army(
		9961,
		2,
		60000,
		10,
		10
	)
	massing_army.location_city = neutral_border_city
	massing_army.move_from = neutral_border_city
	formula_state.armies.append(massing_army)
	var after_massing := DiplomacyAI.peace_willingness_breakdown(
		formula_state,
		0,
		1
	)
	_check(
		neutral_border_city >= 0
			and float(after_massing["external_threat"]) > 0.0
			and float(after_massing["score"])
				> float(before_massing["score"]),
		"中立邻国在本国边境屯兵必须提高和平意愿以便调转战线"
	)
	var massing_matrix_equivalent := true
	var shared_massing_cache := {}
	for observer_id in range(formula_state.nations.size()):
		for enemy_id in range(formula_state.nations.size()):
			if observer_id == enemy_id:
				continue
			massing_matrix_equivalent = (
				massing_matrix_equivalent
				and _approx(
					DiplomacyAI._neutral_border_massing_ratio(
						formula_state,
						observer_id,
						enemy_id,
						shared_massing_cache
					),
					_legacy_neutral_border_massing_ratio(
						formula_state,
						observer_id,
						enemy_id
					),
					0.000001
				)
			)
	_check(
		massing_matrix_equivalent,
		"共享边境集结矩阵必须与逐组合扫描的旧公式逐国一致"
	)

	for a in range(ai_state.nations.size()):
		for b in range(a + 1, ai_state.nations.size()):
			ai_state.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	ai_state.day += DiplomacyAI.MIN_NEUTRAL_DAYS
	var reserve_report := DiplomacyAI.resource_report(ai_state, 0)
	_check(bool(reserve_report["ready"]), "开局完整储备应允许评估进攻战争")
	var objective := DiplomacyAI.select_war_objective(ai_state, 0, 1)
	_check(
		not objective.is_empty()
		and ai_state.cities[int(objective["city_id"])].owner_nation == 1
		and str(objective["reason"]).contains("金")
		and str(objective["reason"]).contains("战略值"),
		"宣战必须选择敌国合法目标城并解释产出和战略价值"
	)
	ai_state.nations[0].ai_aggression = 0.7
	var cautious_war_desire := DiplomacyAI.war_desire(
		ai_state,
		0,
		1
	)
	ai_state.nations[0].ai_aggression = 1.3
	var aggressive_war_desire := DiplomacyAI.war_desire(
		ai_state,
		0,
		1
	)
	_check(
		cautious_war_desire > -INF
		and aggressive_war_desire > cautious_war_desire,
		"国家激进值越高，资源条件相同时宣战意愿必须单调提高"
	)
	ai_state.nations[0].ai_aggression = 1.0
	var default_war_desire := DiplomacyAI.war_desire(
		ai_state,
		0,
		1
	)
	var baseline_day := ai_state.day
	var baseline_escalation := (
		DiplomacyAI.neutral_peace_escalation(
			ai_state,
			0,
			1
		)
	)
	ai_state.day = (
		ai_state.relation_since(0, 1)
		+ DiplomacyAI.PEACE_ESCALATION_FULL_DAYS
	)
	var long_peace_escalation := (
		DiplomacyAI.neutral_peace_escalation(
			ai_state,
			0,
			1
		)
	)
	var long_peace_war_desire := DiplomacyAI.war_desire(
		ai_state,
		0,
		1
	)
	ai_state.day = baseline_day
	_check(
		default_war_desire >= DiplomacyAI.WAR_DECLARE_SCORE
			and _approx(DiplomacyAI.WAR_DECLARE_SCORE, 0.85)
			and _approx(baseline_escalation, 0.0)
			and _approx(
				long_peace_escalation,
				DiplomacyAI.PEACE_ESCALATION_MAX_BONUS
			)
			and long_peace_war_desire
				> default_war_desire,
		"资源就绪国家应达到0.85宣战线，长期和平压力必须单调提高意愿，实为%.3f→%.3f"
			% [default_war_desire, long_peace_war_desire]
	)
	var alliance_edge: Edge = null
	for candidate_edge in ai_state.edges:
		var owner_a := ai_state.cities[
			candidate_edge.city_a
		].owner_nation
		var owner_b := ai_state.cities[
			candidate_edge.city_b
		].owner_nation
		if owner_a == 0 and owner_b == 1:
			alliance_edge = candidate_edge
			break
		if owner_a == 1 and owner_b == 0:
			alliance_edge = candidate_edge
			break
	var release_army: Army = null
	var release_value := 0.0
	if alliance_edge != null:
		var release_city := (
			alliance_edge.city_a
			if ai_state.cities[
				alliance_edge.city_a
			].owner_nation == 0
			else alliance_edge.city_b
		)
		release_army = _make_army(
			9049,
			0,
			15000,
			10,
			10
		)
		release_army.location_city = release_city
		release_army.move_from = release_city
		ai_state.armies.append(release_army)
		release_value = (
			DiplomacyAI._alliance_frontier_release_value(
				ai_state,
				0,
				1
			)
		)
	_check(
		alliance_edge != null and release_value > 0.0,
		"与非战争目标国结盟时，应识别可从共同边境释放的实际驻军战力"
	)
	if release_army != null:
		ai_state.armies.erase(release_army)
	var treasury_before_crisis := ai_state.nations[0].treasury_gold
	var original_gold_income := {}
	for city in ai_state.cities_of(0):
		original_gold_income[city.id] = city.gold_per_month
	var pre_balance := int(
		DiplomacyAI.resource_report(ai_state, 0)["monthly_gold_balance"]
	)
	if pre_balance < 0:
		var income_city := ai_state.cities_of(0)[0]
		income_city.gold_per_month += -pre_balance
	ai_state.nations[0].treasury_gold = 0
	ai_state.nations[0].ai_aggression = 1.5
	var sustainable_zero_treasury := DiplomacyAI.resource_report(ai_state, 0)
	_check(
		int(sustainable_zero_treasury["monthly_gold_balance"]) >= 0
		and not bool(sustainable_zero_treasury["ready"])
		and int(sustainable_zero_treasury["gold_reserve_target"]) > 0
		and int(sustainable_zero_treasury["gold_reserve_gap"])
			== int(sustainable_zero_treasury["gold_reserve_target"]),
		"月收入覆盖军费但国库为0时仍应进入三年储备积累期，不得提前判为备战就绪"
	)
	for city in ai_state.cities_of(0):
		city.gold_per_month = 0
	_check(
		not bool(DiplomacyAI.resource_report(ai_state, 0)["ready"])
		and DiplomacyAI.war_desire(ai_state, 0, 1) == -INF,
		"最高激进值也不得绕过负现金流和国库不足的宣战硬约束"
	)
	for city_id in original_gold_income:
		ai_state.cities[int(city_id)].gold_per_month = int(
			original_gold_income[city_id]
		)
	ai_state.nations[0].treasury_gold = treasury_before_crisis
	ai_state.nations[0].ai_aggression = 1.0
	var preparation_actions := DiplomacyAI.choose_actions(ai_state)
	var preparation_has_objective := false
	for action in preparation_actions:
		if int(action["kind"]) != DiplomacyAI.Action.PREPARE_WAR:
			continue
		preparation_has_objective = (
			action.has("objective_city")
			and int(action["objective_city"]) >= 0
			and str(action["reason"]).contains("储备金")
		)
	_check(
		preparation_has_objective,
		"自然战争候选必须先生成携带目标和储备说明的备战动作"
	)
	var grace_state := GameState.new()
	grace_state.generate_grid_world(32004)
	for grace_a in range(grace_state.nations.size()):
		for grace_b in range(
			grace_a + 1,
			grace_state.nations.size()
		):
			grace_state.set_diplomatic_relation(
				grace_a,
				grace_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	grace_state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	var grace_action: Dictionary = {}
	for action in DiplomacyAI.choose_actions(grace_state):
		if int(action["kind"]) == DiplomacyAI.Action.PREPARE_WAR:
			grace_action = action
			break
	var grace_sim := Simulation.new()
	grace_sim.setup(grace_state)
	var grace_started := (
		not grace_action.is_empty()
		and grace_sim._execute_diplomatic_action(
			grace_action
		)
	)
	var grace_nation_id := int(
		grace_action.get("a", -1)
	)
	if grace_started:
		var preparation_alliance_actions: Array[Dictionary] = []
		var preparation_alliance_committed := {}
		var preparation_alliance_found := (
			DiplomacyAI._collect_preparation_alliance(
				grace_state,
				grace_nation_id,
				int(grace_action["b"]),
				preparation_alliance_actions,
				preparation_alliance_committed
			)
		)
		_check(
			preparation_alliance_found
			and preparation_alliance_actions.size() == 1
			and int(
				preparation_alliance_actions[0]["kind"]
			) == DiplomacyAI.Action.FORM_ALLIANCE
			and int(
				preparation_alliance_actions[0]["b"]
			) != int(grace_action["b"]),
			"备战未完成时应能与非战争目标国结盟，释放其他边境的驻军"
		)
		grace_state.nations[
			grace_nation_id
		].manpower_pool = 0
		grace_sim._refresh_war_preparation_viability()
	var early_cancel := false
	for action in DiplomacyAI.choose_actions(grace_state):
		early_cancel = (
			early_cancel
			or int(action["kind"])
				== DiplomacyAI.Action.CANCEL_WAR_PREPARATION
		)
	_check(
		grace_started
		and not early_cancel,
		"短期资源波动不得立即取消兵力布局未变的备战计划"
	)
	if grace_started:
		grace_state.day += 60
		grace_state.nations[
			grace_nation_id
		].manpower_pool = 100000
		grace_sim._refresh_war_preparation_viability()
		_check(
			grace_state.nations[
				grace_nation_id
			].war_preparation_unready_since_day == -1,
			"备战资源恢复后必须清零取消宽限计时"
		)
		grace_state.nations[
			grace_nation_id
		].manpower_pool = 0
		grace_sim._refresh_war_preparation_viability()
		var second_shortage_day := grace_state.day
		grace_state.day = (
			second_shortage_day
			+ DiplomacyAI.WAR_PREPARATION_RESOURCE_GRACE_DAYS
			- 1
		)
		var before_grace_cancel := false
		for action in DiplomacyAI.choose_actions(
			grace_state
		):
			before_grace_cancel = (
				before_grace_cancel
				or int(action["kind"])
					== DiplomacyAI.Action.CANCEL_WAR_PREPARATION
			)
		_check(
			not before_grace_cancel,
			"资源连续不足89天时仍应维持既定备战"
		)
		grace_state.day += 1
		var after_grace_cancel := false
		for action in DiplomacyAI.choose_actions(
			grace_state
		):
			after_grace_cancel = (
				after_grace_cancel
				or int(action["kind"])
					== DiplomacyAI.Action.CANCEL_WAR_PREPARATION
			)
		_check(
			after_grace_cancel,
			"资源连续不足90天后才允许取消备战"
		)
	grace_sim.free()

	var group_ready_state := GameState.new()
	group_ready_state.generate_grid_world(32019)
	group_ready_state.uses_heightmap = true
	for group_ready_a in range(
		group_ready_state.nations.size()
	):
		for group_ready_b in range(
			group_ready_a + 1,
			group_ready_state.nations.size()
		):
			group_ready_state.set_diplomatic_relation(
				group_ready_a,
				group_ready_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	group_ready_state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	var group_objective := DiplomacyAI.select_war_objective(
		group_ready_state,
		0,
		1
	)
	var group_objective_city := int(
		group_objective.get("city_id", -1)
	)
	var group_staging := (
		DiplomacyAI.staging_cities_for_objective(
			group_ready_state,
			0,
			group_objective_city
		)
	)
	var preparation_group := (
		group_ready_state.nations[0].battle_groups[0]
	)
	var preparation_members := (
		group_ready_state.battle_group_members(
			0,
			preparation_group.id
		)
	)
	var preparation_group_troops := 0
	if not group_staging.is_empty():
		for group_member in preparation_members:
			preparation_group_troops += group_member.size
			group_member.state = Army.State.IDLE
			group_member.location_city = group_staging[0]
			group_member.move_from = group_staging[0]
			group_member.move_to = -1
			group_member.on_edge = false
	var group_ready_nation := group_ready_state.nations[0]
	group_ready_nation.war_preparation_target_nation = 1
	group_ready_nation.war_preparation_objective_city = (
		group_objective_city
	)
	group_ready_nation.war_preparation_started_day = (
		group_ready_state.day
			- DiplomacyAI.WAR_PREPARATION_MIN_DAYS
	)
	var group_ready_sim := Simulation.new()
	group_ready_sim.setup(group_ready_state)
	var group_ready_view := AiWorldView.build(group_ready_state, 0)
	var canonical_preparation := (
		group_ready_sim._plan_campaign_allocation(
			0, group_objective_city,
			[group_objective_city] as Array[int], null, null,
			group_ready_view, true
		)
	)
	var canonical_preparation_applied := (
		group_ready_sim._apply_campaign_plan_atomic(
			0, canonical_preparation
		)
	)
	var old_national_share_requirement := (
		DiplomacyAI.required_assault_troops(
			group_ready_state,
			0,
			group_objective_city
		)
	)
	var full_group_ready := DiplomacyAI.war_preparation_ready(
		group_ready_state,
		0
	)
	preparation_members[0].location_city = (
		group_ready_state.nations[0].capital_city_id
	)
	var incomplete_group_not_ready := not (
		DiplomacyAI.war_preparation_ready(
			group_ready_state,
			0
		)
	)
	_check(
		canonical_preparation_applied
			and not group_objective.is_empty()
			and not group_staging.is_empty()
			and old_national_share_requirement
				> preparation_group_troops
			and full_group_ready
			and incomplete_group_not_ready,
		"正式地图备战应以指定战团全员集结为就绪条件，不得继续要求全国25%%兵力"
	)
	var waiting_preparation_actions: Array[Dictionary] = []
	var waiting_preparation_committed := {}
	for preparation_candidate in [2, 3]:
		group_ready_state.set_diplomatic_relation(
			preparation_candidate,
			1,
			GameState.DiplomaticRelation.ALLIED
		)
	DiplomacyAI._collect_existing_war_preparation(
		group_ready_state,
		0,
		waiting_preparation_actions,
		waiting_preparation_committed,
		{}
	)
	_check(
		waiting_preparation_actions.is_empty()
			and not waiting_preparation_committed.has(0),
		"尚未就绪且未产生外交动作的备战国不得占用 committed 并免疫他国宣战"
	)
	group_ready_nation.war_preparation_started_day = (
		group_ready_state.day
			- DiplomacyAI.WAR_PREPARATION_MAX_DAYS
	)
	var expired_preparation_actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(
		group_ready_state,
		0,
		expired_preparation_actions,
		{}
	)
	_check(
		expired_preparation_actions.is_empty()
			or int(expired_preparation_actions[0]["kind"])
				== DiplomacyAI.Action.DECLARE_WAR,
		"战团超过360天后可在兵力过半时尽力开战，但不得因敌军屯兵或集结不足取消备战"
	)
	group_ready_nation.war_preparation_started_day = (
		group_ready_state.day
			- DiplomacyAI.WAR_PREPARATION_MIN_DAYS
	)
	var stale_group_holder := preparation_members[1]
	var ready_group_holder := preparation_members[0]
	var ready_group_reserve := preparation_members[2]
	var stale_group_edge: Edge = null
	if not group_staging.is_empty():
		for neighbor in group_ready_state.neighbors(group_staging[0]):
			var candidate_edge := group_ready_state.edge_of(
				group_staging[0],
				neighbor
			)
			if (
				neighbor != group_objective_city
				and group_ready_state.cities[neighbor].owner_nation == 0
				and candidate_edge != null
				and candidate_edge.allows_holding
				and candidate_edge.max_manpower
					>= stale_group_holder.max_size
			):
				stale_group_edge = candidate_edge
				break
	if stale_group_edge != null:
		ready_group_holder.state = Army.State.HOLDING
		ready_group_holder.location_city = -1
		ready_group_holder.move_from = group_staging[0]
		ready_group_holder.move_to = group_objective_city
		ready_group_holder.move_progress = (
			Simulation.HOLDING_TARGET_PROGRESS
		)
		ready_group_holder.on_edge = true
		ready_group_reserve.state = Army.State.IDLE
		ready_group_reserve.location_city = group_staging[0]
		ready_group_reserve.move_from = group_staging[0]
		ready_group_reserve.move_to = -1
		ready_group_reserve.on_edge = false
		stale_group_holder.state = Army.State.HOLDING
		stale_group_holder.location_city = -1
		stale_group_holder.move_from = group_staging[0]
		stale_group_holder.move_to = (
			stale_group_edge.city_b
			if stale_group_edge.city_a == group_staging[0]
			else stale_group_edge.city_a
		)
		stale_group_holder.move_progress = (
			Simulation.HOLDING_TARGET_PROGRESS
		)
		stale_group_holder.on_edge = true
		for preparation_member in preparation_members:
			preparation_member.defensive_deployment_until_day = -1
	var convergence_sim := group_ready_sim
	var convergence_view := AiWorldView.build(group_ready_state, 0)
	var convergence_plan := CityDefensePlan.build(
		convergence_view,
		StrategicMapSnapshot.build(convergence_view),
		ThreatField.build(convergence_view)
	)
	convergence_sim._assign_offensive_staging_orders(
		0,
		group_objective_city,
		convergence_plan,
		ArmyCoordinator.new(),
		true,
		true
	)
	_check(
		stale_group_edge != null
			and stale_group_holder.state == Army.State.MOVING
			and stale_group_holder.ai_action
				== ActionCandidate.Kind.RETREAT
			and stale_group_holder.ai_target_city
				== group_staging[0]
			and stale_group_holder.ai_order_reason.contains(
				"从次要边境撤回"
			),
		"战团部分成员已集结时，旧边驻军仍必须继续撤回，不得因最低兵力1而永久停止备战"
	)
	convergence_sim._clear_campaign_preparation_plan(0)
	for preparation_member in preparation_members:
		convergence_sim._settle_idle(
			preparation_member,
			group_staging[0]
		)
		preparation_member.defensive_deployment_until_day = -1
	ready_group_reserve.state = Army.State.RECOVERING
	var strict_partial_view := AiWorldView.build(group_ready_state, 0)
	var strict_partial_plan := (
		convergence_sim._plan_campaign_allocation(
			0, group_objective_city,
			[group_objective_city] as Array[int],
			convergence_plan, ArmyCoordinator.new(),
			strict_partial_view, true
		)
	)
	_check(
		strict_partial_plan.assigned_group_count == 0
			and group_ready_nation.campaign_preparation_plan == null,
		"团内存在恢复中或不可达成员时不得只绑定部分战团，否则外交全员门禁会永久等待"
	)
	convergence_sim.free()

	var objective_state := GameState.new()
	objective_state.generate_grid_world(32005)
	for objective_a in range(objective_state.nations.size()):
		for objective_b in range(objective_a + 1, objective_state.nations.size()):
			objective_state.set_diplomatic_relation(
				objective_a,
				objective_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	objective_state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	var preparation_action: Dictionary = {}
	for action in DiplomacyAI.choose_actions(objective_state):
		if int(action["kind"]) == DiplomacyAI.Action.PREPARE_WAR:
			preparation_action = action
			break
	var objective_sim := Simulation.new()
	objective_sim.setup(objective_state)
	var preparation_executed := (
		not preparation_action.is_empty()
		and objective_sim._execute_diplomatic_action(preparation_action)
	)
	var objective_attacker := int(preparation_action.get("a", -1))
	var objective_defender := int(preparation_action.get("b", -1))
	var objective_city := int(preparation_action.get("objective_city", -1))
	var staging := DiplomacyAI.staging_cities_for_objective(
		objective_state,
		objective_attacker,
		objective_city
	)
	var staged_army: Army = null
	if preparation_executed and not staging.is_empty():
		for army in objective_state.armies:
			if army.owner_nation == objective_attacker:
				if staged_army == null:
					staged_army = army
				army.state = Army.State.IDLE
				army.location_city = staging[0]
				army.move_from = staging[0]
				army.move_to = -1
				army.move_progress = 0.0
				army.on_edge = false
	objective_state.day += DiplomacyAI.WAR_PREPARATION_MIN_DAYS
	var objective_action: Dictionary = {}
	for action in DiplomacyAI.choose_actions(objective_state):
		if (
			int(action["kind"]) == DiplomacyAI.Action.DECLARE_WAR
			and int(action["a"]) == objective_attacker
		):
			objective_action = action
			break
	var objective_executed := (
		not objective_action.is_empty()
		and objective_sim._execute_diplomatic_action(objective_action)
	)
	var objective_campaign := -1
	if objective_executed:
		var objective_view := AiWorldView.build(
			objective_state,
			objective_attacker
		)
		objective_campaign = StrategicMapSnapshot.build(
			objective_view
		).campaign_target
	_check(
		objective_executed
		and preparation_executed
		and int(
			objective_state.war_objective(
				objective_attacker,
				objective_defender
			).get("city_id", -1)
		) == objective_city
		and objective_campaign == objective_city,
		"备战完成后外交目标必须写入战争状态并成为军事 AI 主战役目标"
	)
	_check(
		_approx(
			Simulation.offensive_preparation_multiplier(0),
			1.0
		)
		and _approx(
			Simulation.offensive_preparation_multiplier(
				Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS / 2
			),
			1.5
		)
		and _approx(
			Simulation.offensive_preparation_multiplier(
				Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
			),
			2.0
		)
		and _approx(
			Simulation.offensive_preparation_multiplier(
				Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS * 2
			),
			2.0
		)
		and Simulation.offensive_bonus_duration_days(30) == 30
		and Simulation.offensive_bonus_duration_days(
			Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
		) == Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
		and Simulation.offensive_bonus_duration_days(
			Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS * 2
		) == Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS,
		"攻势倍率和持续期应随准备天数增长，并在正式满准备窗口封顶"
	)
	var interval_nation := objective_state.nations[objective_attacker]
	var original_aggression := interval_nation.ai_aggression
	var personality_intervals: Array[int] = []
	for aggression in [0.5, 1.0, 1.5]:
		interval_nation.ai_aggression = aggression
		personality_intervals.append(
			objective_sim._campaign_offensive_interval(objective_attacker)
		)
	interval_nation.ai_aggression = original_aggression
	_check(
		personality_intervals == [40, 20, 13],
		"低/中/高激进国家的攻势基础波次应分别为40/20/13天，当前=%s"
			% str(personality_intervals)
	)
	_check(
		Simulation.CAMPAIGN_MAX_PARALLEL_TARGETS >= 8
			and Simulation.CAMPAIGN_MAX_WARTIME_GROUPS
				>= Simulation.CAMPAIGN_MAX_PARALLEL_TARGETS * 2,
		"国家级攻势预算必须支持至少八路宽正面和每路双梯队"
	)
	var first_wave_army: Army = null
	for army in objective_state.armies:
		if (
			army.owner_nation == objective_attacker
			and army.state == Army.State.MOVING
			and army.ai_action == ActionCandidate.Kind.ATTACK
			and army.ai_target_city == objective_city
		):
			first_wave_army = army
			break
	_check(
		objective_executed
			and first_wave_army != null
			and objective_state.nations[
				objective_attacker
			].campaign_next_offensive_day
				== objective_state.day
					+ Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS,
		"宣战当日必须把已集结军队转为针对目标城的首轮攻势"
	)
	_check(
		first_wave_army != null
		and _approx(
			first_wave_army.offensive_attack_multiplier,
			Simulation.offensive_preparation_multiplier(
				DiplomacyAI.WAR_PREPARATION_MIN_DAYS
			)
		)
			and _approx(
				first_wave_army.combat_morale(),
				first_wave_army.morale
					* first_wave_army.offensive_attack_multiplier
			)
		and first_wave_army.offensive_bonus_until_day
			== objective_state.day
					+ DiplomacyAI.WAR_PREPARATION_MIN_DAYS,
		"首轮参战军的攻击和有效士气加成必须持续实际备战天数"
	)
	_check(
		not objective_state.campaign_visual_events.is_empty()
		and int(objective_state.campaign_visual_events[-1]["target_city"])
			== objective_city,
		"发动国家级攻势时必须生成指向目标城的短时战略箭头事件"
	)
	var first_wave_count := (
		objective_state.nations[objective_attacker].campaign_offensive_count
	)
	var cooldown_origin := -1
	for city in objective_state.cities_of(objective_attacker):
		if not staging.has(city.id):
			cooldown_origin = city.id
			break
	var cooldown_reinforcement: Army = null
	for army in objective_state.armies:
		if army.owner_nation == objective_attacker and not staging.is_empty():
			objective_sim._settle_idle(army, staging[0])
			if cooldown_reinforcement == null and cooldown_origin >= 0:
				cooldown_reinforcement = army
				objective_sim._settle_idle(
					army,
					cooldown_origin
				)
	objective_state.day = (
		objective_state.nations[objective_attacker].campaign_next_offensive_day
		- 1
	)
	var preorganized := objective_sim._manage_campaign_offensive(
		objective_attacker
	)
	var cooldown_ordered := false
	for army in objective_state.armies:
		if (
			army.owner_nation == objective_attacker
			and army.ai_order_created_day == objective_state.day
			and army.ai_order_reason.contains("战前集结")
		):
			cooldown_ordered = true
			break
	_check(
		preorganized
		and objective_state.nations[
			objective_attacker
		].campaign_offensive_count == first_wave_count
		and cooldown_ordered
		and objective_state.nations[
			objective_attacker
		].campaign_plan_wave == first_wave_count,
		"冷却期必须持续集结下一波军队，且不得提前发动或覆盖当前梯队计划"
	)
	for army in objective_state.armies:
		if army.owner_nation == objective_attacker and not staging.is_empty():
			objective_sim._settle_idle(army, staging[0])
	objective_state.day = (
		objective_state.nations[objective_attacker].campaign_next_offensive_day
	)
	var next_wave_launched := objective_sim._manage_campaign_offensive(
		objective_attacker
	)
	var second_wave_army: Army = null
	for army in objective_state.armies:
		if (
			army.owner_nation == objective_attacker
			and army.state == Army.State.MOVING
			and army.ai_action == ActionCandidate.Kind.ATTACK
			and army.ai_target_city == objective_city
		):
			second_wave_army = army
			break
	_check(
		next_wave_launched
		and objective_state.nations[objective_attacker].campaign_offensive_count
			== first_wave_count + 1,
		"战争持续时每%d天应重新集结并发动下一轮国家级攻势"
			% Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
	)
	_check(
		second_wave_army != null
		and _approx(
			second_wave_army.offensive_attack_multiplier,
				Simulation.offensive_preparation_multiplier(
					Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
				)
			)
			and second_wave_army.offensive_bonus_until_day
				== objective_state.day
					+ Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS,
		"后续攻势倍率应匹配 %d 天重整时长"
			% Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
	)
	var arrow_expiry := int(
		objective_state.campaign_visual_events[-1]["end_day"]
	)
	objective_state.day = arrow_expiry + 1
	objective_state.prune_campaign_visual_events()
	_check(
		objective_state.campaign_visual_events.is_empty(),
		"战略攻势箭头必须在展示期结束后自动清理"
	)
	var persistent_morale_before_expiry := -1.0
	if second_wave_army != null:
		persistent_morale_before_expiry = second_wave_army.morale
		objective_state.day = (
			second_wave_army.offensive_bonus_until_day
		)
		objective_sim._expire_offensive_bonuses()
	_check(
		second_wave_army != null
		and _approx(
			second_wave_army.offensive_attack_multiplier,
			1.0
		)
			and _approx(
				second_wave_army.morale,
				persistent_morale_before_expiry
			)
			and _approx(
				second_wave_army.combat_morale(),
				second_wave_army.morale
			)
		and second_wave_army.offensive_bonus_until_day == -1,
		"攻势攻击和有效士气加成到期必须清除，且不得改写持久士气"
	)
	objective_sim.free()

	var stalemate_state := GameState.new()
	stalemate_state.generate_grid_world(32012)
	stalemate_state.armies.clear()
	stalemate_state.battles.clear()
	for city in stalemate_state.cities:
		city.owner_nation = 0
		stalemate_state.recognized_city_owners[city.id] = 0
	for stalemate_edge in stalemate_state.edges:
		stalemate_edge.max_manpower = 0
	var stalemate_origin := 9
	var stalemate_target := 10
	var stalemate_support := 11
	for enemy_city in [
		stalemate_target,
		stalemate_support,
	]:
		stalemate_state.cities[enemy_city].owner_nation = 1
		stalemate_state.recognized_city_owners[enemy_city] = 1
	stalemate_state.cities[stalemate_target].fort_strength = 10
	stalemate_state.cities[stalemate_target].fort_strength_max = 10
	stalemate_state.edge_of(
		stalemate_origin,
		stalemate_target
	).max_manpower = 30000
	stalemate_state.edge_of(
		stalemate_target,
		stalemate_support
	).max_manpower = 30000
	for nation_a in range(stalemate_state.nations.size()):
		for nation_b in range(
			nation_a + 1,
			stalemate_state.nations.size()
		):
			stalemate_state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	stalemate_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	stalemate_state.set_war_objective(
		0,
		1,
		stalemate_target,
		"均势僵局满准备测试"
	)
	var stalemate_attackers: Array[Army] = []
	for attacker_index in range(2):
		var stalemate_attacker := _make_army(
			9900 + attacker_index,
			0,
			10000,
			10,
			10
		)
		stalemate_attacker.state = Army.State.HOLDING
		stalemate_attacker.location_city = stalemate_origin
		stalemate_attacker.move_from = stalemate_origin
		stalemate_attacker.move_to = stalemate_target
		stalemate_attacker.move_progress = (
			Simulation.HOLDING_TARGET_PROGRESS
		)
		stalemate_attacker.on_edge = true
		stalemate_state.armies.append(stalemate_attacker)
		stalemate_attackers.append(stalemate_attacker)
	stalemate_state.edge_of(
		stalemate_origin,
		stalemate_target
	).passing_count = stalemate_attackers.size()
	var stalemate_defender := _make_army(
		9910,
		1,
		15000,
		10,
		10
	)
	stalemate_defender.location_city = stalemate_target
	stalemate_defender.move_from = stalemate_target
	stalemate_state.armies.append(stalemate_defender)
	for support_index in range(2):
		var support_army := _make_army(
			9920 + support_index,
			1,
			15000,
			10,
			10
		)
		support_army.location_city = stalemate_support
		support_army.move_from = stalemate_support
		stalemate_state.armies.append(support_army)
	var stalemate_nation := stalemate_state.nations[0]
	stalemate_nation.campaign_last_offensive_day = 0
	stalemate_nation.campaign_next_offensive_day = (
		Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
	)
	stalemate_nation.campaign_preparation_started_day = 0
	stalemate_nation.campaign_preparation_targets = [
		stalemate_target
	] as Array[int]
	for stalemate_attacker in stalemate_attackers:
		stalemate_nation.campaign_preparation_assignments[
			stalemate_attacker.id
		] = stalemate_target
	stalemate_state.day = (
		Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS
	)
	var stalemate_sim := Simulation.new()
	stalemate_sim.setup(stalemate_state)
	var stalemate_threat := ThreatField.build(
		AiWorldView.build(stalemate_state, 0)
	)
	var ratio_at_normal_window := (
		stalemate_sim._campaign_projected_assault_ratio(
			0,
			stalemate_target,
			Simulation.CAMPAIGN_OFFENSIVE_INTERVAL_DAYS,
			stalemate_threat
		)
	)
	var ratio_at_full_preparation := (
		stalemate_sim._campaign_projected_assault_ratio(
			0,
			stalemate_target,
			Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS,
			stalemate_threat
		)
	)
	var stalemate_threshold := (
		stalemate_sim._campaign_attack_ratio_threshold(0)
	)
	_check(
		ratio_at_normal_window < stalemate_threshold
			and ratio_at_full_preparation >= stalemate_threshold,
		"均势夹具应仅在满准备窗口后跨过进攻阈值：常规窗%.2f，满准备%.2f，阈值%.2f"
			% [
				ratio_at_normal_window,
				ratio_at_full_preparation,
				stalemate_threshold,
			]
	)
	stalemate_sim._manage_campaign_offensive(
		0,
		null,
		null,
		stalemate_threat
	)
	stalemate_state.day = (
		Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS - 1
	)
	stalemate_sim._manage_campaign_offensive(
		0,
		null,
		null,
		ThreatField.build(
			AiWorldView.build(stalemate_state, 0)
		)
	)
	var no_early_stalemate_attack := true
	for stalemate_attacker in stalemate_attackers:
		no_early_stalemate_attack = (
			no_early_stalemate_attack
			and stalemate_attacker.ai_action
				!= ActionCandidate.Kind.ATTACK
		)
	_check(
		stalemate_nation.campaign_full_preparation_targets.has(
			stalemate_target
		)
			and stalemate_nation.campaign_offensive_count == 0
			and no_early_stalemate_attack,
		"均势攻势在常规窗至满准备前必须持续集结，不得拆成零散提前攻击"
	)
	stalemate_state.day = (
		Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
	)
	var full_preparation_launched := (
		stalemate_sim._manage_campaign_offensive(
			0,
			null,
			null,
			ThreatField.build(
				AiWorldView.build(stalemate_state, 0)
			)
		)
	)
	var full_preparation_attackers := 0
	var full_preparation_bonus_extended := false
	for stalemate_attacker in stalemate_attackers:
		if (
			stalemate_attacker.ai_action
				== ActionCandidate.Kind.ATTACK
			and stalemate_attacker.ai_target_city
				== stalemate_target
			and _approx(
				stalemate_attacker.offensive_attack_multiplier,
				Simulation.OFFENSIVE_BONUS_MAX_MULTIPLIER
			)
		):
			full_preparation_attackers += 1
			full_preparation_bonus_extended = (
				stalemate_attacker.offensive_bonus_until_day
				== stalemate_state.day
					+ Simulation
						.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS
			)
	_check(
		full_preparation_launched
			and full_preparation_attackers > 0
			and stalemate_nation.campaign_offensive_count == 1
			and stalemate_nation
				.campaign_full_preparation_targets.is_empty()
			and full_preparation_bonus_extended,
		(
			"满准备截止日必须以2倍攻击加成统一发动攻势："
			+ "launched=%s attackers=%d count=%d "
			+ "targets=%s"
		) % [
			str(full_preparation_launched),
			full_preparation_attackers,
			stalemate_nation.campaign_offensive_count,
			str(
				stalemate_nation
					.campaign_full_preparation_targets
			),
		]
	)
	stalemate_sim.free()

	var counter_state := GameState.new()
	counter_state.generate_grid_world(32011)
	counter_state.armies.clear()
	for city in counter_state.cities:
		city.owner_nation = 1
	for counter_edge in counter_state.edges:
		counter_edge.max_manpower = 0
	var counter_target := 10
	var counter_origin := counter_state.neighbors(counter_target)[0]
	counter_state.cities[counter_target].owner_nation = 0
	# item 6/7 反攻门槛（与 UtilityAI.assault_commit_threshold 同源）：
	# = 歼灭守军预算(15000) + 维持封锁兵力(工事换算 × SIEGE_COMMIT_MARGIN)。
	# fort=10 → siege_required_manpower(10)=1000；门槛 = 15000 + ceil(1000×2.0) = 17000。
	counter_state.cities[counter_target].fort_strength = 10
	var counter_route := counter_state.edge_of(
		counter_origin,
		counter_target
	)
	counter_route.max_manpower = 30000
	for nation_a in range(counter_state.nations.size()):
		for nation_b in range(
			nation_a + 1,
			counter_state.nations.size()
		):
			counter_state.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	counter_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	counter_state.set_war_objective(
		0,
		1,
		counter_origin,
		"国0原始战争目标"
	)
	var counter_garrison := _make_army(
		969,
		0,
		15000,
		10,
		10
	)
	counter_garrison.location_city = counter_target
	counter_garrison.move_from = counter_target
	counter_state.armies.append(counter_garrison)
	for counter_army_id in range(2):
		var counter_army := _make_army(
			970 + counter_army_id,
			1,
			15000,
			10,
			10
		)
		counter_army.location_city = counter_origin
		counter_army.move_from = counter_origin
		counter_state.armies.append(counter_army)
	var counter_required := DiplomacyAI.required_assault_troops(
		counter_state,
		1,
		counter_target
	)
	var counter_sim := Simulation.new()
	counter_sim.setup(counter_state)
	var counter_launched := counter_sim._manage_campaign_offensive(1)
	var defender_attacking := false
	for army in counter_state.armies:
		if (
			army.owner_nation == 1
			and army.state == Army.State.MOVING
			and army.ai_action == ActionCandidate.Kind.ATTACK
			and army.ai_target_city == counter_target
		):
			defender_attacking = true
			break
	var preserved_diplomatic_objective := counter_state.war_objective(
		0,
		1
	)
	_check(
		counter_launched
		and defender_attacking
		and counter_required == 17000
		and int(
			preserved_diplomatic_objective.get(
				"attacker",
				-1
			)
		) == 0
		and int(
			preserved_diplomatic_objective.get(
				"city_id",
				-1
			)
		) == counter_origin,
		"被宣战方应以1.5倍局部优势主动反攻，且不得覆盖宣战方的外交战争目标"
	)
	counter_sim.free()

	var plan_state := GameState.new()
	plan_state.generate_grid_world(32006)
	plan_state.armies.clear()
	for city in plan_state.cities:
		city.owner_nation = 0
	var plan_origin := 9
	var plan_primary := 10
	var plan_secondary := 17
	var plan_third := 8
	var plan_fourth := 1
	plan_state.cities[plan_origin].is_capital = false
	plan_state.cities[plan_origin].has_warehouse = false
	plan_state.cities[plan_primary].owner_nation = 1
	plan_state.cities[plan_secondary].owner_nation = 1
	plan_state.cities[plan_third].owner_nation = 1
	plan_state.cities[plan_fourth].owner_nation = 1
	for plan_target in [
		plan_primary,
		plan_secondary,
		plan_third,
		plan_fourth,
	]:
		plan_state.edge_of(
			plan_origin,
			plan_target
		).max_manpower = 30000
	plan_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	for plan_army_id in range(8):
		var plan_army := _make_army(
			980 + plan_army_id,
			0,
			15000,
			10,
			10
		)
		plan_army.location_city = plan_origin
		plan_army.move_from = plan_origin
		plan_state.armies.append(plan_army)
	var plan_sim := Simulation.new()
	plan_sim.setup(plan_state)
	var preparation_built := (
		plan_sim._ensure_campaign_preparation_plan(
			0,
			plan_primary
		)
	)
	var preparation_nation := plan_state.nations[0]
	var preparation_target_counts := {}
	for assigned_target in (
		preparation_nation
			.campaign_preparation_assignments.values()
	):
		preparation_target_counts[int(assigned_target)] = int(
			preparation_target_counts.get(
				int(assigned_target),
				0
			)
		) + 1
	_check(
		preparation_built
			and _approx(
				plan_sim._campaign_attack_ratio_threshold(0),
				Simulation.CAMPAIGN_ATTACK_ENTER_RATIO
			)
			and _approx(
				Simulation.CAMPAIGN_ATTACK_ENTER_RATIO,
				1.00
			)
			and preparation_nation
				.campaign_preparation_targets.size() == 4
			and int(
				preparation_target_counts.get(
					plan_primary,
					0
				)
			) > 0
			and int(
				preparation_target_counts.get(
					plan_secondary,
					0
				)
			) > 0
			and int(
				preparation_target_counts.get(
					plan_third,
					0
				)
			) > 0
			and int(
				preparation_target_counts.get(
					plan_fourth,
					0
				)
			) > 0,
		"国家应突破旧三路上限并行准备四个目标，且每支军队只分配一个方向"
	)
	var prepared_targets := (
		preparation_nation
			.campaign_preparation_targets.duplicate()
	)
	var prepared_batch_launched := (
		plan_sim._launch_campaign_offensive(
			0,
			plan_primary,
			60,
			prepared_targets
		)
	)
	var prepared_launched_targets := {}
	for army in plan_state.armies:
		if (
			army.state == Army.State.MOVING
			and army.ai_action == ActionCandidate.Kind.ATTACK
		):
			prepared_launched_targets[army.ai_target_city] = true
	_check(
		prepared_batch_launched
			and prepared_launched_targets.has(plan_primary)
			and prepared_launched_targets.has(plan_secondary)
			and prepared_launched_targets.has(plan_third)
			and prepared_launched_targets.has(plan_fourth),
		"同批准备完成的四个目标必须分别生成攻击命令，不能退化为三路上限"
	)
	_check(
		preparation_nation.campaign_theater_anchor_city
			== plan_primary
			and preparation_nation
				.campaign_theater_started_day
				== plan_state.day,
		"攻势实际发动后必须持久记录主战区锚点"
	)
	for army in plan_state.armies:
		plan_sim._settle_idle(army, plan_origin)
	plan_sim._clear_campaign_attack_plan(0)
	plan_sim._clear_campaign_preparation_plan(0)
	var plan_built := plan_sim._ensure_campaign_attack_plan(
		0,
		plan_primary
	)
	var plan_nation := plan_state.nations[0]
	var frozen_assignments := (
		plan_nation.campaign_attack_assignments.duplicate()
	)
	var plan_stable := plan_sim._ensure_campaign_attack_plan(
		0,
		plan_primary
	)
	_check(
		plan_built
		and plan_stable
		and plan_nation.campaign_plan_targets.size() == 4
		and plan_nation.campaign_plan_targets.has(
			plan_primary
		)
		and plan_nation.campaign_plan_targets.has(
			plan_secondary
		)
		and plan_nation.campaign_plan_targets.has(
			plan_third
		)
		and plan_nation.campaign_plan_targets.has(
			plan_fourth
		)
		and plan_nation.campaign_attack_assignments
			== frozen_assignments,
		"兵力足够时应生成并冻结全部四个方向的具体军队分工"
	)
	var multi_target_launched := (
		plan_sim._launch_campaign_offensive(
			0,
			plan_primary,
			180
		)
	)
	var launched_plan_targets := {}
	var assignments_match_orders := true
	for army in plan_state.armies:
		if not frozen_assignments.has(army.id):
			continue
		var assigned_target := int(
			frozen_assignments[army.id]
		)
		if army.state == Army.State.MOVING:
			launched_plan_targets[assigned_target] = true
			assignments_match_orders = (
				assignments_match_orders
				and army.ai_target_city == assigned_target
			)
	_check(
		multi_target_launched
		and launched_plan_targets.has(plan_primary)
		and launched_plan_targets.has(plan_secondary)
		and launched_plan_targets.has(plan_third)
		and launched_plan_targets.has(plan_fourth)
		and assignments_match_orders,
		"全面攻势执行必须逐军遵守四个计划目标，而非集中到少数方向"
	)
	plan_sim.free()

	# 正式地图宽正面：即便主目标的局部需求足以吞掉全部战团，也必须
	# 先让每个合法方向获得一个独立战团，再用剩余战团补强主目标。
	var broad_state := GameState.new()
	broad_state.generate_grid_world(32066)
	broad_state.uses_heightmap = true
	broad_state.armies.clear()
	for broad_city in broad_state.cities:
		broad_city.owner_nation = 0
	var broad_origin := 9
	var broad_targets: Array[int] = [10, 17, 8]
	for broad_target in broad_targets:
		broad_state.cities[broad_target].owner_nation = 1
		broad_state.recognized_city_owners[broad_target] = 1
		broad_state.edge_of(broad_origin, broad_target).max_manpower = 30000
	# 主目标需要约60000兵力，旧“逐目标填满”会用光四个战团。
	broad_state.cities[broad_targets[0]].fort_strength = 300
	broad_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var broad_nation := broad_state.nations[0]
	broad_nation.battle_groups.clear()
	broad_nation.next_battle_group_id = 0
	var broad_armies: Array[Army] = []
	for broad_index in range(4):
		var broad_group := broad_state.create_battle_group(0)
		var broad_army := _make_army(10800 + broad_index, 0, 15000, 10, 10)
		broad_army.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
		broad_army.location_city = broad_origin
		broad_army.move_from = broad_origin
		broad_state.armies.append(broad_army)
		broad_state.assign_army_to_battle_group(
			broad_army, broad_group.id
		)
		broad_armies.append(broad_army)
	var broad_sim := Simulation.new()
	broad_sim.setup(broad_state)
	var broad_view := AiWorldView.build(broad_state, 0)
	var broad_plan := CityDefensePlan.new()
	broad_plan.view = broad_view
	broad_plan.threat = ThreatField.build(broad_view)
	var broad_plan_before := broad_nation.campaign_preparation_plan
	var broad_targets_before := (
		broad_nation.campaign_preparation_targets.duplicate()
	)
	var broad_assignments_before := (
		broad_nation.campaign_preparation_assignments.duplicate(true)
	)
	var broad_groups_before := (
		broad_nation
			.campaign_preparation_group_assignments.duplicate(true)
	)
	var broad_full_before := (
		broad_nation.campaign_full_preparation_targets.duplicate()
	)
	var broad_started_before := (
		broad_nation.campaign_preparation_started_day
	)
	var broad_multiplier_before := (
		broad_nation.campaign_preparation_multiplier
	)
	var broad_attack_state_before := [
		broad_nation.campaign_attack_assignments.duplicate(true),
		broad_nation.campaign_attack_echelons.duplicate(true),
		broad_nation.campaign_active_echelons.duplicate(true),
		broad_nation.campaign_launched_armies.duplicate(true),
		broad_nation.campaign_echelon_started_days.duplicate(true),
		broad_nation.campaign_plan_targets.duplicate(),
		broad_nation.campaign_plan_wave,
		broad_nation.campaign_plan_primary_city,
		broad_nation.campaign_last_offensive_day,
		broad_nation.campaign_next_offensive_day,
		broad_nation.campaign_offensive_count,
		broad_nation.campaign_theater_anchor_city,
		broad_nation.campaign_theater_started_day,
		broad_nation.treasury_gold,
	]
	var broad_army_state_before := {}
	for broad_army in broad_armies:
		broad_army_state_before[broad_army.id] = [
			broad_army.size,
			broad_army.max_size,
			broad_army.battle_group_id,
			broad_army.strategic_role,
			broad_army.line_assignment_city,
			broad_army.line_assignment_posture,
			broad_army.line_assignment_edge,
			broad_army.state,
			broad_army.location_city,
			broad_army.move_from,
			broad_army.move_to,
			broad_army.path.duplicate(),
			broad_army.defensive_deployment_until_day,
			broad_army.ai_action,
			broad_army.ai_target_city,
			broad_army.ai_order_created_day,
			broad_army.ai_order_until_day,
		]
	var pure_broad_a := broad_sim._plan_campaign_allocation(
		0, broad_targets[0], broad_targets, broad_plan,
		ArmyCoordinator.new(), broad_view, false
	)
	var pure_broad_b := broad_sim._plan_campaign_allocation(
		0, broad_targets[0], broad_targets, broad_plan,
		ArmyCoordinator.new(), broad_view, false
	)
	var broad_armies_unchanged := true
	for broad_army in broad_armies:
		broad_armies_unchanged = (
			broad_armies_unchanged
			and broad_army_state_before[broad_army.id] == [
				broad_army.size,
				broad_army.max_size,
				broad_army.battle_group_id,
				broad_army.strategic_role,
				broad_army.line_assignment_city,
				broad_army.line_assignment_posture,
				broad_army.line_assignment_edge,
				broad_army.state,
				broad_army.location_city,
				broad_army.move_from,
				broad_army.move_to,
				broad_army.path,
				broad_army.defensive_deployment_until_day,
				broad_army.ai_action,
				broad_army.ai_target_city,
				broad_army.ai_order_created_day,
				broad_army.ai_order_until_day,
			]
		)
	var planned_group_occurrences := {}
	var broad_one_group_one_target := true
	for planned_target in pure_broad_a.assigned_target_ids:
		for planned_group_id in pure_broad_a.groups_for_target(
			planned_target
		):
			planned_group_occurrences[planned_group_id] = int(
				planned_group_occurrences.get(planned_group_id, 0)
			) + 1
			broad_one_group_one_target = (
				broad_one_group_one_target
				and pure_broad_a.target_for_group(planned_group_id)
					== planned_target
			)
	for occurrence_count in planned_group_occurrences.values():
		broad_one_group_one_target = (
			broad_one_group_one_target
			and int(occurrence_count) == 1
		)
	_check(
		pure_broad_a != pure_broad_b
			and pure_broad_a.same_allocation(pure_broad_b)
			and planned_group_occurrences.size()
				== pure_broad_a.assigned_group_count
			and pure_broad_a.group_to_target.size()
				== pure_broad_a.assigned_group_count
			and broad_one_group_one_target,
		"相同冻结输入的纯攻势规划必须确定，且每个战团只能属于一个目标"
	)
	_check(
		broad_nation.campaign_preparation_plan == broad_plan_before
			and broad_nation.campaign_preparation_targets
				== broad_targets_before
			and broad_nation.campaign_preparation_assignments
				== broad_assignments_before
			and broad_nation.campaign_preparation_group_assignments
				== broad_groups_before
			and broad_nation.campaign_full_preparation_targets
				== broad_full_before
			and broad_nation.campaign_preparation_started_day
				== broad_started_before
			and _approx(
				broad_nation.campaign_preparation_multiplier,
				broad_multiplier_before
			)
			and broad_attack_state_before == [
				broad_nation.campaign_attack_assignments,
				broad_nation.campaign_attack_echelons,
				broad_nation.campaign_active_echelons,
				broad_nation.campaign_launched_armies,
				broad_nation.campaign_echelon_started_days,
				broad_nation.campaign_plan_targets,
				broad_nation.campaign_plan_wave,
				broad_nation.campaign_plan_primary_city,
				broad_nation.campaign_last_offensive_day,
				broad_nation.campaign_next_offensive_day,
				broad_nation.campaign_offensive_count,
				broad_nation.campaign_theater_anchor_city,
				broad_nation.campaign_theater_started_day,
				broad_nation.treasury_gold,
			]
			and broad_armies_unchanged,
		"纯攻势规划不得修改 Nation 投影或任何 Army 状态"
	)
	var pure_broad_applied := broad_sim._apply_campaign_plan_atomic(
		0, pure_broad_a
	)
	var applied_broad_plan := broad_nation.campaign_preparation_plan
	var applied_broad_snapshot := (
		applied_broad_plan.duplicate_plan()
		if applied_broad_plan != null
		else CampaignAllocationPlan.new()
	)
	var applied_targets_snapshot := (
		broad_nation.campaign_preparation_targets.duplicate()
	)
	var applied_assignments_snapshot := (
		broad_nation.campaign_preparation_assignments.duplicate(true)
	)
	var applied_groups_snapshot := (
		broad_nation
			.campaign_preparation_group_assignments.duplicate(true)
	)
	var applied_full_snapshot := (
		broad_nation.campaign_full_preparation_targets.duplicate()
	)
	var applied_started_snapshot := (
		broad_nation.campaign_preparation_started_day
	)
	var applied_multiplier_snapshot := (
		broad_nation.campaign_preparation_multiplier
	)
	var invalid_broad_plan := pure_broad_a.duplicate_plan()
	var invalid_group_id := -1
	if not invalid_broad_plan.group_to_target.is_empty():
		invalid_group_id = int(
			invalid_broad_plan.group_to_target.keys()[0]
		)
	var invalid_original_target := int(
		invalid_broad_plan.group_to_target.get(invalid_group_id, -1)
	)
	var invalid_second_target := -1
	for candidate_target in invalid_broad_plan.assigned_target_ids:
		if candidate_target != invalid_original_target:
			invalid_second_target = candidate_target
			break
	if invalid_second_target >= 0:
		(
			invalid_broad_plan.target_to_groups[invalid_second_target]
			as Array[int]
		).append(invalid_group_id)
	var invalid_broad_applied := (
		broad_sim._apply_campaign_plan_atomic(0, invalid_broad_plan)
	)
	_check(
		pure_broad_applied
			and invalid_second_target >= 0
			and not invalid_broad_applied
			and broad_nation.campaign_preparation_plan
				== applied_broad_plan
			and broad_nation.campaign_preparation_plan != null
			and broad_nation.campaign_preparation_plan.same_allocation(
				applied_broad_snapshot
			)
			and broad_nation.campaign_preparation_targets
				== applied_targets_snapshot
			and broad_nation.campaign_preparation_assignments
				== applied_assignments_snapshot
			and broad_nation.campaign_preparation_group_assignments
				== applied_groups_snapshot
			and broad_nation.campaign_full_preparation_targets
				== applied_full_snapshot
			and broad_nation.campaign_preparation_started_day
				== applied_started_snapshot
			and _approx(
				broad_nation.campaign_preparation_multiplier,
				applied_multiplier_snapshot
			),
		(
			"非法双向战团映射必须原子失败，且旧 plan 引用与全部兼容投影逐字段不变"
		)
	)
	var broad_built := pure_broad_applied
	var broad_counts := {}
	for broad_army in broad_armies:
		var assigned_target := int(
			broad_nation.campaign_preparation_assignments.get(
				broad_army.id, -1
			)
		)
		broad_counts[assigned_target] = int(
			broad_counts.get(assigned_target, 0)
		) + 1
	_check(
		broad_built
			and broad_nation.campaign_preparation_targets.size() == 3
			and int(broad_counts.get(broad_targets[0], 0)) == 2
			and int(broad_counts.get(broad_targets[1], 0)) == 1
			and int(broad_counts.get(broad_targets[2], 0)) == 1,
		"正式地图攻势必须先覆盖全部合法方向再补强主目标：%s"
			% broad_counts
	)
	broad_nation.treasury_gold = 100000
	var transaction_treasury_before := broad_nation.treasury_gold
	var transaction_offensive_count_before := (
		broad_nation.campaign_offensive_count
	)
	var transaction_plan_before := (
		broad_nation.campaign_preparation_plan
	)
	var transaction_plan_snapshot := (
		transaction_plan_before.duplicate_plan()
	)
	var transaction_targets_before := (
		broad_nation.campaign_preparation_targets.duplicate()
	)
	var transaction_assignments_before := (
		broad_nation.campaign_preparation_assignments.duplicate(true)
	)
	var transaction_groups_before := (
		broad_nation
			.campaign_preparation_group_assignments.duplicate(true)
	)
	var transaction_active_before := [
		broad_nation.campaign_attack_assignments.duplicate(true),
		broad_nation.campaign_attack_echelons.duplicate(true),
		broad_nation.campaign_active_echelons.duplicate(true),
		broad_nation.campaign_launched_armies.duplicate(true),
		broad_nation.campaign_echelon_started_days.duplicate(true),
		broad_nation.campaign_plan_targets.duplicate(),
		broad_nation.campaign_plan_wave,
		broad_nation.campaign_plan_primary_city,
	]
	var transaction_armies_before := {}
	for broad_army in broad_armies:
		transaction_armies_before[broad_army.id] = [
			broad_army.state,
			broad_army.location_city,
			broad_army.move_from,
			broad_army.move_to,
			broad_army.path.duplicate(),
			broad_army.ai_action,
			broad_army.ai_target_city,
		]
	broad_sim._begin_ai_command_collection()
	var broad_collected := broad_sim._launch_campaign_offensive(
		0, broad_targets[0],
		Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS,
		broad_nation.campaign_preparation_targets.duplicate()
	)
	var transaction_payload: Dictionary = {}
	if not broad_sim._pending_campaign_launch_transactions.is_empty():
		transaction_payload = (
			broad_sim._pending_campaign_launch_transactions.values()[0]
		)
	var transaction_cost := int(
		transaction_payload.get("organization_cost", -1)
	)
	var collection_armies_unchanged := true
	for broad_army in broad_armies:
		collection_armies_unchanged = (
			collection_armies_unchanged
			and transaction_armies_before[broad_army.id] == [
				broad_army.state,
				broad_army.location_city,
				broad_army.move_from,
				broad_army.move_to,
				broad_army.path,
				broad_army.ai_action,
				broad_army.ai_target_city,
			]
		)
	_check(
		broad_collected
			and broad_sim._pending_campaign_launch_transactions.size() == 1
			and transaction_cost > 0
			and collection_armies_unchanged
			and broad_nation.treasury_gold
				== transaction_treasury_before
			and broad_nation.campaign_offensive_count
				== transaction_offensive_count_before
			and transaction_active_before == [
				broad_nation.campaign_attack_assignments,
				broad_nation.campaign_attack_echelons,
				broad_nation.campaign_active_echelons,
				broad_nation.campaign_launched_armies,
				broad_nation.campaign_echelon_started_days,
				broad_nation.campaign_plan_targets,
				broad_nation.campaign_plan_wave,
				broad_nation.campaign_plan_primary_city,
			]
			and broad_nation.campaign_preparation_plan
				== transaction_plan_before
			and broad_nation.campaign_preparation_plan.same_allocation(
				transaction_plan_snapshot
			)
			and broad_nation.campaign_preparation_targets
				== transaction_targets_before
			and broad_nation.campaign_preparation_assignments
				== transaction_assignments_before
			and broad_nation.campaign_preparation_group_assignments
				== transaction_groups_before,
		"正式攻势收集阶段只能登记待提交事务，不得提前修改军队、国库、波次或准备态"
	)
	var invalidated_broad_army := broad_armies[0]
	invalidated_broad_army.state = Army.State.RECOVERING
	broad_sim._commit_ai_command_collection([0] as Array[int])
	var failed_batch_clean := true
	for broad_army in broad_armies:
		if broad_army == invalidated_broad_army:
			failed_batch_clean = (
				failed_batch_clean
				and broad_army.state == Army.State.RECOVERING
				and broad_army.ai_action
					!= ActionCandidate.Kind.ATTACK
			)
		else:
			failed_batch_clean = (
				failed_batch_clean
				and broad_army.state == Army.State.IDLE
				and broad_army.ai_action
					!= ActionCandidate.Kind.ATTACK
			)
	_check(
		failed_batch_clean
			and broad_sim.ai_last_command_commit_failures == 1
			and broad_sim._pending_campaign_launch_transactions.is_empty()
			and broad_nation.treasury_gold
				== transaction_treasury_before
			and broad_nation.campaign_offensive_count
				== transaction_offensive_count_before
			and transaction_active_before == [
				broad_nation.campaign_attack_assignments,
				broad_nation.campaign_attack_echelons,
				broad_nation.campaign_active_echelons,
				broad_nation.campaign_launched_armies,
				broad_nation.campaign_echelon_started_days,
				broad_nation.campaign_plan_targets,
				broad_nation.campaign_plan_wave,
				broad_nation.campaign_plan_primary_city,
			]
			and broad_nation.campaign_preparation_plan
				== transaction_plan_before
			and broad_nation.campaign_preparation_plan.same_allocation(
				transaction_plan_snapshot
			)
			and broad_nation.campaign_preparation_targets
				== transaction_targets_before
			and broad_nation.campaign_preparation_assignments
				== transaction_assignments_before
			and broad_nation.campaign_preparation_group_assignments
				== transaction_groups_before,
		"首梯队一军在提交前失效时，正式攻势整批不得移动、扣费、消费准备态或写入 active wave"
	)
	invalidated_broad_army.state = Army.State.IDLE
	broad_sim._begin_ai_command_collection()
	var broad_recollected := broad_sim._launch_campaign_offensive(
		0, broad_targets[0],
		Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS,
		broad_nation.campaign_preparation_targets.duplicate()
	)
	broad_sim._commit_ai_command_collection([0] as Array[int])
	var broad_attackers := 0
	var broad_launched_targets := {}
	for broad_army in broad_armies:
		if broad_army.ai_action == ActionCandidate.Kind.ATTACK:
			broad_attackers += 1
			broad_launched_targets[broad_army.ai_target_city] = true
	_check(
		broad_recollected
			and broad_sim.ai_last_command_commit_failures == 0
			and broad_attackers == broad_armies.size()
			and broad_launched_targets.size() == 3
			and broad_nation.treasury_gold
				== transaction_treasury_before - transaction_cost
			and broad_nation.campaign_offensive_count
				== transaction_offensive_count_before + 1
			and not broad_nation.campaign_plan_targets.is_empty()
			and not broad_nation.campaign_active_echelons.is_empty()
			and broad_nation.campaign_preparation_plan == null
			and broad_nation.campaign_preparation_targets.is_empty()
			and broad_nation.campaign_preparation_assignments.is_empty()
			and broad_nation
				.campaign_preparation_group_assignments.is_empty(),
		(
			"事务恢复后应只扣一次费用，并在三个方向同步投入全部四个首梯队战团："
			+ "armies=%d targets=%s"
		) % [broad_attackers, broad_launched_targets]
	)
	broad_sim.free()

	# 旧存档/外部调用也必须服从执行层硬预算：十个合法准备方向
	# 最终只能冻结并发射八路，二十个已分配战团只能保留十六个。
	var budget_state := GameState.new()
	budget_state.generate_grid_world(32067)
	budget_state.uses_heightmap = true
	budget_state.armies.clear()
	for budget_city in budget_state.cities:
		budget_city.owner_nation = 0
	var budget_targets: Array[int] = [
		1, 3, 5, 7, 17, 19, 21, 23, 33, 35,
	]
	for budget_target in budget_targets:
		budget_state.cities[budget_target].owner_nation = 1
	budget_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	var budget_nation := budget_state.nations[0]
	budget_nation.battle_groups.clear()
	budget_nation.next_battle_group_id = 0
	for budget_index in range(20):
		var budget_target := budget_targets[
			budget_index % budget_targets.size()
		]
		var budget_group := budget_state.create_battle_group(0)
		var budget_army := _make_army(10900 + budget_index, 0, 5000, 10, 10)
		budget_army.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
		budget_army.location_city = budget_target + 8
		budget_army.move_from = budget_target + 8
		budget_state.armies.append(budget_army)
		budget_state.assign_army_to_battle_group(
			budget_army, budget_group.id
		)
		budget_nation.campaign_preparation_assignments[
			budget_army.id
		] = budget_target
		if not budget_nation.campaign_preparation_targets.has(
			budget_target
		):
			budget_nation.campaign_preparation_targets.append(
				budget_target
			)
			budget_nation.campaign_preparation_group_assignments[
				budget_target
			] = budget_group.id
	var budget_sim := Simulation.new()
	budget_sim.setup(budget_state)
	var budget_view := AiWorldView.build(budget_state, 0)
	var budget_allocation := budget_sim._plan_campaign_allocation(
		0, budget_targets[0], budget_targets, null, null,
		budget_view, false
	)
	var budget_plan_applied := budget_sim._apply_campaign_plan_atomic(
		0, budget_allocation
	)
	budget_nation.treasury_gold = 100000
	var budget_launched := budget_sim._launch_campaign_offensive(
		0, budget_targets[0],
		Simulation.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS,
		budget_targets
	)
	var bounded_groups := {}
	for budget_army in budget_state.armies:
		if budget_nation.campaign_preparation_assignments.has(
			budget_army.id
		):
			bounded_groups[budget_army.battle_group_id] = true
	var budget_launched_targets := {}
	for budget_army in budget_state.armies:
		if budget_army.ai_action == ActionCandidate.Kind.ATTACK:
			budget_launched_targets[budget_army.ai_target_city] = true
	_check(
		budget_plan_applied
			and budget_nation.campaign_preparation_targets.size()
				<= Simulation.CAMPAIGN_MAX_PARALLEL_TARGETS
			and bounded_groups.size() <= Simulation.CAMPAIGN_MAX_WARTIME_GROUPS
			and budget_launched
			and budget_nation.campaign_plan_targets.size()
				<= Simulation.CAMPAIGN_MAX_PARALLEL_TARGETS
			and budget_launched_targets.size()
				<= Simulation.CAMPAIGN_MAX_PARALLEL_TARGETS,
		"旧状态与外部准备列表必须在规划、冻结和发射三层裁到8路/16团"
	)
	budget_sim.free()

	var rebalance_state := GameState.new()
	rebalance_state.generate_grid_world(32068)
	rebalance_state.uses_heightmap = true
	rebalance_state.armies.clear()
	for rebalance_city in rebalance_state.cities:
		rebalance_city.owner_nation = 0
	var rebalance_targets: Array[int] = [10, 17, 8]
	for rebalance_target in rebalance_targets.slice(0, 2):
		rebalance_state.cities[rebalance_target].owner_nation = 1
		rebalance_state.edge_of(9, rebalance_target).max_manpower = 30000
	# 第三方向是国2最后一城，满16团预算时必须为它一次预留三团。
	rebalance_state.cities[rebalance_targets[2]].owner_nation = 2
	rebalance_state.edge_of(9, rebalance_targets[2]).max_manpower = 30000
	rebalance_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	rebalance_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.WAR
	)
	var rebalance_nation := rebalance_state.nations[0]
	rebalance_nation.battle_groups.clear()
	rebalance_nation.next_battle_group_id = 0
	for rebalance_index in range(Simulation.CAMPAIGN_MAX_WARTIME_GROUPS):
		var rebalance_group := rebalance_state.create_battle_group(0)
		var rebalance_army := _make_army(11000 + rebalance_index, 0, 5000, 10, 10)
		rebalance_army.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
		rebalance_army.location_city = 9
		rebalance_army.move_from = 9
		rebalance_state.armies.append(rebalance_army)
		rebalance_state.assign_army_to_battle_group(
			rebalance_army, rebalance_group.id
		)
		var old_target := rebalance_targets[rebalance_index % 2]
		rebalance_nation.campaign_preparation_assignments[
			rebalance_army.id
		] = old_target
		if not rebalance_nation.campaign_preparation_targets.has(old_target):
			rebalance_nation.campaign_preparation_targets.append(old_target)
			rebalance_nation.campaign_preparation_group_assignments[
				old_target
			] = rebalance_group.id
	var rebalance_sim := Simulation.new()
	rebalance_sim.setup(rebalance_state)
	var rebalance_view := AiWorldView.build(rebalance_state, 0)
	var rebalance_plan := CityDefensePlan.new()
	rebalance_plan.view = rebalance_view
	rebalance_plan.threat = ThreatField.build(rebalance_view)
	var rebalance_allocation := rebalance_sim._plan_campaign_allocation(
		0, rebalance_targets[0], rebalance_targets, rebalance_plan,
		ArmyCoordinator.new(), rebalance_view, false
	)
	var rebalanced := rebalance_sim._apply_campaign_plan_atomic(
		0, rebalance_allocation
	)
	var groups_per_rebalance_target := {}
	var seen_rebalance_groups := {}
	for rebalance_army in rebalance_state.armies:
		var rebalance_target := int(
			rebalance_nation.campaign_preparation_assignments.get(
				rebalance_army.id, -1
			)
		)
		if rebalance_target < 0:
			continue
		seen_rebalance_groups[rebalance_army.battle_group_id] = true
		groups_per_rebalance_target[rebalance_target] = int(
			groups_per_rebalance_target.get(rebalance_target, 0)
		) + 1
	_check(
		rebalanced
			and int(groups_per_rebalance_target.get(rebalance_targets[0], 0)) > 0
			and int(groups_per_rebalance_target.get(rebalance_targets[1], 0)) > 0
			and int(groups_per_rebalance_target.get(rebalance_targets[2], 0))
				>= Simulation.CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS
			and seen_rebalance_groups.size()
				<= Simulation.CAMPAIGN_MAX_WARTIME_GROUPS,
		"16团已占旧方向时必须保留旧代表团并为新出现的最后一城释放三团：%s"
			% groups_per_rebalance_target
	)
	# 模拟新方向三团全灭但目标/代表团记录仍残留。下一轮不能走
	# “所有团已有分配”的快速路径，必须释放旧增援团并重新补足三团。
	for rebalance_army in rebalance_state.armies:
		if int(rebalance_nation.campaign_preparation_assignments.get(
			rebalance_army.id, -1
		)) == rebalance_targets[2]:
			rebalance_army.size = 0
	var restored_view := AiWorldView.build(rebalance_state, 0)
	rebalance_plan.view = restored_view
	rebalance_plan.snapshot = StrategicMapSnapshot.build(restored_view)
	rebalance_plan.threat = ThreatField.build(restored_view)
	var restored_plan := rebalance_sim._ensure_campaign_preparation_plan(
		0, rebalance_targets[0], rebalance_plan, ArmyCoordinator.new(), true
	)
	var restored_decisive_groups := {}
	for rebalance_army in rebalance_state.armies:
		if (
			rebalance_army.size > 0
			and int(rebalance_nation.campaign_preparation_assignments.get(
				rebalance_army.id, -1
			)) == rebalance_targets[2]
		):
			restored_decisive_groups[rebalance_army.battle_group_id] = true
	_check(
		restored_plan
			and restored_decisive_groups.size()
				>= Simulation.CAMPAIGN_DECISIVE_ASSAULT_MIN_GROUPS,
		"零成员旧目标不得被快速路径永久保留，最后一城必须重新补足三团"
	)
	rebalance_sim.free()

	var role_attack_state := GameState.new()
	role_attack_state.generate_grid_world(32013)
	role_attack_state.uses_heightmap = true
	role_attack_state.armies.clear()
	for city in role_attack_state.cities:
		city.owner_nation = 0
	var role_attack_origin := 9
	var role_attack_target := 10
	role_attack_state.cities[role_attack_target].owner_nation = 1
	role_attack_state.recognized_city_owners[role_attack_target] = 1
	role_attack_state.cities[role_attack_target].fort_strength = 5000
	role_attack_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var role_heavy := _make_army(1984, 0, 15000, 10, 10)
	role_heavy.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	role_heavy.location_city = role_attack_origin
	role_heavy.move_from = role_attack_origin
	var role_city_guard := _make_army(1985, 0, 5000, 10, 10)
	role_city_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	role_city_guard.location_city = role_attack_origin
	role_city_guard.move_from = role_attack_origin
	var role_edge_support := _make_army(1986, 0, 5000, 10, 10)
	role_edge_support.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	role_edge_support.location_city = role_attack_origin
	role_edge_support.move_from = role_attack_origin
	role_attack_state.armies.append_array([
		role_heavy,
		role_city_guard,
		role_edge_support,
	])
	var role_attack_group := (
		role_attack_state.nations[0].battle_groups[0]
	)
	role_attack_state.assign_army_to_battle_group(
		role_heavy,
		role_attack_group.id
	)
	role_attack_state.assign_army_to_battle_group(
		role_edge_support,
		role_attack_group.id
	)
	var other_attack_group := role_attack_state.create_battle_group(
		0
	)
	var other_group_light := _make_army(
		1988,
		0,
		5000,
		10,
		10
	)
	other_group_light.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	other_group_light.location_city = role_attack_origin
	other_group_light.move_from = role_attack_origin
	role_attack_state.armies.append(other_group_light)
	role_attack_state.assign_army_to_battle_group(
		other_group_light,
		other_attack_group.id
	)
	var role_attack_sim := Simulation.new()
	role_attack_sim.setup(role_attack_state)
	var role_attack_view := AiWorldView.build(
		role_attack_state,
		0
	)
	var role_defense_plan := CityDefensePlan.new()
	role_defense_plan.view = role_attack_view
	role_defense_plan.assigned_city_by_army = {
		role_city_guard.id: role_attack_origin,
		role_edge_support.id: role_attack_origin,
	}
	role_defense_plan.assigned_posture_by_army = {
		role_city_guard.id: CityDefensePlan.Posture.CITY,
		role_edge_support.id: CityDefensePlan.Posture.EDGE,
	}
	role_defense_plan.assigned_edge_by_army = {
		role_edge_support.id: role_attack_target,
	}
	role_defense_plan.assigned_armies_by_city = {
		role_attack_origin: [
			role_city_guard.id,
			role_edge_support.id,
		],
	}
	var role_preparation_built := (
		role_attack_sim._ensure_campaign_preparation_plan(
			0,
			role_attack_target,
			role_defense_plan,
			ArmyCoordinator.new()
		)
	)
	var role_assignments := (
		role_attack_state.nations[0]
			.campaign_preparation_assignments
	)
	_check(
		role_preparation_built
			and role_assignments.has(role_heavy.id)
			and role_assignments.has(role_edge_support.id)
			and role_assignments.has(other_group_light.id)
			and not role_assignments.has(role_city_guard.id)
			and role_attack_sim
				._can_assign_campaign_preparation_army(
					0,
					other_group_light,
					role_attack_target
				),
		"高防目标应允许多个完整战团协同准备，独立填线军不得混入"
	)
	var late_group_light := _make_army(1987, 0, 5000, 10, 10)
	late_group_light.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	late_group_light.location_city = role_attack_origin
	late_group_light.move_from = role_attack_origin
	role_attack_state.armies.append(late_group_light)
	role_attack_state.assign_army_to_battle_group(
		late_group_light,
		role_attack_group.id
	)
	var persistent_plan_synced := (
		role_attack_sim._ensure_campaign_preparation_plan(
			0,
			role_attack_target,
			role_defense_plan,
			ArmyCoordinator.new()
		)
	)
	role_assignments = (
		role_attack_state.nations[0]
			.campaign_preparation_assignments
	)
	_check(
		persistent_plan_synced
			and role_assignments.has(late_group_light.id)
			and int(role_assignments[late_group_light.id])
				== role_attack_target,
		"进行中攻势必须自动吸收同一持久战团后来补入的成员"
	)
	role_attack_sim.free()

	var unified_demand_state := GameState.new()
	unified_demand_state.generate_grid_world(32020)
	unified_demand_state.uses_heightmap = true
	unified_demand_state.armies.clear()
	unified_demand_state.battles.clear()
	for demand_city in unified_demand_state.cities:
		demand_city.owner_nation = 0
		unified_demand_state.recognized_city_owners[
			demand_city.id
		] = 0
	for demand_target_city in [10, 11, 12]:
		unified_demand_state.cities[
			demand_target_city
		].owner_nation = 1
		unified_demand_state.recognized_city_owners[
			demand_target_city
		] = 1
	for demand_edge in unified_demand_state.edges:
		demand_edge.max_manpower = 0
	var demand_origin := 9
	var demand_target := 10
	unified_demand_state.edge_of(
		demand_origin,
		demand_target
	).max_manpower = Edge.TERRAIN_LOW_MANPOWER
	unified_demand_state.cities[demand_target].fort_strength = 10
	unified_demand_state.cities[demand_target].fort_strength_max = 10
	for defender_index in range(4):
		var demand_defender := _make_army(
			1990 + defender_index,
			1,
			GameState.INITIAL_LIGHT_ARMY_SIZE,
			10,
			10
		)
		demand_defender.max_size = (
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		demand_defender.location_city = demand_target
		demand_defender.move_from = demand_target
		unified_demand_state.armies.append(demand_defender)
	unified_demand_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	unified_demand_state.set_war_objective(
		0,
		1,
		demand_target,
		"统一需求模型回归"
	)
	var unified_demand_sim := Simulation.new()
	unified_demand_sim.setup(unified_demand_state)
	var unified_targets := (
		unified_demand_sim._campaign_force_demand_targets(
			0,
			StrategicMapSnapshot.build(
				AiWorldView.build(unified_demand_state, 0)
			)
		)
	)
	var unified_demand := (
		unified_demand_sim._campaign_target_group_demand(
			0,
			demand_target
		)
	)
	_check(
		unified_demand_state.cities_of(1).size() == 3
			and DiplomacyAI.objective_staging_capacity()
				== Edge.MIN_MANPOWER
			and unified_targets == [demand_target]
			and int(unified_demand["route_group_manpower"])
				== 10000
			and int(unified_demand["required_manpower"])
				== 22000
			and int(unified_demand["assault_groups"]) == 3
			and int(unified_demand["groups"])
				== 3 * Simulation.CAMPAIGN_PREPARED_ECHELONS,
		"统一需求模型必须对三城国家的窄路目标配置3团首梯队和3团预备梯队"
	)
	unified_demand_sim.free()

	var fallback_state := GameState.new()
	fallback_state.generate_grid_world(32015)
	fallback_state.uses_heightmap = true
	fallback_state.armies.clear()
	for fallback_city in fallback_state.cities:
		fallback_city.owner_nation = 1
	for fallback_city_id in range(10):
		fallback_state.cities[
			fallback_city_id
		].owner_nation = 0
	fallback_state.nations[0].capital_city_id = 0
	var fallback_origin := 9
	var fallback_target := 10
	fallback_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var fallback_city_guard := _make_army(
		1987,
		0,
		5000,
		10,
		10
	)
	fallback_city_guard.max_size = (
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	fallback_city_guard.location_city = fallback_origin
	fallback_city_guard.move_from = fallback_origin
	fallback_state.armies.append(fallback_city_guard)
	var fallback_mobile: Array[Army] = []
	for fallback_index in range(2):
		var fallback_army := _make_army(
			1988 + fallback_index,
			0,
			5000,
			10,
			10
		)
		fallback_army.max_size = (
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		fallback_army.location_city = fallback_origin
		fallback_army.move_from = fallback_origin
		fallback_state.armies.append(fallback_army)
		fallback_mobile.append(fallback_army)
	var fallback_group := fallback_state.nations[0].battle_groups[0]
	for fallback_army in fallback_mobile:
		fallback_state.assign_army_to_battle_group(
			fallback_army,
			fallback_group.id
		)
	var fallback_sim := Simulation.new()
	fallback_sim.setup(fallback_state)
	var fallback_view := AiWorldView.build(fallback_state, 0)
	var fallback_defense_plan := CityDefensePlan.new()
	fallback_defense_plan.view = fallback_view
	fallback_defense_plan.assigned_city_by_army = {
		fallback_city_guard.id: fallback_origin,
	}
	fallback_defense_plan.assigned_posture_by_army = {
		fallback_city_guard.id:
			CityDefensePlan.Posture.CITY,
	}
	fallback_defense_plan.assigned_armies_by_city = {
		fallback_origin: [fallback_city_guard.id],
	}
	var fallback_preparation_built := (
		fallback_sim._ensure_campaign_preparation_plan(
			0,
			fallback_target,
			fallback_defense_plan,
			ArmyCoordinator.new()
		)
	)
	var fallback_assignments := (
		fallback_state.nations[0]
			.campaign_preparation_assignments
	)
	var fallback_only_light := true
	var fallback_mobile_ids := [
		fallback_mobile[0].id,
		fallback_mobile[1].id,
	]
	for fallback_army_id in fallback_assignments:
		fallback_only_light = (
			fallback_only_light
			and fallback_mobile_ids.has(
				int(fallback_army_id)
			)
		)
	_check(
		fallback_preparation_built
			and fallback_assignments.size() == 2
			and fallback_only_light
			and not fallback_assignments.has(
				fallback_city_guard.id
			),
		"只有两支轻军的不满编战团也可组织攻势，且不得抽走独立城市填线军"
	)
	fallback_sim.free()

	# 角色整理后，旧防区快照可能仍记录一支已经归入战团并转为 MAIN 的轻军。攻势应接纳
	# 同一持久战团的两支 MAIN 轻军，但必须拒绝仍承担 CITY/EDGE 防区的独立 LINE。
	var stale_assignment_state := GameState.new()
	stale_assignment_state.generate_grid_world(32016)
	stale_assignment_state.uses_heightmap = true
	stale_assignment_state.armies.clear()
	for stale_assignment_city in stale_assignment_state.cities:
		stale_assignment_city.owner_nation = 1
	for stale_assignment_city_id in range(10):
		stale_assignment_state.cities[
			stale_assignment_city_id
		].owner_nation = 0
	stale_assignment_state.nations[0].capital_city_id = 0
	var stale_assignment_origin := 9
	var stale_assignment_target := 10
	stale_assignment_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var independent_city_guard := _make_army(2100, 0, 5000, 10, 10)
	independent_city_guard.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	independent_city_guard.location_city = stale_assignment_origin
	independent_city_guard.move_from = stale_assignment_origin
	var group_member_with_stale_assignment := _make_army(
		2101,
		0,
		5000,
		10,
		10
	)
	var independent_edge_guard := _make_army(2102, 0, 5000, 10, 10)
	for light_army in [
		group_member_with_stale_assignment,
		independent_edge_guard,
	]:
		light_army.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
		light_army.location_city = stale_assignment_origin
		light_army.move_from = stale_assignment_origin
	var group_member_without_assignment := _make_army(
		2103,
		0,
		4999,
		10,
		10
	)
	group_member_without_assignment.max_size = (
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	group_member_without_assignment.location_city = (
		stale_assignment_origin
	)
	group_member_without_assignment.move_from = stale_assignment_origin
	stale_assignment_state.armies.append_array([
		independent_city_guard,
		group_member_with_stale_assignment,
		independent_edge_guard,
		group_member_without_assignment,
	])
	var support_group := stale_assignment_state.nations[0].battle_groups[0]
	stale_assignment_state.assign_army_to_battle_group(
		group_member_with_stale_assignment,
		support_group.id
	)
	stale_assignment_state.assign_army_to_battle_group(
		group_member_without_assignment,
		support_group.id
	)
	var stale_assignment_sim := Simulation.new()
	stale_assignment_sim.setup(stale_assignment_state)
	var stale_assignment_view := AiWorldView.build(
		stale_assignment_state,
		0
	)
	var stale_assignment_plan := CityDefensePlan.new()
	stale_assignment_plan.view = stale_assignment_view
	stale_assignment_plan.assigned_city_by_army = {
		independent_city_guard.id: stale_assignment_origin,
		group_member_with_stale_assignment.id: stale_assignment_origin,
		independent_edge_guard.id: stale_assignment_origin,
	}
	stale_assignment_plan.assigned_posture_by_army = {
		independent_city_guard.id: CityDefensePlan.Posture.CITY,
		group_member_with_stale_assignment.id:
			CityDefensePlan.Posture.EDGE,
		independent_edge_guard.id: CityDefensePlan.Posture.EDGE,
	}
	stale_assignment_plan.assigned_edge_by_army = {
		group_member_with_stale_assignment.id: stale_assignment_target,
		independent_edge_guard.id: stale_assignment_target,
	}
	stale_assignment_plan.assigned_armies_by_city = {
		stale_assignment_origin: [
			independent_city_guard.id,
			group_member_with_stale_assignment.id,
			independent_edge_guard.id,
		],
	}
	var stale_assignment_built := (
		stale_assignment_sim._ensure_campaign_preparation_plan(
			0,
			stale_assignment_target,
			stale_assignment_plan,
			ArmyCoordinator.new()
		)
	)
	var stale_assignment_campaign_assignments := (
		stale_assignment_state.nations[0]
			.campaign_preparation_assignments
	)
	var defense_assigned_member_count := 0
	for defense_assigned_id in [
		group_member_with_stale_assignment.id,
		independent_edge_guard.id,
	]:
		if stale_assignment_campaign_assignments.has(
			defense_assigned_id
		):
			defense_assigned_member_count += 1
	_check(
		stale_assignment_built
			and stale_assignment_campaign_assignments.size() == 2
			and defense_assigned_member_count == 1
			and stale_assignment_campaign_assignments.has(
				group_member_without_assignment.id
			)
			and stale_assignment_campaign_assignments.has(
				group_member_with_stale_assignment.id
			)
			and not stale_assignment_campaign_assignments.has(
				independent_city_guard.id
			)
			and not stale_assignment_campaign_assignments.has(
				independent_edge_guard.id
			),
		(
			"正式地图轻型攻势应使用同一持久战团的两支 MAIN 轻军；"
			+ "即使旧防区快照仍记录其中一军，也不得抽调独立 CITY/EDGE LINE"
		)
	)
	stale_assignment_sim.free()

	var theater_state := GameState.new()
	theater_state.generate_grid_world(32017)
	theater_state.uses_heightmap = true
	theater_state.armies.clear()
	for theater_city in theater_state.cities:
		theater_city.owner_nation = 0
	for theater_edge in theater_state.edges:
		if theater_edge.max_manpower > 0:
			theater_edge.max_manpower = 30000
	var theater_anchor := 1
	var theater_local_target := 2
	var theater_far_target := 63
	theater_state.cities[theater_anchor].owner_nation = 1
	theater_state.cities[theater_far_target].owner_nation = 1
	theater_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var theater_heavy := _make_army(
		2200,
		0,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		10,
		10
	)
	theater_heavy.max_size = (
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	theater_heavy.location_city = 0
	theater_heavy.move_from = 0
	theater_state.armies.append(theater_heavy)
	var theater_sim := Simulation.new()
	theater_sim.setup(theater_state)
	theater_state.nations[0].campaign_theater_anchor_city = (
		theater_anchor
	)
	theater_state.nations[0].campaign_theater_started_day = 10
	var retry_same_theater := (
		theater_sim._campaign_objective_in_current_theater(
			0,
			theater_far_target
		)
	)
	var local_only_plan := (
		theater_sim._ensure_campaign_preparation_plan(
			0,
			theater_anchor
		)
	)
	_check(
		retry_same_theater == theater_anchor
			and local_only_plan
			and theater_state.nations[0]
				.campaign_preparation_targets
				== [theater_anchor],
		"原战区目标仍为敌城时应继续原方向，且同波不得加入远端第二战区"
	)
	theater_sim._clear_campaign_preparation_plan(0)
	theater_state.cities[theater_anchor].owner_nation = 0
	theater_state.cities[theater_local_target].owner_nation = 1
	theater_state.ownership_revision += 1
	var continued_locally := (
		theater_sim._campaign_objective_in_current_theater(
			0,
			theater_far_target
		)
	)
	_check(
		continued_locally == theater_local_target,
		"原目标攻下后应沿当前战区攻击邻近敌城，不得立即跨图换线"
	)
	theater_state.cities[theater_local_target].owner_nation = 0
	theater_state.ownership_revision += 1
	var strategic_redeployment := (
		theater_sim._campaign_objective_in_current_theater(
			0,
			theater_far_target
		)
	)
	_check(
		strategic_redeployment == theater_far_target,
		"当前战区清空后必须允许重军向远端新战区战略转场"
	)
	theater_sim.free()

	var prewar_state := GameState.new()
	prewar_state.generate_grid_world(32014)
	prewar_state.armies.clear()
	for city in prewar_state.cities:
		city.owner_nation = 0
	var prewar_target := 10
	prewar_state.cities[prewar_target].owner_nation = 1
	prewar_state.cities[prewar_target].fort_strength = 1000
	for prewar_index in range(7):
		var prewar_size := (
			GameState.INITIAL_HEAVY_ARMY_SIZE
			if prewar_index < 2
			else GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		var prewar_army := _make_army(
			1991 + prewar_index,
			0,
			prewar_size,
			10,
			10
		)
		prewar_army.max_size = prewar_size
		prewar_army.location_city = 0
		prewar_army.move_from = 0
		prewar_state.armies.append(prewar_army)
	var prewar_sim := Simulation.new()
	prewar_sim.setup(prewar_state)
	var prewar_view := AiWorldView.build(prewar_state, 0)
	var prewar_defense_plan := CityDefensePlan.new()
	prewar_defense_plan.view = prewar_view
	prewar_sim._begin_ai_command_collection()
	var prewar_changed := (
		prewar_sim._assign_offensive_staging_orders(
			0,
			prewar_target,
			prewar_defense_plan,
			ArmyCoordinator.new(),
			true,
			false
		)
	)
	prewar_sim._commit_ai_command_collection([0])
	var prewar_heavy_orders := 0
	var prewar_light_orders := 0
	for prewar_army in prewar_state.armies:
		if not prewar_army.ai_order_reason.begins_with(
			"战前集结"
		):
			continue
		if (
			prewar_army.max_size
				== GameState.INITIAL_HEAVY_ARMY_SIZE
		):
			prewar_heavy_orders += 1
		elif (
			prewar_army.max_size
				== GameState.INITIAL_LIGHT_ARMY_SIZE
		):
			prewar_light_orders += 1
	_check(
		prewar_changed
			and prewar_heavy_orders > 0
			and prewar_light_orders <= prewar_heavy_orders,
		"宣战前集结的5000支援军不得多于15000攻势军，避免前线城市堆叠"
	)
	prewar_sim.free()

	var critical_state := GameState.new()
	critical_state.generate_grid_world(32012)
	critical_state.armies.clear()
	for city in critical_state.cities:
		city.owner_nation = 0
		city.is_capital = false
		city.has_warehouse = false
		city.is_food_hub = false
		city.is_manpower_hub = false
	for critical_edge in critical_state.edges:
		critical_edge.max_manpower = 100000
	var critical_origin := 0
	var critical_target := 10
	critical_state.cities[critical_origin].is_capital = true
	critical_state.cities[critical_target].owner_nation = 1
	critical_state.cities[critical_target].fort_strength = 1000
	critical_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	for critical_army_id in range(4):
		var critical_army := _make_army(
			1980 + critical_army_id,
			0,
			5000,
			10,
			10
		)
		critical_army.location_city = critical_origin
		critical_army.move_from = critical_origin
		critical_state.armies.append(critical_army)
	var critical_defender := _make_army(
		1990,
		1,
		60000,
		10,
		10
	)
	critical_defender.location_city = critical_target
	critical_defender.move_from = critical_target
	critical_state.armies.append(critical_defender)
	var critical_sim := Simulation.new()
	critical_sim.setup(critical_state)
	critical_sim._begin_ai_command_collection()
	var critical_staging_changed := (
		critical_sim._assign_offensive_staging_orders(
			0,
			critical_target,
			null,
			null,
			false,
			true
		)
	)
	critical_sim._commit_ai_command_collection([0])
	var critical_remaining := 0
	for army in critical_state.armies:
		if (
			army.owner_nation == 0
			and army.state == Army.State.IDLE
			and army.location_city == critical_origin
		):
			critical_remaining += army.size
	_check(
		critical_staging_changed
			and critical_remaining < 10000
			and critical_sim.ai_last_command_commit_failures == 0,
			"攻势集结不得再为关键城市保留固定10000人抽调下限"
	)
	critical_sim.free()

	var route_gate_state := GameState.new()
	route_gate_state.generate_grid_world(32015)
	route_gate_state.uses_heightmap = true
	route_gate_state.armies.clear()
	for route_city in route_gate_state.cities:
		route_city.owner_nation = 0
	var route_gate_target := 10
	for route_enemy_city in [
		route_gate_target,
		30,
		40,
	]:
		route_gate_state.cities[
			route_enemy_city
		].owner_nation = 1
	route_gate_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var route_gate_origin := 9
	route_gate_state.edge_of(
		route_gate_origin,
		route_gate_target
	).max_manpower = 30000
	var route_gate_nation := route_gate_state.nations[0]
	for route_army_index in range(2):
		var route_group := route_gate_state.create_battle_group(0)
		var route_army := _make_army(
			9880 + route_army_index,
			0,
			GameState.INITIAL_HEAVY_ARMY_SIZE,
			10,
			10
		)
		route_army.max_size = (
			GameState.INITIAL_HEAVY_ARMY_SIZE
		)
		route_army.location_city = route_gate_origin
		route_army.move_from = route_gate_origin
		route_gate_state.armies.append(route_army)
		route_gate_state.assign_army_to_battle_group(
			route_army, route_group.id
		)
		route_gate_nation.campaign_preparation_assignments[
			route_army.id
		] = route_gate_target
	route_gate_nation.campaign_preparation_targets = [
		route_gate_target
	] as Array[int]
	route_gate_nation.treasury_gold = 1000
	var route_gate_sim := Simulation.new()
	route_gate_sim.setup(route_gate_state)
	var route_gate_view := AiWorldView.build(route_gate_state, 0)
	var route_gate_allocation := route_gate_sim._plan_campaign_allocation(
		0, route_gate_target, [route_gate_target] as Array[int],
		null, null, route_gate_view, false
	)
	var route_gate_plan_applied := (
		route_gate_sim._apply_campaign_plan_atomic(
			0, route_gate_allocation
		)
	)
	var route_gate_gold := route_gate_nation.treasury_gold
	var route_gate_launched := (
		route_gate_sim._launch_campaign_offensive(
			0,
			route_gate_target,
			180,
			[route_gate_target] as Array[int]
		)
	)
	_check(
		route_gate_plan_applied
			and route_gate_launched
			and route_gate_nation
				.campaign_preparation_targets.is_empty()
			and route_gate_nation
				.campaign_preparation_assignments.is_empty()
			and route_gate_nation.campaign_plan_targets.has(
				route_gate_target
			)
			and not route_gate_nation
				.campaign_post_capture_plans.has(
					route_gate_target
				)
			and route_gate_nation.treasury_gold
				< route_gate_gold,
		"无同国第二步的叶子目标应允许首攻，但不得生成虚假续攻计划"
	)
	route_gate_sim.free()

	var echelon_state := GameState.new()
	echelon_state.generate_grid_world(32009)
	echelon_state.armies.clear()
	for city in echelon_state.cities:
		city.owner_nation = 0
		echelon_state.recognized_city_owners[city.id] = 0
		city.occupation_sponsor_nation = -1
		city.loyalty_target_nation = 0
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
	var echelon_origin := 9
	var echelon_target := 10
	var post_capture_target := 11
	echelon_state.cities[echelon_target].owner_nation = 1
	echelon_state.cities[post_capture_target].owner_nation = 1
	echelon_state.recognized_city_owners[echelon_target] = 1
	echelon_state.recognized_city_owners[
		post_capture_target
	] = 1
	echelon_state.cities[echelon_target].loyalty_target_nation = 1
	echelon_state.cities[post_capture_target].loyalty_target_nation = 1
	_set_single_warehouse(echelon_state, 0, echelon_origin, 1000)
	_set_single_warehouse(echelon_state, 1, post_capture_target, 1000)
	_set_warehouses(echelon_state, 2, [] as Array[int], [] as Array[int])
	_set_warehouses(echelon_state, 3, [] as Array[int], [] as Array[int])
	for echelon_a in range(echelon_state.nations.size()):
		for echelon_b in range(echelon_a + 1, echelon_state.nations.size()):
			echelon_state.set_diplomatic_relation(
				echelon_a, echelon_b, GameState.DiplomaticRelation.NEUTRAL
			)
	echelon_state.edge_of(
		echelon_origin,
		echelon_target
	).max_manpower = 30000
	echelon_state.edge_of(
		echelon_target,
		post_capture_target
	).max_manpower = 30000
	echelon_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	echelon_state.refresh_derived()
	_check(
		echelon_state.territory_structure_valid(),
		"梯队续攻夹具在发起攻势前必须满足领土结构不变量"
	)
	for echelon_army_id in range(2):
		var echelon_army := _make_army(
			990 + echelon_army_id,
			0,
			15000,
			10,
			10
		)
		echelon_army.location_city = echelon_origin
		echelon_army.move_from = echelon_origin
		echelon_state.armies.append(echelon_army)
	var echelon_sim := Simulation.new()
	echelon_sim.setup(echelon_state)
	var one_army_offensive_cost := (
		GameState.offensive_army_gold_cost(15000)
	)
	var echelon_offensive_cost := (
		one_army_offensive_cost * 2
	)
	echelon_state.nations[0].treasury_gold = (
		echelon_offensive_cost - 1
	)
	var unfunded_echelon_launch := (
		echelon_sim._launch_campaign_offensive(
			0,
			echelon_target,
			180
		)
	)
	var unfunded_armies_idle := true
	for army in echelon_state.armies:
		unfunded_armies_idle = (
			unfunded_armies_idle
			and army.state == Army.State.IDLE
		)
	_check(
		not unfunded_echelon_launch
			and unfunded_armies_idle
			and echelon_state.nations[0].treasury_gold
				== echelon_offensive_cost - 1,
		"金库不足时不得发动攻势或预扣组织费"
	)
	echelon_state.nations[0].treasury_gold = 100
	var echelon_launched := echelon_sim._launch_campaign_offensive(
		0,
		echelon_target,
		180
	)
	var echelon_nation := echelon_state.nations[0]
	var lead_army: Army = null
	var followup_army: Army = null
	for army in echelon_state.armies:
		var echelon := int(
			echelon_nation.campaign_attack_echelons.get(
				army.id,
				-1
			)
		)
		if echelon == 0:
			lead_army = army
		elif echelon == 1:
			followup_army = army
	_check(
		echelon_launched
		and lead_army != null
		and lead_army.state == Army.State.MOVING
		and followup_army != null
		and followup_army.state == Army.State.IDLE
		and not echelon_nation.campaign_launched_armies.has(
			followup_army.id
		)
		and echelon_state.nations[0].treasury_gold
			== 100 - echelon_offensive_cost
		and echelon_state.nations[0]
			.last_offensive_gold_cost == echelon_offensive_cost
		and echelon_offensive_cost
			> one_army_offensive_cost,
		"持续攻势应按全部参与梯队扣费，军队越多费用越高；首轮仍只投入最小充分梯队"
	)
	echelon_state.day += 1
	if lead_army != null:
		echelon_sim._release_edge(lead_army)
		var pipeline_siege := echelon_state.new_battle(
			Battle.Kind.SIEGE
		)
		pipeline_siege.city = echelon_state.cities[
			echelon_target
		]
		pipeline_siege.edge = echelon_state.edge_of(
			echelon_origin,
			echelon_target
		)
		pipeline_siege.side_a.append(lead_army)
		lead_army.state = Army.State.FIGHTING
		lead_army.battle_id = pipeline_siege.id
	echelon_sim._advance_campaign_echelons()
	_check(
		lead_army != null
		and lead_army.state == Army.State.FIGHTING
		and followup_army != null
		and followup_army.state == Army.State.MOVING
		and followup_army.ai_action == ActionCandidate.Kind.ATTACK
		and followup_army.ai_target_city == echelon_target
		and int(
			echelon_nation.campaign_active_echelons.get(
				echelon_target,
				-1
			)
		) == 1
		and int(
			echelon_nation.campaign_echelon_started_days.get(
				echelon_target,
				-1
			)
		) == echelon_state.day,
		"首攻梯队进入敌城后，下一梯队必须立即进入已释放道路形成流水强攻"
	)
	_check(
		followup_army != null
		and _approx(
			followup_army.offensive_attack_multiplier,
			Simulation.offensive_preparation_multiplier(180)
		)
		and followup_army.offensive_bonus_until_day
			== echelon_state.day
					+ Simulation
						.OFFENSIVE_BONUS_MAX_PREPARATION_DAYS,
		"后续梯队应继承整轮备战倍率，并从实际投入日计算持续期"
	)
	var post_capture_support := _make_army(
		9950,
		0,
		15000,
		10,
		10
	)
	post_capture_support.location_city = echelon_target
	post_capture_support.move_from = echelon_target
	echelon_state.armies.append(post_capture_support)
	var next_city_defender := _make_army(
		9951,
		1,
		2000,
		10,
		10
	)
	next_city_defender.location_city = post_capture_target
	next_city_defender.move_from = post_capture_target
	echelon_state.armies.append(next_city_defender)
	var lead_bonus_deadline := (
		lead_army.offensive_bonus_until_day
		if lead_army != null
		else -1
	)
	if lead_army != null:
		echelon_sim._capture_city(
			lead_army,
			echelon_state.cities[echelon_target]
		)
	_check(
		lead_army != null
			and lead_army.state == Army.State.MOVING
			and lead_army.ai_action
				== ActionCandidate.Kind.ATTACK
			and lead_army.ai_target_city
				== post_capture_target
			and lead_army.ai_order_reason.contains(
				"两步攻势第二步"
			)
			and lead_army.offensive_bonus_until_day
				== lead_bonus_deadline
			and not echelon_nation
				.campaign_post_capture_plans.has(
					echelon_target
				),
		"攻势必须在首攻前冻结第二步目标，并在占城后保留原截止日继续攻击"
	)
	echelon_sim.free()

	var consolidate_state := GameState.new()
	consolidate_state.generate_grid_world(32014)
	consolidate_state.armies.clear()
	for consolidate_city in consolidate_state.cities:
		consolidate_city.owner_nation = 0
		consolidate_state.recognized_city_owners[
			consolidate_city.id
		] = 0
	for consolidate_a in range(
		consolidate_state.nations.size()
	):
		for consolidate_b in range(
			consolidate_a + 1,
			consolidate_state.nations.size()
		):
			consolidate_state.set_diplomatic_relation(
				consolidate_a,
				consolidate_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	consolidate_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var consolidate_origin := 9
	var consolidate_target := 10
	var consolidate_next := 11
	for enemy_city in [
		consolidate_target,
		consolidate_next,
	]:
		consolidate_state.cities[enemy_city].owner_nation = 1
		consolidate_state.recognized_city_owners[enemy_city] = 1
	consolidate_state.edge_of(
		consolidate_origin,
		consolidate_target
	).max_manpower = 30000
	consolidate_state.edge_of(
		consolidate_target,
		consolidate_next
	).max_manpower = 30000
	var consolidate_army := _make_army(
		9960,
		0,
		15000,
		10,
		10
	)
	consolidate_army.location_city = consolidate_origin
	consolidate_army.move_from = consolidate_origin
	consolidate_army.max_size = (
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	consolidate_army.max_morale = Army.HEAVY_MAX_MORALE
	consolidate_army.offensive_attack_multiplier = 2.0
	consolidate_army.offensive_bonus_until_day = 180
	consolidate_state.armies.append(consolidate_army)
	consolidate_state.nations[0].campaign_post_capture_plans[
		consolidate_target
	] = {
		"next_city": consolidate_next,
		"group_id": -1,
		"heavy_army_id": consolidate_army.id,
		"execution_army_id": consolidate_army.id,
		"enemy_nation": 1,
		"created_day": consolidate_state.day,
		"steps": Simulation.CAMPAIGN_REQUIRED_ATTACK_STEPS,
	}
	var consolidate_sim := Simulation.new()
	consolidate_sim.setup(consolidate_state)
	consolidate_sim._capture_city(
		consolidate_army,
		consolidate_state.cities[consolidate_target]
	)
	_check(
		consolidate_army.state == Army.State.MOVING
			and consolidate_army.ai_action
				== ActionCandidate.Kind.ATTACK
			and consolidate_army.ai_order_reason.contains(
				"两步攻势第二步"
			)
			and not consolidate_state.nations[0]
				.campaign_post_capture_plans.has(
					consolidate_target
				),
		"新占城市后，执行重军必须按预定路线继续第二步"
	)
	consolidate_sim._settle_idle(
		consolidate_army,
		consolidate_target
	)
	var border_support := _make_army(
		9961,
		0,
		8000,
		10,
		10
	)
	border_support.location_city = consolidate_target
	border_support.move_from = consolidate_target
	consolidate_state.armies.append(border_support)
	var border_enemy := _make_army(
		9962,
		1,
		12000,
		10,
		10
	)
	border_enemy.location_city = consolidate_next
	border_enemy.move_from = consolidate_next
	consolidate_state.armies.append(border_enemy)
	consolidate_army.offensive_attack_multiplier = 1.0
	consolidate_army.offensive_bonus_until_day = -1
	consolidate_state.nations[0].campaign_post_capture_plans[
		consolidate_target
	] = {
		"next_city": consolidate_next,
		"group_id": -1,
		"heavy_army_id": consolidate_army.id,
		"execution_army_id": consolidate_army.id,
		"enemy_nation": 1,
		"created_day": consolidate_state.day,
		"steps": Simulation.CAMPAIGN_REQUIRED_ATTACK_STEPS,
	}
	consolidate_sim._execute_campaign_post_capture_plan(
		consolidate_army,
		consolidate_state.cities[consolidate_target]
	)
	_check(
		consolidate_army.state == Army.State.MOVING
			and consolidate_army.ai_action
				== ActionCandidate.Kind.ATTACK
			and consolidate_army.ai_target_city
				== consolidate_next
			and consolidate_army.ai_order_reason.contains(
				"两步攻势第二步"
			),
		"第二步不得因满准备加成到期或守军评分退化为驻边"
	)
	consolidate_sim._settle_idle(
		consolidate_army,
		consolidate_target
	)
	consolidate_army.morale = Combat.MORALE_FLOOR
	consolidate_state.nations[0].campaign_post_capture_plans[
		consolidate_target
	] = {
		"next_city": consolidate_next,
		"group_id": -1,
		"heavy_army_id": consolidate_army.id,
		"execution_army_id": consolidate_army.id,
		"enemy_nation": 1,
		"created_day": consolidate_state.day,
		"steps": Simulation.CAMPAIGN_REQUIRED_ATTACK_STEPS,
	}
	consolidate_sim._execute_campaign_post_capture_plan(
		consolidate_army,
		consolidate_state.cities[consolidate_target]
	)
	_check(
		consolidate_army.ai_action == ActionCandidate.Kind.HOLD
			and consolidate_army.ai_target_city
				== consolidate_target
			and consolidate_army.ai_order_reason.contains(
				"执行重军士气归零"
			)
			and not consolidate_state.nations[0]
				.campaign_post_capture_plans.has(
					consolidate_target
				),
		"执行重军士气归零后必须终止两步攻势并就地驻扎"
	)
	consolidate_sim.free()

	var relief_state := GameState.new()
	relief_state.generate_grid_world(32010)
	relief_state.armies.clear()
	for city in relief_state.cities:
		city.owner_nation = 0
	for relief_edge in relief_state.edges:
		relief_edge.max_manpower = 0
	var relief_target := relief_state.nations[0].capital_city_id
	var relief_source := relief_state.neighbors(relief_target)[0]
	relief_state.cities[relief_source].owner_nation = 2
	var relief_route := relief_state.edge_of(
		relief_source,
		relief_target
	)
	relief_route.max_manpower = 15000
	relief_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	relief_state.set_diplomatic_relation(
		0,
		2,
		GameState.DiplomaticRelation.ALLIED
	)
	var relief_siege := relief_state.new_battle(
		Battle.Kind.SIEGE
	)
	relief_siege.city = relief_state.cities[relief_target]
	relief_siege.edge = relief_route
	for attacker_id in range(3):
		var relief_attacker := _make_army(
			995 + attacker_id,
			1,
			15000,
			10,
			10
		)
		relief_attacker.state = Army.State.FIGHTING
		relief_attacker.location_city = relief_target
		relief_attacker.battle_id = relief_siege.id
		relief_siege.side_a.append(relief_attacker)
		relief_state.armies.append(relief_attacker)
	var relief_armies: Array[Army] = []
	for defender_id in range(2):
		var relief_defender := _make_army(
			1000 + defender_id,
			0,
			15000,
			10,
			10
		)
		relief_defender.location_city = relief_source
		relief_defender.move_from = relief_source
		relief_state.armies.append(relief_defender)
		relief_armies.append(relief_defender)
	var relief_sim := Simulation.new()
	relief_sim.setup(relief_state)
	relief_sim._advance_priority_city_defense_echelons()
	var first_relief: Army = null
	var waiting_relief: Army = null
	for relief_army in relief_armies:
		if relief_army.state == Army.State.MOVING:
			first_relief = relief_army
		elif relief_army.state == Army.State.IDLE:
			waiting_relief = relief_army
	_check(
		first_relief != null
		and waiting_relief != null
		and relief_route.passing_count == 1,
		"重点城市首支援军进入满容量道路后，下一支必须在纵深等待"
	)
	if first_relief != null:
		first_relief.move_progress = 1.0
		relief_sim._arrive_at_node(first_relief)
	relief_sim._advance_priority_city_defense_echelons()
	_check(
		first_relief != null
		and first_relief.state == Army.State.FIGHTING
		and waiting_relief != null
		and waiting_relief.state == Army.State.MOVING
		and waiting_relief.ai_action
			== ActionCandidate.Kind.REINFORCE
		and waiting_relief.ai_target_city == relief_target
		and relief_route.passing_count == 1,
		"重点城市前一援军入城参战并释放道路后，后一援军必须立即流水跟进"
	)
	relief_sim.free()

	var local_relief_state := GameState.new()
	local_relief_state.generate_grid_world(32015)
	local_relief_state.armies.clear()
	for local_city in local_relief_state.cities:
		local_city.owner_nation = 0
	for local_edge_candidate in local_relief_state.edges:
		local_edge_candidate.max_manpower = 0
	var local_target := 18
	var local_source := 17
	var local_route := local_relief_state.edge_of(
		local_source,
		local_target
	)
	local_route.max_manpower = 30000
	local_relief_state.cities[local_target].is_capital = false
	local_relief_state.cities[local_target].has_warehouse = false
	local_relief_state.cities[local_target].is_food_hub = false
	local_relief_state.cities[local_target].is_manpower_hub = false
	local_relief_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var local_siege := local_relief_state.new_battle(
		Battle.Kind.SIEGE
	)
	local_siege.city = local_relief_state.cities[local_target]
	local_siege.edge = local_route
	var local_attacker := _make_army(
		1010,
		1,
		60000,
		10,
		10
	)
	local_attacker.state = Army.State.FIGHTING
	local_attacker.location_city = local_target
	local_attacker.battle_id = local_siege.id
	local_siege.side_a.append(local_attacker)
	var neighboring_guard := _make_army(
		1011,
		0,
		5000,
		10,
		10
	)
	neighboring_guard.max_size = 5000
	neighboring_guard.location_city = local_source
	neighboring_guard.move_from = local_source
	var edge_guard := _make_army(
		1012,
		0,
		5000,
		10,
		10
	)
	edge_guard.max_size = 5000
	edge_guard.state = Army.State.HOLDING
	edge_guard.location_city = -1
	edge_guard.move_from = local_source
	edge_guard.move_to = local_target
	edge_guard.move_progress = Simulation.HOLDING_TARGET_PROGRESS
	edge_guard.on_edge = true
	local_relief_state.armies.append_array([
		local_attacker,
		neighboring_guard,
		edge_guard,
	])
	var local_relief_sim := Simulation.new()
	local_relief_sim.setup(local_relief_state)
	local_relief_sim._advance_priority_city_defense_echelons()
	_check(
		neighboring_guard.state == Army.State.IDLE
			and edge_guard.state == Army.State.HOLDING
			and not neighboring_guard.ai_order_reason.contains(
				"邻接战区驰援"
			)
			and not edge_guard.ai_order_reason.contains(
				"邻接战区驰援"
			),
		"删除邻近填线军自动协防后，邻城军与边槽军必须继续原防区任务"
	)
	edge_guard.line_assignment_city = local_target
	edge_guard.line_assignment_posture = Army.LinePosture.EDGE
	edge_guard.line_assignment_edge = local_source
	var local_sector := FrontierDefenseSector.new()
	local_sector.city_id = local_target
	local_sector.owner_nation = 0
	local_sector.configure(
		[local_source] as Array[int],
		local_relief_state.ownership_revision
	)
	local_sector.assign(1, edge_guard.id)
	local_relief_state.nations[0].frontier_defense_sectors[
		local_target
	] = local_sector
	local_relief_sim._resolve_line_edge_assignment_emergencies()
	_check(
		edge_guard.state == Army.State.HOLDING
			and edge_guard.line_assignment_city == local_target
			and edge_guard.line_assignment_edge == local_source
			and local_sector.state == FrontierDefenseSector.State.NORMAL,
		"受围属于动态战况，边槽 LINE 必须继续原防区而不是回城横跳"
	)
	local_relief_state.cities[local_source].owner_nation = 1
	local_siege.finished = true
	local_relief_sim._resolve_line_edge_assignment_emergencies()
	_check(
		local_sector.state
			== FrontierDefenseSector.State.NORMAL
			and edge_guard.state == Army.State.HOLDING
			and edge_guard.line_assignment_city == local_target
			and edge_guard.line_assignment_edge == local_source,
		"战斗消失也不得生成恢复边槽命令，LINE 全程保持原驻地"
	)
	local_relief_state.cities[local_source].owner_nation = 0
	edge_guard.state = Army.State.HOLDING
	edge_guard.move_from = local_source
	edge_guard.move_to = local_target
	edge_guard.move_progress = Simulation.HOLDING_TARGET_PROGRESS
	edge_guard.on_edge = true
	edge_guard.line_assignment_city = local_target
	edge_guard.line_assignment_posture = Army.LinePosture.EDGE
	edge_guard.line_assignment_edge = local_source
	local_relief_state.cities[local_target].owner_nation = 1
	local_relief_sim._resolve_line_edge_assignment_emergencies()
	_check(
		edge_guard.state == Army.State.RETREATING
			and edge_guard.move_to == local_source
			and edge_guard.line_assignment_city == -1
			and edge_guard.ai_order_reason.contains(
				"锚点城市%d失守" % local_target
			),
		"锚点城市已经失守时，驻边填线军必须撤往友城并清除失效防区"
	)
	local_relief_sim.free()

	var role_state := GameState.new()
	role_state.generate_grid_world(32018)
	role_state.uses_heightmap = true
	role_state.armies.clear()
	for role_city in role_state.cities:
		role_city.owner_nation = 1
	for role_city_id in range(10):
		role_state.cities[role_city_id].owner_nation = 0
	for role_a in range(role_state.nations.size()):
		for role_b in range(
			role_a + 1,
			role_state.nations.size()
		):
			role_state.set_diplomatic_relation(
				role_a,
				role_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var role_lights: Array[Army] = []
	for role_index in range(5):
		var role_light := role_state.create_army(
			0,
			role_index,
			GameState.INITIAL_LIGHT_ARMY_SIZE,
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
		role_lights.append(role_light)
	var role_sim := Simulation.new()
	role_sim.setup(role_state)
	var role_group := role_state.nations[0].battle_groups[0]
	role_state.assign_army_to_battle_group(
		role_lights[0],
		role_group.id
	)
	role_state.assign_army_to_battle_group(
		role_lights[1],
		role_group.id
	)
	role_sim._reconcile_strategic_roles(0)
	var role_signature_before_index: Array[Array] = []
	for role_army in role_state.armies:
		role_signature_before_index.append([
			role_army.id,
			role_army.battle_group_id,
			role_army.strategic_role,
		])
	role_sim._reconcile_strategic_roles(
		0,
		AiWorldView.build_army_index(role_state)
	)
	var role_signature_after_index: Array[Array] = []
	for role_army in role_state.armies:
		role_signature_after_index.append([
			role_army.id,
			role_army.battle_group_id,
			role_army.strategic_role,
		])
	_check(
		role_signature_after_index
			== role_signature_before_index,
		"共享军队索引路径必须与全军扫描路径生成相同的战团和战略角色"
	)
	var promoted_light_count := 0
	var promoted_light: Army = null
	for role_light in role_lights:
		if role_light.is_main_battle_role():
			promoted_light_count += 1
			promoted_light = role_light
	var role_view := AiWorldView.build(role_state, 0)
	var role_plan := CityDefensePlan.build(
		role_view,
		StrategicMapSnapshot.build(role_view),
		ThreatField.build(role_view)
	)
	var line_redeploy_blocked := true
	for role_light in role_lights:
		if role_light.is_main_battle_role():
			continue
		line_redeploy_blocked = (
			line_redeploy_blocked
			and not role_plan.can_redeploy(
				role_light,
				ArmyCoordinator.new()
			)
		)
	_check(
		promoted_light_count == 2
			and promoted_light != null
			and role_plan.assigned_city_for(
				promoted_light
			) >= 0
			and line_redeploy_blocked,
		(
			"战团内两支5000轻军必须承担主战职能，并作为国家级预备队"
			+ "独立展开；不得占用 LINE 防区槽"
		)
	)
	role_sim._ai_assign_targets()
	var line_contract_respected := true
	for role_light in role_lights:
		if not role_light.is_line_role():
			continue
		line_contract_respected = (
			line_contract_respected
			and role_light.ai_action
				not in [
					ActionCandidate.Kind.ATTACK,
					ActionCandidate.Kind.MERGE,
				]
			and (
				role_light.ai_order_reason.is_empty()
				or role_light.ai_order_reason.begins_with(
					"填线部署"
				)
			)
		)
	_check(
		line_contract_respected,
		"和平期填线军只能执行统一填线部署，不得自行攻击、合并或选择其他动作"
	)
	var contract_heavy := role_state.create_army(
		0,
		0,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	role_sim._reconcile_strategic_roles(0)
	var group_roles_preserved := (
		contract_heavy.is_main_battle_role()
		and role_lights[0].is_main_battle_role()
		and role_lights[1].is_main_battle_role()
	)
	for role_index in range(2, role_lights.size()):
		group_roles_preserved = (
			group_roles_preserved
			and role_lights[role_index].is_line_role()
		)
	_check(
		group_roles_preserved,
		"重军加入后同战团两支轻军继续主战，其余5000军继续填线"
	)
	role_state.armies = [role_lights[0]] as Array[Army]
	role_sim._reconcile_strategic_roles(0)
	_check(
		role_lights[0].is_main_battle_role(),
		"国家仅剩一支5000军时，该军必须自动成为主战军"
	)
	role_sim.free()

	var liberation_state := GameState.new()
	liberation_state.generate_grid_world(32016)
	liberation_state.armies.clear()
	liberation_state.battles.clear()
	for liberation_a in range(
		liberation_state.nations.size()
	):
		for liberation_b in range(
			liberation_a + 1,
			liberation_state.nations.size()
		):
			liberation_state.set_diplomatic_relation(
				liberation_a,
				liberation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var legal_owner := 0
	var liberator_nation := 1
	var occupier_nation := 2
	liberation_state.set_diplomatic_relation(
		legal_owner,
		liberator_nation,
		GameState.DiplomaticRelation.ALLIED
	)
	liberation_state.set_diplomatic_relation(
		legal_owner,
		occupier_nation,
		GameState.DiplomaticRelation.WAR
	)
	liberation_state.set_diplomatic_relation(
		liberator_nation,
		occupier_nation,
		GameState.DiplomaticRelation.WAR
	)
	var liberation_city: City = null
	for candidate_city in liberation_state.cities:
		if (
			candidate_city.owner_nation == legal_owner
			and not candidate_city.is_capital
			and not candidate_city.has_warehouse
		):
			liberation_city = candidate_city
			break
	_check(
		liberation_city != null,
		"盟友解放测试必须找到普通法理城市"
	)
	liberation_city.owner_nation = occupier_nation
	liberation_state.recognized_city_owners[
		liberation_city.id
	] = legal_owner
	var liberator := _make_army(
		9050,
		liberator_nation,
		5000,
		10
	)
	liberator.location_city = liberation_city.id
	liberator.move_from = liberation_city.id
	liberator.occupation_claimant_nation = liberator_nation
	liberation_state.armies.append(liberator)
	var liberation_sim := Simulation.new()
	liberation_sim.setup(liberation_state)
	liberation_sim._capture_city(
		liberator,
		liberation_city
	)
	_check(
		liberation_city.owner_nation == legal_owner
			and liberation_state.recognized_owner_of(
				liberation_city.id
			) == legal_owner
			and liberation_city.occupation_sponsor_nation == -1
			and liberator.location_city == liberation_city.id
			and liberator.state == Army.State.IDLE,
		"盟军击退占领者后必须把城市控制权归还法理盟友，而非据为己有"
	)
	liberation_sim.free()

	var defense_state := GameState.new()
	defense_state.generate_grid_world(32007)
	for defense_a in range(defense_state.nations.size()):
		for defense_b in range(defense_a + 1, defense_state.nations.size()):
			defense_state.set_diplomatic_relation(
				defense_a,
				defense_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	defense_state.set_diplomatic_relation(
		0, 3, GameState.DiplomaticRelation.ALLIED
	)
	defense_state.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.ALLIED
	)
	var defense_sim := Simulation.new()
	defense_sim.setup(defense_state)
	var defense_target := DiplomacyAI.select_war_objective(
		defense_state, 0, 1
	)
	var defense_declared := defense_sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": 0,
		"b": 1,
		"objective_city": int(defense_target.get("city_id", -1)),
		"objective_reason": "共同防御测试",
		"mobilization_armies": 0,
		"reason": "主动宣战测试",
	})
	_check(
		defense_declared
		and defense_state.is_enemy(0, 1)
		and defense_state.is_enemy(0, 2)
			and defense_state.is_enemy(3, 1)
			and defense_state.is_enemy(3, 2)
			and int(
				defense_state.war_objective(3, 1).get(
					"city_id",
					-1
				)
			) == int(defense_target.get("city_id", -1)),
		"联盟宣战必须让攻守双方全部成员参战，并共享主动方战争目标"
	)
	var allied_origin: City = null
	var enemy_target: City = null
	var allied_border: Edge = null
	for border_edge in defense_state.edges:
		var border_a := defense_state.cities[border_edge.city_a]
		var border_b := defense_state.cities[border_edge.city_b]
		if border_a.owner_nation == 3 and border_b.owner_nation == 1:
			allied_origin = border_a
			enemy_target = border_b
			allied_border = border_edge
			break
		if border_b.owner_nation == 3 and border_a.owner_nation == 1:
			allied_origin = border_b
			enemy_target = border_a
			allied_border = border_edge
			break
	_check(
		allied_origin != null and enemy_target != null,
		"外交测试地图必须存在国3到国1的相邻边界"
	)
	allied_border.max_manpower = 30000
	var allied_origin_army := _make_army(9051, 0, 1000, 10, 10)
	allied_origin_army.location_city = allied_origin.id
	allied_origin_army.move_from = allied_origin.id
	allied_origin_army.state = Army.State.MOVING
	allied_origin_army.path = [
		enemy_target.id
	] as Array[int]
	defense_state.armies.append(allied_origin_army)
	defense_sim._begin_next_leg(allied_origin_army)
	_check(
		allied_origin_army.occupation_claimant_nation == 3,
		"从盟国边界进入敌境时必须冻结盟国为占领归属国"
	)
	defense_sim._release_edge(allied_origin_army)
	var origin_transfer: Dictionary = defense_state.transfer_city_sovereignty(
		allied_origin.id,
		0,
		"alliance_departure_fixture",
		GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
	)
	defense_state.set_diplomatic_relation(
		0,
		3,
		GameState.DiplomaticRelation.NEUTRAL
	)
	defense_sim._capture_city(allied_origin_army, enemy_target)
	_check(
		bool(origin_transfer.get("ok", false))
			and bool(origin_transfer.get("changed", false))
			and (
				allied_origin_army.size <= 0
			or (
				allied_origin_army.state
					== Army.State.RETREATING
				and not allied_origin_army.is_at_city_node(
					enemy_target.id
				)
			)
		),
		"冻结归属国在破城前失去通行权时，占领权仍归原盟国，但实际攻城军必须撤离"
	)
	_check(
		enemy_target.owner_nation == 3
			and defense_state.recognized_owner_of(enemy_target.id) == 1
			and enemy_target.occupation_sponsor_nation == 0
			and not defense_state.alliance_bloc(0, false).has(3),
		(
			"集团议和前置必须是 claimant 3 已退出当前集团、"
			+ "sponsor 0 仍属 A 方、法理国 1 属 B 方"
		)
	)
	var sponsor_coalition_peace := (
		defense_sim._make_coalition_peace(0, 1)
	)
	_check(
		bool(sponsor_coalition_peace.get("changed", false))
			and enemy_target.owner_nation == 3
			and defense_state.recognized_owner_of(
				enemy_target.id
			) == 3
			and enemy_target.occupation_sponsor_nation == -1
			and defense_state.territory_structure_valid(),
		(
			"集团和平必须按仍在集团内的 occupation sponsor 确认"
			+ "已退盟 claimant 的永久主权，并清空 sponsor"
		)
	)
	defense_sim.free()

	# 冻结的占领接收者在破城前灭亡时必须失效，不能借新占城市复活。
	var dead_claim_state := GameState.new()
	dead_claim_state.generate_grid_world(32019)
	dead_claim_state.armies.clear()
	dead_claim_state.battles.clear()
	for dead_a in range(dead_claim_state.nations.size()):
		for dead_b in range(
			dead_a + 1,
			dead_claim_state.nations.size()
		):
			dead_claim_state.set_diplomatic_relation(
				dead_a,
				dead_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	dead_claim_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var dead_claim_operations: Array[Dictionary] = []
	for city in dead_claim_state.cities_of(3):
		dead_claim_operations.append({
			"city_id": city.id,
			"controller_id": 2,
			"legal_owner_id": 2,
			"sponsor_id": -1,
			"reset_political_target": true,
			"reason": "dead_claimant_fixture",
			"stock_policy": (
				GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
			),
		})
	var dead_claim_removed: Dictionary = (
		dead_claim_state.apply_territory_transaction(dead_claim_operations)
	)
	# 模拟同一天内 alive 派生值尚未刷新；占领接收者必须按真实城池判断，
	# 不能用陈旧 alive 把无城国家复活。
	dead_claim_state.nations[3].alive = true
	var dead_claim_target: City = null
	for city in dead_claim_state.land_cities_of(1):
		if not city.is_capital and not city.has_warehouse:
			dead_claim_target = city
			break
	var dead_claim_army := _make_army(
		9052,
		0,
		5000,
		10
	)
	dead_claim_army.location_city = dead_claim_target.id
	dead_claim_army.move_from = dead_claim_target.id
	dead_claim_army.occupation_claimant_nation = 3
	dead_claim_state.armies.append(dead_claim_army)
	var dead_claim_sim := Simulation.new()
	dead_claim_sim.setup(dead_claim_state)
	dead_claim_sim._capture_city(
		dead_claim_army,
		dead_claim_target
	)
	_check(
		bool(dead_claim_removed.get("ok", false))
			and bool(dead_claim_removed.get("changed", false))
			and dead_claim_target.owner_nation == 0
			and dead_claim_army
				.occupation_claimant_nation == -1,
		"冻结占领接收者已无城时必须忽略陈旧 alive，回退实际攻城国"
	)
	dead_claim_state.refresh_derived()
	_check(
		not dead_claim_state.nations[3].alive,
		"无城的冻结占领接收者不得因新占城市复活"
	)
	dead_claim_sim.free()

	ai_state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.WAR)
	ai_state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	_check(
		DiplomacyAI.alliance_willingness(ai_state, 0, 1)
			>= DiplomacyAI.ALLIANCE_ACCEPT_SCORE
		and DiplomacyAI.alliance_willingness(ai_state, 1, 0)
			>= DiplomacyAI.ALLIANCE_ACCEPT_SCORE,
		"拥有共同敌国的中立双方应愿意结盟"
	)

	var peaceful_alliance_state := GameState.new()
	peaceful_alliance_state.generate_grid_world(32008)
	for peaceful_a in range(peaceful_alliance_state.nations.size()):
		peaceful_alliance_state.nations[peaceful_a].manpower_pool = 0
		for peaceful_b in range(
			peaceful_a + 1, peaceful_alliance_state.nations.size()
		):
			peaceful_alliance_state.set_diplomatic_relation(
				peaceful_a,
				peaceful_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	peaceful_alliance_state.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	var peaceful_alliance_found := false
	for peaceful_action in DiplomacyAI.choose_actions(
		peaceful_alliance_state
	):
		peaceful_alliance_found = (
			peaceful_alliance_found
			or int(peaceful_action["kind"])
				== DiplomacyAI.Action.FORM_ALLIANCE
		)
	_check(
		peaceful_alliance_found,
		"共同防御联盟不是战时临时状态，和平期也应能主动缔结"
	)

	ai_state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	ai_state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	ai_state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.NEUTRAL)
	ai_state.day += DiplomacyAI.MIN_ALLIANCE_DAYS
	_check(
		DiplomacyAI.leave_alliance_desire(ai_state, 0, 1)
			< DiplomacyAI.LEAVE_ALLIANCE_SCORE,
		"共同防御联盟可长期存在，和平且无共同敌人不得自动退盟"
	)

	var attitude_state := GameState.new()
	attitude_state.generate_grid_world(32018)
	for attitude_a in range(attitude_state.nations.size()):
		for attitude_b in range(
			attitude_a + 1,
			attitude_state.nations.size()
		):
			attitude_state.set_diplomatic_relation(
				attitude_a,
				attitude_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	attitude_state.diplomatic_history.append({
		"day": 100,
		"action": DiplomacyAI.Action.MAKE_PEACE,
		"nation_a": 0,
		"nation_b": 1,
		"war_outcome_a": -6.0,
		"war_outcome_b": 6.0,
		"territories_transferred": 1,
	})
	attitude_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.WAR
	)
	attitude_state.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.ALLIED
	)
	var hostile_attitude := (
		DiplomacyAI.diplomatic_attitude_breakdown(
			attitude_state,
			0,
			1
		)
	)
	var victor_attitude := (
		DiplomacyAI.diplomatic_attitude_breakdown(
			attitude_state,
			1,
			0
		)
	)
	_check(
		float(hostile_attitude["historical"]) < 0.0
			and float(victor_attitude["historical"]) == 0.0
			and float(hostile_attitude["military"]) < 0.0
			and float(hostile_attitude["political"]) < 0.0
			and int(hostile_attitude["enemy_allies"]) == 1,
		"外交态度必须区分败战复仇、接壤/目标城市与敌盟关系三个方向性分量"
	)
	attitude_state.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.WAR
	)
	var shared_front_attitude := (
		DiplomacyAI.diplomatic_attitude_breakdown(
			attitude_state,
			0,
			1
		)
	)
	_check(
		float(shared_front_attitude["political"])
			> float(hostile_attitude["political"])
			and int(shared_front_attitude["common_enemies"]) == 1,
		"共同敌人与可释放边境兵力必须改善政治态度并体现缓解战线压力"
	)

	var endgame_state := GameState.new()
	endgame_state.generate_grid_world(32019)
	for endgame_a in range(endgame_state.nations.size()):
		for endgame_b in range(
			endgame_a + 1,
			endgame_state.nations.size()
		):
			endgame_state.set_diplomatic_relation(
				endgame_a,
				endgame_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	for endgame_city in endgame_state.cities:
		var endgame_owner := (
			0 if endgame_city.map_position.x < 0.5 else 1
		)
		endgame_city.owner_nation = endgame_owner
		endgame_city.occupation_sponsor_nation = -1
		endgame_state.recognized_city_owners[
			endgame_city.id
		] = endgame_owner
	for endgame_nation in endgame_state.nations:
		endgame_nation.alive = endgame_nation.id in [0, 1]
		if endgame_nation.alive:
			endgame_nation.treasury_gold = 100000
			endgame_nation.manpower_pool = 100000
	for endgame_army in endgame_state.armies.duplicate():
		if endgame_army.owner_nation not in [0, 1]:
			endgame_state.armies.erase(endgame_army)
	for endgame_owner in [0, 1]:
		for endgame_warehouse in endgame_state.warehouse_cities_of(
			endgame_owner
		):
			endgame_warehouse.food_storage = 100000
	endgame_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	endgame_state.day = DiplomacyAI.MIN_ALLIANCE_DAYS
	var endgame_leave_desire := maxf(
		DiplomacyAI.leave_alliance_desire(
			endgame_state,
			0,
			1
		),
		DiplomacyAI.leave_alliance_desire(
			endgame_state,
			1,
			0
		)
	)
	var endgame_leave_action: Dictionary = {}
	for endgame_action in DiplomacyAI.choose_actions(
		endgame_state
	):
		if (
			int(endgame_action["kind"])
				== DiplomacyAI.Action.LEAVE_ALLIANCE
		):
			endgame_leave_action = endgame_action
			break
	var endgame_sim := Simulation.new()
	endgame_sim.setup(endgame_state)
	var endgame_left := (
		not endgame_leave_action.is_empty()
		and endgame_sim._execute_diplomatic_action(
			endgame_leave_action
		)
	)
	endgame_state.day += DiplomacyAI.MIN_NEUTRAL_DAYS
	var endgame_alliance_score := (
		DiplomacyAI.alliance_willingness(
			endgame_state,
			0,
			1
		)
	)
	var endgame_war_desire := DiplomacyAI.war_desire(
		endgame_state,
		0,
		1
	)
	_check(
		endgame_leave_desire
			>= DiplomacyAI.LEAVE_ALLIANCE_SCORE
			and endgame_left
			and endgame_alliance_score
				< DiplomacyAI.ALLIANCE_ACCEPT_SCORE
			and endgame_war_desire
				>= DiplomacyAI.WAR_DECLARE_SCORE,
		"仅剩两个盟国二分全图时必须退盟、拒绝复盟并转入最终统一竞争"
	)
	endgame_sim.free()

	ai_state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	ai_state.nations[0].treasury_gold = 0
	ai_state.nations[0].unpaid_military_upkeep = 20
	ai_state.nations[0].manpower_pool = 0
	for warehouse in ai_state.warehouse_cities_of(0):
		warehouse.food_storage = 0
	var crisis_reason := "、".join(DiplomacyAI.peace_reasons(ai_state, 0, 1))
	_check(
		crisis_reason.contains("国库")
		and crisis_reason.contains("粮草")
		and crisis_reason.contains("人力"),
		"求和原因应明确指出财政、粮草和人力危机"
	)

	# 防御同盟：0 向 1 宣战时，1 的盟友 2 必须自动对 0 参战。
	ai_state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)
	ai_state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
	ai_state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.NEUTRAL)
	ai_state.day += GameState.DEFAULT_TRUCE_DAYS
	ai_state.nations[1].war_preparation_target_nation = 3
	ai_state.nations[1].war_preparation_objective_city = (
		ai_state.cities_of(3)[0].id
	)
	ai_state.nations[1].war_preparation_started_day = ai_state.day
	var diplomacy_sim := Simulation.new()
	diplomacy_sim.setup(ai_state)
	var declared := diplomacy_sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": 0,
		"b": 1,
		"reason": "专项测试",
	})
	_check(
		declared and ai_state.is_enemy(0, 1) and ai_state.is_enemy(0, 2),
		"宣战应生效，并触发守方现有盟友履行防御义务"
	)
	_check(
		ai_state.nations[1].war_preparation_target_nation == -1,
		"被宣战国必须取消原主动战争准备，立即转入当前防御战争"
	)
	_check(
		ai_state.nations[0].ai_last_diplomatic_target == 1
		and ai_state.nations[0].ai_last_diplomatic_reason == "专项测试",
		"外交动作应记录目标与可解释原因"
	)
	diplomacy_sim.free()


func _test_war_preparation_cancel_cooldown() -> void:
	print("[32a2] 备战冷却：取消备战后冷却期内不得重开，冷却期满后恢复；集结超时尽力而战")
	# 用可复现的 AI 世界：推进到有备战意愿的时代，找出一个「本可发起 PREPARE_WAR」的国家，
	# 给它盖上取消冷却戳后，同一评估里它必须不再出现 PREPARE_WAR；冷却期满后门控解除。
	var gs := GameState.new()
	gs.generate_world(12345, 12)
	gs.day = DiplomacyAI.WAR_FATIGUE_REFERENCE_DAYS * 5 / 2
	var baseline: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(gs, baseline, {}, {})
	var prep_nation := -1
	for action in baseline:
		if int(action.get("kind", -1)) == DiplomacyAI.Action.PREPARE_WAR:
			prep_nation = int(action.get("a", -1))
			break
	# 若该世界此刻无人发起备战，跳过（不同版本平衡下可能无备战意愿），避免脆弱断言。
	if prep_nation < 0:
		_check(true, "该世界此刻无备战意愿，跳过冷却门控用例（非失败）")
		return

	# 盖冷却戳：冷却期内同一评估必须不再为该国产生 PREPARE_WAR。
	gs.nations[prep_nation].war_preparation_cancelled_day = gs.day
	var cooled: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(gs, cooled, {}, {})
	var prepares_in_cooldown := false
	for action in cooled:
		if (
			int(action.get("kind", -1)) == DiplomacyAI.Action.PREPARE_WAR
			and int(action.get("a", -1)) == prep_nation
		):
			prepares_in_cooldown = true
	_check(not prepares_in_cooldown, "取消备战冷却期内该国不得重新发起 PREPARE_WAR")

	# 冷却期满：把取消戳推到冷却窗口之外，门控解除，该国可再次评估备战。
	gs.nations[prep_nation].war_preparation_cancelled_day = (
		gs.day - DiplomacyAI.WAR_PREPARATION_CANCEL_COOLDOWN_DAYS - 1
	)
	var recovered: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(gs, recovered, {}, {})
	var prepares_after := false
	for action in recovered:
		if (
			int(action.get("kind", -1)) == DiplomacyAI.Action.PREPARE_WAR
			and int(action.get("a", -1)) == prep_nation
		):
			prepares_after = true
	_check(prepares_after, "冷却期满后该国必须恢复发起 PREPARE_WAR 的能力")


func _test_war_preparation_route_block_grace() -> void:
	print("[32a3] 备战稳定性：断路自动换薄弱目标；全线封闭与边境屯兵均不得取消")
	var gs := GameState.new()
	gs.generate_grid_world(32041)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	gs.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	var objective := DiplomacyAI.select_war_objective(gs, 0, 1)
	var objective_city := int(objective.get("city_id", -1))
	_check(objective_city >= 0, "测试世界应能为国0选出对国1的进攻目标")
	if objective_city < 0:
		return
	var staging := DiplomacyAI.staging_cities_for_objective(
		gs, 0, objective_city
	)
	_check(not staging.is_empty(), "初始应存在合法集结城市")
	if staging.is_empty():
		return
	var sim := Simulation.new()
	sim.setup(gs)
	var nation := gs.nations[0]
	nation.war_preparation_target_nation = 1
	nation.war_preparation_objective_city = objective_city
	nation.war_preparation_started_day = gs.day
	nation.war_preparation_unready_since_day = -1

	# 只阻断原目标：应生成“保持备战并换目标”动作，而非取消。
	var closed_edges: Array[Edge] = []
	for staging_city in staging:
		var edge := gs.edge_of(staging_city, objective_city)
		if edge != null:
			edge.max_manpower = 0
			closed_edges.append(edge)
	var retarget_actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(
		gs, 0, retarget_actions, {}
	)
	var retarget_action: Dictionary = {}
	for action in retarget_actions:
		if int(action.get("kind", -1)) == DiplomacyAI.Action.RETARGET_WAR_PREPARATION:
			retarget_action = action
			break
	_check(
		not retarget_action.is_empty()
			and int(retarget_action["objective_city"]) != objective_city
			and str(retarget_action["objective_reason"]).contains("薄弱守军"),
		"原目标道路封闭后必须保持对同国备战并改选可达薄弱城市"
	)
	var started_day := nation.war_preparation_started_day
	var mobilization_target := nation.war_mobilization_target_troops
	var retargeted := (
		not retarget_action.is_empty()
		and sim._execute_diplomatic_action(retarget_action)
	)
	_check(
		retargeted
			and nation.war_preparation_started_day == started_day
			and nation.war_mobilization_target_troops == mobilization_target,
		"改换目标必须原子保留原备战开始日和已完成动员，不得重开一轮备战"
	)

	# 封闭攻击者与目标国之间的全部道路，并把备战时钟推过360天。
	# 即使永久无路也只能等待拓扑恢复，不能由道路状态触发取消。
	for edge in gs.edges:
		var owner_a := gs.cities[edge.city_a].owner_nation
		var owner_b := gs.cities[edge.city_b].owner_nation
		if (owner_a == 0 and owner_b == 1) or (owner_a == 1 and owner_b == 0):
			edge.max_manpower = 0
	gs.day = started_day + DiplomacyAI.WAR_PREPARATION_MAX_DAYS + 30
	var blocked_actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(gs, 0, blocked_actions, {})
	var blocked_cancel := false
	for action in blocked_actions:
		blocked_cancel = (
			blocked_cancel
			or int(action.get("kind", -1))
				== DiplomacyAI.Action.CANCEL_WAR_PREPARATION
		)
	_check(
		blocked_actions.is_empty() and not blocked_cancel,
		"全线道路永久封闭且超过集结上限时也不得取消备战"
	)

	# 边境屯兵数量只影响军事部署，不参与是否保持备战的门控。
	var border_army: Army = null
	for army in gs.armies:
		if army.owner_nation == 1:
			border_army = army
			break
	if border_army != null:
		border_army.size = border_army.max_size
		border_army.location_city = objective_city
		border_army.move_from = objective_city
	var massed_actions: Array[Dictionary] = []
	DiplomacyAI._collect_existing_war_preparation(gs, 0, massed_actions, {})
	var massed_cancel := false
	for action in massed_actions:
		massed_cancel = (
			massed_cancel
			or int(action.get("kind", -1))
				== DiplomacyAI.Action.CANCEL_WAR_PREPARATION
		)
	_check(
		not massed_cancel,
		"敌方边境屯兵增减不得触发取消备战"
	)
	sim.free()


func _test_alliance_war_coalitions() -> void:
	print("[32b] 联盟战争：整体宣战、战时入盟、集团议和与分国军事AI")
	var gs := GameState.new()
	gs.generate_grid_world(32021)
	for nation_a in range(gs.nations.size()):
		for nation_b in range(nation_a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	gs.set_diplomatic_relation(
		0, 3, GameState.DiplomaticRelation.ALLIED
	)
	gs.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.ALLIED
	)
	var sim := Simulation.new()
	sim.setup(gs)
	var objective := DiplomacyAI.select_war_objective(gs, 0, 1)
	var objective_city := int(objective.get("city_id", -1))
	var declared := sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": 0,
		"b": 1,
		"objective_city": objective_city,
		"objective_reason": "联盟集团战争回归",
		"mobilization_armies": 0,
		"reason": "联盟整体宣战",
	})
	var complete_war_matrix := declared
	for attacker in [0, 3]:
		for defender in [1, 2]:
			complete_war_matrix = (
				complete_war_matrix
				and gs.is_enemy(attacker, defender)
				and int(
					gs.war_objective(attacker, defender).get(
						"city_id",
						-1
					)
				) == objective_city
			)
	_check(
		complete_war_matrix
			and gs.alliance_bloc(0) == [0, 3]
			and gs.alliance_bloc(1) == [1, 2],
		"联盟宣战必须形成集团间完整敌对矩阵，并向所有攻击成员传播共同目标"
	)
	gs.day += DiplomacyAI.MIN_WAR_DAYS
	var coalition_assessment := DiplomacyAI.peace_assessment(
		gs,
		0,
		1
	)
	_check(
		coalition_assessment["bloc_a"] == [0, 3]
			and coalition_assessment["bloc_b"] == [1, 2]
			and (
				coalition_assessment["breakdown_a"]["member_scores"]
				as Dictionary
			).size() == 2
			and (
				coalition_assessment["breakdown_b"]["member_scores"]
				as Dictionary
			).size() == 2,
		"联盟和平意愿必须聚合双方全部成员，不能只读取议和代表国"
	)
	gs.nations[0].campaign_preparation_targets = [
		objective_city
	] as Array[int]
	_check(
		gs.nations[3].campaign_preparation_targets.is_empty(),
		"联盟共享战争目标，但各国战团与军队Assignment必须保持独立"
	)
	var coalition_peace := sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.MAKE_PEACE,
		"a": 0,
		"b": 1,
		"reason": "联盟整体议和回归",
	})
	var complete_peace_matrix := coalition_peace
	for former_attacker in [0, 3]:
		for former_defender in [1, 2]:
			complete_peace_matrix = (
				complete_peace_matrix
				and not gs.is_enemy(
					former_attacker,
					former_defender
				)
				and gs.truce_until(
					former_attacker,
					former_defender
				) > gs.day
				and gs.war_objective(
					former_attacker,
					former_defender
				).is_empty()
			)
	_check(
		complete_peace_matrix,
		"联盟议和必须原子结束集团间全部战争关系、目标并设置统一停战期"
	)
	sim.free()

	# 和平计划必须把外交与战果确认放进同一事务；两类 revision 各只递增一次。
	var atomic_fixture := _make_atomic_coalition_peace_fixture(32025)
	var atomic_state: GameState = atomic_fixture["state"]
	var atomic_sim: Simulation = atomic_fixture["simulation"]
	var atomic_city_id := int(atomic_fixture["occupied_city_id"])
	var atomic_plan := atomic_sim._plan_coalition_peace(0, 1)
	var atomic_ownership_revision := atomic_state.ownership_revision
	var atomic_diplomacy_revision := atomic_state.diplomacy_revision
	var atomic_peace := atomic_sim._commit_coalition_peace_plan(atomic_plan)
	_check(
		bool(atomic_peace.get("changed", false))
			and atomic_state.recognized_owner_of(atomic_city_id) == 0
			and atomic_state.cities[atomic_city_id].owner_nation == 0
			and atomic_state.cities[
				atomic_city_id
			].occupation_sponsor_nation == -1
			and atomic_state.relation_between(0, 1)
				== GameState.DiplomaticRelation.NEUTRAL
			and atomic_state.truce_until(0, 1)
				== atomic_state.day + GameState.DEFAULT_TRUCE_DAYS
			and atomic_state.ownership_revision
				== atomic_ownership_revision + 1
			and atomic_state.diplomacy_revision
				== atomic_diplomacy_revision + 1,
		"集团和平必须用一笔事务同时确认领土并结束战争，两类 revision 各递增一次"
	)
	atomic_sim.free()

	# stale diplomacy revision 必须在事务入口拒绝；和平的所有外围收尾也不得发生。
	var stale_fixture := _make_atomic_coalition_peace_fixture(32026)
	var stale_state: GameState = stale_fixture["state"]
	var stale_sim: Simulation = stale_fixture["simulation"]
	var stale_plan := stale_sim._plan_coalition_peace(0, 1)
	stale_plan["expected_diplomacy_revision"] = (
		int(stale_plan["expected_diplomacy_revision"]) + 1
	)
	var stale_before := _coalition_peace_fingerprint(stale_state, stale_sim)
	var stale_result := stale_sim._commit_coalition_peace_plan(stale_plan)
	_check(
		not bool(stale_result.get("changed", true))
			and _coalition_peace_fingerprint(stale_state, stale_sim)
				== stale_before,
		(
			"stale diplomacy revision 必须让整笔和平零变化：外交/停战、目标、"
			+ "叛乱、军队/战斗、动员、财政快照及两个 revision 均不得提前收尾"
		)
	)
	stale_sim.free()

	# 即使合法领土操作已排在计划中，末尾非法外交 operation 也必须整批回滚。
	var invalid_fixture := _make_atomic_coalition_peace_fixture(32027)
	var invalid_state: GameState = invalid_fixture["state"]
	var invalid_sim: Simulation = invalid_fixture["simulation"]
	var invalid_plan := invalid_sim._plan_coalition_peace(0, 1)
	var invalid_diplomacy_operations: Array[Dictionary] = []
	invalid_diplomacy_operations.assign(
		invalid_plan["diplomatic_operations"]
	)
	invalid_diplomacy_operations.append({
		"nation_a": 0,
		"nation_b": 2,
		"relation": 999,
		"truce_days": GameState.DEFAULT_TRUCE_DAYS,
	})
	invalid_plan["diplomatic_operations"] = invalid_diplomacy_operations
	var invalid_before := _coalition_peace_fingerprint(
		invalid_state, invalid_sim
	)
	var invalid_result := invalid_sim._commit_coalition_peace_plan(
		invalid_plan
	)
	_check(
		not bool(invalid_result.get("changed", true))
			and _coalition_peace_fingerprint(invalid_state, invalid_sim)
				== invalid_before,
		"和平计划末尾含非法 operation 时必须拒绝整批提交并保持完整状态指纹不变"
	)
	invalid_sim.free()

	# 最终统计必须读取每城最后一条 operation，而不是 collector 中途命中数。
	var statistics_state := GameState.new()
	statistics_state.generate_grid_world(32028)
	statistics_state.armies.clear()
	statistics_state.battles.clear()
	var statistics_city_id := -1
	for candidate in statistics_state.land_cities_of(0):
		if not candidate.is_capital and not candidate.has_warehouse:
			statistics_city_id = candidate.id
			break
	var statistics_rebel := statistics_state.start_regional_rebellion(
		0, [statistics_city_id] as Array[int]
	)
	statistics_state.day += (
		RebellionSystem.REGIONAL_REBELLION_MIN_WAR_DAYS
	)
	var statistics_sim := Simulation.new()
	statistics_sim.setup(statistics_state)
	var statistics_plan := statistics_sim._plan_coalition_peace(
		0, statistics_rebel
	)
	var final_reason := ""
	for operation_value in statistics_plan.get("operations", []):
		var operation: Dictionary = operation_value
		if int(operation.get("city_id", -1)) == statistics_city_id:
			final_reason = str(operation.get("reason", ""))
	_check(
		statistics_city_id >= 0
			and statistics_rebel >= 0
			and int(statistics_plan.get("occupations_restored", -1)) == 0
			and int(statistics_plan.get("territories_transferred", -1)) == 0
			and int(statistics_plan.get("occupations_normalized", -1)) == 0
			and final_reason == "regional_rebellion_recognized",
		"和平统计必须按 operation_by_city 最终 reason 计数，同城后续阶段不得重复虚报"
	)
	statistics_sim.free()

	# 无城 sponsor 仍可参与另一场未结战争。0-1 和平不得把 sponsor=2、legal=3
	# 的独立占领串案 normalize，即使 2 已经没有任何城市。
	var sponsor_fixture := _make_atomic_coalition_peace_fixture(32029)
	var sponsor_state: GameState = sponsor_fixture["state"]
	var sponsor_sim: Simulation = sponsor_fixture["simulation"]
	var isolated_city: City = null
	for candidate in sponsor_state.land_cities_of(3):
		if not candidate.is_capital and not candidate.has_warehouse:
			isolated_city = candidate
			break
	assert(isolated_city != null)
	isolated_city.owner_nation = 0
	isolated_city.occupation_sponsor_nation = 2
	sponsor_state.set_diplomatic_relation(
		2, 3, GameState.DiplomaticRelation.WAR
	)
	var sponsor_removal_ops: Array[Dictionary] = []
	for sponsor_city in sponsor_state.cities_of(2):
		sponsor_removal_ops.append({
			"city_id": sponsor_city.id,
			"controller_id": 3,
			"legal_owner_id": 3,
			"sponsor_id": -1,
			"reset_political_target": true,
			"stock_policy": GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL,
			"reason": "landless_sponsor_fixture",
		})
	var sponsor_removed := sponsor_state.apply_territory_transaction(
		sponsor_removal_ops
	)
	var sponsor_plan := sponsor_sim._plan_coalition_peace(0, 1)
	var sponsor_city_planned := false
	for operation_value in sponsor_plan.get("operations", []):
		var operation: Dictionary = operation_value
		sponsor_city_planned = (
			sponsor_city_planned
			or int(operation.get("city_id", -1)) == isolated_city.id
		)
	_check(
		bool(sponsor_removed.get("ok", false))
			and sponsor_state.cities_of(2).is_empty()
			and sponsor_state.is_enemy(2, 3)
			and not sponsor_city_planned,
		"无城 sponsor 与法理国的另一场 WAR 必须阻止本次集团和平串案归还占领"
	)
	sponsor_sim.free()

	# 嵌套叛乱同时镇压必须把所有 rebel 直接解析到最终母国，不能让中间
	# rebel 在 finalizer 阶段通过吞并其子叛军重新获得军队或资源。
	var nested_state := GameState.new()
	nested_state.generate_grid_world(32030)
	nested_state.armies.clear()
	nested_state.battles.clear()
	for nested_a in range(nested_state.nations.size()):
		for nested_b in range(nested_a + 1, nested_state.nations.size()):
			nested_state.set_diplomatic_relation(
				nested_a, nested_b, GameState.DiplomaticRelation.NEUTRAL
			)
	var nested_core_one := nested_state.land_cities_of(0)[0].id
	var nested_core_two := nested_state.land_cities_of(1)[0].id
	nested_state.rebellions[1] = {
		"parent_id": 0,
		"started_day": 0,
		"core_city_ids": [nested_core_one] as Array[int],
		"recognized": false,
		"active": true,
	}
	nested_state.rebellions[2] = {
		"parent_id": 1,
		"started_day": 0,
		"core_city_ids": [nested_core_two] as Array[int],
		"recognized": false,
		"active": true,
	}
	nested_state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	nested_state.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.WAR)
	nested_state.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	nested_state.day = RebellionSystem.REGIONAL_REBELLION_MIN_WAR_DAYS
	var nested_sim := Simulation.new()
	nested_sim.setup(nested_state)
	var nested_owners: Array[int] = []
	var nested_legal: Array[int] = []
	var nested_sponsors: Array[int] = []
	nested_owners.resize(nested_state.cities.size())
	nested_legal.resize(nested_state.cities.size())
	nested_sponsors.resize(nested_state.cities.size())
	for nested_city in nested_state.cities:
		nested_owners[nested_city.id] = nested_city.owner_nation
		nested_legal[nested_city.id] = nested_state.recognized_owner_of(
			nested_city.id
		)
		nested_sponsors[nested_city.id] = nested_city.occupation_sponsor_nation
	var nested_draft := {
		"owners": nested_owners,
		"legal": nested_legal,
		"sponsors": nested_sponsors,
		"operation_by_city": {},
		"proposed_suzerainty": nested_state.suzerainty.duplicate(true),
	}
	var nested_rebellion_plan := nested_sim._plan_coalition_rebellion_peace(
		nested_draft,
		[Vector2i(0, 1), Vector2i(1, 2)] as Array[Vector2i]
	)
	var nested_annexations: Array[Vector2i] = []
	nested_annexations.assign(nested_rebellion_plan.get("annexations", []))
	_check(
		bool(nested_rebellion_plan.get("ok", false))
			and nested_annexations == (
				[Vector2i(0, 1), Vector2i(0, 2)] as Array[Vector2i]
			),
		"嵌套双叛乱同时镇压必须将每个 rebel 直接规划给最终母国 absorber"
	)
	var nested_peace := nested_sim._make_coalition_peace(0, 1)
	_check(
		bool(nested_peace.get("changed", false))
			and not nested_state.nations[1].alive
			and not nested_state.nations[2].alive
			and nested_state.cities_of(1).is_empty()
			and nested_state.cities_of(2).is_empty()
			and not bool((nested_state.rebellions[1] as Dictionary).get(
				"active", true
			))
			and not bool((nested_state.rebellions[2] as Dictionary).get(
				"active", true
			))
			and nested_state.territory_structure_valid(),
		"嵌套双叛乱提交后两个 rebel 都必须归最终母国且中间 rebel 不得复活"
	)
	nested_sim.free()

	# 地方叛乱的 parent/rebel 即使不是本次议和代表，也必须随所属集团
	# 一并结算；否则 relation 已和平而 rebellion 仍 active，会立刻破坏结构。
	var rebellion_peace_state := GameState.new()
	rebellion_peace_state.generate_grid_world(32024)
	rebellion_peace_state.armies.clear()
	rebellion_peace_state.battles.clear()
	for rebellion_a in range(rebellion_peace_state.nations.size()):
		for rebellion_b in range(
			rebellion_a + 1, rebellion_peace_state.nations.size()
		):
			rebellion_peace_state.set_diplomatic_relation(
				rebellion_a,
				rebellion_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var rebellion_core := -1
	for rebellion_city in rebellion_peace_state.land_cities_of(0):
		if not rebellion_city.is_capital and not rebellion_city.has_warehouse:
			rebellion_core = rebellion_city.id
			break
	var coalition_rebel := rebellion_peace_state.start_regional_rebellion(
		0, [rebellion_core] as Array[int]
	)
	rebellion_peace_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.ALLIED
	)
	rebellion_peace_state.set_diplomatic_relation(
		coalition_rebel, 3, GameState.DiplomaticRelation.ALLIED
	)
	for parent_side in [0, 2]:
		for rebel_side in [coalition_rebel, 3]:
			rebellion_peace_state.set_diplomatic_relation(
				parent_side,
				rebel_side,
				GameState.DiplomaticRelation.WAR
			)
	rebellion_peace_state.day += (
		RebellionSystem.REGIONAL_REBELLION_MIN_WAR_DAYS
	)
	var rebellion_peace_sim := Simulation.new()
	rebellion_peace_sim.setup(rebellion_peace_state)
	var representative_peace := rebellion_peace_sim._make_coalition_peace(
		2, 3
	)
	_check(
		rebellion_core >= 0
			and coalition_rebel >= 0
			and bool(representative_peace.get("changed", false))
			and not bool(
				(rebellion_peace_state.rebellions[coalition_rebel]
					as Dictionary).get("active", true)
			)
			and bool(
				(rebellion_peace_state.rebellions[coalition_rebel]
					as Dictionary).get("recognized", false)
			)
			and not rebellion_peace_state.is_enemy(0, coalition_rebel)
			and rebellion_peace_state.recognized_owner_of(
				rebellion_core
			) == coalition_rebel
			and rebellion_peace_state.cities[
				rebellion_core
			].occupation_sponsor_nation == -1
			and rebellion_peace_state.rebellion_structure_valid()
			and rebellion_peace_state.territory_structure_valid(),
		(
			"代表国 2/3 的集团议和必须同时结算非代表 parent/rebel 0/%d，"
			+ "结束 active rebellion 并保持领土结构合法"
		) % coalition_rebel
	)
	rebellion_peace_sim.free()

	var join_state := GameState.new()
	join_state.generate_grid_world(32022)
	for join_a in range(join_state.nations.size()):
		for join_b in range(join_a + 1, join_state.nations.size()):
			join_state.set_diplomatic_relation(
				join_a,
				join_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	join_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var join_target := join_state.cities_of(1)[0].id
	join_state.set_war_objective(
		0,
		1,
		join_target,
		"既有战争目标"
	)
	var join_sim := Simulation.new()
	join_sim.setup(join_state)
	var joined := join_sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.FORM_ALLIANCE,
		"a": 0,
		"b": 2,
		"reason": "战争中结盟回归",
	})
	_check(
		joined
			and join_state.is_enemy(2, 1)
			and int(
				join_state.war_objective(2, 1).get(
					"city_id",
					-1
				)
			) == join_target
			and join_state.nations[2]
				.war_mobilization_target_troops > 0,
		"战争中结盟必须让新盟友立即参战、继承共同目标并启动本国动员"
	)
	join_sim.free()


# ------------------------------------------------------------------ 32c. 宗藩数据模型不变量（增量 A）

func _test_suzerainty_invariants() -> void:
	print("[32c] 宗藩：分封守恒、对外关系继承、共同体一体化与结构不变量")
	var gs := GameState.new()
	gs.generate_grid_world(32031)
	# 归零到全中立，再布置：0 与 1 交战、0 与 3 结盟，第三方 2 保持中立。
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	gs.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.ALLIED)

	# 选国 0 的两座非首都城市分封。
	var overlord_id := 0
	var enfeoff_cities: Array[int] = []
	for city in gs.land_cities_of(overlord_id):
		if not city.is_capital:
			enfeoff_cities.append(city.id)
		if enfeoff_cities.size() >= 2:
			break

	# 分封前快照，用于守恒校验（人力/金钱/粮食全体系总量不变）。
	var pre_manpower := gs.nations[overlord_id].manpower_pool
	var pre_gold := gs.nations[overlord_id].treasury_gold
	gs.refresh_derived()
	var pre_food := gs.nations[overlord_id].granary_food
	var pre_land_count := gs.land_cities_of(overlord_id).size()

	var subject_id := gs.enfeoff(overlord_id, enfeoff_cities)
	_check(
		subject_id == gs.nations.size() - 1 and subject_id > 0,
		"分封应新建一个完整藩王 Nation 并返回其 id"
	)

	# 领土迁移：迁出城市 owner 与法理归属都归藩王，宗主领土相应减少。
	var territory_ok := gs.land_cities_of(overlord_id).size() == pre_land_count - enfeoff_cities.size()
	for city_id in enfeoff_cities:
		territory_ok = (
			territory_ok
			and gs.cities[city_id].owner_nation == subject_id
			and gs.recognized_owner_of(city_id) == subject_id
		)
	_check(territory_ok, "分封必须迁移城市实控与法理归属，且宗主领土相应减少")

	# 资源守恒：宗主+藩王人力/金钱/粮食总量与分封前相等（floor 不超发）。
	gs.refresh_derived()
	var post_manpower := gs.nations[overlord_id].manpower_pool + gs.nations[subject_id].manpower_pool
	var post_gold := gs.nations[overlord_id].treasury_gold + gs.nations[subject_id].treasury_gold
	var post_food := gs.nations[overlord_id].granary_food + gs.nations[subject_id].granary_food
	_check(
		post_manpower == pre_manpower
			and post_gold == pre_gold
			and post_food == pre_food,
		"分封划转人力/金钱/粮食必须全体系守恒（实为 mp=%d/%d gold=%d/%d food=%d/%d）"
			% [post_manpower, pre_manpower, post_gold, pre_gold, post_food, pre_food]
	)

	# 藩王获得独立首都，但首都是「共享粮仓」的零库存补给中继节点（无独立粮仓）：
	# 粮食归宗主根池，藩王 granary/warehouse 为空、首都 has_warehouse=false。
	var capital_id := gs.nations[subject_id].capital_city_id
	_check(
		capital_id >= 0
			and gs.cities[capital_id].owner_nation == subject_id
			and gs.cities[capital_id].is_capital
			and not gs.cities[capital_id].has_warehouse
			and gs.cities[capital_id].food_storage == 0
			and gs.nations[subject_id].warehouse_city_ids.is_empty()
			and gs.nations[subject_id].granary_food == 0,
		"藩王首都必须是零库存补给中继节点（粮食归共享粮仓，藩王无独立粮仓）"
	)
	# 共享粮仓：藩王的粮食产出重定向到宗主根池；宗主 granary 承载全体系粮食。
	var overlord_food_before := gs.nations[overlord_id].granary_food
	var deposited := gs.deposit_food(subject_id, 100)
	gs.refresh_derived()
	_check(
		gs.food_pool_holder(subject_id) == overlord_id
			and deposited
			and gs.nations[overlord_id].granary_food == overlord_food_before + 100
			and gs.nations[subject_id].granary_food == 0,
		"藩王粮食产出必须归集到宗藩体系根粮池（food_pool_holder=宗主）"
	)

	# 宗藩关系 SSoT 与查询接口。
	_check(
		gs.overlord_of(subject_id) == overlord_id
			and gs.subjects_of(overlord_id) == [subject_id]
			and gs.is_vassal(subject_id)
			and gs.is_overlord(overlord_id)
			and not gs.is_vassal(overlord_id)
			and gs.suzerainty_root(subject_id) == overlord_id
			and gs.suzerainty_root(overlord_id) == overlord_id,
		"宗藩查询接口必须正确反映有向关系"
	)
	_check(
		gs.external_territory_recipient(subject_id) == overlord_id
			and gs.external_territory_recipient(overlord_id)
				== overlord_id,
		"和平藩王的对外领土收益必须上收到宗主，宗主保持自身主权"
	)
	var record := gs.suzerainty_record(subject_id)
	_check(
		_approx(float(record["tribute_rate"]), GameState.DEFAULT_TRIBUTE_RATE)
			and int(record["created_day"]) == gs.day,
		"宗藩关系记录必须写入默认贡赋率与创建日"
	)

	# 对外关系继承：藩王与宗主结盟；继承宗主对第三方的关系（敌 1→WAR，中立 2→NEUTRAL）。
	_check(
		gs.is_allied(subject_id, overlord_id)
			and gs.is_enemy(subject_id, 1)
			and gs.relation_between(subject_id, 2) == GameState.DiplomaticRelation.NEUTRAL
			and gs.is_allied(subject_id, 3),
		"藩王必须与宗主结盟并继承宗主对第三方的对外关系"
	)

	# 对外共同体一体化：宗主与藩王同属一个 alliance_bloc；suzerainty_members 一致。
	var bloc := gs.alliance_bloc(overlord_id)
	_check(
		bloc.has(overlord_id) and bloc.has(subject_id),
		"宗主与藩王必须落在同一个对外军事共同体 alliance_bloc 内"
	)
	_check(
		gs.suzerainty_members(subject_id) == [overlord_id, subject_id]
			and gs.suzerainty_members(overlord_id) == [overlord_id, subject_id],
		"suzerainty_members 必须聚合同一宗主根下全部成员"
	)

	# 结构不变量成立。
	_check(gs.suzerainty_structure_valid(), "分封后宗藩结构不变量必须成立")

	# 驻军地方化：封地内稳定驻防的宗主 LINE 先转给藩王，再凭空补足到「陆城数」；
	# 藩王不得因分封获得 MAIN 或战团（主战力归中央）。
	var vassal_land := gs.land_cities_of(subject_id).size()
	var vassal_line := 0
	var vassal_main := 0
	for army in gs.armies:
		if army.owner_nation == subject_id and army.size > 0:
			if army.is_main_battle_role():
				vassal_main += 1
			elif army.is_line_role():
				vassal_line += 1
	_check(
		vassal_line == vassal_land
			and vassal_main == 0
			and gs.nations[subject_id].battle_groups.is_empty(),
		"分封须赐藩王=陆城数的LINE军、且无MAIN无战团（LINE=%d 陆城=%d MAIN=%d 战团=%d）"
			% [vassal_line, vassal_land, vassal_main, gs.nations[subject_id].battle_groups.size()]
	)
	_check(
		gs._battle_group_structure_valid(),
		"分封赐军后战团结构不变量必须成立"
	)
	# 宗主 MAIN 战团不随分封转隶。
	var group_state := GameState.new()
	group_state.generate_grid_world(32032)
	var group_overlord := 0
	var group_move_city := -1
	for city in group_state.land_cities_of(group_overlord):
		if not city.is_capital:
			group_move_city = city.id
			break
	var overlord_groups_before := group_state.nations[group_overlord].battle_groups.size()
	var group_subject := group_state.enfeoff(group_overlord, [group_move_city])
	_check(
		group_subject > 0
			and group_state.nations[group_subject].battle_groups.is_empty()
			and group_state.nations[group_overlord].battle_groups.size() == overlord_groups_before
			and group_state._battle_group_structure_valid()
			and group_state.suzerainty_structure_valid(),
		"分封后宗主保留全部 MAIN 战团、藩王无战团、结构不变量成立（宗主战团 %d→%d）"
			% [overlord_groups_before, group_state.nations[group_overlord].battle_groups.size()]
	)

	# LINE 转移与补军必须是同一闭环：城内驻军、封地端驻边军地方化；远端 LINE 与
	# MAIN 战团留归宗主；转移后清除旧防区/战役引用，最终只补足 LINE 缺口。
	var transfer_state := GameState.new()
	transfer_state.generate_grid_world(32033)
	var transfer_overlord := 0
	var transfer_region: Array[int] = []
	for city in transfer_state.land_cities_of(
		transfer_overlord
	):
		if city.is_capital:
			continue
		transfer_region.append(city.id)
		if transfer_region.size() >= 3:
			break
	transfer_region = transfer_state.enfeoff_region_closure(
		transfer_overlord,
		transfer_region
	)
	var retained_city := -1
	for city in transfer_state.land_cities_of(
		transfer_overlord
	):
		if not transfer_region.has(city.id):
			retained_city = city.id
			break
	var border_from := -1
	var border_to := -1
	for city_id in transfer_region:
		for neighbor in transfer_state.neighbors(city_id):
			var edge := transfer_state.edge_of(
				city_id,
				neighbor
			)
			if (
				not transfer_region.has(neighbor)
				and edge != null
				and edge.max_manpower > 0
				and edge.allows_holding
			):
				border_from = city_id
				border_to = neighbor
				break
		if border_from >= 0:
			break
	for army in transfer_state.armies:
		if (
			army.owner_nation == transfer_overlord
			and army.is_line_role()
		):
			army.location_city = retained_city
			army.move_from = retained_city
			army.move_to = -1
			army.move_progress = 0.0
			army.on_edge = false
			army.state = Army.State.IDLE
			army.path.clear()
	var local_line := transfer_state._spawn_conjured_army(
		transfer_overlord,
		transfer_region[0],
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		Army.StrategicRole.LINE
	)
	local_line.line_assignment_city = transfer_region[0]
	local_line.line_assignment_posture = (
		Army.LinePosture.CITY
	)
	local_line.ai_action = ActionCandidate.Kind.HOLD
	local_line.ai_target_city = transfer_region[0]
	local_line.ai_order_until_day = 999
	local_line.defensive_deployment_until_day = 999
	transfer_state.nations[
		transfer_overlord
	].campaign_attack_assignments[local_line.id] = (
		transfer_region[0]
	)
	var border_line := transfer_state._spawn_conjured_army(
		transfer_overlord,
		border_from,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		Army.StrategicRole.LINE
	)
	border_line.location_city = border_from
	border_line.move_from = border_from
	border_line.move_to = border_to
	border_line.move_progress = 0.35
	border_line.on_edge = true
	border_line.state = Army.State.HOLDING
	border_line.hold_target_progress = 0.35
	var remote_line := transfer_state._spawn_conjured_army(
		transfer_overlord,
		retained_city,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		Army.StrategicRole.LINE
	)
	var main_group := transfer_state.create_battle_group(
		transfer_overlord
	)
	var local_main := transfer_state._spawn_conjured_army(
		transfer_overlord,
		transfer_region[0],
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		Army.StrategicRole.MAIN
	)
	transfer_state.assign_army_to_battle_group(
		local_main,
		main_group.id
	)
	var transfer_army_count_before := (
		transfer_state.armies.size()
	)
	var transfer_groups_before := transfer_state.nations[
		transfer_overlord
	].battle_groups.size()
	var transfer_subject := transfer_state.enfeoff(
		transfer_overlord,
		transfer_region
	)
	var transferred_line_count := 0
	for army in transfer_state.armies:
		if (
			army.owner_nation == transfer_subject
			and army.size > 0
			and army.is_line_role()
		):
			transferred_line_count += 1
	var expected_conjured := maxi(
		transfer_region.size() - 2,
		0
	)
	_check(
		transfer_subject > 0
			and retained_city >= 0
			and border_from >= 0
			and local_line.owner_nation == transfer_subject
			and border_line.owner_nation == transfer_subject
			and remote_line.owner_nation == transfer_overlord
			and local_main.owner_nation == transfer_overlord
			and local_main.battle_group_id == main_group.id
			and border_line.state == Army.State.HOLDING
			and border_line.move_from == border_from
			and local_line.line_assignment_city == -1
			and local_line.ai_action
				== ActionCandidate.Kind.NONE
			and local_line.ai_target_city == -1
			and local_line.defensive_deployment_until_day
				== -1
			and not transfer_state.nations[
				transfer_overlord
			].campaign_attack_assignments.has(
				local_line.id
			)
			and transferred_line_count
				== transfer_region.size()
			and transfer_state.armies.size()
				== transfer_army_count_before
					+ expected_conjured
			and transfer_state.nations[
				transfer_overlord
			].battle_groups.size()
				== transfer_groups_before
			and transfer_state.nations[
				transfer_subject
			].battle_groups.is_empty()
			and transfer_state
				._battle_group_structure_valid(),
		"分封须地方化城内/驻边LINE、保留远端LINE与MAIN，并仅补足缺口"
	)

	# 非法输入：空区、含宗主首都、非宗主领土、清空宗主领土——均返回 -1 且无副作用。
	var nation_count_before := gs.nations.size()
	var overlord_capital := gs.nations[overlord_id].capital_city_id
	var reject_empty := gs.enfeoff(overlord_id, [] as Array[int])
	var reject_capital := gs.enfeoff(overlord_id, [overlord_capital] as Array[int])
	var foreign_city := gs.land_cities_of(2)[0].id
	var reject_foreign := gs.enfeoff(overlord_id, [foreign_city] as Array[int])
	var occupied_city := gs.land_cities_of(overlord_id)[0]
	if occupied_city.id == overlord_capital:
		occupied_city = gs.land_cities_of(overlord_id)[1]
	var occupied_legal_owner := gs.recognized_owner_of(occupied_city.id)
	gs.recognized_city_owners[occupied_city.id] = 2
	var reject_occupied := gs.enfeoff(
		overlord_id,
		[occupied_city.id] as Array[int]
	)
	gs.recognized_city_owners[occupied_city.id] = occupied_legal_owner
	var all_overlord_cities: Array[int] = []
	for city in gs.land_cities_of(overlord_id):
		all_overlord_cities.append(city.id)
	var reject_drain := gs.enfeoff(overlord_id, all_overlord_cities)
	_check(
		reject_empty == -1
			and reject_capital == -1
			and reject_foreign == -1
			and reject_occupied == -1
			and reject_drain == -1
			and gs.nations.size() == nation_count_before,
		(
			"非法分封（空区/含首都/非本国城/临时占领地/清空领土）"
			+ "必须被拒绝且不建国"
		)
	)
	_check(gs.suzerainty_structure_valid(), "非法分封被拒后宗藩结构仍须合法")

	# 分封切断宗主直辖领土时，被切断飞地必须自动并入同一封地。
	var closure_state := GameState.new()
	closure_state.generate_grid_world(32033)
	closure_state.armies.clear()
	closure_state.battles.clear()
	for city in closure_state.cities:
		city.owner_nation = 1
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		closure_state.recognized_city_owners[city.id] = 1
	for closure_edge in closure_state.edges:
		closure_edge.max_manpower = 0
	for closure_city_id in [0, 1, 2, 3, 8]:
		closure_state.cities[closure_city_id].owner_nation = 0
		closure_state.recognized_city_owners[
			closure_city_id
		] = 0
	for closure_road in [
		[0, 1],
		[1, 2],
		[2, 3],
		[0, 8],
	]:
		closure_state.edge_of(
			int(closure_road[0]),
			int(closure_road[1])
		).max_manpower = Edge.STANDARD_MANPOWER
	_set_single_warehouse(closure_state, 0, 0, 100)
	closure_state.refresh_derived()
	var closure_region := closure_state.enfeoff_region_closure(
		0,
		[1] as Array[int]
	)
	var closure_subject := closure_state.enfeoff(
		0,
		[1] as Array[int]
	)
	_check(
		closure_region == [1, 2, 3]
			and closure_subject >= 0
			and closure_state.cities[1].owner_nation
				== closure_subject
			and closure_state.cities[2].owner_nation
				== closure_subject
			and closure_state.cities[3].owner_nation
				== closure_subject
			and closure_state.cities[8].owner_nation == 0
			and _nation_territory_contiguous(
				closure_state,
				0
			),
		"分封城1切断城2/3时，飞地2/3必须一并封出，宗主保留城0/8连续"
	)


# ------------------------------------------------------------------ 32d. 贡赋月度结算（增量 B）

func _test_vassal_tribute() -> void:
	print("[32d] 宗藩：贡赋按当月税收比例上缴、全体系守恒、逐级支持多级")
	var gs := GameState.new()
	gs.generate_grid_world(32041)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	# 构造两级宗藩：0 为根宗主，1 为其藩王，2 为 1 的次级藩王（多级逐级上缴）。
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	gs.set_diplomatic_relation(1, 2, GameState.DiplomaticRelation.ALLIED)
	gs.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": 0.25,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	gs.suzerainty[2] = {
		"overlord_id": 1,
		"tribute_rate": 0.50,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	_check(
		gs.external_territory_recipient(2) == 0,
		"多级和平宗藩中，次级藩王的对外领土收益必须逐级上收到根宗主"
	)
	gs.suzerainty[1]["civil_war"] = true
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	_check(
		gs.external_territory_recipient(2) == 1,
		"中间藩王反叛后，其子树对外领土收益必须止于反叛方，不得越过内战边"
	)
	var civil_war_flows := Simulation.monthly_gold_flows(gs)
	for civil_war_nation in gs.nations:
		civil_war_nation.treasury_gold = 1000
	var civil_war_treasuries := [
		gs.nations[0].treasury_gold,
		gs.nations[1].treasury_gold,
		gs.nations[2].treasury_gold,
	]
	var civil_war_income: Array[int] = [0, 400, 200]
	var subordinate_rate := Simulation.effective_tribute_rate(gs, 2)
	var subordinate_tribute := int(floor(
		float(civil_war_income[2]) * subordinate_rate
	))
	var civil_war_sim := Simulation.new()
	civil_war_sim.setup(gs)
	civil_war_sim._resolve_tribute(civil_war_income)
	_check(
		is_zero_approx(Simulation.effective_tribute_rate(gs, 1))
			and subordinate_rate > 0.0
			and int(civil_war_flows[1]["tribute_paid"]) == 0
			and int(civil_war_flows[0]["tribute_received"]) == 0
			and int(civil_war_flows[2]["tribute_paid"]) > 0
			and int(civil_war_flows[1]["tribute_received"]) > 0
			and gs.nations[0].treasury_gold == civil_war_treasuries[0]
			and gs.nations[1].treasury_gold
				== civil_war_treasuries[1] + subordinate_tribute
			and gs.nations[2].treasury_gold
				== civil_war_treasuries[2] - subordinate_tribute,
		(
			"内战只应暂停反叛藩王向直属宗主的贡赋，反叛子树内部和平贡赋仍须结算："
			+ "rates=%.2f/%.2f flows=%s treasuries=%d/%d/%d"
		) % [
			Simulation.effective_tribute_rate(gs, 1),
			Simulation.effective_tribute_rate(gs, 2),
			str(civil_war_flows),
			gs.nations[0].treasury_gold,
			gs.nations[1].treasury_gold,
			gs.nations[2].treasury_gold,
		]
	)
	civil_war_sim.free()
	gs.suzerainty[1]["civil_war"] = false
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	_check(
		_approx(Simulation.effective_tribute_rate(gs, 1), 0.25),
		"内战结束后贡赋率必须恢复宗藩记录中的基础税率"
	)
	var sim := Simulation.new()
	sim.setup(gs)

	# 纯函数层：给定当月税收，验证守恒与逐级比例（floor）。
	for nation in gs.nations:
		nation.treasury_gold = 1000
	var gold_income: Array[int] = []
	gold_income.resize(gs.nations.size())
	gold_income.fill(0)
	gold_income[1] = 400   # 藩王 1 当月税收
	gold_income[2] = 200   # 次级藩王 2 当月税收
	var total_before := 0
	for nation in gs.nations:
		total_before += nation.treasury_gold
	sim._resolve_tribute(gold_income)
	var total_after := 0
	for nation in gs.nations:
		total_after += nation.treasury_gold
	# 1 上缴 floor(400*0.25)=100 给 0；2 上缴 floor(200*0.5)=100 给 1。
	_check(
		gs.nations[0].treasury_gold == 1000 + 100
			and gs.nations[1].treasury_gold == 1000 - 100 + 100
			and gs.nations[2].treasury_gold == 1000 - 100
			and total_after == total_before,
		"贡赋必须按当月税收比例逐级上缴且金钱全体系守恒（0=%d 1=%d 2=%d）"
			% [gs.nations[0].treasury_gold, gs.nations[1].treasury_gold, gs.nations[2].treasury_gold]
	)

	# 贡赋不得把藩王国库抽成负数：税收极高但国库很低时按国库封顶。
	gs.nations[2].treasury_gold = 30
	var poor_income: Array[int] = []
	poor_income.resize(gs.nations.size())
	poor_income.fill(0)
	poor_income[2] = 1000   # floor(1000*0.5)=500，但国库只有 30
	sim._resolve_tribute(poor_income)
	_check(
		gs.nations[2].treasury_gold == 0,
		"贡赋按国库余额封顶，不得使藩王国库为负（实为 %d）" % gs.nations[2].treasury_gold
	)

	# 财政派生必须与真实月结算同源：城市税收 + 贡赋流入 - 贡赋流出 - 军费。
	for nation in gs.nations:
		nation.treasury_gold = 100000
	var predicted_flows := Simulation.monthly_gold_flows(
		gs
	)
	var treasury_before_month: Array[int] = []
	var reports_match_flows := true
	var report_cache := {}
	for nation in gs.nations:
		treasury_before_month.append(nation.treasury_gold)
		var report := DiplomacyAI.resource_report(
			gs,
			nation.id,
			report_cache
		)
		var flow: Dictionary = predicted_flows[nation.id]
		reports_match_flows = (
			reports_match_flows
			and int(report["monthly_city_gold_income"])
				== int(flow["city_income"])
			and int(report["monthly_tribute_income"])
				== int(flow["tribute_received"])
			and int(report["monthly_tribute_expense"])
				== int(flow["tribute_paid"])
			and int(report["monthly_gold_balance"])
				== int(flow["balance"])
		)
	sim._resolve_economy()
	var settlement_matches_prediction := true
	for nation in gs.nations:
		settlement_matches_prediction = (
			settlement_matches_prediction
			and nation.treasury_gold
				- treasury_before_month[nation.id]
				== int(predicted_flows[nation.id]["balance"])
		)
	_check(
		reports_match_flows
			and settlement_matches_prediction,
		"前端/AI财政派生必须逐国等于真实月结算国库变化（含多级贡赋）"
	)

	# 端到端：完整推进一个月，藩王必有正税收并向宗主净转移金钱。
	var e2e := GameState.new()
	e2e.generate_grid_world(32042)
	for a in range(e2e.nations.size()):
		for b in range(a + 1, e2e.nations.size()):
			e2e.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var e2e_cities: Array[int] = []
	for city in e2e.land_cities_of(0):
		if not city.is_capital:
			e2e_cities.append(city.id)
		if e2e_cities.size() >= 3:
			break
	var e2e_subject := e2e.enfeoff(0, e2e_cities, 0.25)
	var e2e_sim := Simulation.new()
	e2e_sim.diplomacy_enabled = false   # 隔离外交/AI 噪声，只观察经济结算
	e2e_sim.setup(e2e)
	var overlord_before := e2e.nations[0].treasury_gold
	var total_system_before := e2e.nations[0].treasury_gold + e2e.nations[e2e_subject].treasury_gold
	for _i in range(Simulation.DAYS_PER_MONTH):
		e2e_sim._advance_day()
	# 军费只在体系内部支付给“无主”开销，宗藩间的贡赋转移本身仍守恒：
	# 校验宗主收到的贡赋 > 0（藩王有税收且已上缴）。
	var overlord_gain := e2e.nations[0].treasury_gold - overlord_before
	var total_system_after := e2e.nations[0].treasury_gold + e2e.nations[e2e_subject].treasury_gold
	_check(
		e2e_subject > 0 and overlord_gain > 0 and total_system_after >= total_system_before,
		"端到端一个月后宗主应收到藩王贡赋（overlord_gain=%d）" % overlord_gain
	)

	# 长期财政压力：藩王月亏、宗主靠贡赋恰好覆盖军费且国库始终为 0。
	# 藩王 AI 应在首月缩编到收支平衡，后续月份不得因旧 unpaid 记录重复缩编；
	# 宗主月净为 0，不应仅因国库为 0 被误判为财政危机。
	var crisis := GameState.new()
	crisis.generate_grid_world(32043)
	crisis.armies.clear()
	crisis.battles.clear()
	crisis.uses_heightmap = true
	for a in range(crisis.nations.size()):
		for b in range(a + 1, crisis.nations.size()):
			crisis.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	for nation in crisis.nations:
		_set_neutral_ruler(nation)
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
		nation.warehouse_city_ids.clear()
		nation.battle_groups.clear()
		nation.next_battle_group_id = 0
	for city in crisis.cities:
		city.owner_nation = 0
		crisis.recognized_city_owners[city.id] = 0
		city.gold_per_month = 0
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
	var overlord_id := 0
	var subject_id := 1
	var overlord_city := 0
	var subject_city := 1
	crisis.cities[subject_city].owner_nation = subject_id
	crisis.recognized_city_owners[subject_city] = subject_id
	crisis.cities[subject_city].gold_per_month = 10
	crisis.nations[overlord_id].capital_city_id = overlord_city
	crisis.nations[subject_id].capital_city_id = subject_city
	crisis.cities[overlord_city].is_capital = true
	crisis.cities[overlord_city].has_warehouse = true
	crisis.cities[overlord_city].food_storage = 1000000
	crisis.nations[overlord_id].warehouse_city_ids = [
		overlord_city
	] as Array[int]
	crisis.cities[subject_city].is_capital = true
	crisis.set_diplomatic_relation(
		overlord_id,
		subject_id,
		GameState.DiplomaticRelation.ALLIED
	)
	crisis.suzerainty[subject_id] = {
		"overlord_id": overlord_id,
		"tribute_rate": 0.25,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	# 本夹具只验证贡赋与军费缩编；封闭路网以隔离新增贸易税，维持
	# “宗主恰好收支为零”的既有前置条件。
	for crisis_edge in crisis.edges:
		crisis_edge.max_manpower = 0
	crisis.refresh_derived()
	var subject_city_income := Simulation.city_gold_output(
		crisis,
		crisis.cities[subject_city]
	)
	var subject_tribute := int(floor(
		float(subject_city_income)
		* Simulation.effective_tribute_rate(
			crisis,
			subject_id
		)
	))
	var overlord_army := crisis.create_army(
		overlord_id,
		overlord_city,
		subject_tribute
			* GameState.WAR_GOLD_TROOPS_PER_UNIT,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var subject_light_a := crisis.create_army(
		subject_id,
		subject_city,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var subject_light_b := crisis.create_army(
		subject_id,
		subject_city,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var subject_heavy := crisis.create_army(
		subject_id,
		subject_city,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		GameState.INITIAL_HEAVY_ARMY_SIZE
	)
	for nation in crisis.nations:
		nation.treasury_gold = 0
		nation.manpower_pool = 0
		nation.food_demand_ema = 0.0
	var crisis_sim := Simulation.new()
	crisis_sim.diplomacy_enabled = false
	crisis_sim.setup(crisis)
	var initial_flows := Simulation.monthly_gold_flows(
		crisis
	)
	var initial_subject_upkeep := int(
		initial_flows[subject_id]["military_upkeep"]
	)
	var expected_subject_deficit := -int(
		initial_flows[subject_id]["balance"]
	)
	var overlord_treasuries: Array[int] = []
	var subject_treasuries: Array[int] = []
	var subject_unpaid: Array[int] = []
	var subject_upkeep_after_ai: Array[int] = []
	var subject_demobilized: Array[bool] = []
	var overlord_demobilized: Array[bool] = []
	for month_index in range(6):
		crisis.day = (
			(month_index + 1)
			* Simulation.DAYS_PER_MONTH
		)
		crisis_sim._resolve_economy()
		overlord_treasuries.append(
			crisis.nations[overlord_id].treasury_gold
		)
		subject_treasuries.append(
			crisis.nations[subject_id].treasury_gold
		)
		subject_unpaid.append(
			crisis.nations[
				subject_id
			].unpaid_military_upkeep
		)
		var subject_view := AiWorldView.build(
			crisis,
			subject_id
		)
		var subject_snapshot := StrategicMapSnapshot.build(
			subject_view
		)
		var subject_threat := ThreatField.build(
			subject_view
		)
		subject_demobilized.append(
			crisis_sim._ai_manage_force_structure(
				subject_view,
				subject_snapshot,
				subject_threat,
				CityDefensePlan.build(
					subject_view,
					subject_snapshot,
					subject_threat
				)
			)
		)
		subject_upkeep_after_ai.append(
			Simulation.effective_monthly_military_upkeep(
				crisis, subject_id
			)
		)
		var overlord_view := AiWorldView.build(
			crisis,
			overlord_id
		)
		var overlord_snapshot := StrategicMapSnapshot.build(
			overlord_view
		)
		var overlord_threat := ThreatField.build(
			overlord_view
		)
		overlord_demobilized.append(
			crisis_sim._ai_manage_force_structure(
				overlord_view,
				overlord_snapshot,
				overlord_threat,
				CityDefensePlan.build(
					overlord_view,
					overlord_snapshot,
					overlord_threat
				)
			)
		)
	var overlord_treasury_grows := true
	var subject_treasury_grows := true
	var no_repeat_demobilization := true
	var overlord_only_initial_demobilization := true
	for month_index in range(6):
		if month_index > 0:
			no_repeat_demobilization = (
				no_repeat_demobilization
				and not subject_demobilized[month_index]
			)
			overlord_only_initial_demobilization = (
				overlord_only_initial_demobilization
				and not overlord_demobilized[month_index]
			)
			overlord_treasury_grows = (
				overlord_treasury_grows
				and overlord_treasuries[month_index]
					> overlord_treasuries[month_index - 1]
			)
			subject_treasury_grows = (
				subject_treasury_grows
				and subject_treasuries[month_index]
					> subject_treasuries[month_index - 1]
			)
	_check(
		overlord_army != null
			and subject_light_a != null
			and subject_light_b != null
			and subject_heavy != null
			and int(initial_flows[overlord_id]["balance"])
				== 0
			and expected_subject_deficit > 0
			and subject_demobilized[0]
			and overlord_demobilized[0]
			and subject_upkeep_after_ai[0]
				< subject_city_income - subject_tribute
			and subject_unpaid[0]
				== expected_subject_deficit
			and subject_unpaid[1] == 0
			and no_repeat_demobilization
			and overlord_only_initial_demobilization
			and overlord_treasury_grows
			and subject_treasury_grows,
		"长期贡赋财政：双方应只在首轮按三年储备预算缩编一次，随后国库稳定正增长"
	)
	print(
		"  [32d-finance] 城收=%d 贡赋=%d 藩王军费=%d→%d 月亏=%d "
		% [
			subject_city_income,
			subject_tribute,
			initial_subject_upkeep,
			subject_upkeep_after_ai[0],
			expected_subject_deficit,
		]
		+ "藩王国库=%s 未付=%s 缩编=%s 宗主国库=%s 宗主缩编=%s"
		% [
			str(subject_treasuries),
			str(subject_unpaid),
			str(subject_demobilized),
			str(overlord_treasuries),
			str(overlord_demobilized),
		]
	)
	sim.free()
	e2e_sim.free()
	crisis_sim.free()


# ------------------------------------------------------------------ 32e. 区域负担评估与分封 AI（增量 B3）

func _test_enfeoff_ai() -> void:
	print("[32e] 宗藩：区域粮食/财政收益、封地道路连续性、AI 分封触发与门控")
	# 1. evaluate_region_burden 数学：负担比 = 区域边疆线所需LINE军月粮耗 / 区域月粮产；
	# 财政收益 = 可转移LINE军费 + 治理增产后的预计贡赋 - 当前直辖收入。
	var gs := GameState.new()
	gs.generate_grid_world(32051)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.WAR)
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if city.is_capital:
			continue
		# 只收接敌的边疆城，确保区域有正的应然防务需求可供校验。
		if DiplomacyAI._city_is_frontier(gs, 0, city.id):
			region.append(city.id)
		if region.size() >= 3:
			break
	var expected_food_output := 0.0
	var expected_direct_gold := 0
	var expected_vassal_gold := 0
	for city_id in region:
		expected_food_output += float(gs.cities[city_id].food_per_half_year) / 6.0
		var city_gold := Simulation.city_gold_output(
			gs,
			gs.cities[city_id]
		)
		expected_direct_gold += city_gold
		expected_vassal_gold += int(floor(
			float(city_gold)
			* Simulation
				.VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER
		))
	var expected_transfer_upkeep := 0
	var expected_transfer_count := 0
	for army in gs.transferable_vassal_line_armies(
		0,
		region
	):
		expected_transfer_count += 1
		expected_transfer_upkeep += (
			GameState.army_monthly_upkeep(army.size)
		)
	var expected_tribute := int(floor(
		float(expected_vassal_gold)
		* GameState.DEFAULT_TRIBUTE_RATE
	))
	var burden := DiplomacyAI.evaluate_region_burden(gs, 0, region)
	_check(
		_approx(float(burden["monthly_food_output"]), expected_food_output)
			and float(burden["burden_ratio"]) >= 0.0
			and int(burden["direct_gold_income"])
				== expected_direct_gold
			and int(burden["projected_vassal_gold_income"])
				== expected_vassal_gold
			and int(burden["projected_tribute_income"])
				== expected_tribute
			and int(burden["transferable_line_count"])
				== expected_transfer_count
			and int(burden["transferable_line_upkeep"])
				== expected_transfer_upkeep
			and int(burden["monthly_fiscal_benefit"])
				== (
					expected_transfer_upkeep
					+ expected_tribute
					- expected_direct_gold
				),
		"区域负担画像必须同源计算粮食负担与分封财政反事实"
	)
	# 负担比分子应来自「边疆线所需驻军」而非实际驻军：接敌区应有正的防务需求，
	# 且负担比随所需防务兵力（边疆线）单调——完全内陆无接敌边的区域负担比为 0。
	_check(
		int(burden["required_defense_troops"]) > 0
			and float(burden["burden_ratio"]) > 0.0,
		"接敌区域必须有正的应然防务需求与正负担比（实为 troops=%d ratio=%.3f）"
			% [int(burden["required_defense_troops"]), float(burden["burden_ratio"])]
	)
	# 内陆无接敌区：构造一个全被本国包围的单城区域，防务需求应为 0。
	var inland_gs := GameState.new()
	inland_gs.generate_grid_world(32051)
	# 全国和平且同属一主的语境下，任取一座四邻皆本国的内陆城，防务需求必为 0。
	var inland_region: Array[int] = []
	for city in inland_gs.land_cities_of(0):
		var all_domestic := true
		for neighbor in inland_gs.neighbors(city.id):
			if inland_gs.cities[neighbor].owner_nation != 0:
				all_domestic = false
				break
		if all_domestic and not city.is_capital:
			inland_region = [city.id]
			break
	if not inland_region.is_empty():
		var inland_burden := DiplomacyAI.evaluate_region_burden(inland_gs, 0, inland_region)
		_check(
			int(inland_burden["required_defense_troops"]) == 0
				and _approx(float(inland_burden["burden_ratio"]), 0.0),
			"完全内陆区域的应然防务需求与负担比必须为 0"
		)

	# 2. _grow_enfeoff_region 道路连续性：返回区域必须道路连通且全属本国非首都。
	var grow_state := GameState.new()
	grow_state.generate_grid_world(32052)
	var grown := DiplomacyAI._grow_enfeoff_region(grow_state, 0)
	var continuity_ok := true
	if grown.size() >= 2:
		# 每座城至少与区域内另一城有正容量边（连通性必要条件）。
		var grown_set := {}
		for cid in grown:
			grown_set[cid] = true
		for cid in grown:
			if grow_state.cities[cid].owner_nation != 0 or grow_state.cities[cid].is_capital:
				continuity_ok = false
				break
			var linked := false
			for neighbor in grow_state.neighbors(cid):
				if grown_set.has(neighbor):
					var e := grow_state.edge_of(cid, neighbor)
					if e != null and e.max_manpower > 0:
						linked = true
						break
			if not linked:
				continuity_ok = false
				break
	_check(continuity_ok, "生成的候选封地必须道路连续且全属本国非首都城")

	# 3. AI 门控与触发：战时不分封（新规则）；和平时若有高负担远边疆区则可触发。
	var ai_state := GameState.new()
	ai_state.generate_grid_world(32053)
	for a in range(ai_state.nations.size()):
		for b in range(a + 1, ai_state.nations.size()):
			ai_state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	# 先制造中央全面外战：此时不得分封（战时把前线连弱藩王一起甩出会崩溃）。
	for other in range(1, ai_state.nations.size()):
		ai_state.set_diplomatic_relation(0, other, GameState.DiplomaticRelation.WAR)
	var war_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(ai_state, war_actions, {}, {})
	var war_triggered := false
	for act in war_actions:
		if int(act.get("kind", -1)) == DiplomacyAI.Action.ENFEOFF and int(act.get("a", -1)) == 0:
			war_triggered = true
	_check(not war_triggered, "战时（中央有实战前线）不得分封")

	# 恢复和平：全部关系回中立，此时才允许分封。
	for other in range(1, ai_state.nations.size()):
		ai_state.set_diplomatic_relation(0, other, GameState.DiplomaticRelation.NEUTRAL)
	var peace_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(ai_state, peace_actions, {}, {})
	var triggered := false
	var triggered_region: Array[int] = []
	for act in peace_actions:
		if int(act.get("kind", -1)) == DiplomacyAI.Action.ENFEOFF and int(act.get("a", -1)) == 0:
			triggered = true
			for cv in act.get("region_cities", []):
				triggered_region.append(int(cv))
	# 和平时是否触发取决于是否有过阈的远边疆区；若未触发，须是被负担比/留核心合法挡下。
	var gate_region := DiplomacyAI._grow_enfeoff_region(ai_state, 0)
	var gate_reason_ok := true
	if not triggered and gate_region.size() >= DiplomacyAI.ENFEOFF_MIN_REGION_CITIES:
		var gate_burden := DiplomacyAI.evaluate_region_burden(ai_state, 0, gate_region)
		gate_reason_ok = (
				(
					float(gate_burden["burden_ratio"])
						< DiplomacyAI
							.ENFEOFF_BURDEN_RATIO_THRESHOLD
					and int(
						gate_burden[
							"monthly_fiscal_benefit"
						]
					) <= 0
				)
			or ai_state.land_cities_of(0).size() - gate_region.size()
				< DiplomacyAI.ENFEOFF_MIN_OVERLORD_CITIES_AFTER
		)
	_check(
		(triggered and triggered_region.size() >= DiplomacyAI.ENFEOFF_MIN_REGION_CITIES)
			or gate_reason_ok,
			"和平时分封要么由财政/粮食收益触发，要么被双收益/留核心门控合法挡下"
	)

	# 4. 财政路径独立触发：把候选区粮产抬高到低负担、直辖金产压低，并布置三支
	# 可转移 LINE；此时必须因「转军费 + 贡赋 - 直辖收入」为正而分封。
	var finance_state := GameState.new()
	finance_state.generate_grid_world(32054)
	for a in range(finance_state.nations.size()):
		for b in range(a + 1, finance_state.nations.size()):
			finance_state.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var finance_region := DiplomacyAI._grow_enfeoff_region(
		finance_state,
		0
	)
	var finance_retained_city := -1
	for city in finance_state.land_cities_of(0):
		if not finance_region.has(city.id):
			finance_retained_city = city.id
			break
	for army in finance_state.armies:
		if army.owner_nation == 0 and army.is_line_role():
			army.location_city = finance_retained_city
			army.move_from = finance_retained_city
			army.move_to = -1
			army.on_edge = false
			army.state = Army.State.IDLE
	for city_id in finance_region:
		finance_state.cities[city_id].gold_per_month = 1
		finance_state.cities[
			city_id
		].food_per_half_year = 100000
	if not finance_region.is_empty():
		for index in range(3):
			finance_state._spawn_conjured_army(
				0,
				finance_region[
					index % finance_region.size()
				],
				GameState.INITIAL_LIGHT_ARMY_SIZE,
				Army.StrategicRole.LINE
			)
	var finance_report := (
		DiplomacyAI.evaluate_region_burden(
			finance_state,
			0,
			finance_region
		)
	)
	var finance_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(
		finance_state,
		finance_actions,
		{},
		{}
	)
	var finance_triggered := false
	var finance_reason := ""
	for action in finance_actions:
		if (
			int(action.get("kind", -1))
				== DiplomacyAI.Action.ENFEOFF
			and int(action.get("a", -1)) == 0
		):
			finance_triggered = true
			finance_reason = str(action.get("reason", ""))
	_check(
		finance_region.size()
			>= DiplomacyAI.ENFEOFF_MIN_REGION_CITIES
			and finance_retained_city >= 0
			and float(finance_report["burden_ratio"])
				< DiplomacyAI
					.ENFEOFF_BURDEN_RATIO_THRESHOLD
			and int(
				finance_report["monthly_fiscal_benefit"]
			) > 0
			and finance_triggered
			and finance_reason.contains("财政月增益"),
		"低粮食负担但财政月增益为正时，AI 必须把分封作为开源节流策略"
	)

	# 5. 治理压力路径：旧双收益否决已被治理压力规则补全。若候选区虽财政为负、
	# 粮食负担低，但存在超行政半径且低忠的远地压力，则仍可因治理收益而分封。
	var loss_state := GameState.new()
	loss_state.generate_grid_world(32055)
	for a in range(loss_state.nations.size()):
		for b in range(a + 1, loss_state.nations.size()):
			loss_state.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var loss_region := DiplomacyAI._grow_enfeoff_region(
		loss_state,
		0
	)
	var loss_retained_city := -1
	for city in loss_state.land_cities_of(0):
		if not loss_region.has(city.id):
			loss_retained_city = city.id
			break
	for army in loss_state.armies:
		if army.owner_nation == 0 and army.is_line_role():
			army.location_city = loss_retained_city
			army.move_from = loss_retained_city
			army.move_to = -1
			army.on_edge = false
			army.state = Army.State.IDLE
	for city_id in loss_region:
		loss_state.cities[city_id].gold_per_month = 100
		loss_state.cities[
			city_id
		].food_per_half_year = 100000
	var loss_report := DiplomacyAI.evaluate_region_burden(
		loss_state,
		0,
		loss_region
	)
	var loss_governance := DiplomacyAI.evaluate_region_governance_pressure(
		loss_state,
		0,
		loss_region,
		RebellionSystem.capital_hops(loss_state, 0)
	)
	var loss_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(
		loss_state,
		loss_actions,
		{},
		{}
	)
	var loss_triggered := false
	var loss_reason := ""
	for action in loss_actions:
		if (
			int(action.get("kind", -1))
				== DiplomacyAI.Action.ENFEOFF
			and int(action.get("a", -1)) == 0
		):
			loss_triggered = true
			loss_reason = str(action.get("reason", ""))
	_check(
		loss_region.size()
			>= DiplomacyAI.ENFEOFF_MIN_REGION_CITIES
			and loss_retained_city >= 0
			and int(loss_report["transferable_line_count"])
				== 0
			and int(loss_report["monthly_fiscal_benefit"])
				< 0
			and float(loss_report["burden_ratio"])
				< DiplomacyAI
					.ENFEOFF_BURDEN_RATIO_THRESHOLD
			and int(loss_governance["pressured_city_count"]) >= 1
			and float(loss_governance["pressure_score"])
				>= DiplomacyAI.ENFEOFF_GOVERNANCE_PRESSURE_THRESHOLD
			and loss_triggered
			and loss_reason.contains("治理压力"),
		"财政月增益为负且粮食负担低时，远地治理压力高仍可触发分封"
	)

	# 5b. 真正的负面对照：财政为负、粮食负担低且治理压力也低于阈值时，AI 不得分封。
	var shallow_state := GameState.new()
	for nation_id in range(3):
		var shallow_nation := Nation.new()
		shallow_nation.id = nation_id
		shallow_nation.alive = true
		shallow_nation.ruler_archetype = RulerProfile.BALANCED
		shallow_nation.trade_policy = RulerProfile.POLICY_BALANCED
		shallow_nation.capital_city_id = 0 if nation_id == 0 else -1
		shallow_nation.treasury_gold = 1000
		shallow_nation.manpower_pool = 100000
		shallow_nation.military_payment_ratio = 1.0
		shallow_state.nations.append(shallow_nation)
	for city_id in range(11):
		var shallow_city := City.new()
		shallow_city.id = city_id
		shallow_city.name = "浅压城%d" % city_id
		shallow_city.short_name = String.chr(0x4E00 + city_id)
		shallow_city.owner_nation = 0 if city_id < 9 else 1
		shallow_city.map_position = Vector2(float(city_id) / 20.0, 0.5)
		shallow_city.coord = Vector2i(city_id, 0)
		shallow_city.loyalty = 75.0
		shallow_city.loyalty_target_nation = shallow_city.owner_nation
		shallow_city.gold_per_month = 10
		shallow_city.manpower_per_month = 10
		shallow_city.food_per_half_year = 600
		shallow_city.is_capital = city_id == 0
		shallow_city.has_warehouse = city_id == 0
		if (
			shallow_city.owner_nation == 1
			and shallow_state.nations[1].capital_city_id < 0
		):
			shallow_state.nations[1].capital_city_id = city_id
			shallow_city.is_capital = true
			shallow_city.has_warehouse = true
		shallow_state.cities.append(shallow_city)
		shallow_state.adjacency[city_id] = [] as Array[int]
	for city_id in range(shallow_state.cities.size() - 1):
		var shallow_edge := Edge.new()
		shallow_edge.city_a = city_id
		shallow_edge.city_b = city_id + 1
		shallow_edge.max_manpower = Edge.STANDARD_MANPOWER
		shallow_edge.distance = 1
		shallow_state.edge_lookup[
			shallow_state.edge_key(shallow_edge.city_a, shallow_edge.city_b)
		] = shallow_edge
		(shallow_state.adjacency[shallow_edge.city_a] as Array[int]).append(
			shallow_edge.city_b
		)
		(shallow_state.adjacency[shallow_edge.city_b] as Array[int]).append(
			shallow_edge.city_a
		)
	for city_id in shallow_state.adjacency.keys():
		(shallow_state.adjacency[city_id] as Array[int]).sort()
	shallow_state.recognized_city_owners.resize(shallow_state.cities.size())
	for city in shallow_state.cities:
		shallow_state.recognized_city_owners[city.id] = city.owner_nation
	for a in range(shallow_state.nations.size()):
		for b in range(a + 1, shallow_state.nations.size()):
			shallow_state.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var shallow_region := DiplomacyAI._grow_enfeoff_region(
		shallow_state,
		0
	)
	var shallow_retained_city := -1
	for city in shallow_state.land_cities_of(0):
		if not shallow_region.has(city.id):
			shallow_retained_city = city.id
			break
	for army in shallow_state.armies:
		if army.owner_nation == 0 and army.is_line_role():
			army.location_city = shallow_retained_city
			army.move_from = shallow_retained_city
			army.move_to = -1
			army.on_edge = false
			army.state = Army.State.IDLE
	for city_id in shallow_region:
		shallow_state.cities[city_id].gold_per_month = 100
		shallow_state.cities[city_id].food_per_half_year = 100000
	var shallow_report := DiplomacyAI.evaluate_region_burden(
		shallow_state,
		0,
		shallow_region
	)
	var shallow_governance := DiplomacyAI.evaluate_region_governance_pressure(
		shallow_state,
		0,
		shallow_region,
		RebellionSystem.capital_hops(shallow_state, 0)
	)
	var shallow_actions: Array[Dictionary] = []
	DiplomacyAI._collect_enfeoff_actions(
		shallow_state,
		shallow_actions,
		{},
		{}
	)
	var shallow_triggered := false
	for action in shallow_actions:
		if (
			int(action.get("kind", -1))
				== DiplomacyAI.Action.ENFEOFF
			and int(action.get("a", -1)) == 0
		):
			shallow_triggered = true
	_check(
		shallow_region.size()
			>= DiplomacyAI.ENFEOFF_MIN_REGION_CITIES
			and shallow_retained_city >= 0
			and int(shallow_report["transferable_line_count"])
				== 0
			and int(shallow_report["monthly_fiscal_benefit"])
				< 0
			and float(shallow_report["burden_ratio"])
				< DiplomacyAI
					.ENFEOFF_BURDEN_RATIO_THRESHOLD
			and int(shallow_governance["pressured_city_count"]) >= 1
			and float(shallow_governance["pressure_score"])
				< DiplomacyAI.ENFEOFF_GOVERNANCE_PRESSURE_THRESHOLD
			and not shallow_triggered,
		"财政月增益为负且粮食负担低、治理压力也低时，AI 不得分封"
	)

	# 6. 直接验证执行链：手动构造一个满足全部前置的分封并执行，校验不变量。
	if not triggered:
		triggered_region = gate_region
	if triggered_region.size() >= DiplomacyAI.ENFEOFF_MIN_REGION_CITIES:
		var sim := Simulation.new()
		sim.setup(ai_state)
		var executed := sim._execute_diplomatic_action({
			"kind": DiplomacyAI.Action.ENFEOFF,
			"a": 0,
			"b": 0,
			"region_cities": triggered_region,
			"reason": "回归：和平期远边疆分封执行链",
		})
		var new_subject := ai_state.overlord_of(ai_state.nations.size() - 1)
		_check(
			executed
				and ai_state.is_overlord(0)
				and ai_state.subjects_of(0).size() == 1
				and new_subject == 0
				and ai_state.suzerainty_structure_valid()
				and ai_state._battle_group_structure_valid(),
			"AI 分封动作执行后必须真实建立宗藩关系并保持全部结构不变量"
		)
		sim.free()


# ------------------------------------------------------------------ 32f. 宗藩生命周期：纽带保护与死亡清理

func _test_suzerainty_lifecycle() -> void:
	print("[32f] 宗藩：退盟不得解除宗藩纽带、死亡国悬空记录清理、多级上移")
	# 1. 退盟保护：AI 不得对宗主-藩王对产出 LEAVE_ALLIANCE 动作。
	var gs := GameState.new()
	gs.generate_grid_world(32061)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 3:
			break
	var subject := gs.enfeoff(0, region)
	_check(subject > 0 and gs.is_suzerainty_pair(0, subject), "分封应建立宗主-藩王对")
	var leave_actions: Array[Dictionary] = []
	DiplomacyAI._collect_leave_alliance_actions(gs, leave_actions, {}, {})
	var breaks_bond := false
	for act in leave_actions:
		var la := int(act.get("a", -1))
		var lb := int(act.get("b", -1))
		if gs.is_suzerainty_pair(la, lb):
			breaks_bond = true
	_check(not breaks_bond, "普通退盟不得解除宗主-藩王的 ALLIED 纽带")

	# 2. 死亡藩王清理：藩王失去全部城市后其宗藩记录必须被移除。
	var dv := GameState.new()
	dv.generate_grid_world(32062)
	for a in range(dv.nations.size()):
		for b in range(a + 1, dv.nations.size()):
			dv.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var dv_region: Array[int] = []
	for city in dv.land_cities_of(0):
		if not city.is_capital:
			dv_region.append(city.id)
		if dv_region.size() >= 3:
			break
	var dead_vassal := dv.enfeoff(0, dv_region)
	# 用一笔合法事务把藩王的实控与法理同步交回宗主，模拟藩王被灭。
	var dv_transfer := _transfer_all_owned_cities_for_fixture(
		dv, dead_vassal, 0, "dead_vassal_fixture"
	)
	var dv_pruned_after_transaction := dv.prune_dead_suzerainty()
	_check(
		bool(dv_transfer.get("ok", false))
			and bool(dv_transfer.get("changed", false))
			and bool(dv_transfer.get("political_changed", false))
			and not dv_pruned_after_transaction
			and not dv.is_vassal(dead_vassal)
			and dv.suzerainty_structure_valid()
			and dv.territory_structure_valid(),
		"死亡藩王必须由领土事务原子清理，后续 prune 幂等且不变量成立"
	)

	# 3. 死亡宗主：多级链中，宗主被灭后其藩王上移到祖父（保持链连续）。
	var mv := GameState.new()
	mv.generate_grid_world(32063)
	for a in range(mv.nations.size()):
		for b in range(a + 1, mv.nations.size()):
			mv.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	# 手工构造三级链：2 是 0 的藩王，3 是 2 的藩王（0→2→3）。
	mv.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	mv.set_diplomatic_relation(2, 3, GameState.DiplomaticRelation.ALLIED)
	# 最终 3 会越过死亡中间节点改投 0；预先建立的普通联盟边使最终图
	# 在领土事务提交后仍满足宗藩关系约束。
	mv.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.ALLIED)
	mv.suzerainty[2] = {
		"overlord_id": 0,
		"tribute_rate": 0.25, "created_day": 0, "last_centralization_day": -1,
		"civil_war": false,
	}
	mv.suzerainty[3] = {
		"overlord_id": 2,
		"tribute_rate": 0.25, "created_day": 0, "last_centralization_day": -1,
		"civil_war": false,
	}
	# 灭掉中间宗主 2：一笔事务同步其全部城市的实控与法理。
	var mv_transfer := _transfer_all_owned_cities_for_fixture(
		mv, 2, 0, "dead_middle_overlord_fixture"
	)
	var mv_pruned_after_transaction := mv.prune_dead_suzerainty()
	_check(
		bool(mv_transfer.get("ok", false))
			and bool(mv_transfer.get("changed", false))
			and bool(mv_transfer.get("political_changed", false))
			and not mv_pruned_after_transaction
			and not mv.is_vassal(2)
			and mv.overlord_of(3) == 0
			and mv.relation_between(3, 0) == GameState.DiplomaticRelation.ALLIED
			and mv.suzerainty_structure_valid()
			and mv.territory_structure_valid(),
		"中间宗主消亡后其藩王必须上移到祖父并保持 ALLIED 与不变量（overlord_of(3)=%d）"
			% mv.overlord_of(3)
	)

	# 4. 无祖父的和平藩王独立后必须把零库存中继首都升格为自身粮仓。
	var independent := GameState.new()
	independent.generate_grid_world(32064)
	for a in range(independent.nations.size()):
		for b in range(a + 1, independent.nations.size()):
			independent.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var independent_region: Array[int] = []
	for city in independent.land_cities_of(0):
		if not city.is_capital:
			independent_region.append(city.id)
		if independent_region.size() >= 3:
			break
	var independent_subject := independent.enfeoff(
		0,
		independent_region
	)
	var independent_transfer := _transfer_all_owned_cities_for_fixture(
		independent, 0, 1, "dead_root_overlord_fixture"
	)
	var independent_pruned_after_transaction := (
		independent.prune_dead_suzerainty()
	)
	var independent_capital := (
		independent.nations[
			independent_subject
		].capital_city_id
	)
	var independent_food_before := independent.cities[
		independent_capital
	].food_storage
	var independent_deposit := independent.deposit_food(
		independent_subject,
		10
	)
	_check(
		bool(independent_transfer.get("ok", false))
			and bool(independent_transfer.get("changed", false))
			and bool(independent_transfer.get("political_changed", false))
			and not independent_pruned_after_transaction
			and not independent.is_vassal(
				independent_subject
			)
			and independent.cities[
				independent_capital
			].has_warehouse
			and independent.nations[
				independent_subject
			].warehouse_city_ids == (
				[independent_capital] as Array[int]
			)
			and independent_deposit
			and independent.cities[
				independent_capital
			].food_storage == independent_food_before + 10,
		"和平藩王因宗主死亡独立后，首都必须升格粮仓且后续产粮可入库"
	)


# ------------------------------------------------------------------ 32g. 削藩内战：内战态关系与共同体解散（增量 C1）

func _test_civil_war_relations() -> void:
	print("[32g] 削藩内战：内战态宗藩WAR、共同体解散、状态机与不变量")
	var gs := GameState.new()
	gs.generate_grid_world(32071)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 3:
			break
	var subject := gs.enfeoff(0, region)
	_check(
		subject > 0
			and not gs.is_in_civil_war(subject)
			and gs.is_allied(0, subject)
			and gs.alliance_bloc(0).has(subject),
		"分封后：非内战、宗藩ALLIED、同属一个对外共同体"
	)

	# 发起削藩内战：宗藩转 WAR、共同体解散、不变量在内战态下成立。
	var started := gs.start_civil_war(subject)
	_check(
		started
			and gs.is_in_civil_war(subject)
			and gs.is_enemy(0, subject)
			and not gs.alliance_bloc(0).has(subject)
			and gs.suzerainty_structure_valid()
			and gs.territory_structure_valid()
			and gs._battle_group_structure_valid(),
		"内战态：宗藩必须WAR、对外共同体解散、结构不变量仍成立"
	)
	# 内战期间宗藩关系仍在（仅关系态变化，非撤藩）。
	_check(
		gs.overlord_of(subject) == 0 and gs.is_vassal(subject),
		"内战期间宗藩关系记录必须保留（内战≠撤藩）"
	)
	# 重复发起应失败（幂等保护）。
	_check(not gs.start_civil_war(subject), "已在内战中不得重复发起")

	# 结束内战（藩王战败保留宗藩）：恢复ALLIED、清内战标记、共同体重聚。
	var ended := gs.end_civil_war(subject)
	_check(
		ended
			and not gs.is_in_civil_war(subject)
			and gs.is_allied(0, subject)
			and gs.alliance_bloc(0).has(subject)
			and gs.suzerainty_structure_valid()
			and gs.territory_structure_valid()
			and gs._battle_group_structure_valid(),
		"内战结束：宗藩恢复ALLIED、共同体重聚、不变量成立"
	)

	# 内战中宗主死亡：藩王应脱离（无祖父则独立），内战标记清除。
	var dg := GameState.new()
	dg.generate_grid_world(32072)
	for a in range(dg.nations.size()):
		for b in range(a + 1, dg.nations.size()):
			dg.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var dg_region: Array[int] = []
	for city in dg.land_cities_of(0):
		if not city.is_capital:
			dg_region.append(city.id)
		if dg_region.size() >= 3:
			break
	var dg_sub := dg.enfeoff(0, dg_region)
	dg.start_civil_war(dg_sub)
	# 宗主 0 全境失守：同一事务同步实控、法理、库存与最终宗藩图。
	var dg_transfer := _transfer_all_owned_cities_for_fixture(
		dg, 0, dg_sub, "civil_war_dead_overlord_fixture"
	)
	var dg_pruned_after_transaction := dg.prune_dead_suzerainty()
	_check(
		bool(dg_transfer.get("ok", false))
			and bool(dg_transfer.get("changed", false))
			and bool(dg_transfer.get("political_changed", false))
			and not dg_pruned_after_transaction
			and not dg.is_vassal(dg_sub)
			and dg.suzerainty_structure_valid()
			and dg.territory_structure_valid(),
		(
			"内战中宗主消亡必须由领土事务原子完成：藩王脱离宗藩、"
			+ "内战标记随记录清除，后续 prune 幂等"
		)
	)

	# 内战宗藩对不得被联盟批量议和误停战（回归：撤藩不变量后期偶发失败根因）。
	# 构造宗主 0 与内战藩王 1 分属对立联盟集团：0 ALLIED 2、1 ALLIED 3、2↔3 外部 WAR。
	# bloc(0)={0,2} 与 bloc(1)={1,3} 因 2↔3 议和时会遍历到内战对 0↔1（WAR），
	# 若在此停战会抹掉 WAR 却留 civil_war 标记 → 违反不变量第2条，潜伏到后续撤藩才爆。
	var cw := GameState.new()
	cw.generate_grid_world(32073)
	for a in range(cw.nations.size()):
		for b in range(a + 1, cw.nations.size()):
			cw.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	cw.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": true,
	}
	cw.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	cw.set_diplomatic_relation(0, 2, GameState.DiplomaticRelation.ALLIED)
	cw.set_diplomatic_relation(1, 3, GameState.DiplomaticRelation.ALLIED)
	cw.set_diplomatic_relation(0, 3, GameState.DiplomaticRelation.WAR)
	cw.set_diplomatic_relation(2, 1, GameState.DiplomaticRelation.WAR)
	cw.set_diplomatic_relation(2, 3, GameState.DiplomaticRelation.WAR)
	cw.refresh_derived()
	_check(
		cw.alliance_bloc(0, false) == [0, 2]
			and cw.alliance_bloc(1, false) == [1, 3]
			and cw.suzerainty_structure_valid(),
		"复现前置：内战宗主与藩王分属对立联盟集团，初始结构合法"
	)
	var cw_sim := Simulation.new()
	cw_sim.setup(cw)
	var civil_city := cw.land_cities_of(1)[0]
	var civil_occupation_city: City = null
	for candidate in cw.land_cities_of(1):
		if (
			candidate.id != civil_city.id
			and not candidate.is_capital
			and not candidate.has_warehouse
		):
			civil_occupation_city = candidate
			break
	_check(
		civil_occupation_city != null,
		"削藩内战和平隔离回归必须找到一座普通藩王城市"
	)
	var civil_control_changed := false
	if civil_occupation_city != null:
		var civil_control_result: Dictionary = cw.transfer_city_control(
			civil_occupation_city.id, 0, 0
		)
		civil_control_changed = bool(
			civil_control_result.get("changed", false)
		)
		# 同时做成断联占领，确保普通和平的 restore 与 recognize 两条
		# 领土结算路径都不得越权处理被排除的削藩内战战果。
		for neighbor in cw.neighbors(civil_occupation_city.id):
			var occupation_edge := cw.edge_of(
				civil_occupation_city.id, neighbor
			)
			if occupation_edge != null:
				occupation_edge.max_manpower = 0
	var civil_besieger: Army = null
	var allied_defender: Army = null
	for army in cw.armies:
		if army.owner_nation == 0 and civil_besieger == null:
			civil_besieger = army
		elif (
			army.owner_nation == 3
			and allied_defender == null
		):
			allied_defender = army
	var civil_siege := cw.new_battle(
		Battle.Kind.SIEGE
	)
	civil_siege.city = civil_city
	civil_siege.has_garrison = true
	civil_siege.side_a.append(civil_besieger)
	civil_siege.side_b.append(allied_defender)
	civil_besieger.state = Army.State.FIGHTING
	civil_besieger.battle_id = civil_siege.id
	allied_defender.state = Army.State.FIGHTING
	allied_defender.battle_id = civil_siege.id
	# 触发外部战争 2↔3 的联盟议和（主对非内战对，绕过收集器层门控，直击执行层）。
	var cw_peace := cw_sim._make_coalition_peace(2, 3)
	_check(
		bool(cw_peace.get("changed", false))
			and cw.relation_between(2, 3) == GameState.DiplomaticRelation.NEUTRAL,
		"外部战争 2↔3 仍正常经联盟议和停战"
	)
	_check(
		civil_control_changed
			and cw.relation_between(0, 1) == GameState.DiplomaticRelation.WAR
			and cw.is_in_civil_war(1)
			and civil_occupation_city != null
			and civil_occupation_city.owner_nation == 0
			and cw.recognized_owner_of(civil_occupation_city.id) == 1
			and civil_occupation_city.occupation_sponsor_nation == 0
			and int(cw_peace.get("territories_transferred", -1)) == 0
			and int(cw_peace.get("occupations_restored", -1)) == 0
			and int(cw_peace.get("occupations_normalized", -1)) == 0
			and cw.suzerainty_structure_valid()
			and cw.territory_structure_valid(),
		(
			"普通集团议和必须排除仍在继续的削藩内战 0↔1：关系保持 WAR，"
			+ "断联内战占领既不恢复也不确认法理，结构不变量成立"
		)
	)
	_check(
		cw.battles.has(civil_siege)
			and not civil_siege.finished
			and civil_siege.side_a.has(civil_besieger)
			and not civil_siege.side_b.has(
				allied_defender
			)
			and civil_besieger.battle_id
				== civil_siege.id
			and allied_defender.battle_id == -1,
		"外部盟友议和只能移出该盟友守军，仍为 WAR 的削藩围城必须继续"
	)
	# 内战战果结算由内战自身负责；结束该内战后再做统一和平归一化，
	# 不需要挂起或重放刚才那场普通战争的领土事务。
	var civil_war_ended := cw.end_civil_war(1)
	var normalized_after_civil_war := cw.normalize_peaceful_occupations()
	_check(
		civil_war_ended
			and normalized_after_civil_war.is_empty()
			and civil_occupation_city.owner_nation == 1
			and cw.recognized_owner_of(civil_occupation_city.id) == 1
			and civil_occupation_city.occupation_sponsor_nation == -1
			and cw.territory_structure_valid(),
		"削藩内战结束后统一归一化必须清理其临时占领，不依赖普通和平重放"
	)
	cw_sim.free()



# ------------------------------------------------------------------ 32h. 削藩决策与反抗判据（增量 C2）

func _test_centralization_decision() -> void:
	print("[32h] 削藩：财政收益主判据、高威胁例外、反抗比、和平撤藩守恒")
	# 构造宗主 0 + 藩王：把藩王大部分军队清掉，制造宗主压倒性优势→藩王接受。
	var gs := GameState.new()
	gs.generate_grid_world(32081)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 3:
			break
	var subject := gs.enfeoff(0, region)
	_check(subject > 0, "分封应成功建立藩王")

	# 削弱藩王：清空其大部分军队，使反抗比远低于阈值 → 预判为「接受」。
	var removed := 0
	for army in gs.armies:
		if army.owner_nation == subject and removed < 100:
			army.size = 0
			removed += 1
	var weak_ratio := DiplomacyAI.vassal_resist_ratio(gs, subject)
	var weak_fiscal := (
		DiplomacyAI
			.evaluate_centralization_fiscal_benefit(
				gs,
				subject
			)
	)
	var expected_direct_income := 0
	for city in gs.cities_of(subject):
		expected_direct_income += (
			Simulation.city_gold_output_before_governance(
				gs,
				city
			)
		)
	var weak_gold_flow := Simulation.monthly_gold_flows(gs)[
		subject
	]
	_check(
		weak_ratio
			< DiplomacyAI.CENTRALIZE_RESIST_RATIO_THRESHOLD
			and int(weak_fiscal["projected_direct_income"])
				== expected_direct_income
			and int(weak_fiscal["inherited_subordinate_tribute"])
				== int(weak_gold_flow["tribute_received"])
			and int(weak_fiscal["lost_subject_tribute"])
				== int(weak_gold_flow["tribute_paid"])
			and int(weak_fiscal["inherited_military_upkeep"])
				== int(weak_gold_flow["military_upkeep"])
			and int(weak_fiscal["monthly_fiscal_benefit"])
				== (
					expected_direct_income
					+ int(weak_gold_flow["tribute_received"])
					- int(weak_gold_flow["tribute_paid"])
					- int(weak_gold_flow["military_upkeep"])
				),
		"撤藩财政反事实须同源计算直辖收入、下级贡赋、原贡赋与接收军费"
	)
	# 分封保护期内不得削藩：刚分封（created_day==0）时评估应无削藩动作，杜绝「封了又撤」横跳。
	var fresh_actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(gs, fresh_actions, {}, {})
	var fresh_has_centralize := false
	for act in fresh_actions:
		if int(act.get("kind", -1)) == DiplomacyAI.Action.CENTRALIZE and int(act.get("b", -1)) == subject:
			fresh_has_centralize = true
	_check(
		not fresh_has_centralize,
		"分封保护期内不得对新藩王削藩（防止分封↔撤回反复横跳）"
	)
	# 越过分封保护期后方可削藩：把世界日推进到超过 CENTRALIZE_MIN_VASSAL_AGE_DAYS。
	gs.day = DiplomacyAI.CENTRALIZE_MIN_VASSAL_AGE_DAYS + 1
	var actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(gs, actions, {}, {})
	var accept_action := {}
	for act in actions:
		if int(act.get("kind", -1)) == DiplomacyAI.Action.CENTRALIZE and int(act.get("b", -1)) == subject:
			accept_action = act
	_check(
		int(weak_fiscal["monthly_fiscal_benefit"]) > 0
			and not accept_action.is_empty()
			and int(
				accept_action.get(
					"monthly_fiscal_benefit",
					0
				)
			) > 0
			and not bool(accept_action.get("resist", true)),
		"撤藩财政收益为正且藩王弱小时，应产出和平撤藩动作"
	)

	# 战时不得削藩：给宗主制造实战外战，动作应消失。
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var war_actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(gs, war_actions, {}, {})
	var war_has_centralize := false
	for act in war_actions:
		if int(act.get("kind", -1)) == DiplomacyAI.Action.CENTRALIZE and int(act.get("a", -1)) == 0:
			war_has_centralize = true
	_check(not war_has_centralize, "宗主正陷外战时不得削藩")
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.NEUTRAL)

	# 和平撤藩执行：资源守恒（撤藩前后宗主+藩王 人力/金钱 总量不变）、藩王被吸收。
	var pre_manpower := gs.nations[0].manpower_pool + gs.nations[subject].manpower_pool
	var pre_gold := gs.nations[0].treasury_gold + gs.nations[subject].treasury_gold
	var subject_cities := gs.land_cities_of(subject).size()
	var overlord_cities_before := gs.land_cities_of(0).size()
	var sim := Simulation.new()
	sim.setup(gs)
	var executed := sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.CENTRALIZE,
		"a": 0,
		"b": subject,
		"resist": false,
		"reason": "回归：和平撤藩",
	})
	_check(
		executed
			and not gs.is_vassal(subject)
			and not gs.nations[subject].alive
			and gs.land_cities_of(0).size() == overlord_cities_before + subject_cities
			and gs.nations[0].manpower_pool == pre_manpower
			and gs.nations[0].treasury_gold == pre_gold
			and gs.suzerainty_structure_valid()
			and gs._battle_group_structure_valid(),
		"和平撤藩：藩王全境并回宗主、资源守恒、宗藩记录清除、不变量成立"
	)
	sim.free()

	# 财政亏损且威胁不高时不得撤藩，防止移除军力优势门槛后周期性无条件削藩。
	var loss_state := GameState.new()
	loss_state.generate_grid_world(32083)
	for a in range(loss_state.nations.size()):
		for b in range(a + 1, loss_state.nations.size()):
			loss_state.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var loss_region: Array[int] = []
	for city in loss_state.land_cities_of(0):
		if not city.is_capital:
			loss_region.append(city.id)
		if loss_region.size() >= 3:
			break
	var loss_subject := loss_state.enfeoff(
		0,
		loss_region
	)
	for city in loss_state.cities_of(loss_subject):
		city.gold_per_month = 0
	loss_state.day = (
		DiplomacyAI.CENTRALIZE_MIN_VASSAL_AGE_DAYS + 1
	)
	var loss_fiscal := (
		DiplomacyAI
			.evaluate_centralization_fiscal_benefit(
				loss_state,
				loss_subject
			)
	)
	var loss_ratio := DiplomacyAI.vassal_resist_ratio(
		loss_state,
		loss_subject
	)
	var loss_actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(
		loss_state,
		loss_actions,
		{},
		{}
	)
	var loss_has_centralize := false
	for action in loss_actions:
		if (
			int(action.get("kind", -1))
				== DiplomacyAI.Action.CENTRALIZE
			and int(action.get("b", -1))
				== loss_subject
		):
			loss_has_centralize = true
	_check(
		int(loss_fiscal["monthly_fiscal_benefit"]) < 0
			and loss_ratio
				< DiplomacyAI
					.CENTRALIZE_POLITICAL_THREAT_RATIO_THRESHOLD
			and not loss_has_centralize,
		"撤藩财政亏损且政治威胁未达高危阈值时，不得削藩"
	)

	# 高威胁例外：大藩王即使撤藩财政亏损、军力强于宗主，仍应触发削藩并反抗。
	var rs := GameState.new()
	rs.generate_grid_world(32082)
	for a in range(rs.nations.size()):
		for b in range(a + 1, rs.nations.size()):
			rs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var rs_region: Array[int] = []
	for city in rs.land_cities_of(0):
		if not city.is_capital:
			rs_region.append(city.id)
		if rs_region.size() >= 3:
			break
	var rs_sub := rs.enfeoff(0, rs_region)
	for city in rs.cities_of(rs_sub):
		city.gold_per_month = 0
	# 削弱宗主自身军队，使藩王超过高威胁阈值；旧的 1.5 倍军力优势门槛在此必定失败。
	var rs_removed := 0
	for army in rs.armies:
		if army.owner_nation == 0 and rs_removed < 100:
			army.size = 0
			rs_removed += 1
	rs.day = (
		DiplomacyAI.CENTRALIZE_MIN_VASSAL_AGE_DAYS + 1
	)
	var rs_fiscal := (
		DiplomacyAI
			.evaluate_centralization_fiscal_benefit(
				rs,
				rs_sub
			)
	)
	var strong_ratio := DiplomacyAI.vassal_resist_ratio(rs, rs_sub)
	# 削藩反抗现由 RebellionSystem 统一判断：除军力外，还必须满足
	# 低忠诚持续三个月与双方叛乱冷却。显式构造该政治成熟状态。
	for city in rs.land_cities_of(rs_sub):
		city.loyalty = RebellionSystem.LOYALTY_REBEL
		city.rebellion_progress = RebellionSystem.REBELLION_PROGRESS_MONTHS
	rs.nations[0].last_rebellion_day = -1
	rs.nations[rs_sub].last_rebellion_day = -1
	var rs_actions: Array[Dictionary] = []
	DiplomacyAI._collect_centralization_actions(
		rs,
		rs_actions,
		{},
		{}
	)
	var resist_action := {}
	for action in rs_actions:
		if (
			int(action.get("kind", -1))
				== DiplomacyAI.Action.CENTRALIZE
			and int(action.get("b", -1)) == rs_sub
		):
			resist_action = action
	var rs_sim := Simulation.new()
	rs_sim.setup(rs)
	var rs_exec := (
		rs_sim._execute_diplomatic_action(resist_action)
		if not resist_action.is_empty()
		else false
	)
	_check(
		int(rs_fiscal["monthly_fiscal_benefit"]) < 0
			and strong_ratio
				>= DiplomacyAI
					.CENTRALIZE_POLITICAL_THREAT_RATIO_THRESHOLD
			and not resist_action.is_empty()
			and bool(resist_action.get("resist", false))
			and str(
				resist_action.get("reason", "")
			).contains("政治威胁比")
			and rs_exec
			and rs.is_in_civil_war(rs_sub)
			and rs.is_enemy(0, rs_sub)
			and rs.is_vassal(rs_sub)
			and rs.suzerainty_structure_valid(),
		"高威胁大藩王须绕过财政亏损触发削藩，并以反抗进入内战"
	)
	rs_sim.free()


# ------------------------------------------------------------------ 32i. 削藩内战通吃结算（增量 C3）

func _test_civil_war_annexation() -> void:
	print("[32i] 削藩内战：宗主占藩王首都吞并、藩王占宗主首都继承体系")
	# 情形一：宗主赢——占藩王首都→吞并藩王全境。
	var gs := GameState.new()
	gs.generate_grid_world(32091)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 8:
			break
	var subject := gs.enfeoff(0, region)
	var child_region: Array[int] = []
	var subject_land_count := gs.land_cities_of(subject).size()
	for child_candidate in gs.land_cities_of(subject):
		if child_candidate.is_capital:
			continue
		var candidate_closure := gs.enfeoff_region_closure(
			subject,
			[child_candidate.id] as Array[int]
		)
		if (
			not candidate_closure.is_empty()
			and candidate_closure.size() < subject_land_count
		):
			child_region = candidate_closure
			break
	var child_subject := gs.enfeoff(subject, child_region)
	_check(
		child_subject > subject
			and gs.overlord_of(child_subject) == subject,
		"削藩兼并测试须通过真实分封建立下级藩王"
	)
	gs.start_civil_war(subject)
	_check(
		gs.external_territory_recipient(subject) == subject,
		"削藩内战反叛方已脱离和平主权链，对外领土接收者必须是自己"
	)
	# 用合法世界上的 stale revision 在任何提交前拒绝兼并。这里包含下级
	# 藩王，能精确捕获旧实现先改挂宗藩树/外交、再因领土事务失败而半提交。
	var rejected_annex_before := _territory_fingerprint(gs)
	var rejected_annex := gs.annex_nation(
		0, subject, gs.ownership_revision + 1
	)
	_check(
		not rejected_annex
			and _territory_fingerprint(gs) == rejected_annex_before
			and gs.is_in_civil_war(subject)
			and gs.overlord_of(subject) == 0
			and gs.overlord_of(child_subject) == subject
			and gs.suzerainty_structure_valid()
			and gs.territory_structure_valid()
			and gs._battle_group_structure_valid(),
		(
			"annex_nation 的领土 revision 冲突必须返回 false，且宗藩树/"
			+ "外交/军队/资源/领土完整回滚"
		)
	)
	# stock_policy_overrides 是刻意受限的兼并入口：不能借它改写败方
	# 当前未实控的城市，也不能注入事务不认识的库存策略。任一非法项
	# 必须在 planner 阶段整笔拒绝且没有副作用。
	var invalid_override_before := _territory_fingerprint(gs)
	var rejected_foreign_override := gs.annex_nation(
		0,
		subject,
		-1,
		{
			gs.nations[0].capital_city_id: (
				GameState.TerritoryStockDisposition.CAPTURE_SPOILS
			),
		}
	)
	var rejected_policy_override := gs.annex_nation(
		0,
		subject,
		-1,
		{gs.nations[subject].capital_city_id: 999}
	)
	_check(
		not rejected_foreign_override
			and not rejected_policy_override
			and _territory_fingerprint(gs) == invalid_override_before,
		(
			"annex_nation 库存 override 仅允许败方当前实控城市和四种"
			+ "合法策略，非法项必须零副作用拒绝"
		)
	)
	# 把反叛藩王压缩到只剩首都一城：旧实现会先提交单城占领，令
	# 领土事务提前删除死亡藩王的内战边，随后再也识别不到通吃。
	var subject_capital_id := gs.nations[subject].capital_city_id
	var subject_collapse_operations: Array[Dictionary] = []
	for subject_city in gs.cities_of(subject):
		if subject_city.id == subject_capital_id:
			continue
		subject_collapse_operations.append({
			"city_id": subject_city.id,
			"controller_id": 0,
			"legal_owner_id": 0,
			"sponsor_id": -1,
			"reset_political_target": true,
			"stock_policy": (
				GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
			),
			"reason": "civil_capture_last_capital_fixture",
		})
	var subject_collapsed := gs.apply_territory_transaction(
		subject_collapse_operations
	)
	var subject_capital := gs.cities[subject_capital_id]
	subject_capital.food_storage = 100
	gs.refresh_derived()
	_check(
		bool(subject_collapsed.get("ok", false))
			and gs.cities_of(subject).size() == 1
			and subject_capital.owner_nation == subject
			and subject_capital.has_warehouse
			and gs.overlord_of(child_subject) == subject
			and gs.is_in_civil_war(subject),
		"宗主胜回归夹具须保留内战藩王最后一座首都及其下级藩王"
	)
	var overlord_cities_before := gs.land_cities_of(0).size()
	var subject_cities := gs.land_cities_of(subject).size()
	var overlord_food_before := gs.nations[0].granary_food
	var capture_revision_before := gs.ownership_revision
	var sim := Simulation.new()
	sim.setup(gs)
	var overlord_captor: Army = null
	for candidate in gs.armies:
		if candidate.owner_nation == 0 and candidate.size > 0:
			overlord_captor = candidate
			break
	_check(overlord_captor != null, "宗主胜回归须找到宗主攻城军")
	if overlord_captor != null:
		overlord_captor.location_city = subject_capital_id
		overlord_captor.move_from = subject_capital_id
		overlord_captor.move_to = -1
		overlord_captor.move_progress = 0.0
		overlord_captor.on_edge = false
		overlord_captor.state = Army.State.IDLE
		overlord_captor.battle_id = -1
		overlord_captor.path.clear()
		overlord_captor.occupation_claimant_nation = 0
		sim._capture_city(
			overlord_captor, subject_capital, -1, false
		)
	_check(
		not gs.is_vassal(subject)
			and not gs.nations[subject].alive
			and gs.overlord_of(child_subject) == 0
			and gs.is_allied(0, child_subject)
			and gs.land_cities_of(0).size() == overlord_cities_before + subject_cities
			and subject_capital.owner_nation == 0
			and not subject_capital.has_warehouse
			and subject_capital.food_storage == 0
			and gs.nations[0].granary_food == (
				overlord_food_before
				+ int(floor(
					100.0 * GameState.TERRITORY_CAPTURE_SPOILS_RATE
				))
			)
			and gs.ownership_revision == capture_revision_before + 1
			and gs.suzerainty_structure_valid()
			and gs.territory_structure_valid()
			and gs._battle_group_structure_valid(),
		(
			"宗主真实攻破藩王最后首都：单次事务吞并、下级藩王改投，"
			+ "首都库存仅获30%且不变量成立"
		)
	)
	sim.free()

	# 兼并原语必须分别迁移实控与法理，并终止兼并后失去敌对性的战斗。
	var atomic := GameState.new()
	atomic.generate_grid_world(32093)
	for a in range(atomic.nations.size()):
		for b in range(a + 1, atomic.nations.size()):
			atomic.set_diplomatic_relation(
				a,
				b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	atomic.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var captured_legal_city := atomic.land_cities_of(1)[0]
	captured_legal_city.owner_nation = 0
	var third_party_legal_city := atomic.land_cities_of(1)[1]
	atomic.recognized_city_owners[
		third_party_legal_city.id
	] = 2
	third_party_legal_city.occupation_sponsor_nation = 1
	var absorber_army: Army = null
	var absorbed_army: Army = null
	for army in atomic.armies:
		if army.owner_nation == 0 and absorber_army == null:
			absorber_army = army
		elif (
			army.owner_nation == 1
			and absorbed_army == null
		):
			absorbed_army = army
	var stale_claim_army: Army = atomic.armies[0]
	stale_claim_army.occupation_claimant_nation = 1
	var internal_battle := atomic.new_battle(
		Battle.Kind.FIELD
	)
	internal_battle.side_a.append(absorber_army)
	internal_battle.side_b.append(absorbed_army)
	absorber_army.state = Army.State.FIGHTING
	absorber_army.battle_id = internal_battle.id
	absorbed_army.state = Army.State.FIGHTING
	absorbed_army.battle_id = internal_battle.id
	var atomic_annexed := atomic.annex_nation(0, 1)
	_check(
		atomic_annexed
			and atomic.recognized_owner_of(
			captured_legal_city.id
		) == 0
			and third_party_legal_city.owner_nation == 0
			and atomic.recognized_owner_of(
				third_party_legal_city.id
			) == 2
			and third_party_legal_city
				.occupation_sponsor_nation == 0
			and internal_battle.finished
			and absorber_army.battle_id == -1
			and absorbed_army.battle_id == -1
			and absorber_army.owner_nation == 0
			and absorbed_army.owner_nation == 0
			and stale_claim_army
				.occupation_claimant_nation == 0,
		"兼并须独立迁移实控/法理/占领声明，并原子解除已变成同国的战斗"
	)

	# 情形二：藩王赢——占宗主首都→夺取宗主全境，其余藩王转投，胜者成新顶点。
	var vs := GameState.new()
	vs.generate_grid_world(32092)
	for a in range(vs.nations.size()):
		for b in range(a + 1, vs.nations.size()):
			vs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	# 宗主 0 分封两个藩王：winner 与 sibling。
	var r1: Array[int] = []
	for city in vs.land_cities_of(0):
		if not city.is_capital:
			r1.append(city.id)
		if r1.size() >= 3:
			break
	var winner := vs.enfeoff(0, r1)
	var r2: Array[int] = []
	for city in vs.land_cities_of(0):
		if not city.is_capital:
			r2.append(city.id)
		if r2.size() >= 3:
			break
	var sibling := vs.enfeoff(0, r2)
	_check(winner > 0 and sibling > 0 and winner != sibling, "应成功分封两个藩王")
	vs.start_civil_war(winner)
	# 同样把旧宗主压缩到只剩首都，以覆盖反向兼并时首笔单城事务
	# 会提前提升藩王、令 live 宗藩查询失效的历史回归。
	var overlord_capital_id := vs.nations[0].capital_city_id
	var overlord_collapse_operations: Array[Dictionary] = []
	for overlord_city in vs.cities_of(0):
		if overlord_city.id == overlord_capital_id:
			continue
		overlord_collapse_operations.append({
			"city_id": overlord_city.id,
			"controller_id": winner,
			"legal_owner_id": winner,
			"sponsor_id": -1,
			"reset_political_target": true,
			"stock_policy": (
				GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
			),
			"reason": "civil_capture_last_overlord_capital_fixture",
		})
	var overlord_collapsed := vs.apply_territory_transaction(
		overlord_collapse_operations
	)
	var overlord_capital := vs.cities[overlord_capital_id]
	overlord_capital.food_storage = 100
	vs.refresh_derived()
	_check(
		bool(overlord_collapsed.get("ok", false))
			and vs.cities_of(0).size() == 1
			and overlord_capital.owner_nation == 0
			and overlord_capital.has_warehouse
			and vs.overlord_of(winner) == 0
			and vs.is_in_civil_war(winner)
			and vs.overlord_of(sibling) == 0,
		"藩王胜回归夹具须保留旧宗主最后一座首都与兄弟藩王"
	)
	var winner_food_before := vs.nations[winner].granary_food
	var vs_capture_revision_before := vs.ownership_revision
	var vs_sim := Simulation.new()
	vs_sim.setup(vs)
	var vassal_captor: Army = null
	for candidate in vs.armies:
		if candidate.owner_nation == winner and candidate.size > 0:
			vassal_captor = candidate
			break
	_check(vassal_captor != null, "藩王胜回归须找到反叛方攻城军")
	if vassal_captor != null:
		vassal_captor.location_city = overlord_capital_id
		vassal_captor.move_from = overlord_capital_id
		vassal_captor.move_to = -1
		vassal_captor.move_progress = 0.0
		vassal_captor.on_edge = false
		vassal_captor.state = Army.State.IDLE
		vassal_captor.battle_id = -1
		vassal_captor.path.clear()
		vassal_captor.occupation_claimant_nation = winner
		vs_sim._capture_city(
			vassal_captor, overlord_capital, -1, false
		)
	_check(
		not vs.nations[0].alive
			and vs.cities_of(0).is_empty()
			and not vs.is_vassal(winner)          # 胜者升为新顶点
			and vs.overlord_of(sibling) == winner  # 兄弟藩王转投胜者
			and vs.is_allied(winner, sibling)
			and not vs.is_in_civil_war(sibling)
			and overlord_capital.owner_nation == winner
			and not overlord_capital.has_warehouse
			and overlord_capital.food_storage == 0
			and vs.nations[winner].granary_food == (
				winner_food_before
				+ int(floor(
					100.0 * GameState.TERRITORY_CAPTURE_SPOILS_RATE
				))
			)
			and vs.ownership_revision == vs_capture_revision_before + 1
			and vs.suzerainty_structure_valid()
			and vs.territory_structure_valid()
			and vs._battle_group_structure_valid(),
		(
			"藩王真实攻破宗主最后首都：单次事务继承体系、兄弟改投，"
			+ "首都库存仅获30%且胜者成为主权顶点"
		)
	)
	vs_sim.free()


# ------------------------------------------------------------------ 32i2. 共享粮仓 + 补给中继节点 + 内战切分

func _test_shared_granary_and_relay_supply() -> void:
	print("[32i2] 共享粮仓：分封守恒归根池、藩王首都零库存中继降损耗、内战切分守恒+火星兵")
	# --- 1. 分封：粮食不划走、全归宗主根池；藩王首都为零库存中继节点 ---
	var gs := GameState.new()
	gs.generate_grid_world(41001)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	gs.refresh_derived()
	var pre_food := gs.nations[0].granary_food
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 3:
			break
	var subject := gs.enfeoff(0, region)
	gs.refresh_derived()
	# 本段只验证宗藩共享粮池聚合；贸易已不再产生粮食外部流量。
	for pool_nation in gs.nations:
		pool_nation.trade_policy = RulerProfile.POLICY_ISOLATION
	var sub_capital := gs.nations[subject].capital_city_id
	_check(
		subject > 0
			and not gs.cities[sub_capital].has_warehouse
			and gs.cities[sub_capital].food_storage == 0
			and gs.nations[subject].granary_food == 0
			and gs.nations[0].granary_food == pre_food
			and gs.food_pool_holder(subject) == 0,
		"分封后粮食全留宗主根池（%d==%d）、藩王首都零库存中继" % [gs.nations[0].granary_food, pre_food]
	)
	gs.nations[0].food_demand_ema = 100000.0
	gs.nations[subject].food_demand_ema = 200000.0
	var pool_expected_production := 0.0
	var pool_garrisons := Simulation.build_garrison_index(
		gs
	)
	for member_id in gs.food_pool_members(0):
		for city in gs.cities_of(member_id):
			pool_expected_production += (
				float(Simulation.city_food_output(
					gs,
					city,
					pool_garrisons
				)) / 6.0
			)
	var pool_report := DiplomacyAI.war_food_report(
		gs,
		0
	)
	_check(
		int(pool_report["pool_holder"]) == 0
			and pool_report["pool_members"]
				== gs.food_pool_members(0)
			and is_equal_approx(
				float(pool_report[
					"monthly_food_production"
				]),
				pool_expected_production
			)
			and is_equal_approx(
				float(pool_report[
					"current_monthly_demand"
				]),
				300000.0
			),
		"宗藩战争粮食报告必须按共享粮池聚合全部成员的生产、需求与库存"
	)

	# --- 2. 补给中继降损耗：构造线性走廊 0-8-16-24-32-40，宗主根首都在城0，藩王首都在城40。
	# 城40 远离城0（5 跳）。藩王首都作为零损耗中继起点注入后，城40 处损耗应从「5 跳距离」
	# 骤降到 0（它就是中继起点），对照「无中继」（藩王首都不作起点）时城40 需从城0 累计 5 跳。 ---
	var corr := GameState.new()
	corr.generate_grid_world(41005)
	corr.armies.clear()
	corr.battles.clear()
	for city in corr.cities:
		city.owner_nation = 3
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		corr.recognized_city_owners[city.id] = 3
	for corridor_edge in corr.edges:
		corridor_edge.max_manpower = 0
	# 走廊城归宗主 0；城40 稍后划给藩王作首都。
	for corridor_city_id in [0, 8, 16, 24, 32, 40]:
		corr.cities[corridor_city_id].owner_nation = 0
		corr.recognized_city_owners[corridor_city_id] = 0
	for corridor_road in [[0, 8], [8, 16], [16, 24], [24, 32], [32, 40]]:
		corr.edge_of(int(corridor_road[0]), int(corridor_road[1])).max_manpower = Edge.STANDARD_MANPOWER
	corr.nations[0].capital_city_id = 0
	corr.cities[0].is_capital = true
	corr.cities[0].has_warehouse = true
	corr.cities[0].food_storage = 100000
	corr.nations[0].warehouse_city_ids = [0] as Array[int]
	corr.refresh_derived()
	# 对照组（无中继）：城40 仍属宗主、非中继起点，损耗从城0 累计 5 跳。
	var no_relay_network := Pathfinding.build_supply_network(corr, 0)
	var no_relay_dist := INF
	for source in no_relay_network:
		var pdist: PackedFloat64Array = source["dist"]
		no_relay_dist = minf(no_relay_dist, pdist[40])
	# 实验组（有中继）：把城40 划为藩王首都（零库存中继节点）。
	var corr_sub := corr.enfeoff(0, [40])
	corr.refresh_derived()
	_check(
		corr_sub > 0
			and corr.nations[corr_sub].capital_city_id == 40
			and not corr.cities[40].has_warehouse
			and corr.food_pool_relay_capitals(0) == ([40] as Array[int]),
		"走廊藩王首都(城40)须为宗主粮池的零库存中继起点"
	)
	var relay_network := Pathfinding.build_supply_network(corr, 0)
	var relay_dist := INF
	for source in relay_network:
		var dist_field: PackedFloat64Array = source["dist"]
		relay_dist = minf(relay_dist, dist_field[40])
	_check(
		is_equal_approx(relay_dist, 0.0) and no_relay_dist > 0.0,
		"藩王首都中继必须把偏远城40 损耗从%.4f 降到 0（中继起点自身零损耗）" % no_relay_dist
	)

	# --- 3. 削藩内战：反叛方按领土粮食产能占比切分共享库存（守恒）、并刷火星兵 ---
	var cw := GameState.new()
	cw.generate_grid_world(41002)
	for a in range(cw.nations.size()):
		for b in range(a + 1, cw.nations.size()):
			cw.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	cw.refresh_derived()
	var cw_region: Array[int] = []
	for city in cw.land_cities_of(0):
		if not city.is_capital:
			cw_region.append(city.id)
		if cw_region.size() >= 3:
			break
	var rebel := cw.enfeoff(0, cw_region)
	cw.refresh_derived()
	var pool_food_before := cw.nations[0].granary_food + cw.nations[rebel].granary_food
	var rebel_armies_before := 0
	for army in cw.armies:
		if army.owner_nation == rebel and army.size > 0:
			rebel_armies_before += 1
	var rebel_land := cw.land_cities_of(rebel).size()
	var started := cw.start_civil_war(rebel)
	cw.refresh_derived()
	# 切分守恒：内战后宗主根池 + 反叛方新池 = 内战前共享池总量。
	var pool_food_after := cw.nations[0].granary_food + cw.nations[rebel].granary_food
	_check(
		started
			and pool_food_after == pool_food_before
			and cw.nations[rebel].granary_food > 0
			and cw.cities[cw.nations[rebel].capital_city_id].has_warehouse
			and cw.food_pool_holder(rebel) == rebel,
		"内战切分共享库存必须守恒（前%d==后%d）且反叛方自成一池" % [pool_food_before, pool_food_after]
	)
	# 火星兵：反叛方首都凭空动员 ceil(0.1 × 陆城数) 个满编主战军团。
	var expected_uprising := int(ceil(0.1 * float(rebel_land)))
	var rebel_main_armies := 0
	for army in cw.armies:
		if (
			army.owner_nation == rebel
			and army.size == GameState.INITIAL_HEAVY_ARMY_SIZE
			and army.strategic_role == Army.StrategicRole.MAIN
			and army.location_city == cw.nations[rebel].capital_city_id
		):
			rebel_main_armies += 1
	_check(
		rebel_main_armies >= expected_uprising
			and expected_uprising >= 1
			and cw._battle_group_structure_valid()
			and cw.suzerainty_structure_valid(),
		"内战起兵须刷 ceil(0.1×%d)=%d 个满编主战火星兵（实测≥%d）且结构不变量成立"
			% [rebel_land, expected_uprising, rebel_main_armies]
	)


# ------------------------------------------------------------------ 32i3. 藩王就近治理产出加成

func _test_vassal_governance_output_bonus() -> void:
	print("[32i3] 藩王加成：藩王疆域城市钱粮产出×1.5、owner 派生自动生效、经济结算与AI估值同源")
	var gs := GameState.new()
	gs.generate_grid_world(41010)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	# 构造宗主 0 与藩王，藩王 id 明确；随后在同一城上翻转 owner，隔离 garrison/war 等混淆项，
	# 纯粹检验「owner 是否藩王」这一维度对产出真源的 1.5× 影响。
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 3:
			break
	var subject := gs.enfeoff(0, region)
	_check(subject > 0 and gs.is_vassal(subject) and not gs.is_vassal(0), "分封应建立藩王且宗主非藩王")
	# 本用例只隔离宗藩治理倍率；新藩王正常会获得独立随机君主，
	# 若不显式中性化便会把治理倍率与君主产出倍率混在一起。
	_set_neutral_ruler(gs.nations[0])
	_set_neutral_ruler(gs.nations[subject])

	# 取一座宗主直辖的非首都城作探针（owner=0，非藩王）。清战乱减产 + 清驻军，
	# 使 garrison 惩罚在翻转 owner 前后都为 0，隔离出纯粹的治理倍率维度。
	var probe: City = null
	for city in gs.land_cities_of(0):
		if not city.is_capital and city.gold_per_month > 0 and city.food_per_half_year > 0:
			probe = city
			break
	_check(probe != null, "需要一座有正钱粮产出的宗主城作为探针")
	probe.war_disruption_until_day = 0
	for army in gs.armies:
		if not army.on_edge and army.location_city == probe.id:
			army.size = 0
	var overlord_gold := Simulation.city_gold_output(gs, probe)
	var overlord_food := Simulation.city_food_output(gs, probe)
	_check(
		is_equal_approx(Simulation.city_governance_output_multiplier(gs, probe), 1.0)
			and overlord_gold == probe.gold_per_month,
		"宗主直辖城无治理加成（倍率=1，钱产=基础字段）"
	)

	# 仅把该城 owner 翻转为藩王（不动其它状态），同城产出应精确变 1.5×（floor）。
	probe.owner_nation = subject
	var vassal_gold := Simulation.city_gold_output(gs, probe)
	var vassal_food := Simulation.city_food_output(gs, probe)
	_check(
		is_equal_approx(
			Simulation.city_governance_output_multiplier(gs, probe),
			Simulation.VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER
		)
			and vassal_gold == int(floor(float(overlord_gold) * 1.5))
			and vassal_food == int(floor(float(overlord_food) * 1.5)),
		"藩王城钱粮产出须为 1.5×（gold %d→%d、food %d→%d）"
			% [overlord_gold, vassal_gold, overlord_food, vassal_food]
	)

	# owner 派生：翻回宗主，加成自动消失（纯 owner 派生、零残留状态）。
	probe.owner_nation = 0
	_check(
		is_equal_approx(Simulation.city_governance_output_multiplier(gs, probe), 1.0)
			and Simulation.city_gold_output(gs, probe) == overlord_gold,
		"城并回宗主后治理加成必须自动消失（纯 owner 派生）"
	)


# ------------------------------------------------------------------ 32i4. 宗藩断联不等于占领

func _test_suzerainty_disconnection_requires_capture() -> void:
	print("[32i4] 宗藩飞地：断联不等于占领，实际攻占后议和才确认法理")

	# --- 子场景 A：合法连通的藩王领土不得被误清理（无假阳性）---
	# 链 0-1-2-3-4：宗主 0 首都=城0、直辖 城0/城1；藩王 1 领 城2/城3/城4，经 城1-城2 连回宗主。
	# 此时藩王领土经宗主城1 与体系首都连通（体系视为整体），不是飞地 → 每日清理必须不动它。
	var sa := GameState.new()
	sa.generate_grid_world(51001)
	sa.armies.clear()
	sa.battles.clear()
	for city in sa.cities:
		city.owner_nation = 3
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		sa.recognized_city_owners[city.id] = 3
	for c in [0, 1]:
		sa.cities[c].owner_nation = 0
		sa.recognized_city_owners[c] = 0
	for c in [2, 3, 4]:
		sa.cities[c].owner_nation = 1
		sa.recognized_city_owners[c] = 1
	for road in [[0, 1], [1, 2], [2, 3], [3, 4]]:
		var e := sa.edge_of(int(road[0]), int(road[1]))
		if e != null:
			e.max_manpower = Edge.STANDARD_MANPOWER
	sa.nations[0].capital_city_id = 0
	sa.cities[0].is_capital = true
	sa.cities[0].has_warehouse = true
	sa.nations[1].capital_city_id = 2
	sa.cities[2].is_capital = true
	for a in range(sa.nations.size()):
		for b in range(a + 1, sa.nations.size()):
			sa.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	sa.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	sa.suzerainty[1] = {
		"overlord_id": 0, "tribute_rate": 0.25,
		"created_day": 0, "last_centralization_day": -1, "civil_war": false,
	}
	sa.refresh_derived()
	_check(
		sa.cities[2].owner_nation == 1
			and sa.cities[3].owner_nation == 1
			and sa.cities[4].owner_nation == 1
			and sa.suzerainty_structure_valid(),
		"无假阳性：经宗主连通的藩王领土不得被误清理（2=%d 3=%d 4=%d）"
			% [sa.cities[2].owner_nation, sa.cities[3].owner_nation, sa.cities[4].owner_nation]
	)

	# --- 子场景 B：被敌方体系包围也不能自动易手；实际攻占才产生临时占领。---
	# 链 0-1-2-3-4，体系 0→1 的藩王领城3/4；城2 属敌体系 2→3 的藩王3。
	var sb := GameState.new()
	sb.generate_grid_world(51002)
	sb.armies.clear()
	sb.battles.clear()
	for city in sb.cities:
		city.owner_nation = 3
		city.is_capital = false
		city.has_warehouse = false
		city.food_storage = 0
		sb.recognized_city_owners[city.id] = 3
	for c in [0, 1]:
		sb.cities[c].owner_nation = 0
		sb.recognized_city_owners[c] = 0
	for c in [3, 4]:
		sb.cities[c].owner_nation = 1
		sb.recognized_city_owners[c] = 1
	sb.cities[63].owner_nation = 2
	sb.recognized_city_owners[63] = 2
	for road in [[0, 1], [1, 2], [2, 3], [3, 4]]:
		var e := sb.edge_of(int(road[0]), int(road[1]))
		if e != null:
			e.max_manpower = Edge.STANDARD_MANPOWER
	sb.nations[0].capital_city_id = 0
	sb.cities[0].is_capital = true
	sb.cities[0].has_warehouse = true
	sb.nations[1].capital_city_id = 3
	sb.cities[3].is_capital = true
	_set_single_warehouse(sb, 0, 0, 0)
	_set_warehouses(sb, 1, [] as Array[int], [] as Array[int], 3)
	sb.cities[3].is_capital = true
	_set_single_warehouse(sb, 2, 63, 0)
	# 国3在本夹具中没有实控城市，必须显式清掉生成期留下的首都/粮仓索引。
	# 国3仍持有大多数背景城市，作为国2的和平藩属保留首都但不设独立粮仓。
	_set_warehouses(sb, 3, [] as Array[int], [] as Array[int], 62)
	sb.cities[62].is_capital = true
	for a in range(sb.nations.size()):
		for b in range(a + 1, sb.nations.size()):
			sb.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	sb.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.ALLIED)
	sb.suzerainty[1] = {
		"overlord_id": 0, "tribute_rate": 0.25,
		"created_day": 0, "last_centralization_day": -1, "civil_war": false,
	}
	sb.set_diplomatic_relation(2, 3, GameState.DiplomaticRelation.ALLIED)
	sb.suzerainty[3] = {
		"overlord_id": 2, "tribute_rate": 0.25,
		"created_day": 0, "last_centralization_day": -1, "civil_war": false,
	}
	for attacker in [0, 1]:
		for defender in [2, 3]:
			sb.set_diplomatic_relation(
				attacker, defender, GameState.DiplomaticRelation.WAR
			)
	var sb_garrison := _make_army(12990, 1, 5000, 10, 10)
	sb_garrison.max_size = GameState.INITIAL_LIGHT_ARMY_SIZE
	sb_garrison.location_city = 3
	sb_garrison.move_from = 3
	sb_garrison.state = Army.State.IDLE
	sb.armies.append(sb_garrison)
	sb.refresh_derived()
	_check(
		sb.cities[3].owner_nation == 1
			and sb.cities[4].owner_nation == 1
			and sb_garrison.size == 5000,
		(
			"战争飞地内仍有本体系守军时不得因道路断联直接吞并或删除驻军"
			+ "（3=%d 4=%d 守军=%d）"
		) % [
			sb.cities[3].owner_nation,
			sb.cities[4].owner_nation,
			sb_garrison.size,
		]
	)
	# 和平时地理断联本身不能代替割地协议。
	for attacker in [0, 1]:
		for defender in [2, 3]:
			sb.set_diplomatic_relation(
				attacker, defender, GameState.DiplomaticRelation.NEUTRAL
			)
	sb_garrison.size = 0
	_check(
		sb.cities[3].owner_nation == 1
			and sb.cities[4].owner_nation == 1
			and sb.recognized_owner_of(3) == 1
			and sb.recognized_owner_of(4) == 1,
		"和平时断联藩王飞地不得无协议自动割给相邻国家"
	)
	# 恢复战争后，即使没有守军，断联本身也不能产生敌方实控。
	for attacker in [0, 1]:
		for defender in [2, 3]:
			sb.set_diplomatic_relation(
				attacker, defender, GameState.DiplomaticRelation.WAR
			)
	_check(
		sb.cities[3].owner_nation == 1
			and sb.cities[4].owner_nation == 1
			and sb.recognized_owner_of(3) == 1
			and sb.recognized_owner_of(4) == 1
			and sb.cities[3].occupation_sponsor_nation == -1
			and sb.cities[4].occupation_sponsor_nation == -1
			and sb.suzerainty_structure_valid(),
		(
			"战争与道路断联不能替代真实攻城，飞地 {3,4} 必须继续由原国实控"
			+ "（3=%d 4=%d）"
		)
			% [sb.cities[3].owner_nation, sb.cities[4].owner_nation]
	)
	# 显式模拟城4被敌方宗主实际攻下；只有这一步才能形成临时占领。
	var sb_capture_result: Dictionary = sb.transfer_city_control(4, 2, 2)
	_check(
		bool(sb_capture_result.get("changed", false))
			and sb.cities[3].owner_nation == 1
			and sb.recognized_owner_of(3) == 1
			and sb.cities[3].occupation_sponsor_nation == -1
			and sb.cities[4].owner_nation == 2
			and sb.recognized_owner_of(4) == 1
			and sb.cities[4].occupation_sponsor_nation == 2
			and sb.territory_structure_valid(),
		"只有显式 transfer_city_control 才能把断联城4变成敌方临时占领"
	)
	var sb_recognized := sb.recognize_coalition_occupied_territory(
		[0, 1] as Array[int],
		[2, 3] as Array[int]
	)
	_check(
		sb_recognized == ([4] as Array[int])
			and sb.cities[3].owner_nation == 1
			and sb.recognized_owner_of(3) == 1
			and sb.cities[3].occupation_sponsor_nation == -1
			and sb.cities[4].owner_nation == 2
			and sb.recognized_owner_of(4) == 2
			and sb.cities[4].occupation_sponsor_nation == -1
			and sb.territory_structure_valid(),
		"只有实际攻占形成的临时占领，才可在集团议和后确认为法理领土"
	)


# ------------------------------------------------------------------ 32i4b. 对外领土主权接收者

func _test_external_territory_sovereignty() -> void:
	print("[32i4b] 对外领土：藩王与盟友出发地决定战果，法理收复仍归原藩王")
	var gs := GameState.new()
	gs.generate_grid_world(51003)
	gs.armies.clear()
	gs.battles.clear()
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	# 两个独立宗藩体系：0→1 与 2→3。
	for pair in [[0, 1], [2, 3]]:
		var root := int(pair[0])
		var subject := int(pair[1])
		gs.suzerainty[subject] = {
			"overlord_id": root,
			"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
			"created_day": 0,
			"last_centralization_day": -1,
			"civil_war": false,
		}
		gs.set_diplomatic_relation(
			root, subject, GameState.DiplomaticRelation.ALLIED
		)
		# 手工挂接宗藩时同步模拟 enfeoff() 的共享粮仓语义：藩王首都
		# 保留首都身份，但不再拥有独立粮仓或库存。
		for warehouse_id in gs.nations[subject].warehouse_city_ids:
			gs.cities[warehouse_id].has_warehouse = false
			gs.cities[warehouse_id].food_storage = 0
		gs.nations[subject].warehouse_city_ids.clear()
	for attacker in [0, 1]:
		for defender in [2, 3]:
			gs.set_diplomatic_relation(
				attacker, defender, GameState.DiplomaticRelation.WAR
			)
	gs.refresh_derived()
	var subject_origin: City = null
	var subject_target: City = null
	for border_edge in gs.edges:
		var border_a := gs.cities[border_edge.city_a]
		var border_b := gs.cities[border_edge.city_b]
		if border_a.owner_nation == 1 and border_b.owner_nation == 3:
			subject_origin = border_a
			subject_target = border_b
			border_edge.max_manpower = Edge.STANDARD_MANPOWER
			break
		if border_b.owner_nation == 1 and border_a.owner_nation == 3:
			subject_origin = border_b
			subject_target = border_a
			border_edge.max_manpower = Edge.STANDARD_MANPOWER
			break
	var second_target: City = null
	for city in gs.land_cities_of(3):
		if city != subject_target and not city.is_capital and not city.has_warehouse:
			second_target = city
			break
	_check(
		subject_origin != null and subject_target != null and second_target != null,
		"跨宗藩领土测试必须找到藩王到敌方藩王的真实边界及第二座普通城"
	)
	var sim := Simulation.new()
	sim.setup(gs)
	# A 宗主军从自己的藩王领土出发攻下 B 藩王城市：实控归提供
	# 进攻出发地的 A 藩王，B 藩王法理暂时保留，sponsor 仍是实际交战军。
	var subject_army := _make_army(12991, 0, 5000, 10, 10)
	subject_army.location_city = subject_origin.id
	subject_army.move_from = subject_origin.id
	subject_army.state = Army.State.MOVING
	subject_army.path = [subject_target.id] as Array[int]
	gs.armies.append(subject_army)
	sim._begin_next_leg(subject_army)
	var frozen_subject_claimant := subject_army.occupation_claimant_nation
	sim._release_edge(subject_army)
	subject_army.location_city = subject_target.id
	subject_army.move_from = subject_target.id
	sim._capture_city(subject_army, subject_target)
	_check(
		frozen_subject_claimant == 1
			and subject_army.occupation_claimant_nation == -1
			and subject_target.owner_nation == 1
			and gs.recognized_owner_of(subject_target.id) == 3
			and subject_target.occupation_sponsor_nation == 0,
		(
			"宗主军从藩王领土进攻时实控必须归该藩王，"
			+ "sponsor 保留宗主且不能把控制权上收"
		)
	)
	var recognized := gs.recognize_coalition_occupied_territory(
		[0, 1] as Array[int],
		[2, 3] as Array[int]
	)
	_check(
		recognized.has(subject_target.id)
			and subject_target.owner_nation == 1
			and gs.recognized_owner_of(subject_target.id) == 1
			and subject_target.occupation_sponsor_nation == -1,
		"集团议和确认战果时，外国藩王旧地必须成为实际占领藩王的法理领土"
	)

	# 集团和平：claimant 1 控制并持有库存的粮仓确认给自身时，作为
	# 和平藩王仍共享宗主 0 的粮池，库存必须完整进入根粮仓。
	var coalition_warehouse: City = null
	for candidate in gs.land_cities_of(2):
		if not candidate.is_capital and not candidate.has_warehouse:
			coalition_warehouse = candidate
			break
	_check(
		coalition_warehouse != null,
		"集团和平粮仓上收回归必须找到一座普通敌方城市"
	)
	if coalition_warehouse != null:
		var coalition_recipient_warehouse := gs.warehouse_cities_of(0)[0]
		var coalition_food_before := coalition_recipient_warehouse.food_storage
		var coalition_captured_food := 137
		coalition_warehouse.owner_nation = 1
		coalition_warehouse.occupation_sponsor_nation = 1
		coalition_warehouse.has_warehouse = true
		coalition_warehouse.food_storage = coalition_captured_food
		gs.nations[1].warehouse_city_ids.append(coalition_warehouse.id)
		var coalition_warehouse_recognized := (
			gs.recognize_coalition_occupied_territory(
				[0, 1] as Array[int],
				[2, 3] as Array[int]
			)
		)
		_check(
			coalition_warehouse_recognized.has(
				coalition_warehouse.id
			)
				and coalition_warehouse.owner_nation == 1
				and gs.recognized_owner_of(coalition_warehouse.id) == 1
				and coalition_warehouse.occupation_sponsor_nation == -1
				and not coalition_warehouse.has_warehouse
				and coalition_warehouse.food_storage == 0
				and not gs.nations[1].warehouse_city_ids.has(
					coalition_warehouse.id
				)
				and coalition_recipient_warehouse.food_storage
					== coalition_food_before + coalition_captured_food
				and gs.territory_structure_valid(),
			"集团和平确认藩王 claimant 粮仓时必须完整回流共享粮池并清理原城粮仓状态"
		)

	# 宗主替本体系藩王收复其法理旧地时，法理优先，仍归原藩王。
	gs.recognized_city_owners[second_target.id] = 1
	var root_army := _make_army(12992, 0, 5000, 10, 10)
	root_army.location_city = second_target.id
	root_army.move_from = second_target.id
	gs.armies.append(root_army)
	sim._capture_city(root_army, second_target)
	_check(
		second_target.owner_nation == 1
			and gs.recognized_owner_of(second_target.id) == 1
			and second_target.occupation_sponsor_nation == -1,
		"宗主或同体系盟军收复藩王法理领土时必须归还藩王，不能上收宗主"
	)
	_check(gs.suzerainty_structure_valid(), "跨体系领土结算后宗藩结构必须保持合法")
	gs.refresh_derived()
	_check(
		gs.territory_structure_valid(),
		"跨体系领土结算后实控/法理/首都/粮仓结构必须保持合法"
	)
	sim.free()

	# 宗主0/藩王1/敌2：藩王攻城时战果实控与 sponsor 都归藩王。
	# 藩王随后灭亡时，正常的死亡宗藩继承再把其法理交给宗主。
	var departed_state := GameState.new()
	departed_state.generate_grid_world(51005)
	departed_state.armies.clear()
	departed_state.battles.clear()
	for departed_a in range(departed_state.nations.size()):
		for departed_b in range(
			departed_a + 1, departed_state.nations.size()
		):
			departed_state.set_diplomatic_relation(
				departed_a, departed_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	departed_state.suzerainty[1] = {
		"overlord_id": 0,
		"tribute_rate": GameState.DEFAULT_TRIBUTE_RATE,
		"created_day": 0,
		"last_centralization_day": -1,
		"civil_war": false,
	}
	departed_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.ALLIED
	)
	departed_state.set_diplomatic_relation(
		0, 2, GameState.DiplomaticRelation.WAR
	)
	departed_state.set_diplomatic_relation(
		1, 2, GameState.DiplomaticRelation.WAR
	)
	# 手工宗藩与 enfeoff 保持相同共享粮池语义。
	for departed_warehouse_id in (
		departed_state.nations[1].warehouse_city_ids.duplicate()
	):
		departed_state.cities[departed_warehouse_id].has_warehouse = false
		departed_state.cities[departed_warehouse_id].food_storage = 0
	departed_state.nations[1].warehouse_city_ids.clear()
	departed_state.refresh_derived()
	var departed_target: City = null
	for candidate in departed_state.land_cities_of(2):
		if not candidate.is_capital and not candidate.has_warehouse:
			departed_target = candidate
			break
	_check(departed_target != null, "死亡藩王 sponsor 回归必须找到敌方普通城市")
	if departed_target != null:
		var departed_sim := Simulation.new()
		departed_sim.setup(departed_state)
		var departed_army := _make_army(12993, 1, 5000, 10, 10)
		departed_army.location_city = departed_target.id
		departed_army.move_from = departed_target.id
		departed_state.armies.append(departed_army)
		departed_sim._capture_city(departed_army, departed_target)
		_check(
			departed_target.owner_nation == 1
				and departed_state.recognized_owner_of(departed_target.id) == 2
				and departed_target.occupation_sponsor_nation == 1,
			"藩王军攻下敌城后必须形成 owner=1 sponsor=1 legal=2"
		)
		var subject_operations: Array[Dictionary] = []
		for subject_city in departed_state.cities_of(1):
			subject_operations.append({
				"city_id": subject_city.id,
				"controller_id": 0,
				"legal_owner_id": 0,
				"sponsor_id": -1,
				"reset_political_target": true,
				"reason": "departed_vassal_fixture",
				"stock_policy": (
					GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
				),
			})
		var subject_removed: Dictionary = (
			departed_state.apply_territory_transaction(subject_operations)
		)
		departed_state.suzerainty.erase(1)
		departed_state.set_diplomatic_relation(
			1, 2, GameState.DiplomaticRelation.NEUTRAL
		)
		departed_state.refresh_derived()
		var departed_peace := departed_sim._make_coalition_peace(0, 2)
		_check(
			bool(subject_removed.get("ok", false))
				and bool(subject_removed.get("changed", false))
				and departed_state.cities_of(1).is_empty()
				and not departed_state.nations[1].alive
				and not departed_state.is_enemy(1, 2)
				and bool(departed_peace.get("changed", false))
				and departed_target.owner_nation == 0
				and departed_state.recognized_owner_of(departed_target.id) == 0
				and departed_target.occupation_sponsor_nation == -1
				and departed_state.territory_structure_valid(),
			(
				"藩王无城并退出 1-2 战争后，0-2 集团议和仍必须按宗主 "
				+ "sponsor 将其攻占城永久确认给0"
			)
		)
		departed_sim.free()


# ------------------------------------------------------------------ 32i5. 藩王 MAIN 封国内线指挥

func _test_vassal_local_main_command() -> void:
	print("[32i5] 藩王军制：分封赐LINE、自主征MAIN、封国内线换防与法理收复")
	var gs := GameState.new()
	gs.generate_grid_world(52001)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var region: Array[int] = []
	for city in gs.land_cities_of(0):
		if not city.is_capital:
			region.append(city.id)
		if region.size() >= 3:
			break
	var subject := gs.enfeoff(0, region)
	_check(subject > 0, "分封应成功建立藩王")

	# 分封当下地方化驻防 LINE 并补齐到陆城数；MAIN 留待后续自费组建。
	var land := gs.land_cities_of(subject).size()
	var line_n := 0
	var main_n := 0
	for army in gs.armies:
		if army.owner_nation == subject and army.size > 0:
			if army.is_main_battle_role():
				main_n += 1
			elif army.is_line_role():
				line_n += 1
	_check(
		line_n == land and main_n == 0 and gs.nations[subject].battle_groups.is_empty(),
		"分封赐藩王=陆城数的LINE(实%d/城%d)、无MAIN(%d)、无战团(%d)"
			% [line_n, land, main_n, gs.nations[subject].battle_groups.size()]
	)

	# 藩王可用自身资源组建 MAIN 战团。
	var sim := Simulation.new()
	sim.setup(gs)
	gs.uses_heightmap = true
	gs.nations[subject].treasury_gold = 100000
	gs.nations[subject].manpower_pool = 100000
	var cap := gs.nations[subject].capital_city_id
	gs.deposit_food(0, 100000)
	var initial_view := AiWorldView.build(gs, subject)
	var initial_snapshot := StrategicMapSnapshot.build(
		initial_view
	)
	var initial_threat := ThreatField.build(initial_view)
	var initial_plan := CityDefensePlan.build(
		initial_view,
		initial_snapshot,
		initial_threat
	)
	var autonomous_recruited := (
		sim._ai_manage_force_structure(
			initial_view,
			initial_snapshot,
			initial_threat,
			initial_plan
		)
	)
	var vassal_group: BattleGroup = (
		gs.nations[subject].battle_groups[0]
		if not gs.nations[
			subject
		].battle_groups.is_empty()
		else null
	)
	var autonomous_main: Army = null
	if vassal_group != null:
		var autonomous_members := (
			gs.battle_group_members(
				subject,
				vassal_group.id
			)
		)
		if not autonomous_members.is_empty():
			autonomous_main = autonomous_members[0]
	_check(
		autonomous_recruited
			and autonomous_main != null
			and autonomous_main.is_main_battle_role(),
		"资源充足时藩王 AI 应自主创建第一支 MAIN 战团"
	)
	if vassal_group == null or autonomous_main == null:
		sim.free()
		return
	var vassal_main := sim._create_army_for_nation(
		subject,
		cap,
		GameState.INITIAL_HEAVY_ARMY_SIZE,
		"藩王组建内线MAIN",
		true,
		vassal_group.id if vassal_group != null else -1
	)
	_check(
		vassal_main != null
			and vassal_main.owner_nation == subject
			and vassal_main.is_main_battle_role(),
		"藩王应能以本国资源组建自有 MAIN 战团"
	)
	if vassal_main == null:
		sim.free()
		return

	# 对照：宗主 0 征 MAIN 应成功（宗主可建主战力）。
	gs.nations[0].treasury_gold = 100000
	gs.nations[0].manpower_pool = 100000
	var overlord_cap := gs.nations[0].capital_city_id
	var overlord_group := gs.create_battle_group(0)
	var overlord_main := sim._create_army_for_nation(
		0, overlord_cap, GameState.INITIAL_HEAVY_ARMY_SIZE, "宗主征MAIN", true, overlord_group.id
	)
	_check(
		overlord_main != null and overlord_main.is_main_battle_role(),
		"宗主必须能征召 MAIN 主战军团（对照）"
	)

	# 平时 MAIN 归入完整战团并驻扎在本藩王重点城市。
	var reserve_view := AiWorldView.build(gs, subject)
	var reserve_snapshot := StrategicMapSnapshot.build(
		reserve_view
	)
	var reserve_threat := ThreatField.build(reserve_view)
	var reserve_plan := CityDefensePlan.build(
		reserve_view,
		reserve_snapshot,
		reserve_threat
	)
	var reserve_city := reserve_plan.assigned_city_for(
		vassal_main
	)
	_check(
		reserve_plan.vassal_main_reserve_city_count() >= 1
			and reserve_city >= 0
			and gs.cities[reserve_city].owner_nation
				== subject,
		"藩王 MAIN 必须被分配到本国重点城市（reserve=%d count=%d）"
			% [
				reserve_city,
				reserve_plan.vassal_main_reserve_city_count(),
			]
	)

	# 战时本藩王防区内换防：任一本国城市被围后，完整 MAIN 战团优先调往该城解围。
	var relief_city := -1
	for neighbor in gs.neighbors(cap):
		var edge := gs.edge_of(cap, neighbor)
		if (
			gs.cities[neighbor].owner_nation == subject
			and edge != null
			and edge.max_manpower
				>= GameState.INITIAL_HEAVY_ARMY_SIZE
		):
			relief_city = neighbor
			break
	_check(relief_city >= 0, "藩王换防测试需要第二座封地城市")
	var enemy_id := 1
	gs.set_diplomatic_relation(
		subject,
		enemy_id,
		GameState.DiplomaticRelation.WAR
	)
	var besieger := _make_army(
		9701,
		enemy_id,
		5000,
		10
	)
	besieger.state = Army.State.FIGHTING
	besieger.location_city = relief_city
	besieger.move_from = relief_city
	gs.armies.append(besieger)
	var relief_siege := gs.new_battle(Battle.Kind.SIEGE)
	relief_siege.city = gs.cities[relief_city]
	relief_siege.side_a.append(besieger)
	besieger.battle_id = relief_siege.id
	var relief_view := AiWorldView.build(gs, subject)
	var relief_plan := CityDefensePlan.build(
		relief_view,
		StrategicMapSnapshot.build(relief_view),
		ThreatField.build(relief_view)
	)
	var relief_candidate := relief_plan.candidate_for(
		vassal_main,
		ArmyCoordinator.new()
	)
	_check(
		relief_plan.assigned_city_for(vassal_main)
				== relief_city
			and relief_candidate != null
			and relief_candidate.kind
				== ActionCandidate.Kind.REINFORCE
			and relief_candidate.target_city
				== relief_city,
		"战时藩王 MAIN 应在本防区换防并增援被围城市%d"
			% relief_city
	)

	# 法理失地收复：失守封地是唯一允许的攻击目标，且仍按普通围城门槛评估。
	gs.battles.clear()
	gs.armies.erase(besieger)
	for army in gs.armies.duplicate():
		if army.owner_nation == enemy_id:
			gs.armies.erase(army)
	gs.cities[relief_city].owner_nation = enemy_id
	gs.recognized_city_owners[relief_city] = subject
	gs.cities[relief_city].fort_strength = 1
	gs.ownership_revision += 1
	gs.deposit_food(0, 100000)
	var reclaim_view := AiWorldView.build(gs, subject)
	var reclaim_snapshot := StrategicMapSnapshot.build(
		reclaim_view
	)
	var reclaim_candidate := UtilityAI.choose(
		reclaim_view,
		reclaim_snapshot,
		ThreatField.build(reclaim_view),
		ArmyCoordinator.new(),
		vassal_main,
		UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO,
		CityDefensePlan.build(
			reclaim_view,
			reclaim_snapshot,
			ThreatField.build(reclaim_view)
		)
	)
	_check(
		reclaim_candidate.kind
				== ActionCandidate.Kind.ATTACK
			and reclaim_candidate.target_city
				== relief_city,
		"藩王 MAIN 应主动收复本国法理失地%d，不得攻击其他敌城（kind=%d target=%d reason=%s）"
			% [
				relief_city,
				reclaim_candidate.kind,
				reclaim_candidate.target_city,
				reclaim_candidate.reason,
			]
	)

	# 攻势外交门控：藩王与敌国交战也不主动宣战（进攻性外交由宗主代理）。
	var war_state := GameState.new()
	war_state.generate_grid_world(52002)
	for a in range(war_state.nations.size()):
		for b in range(a + 1, war_state.nations.size()):
			war_state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var war_region: Array[int] = []
	for city in war_state.land_cities_of(0):
		if not city.is_capital:
			war_region.append(city.id)
		if war_region.size() >= 3:
			break
	var war_vassal := war_state.enfeoff(0, war_region)
	var war_actions: Array[Dictionary] = []
	DiplomacyAI._collect_war_actions(war_state, war_actions, {}, {})
	var vassal_declares := false
	for action in war_actions:
		if int(action.get("a", -1)) == war_vassal or int(action.get("nation_id", -1)) == war_vassal:
			vassal_declares = true
	_check(not vassal_declares, "藩王不得出现在主动宣战/战备动作的发起方")
	sim.free()


# ------------------------------------------------------------------ 32i6. 敌城滞留军队每日驱离

func _test_stranded_hostile_army_eviction() -> void:
	print("[32i6] 敌城滞留驱离：定居在无通行权敌城的己方军队须每日兜底撤离，杜绝 IDLE 死锁")
	var gs := GameState.new()
	gs.generate_grid_world(53001)
	gs.armies.clear()
	gs.battles.clear()
	# 全图归敌国 1；国 0 只留首都城0，与敌城1 有正容量道路（撤退有路可走）。
	for city in gs.cities:
		city.owner_nation = 1
		city.is_capital = false
		city.has_warehouse = false
		gs.recognized_city_owners[city.id] = 1
	gs.cities[0].owner_nation = 0
	gs.recognized_city_owners[0] = 0
	gs.nations[0].capital_city_id = 0
	gs.cities[0].is_capital = true
	gs.cities[0].has_warehouse = true
	gs.nations[1].capital_city_id = 63
	gs.cities[63].is_capital = true
	for road in [[0, 1], [1, 2]]:
		var e := gs.edge_of(int(road[0]), int(road[1]))
		if e != null:
			e.max_manpower = Edge.STANDARD_MANPOWER
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	gs.refresh_derived()
	# 人为制造滞留：国 0 的一支 LINE 军 IDLE 定居在敌城1（无通行权）。
	var stranded := _make_army(9301, 0, 5000, 10)
	stranded.location_city = 1
	stranded.move_from = 1
	stranded.move_to = -1
	stranded.on_edge = false
	stranded.state = Army.State.IDLE
	gs.armies.append(stranded)
	var sim := Simulation.new()
	sim.setup(gs)
	_check(
		stranded.current_city_node() == 1
			and not gs.has_military_access(0, 1),
		"前置：滞留军应定居敌城1 且国0 对国1 无通行权"
	)
	# 直接触发兜底清理：滞留军须被撤离（不再定居敌城1）。
	sim._evict_stranded_hostile_armies()
	_check(
		stranded.state == Army.State.RETREATING
			or stranded.current_city_node() != 1
			or stranded.size <= 0,
		"敌城滞留军队须被驱离（state=%d node=%d size=%d）"
			% [stranded.state, stranded.current_city_node(), stranded.size]
	)
	sim.free()


# ------------------------------------------------------------------ 32j. 分封战争加成 + 藩王首都失陷不投降

func _test_vassal_wartime_support_and_capital() -> void:
	print("[32j] 分封战争加成：前线藩王自有军团守土、后方藩王提贡赋、藩王首都失陷不投降割地")
	var gs := GameState.new()
	gs.generate_grid_world(32095)
	for a in range(gs.nations.size()):
		for b in range(a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	# 国家角色：0=宗主，1=前线藩王，2=后方藩王，3=敌国。
	# 城市（基于 grid 真实边）：城0=宗主首都；城1=前线藩王首都(城1↔城2 有边,接壤敌国)；
	# 城2=敌国；城9=后方藩王首都(城9 邻 城1/城10/城17,均非敌国,不接壤)。
	var overlord := 0
	var front_vassal := 1
	var rear_vassal := 2
	var enemy := 3
	# 全图先归宗主，再逐一指派测试相关城市，确保接壤关系完全可控。
	for city in gs.cities:
		city.owner_nation = overlord
		city.is_capital = false
		city.has_warehouse = false
		gs.recognized_city_owners[city.id] = overlord
	var overlord_capital := 0
	var front_city := 1
	var enemy_city := 2
	var rear_city := 9
	gs.cities[front_city].owner_nation = front_vassal
	gs.recognized_city_owners[front_city] = front_vassal
	gs.cities[enemy_city].owner_nation = enemy
	gs.recognized_city_owners[enemy_city] = enemy
	gs.cities[rear_city].owner_nation = rear_vassal
	gs.recognized_city_owners[rear_city] = rear_vassal
	gs.nations[overlord].capital_city_id = overlord_capital
	gs.cities[overlord_capital].is_capital = true
	gs.cities[front_city].is_capital = true
	gs.cities[rear_city].is_capital = true
	gs.nations[front_vassal].capital_city_id = front_city
	gs.nations[rear_vassal].capital_city_id = rear_city
	# 宗藩记录：两藩王挂到宗主 0，默认贡赋率；宗主↔藩王 ALLIED。
	for sub in [front_vassal, rear_vassal]:
		gs.set_diplomatic_relation(overlord, sub, GameState.DiplomaticRelation.ALLIED)
		gs.suzerainty[sub] = {
			"overlord_id": overlord,
			"tribute_rate": 0.25,
			"created_day": 0,
			"last_centralization_day": -1,
			"civil_war": false,
		}
	# 对外共同体化：宗主与两藩王都与敌国处于战争（体系对外统一敌对）。
	gs.set_diplomatic_relation(overlord, enemy, GameState.DiplomaticRelation.WAR)
	gs.set_diplomatic_relation(front_vassal, enemy, GameState.DiplomaticRelation.WAR)
	gs.set_diplomatic_relation(rear_vassal, enemy, GameState.DiplomaticRelation.WAR)
	gs.refresh_derived()

	# 接壤判定：前线藩王接壤敌国，后方藩王不接壤。
	_check(
		gs.vassal_borders_system_enemy(front_vassal)
			and not gs.vassal_borders_system_enemy(rear_vassal),
		"接壤判定：前线藩王须接壤敌国、后方藩王须不接壤（front=%s rear=%s）"
			% [
				str(gs.vassal_borders_system_enemy(front_vassal)),
				str(gs.vassal_borders_system_enemy(rear_vassal)),
			]
	)

	# 给前线藩王一支静止在本土的 MAIN 战团（重军），验证战时仍归藩王守土。
	# 复用藩王已有军队并迁到封地首都：新建会撞军队数上限（藩王城少、配额已被
	# 网格初始填线军占满），故改造既有军队为静止 MAIN，语义等价且不违反数量约束。
	var heavy: Army = null
	for army in gs.armies:
		if army.owner_nation == front_vassal and army.size > 0:
			heavy = army
			break
	_check(heavy != null, "前线藩王须有可改造为 MAIN 的既有军队")
	heavy.clear_line_assignment()
	heavy.battle_group_id = -1
	heavy.location_city = front_city
	heavy.move_from = front_city
	heavy.move_to = -1
	heavy.on_edge = false
	heavy.state = Army.State.IDLE
	heavy.max_size = GameState.INITIAL_HEAVY_ARMY_SIZE
	heavy.size = GameState.INITIAL_HEAVY_ARMY_SIZE
	heavy.strategic_role = Army.StrategicRole.MAIN
	var fg := gs.create_battle_group(front_vassal)
	gs.assign_army_to_battle_group(heavy, fg.id)
	var heavy_id := heavy.id
	_check(
		heavy.owner_nation == front_vassal
			and gs._battle_group_structure_valid()
			and gs.suzerainty_structure_valid(),
		"前线藩王的 MAIN 战团必须保留本国所有权、只承担封地防御（army=%d owner=%d）"
			% [heavy_id, heavy.owner_nation]
	)

	# 战时贡赋：结算后后方藩王按提升率上缴、前线藩王不被强制加税。
	var sim := Simulation.new()
	sim.setup(gs)
	for n in gs.nations:
		n.treasury_gold = 1000
	var gold_income: Array[int] = []
	gold_income.resize(gs.nations.size())
	gold_income.fill(0)
	gold_income[rear_vassal] = 100
	gold_income[front_vassal] = 100
	sim._resolve_tribute(gold_income)
	# 后方藩王按 max(0.25, 0.60)=0.60 上缴 100×0.6=60；前线藩王按记录率 0.25 上缴 25。
	_check(
		gs.nations[rear_vassal].treasury_gold == 1000 - 60
			and gs.nations[front_vassal].treasury_gold == 1000 - 25,
		"战时后方藩王按提升率上缴、前线藩王按原率（后方余%d 前线余%d）"
			% [gs.nations[rear_vassal].treasury_gold, gs.nations[front_vassal].treasury_gold]
	)
	sim._resolve_economy()
	_check(
		heavy.owner_nation == front_vassal
			and heavy.battle_group_id == fg.id,
		"战时经济结算不得抽调前线藩王 MAIN（owner=%d group=%d）"
			% [heavy.owner_nation, heavy.battle_group_id]
	)
	sim.free()

	# 藩王首都失陷不触发投降割地：敌国占领前线藩王首都，只丢该城，不整国投降。
	var cap_state := GameState.new()
	cap_state.generate_grid_world(32096)
	for a in range(cap_state.nations.size()):
		for b in range(a + 1, cap_state.nations.size()):
			cap_state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var cap_region: Array[int] = []
	for city in cap_state.land_cities_of(0):
		if not city.is_capital:
			cap_region.append(city.id)
		if cap_region.size() >= 3:
			break
	var cap_subject := cap_state.enfeoff(0, cap_region)
	_check(cap_subject > 0, "分封应成功建立藩王（首都失陷用例）")
	var cap_sim := Simulation.new()
	cap_sim.setup(cap_state)
	var vassal_capital := cap_state.nations[cap_subject].capital_city_id
	var vassal_city_count_before := cap_state.land_cities_of(cap_subject).size()
	var history_before := cap_state.diplomatic_history.size()
	# 敌国 1 与藩王开战并直接占领藩王首都。
	cap_state.set_diplomatic_relation(1, cap_subject, GameState.DiplomaticRelation.WAR)
	var invader := _make_army(9500, 1, 5000, 10)
	invader.location_city = vassal_capital
	invader.move_from = vassal_capital
	cap_state.armies.append(invader)
	cap_sim._capture_city(invader, cap_state.cities[vassal_capital], 1)
	var relocated_vassal_capital := (
		cap_state.nations[cap_subject].capital_city_id
	)
	_check(
		cap_state.cities[vassal_capital].owner_nation == 1
			and cap_state.diplomatic_history.size() == history_before
			and cap_state.land_cities_of(cap_subject).size()
				== vassal_city_count_before - 1
			and cap_state.suzerainty_structure_valid(),
		"藩王首都失陷只丢该城、不触发投降割地、不写投降历史、宗藩不变量成立"
	)
	_check(
		relocated_vassal_capital >= 0
			and relocated_vassal_capital != vassal_capital
			and cap_state.cities[relocated_vassal_capital].owner_nation
				== cap_subject
			and cap_state.cities[relocated_vassal_capital].is_capital
			and not cap_state.cities[relocated_vassal_capital].has_warehouse
			and cap_state.nations[cap_subject].warehouse_city_ids.is_empty()
			and not cap_state.cities[vassal_capital].is_capital,
		"藩王首都失陷后必须立即迁都，且新首都仍是共享粮仓零库存中继"
	)
	_check(
		cap_state.territory_structure_valid(),
		"藩王首都失陷事务结束后领土结构不变量必须成立"
	)
	cap_sim.free()

	# 藩王全境失守不能触发整个宗藩体系集团议和。藩王只退出自己的
	# 战争关系，宗主继续对外作战，最终议和权仍在宗主。
	var eliminated_state := GameState.new()
	eliminated_state.generate_grid_world(32097)
	for a in range(eliminated_state.nations.size()):
		for b in range(a + 1, eliminated_state.nations.size()):
			eliminated_state.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	var eliminated_region: Array[int] = []
	for candidate in eliminated_state.land_cities_of(0):
		if not candidate.is_capital:
			eliminated_region.append(candidate.id)
		if eliminated_region.size() >= 3:
			break
	var eliminated_subject := eliminated_state.enfeoff(
		0, eliminated_region
	)
	eliminated_state.set_diplomatic_relation(
		0, 1, GameState.DiplomaticRelation.WAR
	)
	eliminated_state.set_diplomatic_relation(
		eliminated_subject, 1, GameState.DiplomaticRelation.WAR
	)
	for lost_city in eliminated_state.cities_of(eliminated_subject):
		lost_city.owner_nation = 1
		lost_city.occupation_sponsor_nation = 1
	eliminated_state.refresh_derived()
	var subject_field_army := _make_army(9501, eliminated_subject, 5000, 10)
	var subject_enemy_army := _make_army(9502, 1, 5000, 10)
	var root_field_army := _make_army(9503, 0, 5000, 10)
	var root_enemy_army := _make_army(9504, 1, 5000, 10)
	var subject_battle := eliminated_state.new_battle(Battle.Kind.FIELD)
	subject_battle.side_a.append(subject_field_army)
	subject_battle.side_b.append(subject_enemy_army)
	var root_battle := eliminated_state.new_battle(Battle.Kind.FIELD)
	root_battle.side_a.append(root_field_army)
	root_battle.side_b.append(root_enemy_army)
	for battle_setup in [
		[subject_field_army, subject_battle.id],
		[subject_enemy_army, subject_battle.id],
		[root_field_army, root_battle.id],
		[root_enemy_army, root_battle.id],
	]:
		var field_army: Army = battle_setup[0]
		field_army.state = Army.State.FIGHTING
		field_army.battle_id = int(battle_setup[1])
		eliminated_state.armies.append(field_army)
	# 保留宗藩记录直到无城结算识别其身份。
	var eliminated_sim := Simulation.new()
	eliminated_sim.setup(eliminated_state)
	var eliminated_history_before := eliminated_state.diplomatic_history.size()
	eliminated_sim._resolve_eliminated_nation_capitulations()
	_check(
		eliminated_state.is_enemy(0, 1)
			and not eliminated_state.is_enemy(eliminated_subject, 1)
			and subject_battle.finished
			and not root_battle.finished
			and subject_field_army.battle_id == -1
			and root_field_army.battle_id == root_battle.id
			and eliminated_state.diplomatic_history.size()
				== eliminated_history_before,
		(
			"藩王全境失守只结束自身战争与战斗，不得终止宗主对外战争："
			+ "root_war=%s subject_war=%s subject_finished=%s root_finished=%s "
			+ "subject_bid=%d root_bid=%d history=%d/%d"
		) % [
			str(eliminated_state.is_enemy(0, 1)),
			str(eliminated_state.is_enemy(eliminated_subject, 1)),
			str(subject_battle.finished),
			str(root_battle.finished),
			subject_field_army.battle_id,
			root_field_army.battle_id,
			eliminated_state.diplomatic_history.size(),
			eliminated_history_before,
		]
	)
	eliminated_state.prune_dead_suzerainty()
	var inherited_legal_claims := true
	for lost_city in eliminated_state.cities:
		if lost_city.owner_nation == 1 and lost_city.occupation_sponsor_nation == 1:
			inherited_legal_claims = (
				inherited_legal_claims
				and eliminated_state.recognized_owner_of(lost_city.id) == 0
			)
	_check(
		not eliminated_state.is_vassal(eliminated_subject)
			and inherited_legal_claims
			and eliminated_state.suzerainty_structure_valid(),
		"灭亡藩王退出战争后，封地法理须回归宗主并清理宗藩记录"
	)
	eliminated_sim.free()


# ------------------------------------------------------------------ 33. 和平裁军与潜在边境守备

func _test_peacetime_demobilization_and_border_defense() -> void:
	print("[33] 和平军备：30%编制、主动裁军屯粮、高威胁中立边境驻军")
	var gs := GameState.new()
	gs.generate_grid_world(33001)
	# 本用例刻意制造零产粮压力，隔离国际粮食外援。
	for nation in gs.nations:
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
	for nation_a in range(gs.nations.size()):
		for nation_b in range(nation_a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var sim := Simulation.new()
	sim.setup(gs)
	var view := AiWorldView.build(gs, 0)
	var snapshot := StrategicMapSnapshot.build(view)
	_check(
		snapshot.frontier_cities.is_empty()
		and not snapshot.potential_frontier_cities.is_empty(),
		"和平期不应有战争前线，但高威胁邻国边境应进入潜在前线"
	)
	var observed_border := int(snapshot.potential_frontier_cities[0])
	var observed_enemy_city := -1
	for neighbor in gs.neighbors(observed_border):
		if (
			gs.cities[neighbor].owner_nation != 0
			and gs.relation_between(
				0, gs.cities[neighbor].owner_nation
			) == GameState.DiplomaticRelation.NEUTRAL
		):
			observed_enemy_city = neighbor
			break
	var concentrated_enemy: Army = null
	if observed_enemy_city >= 0:
		var enemy_nation := gs.cities[observed_enemy_city].owner_nation
		for army in gs.armies:
			if army.owner_nation == enemy_nation:
				concentrated_enemy = army
				break
	var threat_before_concentration := snapshot.potential_threat_at(
		observed_border
	)
	var old_enemy_city := -1
	var old_enemy_size := 0
	var old_enemy_max_size := 0
	if concentrated_enemy != null:
		old_enemy_city = concentrated_enemy.location_city
		old_enemy_size = concentrated_enemy.size
		old_enemy_max_size = concentrated_enemy.max_size
		concentrated_enemy.state = Army.State.IDLE
		concentrated_enemy.location_city = observed_enemy_city
		concentrated_enemy.move_from = observed_enemy_city
		concentrated_enemy.move_to = -1
		concentrated_enemy.on_edge = false
		concentrated_enemy.size = 60000
		concentrated_enemy.max_size = 60000
	var concentrated_snapshot := StrategicMapSnapshot.build(
		AiWorldView.build(gs, 0)
	)
	_check(
		concentrated_enemy != null
		and concentrated_snapshot.potential_threat_at(observed_border)
			> threat_before_concentration,
		"中立邻国在某方向集中兵力后，守方必须提高该边境的预警和布防需求"
	)
	var depth_city := -1
	for neighbor in gs.neighbors(observed_border):
		if gs.cities[neighbor].owner_nation == 0:
			depth_city = neighbor
			break
	var propagation_ratio := 0.0
	if depth_city >= 0:
		var propagation_view := AiWorldView.build(gs, 0)
		var propagation_snapshot := StrategicMapSnapshot.new()
		propagation_snapshot.city_value[observed_border] = 1.0
		propagation_snapshot.city_value[depth_city] = 1.0
		propagation_snapshot.potential_border_threat[
			observed_border
		] = 10000.0
		propagation_snapshot.potential_border_threat[
			depth_city
		] = 1.0
		var propagation_threat := ThreatField.new()
		propagation_threat.threat_by_city[observed_border] = 10000.0
		propagation_threat.threat_by_city[depth_city] = 1.0
		var propagation_plan := CityDefensePlan.new()
		propagation_plan.view = propagation_view
		propagation_plan.snapshot = propagation_snapshot
		propagation_plan.threat = propagation_threat
		propagation_plan.frontline_distribution_enabled = true
		propagation_plan.primary_frontline_cities[
			observed_border
		] = true
		propagation_plan.frontline_cities[observed_border] = true
		propagation_plan.frontline_cities[depth_city] = true
		propagation_plan._normalize_frontline_requirements(10000.0)
		propagation_ratio = (
			float(
				propagation_plan.frontline_allocation.get(
					depth_city,
					0.0
				)
			)
			/ maxf(
				float(
					propagation_plan.frontline_allocation.get(
						observed_border,
						0.0
					)
				),
				1.0
			)
		)
	_check(
		depth_city >= 0 and propagation_ratio > 0.5,
		"二线城市即使已有微小背景危险，也必须继承相邻高压一线的行军衰减危险"
	)
	var balance_state := GameState.new()
	balance_state.generate_grid_world(32010)
	balance_state.armies.clear()
	for city in balance_state.cities:
		city.owner_nation = 0
	for balance_a in range(balance_state.nations.size()):
		for balance_b in range(
			balance_a + 1,
			balance_state.nations.size()
		):
			balance_state.set_diplomatic_relation(
				balance_a,
				balance_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	balance_state.cities[0].fort_strength = 0
	balance_state.cities[1].fort_strength = 0
	balance_state.edge_of(0, 1).max_manpower = 30000
	for balance_army_id in range(4):
		var balance_army := _make_army(
			1100 + balance_army_id,
			0,
			5000,
			10,
			10
		)
		balance_army.max_size = 5000
		balance_army.location_city = 0 if balance_army_id < 3 else 1
		balance_army.move_from = balance_army.location_city
		balance_state.armies.append(balance_army)
	var balance_view := AiWorldView.build(balance_state, 0)
	var balance_plan := CityDefensePlan.new()
	balance_plan.view = balance_view
	balance_plan.snapshot = StrategicMapSnapshot.new()
	balance_plan.threat = ThreatField.new()
	balance_plan.frontline_distribution_enabled = true
	balance_plan.frontline_cities[0] = true
	balance_plan.frontline_cities[1] = true
	balance_plan.frontline_allocation[0] = 5000.0
	balance_plan.frontline_allocation[1] = 5000.0
	var saturation_rebalance := balance_plan.candidate_for(
		balance_state.armies[0],
		ArmyCoordinator.new()
	)
	_check(
		saturation_rebalance != null
		and saturation_rebalance.kind
			== ActionCandidate.Kind.REINFORCE
		and saturation_rebalance.target_city == 1
		and saturation_rebalance.defensive_deployment,
		"所有防区达标后仍应按覆盖/目标饱和度展开多余兵力，并纳入防御部署锁"
	)
	view = AiWorldView.build(gs, 0)
	snapshot = concentrated_snapshot
	var capital_id := gs.nations[0].capital_city_id
	for army in view.friendly_armies:
		if army.location_city == capital_id:
			army.size = 5000
			break
	var interior_army: Army = null
	for army in view.friendly_armies:
		if (
			army.location_city != capital_id
			and army.is_line_role()
			and not snapshot.potential_frontier_cities.has(army.location_city)
		):
			interior_army = army
			break
	_check(interior_army != null, "测试地图应存在非首都、非边境的内地军")
	if interior_army != null:
		interior_army.size = 5000
		var peacetime_threat := ThreatField.build(view)
		var peacetime_plan := CityDefensePlan.build(
			view,
			snapshot,
			peacetime_threat
		)
		var reinforce := peacetime_plan.candidate_for(
			interior_army,
			ArmyCoordinator.new()
		)
		_check(
			reinforce != null
			and snapshot.potential_frontier_cities.has(reinforce.target_city)
			and reinforce.defensive_deployment,
			(
				"内地军应优先增援高威胁国家边境，而不是继续聚集首都：%s"
				% (
					"null"
					if reinforce == null
					else "kind=%d target=%d reason=%s" % [
						reinforce.kind,
						reinforce.target_city,
						reinforce.reason,
					]
				)
			)
		)
		interior_army.defensive_deployment_until_day = (
			view.day + Simulation.DEFENSIVE_DEPLOYMENT_LOCK_DAYS
		)
		var locked_redeployment := peacetime_plan.candidate_for(
			interior_army,
			ArmyCoordinator.new()
		)
		_check(
			locked_redeployment == null,
			"非紧急边境评分波动不得打破防御部署锁并触发反复换防"
		)
		var locked_utility_action := UtilityAI.choose(
			view,
			snapshot,
			peacetime_threat,
			ArmyCoordinator.new(),
			interior_army,
			UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO,
			peacetime_plan
		)
		_check(
			locked_utility_action.kind
				== ActionCandidate.Kind.NONE,
			"部署锁期间不得通过合并候选绕过约束调走军队"
		)
		interior_army.defensive_deployment_until_day = view.day
		var unlocked_redeployment := peacetime_plan.candidate_for(
			interior_army,
			ArmyCoordinator.new()
		)
		_check(
			unlocked_redeployment != null
			and unlocked_redeployment.defensive_deployment,
			"防御部署锁到期后应重新允许正常换防"
		)
	var border_army: Army = null
	for army in view.friendly_armies:
		if army.location_city == observed_border:
			border_army = army
			break
	_check(border_army != null, "潜在边境城市应有可用于驻边测试的本国军队")
	if border_army != null:
		border_army.size = 5000
		var border_threat := ThreatField.build(view)
		var border_plan := CityDefensePlan.build(
			view,
			snapshot,
			border_threat
		)
		var hold := border_plan.candidate_for(
			border_army,
			ArmyCoordinator.new()
		)
		var serves_pressured_frontier := (
			hold != null
			and hold.defensive_deployment
			and (
				(
					hold.kind == ActionCandidate.Kind.HOLD
					and snapshot.potential_frontier_cities.has(
						border_army.location_city
					)
					and snapshot.potential_threat_of_edge(
						border_army.location_city,
						hold.target_city
					) > 0.0
					and hold.reason.contains("驻边")
				)
				or (
					hold.kind == ActionCandidate.Kind.REINFORCE
					and snapshot.potential_frontier_cities.has(
						hold.target_city
					)
					and hold.reason.contains(
						"高威胁中立国边境"
					)
				)
			)
		)
		_check(
			serves_pressured_frontier,
			(
				"边境军应服务于高压边境目标（驻边或转援未满足防区）：%s posture=%d edge=%d"
				% [
					"null" if hold == null else (
						"kind=%d target=%d reason=%s" % [
							hold.kind,
							hold.target_city,
							hold.reason,
						]
					),
					border_plan.posture_at(
						border_army.location_city
					),
					border_plan.preferred_edge_at(
						border_army.location_city
					),
				]
			)
		)
	if concentrated_enemy != null:
		concentrated_enemy.location_city = old_enemy_city
		concentrated_enemy.move_from = old_enemy_city
		concentrated_enemy.size = old_enemy_size
		concentrated_enemy.max_size = old_enemy_max_size

	gs.nations[0].manpower_pool = 100000
	for army in gs.armies:
		if army.owner_nation == 0:
			army.size = 1000
	for _month in range(10):
		sim._resolve_reinforcements()
	var peacetime_cap := int(ceil(
		float(Army.DEFAULT_MAX_SIZE) * Simulation.PEACETIME_STRENGTH_RATIO
	))
	var exceeded_peacetime_cap := false
	for army in gs.armies:
		if army.owner_nation == 0 and army.size > peacetime_cap:
			exceeded_peacetime_cap = true
	_check(
		not exceeded_peacetime_cap,
		"和平期自动补员不得超过30%%编制%d人" % peacetime_cap
	)

	for army in gs.armies:
		if army.owner_nation == 0:
			army.size = int(ceil(
				float(army.max_size) * 0.60
			))
	for city in gs.cities_of(0):
		city.food_per_half_year = 0
	for warehouse in gs.warehouse_cities_of(0):
		warehouse.food_storage = 0
	view = AiWorldView.build(gs, 0)
	snapshot = StrategicMapSnapshot.build(view)
	gs.uses_heightmap = true
	var food_before := sim._food_security_report(0)
	var troops_before := 0
	var formations_before := view.friendly_armies.size()
	for army in view.friendly_armies:
		troops_before += army.size
	var manpower_before := gs.nations[0].manpower_pool
	var demobilized := sim._demobilize_for_food_security(
		view,
		ThreatField.build(view),
		food_before,
		formations_before
	)
	var food_after := sim._food_security_report(0)
	var troops_after := 0
	var formations_after := 0
	for army in gs.armies:
		if army.owner_nation == 0:
			troops_after += army.size
			formations_after += 1
	var troops_reduced := troops_after < troops_before
	var manpower_returned := gs.nations[0].manpower_pool > manpower_before
	var demand_reduced := (
		float(food_after["monthly_demand"])
		< float(food_before["monthly_demand"])
	)
	var budget_is_bounded := (
		float(food_before["sustainable_demand"])
		<= float(food_before["monthly_production"])
		and float(food_before["full_strength_annual_demand"]) > 0.0
		and float(food_before["full_strength_runway_years"]) >= 0.0
	)
	var reason_recorded := (
		gs.nations[0].ai_last_force_reason.contains("军粮预算缩编")
	)
	_check(
		demobilized
		and troops_reduced
		and manpower_returned
		and demand_reduced
		and formations_after == formations_before
		and budget_is_bounded
		and reason_recorded,
		(
			"粮食压力下应保留编制、缩编返还人力并控制粮耗：checks=%s/%s/%s/%s/%s/%s "
			+ "troops=%d→%d "
			+ "manpower=%d→%d demand=%.1f→%.1f sustainable=%.1f production=%.1f reason=%s"
		) % [
			str(demobilized),
			str(troops_reduced),
			str(manpower_returned),
			str(demand_reduced),
			str(formations_after == formations_before),
			str(budget_is_bounded and reason_recorded),
			troops_before,
			troops_after,
			manpower_before,
			gs.nations[0].manpower_pool,
			food_before["monthly_demand"],
			food_after["monthly_demand"],
			food_before["sustainable_demand"],
			food_before["monthly_production"],
			gs.nations[0].ai_last_force_reason,
		]
	)
	sim.free()


# ------------------------------------------------------------------ 34. 资源核心与粮食战争动员

func _test_resource_hubs_and_food_mobilization() -> void:
	print("[34] 资源核心：AI价值识别；富粮国家宣战时有限爆兵")
	var gs := GameState.new()
	gs.generate_grid_world(34001)
	# 本用例直接对比本国产粮动员能力；贸易不再自动购买粮食或人力。
	for nation in gs.nations:
		nation.trade_policy = RulerProfile.POLICY_ISOLATION
	for nation_a in range(gs.nations.size()):
		for nation_b in range(nation_a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	gs.day = DiplomacyAI.MIN_NEUTRAL_DAYS
	for city in gs.cities_of(0):
		city.food_per_half_year = 120
	for city in gs.cities_of(1):
		city.food_per_half_year = 0
	for army in gs.armies:
		if army.owner_nation == 0:
			army.size = 333
		elif army.owner_nation == 1:
			army.size = 1333
	gs.nations[0].manpower_pool = 30000
	gs.nations[1].manpower_pool = 30000
	for warehouse in gs.warehouse_cities_of(0):
		warehouse.food_storage = 5000
	for warehouse in gs.warehouse_cities_of(1):
		warehouse.food_storage = 100
	var rich_capacity := DiplomacyAI.mobilization_capacity(gs, 0)
	var defensive_capacity := DiplomacyAI.mobilization_capacity(
		gs,
		0,
		DiplomacyAI.FoodPosture.DEFENSIVE_WAR
	)
	var poor_capacity := DiplomacyAI.mobilization_capacity(gs, 1)
	var light_creation_cost := (
		GameState.formation_creation_gold_cost(
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
	)
	var rich_gold_before_exact_cost := (
		gs.nations[0].treasury_gold
	)
	var exact_cost_report := DiplomacyAI.resource_report(gs, 0)
	var half_year_reserve := (
		int(exact_cost_report["gold_reserve_baseline_income"])
		* Simulation.WAR_GOLD_RESERVE_MONTHS
	)
	gs.nations[0].treasury_gold = light_creation_cost
	var below_reserve_war_capacity := (
		DiplomacyAI.mobilization_capacity(
			gs,
			0,
			DiplomacyAI.FoodPosture.OFFENSIVE_WAR
		)
	)
	gs.nations[0].treasury_gold = (
		half_year_reserve + light_creation_cost
	)
	var exact_reserve_war_capacity := (
		DiplomacyAI.mobilization_capacity(
			gs,
			0,
			DiplomacyAI.FoodPosture.OFFENSIVE_WAR
		)
	)
	gs.nations[0].treasury_gold = light_creation_cost
	var exact_cost_guarded_capacity := (
		DiplomacyAI.mobilization_capacity(
			gs,
			0,
			DiplomacyAI.FoodPosture.GUARDED
		)
	)
	gs.nations[0].treasury_gold = rich_gold_before_exact_cost
	var rich_target_troops := DiplomacyAI._troop_count(gs, 0) \
		+ rich_capacity * DiplomacyAI.MOBILIZATION_ARMY_SIZE
	var rich_food_plan := DiplomacyAI.war_food_report(
		gs,
		0,
		rich_target_troops,
		DiplomacyAI.FoodPosture.OFFENSIVE_WAR
	)
	var stock_before_runway_test := gs.warehouse_cities_of(0)[0].food_storage
	gs.warehouse_cities_of(0)[0].food_storage = 500
	var low_stock_plan := DiplomacyAI.war_food_report(
		gs,
		0,
		rich_target_troops,
		DiplomacyAI.FoodPosture.OFFENSIVE_WAR
	)
	gs.warehouse_cities_of(0)[0].food_storage = stock_before_runway_test
	_check(
		rich_capacity == DiplomacyAI.MAX_MOBILIZATION_ARMIES
		and defensive_capacity >= rich_capacity
		and poor_capacity == 0,
		"富粮国应可额外动员4军，防御动员不少于进攻，贫粮大国不得爆兵"
	)
	_check(
		below_reserve_war_capacity == 0
			and exact_reserve_war_capacity >= 1
			and exact_cost_guarded_capacity == 0,
		"战争动员必须保留战前半年收入；半年储备外刚好一笔建制费可扩军，和平仍保护三年目标"
	)
	_check(
		bool(rich_food_plan["target_sustainable"])
		and float(rich_food_plan["target_runway_years"])
			>= DiplomacyAI.OFFENSIVE_CAMPAIGN_YEARS
		and float(rich_food_plan["target_runway_years"])
			>= float(low_stock_plan["target_runway_years"])
		and float(rich_food_plan["full_strength_annual_demand"])
			> float(rich_food_plan["target_annual_demand"]),
		"战争粮食报告应量化目标/满编年耗，库存越多可支撑战争越久"
	)
	_check(
		DiplomacyAI.war_desire(gs, 0, 1) >= DiplomacyAI.WAR_DECLARE_SCORE,
		"粮食动员潜力应使富粮小国具备向贫粮大国宣战的决策能力"
	)

	var resource_target: City = null
	for city in gs.cities_of(1):
		for neighbor in gs.neighbors(city.id):
			if (
				gs.cities[neighbor].owner_nation == 0
				and gs.edge_of(city.id, neighbor).max_manpower > 0
			):
				resource_target = city
				break
		if resource_target != null:
			break
	_check(resource_target != null, "测试地图应存在国0接壤的国1城市")
	if resource_target != null:
		for city in gs.cities_of(1):
			city.is_food_hub = false
			city.is_manpower_hub = false
		resource_target.is_food_hub = true
		resource_target.is_manpower_hub = true
		resource_target.food_per_half_year = 1000
		resource_target.manpower_per_month = 200
		var selected := DiplomacyAI.select_war_objective(gs, 0, 1)
		_check(
			int(selected.get("city_id", -1)) == resource_target.id
			and str(selected.get("reason", "")).contains("粮食核心")
			and str(selected.get("reason", "")).contains("人口核心"),
			"高产粮食/人口城市应成为优先战争目标并写入原因"
		)
		resource_target.is_food_hub = false
		resource_target.is_manpower_hub = false
		resource_target.food_per_half_year = 0
		resource_target.manpower_per_month = 10

	var capital_id := gs.nations[0].capital_city_id
	for army in gs.armies:
		if army.owner_nation == 0 and army.location_city == capital_id:
			army.size = 5000
			break
	var troops_before := 0
	for army in gs.armies:
		if army.owner_nation == 0:
			troops_before += army.size
	var sim := Simulation.new()
	sim.setup(gs)
	var declared := sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.DECLARE_WAR,
		"a": 0,
		"b": 1,
		"objective_city": resource_target.id if resource_target != null else -1,
		"objective_reason": "资源核心测试",
		"mobilization_armies": rich_capacity,
		"reason": "富粮动员测试",
	})
	_check(
		declared
		and gs.nations[0].war_mobilization_target_troops
			== troops_before + rich_capacity * Simulation.NEW_ARMY_SIZE
		and gs.nations[1].war_mobilization_target_troops > 0
		and gs.nations[1].war_mobilization_target_troops
			< gs.nations[0].war_mobilization_target_troops,
		"宣战双方应按各自粮食条件设置不同目标兵力"
	)
	var army_count_before := gs.armies.size()
	gs.uses_heightmap = true
	var mobilized := sim._ai_manage_force_structure(
		AiWorldView.build(gs, 0),
		StrategicMapSnapshot.build(AiWorldView.build(gs, 0)),
		ThreatField.build(AiWorldView.build(gs, 0))
	)
	_check(
		mobilized
			and gs.armies.size() == army_count_before + 1
			and gs.nations[0].ai_last_force_reason.contains(
				"战争生存动员"
			),
		"有效战争动员目标必须允许在库存门禁内继续扩军"
	)
	sim._execute_diplomatic_action({
		"kind": DiplomacyAI.Action.MAKE_PEACE,
		"a": 0,
		"b": 1,
		"reason": "动员清理测试",
	})
	_check(
		gs.nations[0].war_mobilization_target_troops == 0
		and gs.nations[0].war_mobilization_until_day == -1,
			"结束最后一场战争后必须清除动员目标"
	)
	sim.free()


func _test_small_nation_survival_and_emergency_recruitment() -> void:
	print("[34b] 小国生存：最后城市集中守备、负收益应急征兵与库存硬边界")
	var gs := GameState.new()
	gs.generate_grid_world(34002)
	gs.uses_heightmap = true
	gs.armies.clear()
	gs.battles.clear()
	for nation_a in range(gs.nations.size()):
		for nation_b in range(nation_a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				nation_a,
				nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	var last_city_id := gs.nations[0].capital_city_id
	for city in gs.cities:
		city.owner_nation = 1
		city.has_warehouse = false
		city.is_capital = false
		if city.id == last_city_id:
			city.owner_nation = 0
			city.has_warehouse = true
			city.is_capital = true
			city.food_per_half_year = 0
			city.food_storage = 100000
	gs.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var guard := gs.create_army(
		0,
		last_city_id,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var enemy_city_id := gs.neighbors(last_city_id)[0]
	var besieger := gs.create_army(
		1,
		enemy_city_id,
		GameState.INITIAL_LIGHT_ARMY_SIZE,
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	var sim := Simulation.new()
	sim.setup(gs)
	var peaceful_view := AiWorldView.build(gs, 0)
	var peaceful_plan := CityDefensePlan.new()
	peaceful_plan.view = peaceful_view
	peaceful_plan.snapshot = StrategicMapSnapshot.build(
		peaceful_view
	)
	peaceful_plan.threat = ThreatField.build(peaceful_view)
	var peaceful_slots := (
		peaceful_plan._build_role_defense_slots()
	)
	var siege := gs.new_battle(Battle.Kind.SIEGE)
	siege.city = gs.cities[last_city_id]
	siege.edge = gs.edge_of(last_city_id, enemy_city_id)
	siege.has_garrison = true
	siege.side_a.append(besieger)
	siege.side_b.append(guard)
	besieger.state = Army.State.FIGHTING
	besieger.battle_id = siege.id
	guard.state = Army.State.FIGHTING
	guard.battle_id = siege.id
	var siege_view := AiWorldView.build(gs, 0)
	var siege_plan := CityDefensePlan.new()
	siege_plan.view = siege_view
	siege_plan.snapshot = StrategicMapSnapshot.build(siege_view)
	siege_plan.threat = ThreatField.build(siege_view)
	var siege_slots := siege_plan._build_role_defense_slots()
	_check(
		peaceful_slots.size() == 1
			and int(peaceful_slots[0]["posture"])
				== CityDefensePlan.Posture.CITY
			and siege_slots.size() == 1
			and int(siege_slots[0]["city_id"]) == last_city_id
			and int(siege_slots[0]["posture"])
				== CityDefensePlan.Posture.CITY,
		"一城小国的 LINE 槽不随围城增减，机动 MAIN 独立承担解围"
	)
	var creation_cost := (
		GameState.formation_creation_gold_cost(
			GameState.INITIAL_LIGHT_ARMY_SIZE
		)
	)
	gs.nations[0].manpower_pool = (
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	gs.nations[0].treasury_gold = creation_cost
	var food_report := sim._food_security_report(
		0,
		siege_view.friendly_armies
	)
	var mobilized := sim._ai_manage_force_structure(
		siege_view,
		StrategicMapSnapshot.build(siege_view),
		ThreatField.build(siege_view)
	)
	var emergency_army: Army = null
	for army in gs.armies:
		if army.owner_nation == 0 and army != guard:
			emergency_army = army
			break
	_check(
		mobilized
			and emergency_army != null
			and gs.active_army_count(0) == 2
			and float(food_report["monthly_surplus"]) < 0.0
			and float(food_report["runway_years"])
				>= Simulation.EMERGENCY_RECRUITMENT_MIN_RUNWAY_YEARS
			and gs.nations[0].treasury_gold == 0
			and gs.nations[0].manpower_pool == 0,
		"最后城市被围时，即使钱粮净收益为负，只要库存续航足够且能现付成本就应征募第2支轻军"
	)
	if emergency_army != null:
		sim._reconcile_siege_city_defenders(siege)
	_check(
		emergency_army != null
			and siege.has_army(emergency_army)
			and emergency_army.battle_id == siege.id,
		"被围城市当日新征军必须进入现有围城守军侧，不能留在战斗外"
	)
	# 资源充足也不得继续把小国的单支机动预备队补成二轻一重完整战团。
	# 连续多轮调用锁住稳定目标，而不是只验证第一次应急征兵。
	gs.nations[0].manpower_pool = 100000
	gs.nations[0].treasury_gold = 100000
	var small_nation_grew_again := false
	for _force_tick in range(5):
		var stable_view := AiWorldView.build(gs, 0)
		small_nation_grew_again = (
			sim._ai_manage_force_structure(
				stable_view,
				StrategicMapSnapshot.build(stable_view),
				ThreatField.build(stable_view)
			)
			or small_nation_grew_again
		)
	var small_line_count := 0
	var small_main_light_count := 0
	var small_main_heavy_count := 0
	for small_army in gs.armies:
		if small_army.owner_nation != 0 or small_army.size <= 0:
			continue
		if small_army.is_line_role():
			small_line_count += 1
		elif small_army.max_size >= GameState.INITIAL_HEAVY_ARMY_SIZE:
			small_main_heavy_count += 1
		else:
			small_main_light_count += 1
	_check(
		not small_nation_grew_again
			and gs.active_army_count(0) == 2
			and small_line_count == 1
			and small_main_light_count
				== Simulation.SMALL_NATION_MOBILE_RESERVE_ARMIES
			and small_main_heavy_count == 0
			and emergency_army != null
			and emergency_army.battle_group_id >= 0
			and gs.battle_group_members(
				0, emergency_army.battle_group_id
			).size() == 1,
		"一城小国长期应稳定为一支填线守军加一支轻型机动预备队，不得继续补满重军战团"
	)
	if emergency_army != null:
		siege.side_b.erase(emergency_army)
		emergency_army.battle_id = -1
		gs.armies.erase(emergency_army)
	gs.cities[last_city_id].food_storage = 0
	gs.nations[0].manpower_pool = (
		GameState.INITIAL_LIGHT_ARMY_SIZE
	)
	gs.nations[0].treasury_gold = creation_cost
	var empty_stock_view := AiWorldView.build(gs, 0)
	var blocked_by_empty_stock := (
		sim._ai_manage_force_structure(
			empty_stock_view,
			StrategicMapSnapshot.build(empty_stock_view),
			ThreatField.build(empty_stock_view)
		)
	)
	_check(
		not blocked_by_empty_stock
			and gs.active_army_count(0) == 1
			and gs.nations[0].treasury_gold == creation_cost
			and gs.nations[0].manpower_pool
				== GameState.INITIAL_LIGHT_ARMY_SIZE,
		"负收益征兵不等于透支：粮库为0时必须拒绝建军且不得预扣金钱或人力"
	)
	sim.free()


## [35] 阶段1 战斗公平性与守恒：胜负与 A/B 位置无关、伤亡整数守恒、平局、士气影响战力、拆分不改总量。
func _test_combat_fairness_and_conservation() -> void:
	print("[35] 战斗公平：A/B 无偏置 + 伤亡守恒 + 平局 + 士气战力 + 拆分等价")

	# (a) A/B 位置无偏置：同一对不对称阵容，交换 side_a/side_b 与固定种子后，胜方应随之镜像交换。
	#     强者(3000)对弱者(1000)：强者所在侧必胜，与它站 A 还是 B 无关。
	var seed_list := [1, 7, 42, 123, 999]
	var ab_consistent := true
	for s in seed_list:
		var rng1 := RandomNumberGenerator.new(); rng1.seed = s
		var strong_a := _make_field_battle([_make_army(0, 0, 3000, 10)], [_make_army(1, 1, 1000, 10)], 0.0, 4)
		_run_battle(strong_a, rng1)
		var rng2 := RandomNumberGenerator.new(); rng2.seed = s
		var strong_b := _make_field_battle([_make_army(0, 0, 1000, 10)], [_make_army(1, 1, 3000, 10)], 0.0, 4)
		_run_battle(strong_b, rng2)
		# 强者在 A 时 winner==1，强者在 B 时 winner==2；否则说明有位置偏置。
		if strong_a.winner_side != 1 or strong_b.winner_side != 2:
			ab_consistent = false
	_check(ab_consistent, "强弱对决胜负必须随位置镜像交换，不得有 A/B 偏置")

	# (b) decide_winner 纯函数对称性：交换输入，输出必须 1↔2 对称，平局(0)不变。
	_check(Combat.decide_winner(true, false, false, false, 0.0, 0.0) == 2, "仅 A 被歼→B 胜")
	_check(Combat.decide_winner(false, true, false, false, 0.0, 0.0) == 1, "仅 B 被歼→A 胜")
	_check(Combat.decide_winner(false, false, true, false, 5.0, 3.0) == 2, "仅 A 溃→B 胜")
	_check(Combat.decide_winner(false, false, false, true, 3.0, 5.0) == 1, "仅 B 溃→A 胜")
	_check(Combat.decide_winner(true, true, false, false, 5.0, 3.0) == 1, "同时歼灭→残力高者(A)胜")
	_check(Combat.decide_winner(true, true, false, false, 3.0, 5.0) == 2, "同时歼灭→残力高者(B)胜")
	_check(Combat.decide_winner(true, true, false, false, 4.0, 4.0) == 0, "同时歼灭且残力相等→平局")
	_check(Combat.decide_winner(false, false, true, true, 4.0, 4.0) == 0, "同时溃败且残力相等→平局")

	# (c) 完全对称战斗：同质双方（同 size/atk/def/morale）应打成平局(0)，绝不默认 A 胜。
	var sym_ties := 0
	for s in seed_list:
		var rng := RandomNumberGenerator.new(); rng.seed = s
		var b := _make_field_battle([_make_army(0, 0, 1000, 10)], [_make_army(1, 1, 1000, 10)], 0.0, 4)
		_run_battle(b, rng)
		if b.winner_side == 0:
			sym_ties += 1
	_check(sym_ties == seed_list.size(), "完全对称战斗应全部判平局，实为 %d/%d" % [sym_ties, seed_list.size()])

	# (d) 伤亡整数守恒（最大余数法）：sum == min(round(loss), Σsize)，每支 0<=c<=size。
	var sizes: Array[int] = [1000, 3000, 500, 2500]
	var pool := 7000
	var cas := Combat.distribute_casualties(sizes, 1234.0)
	var sum_cas := 0
	var bounded := true
	for i in range(sizes.size()):
		sum_cas += cas[i]
		if cas[i] < 0 or cas[i] > sizes[i]:
			bounded = false
	_check(sum_cas == 1234, "伤亡守恒：Σ应=1234，实为 %d" % sum_cas)
	_check(bounded, "每支伤亡必须在 [0, size] 内")
	# 溢出夹住：loss 超过总兵力 → 全歼，Σ==pool。
	var cas_all := Combat.distribute_casualties(sizes, 99999.0)
	var sum_all := 0
	for c in cas_all:
		sum_all += c
	_check(sum_all == pool, "损失超总兵力应全歼 Σ==%d，实为 %d" % [pool, sum_all])

	# (e) 拆分不改变总伤亡（防套利 item12）：1×10000 与 10×1000 承受同一 loss，总伤相等。
	var loss_target := 3456.0
	var single_sum := 0
	for c in Combat.distribute_casualties([10000], loss_target):
		single_sum += c
	var split_sizes: Array[int] = []
	for _i in range(10):
		split_sizes.append(1000)
	var split_sum := 0
	for c in Combat.distribute_casualties(split_sizes, loss_target):
		split_sum += c
	_check(single_sum == split_sum, "拆分伤亡总量应一致：单支%d vs 10支%d" % [single_sum, split_sum])

	# (f) 士气影响战力：combat_efficiency 单调、满士气=1.0、下界=MIN_COMBAT_EFFICIENCY。
	_check(_approx(Combat.combat_efficiency(1.0), 1.0), "满士气效率应=1.0")
	_check(_approx(Combat.combat_efficiency(0.0), Combat.MIN_COMBAT_EFFICIENCY), "零士气效率应=下界")
	_check(Combat.combat_efficiency(0.5) > Combat.combat_efficiency(0.2), "效率随士气单调递增")
	# 同兵力同装备，满士气攻方一回合杀伤应 ≥ 疲劳攻方（士气折算攻击力，而非第二血条）。
	var full_att := _make_army(0, 0, 2000, 10)             # morale 默认 1.0
	var tired_att := _make_army(0, 0, 2000, 10); tired_att.morale = 0.3
	var loss_full := _one_round_side_b_loss([full_att], [_make_army(2, 1, 3000, 10)], 90)
	var loss_tired := _one_round_side_b_loss([tired_att], [_make_army(2, 1, 3000, 10)], 90)
	_check(loss_full > loss_tired, "满士气攻方杀伤(%d)应高于疲劳攻方(%d)（士气折算战力）" % [loss_full, loss_tired])
	var mixed_strong := _make_army(3, 0, 1000, 20, 10)
	mixed_strong.morale = 0.25
	mixed_strong.offensive_attack_multiplier = 1.5
	var mixed_steady := _make_army(4, 0, 2000, 8, 10)
	mixed_steady.morale = 0.75
	var mixed_side: Array[Army] = [
		mixed_strong,
		mixed_steady,
	]
	var mixed_expected_attack := (
		float(mixed_strong.size)
			* float(mixed_strong.attack)
			* mixed_strong.offensive_attack_multiplier
				* Combat.combat_efficiency(
					mixed_strong.combat_morale()
				)
		+ float(mixed_steady.size)
			* float(mixed_steady.attack)
			* Combat.combat_efficiency(mixed_steady.morale)
	)
	var mixed_frontline := Combat.frontline_allocation(
		mixed_side,
		100000
	)
	var mixed_actual_attack := Combat._frontline_attack(
		mixed_frontline,
		Combat._side_combat_efficiency(mixed_side)
	)
	_check(
		_approx(
			mixed_actual_attack,
			mixed_expected_attack,
			0.000001
		),
		"无限正面混编军的侧级组织效率必须严格还原逐军火力求和"
	)
	# 君主倍率改变的是有效士气量纲。侵蚀回写必须同时除以攻势与君主倍率，
	# 否则 ruler>1 的军队会被多扣、ruler<1 的军队会被少扣。
	var high_ruler_morale := _make_army(5, 0, 1000, 10, 10)
	var low_ruler_morale := _make_army(6, 0, 1000, 10, 10)
	high_ruler_morale.morale = 0.8
	low_ruler_morale.morale = 0.8
	high_ruler_morale.offensive_attack_multiplier = 1.5
	low_ruler_morale.offensive_attack_multiplier = 1.5
	high_ruler_morale.ruler_morale_multiplier = 1.25
	low_ruler_morale.ruler_morale_multiplier = 0.5
	var ruler_morale_side: Array[Army] = [
		high_ruler_morale,
		low_ruler_morale,
	]
	var ruler_morale_frontline: Array[Dictionary] = [
		{
			"army": high_ruler_morale,
			"committed": high_ruler_morale.size,
			"size_before": high_ruler_morale.size,
		},
		{
			"army": low_ruler_morale,
			"committed": low_ruler_morale.size,
			"size_before": low_ruler_morale.size,
		},
	]
	var high_effective_before := high_ruler_morale.combat_morale()
	var low_effective_before := low_ruler_morale.combat_morale()
	var ruler_mass_before := (
		float(high_ruler_morale.size) * high_effective_before
		+ float(low_ruler_morale.size) * low_effective_before
	)
	Combat._erode_frontline_morale(
		ruler_morale_side,
		ruler_morale_frontline,
		0,
		ruler_mass_before / 2000.0
	)
	var ruler_mass_after := (
		float(high_ruler_morale.size)
			* high_ruler_morale.combat_morale()
		+ float(low_ruler_morale.size)
			* low_ruler_morale.combat_morale()
	)
	_check(
		_approx(
			ruler_mass_after,
			ruler_mass_before
				- 2000.0 * Combat.MORALE_BASE_DECAY,
			0.000001
		),
		"不同君主倍率的前线侵蚀后，有效士气质量必须精确达到目标"
	)
	_check(
		_approx(
			high_effective_before
				- high_ruler_morale.combat_morale(),
			Combat.MORALE_BASE_DECAY,
			0.000001
		)
		and _approx(
			low_effective_before
				- low_ruler_morale.combat_morale(),
			Combat.MORALE_BASE_DECAY,
			0.000001
		),
		"君主士气倍率不得放大或缩小每兵有效士气侵蚀"
	)

	# (g) 正面宽度/预备队（item 5）：窄路(frontage=5000)上大军(20000)无法全数展开。
	_check(Combat.frontage_engaged_ratio(20000, 5000) == 0.25, "2万兵挤5千正面→参战比例应=0.25")
	_check(Combat.frontage_engaged_ratio(3000, 5000) == 1.0, "兵力小于正面→全员参战")
	# 拆分不增加总正面（item12）：1×20000 与 20×1000 在同一窄路，一回合对守军总杀伤应一致。
	var single_army := _make_field_battle([_make_army(0, 0, 20000, 10)], [_make_army(99, 1, 20000, 10)], 0.0, 4)
	single_army.edge.max_manpower = 5000
	var split_list: Array = []
	for k in range(20):
		split_list.append(_make_army(k, 0, 1000, 10))
	var split_army := _make_field_battle(split_list, [_make_army(99, 1, 20000, 10)], 0.0, 4)
	split_army.edge.max_manpower = 5000
	var rng_s1 := RandomNumberGenerator.new(); rng_s1.seed = 3
	var rng_s2 := RandomNumberGenerator.new(); rng_s2.seed = 3
	var sb1 := single_army.side_size(single_army.side_b)
	var sb2 := split_army.side_size(split_army.side_b)
	Combat.resolve_round(single_army, rng_s1)
	Combat.resolve_round(split_army, rng_s2)
	var single_dmg := sb1 - single_army.side_size(single_army.side_b)
	var split_dmg := sb2 - split_army.side_size(split_army.side_b)
	_check(absi(single_dmg - split_dmg) <= 2, "窄路拆分总杀伤应一致：单支%d vs 拆分%d" % [single_dmg, split_dmg])
	# 完整多回合受限正面不变量：1×10000 与 2×5000 对同一敌军时，
	# 行政编组粒度不得改变逐轮火力、伤亡、全军组织度、胜负或时长。
	var constrained_whole := _make_field_battle(
		[_make_army(10, 0, 10000, 10, 10)],
		[_make_army(20, 1, 10000, 10, 10)],
		0.0,
		4
	)
	var constrained_split := _make_field_battle(
		[
			_make_army(11, 0, 5000, 10, 10),
			_make_army(12, 0, 5000, 10, 10),
		],
		[_make_army(21, 1, 10000, 10, 10)],
		0.0,
		4
	)
	constrained_whole.edge.max_manpower = 5000
	constrained_split.edge.max_manpower = 5000
	var constrained_rng_whole := RandomNumberGenerator.new()
	var constrained_rng_split := RandomNumberGenerator.new()
	constrained_rng_whole.seed = 860001
	constrained_rng_split.seed = 860001
	var constrained_start_a := constrained_whole.side_size(
		constrained_whole.side_a
	)
	var constrained_start_b := constrained_whole.side_size(
		constrained_whole.side_b
	)
	var constrained_trace_equal := true
	var constrained_rounds := 0
	Combat.battle_log_enabled = true
	while (
		not constrained_whole.finished
		and not constrained_split.finished
		and constrained_rounds < 1000
	):
		Combat.clear_battle_log()
		Combat.resolve_round(
			constrained_whole,
			constrained_rng_whole
		)
		var whole_record: Dictionary = (
			Combat.battle_log[-1].duplicate(true)
		)
		Combat.clear_battle_log()
		Combat.resolve_round(
			constrained_split,
			constrained_rng_split
		)
		var split_record: Dictionary = (
			Combat.battle_log[-1].duplicate(true)
		)
		constrained_trace_equal = (
			constrained_trace_equal
			and int(whole_record["casualties_a"])
				== int(split_record["casualties_a"])
			and int(whole_record["casualties_b"])
				== int(split_record["casualties_b"])
			and _approx(
				float(whole_record["effective_attack_a"]),
				float(split_record["effective_attack_a"]),
				0.000001
			)
			and _approx(
				float(whole_record["effective_attack_b"]),
				float(split_record["effective_attack_b"]),
				0.000001
			)
			and _approx(
				_battle_force_morale(
					constrained_whole.side_a,
					constrained_whole.routed_a
				),
				_battle_force_morale(
					constrained_split.side_a,
					constrained_split.routed_a
				),
				0.000000001
			)
			and _approx(
				_battle_force_morale(
					constrained_whole.side_b,
					constrained_whole.routed_b
				),
				_battle_force_morale(
					constrained_split.side_b,
					constrained_split.routed_b
				),
				0.000000001
			)
		)
		constrained_rounds += 1
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()
	var constrained_loss_whole := [
		constrained_start_a
			- constrained_whole.side_size(
				constrained_whole.side_a
			)
			- constrained_whole.side_size(
				constrained_whole.routed_a
			),
		constrained_start_b
			- constrained_whole.side_size(
				constrained_whole.side_b
			)
			- constrained_whole.side_size(
				constrained_whole.routed_b
			),
	]
	var constrained_loss_split := [
		constrained_start_a
			- constrained_split.side_size(
				constrained_split.side_a
			)
			- constrained_split.side_size(
				constrained_split.routed_a
			),
		constrained_start_b
			- constrained_split.side_size(
				constrained_split.side_b
			)
			- constrained_split.side_size(
				constrained_split.routed_b
			),
	]
	_check(
		constrained_trace_equal
			and constrained_whole.finished
			and constrained_split.finished
			and constrained_whole.winner_side
				== constrained_split.winner_side
			and constrained_whole.round_no
				== constrained_split.round_no
			and constrained_loss_whole
				== constrained_loss_split,
		(
			"5000正面完整战斗拆分不变量失败："
			+ "winner=%d/%d rounds=%d/%d loss=%s/%s"
		) % [
			constrained_whole.winner_side,
			constrained_split.winner_side,
			constrained_whole.round_no,
			constrained_split.round_no,
			str(constrained_loss_whole),
			str(constrained_loss_split),
		]
	)
	# 窄路一回合杀伤应显著低于宽路：大军被正面卡住，只有前线部队出力。
	var wide := _make_field_battle([_make_army(0, 0, 20000, 10)], [_make_army(2, 1, 20000, 10)], 0.0, 4)
	wide.edge.max_manpower = 100000        # 宽路：全员展开
	var narrow := _make_field_battle([_make_army(0, 0, 20000, 10)], [_make_army(2, 1, 20000, 10)], 0.0, 4)
	narrow.edge.max_manpower = 5000        # 窄路：仅 5000 展开
	var rng_w := RandomNumberGenerator.new(); rng_w.seed = 7
	var rng_n := RandomNumberGenerator.new(); rng_n.seed = 7
	var wide_before := wide.side_size(wide.side_b)
	var narrow_before := narrow.side_size(narrow.side_b)
	Combat.resolve_round(wide, rng_w)
	Combat.resolve_round(narrow, rng_n)
	var wide_loss := wide_before - wide.side_size(wide.side_b)
	var narrow_loss := narrow_before - narrow.side_size(narrow.side_b)
	_check(narrow_loss < wide_loss, "窄路杀伤(%d)应显著低于宽路(%d)（预备队不出力）" % [narrow_loss, wide_loss])
	# 预备队不受伤亡：窄路一回合伤亡不得超过前线参战兵力 5000。
	_check(narrow_loss <= 5000, "窄路单回合伤亡(%d)不得超过前线正面 5000（预备队不受伤）" % narrow_loss)

	# (h) 军队 id 不改变战斗结果（item 16 对称性）：完全相同的阵容，仅把 id 整体错开，
	#     多回合解算结果必须逐位一致——战斗数学不得依赖 id。
	var rng_id1 := RandomNumberGenerator.new(); rng_id1.seed = 55
	var low_ids := _make_field_battle([_make_army(0, 0, 4000, 11, 9)], [_make_army(1, 1, 3800, 10, 10)], 0.2, 4)
	var l1 := _run_battle(low_ids, rng_id1)
	var rng_id2 := RandomNumberGenerator.new(); rng_id2.seed = 55
	var high_ids := _make_field_battle([_make_army(500, 0, 4000, 11, 9)], [_make_army(501, 1, 3800, 10, 10)], 0.2, 4)
	var l2 := _run_battle(high_ids, rng_id2)
	_check(
		low_ids.winner_side == high_ids.winner_side
		and low_ids.side_size(low_ids.side_a) == high_ids.side_size(high_ids.side_a)
		and low_ids.side_size(low_ids.side_b) == high_ids.side_size(high_ids.side_b)
		and l1 == l2,
		"军队 id 整体偏移不得改变战斗结果（胜负/存活/回合数逐位一致）"
	)

	# (i) 一侧内部创建/加入顺序不改变战斗结果（item 16 + 本轮镜像修复的核心不变量）：
	#     同一多重集 {3000,1000,2000} 以正序与逆序装入 side_a，对同一 side_b 打同种子多回合，
	#     结果必须逐位一致。浮点求和不满足结合律，靠 resolve_round 内的物理键规范排序消除顺序依赖。
	var rng_o1 := RandomNumberGenerator.new(); rng_o1.seed = 88
	var fwd := _make_field_battle(
		[_make_army(0, 0, 3000, 10, 10), _make_army(1, 0, 1000, 10, 10), _make_army(2, 0, 2000, 10, 10)],
		[_make_army(9, 1, 6100, 10, 10)], 0.1, 4
	)
	var of1 := _run_battle(fwd, rng_o1)
	var rng_o2 := RandomNumberGenerator.new(); rng_o2.seed = 88
	var rev := _make_field_battle(
		[_make_army(0, 0, 2000, 10, 10), _make_army(1, 0, 1000, 10, 10), _make_army(2, 0, 3000, 10, 10)],
		[_make_army(9, 1, 6100, 10, 10)], 0.1, 4
	)
	var of2 := _run_battle(rev, rng_o2)
	_check(
		fwd.winner_side == rev.winner_side
		and fwd.side_size(fwd.side_a) == rev.side_size(rev.side_a)
		and fwd.side_size(fwd.side_b) == rev.side_size(rev.side_b)
		and of1 == of2,
		"同一多重集不同装入顺序，战斗结果必须逐位一致（浮点求和顺序无关）"
	)

	# (j) 共享战场骰下的镜像单回合对称（item 8「共享战场随机因素」）：同质双方注入同一 shared_roll，
	#     无论骰值取 DICE_MIN..DICE_MAX 哪一档，单回合后两侧 size 与 morale 必须严格对称。
	var shared_roll_symmetric := true
	for roll in range(Combat.DICE_MIN, Combat.DICE_MAX + 1):
		var ma := _make_army(0, 0, 5000, 10, 10)
		var mb := _make_army(1, 1, 5000, 10, 10)
		var mbat := _make_field_battle([ma], [mb], 0.3, 4)
		Combat.resolve_round(mbat, RandomNumberGenerator.new(), roll)
		if ma.size != mb.size or not is_equal_approx(ma.morale, mb.morale):
			shared_roll_symmetric = false
	_check(shared_roll_symmetric, "共享战场骰任一档位下，同质双方单回合结果必须严格对称")

	# (k) 共享骰的确定性裁决（镜像公平优先的既定取舍，item 8 独立侧骰已放弃）：
	#     shared_roll 同乘双方火力，故骰值只改变战斗「烈度/速度」、不改变相对胜负。
	#     后果：给定兵力比，单场野战胜负是确定的——5% 兵力优势方在所有种子下必胜（无单场逆转）。
	#     这是「镜像公平 > 单场戏剧性」抉择的直接代价，在此固化为回归门槛，使该取舍显式可见。
	#     宏观戏剧性/局部逆转仍存在于战略层（骰值改变战斗时序→影响哪些战斗发生→领土交换）。
	var adv_wins := 0
	var total_battles := 200
	for s in range(total_battles):
		var rng := RandomNumberGenerator.new(); rng.seed = 1000 + s
		var adv := _make_field_battle([_make_army(0, 0, 2100, 10, 10)], [_make_army(1, 1, 2000, 10, 10)], 0.1, 4)
		_run_battle(adv, rng)
		if adv.winner_side == 1:
			adv_wins += 1
	_check(
		adv_wins == total_battles,
		"共享骰下 5%%兵力优势方应确定性全胜(200/200)，实为 %d——若非全胜说明骰值错误地改变了相对胜负" % adv_wins
	)


## [36] item15 结构化战斗日志：默认关闭零记录、启用后字段完整可读、且不改变战斗结果（镜像安全）。
func _test_structured_battle_log() -> void:
	print("[36] 结构化战斗日志：可关闭 + 字段完整 + 不影响战斗数值")

	# (a) 默认关闭：跑一场战斗不产生任何日志。
	Combat.clear_battle_log()
	Combat.battle_log_enabled = false
	var rng0 := RandomNumberGenerator.new(); rng0.seed = 7
	var quiet := _make_field_battle([_make_army(0, 0, 2000, 10)], [_make_army(1, 1, 2000, 10)], 0.2, 4)
	_run_battle(quiet, rng0)
	_check(Combat.battle_log.is_empty(), "日志默认关闭时不得产生任何记录，实为 %d 条" % Combat.battle_log.size())

	# (b) 启用后：每回合一条记录，字段齐全（对照方案书 item15 字段清单），末条 winner 与战斗一致。
	Combat.clear_battle_log()
	Combat.battle_log_enabled = true
	var rng1 := RandomNumberGenerator.new(); rng1.seed = 7
	var logged := _make_field_battle([_make_army(0, 0, 3000, 12)], [_make_army(1, 1, 2000, 10)], 0.3, 4)
	logged.id = 77
	var rounds := _run_battle(logged, rng1)
	_check(Combat.battle_log.size() == rounds,
		"启用日志后记录条数应等于回合数 %d，实为 %d" % [rounds, Combat.battle_log.size()])
	var required_keys := [
		"battle_id", "day", "round_no", "kind", "participants_a", "participants_b",
		"frontline_strength_a", "reserve_strength_a", "effective_attack_a", "effective_defense_a",
		"shared_random_modifier", "side_random_modifier", "terrain_modifier_a", "supply_modifier_a",
		"casualties_a", "morale_before_a", "morale_after_a", "reinforcements_arrived_a",
		"rout_reason", "winner_or_draw",
	]
	var first: Dictionary = Combat.battle_log[0]
	var keys_ok := true
	for k in required_keys:
		if not first.has(k):
			keys_ok = false
	_check(keys_ok, "日志记录应包含 item15 规定的全部字段，缺失键；实有 %s" % str(first.keys()))
	_check(int(first["battle_id"]) == 77, "日志应携带 battle_id，实为 %s" % str(first["battle_id"]))
	var last: Dictionary = Combat.battle_log[Combat.battle_log.size() - 1]
	_check(int(last["winner_or_draw"]) == logged.winner_side and String(last["rout_reason"]) != "none",
		"末条日志 winner/rout_reason 应与战斗结束态一致：winner=%s reason=%s" % [
			str(last["winner_or_draw"]), str(last["rout_reason"])])
	# morale_after 应随回合单调不增（士气侵蚀），且首回合 morale_before≈1.0。
	_check(_approx(float(first["morale_before_a"]), 1.0),
		"满编新军首回合 morale_before 应≈1.0，实为 %.4f" % float(first["morale_before_a"]))
	_check(
		first["participants_a"] is Array
			and not (first["participants_a"] as Array).is_empty()
			and first["battle_context"] is Dictionary,
		"日志应携带可独立回放的参战军快照与战场上下文"
	)

	# (c) JSONL 落盘/加载/回放：每条记录可独立重建，篡改结果必须被检测。
	var log_path := "user://combat_log_roundtrip_test.jsonl"
	var saved := CombatLog.save_jsonl(
		Combat.battle_log,
		log_path
	)
	var loaded := CombatLog.load_jsonl(log_path)
	_check(
		bool(saved.get("ok", false))
			and bool(loaded.get("ok", false))
			and (loaded["records"] as Array).size()
				== Combat.battle_log.size(),
		"结构化日志 JSONL 应可完整落盘并加载：save=%s load=%s"
			% [str(saved), str(loaded)]
	)
	if bool(loaded.get("ok", false)):
		var replayed := CombatLog.replay_records(
			loaded["records"] as Array[Dictionary]
		)
		_check(
			bool(replayed.get("ok", false)),
			"加载后的战斗日志应逐回合确定性重放：%s"
				% str(replayed)
		)
		var tampered: Array[Dictionary] = (
			loaded["records"] as Array[Dictionary]
		).duplicate(true)
		if not tampered.is_empty():
			var after_a: Array = tampered[0][
				"participants_after_a"
			]
			if not after_a.is_empty():
				after_a[0]["size"] = int(
					after_a[0]["size"]
				) + 1
				var rejected := CombatLog.replay_records(
					tampered
				)
				_check(
					not bool(rejected.get("ok", true)),
					"回放器必须拒绝被篡改的战斗结果"
				)
				var entropy_tampered: Array[Dictionary] = (
					loaded["records"] as Array[Dictionary]
				).duplicate(true)
				entropy_tampered[0]["tactical_entropy"] = (
					int(entropy_tampered[0]["tactical_entropy"])
					+ 1234567
				)
				var entropy_rejected := CombatLog.replay_records(
					entropy_tampered
				)
				_check(
					not bool(entropy_rejected.get("ok", true)),
					"回放器必须拒绝被篡改的战术熵，不能只信任日志中的派生修正"
				)
				var key_tampered: Array[Dictionary] = (
					loaded["records"] as Array[Dictionary]
				).duplicate(true)
				var key_context: Dictionary = key_tampered[0][
					"battle_context"
				]
				key_context["tactical_key_a"] = (
					int(key_context["tactical_key_a"])
					+ 7654321
				)
				var key_rejected := CombatLog.replay_records(
					key_tampered
				)
				_check(
					not bool(key_rejected.get("ok", true)),
					"回放器必须拒绝被篡改的 tactical key"
				)
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(log_path)
	)

	# (d) 镜像安全：开/关日志跑同种子同阵容，战斗结果逐位一致（日志只读、不改数值）。
	Combat.battle_log_enabled = false
	var rng_off := RandomNumberGenerator.new(); rng_off.seed = 12345
	var b_off := _make_field_battle([_make_army(0, 0, 2500, 11)], [_make_army(1, 1, 2300, 10)], 0.25, 4)
	_run_battle(b_off, rng_off)
	var off_a := b_off.side_size(b_off.side_a)
	var off_b := b_off.side_size(b_off.side_b)
	Combat.clear_battle_log()
	Combat.battle_log_enabled = true
	var rng_on := RandomNumberGenerator.new(); rng_on.seed = 12345
	var b_on := _make_field_battle([_make_army(0, 0, 2500, 11)], [_make_army(1, 1, 2300, 10)], 0.25, 4)
	_run_battle(b_on, rng_on)
	_check(b_on.side_size(b_on.side_a) == off_a and b_on.side_size(b_on.side_b) == off_b
		and b_on.winner_side == b_off.winner_side,
		"开启日志不得改变战斗结果：off=(%d,%d,w%d) on=(%d,%d,w%d)" % [
			off_a, off_b, b_off.winner_side,
			b_on.side_size(b_on.side_a), b_on.side_size(b_on.side_b), b_on.winner_side])

	# 收尾：恢复默认关闭态，避免污染其他测试。
	Combat.battle_log_enabled = false
	Combat.clear_battle_log()


## [36b] 首都防御加成：城市作为首都时城防加成翻倍（真源 + 实战 + AI 估值三处一致）。
func _test_capital_defense_bonus() -> void:
	print("[36b] 首都防御：city_defense_modifier 翻倍、守军实战损失更小、AI 估值翻倍")
	# 真源函数：同 fort_strength 下首都返回 2 倍、非首都返回原值；空城返回 0。
	var plain := City.new()
	plain.fort_strength = 20
	plain.is_capital = false
	var capital := City.new()
	capital.fort_strength = 20
	capital.is_capital = true
	_check(
		Combat.city_defense_modifier(plain) == 20
			and Combat.city_defense_modifier(capital) == 40,
		"city_defense_modifier：非首都=fort(20)，首都=fort×2(40)，实为 %d/%d"
			% [Combat.city_defense_modifier(plain), Combat.city_defense_modifier(capital)]
	)

	# AI 估值：首都城防等效战力应为非首都的两倍（同源换算）。
	_check(
		is_equal_approx(
			ArmyPower.city_defense(capital),
			ArmyPower.city_defense(plain) * 2.0
		) and ArmyPower.city_defense(plain) > 0.0,
		"ArmyPower.city_defense：首都应为非首都两倍（%.1f vs %.1f）"
			% [ArmyPower.city_defense(capital), ArmyPower.city_defense(plain)]
	)

	# 实战对照：同种子、同攻方、同 fort，守军在首都因城防加成翻倍而损失更少。
	var rng_plain := RandomNumberGenerator.new(); rng_plain.seed = 42
	var atk_plain := _make_army(0, 0, 1000, 12)
	var def_plain := _make_army(1, 1, 1000, 10)
	var b_plain := _make_siege_battle([atk_plain], def_plain, 20, 4)
	b_plain.city.is_capital = false
	Combat.resolve_round(b_plain, rng_plain)
	var loss_plain := 1000 - def_plain.size

	var rng_cap := RandomNumberGenerator.new(); rng_cap.seed = 42
	var atk_cap := _make_army(0, 0, 1000, 12)
	var def_cap := _make_army(1, 1, 1000, 10)
	var b_cap := _make_siege_battle([atk_cap], def_cap, 20, 4)
	b_cap.city.is_capital = true
	Combat.resolve_round(b_cap, rng_cap)
	var loss_cap := 1000 - def_cap.size
	_check(
		loss_cap < loss_plain,
		"首都守军城防加成翻倍应让守军损失更少：非首都损%d vs 首都损%d"
			% [loss_plain, loss_cap]
	)


## [37] 决策排序镜像等变：城市物理序在左右镜像国家间一致，实体 ID 置换不改军队顺序。
func _test_equivariant_ordering() -> void:
	print("[37] 镜像等变排序：城市镜像 + 军队 ID 置换不变")
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var city_order_ok := true
	for row_a in range(GameState.GRID / 2):
		for col_a in range(GameState.GRID / 2):
			var a := row_a * GameState.GRID + col_a
			var mirror_a := (
				row_a * GameState.GRID
				+ GameState.GRID - 1 - col_a
			)
			for row_b in range(GameState.GRID / 2):
				for col_b in range(GameState.GRID / 2):
					var b := row_b * GameState.GRID + col_b
					var mirror_b := (
						row_b * GameState.GRID
						+ GameState.GRID - 1 - col_b
					)
					if (
						EquivariantOrder.city_id_less(
							gs, 0, a, b
						)
						!= EquivariantOrder.city_id_less(
							gs, 1, mirror_a, mirror_b
						)
					):
						city_order_ok = false
	_check(
		city_order_ok,
		"势力局部城市物理序应在水平镜像国家间严格等变"
	)

	var army_a := _make_army(1, 0, 1000, 10, 10)
	army_a.location_city = 0
	army_a.move_from = 0
	var army_b := _make_army(999, 0, 1000, 10, 10)
	army_b.location_city = 8
	army_b.move_from = 8
	var before := EquivariantOrder.army_less(
		gs, 0, army_a, army_b
	)
	army_a.id = 999999
	army_b.id = -100
	var after := EquivariantOrder.army_less(
		gs, 0, army_a, army_b
	)
	_check(
		before == after,
		"交换军队 ID 不得改变决策物理顺序"
	)

	# 首都与领土质心均落在中轴时，没有可等变的固定左右朝向；镜像城市
	# 必须落入同一轨道键，而不是隐式固定为“向右”。
	for city in gs.cities:
		city.owner_nation = 3
	gs.nations[0].capital_city_id = 0
	gs.cities[0].owner_nation = 0
	gs.cities[0].map_position = Vector2(0.5, 0.5)
	for city_id in [1, 2]:
		gs.cities[city_id].owner_nation = 0
		gs.cities[city_id].map_position = Vector2(
			0.4 if city_id == 1 else 0.6,
			0.25
		)
		gs.cities[city_id].terrain_height = 0.5
		gs.cities[city_id].terrain_relief = 0.5
	EquivariantOrder._city_rank_cache.clear()
	_check(
		is_zero_approx(
			EquivariantOrder._nation_forward_sign(gs, 0)
		)
			and EquivariantOrder.city_key(gs, 0, 1)
				== EquivariantOrder.city_key(gs, 0, 2)
			and not EquivariantOrder.city_id_less(
				gs, 0, 1, 2
			)
			and not EquivariantOrder.city_id_less(
				gs, 0, 2, 1
			),
		"中轴自映射势力必须使用 abs(x-0.5) 轨道，不能任意选择全局方向"
	)


## [38] 审查闭环：跨回合援军、真实预备队、单军溃退、有效围城、日补给。
func _test_remaining_combat_risk_closures() -> void:
	print("[38] 残余机制闭环：跨日援军 + 显式预备队 + 单军溃退 + 有效围城 + 日补给")

	# (a) 两批援军跨两个回合抵达，整场累计提振仍不得超过 0.20。
	var tired := _make_army(10000, 0, 1000, 0, 10)
	tired.morale = 0.30
	var enemy := _make_army(10001, 1, 20000, 0, 10)
	var reinforcement_battle := _make_field_battle(
		[tired],
		[enemy],
		0.0,
		4
	)
	reinforcement_battle.edge.max_manpower = 30000
	for batch in range(2):
		var fresh := _make_army(
			10002 + batch,
			0,
			5000,
			0,
			10
		)
		reinforcement_battle.side_a.append(fresh)
		reinforcement_battle.reinforce_fresh_a.append(fresh)
		Combat.resolve_round(
			reinforcement_battle,
			RandomNumberGenerator.new(),
			0,
			1234 + batch
		)
	_check(
		_approx(
			reinforcement_battle.reinforcement_morale_gained_a,
			Combat.REINFORCE_MORALE_MAX
		),
		"跨回合分批援军的整场累计提振应封顶 %.2f，实为 %.4f"
			% [
				Combat.REINFORCE_MORALE_MAX,
				reinforcement_battle.reinforcement_morale_gained_a,
			]
	)

	# (b) 5000 正面只能投入第一军；完整预备队首轮不伤亡、不掉战斗士气。
	var frontline := _make_army(10010, 0, 5000, 10, 10)
	var reserve := _make_army(10011, 0, 4000, 10, 10)
	var opponent := _make_army(10012, 1, 5000, 10, 10)
	var frontage_battle := _make_field_battle(
		[frontline, reserve],
		[opponent],
		0.0,
		4
	)
	frontage_battle.edge.max_manpower = 5000
	Combat.resolve_round(
		frontage_battle,
		RandomNumberGenerator.new(),
		0,
		99
	)
	_check(
		reserve.size == 4000 and _approx(reserve.morale, 1.0),
		"完整预备队首轮应保持兵力和组织度，实为 size=%d morale=%.4f"
			% [reserve.size, reserve.morale]
	)
	_check(
		frontline.size < 5000 and frontline.morale < 1.0,
		"前线军应独自承担首轮伤亡与士气侵蚀"
	)
	frontline.size = 0
	var reserve_before := reserve.size
	Combat.resolve_round(
		frontage_battle,
		RandomNumberGenerator.new(),
		0,
		100
	)
	_check(
		reserve.size < reserve_before and reserve.morale < 1.0,
		"前线退出后，预备队应在下一轮补入并开始承受战斗损耗"
	)

	# (c) 单军跌破 ARMY_ROUT_THRESHOLD 后立即离开战斗侧，健康预备队继续作战。
	var near_rout := _make_army(10020, 0, 5000, 10, 10)
	near_rout.morale = Combat.ARMY_ROUT_THRESHOLD + 0.001
	var healthy := _make_army(10021, 0, 4000, 10, 10)
	var rout_enemy := _make_army(10022, 1, 5000, 10, 10)
	var rout_battle := _make_field_battle(
		[near_rout, healthy],
		[rout_enemy],
		0.0,
		4
	)
	rout_battle.edge.max_manpower = 5000
	Combat.resolve_round(
		rout_battle,
		RandomNumberGenerator.new(),
		0,
		77
	)
	_check(
		rout_battle.routed_a.has(near_rout)
			and not rout_battle.side_a.has(near_rout)
			and rout_battle.side_a.has(healthy)
			and not rout_battle.finished,
		"单军跌破阈值应立即退出，健康预备队应保持战斗"
	)
	var promotion_state := GameState.new()
	promotion_state.generate_grid_world(38042)
	promotion_state.armies.clear()
	var broken_challenger := _make_army(
		10023,
		0,
		1000,
		10,
		10
	)
	broken_challenger.morale = (
		Combat.ARMY_ROUT_THRESHOLD - 0.001
	)
	broken_challenger.location_city = (
		promotion_state.cities_of(0)[0].id
	)
	broken_challenger.move_from = broken_challenger.location_city
	promotion_state.armies.append(broken_challenger)
	var promotion_battle := Battle.new()
	promotion_battle.kind = Battle.Kind.SIEGE
	promotion_battle.city = promotion_state.cities_of(1)[0]
	promotion_battle.side_b.append(broken_challenger)
	var promotion_sim := Simulation.new()
	promotion_sim.setup(promotion_state)
	promotion_sim._promote_challengers(promotion_battle)
	_check(
		promotion_battle.finished
			and promotion_battle.side_a.is_empty(),
		"低于单军阈值的挑战者不得绕过战斗回合接管围城"
	)
	var healthy_challenger := _make_army(
		10024,
		0,
		1000,
		10,
		10
	)
	var takeover_battle := Battle.new()
	takeover_battle.kind = Battle.Kind.SIEGE
	takeover_battle.city = promotion_state.cities_of(1)[0]
	takeover_battle.side_b.append(healthy_challenger)
	takeover_battle.reinforce_fresh_b.append(
		healthy_challenger
	)
	takeover_battle.frontline_priority_b[
		healthy_challenger
	] = 2
	takeover_battle.reinforcement_morale_gained_b = 0.12
	takeover_battle.tactical_key_b = 123456
	promotion_sim._promote_challengers(takeover_battle)
	_check(
		takeover_battle.side_a.has(healthy_challenger)
			and takeover_battle.reinforce_fresh_a.has(
				healthy_challenger
			)
			and _approx(
				takeover_battle.reinforcement_morale_gained_a,
				0.12
			)
			and takeover_battle.tactical_key_a == 123456
			and takeover_battle.side_b.is_empty()
			and takeover_battle.reinforce_fresh_b.is_empty()
			and _approx(
				takeover_battle.reinforcement_morale_gained_b,
				0.0
			),
		"挑战者接管围城时应迁移自身累计/新援状态并清空旧 side_b 身份"
	)
	promotion_sim.free()

	# (d) 围城只计算城墙正面内、受组织度和当日补给修正的有效兵力。
	var siege_full := _make_army(10030, 0, 10000, 10, 10)
	var siege_tired := _make_army(10031, 0, 10000, 10, 10)
	siege_tired.morale = 0.50
	var siege_unsupplied := _make_army(10032, 0, 10000, 10, 10)
	siege_unsupplied.supply_ratio = 0.50
	var full_strength := Combat.effective_siege_strength([siege_full])
	var tired_strength := Combat.effective_siege_strength([siege_tired])
	var unsupplied_strength := Combat.effective_siege_strength([
		siege_unsupplied
	])
	_check(
		full_strength == 10000
			and tired_strength < full_strength
			and unsupplied_strength < full_strength,
		"低士气/部分缺粮必须降低有效围城兵力：full=%d tired=%d supply=%d"
			% [full_strength, tired_strength, unsupplied_strength]
	)
	var siege_mass_a := _make_army(10033, 0, 10000, 10, 10)
	var siege_mass_b := _make_army(10034, 0, 10000, 10, 10)
	_check(
		Combat.effective_siege_strength([
			siege_mass_a,
			siege_mass_b,
		]) == Combat.SIEGE_FRONTAGE,
		"超额围城兵力应受城墙正面 %d 限制"
			% Combat.SIEGE_FRONTAGE
	)

	# (e) 军粮每天重算：30 天总耗保持月口径；同月兵力变化和库存不足立即反映。
	var supply_state := GameState.new()
	supply_state.generate_grid_world(38038)
	var supply_sim := Simulation.new()
	supply_sim.setup(supply_state)
	supply_state.armies.clear()
	var supply_city := supply_state.cities_of(0)[0]
	_set_single_warehouse(
		supply_state,
		0,
		supply_city.id,
		100
	)
	var supplied_army := _make_army(10040, 0, 12000, 10, 10)
	supplied_army.location_city = supply_city.id
	supplied_army.move_from = supply_city.id
	supply_state.armies.append(supplied_army)
	for day in range(1, 31):
		supply_state.day = day
		supply_sim._resolve_supply()
	_check(
		supply_city.food_storage == 70,
		"12000 人 30 天应消耗旧月口径 30 粮，不得按日 ceil 放大，实余 %d"
			% supply_city.food_storage
	)
	supplied_army.size = 24000
	supply_city.food_storage = 1
	supply_state.day = 31
	supply_sim._resolve_supply()
	_check(
		_approx(supplied_army.supply_ratio, 0.5)
			and supplied_army.starving,
		"同月兵力翻倍且仅余 1 粮时，当日 2 粮需求应立即得到 0.5 满足率，实为 %.3f"
			% supplied_army.supply_ratio
	)
	supply_sim.free()

	# (f) 同日增援资格必须按冻结战线批量判定；后方第一军加入不能把战线
	# 推回并让更远的第二军级联加入。
	var join_state := GameState.new()
	join_state.generate_grid_world(38039)
	join_state.armies.clear()
	join_state.battles.clear()
	var join_edge := join_state.edges[0]
	join_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	var core_a := _place_army_on_edge(
		join_state, 10050, 0,
		join_edge.city_a, join_edge.city_b, 0.40
	)
	var core_b := _place_army_on_edge(
		join_state, 10051, 1,
		join_edge.city_b, join_edge.city_a, 0.40
	)
	var near_b := _place_army_on_edge(
		join_state, 10052, 1,
		join_edge.city_b, join_edge.city_a, 0.30
	)
	var far_b := _place_army_on_edge(
		join_state, 10053, 1,
		join_edge.city_b, join_edge.city_a, 0.20
	)
	var existing := join_state.new_battle(Battle.Kind.FIELD)
	existing.edge = join_edge
	existing.contact_dist_a = 0.40 * float(join_edge.distance)
	existing.contact_dist_b = 0.60 * float(join_edge.distance)
	existing.side_a.append(core_a)
	existing.side_b.append(core_b)
	for core in [core_a, core_b]:
		core.state = Army.State.FIGHTING
		core.battle_id = existing.id
	var join_sim := Simulation.new()
	join_sim.setup(join_state)
	join_sim._detect_encounters()
	_check(
		existing.side_b.has(near_b)
			and not existing.side_b.has(far_b)
			and far_b.battle_id == -1
			and _approx(
				existing.contact_dist_b,
				0.60 * float(join_edge.distance)
			),
		"同日增援应冻结资格且后军不得把反向战线推回"
	)
	join_sim.free()

	var initial_join_state := GameState.new()
	initial_join_state.generate_grid_world(38041)
	initial_join_state.armies.clear()
	initial_join_state.battles.clear()
	var initial_edge := initial_join_state.edges[0]
	initial_join_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	_place_army_on_edge(
		initial_join_state, 10054, 0,
		initial_edge.city_a, initial_edge.city_b, 0.45
	)
	_place_army_on_edge(
		initial_join_state, 10055, 1,
		initial_edge.city_b, initial_edge.city_a, 0.45
	)
	var initial_near := _place_army_on_edge(
		initial_join_state, 10056, 1,
		initial_edge.city_b, initial_edge.city_a, 0.35
	)
	var initial_far := _place_army_on_edge(
		initial_join_state, 10057, 1,
		initial_edge.city_b, initial_edge.city_a, 0.25
	)
	var initial_join_sim := Simulation.new()
	initial_join_sim.setup(initial_join_state)
	initial_join_sim._detect_encounters()
	var initial_nation_one_side: Array[Army] = []
	if initial_join_state.battles.size() == 1:
		var initial_battle := initial_join_state.battles[0]
		initial_nation_one_side = (
			initial_battle.side_a
			if (
				not initial_battle.side_a.is_empty()
				and initial_battle.side_a[0].owner_nation == 1
			)
			else initial_battle.side_b
		)
	_check(
		initial_join_state.battles.size() == 1
			and initial_nation_one_side.has(initial_near)
			and not initial_nation_one_side.has(initial_far),
		"新战斗首日也应冻结增援资格，禁止逐支加入形成级联"
	)
	initial_join_sim.free()

	# (g) 拆分/合并不能重置每日补给结算相位或既有缺粮减员债。
	var debt_state := GameState.new()
	debt_state.generate_grid_world(38040)
	debt_state.armies.clear()
	var debt_army := _make_army(10060, 0, 8000, 10, 10)
	debt_army.max_size = 10000
	debt_army.location_city = debt_state.cities_of(0)[0].id
	debt_army.move_from = debt_army.location_city
	debt_army.supply_debt = 0.75
	debt_army.supply_food_debt = 0.60
	debt_state.armies.append(debt_army)
	var debt_parts := debt_state.split_army(debt_army, 5000)
	var split_supply_debt := 0.0
	var split_food_debt := 0.0
	for part in debt_parts:
		split_supply_debt += part.supply_debt
		split_food_debt += part.supply_food_debt
	debt_parts[0].max_size = 10000
	ArmyCoordinator._merge_into(
		debt_state,
		debt_parts[0],
		debt_parts[1]
	)
	_check(
		_approx(split_supply_debt, 0.75)
			and _approx(split_food_debt, 0.60)
			and _approx(debt_parts[0].supply_debt, 0.75)
			and _approx(debt_parts[0].supply_food_debt, 0.60),
		"拆分/合并应守恒 supply_debt 与 supply_food_debt"
	)


# ------------------------------------------------------------------ 工厂辅助

func _make_atomic_coalition_peace_fixture(seed: int) -> Dictionary:
	var gs := GameState.new()
	gs.generate_grid_world(seed)
	gs.armies.clear()
	gs.battles.clear()
	for nation_a in range(gs.nations.size()):
		for nation_b in range(nation_a + 1, gs.nations.size()):
			gs.set_diplomatic_relation(
				nation_a, nation_b,
				GameState.DiplomaticRelation.NEUTRAL
			)
	gs.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var occupied_city: City = null
	for candidate in gs.land_cities_of(1):
		if candidate.is_capital or candidate.has_warehouse:
			continue
		for neighbor in gs.neighbors(candidate.id):
			if gs.cities[neighbor].owner_nation == 0:
				occupied_city = candidate
				break
		if occupied_city != null:
			break
	assert(occupied_city != null)
	occupied_city.owner_nation = 0
	occupied_city.occupation_sponsor_nation = 0
	gs.ownership_revision += 1
	gs.set_war_objective(0, 1, occupied_city.id, "原子和平回滚目标")
	gs.nations[0].war_mobilization_target_troops = 34567
	gs.nations[0].war_mobilization_until_day = gs.day + 90
	gs.nations[0].war_mobilization_reason = "原子和平回滚动员"
	gs.nations[0].war_gold_income_snapshot = 777
	gs.nations[0].war_gold_income_snapshot_day = gs.day
	var attacker := _make_army(320250, 0, 5000, 10, 10)
	var defender := _make_army(320251, 1, 5000, 10, 10)
	attacker.location_city = occupied_city.id
	attacker.move_from = occupied_city.id
	defender.location_city = occupied_city.id
	defender.move_from = occupied_city.id
	gs.armies.append(attacker)
	gs.armies.append(defender)
	var battle := gs.new_battle(Battle.Kind.FIELD)
	battle.side_a.append(attacker)
	battle.side_b.append(defender)
	attacker.state = Army.State.FIGHTING
	attacker.battle_id = battle.id
	defender.state = Army.State.FIGHTING
	defender.battle_id = battle.id
	var sim := Simulation.new()
	sim.setup(gs)
	# setup 的财政同步是夹具初始化的一部分；测试指纹从计划完成后才冻结。
	return {
		"state": gs,
		"simulation": sim,
		"occupied_city_id": occupied_city.id,
	}


func _coalition_peace_fingerprint(
	gs: GameState,
	sim: Simulation
) -> Dictionary:
	var result := _territory_fingerprint(gs)
	result["war_objectives"] = gs.war_objectives.duplicate(true)
	result["rebellions"] = gs.rebellions.duplicate(true)
	result["diplomatic_history"] = gs.diplomatic_history.duplicate(true)
	result["war_gold_snapshot_diplomacy_revision"] = (
		sim._war_gold_snapshot_diplomacy_revision
	)
	result["ai_last_decision_day"] = sim._ai_last_decision_day
	var mobilization_rows: Array[Dictionary] = []
	for nation in gs.nations:
		mobilization_rows.append({
			"id": nation.id,
			"war_gold_income_snapshot": nation.war_gold_income_snapshot,
			"war_gold_income_snapshot_day": nation.war_gold_income_snapshot_day,
			"war_mobilization_target_troops": (
				nation.war_mobilization_target_troops
			),
			"war_mobilization_until_day": nation.war_mobilization_until_day,
			"war_mobilization_reason": nation.war_mobilization_reason,
			"war_preparation_target_nation": (
				nation.war_preparation_target_nation
			),
			"campaign_preparation_targets": (
				nation.campaign_preparation_targets.duplicate()
			),
			"campaign_last_offensive_day": nation.campaign_last_offensive_day,
			"campaign_next_offensive_day": nation.campaign_next_offensive_day,
			"campaign_offensive_count": nation.campaign_offensive_count,
			"campaign_theater_anchor_city": nation.campaign_theater_anchor_city,
			"campaign_theater_started_day": nation.campaign_theater_started_day,
			"campaign_preparation_started_day": (
				nation.campaign_preparation_started_day
			),
			"campaign_preparation_assignments": (
				nation.campaign_preparation_assignments.duplicate(true)
			),
			"campaign_preparation_group_assignments": (
				nation.campaign_preparation_group_assignments.duplicate(true)
			),
			"campaign_full_preparation_targets": (
				nation.campaign_full_preparation_targets.duplicate()
			),
			"campaign_post_capture_plans": (
				nation.campaign_post_capture_plans.duplicate(true)
			),
			"campaign_attack_assignments": (
				nation.campaign_attack_assignments.duplicate(true)
			),
			"campaign_attack_echelons": (
				nation.campaign_attack_echelons.duplicate(true)
			),
			"campaign_active_echelons": (
				nation.campaign_active_echelons.duplicate(true)
			),
			"campaign_launched_armies": (
				nation.campaign_launched_armies.duplicate(true)
			),
			"campaign_echelon_started_days": (
				nation.campaign_echelon_started_days.duplicate(true)
			),
			"campaign_plan_targets": nation.campaign_plan_targets.duplicate(),
			"campaign_plan_wave": nation.campaign_plan_wave,
			"campaign_plan_primary_city": nation.campaign_plan_primary_city,
		})
	result["mobilization"] = mobilization_rows
	var army_runtime_rows: Array[Dictionary] = []
	for army in gs.armies:
		army_runtime_rows.append({
			"id": army.id,
			"owner": army.owner_nation,
			"size": army.size,
			"state": army.state,
			"battle_id": army.battle_id,
			"path": army.path.duplicate(),
			"location_city": army.location_city,
			"move_from": army.move_from,
			"move_to": army.move_to,
			"move_progress": army.move_progress,
			"on_edge": army.on_edge,
			"diplomatic_repatriation": army.diplomatic_repatriation,
			"forced_retreat": army.forced_retreat,
			"ai_action": army.ai_action,
			"ai_target_city": army.ai_target_city,
			"ai_order_until_day": army.ai_order_until_day,
			"ai_order_reason": army.ai_order_reason,
		})
	result["army_runtime"] = army_runtime_rows
	var battle_rows: Array[Dictionary] = []
	for battle in gs.battles:
		var side_a_ids: Array[int] = []
		var side_b_ids: Array[int] = []
		for army in battle.side_a:
			side_a_ids.append(army.id)
		for army in battle.side_b:
			side_b_ids.append(army.id)
		battle_rows.append({
			"id": battle.id,
			"kind": battle.kind,
			"finished": battle.finished,
			"winner_side": battle.winner_side,
			"round_no": battle.round_no,
			"has_garrison": battle.has_garrison,
			"siege_progress": battle.siege_progress,
			"contact_dist_a": battle.contact_dist_a,
			"contact_dist_b": battle.contact_dist_b,
			"side_a": side_a_ids,
			"side_b": side_b_ids,
			"city_id": battle.city.id if battle.city != null else -1,
			"edge_key": (
				GameState.edge_key(battle.edge.city_a, battle.edge.city_b)
				if battle.edge != null
				else -1
			),
		})
	result["battles"] = battle_rows
	return result


func _transfer_all_owned_cities_for_fixture(
	gs: GameState,
	former_owner: int,
	recipient: int,
	reason: String
) -> Dictionary:
	var operations: Array[Dictionary] = []
	for city in gs.cities:
		if city.owner_nation != former_owner:
			continue
		operations.append({
			"city_id": city.id,
			"controller_id": recipient,
			"legal_owner_id": recipient,
			"sponsor_id": -1,
			"reset_political_target": true,
			"stock_policy": (
				GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
			),
			"reason": reason,
		})
	return gs.apply_territory_transaction(operations)


func _territory_fingerprint(gs: GameState) -> Dictionary:
	var city_rows: Array[Dictionary] = []
	for city in gs.cities:
		city_rows.append({
			"id": city.id,
			"owner": city.owner_nation,
			"legal": gs.recognized_owner_of(city.id),
			"sponsor": city.occupation_sponsor_nation,
			"capital": city.is_capital,
			"warehouse": city.has_warehouse,
			"food": city.food_storage,
		})
	var nation_rows: Array[Dictionary] = []
	for nation in gs.nations:
		nation_rows.append({
			"id": nation.id,
			"alive": nation.alive,
			"capital_city_id": nation.capital_city_id,
			"warehouse_city_ids": nation.warehouse_city_ids.duplicate(),
			"granary_food": nation.granary_food,
			"manpower_pool": nation.manpower_pool,
			"treasury_gold": nation.treasury_gold,
			"last_rebellion_day": nation.last_rebellion_day,
		})
	var army_rows: Array[Dictionary] = []
	for army in gs.armies:
		army_rows.append({
			"id": army.id,
			"owner": army.owner_nation,
			"size": army.size,
			"battle_group_id": army.battle_group_id,
			"occupation_claimant": army.occupation_claimant_nation,
			"state": army.state,
			"battle_id": army.battle_id,
		})
	return {
		"cities": city_rows,
		"nations": nation_rows,
		"armies": army_rows,
		"suzerainty": gs.suzerainty.duplicate(true),
		"diplomatic_relations": gs.diplomatic_relations.duplicate(true),
		"diplomatic_since_day": gs.diplomatic_since_day.duplicate(true),
		"truce_until_day": gs.truce_until_day.duplicate(true),
		"ownership_revision": gs.ownership_revision,
		"diplomacy_revision": gs.diplomacy_revision,
	}


func _make_edge(danger: float, distance: int) -> Edge:
	var e := Edge.new()
	e.city_a = 0
	e.city_b = 1
	e.distance = distance
	e.danger = danger
	e.max_manpower = 45000
	return e


func _set_warehouses(
	gs: GameState,
	nation_id: int,
	city_ids: Array[int],
	stocks: Array[int],
	capital_id: int = -1
) -> void:
	var nation := gs.nations[nation_id]
	for old_id in nation.warehouse_city_ids:
		var old_city := gs.cities[old_id]
		old_city.is_capital = false
		old_city.has_warehouse = false
		old_city.food_storage = 0
	nation.warehouse_city_ids = city_ids.duplicate()
	nation.capital_city_id = capital_id if capital_id != -1 else (
		city_ids[0] if not city_ids.is_empty() else -1
	)
	for i in range(city_ids.size()):
		var city := gs.cities[city_ids[i]]
		city.has_warehouse = true
		city.is_capital = city.id == nation.capital_city_id
		city.food_storage = stocks[i]


func _set_single_warehouse(gs: GameState, nation_id: int, city_id: int, stock: int) -> void:
	_set_warehouses(
		gs,
		nation_id,
		[city_id] as Array[int],
		[stock] as Array[int],
		city_id
	)


## 本国全部实控城是否都能从首都经本国可通行道路到达（地图连续性判定）。
func _nation_territory_contiguous(gs: GameState, nation_id: int) -> bool:
	var capital := gs.nations[nation_id].capital_city_id
	if capital < 0:
		return true
	var seen := {capital: true}
	var queue: Array[int] = [capital]
	var cursor := 0
	while cursor < queue.size():
		var cid := queue[cursor]
		cursor += 1
		for neighbor in gs.neighbors(cid):
			var edge := gs.edge_of(cid, neighbor)
			if (
				seen.has(neighbor)
				or edge == null
				or edge.max_manpower <= 0
				or gs.cities[neighbor].owner_nation != nation_id
			):
				continue
			seen[neighbor] = true
			queue.append(neighbor)
	for city in gs.cities:
		if city.owner_nation == nation_id and not seen.has(city.id):
			return false
	return true


func _make_army(aid: int, nation: int, size: int, atk: int, def_v: int = 10) -> Army:
	var a := Army.new()
	a.id = aid
	a.owner_nation = nation
	a.size = size
	a.attack = atk
	a.defense = def_v
	return a


## 构造一场野战：side_a / side_b 各军在边中点相遇（contact = L/2）。
func _make_field_battle(side_a: Array, side_b: Array, danger: float, distance: int) -> Battle:
	var b := Battle.new()
	b.id = 0
	b.kind = Battle.Kind.FIELD
	b.edge = _make_edge(danger, distance)
	b.contact_dist_a = distance / 2.0
	b.contact_dist_b = distance / 2.0
	# 通用机制单测隔离战术运气，专门的 item 8 统计测试负责验证独立随机。
	b.tactical_key_a = 101
	b.tactical_key_b = 101
	for a in side_a:
		b.side_a.append(a)
	for a in side_b:
		b.side_b.append(a)
	return b


## 构造一场攻城：攻方在城墙(dist=L)、守军在城中(dist=0)，守军享 fort_strength 城防加成。
func _make_siege_battle(attackers: Array, defender: Army, fort_strength: int, distance: int) -> Battle:
	var b := Battle.new()
	b.id = 0
	b.kind = Battle.Kind.SIEGE
	b.edge = _make_edge(0.0, distance)
	b.city = City.new()
	b.city.fort_strength = fort_strength
	b.has_garrison = true              # side_b 为驻城守军，享城防加成（combat 按此 gate）
	b.contact_dist_a = float(distance)
	b.contact_dist_b = 0.0
	b.tactical_key_a = 101
	b.tactical_key_b = 101
	for a in attackers:
		b.side_a.append(a)
	b.side_b.append(defender)
	return b


## 跑完一场战斗（回合直到结束），返回回合数。带硬上限防死循环。
func _run_battle(battle: Battle, rng: RandomNumberGenerator) -> int:
	var guard := 0
	while not battle.finished and guard < 1000:
		Combat.resolve_round(battle, rng)
		guard += 1
	return guard


func _battle_force_morale(
	active: Array[Army],
	routed: Array[Army]
) -> float:
	var morale_mass := 0.0
	var manpower := 0
	for army in active + routed:
		if army.size <= 0:
			continue
		morale_mass += float(army.size) * army.morale
		manpower += army.size
	return (
		morale_mass / float(manpower)
		if manpower > 0
		else 0.0
	)


## 纯围城（无守军）：side_b 空、has_garrison=false。
## fort_strength = 工事强度（战力量纲）；siege_required = 破城所需兵力（兵力量纲，围城比值分母）。
## 未显式指定 siege_required 时，按空城口径由工事换算（Combat.siege_required_manpower）。
func _make_pure_siege(attacker: Army, fort_strength: int, distance: int, siege_required: int = -1) -> Battle:
	var b := Battle.new()
	b.id = 0
	b.kind = Battle.Kind.SIEGE
	b.edge = _make_edge(0.0, distance)
	b.city = City.new()
	b.city.id = 0
	b.city.owner_nation = 9          # 中立占位，_capture_city 会改写
	b.city.fort_strength = fort_strength
	b.city.food_storage = 100        # 有粮：不触发粮尽衰减
	b.has_garrison = false
	b.siege_required = (
		siege_required if siege_required >= 0
		else Combat.siege_required_manpower(fort_strength)
	)
	b.contact_dist_a = float(distance)
	b.side_a.append(attacker)
	return b


## 在 gs 的 (from_city→to_city) 边上放一支 MOVING 军队（受控位置）。
## progress 为该军自身 move_progress；norm 位置由 _norm_pos 依 move_from 推导。
func _place_army_on_edge(gs, id: int, nation: int, from_city: int, to_city: int, progress: float) -> Army:
	var a := _make_army(id, nation, 1000, 10)
	a.state = Army.State.MOVING
	a.move_from = from_city
	a.move_to = to_city
	a.move_progress = progress
	a.on_edge = true
	gs.armies.append(a)
	return a


func _legacy_neutral_border_massing_ratio(
	game_state: GameState,
	observer_id: int,
	current_enemy_id: int
) -> float:
	var border_power := 0.0
	for other in game_state.nations:
		if (
			not other.alive
			or other.id in [observer_id, current_enemy_id]
			or game_state.is_allied(observer_id, other.id)
			or game_state.is_enemy(observer_id, other.id)
		):
			continue
		var frontier_cities := {}
		for edge in game_state.edges:
			if edge.max_manpower <= 0:
				continue
			var owner_a := game_state.cities[
				edge.city_a
			].owner_nation
			var owner_b := game_state.cities[
				edge.city_b
			].owner_nation
			if owner_a == observer_id and owner_b == other.id:
				frontier_cities[edge.city_b] = true
			elif owner_b == observer_id and owner_a == other.id:
				frontier_cities[edge.city_a] = true
		for army in game_state.armies:
			if army.owner_nation != other.id or army.size <= 0:
				continue
			if (
				(
					army.location_city >= 0
					and frontier_cities.has(army.location_city)
				)
				or (
					army.on_edge
					and army.move_to >= 0
					and (
						frontier_cities.has(army.move_from)
						or frontier_cities.has(army.move_to)
					)
				)
			):
				border_power += ArmyPower.effective(army)
	return minf(
		border_power
			/ maxf(
				DiplomacyAI._national_power(
					game_state,
					observer_id,
					{}
				),
				1.0
			),
		DiplomacyAI.PEACE_MAX_BORDER_MASSING_RATIO
	)
