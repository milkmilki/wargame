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
	_test_responsive_map_layout()
	_test_terrain_multiplier()
	_test_battle_basics()
	_test_retreat_mechanic()
	_test_garrison_defense()
	_test_multi_vs_one()
	_test_starvation_morale()
	_test_persistent_morale()
	_test_simulation_progress()
	_test_determinism()
	_test_time_layering()
	_test_siege_dice()
	_test_trigger_detection()
	_test_three_way_battle()
	_test_three_way_siege()
	_test_multi_army_aggregation()
	_test_three_way_serial()
	_test_siege_arrival_triggers()
	_test_crosspass_field_priority()
	_test_capacity_no_block_enemy()
	_test_directional_friendly_capacity()
	_test_march_time_linear()
	_test_siege_time_curve()
	_test_siege_food_clock()
	_test_weak_attack_retreat()
	_test_morale_retreat_recovery()
	_test_supply_morale_and_passive_retreat_battle()
	_test_siege_battle_then_progress_order()
	_test_siege_interruption_and_late_garrison()
	_test_edge_holding_state()
	_test_edge_supply_from_both_endpoints()
	_test_warehouse_logistics()
	_test_holding_combat_adaptation()
	_test_retreat_contact_and_position_continuity()
	_test_ai_strategic_map_and_threat()
	_test_ai_merge_and_retreat_utility()
	_test_ai_encirclement_breakout_and_relief()
	_test_manpower_pool_and_force_commands()
	_test_diplomacy_state_and_ai()
	_test_peacetime_demobilization_and_border_defense()
	_test_resource_hubs_and_food_mobilization()

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

# ------------------------------------------------------------------ 1. 世界生成

func _test_world_generation() -> void:
	print("[1] 世界生成不变量")
	var gs := GameState.new()
	gs.generate_world(12345)
	_check(gs.cities.size() == 64, "城市数应为 64，实为 %d" % gs.cities.size())
	_check(
		gs.edges.size() >= 63 and gs.edges.size() < 160,
		"真实地图应使用稀疏局部图，边数实为 %d" % gs.edges.size()
	)
	var chokepoint_count := 0
	for edge in gs.edges:
		if (
			edge.max_manpower > 0
			and edge.danger
				>= Combat.CHOKEPOINT_DANGER_THRESHOLD
		):
			chokepoint_count += 1
	_check(
		chokepoint_count > 0,
		"真实地图至少应生成一条可通行高险关隘"
	)
	_check(gs.armies.size() == 96, "初始军队数应为 96，实为 %d" % gs.armies.size())
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
	# 四等份：每国 16 城
	for n in gs.nations:
		var cnt := gs.cities_of(n.id).size()
		_check(cnt == 16, "国%d 初始应有 16 城，实为 %d" % [n.id, cnt])
		var food_hubs: Array[City] = []
		var manpower_hubs: Array[City] = []
		for owned_city in gs.cities_of(n.id):
			if owned_city.is_food_hub:
				food_hubs.append(owned_city)
			if owned_city.is_manpower_hub:
				manpower_hubs.append(owned_city)
		_check(
			food_hubs.size() == 1
			and food_hubs[0].food_per_half_year >= GameState.FOOD_HUB_MIN_OUTPUT,
			"国%d 应有一个高产粮食核心" % n.id
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
		var owned_queue: Array[int] = [gs.cities_of(n.id)[0].id]
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
		_check(
			owned_reachable.size() == 16,
			"国%d 初始 16 城应形成连续领土，实为 %d" % [n.id, owned_reachable.size()]
		)
		var light_armies := 0
		var heavy_armies := 0
		var initial_troops := 0
		for army in gs.armies:
			if army.owner_nation != n.id:
				continue
			initial_troops += army.size
			if (
				army.size == GameState.INITIAL_LIGHT_ARMY_SIZE
				and army.max_size == GameState.INITIAL_LIGHT_ARMY_SIZE
			):
				light_armies += 1
			elif (
				army.size == GameState.INITIAL_HEAVY_ARMY_SIZE
				and army.max_size == GameState.INITIAL_HEAVY_ARMY_SIZE
			):
				heavy_armies += 1
		_check(
			light_armies == cnt
			and heavy_armies == cnt / 2
			and light_armies + heavy_armies
				== int(float(cnt) * 1.5),
			"国%d 初始军制应为每城1支5000军、每2城1支15000军" % n.id
		)
		_check(
			initial_troops == 200000,
			"国%d 初始24军应满编20万人，实为%d" % [n.id, initial_troops]
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
	var positions_unique := {}
	var terrain_has_relief := false
	for city in gs.cities:
		positions_unique[city.map_position] = true
		terrain_has_relief = terrain_has_relief or city.terrain_relief > 0.0
	_check(gs.uses_heightmap and positions_unique.size() == 64,
		"正式世界应从高度图生成 64 个互异城市位置")
	_check(terrain_has_relief, "城市应保存高度图局部起伏数据")
	var minimum_city_spacing := INF
	for a in range(gs.cities.size()):
		for b in range(a + 1, gs.cities.size()):
			var delta := gs.cities[a].map_position - gs.cities[b].map_position
			delta.x *= gs.map_aspect_ratio
			minimum_city_spacing = minf(minimum_city_spacing, delta.length())
	_check(
		minimum_city_spacing >= 0.075,
		"城市点应保持足够间距，实为 %.4f" % minimum_city_spacing
	)
	_check(
		gs.map_source_region_normalized.position.x > 0.0
		and gs.map_source_region_normalized.position.y > 0.0
		and gs.map_source_region_normalized.end.x < 1.0
		and gs.map_source_region_normalized.end.y < 1.0,
		"底图应裁切到 Alpha 陆地包围盒，排除外围水印区域"
	)
	var province_seen := {}
	var province_has_sea := false
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
			province_ids_valid and province_id < gs.cities.size()
		)
		province_seen[province_id] = true
	_check(
		province_ids_valid
		and province_has_sea
		and province_seen.size() == gs.cities.size(),
		"陆地掩码 Voronoi 必须为64城各生成独立省份，轮廓外保持透明"
	)
	var province_owners_stable := true
	for city in gs.cities:
		province_owners_stable = (
			province_owners_stable
			and gs.recognized_owner_of(city.id) == city.owner_nation
		)
	_check(province_owners_stable, "省份必须保存不随占领变化的初始归属")
	var province_geometry := MapRenderer.build_province_boundary_segments(gs)
	_check(
		not (province_geometry["province"] as PackedVector2Array).is_empty()
		and not (province_geometry["nation"] as PackedVector2Array).is_empty()
		and not (province_geometry["coast"] as PackedVector2Array).is_empty(),
		"省份栅格必须能提取省界、国境和地图外轮廓三种线段"
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
	# 每国只有首都一个粮仓；原 16 城初始储备全部归集到该粮仓。
	for n in gs.nations:
		var warehouses := gs.warehouse_cities_of(n.id)
		_check(warehouses.size() == 1 and warehouses[0].id == n.capital_city_id,
			"国%d 初始应只有首都一个粮仓" % n.id)
		_check(
			warehouses[0].food_storage
				>= 16 * GameState.INITIAL_CITY_FOOD_STOCK_MIN
			and warehouses[0].food_storage
				<= 16 * GameState.INITIAL_CITY_FOOD_STOCK_MAX,
			"国%d 首都粮仓应归集 16 城初始储备，实为 %d" % [n.id, warehouses[0].food_storage])
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
		5000: 0,
		15000: 0,
		30000: 0,
		60000: 0,
		100000: 0,
	}
	var degrees := {}
	var longest_edge := 0.0
	var roads_by_relief: Array[Edge] = gs.edges.duplicate()
	roads_by_relief.sort_custom(func(a: Edge, b: Edge) -> bool:
		return a.max_height_difference < b.max_height_difference
	)
	for edge in gs.edges:
		road_counts[edge.max_manpower] = int(road_counts.get(edge.max_manpower, 0)) + 1
		_check(
			MapRenderer.is_edge_visible(edge)
				== (edge.max_manpower > 0),
			"地图只应显示正容量道路"
		)
		degrees[edge.city_a] = int(degrees.get(edge.city_a, 0)) + 1
		degrees[edge.city_b] = int(degrees.get(edge.city_b, 0)) + 1
		var delta := (
			gs.cities[edge.city_a].map_position
			- gs.cities[edge.city_b].map_position
		)
		delta.x *= gs.map_aspect_ratio
		longest_edge = maxf(longest_edge, delta.length())
	_check(
		int(road_counts[0]) > 0,
		"最高起伏道路中应包含不可供大军通行的边，分布=%s" % str(road_counts)
	)
	_check(
		int(road_counts[5000]) > 0
		and int(road_counts[15000]) > 0
		and int(road_counts[30000]) > 0
		and int(road_counts[60000]) > 0
		and int(road_counts[100000]) > 0,
		"正容量道路应形成 5000~100000 人的五个等级，分布=%s"
			% str(road_counts)
	)
	_check(
		int(road_counts[100000])
			< int(ceil(float(gs.edges.size()) * 0.10)),
		"十万人平原大道必须保持稀少，分布=%s" % str(road_counts)
	)
	var low_relief_average := 0.0
	var high_relief_average := 0.0
	var comparison_count := maxi(gs.edges.size() / 4, 1)
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
		"Delaunay 局部图的城市度数应自然变化，不能硬编码固定边数"
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
			and original.max_manpower == copied.max_manpower
			and _approx(
				original.max_height_difference,
				copied.max_height_difference
			)
		)
	_check(terrain_deterministic, "相同高度图与种子必须生成完全一致的城市和道路")


