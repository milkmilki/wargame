class_name ArmyPower
extends RefCounted
## AI 战力估算。只用于规划，不替代 Combat 的真实解算。


static func effective(army: Army) -> float:
	if army == null or army.size <= 0:
		return 0.0
	var quality := sqrt(maxf(float(army.attack * army.defense), 1.0)) / 10.0
	var morale_factor := clampf(army.morale, 0.0, 1.0)
	var supply_factor := 0.5 + 0.5 * clampf(army.supply_ratio, 0.0, 1.0)
	return float(army.size) * quality * morale_factor * supply_factor


static func city_defense(city: City) -> float:
	return float(maxi(city.defense, 0)) * 10.0


static func combined(armies: Array[Army]) -> float:
	var total := 0.0
	for army in armies:
		total += effective(army)
	return total
