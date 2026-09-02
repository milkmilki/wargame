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

	for city_id in range(cities.size()):
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
			return _failure("最终领土三元组无效。")

	return {
		"ok": true,
		"planned_owners": planned_owners,
		"planned_legal_owners": planned_legal_owners,
		"planned_sponsors": planned_sponsors,
		"normalized_operations": normalized_operations,
		"changed_city_ids": changed_city_ids,
	}


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