func _test_responsive_map_layout() -> void:
	print("[1b] 响应式界面：窗口放大时地图同比增大并保持居中")
	var base := MapRenderer.compute_layout_for_viewport(Vector2(1280, 720), 4)
	var large := MapRenderer.compute_layout_for_viewport(Vector2(1920, 1080), 4)
	_check(
		_approx(float(large["cell"]) / float(base["cell"]), 1.5),
		"窗口同比放大 1.5 倍时地图单元格也应放大 1.5 倍"
	)
	var large_origin: Vector2 = large["origin"]
	_check(
		large_origin.y > 120.0,
		"国家详情卡应保留独立顶部区域，不得覆盖地图"
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
		"窄窗口应自动减少 HUD 列数并为多行国家数据留出空间"
	)
	var ui_font := MapRenderer.create_ui_font()
	_check(
		ui_font.has_char("国".unicode_at(0)),
		"HUD 字体必须包含中文字形，不能回退为乱码或方框"
	)

# ------------------------------------------------------------------ 2. 地形惩罚

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
	_check(
		_approx(
			Combat.attack_multiplier(
				Combat.CHOKEPOINT_DANGER_THRESHOLD
			),
			Combat.CHOKEPOINT_ATTACK_MULTIPLIER
		),
		"高险关隘应把进攻方攻击倍率压低到25%%"
	)
	_check(
		Combat.attack_multiplier(
			Combat.CHOKEPOINT_DANGER_THRESHOLD - 0.01
		) > Combat.CHOKEPOINT_ATTACK_MULTIPLIER,
		"关隘级惩罚只能作用于少数高危险道路"
	)

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

	# (b) 战后恢复：非交战、有粮军队每月回士气，封顶 1.0。
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)
	var probe := gs.armies[0]
	probe.morale = 0.2
	probe.state = Army.State.IDLE
	probe.starving = false
	var before := probe.morale
	sim._recover_morale()
	_check(probe.morale > before, "非交战有粮军队士气应恢复：%.2f -> %.2f" % [before, probe.morale])
	_check(probe.morale <= 1.0, "士气恢复不应越界 1.0")
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
	var monthly := 0
	for c in gs.cities:
		monthly += Simulation.city_gold_output(gs, c)
	var war_upkeep := 0
	for nation in gs.nations:
		var troops := 0
		for army in gs.armies:
			if army.owner_nation == nation.id:
				troops += army.size
		war_upkeep += int(ceil(
			float(troops) / float(GameState.WAR_GOLD_TROOPS_PER_UNIT)
		))
	sim._advance_day()   # day==30
	var after := 0
	for n in gs.nations:
		after += n.treasury_gold
	var expected_treasury := before + monthly - war_upkeep
	_check(after == expected_treasury,
		"day30 应结算月收入并扣战争军费：应 %d，实为 %d"
			% [expected_treasury, after])
	sim.free()

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
	print("[9] 确定性围城：5× 门槛 + 兵力倍数递减(90→3 天) + 破城归攻方")
	var gs := GameState.new()
	gs.generate_grid_world(12345)
	var sim := Simulation.new()
	sim.setup(gs)

	# 1. 破城需 >1 tick（累积，非瞬占），破城后城归攻方。ratio=1000/100=10 → ~48 天。
	var b := _make_pure_siege(_make_army(0, 0, 1000, 10), 10, 4, 100)
	var ticks := _run_siege(sim, b)
	_check(ticks > 1, "围城累积破城应 >1 天（非瞬占），实为 %d" % ticks)
	_check(b.city.owner_nation == 0, "破城后城应归攻方 nation0，实为 %d" % b.city.owner_nation)
	_check(b.winner_side == 1, "破城 winner_side 应为 1，实为 %d" % b.winner_side)

	# 2. 兵力倍数越高围城越快（确定性、无掷骰、与城防无关）：r=100 应快于 r=5。
	var t_r5 := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 500, 10), 10, 4, 100))   # r=5
	var t_r100 := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 10000, 10), 10, 4, 100)) # r=100
	_check(t_r100 < t_r5, "高兵力倍数(r=100)应快于低倍数(r=5)：%d vs %d" % [t_r100, t_r5])

	# 3. 边界标定：r=5 → 90 天（±1 容差）；r 极大 → 趋近 3 天。
	_check(absi(t_r5 - 90) <= 1, "r=5 围城应约 90 天，实为 %d" % t_r5)
	var t_rinf := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 1000000, 10), 10, 4, 100))
	_check(t_rinf <= 4 and t_rinf >= 3, "r→∞ 围城应趋近 3 天(3~4)，实为 %d" % t_rinf)

	# 4. 5× 门槛：ratio<5 时立即结束围城并强制撤离，不能永久切断补给。
	var weak_attacker := _make_army(0, 0, 400, 10)
	var b_stall := _make_pure_siege(weak_attacker, 10, 4, 100)   # r=4 <5
	var stalled := _run_siege(sim, b_stall)
	_check(stalled == 1 and b_stall.finished,
		"ratio<5(=4) 围城应首日终止，实跑 %d finished=%s" % [stalled, b_stall.finished])
	_check(b_stall.siege_progress == 0.0 and b_stall.side_a.is_empty(),
		"ratio<5(=4) 不得推进且攻方必须撤出围城")

	# 5. 城防不再影响纯围城速度（确定性递减只看兵力倍数）：同 ratio 同 garrison_ref 下高低城防同时。
	var t_deflo := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 1000, 10), 5, 4, 100))
	var t_defhi := _run_siege(sim, _make_pure_siege(_make_army(0, 0, 1000, 10), 40, 4, 100))
	_check(t_deflo == t_defhi, "纯围城速度应只取决于兵力倍数，与城防无关：%d vs %d" % [t_deflo, t_defhi])

	sim.free()


