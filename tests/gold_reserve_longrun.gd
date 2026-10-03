extends SceneTree
## 真实地图和平财政长测：储备只是报告，不保证现金流为正或攒满目标。
## 验证零国库扩军后支付率、财政缺口和派生战力仍保持一致。

const DAYS: int = 1080


func _init() -> void:
	var state := GameState.new()
	state.generate_world(12345)
	for a in range(state.nations.size()):
		for b in range(a + 1, state.nations.size()):
			state.set_diplomatic_relation(
				a, b, GameState.DiplomaticRelation.NEUTRAL
			)
	for nation in state.nations:
		nation.treasury_gold = 0
	var simulation := Simulation.new()
	root.add_child(simulation)
	simulation.setup(state)
	simulation.diplomacy_enabled = false
	for _day in range(DAYS):
		simulation._advance_day()
	var flows := Simulation.monthly_gold_flows(state)
	var valid := true
	for nation in state.nations:
		var policy := Simulation.gold_reserve_policy(
			state, nation.id, flows
		)
		var target := int(policy["reserve_target"])
		var ratio := (
			float(nation.treasury_gold) / float(target)
			if target > 0 else 1.0
		)
		var balance := int(flows[nation.id]["balance"])
		print(
			"GOLD_RESERVE nation=", nation.id,
			" treasury=", nation.treasury_gold,
			" income=", flows[nation.id]["net_income"],
			" upkeep=", flows[nation.id]["military_upkeep"],
			" balance=", balance,
			" target=", target,
			" ratio=", ratio
		)
		valid = valid and (
			target >= 0
			and nation.treasury_gold >= 0
			and nation.military_payment_ratio >= 0
			and nation.military_payment_ratio <= 1
			and not policy.has("required_upkeep_savings")
			and policy.gold_shortage == (int(policy.forecast.gold_deficit) > 0)
		)
	for army in state.armies:
		valid = valid and is_equal_approx(army.funding_multiplier, Army.funding_from_payment(state.nations[army.owner_nation].military_payment_ratio))
	print("verdict=", "GOLD_RESERVE_OK" if valid else "GOLD_RESERVE_INVALID")
	simulation.free()
	quit(0 if valid else 1)
