class_name NativeSnapshotBuilder
extends RefCounted
## 将脚本对象图一次性冻结为 NativeSimulationCore 的版本化 SoA 快照。
## 该桥只允许在日提交边界调用；native tick 接管后，展示层将改读反向只读快照。

const SCHEMA_VERSION: int = 24
const ROYAL_NATION_FIELDS := ["state_level", "empire_founder_person_id", "empire_recognized_day", "royal_titles_initialized", "royal_generation", "absorbed_into_nation_id", "last_royal_expense_basis_points", "last_royal_title_counts"]


static func succession_validation_error(snapshot: Dictionary) -> String:
	if int(snapshot.get("schema_version", -1)) != SCHEMA_VERSION:
		return "Incompatible native snapshot schema"
	if not snapshot.get("battles") is Dictionary:
		return "Invalid battle table"
	var battle_error := battle_validation_error(snapshot.battles)
	if not battle_error.is_empty():
		return battle_error
	var chronicle_events = snapshot.get("chronicle_events", [])
	if not chronicle_events is Array:
		return "Invalid chronicle event list"
	for event_value in chronicle_events:
		if not event_value is Dictionary or not event_value.has("text") or not event_value.has("day"):
			return "Invalid chronicle event"
	var pending_wars = snapshot.get("chronicle_pending_war_ids", [])
	if not pending_wars is Array:
		return "Invalid chronicle pending list"
	var nations: Dictionary = snapshot.get("nations", {})
	var count := int(nations.get("count", -1))
	for key in ["family_tree_ids", "ruler_person_ids", "crown_prince_ids", "competition_closed", "succession_identity", "ruler_archetypes", "ruler_revisions", "ruler_started_days", "ruler_traits", "alive"]:
		if not nations.has(key) or nations[key].size() != count:
			return "Invalid nation politics column: " + key
	for key in ROYAL_NATION_FIELDS:
		if not nations.get(key) is Array or nations[key].size() != count:
			return "Invalid royal nation column: " + key
	var offsets: PackedInt32Array = nations.get("prince_offsets", PackedInt32Array())
	var ids: PackedInt32Array = nations.get("prince_ids", PackedInt32Array())
	if offsets.size() != count + 1 or offsets[0] != 0 or offsets[count] != ids.size():
		return "Invalid prince offsets"
	var trees := {}
	for tree in snapshot.get("family_trees", []):
		var members := {}
		for member in tree.members:
			if members.has(member.id):
				return "Duplicate family person"
			members[member.id] = member
		trees[tree.id] = members
	var incumbents := {}
	for index in range(count):
		if offsets[index] < 0 or offsets[index] > offsets[index + 1] or offsets[index + 1] > ids.size():
			return "Invalid prince offset range"
		var members: Dictionary = trees.get(nations.family_tree_ids[index], {})
		var ruler := int(nations.ruler_person_ids[index])
		if ruler >= 0 and not members.has(ruler):
			return "Missing ruler person"
		if ruler >= 0 and bool(nations.alive[index]) and not bool(nations.succession_identity[index]):
			if incumbents.has(ruler): return "Person holds multiple active thrones"
			incumbents[ruler] = index
		var crown := int(nations.crown_prince_ids[index])
		var seen := {}
		for position in range(offsets[index], offsets[index + 1]):
			var person_id := ids[position]
			if seen.has(person_id) or not members.has(person_id) or int(members[person_id].parent_id) != ruler:
				return "Invalid prince person reference"
			seen[person_id] = true
		if crown >= 0 and not seen.has(crown):
			return "Invalid crown prince reference"
	var royal_error := royal_validation_error(nations, trees)
	if not royal_error.is_empty():
		return royal_error
	var armies: Dictionary = snapshot.get("armies", {})
	if not armies.has("political_person_id") or armies.political_person_id.size() != int(armies.get("count", -1)):
		return "Invalid army political column"
	var army_count := int(armies.get("count", -1))
	for key in ["id", "owner"]:
		if not armies.has(key) or armies[key].size() != army_count:
			return "Invalid army reference column: " + key
	var army_ids := {}
	for position in range(army_count):
		var army_id := int(armies.id[position])
		if army_ids.has(army_id):
			return "Duplicate army id"
		army_ids[army_id] = true
		var owner_id := int(armies.owner[position])
		if owner_id < 0 or owner_id >= count:
			return "Invalid army owner reference"
		var patron_id := int(armies.political_person_id[position])
		if patron_id < 0:
			continue
		var owner_members: Dictionary = trees.get(nations.family_tree_ids[owner_id], {})
		if not owner_members.has(patron_id):
			return "Invalid army political person reference"
	var conflicts: Array = snapshot.get("succession_conflicts", [])
	var conflict_nations := {}
	var conflict_armies := {}
	var cities: Dictionary = snapshot.get("cities", {})
	var city_count := int(cities.get("count", -1))
	for raw_conflict in conflicts:
		if not raw_conflict is Dictionary:
			return "Invalid succession conflict record"
		var conflict: Dictionary = raw_conflict
		var conflict_nation := int(conflict.get("nation_id", -1))
		if conflict_nation < 0 or conflict_nation >= count or conflict_nations.has(conflict_nation):
			return "Invalid succession conflict nation"
		conflict_nations[conflict_nation] = true
		for city_key in ["capital_city_id", "camp_city_id"]:
			var city_id := int(conflict.get(city_key, -1))
			if city_id < 0 or city_id >= city_count:
				return "Invalid succession conflict city reference"
		var rebel_id := int(conflict.get("rebel_nation_id", -1))
		if rebel_id >= count or rebel_id == conflict_nation:
			return "Invalid succession rebel identity reference"
		if rebel_id >= 0 and not bool(nations.succession_identity[rebel_id]):
			return "Succession rebel is not a temporary identity"
		var conflict_members: Dictionary = trees.get(nations.family_tree_ids[conflict_nation], {})
		for person_key in ["challenger_person_id", "crown_person_id"]:
			var person_id := int(conflict.get(person_key, -1))
			if person_id < 0 or not conflict_members.has(person_id):
				return "Invalid succession conflict person reference"
		for army_key in ["army_ids", "crown_army_ids"]:
			for raw_army_id in conflict.get(army_key, []):
				var conflict_army_id := int(raw_army_id)
				if not army_ids.has(conflict_army_id) or conflict_armies.has(conflict_army_id):
					return "Invalid succession conflict army reference"
				conflict_armies[conflict_army_id] = true
	return ""


