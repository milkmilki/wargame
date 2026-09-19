class_name CityOutputRules
extends RefCounted
## 城市非贸易产值的纯计算规则。经济结算和贸易中心选举共同使用此处，
## 避免两套“城市产值”口径随平衡调整逐渐分叉。

const CITY_WAR_OUTPUT_MULTIPLIER: float = 0.50
const VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER: float = 1.50
const CAPITAL_NATIONAL_GOLD_SHARE: float = 0.20


static func city_gold_outputs(game_state: GameState) -> PackedInt32Array:
	var result := PackedInt32Array()
	if game_state == null:
		return result
	result.resize(game_state.cities.size())
	var modifiers_by_nation: Array[Dictionary] = []
	for nation in game_state.nations:
		modifiers_by_nation.append(RulerProfile.modifiers(nation))
	for city in game_state.cities:
		if city.id < 0 or city.id >= result.size():
			continue
		var modifiers: Dictionary = (
			modifiers_by_nation[city.owner_nation]
			if (
				city.owner_nation >= 0
				and city.owner_nation < modifiers_by_nation.size()
			)
			else {}
		)
		result[city.id] = city_gold_output(game_state, city, modifiers)
	return result


static func city_potential_gold_outputs(game_state: GameState) -> PackedInt32Array:
	var result := PackedInt32Array()
	if game_state == null:
		return result
	result.resize(game_state.cities.size())
	var modifiers_by_nation: Array[Dictionary] = []
	for nation in game_state.nations:
		modifiers_by_nation.append(RulerProfile.modifiers(nation))
	for city in game_state.cities:
		if city.id < 0 or city.id >= result.size():
			continue
		var modifiers: Dictionary = (
			modifiers_by_nation[city.owner_nation]
			if (
				city.owner_nation >= 0
				and city.owner_nation < modifiers_by_nation.size()
			)
			else {}
		)
		result[city.id] = city_potential_gold_output(
			game_state, city, modifiers
		)
	return result


static func city_gold_output(
	game_state: GameState,
	city: City,
	ruler_modifiers: Dictionary = {}
) -> int:
	if game_state == null or city == null:
		return 0
	if not game_state.city_administrative_output_enabled(city.id):
		return 0
	var output := city_gold_output_before_governance(game_state, city)
	output = maxi(int(floor(
		float(output) * city_governance_output_multiplier(game_state, city)
	)), 0)
	if (
		city.owner_nation < 0
		or city.owner_nation >= game_state.nations.size()
	):
		return output
	var modifiers := (
		ruler_modifiers
		if not ruler_modifiers.is_empty()
		else RulerProfile.modifiers(game_state.nations[city.owner_nation])
	)
	return maxi(int(floor(
		float(output)
			* float(modifiers.get(RulerProfile.KEY_GOLD_OUTPUT, 1.0))
	)), 0)


static func city_potential_gold_output(
	game_state: GameState,
	city: City,
	ruler_modifiers: Dictionary = {}
) -> int:
	if game_state == null or city == null:
		return 0
	var output := city_gold_output_before_governance(
		game_state, city, false
	)
	output = maxi(int(floor(
		float(output) * city_governance_output_multiplier(game_state, city)
	)), 0)
	if city.owner_nation < 0 or city.owner_nation >= game_state.nations.size():
		return output
	var modifiers := (
		ruler_modifiers
		if not ruler_modifiers.is_empty()
		else RulerProfile.modifiers(game_state.nations[city.owner_nation])
	)
	return maxi(int(floor(
		float(output)
			* float(modifiers.get(RulerProfile.KEY_GOLD_OUTPUT, 1.0))
	)), 0)


static func city_gold_output_before_governance(
	game_state: GameState,
	city: City,
	respect_administration: bool = true
) -> int:
	if (
		respect_administration
		and not game_state.city_administrative_output_enabled(city.id)
	):
		return 0
	var output := city.gold_per_month
	output += capital_national_gold_addition(
		game_state, city, respect_administration
	)
	if city_war_disrupted(game_state, city):
		output = int(floor(float(output) * CITY_WAR_OUTPUT_MULTIPLIER))
	return maxi(output, 0)


static func capital_national_gold_addition(
	game_state: GameState,
	city: City,
	respect_administration: bool = true
) -> int:
	if (
		game_state == null
		or city == null
		or not city.is_capital
		or city.owner_nation < 0
		or city.owner_nation >= game_state.nations.size()
		or game_state.nations[city.owner_nation].capital_city_id != city.id
	):
		return 0
	var national_base_gold := 0
	for owned_city in game_state.land_cities_of(city.owner_nation):
		if (
			respect_administration
			and not game_state.city_administrative_output_enabled(owned_city.id)
		):
			continue
		national_base_gold += maxi(owned_city.gold_per_month, 0)
	return int(floor(
		float(national_base_gold) * CAPITAL_NATIONAL_GOLD_SHARE
	))


static func city_governance_output_multiplier(
	game_state: GameState,
	city: City
) -> float:
	if (
		game_state == null
		or city == null
		or city.owner_nation < 0
		or city.owner_nation >= game_state.nations.size()
		or not game_state.is_vassal(city.owner_nation)
	):
		return 1.0
	return VASSAL_GOVERNANCE_OUTPUT_MULTIPLIER


static func city_war_disrupted(
	game_state: GameState,
	city: City
) -> bool:
	return (
		game_state != null
		and city != null
		and game_state.day < city.war_disruption_until_day
	)
