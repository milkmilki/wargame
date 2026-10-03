class_name ResourceBalanceRules
extends RefCounted
## Deterministic annual conversion between reserve pools. One transfer moves
## exactly one gold-equivalent bundle, so conversion cannot create value.

const FOOD_PER_GOLD: int = 25
const MANPOWER_PER_GOLD: int = 50
const ANNUAL_INCOME_SHARE: float = 0.25

const GOLD_INDEX: int = 0
const MANPOWER_INDEX: int = 1
const FOOD_INDEX: int = 2


static func plan(
	gold: int, manpower: int, food: int, annual_gold_income: int,
	include_food: bool, policy: Dictionary = {}
) -> Dictionary:
	var before := PackedInt64Array([maxi(gold, 0), maxi(manpower, 0) / MANPOWER_PER_GOLD, maxi(food, 0) / FOOD_PER_GOLD])
	var units := [1, MANPOWER_PER_GOLD, FOOD_PER_GOLD]
	var remainders := [0, maxi(manpower, 0) % MANPOWER_PER_GOLD, maxi(food, 0) % FOOD_PER_GOLD]
	var count := 3 if include_food else 2
	var total := before[0] + before[1] + (before[2] if include_food else 0)
	var cap := maxi(int(floor(maxi(annual_gold_income, 0) * ANNUAL_INCOME_SHARE)), 1) if total > 0 else 0
	var soft: Array = policy.get("targets", [0, 0, 0])
	var hard: Array = policy.get("hard_targets", [0, 0, 0])
	var capacities: Array = policy.get("capacities", [2147483647, 2147483647, 2147483647])
	var protected := PackedInt32Array()
	protected.resize(count)
	var after := before.duplicate()
	for index in range(count):
		protected[index] = int(ceil(float(maxi(int(soft[index]), int(hard[index]))) / units[index]))
	var moved := 0
	for targets in [hard, soft]:
		var donors := PackedInt32Array()
		var receivers := PackedInt32Array()
		donors.resize(count)
		receivers.resize(count)
		var donor_total := 0
		var receiver_total := 0
		for index in range(count):
			donors[index] = maxi(after[index] - protected[index], 0)
			var capacity_bundles := maxi(int(capacities[index]) - int(remainders[index]), 0) / int(units[index])
			var desired := mini(int(ceil(float(targets[index]) / units[index])), capacity_bundles)
			receivers[index] = maxi(desired - after[index], 0)
			donor_total += donors[index]
			receiver_total += receivers[index]
		var amount := mini(cap - moved, mini(donor_total, receiver_total))
		var donor_moves := _proportional_allocation(donors, donor_total, amount)
		var receiver_moves := _proportional_allocation(receivers, receiver_total, amount)
		for index in range(count):
			after[index] += receiver_moves[index] - donor_moves[index]
		moved += amount
	return {
		"gold_delta": after[0] - before[0],
		"manpower_delta": (after[1] - before[1]) * MANPOWER_PER_GOLD,
		"food_delta": (after[2] - before[2]) * FOOD_PER_GOLD if include_food else 0,
		"transferred_value": moved, "transfer_cap": cap,
	}


static func _proportional_allocation(
	amounts: PackedInt32Array,
	total: int,
	allocated_total: int
) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(amounts.size())
	if total <= 0 or allocated_total <= 0:
		return result
	var remainders: Array[Dictionary] = []
	var allocated := 0
	for index in range(amounts.size()):
		var numerator := amounts[index] * allocated_total
		result[index] = int(numerator / total)
		allocated += result[index]
		remainders.append({
			"index": index,
			"remainder": numerator % total,
		})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["remainder"]) != int(b["remainder"]):
			return int(a["remainder"]) > int(b["remainder"])
		return int(a["index"]) < int(b["index"])
	)
	for offset in range(allocated_total - allocated):
		result[int(remainders[offset]["index"])] += 1
	return result
