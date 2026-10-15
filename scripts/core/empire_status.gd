class_name EmpireStatus
extends RefCounted
## 认可只在完整政治结算后调用；读取历史/财务/界面不会改变等级。

const COUNTRY := 0
const EMPIRE := 1
const REQUIRED_TRADE_REGIONS := 1
const CORE_GARRISON_MULTIPLIER := 2

static func peaceful_root(state: GameState, nation_id: int) -> int:
	var visited := {}
	var current := nation_id
	while current >= 0 and current < state.nations.size():
		if visited.has(current) or not state.nations[current].alive or state.nations[current].succession_identity:
			return -1
		if not state.suzerainty.has(current):
			return current
		if state.is_in_civil_war(current):
			return -1
		visited[current] = true
		current = int(state.suzerainty[current].overlord_id)
	return -1

## A peaceful subject inherits protection, but an ordinary ally does not.
## An empire retains its own institution even if it later becomes a subject.
static func protecting_empire(state: GameState, nation_id: int) -> int:
	var visited := {}
	var current := nation_id
	while current >= 0 and current < state.nations.size():
		var nation := state.nations[current]
		if visited.has(current) or not nation.alive or nation.succession_identity:
			return -1
		if nation.state_level == EMPIRE:
			return current
		if not state.suzerainty.has(current) or state.is_in_civil_war(current):
			return -1
		visited[current] = true
		current = int(state.suzerainty[current].overlord_id)
	return -1

static func has_core_garrison_bonus(state: GameState, city_id: int) -> bool:
	var controller := state.cities[city_id].owner_nation
	if protecting_empire(state, controller) < 0:
		return false
	var legal := state.recognized_owner_of(city_id)
	if controller == legal:
		return true
	var root := peaceful_root(state, controller)
	return root >= 0 and root == peaceful_root(state, legal)

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
	if state == null or state.has_meta("historical_prince_reports") or state.has_meta("ruler_accession_in_progress"):
		return
	var completed := completed_regions(state)
	for nation in state.nations:
		if not nation.alive or nation.succession_identity or nation.state_level == EMPIRE or state.suzerainty.has(nation.id):
			continue
		if int(completed.get(nation.id, 0)) < REQUIRED_TRADE_REGIONS or nation.ruler_person_id < 0:
			continue
		nation.state_level = EMPIRE
		nation.empire_founder_person_id = nation.ruler_person_id
		nation.empire_recognized_day = state.day
		PrincePolitics.person(state, nation.id, nation.ruler_person_id)["taizu"] = true
		FamilyTree.record_current_title(state, nation.id)
		state.family_revision += 1
		state.garrison_revision += 1
		state.chronicle_events.append({"day": state.day, "year": int(state.day / 360) + 1,
			"kind": "empire", "actor_ids": [nation.id], "target_ids": [],
			"person_id": nation.ruler_person_id, "actor_name": WorldNaming.nation_display_name(state,nation.id), "result": "recognized",
			"text": "%d年 %s整合一个贸易区域，晋为帝国，%s为太祖" % [int(state.day / 360) + 1, WorldNaming.nation_display_name(state,nation.id), nation.ruler_name]})
	RoyalTitles.reconcile(state)
