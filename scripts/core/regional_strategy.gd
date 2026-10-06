class_name RegionalStrategy
extends RefCounted

const LATITUDE_KNOTS := [0.0, 18.0, 25.0, 35.0, 45.0, 65.0, 90.0]
const OUTPUT_KNOTS := [0.30, 0.55, 1.00, 1.00, 0.45, 0.10, 0.05]
const LATITUDE_DISTANCE_SCALE: float = 30.0
const HEIGHT_DISTANCE_SCALE: float = 0.5
const LATITUDE_SIMILARITY_WEIGHT: float = 0.6
const ENVIRONMENT_WEIGHT: float = 0.7
const CONQUEROR_ENVIRONMENT_WEIGHT: float = 0.35
const CONFLICT_WEIGHT: float = 1.35
const SHARED_GOAL_WEIGHT: float = 0.45
const INTEGRATION_BASE_BENEFIT: float = 0.8
const INTEGRATION_COMPLETION_BENEFIT: float = 2.2
static var geometry_build_count: int = 0
static var control_build_count: int = 0
static var query_count: int = 0


static func latitude_output_multiplier(latitude: float) -> float:
	var value := clampf(absf(latitude), 0.0, 90.0)
	for index in range(1, LATITUDE_KNOTS.size()):
		if value <= float(LATITUDE_KNOTS[index]):
			return lerpf(float(OUTPUT_KNOTS[index - 1]), float(OUTPUT_KNOTS[index]),
				smoothstep(float(LATITUDE_KNOTS[index - 1]), float(LATITUDE_KNOTS[index]), value))
	return float(OUTPUT_KNOTS[-1])


static func city_latitude(state: GameState, city: City) -> float:
	if not state.uses_heightmap:
		return 0.0
	var settings := state.city_density_settings
	if settings.is_empty():
		settings = TerrainMapGenerator.default_city_density_settings()
	return TerrainMapGenerator.latitude_for_map_y(city.map_position.y, settings)


static func invalidate_geometry(state: GameState) -> void:
	state._regional_strategy_geometry.clear()
	state._regional_strategy_control.clear()
	state.regional_strategy_revision += 1


static func geometry(state: GameState) -> Dictionary:
	var revision := [state.region_analysis_revision, state.administrative_region_revision,
		state.road_network_revision, state.cities.size()]
	if state._regional_strategy_geometry.get("revision") == revision:
		return state._regional_strategy_geometry
	geometry_build_count += 1
	var regions := PackedInt32Array()
	regions.resize(state.cities.size())
	regions.fill(-1)
	var members := {}
	var anchors := {}
	var environments := {}
	for city in state.cities:
		if city.is_dock or not city.politically_active:
			continue
		var center := state.administrative_center_of(city.id)
		if center < 0:
			center = city.id
		var region := int(state.region_ids[center]) if center < state.region_ids.size() else center
		if region < 0:
			region = center
		regions[city.id] = region
		if not members.has(region):
			members[region] = [] as Array[int]
			anchors[region] = center
			environments[region] = Vector3.ZERO
		(members[region] as Array[int]).append(city.id)
		if EquivariantOrder.mirror_orbit_city_less(state, center, int(anchors[region])):
			anchors[region] = center
		environments[region] += Vector3(absf(city_latitude(state, city)), city.terrain_height, 1.0)
	for region in environments:
		var totals: Vector3 = environments[region]
		environments[region] = Vector2(totals.x, totals.y) / maxf(totals.z, 1.0)
	var adjacent_regions := {}
	for border in state.territorial_border_pairs():
		var a := regions[border.x]
		var b := regions[border.y]
		if a < 0 or b < 0 or a == b:
			continue
		if not adjacent_regions.has(a):
			adjacent_regions[a] = {}
		if not adjacent_regions.has(b):
			adjacent_regions[b] = {}
		adjacent_regions[a][b] = true
		adjacent_regions[b][a] = true
	state._regional_strategy_geometry = {"revision": revision, "regions": regions,
		"members": members, "anchors": anchors, "environments": environments,
		"adjacent_regions": adjacent_regions}
	state._regional_strategy_control.clear()
	return state._regional_strategy_geometry