static func royal_validation_error(nations: Dictionary, trees: Dictionary) -> String:
	var count := int(nations.count)
	for nation_id in range(count):
		var level := int(nations.state_level[nation_id])
		var founder := int(nations.empire_founder_person_id[nation_id])
		var members: Dictionary = trees.get(nations.family_tree_ids[nation_id], {})
		if level not in [EmpireStatus.COUNTRY, EmpireStatus.EMPIRE]:
			return "Invalid nation state level"
		if level == EmpireStatus.EMPIRE and (not members.has(founder) or int(nations.empire_recognized_day[nation_id]) < 0):
			return "Invalid empire founder reference"
		if level == EmpireStatus.COUNTRY and founder >= 0:
			return "Country cannot have an empire founder"
		var absorber := int(nations.absorbed_into_nation_id[nation_id])
		if absorber >= count or absorber == nation_id:
			return "Invalid annex archive reference"
		if int(nations.royal_generation[nation_id]) < 0 or int(nations.last_royal_expense_basis_points[nation_id]) < 0:
			return "Invalid royal generation or expense"
		if not nations.last_royal_title_counts[nation_id] is Array or nations.last_royal_title_counts[nation_id].size() != 4:
			return "Invalid royal expense counts"
	for tree_id in trees:
		var members: Dictionary = trees[tree_id]
		var ancestry_checked := {}
		for person_id in members:
			var ancestry := {}
			var current := int(person_id)
			while members.has(current) and not ancestry_checked.has(current):
				if ancestry.has(current): return "Cyclic family ancestry"
				ancestry[current] = true
				current = int(members[current].get("parent_id", -1))
			ancestry_checked.merge(ancestry)
		for member in members.values():
			for flag in ["children_initialized", "synthetic_ancestor", "remote_branch"]:
				if member.has(flag) and not member[flag] is bool: return "Invalid family lifecycle flag"
			if bool(member.get("synthetic_ancestor", false)) and (bool(member.get("alive", true)) or int(member.get("office_nation_id", -1)) >= 0 or int(member.get("title_rank", 0)) > 0):
				return "Invalid synthetic ancestor"
			var parent := int(member.get("parent_id", -1))
			if parent >= 0 and (not members.has(parent) or parent == int(member.id)):
				return "Invalid family parent reference"
			var rank := int(member.get("title_rank", 0))
			var restore := int(member.get("restorable_title_rank", 0))
			if rank < 0 or rank > 3 or restore < 0 or restore > 3:
				return "Invalid royal title rank"
			var payer := int(member.get("title_payer_id", -1))
			if bool(member.get("title_managed", false)):
				if payer < 0 or payer >= count or int(nations.family_tree_ids[payer]) != int(tree_id):
					return "Invalid royal payer reference"
				if not members.has(int(member.get("title_branch_id", -1))):
					return "Invalid royal branch reference"
			var fief := int(member.get("enfeoffed_nation_id", -1))
			if fief >= count or (fief >= 0 and rank > 0 and bool(member.get("alive", true))):
				return "Actual fief and virtual title cannot coexist"
			if bool(member.get("crown", false)) and rank > 0 and bool(member.get("alive", true)):
				return "Crown cannot receive a virtual stipend"
			var office := int(member.get("office_nation_id", -1))
			if office >= count or (office >= 0 and int(nations.family_tree_ids[office]) != int(tree_id)):
				return "Invalid royal office reference"
			if office >= 0 and bool(member.get("alive", true)) and bool(nations.alive[office]) and int(nations.ruler_person_ids[office]) != int(member.id):
				return "Invalid incumbent person reference"
			if office >= 0 and bool(member.get("alive", true)) and bool(nations.alive[office]) and rank > 0:
				return "Incumbent cannot receive a virtual stipend"
			for child in member.get("child_ids", []):
				if not members.has(int(child)) or int(members[int(child)].parent_id) != int(member.id):
					return "Invalid family child reference"
	return ""


static func battle_validation_error(battles: Dictionary) -> String:
	if not battles.get("count") is int:
		return "Invalid battle count"
	var count: int = battles.count
	if count < 0:
		return "Invalid battle count"
	for key in ["field_dice", "assault_dice", "field_sequence", "assault_sequence"]:
		if not battles.has(key):
			return "Invalid battle dice column: " + key
		if key.ends_with("_dice") and not battles[key] is Array:
			return "Invalid battle dice column: " + key
		if key.ends_with("_sequence") and not battles[key] is PackedInt32Array:
			return "Invalid battle sequence column: " + key
		if battles[key].size() != count:
			return "Invalid battle dice column: " + key
	for index in range(count):
		for kind in ["field", "assault"]:
			var raw = battles[kind + "_dice"][index]
			if not raw is PackedInt32Array:
				return "Invalid battle dice type"
			var sequence := int(battles[kind + "_sequence"][index])
			if sequence < 0 or (not raw.is_empty() and (not Battle.valid_dice(raw) or sequence == 0)):
				return "Invalid battle opening dice"
	return ""


