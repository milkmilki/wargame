extends RefCounted
## Builds the territory tuple snapshot used by GameState's atomic transaction.
## This module only reads the current state and never commits mutations.


static func plan_operations(
	cities: Array,
	recognized_city_owners: Array[int],
	nation_count: int,
	operations: Array[Dictionary],
	day: int,
	rebellion_cooldown_days: int,
	default_stock_policy: int,
	allowed_stock_policies: Array[int]
) -> Dictionary:
	var snapshot := _snapshot_territory_tuples(
		cities, recognized_city_owners, nation_count
	)
	if not bool(snapshot.get("ok", false)):
		return snapshot
	var planned_owners: Array[int] = snapshot["planned_owners"]
	var planned_legal_owners: Array[int] = snapshot["planned_legal_owners"]
	var planned_sponsors: Array[int] = snapshot["planned_sponsors"]
	var normalized := _normalize_operations(
		cities,
		recognized_city_owners,
		nation_count,
		operations,
		day,
		rebellion_cooldown_days,
		default_stock_policy,
		allowed_stock_policies,
		planned_owners,
		planned_legal_owners,
		planned_sponsors
	)
	if not bool(normalized.get("ok", false)):
		return normalized
	if not _territory_tuples_valid(
		planned_owners, planned_legal_owners, planned_sponsors, nation_count
	):
		return _failure("最终领土三元组无效。")
	return {
		"ok": true,
		"planned_owners": planned_owners,
		"planned_legal_owners": planned_legal_owners,
		"planned_sponsors": planned_sponsors,
		"normalized_operations": normalized["normalized_operations"],
		"changed_city_ids": normalized["changed_city_ids"],
	}


static func _snapshot_territory_tuples(
	cities: Array,
	recognized_city_owners: Array[int],
	nation_count: int
) -> Dictionary:
	var planned_owners: Array[int] = []
	var planned_legal_owners: Array[int] = []
	var planned_sponsors: Array[int] = []
	planned_owners.resize(cities.size())
	planned_legal_owners.resize(cities.size())
	planned_sponsors.resize(cities.size())
	for city in cities:
		if (
			city.id < 0
			or city.id >= cities.size()
			or city.owner_nation < 0
			or city.owner_nation >= nation_count
			or recognized_city_owners[city.id] < 0
			or recognized_city_owners[city.id] >= nation_count
			or city.occupation_sponsor_nation < -1
			or city.occupation_sponsor_nation >= nation_count
		):
			return _failure("现有领土三元组包含无效国家。")
		planned_owners[city.id] = city.owner_nation
		planned_legal_owners[city.id] = recognized_city_owners[city.id]
		planned_sponsors[city.id] = city.occupation_sponsor_nation
	return {
		"ok": true,
		"planned_owners": planned_owners,
		"planned_legal_owners": planned_legal_owners,
		"planned_sponsors": planned_sponsors,
	}