static func control(state: GameState) -> Dictionary:
	var geo := geometry(state)
	var revision := [state.ownership_revision, state.diplomacy_revision, geo["revision"]]
	if state._regional_strategy_control.get("revision") == revision:
		return state._regional_strategy_control
	control_build_count += 1
	var roots := {}
	var root_members := {}
	for nation in state.nations:
		if roots.has(nation.id):
			continue
		# Memoize peaceful parent chains so nested vassals visit each edge once.
		var chain: Array[int] = []
		var current := nation.id
		while not roots.has(current) and chain.size() <= state.nations.size():
			chain.append(current)
			if not state.suzerainty.has(current) or state.is_in_civil_war(current):
				break
			current = int(state.suzerainty[current]["overlord_id"])
		var root_id := int(roots.get(current, current))
		for member_id in chain:
			roots[member_id] = (
				state.food_pool_holder(member_id)
				if chain.size() > state.nations.size() else root_id
			)
	for nation in state.nations:
		var root := int(roots[nation.id])
		if not root_members.has(root):
			root_members[root] = [] as Array[int]
		(root_members[root] as Array[int]).append(nation.id)
	var owned := {}
	var root_owned := {}
	var claims := {}
	var values := {}
	var regions: PackedInt32Array = geo["regions"]
	for city in state.cities:
		var region := regions[city.id]
		if region < 0:
			continue
		var owner_key := Vector2i(city.owner_nation, region)
		owned[owner_key] = int(owned.get(owner_key, 0)) + 1
		var root_key := Vector2i(int(roots.get(city.owner_nation, city.owner_nation)), region)
		root_owned[root_key] = int(root_owned.get(root_key, 0)) + 1
		var center := state.administrative_center_of(city.id)
		claims[Vector2i(state.recognized_owner_of(city.id), center)] = true
		var centrality := float(state.node_betweenness[city.id]) if city.id < state.node_betweenness.size() else 0.0
		values[region] = Vector4(values.get(region, Vector4.ZERO)) + Vector4(
			city.gold_per_month, city.food_per_half_year, city.manpower_per_month, centrality)
	var neighbors := {}
	var border_cities := {}
	for pair in state.territorial_border_pairs():
		for direction in [pair, Vector2i(pair.y, pair.x)]:
			var target_region := regions[direction.y]
			var root := int(roots.get(state.cities[direction.x].owner_nation, -1))
			if root < 0 or target_region < 0 or regions[direction.x] < 0:
				continue
			if not neighbors.has(root):
				neighbors[root] = {}
			neighbors[root][target_region] = true
			var key := Vector2i(root, target_region)
			if not border_cities.has(key):
				border_cities[key] = [] as Array[int]
			(border_cities[key] as Array[int]).append(direction.y)
	state._regional_strategy_control = {"revision": revision, "roots": roots,
		"root_members": root_members,
		"owned": owned, "root_owned": root_owned, "claims": claims, "values": values,
		"neighbors": neighbors, "border_cities": border_cities}
	return state._regional_strategy_control


static func city_region(state: GameState, city_id: int) -> int:
	query_count += 1
	if city_id < 0 or city_id >= state.cities.size():
		return -1
	return int((geometry(state)["regions"] as PackedInt32Array)[city_id])


static func regions_are_adjacent(state: GameState, a: int, b: int) -> bool:
	var geo := geometry(state)
	if not (geo["members"] as Dictionary).has(a) or not (geo["members"] as Dictionary).has(b):
		return false
	return a == b or (geo["adjacent_regions"].get(a, {}) as Dictionary).has(b)


static func initial_region(state: GameState, nation_id: int) -> int:
	var data := control(state)
	var geo := geometry(state)
	var capital_region := city_region(state, state.nations[nation_id].capital_city_id)
	var best := -1
	var best_count := 0
	for region_value in geo["members"]:
		var region := int(region_value)
		var count := int(data["owned"].get(Vector2i(nation_id, region), 0))
		if count > best_count or (count > 0 and count == best_count and (
			(region == capital_region and best != capital_region)
			or (best != capital_region and EquivariantOrder.city_id_less(state, nation_id,
				int(geo["anchors"][region]), int(geo["anchors"].get(best, -1)))))):
			best = region
			best_count = count
	return best


