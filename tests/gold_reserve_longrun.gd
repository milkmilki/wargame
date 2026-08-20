extends SceneTree
## 真实地图和平财政长测：所有国家从零国库出发，验证军制 AI 会形成
## 正现金流并持续接近三年月收入储备，而非停在零现金收支平衡点。

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
			target > 0
			and nation.treasury_gold > 0
			and nation.unpaid_military_upkeep == 0
			and (balance > 0 or nation.treasury_gold >= target)
			and ratio >= 0.45
		)
	print("verdict=", "GOLD_RESERVE_OK" if valid else "GOLD_RESERVE_INVALID")
	simulation.free()
	quit(0 if valid else 1)