static func build(state: GameState) -> Dictionary:
	var nations := _build_nations(state)
	for key in ROYAL_NATION_FIELDS:
		var column: Array = []
		for nation in state.nations:
			var value = nation.get(key)
			column.append(value.duplicate(true) if value is Array else value)
		nations[key] = column
	var cities := _build_cities(state)
	var edges_and_indices := _build_edges(state)
	var armies_and_indices := _build_armies(state)
	var battles := _build_battles(
		state,
		edges_and_indices["indices"],
		armies_and_indices["indices"]
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"revision": state.day,
		"day": state.day,
		"rng_state": state.rng.state,
		"next_army_id": state._next_army_id,
		"next_battle_id": state._next_battle_id,
		"next_war_id": state.next_war_id,
		"next_campaign_front_id": state.next_campaign_front_id,
		"next_campaign_pair_id": state.next_campaign_pair_id,
		"next_family_tree_id": state.next_family_tree_id,
		"next_family_person_id": state.next_family_person_id,
		"family_revision": state.family_revision,
		"family_trees": _build_family_trees(state),
		"succession_conflicts": _build_succession_conflicts(state),
		"succession_events": state.succession_events.duplicate(true),
		"chronicle_events": state.chronicle_events.duplicate(true),
		"war_chronicle_contexts": state.war_chronicle_contexts.duplicate(true),
		"chronicle_pending_war_ids": state.chronicle_pending_war_ids.duplicate(),
		"winner": state.winner,
		"uses_heightmap": int(state.uses_heightmap),
		"ownership_revision": state.ownership_revision,
		"diplomacy_revision": state.diplomacy_revision,
		"garrison_revision": state.garrison_revision,
		"regional_strategy_revision": state.regional_strategy_revision,
		"nations": nations,
		"cities": cities,
		"edges": edges_and_indices["snapshot"],
		"armies": armies_and_indices["snapshot"],
		"battles": battles,
		"campaign_fronts": _build_campaign_fronts(state),
		"campaign_pairs": _build_campaign_pairs(state),
	}