func _run_siege(sim, b) -> int:
	var guard := 0
	while not b.finished and guard < 2000:
		sim._advance_siege(b)
		guard += 1
	return guard

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
	_check(b.battle_id == -1 and b.state == Army.State.MOVING and b.move_from == city.id,
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

	# (a) 2v2 聚合触发：同国靠后友军（>CONTACT_EPS）也应并入本侧（旧码会漏 → 1v1）
	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	gs.armies.clear(); gs.battles.clear()
	_place_army_on_edge(gs, 0, 0, 0, 1, 0.50)   # A0 n0 norm0.50
	_place_army_on_edge(gs, 1, 0, 0, 1, 0.20)   # A1 n0 norm0.20（靠后）
	_place_army_on_edge(gs, 2, 1, 1, 0, 0.50)   # B0 n1 norm0.50
	_place_army_on_edge(gs, 3, 1, 1, 0, 0.20)   # B1 n1 norm0.80
	sim._detect_encounters()
	_check(gs.battles.size() == 1, "2v2 应仅 1 场战斗，实为 %d" % gs.battles.size())
	if gs.battles.size() == 1:
		var bt: Battle = gs.battles[0]
		_check(bt.side_a.size() == 2 and _single_nation(bt.side_a), "side_a 应聚合 2 支且同 n0，实为 %d" % bt.side_a.size())
		_check(bt.side_b.size() == 2 and _single_nation(bt.side_b), "side_b 应聚合 2 支且同 n1，实为 %d" % bt.side_b.size())
	sim.free()

	# (b) 攻击力 Σ 累加：拆成 2 支（各 1000）与合成 1 支（2000）对同一守军的伤害应相等
	var loss_split := _one_round_side_b_loss([_make_army(0, 0, 1000, 10), _make_army(1, 0, 1000, 10)], [_make_army(2, 1, 3000, 10)], 90)
	var loss_single := _one_round_side_b_loss([_make_army(0, 0, 2000, 10)], [_make_army(2, 1, 3000, 10)], 90)
	_check(loss_split == loss_single, "攻击Σ累加：拆分(%d) 应等于合成(%d)" % [loss_split, loss_single])

	# (c) 防御反拆分漏洞：守军拆成 2×500(def12) 与 1×1000(def12) 承受同一火力，总伤应近似相等
	var loss_def_single := _one_round_side_b_loss([_make_army(0, 0, 2000, 10)], [_make_army(2, 1, 1000, 10, 12)], 91)
	var loss_def_split := _one_round_side_b_loss([_make_army(0, 0, 2000, 10)], [_make_army(2, 1, 500, 10, 12), _make_army(3, 1, 500, 10, 12)], 91)
	_check(absi(loss_def_single - loss_def_split) <= 2, "防御反拆分：单支(%d) 与拆分(%d) 总伤应近似（差≤2）" % [loss_def_single, loss_def_split])

	# (d) 增援回气：疲劳(0.30)友军获满员援军(morale1.0)加入，士气应回升约 +0.10；援军自身不变
	var gs2 := GameState.new(); gs2.generate_grid_world(12345)
	var sim2 := Simulation.new(); sim2.setup(gs2)
	var tired := _make_army(0, 0, 1000, 10); tired.morale = 0.30
	var defender := _make_army(1, 1, 1000, 10)
	var battle := _make_field_battle([tired], [defender], 0.0, 4)
	var fresh := _make_army(2, 0, 1000, 10); fresh.morale = 1.0
	fresh.move_from = 0; fresh.move_to = 1; fresh.move_progress = 0.5
	sim2._join_field_battle(battle, fresh, battle.edge)
	_check(battle.side_a.size() == 2, "增援后 side_a 应为 2 支")
	_check(_approx(tired.morale, 0.40, 0.001), "疲劳友军应因增援回气至约 0.40，实为 %.3f" % tired.morale)
	_check(_approx(fresh.morale, 1.0), "援军自身士气不应被自己提振")
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
		_check(bt.side_a.size() == na_count and bt.side_b.size() == nb_count,
			"%dv%d 聚合计数应为 %d/%d，实为 %d/%d" % [na_count, nb_count, na_count, nb_count, bt.side_a.size(), bt.side_b.size()])
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

	# (d) 守军仍在，真第三国(nation1)抵达 → 三方不可共存，从目标城撤回（不并入任一侧）
	gs3.cities[62].owner_nation = 1   # 为第三国提供合法本国退路，禁止借道其他敌城
	var intruder := _make_army(922, 1, 1000, 10)
	intruder.move_from = 62; intruder.move_to = 63; intruder.move_progress = 1.0; intruder.on_edge = true
	intruder.state = Army.State.MOVING
	gs3.armies.append(intruder)
	sim3._arrive_at_node(intruder)
	_check(intruder.battle_id == -1 and intruder.state == Army.State.MOVING
		and intruder.move_from == city3.id,
		"守军在场时真第三国应从目标城撤回且不介入")

	# (e) 城主援军解围胜利后应入城驻守，而非"晋升为围城方去围自己的城"
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
	sim.free(); sim2.free(); sim3.free(); sim4.free()

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

# ------------------------------------------------------------------ 17. 一万五容量边错身：敌军不占本国方向容量

func _test_capacity_no_block_enemy() -> void:
	print("[17] 一万五容量边：敌军先占边，迎战方不得被交通容量挡在城里错身穿过")

	var gs := GameState.new(); gs.generate_grid_world(12345)
	var sim := Simulation.new(); sim.setup(gs)
	var c1 := -1; var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation != gs.cities[e.city_b].owner_nation:
			c1 = e.city_a; c2 = e.city_b; break
	_check(c1 != -1, "应存在一条敌对相邻边")
	var edge := gs.edge_of(c1, c2)
	edge.max_manpower = 15000        # 单槽：复现容量满
	edge.distance = 3; edge.danger = 0.0
	gs.armies.clear(); gs.battles.clear()

	# R 从 c1 出发，先占满单槽边
	var R := _make_army(1, gs.cities[c1].owner_nation, 1000, 10)
	R.state = Army.State.MOVING; R.move_from = c1; R.move_to = -1
	R.location_city = c1; R.path = [c2] as Array[int]
	gs.armies.append(R)
	sim._begin_next_leg(R)
	_check(R.on_edge and R.move_to == c2, "R 应占用单槽边 (on_edge)")
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
	print("[17b] 边容量：同国同向受限，反向独立，敌军不占友军名额")
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
	first.state = Army.State.MOVING
	first.location_city = from_city
	first.move_from = from_city
	first.path = [to_city] as Array[int]
	gs.armies.append(first)
	sim._begin_next_leg(first)
	_check(first.on_edge and first.move_to == to_city, "首支同向友军应进入边")

	var same_direction := _make_army(1701, nation_id, 1000, 10)
	same_direction.max_size = 5000
	same_direction.state = Army.State.MOVING
	same_direction.location_city = from_city
	same_direction.move_from = from_city
	same_direction.path = [to_city] as Array[int]
	gs.armies.append(same_direction)
	sim._begin_next_leg(same_direction)
	_check(not same_direction.on_edge and same_direction.move_to == -1,
		"同国同方向达到 max_manpower 后应等待")

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
		"总占用可超过单方向上限：正向友军+反向友军+敌军应为 3")

	sim._release_edge(first)
	sim._begin_next_leg(same_direction)
	_check(same_direction.on_edge and same_direction.move_to == to_city,
		"同向友军释放名额后，等待军应能进入")
	for small_index in range(2):
		var small := _make_army(
			1710 + small_index,
			nation_id,
			1000,
			10
		)
		small.max_size = 5000
		small.state = Army.State.MOVING
		small.location_city = from_city
		small.move_from = from_city
		small.path = [to_city] as Array[int]
		gs.armies.append(small)
		sim._begin_next_leg(small)
		_check(
			small.on_edge,
			"三支满编合计15000人的小军应可同向进入一万五容量边"
		)
	var fourth_small := _make_army(
		1712,
		nation_id,
		1000,
		10
	)
	fourth_small.max_size = 5000
	fourth_small.state = Army.State.MOVING
	fourth_small.location_city = from_city
	fourth_small.move_from = from_city
	fourth_small.path = [to_city] as Array[int]
	gs.armies.append(fourth_small)
	sim._begin_next_leg(fourth_small)
	_check(
		not fourth_small.on_edge,
		"满编总额超过道路容量后必须等待"
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

# ------------------------------------------------------------------ 18. R1 行军时长线性映射

func _test_march_time_linear() -> void:
	print("[18] R1 行军：任意长度 10~30 天，随长度线性插值")
	# 边界：distance=1 → 10 天（最短）；distance>=5 → 30 天（最长，clamp 封顶）。
	_check(_approx(Simulation.march_days(1), 10.0), "distance=1 应 10 天，实为 %.1f" % Simulation.march_days(1))
	_check(_approx(Simulation.march_days(5), 30.0), "distance=5 应 30 天，实为 %.1f" % Simulation.march_days(5))
	_check(_approx(Simulation.march_days(3), 20.0), "distance=3 应 20 天（线性中点），实为 %.1f" % Simulation.march_days(3))
	# 越界护栏：非法/超长距离仍夹在 [10,30]。
	_check(Simulation.march_days(0) >= 10.0, "distance=0 应夹到下界 >=10，实为 %.1f" % Simulation.march_days(0))
	_check(Simulation.march_days(99) <= 30.0, "distance=99 应夹到上界 <=30，实为 %.1f" % Simulation.march_days(99))
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
	print("[19] R2 围城：5× 门槛 + 90→3 天递减标定")
	# 每日进度 = 100/围城天数。反推天数 = 100/每日进度。
	# r<5：不推进（进度 0）。
	_check(Combat.siege_daily_progress(400, 100) == 0.0, "r=4(<5) 应不推进，实为 %.3f" % Combat.siege_daily_progress(400, 100))
	_check(Combat.siege_daily_progress(499, 100) == 0.0, "r=4.99(<5) 应不推进")
	# r=5：恰好 90 天（基准）。
	var days_r5 := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(500, 100)
	_check(_approx(days_r5, 90.0, 0.01), "r=5 应 90 天，实为 %.3f" % days_r5)
	# r→∞：趋近下界 3 天。
	var days_rinf := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(100000000, 100)
	_check(days_rinf >= 3.0 and days_rinf <= 3.01, "r→∞ 应趋近 3 天，实为 %.3f" % days_rinf)
	# 单调递减：兵力倍数越大，围城天数越短。
	var mono := true
	var prev := 1e9
	for mult in [5, 6, 8, 10, 20, 50, 100]:
		var dp := Combat.siege_daily_progress(mult * 100, 100)
		var d := Combat.SIEGE_PROGRESS_REQUIRED / dp
		if d > prev + 1e-6:
			mono = false
		prev = d
	_check(mono, "围城天数应随兵力倍数单调递减")
	# 全程夹在 [3,90]。
	var in_range := true
	for mult in [5, 7, 13, 30, 200, 1000]:
		var d := Combat.SIEGE_PROGRESS_REQUIRED / Combat.siege_daily_progress(mult * 100, 100)
		if d < 3.0 - 1e-6 or d > 90.0 + 1e-6:
			in_range = false
	_check(in_range, "围城天数应恒在 [3,90] 区间")

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
	siege.side_a.append(atk); siege.garrison_ref = 100000            # 超高基准→永不推进
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
	# 粮尽 → 守军城防加成大幅衰减（战力大幅下降）。
	var garr_full := city.defense
	var garr_starve := int(round(city.defense * Combat.SIEGE_STARVE_DEF_MULT))
	_check(garr_starve < garr_full, "粮尽守军城防应大幅下降：%d → %d" % [garr_full, garr_starve])
	_check(_approx(float(garr_starve) / maxf(float(garr_full), 1.0), Combat.SIEGE_STARVE_DEF_MULT, 0.05),
		"粮尽城防应约为原值 ×%.1f" % Combat.SIEGE_STARVE_DEF_MULT)
	sim.free()

# ------------------------------------------------------------------ 21. R4 空城弱攻退避

func _test_weak_attack_retreat() -> void:
	print("[21] R4 空城弱攻：兵力 < 城防则不围城、自动向友方城撤离")
	var gs := GameState.new()
	gs.generate_grid_world(555)
	var sim := Simulation.new()
	sim.setup(gs)
	# 找一条敌对边：c1(攻方国) → c2(空城，防御高)。
	var c1 := -1; var c2 := -1
	for e in gs.edges:
		if gs.cities[e.city_a].owner_nation != gs.cities[e.city_b].owner_nation:
			c1 = e.city_a; c2 = e.city_b; break
	var edge := gs.edge_of(c1, c2)
	var target := gs.cities[c2]
	target.defense = 300                     # 高城防
	gs.armies.clear(); gs.battles.clear()
	# 确保 c2 为空城（无守军）。攻方兵力 100 < 城防 300。
	var atk := _make_army(1, gs.cities[c1].owner_nation, 100, 10)
	atk.state = Army.State.MOVING; atk.move_from = c1; atk.move_to = c2
	atk.location_city = c1; atk.on_edge = true; atk.move_progress = 1.0
	gs.armies.append(atk)
	var before_owner := target.owner_nation
	# 攻方到达空城 → 触发围城判定：弱攻应撤离，不占城、不建围城。
	sim._start_or_join_siege(atk, target, edge)
	_check(gs.city_under_siege(c2) == false, "弱攻空城不应建立围城")
	_check(target.owner_nation == before_owner, "弱攻不得占据空城（owner 不变）")
	_check(atk.state == Army.State.MOVING, "弱攻方应转为 MOVING 撤离，实为 %d" % atk.state)
	_check(atk.move_to != c2, "撤离目标不应是被攻空城 c2")
	# 对照：强攻（兵力 >= 城防）应正常建立围城。
	gs.armies.clear(); gs.battles.clear()
	var strong := _make_army(2, gs.cities[c1].owner_nation, 400, 10)   # 400 >= 300
	strong.state = Army.State.MOVING; strong.move_from = c1; strong.move_to = c2
	strong.location_city = c1; strong.on_edge = true; strong.move_progress = 1.0
	gs.armies.append(strong)
	sim._start_or_join_siege(strong, target, edge)
	_check(gs.city_under_siege(c2), "强攻(兵力>=城防)应正常建立围城")
	sim.free()

# ------------------------------------------------------------------ 22. 士气崩溃撤退 + 驻城恢复

func _test_morale_retreat_recovery() -> void:
	print("[22] 士气崩溃：撤往最近友城 + 驻城耗粮恢复 + 满士气/粮尽解锁")
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
	while broken.state == Army.State.RETREATING and guard < 40:
		sim._advance_movement()
		guard += 1
	_check(broken.state == Army.State.RECOVERING and broken.location_city == c2,
		"抵达最近友城后应进入 RECOVERING 驻守，state=%d city=%d" % [broken.state, broken.location_city])
	_check(gs.army_at_city(c2) == broken, "RECOVERING 军队应计入驻城守军，不能被视为空城")
	sim._ai_assign_targets()
	_check(broken.state == Army.State.RECOVERING, "恢复驻守期间不得执行下一步行动")

	# RECOVERING 不走普通补给扣粮，只由恢复结算消费本城资源，避免双重扣除。
	_set_single_warehouse(gs, broken.owner_nation, c2, 100)
	sim._resolve_supply()
	_check(gs.cities[c2].food_storage == 100, "RECOVERING 不应被普通补给重复扣粮")
	sim._recover_morale()
	var recovery_demand := int(ceil(1000.0 * Simulation.RECOVERY_FOOD_PER_CAPITA))
	_check(
		_approx(broken.morale, Combat.MORALE_RECOVER)
		and gs.cities[c2].food_storage == 100 - recovery_demand,
		"1000 人首月应耗 %d 粮并恢复 %.2f 士气，实为 morale=%.2f food=%d" % [
			recovery_demand,
			Combat.MORALE_RECOVER, broken.morale, gs.cities[c2].food_storage
		])
	_check(broken.state == Army.State.RECOVERING, "士气未满且城市有粮时必须继续驻守")

	while broken.state == Army.State.RECOVERING and guard < 60:
		sim._recover_morale()
		guard += 1
	_check(broken.state == Army.State.IDLE and _approx(broken.morale, 1.0),
		"士气回满后应解除驻守并转 IDLE，morale=%.2f state=%d" % [broken.morale, broken.state])

	# 对照：资源不足时按比例恢复，粮尽立即解除驻守，但保留未满士气。
	gs.armies.clear()
	var starved := _make_army(501, gs.cities[c2].owner_nation, 1000, 10)
	starved.morale = 0.0
	starved.state = Army.State.RECOVERING
	starved.location_city = c2
	starved.move_from = c2
	gs.armies.append(starved)
	_set_single_warehouse(gs, starved.owner_nation, c2, 2)
	sim._recover_morale()
	_check(gs.cities[c2].food_storage == 0, "恢复资源不足时应耗尽本城剩余粮食")
	_check(starved.state == Army.State.IDLE, "城内恢复资源耗尽后应解除强制驻守")
	_check(starved.morale > 0.0 and starved.morale < Combat.MORALE_RECOVER,
		"资源不足应按供给比例部分恢复，实为 %.3f" % starved.morale)

	# 城市恢复期间若易主，旧城主驻军必须被统一驱逐，不能滞留敌城。
	starved.state = Army.State.RECOVERING
	var old_owner := starved.owner_nation
	var historical_owner := gs.recognized_owner_of(c2)
	var captor := _make_army(502, (old_owner + 1) % GameState.NATION_COUNT, 1200, 10)
	gs.armies.append(captor)
	sim._capture_city(captor, gs.cities[c2])
	_check(starved.size <= 0 or starved.state == Army.State.RETREATING,
		"恢复驻军所在城市易主后应重新撤退（无友城则溃散），state=%d size=%d" % [starved.state, starved.size])
	_check(not (starved.state == Army.State.RECOVERING and gs.cities[c2].owner_nation != old_owner),
		"RECOVERING 军队不得滞留敌方城市")
	_check(
		gs.recognized_owner_of(c2) == historical_owner
		and gs.cities[c2].owner_nation != historical_owner,
		"占领只能改变当前归属，省份初始底色归属必须保持不变"
	)

	# 多支恢复驻军必须全部加入守城，5× 门槛基准取总兵力，而非只取第一支。
	gs.armies.clear()
	gs.battles.clear()
	var city_owner := gs.cities[c2].owner_nation
	var g1 := _make_army(503, city_owner, 300, 10)
	var g2 := _make_army(504, city_owner, 200, 10)
	for garrison in [g1, g2]:
		garrison.state = Army.State.RECOVERING
		garrison.location_city = c2
		garrison.move_from = c2
		gs.armies.append(garrison)
	var invader := _make_army(505, old_owner, 1000, 10)
	invader.move_from = c1
	invader.move_to = c2
	gs.armies.append(invader)
	sim._start_or_join_siege(invader, gs.cities[c2], edge)
	var recovery_siege: Battle = gs.battles[0]
	_check(recovery_siege.side_b.size() == 2, "两支 RECOVERING 驻军应全部加入守城")
	_check(recovery_siege.garrison_ref == 500, "守方基准应取全部驻军总兵力 500，实为 %d" % recovery_siege.garrison_ref)
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

	# 自由行军军队完全断粮：每月损失 0.20 士气；由 0.10 跌至 0 后应自动转溃逃。
	var hungry := _place_army_on_edge(gs, 600, nation, c1, c2, 0.4)
	hungry.morale = 0.10
	sim._resolve_supply()
	_check(_approx(hungry.morale, 0.0), "完全断粮应将 0.10 士气降至 0，实为 %.3f" % hungry.morale)
	_check(hungry.state == Army.State.RETREATING and hungry.forced_retreat,
		"自由军士气降至 0 后应自动进入溃逃状态")

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

	# 收复自己的法理城市不再重复普通征服围城：空城立即恢复，击败占领军后同日恢复。
	gs.armies.clear()
	gs.battles.clear()
	var legal_owner := gs.cities[from_city].owner_nation
	var occupier := (legal_owner + 1) % GameState.NATION_COUNT
	gs.cities[siege_city].owner_nation = occupier
	gs.recognized_city_owners[siege_city] = legal_owner
	gs.cities[siege_city].defense = 1000
	var weak_reclaimer := _make_army(
		702,
		legal_owner,
		1,
		10
	)
	weak_reclaimer.move_from = from_city
	weak_reclaimer.move_to = siege_city
	weak_reclaimer.location_city = from_city
	gs.armies.append(weak_reclaimer)
	var reclaim_view := AiWorldView.build(
		gs,
		legal_owner
	)
	var reclaim_candidate := UtilityAI._attack_candidate(
		reclaim_view,
		StrategicMapSnapshot.build(reclaim_view),
		ThreatField.build(reclaim_view),
		ArmyCoordinator.new(),
		weak_reclaimer,
		UtilityAI.ASSAULT_PARTICIPANT_MIN_RATIO
	)
	_check(
		reclaim_candidate != null
		and reclaim_candidate.kind
			== ActionCandidate.Kind.ATTACK
		and reclaim_candidate.target_city
			== siege_city,
		"AI应主动进攻无守军的本国法理城市"
	)
	sim._start_or_join_siege(
		weak_reclaimer,
		gs.cities[siege_city],
		road
	)
	_check(
		gs.cities[siege_city].owner_nation == legal_owner
		and weak_reclaimer.location_city == siege_city
		and gs.battles.is_empty(),
		"无守军的本国法理城市应立即收复，不受普通城防门槛阻挡"
	)

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
		gs.cities[siege_city].owner_nation == legal_owner
		and reclamation_battle.finished
		and reclaimer.location_city == siege_city,
		"击败占领军后应立即收复本国法理城市，不得胜而不占"
	)
	sim.free()

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
	siege.garrison_ref = 100
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
		siege.garrison_ref == 1000,
		"后到守军应更新围城守方兵力基准，实为 %d" % siege.garrison_ref
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

	var c1 := -1
	var c2 := -1
	for edge in gs.edges:
		if gs.cities[edge.city_a].owner_nation != gs.cities[edge.city_b].owner_nation:
			c1 = edge.city_a
			c2 = edge.city_b
			break
	# 保证 c1 的该敌对边是唯一高 danger 驻防候选。
	for neighbor in gs.neighbors(c1):
		gs.edge_of(c1, neighbor).danger = 0.0
	var hold_edge := gs.edge_of(c1, c2)
	hold_edge.danger = 0.9
	hold_edge.max_manpower = 45000
	gs.cities[c1].is_food_hub = true
	var holder := _make_army(800, gs.cities[c1].owner_nation, 1000, 10)
	holder.state = Army.State.IDLE
	holder.location_city = c1
	holder.move_from = c1
	gs.armies.append(holder)

	sim._ai_assign_targets()
	_check(holder.state == Army.State.MOVING and holder.move_to == c2,
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

	# 独立世界验证首都失守：30% 库存汇入胜方首都，败方从剩余城市迁都。
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
	sim.free()
	sim2.free()

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
	_check(battle.holding_side == 1 and _approx(battle.holding_days, 60.0),
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
	siege.garrison_ref = 10
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
	_check(third_party.state == Army.State.MOVING
		and third_party.move_from == target_city.id
		and third_party.move_to == source_city.id
		and _approx(third_party.move_progress, 0.0),
		"第三方抵达围城后应从目标城连续撤退；state=%d from=%d to=%d progress=%.3f"
			% [third_party.state, third_party.move_from, third_party.move_to, third_party.move_progress])

	# 重开游戏复用 Renderer 时必须丢弃旧世界位置快照，防止相同 army id 跨世界飞行。
	var renderer := MapRenderer.new()
	renderer._prev_pos = {0: Vector2(7.5, 7.5)}
	renderer._curr_pos = {0: Vector2(7.5, 7.5)}
	renderer._last_day = 99
	renderer.setup(gs, sim)
	_check(renderer._prev_pos.is_empty() and renderer._curr_pos.is_empty() and renderer._last_day == -1,
		"Renderer.setup 必须清空旧世界插值快照")
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
	_check(
		Simulation._ai_nation_ids_for_day(4, 0) == [0, 1, 2, 3]
		and Simulation._ai_nation_ids_for_day(4, 5) == [1, 2, 3, 0]
		and Simulation._ai_nation_ids_for_day(4, 15) == [3, 0, 1, 2]
		and Simulation._ai_nation_ids_for_day(4, 15, false)
			== [0, 1, 2, 3],
		"国家决策起点必须按AI决策轮次轮换，旧版固定顺序仅用于A/B"
	)
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
	var key01 := StrategicMapSnapshot._edge_key(0, 1)
	var key12 := StrategicMapSnapshot._edge_key(1, 2)
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
	threat = ThreatField.build(AiWorldView.build(gs, 0))
	_check(
		_approx(threat.threat_at(1), 0.0),
		"一万五满编敌军的威胁不得穿过五千容量道路"
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
	route_state.cities[1].defense = 1
	route_state.cities[2].defense = 1
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
	_check(
		anchor_merge == null
		and follower_merge != null
		and follower_merge.target_city == merge_anchor.location_city,
		"等战力跨城合并必须按军队ID形成单向偏序，禁止互相追逐成环"
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

	gs.armies.clear()
	var capital_id := gs.nations[0].capital_city_id
	var capital_guard := _make_army(934, 0, 4000, 10, 10)
	capital_guard.location_city = capital_id
	capital_guard.move_from = capital_id
	capital_guard.state = Army.State.IDLE
	var mobile := _make_army(935, 0, 6000, 10, 10)
	mobile.location_city = 0
	mobile.move_from = 0
	mobile.state = Army.State.IDLE
	gs.armies.append_array([capital_guard, mobile])
	for city in gs.cities_of(0):
		if city.id == capital_id:
			continue
		var local_guard := _make_army(
			9400 + city.id,
			0,
			15000,
			10,
			10
		)
		local_guard.location_city = city.id
		local_guard.move_from = city.id
		local_guard.state = Army.State.IDLE
		gs.armies.append(local_guard)
	view = AiWorldView.build(gs, 0)
	snapshot = StrategicMapSnapshot.build(view)
	threat = ThreatField.build(view)
	var guard_candidate := UtilityAI.choose(
		view, snapshot, threat, ArmyCoordinator.new(), capital_guard
	)
	_check(
		guard_candidate.kind == ActionCandidate.Kind.NONE
		and guard_candidate.reason.contains("最低守备"),
		"抽走后低于 5000 的首都守军必须拒绝普通移动命令"
	)
	var reinforce_candidate := UtilityAI.choose(
		view, snapshot, threat, ArmyCoordinator.new(), mobile
	)
	_check(
		reinforce_candidate.kind == ActionCandidate.Kind.REINFORCE
		and reinforce_candidate.target_city == capital_id,
		"首都守备不足时应生成定向增援：kind=%d target=%d capital=%d"
			% [reinforce_candidate.kind, reinforce_candidate.target_city, capital_id]
	)
	var distant_enemy_city := capital_id + 2
	gs.cities[distant_enemy_city].owner_nation = 1
	gs.edge_of(capital_id, capital_id + 1).max_manpower = 30000
	gs.edge_of(capital_id, capital_id + 1).distance = 1
	gs.edge_of(capital_id + 1, distant_enemy_city).max_manpower = 30000
	gs.edge_of(capital_id + 1, distant_enemy_city).distance = 1
	var distant_enemy := _make_army(936, 1, 12000, 12, 12)
	distant_enemy.location_city = distant_enemy_city
	distant_enemy.move_from = distant_enemy_city
	distant_enemy.state = Army.State.IDLE
	gs.armies.append(distant_enemy)
	view = AiWorldView.build(gs, 0)
	threat = ThreatField.build(view)
	var current_required := UtilityAI.required_logistics_garrison(
		view, snapshot, threat, capital_id
	)
	view.adaptive_garrison_enabled = false
	var legacy_required := UtilityAI.required_logistics_garrison(
		view, snapshot, threat, capital_id
	)
	_check(
		_approx(current_required, 5000.0) and legacy_required > current_required,
		"非前线首都不应把两跳外传播威胁全部折算为常驻军：new=%.1f old=%.1f"
			% [current_required, legacy_required]
	)

	var corridor_state := GameState.new()
	corridor_state.generate_grid_world(7003)
	corridor_state.armies.clear()
	for city in corridor_state.cities:
		city.owner_nation = 0
	corridor_state.cities[4].owner_nation = 1
	for corridor_edge in corridor_state.edges:
		corridor_edge.max_manpower = 0
	for pair in [[0, 1], [1, 2], [2, 3], [3, 4], [0, 8]]:
		var open_edge := corridor_state.edge_of(pair[0], pair[1])
		open_edge.max_manpower = 30000
		open_edge.distance = 1
		open_edge.danger = 0.1
	_set_single_warehouse(corridor_state, 0, 0, 5000)
	var warehouse_guard := _make_army(936, 0, 6000, 10, 10)
	warehouse_guard.location_city = 0
	warehouse_guard.move_from = 0
	var corridor_guard := _make_army(937, 0, 2000, 10, 10)
	corridor_guard.location_city = 2
	corridor_guard.move_from = 2
	var frontline_guard := _make_army(938, 0, 15000, 10, 10)
	frontline_guard.location_city = 3
	frontline_guard.move_from = 3
	var corridor_mobile := _make_army(939, 0, 4000, 10, 10)
	corridor_mobile.location_city = 8
	corridor_mobile.move_from = 8
	var corridor_main_force := _make_army(941, 0, 15000, 10, 10)
	corridor_main_force.location_city = 8
	corridor_main_force.move_from = 8
	var corridor_enemy := _make_army(940, 1, 20000, 10, 10)
	corridor_enemy.location_city = 4
	corridor_enemy.move_from = 4
	corridor_state.armies.append_array([
		warehouse_guard,
		corridor_guard,
		frontline_guard,
		corridor_mobile,
		corridor_enemy,
	])
	var corridor_view := AiWorldView.build(corridor_state, 0)
	var corridor_snapshot := StrategicMapSnapshot.build(corridor_view)
	var corridor_threat := ThreatField.build(corridor_view)
	_check(
		corridor_snapshot.critical_supply_cities.has(1)
		and corridor_snapshot.critical_supply_cities.has(2)
		and corridor_snapshot.supply_importance_at(2)
			>= UtilityAI.SUPPLY_CORRIDOR_MIN_IMPORTANCE,
		"粮仓到前线的唯一通路节点必须被识别为关键粮道"
	)
	var corridor_required := UtilityAI.required_logistics_garrison(
		corridor_view,
		corridor_snapshot,
		corridor_threat,
		2
	)
	_check(
		corridor_required > ArmyPower.effective(corridor_guard),
		"受威胁粮道节点应计算出超过现有守军的明确守备缺口"
	)
	var corridor_reinforcement := UtilityAI.choose(
		corridor_view,
		corridor_snapshot,
		corridor_threat,
		ArmyCoordinator.new(),
		corridor_mobile
	)
	_check(
		corridor_reinforcement.kind == ActionCandidate.Kind.REINFORCE
		and corridor_reinforcement.target_city in [1, 2]
		and corridor_reinforcement.reason.contains("粮道"),
		"前线已有守军时，后方机动军应增援即将被截断的内部粮道：kind=%d target=%d reason=%s"
			% [
				corridor_reinforcement.kind,
				corridor_reinforcement.target_city,
				corridor_reinforcement.reason,
			]
	)
	var main_force_order := UtilityAI.choose(
		corridor_view,
		corridor_snapshot,
		corridor_threat,
		ArmyCoordinator.new(),
		corridor_main_force
	)
	_check(
		not (
			main_force_order.kind == ActionCandidate.Kind.REINFORCE
			and main_force_order.target_city in [1, 2]
		),
		"内部粮道缺口不得抽调超过5000战力的前线主力"
	)
	corridor_view.supply_corridor_defense_enabled = false
	_check(
		UtilityAI.required_logistics_garrison(
			corridor_view,
			corridor_snapshot,
			corridor_threat,
			2
		) == 0.0,
		"A/B 当前 AI 对照开关应只关闭新增粮道守备需求"
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

func _test_ai_encirclement_breakout_and_relief() -> void:
	print("[30b] AI 包围协同：多方向进攻、断粮突围、紧急解围")
	var gs := GameState.new()
	gs.generate_grid_world(7030)
	gs.armies.clear()
	for city in gs.cities:
		city.owner_nation = 0
	var target_id := 18
	gs.cities[target_id].owner_nation = 1
	gs.cities[target_id].defense = 100
	_set_single_warehouse(gs, 0, 0, 5000)
	for neighbor in gs.neighbors(target_id):
		gs.edge_of(target_id, neighbor).max_manpower = 30000
	gs.edge_of(17, target_id).distance = 5
	gs.edge_of(19, target_id).distance = 1
	var holder_a := _make_army(940, 0, 400, 20, 20)
	holder_a.state = Army.State.HOLDING
	holder_a.location_city = 17
	holder_a.move_from = 17
	holder_a.move_to = target_id
	holder_a.move_progress = 0.5
	holder_a.on_edge = true
	var holder_b := _make_army(941, 0, 400, 20, 20)
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
	edge_guard_state.cities[guarded_target].defense = 1
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
	participant_state.cities[18].defense = 1
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
		[tiny_participant, assault_support] as Array[Army],
		participant_snapshot,
		false
	)
	var improved_order := Simulation._sort_ai_decision_order(
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
	breakout_state.cities[breakout_target].defense = 10
	var starving := _make_army(942, 0, 1000, 10, 10)
	starving.location_city = breakout_from
	starving.move_from = breakout_from
	starving.state = Army.State.IDLE
	starving.starving = true
	starving.supply_ratio = 0.0
	starving.morale = 0.2
	breakout_state.armies.append(starving)
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
	breakout_state.cities[breakout_target].defense = 100
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
	_check(gs.nations[nation_id].manpower_pool == expected_initial,
		"开局人口库应汇总本国城市储备：应 %d，实为 %d"
			% [expected_initial, gs.nations[nation_id].manpower_pool])
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
		initial_light_armies == 16 and initial_heavy_armies == 8,
		"初始军制应为16支5000编制军和8支15000编制军"
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
	sim._resolve_reinforcements()
	_check(holder.size == 1000 and gs.nations[nation_id].manpower_pool == 10,
		"当前边有敌军争夺时必须禁止边上补员")

	gs.armies.erase(enemy)
	holder.on_edge = false
	gs.armies.erase(holder)
	var capital_id := gs.nations[nation_id].capital_city_id
	gs.nations[nation_id].manpower_pool = 6000
	var created := sim._create_army_for_nation(nation_id, capital_id, "测试建军")
	_check(created != null and created.size == 5000 and created.max_size == 15000
		and gs.nations[nation_id].manpower_pool == 1000,
		"建军应消耗 5000 人并创建满编上限 15000 的军队")
	var pool_before_disband := gs.nations[nation_id].manpower_pool
	var created_size := created.size
	_check(sim._disband_army(created, "测试解散")
		and not gs.armies.has(created)
		and gs.nations[nation_id].manpower_pool == pool_before_disband + created_size,
		"解散应删除军队并把全部幸存人数返还全国人口库")

	var split_source := gs.create_army(
		nation_id,
		capital_id,
		13021
	)
	split_source.attack = 13
	split_source.defense = 14
	split_source.morale = 0.73
	var split_parts := gs.split_army(
		split_source,
		5000
	)
	var split_size_total := 0
	var split_capacity_total := 0
	var split_attributes_preserved := true
	for split_part in split_parts:
		split_size_total += split_part.size
		split_capacity_total += split_part.max_size
		split_attributes_preserved = (
			split_attributes_preserved
			and split_part.attack == 13
			and split_part.defense == 14
			and _approx(split_part.morale, 0.73)
		)
	_check(
		split_parts.size() == 3
		and split_size_total == 13021
		and split_capacity_total == 15000
		and split_attributes_preserved,
		"拆分应生成三支5000编制并保持兵力、编制和战斗属性守恒"
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
	var narrow_parts_valid := true
	for narrow_part in narrow_state.armies:
		if (
			narrow_part.owner_nation == 0
			and narrow_part.max_size != 5000
		):
			narrow_parts_valid = false
	_check(
		narrow_split_changed
		and narrow_state.active_army_count(0) == 3
		and narrow_parts_valid,
		"AI应在唯一进攻路线容量不足时主动拆分标准军"
	)
	narrow_army.state = Army.State.MOVING
	narrow_army.move_from = 0
	narrow_army.path = [1] as Array[int]
	narrow_sim._begin_next_leg(narrow_army)
	_check(
		narrow_army.on_edge
		and narrow_army.move_to == 1,
		"拆分后的五千编制军应能进入五千容量道路"
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
	var gs := GameState.new()
	gs.generate_grid_world(32001)
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
	_check(
		not (
			alliance_geometry["alliance"] as PackedVector2Array
		).is_empty(),
		"盟国接壤边界应生成独立青色联盟线段"
	)
	var nation_lines := MapRenderer.nation_detail_lines(gs, 0)
	_check(
		nation_lines.size() == 2
		and nation_lines[0].contains("金")
		and nation_lines[1].contains("粮")
		and nation_lines[1].contains("盟"),
		"国家详情卡必须独立展示财政、粮食和外交状态"
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
		and total_food_before - total_food_after == expected_allied_demand,
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
	settlement_city.owner_nation = 0
	encounter_state.ownership_revision += 1
	_check(
		encounter_state.recognized_owner_of(settlement_city.id) == 1,
		"战争期间实际控制与法理归属不同时应保持占领状态"
	)
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
		encounter_state.recognized_owner_of(settlement_city.id) == 0,
		"和平协议必须确认双方实际控制城市的领土转移，停止显示占领斜线"
	)
	encounter_sim.free()

	var ai_state := GameState.new()
	ai_state.generate_grid_world(32003)
	ai_state.day = DiplomacyAI.FORCED_PEACE_DAYS
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
	var sustainable_zero_treasury := DiplomacyAI.resource_report(ai_state, 0)
	_check(
		int(sustainable_zero_treasury["monthly_gold_balance"]) >= 0
		and bool(sustainable_zero_treasury["ready"])
		and not "、".join(
			DiplomacyAI.peace_reasons(ai_state, 0, 1)
		).contains("国库"),
		"月收入覆盖军费时，国库余额为0不得被误报为财政危机"
	)
	for city in ai_state.cities_of(0):
		city.gold_per_month = 0
	_check(
		not bool(DiplomacyAI.resource_report(ai_state, 0)["ready"])
		and DiplomacyAI.war_desire(ai_state, 0, 1) == -INF,
		"月现金流为负且国库不足六个月时不得宣战"
	)
	for city_id in original_gold_income:
		ai_state.cities[int(city_id)].gold_per_month = int(
			original_gold_income[city_id]
		)
	ai_state.nations[0].treasury_gold = treasury_before_crisis
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
			Simulation.offensive_preparation_multiplier(90),
			1.5
		)
		and _approx(
			Simulation.offensive_preparation_multiplier(180),
			2.0
		)
		and _approx(
			Simulation.offensive_preparation_multiplier(360),
			2.0
		),
		"攻势倍率必须从0天1倍线性增长，并在备战180天封顶2倍"
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
		objective_executed and first_wave_army != null,
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
		and first_wave_army.offensive_bonus_until_day
			== objective_state.day
				+ Simulation.OFFENSIVE_BONUS_DURATION_DAYS,
		"首轮参战军必须按实际备战天数获得持续30天的攻击加成"
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
		"战争持续时每90天应重新集结并发动下一轮国家级攻势"
	)
	_check(
		second_wave_army != null
		and _approx(
			second_wave_army.offensive_attack_multiplier,
			1.5
		),
		"间隔90天发动的后续攻势应获得1.5倍攻击倍率"
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
	if second_wave_army != null:
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
		and second_wave_army.offensive_bonus_until_day == -1,
		"攻势攻击加成必须在30天截止日清除"
	)
	objective_sim.free()

	var plan_state := GameState.new()
	plan_state.generate_grid_world(32006)
	plan_state.armies.clear()
	for city in plan_state.cities:
		city.owner_nation = 0
	var plan_origin := 9
	var plan_primary := 10
	var plan_secondary := 17
	plan_state.cities[plan_primary].owner_nation = 1
	plan_state.cities[plan_secondary].owner_nation = 1
	plan_state.edge_of(
		plan_origin,
		plan_primary
	).max_manpower = 30000
	plan_state.edge_of(
		plan_origin,
		plan_secondary
	).max_manpower = 30000
	plan_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
	)
	for plan_army_id in range(3):
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
		and plan_nation.campaign_plan_targets.size() == 2
		and plan_nation.campaign_plan_targets.has(
			plan_primary
		)
		and plan_nation.campaign_plan_targets.has(
			plan_secondary
		)
		and plan_nation.campaign_attack_assignments
			== frozen_assignments,
		"兵力足够时应生成并冻结主攻与第二方向的具体军队分工"
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
		and assignments_match_orders,
		"攻势执行必须逐军遵守计划中的目标城市，而非全部冲向主目标"
	)
	plan_sim.free()

	var echelon_state := GameState.new()
	echelon_state.generate_grid_world(32009)
	echelon_state.armies.clear()
	for city in echelon_state.cities:
		city.owner_nation = 0
	var echelon_origin := 9
	var echelon_target := 10
	echelon_state.cities[echelon_target].owner_nation = 1
	echelon_state.edge_of(
		echelon_origin,
		echelon_target
	).max_manpower = 30000
	echelon_state.set_diplomatic_relation(
		0,
		1,
		GameState.DiplomaticRelation.WAR
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
		),
		"持续攻势首轮只能投入最小充分梯队，后续梯队必须在出发地待命"
	)
	echelon_state.day += 1
	if lead_army != null:
		echelon_sim._retreat(lead_army)
	echelon_sim._advance_campaign_echelons()
	_check(
		lead_army != null
		and lead_army.state == Army.State.RETREATING
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
		"首攻梯队撤退后，下一梯队必须次日立即接替进攻而非等待90天"
	)
	_check(
		followup_army != null
		and _approx(
			followup_army.offensive_attack_multiplier,
			Simulation.offensive_preparation_multiplier(180)
		)
		and followup_army.offensive_bonus_until_day
			== echelon_state.day
				+ Simulation.OFFENSIVE_BONUS_DURATION_DAYS,
		"后续梯队应继承整轮备战倍率，并从实际投入日计算持续期"
	)
	echelon_sim.free()

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
		and not defense_state.is_enemy(3, 1)
		and not defense_state.is_enemy(3, 2),
		"共同防御只召唤被宣战方盟友，攻击方盟友不得加入主动战争"
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
	allied_origin.owner_nation = 0
	defense_sim._capture_city(allied_origin_army, enemy_target)
	defense_state.set_diplomatic_relation(
		0,
		3,
		GameState.DiplomaticRelation.NEUTRAL
	)
	var allied_legal_transfer := (
		defense_state.recognize_occupied_territory(0, 1)
	)
	_check(
		enemy_target.owner_nation == 3
		and allied_legal_transfer.has(enemy_target.id)
		and defense_state.recognized_owner_of(
			enemy_target.id
		) == 3,
		"从盟国领土出发的占领及和平后法理必须归出发地盟国"
	)
	defense_sim.free()

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

	ai_state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	ai_state.nations[0].treasury_gold = 0
	ai_state.nations[0].unpaid_war_cost = 20
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


# ------------------------------------------------------------------ 33. 和平裁军与潜在边境守备

func _test_peacetime_demobilization_and_border_defense() -> void:
	print("[33] 和平军备：30%编制、主动裁军屯粮、高威胁中立边境驻军")
	var gs := GameState.new()
	gs.generate_grid_world(33001)
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
	balance_state.cities[0].defense = 0
	balance_state.cities[1].defense = 0
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
			and reinforce.defensive_deployment
			and reinforce.reason.contains("高威胁中立国边境"),
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
		_check(
			hold != null
			and hold.kind == ActionCandidate.Kind.HOLD
			and snapshot.potential_threat_of_edge(
				border_army.location_city,
				hold.target_city
			) > 0.0
			and hold.reason.contains("驻边"),
			(
				"边境军应按统一防御姿态部署：%s posture=%d edge=%d"
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

	for city in gs.cities_of(0):
		city.food_per_half_year = 0
	for warehouse in gs.warehouse_cities_of(0):
		warehouse.food_storage = 0
	view = AiWorldView.build(gs, 0)
	snapshot = StrategicMapSnapshot.build(view)
	var food_before := sim._food_security_report(0)
	var troops_before := 0
	for army in view.friendly_armies:
		troops_before += army.size
	var manpower_before := gs.nations[0].manpower_pool
	var demobilized := sim._ai_manage_force_structure(
		view,
		snapshot,
		ThreatField.build(view)
	)
	var food_after := sim._food_security_report(0)
	var troops_after := 0
	for army in gs.armies:
		if army.owner_nation == 0:
			troops_after += army.size
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
		and budget_is_bounded
		and reason_recorded,
		(
			"粮食压力下应缩编、返还人力并控制粮耗：checks=%s/%s/%s/%s/%s "
			+ "troops=%d→%d "
			+ "manpower=%d→%d demand=%.1f→%.1f sustainable=%.1f production=%.1f reason=%s"
		) % [
			str(demobilized),
			str(troops_reduced),
			str(manpower_returned),
			str(demand_reduced),
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
	var mobilized := sim._ai_manage_force_structure(
		AiWorldView.build(gs, 0),
		StrategicMapSnapshot.build(AiWorldView.build(gs, 0)),
		ThreatField.build(AiWorldView.build(gs, 0))
	)
	_check(
		mobilized
		and gs.armies.size() == army_count_before + 1
		and gs.nations[0].ai_last_force_reason.contains("战争粮食动员"),
		"富粮国应在宣战后快速建立5000人动员军"
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


# ------------------------------------------------------------------ 工厂辅助

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
	for a in side_a:
		b.side_a.append(a)
	for a in side_b:
		b.side_b.append(a)
	return b


## 构造一场攻城：攻方在城墙(dist=L)、守军在城中(dist=0)，守军享 garrison 城防加成。
func _make_siege_battle(attackers: Array, defender: Army, garrison: int, distance: int) -> Battle:
	var b := Battle.new()
	b.id = 0
	b.kind = Battle.Kind.SIEGE
	b.edge = _make_edge(0.0, distance)
	b.city = City.new()
	b.city.defense = garrison
	b.has_garrison = true              # side_b 为驻城守军，享城防加成（combat 按此 gate）
	b.contact_dist_a = float(distance)
	b.contact_dist_b = 0.0
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


## 纯围城（无守军）：side_b 空、has_garrison=false。garrison_ref 为 5× 门槛分母。
func _make_pure_siege(attacker: Army, defense: int, distance: int, garrison_ref: int = -1) -> Battle:
	var b := Battle.new()
	b.id = 0
	b.kind = Battle.Kind.SIEGE
	b.edge = _make_edge(0.0, distance)
	b.city = City.new()
	b.city.id = 0
	b.city.owner_nation = 9          # 中立占位，_capture_city 会改写
	b.city.defense = defense
	b.city.food_storage = 100        # 有粮：不触发粮尽衰减
	b.has_garrison = false
	b.garrison_ref = garrison_ref if garrison_ref >= 0 else defense   # 默认空城以城防为基准
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