static func _normalize_operations(
	cities: Array,
	recognized_city_owners: Array[int],
	nation_count: int,
	operations: Array[Dictionary],
	day: int,
	rebellion_cooldown_days: int,
	default_stock_policy: int,
	allowed_stock_policies: Array[int],
	planned_owners: Array[int],
	planned_legal_owners: Array[int],
	planned_sponsors: Array[int]
) -> Dictionary:
	var normalized_operations: Array[Dictionary] = []
	var operation_by_city := {}
	var changed_city_ids: Array[int] = []
	for operation in operations:
		if not operation.has("city_id"):
			return _failure("领土操作缺少 city_id。")
		var city_id := int(operation["city_id"])
		if (
			city_id < 0
			or city_id >= cities.size()
			or operation_by_city.has(city_id)
		):
			return _failure("领土操作包含无效或重复城市。")
		var city = cities[city_id]
		var controller_id: int = city.owner_nation
		if operation.has("controller_id"):
			controller_id = int(operation["controller_id"])
		elif operation.has("owner_nation"):
			controller_id = int(operation["owner_nation"])
		var legal_owner_id := recognized_city_owners[city_id]
		if operation.has("legal_owner_id"):
			legal_owner_id = int(operation["legal_owner_id"])
		elif operation.has("legal_owner_nation"):
			legal_owner_id = int(operation["legal_owner_nation"])
		var sponsor_id: int = city.occupation_sponsor_nation
		if operation.has("sponsor_id"):
			sponsor_id = int(operation["sponsor_id"])
		elif operation.has("occupation_sponsor_nation"):
			sponsor_id = int(operation["occupation_sponsor_nation"])
		if (
			controller_id < 0
			or controller_id >= nation_count
			or legal_owner_id < 0
			or legal_owner_id >= nation_count
		):
			return _failure("领土操作包含无效国家。")
		if controller_id == legal_owner_id:
			sponsor_id = -1
		elif sponsor_id < 0 or sponsor_id >= nation_count:
			return _failure("临时占领必须指定有效的战争结算责任方。")
		var stock_policy := int(operation.get(
			"stock_policy", default_stock_policy
		))
		if stock_policy not in allowed_stock_policies:
			return _failure("未知的领土库存结算策略。")
		var reset_target := bool(operation.get(
			"reset_political_target", false
		))
		var reason := str(operation.get("reason", "territory_transfer"))
		var cooldown_until: int = city.rebellion_cooldown_until_day
		if reset_target:
			cooldown_until = maxi(
				cooldown_until,
				day + rebellion_cooldown_days
			)
		var operation_changed: bool = (
			city.owner_nation != controller_id
			or recognized_city_owners[city_id] != legal_owner_id
			or city.occupation_sponsor_nation != sponsor_id
			or (
				reset_target
				and (
					city.loyalty_target_nation != legal_owner_id
					or not is_zero_approx(city.loyalty_trend)
					or city.unrest != 100.0 - city.loyalty
					or city.rebellion_progress != 0
					or city.rebellion_cooldown_until_day != cooldown_until
					or city.last_loyalty_reason != reason
				)
			)
		)
		var normalized := {
			"city_id": city_id,
			"controller_id": controller_id,
			"legal_owner_id": legal_owner_id,
			"sponsor_id": sponsor_id,
			"reset_political_target": reset_target,
			"cooldown_until": cooldown_until,
			"reason": reason,
			"stock_policy": stock_policy,
		}
		normalized_operations.append(normalized)
		operation_by_city[city_id] = normalized
		planned_owners[city_id] = controller_id
		planned_legal_owners[city_id] = legal_owner_id
		planned_sponsors[city_id] = sponsor_id
		if operation_changed:
			changed_city_ids.append(city_id)
	return {
		"ok": true,
		"normalized_operations": normalized_operations,
		"changed_city_ids": changed_city_ids,
	}


static func _territory_tuples_valid(
	planned_owners: Array[int],
	planned_legal_owners: Array[int],
	planned_sponsors: Array[int],
	nation_count: int
) -> bool:
	for city_id in range(planned_owners.size()):
		var owner_id := planned_owners[city_id]
		var legal_id := planned_legal_owners[city_id]
		var sponsor_id := planned_sponsors[city_id]
		if (
			owner_id < 0 or owner_id >= nation_count
			or legal_id < 0 or legal_id >= nation_count
			or (owner_id == legal_id and sponsor_id != -1)
			or (
				owner_id != legal_id
				and (sponsor_id < 0 or sponsor_id >= nation_count)
			)
		):
			return false
	return true