static func target_region(state: GameState, nation_id: int) -> int:
	if nation_id < 0 or nation_id >= state.nations.size() or not state.nations[nation_id].alive:
		return -1
	var region := city_region(state, state.nations[nation_id].strategic_region_anchor_city_id)
	return region if region >= 0 else initial_region(state, nation_id)


static func integration_report(state: GameState, nation_id: int, region: int = -1) -> Dictionary:
	if region < 0:
		region = target_region(state, nation_id)
	var geo := geometry(state)
	var data := control(state)
	var total := (geo["members"].get(region, []) as Array).size()
	var root := int(data["roots"].get(nation_id, nation_id))
	var integrated := int(data["root_owned"].get(Vector2i(root, region), 0))
	return {"region_id": region, "total": total, "integrated": integrated,
		"complete": total > 0 and integrated == total}


static func can_expand(nation: Nation) -> bool:
	return RulerProfile.offensive_allowed(nation) \
		and not nation.ruler_traits.has(RulerProfile.TRAIT_CAUTIOUS)


static func similarity(state: GameState, a: int, b: int) -> float:
	if not state.uses_heightmap:
		return 1.0
	var profiles: Dictionary = geometry(state)["environments"]
	if not profiles.has(a) or not profiles.has(b):
		return 1.0
	var delta: Vector2 = (Vector2(profiles[a]) - Vector2(profiles[b])).abs()
	return 1.0 - LATITUDE_SIMILARITY_WEIGHT * clampf(delta.x / LATITUDE_DISTANCE_SCALE, 0.0, 1.0) \
		- (1.0 - LATITUDE_SIMILARITY_WEIGHT) * clampf(delta.y / HEIGHT_DISTANCE_SCALE, 0.0, 1.0)


static func choose_next_region(state: GameState, nation_id: int) -> int:
	var geo := geometry(state)
	var data := control(state)
	var root := int(data["roots"].get(nation_id, nation_id))
	var reference := city_region(state, state.nations[nation_id].capital_city_id)
	var candidates: Array[int] = []
	var maximum := Vector4.ONE
	var evaluation_cache := {}
	for region_value in geo["members"]:
		var region := int(region_value)
		if bool(integration_report(state, nation_id, region)["complete"]):
			continue
		var reachable := region_has_entry(state, nation_id, region, evaluation_cache)
		if reachable:
			candidates.append(region)
			var value: Vector4 = data["values"].get(region, Vector4.ZERO)
			maximum = Vector4(maxf(maximum.x, value.x), maxf(maximum.y, value.y),
				maxf(maximum.z, value.z), maxf(maximum.w, value.w))
	var weight := CONQUEROR_ENVIRONMENT_WEIGHT if state.nations[nation_id].ruler_archetype == RulerProfile.CONQUEROR else ENVIRONMENT_WEIGHT
	var best := -1
	var best_score := -INF
	for region in candidates:
		var value: Vector4 = data["values"].get(region, Vector4.ZERO)
		var normalized := value / maximum
		var economic := (normalized.x + normalized.y + normalized.z + normalized.w) / 4.0
		var score := weight * similarity(state, reference, region) + (1.0 - weight) * economic
		if score > best_score or (is_equal_approx(score, best_score) and EquivariantOrder.city_id_less(
			state, nation_id, int(geo["anchors"][region]), int(geo["anchors"].get(best, -1)))):
			best = region
			best_score = score
	return best

static func region_has_entry(state: GameState, nation_id: int, region: int, cache: Dictionary = {}) -> bool:
	for city_id in geometry(state)["members"].get(region, []):
		var owner := state.cities[int(city_id)].owner_nation
		if owner < 0 or owner == nation_id or state.has_military_access(nation_id, owner): continue
		if DiplomacyAI.can_initiate_war_at_range(state, nation_id, owner, cache) and not MilitaryReachability.prewar_entries(state, nation_id, int(city_id), cache).is_empty(): return true
	return false


