class_name ChronicleRules
extends RefCounted
## 只在政治事务最终结束时生成一次编年史文本。

static func begin_war(state: GameState, war_id: int, attackers: Array, defenders: Array) -> void:
	if state == null or war_id < 0:
		return
	if state.war_chronicle_contexts.has(war_id):
		var existing: Dictionary = state.war_chronicle_contexts[war_id]
		for value in attackers:
			var id := int(value)
			if id >= 0 and not existing["actor_ids"].has(id):
				existing["actor_ids"].append(id)
				if id < state.nations.size(): existing["actor_names"][id] = str(state.nations[id].name)
		for value in defenders:
			var id := int(value)
			if id >= 0 and not existing["target_ids"].has(id):
				existing["target_ids"].append(id)
				if id < state.nations.size(): existing["target_names"][id] = str(state.nations[id].name)
		existing["actor_ids"].sort(); existing["target_ids"].sort()
		state.war_chronicle_contexts[war_id] = existing
		return
	var actor_ids: Array[int] = []
	var target_ids: Array[int] = []
	for value in attackers:
		var id := int(value)
		if id >= 0 and not actor_ids.has(id): actor_ids.append(id)
	for value in defenders:
		var id := int(value)
		if id >= 0 and not target_ids.has(id): target_ids.append(id)
	actor_ids.sort(); target_ids.sort()
	var baseline := {}
	for city in state.cities:
		baseline[city.id] = state.recognized_owner_of(city.id)
	var actor_names := {}
	var target_names := {}
	for id in actor_ids:
		if id < state.nations.size(): actor_names[id] = str(state.nations[id].name)
	for id in target_ids:
		if id < state.nations.size(): target_names[id] = str(state.nations[id].name)
	state.war_chronicle_contexts[war_id] = {
		"war_id": war_id, "actor_ids": actor_ids, "target_ids": target_ids,
		"actor_names": actor_names, "target_names": target_names,
		"baseline_owners": baseline, "casualties_by_nation": {},
		"pending": false, "recorded": false
	}

static func add_war_members(state: GameState, war_id: int, attackers: Array, defenders: Array) -> void:
	begin_war(state, war_id, attackers, defenders)

static func merge_war(state: GameState, keep_id: int, merged_id: int) -> void:
	if state == null or keep_id < 0 or merged_id < 0 or keep_id == merged_id:
		return
	if not state.war_chronicle_contexts.has(merged_id):
		return
	if not state.war_chronicle_contexts.has(keep_id):
		state.war_chronicle_contexts[keep_id] = state.war_chronicle_contexts[merged_id]
		state.war_chronicle_contexts[keep_id]["war_id"] = keep_id
		state.war_chronicle_contexts.erase(merged_id)
		return
	var dst: Dictionary = state.war_chronicle_contexts[keep_id]
	var src: Dictionary = state.war_chronicle_contexts[merged_id]
	for key in ["actor_ids", "target_ids"]:
		for id in src.get(key, []):
			if not dst[key].has(id): dst[key].append(id)
		dst[key].sort()
	for key in ["actor_names", "target_names", "baseline_owners"]:
		for id in src.get(key, {}):
			if not dst[key].has(id): dst[key][id] = src[key][id]
	for id in src.get("casualties_by_nation", {}):
		dst["casualties_by_nation"][id] = int(dst["casualties_by_nation"].get(id, 0)) + int(src["casualties_by_nation"][id])
	state.war_chronicle_contexts[keep_id] = dst
	state.war_chronicle_contexts.erase(merged_id)

static func record_casualties(state: GameState, war_id: int, owner_id: int, amount: int) -> void:
	if amount <= 0 or not state.war_chronicle_contexts.has(war_id): return
	var ctx: Dictionary = state.war_chronicle_contexts[war_id]
	ctx["casualties_by_nation"][owner_id] = int(ctx["casualties_by_nation"].get(owner_id, 0)) + amount
	state.war_chronicle_contexts[war_id] = ctx

static func mark_pending(state: GameState, war_id: int) -> void:
	if war_id >= 0 and state.war_chronicle_contexts.has(war_id):
		state.war_chronicle_contexts[war_id]["pending"] = true
		if not state.chronicle_pending_war_ids.has(war_id): state.chronicle_pending_war_ids.append(war_id)

static func finalize_pending(state: GameState) -> void:
	if state == null: return
	var pending := state.chronicle_pending_war_ids.duplicate()
	state.chronicle_pending_war_ids.clear()
	for war_id_value in pending:
		var war_id := int(war_id_value)
		if not state.war_chronicle_contexts.has(war_id):
			continue
		if _war_still_exists(state, war_id) or not _war_resources_released(state, war_id):
			state.chronicle_pending_war_ids.append(war_id)
		else:
			finalize_war(state, war_id)