static func plan_diplomacy(
	planned_suzerainty: Dictionary,
	diplomatic_operations: Array[Dictionary],
	nation_count: int,
	diplomatic_relations: Dictionary,
	diplomatic_since_day: Dictionary,
	truce_until_day: Dictionary,
	day: int,
	neutral_relation: int,
	war_relation: int,
	allied_relation: int,
	regional_peace_locked: Callable
) -> Dictionary:
	var normalized := _normalize_diplomatic_operations(
		diplomatic_operations,
		nation_count,
		diplomatic_relations,
		war_relation,
		neutral_relation,
		allied_relation,
		regional_peace_locked
	)
	if not bool(normalized.get("ok", false)):
		return normalized
	var explicit_relations: Dictionary = normalized["explicit_relations"]
	var conflict := _validate_suzerainty_relations(
		planned_suzerainty,
		explicit_relations,
		war_relation,
		allied_relation
	)
	if not bool(conflict.get("ok", false)):
		return conflict

	var planned_relations := diplomatic_relations.duplicate(true)
	var planned_since := diplomatic_since_day.duplicate(true)
	var planned_truce := truce_until_day.duplicate(true)
	_apply_explicit_relations(
		explicit_relations,
		diplomatic_relations,
		planned_relations,
		planned_since,
		planned_truce,
		day,
		war_relation
	)
	_apply_suzerainty_relations(
		planned_suzerainty,
		explicit_relations,
		diplomatic_relations,
		planned_relations,
		planned_since,
		planned_truce,
		day,
		war_relation,
		allied_relation
	)
	return {
		"ok": true,
		"planned_relations": planned_relations,
		"planned_since": planned_since,
		"planned_truce": planned_truce,
		"changed": (
			planned_relations != diplomatic_relations
			or planned_since != diplomatic_since_day
			or planned_truce != truce_until_day
		),
	}


static func plan_structure(
	cities: Array,
	nations: Array,
	planned_owners: Array[int],
	final_city_counts: Array[int],
	planned_suzerainty: Dictionary,
	preferred_capitals: Dictionary,
	select_capital: Callable,
	select_pool_holder: Callable
) -> Dictionary:
	var preferred := _normalize_preferred_capitals(
		cities, nations.size(), planned_owners, preferred_capitals
	)
	if not bool(preferred.get("ok", false)):
		return preferred
	var capitals := _plan_capitals(
		nations,
		planned_owners,
		final_city_counts,
		preferred["capitals"],
		select_capital
	)
	if not bool(capitals.get("ok", false)):
		return capitals
	var planned_capitals: Array[int] = capitals["planned_capitals"]
	var pools := _plan_pool_holders(
		nations,
		final_city_counts,
		planned_suzerainty,
		planned_capitals,
		select_pool_holder
	)
	if not bool(pools.get("ok", false)):
		return pools
	var final_pool_holders: Array[int] = pools["final_pool_holders"]
	return {
		"ok": true,
		"planned_capitals": planned_capitals,
		"final_pool_holders": final_pool_holders,
		"planned_warehouse_flags": _plan_warehouse_flags(
			cities,
			nations,
			planned_owners,
			final_city_counts,
			planned_capitals,
			final_pool_holders
		),
	}


static func plan_food_ledger(
	cities: Array,
	nations: Array,
	normalized_operations: Array[Dictionary],
	planned_owners: Array[int],
	final_city_counts: Array[int],
	requested_suzerainty: Dictionary,
	final_pool_holders: Array[int],
	planned_capitals: Array[int],
	planned_warehouse_flags: Array[bool],
	return_to_old_pool_policy: int,
	move_to_new_pool_policy: int,
	capture_spoils_policy: int,
	destroy_policy: int,
	capture_spoils_rate: float,
	select_pool_holder: Callable
) -> Dictionary:
	var planned_food: Array[int] = []
	planned_food.resize(cities.size())
	for city in cities:
		planned_food[city.id] = city.food_storage
	var stock_credits := {}
	var moved_stock := _settle_moved_city_stock(
		cities,
		nations.size(),
		normalized_operations,
		final_city_counts,
		requested_suzerainty,
		final_pool_holders,
		planned_capitals,
		planned_warehouse_flags,
		planned_food,
		stock_credits,
		return_to_old_pool_policy,
		move_to_new_pool_policy,
		capture_spoils_policy,
		destroy_policy,
		capture_spoils_rate,
		select_pool_holder
	)
	if not bool(moved_stock.get("ok", false)):
		return moved_stock
	var removed_stock := _return_removed_warehouse_stock(
		cities,
		planned_owners,
		final_pool_holders,
		planned_capitals,
		planned_warehouse_flags,
		planned_food,
		stock_credits
	)
	if not bool(removed_stock.get("ok", false)):
		return removed_stock
	_return_subject_capital_stock(
		nations,
		final_city_counts,
		final_pool_holders,
		planned_capitals,
		planned_food,
		stock_credits
	)
	for recipient_value in stock_credits:
		var recipient := int(recipient_value)
		planned_food[planned_capitals[recipient]] += int(
			stock_credits[recipient_value]
		)
	return {"ok": true, "planned_food": planned_food}