static func update_target(state: GameState, nation_id: int, succession: bool = false) -> bool:
	var nation := state.nations[nation_id]
	var anchor := nation.strategic_region_anchor_city_id
	var region := city_region(state, anchor) if nation.alive else -1
	if nation.alive and region < 0:
		region = initial_region(state, nation_id)
	elif nation.alive and int(integration_report(state, nation_id, region)["integrated"]) == 0 and not region_has_entry(state, nation_id, region):
		var next := choose_next_region(state, nation_id) if can_expand(nation) else -1
		region = next if next >= 0 else initial_region(state, nation_id)
	elif nation.alive and bool(integration_report(state, nation_id, region)["complete"]) \
		and can_expand(nation):
		var next := choose_next_region(state, nation_id)
		if next >= 0:
			region = next
	var next_anchor := int(geometry(state)["anchors"].get(region, -1)) if nation.alive else -1
	# Keep an existing anchor across ownership and region numbering changes.
	if region >= 0 and city_region(state, anchor) == region:
		next_anchor = anchor
	if next_anchor == anchor:
		return false
	nation.strategic_region_anchor_city_id = next_anchor
	state.regional_strategy_revision += 1
	if anchor >= 0 and nation.alive:
		state.diplomatic_history.append({"kind": "regional_strategy_goal_changed", "day": state.day,
			"nation_a": nation_id, "previous_anchor": anchor, "anchor": next_anchor,
			"succession": succession})
	return true


static func initialize_targets(state: GameState) -> void:
	for nation in state.nations:
		if nation.strategic_region_anchor_city_id < 0:
			update_target(state, nation.id)


static func update_targets(state: GameState) -> void:
	for nation in state.nations:
		update_target(state, nation.id)


static func allows_objective(state: GameState, nation_id: int, center_id: int, reclamation_only: bool = false) -> bool:
	var center := state.administrative_center_of(center_id)
	if center < 0:
		return false
	var legal := bool(control(state)["claims"].get(Vector2i(nation_id, center), false))
	if not VassalConflict.for_pair(state, nation_id, state.cities[center].owner_nation).is_empty(): return true
	if reclamation_only:
		return legal
	return legal or city_region(state, center) == target_region(state, nation_id) \
		or (state.is_enemy(nation_id, state.cities[center].owner_nation)
			and state.is_same_suzerainty_system(nation_id, state.cities[center].owner_nation))


static func integration_war_bonus(state: GameState, nation_id: int, target_id: int) -> float:
	var region := target_region(state, nation_id)
	if region < 0 or target_id < 0 or target_id >= state.nations.size() or not state.nations[target_id].alive:
		return 0.0
	var data := control(state)
	var root := int(data["roots"].get(nation_id, nation_id))
	var target_root := int(data["roots"].get(target_id, target_id))
	if root == target_root:
		return 0.0
	var report := integration_report(state, nation_id, region)
	var total := int(report["total"])
	var integrated := int(report["integrated"])
	var remaining := total - integrated
	var target_owned := int(data["root_owned"].get(Vector2i(target_root, region), 0))
	if total <= 0 or remaining <= 0 or target_owned <= 0:
		return 0.0
	var progress := clampf(float(integrated) / float(total), 0.0, 1.0)
	var outstanding_share := clampf(float(target_owned) / float(remaining), 0.0, 1.0)
	return (INTEGRATION_BASE_BENEFIT + INTEGRATION_COMPLETION_BENEFIT * progress * progress) \
		* (0.5 + 0.5 * outstanding_share)


static func rivalry(state: GameState, nation_id: int, other_id: int) -> float:
	var a := target_region(state, nation_id)
	var b := target_region(state, other_id)
	if a < 0 or b < 0:
		return 0.0
	var data := control(state)
	var root_a := int(data["roots"].get(nation_id, nation_id))
	var root_b := int(data["roots"].get(other_id, other_id))
	if root_a == root_b:
		return 0.0
	var totals: Dictionary = geometry(state)["members"]
	var share_a := float(data["root_owned"].get(Vector2i(root_b, a), 0)) / float(maxi((totals.get(a, []) as Array).size(), 1))
	var share_b := float(data["root_owned"].get(Vector2i(root_a, b), 0)) / float(maxi((totals.get(b, []) as Array).size(), 1))
	return CONFLICT_WEIGHT * maxf(share_a, share_b) + (SHARED_GOAL_WEIGHT if a == b else 0.0)