static func finalize_war(state: GameState, war_id: int) -> bool:
	if state == null or not state.war_chronicle_contexts.has(war_id) or _war_still_exists(state, war_id) or not _war_resources_released(state, war_id): return false
	var ctx: Dictionary = state.war_chronicle_contexts[war_id]
	if bool(ctx.get("recorded", false)): return false
	var actor_ids: Array = ctx.get("actor_ids", [])
	var target_ids: Array = ctx.get("target_ids", [])
	var taken: Array[String] = []
	var lost: Array[String] = []
	var actor_set := {}; var target_set := {}
	for id in actor_ids: actor_set[int(id)] = true
	for id in target_ids: target_set[int(id)] = true
	for city in state.cities:
		var before := int(ctx.get("baseline_owners", {}).get(city.id, -1))
		var after := state.recognized_owner_of(city.id)
		if before in target_set and after in actor_set and state.administrative_center_city_ids.has(city.id):
			taken.append(str(city.name))
		if before in actor_set and after in target_set and state.administrative_center_city_ids.has(city.id):
			lost.append(str(city.name))
	taken.sort(); lost.sort()
	var actor_name := _first_name(ctx.get("actor_names", {}), actor_ids)
	var target_name := _first_name(ctx.get("target_names", {}), target_ids)
	var enemy_losses := 0
	for id in target_ids: enemy_losses += int(ctx.get("casualties_by_nation", {}).get(int(id), 0))
	var actor_losses := 0
	for id in actor_ids: actor_losses += int(ctx.get("casualties_by_nation", {}).get(int(id), 0))
	var day := state.day
	var year := int(day / 360) + 1
	var views := {}
	var target_destroyed := _any_dead(state, target_ids)
	var actor_destroyed := _any_dead(state, actor_ids)
	# Gains and losses are measured separately so each country's view is correct.
	var actor_won := not taken.is_empty() or target_destroyed or (taken.is_empty() and lost.is_empty() and enemy_losses > actor_losses)
	var defender_won := not lost.is_empty() or actor_destroyed or (taken.is_empty() and lost.is_empty() and actor_losses > enemy_losses)
	var actor_destroyed_names := _dead_names(state, ctx.get("actor_names", {}), actor_ids)
	var target_destroyed_names := _dead_names(state, ctx.get("target_names", {}), target_ids)
	var actor_text := _compose_war_view(
		year, true, target_name, actor_won, enemy_losses, taken, lost,
		target_destroyed_names, false
	)
	var defender_text := _compose_war_view(
		year, false, actor_name, defender_won, actor_losses, lost, taken,
		actor_destroyed_names, false
	)
	var event := {"day": day, "year": year, "kind": "external_war", "war_id": war_id,
		"actor_ids": actor_ids.duplicate(), "target_ids": target_ids.duplicate(),
		"actor_name": actor_name, "target_names": _names_for_ids(ctx.get("target_names", {}), target_ids),
		"result": "victory" if actor_won else "defeat", "casualties": actor_losses + enemy_losses,
		"attacker_casualties": actor_losses, "defender_casualties": enemy_losses,
		"captured_centers": taken.duplicate(), "lost_centers": lost.duplicate(),
		"views": views}
	for id in actor_ids:
		var actor_view := _compose_war_view(
			year, true, target_name, actor_won, enemy_losses, taken, lost,
			target_destroyed_names,
			int(id) >= 0 and int(id) < state.nations.size() and not state.nations[int(id)].alive
		)
		views[int(id)] = actor_view
	for id in target_ids:
		var defender_view := _compose_war_view(
			year, false, actor_name, defender_won, actor_losses, lost, taken,
			actor_destroyed_names,
			int(id) >= 0 and int(id) < state.nations.size() and not state.nations[int(id)].alive
		)
		views[int(id)] = defender_view
	# 主文本与主动方第一个成员的视角完全一致；联盟中各国仍从自己的 views 读取。
	event["text"] = str(views.get(int(actor_ids[0]) if not actor_ids.is_empty() else -1, actor_text))
	state.chronicle_events.append(event)
	ctx["recorded"] = true
	state.war_chronicle_contexts.erase(war_id)
	return true