static func _settle_moved_city_stock(
	cities: Array,
	nation_count: int,
	normalized_operations: Array[Dictionary],
	final_city_counts: Array[int],
	requested_suzerainty: Dictionary,
	final_pool_holders: Array[int],
	planned_capitals: Array[int],
	planned_warehouse_flags: Array[bool],
	planned_food: Array[int],
	stock_credits: Dictionary,
	return_to_old_pool_policy: int,
	move_to_new_pool_policy: int,
	capture_spoils_policy: int,
	destroy_policy: int,
	capture_spoils_rate: float,
	select_pool_holder: Callable
) -> Dictionary:
	for normalized in normalized_operations:
		var city_id := int(normalized["city_id"])
		var city = cities[city_id]
		if city.owner_nation == int(normalized["controller_id"]):
			continue
		var stock: int = city.food_storage
		planned_food[city_id] = 0
		if stock <= 0:
			continue
		var policy := int(normalized["stock_policy"])
		var recipient := -1
		var credited := stock
		if policy == return_to_old_pool_policy:
			recipient = int(select_pool_holder.call(
				city.owner_nation, final_city_counts, requested_suzerainty
			))
		elif policy == move_to_new_pool_policy:
			recipient = final_pool_holders[int(normalized["controller_id"])]
		elif policy == capture_spoils_policy:
			recipient = final_pool_holders[int(normalized["controller_id"])]
			credited = int(floor(float(stock) * capture_spoils_rate))
		elif policy == destroy_policy:
			credited = 0
		if credited <= 0:
			continue
		if (
			recipient < 0
			or recipient >= nation_count
			or final_city_counts[recipient] <= 0
			or planned_capitals[recipient] < 0
			or not planned_warehouse_flags[planned_capitals[recipient]]
		):
			return _failure("库存策略在最终版图中没有可入账粮池。")
		stock_credits[recipient] = (
			int(stock_credits.get(recipient, 0)) + credited
		)
	return {"ok": true}


static func _return_removed_warehouse_stock(
	cities: Array,
	planned_owners: Array[int],
	final_pool_holders: Array[int],
	planned_capitals: Array[int],
	planned_warehouse_flags: Array[bool],
	planned_food: Array[int],
	stock_credits: Dictionary
) -> Dictionary:
	for city in cities:
		if (
			city.owner_nation != planned_owners[city.id]
			or not city.has_warehouse
			or planned_warehouse_flags[city.id]
		):
			continue
		var stock := planned_food[city.id]
		planned_food[city.id] = 0
		if stock <= 0:
			continue
		var recipient := final_pool_holders[planned_owners[city.id]]
		if recipient < 0 or planned_capitals[recipient] < 0:
			return _failure("被摘除粮仓的库存没有可入账粮池。")
		stock_credits[recipient] = (
			int(stock_credits.get(recipient, 0)) + stock
		)
	return {"ok": true}


static func _return_subject_capital_stock(
	nations: Array,
	final_city_counts: Array[int],
	final_pool_holders: Array[int],
	planned_capitals: Array[int],
	planned_food: Array[int],
	stock_credits: Dictionary
) -> void:
	for nation in nations:
		if (
			final_city_counts[nation.id] <= 0
			or final_pool_holders[nation.id] == nation.id
		):
			continue
		var capital_id := planned_capitals[nation.id]
		var stock := planned_food[capital_id]
		planned_food[capital_id] = 0
		if stock > 0:
			var recipient := final_pool_holders[nation.id]
			stock_credits[recipient] = (
				int(stock_credits.get(recipient, 0)) + stock
			)


