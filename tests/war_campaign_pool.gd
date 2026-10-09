extends SceneTree
## 集团战争池门禁：共享战线是唯一真源，军队所有权与每国调兵上限仍独立。

var _failures: Array[String] = []


func _init() -> void:
	_test_shared_front_binding_and_snapshot()
	_test_connected_allies_form_one_component()
	_test_shared_allocation_and_per_nation_limit()
	_test_dynamic_component_split()
	_test_allocation_without_front_uses_full_component()
	_test_merged_component_trims_extra_offensive_fronts()
	_test_chain_connected_allies_share_component()
	_test_nonborder_allies_keep_separate_components()
	_test_objective_owner_becomes_front_anchor()
	_test_completed_objective_is_not_recreated()
	_test_empty_front_stays_with_its_war_side()
	_test_annexed_army_leaves_old_war_pool()
	_test_restored_army_leaves_parent_war_pool()
	_test_eliminated_rebel_cannot_keep_zombie_war()
	_test_atomic_diplomacy_resynchronizes_war_index()
	if _failures.is_empty():
		print("WAR_CAMPAIGN_POOL_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WAR_CAMPAIGN_POOL_FAILED count=%d" % _failures.size())
	quit(1)


func _test_shared_front_binding_and_snapshot() -> void:
	var fixture := _connected_war_fixture(94140)
	if fixture.is_empty():
		_fail("无法构造接壤盟军战争夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var war_id := int(fixture["war_id"])
	var center_id := int(fixture["center_id"])
	var front := state.create_campaign_front(
		war_id, members, members[0],
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	var army := _army(941400, members[0], state.nations[members[0]].capital_city_id)
	state.armies.append(army)
	front.army_assignments[army.id] = center_id
	army.campaign_war_id = war_id
	army.campaign_front_id = front.front_id
	var snapshot := NativeSnapshotBuilder.build(state)
	var army_snapshot: Dictionary = snapshot["armies"]
	var front_snapshot: Dictionary = snapshot["campaign_fronts"]
	_check(state.campaign_assignment_center(army.id) == center_id,
		"军队必须通过 campaign_front_id 解析州绑定")
	_check((army_snapshot["campaign_front_id"] as PackedInt32Array)[-1] == front.front_id,
		"原生军队快照必须记录共享战线 ID")
	_check(int(front_snapshot["count"]) == 1,
		"原生快照必须全局记录共享战线且不按参与国复制")
	_check((front_snapshot["participant_ids"] as PackedInt32Array).size() == members.size(),
		"共享战线快照必须记录全部参与国")


func _test_connected_allies_form_one_component() -> void:
	var fixture := _connected_war_fixture(94141)
	if fixture.is_empty():
		_fail("无法构造连通分量夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var war_id := int(fixture["war_id"])
	var matching: Array[Dictionary] = []
	for component in state.coalition_campaign_components(war_id):
		if (component["members"] as Array[int]).has(members[0]):
			matching.append(component)
	_check(matching.size() == 1, "同一战争中的接壤盟友必须只出现于一个连通分量")
	if matching.size() == 1:
		_check(matching[0]["members"] == members,
			"接壤盟友必须共享同一连通分量，不能各自生成战争目标")


func _test_shared_allocation_and_per_nation_limit() -> void:
	var fixture := _connected_war_fixture(94142)
	if fixture.is_empty():
		_fail("无法构造集团分兵夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var enemy_id := int(fixture["enemy_id"])
	var war_id := int(fixture["war_id"])
	var defense_center := state.administrative_center_of(
		state.nations[members[0]].capital_city_id
	)
	var front := state.create_campaign_front(
		war_id, members, members[0],
		CoalitionCampaignFront.Mode.DEFENSE, defense_center
	)
	for index in range(8):
		state.armies.append(_army(941500 + index, enemy_id, defense_center))
	for member_id in members:
		for index in range(6):
			state.armies.append(_army(
				942000 + member_id * 20 + index, member_id, defense_center
			))
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var component: Dictionary = {}
	for value in state.coalition_campaign_components(war_id):
		if (value["members"] as Array[int]).has(members[0]):
			component = value
			break
	_check(not component.is_empty(), "集团分兵前必须找到战争连通分量")
	if not component.is_empty():
		sim._allocate_coalition_fronts(component)
	var assigned_by_owner := {}
	for army in state.armies:
		if army.campaign_front_id == front.front_id:
			assigned_by_owner[army.owner_nation] = int(
				assigned_by_owner.get(army.owner_nation, 0)
			) + 1
	var assigned_total := 0
	for count_value in assigned_by_owner.values():
		assigned_total += int(count_value)
	var required := sim._front_requirement(front)
	_check(assigned_total == ceili(float(required) / GameState.INITIAL_HEAVY_ARMY_SIZE),
		"首次动员必须同轮补足一次共享需求，不逐国重复补满")
	var exceeds_transfer_quota := false
	for member_id in members:
		if int(assigned_by_owner.get(member_id, 0)) > 3:
			exceeds_transfer_quota = true
		_check(int(assigned_by_owner.get(member_id, 0)) <= 6,
			"首次动员只能使用本国实际拥有的六军")
		_check(int(assigned_by_owner.get(member_id, 0)) > 0,
			"共享防守缺口必须允许接壤盟军共同补足")
	_check(exceeds_transfer_quota,
		"无绑定预备军首次动员不受活跃战线三军改派限制")
	var report_a := state.coalition_campaign_allocation(war_id, members[0])
	var report_b := state.coalition_campaign_allocation(war_id, members[1])
	_check(int(report_a["war_pool_total"]) == int(report_b["war_pool_total"]),
		"同一连通分量成员必须读取同一集团战争池总量")
	_check((report_a["fronts"] as Dictionary).size() == 1,
		"共享州只允许存在一份集团战线需求")
	sim.free()


func _test_dynamic_component_split() -> void:
	var fixture := _connected_war_fixture(94143)
	if fixture.is_empty():
		_fail("无法构造动态拆分夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var war_id := int(fixture["war_id"])
	var center_id := int(fixture["center_id"])
	var front := state.create_campaign_front(
		war_id, members, members[0],
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	for index in range(2):
		var army := _army(
			943000 + index, members[1], state.nations[members[1]].capital_city_id
		)
		state.armies.append(army)
		front.army_assignments[army.id] = center_id
		army.campaign_war_id = war_id
		army.campaign_front_id = front.front_id
	state.set_diplomatic_relation(
		members[0], members[1], GameState.DiplomaticRelation.NEUTRAL
	)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._reconcile_coalition_fronts(state.coalition_campaign_components(war_id))
	_check(front.participant_nation_ids == [members[1]],
		"联盟拆分后进攻战线必须由已绑定兵力最多的分量继承")
	for army in state.armies:
		if army.owner_nation == members[1]:
			_check(army.campaign_front_id == front.front_id,
				"继承分量的军队绑定不得丢失")
	sim.free()


func _test_allocation_without_front_uses_full_component() -> void:
	var fixture := _connected_war_fixture(94144)
	if fixture.is_empty():
		_fail("无法构造无战线集团报告夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var report := state.coalition_campaign_allocation(
		int(fixture["war_id"]), members[0]
	)
	_check(report["component_members"] == members,
		"尚未建立战线时，集团报告仍必须返回完整连通分量")


func _test_merged_component_trims_extra_offensive_fronts() -> void:
	var fixture := _connected_war_fixture(94145)
	if fixture.is_empty():
		_fail("无法构造集团战线裁剪夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var war_id := int(fixture["war_id"])
	var enemy_id := int(fixture["enemy_id"])
	var centers: Array[int] = []
	for city in state.cities:
		if (
			state.is_zhou_city(city.id)
			and city.owner_nation not in members
		):
			state.transfer_city_sovereignty(
				city.id, enemy_id, "集团战线裁剪夹具"
			)
			centers.append(city.id)
			if centers.size() == 3:
				break
	if centers.size() < 3:
		return
	var armies: Array[Army] = []
	for index in range(3):
		var front := state.create_campaign_front(
			war_id, members, members[0],
			CoalitionCampaignFront.Mode.OFFENSE, centers[index]
		)
		var owner_id := members[index % members.size()]
		var army := _army(
			944000 + index, owner_id,
			state.nations[owner_id].capital_city_id
		)
		state.armies.append(army)
		front.army_assignments[army.id] = centers[index]
		army.campaign_war_id = war_id
		army.campaign_front_id = front.front_id
		armies.append(army)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._reconcile_coalition_fronts(
		state.coalition_campaign_components(war_id)
	)
	state.sync_campaign_pairs(state.coalition_campaign_components(war_id))
	sim._reconcile_campaign_battlefields()
	var remaining := state.campaign_fronts_for_nation(
		members[0], war_id, CoalitionCampaignFront.Mode.OFFENSE
	)
	_check(remaining.size() == 2,
		"同一敌对集合对合并后最多只能保留两个共享州战场")
	var released := 0
	for army in armies:
		if army.campaign_front_id < 0:
			released += 1
			_check(army.campaign_war_id == war_id,
				"裁剪多余战线时必须保留军队的战争池绑定")
	_check(released == 1, "第三条进攻线的军队必须回到集团战争池")
	sim.free()


func _test_chain_connected_allies_share_component() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(94146, 12, 96)
	_neutralize(state)
	var neighbors := _nation_border_neighbors(state)
	var chain: Array[int] = []
	for middle_value in neighbors:
		var middle := int(middle_value)
		var adjacent: Array = (neighbors[middle] as Dictionary).keys()
		adjacent.sort()
		if adjacent.size() >= 2:
			chain = [int(adjacent[0]), middle, int(adjacent[1])] as Array[int]
			break
	if chain.is_empty():
		_fail("无法构造A-B-C链式接壤夹具")
		return
	var enemy_id := _nation_outside(state, chain)
	if enemy_id < 0:
		_fail("链式接壤夹具缺少共同敌国")
		return
	state.set_diplomatic_relation(
		chain[0], chain[1], GameState.DiplomaticRelation.ALLIED
	)
	state.set_diplomatic_relation(
		chain[1], chain[2], GameState.DiplomaticRelation.ALLIED
	)
	var war_id := -1
	for member_id in chain:
		state.set_diplomatic_relation(
			member_id, enemy_id, GameState.DiplomaticRelation.WAR
		)
		var member_war_id := state.war_id_between(member_id, enemy_id)
		if war_id < 0:
			war_id = member_war_id
		else:
			state.merge_war_ids(war_id, member_war_id)
	chain.sort()
	var matched := false
	for component in state.coalition_campaign_components(war_id):
		if (component["members"] as Array[int]) == chain:
			matched = true
			break
	_check(matched, "A-B-C链式接壤盟国必须形成一个共享战线分量")


func _test_nonborder_allies_keep_separate_components() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(94147, 12, 96)
	_neutralize(state)
	var neighbors := _nation_border_neighbors(state)
	var pair := Vector2i(-1, -1)
	for nation_a in range(state.nations.size()):
		if not state.nations[nation_a].alive:
			continue
		for nation_b in range(nation_a + 1, state.nations.size()):
			if (
				state.nations[nation_b].alive
				and not (neighbors.get(nation_a, {}) as Dictionary).has(nation_b)
			):
				pair = Vector2i(nation_a, nation_b)
				break
		if pair.x >= 0:
			break
	if pair.x < 0:
		_fail("无法构造不接壤盟国夹具")
		return
	var members: Array[int] = [pair.x, pair.y]
	var enemy_id := _nation_outside(state, members)
	if enemy_id < 0:
		_fail("不接壤盟国夹具缺少共同敌国")
		return
	state.set_diplomatic_relation(
		pair.x, pair.y, GameState.DiplomaticRelation.ALLIED
	)
	var war_id := -1
	for member_id in members:
		state.set_diplomatic_relation(
			member_id, enemy_id, GameState.DiplomaticRelation.WAR
		)
		var member_war_id := state.war_id_between(member_id, enemy_id)
		if war_id < 0:
			war_id = member_war_id
		else:
			state.merge_war_ids(war_id, member_war_id)
	var member_components := 0
	for component in state.coalition_campaign_components(war_id):
		var component_members: Array[int] = component["members"]
		if component_members.has(pair.x) or component_members.has(pair.y):
			member_components += 1
			_check(component_members.size() == 1,
				"不接壤盟国不得共享州战线和战争兵力池")
	_check(member_components == 2, "不接壤盟国必须各自维护独立连通分量")


func _test_objective_owner_becomes_front_anchor() -> void:
	var fixture := _connected_war_fixture(94148)
	if fixture.is_empty():
		_fail("无法构造集团目标锚点夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var enemy_id := int(fixture["enemy_id"])
	var war_id := int(fixture["war_id"])
	state.clear_war_objective(members[0], enemy_id)
	# This fixture tests route ownership, not a randomly generated ruler's war veto.
	state.nations[members[1]].ruler_archetype = RulerProfile.BALANCED
	state.nations[members[1]].ruler_traits.clear()
	state.nations[members[1]].strategic_region_anchor_city_id = int(fixture["center_id"])
	var entry_id := int(fixture["center_id"])
	for city_id in state.administrative_members(entry_id):
		if city_id != entry_id and not state.cities[city_id].is_dock and state.cities[city_id].owner_nation == enemy_id:
			entry_id = city_id
			break
	# Anchor selection needs a real frontier, not only a diplomatic label.
	state._add_edge(state.nations[members[1]].capital_city_id, entry_id)
	state.road_network_revision += 1
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var component: Dictionary = {}
	for candidate in state.coalition_campaign_components(war_id):
		if (candidate["members"] as Array[int]) == members:
			component = candidate
			break
	var objective := sim._select_component_objective(
		component, {}, {}
	)
	_check(int(objective.get("anchor_nation_id", -1)) == members[1],
		"共享目标必须保留实际提出目标的成员国作为路线锚点")
	var staged_army := _army(945800, members[1], state.nations[members[1]].capital_city_id)
	state.armies.append(staged_army)
	sim._plan_coalition_component(component, [] as Array[int], {})
	var fronts := state.campaign_fronts_for_nation(
		members[0], war_id, CoalitionCampaignFront.Mode.OFFENSE
	)
	_check(not fronts.is_empty() and fronts[0].anchor_nation_id == members[1],
		"共享战线入口和集结点必须使用目标提出国，而非成员排序第一国")
	sim.free()


func _test_completed_objective_is_not_recreated() -> void:
	var fixture := _connected_war_fixture(94149)
	if fixture.is_empty():
		_fail("无法构造已完成州战线生命周期夹具")
		return
	var state: GameState = fixture["state"]
	var members: Array[int] = fixture["members"]
	var enemy_id := int(fixture["enemy_id"])
	var war_id := int(fixture["war_id"])
	var center_id := int(fixture["center_id"])
	for city_id in state.administrative_members(center_id):
		state.cities[city_id].owner_nation = members[0]
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	var component: Dictionary = {}
	for candidate in state.coalition_campaign_components(war_id):
		if (candidate["members"] as Array[int]) == members:
			component = candidate
			break
	_check(not component.is_empty(), "已完成州测试必须找到战争连通分量")
	if component.is_empty():
		sim.free()
		return
	var cache_key := "%d:[]" % enemy_id
	var objective_cache := {
		cache_key: {
			"city_id": center_id,
			"administrative_center_city_id": center_id,
			"value": 1000.0,
		},
	}
	var selected := sim._select_component_objective(
		component, objective_cache, {}
	)
	_check(
		int(selected.get("administrative_center_city_id", -1)) != center_id,
		"普通目标评分不得重新选择已经肃清的州",
	)
	var obsolete := state.create_campaign_front(
		war_id, members, members[0],
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	sim._plan_coalition_component(component, [] as Array[int], objective_cache)
	var first_replacement := state.campaign_front_for(
		members[0], center_id, CoalitionCampaignFront.Mode.OFFENSE, war_id
	)
	sim._plan_coalition_component(component, [] as Array[int], objective_cache)
	var second_replacement := state.campaign_front_for(
		members[0], center_id, CoalitionCampaignFront.Mode.OFFENSE, war_id
	)
	_check(state.campaign_front(obsolete.front_id) == null,
		"已完成州的旧战线必须被释放")
	_check(first_replacement == null and second_replacement == null,
		"已完成州不得在后续规划中反复重建战线")
	sim.free()


func _test_empty_front_stays_with_its_war_side() -> void:
	var fixture := _connected_war_fixture(94150)
	if fixture.is_empty():
		_fail("无法构造空战线阵营归属夹具")
		return
	var state: GameState = fixture["state"]
	var war_id := int(fixture["war_id"])
	var components := state.coalition_campaign_components(war_id)
	_check(components.size() >= 2, "阵营归属测试必须包含交战双方分量")
	if components.size() < 2:
		return
	var owner_component: Dictionary = components[-1]
	var members: Array[int] = owner_component["members"]
	var enemy_ids: Array[int] = owner_component["enemy_ids"]
	var center_id := -1
	for city in state.cities:
		if state.is_zhou_city(city.id) and enemy_ids.has(city.owner_nation):
			center_id = city.id
			break
	_check(center_id >= 0, "空战线阵营归属夹具必须找到敌方目标州")
	if center_id < 0:
		return
	var front := state.create_campaign_front(
		war_id, members, members[0],
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	var sim := Simulation.new()
	root.add_child(sim)
	sim.setup(state)
	sim._reconcile_coalition_fronts(components)
	_check(state.campaign_front(front.front_id) != null,
		"尚未分到军队的合法进攻线不得在阵营调和时被删除")
	_check(front.participant_nation_ids == members,
		"尚未分到军队的进攻线不得被迁移到敌对阵营")
	sim.free()


func _test_annexed_army_leaves_old_war_pool() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(94151, 8, 48)
	state.armies.clear()
	state.battles.clear()
	state.clear_campaign_fronts()
	_neutralize(state)
	var old_owner := 1
	var absorber := 2
	var enemy_id := 0
	state.set_diplomatic_relation(
		old_owner, enemy_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.war_id_between(old_owner, enemy_id)
	var center_id := state.administrative_center_of(
		state.nations[enemy_id].capital_city_id
	)
	var front := state.create_campaign_front(
		war_id, [old_owner] as Array[int], old_owner,
		CoalitionCampaignFront.Mode.OFFENSE, center_id
	)
	var army := _army(
		941510, old_owner, state.nations[old_owner].capital_city_id
	)
	army.campaign_war_id = war_id
	army.campaign_front_id = front.front_id
	front.army_assignments[army.id] = center_id
	state.armies.append(army)
	state.finalize_annexation_after_territory_commit(absorber, old_owner)
	_check(army.owner_nation == absorber,
		"兼并后被兼并国军队必须转归兼并国")
	_check(army.campaign_war_id == -1 and army.campaign_front_id == -1,
		"兼并军队不得继承被兼并国的旧战争池或州战线绑定")
	_check(not front.army_assignments.has(army.id),
		"兼并军队必须从旧共享战线的军队索引中移除")


func _test_restored_army_leaves_parent_war_pool() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(94152, 8, 48)
	state.armies.clear()
	state.battles.clear()
	state.clear_campaign_fronts()
	_neutralize(state)
	var parent_id := -1
	var restore_city: City = null
	for nation in state.nations:
		for city in state.land_cities_of(nation.id):
			if not city.is_capital:
				parent_id = nation.id
				restore_city = city
				break
		if restore_city != null:
			break
	_check(restore_city != null, "忠诚恢复战争池夹具必须找到非首都陆城")
	if restore_city == null:
		return
	preload("res://tests/state_rebellion_fixture.gd").isolate_city_as_state(state, restore_city.id)
	var target_id := _nation_outside(state, [parent_id] as Array[int])
	var enemy_id := _nation_outside(
		state, [parent_id, target_id] as Array[int]
	)
	_check(target_id >= 0 and enemy_id >= 0,
		"忠诚恢复战争池夹具必须找到目标国和原敌国")
	if target_id < 0 or enemy_id < 0:
		return
	state.set_diplomatic_relation(
		parent_id, enemy_id, GameState.DiplomaticRelation.WAR
	)
	var old_war_id := state.war_id_between(parent_id, enemy_id)
	var enemy_center := state.administrative_center_of(
		state.nations[enemy_id].capital_city_id
	)
	var front := state.create_campaign_front(
		old_war_id, [parent_id] as Array[int], parent_id,
		CoalitionCampaignFront.Mode.OFFENSE, enemy_center
	)
	var army := _army(941520, parent_id, restore_city.id)
	army.campaign_war_id = old_war_id
	army.campaign_front_id = front.front_id
	front.army_assignments[army.id] = enemy_center
	state.armies.append(army)
	restore_city.loyalty_target_nation = target_id
	var restored := state.restore_regional_loyalty_target(
		parent_id, target_id, [restore_city.id] as Array[int]
	)
	_check(restored and army.owner_nation == target_id,
		"忠诚恢复必须让当地驻军随城市转归目标国")
	_check(army.campaign_war_id == -1 and army.campaign_front_id == -1,
		"归附军队不得把母国的旧战争池和州战线带给目标国")
	_check(not front.army_assignments.has(army.id),
		"归附军队必须从母国旧战线索引中移除")


func _test_eliminated_rebel_cannot_keep_zombie_war() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(94153, 8, 48)
	state.armies.clear()
	state.battles.clear()
	state.clear_campaign_fronts()
	_neutralize(state)
	var parent_id := 0
	var rebel_id := 1
	state.rebellions[rebel_id] = {
		"parent_id": parent_id,
		"started_day": -1000,
		"core_city_ids": [] as Array[int],
		"recognized": false,
		"active": true,
		"reason": "僵尸战争回归夹具",
	}
	state.set_diplomatic_relation(
		parent_id, rebel_id, GameState.DiplomaticRelation.WAR
	)
	var war_id := state.war_id_between(parent_id, rebel_id)
	var operations: Array[Dictionary] = []
	for city in state.cities:
		if city.owner_nation == rebel_id:
			operations.append({
				"city_id": city.id,
				"controller_id": parent_id,
				"legal_owner_id": parent_id,
				"sponsor_id": -1,
				"reset_political_target": true,
				"reason": "eliminated_rebel_war_cleanup_fixture",
				"stock_policy": (
					GameState.TerritoryStockDisposition.MOVE_TO_NEW_POOL
				),
			})
	var transaction := state.apply_territory_transaction(
		operations, {}, state.ownership_revision, null,
		[{
			"nation_a": parent_id,
			"nation_b": rebel_id,
			"relation": GameState.DiplomaticRelation.NEUTRAL,
			"truce_days": GameState.DEFAULT_TRUCE_DAYS,
		}] as Array[Dictionary],
		state.diplomacy_revision,
	)
	_check(bool(transaction.get("ok", false)),
		"灭国领土事务必须成功同步战争关系索引：%s"
			% str(transaction.get("error", "")))
	_check(not state.nations[rebel_id].alive,
		"灭国领土事务提交后地方叛军必须完全失去陆城")
	_check(not state.is_enemy(parent_id, rebel_id),
		"地方叛军灭亡后必须当天结束与母国的战争关系")
	_check(state.war_id_between(parent_id, rebel_id) == -1,
		"灭亡叛军的战争边不得继续保留 war_id")
	_check(not state.war_relation_ids.values().has(war_id),
		"没有其他参战边时必须释放灭亡叛军的整个战争池")


func _test_atomic_diplomacy_resynchronizes_war_index() -> void:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(94154, 8, 48)
	_neutralize(state)
	state.set_diplomatic_relation(0, 1, GameState.DiplomaticRelation.WAR)
	var stale_war_id := state.war_id_between(0, 1)
	state.diplomatic_relations["0:1"] = GameState.DiplomaticRelation.NEUTRAL
	var transaction := state.apply_territory_transaction(
		[] as Array[Dictionary], {}, state.ownership_revision, null,
		[{
			"nation_a": 2,
			"nation_b": 3,
			"relation": GameState.DiplomaticRelation.ALLIED,
		}] as Array[Dictionary],
		state.diplomacy_revision,
	)
	_check(bool(transaction.get("ok", false)),
		"原子外交同步战争索引夹具必须成功提交")
	_check(state.war_id_between(0, 1) == -1,
		"原子外交提交必须以当前关系图清除中立边上的陈旧 war_id")
	_check(not state.war_relation_ids.values().has(stale_war_id),
		"没有其他战争边引用时必须释放陈旧战争池")


func _neutralize(state: GameState) -> void:
	for nation_a in range(state.nations.size()):
		for nation_b in range(nation_a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				nation_a, nation_b, GameState.DiplomaticRelation.NEUTRAL
			)


func _nation_border_neighbors(state: GameState) -> Dictionary:
	var result := {}
	for pair in state.territorial_border_pairs():
		var owner_a := state.cities[pair.x].owner_nation
		var owner_b := state.cities[pair.y].owner_nation
		if owner_a < 0 or owner_b < 0 or owner_a == owner_b:
			continue
		if not result.has(owner_a):
			result[owner_a] = {}
		if not result.has(owner_b):
			result[owner_b] = {}
		(result[owner_a] as Dictionary)[owner_b] = true
		(result[owner_b] as Dictionary)[owner_a] = true
	return result


func _nation_outside(state: GameState, excluded: Array[int]) -> int:
	for nation in state.nations:
		if nation.alive and nation.id not in excluded:
			return nation.id
	return -1


func _connected_war_fixture(seed: int) -> Dictionary:
	var state := preload("res://tests/support/grid_world.gd").new()
	state.generate_world(seed, 8, 48)
	state.armies.clear()
	state.battles.clear()
	state.clear_campaign_fronts()
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(a, b, GameState.DiplomaticRelation.NEUTRAL)
	var pair := Vector2i(-1, -1)
	for contact in state.territorial_border_pairs():
		var owner_a := state.cities[contact.x].owner_nation
		var owner_b := state.cities[contact.y].owner_nation
		if owner_a >= 0 and owner_b >= 0 and owner_a != owner_b:
			pair = Vector2i(owner_a, owner_b)
			break
	if pair.x < 0:
			return {}
	var enemy_id := -1
	for nation in state.nations:
		if nation.id not in [pair.x, pair.y] and nation.alive:
			enemy_id = nation.id
			break
	if enemy_id < 0:
			return {}
	state.set_diplomatic_relation(pair.x, pair.y, GameState.DiplomaticRelation.ALLIED)
	state.set_diplomatic_relation(pair.x, enemy_id, GameState.DiplomaticRelation.WAR)
	var war_id := state.war_id_between(pair.x, enemy_id)
	state.set_diplomatic_relation(pair.y, enemy_id, GameState.DiplomaticRelation.WAR)
	state.merge_war_ids(war_id, state.war_id_between(pair.y, enemy_id))
	var center_id := state.administrative_center_of(
		state.nations[enemy_id].capital_city_id
	)
	state.set_war_objective(pair.x, enemy_id, center_id, "集团战线门禁", war_id)
	state.set_war_objective(pair.y, enemy_id, center_id, "集团战线门禁", war_id)
	var members: Array[int] = [pair.x, pair.y]
	members.sort()
	return {
		"state": state,
		"members": members,
		"enemy_id": enemy_id,
		"war_id": war_id,
		"center_id": center_id,
	}


func _army(id: int, owner_id: int, city_id: int) -> Army:
	var army := Army.new()
	army.id = id
	army.owner_nation = owner_id
	army.size = 15000
	army.max_size = 15000
	army.location_city = city_id
	army.move_from = city_id
	army.state = Army.State.IDLE
	army.morale = army.max_morale
	army.supply_ratio = 1.0
	return army


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
