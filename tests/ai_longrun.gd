extends SceneTree
## Utility AI 多种子长跑诊断。手动运行，不纳入每次快速回归。

const SEEDS: Array[int] = [12345, 23456, 34567, 45678]
const DAYS: int = 1095


func _init() -> void:
	var total_start := Time.get_ticks_msec()
	var failed := false
	for world_seed in SEEDS:
		var state := GameState.new()
		state.generate_world(world_seed)
		var simulation := Simulation.new()
		root.add_child(simulation)
		simulation.setup(state)
		var initial_owners: Array[int] = []
		for city in state.cities:
			initial_owners.append(city.owner_nation)
		var seed_start := Time.get_ticks_msec()
		for _day in range(DAYS):
			if state.winner != -1:
				break
			simulation._advance_day()
		var captures := 0
		for city in state.cities:
			if city.owner_nation != initial_owners[city.id]:
				captures += 1
		var alive := 0
		for nation in state.nations:
			if nation.alive:
				alive += 1
		var ordered := 0
		var invalid := 0
		var troops := 0
		var starving := 0
		for army in state.armies:
			troops += army.size
			if army.starving:
				starving += 1
			if army.ai_order_created_day >= 0:
				ordered += 1
			if army.size <= 0 or army.owner_nation < 0 or army.owner_nation >= state.nations.size():
				invalid += 1
		var manpower := 0
		var food := 0
		for nation in state.nations:
			manpower += nation.manpower_pool
			food += nation.granary_food
		var elapsed := Time.get_ticks_msec() - seed_start
		print(
			(
				"seed=%d day=%d alive=%d armies=%d troops=%d manpower=%d food=%d "
				+ "starving=%d captures=%d ordered=%d invalid=%d ms=%d"
			)
			% [
				world_seed,
				state.day,
				alive,
				state.armies.size(),
				troops,
				manpower,
				food,
				starving,
				captures,
				ordered,
				invalid,
				elapsed,
			]
		)
		if captures == 0 or ordered == 0 or invalid > 0:
			failed = true
		simulation.free()
	print("total_ms=%d" % (Time.get_ticks_msec() - total_start))
	quit(1 if failed else 0)