static func _normalize_preferred_capitals(
	cities: Array,
	nation_count: int,
	planned_owners: Array[int],
	preferred_capitals: Dictionary
) -> Dictionary:
	var normalized := {}
	for nation_value in preferred_capitals:
		var nation_id := int(nation_value)
		var preferred_id := int(preferred_capitals[nation_value])
		if (
			nation_id < 0 or nation_id >= nation_count
			or preferred_id < 0 or preferred_id >= cities.size()
			or planned_owners[preferred_id] != nation_id
			or cities[preferred_id].is_dock
		):
			return _failure("preferred_capitals 包含无效首都。")
		normalized[nation_id] = preferred_id
	return {"ok": true, "capitals": normalized}


static func _plan_capitals(
	nations: Array,
	planned_owners: Array[int],
	final_city_counts: Array[int],
	preferred_capitals: Dictionary,
	select_capital: Callable
) -> Dictionary:
	var planned_capitals: Array[int] = []
	planned_capitals.resize(nations.size())
	planned_capitals.fill(-1)
	for nation in nations:
		if final_city_counts[nation.id] <= 0:
			continue
		planned_capitals[nation.id] = int(select_capital.call(
			nation.id,
			planned_owners,
			int(preferred_capitals.get(nation.id, -1))
		))
		if planned_capitals[nation.id] < 0:
			return _failure("无法为有城国家规划首都。")
	return {"ok": true, "planned_capitals": planned_capitals}


static func _plan_pool_holders(
	nations: Array,
	final_city_counts: Array[int],
	planned_suzerainty: Dictionary,
	planned_capitals: Array[int],
	select_pool_holder: Callable
) -> Dictionary:
	var final_pool_holders: Array[int] = []
	final_pool_holders.resize(nations.size())
	final_pool_holders.fill(-1)
	for nation in nations:
		if final_city_counts[nation.id] <= 0:
			continue
		var holder_id := int(select_pool_holder.call(
			nation.id, final_city_counts, planned_suzerainty
		))
		if (
			holder_id < 0
			or holder_id >= nations.size()
			or final_city_counts[holder_id] <= 0
			or planned_capitals[holder_id] < 0
		):
			return _failure("领土操作后的粮池持有者没有可用首都。")
		final_pool_holders[nation.id] = holder_id
	return {"ok": true, "final_pool_holders": final_pool_holders}


static func _plan_warehouse_flags(
	cities: Array,
	nations: Array,
	planned_owners: Array[int],
	final_city_counts: Array[int],
	planned_capitals: Array[int],
	final_pool_holders: Array[int]
) -> Array[bool]:
	var flags: Array[bool] = []
	flags.resize(cities.size())
	flags.fill(false)
	for city in cities:
		var final_owner := planned_owners[city.id]
		flags[city.id] = (
			not city.is_dock
			and city.has_warehouse
			and city.owner_nation == final_owner
			and final_pool_holders[final_owner] == final_owner
		)
	for nation in nations:
		if (
			final_city_counts[nation.id] > 0
			and final_pool_holders[nation.id] == nation.id
		):
			flags[planned_capitals[nation.id]] = true
	return flags


