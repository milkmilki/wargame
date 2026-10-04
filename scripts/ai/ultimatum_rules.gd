class_name UltimatumRules
extends RefCounted

enum Outcome { REFUSE, SUBMIT, ANNEX }

const SUBMISSION_THRESHOLD: float = 55.0
const ANNEXATION_THRESHOLD: float = 80.0
const ANNEXATION_SIZE_RATIO: int = 3
const BASE_SCORE: float = 20.0
const MILITARY_WEIGHT: float = 60.0
const MILITARY_LOG_SCALE: float = 2.0
const ENVIRONMENT_FLOOR: float = 0.35
const ALLIED_SUPPORT_RATIO: float = 0.5
const INTIMIDATION_CAP: float = 15.0
const RESISTANCE_MIN: float = -5.0
const RESISTANCE_MAX: float = 20.0

static func score(a: float, d: float, similarity: float, intimidation: float, resistance: float) -> float:
	var military := clampf(log(maxf(a, 1.0) / maxf(d, 1.0)) / log(2.0) / MILITARY_LOG_SCALE, 0.0, 1.0)
	return clampf((BASE_SCORE + MILITARY_WEIGHT * military + intimidation - resistance)
		* (ENVIRONMENT_FLOOR + (1.0 - ENVIRONMENT_FLOOR) * clampf(similarity, 0.0, 1.0)), 0.0, 100.0)

static func outcome_for_score(value: float, annexation_allowed: bool) -> int:
	if value >= ANNEXATION_THRESHOLD and annexation_allowed:
		return Outcome.ANNEX
	return Outcome.SUBMIT if value >= SUBMISSION_THRESHOLD else Outcome.REFUSE

static func evaluate(state: GameState, attacker_id: int, target_id: int, cache: Dictionary = {}) -> Dictionary:
	var result := {"eligible": false, "outcome": Outcome.REFUSE, "score": 0.0,
		"attacker_power": 0.0, "defender_power": 0.0, "allied_support": 0.0,
		"power_ratio": 0.0, "similarity": 1.0, "intimidation": 0.0,
		"resistance": 0.0, "annexation_allowed": false, "target_members": [],
		"target_land_cities": 0, "attacker_land_cities": 0}
	if attacker_id < 0 or target_id < 0 or attacker_id >= state.nations.size() or target_id >= state.nations.size():
		return result
	if state.is_succession_identity(attacker_id) or state.is_succession_identity(target_id):
		return result
	if not state.nations[attacker_id].alive or not state.nations[target_id].alive or state.is_vassal(target_id):
		return result
	var index := _index(state, cache)
	var roots: Dictionary = index.roots
	var target_root := int(roots[target_id])
	var attacker_root := int(roots[attacker_id])
	if target_root == attacker_root:
		return result
	var members: Array = index.members[target_root]
	result.target_members = members.duplicate()
	for member_id in members:
		if state.is_in_civil_war(member_id) or state.rebellions.has(member_id) or state.nations[member_id].name_kind == WorldNaming.KIND_REBEL or not state.wars_of(member_id).is_empty():
			return result
	# A political root can have a civil-war branch outside the peaceful food pool.
	for subject_id in state.suzerainty:
		if state.is_in_civil_war(subject_id) and state.suzerainty_root(subject_id) == target_id:
			return result
	var attacker := state.nations[attacker_id]
	var prepared := {}
	for army_id in attacker.war_preparation_army_ids:
		prepared[army_id] = true
	var attacking_power := 0.0
	for army in index.armies.get(attacker_id, []):
		if prepared.has(army.id) and army.campaign_war_id < 0 and army.campaign_front_id < 0 and army.state == Army.State.IDLE and army.is_at_city_node(attacker.war_preparation_staging_city_id):
			attacking_power += ArmyPower.effective(army)
	result.attacker_power = attacking_power
	if attacking_power <= 0.0:
		return result
	var defending_power := 0.0
	for member_id in members:
		for army in index.armies.get(member_id, []):
			var city_ids: Array = [army.move_from, army.move_to] if army.on_edge else [army.location_city]
			for city_id in city_ids:
				if city_id >= 0 and city_id < state.cities.size() and roots.get(state.cities[city_id].owner_nation, -1) == target_root:
					defending_power += ArmyPower.effective(army)
					break
	var capital_center := state.administrative_center_of(state.nations[target_id].capital_city_id)
	defending_power += ArmyPower.city_garrison_defense(state, attacker_id, capital_center)
	var support := 0.0
	var bloc := state.alliance_bloc(target_id)
	for ally_id in index.neighbors.get(target_root, {}):
		if not bloc.has(ally_id) or roots[ally_id] == target_root or roots[ally_id] == attacker_root:
			continue
		var reserved: Dictionary = index.reserved
		for army in index.armies.get(ally_id, []):
			if army.state == Army.State.IDLE and army.campaign_war_id < 0 and army.campaign_front_id < 0 and not reserved.has(army.id):
				support += ArmyPower.effective(army)
	result.allied_support = minf(support * ALLIED_SUPPORT_RATIO, defending_power * ALLIED_SUPPORT_RATIO)
	result.defender_power = defending_power + float(result.allied_support)
	result.power_ratio = attacking_power / maxf(float(result.defender_power), 1.0)
	result.similarity = RegionalStrategy.similarity(state,
		RegionalStrategy.city_region(state, state.administrative_center_of(attacker.capital_city_id)),
		RegionalStrategy.city_region(state, capital_center))
	result.intimidation = intimidation(attacker)
	result.resistance = resistance(attacker, state.nations[target_id])
	result.target_land_cities = int(index.land_counts.get(target_root, 0))
	result.attacker_land_cities = int(index.land_counts.get(attacker_root, 0))
	result.annexation_allowed = int(result.target_land_cities) * ANNEXATION_SIZE_RATIO <= int(result.attacker_land_cities)
	result.score = score(attacking_power, result.defender_power, result.similarity, result.intimidation, result.resistance)
	result.outcome = outcome_for_score(result.score, result.annexation_allowed)
	result.eligible = true
	return result

