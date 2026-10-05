class_name EmpireStatus
extends RefCounted
## 认可只在完整政治结算后调用；读取历史/财务/界面不会改变等级。

const COUNTRY := 0
const EMPIRE := 1

static func peaceful_root(state: GameState, nation_id: int) -> int:
	var visited := {}
	var current := nation_id
	while current >= 0 and current < state.nations.size() and state.suzerainty.has(current):
		if visited.has(current) or state.is_in_civil_war(current):
			return -1
		visited[current] = true
		current = int(state.suzerainty[current].overlord_id)
	return current if current >= 0 and current < state.nations.size() and state.nations[current].alive else -1

static func completed_regions(state: GameState) -> Dictionary:
	var roots := {}
	for nation in state.nations:
		roots[nation.id] = peaceful_root(state, nation.id)
	var regions := {}
	for city in state.cities:
		if city.is_dock or not city.politically_active or city.id >= state.region_ids.size():
			continue
		var region := int(state.region_ids[city.id])
		if region < 0:
			continue
		var controller := int(roots.get(city.owner_nation, -1))
		var legal := int(roots.get(state.recognized_owner_of(city.id), -1))
		var root_id := controller if controller == legal else -1
		if not regions.has(region):
			regions[region] = root_id
		elif int(regions[region]) != root_id:
			regions[region] = -1
	var result := {}
	for root_id in regions.values():
		if int(root_id) >= 0:
			result[root_id] = int(result.get(root_id, 0)) + 1
	return result

static func reconcile(state: GameState) -> void:
	if state == null or state.has_meta("historical_prince_reports"):
		return
	var completed := completed_regions(state)
	for nation in state.nations:
		if not nation.alive or nation.succession_identity or nation.state_level == EMPIRE or state.suzerainty.has(nation.id):
			continue
		if int(completed.get(nation.id, 0)) < 2 or nation.ruler_person_id < 0:
			continue
		nation.state_level = EMPIRE
		nation.empire_founder_person_id = nation.ruler_person_id
		nation.empire_recognized_day = state.day
		PrincePolitics.person(state, nation.id, nation.ruler_person_id)["taizu"] = true
		FamilyTree.record_current_title(state, nation.id)
		state.family_revision += 1
		state.chronicle_events.append({"day": state.day, "year": int(state.day / 360) + 1,
			"kind": "empire", "actor_ids": [nation.id], "target_ids": [],
			"person_id": nation.ruler_person_id, "actor_name": nation.name, "result": "recognized",
			"text": "%d年 %s整合两大贸易区域，晋为帝国，%s为太祖" % [int(state.day / 360) + 1, nation.name, nation.ruler_name]})
	RoyalTitles.reconcile(state)
