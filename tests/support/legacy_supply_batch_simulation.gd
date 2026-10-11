extends Simulation
## Frozen pre-optimization supply scheduler, oracle only (2026-10-11).


func _precompute_supply_sources_over_frames() -> Dictionary:
	var payloads: Array[Dictionary] = []
	var chunk: Array[Army] = []
	const CHUNK_SIZE: int = 32
	for army in state.armies:
		if army.size <= 0 or army.state == Army.State.RECOVERING:
			continue
		var siege_garrison := _siege_garrison_battle_of(army)
		if siege_garrison != null and siege_garrison.city.food_storage > 0 and _succession_battle_context(siege_garrison) == null:
			continue
		chunk.append(army)
		if chunk.size() >= CHUNK_SIZE:
			payloads.append(_make_supply_source_job(chunk))
			chunk = [] as Array[Army]
	if not chunk.is_empty():
		payloads.append(_make_supply_source_job(chunk))
	if payloads.is_empty():
		return {}
	var task_ids: Array[int] = []
	for payload in payloads:
		task_ids.append(WorkerThreadPool.add_task(
			_compute_supply_source_job.bind(payload), false,
			"WorldWar supply sources"
		))
	while true:
		var complete := true
		for task_id in task_ids:
			if not WorkerThreadPool.is_task_completed(task_id):
				complete = false
				break
		if complete:
			break
		await get_tree().process_frame
	for task_id in task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	var result := {}
	for payload in payloads:
		for key in payload["results"] as Dictionary:
			result[key] = (payload["results"] as Dictionary)[key]
	return result


func _prepare_supply_network_caches() -> Array[int]:
	_daily_supply_source_cache.clear()
	_daily_food_multiplier_cache.clear()
	_battle_lookup_cache.clear()
	for battle in state.battles:
		_battle_lookup_cache[battle.id] = battle
	# 一次性预算共享依赖：被围城集合（O(B)）与各粮仓可用性，供逐国指纹复用，
	# 避免在指纹里逐粮仓 city_under_siege 的 O(B) 扫描退化成 O(城×B)。
	var besieged := state.besieged_city_ids()
	_invalidate_supply_city_sources_for_siege_changes(besieged)
	var active_nations := {}
	var occupied_edges_by_owner := {}
	for army in state.armies:
		if army.size <= 0:
			continue
		active_nations[army.owner_nation] = true
		if not army.on_edge or army.move_to < 0:
			continue
		if not occupied_edges_by_owner.has(army.owner_nation):
			occupied_edges_by_owner[army.owner_nation] = {}
		(occupied_edges_by_owner[army.owner_nation] as Dictionary)[
			GameState.edge_key(army.move_from, army.move_to)
		] = true
	var active_ids: Array[int] = []
	for nation_id_value in active_nations:
		active_ids.append(int(nation_id_value))
	active_ids.sort()
	_prepared_supply_blocked_edges.clear()
	if supply_network_cache_disabled:
		# 等价性守卫用：强制每天全量重建，复现指纹缓存前的旧行为。
		_daily_supply_network_cache.clear()
		_stable_supply_city_source_cache.clear()
	var warehouse_state := (
		{}
		if supply_network_cache_disabled
		else _supply_warehouse_availability(besieged)
	)
	for nation_id_value in active_ids:
		var nation_id := int(nation_id_value)
		var enemy_edges := {}
		for owner_id_value in occupied_edges_by_owner:
			var owner_id := int(owner_id_value)
			if not state.is_enemy(nation_id, owner_id) or state.succession_identity_pair(nation_id, owner_id):
				continue
			for edge_key_value in (
				occupied_edges_by_owner[owner_id]
				as Dictionary
			):
				enemy_edges[int(edge_key_value)] = true
		_prepared_supply_blocked_edges[nation_id] = (
			enemy_edges
		)
		if supply_network_cache_disabled:
			continue
		var fp := _supply_network_fingerprint(
			nation_id,
			warehouse_state,
			_supply_relevant_blocked_edges(nation_id, enemy_edges),
			besieged
		)
		# Switching into an active succession context restores conservative keys.
		fp.append(1 if not state.atlas_layout.is_empty() and state.succession_conflicts.is_empty() else 0)
		if _supply_network_fingerprints.get(nation_id, []) != fp:
			_daily_supply_network_cache.erase(nation_id)
			_stable_supply_city_source_cache.erase(nation_id)
			_supply_network_fingerprints[nation_id] = fp
	return active_ids


## Changes on roads the logistics search cannot enter cannot change its field.
## Filter the cache dependency only; actual searches retain all enemy blockers.


func _supply_network_fingerprint(
	nation_id: int,
	warehouse_state: Dictionary,
	enemy_edges: Dictionary,
	besieged: Dictionary,
	_owner_rows: Dictionary = {}
) -> Array[int]:
	return SupplyRules.network_fingerprint(
		state, nation_id, warehouse_state, enemy_edges, besieged
	)


## 预算各国可用粮仓（存量>0 且未被围）为 owner_id -> Array[city_id]，供逐国
## 指纹复用，避免每国重复遍历全部粮仓与逐粮仓 city_under_siege。


func _supply_relevant_blocked_edges(nation_id: int, enemy_edges: Dictionary) -> Dictionary:
	if state.atlas_layout.is_empty() or not state.succession_conflicts.is_empty():
		return enemy_edges
	var relevant := {}
	for key in enemy_edges:
		var edge: Edge = state.edge_lookup.get(key)
		if edge != null and edge.max_manpower > 0 and state.atlas_edge_access(edge,nation_id,-1,true):
			relevant[key] = true
	return relevant


## 真实运行路径在逐军计划前后台预热失效的国家级补给网络。旧路径把网络冷启动
## 隐藏在第一支军队的计划内，单次不可分割计算可阻塞主线程数十毫秒。任务期间
## GameState 冻结，各 worker 只写预分配结果数组中的独占索引；主线程完成后按
## 国家 ID 顺序提交。并发数取国家数、逻辑核数减一与 4 路上限的最小值。