static func intimidation(nation: Nation) -> float:
	var value := float({RulerProfile.CONQUEROR: 10, RulerProfile.REFORMER: 4, RulerProfile.TYRANT: 5}.get(nation.ruler_archetype, 0))
	var traits := {RulerProfile.TRAIT_MARTIAL: 3, RulerProfile.TRAIT_AMBITIOUS: 2, RulerProfile.TRAIT_CHARISMATIC: 4}
	for trait_id in traits:
		if nation.ruler_traits.has(trait_id):
			value += float(traits[trait_id])
	return minf(value, INTIMIDATION_CAP)

static func resistance(attacker: Nation, defender: Nation) -> float:
	var value := float({RulerProfile.CONQUEROR: 12, RulerProfile.GUARDIAN: 8, RulerProfile.TYRANT: 8,
		RulerProfile.REFORMER: 5, RulerProfile.DIPLOMAT: 3}.get(defender.ruler_archetype, 0))
	if defender.ruler_traits.has(RulerProfile.TRAIT_MARTIAL):
		value += 5.0
	if defender.ruler_traits.has(RulerProfile.TRAIT_AMBITIOUS):
		value += 5.0
	if defender.ruler_traits.has(RulerProfile.TRAIT_CAUTIOUS):
		value -= 3.0
	if attacker.ruler_archetype == RulerProfile.TYRANT:
		value += 8.0
	if attacker.ruler_traits.has(RulerProfile.TRAIT_HARSH):
		value += 5.0
	return clampf(value, RESISTANCE_MIN, RESISTANCE_MAX)

static func _index(state: GameState, cache: Dictionary) -> Dictionary:
	var key := "ultimatum_index:%d:%d" % [state.ownership_revision, state.diplomacy_revision]
	if cache.has(key):
		return cache[key]
	var result := {"roots": {}, "members": {}, "land_counts": {}, "armies": {}, "reserved": {}, "neighbors": {}}
	for nation in state.nations:
		var root := state.food_pool_holder(nation.id)
		result.roots[nation.id] = root
		if not result.members.has(root):
			result.members[root] = []
		if nation.alive:
			result.members[root].append(nation.id)
		for army_id in nation.war_preparation_army_ids:
			result.reserved[army_id] = true
	for city in state.cities:
		if city.politically_active and not city.is_dock and result.roots.has(city.owner_nation):
			var root := int(result.roots[city.owner_nation])
			result.land_counts[root] = int(result.land_counts.get(root, 0)) + 1
	for army in state.armies:
		if state.army_effective_for_field_campaign(army) and not army.is_city_garrison:
			if not result.armies.has(army.owner_nation):
				result.armies[army.owner_nation] = []
			result.armies[army.owner_nation].append(army)
	for pair in state.territorial_border_pairs():
		var a := state.cities[pair.x].owner_nation
		var b := state.cities[pair.y].owner_nation
		if a < 0 or b < 0 or a == b:
			continue
		for ids in [Vector2i(a, b), Vector2i(b, a)]:
			var root := int(result.roots[ids.x])
			if not result.neighbors.has(root):
				result.neighbors[root] = {}
			result.neighbors[root][ids.y] = true
	cache[key] = result
	return result
