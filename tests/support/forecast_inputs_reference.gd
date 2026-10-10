extends RefCounted
var state: GameState
var cache: Dictionary
var flows: Array[Dictionary]
var armies: Dictionary
var garrison_index: Dictionary
var conservative_index: Dictionary
var garrison_food := {}
var food_output := {}
var manpower_output := {}
var capital_fields := {}
var garrison_contexts := {}
var inputs: Array[Dictionary] = []
var pools := {}
var phase := 0
var cursor := 0
func _init(source: GameState,values: Dictionary):
	state=source; cache=values
	if not cache.has("monthly_gold_flows"): cache.monthly_gold_flows=Simulation.monthly_gold_flows(state)
	flows=cache.monthly_gold_flows
	armies=ReinforcementRules.bucket_armies_by_nation(state,true)
	garrison_index=Simulation.build_garrison_index(state)
	conservative_index=garrison_index.duplicate()
func step() -> void:
	var count: int = state.cities.size() if phase==0 else state.administrative_center_city_ids.size() if phase==1 else state.nations.size()
	if cursor>=count: phase+=1; cursor=0; return
	match phase:
		0: city(state.cities[cursor])
		1: center(state.administrative_center_city_ids[cursor])
		2: nation(state.nations[cursor])
		3: pool(state.nations[cursor])
	cursor+=1
func city(city: City) -> void:
	if city.owner_nation < 0 or city.is_dock:
		return
	food_output[city.owner_nation] = int(food_output.get(city.owner_nation,0))+maxi(city.food_per_half_year,0)
	manpower_output[city.owner_nation] = int(manpower_output.get(city.owner_nation,0))+maxi(city.manpower_per_month,0)
	conservative_index[city.id] = int(ceil(float(city.manpower_per_month) * Simulation.CITY_GARRISON_CAPACITY_PER_MANPOWER * Simulation.CITY_GARRISON_FOOD_PENALTY_MAX / Simulation.CITY_GARRISON_FOOD_PENALTY_RATE))
func center(center_value: int) -> void:
	var center_id := int(center_value)
	var city := state.cities[center_id]
	if city.owner_nation >= 0:
		var owner := city.owner_nation
		if not capital_fields.has(owner):
			capital_fields[owner]=state.capital_hop_distances(owner)
			var nation := state.nations[owner]
			garrison_contexts[owner]={"administrative_radius":RebellionSystem.administrative_radius(nation),"upkeep_multiplier":RulerProfile.upkeep_multiplier(nation),"food_multiplier":RulerProfile.food_consumption_multiplier(nation)}
		garrison_food[owner] = int(garrison_food.get(owner, 0)) + int(Simulation.city_garrison_cost_report(state, owner, center_id, city.garrison_manpower, capital_fields[owner],garrison_contexts[owner]).food_demand)
