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
	gold: int,
	manpower: int,
	food: int,
	annual_gold_income: int,
	include_food: bool
) -> Dictionary:
	var before := PackedInt32Array([
		maxi(gold, 0),
		maxi(manpower, 0) / MANPOWER_PER_GOLD,
		maxi(food, 0) / FOOD_PER_GOLD,
	])
	var after := before.duplicate()
	var resource_count := 3 if include_food else 2
	var total_value := 0
	for index in range(resource_count):
		total_value += after[index]
	var transfer_cap := (
		maxi(int(floor(
			float(maxi(annual_gold_income, 0)) * ANNUAL_INCOME_SHARE
		)), 1)
		if total_value > 0 else 0
	)
	var targets := _balanced_targets(before, resource_count, total_value)
	var donor_amounts := PackedInt32Array()
	var receiver_amounts := PackedInt32Array()
	donor_amounts.resize(resource_count)
	receiver_amounts.resize(resource_count)
	var required_transfer := 0
	for index in range(resource_count):
		donor_amounts[index] = maxi(before[index] - targets[index], 0)
		receiver_amounts[index] = maxi(targets[index] - before[index], 0)
		required_transfer += receiver_amounts[index]
	var transferred := mini(required_transfer, transfer_cap)
	var donor_moves := _proportional_allocation(
		donor_amounts, required_transfer, transferred
	)
	var receiver_moves := _proportional_allocation(
		receiver_amounts, required_transfer, transferred
	)
	for index in range(resource_count):
		after[index] += receiver_moves[index] - donor_moves[index]
	return {
		"gold_delta": after[GOLD_INDEX] - before[GOLD_INDEX],
		"manpower_delta": (
			after[MANPOWER_INDEX] - before[MANPOWER_INDEX]
		) * MANPOWER_PER_GOLD,
		"food_delta": (
			(after[FOOD_INDEX] - before[FOOD_INDEX]) * FOOD_PER_GOLD
			if include_food else 0
		),
		"transferred_value": transferred,
		"transfer_cap": transfer_cap,
	}


static func _balanced_targets(
	values: PackedInt32Array,
	count: int,
	total: int
) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(count)
	result.fill(int(total / count))
	var order: Array[int] = []
	for index in range(count):
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		if values[a] != values[b]:
			return values[a] > values[b]
		return a < b
	)
	for index in range(total % count):
		result[order[index]] += 1
	return result


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