static func _normalize_diplomatic_operations(
	operations: Array[Dictionary],
	nation_count: int,
	current_relations: Dictionary,
	war_relation: int,
	neutral_relation: int,
	allied_relation: int,
	regional_peace_locked: Callable
) -> Dictionary:
	var explicit_relations := {}
	for operation in operations:
		if (
			not operation.has("nation_a")
			or not operation.has("nation_b")
			or not operation.has("relation")
			or typeof(operation.get("nation_a")) != TYPE_INT
			or typeof(operation.get("nation_b")) != TYPE_INT
			or typeof(operation.get("relation")) != TYPE_INT
			or (
				operation.has("truce_days")
				and typeof(operation.get("truce_days")) != TYPE_INT
			)
		):
			return _failure("外交操作缺少国家或关系字段。")
		var nation_a := int(operation["nation_a"])
		var nation_b := int(operation["nation_b"])
		var relation := int(operation["relation"])
		var truce_days := int(operation.get("truce_days", 0))
		if (
			nation_a < 0 or nation_a >= nation_count
			or nation_b < 0 or nation_b >= nation_count
			or nation_a == nation_b
			or relation not in [
				neutral_relation, war_relation, allied_relation,
			]
			or truce_days < 0
		):
			return _failure("外交操作包含无效国家、关系或停战期。")
		var key := _diplomacy_key(nation_a, nation_b)
		if (
			relation != war_relation
			and int(current_relations.get(key, war_relation)) == war_relation
			and bool(regional_peace_locked.call(nation_a, nation_b))
		):
			return _failure("地方叛乱战争尚未满一年。")
		if explicit_relations.has(key):
			return _failure("外交操作包含重复国家对。")
		explicit_relations[key] = {
			"relation": relation, "truce_days": truce_days,
		}
	return {"ok": true, "explicit_relations": explicit_relations}


static func _validate_suzerainty_relations(
	planned_suzerainty: Dictionary,
	explicit_relations: Dictionary,
	war_relation: int,
	allied_relation: int
) -> Dictionary:
	for subject_value in planned_suzerainty:
		var subject_id := int(subject_value)
		var record: Dictionary = planned_suzerainty[subject_id]
		var key := _diplomacy_key(subject_id, int(record["overlord_id"]))
		var expected_relation := (
			war_relation
			if bool(record.get("civil_war", false))
			else allied_relation
		)
		if (
			explicit_relations.has(key)
			and int((explicit_relations[key] as Dictionary)["relation"])
				!= expected_relation
		):
			return _failure("显式外交操作与最终宗藩关系冲突。")
	return {"ok": true}


static func _apply_explicit_relations(
	explicit_relations: Dictionary,
	current_relations: Dictionary,
	planned_relations: Dictionary,
	planned_since: Dictionary,
	planned_truce: Dictionary,
	day: int,
	war_relation: int
) -> void:
	for key_value in explicit_relations:
		var key := str(key_value)
		var operation: Dictionary = explicit_relations[key_value]
		var relation := int(operation["relation"])
		var previous_relation := int(current_relations.get(key, war_relation))
		if previous_relation != relation:
			planned_relations[key] = relation
			planned_since[key] = day
			if previous_relation == war_relation and relation != war_relation:
				planned_truce[key] = maxi(
					int(planned_truce.get(key, 0)),
					day + int(operation["truce_days"])
				)


static func _apply_suzerainty_relations(
	planned_suzerainty: Dictionary,
	explicit_relations: Dictionary,
	current_relations: Dictionary,
	planned_relations: Dictionary,
	planned_since: Dictionary,
	planned_truce: Dictionary,
	day: int,
	war_relation: int,
	allied_relation: int
) -> void:
	for subject_value in planned_suzerainty:
		var subject_id := int(subject_value)
		var record: Dictionary = planned_suzerainty[subject_id]
		var key := _diplomacy_key(subject_id, int(record["overlord_id"]))
		if explicit_relations.has(key):
			continue
		var relation := (
			war_relation
			if bool(record.get("civil_war", false))
			else allied_relation
		)
		var previous_relation := int(current_relations.get(key, war_relation))
		if previous_relation == relation:
			continue
		planned_relations[key] = relation
		planned_since[key] = day
		if previous_relation == war_relation and relation != war_relation:
			planned_truce[key] = maxi(int(planned_truce.get(key, 0)), day)


static func _diplomacy_key(nation_a: int, nation_b: int) -> String:
	return "%d:%d" % [mini(nation_a, nation_b), maxi(nation_a, nation_b)]


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false, "changed": false,
		"territory_changed": false,
		"political_changed": false,
		"diplomacy_changed": false,
		"error": error,
		"changed_city_ids": [] as Array[int],
	}
