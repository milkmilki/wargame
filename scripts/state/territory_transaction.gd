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


static func _failure(error: String) -> Dictionary:
	return {
		"ok": false, "changed": false,
		"territory_changed": false,
		"political_changed": false,
		"diplomacy_changed": false,
		"error": error,
		"changed_city_ids": [] as Array[int],
	}