static func record_ultimatum(state: GameState, attacker_id: int, target_id: int, outcome: int, title: String = "", affected_members: Array = [], target_name_snapshot: String = "") -> void:
	if state == null or attacker_id < 0 or target_id < 0 or attacker_id >= state.nations.size() or target_id >= state.nations.size(): return
	var year := int(state.day / 360) + 1
	var target := target_name_snapshot if not target_name_snapshot.is_empty() else str(state.nations[target_id].name)
	var label := "纳土" if outcome == 2 else "称臣"
	var text := "%d年 威服%s，%s" % [year, target, label]
	if not title.is_empty(): text += "，封%s" % title
	var members: Array[int] = []
	for value in affected_members:
		var id := int(value)
		if id >= 0 and id < state.nations.size() and not members.has(id): members.append(id)
	if members.is_empty(): members = [target_id]
	var target_names: Array[String] = []
	for id in members: target_names.append(str(state.nations[id].name))
	if members.has(target_id):
		target_names[members.find(target_id)] = target
	state.chronicle_events.append({"day": state.day, "year": year, "kind": "ultimatum", "actor_ids": [attacker_id], "target_ids": members, "actor_name": str(state.nations[attacker_id].name), "target_names": target_names, "result": label, "text": text})

static func record_rebellion(state: GameState, rebel_id: int, parent_id: int, ruler_name: String, centers: Array[String], recognized: bool, sovereign_name: String) -> void:
	if state == null: return
	var year := int(state.day / 360) + 1
	var center_text := "、".join(centers)
	var text := "%d年 贼%s起%s州，%s" % [year, ruler_name, center_text, ("自号%s帝" % ruler_name) if recognized else "平"]
	if recognized and not sovereign_name.is_empty(): text = "%d年 贼%s起%s州，自号%s帝" % [year, ruler_name, center_text, sovereign_name]
	state.chronicle_events.append({"day": state.day, "year": year, "kind": "rebellion", "actor_ids": [rebel_id], "target_ids": [parent_id], "ruler_name": ruler_name, "captured_centers": centers.duplicate(), "result": "recognized" if recognized else "suppressed", "text": text})

static func record_rebellion_external_end(state: GameState, rebel_id: int, parent_id: int, ruler_name: String, centers: Array[String]) -> void:
	if state == null: return
	var year := int(state.day / 360) + 1
	state.chronicle_events.append({"day": state.day, "year": year, "kind": "rebellion", "actor_ids": [rebel_id], "target_ids": [parent_id], "ruler_name": ruler_name, "captured_centers": centers.duplicate(), "result": "external_end", "text": "%d年 贼%s起%s州，外部干扰结束" % [year, ruler_name, "、".join(centers)]})

static func _war_still_exists(state: GameState, war_id: int) -> bool:
	for value in state.war_relation_ids.values():
		if int(value) == war_id: return true
	return false

static func _war_resources_released(state: GameState, war_id: int) -> bool:
	for army in state.armies:
		if army.campaign_war_id == war_id:
			return false
	for front_value in state.campaign_fronts.values():
		var front := front_value as CoalitionCampaignFront
		if front != null and front.war_id == war_id:
			return false
	return true

static func _first_name(names: Dictionary, ids: Array) -> String:
	for id in ids:
		if names.has(int(id)): return str(names[int(id)])
	return "未知"

static func _names_for_ids(names: Dictionary, ids: Array) -> Array[String]:
	var result: Array[String] = []
	for id in ids:
		result.append(str(names.get(int(id), "")))
	return result

static func _dead_names(state: GameState, names: Dictionary, ids: Array) -> Array[String]:
	var result: Array[String] = []
	for value in ids:
		var id := int(value)
		if id < 0 or id >= state.nations.size() or state.nations[id].alive:
			continue
		var name := str(names.get(id, "未知"))
		if not name.is_empty() and not result.has(name):
			result.append(name)
	return result

static func _compose_war_view(
	year: int,
	is_attacker: bool,
	opponent_name: String,
	won: bool,
	enemy_losses: int,
	gained: Array[String],
	lost: Array[String],
	enemy_destroyed_names: Array[String],
	own_destroyed: bool
) -> String:
	var prefix := "%d年 征%s" % [year, opponent_name] if is_attacker else "%d年 %s伐我" % [year, opponent_name]
	var text := "%s，%s" % [prefix, "破之" if won else "败绩"]
	if enemy_losses > 0:
		text += "，斩敌%d" % enemy_losses
	if won and not gained.is_empty():
		text += "，取%s" % "、".join(gained)
	elif not won and not lost.is_empty():
		text += "，%s州陷" % "、".join(lost)
	for name in enemy_destroyed_names:
		text += " 灭%s为郡" % str(name)
	if own_destroyed:
		text += " 国除"
	return text

static func _any_dead(state: GameState, ids: Array) -> bool:
	for value in ids:
		var id := int(value)
		if id >= 0 and id < state.nations.size() and not state.nations[id].alive:
			return true
	return false