static func _build_succession_conflicts(state: GameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids := state.succession_conflicts.keys()
	ids.sort()
	for nation_id in ids:
		var conflict := state.succession_conflicts[nation_id] as SuccessionConflict
		var record := {}
		for property in conflict.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
				var value = conflict.get(property.name)
				record[property.name] = value.duplicate(true) if value is Array or value is Dictionary else value
		result.append(record)
	return result


static func _build_family_trees(state: GameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tree_ids := state.family_trees.keys()
	tree_ids.sort()
	for tree_id in tree_ids:
		var tree: Dictionary = state.family_trees[tree_id]
		var member_ids: Array = tree.members.keys()
		member_ids.sort()
		var members: Array[Dictionary] = []
		for person_id in member_ids:
			members.append(tree.members[person_id].duplicate(true))
		result.append({"id": tree_id, "root_person_id": tree.root_person_id, "members": members})
	return result


static func _build_campaign_pairs(state: GameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = state.campaign_pairs.keys()
	ids.sort()
	for pair_id in ids:
		var pair := state.campaign_pairs[pair_id] as CoalitionCampaignPair
		var cooldowns: Array[Vector2i] = []
		var members: Array = pair.cooldown_until_by_nation.keys()
		members.sort()
		for nation_id in members:
			cooldowns.append(Vector2i(int(nation_id), int(pair.cooldown_until_by_nation[nation_id])))
		result.append({"pair_id": pair.pair_id, "war_id": pair.war_id,
			"side_a": PackedInt32Array(pair.side_a_nation_ids), "side_b": PackedInt32Array(pair.side_b_nation_ids),
			"battlefields": pair.battlefields.duplicate(true), "cooldowns": cooldowns})
	return result


static func _build_nations(state: GameState) -> Dictionary:
	var ids := PackedInt32Array()
	var capitals := PackedInt32Array()
	var strategic_region_anchors := PackedInt32Array()
	var family_tree_ids := PackedInt32Array()
	var ruler_person_ids := PackedInt32Array()
	var ruler_archetypes := PackedInt32Array()
	var ruler_revisions := PackedInt32Array()
	var ruler_started_days := PackedInt32Array()
	var ruler_traits: Array[Array] = []
	var crown_prince_ids := PackedInt32Array()
	var prince_offsets := PackedInt32Array([0])
	var prince_ids := PackedInt32Array()
	var competition_closed := PackedByteArray()
	var succession_identity := PackedByteArray()
	var vassal_title_bases := PackedStringArray()
	var gold := PackedInt32Array()
	var manpower := PackedInt32Array()
	var last_military_upkeep := PackedInt32Array()
	var court_expense_rate := PackedFloat64Array()
	var court_expense_due := PackedInt32Array()
	var court_expense_paid := PackedInt32Array()
	var last_field_army_upkeep := PackedInt32Array()
	var last_garrison_upkeep := PackedInt32Array()
	var unpaid_military_upkeep := PackedInt32Array()
	var payment_ratio := PackedFloat64Array()
	var granary_food := PackedInt32Array()
	var last_food_demand := PackedInt32Array()
	var last_garrison_food_demand := PackedInt32Array()
	var food_demand_ema := PackedFloat64Array()
	var overlord := PackedInt32Array()
	var effective_tribute_rate := PackedFloat64Array()
	var food_pool_holder := PackedInt32Array()
	var suzerainty_tribute_rate := PackedFloat64Array()
	var suzerainty_created_day := PackedInt32Array()
	var suzerainty_last_centralization_day := PackedInt32Array()
	var suzerainty_civil_war := PackedByteArray()
	var next_battle_group_id := PackedInt32Array()
	var battle_group_offsets := PackedInt32Array([0])
	var battle_group_ids := PackedInt32Array()
	var battle_group_created_day := PackedInt32Array()
	var ai_aggression := PackedFloat64Array()
	var war_preparation_target := PackedInt32Array()
	var war_preparation_objective := PackedInt32Array()
	var war_preparation_staging_city := PackedInt32Array()
	var war_preparation_started_day := PackedInt32Array()
	var war_preparation_army_offsets := PackedInt32Array([0])
	var war_preparation_army_ids := PackedInt32Array()
	var alive := PackedByteArray()
	for nation in state.nations:
		ids.append(nation.id)
		capitals.append(nation.capital_city_id)
		strategic_region_anchors.append(nation.strategic_region_anchor_city_id)
		family_tree_ids.append(nation.family_tree_id)
		ruler_person_ids.append(nation.ruler_person_id)
		ruler_archetypes.append(nation.ruler_archetype)
		ruler_revisions.append(nation.ruler_revision)
		ruler_started_days.append(nation.ruler_started_day)
		ruler_traits.append(nation.ruler_traits.duplicate())
		crown_prince_ids.append(nation.crown_prince_person_id)
		prince_ids.append_array(PackedInt32Array(nation.prince_person_ids))
		prince_offsets.append(prince_ids.size())
		competition_closed.append(int(nation.succession_competition_closed))
		succession_identity.append(int(nation.succession_identity))
		vassal_title_bases.append(nation.vassal_title_base)
		gold.append(nation.treasury_gold)
		manpower.append(nation.manpower_pool)
		last_military_upkeep.append(nation.last_military_upkeep)
		court_expense_rate.append(nation.last_court_expense_rate)
		court_expense_due.append(nation.last_court_expense_due)
		court_expense_paid.append(nation.last_court_expense_paid)
		last_field_army_upkeep.append(nation.last_field_army_upkeep)
		last_garrison_upkeep.append(nation.last_garrison_upkeep)
		unpaid_military_upkeep.append(
			nation.unpaid_military_upkeep
		)
		payment_ratio.append(nation.military_payment_ratio)
		granary_food.append(nation.granary_food)
		last_food_demand.append(nation.last_food_demand)
		last_garrison_food_demand.append(nation.last_garrison_food_demand)
		food_demand_ema.append(nation.food_demand_ema)
		overlord.append(state.overlord_of(nation.id))
		effective_tribute_rate.append(
			Simulation.effective_tribute_rate(
				state,
				nation.id
			)
		)
		food_pool_holder.append(
			state.food_pool_holder(nation.id)
		)
		var suzerainty_record := state.suzerainty_record(nation.id)
		suzerainty_tribute_rate.append(float(
			suzerainty_record.get("tribute_rate", 0.0)
		))
		suzerainty_created_day.append(int(
			suzerainty_record.get("created_day", -1)
		))
		suzerainty_last_centralization_day.append(int(
			suzerainty_record.get(
				"last_centralization_day",
				-1
			)
		))
		suzerainty_civil_war.append(int(
			suzerainty_record.get("civil_war", false)
		))
		next_battle_group_id.append(nation.next_battle_group_id)
		for group in nation.battle_groups:
			battle_group_ids.append(group.id)
			battle_group_created_day.append(group.created_day)
		battle_group_offsets.append(battle_group_ids.size())
		ai_aggression.append(nation.ai_aggression)
		war_preparation_target.append(
			nation.war_preparation_target_nation
		)
		war_preparation_objective.append(
			nation.war_preparation_objective_city
		)
		war_preparation_staging_city.append(
			nation.war_preparation_staging_city_id
		)
		war_preparation_started_day.append(
			nation.war_preparation_started_day
		)
		var preparation_army_ids := nation.war_preparation_army_ids.duplicate()
		preparation_army_ids.sort()
		for army_id in preparation_army_ids:
			war_preparation_army_ids.append(army_id)
		war_preparation_army_offsets.append(
			war_preparation_army_ids.size()
		)
		alive.append(int(nation.alive))

	var diplomacy := PackedByteArray()
	var diplomacy_since_day := PackedInt32Array()
	var truce_until_day := PackedInt32Array()
	var war_objective_city := PackedInt32Array()
	var war_objective_started_day := PackedInt32Array()
	var war_relation_id := PackedInt32Array()
	for nation_a in range(state.nations.size()):
		for nation_b in range(state.nations.size()):
			diplomacy.append(
				state.relation_between(nation_a, nation_b)
			)
			diplomacy_since_day.append(
				state.relation_since(nation_a, nation_b)
			)
			truce_until_day.append(
				state.truce_until(nation_a, nation_b)
			)
			war_relation_id.append(state.war_id_between(nation_a, nation_b))
			var objective := state.war_objective(
				nation_a,
				nation_b
			)
			var directed := (
				not objective.is_empty()
				and int(objective.get("attacker", -1)) == nation_a
				and int(objective.get("defender", -1)) == nation_b
			)
			war_objective_city.append(
				int(objective.get("city_id", -1))
				if directed
				else -1
			)
			war_objective_started_day.append(
				int(objective.get("started_day", -1))
				if directed
				else -1
			)
	return {
		"count": state.nations.size(),
		"ids": ids,
		"capitals": capitals,
		"strategic_region_anchors": strategic_region_anchors,
		"family_tree_ids": family_tree_ids,
		"ruler_person_ids": ruler_person_ids,
		"ruler_archetypes": ruler_archetypes,
		"ruler_revisions": ruler_revisions,
		"ruler_started_days": ruler_started_days,
		"ruler_traits": ruler_traits,
		"crown_prince_ids": crown_prince_ids,
		"prince_offsets": prince_offsets,
		"prince_ids": prince_ids,
		"competition_closed": competition_closed,
		"succession_identity": succession_identity,
		"vassal_title_bases": vassal_title_bases,
		"gold": gold,
		"manpower": manpower,
		"last_military_upkeep": last_military_upkeep,
		"last_court_expense_rate": court_expense_rate,
		"last_court_expense_due": court_expense_due,
		"last_court_expense_paid": court_expense_paid,
		"last_field_army_upkeep": last_field_army_upkeep,
		"last_garrison_upkeep": last_garrison_upkeep,
		"unpaid_military_upkeep": unpaid_military_upkeep,
		"payment_ratio": payment_ratio,
		"granary_food": granary_food,
		"last_food_demand": last_food_demand,
		"last_garrison_food_demand": last_garrison_food_demand,
		"food_demand_ema": food_demand_ema,
		"overlord": overlord,
		"effective_tribute_rate": effective_tribute_rate,
		"food_pool_holder": food_pool_holder,
		"suzerainty_tribute_rate": suzerainty_tribute_rate,
		"suzerainty_created_day": suzerainty_created_day,
		"suzerainty_last_centralization_day":
			suzerainty_last_centralization_day,
		"suzerainty_civil_war": suzerainty_civil_war,
		"next_battle_group_id": next_battle_group_id,
		"battle_group_offsets": battle_group_offsets,
		"battle_group_ids": battle_group_ids,
		"battle_group_created_day": battle_group_created_day,
		"ai_aggression": ai_aggression,
		"war_preparation_target": war_preparation_target,
		"war_preparation_objective": war_preparation_objective,
		"war_preparation_staging_city": war_preparation_staging_city,
		"war_preparation_started_day":
			war_preparation_started_day,
		"war_preparation_army_offsets": war_preparation_army_offsets,
		"war_preparation_army_ids": war_preparation_army_ids,
		"alive": alive,
		"diplomacy": diplomacy,
		"diplomacy_since_day": diplomacy_since_day,
		"truce_until_day": truce_until_day,
		"war_objective_city": war_objective_city,
		"war_objective_started_day":
			war_objective_started_day,
		"war_relation_id": war_relation_id,
	}


static func _build_cities(state: GameState) -> Dictionary:
	var ids := PackedInt32Array()
	var position_x := PackedFloat64Array()
	var position_y := PackedFloat64Array()
	var terrain_height := PackedFloat64Array()
	var terrain_relief := PackedFloat64Array()
	var owner := PackedInt32Array()
	var recognized_owner := PackedInt32Array()
	var occupation_sponsor := PackedInt32Array()
	var garrison_manpower := PackedInt32Array()
	var garrison_supply_ratio := PackedFloat64Array()
	var manpower_output := PackedInt32Array()
	var food := PackedInt32Array()
	var gold_output := PackedInt32Array()
	var food_output := PackedInt32Array()
	var warehouse := PackedByteArray()
	var food_hub := PackedByteArray()
	var manpower_hub := PackedByteArray()
	var at_war := PackedByteArray()
	var administrative_rebellion_progress := PackedInt32Array()
	var war_disruption_until_day := PackedInt32Array()
	for city in state.cities:
		ids.append(city.id)
		position_x.append(city.map_position.x)
		position_y.append(city.map_position.y)
		terrain_height.append(city.terrain_height)
		terrain_relief.append(city.terrain_relief)
		owner.append(city.owner_nation)
		recognized_owner.append(state.recognized_owner_of(city.id))
		occupation_sponsor.append(city.occupation_sponsor_nation)
		garrison_manpower.append(city.garrison_manpower)
		garrison_supply_ratio.append(city.garrison_supply_ratio)
		manpower_output.append(city.manpower_per_month)
		food.append(city.food_storage)
		gold_output.append(city.gold_per_month)
		food_output.append(city.food_per_half_year)
		warehouse.append(int(city.has_warehouse))
		food_hub.append(int(city.is_food_hub))
		manpower_hub.append(int(city.is_manpower_hub))
		at_war.append(int(city.at_war))
		administrative_rebellion_progress.append(city.administrative_rebellion_progress)
		war_disruption_until_day.append(
			city.war_disruption_until_day
		)
	return {
		"count": state.cities.size(),
		"ids": ids,
		"position_x": position_x,
		"position_y": position_y,
		"terrain_height": terrain_height,
		"terrain_relief": terrain_relief,
		"owner": owner,
		"recognized_owner": recognized_owner,
		"occupation_sponsor": occupation_sponsor,
		"garrison_manpower": garrison_manpower,
		"garrison_supply_ratio": garrison_supply_ratio,
		"manpower_output": manpower_output,
		"food": food,
		"gold_output": gold_output,
		"food_output": food_output,
		"warehouse": warehouse,
		"food_hub": food_hub,
		"manpower_hub": manpower_hub,
		"at_war": at_war,
		"administrative_rebellion_progress": administrative_rebellion_progress,
		"war_disruption_until_day": war_disruption_until_day,
	}


static func _build_edges(state: GameState) -> Dictionary:
	var city_a := PackedInt32Array()
	var city_b := PackedInt32Array()
	var kind := PackedInt32Array()
	var capacity := PackedInt32Array()
	var distance := PackedInt32Array()
	var danger := PackedFloat64Array()
	var travel_multiplier := PackedFloat64Array()
	var supply_multiplier := PackedFloat64Array()
	var allows_holding := PackedByteArray()
	var terrain_connector := PackedByteArray()
	var occupied := PackedByteArray()
	var passing_count := PackedInt32Array()
	var indices := {}
	for index in range(state.edges.size()):
		var edge: Edge = state.edges[index]
		indices[edge] = index
		city_a.append(edge.city_a)
		city_b.append(edge.city_b)
		kind.append(edge.kind)
		capacity.append(edge.max_manpower)
		distance.append(edge.distance)
		danger.append(edge.danger)
		travel_multiplier.append(edge.travel_time_multiplier)
		supply_multiplier.append(edge.supply_loss_multiplier)
		allows_holding.append(int(edge.allows_holding))
		terrain_connector.append(int(edge.is_terrain_connector))
		occupied.append(int(edge.occupied))
		passing_count.append(edge.passing_count)
	return {
		"indices": indices,
		"snapshot": {
			"count": state.edges.size(),
			"a": city_a,
			"b": city_b,
			"kind": kind,
			"capacity": capacity,
			"distance": distance,
			"danger": danger,
			"travel_multiplier": travel_multiplier,
			"supply_multiplier": supply_multiplier,
			"allows_holding": allows_holding,
			"terrain_connector": terrain_connector,
			"occupied": occupied,
			"passing_count": passing_count,
		},
	}


static func _build_campaign_fronts(state: GameState) -> Dictionary:
	var front_ids := PackedInt32Array()
	var pair_ids := PackedInt32Array()
	var battlefield_slots := PackedInt32Array()
	var selection_reasons := PackedInt32Array()
	var retiring := PackedByteArray()
	var war_ids := PackedInt32Array()
	var modes := PackedInt32Array()
	var centers := PackedInt32Array()
	var anchors := PackedInt32Array()
	var phases := PackedInt32Array()
	var staging_cities := PackedInt32Array()
	var camp_cities := PackedInt32Array()
	var failed_until_days := PackedInt32Array()
	var reported_effective_manpower := PackedInt32Array()
	var reported_requirements := PackedInt32Array()
	var combat_report_locked := PackedByteArray()
	var combat_report_days := PackedInt32Array()
	var participant_offsets := PackedInt32Array([0])
	var participant_ids := PackedInt32Array()
	var tactical_offsets := PackedInt32Array([0])
	var tactical_city_ids := PackedInt32Array()
	var assignment_offsets := PackedInt32Array([0])
	var assignment_army_ids := PackedInt32Array()
	var assignment_targets := PackedInt32Array()
	var ids: Array = state.campaign_fronts.keys()
	ids.sort()
	for front_id_value in ids:
		var front := state.campaign_front(int(front_id_value))
		if front == null:
			continue
		front_ids.append(front.front_id)
		pair_ids.append(front.campaign_pair_id)
		battlefield_slots.append(front.battlefield_slot)
		selection_reasons.append(front.selection_reason)
		retiring.append(int(front.retiring))
		war_ids.append(front.war_id)
		modes.append(front.mode)
		centers.append(front.center_city_id)
		anchors.append(front.anchor_nation_id)
		phases.append(front.phase)
		staging_cities.append(front.staging_city_id)
		camp_cities.append(front.camp_city_id)
		failed_until_days.append(front.failed_until_day)
		reported_effective_manpower.append(
			front.reported_effective_manpower
		)
		reported_requirements.append(front.reported_requirement)
		combat_report_locked.append(1 if front.combat_report_locked else 0)
		combat_report_days.append(front.combat_report_day)
		participant_ids.append_array(PackedInt32Array(
			front.participant_nation_ids
		))
		participant_offsets.append(participant_ids.size())
		tactical_city_ids.append_array(PackedInt32Array(
			front.tactical_target_city_ids
		))
		tactical_offsets.append(tactical_city_ids.size())
		var army_ids: Array = front.army_assignments.keys()
		army_ids.sort()
		for army_id_value in army_ids:
			var army_id := int(army_id_value)
			assignment_army_ids.append(army_id)
			assignment_targets.append(int(front.army_assignments[army_id]))
		assignment_offsets.append(assignment_army_ids.size())
	return {
		"count": front_ids.size(),
		"front_ids": front_ids,
		"pair_ids": pair_ids,
		"battlefield_slots": battlefield_slots,
		"selection_reasons": selection_reasons,
		"retiring": retiring,
		"war_ids": war_ids,
		"modes": modes,
		"centers": centers,
		"anchors": anchors,
		"phases": phases,
		"staging_cities": staging_cities,
		"camp_cities": camp_cities,
		"failed_until_days": failed_until_days,
		"reported_effective_manpower": reported_effective_manpower,
		"reported_requirements": reported_requirements,
		"combat_report_locked": combat_report_locked,
		"combat_report_days": combat_report_days,
		"participant_offsets": participant_offsets,
		"participant_ids": participant_ids,
		"tactical_offsets": tactical_offsets,
		"tactical_city_ids": tactical_city_ids,
		"assignment_offsets": assignment_offsets,
		"assignment_army_ids": assignment_army_ids,
		"assignment_targets": assignment_targets,
	}


static func _build_armies(state: GameState) -> Dictionary:
	var ids := PackedInt32Array()
	var owner := PackedInt32Array()
	var size := PackedInt32Array()
	var max_size := PackedInt32Array()
	var speed_factor := PackedFloat64Array()
	var attack := PackedInt32Array()
	var defense := PackedInt32Array()
	var battle_group_id := PackedInt32Array()
	var states := PackedInt32Array()
	var location := PackedInt32Array()
	var move_from := PackedInt32Array()
	var move_to := PackedInt32Array()
	var battle_id := PackedInt32Array()
	var campaign_war_id := PackedInt32Array()
	var campaign_front_id := PackedInt32Array()
	var political_person_id := PackedInt32Array()
	var path_offsets := PackedInt32Array([0])
	var path_cities := PackedInt32Array()
	var path_cursor := PackedInt32Array()
	var move_progress := PackedFloat64Array()
	var morale := PackedFloat64Array()
	var max_morale := PackedFloat64Array()
	var supply_ratio := PackedFloat64Array()
	var supply_debt := PackedFloat64Array()
	var supply_food_debt := PackedFloat64Array()
	var holding_days := PackedInt32Array()
	var hold_target_progress := PackedFloat64Array()
	var defensive_deployment_until_day := PackedInt32Array()
	var defensive_blocked_edge_a := PackedInt32Array()
	var defensive_blocked_edge_b := PackedInt32Array()
	var occupation_claimant := PackedInt32Array()
	var ai_action := PackedInt32Array()
	var ai_target_city := PackedInt32Array()
	var ai_order_created_day := PackedInt32Array()
	var ai_order_until_day := PackedInt32Array()
	var ai_order_score := PackedFloat64Array()
	var on_edge := PackedByteArray()
	var encounter_blocked := PackedByteArray()
	var starving := PackedByteArray()
	var resume_holding_after_battle := PackedByteArray()
	var forced_retreat := PackedByteArray()
	var diplomatic_repatriation := PackedByteArray()
	var indices := {}
	for index in range(state.armies.size()):
		var army: Army = state.armies[index]
		indices[army] = index
		ids.append(army.id)
		owner.append(army.owner_nation)
		size.append(army.size)
		max_size.append(army.max_size)
		speed_factor.append(army.speed_factor)
		attack.append(army.attack)
		defense.append(army.defense)
		battle_group_id.append(army.battle_group_id)
		states.append(army.state)
		location.append(army.location_city)
		move_from.append(army.move_from)
		move_to.append(army.move_to)
		battle_id.append(army.battle_id)
		campaign_war_id.append(army.campaign_war_id)
		campaign_front_id.append(army.campaign_front_id)
		political_person_id.append(army.political_person_id)
		path_cities.append_array(PackedInt32Array(army.path))
		path_offsets.append(path_cities.size())
		path_cursor.append(0)
		move_progress.append(army.move_progress)
		morale.append(army.morale)
		max_morale.append(army.max_morale)
		supply_ratio.append(army.supply_ratio)
		supply_debt.append(army.supply_debt)
		supply_food_debt.append(army.supply_food_debt)
		holding_days.append(army.holding_days)
		hold_target_progress.append(army.hold_target_progress)
		defensive_deployment_until_day.append(
			army.defensive_deployment_until_day
		)
		defensive_blocked_edge_a.append(
			army.defensive_blocked_edge_a
		)
		defensive_blocked_edge_b.append(
			army.defensive_blocked_edge_b
		)
		occupation_claimant.append(
			army.occupation_claimant_nation
		)
		ai_action.append(army.ai_action)
		ai_target_city.append(army.ai_target_city)
		ai_order_created_day.append(army.ai_order_created_day)
		ai_order_until_day.append(army.ai_order_until_day)
		ai_order_score.append(army.ai_order_score)
		on_edge.append(int(army.on_edge))
		encounter_blocked.append(int(army.encounter_blocked))
		starving.append(int(army.starving))
		resume_holding_after_battle.append(
			int(army.resume_holding_after_battle)
		)
		forced_retreat.append(int(army.forced_retreat))
		diplomatic_repatriation.append(
			int(army.diplomatic_repatriation)
		)
	return {
		"indices": indices,
		"snapshot": {
			"count": state.armies.size(),
			"id": ids,
			"owner": owner,
			"political_person_id": political_person_id,
			"size": size,
			"max_size": max_size,
			"speed_factor": speed_factor,
			"attack": attack,
			"defense": defense,
			"battle_group_id": battle_group_id,
			"state": states,
			"location": location,
			"move_from": move_from,
			"move_to": move_to,
			"battle_id": battle_id,
			"campaign_war_id": campaign_war_id,
			"campaign_front_id": campaign_front_id,
			"path_offsets": path_offsets,
			"path_cities": path_cities,
			"path_cursor": path_cursor,
			"move_progress": move_progress,
			"morale": morale,
			"max_morale": max_morale,
			"supply_ratio": supply_ratio,
			"supply_debt": supply_debt,
			"supply_food_debt": supply_food_debt,
			"holding_days": holding_days,
			"hold_target_progress": hold_target_progress,
			"defensive_deployment_until_day":
				defensive_deployment_until_day,
			"defensive_blocked_edge_a":
				defensive_blocked_edge_a,
			"defensive_blocked_edge_b":
				defensive_blocked_edge_b,
			"occupation_claimant": occupation_claimant,
			"ai_action": ai_action,
			"ai_target_city": ai_target_city,
			"ai_order_created_day": ai_order_created_day,
			"ai_order_until_day": ai_order_until_day,
			"ai_order_score": ai_order_score,
			"on_edge": on_edge,
			"encounter_blocked": encounter_blocked,
			"starving": starving,
			"resume_holding_after_battle":
				resume_holding_after_battle,
			"forced_retreat": forced_retreat,
			"diplomatic_repatriation":
				diplomatic_repatriation,
		},
	}


static func _build_battles(
	state: GameState,
	edge_indices: Dictionary,
	army_indices: Dictionary
) -> Dictionary:
	var ids := PackedInt32Array()
	var kind := PackedInt32Array()
	var edge_index := PackedInt32Array()
	var city_index := PackedInt32Array()
	var contact_dist_a := PackedFloat64Array()
	var contact_dist_b := PackedFloat64Array()
	var holding_side := PackedInt32Array()
	var holding_days := PackedFloat64Array()
	var round_no := PackedInt32Array()
	var field_dice: Array[PackedInt32Array] = []
	var assault_dice: Array[PackedInt32Array] = []
	var field_sequence := PackedInt32Array()
	var assault_sequence := PackedInt32Array()
	var side_b_defends_city := PackedByteArray()
	var uses_field_combat_rules := PackedByteArray()
	var finished := PackedByteArray()
	var winner_side := PackedInt32Array()
	var field_rout_attrition_multiplier := PackedFloat64Array()
	var side_a_offsets := PackedInt32Array([0])
	var side_a_armies := PackedInt32Array()
	var side_b_offsets := PackedInt32Array([0])
	var side_b_armies := PackedInt32Array()
	var fresh_a_offsets := PackedInt32Array([0])
	var fresh_a_armies := PackedInt32Array()
	var fresh_b_offsets := PackedInt32Array([0])
	var fresh_b_armies := PackedInt32Array()
	var routed_a_offsets := PackedInt32Array([0])
	var routed_a_armies := PackedInt32Array()
	var routed_b_offsets := PackedInt32Array([0])
	var routed_b_armies := PackedInt32Array()
	var side_a_priority := PackedInt32Array()
	var side_b_priority := PackedInt32Array()
	for battle in state.battles:
		ids.append(battle.id)
		kind.append(battle.kind)
		edge_index.append(
			int(edge_indices.get(battle.edge, -1))
		)
		city_index.append(
			battle.city.id if battle.city != null else -1
		)
		contact_dist_a.append(battle.contact_dist_a)
		contact_dist_b.append(battle.contact_dist_b)
		holding_side.append(battle.holding_side)
		holding_days.append(battle.holding_days)
		round_no.append(battle.round_no)
		field_dice.append(battle.field_dice.duplicate())
		assault_dice.append(battle.assault_dice.duplicate())
		field_sequence.append(battle.field_sequence)
		assault_sequence.append(battle.assault_sequence)
		side_b_defends_city.append(int(battle.side_b_defends_city))
		uses_field_combat_rules.append(int(
			battle.uses_field_combat_rules()
		))
		finished.append(int(battle.finished))
		winner_side.append(battle.winner_side)
		field_rout_attrition_multiplier.append(
			battle.field_rout_attrition_multiplier
		)
		for army in battle.side_a:
			side_a_armies.append(
				int(army_indices.get(army, -1))
			)
			side_a_priority.append(
				int(battle.frontline_priority_a.get(
					army,
					1 << 30
				))
			)
		side_a_offsets.append(side_a_armies.size())
		for army in battle.side_b:
			side_b_armies.append(
				int(army_indices.get(army, -1))
			)
			side_b_priority.append(
				int(battle.frontline_priority_b.get(
					army,
					1 << 30
				))
			)
		side_b_offsets.append(side_b_armies.size())
		for army in battle.reinforce_fresh_a:
			fresh_a_armies.append(
				int(army_indices.get(army, -1))
			)
		fresh_a_offsets.append(fresh_a_armies.size())
		for army in battle.reinforce_fresh_b:
			fresh_b_armies.append(
				int(army_indices.get(army, -1))
			)
		fresh_b_offsets.append(fresh_b_armies.size())
		for army in battle.routed_a:
			routed_a_armies.append(
				int(army_indices.get(army, -1))
			)
		routed_a_offsets.append(routed_a_armies.size())
		for army in battle.routed_b:
			routed_b_armies.append(
				int(army_indices.get(army, -1))
			)
		routed_b_offsets.append(routed_b_armies.size())
	return {
		"count": state.battles.size(),
		"id": ids,
		"kind": kind,
		"edge_index": edge_index,
		"city_index": city_index,
		"contact_dist_a": contact_dist_a,
		"contact_dist_b": contact_dist_b,
		"holding_side": holding_side,
		"holding_days": holding_days,
		"round_no": round_no,
		"field_dice": field_dice,
		"assault_dice": assault_dice,
		"field_sequence": field_sequence,
		"assault_sequence": assault_sequence,
		"side_b_defends_city": side_b_defends_city,
		"uses_field_combat_rules": uses_field_combat_rules,
		"finished": finished,
		"winner_side": winner_side,
		"field_rout_attrition_multiplier": field_rout_attrition_multiplier,
		"side_a_offsets": side_a_offsets,
		"side_a_armies": side_a_armies,
		"side_b_offsets": side_b_offsets,
		"side_b_armies": side_b_armies,
		"fresh_a_offsets": fresh_a_offsets,
		"fresh_a_armies": fresh_a_armies,
		"fresh_b_offsets": fresh_b_offsets,
		"fresh_b_armies": fresh_b_armies,
		"routed_a_offsets": routed_a_offsets,
		"routed_a_armies": routed_a_armies,
		"routed_b_offsets": routed_b_offsets,
		"routed_b_armies": routed_b_armies,
		"side_a_priority": side_a_priority,
		"side_b_priority": side_b_priority,
	}
