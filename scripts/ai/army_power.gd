class_name ArmyPower
extends RefCounted
## AI 战力估算。只用于规划，不替代 Combat 的真实解算。


static func effective(army: Army) -> float:
	if army == null or army.size <= 0:
		return 0.0
	var quality := (
		sqrt(maxf(
			float(army.attack * army.defense)
				* maxf(
					army.offensive_attack_multiplier,
					1.0
				),
			1.0
		))
		/ 10.0
	)
	var morale_factor := clampf(army.combat_morale(), 0.0, 1.0)
	var supply_factor := 0.5 + 0.5 * clampf(army.supply_ratio, 0.0, 1.0)
	return float(army.size) * quality * morale_factor * supply_factor


## 城市固有防御的等效战力（战力量纲，用于 AI 威胁/攻防规划，与军队 effective power 可比）。
## 语义 = 城墙工事结构强度的战力投影，与「破城所需兵力」(Combat.siege_required_manpower)
## 是不同量纲的两个量：前者进威胁评估，后者进围城比值分母（item 6：禁止量纲混用）。
static func city_defense(city: City) -> float:
	return float(maxi(city.fort_strength, 0)) * 10.0


static func combined(armies: Array[Army]) -> float:
	var total := 0.0
	for army in armies:
		total += effective(army)
	return total
