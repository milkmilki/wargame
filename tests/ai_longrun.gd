extends SceneTree
## Utility AI 多种子长跑诊断。手动运行，不纳入每次快速回归。

const SEEDS: Array[int] = [12345, 23456, 34567, 45678]
const DAYS: int = 1095


func _init() -> void:
	var total_start := Time.get_ticks_msec()
	var failed := false
	var total_mobilization_armies := 0
	var total_captures := 0
	var total_war_declarations := 0
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
		var diplomatic_counts := {
			DiplomacyAI.Action.MAKE_PEACE: 0,
			DiplomacyAI.Action.DECLARE_WAR: 0,
			DiplomacyAI.Action.FORM_ALLIANCE: 0,
			DiplomacyAI.Action.LEAVE_ALLIANCE: 0,
			DiplomacyAI.Action.PREPARE_WAR: 0,
			DiplomacyAI.Action.CANCEL_WAR_PREPARATION: 0,
		}
		var objective_declarations := 0
		var resource_peaces := 0
		var mobilization_armies := 0
		for event in state.diplomatic_history:
			var action := int(event["action"])
			diplomatic_counts[action] = int(diplomatic_counts.get(action, 0)) + 1
			if action == DiplomacyAI.Action.DECLARE_WAR and event.has("objective_city"):
				objective_declarations += 1
				mobilization_armies += int(event.get("mobilization_armies", 0))
			if action == DiplomacyAI.Action.MAKE_PEACE:
				var reason := str(event["reason"])
				if (
					reason.contains("国库")
					or reason.contains("粮草")
					or reason.contains("人力")
				):
					resource_peaces += 1
		var war_pairs := 0
		var alliance_pairs := 0
		for nation_a in range(state.nations.size()):
			for nation_b in range(nation_a + 1, state.nations.size()):
				if state.is_enemy(nation_a, nation_b):
					war_pairs += 1
				elif state.is_allied(nation_a, nation_b):
					alliance_pairs += 1
		var capital_armies := 0
		var border_armies := 0
		for nation in state.nations:
			if not nation.alive:
				continue
			var snapshot := StrategicMapSnapshot.build(
				AiWorldView.build(state, nation.id)
			)
			var defended := {}
			for city_id in snapshot.frontier_cities:
				defended[city_id] = true
			for city_id in snapshot.potential_frontier_cities:
				defended[city_id] = true
			for army in state.armies:
				if army.owner_nation != nation.id or army.size <= 0:
					continue
				if (
					army.state in [Army.State.IDLE, Army.State.RECOVERING]
					and army.location_city == nation.capital_city_id
				):
					capital_armies += 1
				if (
					army.state in [Army.State.IDLE, Army.State.RECOVERING]
					and defended.has(army.location_city)
				) or (
					army.state == Army.State.HOLDING
					and (
						defended.has(army.move_from)
						or defended.has(army.move_to)
					)
				):
					border_armies += 1
		var elapsed := Time.get_ticks_msec() - seed_start
		total_mobilization_armies += mobilization_armies
		total_captures += captures
		total_war_declarations += int(
			diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR]
		)
		print(
			(
				"seed=%d day=%d alive=%d armies=%d troops=%d manpower=%d food=%d "
				+ "starving=%d captures=%d ordered=%d invalid=%d "
				+ "peace=%d prepare=%d cancel_prepare=%d war=%d objectives=%d "
				+ "mobilized=%d resource_peace=%d "
				+ "ally=%d leave=%d "
				+ "war_pairs=%d alliance_pairs=%d capital_armies=%d border_armies=%d "
				+ "commit_failures=%d ms=%d"
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
				diplomatic_counts[DiplomacyAI.Action.MAKE_PEACE],
				diplomatic_counts[DiplomacyAI.Action.PREPARE_WAR],
				diplomatic_counts[DiplomacyAI.Action.CANCEL_WAR_PREPARATION],
				diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR],
				objective_declarations,
				mobilization_armies,
				resource_peaces,
				diplomatic_counts[DiplomacyAI.Action.FORM_ALLIANCE],
				diplomatic_counts[DiplomacyAI.Action.LEAVE_ALLIANCE],
				war_pairs,
				alliance_pairs,
				capital_armies,
				border_armies,
				simulation.ai_command_commit_failure_total,
				elapsed,
			]
		)
		if simulation.ai_command_commit_failure_total > 0:
			print(
				"  commit_failure_log=%s"
				% str(simulation.ai_command_commit_failure_log)
			)
		if (
			ordered == 0
			or invalid > 0
			or simulation.ai_command_commit_failure_total > 0
			or food <= 0
			or border_armies == 0
			or state.diplomatic_history.is_empty()
			or objective_declarations
				!= int(diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR])
			or int(diplomatic_counts[DiplomacyAI.Action.PREPARE_WAR])
				< int(diplomatic_counts[DiplomacyAI.Action.DECLARE_WAR])
		):
			failed = true
		simulation.free()
	if total_captures == 0 or total_war_declarations == 0:
		failed = true
	print(
		"total_captures=%d total_wars=%d total_mobilized=%d"
		% [
			total_captures,
			total_war_declarations,
			total_mobilization_armies,
		]
	)
	print("total_ms=%d" % (Time.get_ticks_msec() - total_start))
	quit(1 if failed else 0)