func nation(nation: Nation) -> void:
	var ruler_modifiers := RulerProfile.modifiers(nation)
	var field := 0.0
	var troops := 0
	var base_upkeep := 0
	var consumers: Array = []
	var owned: Array = armies.get(nation.id, [])
	var refill := 0
	var consumption_multiplier := float(ruler_modifiers[RulerProfile.KEY_FOOD_CONSUMPTION])
	for army in owned:
		if army.size <= 0:
			continue
		troops += army.size
		base_upkeep += GameState.army_monthly_upkeep(army.size)
		var rate := float(TradeNetwork._projected_army_monthly_food_demand(army, nation, consumption_multiplier))
		field += rate
		consumers.append({"rate": rate, "debt": army.supply_food_debt})
		refill += mini(maxi(army.max_size - army.size, 0), ReinforcementRules.monthly_reinforcement_cap(army))
	var garrison := int(garrison_food.get(nation.id, 0))
	var settled := maxf(float(nation.last_food_demand), nation.food_demand_ema) - garrison
	var factor := maxf(settled, field) / maxf(field, 1)
	for consumer in consumers:
		consumer.rate = float(consumer.rate) * factor
	field *= factor
	var harvest := 0
	var conservative := 0
	for city in DiplomacyAI._cached_cities_of(state, nation.id, cache):
		harvest += Simulation.city_food_output(state, city, garrison_index, ruler_modifiers)
		conservative += Simulation.city_food_output(state, city, conservative_index, ruler_modifiers)
	var trade := DiplomacyAI._trade_report(state, nation.id, cache)
	var flow: Dictionary = flows[nation.id]
	var pool_id := state.food_pool_holder(nation.id)
	var manpower_capacity := 0
	for member in state.food_pool_members(nation.id): manpower_capacity+=int(manpower_output.get(member,0))*GameState.INITIAL_MANPOWER_RESERVE_MONTHS
	if not pools.has(pool_id):
		pools[pool_id] = {"field": 0.0, "garrison": 0, "harvest": 0, "trade": 0, "exports": 0, "consumers": []}
	var pool: Dictionary = pools[pool_id]
	pool.field += field
	pool.garrison += garrison
	pool.harvest += harvest
	pool.trade += int(trade.monthly_food_import) - int(trade.monthly_food_export)
	pool.exports += int(trade.monthly_food_export)
	pool.consumers.append_array(consumers)
	inputs.append({
		"day": state.day, "gold": nation.treasury_gold,
		"pending_supply_days": int(cache.get("__forecast_pending_supply", false)),
		"income": int(flow.net_income), "court": int(flow.court_expense_due),
		"upkeep": int(flow.military_upkeep), "field_upkeep": int(flow.field_army_upkeep),
		"necessary_gold": int(flow.court_expense_due) + int(flow.military_upkeep) + int(flow.tribute_paid) + int(flow.food_trade_expense) + int(flow.manpower_trade_expense),
		"troops": troops, "base_upkeep": base_upkeep, "army_count": owned.size(), "nation_field_food": field, "harvest_loss": maxi(harvest - conservative, 0),
		"manpower_target": mini(manpower_capacity, maxi(DiplomacyAI.MIN_MANPOWER_RESERVE, maxi(int(ceil(troops * 0.15)), refill))),
		"food_multiplier": consumption_multiplier, "upkeep_multiplier": float(ruler_modifiers[RulerProfile.KEY_UPKEEP]),
		"reserve_months_bonus": int(ruler_modifiers[RulerProfile.KEY_RESERVE_MONTHS]),
	})
func pool(nation: Nation) -> void:
	var pool_id := state.food_pool_holder(nation.id)
	var pool: Dictionary = pools[pool_id]
	var input: Dictionary = inputs[nation.id]
	input.field_food = pool.field
	input.garrison_food = pool.garrison
	input.harvest = pool.harvest
	input.trade_food = pool.trade
	input.export_food = pool.exports
	input.consumers = pool.consumers
	if not pool.has("consumption"):
		var consumption := {}
		var first_event := (state.day / 30 + 1) * 30
		var pending_days := int(input.pending_supply_days)
		var elapsed_days: Array[int] = [pending_days, 359 + pending_days, 360 + pending_days]
		for event in range(first_event, state.day + 361, 30):
			elapsed_days.append(maxi(event - state.day - 1, 0) + pending_days)
			elapsed_days.append(event - state.day + pending_days)
		for elapsed in elapsed_days:
			if not consumption.has(elapsed):
				var amount := 0.0
				for consumer in pool.consumers:
					amount += floor(float(consumer.rate) * elapsed / 30.0 + float(consumer.debt) + 0.000001)
				if pool.consumers.is_empty():
					amount = floor(float(pool.field) * elapsed / 30.0 + 0.000001)
				consumption[elapsed] = amount
		pool.consumption = consumption
	input.consumption = pool.consumption
	input.food = DiplomacyAI._food_stock(state, pool_id, cache)
	var storage_capacity := 0
	for member in state.food_pool_members(pool_id): storage_capacity+=int(food_output.get(member,0))*GameState.FOOD_CAPACITY_HALF_YEARS
	input.food_capacity = storage_capacity
